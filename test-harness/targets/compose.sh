#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=test-harness/lib/common.sh
source "$REPO_ROOT/test-harness/lib/common.sh"

ADAPTER="compose"
ACTION="${1:-}"
shift || true

SCENARIO=""
RUN_ID="$(hvk_default_run_id)"
WORKDIR="$REPO_ROOT/test-harness/work"
COMPOSE_ENGINE="${COMPOSE_ENGINE:-docker}"
PROFILE="${COMPOSE_PROFILE:-localnet}"
TIMEOUT_SECONDS=300
POLL_INTERVAL_SECONDS=5

while (($# > 0)); do
  case "$1" in
    --scenario)
      SCENARIO="${2:-}"
      shift 2
      ;;
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --workdir)
      WORKDIR="${2:-}"
      shift 2
      ;;
    --compose-engine)
      COMPOSE_ENGINE="${2:-}"
      shift 2
      ;;
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --timeout-seconds)
      TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --poll-interval-seconds)
      POLL_INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    *)
      hvk_emit_err_and_exit "$ADAPTER" "${ACTION:-unknown}" "$RUN_ID" "invalid_args" "Unknown option: $1" 2
      ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  hvk_emit_err_and_exit "$ADAPTER" "unknown" "$RUN_ID" "invalid_args" "Missing action" 2
fi

STATE_DIR="$WORKDIR/state/$ADAPTER/$RUN_ID"
ARTIFACT_DIR="$WORKDIR/artifacts/$ADAPTER/$RUN_ID"
INVENTORY_PATH="$STATE_DIR/inventory.yml"
COMPOSE_BASE="$REPO_ROOT/solana-localnet/docker-compose.yml"
COMPOSE_OVERRIDE_DOCKER="$REPO_ROOT/solana-localnet/docker-compose.docker.yml"
COMPOSE_OVERRIDE_PODMAN="$REPO_ROOT/solana-localnet/docker-compose.podman.yml"

hvk_mkdir "$STATE_DIR"
hvk_mkdir "$ARTIFACT_DIR"

compose_exec() {
  local override="$COMPOSE_OVERRIDE_DOCKER"
  local bin="docker"
  if [[ "$COMPOSE_ENGINE" == "podman" ]]; then
    override="$COMPOSE_OVERRIDE_PODMAN"
    bin="podman"
  fi
  "$bin" compose -f "$COMPOSE_BASE" -f "$override" --profile "$PROFILE" "$@"
}

validate() {
  if [[ -z "$SCENARIO" ]]; then
    hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "invalid_args" "Missing required --scenario" 2
  fi

  hvk_require_cmd jq || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_dependency" "jq not found" 3

  case "$COMPOSE_ENGINE" in
    docker)
      hvk_require_cmd docker || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_dependency" "docker not found" 3
      ;;
    podman)
      hvk_require_cmd podman || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_dependency" "podman not found" 3
      ;;
    *)
      hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "invalid_args" "Unsupported compose engine: $COMPOSE_ENGINE" 2
      ;;
  esac

  [[ -f "$COMPOSE_BASE" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "Missing compose file: $COMPOSE_BASE" 3
  [[ -x "$REPO_ROOT/solana-localnet/tests/test-localnet.sh" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "Missing executable: solana-localnet/tests/test-localnet.sh" 3

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Compose adapter validation passed" \
    "$(jq -cn --arg engine "$COMPOSE_ENGINE" --arg profile "$PROFILE" --arg state_dir "$STATE_DIR" '{engine: $engine, profile: $profile, state_dir: $state_dir}')"
}

up() {
  validate >/dev/null
  echo "[$ADAPTER] Bringing up stack via existing localnet test harness ($COMPOSE_ENGINE)..." >&2
  "$REPO_ROOT/solana-localnet/tests/test-localnet.sh" "$COMPOSE_ENGINE"

  jq -cn \
    --arg scenario "$SCENARIO" \
    --arg engine "$COMPOSE_ENGINE" \
    --arg profile "$PROFILE" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{scenario: $scenario, engine: $engine, profile: $profile, created_at: $created_at}' \
    >"$STATE_DIR/metadata.json"

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Compose stack is up" \
    "$(jq -cn --arg state_dir "$STATE_DIR" '{state_dir: $state_dir}')"
}

inventory() {
  validate >/dev/null

  cat >"$INVENTORY_PATH" <<'EOF'
all:
  hosts:
    host-alpha:
      ansible_host: 172.25.0.11
      ansible_port: 22
      ansible_user: ubuntu
    host-bravo:
      ansible_host: 172.25.0.12
      ansible_port: 22
      ansible_user: ubuntu
    host-charlie:
      ansible_host: 172.25.0.13
      ansible_port: 22
      ansible_user: ubuntu
  children:
    solana_localnet:
      hosts:
        host-alpha:
        host-bravo:
        host-charlie:
EOF

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Compose inventory generated" \
    "$(jq -cn --arg inventory_path "$INVENTORY_PATH" --argjson hosts '[
      {"name":"host-alpha","ansible_host":"172.25.0.11","ansible_port":22},
      {"name":"host-bravo","ansible_host":"172.25.0.12","ansible_port":22},
      {"name":"host-charlie","ansible_host":"172.25.0.13","ansible_port":22}
    ]' '{inventory_path: $inventory_path, hosts: $hosts}')"
}

wait_ready() {
  validate >/dev/null
  local services=("gossip-entrypoint" "host-alpha" "host-bravo" "host-charlie" "ansible-control-localnet")
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local service

  for service in "${services[@]}"; do
    echo "[$ADAPTER] waiting for service: $service" >&2
    while true; do
      if compose_exec exec -T "$service" true >/dev/null 2>&1; then
        break
      fi
      if ((SECONDS >= deadline)); then
        hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "timeout" "Timed out waiting for service: $service" 4
      fi
      sleep "$POLL_INTERVAL_SECONDS"
    done
  done

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Compose services are reachable"
}

down() {
  validate >/dev/null
  echo "[$ADAPTER] tearing down compose stack..." >&2
  compose_exec down --remove-orphans --volumes || true
  "$REPO_ROOT/solana-localnet/cleanup-generated-localnet-dirs.sh" "$COMPOSE_ENGINE" || true
  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Compose stack torn down"
}

artifacts() {
  validate >/dev/null

  {
    echo "adapter=$ADAPTER"
    echo "scenario=$SCENARIO"
    echo "run_id=$RUN_ID"
    echo "engine=$COMPOSE_ENGINE"
    echo "profile=$PROFILE"
  } >"$ARTIFACT_DIR/metadata.env"

  compose_exec ps >"$ARTIFACT_DIR/compose-ps.txt" 2>&1 || true
  compose_exec logs --no-color >"$ARTIFACT_DIR/compose-logs.txt" 2>&1 || true

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Compose artifacts collected" \
    "$(jq -cn --arg artifacts_path "$ARTIFACT_DIR" '{artifacts_path: $artifacts_path}')"
}

describe() {
  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Compose adapter capabilities" \
    "$(jq -cn '{
      capabilities: {
        supports_destroy: true,
        supports_artifacts: true,
        supports_multi_host: true,
        supports_resource_profiles: false,
        supports_scenario_matrix: true
      }
    }')"
}

case "$ACTION" in
  validate) validate ;;
  up) up ;;
  inventory) inventory ;;
  wait) wait_ready ;;
  down) down ;;
  artifacts) artifacts ;;
  describe) describe ;;
  *)
    hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "invalid_action" "Unsupported action: $ACTION" 2
    ;;
esac

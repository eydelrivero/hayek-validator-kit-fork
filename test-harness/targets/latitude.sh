#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=test-harness/lib/common.sh
source "$REPO_ROOT/test-harness/lib/common.sh"

ADAPTER="latitude"
ACTION="${1:-}"
shift || true

SCENARIO=""
RUN_ID="$(hvk_default_run_id)"
WORKDIR="$REPO_ROOT/test-harness/work"
TIMEOUT_SECONDS=1200
POLL_INTERVAL_SECONDS=20

OPERATOR_NAME="${LATITUDE_OPERATOR_NAME:-}"
OPERATOR_SSH_PUBLIC_KEY="${LATITUDE_OPERATOR_SSH_PUBLIC_KEY:-}"
OPERATOR_SSH_PUBLIC_KEY_FILE="${LATITUDE_OPERATOR_SSH_PUBLIC_KEY_FILE:-}"
OPERATOR_SSH_PRIVATE_KEY_FILE="${LATITUDE_OPERATOR_SSH_PRIVATE_KEY_FILE:-}"
PLAN="${LATITUDE_PLAN:-m4-metal-small}"
PROJECT="${PROJECT:-ZZZ HVK Test Harness}"
SKIP_POST_CHECKS=true
SSH_USER="${SSH_USER:-ubuntu}"
PROJECT_DESCRIPTION_SENTINEL="${PROJECT_DESCRIPTION_SENTINEL:-managed-by-hvk-test-harness}"
PROJECT_ENVIRONMENT="${PROJECT_ENVIRONMENT:-Development}"

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
    --timeout-seconds)
      TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --poll-interval-seconds)
      POLL_INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    --operator-name)
      OPERATOR_NAME="${2:-}"
      shift 2
      ;;
    --operator-ssh-public-key)
      OPERATOR_SSH_PUBLIC_KEY="${2:-}"
      shift 2
      ;;
    --operator-ssh-public-key-file)
      OPERATOR_SSH_PUBLIC_KEY_FILE="${2:-}"
      shift 2
      ;;
    --operator-ssh-private-key-file)
      OPERATOR_SSH_PRIVATE_KEY_FILE="${2:-}"
      shift 2
      ;;
    --plan)
      PLAN="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --skip-post-checks)
      SKIP_POST_CHECKS=true
      shift
      ;;
    --run-post-checks)
      SKIP_POST_CHECKS=false
      shift
      ;;
    --ssh-user)
      SSH_USER="${2:-}"
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

if [[ -n "$OPERATOR_SSH_PUBLIC_KEY_FILE" && -z "$OPERATOR_SSH_PUBLIC_KEY" ]]; then
  [[ -r "$OPERATOR_SSH_PUBLIC_KEY_FILE" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "Operator SSH public key file is not readable: $OPERATOR_SSH_PUBLIC_KEY_FILE" 3
  OPERATOR_SSH_PUBLIC_KEY="$(cat "$OPERATOR_SSH_PUBLIC_KEY_FILE")"
fi

STATE_DIR="$WORKDIR/state/$ADAPTER/$RUN_ID"
ARTIFACT_DIR="$WORKDIR/artifacts/$ADAPTER/$RUN_ID"
INVENTORY_PATH="$STATE_DIR/inventory.yml"
IP_FILE="$STATE_DIR/server_ip.txt"
SERVER_ID_FILE="$STATE_DIR/server_id.txt"
HOSTNAME_FILE="$STATE_DIR/hostname.txt"

hvk_mkdir "$STATE_DIR"
hvk_mkdir "$ARTIFACT_DIR"

PROVISION_SCRIPT="$REPO_ROOT/bare-metal/latitudesh/provision_latitude_server.sh"
DESTROY_SCRIPT="$REPO_ROOT/bare-metal/latitudesh/destroy_latitude_server.sh"

hostname_for_run() {
  local base
  local scenario
  base="${OPERATOR_NAME:-unknown}"
  scenario="${SCENARIO:-default}"
  base="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
  scenario="$(printf '%s' "$scenario" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
  base="${base#-}"
  base="${base%-}"
  scenario="${scenario#-}"
  scenario="${scenario%-}"
  printf 'hvk-%s-%s-%s\n' "${base:0:12}" "${scenario:0:16}" "${RUN_ID:0:12}"
}

validate() {
  if [[ -z "$SCENARIO" ]]; then
    hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "invalid_args" "Missing required --scenario" 2
  fi
  [[ -n "$OPERATOR_NAME" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "invalid_args" "Missing required --operator-name" 2
  [[ -n "$OPERATOR_SSH_PUBLIC_KEY" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "invalid_args" "Missing operator SSH public key (--operator-ssh-public-key or --operator-ssh-public-key-file)" 2
  [[ -x "$PROVISION_SCRIPT" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "Missing executable: $PROVISION_SCRIPT" 3
  [[ -x "$DESTROY_SCRIPT" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "Missing executable: $DESTROY_SCRIPT" 3
  hvk_require_cmd jq || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_dependency" "jq not found" 3
  hvk_require_cmd lsh || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_dependency" "lsh not found" 3

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Latitude adapter validation passed" \
    "$(jq -cn --arg operator "$OPERATOR_NAME" --arg plan "$PLAN" --arg project "$PROJECT" '{operator: $operator, plan: $plan, project: $project}')"
}

up() {
  validate >/dev/null

  local args=(
    --operator-name "$OPERATOR_NAME"
    --operator-ssh-public-key "$OPERATOR_SSH_PUBLIC_KEY"
    --hostname "$(hostname_for_run)"
    --plan "$PLAN"
  )
  if [[ "$SKIP_POST_CHECKS" == true ]]; then
    args+=(--skip-post-checks)
  fi

  OUTPUT_IP_FILE="$IP_FILE" \
  OUTPUT_SERVER_ID_FILE="$SERVER_ID_FILE" \
  PROJECT="$PROJECT" \
  PROJECT_DESCRIPTION_SENTINEL="$PROJECT_DESCRIPTION_SENTINEL" \
  PROJECT_ENVIRONMENT="$PROJECT_ENVIRONMENT" \
  WAIT_MAX_POLLS="$((TIMEOUT_SECONDS / POLL_INTERVAL_SECONDS))" \
  WAIT_INTERVAL_SECONDS="$POLL_INTERVAL_SECONDS" \
  SSH_USER="$SSH_USER" \
  SSH_PRIVATE_KEY="$OPERATOR_SSH_PRIVATE_KEY_FILE" \
  "$PROVISION_SCRIPT" "${args[@]}"

  hostname_for_run >"$HOSTNAME_FILE"

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Latitude server provisioned" \
    "$(jq -cn --arg ip_file "$IP_FILE" --arg server_id_file "$SERVER_ID_FILE" '{ip_file: $ip_file, server_id_file: $server_id_file}')"
}

inventory() {
  validate >/dev/null
  [[ -r "$IP_FILE" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_state" "Missing IP file: $IP_FILE. Run 'up' first." 4
  local ip
  ip="$(cat "$IP_FILE")"

  cat >"$INVENTORY_PATH" <<EOF
all:
  hosts:
    latitude-host:
      ansible_host: ${ip}
      ansible_port: 22
      ansible_user: ${SSH_USER}
EOF

  if [[ -n "$OPERATOR_SSH_PRIVATE_KEY_FILE" ]]; then
    cat >>"$INVENTORY_PATH" <<EOF
      ansible_ssh_private_key_file: ${OPERATOR_SSH_PRIVATE_KEY_FILE}
EOF
  fi

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Latitude inventory generated" \
    "$(jq -cn --arg inventory_path "$INVENTORY_PATH" --arg ip "$ip" --argjson hosts '[{"name":"latitude-host","ansible_port":22}]' '{inventory_path: $inventory_path, primary_ip: $ip, hosts: $hosts}')"
}

wait_ready() {
  validate >/dev/null
  [[ -r "$IP_FILE" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_state" "Missing IP file: $IP_FILE. Run 'up' first." 4
  local ip
  ip="$(cat "$IP_FILE")"

  if [[ -z "$OPERATOR_SSH_PRIVATE_KEY_FILE" ]]; then
    hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "No private key provided; skipping SSH wait" \
      "$(jq -cn --arg ip "$ip" '{primary_ip: $ip, ssh_wait_skipped: true}')"
    return 0
  fi

  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o IdentitiesOnly=yes -o IdentityAgent=none -i "$OPERATOR_SSH_PRIVATE_KEY_FILE")

  while true; do
    if ssh "${ssh_opts[@]}" "${SSH_USER}@${ip}" 'true' >/dev/null 2>&1; then
      break
    fi
    if ((SECONDS >= deadline)); then
      hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "timeout" "Timed out waiting for SSH on ${SSH_USER}@${ip}" 4
    fi
    sleep "$POLL_INTERVAL_SECONDS"
  done

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Latitude SSH is reachable" \
    "$(jq -cn --arg ip "$ip" '{primary_ip: $ip}')"
}

down() {
  validate >/dev/null
  local args=()
  if [[ -r "$SERVER_ID_FILE" ]]; then
    args+=(--server-id "$(cat "$SERVER_ID_FILE")")
  else
    hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_state" "Missing server ID for teardown. Refusing hostname-based deletion." 4
  fi

  args+=(--project "$PROJECT")
  "$DESTROY_SCRIPT" "${args[@]}"

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Latitude server teardown requested"
}

artifacts() {
  validate >/dev/null
  [[ -r "$IP_FILE" ]] && cp "$IP_FILE" "$ARTIFACT_DIR/server_ip.txt" || true
  [[ -r "$SERVER_ID_FILE" ]] && cp "$SERVER_ID_FILE" "$ARTIFACT_DIR/server_id.txt" || true
  [[ -r "$HOSTNAME_FILE" ]] && cp "$HOSTNAME_FILE" "$ARTIFACT_DIR/hostname.txt" || true

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Latitude artifacts collected" \
    "$(jq -cn --arg artifacts_path "$ARTIFACT_DIR" '{artifacts_path: $artifacts_path}')"
}

describe() {
  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "Latitude adapter capabilities" \
    "$(jq -cn '{
      capabilities: {
        supports_destroy: true,
        supports_artifacts: true,
        supports_multi_host: false,
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

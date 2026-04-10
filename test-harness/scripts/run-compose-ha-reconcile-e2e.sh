#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

COMPOSE_ENGINE="${COMPOSE_ENGINE:-docker}"
SCENARIO="${SCENARIO:-hot_swap_matrix}"
WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work}"
RUN_ID_PREFIX="${RUN_ID_PREFIX:-compose-ha-reconcile}"
SOURCE_HOST="${SOURCE_HOST:-host-bravo}"
DESTINATION_HOST="${DESTINATION_HOST:-host-charlie}"
SOURCE_FLAVOR="${SOURCE_FLAVOR:-agave}"
DESTINATION_FLAVOR="${DESTINATION_FLAVOR:-agave}"
VALIDATOR_NAME="${VALIDATOR_NAME:-demo2}"
OPERATOR_USER="${OPERATOR_USER:-ubuntu}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1800}"
RETAIN_ON_FAILURE=false
RUN_ID=""
INVENTORY_PATH=""

usage() {
  cat <<'EOF'
Usage:
  run-compose-ha-reconcile-e2e.sh [options]

Options:
  --compose-engine <docker|podman>   (default: docker)
  --scenario <name>                  (default: hot_swap_matrix)
  --workdir <path>                   (default: ./test-harness/work)
  --run-id-prefix <id>               (default: compose-ha-reconcile)
  --source-host <name>               (default: host-bravo)
  --destination-host <name>          (default: host-charlie)
  --source-flavor <flavor>           (default: agave)
  --destination-flavor <flavor>      (default: agave)
  --validator-name <name>            (default: demo2)
  --operator-user <name>             (default: ubuntu)
  --timeout-seconds <int>            (default: 1800)
  --retain-on-failure
EOF
}

while (($# > 0)); do
  case "$1" in
    --compose-engine)
      COMPOSE_ENGINE="${2:-}"
      shift 2
      ;;
    --scenario)
      SCENARIO="${2:-}"
      shift 2
      ;;
    --workdir)
      WORKDIR="${2:-}"
      shift 2
      ;;
    --run-id-prefix)
      RUN_ID_PREFIX="${2:-}"
      shift 2
      ;;
    --source-host)
      SOURCE_HOST="${2:-}"
      shift 2
      ;;
    --destination-host)
      DESTINATION_HOST="${2:-}"
      shift 2
      ;;
    --source-flavor)
      SOURCE_FLAVOR="${2:-}"
      shift 2
      ;;
    --destination-flavor)
      DESTINATION_FLAVOR="${2:-}"
      shift 2
      ;;
    --validator-name)
      VALIDATOR_NAME="${2:-}"
      shift 2
      ;;
    --operator-user)
      OPERATOR_USER="${2:-}"
      shift 2
      ;;
    --timeout-seconds)
      TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --retain-on-failure)
      RETAIN_ON_FAILURE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

RUN_ID="${RUN_ID_PREFIX}-$(date +%Y%m%d-%H%M%S)"

target_args=(
  --scenario "$SCENARIO"
  --run-id "$RUN_ID"
  --workdir "$WORKDIR"
  --compose-engine "$COMPOSE_ENGINE"
)

export VERIFY_HA_RECONCILE=true
export SOLANA_VALIDATOR_HA_SOURCE_NODE_ID="${SOLANA_VALIDATOR_HA_SOURCE_NODE_ID:-ark}"
export SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID="${SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID:-fog}"
export SOLANA_VALIDATOR_HA_SOURCE_PRIORITY="${SOLANA_VALIDATOR_HA_SOURCE_PRIORITY:-10}"
export SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY="${SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY:-20}"
cleanup() {
  local exit_code="$1"

  "$REPO_ROOT/test-harness/targets/compose.sh" artifacts "${target_args[@]}" >/dev/null 2>&1 || true

  if [[ "$exit_code" -eq 0 ]]; then
    "$REPO_ROOT/test-harness/targets/compose.sh" down "${target_args[@]}" >/dev/null 2>&1 || true
    return
  fi

  if [[ "$RETAIN_ON_FAILURE" == true ]]; then
    echo "Retaining compose harness run on failure: $RUN_ID" >&2
    return
  fi

  "$REPO_ROOT/test-harness/targets/compose.sh" down "${target_args[@]}" >/dev/null 2>&1 || true
}

trap 'cleanup "$?"' EXIT

"$REPO_ROOT/test-harness/targets/compose.sh" up "${target_args[@]}"
inventory_json="$("$REPO_ROOT/test-harness/targets/compose.sh" inventory "${target_args[@]}")"
INVENTORY_PATH="$(jq -r '.inventory_path // empty' <<<"$inventory_json")"

if [[ -z "$INVENTORY_PATH" || ! -r "$INVENTORY_PATH" ]]; then
  echo "Failed to locate compose inventory for run $RUN_ID" >&2
  exit 1
fi

"$REPO_ROOT/test-harness/targets/compose.sh" wait "${target_args[@]}" --timeout-seconds "$TIMEOUT_SECONDS"

rc=0
"$REPO_ROOT/test-harness/scripts/verify-compose-ha-reconcile.sh" \
  --compose-engine "$COMPOSE_ENGINE" \
  --inventory "$INVENTORY_PATH" \
  --source-host "$SOURCE_HOST" \
  --destination-host "$DESTINATION_HOST" \
  --source-flavor "$SOURCE_FLAVOR" \
  --destination-flavor "$DESTINATION_FLAVOR" \
  --validator-name "$VALIDATOR_NAME" \
  --operator-user "$OPERATOR_USER" || rc=$?

exit "$rc"

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

run_id="${RUN_ID_PREFIX}-$(date +%Y%m%d-%H%M%S)"

verify_cmd="$REPO_ROOT/test-harness/scripts/verify-compose-hot-swap.sh --compose-engine $COMPOSE_ENGINE --inventory <inventory> --source-host $SOURCE_HOST --destination-host $DESTINATION_HOST --source-flavor $SOURCE_FLAVOR --destination-flavor $DESTINATION_FLAVOR --validator-name $VALIDATOR_NAME --operator-user $OPERATOR_USER"

export SOLANA_VALIDATOR_HA_RUNTIME_ENABLED=true
export SOLANA_VALIDATOR_HA_SOURCE_NODE_ID="${SOLANA_VALIDATOR_HA_SOURCE_NODE_ID:-ark}"
export SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID="${SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID:-fog}"
export SOLANA_VALIDATOR_HA_SOURCE_PRIORITY="${SOLANA_VALIDATOR_HA_SOURCE_PRIORITY:-10}"
export SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY="${SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY:-20}"

hvk_args=(
  "$REPO_ROOT/test-harness/bin/hvk-test" run
  --target compose
  --scenario "$SCENARIO"
  --run-id "$run_id"
  --workdir "$WORKDIR"
  --compose-engine "$COMPOSE_ENGINE"
  --timeout-seconds "$TIMEOUT_SECONDS"
  --verify-cmd "$verify_cmd"
)

if [[ "$RETAIN_ON_FAILURE" == true ]]; then
  hvk_args+=(--retain-on-failure)
fi

exec "${hvk_args[@]}"

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

COMPOSE_ENGINE="${COMPOSE_ENGINE:-docker}"
SCENARIO="${SCENARIO:-hot_swap_matrix}"
WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work}"
SOURCE_HOST="${SOURCE_HOST:-host-alpha}"
DESTINATION_HOST="${DESTINATION_HOST:-host-bravo}"
VALIDATOR_NAME="${VALIDATOR_NAME:-demo1}"
OPERATOR_USER="${OPERATOR_USER:-ubuntu}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1800}"
CONTINUE_ON_ERROR=false
RETAIN_ON_FAILURE=false

usage() {
  cat <<'EOF'
Usage:
  run-compose-hot-swap-matrix.sh [options]

Options:
  --compose-engine <docker|podman>   (default: docker)
  --scenario <name>                  (default: hot_swap_matrix)
  --workdir <path>                   (default: ./test-harness/work)
  --source-host <name>               (default: host-alpha)
  --destination-host <name>          (default: host-bravo)
  --validator-name <name>            (default: demo1)
  --operator-user <name>             (default: ubuntu)
  --timeout-seconds <int>            (default: 1800)
  --continue-on-error
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
    --source-host)
      SOURCE_HOST="${2:-}"
      shift 2
      ;;
    --destination-host)
      DESTINATION_HOST="${2:-}"
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
    --continue-on-error)
      CONTINUE_ON_ERROR=true
      shift
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

cases=(
  "agave_to_agave:agave:agave"
  "agave_to_jito_bam:agave:jito-bam"
  "jito_bam_to_agave:jito-bam:agave"
  "jito_bam_to_jito_bam:jito-bam:jito-bam"
)

pass_count=0
fail_count=0

run_case() {
  local case_name="$1"
  local source_flavor="$2"
  local destination_flavor="$3"
  local run_id="$4"
  local rc=0
  local inventory_json=""
  local inventory_path=""
  local target_args=(
    --scenario "$SCENARIO"
    --run-id "$run_id"
    --workdir "$WORKDIR"
    --compose-engine "$COMPOSE_ENGINE"
  )

  "$REPO_ROOT/test-harness/targets/compose.sh" up "${target_args[@]}" || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    inventory_json="$("$REPO_ROOT/test-harness/targets/compose.sh" inventory "${target_args[@]}")" || rc=$?
  fi

  if [[ "$rc" -eq 0 ]]; then
    inventory_path="$(jq -r '.inventory_path // empty' <<<"$inventory_json")"
    if [[ -z "$inventory_path" || ! -r "$inventory_path" ]]; then
      echo "Failed to locate compose inventory for run $run_id" >&2
      rc=1
    fi
  fi

  if [[ "$rc" -eq 0 ]]; then
    "$REPO_ROOT/test-harness/targets/compose.sh" wait "${target_args[@]}" --timeout-seconds "$TIMEOUT_SECONDS" || rc=$?
  fi

  if [[ "$rc" -eq 0 ]]; then
    "$REPO_ROOT/test-harness/scripts/verify-compose-hot-swap.sh" \
      --compose-engine "$COMPOSE_ENGINE" \
      --inventory "$inventory_path" \
      --source-host "$SOURCE_HOST" \
      --destination-host "$DESTINATION_HOST" \
      --source-flavor "$source_flavor" \
      --destination-flavor "$destination_flavor" \
      --validator-name "$VALIDATOR_NAME" \
      --operator-user "$OPERATOR_USER" || rc=$?
  fi

  "$REPO_ROOT/test-harness/targets/compose.sh" artifacts "${target_args[@]}" >/dev/null 2>&1 || true

  if [[ "$rc" -eq 0 || "$RETAIN_ON_FAILURE" != true ]]; then
    "$REPO_ROOT/test-harness/targets/compose.sh" down "${target_args[@]}" >/dev/null 2>&1 || true
  else
    echo "Retaining compose harness run on failure: $run_id" >&2
  fi

  return "$rc"
}

for case_entry in "${cases[@]}"; do
  IFS=':' read -r case_name source_flavor destination_flavor <<<"$case_entry"
  run_id="hot-swap-${case_name}-$(date +%Y%m%d-%H%M%S)"

  echo "==> Running case: $case_name ($source_flavor -> $destination_flavor)" >&2

  if run_case "$case_name" "$source_flavor" "$destination_flavor" "$run_id"; then
    echo "PASS: $case_name" >&2
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $case_name" >&2
    fail_count=$((fail_count + 1))
    if [[ "$CONTINUE_ON_ERROR" != true ]]; then
      break
    fi
  fi
done

echo "Hot-swap matrix summary: passed=$pass_count failed=$fail_count" >&2
if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi

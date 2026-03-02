#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work/vm-hot-swap}"
RUN_ID_PREFIX="${RUN_ID_PREFIX:-vm-hot-swap}"
VM_ARCH="${VM_ARCH:-}"
VM_BASE_IMAGE="${VM_BASE_IMAGE:-}"
CONTINUE_ON_ERROR=false
RETAIN_ON_FAILURE=false
RETAIN_ALWAYS=false

usage() {
  cat <<'EOF'
Usage:
  run-vm-hot-swap-matrix.sh [options]

Options:
  --workdir <path>                 (default: ./test-harness/work/vm-hot-swap)
  --run-id-prefix <id>             (default: vm-hot-swap)
  --vm-arch <amd64|arm64>
  --vm-base-image <path>
  --continue-on-error
  --retain-on-failure
  --retain-always
EOF
}

while (($# > 0)); do
  case "$1" in
    --workdir)
      WORKDIR="${2:-}"
      shift 2
      ;;
    --run-id-prefix)
      RUN_ID_PREFIX="${2:-}"
      shift 2
      ;;
    --vm-arch)
      VM_ARCH="${2:-}"
      shift 2
      ;;
    --vm-base-image)
      VM_BASE_IMAGE="${2:-}"
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
    --retain-always)
      RETAIN_ALWAYS=true
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

for idx in "${!cases[@]}"; do
  case_entry="${cases[$idx]}"
  IFS=':' read -r case_name source_flavor destination_flavor <<<"$case_entry"

  run_id="${RUN_ID_PREFIX}-${case_name}-$(date +%Y%m%d-%H%M%S)"
  offset=$((idx * 200))
  src_port=$((2222 + offset))
  src_port_alt=$((2522 + offset))
  dst_port=$((3222 + offset))
  dst_port_alt=$((3522 + offset))

  args=(
    "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh"
    --run-id "$run_id"
    --workdir "$WORKDIR"
    --source-flavor "$source_flavor"
    --destination-flavor "$destination_flavor"
    --source-ssh-port "$src_port"
    --source-ssh-port-alt "$src_port_alt"
    --destination-ssh-port "$dst_port"
    --destination-ssh-port-alt "$dst_port_alt"
  )

  if [[ -n "$VM_ARCH" ]]; then
    args+=(--vm-arch "$VM_ARCH")
  fi
  if [[ -n "$VM_BASE_IMAGE" ]]; then
    args+=(--vm-base-image "$VM_BASE_IMAGE")
  fi
  if [[ "$RETAIN_ON_FAILURE" == true ]]; then
    args+=(--retain-on-failure)
  fi
  if [[ "$RETAIN_ALWAYS" == true ]]; then
    args+=(--retain-always)
  fi

  echo "==> Running VM case: $case_name ($source_flavor -> $destination_flavor)" >&2
  if "${args[@]}"; then
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

echo "VM hot-swap matrix summary: passed=$pass_count failed=$fail_count" >&2
if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi

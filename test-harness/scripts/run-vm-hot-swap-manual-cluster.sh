#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work/vm-hot-swap-manual}"
RUN_ID_PREFIX="${RUN_ID_PREFIX:-vm-hot-swap-manual}"
STATE_FILE="${STATE_FILE:-$REPO_ROOT/test-harness/work/manual-vm-cluster/current.env}"
VM_ARCH="${VM_ARCH:-}"
VM_BASE_IMAGE="${VM_BASE_IMAGE:-}"
SOURCE_FLAVOR="${SOURCE_FLAVOR:-agave}"
DESTINATION_FLAVOR="${DESTINATION_FLAVOR:-jito-bam}"
PRUNE_OLD_RUNS="${PRUNE_OLD_RUNS:-true}"
PRUNE_KEEP_RUNS="${PRUNE_KEEP_RUNS:-6}"
PRUNE_MIN_FREE_GB="${PRUNE_MIN_FREE_GB:-40}"
PRUNE_MUTABLE_CACHE_DIRS="${PRUNE_MUTABLE_CACHE_DIRS:-auto}"
KILL_STALE_QEMU="${KILL_STALE_QEMU:-true}"
REUSE_PREPARED_VMS="${REUSE_PREPARED_VMS:-true}"
REFRESH_PREPARED_VMS=false
PREPARED_CACHE_KEY_OVERRIDE="${PREPARED_CACHE_KEY_OVERRIDE:-}"
SHARED_ENTRYPOINT_VM="${SHARED_ENTRYPOINT_VM:-false}"
ENTRYPOINT_VM_BRIDGE_IP="${ENTRYPOINT_VM_BRIDGE_IP:-192.168.100.13}"

usage() {
  cat <<'EOF'
Usage:
  run-vm-hot-swap-manual-cluster.sh [options]

Starts the same VM environment used by the L3 canary flow, but exits before
running the hot-swap playbook so the cluster stays up for manual testing.

Options:
  --workdir <path>                 (default: ./test-harness/work/vm-hot-swap-manual)
  --run-id-prefix <id>             (default: vm-hot-swap-manual)
  --state-file <path>              (default: ./test-harness/work/manual-vm-cluster/current.env)
  --vm-arch <amd64|arm64>
  --vm-base-image <path>
  --source-flavor <flavor>         (default: agave)
  --destination-flavor <flavor>    (default: jito-bam)
  --no-prune
  --prune-keep-runs <n>            (default: 6)
  --prune-min-free-gb <n>          (default: 40)
  --prune-mutable-caches
  --no-prune-mutable-caches
  --no-kill-stale-qemu
  --shared-entrypoint
  --no-shared-entrypoint
  --no-vm-reuse
  --refresh-vm-reuse
  --prepared-cache-key <text>
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
    --state-file)
      STATE_FILE="${2:-}"
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
    --source-flavor)
      SOURCE_FLAVOR="${2:-}"
      shift 2
      ;;
    --destination-flavor)
      DESTINATION_FLAVOR="${2:-}"
      shift 2
      ;;
    --no-prune)
      PRUNE_OLD_RUNS=false
      shift
      ;;
    --prune-keep-runs)
      PRUNE_KEEP_RUNS="${2:-}"
      shift 2
      ;;
    --prune-min-free-gb)
      PRUNE_MIN_FREE_GB="${2:-}"
      shift 2
      ;;
    --prune-mutable-caches)
      PRUNE_MUTABLE_CACHE_DIRS=true
      shift
      ;;
    --no-prune-mutable-caches)
      PRUNE_MUTABLE_CACHE_DIRS=false
      shift
      ;;
    --no-kill-stale-qemu)
      KILL_STALE_QEMU=false
      shift
      ;;
    --shared-entrypoint)
      SHARED_ENTRYPOINT_VM=true
      shift
      ;;
    --no-shared-entrypoint)
      SHARED_ENTRYPOINT_VM=false
      shift
      ;;
    --no-vm-reuse)
      REUSE_PREPARED_VMS=false
      shift
      ;;
    --refresh-vm-reuse)
      REFRESH_PREPARED_VMS=true
      shift
      ;;
    --prepared-cache-key)
      PREPARED_CACHE_KEY_OVERRIDE="${2:-}"
      shift 2
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

write_state_var() {
  local key="$1"
  local value="${2:-}"
  printf '%s=%q\n' "$key" "$value" >>"$STATE_FILE"
}

find_latest_case_dir() {
  local pattern="${RUN_ID_PREFIX}-canary-${SOURCE_FLAVOR}-to-${DESTINATION_FLAVOR}-*"

  find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d -name "$pattern" -printf '%f\n' \
    | LC_ALL=C sort \
    | tail -n 1 \
    | awk -v workdir="$WORKDIR" 'NF { print workdir "/" $0 }'
}

mkdir -p "$WORKDIR" "$(dirname "$STATE_FILE")"

echo "==> [manual] Preparing VM cluster for manual testing..." >&2

l3_args=(
  --mode canary
  --workdir "$WORKDIR"
  --run-id-prefix "$RUN_ID_PREFIX"
  --source-flavor "$SOURCE_FLAVOR"
  --destination-flavor "$DESTINATION_FLAVOR"
  --retain-always
)

if [[ -n "$VM_ARCH" ]]; then
  l3_args+=(--vm-arch "$VM_ARCH")
fi
if [[ -n "$VM_BASE_IMAGE" ]]; then
  l3_args+=(--vm-base-image "$VM_BASE_IMAGE")
fi
if [[ "$PRUNE_OLD_RUNS" != "true" ]]; then
  l3_args+=(--no-prune)
fi
l3_args+=(--prune-keep-runs "$PRUNE_KEEP_RUNS" --prune-min-free-gb "$PRUNE_MIN_FREE_GB")
case "$PRUNE_MUTABLE_CACHE_DIRS" in
  true) l3_args+=(--prune-mutable-caches) ;;
  false) l3_args+=(--no-prune-mutable-caches) ;;
esac
if [[ "$KILL_STALE_QEMU" != "true" ]]; then
  l3_args+=(--no-kill-stale-qemu)
fi
if [[ "$SHARED_ENTRYPOINT_VM" == "true" ]]; then
  l3_args+=(--shared-entrypoint)
else
  l3_args+=(--no-shared-entrypoint)
fi
if [[ "$REUSE_PREPARED_VMS" != "true" ]]; then
  l3_args+=(--no-vm-reuse)
fi
if [[ "$REFRESH_PREPARED_VMS" == "true" ]]; then
  l3_args+=(--refresh-vm-reuse)
fi
if [[ -n "$PREPARED_CACHE_KEY_OVERRIDE" ]]; then
  l3_args+=(--prepared-cache-key "$PREPARED_CACHE_KEY_OVERRIDE")
fi

env VM_MANUAL_TEST_ONLY=true \
  "$REPO_ROOT/test-harness/scripts/run-vm-hot-swap-l3-e2e.sh" \
  "${l3_args[@]}"

case_dir="$(find_latest_case_dir)"
if [[ -z "$case_dir" || ! -d "$case_dir" ]]; then
  echo "Manual cluster started, but the retained case directory could not be located under $WORKDIR." >&2
  exit 1
fi

run_id="$(basename "$case_dir")"
entrypoint_pid_file="$case_dir/entrypoint-qemu.pid"
entrypoint_inventory="$case_dir/inventory.entrypoint.bootstrap.yml"
if [[ "$SHARED_ENTRYPOINT_VM" == "true" ]]; then
  entrypoint_pid_file="$WORKDIR/_shared-entrypoint-vm/entrypoint-qemu.pid"
  entrypoint_inventory="$WORKDIR/_shared-entrypoint-vm/inventory.entrypoint.bootstrap.yml"
fi

: >"$STATE_FILE"
write_state_var RUN_ID "$run_id"
write_state_var WORKDIR "$WORKDIR"
write_state_var CASE_DIR "$case_dir"
write_state_var SOURCE_FLAVOR "$SOURCE_FLAVOR"
write_state_var DESTINATION_FLAVOR "$DESTINATION_FLAVOR"
write_state_var SHARED_ENTRYPOINT_VM "$SHARED_ENTRYPOINT_VM"
write_state_var OPERATOR_INVENTORY "$case_dir/inventory.operator.yml"
write_state_var BOOTSTRAP_INVENTORY "$case_dir/inventory.bootstrap.yml"
write_state_var ENTRYPOINT_VM_BOOTSTRAP_INVENTORY "$entrypoint_inventory"
write_state_var SRC_PID_FILE "$case_dir/source-qemu.pid"
write_state_var DST_PID_FILE "$case_dir/destination-qemu.pid"
write_state_var ENTRYPOINT_VM_PID_FILE "$entrypoint_pid_file"
write_state_var LOCALNET_ENTRYPOINT_PID_FILE "$case_dir/localnet-entrypoint.pid"
write_state_var LOCALNET_ENTRYPOINT_LOG "$case_dir/artifacts/localnet-entrypoint.log"
write_state_var ENTRYPOINT_RPC_URL "http://${ENTRYPOINT_VM_BRIDGE_IP}:8899"
write_state_var ENTRYPOINT_GOSSIP "${ENTRYPOINT_VM_BRIDGE_IP}:8001"
write_state_var STATE_FILE "$STATE_FILE"

echo "==> [manual] Cluster ready for manual testing." >&2
echo "    state: $STATE_FILE" >&2
echo "    case:  $case_dir" >&2
echo "    rpc:   http://${ENTRYPOINT_VM_BRIDGE_IP}:8899" >&2
echo "    stop:  $REPO_ROOT/test-harness/scripts/teardown-vm-hot-swap-manual-cluster.sh" >&2

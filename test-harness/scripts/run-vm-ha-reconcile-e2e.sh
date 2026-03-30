#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work/vm-ha-reconcile}"
RUN_ID_PREFIX="${RUN_ID_PREFIX:-vm-ha-reconcile}"
VM_ARCH="${VM_ARCH:-}"
VM_BASE_IMAGE="${VM_BASE_IMAGE:-}"
SOURCE_FLAVOR="${SOURCE_FLAVOR:-agave}"
DESTINATION_FLAVOR="${DESTINATION_FLAVOR:-jito-bam}"
HA_RECONCILE_MODE="${HA_RECONCILE_MODE:-expand}"
HA_PREVIOUS_HOSTS="${HA_PREVIOUS_HOSTS:-}"
HA_REMOVED_HOSTS="${HA_REMOVED_HOSTS:-}"
RETAIN_ON_FAILURE=false
RETAIN_ALWAYS=false

usage() {
  cat <<'EOF'
Usage:
  run-vm-ha-reconcile-e2e.sh [options]

Options:
  --workdir <path>                 (default: ./test-harness/work/vm-ha-reconcile)
  --run-id-prefix <id>             (default: vm-ha-reconcile)
  --vm-arch <amd64|arm64>
  --vm-base-image <path>
  --source-flavor <flavor>         (default: agave)
  --destination-flavor <flavor>    (default: jito-bam)
  --ha-reconcile-mode <in_place|expand|contract> (default: expand)
  --ha-previous-hosts <csv>        (default for expand: vm-source)
  --ha-removed-hosts <csv>         (required for contract; unsupported in current 2-VM wrapper)
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
    --source-flavor)
      SOURCE_FLAVOR="${2:-}"
      shift 2
      ;;
    --destination-flavor)
      DESTINATION_FLAVOR="${2:-}"
      shift 2
      ;;
    --ha-reconcile-mode)
      HA_RECONCILE_MODE="${2:-}"
      shift 2
      ;;
    --ha-previous-hosts)
      HA_PREVIOUS_HOSTS="${2:-}"
      shift 2
      ;;
    --ha-removed-hosts)
      HA_REMOVED_HOSTS="${2:-}"
      shift 2
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

case "$HA_RECONCILE_MODE" in
  in_place|expand|contract)
    ;;
  *)
    echo "Unsupported HA reconcile mode: $HA_RECONCILE_MODE" >&2
    exit 2
    ;;
esac

if [[ "$HA_RECONCILE_MODE" == "expand" && -z "$HA_PREVIOUS_HOSTS" ]]; then
  HA_PREVIOUS_HOSTS="vm-source"
fi

if [[ "$HA_RECONCILE_MODE" == "contract" ]]; then
  echo "The current VM HA reconcile wrapper provisions only two VMs (vm-source and vm-destination)." >&2
  echo "contract requires a larger previous membership than the retained target group, so this topology cannot exercise it safely yet." >&2
  echo "Extend the VM harness to provision a third HA member before using ha_reconcile_mode=contract here." >&2
  exit 2
fi

verify_args=(
  --workdir "$WORKDIR"
  --run-id "${RUN_ID_PREFIX}-$(date +%Y%m%d-%H%M%S)"
  --source-flavor "$SOURCE_FLAVOR"
  --destination-flavor "$DESTINATION_FLAVOR"
)

if [[ -n "$VM_ARCH" ]]; then
  verify_args+=(--vm-arch "$VM_ARCH")
fi

if [[ -n "$VM_BASE_IMAGE" ]]; then
  verify_args+=(--vm-base-image "$VM_BASE_IMAGE")
fi

if [[ "$RETAIN_ON_FAILURE" == "true" ]]; then
  verify_args+=(--retain-on-failure)
fi

if [[ "$RETAIN_ALWAYS" == "true" ]]; then
  verify_args+=(--retain-always)
fi

export VM_NETWORK_MODE="${VM_NETWORK_MODE:-shared-bridge}"
export VM_LOCALNET_ENTRYPOINT_MODE="${VM_LOCALNET_ENTRYPOINT_MODE:-vm}"
export VM_SOURCE_BRIDGE_IP="${VM_SOURCE_BRIDGE_IP:-192.168.100.11}"
export VM_DESTINATION_BRIDGE_IP="${VM_DESTINATION_BRIDGE_IP:-192.168.100.12}"
export ENTRYPOINT_VM_BRIDGE_IP="${ENTRYPOINT_VM_BRIDGE_IP:-192.168.100.13}"
export VM_BRIDGE_GATEWAY_IP="${VM_BRIDGE_GATEWAY_IP:-192.168.100.1}"
export VM_SOURCE_TAP_IFACE="${VM_SOURCE_TAP_IFACE:-tap-hvk-ha-src}"
export VM_DESTINATION_TAP_IFACE="${VM_DESTINATION_TAP_IFACE:-tap-hvk-ha-dst}"
export ENTRYPOINT_VM_TAP_IFACE="${ENTRYPOINT_VM_TAP_IFACE:-tap-hvk-ha-ent}"
export SOLANA_VALIDATOR_HA_RUNTIME_ENABLED=true
export HA_RECONCILE_MODE
export HA_PREVIOUS_HOSTS
export HA_REMOVED_HOSTS

exec "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh" "${verify_args[@]}"

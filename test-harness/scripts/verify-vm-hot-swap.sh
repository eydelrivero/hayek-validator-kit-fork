#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_START_TS="$(date +%s)"

RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work/vm-hot-swap}"
VM_ARCH="${VM_ARCH:-}"
VM_BASE_IMAGE="${VM_BASE_IMAGE:-}"
VM_CPUS="${VM_CPUS:-4}"
VM_RAM_MB="${VM_RAM_MB:-8192}"
VM_DISK_SYSTEM_GB="${VM_DISK_SYSTEM_GB:-40}"
VM_DISK_LEDGER_GB="${VM_DISK_LEDGER_GB:-20}"
VM_DISK_ACCOUNTS_GB="${VM_DISK_ACCOUNTS_GB:-10}"
VM_DISK_SNAPSHOTS_GB="${VM_DISK_SNAPSHOTS_GB:-0}"
VM_QEMU_EFI="${VM_QEMU_EFI:-}"
VM_NETWORK_MODE="${VM_NETWORK_MODE:-usernet}"
VM_BRIDGE_NAME="${VM_BRIDGE_NAME:-br-hvk}"
VM_BRIDGE_CIDR_PREFIX="${VM_BRIDGE_CIDR_PREFIX:-24}"
VM_BRIDGE_GATEWAY_IP="${VM_BRIDGE_GATEWAY_IP:-}"
VM_BRIDGE_DNS_IP="${VM_BRIDGE_DNS_IP:-}"
VM_NETWORK_MATCH_NAME="${VM_NETWORK_MATCH_NAME:-e*}"
VM_SOURCE_BRIDGE_IP="${VM_SOURCE_BRIDGE_IP:-}"
VM_DESTINATION_BRIDGE_IP="${VM_DESTINATION_BRIDGE_IP:-}"
VM_SOURCE_TAP_IFACE="${VM_SOURCE_TAP_IFACE:-}"
VM_DESTINATION_TAP_IFACE="${VM_DESTINATION_TAP_IFACE:-}"
VM_SOURCE_MAC_ADDRESS="${VM_SOURCE_MAC_ADDRESS:-52:54:00:10:00:11}"
VM_DESTINATION_MAC_ADDRESS="${VM_DESTINATION_MAC_ADDRESS:-52:54:00:10:00:12}"

SSH_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_FILE:-$REPO_ROOT/scripts/vm-test/work/id_ed25519}"
SOURCE_SSH_PORT="${SOURCE_SSH_PORT:-2222}"
SOURCE_SSH_PORT_ALT="${SOURCE_SSH_PORT_ALT:-2522}"
DESTINATION_SSH_PORT="${DESTINATION_SSH_PORT:-3222}"
DESTINATION_SSH_PORT_ALT="${DESTINATION_SSH_PORT_ALT:-3522}"
SSH_WAIT_TIMEOUT="${SSH_WAIT_TIMEOUT:-420}"

BOOTSTRAP_USER="${BOOTSTRAP_USER:-ubuntu}"
METAL_BOX_SYSADMIN_USER="${METAL_BOX_SYSADMIN_USER:-alice}"
VALIDATOR_OPERATOR_USER="${VALIDATOR_OPERATOR_USER:-bob}"
VALIDATOR_NAME="${VALIDATOR_NAME:-demo1}"
SOLANA_CLUSTER="${SOLANA_CLUSTER:-localnet}"
SOLANA_CLUSTER_NORMALIZED="${SOLANA_CLUSTER#solana_}"
SOLANA_CLUSTER_VARS_FILE="${SOLANA_CLUSTER_VARS_FILE:-$REPO_ROOT/ansible/group_vars/solana_${SOLANA_CLUSTER_NORMALIZED}.yml}"
CITY_GROUP="${CITY_GROUP:-city_dal}"
CITY_GROUP_VARS_FILE="${CITY_GROUP_VARS_FILE:-$REPO_ROOT/ansible/group_vars/${CITY_GROUP}.yml}"
SWAP_EPOCH_END_THRESHOLD_SEC="${SWAP_EPOCH_END_THRESHOLD_SEC:-0}"
PRE_SWAP_CATCHUP_TIMEOUT_SEC="${PRE_SWAP_CATCHUP_TIMEOUT_SEC:-900}"
PRE_SWAP_TOWER_TIMEOUT_SEC="${PRE_SWAP_TOWER_TIMEOUT_SEC:-120}"
REUSE_RUNTIME_READY_TIMEOUT_SEC="${REUSE_RUNTIME_READY_TIMEOUT_SEC:-900}"
VM_ENTRYPOINT_PREFLIGHT_TIMEOUT_SEC="${VM_ENTRYPOINT_PREFLIGHT_TIMEOUT_SEC:-60}"
VM_ENTRYPOINT_PREFLIGHT_RETRIES="${VM_ENTRYPOINT_PREFLIGHT_RETRIES:-3}"
VM_ENTRYPOINT_PREFLIGHT_RETRY_SLEEP_SEC="${VM_ENTRYPOINT_PREFLIGHT_RETRY_SLEEP_SEC:-3}"
PRE_SWAP_INJECTION_MODE="${PRE_SWAP_INJECTION_MODE:-none}"
VM_AUTHORIZED_IP="${VM_AUTHORIZED_IP:-10.0.2.2}"
SSH_COMMON_ARGS="${SSH_COMMON_ARGS:--o IdentitiesOnly=yes -o IdentityAgent=none -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no}"
ENABLE_VM_TEST_SYSADMIN_NOPASSWD="${ENABLE_VM_TEST_SYSADMIN_NOPASSWD:-true}"
AUTO_KILL_CONFLICTING_QEMU="${AUTO_KILL_CONFLICTING_QEMU:-true}"
VM_METAL_BOX_SKIP_TAGS="${VM_METAL_BOX_SKIP_TAGS:-restart,cpu-isolation}"
VM_DISABLE_CPU_GOVERNOR_SERVICE="${VM_DISABLE_CPU_GOVERNOR_SERVICE:-true}"
VM_LOCALNET_ENTRYPOINT_MODE="${VM_LOCALNET_ENTRYPOINT_MODE:-auto}"
VM_LOCALNET_ENTRYPOINT_RPC_HOST="${VM_LOCALNET_ENTRYPOINT_RPC_HOST:-127.0.0.1}"
VM_LOCALNET_ENTRYPOINT_RPC_PORT="${VM_LOCALNET_ENTRYPOINT_RPC_PORT:-8899}"
VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS="${VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS:-10.0.2.2}"
VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_PROCESS="${VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_PROCESS:-127.0.0.1}"
VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT="${VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT:-8001}"
VM_LOCALNET_ENTRYPOINT_DYNAMIC_PORT_RANGE="${VM_LOCALNET_ENTRYPOINT_DYNAMIC_PORT_RANGE:-8000-8030}"
VM_LOCALNET_ENTRYPOINT_SLOTS_PER_EPOCH="${VM_LOCALNET_ENTRYPOINT_SLOTS_PER_EPOCH:-750}"
VM_LOCALNET_ENTRYPOINT_LIMIT_LEDGER_SIZE="${VM_LOCALNET_ENTRYPOINT_LIMIT_LEDGER_SIZE:-50000000}"
VM_LOCALNET_ENTRYPOINT_FAUCET_PORT="${VM_LOCALNET_ENTRYPOINT_FAUCET_PORT:-19900}"
VM_LOCALNET_ENTRYPOINT_ENGINE="${VM_LOCALNET_ENTRYPOINT_ENGINE:-auto}"
VM_LOCALNET_ENTRYPOINT_CONTAINER_IMAGE="${VM_LOCALNET_ENTRYPOINT_CONTAINER_IMAGE:-}"
VM_LOCALNET_ENTRYPOINT_CONTAINER_DYNAMIC_PORT_RANGE="${VM_LOCALNET_ENTRYPOINT_CONTAINER_DYNAMIC_PORT_RANGE:-}"
VM_LOCALNET_ENTRYPOINT_CONTAINER_REBUILD="${VM_LOCALNET_ENTRYPOINT_CONTAINER_REBUILD:-false}"
ENTRYPOINT_VM_SSH_PORT="${ENTRYPOINT_VM_SSH_PORT:-4222}"
ENTRYPOINT_VM_SSH_PORT_ALT="${ENTRYPOINT_VM_SSH_PORT_ALT:-4522}"
ENTRYPOINT_VM_GUEST_RPC_PORT="${ENTRYPOINT_VM_GUEST_RPC_PORT:-8899}"
ENTRYPOINT_VM_GUEST_GOSSIP_PORT="${ENTRYPOINT_VM_GUEST_GOSSIP_PORT:-8001}"
ENTRYPOINT_VM_GUEST_FAUCET_PORT="${ENTRYPOINT_VM_GUEST_FAUCET_PORT:-9900}"
ENTRYPOINT_VM_BASE_IMAGE="${ENTRYPOINT_VM_BASE_IMAGE:-}"
ENTRYPOINT_VM_SKIP_CLI_INSTALL="${ENTRYPOINT_VM_SKIP_CLI_INSTALL:-auto}"
SHARED_ENTRYPOINT_VM="${SHARED_ENTRYPOINT_VM:-false}"
VM_SOURCE_DISK_PARENT_PREFIX="${VM_SOURCE_DISK_PARENT_PREFIX:-}"
VM_DESTINATION_DISK_PARENT_PREFIX="${VM_DESTINATION_DISK_PARENT_PREFIX:-}"
VM_ENTRYPOINT_DISK_PARENT_PREFIX="${VM_ENTRYPOINT_DISK_PARENT_PREFIX:-}"
VM_PREPARE_ONLY="${VM_PREPARE_ONLY:-false}"
VM_PREPARE_EXPORT_DIR="${VM_PREPARE_EXPORT_DIR:-}"
VM_ENTRYPOINT_PREPARE_ONLY="${VM_ENTRYPOINT_PREPARE_ONLY:-false}"
VM_MANUAL_TEST_ONLY="${VM_MANUAL_TEST_ONLY:-false}"
PREPARED_VM_REUSE_MODE=false
ENTRYPOINT_VM_BRIDGE_IP="${ENTRYPOINT_VM_BRIDGE_IP:-}"
ENTRYPOINT_VM_TAP_IFACE="${ENTRYPOINT_VM_TAP_IFACE:-}"
ENTRYPOINT_VM_MAC_ADDRESS="${ENTRYPOINT_VM_MAC_ADDRESS:-52:54:00:10:00:13}"

SOURCE_FLAVOR=""
DESTINATION_FLAVOR=""

AGAVE_VERSION="${AGAVE_VERSION:-3.1.10}"
JITO_VERSION="${JITO_VERSION:-2.3.6}"
BAM_JITO_VERSION="${BAM_JITO_VERSION:-3.1.10}"
BAM_JITO_VERSION_PATCH="${BAM_JITO_VERSION_PATCH:-}"
BAM_EXPECT_CLIENT_REGEX="${BAM_EXPECT_CLIENT_REGEX:-Bam}"
BUILD_FROM_SOURCE="${BUILD_FROM_SOURCE:-false}"
FORCE_HOST_CLEANUP="${FORCE_HOST_CLEANUP:-true}"
SKIP_CONFIRMATION_PAUSES="${SKIP_CONFIRMATION_PAUSES:-true}"
SOLANA_VALIDATOR_HA_RUNTIME_ENABLED="${SOLANA_VALIDATOR_HA_RUNTIME_ENABLED:-false}"
SOLANA_VALIDATOR_HA_RECONCILE_GROUP="${SOLANA_VALIDATOR_HA_RECONCILE_GROUP:-ha_vm_hot_swap}"
SOLANA_VALIDATOR_HA_SOURCE_NODE_ID="${SOLANA_VALIDATOR_HA_SOURCE_NODE_ID:-ark}"
SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID="${SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID:-fog}"
SOLANA_VALIDATOR_HA_SOURCE_PRIORITY="${SOLANA_VALIDATOR_HA_SOURCE_PRIORITY:-10}"
SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY="${SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY:-20}"
HA_RECONCILE_INVENTORY_GROUP_ALL="${HA_RECONCILE_INVENTORY_GROUP_ALL:-}"
HA_RECONCILE_ALLOW_DECOMMISSION="${HA_RECONCILE_ALLOW_DECOMMISSION:-false}"

if [[ -z "$VM_LOCALNET_ENTRYPOINT_CONTAINER_IMAGE" ]]; then
  VM_LOCALNET_ENTRYPOINT_CONTAINER_IMAGE="hvk-vm-gossip-entrypoint:${AGAVE_VERSION}"
fi

VALIDATOR_KEYSET_SOURCE_DIR="${VALIDATOR_KEYSET_SOURCE_DIR:-$REPO_ROOT/solana-localnet/validator-keys/demo1}"
SOURCE_VALIDATOR_KEYSET_NAME="${SOURCE_VALIDATOR_KEYSET_NAME:-${VALIDATOR_NAME}-vm-source}"
DESTINATION_VALIDATOR_KEYSET_NAME="${DESTINATION_VALIDATOR_KEYSET_NAME:-${VALIDATOR_NAME}-vm-destination}"
SOURCE_HOT_SPARE_IDENTITY_SOURCE="${SOURCE_HOT_SPARE_IDENTITY_SOURCE:-$VALIDATOR_KEYSET_SOURCE_DIR/hot-spare-identity.json}"
DESTINATION_HOT_SPARE_IDENTITY_SOURCE="${DESTINATION_HOT_SPARE_IDENTITY_SOURCE:-$REPO_ROOT/solana-localnet/validator-keys/demo2/hot-spare-identity.json}"

RETAIN_ALWAYS=false
RETAIN_ON_FAILURE=false
EXEC_OK=false
REPORT_EMITTED=false
PRE_SWAP_VERIFIED=false
HOT_SWAP_COMPLETED=false
POST_SWAP_VERIFIED=false
SWAP_IDENTITY_VERIFIED=false
ENTRYPOINT_PREFLIGHT_VM_SOURCE=false
ENTRYPOINT_PREFLIGHT_VM_DESTINATION=false
USERS_METAL_SETUP_DURATION_SEC=0
ENTRYPOINT_PREFLIGHT_DURATION_SEC=0
SOURCE_SETUP_DURATION_SEC=0
DESTINATION_SETUP_DURATION_SEC=0
PRE_SWAP_VERIFY_DURATION_SEC=0
HOT_SWAP_DURATION_SEC=0
POST_SWAP_VERIFY_DURATION_SEC=0
TOTAL_DURATION_SEC=0
HOST_VERSION_VM_SOURCE=""
HOST_VERSION_VM_DESTINATION=""
HOST_SERVICE_VM_SOURCE=""
HOST_SERVICE_VM_DESTINATION=""
HOST_DIAGNOSTIC_VM_SOURCE=""
HOST_DIAGNOSTIC_VM_DESTINATION=""
ENTRYPOINT_PREFLIGHT_DETAILS_VM_SOURCE=""
ENTRYPOINT_PREFLIGHT_DETAILS_VM_DESTINATION=""
SOURCE_IDENTITY_BEFORE=""
SOURCE_PRIMARY_TARGET_BEFORE=""
SOURCE_HOT_SPARE_BEFORE=""
DESTINATION_IDENTITY_BEFORE=""
DESTINATION_PRIMARY_TARGET_BEFORE=""
DESTINATION_HOT_SPARE_BEFORE=""
SOURCE_IDENTITY_AFTER=""
SOURCE_PRIMARY_TARGET_AFTER=""
SOURCE_HOT_SPARE_AFTER=""
DESTINATION_IDENTITY_AFTER=""
DESTINATION_PRIMARY_TARGET_AFTER=""
DESTINATION_HOT_SPARE_AFTER=""
CATCHUP_SNAPSHOT_BEFORE=""
CATCHUP_SNAPSHOT_AFTER=""
GOSSIP_SNAPSHOT_BEFORE=""
GOSSIP_SNAPSHOT_AFTER=""
EARLY_FAILURE_REASON=""
ENTRYPOINT_BOOTSTRAP_OUTPUT=""
REPORT_DIAGNOSIS=""
CURRENT_PHASE="initialization"

on_error() {
  local rc="${1:-1}"
  local line="${2:-unknown}"
  local failed_command="${BASH_COMMAND:-unknown}"

  if [[ "${REPORT_EMITTED:-false}" == "true" ]]; then
    return 0
  fi

  if [[ -z "${EARLY_FAILURE_REASON:-}" ]]; then
    EARLY_FAILURE_REASON="Command failed during ${CURRENT_PHASE:-unknown} (line ${line}, exit ${rc})"
  fi

  if [[ -z "${ENTRYPOINT_BOOTSTRAP_OUTPUT:-}" ]]; then
    ENTRYPOINT_BOOTSTRAP_OUTPUT="Failed command: ${failed_command}"
  elif [[ "${ENTRYPOINT_BOOTSTRAP_OUTPUT}" != *"Failed command:"* ]]; then
    ENTRYPOINT_BOOTSTRAP_OUTPUT="${ENTRYPOINT_BOOTSTRAP_OUTPUT}

Failed command: ${failed_command}"
  fi

  return 0
}

usage() {
  cat <<'EOF'
Usage:
  verify-vm-hot-swap.sh --source-flavor <flavor> --destination-flavor <flavor> [options]

Required:
  --source-flavor <agave|jito-shared|jito-cohosted|jito-bam>
  --destination-flavor <agave|jito-shared|jito-cohosted|jito-bam>

Optional:
  --run-id <id>
  --workdir <path>
  --vm-arch <amd64|arm64>
  --vm-base-image <path>
  --source-ssh-port <int>            (default: 2222)
  --source-ssh-port-alt <int>        (default: 2522)
  --destination-ssh-port <int>       (default: 3222)
  --destination-ssh-port-alt <int>   (default: 3522)
  --retain-always
  --retain-on-failure

Environment:
  PRE_SWAP_INJECTION_MODE=none|stop_source_validator_service|mismatch_destination_primary_identity|block_source_to_destination_ssh
    (backward-compat alias: stop_entrypoint_rpc)
  SHARED_ENTRYPOINT_VM=true|false (default: false; keeps a shared entrypoint VM under <workdir> across runs)
  VM_SOURCE_DISK_PARENT_PREFIX=<abs-prefix> and VM_DESTINATION_DISK_PARENT_PREFIX=<abs-prefix> (reuse prepared source/destination disks via qcow2 overlays)
  VM_ENTRYPOINT_DISK_PARENT_PREFIX=<abs-prefix> (reuse a stateless entrypoint VM disk cache via qcow2 overlays)
  VM_PREPARE_ONLY=true with VM_PREPARE_EXPORT_DIR=<dir> (prepare source/destination VM disks and exit before swap)
  VM_ENTRYPOINT_PREPARE_ONLY=true (prepare shared entrypoint VM cache [CLI + launcher], do not start localnet runtime)
  VM_MANUAL_TEST_ONLY=true (boot a full pre-swap cluster for manual testing, emit report, retain VMs if requested, and skip the swap)
  HA_RECONCILE_INVENTORY_GROUP_ALL=<group> (optional HA universe override for pb_reconcile_validator_ha_cluster.yml)
  HA_RECONCILE_ALLOW_DECOMMISSION=true|false (default: false; required when target HA group omits managed peers)
EOF
}

while (($# > 0)); do
  case "$1" in
    --source-flavor)
      SOURCE_FLAVOR="${2:-}"
      shift 2
      ;;
    --destination-flavor)
      DESTINATION_FLAVOR="${2:-}"
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
    --vm-arch)
      VM_ARCH="${2:-}"
      shift 2
      ;;
    --vm-base-image)
      VM_BASE_IMAGE="${2:-}"
      shift 2
      ;;
    --source-ssh-port)
      SOURCE_SSH_PORT="${2:-}"
      shift 2
      ;;
    --source-ssh-port-alt)
      SOURCE_SSH_PORT_ALT="${2:-}"
      shift 2
      ;;
    --destination-ssh-port)
      DESTINATION_SSH_PORT="${2:-}"
      shift 2
      ;;
    --destination-ssh-port-alt)
      DESTINATION_SSH_PORT_ALT="${2:-}"
      shift 2
      ;;
    --retain-always)
      RETAIN_ALWAYS=true
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

if [[ -z "$SOURCE_FLAVOR" || -z "$DESTINATION_FLAVOR" ]]; then
  usage
  exit 2
fi

if [[ -n "$VM_SOURCE_DISK_PARENT_PREFIX" || -n "$VM_DESTINATION_DISK_PARENT_PREFIX" ]]; then
  if [[ -z "$VM_SOURCE_DISK_PARENT_PREFIX" || -z "$VM_DESTINATION_DISK_PARENT_PREFIX" ]]; then
    echo "Both VM_SOURCE_DISK_PARENT_PREFIX and VM_DESTINATION_DISK_PARENT_PREFIX must be set together." >&2
    exit 2
  fi
  PREPARED_VM_REUSE_MODE=true
fi

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    case "$cmd" in
      solana|solana-keygen|solana-test-validator)
        echo "Missing required command: $cmd" >&2
        echo "The VM hot-swap harness requires Solana CLI tools on the host PATH for localnet control-plane operations." >&2
        echo "Install or expose host-side binaries for: solana, solana-keygen, and solana-test-validator." >&2
        echo "Then verify with: solana --version && solana-keygen --version && solana-test-validator --version" >&2
        ;;
      *)
        echo "Missing required command: $cmd" >&2
        ;;
    esac
    exit 3
  fi
}

detect_shared_bridge_uplink_iface() {
  ip route show default 2>/dev/null | awk '/^default/ { print $5; exit }'
}

detect_shared_bridge_dns_ipv4() {
  local uplink_iface="$1"

  if command -v resolvectl >/dev/null 2>&1 && [[ -n "$uplink_iface" ]]; then
    resolvectl dns "$uplink_iface" 2>/dev/null \
      | awk '{ for (i = 3; i <= NF; i++) if ($i ~ /^[0-9.]+$/ && $i !~ /^127\./) { print $i; exit } }'
    return 0
  fi

  awk '/^nameserver[[:space:]]+[0-9.]+$/ { if ($2 !~ /^127\./) { print $2; exit } }' /etc/resolv.conf 2>/dev/null
}

for cmd in ansible-playbook ansible jq qemu-img ssh-keygen ssh-keyscan; do
  require_cmd "$cmd"
done

case "$VM_NETWORK_MODE" in
  usernet|shared-bridge) ;;
  *)
    echo "Unsupported VM_NETWORK_MODE: $VM_NETWORK_MODE (expected: usernet|shared-bridge)" >&2
    exit 2
    ;;
esac

# Ensure role/module lookup is stable regardless of caller working directory.
export TERM="${TERM:-dumb}"
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"
export ANSIBLE_ROLES_PATH="$REPO_ROOT/ansible/roles"
export ANSIBLE_BECOME_TIMEOUT="${ANSIBLE_BECOME_TIMEOUT:-45}"
export ANSIBLE_TIMEOUT="${ANSIBLE_TIMEOUT:-45}"
if [[ ! -r "$SOLANA_CLUSTER_VARS_FILE" ]]; then
  echo "Cluster vars file is not readable: $SOLANA_CLUSTER_VARS_FILE" >&2
  exit 3
fi
if [[ ! -r "$CITY_GROUP_VARS_FILE" ]]; then
  echo "City group vars file is not readable: $CITY_GROUP_VARS_FILE" >&2
  exit 3
fi

COMMON_ANSIBLE_EXTRA_VARS_ARGS=(
  -e "@$REPO_ROOT/ansible/group_vars/all.yml"
  -e "@$REPO_ROOT/ansible/group_vars/solana.yml"
  -e "@$SOLANA_CLUSTER_VARS_FILE"
  -e "@$CITY_GROUP_VARS_FILE"
)

if [[ "$SOLANA_CLUSTER_NORMALIZED" == "localnet" ]]; then
  case "$VM_LOCALNET_ENTRYPOINT_MODE" in
    auto|container|external|host|vm) ;;
    *)
      echo "Unsupported VM_LOCALNET_ENTRYPOINT_MODE: $VM_LOCALNET_ENTRYPOINT_MODE (expected: auto|container|external|host|vm)" >&2
      exit 2
      ;;
  esac
  if [[ "$VM_NETWORK_MODE" == "shared-bridge" ]]; then
    if [[ -z "$VM_SOURCE_BRIDGE_IP" || -z "$VM_DESTINATION_BRIDGE_IP" || -z "$VM_BRIDGE_GATEWAY_IP" || -z "$VM_SOURCE_TAP_IFACE" || -z "$VM_DESTINATION_TAP_IFACE" ]]; then
      echo "VM_NETWORK_MODE=shared-bridge requires VM_SOURCE_BRIDGE_IP, VM_DESTINATION_BRIDGE_IP, VM_BRIDGE_GATEWAY_IP, VM_SOURCE_TAP_IFACE, and VM_DESTINATION_TAP_IFACE." >&2
      exit 2
    fi
    if [[ -z "$VM_BRIDGE_DNS_IP" ]]; then
      VM_BRIDGE_DNS_IP="$(detect_shared_bridge_dns_ipv4 "$(detect_shared_bridge_uplink_iface)")"
      if [[ -n "$VM_BRIDGE_DNS_IP" ]]; then
        echo "[vm-hot-swap] Auto-detected shared-bridge guest DNS server: ${VM_BRIDGE_DNS_IP}" >&2
      else
        VM_BRIDGE_DNS_IP="$VM_BRIDGE_GATEWAY_IP"
        echo "[vm-hot-swap] Warning: unable to auto-detect a non-loopback DNS server; falling back to bridge gateway ${VM_BRIDGE_DNS_IP}." >&2
      fi
    fi
    case "$VM_LOCALNET_ENTRYPOINT_MODE" in
      host|external) ;;
      vm)
        if [[ -z "$ENTRYPOINT_VM_BRIDGE_IP" || -z "$ENTRYPOINT_VM_TAP_IFACE" ]]; then
          echo "VM_LOCALNET_ENTRYPOINT_MODE=vm with VM_NETWORK_MODE=shared-bridge requires ENTRYPOINT_VM_BRIDGE_IP and ENTRYPOINT_VM_TAP_IFACE." >&2
          exit 2
        fi
        ;;
      *)
        echo "VM_NETWORK_MODE=shared-bridge currently supports VM_LOCALNET_ENTRYPOINT_MODE=host, external, or vm only. Compose/container remains double-NAT." >&2
        exit 2
        ;;
    esac
    if [[ "$VM_LOCALNET_ENTRYPOINT_MODE" == "vm" ]]; then
      if [[ "$VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS" == "10.0.2.2" ]]; then
        VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS="$ENTRYPOINT_VM_BRIDGE_IP"
      fi
      if [[ "$VM_LOCALNET_ENTRYPOINT_RPC_HOST" == "127.0.0.1" ]]; then
        VM_LOCALNET_ENTRYPOINT_RPC_HOST="$ENTRYPOINT_VM_BRIDGE_IP"
      fi
      if [[ "$VM_AUTHORIZED_IP" == "10.0.2.2" || "$VM_AUTHORIZED_IP" == "$VM_BRIDGE_GATEWAY_IP" ]]; then
        VM_AUTHORIZED_IP="$VM_BRIDGE_GATEWAY_IP"
      fi
    else
      if [[ "$VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS" == "10.0.2.2" ]]; then
        VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS="$VM_BRIDGE_GATEWAY_IP"
      fi
      if [[ "$VM_AUTHORIZED_IP" == "10.0.2.2" ]]; then
        VM_AUTHORIZED_IP="$VM_BRIDGE_GATEWAY_IP"
      fi
    fi
  fi
  COMMON_ANSIBLE_EXTRA_VARS_ARGS+=(
    -e "solana_rpc_url=http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}"
    -e "{\"solana_gossip_entrypoints\":[\"${VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS}:${VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT}\"]}"
  )
fi

CPU_GOVERNOR_MANAGE="true"
if [[ "$VM_DISABLE_CPU_GOVERNOR_SERVICE" == "true" ]]; then
  CPU_GOVERNOR_MANAGE="false"
fi

if [[ -z "$VM_ARCH" ]]; then
  case "$(uname -m)" in
    arm64|aarch64) VM_ARCH="arm64" ;;
    *) VM_ARCH="amd64" ;;
  esac
fi

if [[ -z "$VM_BASE_IMAGE" ]]; then
  VM_BASE_IMAGE="$REPO_ROOT/scripts/vm-test/work/ubuntu-${VM_ARCH}.img"
fi
if [[ ! -r "$VM_BASE_IMAGE" ]]; then
  echo "VM base image is not readable: $VM_BASE_IMAGE" >&2
  exit 3
fi
vm_base_image_name="$(basename "$VM_BASE_IMAGE")"
case "$vm_base_image_name" in
  *amd64*)
    if [[ "$VM_ARCH" != "amd64" ]]; then
      echo "VM arch/base image mismatch: VM_ARCH=$VM_ARCH but base image looks like amd64 ($VM_BASE_IMAGE)" >&2
      exit 2
    fi
    ;;
  *arm64*|*aarch64*)
    if [[ "$VM_ARCH" != "arm64" ]]; then
      echo "VM arch/base image mismatch: VM_ARCH=$VM_ARCH but base image looks like arm64 ($VM_BASE_IMAGE)" >&2
      exit 2
    fi
    ;;
esac
if [[ -z "$ENTRYPOINT_VM_BASE_IMAGE" ]]; then
  ENTRYPOINT_VM_BASE_IMAGE="$VM_BASE_IMAGE"
fi
if [[ ! -r "$ENTRYPOINT_VM_BASE_IMAGE" ]]; then
  echo "Entrypoint VM base image is not readable: $ENTRYPOINT_VM_BASE_IMAGE" >&2
  exit 3
fi

if [[ ! -r "$VALIDATOR_KEYSET_SOURCE_DIR/primary-target-identity.json" ]]; then
  echo "Validator keyset source directory is missing primary-target-identity.json: $VALIDATOR_KEYSET_SOURCE_DIR" >&2
  exit 3
fi
if [[ ! -r "$VALIDATOR_KEYSET_SOURCE_DIR/vote-account.json" ]]; then
  echo "Validator keyset source directory is missing vote-account.json: $VALIDATOR_KEYSET_SOURCE_DIR" >&2
  exit 3
fi
if [[ ! -r "$SOURCE_HOT_SPARE_IDENTITY_SOURCE" ]]; then
  echo "Source hot-spare identity is not readable: $SOURCE_HOT_SPARE_IDENTITY_SOURCE" >&2
  exit 3
fi
if [[ ! -r "$DESTINATION_HOT_SPARE_IDENTITY_SOURCE" ]]; then
  echo "Destination hot-spare identity is not readable: $DESTINATION_HOT_SPARE_IDENTITY_SOURCE" >&2
  exit 3
fi

mkdir -p "$(dirname "$SSH_PRIVATE_KEY_FILE")"
if [[ ! -r "$SSH_PRIVATE_KEY_FILE" ]]; then
  ssh-keygen -t ed25519 -f "$SSH_PRIVATE_KEY_FILE" -N "" >/dev/null
fi
if [[ ! -r "${SSH_PRIVATE_KEY_FILE}.pub" ]]; then
  ssh-keygen -y -f "$SSH_PRIVATE_KEY_FILE" >"${SSH_PRIVATE_KEY_FILE}.pub"
fi
SSH_PUBLIC_KEY="$(cat "${SSH_PRIVATE_KEY_FILE}.pub")"

ensure_local_keyset() {
  local target_dir="$1"
  local hot_spare_source="$2"

  mkdir -p "$(dirname "$target_dir")"
  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  cp -a "$VALIDATOR_KEYSET_SOURCE_DIR"/. "$target_dir"/
  cp -f "$hot_spare_source" "$target_dir/hot-spare-identity.json"
}

ha_client_for_flavor() {
  local flavor="$1"
  case "$flavor" in
    agave)
      printf '%s\n' "agave"
      ;;
    jito-shared|jito-cohosted|jito-bam)
      printf '%s\n' "jito"
      ;;
    *)
      echo "Unsupported HA client flavor: $flavor" >&2
      exit 2
      ;;
  esac
}

expected_client_regex_for_flavor() {
  local flavor="$1"
  case "$flavor" in
    agave) echo 'client:(Solana|Agave)' ;;
    jito-shared|jito-cohosted|jito-bam) echo 'client:(JitoLabs|Bam)' ;;
    *)
      echo "Unsupported flavor: $flavor" >&2
      exit 2
      ;;
  esac
}

LOCALNET_ENTRYPOINT_PID_FILE=""
LOCALNET_ENTRYPOINT_LOG=""
LOCALNET_ENTRYPOINT_STARTED_BY_SCRIPT=false
LOCALNET_ENTRYPOINT_GENESIS_HASH=""
LOCALNET_ENTRYPOINT_CONTAINER_STARTED_BY_SCRIPT=false
LOCALNET_ENTRYPOINT_ENGINE_RESOLVED=""
LOCALNET_ENTRYPOINT_CONTAINER_NAME=""
LOCALNET_ENTRYPOINT_COMPOSE_PROJECT=""
LOCALNET_ENTRYPOINT_CONTAINER_LEDGER_DIR=""
LOCALNET_ENTRYPOINT_CONTAINER_PORT_RANGE=""
LOCALNET_ENTRYPOINT_COMPOSE_HELPER="$REPO_ROOT/test-harness/scripts/manage-vm-control-plane.sh"

is_tcp_port_listening() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1
}

localnet_rpc_ready() {
  local rpc_url="$1"
  solana -u "$rpc_url" genesis-hash >/dev/null 2>&1
}

vm_uses_shared_bridge() {
  [[ "${VM_NETWORK_MODE}" == "shared-bridge" ]]
}

assert_shared_bridge_network_ready() {
  local missing=false
  local iface
  local required_ifaces=("$VM_SOURCE_TAP_IFACE" "$VM_DESTINATION_TAP_IFACE")

  if ! vm_uses_shared_bridge; then
    return 0
  fi

  if ! command -v ip >/dev/null 2>&1; then
    echo "VM_NETWORK_MODE=shared-bridge requires the 'ip' command (iproute2)." >&2
    exit 3
  fi

  if ! ip link show "$VM_BRIDGE_NAME" >/dev/null 2>&1; then
    echo "[vm-hot-swap] Missing shared bridge interface: ${VM_BRIDGE_NAME}" >&2
    missing=true
  fi

  if entrypoint_mode_uses_vm; then
    required_ifaces+=("$ENTRYPOINT_VM_TAP_IFACE")
  fi

  for iface in "${required_ifaces[@]}"; do
    if [[ -z "$iface" ]]; then
      continue
    fi
    if ! ip link show "$iface" >/dev/null 2>&1; then
      echo "[vm-hot-swap] Missing shared-bridge TAP interface: ${iface}" >&2
      missing=true
    fi
  done

  if [[ "$missing" == "true" ]]; then
    EARLY_FAILURE_REASON="Shared bridge/tap networking is not ready"
    ENTRYPOINT_BOOTSTRAP_OUTPUT="Missing bridge/tap interfaces for VM_NETWORK_MODE=shared-bridge"
    cat >&2 <<EOF
[vm-hot-swap] Shared bridge/tap networking is not ready.
[vm-hot-swap] Recreate it with:
  ./scripts/vm-test/setup-shared-bridge.sh
[vm-hot-swap] If that asks for privileges, run it with sudo.
EOF
    exit 3
  fi
}

vm_bootstrap_host_for() {
  local host="$1"
  if vm_uses_shared_bridge; then
    case "$host" in
      vm-source) printf '%s\n' "$VM_SOURCE_BRIDGE_IP" ;;
      vm-destination) printf '%s\n' "$VM_DESTINATION_BRIDGE_IP" ;;
      vm-entrypoint) printf '%s\n' "$ENTRYPOINT_VM_BRIDGE_IP" ;;
      *) return 1 ;;
    esac
  else
    printf '127.0.0.1\n'
  fi
}

vm_bootstrap_port_for() {
  local host="$1"
  if vm_uses_shared_bridge; then
    printf '22\n'
  else
    case "$host" in
      vm-source) printf '%s\n' "$SOURCE_SSH_PORT" ;;
      vm-destination) printf '%s\n' "$DESTINATION_SSH_PORT" ;;
      vm-entrypoint) printf '%s\n' "$ENTRYPOINT_VM_SSH_PORT" ;;
      *) return 1 ;;
    esac
  fi
}

vm_operator_host_for() {
  vm_bootstrap_host_for "$1"
}

vm_operator_port_for() {
  local host="$1"
  if vm_uses_shared_bridge; then
    printf '2522\n'
  else
    case "$host" in
      vm-source) printf '%s\n' "$SOURCE_SSH_PORT_ALT" ;;
      vm-destination) printf '%s\n' "$DESTINATION_SSH_PORT_ALT" ;;
      vm-entrypoint) printf '%s\n' "$ENTRYPOINT_VM_SSH_PORT_ALT" ;;
      *) return 1 ;;
    esac
  fi
}

vm_tap_iface_for() {
  local host="$1"
  case "$host" in
    vm-source) printf '%s\n' "$VM_SOURCE_TAP_IFACE" ;;
    vm-destination) printf '%s\n' "$VM_DESTINATION_TAP_IFACE" ;;
    vm-entrypoint) printf '%s\n' "$ENTRYPOINT_VM_TAP_IFACE" ;;
    *) return 1 ;;
  esac
}

vm_mac_address_for() {
  local host="$1"
  case "$host" in
    vm-source) printf '%s\n' "$VM_SOURCE_MAC_ADDRESS" ;;
    vm-destination) printf '%s\n' "$VM_DESTINATION_MAC_ADDRESS" ;;
    vm-entrypoint) printf '%s\n' "$ENTRYPOINT_VM_MAC_ADDRESS" ;;
    *) return 1 ;;
  esac
}

derive_report_diagnosis() {
  REPORT_DIAGNOSIS=""

  if [[ "$ENTRYPOINT_PREFLIGHT_VM_SOURCE" == "true" && "$ENTRYPOINT_PREFLIGHT_VM_DESTINATION" == "true" ]] \
    && [[ "$HOST_DIAGNOSTIC_VM_SOURCE" == *"unable to determine the validator's public IP address"* ]]; then
    REPORT_DIAGNOSIS="Control plane healthy; source validator is failing public-IP discovery. Current VM path is QEMU user-mode NAT to host to Docker Desktop to compose control plane (double NAT), so the entrypoint observes the Docker gateway rather than the validator VM's reachable address. Use VM_NETWORK_MODE=shared-bridge with a bridge-attached entrypoint VM or an external entrypoint on the same bridge, or keep using compose-only localnet for swap logic."
  elif [[ "$HOST_DIAGNOSTIC_VM_SOURCE" == *"unable to determine the validator's public IP address"* ]]; then
    REPORT_DIAGNOSIS="Source validator is failing public-IP discovery through the configured entrypoint path. Verify that the entrypoint can validate the validator VM's real routable address, not a NAT gateway address."
  elif [[ "$PRE_SWAP_VERIFIED" == "false" && "$HOST_SERVICE_VM_SOURCE" == *"/active/running"* ]]; then
    REPORT_DIAGNOSIS="Source validator service appears briefly active but failed runtime verification. Check Runtime Diagnostics for crash-loop evidence."
  fi
}

wait_for_ssh_or_qemu_exit() {
  local label="$1"
  local host="$2"
  local port="$3"
  local timeout="$4"
  local pid_file="$5"
  local qemu_log="$6"
  local start_ts now elapsed pid=""
  local qemu_log_tail=""

  start_ts="$(date +%s)"
  while true; do
    if ssh-keyscan -T 5 -p "$port" "$host" >/dev/null 2>&1; then
      return 0
    fi

    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -z "$pid" ]] || ! kill -0 "$pid" >/dev/null 2>&1; then
      qemu_log_tail="$(tail -n 120 "$qemu_log" 2>/dev/null || true)"
      EARLY_FAILURE_REASON="${label} QEMU process exited before SSH became reachable at ${host}:${port}."
      ENTRYPOINT_BOOTSTRAP_OUTPUT="${qemu_log_tail:-qemu log not captured}"
      echo "[vm-hot-swap] ${label} QEMU process exited before SSH became reachable at ${host}:${port}." >&2
      echo "[vm-hot-swap] Last ${label} QEMU log lines:" >&2
      if [[ -n "$qemu_log_tail" ]]; then
        printf '%s\n' "$qemu_log_tail" >&2
      fi
      exit 4
    fi

    now="$(date +%s)"
    elapsed=$((now - start_ts))
    if (( elapsed >= timeout )); then
      qemu_log_tail="$(tail -n 120 "$qemu_log" 2>/dev/null || true)"
      EARLY_FAILURE_REASON="Timeout waiting for ${label} SSH at ${host}:${port} (${timeout}s)"
      ENTRYPOINT_BOOTSTRAP_OUTPUT="${qemu_log_tail:-qemu log not captured}"
      echo "[vm-hot-swap] Timeout waiting for ${label} SSH at ${host}:${port} (${timeout}s)." >&2
      echo "[vm-hot-swap] Last ${label} QEMU log lines:" >&2
      if [[ -n "$qemu_log_tail" ]]; then
        printf '%s\n' "$qemu_log_tail" >&2
      fi
      exit 4
    fi
    sleep 1
  done
}

is_local_address() {
  local host="${1,,}"
  [[ "$host" == "127.0.0.1" || "$host" == "localhost" || "$host" == "0.0.0.0" ]]
}

listener_pids_for_port() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | sort -u || true
}

kill_stale_localnet_entrypoint_listener_pids() {
  local port="$1"
  local pid
  for pid in $(
    lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null \
      | awk 'NR > 1 && ($0 ~ /solana-test-validator/) { print $2 }' \
      | sort -u
  ); do
    if [[ -n "$pid" ]]; then
      echo "[vm-hot-swap] Stopping stale solana-test-validator listener on port ${port} (pid=${pid})" >&2
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
  done
}

remove_stale_harness_entrypoint_containers() {
  local name

  resolve_localnet_entrypoint_engine
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    case "$name" in
      hvk-vm-entrypoint-*|hvk-vmctl-*-gossip-entrypoint-vm-*|hvk-vmctl-*-ansible-control-vm-*)
        echo "[vm-hot-swap] Removing stale harness entrypoint container ${name}" >&2
        "$LOCALNET_ENTRYPOINT_ENGINE_RESOLVED" rm -f "$name" >/dev/null 2>&1 || true
        ;;
    esac
  done < <("$LOCALNET_ENTRYPOINT_ENGINE_RESOLVED" ps -a --format '{{.Names}}' 2>/dev/null || true)
}

container_using_host_port() {
  local port="$1"
  local line

  resolve_localnet_entrypoint_engine
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ (^|[[:space:],])0\.0\.0\.0:${port}\-\> ]] || [[ "$line" =~ (^|[[:space:],]):::${port}\-\> ]]; then
      printf '%s\n' "${line%%$'\t'*}"
      return 0
    fi
  done < <("$LOCALNET_ENTRYPOINT_ENGINE_RESOLVED" ps -a --format '{{.Names}}{{printf "\t"}}{{.Ports}}' 2>/dev/null || true)
  return 1
}

container_exists() {
  local name="$1"
  resolve_localnet_entrypoint_engine
  "$LOCALNET_ENTRYPOINT_ENGINE_RESOLVED" container inspect "$name" >/dev/null 2>&1
}

container_is_running() {
  local name="$1"
  local state=""
  resolve_localnet_entrypoint_engine
  state="$("$LOCALNET_ENTRYPOINT_ENGINE_RESOLVED" inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)"
  [[ "$state" == "true" ]]
}

assert_localnet_entrypoint_tcp_port_free() {
  local port="$1"
  local label="$2"
  local container_name=""

  container_name="$(container_using_host_port "$port" || true)"
  if [[ -n "$container_name" ]]; then
    if [[ "$container_name" =~ ^hvk-vm-entrypoint- ]] || [[ "$container_name" =~ ^hvk-vmctl-.*-(gossip-entrypoint-vm|ansible-control-vm)-[0-9]+$ ]]; then
      echo "[vm-hot-swap] Removing stale harness entrypoint container ${container_name} (publishing port ${port})" >&2
      "$LOCALNET_ENTRYPOINT_ENGINE_RESOLVED" rm -f "$container_name" >/dev/null 2>&1 || true
    else
      echo "${label} port ${port} is already published by container ${container_name}." >&2
      "$LOCALNET_ENTRYPOINT_ENGINE_RESOLVED" ps -a --filter "name=${container_name}" >&2 || true
      exit 3
    fi
  fi

  if ! is_tcp_port_listening "$port"; then
    return 0
  fi

  echo "${label} port ${port} is already in use by a non-harness process/container." >&2
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2 || true
  exit 3
}

stop_localnet_entrypoint_if_started() {
  if [[ "$LOCALNET_ENTRYPOINT_STARTED_BY_SCRIPT" != "true" ]]; then
    return 0
  fi
  if [[ -n "$LOCALNET_ENTRYPOINT_PID_FILE" && -f "$LOCALNET_ENTRYPOINT_PID_FILE" ]]; then
    local pid
    pid="$(cat "$LOCALNET_ENTRYPOINT_PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
  fi
}

is_ip_literal() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+(\.[0-9]+){3}$ || "$value" =~ : ]]
}

resolve_localnet_entrypoint_engine() {
  local requested="$VM_LOCALNET_ENTRYPOINT_ENGINE"
  if [[ -n "$LOCALNET_ENTRYPOINT_ENGINE_RESOLVED" ]]; then
    return 0
  fi

  case "$requested" in
    auto)
      if command -v docker >/dev/null 2>&1; then
        LOCALNET_ENTRYPOINT_ENGINE_RESOLVED="docker"
      elif command -v podman >/dev/null 2>&1; then
        LOCALNET_ENTRYPOINT_ENGINE_RESOLVED="podman"
      else
        echo "VM_LOCALNET_ENTRYPOINT_MODE requires docker or podman on PATH." >&2
        exit 3
      fi
      ;;
    docker|podman)
      require_cmd "$requested"
      LOCALNET_ENTRYPOINT_ENGINE_RESOLVED="$requested"
      ;;
    *)
      echo "Unsupported VM_LOCALNET_ENTRYPOINT_ENGINE: $requested (expected: auto|docker|podman)" >&2
      exit 2
      ;;
  esac
}

entrypoint_mode_uses_container() {
  [[ "$VM_LOCALNET_ENTRYPOINT_MODE" == "auto" || "$VM_LOCALNET_ENTRYPOINT_MODE" == "container" ]]
}

entrypoint_mode_uses_vm() {
  [[ "$VM_LOCALNET_ENTRYPOINT_MODE" == "vm" ]]
}

compute_container_entrypoint_dynamic_port_range() {
  local configured="$VM_LOCALNET_ENTRYPOINT_CONTAINER_DYNAMIC_PORT_RANGE"
  local base_range="${VM_LOCALNET_ENTRYPOINT_DYNAMIC_PORT_RANGE}"
  local start=""
  local end=""
  local width=30
  local derived_start
  local derived_end

  if [[ -n "$LOCALNET_ENTRYPOINT_CONTAINER_PORT_RANGE" ]]; then
    return 0
  fi

  if [[ -n "$configured" ]]; then
    LOCALNET_ENTRYPOINT_CONTAINER_PORT_RANGE="$configured"
    return 0
  fi

  if [[ "$base_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    start="${BASH_REMATCH[1]}"
    end="${BASH_REMATCH[2]}"
    if (( end >= start )); then
      width=$(( end - start ))
    fi
  fi

  # Keep the dynamic range distinct from explicitly published RPC/gossip/faucet
  # ports so the container runtime does not try to bind the same host port twice.
  derived_start=$(( VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT + 1 ))
  if (( derived_start < 1024 )); then
    derived_start=1024
  fi
  if (( derived_start == VM_LOCALNET_ENTRYPOINT_RPC_PORT )); then
    derived_start=$(( derived_start + 1 ))
  fi
  if (( derived_start == VM_LOCALNET_ENTRYPOINT_FAUCET_PORT )); then
    derived_start=$(( derived_start + 1 ))
  fi
  derived_end=$(( derived_start + width ))
  if (( VM_LOCALNET_ENTRYPOINT_RPC_PORT >= derived_start && VM_LOCALNET_ENTRYPOINT_RPC_PORT <= derived_end )); then
    derived_start=$(( VM_LOCALNET_ENTRYPOINT_RPC_PORT + 1 ))
    derived_end=$(( derived_start + width ))
  fi
  if (( VM_LOCALNET_ENTRYPOINT_FAUCET_PORT >= derived_start && VM_LOCALNET_ENTRYPOINT_FAUCET_PORT <= derived_end )); then
    derived_start=$(( VM_LOCALNET_ENTRYPOINT_FAUCET_PORT + 1 ))
    derived_end=$(( derived_start + width ))
  fi
  LOCALNET_ENTRYPOINT_CONTAINER_PORT_RANGE="${derived_start}-${derived_end}"
}

run_compose_vm_control_plane() {
  if [[ ! -x "$LOCALNET_ENTRYPOINT_COMPOSE_HELPER" ]]; then
    echo "VM control-plane helper is not executable: $LOCALNET_ENTRYPOINT_COMPOSE_HELPER" >&2
    exit 3
  fi

  VMH_ENGINE="$LOCALNET_ENTRYPOINT_ENGINE_RESOLVED" \
  VMH_PROJECT_NAME="$LOCALNET_ENTRYPOINT_COMPOSE_PROJECT" \
  VMH_SOLANA_RELEASE="$AGAVE_VERSION" \
  VMH_RPC_PORT="$VM_LOCALNET_ENTRYPOINT_RPC_PORT" \
  VMH_GOSSIP_PORT="$VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT" \
  VMH_FAUCET_PORT="$VM_LOCALNET_ENTRYPOINT_FAUCET_PORT" \
  VMH_DYNAMIC_PORT_RANGE="$LOCALNET_ENTRYPOINT_CONTAINER_PORT_RANGE" \
  VMH_GOSSIP_HOST="$VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS" \
  VMH_SLOTS_PER_EPOCH="$VM_LOCALNET_ENTRYPOINT_SLOTS_PER_EPOCH" \
  VMH_LIMIT_LEDGER_SIZE="$VM_LOCALNET_ENTRYPOINT_LIMIT_LEDGER_SIZE" \
  VMH_REBUILD="$VM_LOCALNET_ENTRYPOINT_CONTAINER_REBUILD" \
  "$LOCALNET_ENTRYPOINT_COMPOSE_HELPER" "$@"
}

capture_container_entrypoint_log() {
  if [[ "$LOCALNET_ENTRYPOINT_CONTAINER_STARTED_BY_SCRIPT" != "true" && -z "$LOCALNET_ENTRYPOINT_ENGINE_RESOLVED" ]]; then
    return 0
  fi
  if [[ -z "$LOCALNET_ENTRYPOINT_LOG" ]]; then
    return 0
  fi

  resolve_localnet_entrypoint_engine
  compute_container_entrypoint_dynamic_port_range
  if ! run_compose_vm_control_plane logs >"$LOCALNET_ENTRYPOINT_LOG" 2>&1; then
    : >"$LOCALNET_ENTRYPOINT_LOG"
  fi
  return 0
}

append_localnet_entrypoint_log_tail_to_bootstrap_output() {
  local log_tail=""
  if [[ -f "$LOCALNET_ENTRYPOINT_LOG" ]]; then
    log_tail="$(tail -n 120 "$LOCALNET_ENTRYPOINT_LOG" 2>/dev/null || true)"
    if [[ -n "$log_tail" ]]; then
      ENTRYPOINT_BOOTSTRAP_OUTPUT="${ENTRYPOINT_BOOTSTRAP_OUTPUT}

--- localnet-entrypoint.log (tail) ---
${log_tail}"
    fi
  fi
}

stop_container_localnet_entrypoint_if_started() {
  if [[ "$LOCALNET_ENTRYPOINT_CONTAINER_STARTED_BY_SCRIPT" != "true" ]]; then
    return 0
  fi
  resolve_localnet_entrypoint_engine
  compute_container_entrypoint_dynamic_port_range
  run_compose_vm_control_plane down >/dev/null 2>&1 || true
}

print_localnet_entrypoint_debug() {
  capture_entrypoint_vm_log || true
  capture_container_entrypoint_log || true
  echo "[vm-hot-swap] Expected localnet entrypoint endpoints for VMs:" >&2
  echo "[vm-hot-swap]   RPC: ${VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}" >&2
  echo "[vm-hot-swap]   Gossip TCP/IP echo: ${VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS}:${VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT}" >&2
  echo "[vm-hot-swap] Host-side RPC listener check:" >&2
  lsof -nP -iTCP:"$VM_LOCALNET_ENTRYPOINT_RPC_PORT" -sTCP:LISTEN >&2 || true
  echo "[vm-hot-swap] Host-side gossip listener check:" >&2
  lsof -nP -iTCP:"$VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT" -sTCP:LISTEN >&2 || true
  if entrypoint_mode_uses_container; then
    resolve_localnet_entrypoint_engine
    compute_container_entrypoint_dynamic_port_range
    echo "[vm-hot-swap] Entrypoint container engine: ${LOCALNET_ENTRYPOINT_ENGINE_RESOLVED}" >&2
    echo "[vm-hot-swap] Entrypoint compose project: ${LOCALNET_ENTRYPOINT_COMPOSE_PROJECT}" >&2
    echo "[vm-hot-swap] Entrypoint service ref: ${LOCALNET_ENTRYPOINT_CONTAINER_NAME}" >&2
    run_compose_vm_control_plane ps >&2 || true
  fi
  if entrypoint_mode_uses_vm; then
    echo "[vm-hot-swap] Entrypoint VM SSH: $(vm_bootstrap_host_for vm-entrypoint):$(vm_bootstrap_port_for vm-entrypoint)" >&2
    if [[ -n "${ENTRYPOINT_VM_QEMU_LOG:-}" && -f "${ENTRYPOINT_VM_QEMU_LOG:-}" ]]; then
      echo "[vm-hot-swap] Last entrypoint VM QEMU log lines:" >&2
      tail -n 80 "$ENTRYPOINT_VM_QEMU_LOG" >&2 || true
    fi
  fi
  if [[ -n "$LOCALNET_ENTRYPOINT_LOG" && -f "$LOCALNET_ENTRYPOINT_LOG" ]]; then
    echo "[vm-hot-swap] Last localnet entrypoint log lines:" >&2
    tail -n 80 "$LOCALNET_ENTRYPOINT_LOG" >&2 || true
  fi
}

capture_entrypoint_vm_log() {
  if ! entrypoint_mode_uses_vm; then
    return 0
  fi
  if [[ -z "${ENTRYPOINT_VM_BOOTSTRAP_INVENTORY:-}" || ! -f "${ENTRYPOINT_VM_BOOTSTRAP_INVENTORY:-}" ]]; then
    return 0
  fi
  if [[ -z "${LOCALNET_ENTRYPOINT_LOG:-}" ]]; then
    return 0
  fi

  ansible "vm-entrypoint" -i "$ENTRYPOINT_VM_BOOTSTRAP_INVENTORY" -u "$BOOTSTRAP_USER" -b \
    -m shell -a "test -f /var/tmp/localnet-entrypoint.log && tail -n 200 /var/tmp/localnet-entrypoint.log || true" -o 2>/dev/null \
    | awk -F' \\(stdout\\) ' 'NF > 1 { print $2 }' >"$LOCALNET_ENTRYPOINT_LOG" || true
}

ensure_container_localnet_entrypoint_service() {
  local rpc_url
  local up_output=""
  local tries=0

  resolve_localnet_entrypoint_engine
  LOCALNET_ENTRYPOINT_COMPOSE_PROJECT="${LOCALNET_ENTRYPOINT_COMPOSE_PROJECT:-hvk-vmctl-${RUN_ID}}"
  LOCALNET_ENTRYPOINT_CONTAINER_NAME="${LOCALNET_ENTRYPOINT_COMPOSE_PROJECT}/gossip-entrypoint-vm"
  compute_container_entrypoint_dynamic_port_range
  rpc_url="http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}"

  remove_stale_harness_entrypoint_containers
  kill_conflicting_qemu_listener "$VM_LOCALNET_ENTRYPOINT_RPC_PORT"
  kill_conflicting_qemu_listener "$VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT"
  kill_conflicting_qemu_listener "$VM_LOCALNET_ENTRYPOINT_FAUCET_PORT"
  kill_stale_localnet_entrypoint_listener_pids "$VM_LOCALNET_ENTRYPOINT_RPC_PORT"
  kill_stale_localnet_entrypoint_listener_pids "$VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT"
  kill_stale_localnet_entrypoint_listener_pids "$VM_LOCALNET_ENTRYPOINT_FAUCET_PORT"
  assert_localnet_entrypoint_tcp_port_free "$VM_LOCALNET_ENTRYPOINT_RPC_PORT" "Localnet entrypoint RPC"
  assert_localnet_entrypoint_tcp_port_free "$VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT" "Localnet entrypoint gossip"
  assert_localnet_entrypoint_tcp_port_free "$VM_LOCALNET_ENTRYPOINT_FAUCET_PORT" "Localnet entrypoint faucet"
  echo "[vm-hot-swap] Starting compose-managed VM control plane (${LOCALNET_ENTRYPOINT_COMPOSE_PROJECT})..." >&2
  up_output="$(run_compose_vm_control_plane up 2>&1)" || {
    if grep -q "did not expose a healthy RPC endpoint" <<<"$up_output"; then
      EARLY_FAILURE_REASON="Compose-managed localnet entrypoint did not expose a healthy RPC endpoint"
    elif grep -q "did not reach finalized slot" <<<"$up_output"; then
      EARLY_FAILURE_REASON="Compose-managed localnet entrypoint did not finalize enough slots"
    elif grep -q "ansible-control-vm did not become ready" <<<"$up_output"; then
      EARLY_FAILURE_REASON="ansible-control-vm did not become ready"
    else
      EARLY_FAILURE_REASON="Failed to start compose-managed VM control plane"
    fi
    ENTRYPOINT_BOOTSTRAP_OUTPUT="$(printf '%s\n' "$up_output" | tail -n 120)"
    capture_container_entrypoint_log || true
    append_localnet_entrypoint_log_tail_to_bootstrap_output
    echo "$EARLY_FAILURE_REASON" >&2
    echo "$ENTRYPOINT_BOOTSTRAP_OUTPUT" >&2
    exit 1
  }
  LOCALNET_ENTRYPOINT_CONTAINER_STARTED_BY_SCRIPT=true
  LOCALNET_ENTRYPOINT_CONTAINER_LEDGER_DIR="compose:${LOCALNET_ENTRYPOINT_COMPOSE_PROJECT}/gossip-entrypoint-vm:/var/tmp/test-ledger"

  until solana -u "$rpc_url" genesis-hash >/dev/null 2>&1; do
    tries=$((tries + 1))
    if ((tries > 30)); then
      EARLY_FAILURE_REASON="Compose-managed localnet entrypoint did not become queryable at ${rpc_url}"
      ENTRYPOINT_BOOTSTRAP_OUTPUT="$(printf '%s\n' "$up_output" | tail -n 120)"
      capture_container_entrypoint_log || true
      append_localnet_entrypoint_log_tail_to_bootstrap_output
      echo "$EARLY_FAILURE_REASON" >&2
      print_localnet_entrypoint_debug
      exit 4
    fi
    sleep 1
  done

  capture_container_entrypoint_log || true
}

ensure_entrypoint_vm_localnet_service() {
  local extra_host_fwds
  local rpc_url
  local tries=0
  local install_output=""
  local install_log_file=""
  local copy_output=""
  local start_output=""
  local start_cmd=""
  local entrypoint_bootstrap_host
  local entrypoint_bootstrap_port
  local entrypoint_operator_port
  local cli_probe_cmd
  local skip_cli_install=false
  local entrypoint_pid=""
  local install_attempt=0
  local install_max_attempts=3
  local install_ok=false

  rpc_url="http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}"
  entrypoint_bootstrap_host="$(vm_bootstrap_host_for vm-entrypoint)"
  entrypoint_bootstrap_port="$(vm_bootstrap_port_for vm-entrypoint)"
  entrypoint_operator_port="$(vm_operator_port_for vm-entrypoint)"

  if [[ -f "$ENTRYPOINT_VM_PID_FILE" ]]; then
    entrypoint_pid="$(cat "$ENTRYPOINT_VM_PID_FILE" 2>/dev/null || true)"
  fi

  if [[ -n "$entrypoint_pid" ]] && kill -0 "$entrypoint_pid" >/dev/null 2>&1; then
    if localnet_rpc_ready "$rpc_url"; then
      capture_entrypoint_vm_log
      return 0
    fi

    if ! "$REPO_ROOT/scripts/vm-test/wait-for-ssh.sh" "$entrypoint_bootstrap_host" "$entrypoint_bootstrap_port" 20 >/dev/null 2>&1; then
      echo "[vm-hot-swap] Existing entrypoint VM process ${entrypoint_pid} is unhealthy (SSH unreachable); restarting it." >&2
      kill "$entrypoint_pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$entrypoint_pid" >/dev/null 2>&1; then
        kill -9 "$entrypoint_pid" >/dev/null 2>&1 || true
      fi
      rm -f "$ENTRYPOINT_VM_PID_FILE"
      entrypoint_pid=""
    fi
  fi

  if vm_uses_shared_bridge; then
    extra_host_fwds=""
  else
    extra_host_fwds="hostfwd=tcp::${VM_LOCALNET_ENTRYPOINT_RPC_PORT}-:${ENTRYPOINT_VM_GUEST_RPC_PORT},hostfwd=tcp::${VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT}-:${ENTRYPOINT_VM_GUEST_GOSSIP_PORT},hostfwd=udp::${VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT}-:${ENTRYPOINT_VM_GUEST_GOSSIP_PORT},hostfwd=tcp::${VM_LOCALNET_ENTRYPOINT_FAUCET_PORT}-:${ENTRYPOINT_VM_GUEST_FAUCET_PORT}"
  fi

  if [[ -z "$entrypoint_pid" ]] || ! kill -0 "$entrypoint_pid" >/dev/null 2>&1; then
    echo "[vm-hot-swap] Starting isolated entrypoint VM..." >&2
    start_vm "vm-entrypoint" "$ENTRYPOINT_VM_NAME" "$ENTRYPOINT_VM_DIR" "$entrypoint_bootstrap_host" "$entrypoint_bootstrap_port" "$entrypoint_operator_port" "$ENTRYPOINT_VM_QEMU_LOG" "$ENTRYPOINT_VM_PID_FILE" "$(vm_tap_iface_for vm-entrypoint)" "$extra_host_fwds" "$ENTRYPOINT_VM_BASE_IMAGE" "$VM_ENTRYPOINT_DISK_PARENT_PREFIX"
  fi

  cli_probe_cmd="set -eu; for candidate in /opt/solana/active_release/bin/solana-test-validator /home/${BOOTSTRAP_USER}/.local/share/solana/install/active_release/bin/solana-test-validator; do if [ -x \"\$candidate\" ] && [ -s \"\$candidate\" ] && \"\$candidate\" --version >/dev/null 2>&1; then exit 0; fi; done; exit 1"
  case "$ENTRYPOINT_VM_SKIP_CLI_INSTALL" in
    true)
      skip_cli_install=true
      ;;
    false)
      skip_cli_install=false
      ;;
    auto)
      if ansible "vm-entrypoint" -i "$ENTRYPOINT_VM_BOOTSTRAP_INVENTORY" -u "$BOOTSTRAP_USER" -b \
        -m shell -a "$cli_probe_cmd" -o >/dev/null 2>&1; then
        skip_cli_install=true
      fi
      ;;
    *)
      echo "Unsupported ENTRYPOINT_VM_SKIP_CLI_INSTALL: $ENTRYPOINT_VM_SKIP_CLI_INSTALL (expected: auto|true|false)" >&2
      exit 2
      ;;
  esac

  if [[ "$skip_cli_install" != "true" ]]; then
    echo "[vm-hot-swap] Ensuring Agave CLI is available inside the isolated entrypoint VM..." >&2
    install_log_file="$ARTIFACTS_DIR/entrypoint-cli-install.log"
    : >"$install_log_file"
    echo "[vm-hot-swap] Entrypoint CLI install log: $install_log_file" >&2
    while (( install_attempt < install_max_attempts )); do
      install_attempt=$((install_attempt + 1))
      echo "[vm-hot-swap] Entrypoint CLI install attempt ${install_attempt}/${install_max_attempts}..." >&2
      if ansible-playbook \
        -i "$ENTRYPOINT_VM_BOOTSTRAP_INVENTORY" \
        "$REPO_ROOT/ansible/playbooks/pb_install_solana_cli_agave.yml" \
        -e "@$REPO_ROOT/ansible/group_vars/all.yml" \
        -e "@$REPO_ROOT/ansible/group_vars/solana.yml" \
        -e "@$REPO_ROOT/ansible/group_vars/solana_localnet.yml" \
        -e "solana_cluster=localnet" \
        -e "solana_rpc_url=http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}" \
        -e "target_host=vm-entrypoint" \
        -e "operator_user=$BOOTSTRAP_USER" \
        -e "agave_version=$AGAVE_VERSION" \
        -e "build_from_source=$BUILD_FROM_SOURCE" 2>&1 | tee -a "$install_log_file"; then
        install_ok=true
        break
      fi

      install_output="$(tail -n 120 "$install_log_file" 2>/dev/null || true)"
      if grep -Eiq "Failed to connect to the host via ssh: ssh: connect to host .* port .*: Connection refused|Connection timed out|No route to host" <<<"$install_output"; then
        echo "[vm-hot-swap] Entrypoint CLI install hit transient SSH failure; waiting for SSH and retrying..." >&2
        "$REPO_ROOT/scripts/vm-test/wait-for-ssh.sh" "$entrypoint_bootstrap_host" "$entrypoint_bootstrap_port" 60 >/dev/null 2>&1 || true
        continue
      fi
      break
    done

    if [[ "$install_ok" != "true" ]]; then
      EARLY_FAILURE_REASON="Failed to install Agave CLI in isolated entrypoint VM"
      install_output="$(tail -n 80 "$install_log_file" 2>/dev/null || true)"
      ENTRYPOINT_BOOTSTRAP_OUTPUT="${install_output:-not captured}"
      echo "$EARLY_FAILURE_REASON" >&2
      echo "$ENTRYPOINT_BOOTSTRAP_OUTPUT" >&2
      exit 1
    fi
  else
    echo "[vm-hot-swap] Reusing preinstalled Solana CLI in the isolated entrypoint VM." >&2
  fi

  copy_output="$(
    ansible "vm-entrypoint" -i "$ENTRYPOINT_VM_BOOTSTRAP_INVENTORY" -u "$BOOTSTRAP_USER" -b \
      -m copy -a "src=$REPO_ROOT/solana-localnet/container-setup/scripts/localnet-gossip-entrypoint-setup.sh dest=/usr/local/bin/hvk-localnet-gossip-entrypoint-setup.sh mode=0755" -o 2>&1
  )" || {
    EARLY_FAILURE_REASON="Failed to stage the localnet entrypoint launcher in isolated entrypoint VM"
    ENTRYPOINT_BOOTSTRAP_OUTPUT="$(printf '%s\n' "$copy_output" | tail -n 80)"
    echo "$EARLY_FAILURE_REASON" >&2
    echo "$ENTRYPOINT_BOOTSTRAP_OUTPUT" >&2
    exit 1
  }

  if [[ "$VM_ENTRYPOINT_PREPARE_ONLY" == "true" ]]; then
    echo "[vm-hot-swap] Prepared shared entrypoint VM cache (CLI + launcher only); skipping localnet runtime start." >&2
    return 0
  fi

  echo "[vm-hot-swap] Starting localnet entrypoint inside the isolated entrypoint VM..." >&2
  start_cmd="$(cat <<EOF
set -eu
pkill -x solana-test-validator >/dev/null 2>&1 || true
export PATH='/opt/solana/active_release/bin:/home/${BOOTSTRAP_USER}/.local/share/solana/install/active_release/bin:'"\$PATH"
export SLOTS_PER_EPOCH='${VM_LOCALNET_ENTRYPOINT_SLOTS_PER_EPOCH}'
export LIMIT_LEDGER_SIZE='${VM_LOCALNET_ENTRYPOINT_LIMIT_LEDGER_SIZE}'
export DYNAMIC_PORT_RANGE='${VM_LOCALNET_ENTRYPOINT_DYNAMIC_PORT_RANGE}'
export RPC_PORT='${ENTRYPOINT_VM_GUEST_RPC_PORT}'
export FAUCET_PORT='${ENTRYPOINT_VM_GUEST_FAUCET_PORT}'
export BIND_ADDRESS='0.0.0.0'
export GOSSIP_HOST='${VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS}'
export GOSSIP_PORT='${ENTRYPOINT_VM_GUEST_GOSSIP_PORT}'
export LEDGER_DIR='/var/tmp/test-ledger'
export RESET_FLAG='--reset'
for candidate in \
  /opt/solana/active_release/bin/solana-test-validator \
  /home/${BOOTSTRAP_USER}/.local/share/solana/install/active_release/bin/solana-test-validator; do
  if [ -x "\$candidate" ] && [ -s "\$candidate" ] && "\$candidate" --version >/dev/null 2>&1; then
    export TEST_VALIDATOR_BIN="\$candidate"
    break
  fi
done
if [ -z "\${TEST_VALIDATOR_BIN:-}" ]; then
  echo "No working solana-test-validator binary found in expected install paths." >&2
  exit 1
fi
rm -f /var/tmp/localnet-entrypoint.log
nohup /usr/local/bin/hvk-localnet-gossip-entrypoint-setup.sh >/var/tmp/localnet-entrypoint.log 2>&1 </dev/null &
EOF
)"
  start_output="$(
    ansible "vm-entrypoint" -i "$ENTRYPOINT_VM_BOOTSTRAP_INVENTORY" -u "$BOOTSTRAP_USER" -b \
      -m shell -a "$start_cmd" -o 2>&1
  )" || {
    EARLY_FAILURE_REASON="Failed to start localnet entrypoint inside isolated entrypoint VM"
    ENTRYPOINT_BOOTSTRAP_OUTPUT="$(printf '%s\n' "$start_output" | tail -n 80)"
    echo "$EARLY_FAILURE_REASON" >&2
    echo "$ENTRYPOINT_BOOTSTRAP_OUTPUT" >&2
    exit 1
  }

  until solana -u "$rpc_url" genesis-hash >/dev/null 2>&1; do
    tries=$((tries + 1))
    if ((tries > 120)); then
      capture_entrypoint_vm_log
      EARLY_FAILURE_REASON="Isolated localnet entrypoint VM did not become ready at ${rpc_url}"
      ENTRYPOINT_BOOTSTRAP_OUTPUT="$(printf '%s\n' "$start_output" | tail -n 80)"
      echo "Isolated localnet entrypoint VM did not become ready at ${rpc_url}." >&2
      print_localnet_entrypoint_debug
      exit 4
    fi
    sleep 1
  done

  capture_entrypoint_vm_log
}

ensure_localnet_demo_validator_accounts() {
  local rpc_url
  local keys_dir
  local primary_key
  local vote_key
  local withdrawer_key
  local stake_key
  local vote_pubkey
  local stake_pubkey=""
  local payer_key="$HOME/.config/solana/id.json"

  if [[ "$SOLANA_CLUSTER_NORMALIZED" != "localnet" ]]; then
    return 0
  fi
  if ! entrypoint_mode_uses_vm; then
    return 0
  fi

  rpc_url="http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}"
  keys_dir="$VALIDATOR_KEYSET_SOURCE_DIR"
  primary_key="$keys_dir/primary-target-identity.json"
  vote_key="$keys_dir/vote-account.json"
  withdrawer_key="$keys_dir/authorized-withdrawer.json"
  stake_key="$keys_dir/stake-account.json"

  require_cmd solana
  require_cmd solana-keygen

  [[ -f "$primary_key" ]] || { echo "Missing validator primary identity key: $primary_key" >&2; exit 1; }
  [[ -f "$vote_key" ]] || { echo "Missing validator vote account key: $vote_key" >&2; exit 1; }
  [[ -f "$withdrawer_key" ]] || { echo "Missing validator withdrawer key: $withdrawer_key" >&2; exit 1; }

  vote_pubkey="$(solana-keygen pubkey "$vote_key")"
  if solana -u "$rpc_url" account "$vote_pubkey" >/dev/null 2>&1; then
    return 0
  fi

  echo "[vm-hot-swap] Initializing localnet demo validator accounts for ${VALIDATOR_NAME}..." >&2

  mkdir -p "$(dirname "$payer_key")"
  if [[ ! -f "$payer_key" ]]; then
    solana-keygen new -s --no-bip39-passphrase -o "$payer_key" >/dev/null
  fi

  solana -u "$rpc_url" airdrop 500000 >/dev/null
  solana -u "$rpc_url" --keypair "$primary_key" airdrop 42 >/dev/null || true
  solana -u "$rpc_url" create-vote-account "$vote_key" "$primary_key" "$withdrawer_key" >/dev/null

  if [[ -f "$stake_key" ]]; then
    stake_pubkey="$(solana-keygen pubkey "$stake_key")"
    if ! solana -u "$rpc_url" account "$stake_pubkey" >/dev/null 2>&1; then
      solana -u "$rpc_url" create-stake-account "$stake_key" 200000 >/dev/null
    fi
    solana -u "$rpc_url" delegate-stake "$stake_key" "$vote_key" --force >/dev/null || true
  fi

  for _ in $(seq 1 30); do
    if solana -u "$rpc_url" account "$vote_pubkey" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "Localnet vote account ${vote_pubkey} was not visible on ${rpc_url} after initialization." >&2
  exit 1
}

ensure_localnet_entrypoint() {
  if [[ "$SOLANA_CLUSTER_NORMALIZED" != "localnet" ]]; then
    return 0
  fi

  require_cmd solana

  if entrypoint_mode_uses_container; then
    ensure_container_localnet_entrypoint_service
    LOCALNET_ENTRYPOINT_GENESIS_HASH="$(solana -u "http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}" genesis-hash)"
    COMMON_ANSIBLE_EXTRA_VARS_ARGS+=(-e "expected_genesis_hash=$LOCALNET_ENTRYPOINT_GENESIS_HASH")
    return 0
  fi

  if entrypoint_mode_uses_vm; then
    ensure_entrypoint_vm_localnet_service
    ensure_localnet_demo_validator_accounts
    LOCALNET_ENTRYPOINT_GENESIS_HASH="$(solana -u "http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}" genesis-hash)"
    COMMON_ANSIBLE_EXTRA_VARS_ARGS+=(-e "expected_genesis_hash=$LOCALNET_ENTRYPOINT_GENESIS_HASH")
    return 0
  fi

  local rpc_port="$VM_LOCALNET_ENTRYPOINT_RPC_PORT"
  local rpc_url="http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}"
  local gossip_port="$VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT"
  local process_gossip_host="$VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_PROCESS"
  local rpc_listening=false
  local rpc_ready=false
  local gossip_listening=false

  if is_tcp_port_listening "$rpc_port"; then
    rpc_listening=true
  fi
  if is_local_address "$process_gossip_host" && is_tcp_port_listening "$gossip_port"; then
    gossip_listening=true
  fi
  if [[ "$rpc_listening" == "true" ]] && localnet_rpc_ready "$rpc_url"; then
    rpc_ready=true
  fi

  if [[ "$rpc_ready" == "true" ]] && { [[ "$gossip_listening" == "true" ]] || ! is_local_address "$process_gossip_host"; }; then
    echo "[vm-hot-swap] Reusing healthy localnet entrypoint at ${rpc_url}" >&2
  else
    if [[ "$VM_LOCALNET_ENTRYPOINT_MODE" == "external" ]]; then
      echo "Localnet entrypoint is unhealthy at ${rpc_url} (rpc_ready=${rpc_ready}, gossip_listening=${gossip_listening}) and VM_LOCALNET_ENTRYPOINT_MODE=external." >&2
      echo "Start a healthy external entrypoint first, or set VM_LOCALNET_ENTRYPOINT_MODE=auto." >&2
      exit 3
    fi

    kill_stale_localnet_entrypoint_listener_pids "$rpc_port"
    kill_stale_localnet_entrypoint_listener_pids "$gossip_port"

    if is_tcp_port_listening "$rpc_port"; then
      echo "RPC port ${rpc_port} is already in use by a non-solana-test-validator process." >&2
      echo "Choose another VM_LOCALNET_ENTRYPOINT_RPC_PORT or stop the conflicting process." >&2
      exit 3
    fi
    if is_tcp_port_listening "$gossip_port"; then
      echo "Gossip port ${gossip_port} is already in use by a non-solana-test-validator process." >&2
      echo "Choose another VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT or stop the conflicting process." >&2
      exit 3
    fi

    require_cmd solana-test-validator
    echo "[vm-hot-swap] Starting localnet entrypoint via solana-test-validator at ${rpc_url} ..." >&2
    nohup solana-test-validator \
      --slots-per-epoch "$VM_LOCALNET_ENTRYPOINT_SLOTS_PER_EPOCH" \
      --limit-ledger-size "$VM_LOCALNET_ENTRYPOINT_LIMIT_LEDGER_SIZE" \
      --dynamic-port-range "$VM_LOCALNET_ENTRYPOINT_DYNAMIC_PORT_RANGE" \
      --rpc-port "$VM_LOCALNET_ENTRYPOINT_RPC_PORT" \
      --faucet-port "$VM_LOCALNET_ENTRYPOINT_FAUCET_PORT" \
      --bind-address 0.0.0.0 \
      --gossip-host "$VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_PROCESS" \
      --gossip-port "$VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT" \
      --reset >"$LOCALNET_ENTRYPOINT_LOG" 2>&1 &
    echo $! >"$LOCALNET_ENTRYPOINT_PID_FILE"
    LOCALNET_ENTRYPOINT_STARTED_BY_SCRIPT=true
  fi

  local tries=0
  until solana -u "$rpc_url" genesis-hash >/dev/null 2>&1; do
    if [[ "$LOCALNET_ENTRYPOINT_STARTED_BY_SCRIPT" == "true" && -f "$LOCALNET_ENTRYPOINT_PID_FILE" ]]; then
      local started_pid
      started_pid="$(cat "$LOCALNET_ENTRYPOINT_PID_FILE" 2>/dev/null || true)"
      if [[ -n "$started_pid" ]] && ! kill -0 "$started_pid" >/dev/null 2>&1; then
        echo "Localnet entrypoint process exited before becoming ready (pid=${started_pid})." >&2
        if [[ -n "$LOCALNET_ENTRYPOINT_LOG" && -f "$LOCALNET_ENTRYPOINT_LOG" ]]; then
          echo "[vm-hot-swap] Last entrypoint log lines:" >&2
          tail -n 120 "$LOCALNET_ENTRYPOINT_LOG" >&2 || true
        fi
        exit 4
      fi
    fi
    tries=$((tries + 1))
    if ((tries > 120)); then
      echo "Localnet entrypoint at ${rpc_url} did not become ready in time." >&2
      if [[ -n "$LOCALNET_ENTRYPOINT_LOG" && -f "$LOCALNET_ENTRYPOINT_LOG" ]]; then
        echo "[vm-hot-swap] Last entrypoint log lines:" >&2
        tail -n 80 "$LOCALNET_ENTRYPOINT_LOG" >&2 || true
      fi
      exit 4
    fi
    sleep 1
  done

  LOCALNET_ENTRYPOINT_GENESIS_HASH="$(solana -u "$rpc_url" genesis-hash)"
  COMMON_ANSIBLE_EXTRA_VARS_ARGS+=(-e "expected_genesis_hash=$LOCALNET_ENTRYPOINT_GENESIS_HASH")
}

assert_vm_can_reach_localnet_entrypoint() {
  local host="$1"
  local label="$2"
  local vm_entrypoint_host="$VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS"
  local rpc_port="$VM_LOCALNET_ENTRYPOINT_RPC_PORT"
  local gossip_port="$VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT"
  local wait_timeout="${3:-$VM_ENTRYPOINT_PREFLIGHT_TIMEOUT_SEC}"
  local max_attempts="$VM_ENTRYPOINT_PREFLIGHT_RETRIES"
  local retry_sleep="$VM_ENTRYPOINT_PREFLIGHT_RETRY_SLEEP_SEC"
  local resolve_cmd
  local rpc_check_output=""
  local gossip_check_output=""
  local attempt=0
  local rc=0

  if [[ "$SOLANA_CLUSTER_NORMALIZED" != "localnet" ]]; then
    return 0
  fi

  if [[ ! -f "$OPERATOR_INVENTORY" ]]; then
    echo "[vm-hot-swap] Cannot verify ${label} entrypoint reachability before operator inventory exists." >&2
    exit 2
  fi

  if ! command -v ansible >/dev/null 2>&1; then
    echo "[vm-hot-swap] ansible is required to verify VM reachability to the localnet entrypoint." >&2
    exit 2
  fi

  if ! command -v lsof >/dev/null 2>&1; then
    echo "[vm-hot-swap] lsof is required to debug localnet entrypoint listener failures." >&2
    exit 2
  fi

  if ! is_ip_literal "$vm_entrypoint_host"; then
    resolve_cmd="set -eu; getent ahostsv4 \"$vm_entrypoint_host\" >/dev/null 2>&1 || getent hosts \"$vm_entrypoint_host\" >/dev/null 2>&1"
    if ! ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -e "ansible_become=false" \
      -m shell -a "$resolve_cmd" -o >/dev/null; then
      echo "[vm-hot-swap] ${label} VM cannot resolve entrypoint host ${vm_entrypoint_host}." >&2
      print_localnet_entrypoint_debug
      exit 1
    fi
  fi

  if ! [[ "$wait_timeout" =~ ^[0-9]+$ ]] || (( wait_timeout < 1 )); then
    wait_timeout=60
  fi
  if ! [[ "$max_attempts" =~ ^[0-9]+$ ]] || (( max_attempts < 1 )); then
    max_attempts=1
  fi
  if ! [[ "$retry_sleep" =~ ^[0-9]+$ ]] || (( retry_sleep < 0 )); then
    retry_sleep=3
  fi

  rc=0
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    rc=0
    rpc_check_output="$(
      ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" \
        -e "ansible_become=false" \
        -m wait_for -a "host=${vm_entrypoint_host} port=${rpc_port} timeout=${wait_timeout} connect_timeout=5 state=started" -o 2>&1
    )" || rc=$?
    if (( rc == 0 )); then
      break
    fi
    if (( attempt < max_attempts )); then
      echo "[vm-hot-swap] ${label} VM RPC reachability attempt ${attempt}/${max_attempts} failed for ${vm_entrypoint_host}:${rpc_port}; retrying in ${retry_sleep}s." >&2
      sleep "$retry_sleep"
    fi
  done
  if (( rc != 0 )); then
    echo "[vm-hot-swap] ${label} VM cannot reach localnet entrypoint RPC at ${vm_entrypoint_host}:${rpc_port}." >&2
    if [[ -n "$rpc_check_output" ]]; then
      echo "[vm-hot-swap] Ansible wait_for output (RPC):" >&2
      printf '%s\n' "$rpc_check_output" | tail -n 80 >&2 || true
    fi
    print_localnet_entrypoint_debug
    exit 1
  fi

  rc=0
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    rc=0
    gossip_check_output="$(
      ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" \
        -e "ansible_become=false" \
        -m wait_for -a "host=${vm_entrypoint_host} port=${gossip_port} timeout=${wait_timeout} connect_timeout=5 state=started" -o 2>&1
    )" || rc=$?
    if (( rc == 0 )); then
      break
    fi
    if (( attempt < max_attempts )); then
      echo "[vm-hot-swap] ${label} VM gossip reachability attempt ${attempt}/${max_attempts} failed for ${vm_entrypoint_host}:${gossip_port}; retrying in ${retry_sleep}s." >&2
      sleep "$retry_sleep"
    fi
  done
  if (( rc != 0 )); then
    echo "[vm-hot-swap] ${label} VM cannot reach localnet entrypoint gossip TCP/IP-echo at ${vm_entrypoint_host}:${gossip_port}." >&2
    if [[ -n "$gossip_check_output" ]]; then
      echo "[vm-hot-swap] Ansible wait_for output (gossip):" >&2
      printf '%s\n' "$gossip_check_output" | tail -n 80 >&2 || true
    fi
    print_localnet_entrypoint_debug
    exit 1
  fi

  case "$host" in
    vm-source)
      ENTRYPOINT_PREFLIGHT_VM_SOURCE=true
      ENTRYPOINT_PREFLIGHT_DETAILS_VM_SOURCE="${vm_entrypoint_host}:${rpc_port},${vm_entrypoint_host}:${gossip_port}"
      ;;
    vm-destination)
      ENTRYPOINT_PREFLIGHT_VM_DESTINATION=true
      ENTRYPOINT_PREFLIGHT_DETAILS_VM_DESTINATION="${vm_entrypoint_host}:${rpc_port},${vm_entrypoint_host}:${gossip_port}"
      ;;
    *)
      echo "[vm-hot-swap] Unsupported host for entrypoint preflight: ${host}" >&2
      exit 2
      ;;
  esac
}

assert_host_can_query_localnet_entrypoint() {
  local host="$1"
  local label="$2"
  local rpc_url
  local cmd
  local output
  local rc=0

  if [[ "$SOLANA_CLUSTER_NORMALIZED" != "localnet" ]]; then
    return 0
  fi

  rpc_url="http://${VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}"
  cmd="set -eu; actual=\$(/opt/solana/active_release/bin/solana -u \"$rpc_url\" genesis-hash); [ \"\$actual\" = \"$LOCALNET_ENTRYPOINT_GENESIS_HASH\" ]"
  output="$(
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "$cmd" -o 2>&1
  )" || rc=$?

  if ((rc != 0)); then
    echo "[vm-hot-swap] ${label} host cannot query the localnet entrypoint via Solana CLI at ${rpc_url}." >&2
    echo "$output" >&2
    print_localnet_entrypoint_debug
    exit 1
  fi
}

sync_host_expected_genesis_hash() {
  local host="$1"
  local update_cmd
  local output
  local rc=0

  if [[ "$SOLANA_CLUSTER_NORMALIZED" != "localnet" ]]; then
    return 0
  fi
  if [[ -z "${LOCALNET_ENTRYPOINT_GENESIS_HASH:-}" ]]; then
    echo "[vm-hot-swap] Localnet genesis hash not captured yet; cannot align host ${host}." >&2
    exit 1
  fi

  update_cmd="set -eu; script='/opt/validator/scripts/run-${VALIDATOR_NAME}.sh'; if [ ! -f \"\$script\" ]; then echo \"missing startup script: \$script\" >&2; exit 1; fi; if grep -q -- '--expected-genesis-hash ${LOCALNET_ENTRYPOINT_GENESIS_HASH}' \"\$script\"; then echo 'already-aligned'; exit 0; fi; sed -i -E \"s#(--expected-genesis-hash[[:space:]]+)[^[:space:]\\\\]+#\\1${LOCALNET_ENTRYPOINT_GENESIS_HASH}#g\" \"\$script\"; grep -q -- '--expected-genesis-hash ${LOCALNET_ENTRYPOINT_GENESIS_HASH}' \"\$script\"; systemctl daemon-reload; systemctl restart sol; echo 'updated-and-restarted'"
  output="$(
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "$update_cmd" -o 2>&1
  )" || rc=$?

  if (( rc != 0 )); then
    echo "[vm-hot-swap] Failed to align expected genesis hash on ${host}." >&2
    echo "$output" >&2
    exit 1
  fi
}

shorten_vm_name() {
  local raw_name="$1"
  local max_len="${2:-63}"
  local suffix=""
  local prefix_len=0

  if (( ${#raw_name} <= max_len )); then
    printf '%s' "$raw_name"
    return 0
  fi

  suffix="$(
    printf '%s' "$raw_name" | sha256sum | awk '{print substr($1, 1, 8)}'
  )"
  prefix_len=$(( max_len - ${#suffix} - 1 ))
  if (( prefix_len < 1 )); then
    prefix_len=1
  fi

  printf '%s-%s' "${raw_name:0:prefix_len}" "$suffix"
}

CASE_DIR="$WORKDIR/$RUN_ID"
SRC_VM_NAME="$(shorten_vm_name "hvk-src-${RUN_ID}")"
DST_VM_NAME="$(shorten_vm_name "hvk-dst-${RUN_ID}")"
ENTRYPOINT_VM_NAME="$(shorten_vm_name "hvk-entry-${RUN_ID}")"
SRC_VM_DIR="$CASE_DIR/source"
DST_VM_DIR="$CASE_DIR/destination"
ENTRYPOINT_VM_DIR="$CASE_DIR/entrypoint"
ARTIFACTS_DIR="$CASE_DIR/artifacts"
mkdir -p "$SRC_VM_DIR" "$DST_VM_DIR" "$ENTRYPOINT_VM_DIR" "$ARTIFACTS_DIR"

SRC_QEMU_LOG="$ARTIFACTS_DIR/source-qemu.log"
DST_QEMU_LOG="$ARTIFACTS_DIR/destination-qemu.log"
ENTRYPOINT_VM_QEMU_LOG="$ARTIFACTS_DIR/entrypoint-qemu.log"
SRC_PID_FILE="$CASE_DIR/source-qemu.pid"
DST_PID_FILE="$CASE_DIR/destination-qemu.pid"
ENTRYPOINT_VM_PID_FILE="$CASE_DIR/entrypoint-qemu.pid"
ENTRYPOINT_VM_BOOTSTRAP_INVENTORY="$CASE_DIR/inventory.entrypoint.bootstrap.yml"
LOCALNET_ENTRYPOINT_PID_FILE="$CASE_DIR/localnet-entrypoint.pid"
LOCALNET_ENTRYPOINT_LOG="$ARTIFACTS_DIR/localnet-entrypoint.log"

if [[ "$SHARED_ENTRYPOINT_VM" == "true" ]]; then
  SHARED_ENTRYPOINT_ROOT="$WORKDIR/_shared-entrypoint-vm"
  ENTRYPOINT_VM_NAME="hvk-entry-shared-${VM_ARCH}"
  ENTRYPOINT_VM_DIR="$SHARED_ENTRYPOINT_ROOT/vm"
  ENTRYPOINT_VM_QEMU_LOG="$SHARED_ENTRYPOINT_ROOT/entrypoint-qemu.log"
  ENTRYPOINT_VM_PID_FILE="$SHARED_ENTRYPOINT_ROOT/entrypoint-qemu.pid"
  ENTRYPOINT_VM_BOOTSTRAP_INVENTORY="$SHARED_ENTRYPOINT_ROOT/inventory.entrypoint.bootstrap.yml"
  mkdir -p "$ENTRYPOINT_VM_DIR"
fi

emit_test_report() {
  local result="${1:-}"
  local report_file="$ARTIFACTS_DIR/test-report.txt"
  local json_report_file="$ARTIFACTS_DIR/test-report.json"

  if declare -f capture_runtime_diagnostics_if_possible >/dev/null 2>&1; then
    capture_runtime_diagnostics_if_possible
  fi

  if [[ -z "$result" ]]; then
    if [[ "$EXEC_OK" == "true" ]]; then
      result="PASS"
    else
      result="FAIL"
    fi
  fi
  TOTAL_DURATION_SEC=$(( $(date +%s) - SCRIPT_START_TS ))
  derive_report_diagnosis

  cat >"$report_file" <<EOF
============================================================
VM Hot Swap Test Report
============================================================
Run ID: ${RUN_ID}
Result: ${result}
Case: ${SOURCE_FLAVOR:-unknown} -> ${DESTINATION_FLAVOR:-unknown}
Cluster: ${SOLANA_CLUSTER:-unknown}
City group: ${CITY_GROUP:-unknown}
VM arch: ${VM_ARCH:-unknown}
VM network mode: ${VM_NETWORK_MODE}

Note
- Partial report generated before full verification helpers were initialized.

Early Failure
- Reason: ${EARLY_FAILURE_REASON:-not captured}
- Bootstrap output:
${ENTRYPOINT_BOOTSTRAP_OUTPUT:-not captured}

Checks Passed
- Localnet entrypoint preflight (source VM): ${ENTRYPOINT_PREFLIGHT_VM_SOURCE}
- Localnet entrypoint preflight (destination VM): ${ENTRYPOINT_PREFLIGHT_VM_DESTINATION}
- Pre-swap runtime verification: ${PRE_SWAP_VERIFIED}
- Post-swap identity verification: ${SWAP_IDENTITY_VERIFIED}
- Post-swap runtime verification: ${POST_SWAP_VERIFIED}

Diagnosis
${REPORT_DIAGNOSIS:-No additional diagnosis captured.}

Artifacts
- Case directory: ${CASE_DIR}
- Source QEMU log: ${SRC_QEMU_LOG}
- Destination QEMU log: ${DST_QEMU_LOG}
- Entrypoint VM QEMU log (vm mode): ${ENTRYPOINT_VM_QEMU_LOG:-not used}
- Entrypoint container engine: ${LOCALNET_ENTRYPOINT_ENGINE_RESOLVED:-not used}
- Entrypoint container name: ${LOCALNET_ENTRYPOINT_CONTAINER_NAME:-not used}
- Localnet entrypoint log: ${LOCALNET_ENTRYPOINT_LOG:-not used}
- Report file: ${report_file}
- JSON report file: ${json_report_file}
============================================================
EOF

  jq -n \
    --arg run_id "$RUN_ID" \
    --arg result "$result" \
    --arg source_flavor "${SOURCE_FLAVOR:-unknown}" \
    --arg destination_flavor "${DESTINATION_FLAVOR:-unknown}" \
    --arg cluster "${SOLANA_CLUSTER:-unknown}" \
    --arg city_group "${CITY_GROUP:-unknown}" \
    --arg vm_arch "${VM_ARCH:-unknown}" \
    --arg vm_network_mode "${VM_NETWORK_MODE}" \
    --argjson total_duration_sec "$TOTAL_DURATION_SEC" \
    --argjson entrypoint_preflight_vm_source "$ENTRYPOINT_PREFLIGHT_VM_SOURCE" \
    --argjson entrypoint_preflight_vm_destination "$ENTRYPOINT_PREFLIGHT_VM_DESTINATION" \
    --argjson pre_swap_verified "$PRE_SWAP_VERIFIED" \
    --argjson hot_swap_completed "$HOT_SWAP_COMPLETED" \
    --argjson swap_identity_verified "$SWAP_IDENTITY_VERIFIED" \
    --argjson post_swap_verified "$POST_SWAP_VERIFIED" \
    --arg early_failure_reason "${EARLY_FAILURE_REASON:-not captured}" \
    --arg entrypoint_bootstrap_output "${ENTRYPOINT_BOOTSTRAP_OUTPUT:-not captured}" \
    --arg report_diagnosis "${REPORT_DIAGNOSIS:-No additional diagnosis captured.}" \
    --arg case_dir "$CASE_DIR" \
    --arg source_qemu_log "$SRC_QEMU_LOG" \
    --arg destination_qemu_log "$DST_QEMU_LOG" \
    --arg entrypoint_vm_qemu_log "${ENTRYPOINT_VM_QEMU_LOG:-not used}" \
    --arg entrypoint_container_engine "${LOCALNET_ENTRYPOINT_ENGINE_RESOLVED:-not used}" \
    --arg entrypoint_container_name "${LOCALNET_ENTRYPOINT_CONTAINER_NAME:-not used}" \
    --arg localnet_entrypoint_log "${LOCALNET_ENTRYPOINT_LOG:-not used}" \
    --arg text_report_file "$report_file" \
    --arg json_report_file "$json_report_file" \
    '{
      run_id: $run_id,
      result: $result,
      case: {
        source_flavor: $source_flavor,
        destination_flavor: $destination_flavor
      },
      environment: {
        cluster: $cluster,
        city_group: $city_group,
        vm_arch: $vm_arch,
        vm_network_mode: $vm_network_mode
      },
      durations_sec: {
        total: $total_duration_sec
      },
      checks_passed: {
        localnet_entrypoint_preflight_source: $entrypoint_preflight_vm_source,
        localnet_entrypoint_preflight_destination: $entrypoint_preflight_vm_destination,
        pre_swap_runtime_and_client: $pre_swap_verified,
        hot_swap_playbook_completed: $hot_swap_completed,
        post_swap_identity: $swap_identity_verified,
        post_swap_runtime_and_client: $post_swap_verified
      },
      early_failure: {
        reason: $early_failure_reason,
        bootstrap_output: $entrypoint_bootstrap_output
      },
      diagnosis: $report_diagnosis,
      note: "Partial report generated before full verification helpers were initialized.",
      artifacts: {
        case_dir: $case_dir,
        source_qemu_log: $source_qemu_log,
        destination_qemu_log: $destination_qemu_log,
        entrypoint_vm_qemu_log: $entrypoint_vm_qemu_log,
        entrypoint_container_engine: $entrypoint_container_engine,
        entrypoint_container_name: $entrypoint_container_name,
        localnet_entrypoint_log: $localnet_entrypoint_log,
        text_report_file: $text_report_file,
        json_report_file: $json_report_file
      }
    }' >"$json_report_file"

  echo "[vm-hot-swap] Wrote reports:" >&2
  echo "[vm-hot-swap]   text: $report_file" >&2
  echo "[vm-hot-swap]   json: $json_report_file" >&2
  echo "[vm-hot-swap] --- Begin test report ---" >&2
  cat "$report_file" >&2
  echo "[vm-hot-swap] --- End test report ---" >&2
  REPORT_EMITTED=true
}

cleanup_vm() {
  local pid_file="$1"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
  fi
}

kill_conflicting_qemu_listener() {
  local port="$1"
  local qemu_pids=""
  qemu_pids="$(
    lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null \
      | awk 'NR > 1 && $1 ~ /^qemu-syst/ { print $2 }' \
      | sort -u || true
  )"
  if [[ -z "$qemu_pids" ]]; then
    return 0
  fi

  local pid
  for pid in $qemu_pids; do
    echo "[vm-hot-swap] Reclaiming port ${port} from stale qemu pid=${pid}" >&2
    kill "$pid" >/dev/null 2>&1 || true
    sleep 1
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  done
}

cleanup() {
  if [[ "$VM_ENTRYPOINT_PREPARE_ONLY" != "true" ]]; then
    capture_container_entrypoint_log || true
    capture_entrypoint_vm_log || true
    stop_container_localnet_entrypoint_if_started
    stop_localnet_entrypoint_if_started
  fi
  if [[ "${REPORT_EMITTED:-false}" != "true" && -n "${ARTIFACTS_DIR:-}" && -d "${ARTIFACTS_DIR:-}" ]]; then
    emit_test_report || true
  fi
  local keep=false
  if [[ "$RETAIN_ALWAYS" == true ]]; then
    keep=true
  elif [[ "$EXEC_OK" != true && "$RETAIN_ON_FAILURE" == true ]]; then
    keep=true
  fi
  if [[ "$keep" == true ]]; then
    echo "[vm-hot-swap] retaining VM processes/artifacts at $CASE_DIR" >&2
    return 0
  fi
  if [[ "$SHARED_ENTRYPOINT_VM" != "true" ]]; then
    cleanup_vm "$ENTRYPOINT_VM_PID_FILE"
  fi
  cleanup_vm "$SRC_PID_FILE"
  cleanup_vm "$DST_PID_FILE"
}
trap 'on_error $? $LINENO' ERR
trap cleanup EXIT

run_script_for_arch() {
  case "$VM_ARCH" in
    amd64) echo "$REPO_ROOT/scripts/vm-test/run-qemu-amd64.sh" ;;
    arm64) echo "$REPO_ROOT/scripts/vm-test/run-qemu-arm64.sh" ;;
    *)
      echo "Unsupported VM arch: $VM_ARCH" >&2
      exit 2
      ;;
  esac
}

RUN_SCRIPT="$(run_script_for_arch)"
if [[ ! -x "$RUN_SCRIPT" ]]; then
  echo "Run script not executable: $RUN_SCRIPT" >&2
  exit 3
fi

snapshots_disk_enabled() {
  [[ "${VM_DISK_SNAPSHOTS_GB:-0}" =~ ^[0-9]+$ ]] || return 1
  (( VM_DISK_SNAPSHOTS_GB > 0 ))
}

assert_disk_parent_prefix_ready() {
  local prefix="$1"
  local label="$2"
  local path
  local suffixes=(".qcow2" "-ledger.qcow2" "-accounts.qcow2")

  if snapshots_disk_enabled; then
    suffixes+=("-snapshots.qcow2")
  fi

  for suffix in "${suffixes[@]}"; do
    path="${prefix}${suffix}"
    if [[ ! -r "$path" ]]; then
      echo "[vm-hot-swap] Missing ${label} parent disk: $path" >&2
      exit 3
    fi
  done
}

if [[ -n "$VM_SOURCE_DISK_PARENT_PREFIX" ]]; then
  assert_disk_parent_prefix_ready "$VM_SOURCE_DISK_PARENT_PREFIX" "source"
fi
if [[ -n "$VM_DESTINATION_DISK_PARENT_PREFIX" ]]; then
  assert_disk_parent_prefix_ready "$VM_DESTINATION_DISK_PARENT_PREFIX" "destination"
fi
if [[ -n "$VM_ENTRYPOINT_DISK_PARENT_PREFIX" ]]; then
  assert_disk_parent_prefix_ready "$VM_ENTRYPOINT_DISK_PARENT_PREFIX" "entrypoint"
fi

start_vm() {
  local vm_role="$1"
  local vm_name="$2"
  local vm_dir="$3"
  local ssh_host="$4"
  local ssh_port="$5"
  local ssh_port_alt="$6"
  local qemu_log="$7"
  local pid_file="$8"
  local tap_iface="$9"
  local extra_host_fwds="${10:-}"
  local base_image="${11:-$VM_BASE_IMAGE}"
  local disk_parent_prefix="${12:-}"
  local ssh_wait_port="${13:-$ssh_port}"
  local vm_mac_address
  local reuse_existing_disks=false

  vm_mac_address="$(vm_mac_address_for "$vm_role")"

  if vm_uses_shared_bridge; then
    WORK_DIR="$vm_dir" \
    VM_STATIC_IPV4="$ssh_host" \
    VM_GATEWAY_IPV4="$VM_BRIDGE_GATEWAY_IP" \
    VM_DNS_IPV4="$VM_BRIDGE_DNS_IP" \
    VM_CIDR_PREFIX="$VM_BRIDGE_CIDR_PREFIX" \
    VM_NETWORK_MATCH_NAME="$VM_NETWORK_MATCH_NAME" \
    "$REPO_ROOT/scripts/vm-test/make-seed.sh" "$vm_name" "$SSH_PUBLIC_KEY"
  else
    WORK_DIR="$vm_dir" "$REPO_ROOT/scripts/vm-test/make-seed.sh" "$vm_name" "$SSH_PUBLIC_KEY"
  fi

  if [[ "$vm_role" == "vm-entrypoint" && "$SHARED_ENTRYPOINT_VM" == "true" ]] \
    && [[ -z "$disk_parent_prefix" ]] \
    && [[ -r "$vm_dir/${vm_name}.qcow2" ]] \
    && [[ -r "$vm_dir/${vm_name}-ledger.qcow2" ]] \
    && [[ -r "$vm_dir/${vm_name}-accounts.qcow2" ]] \
    && { ! snapshots_disk_enabled || [[ -r "$vm_dir/${vm_name}-snapshots.qcow2" ]]; }; then
    reuse_existing_disks=true
  fi

  if [[ -n "$disk_parent_prefix" ]]; then
    WORK_DIR="$vm_dir" \
    VM_DISK_SYSTEM_GB="$VM_DISK_SYSTEM_GB" \
    VM_DISK_LEDGER_GB="$VM_DISK_LEDGER_GB" \
    VM_DISK_ACCOUNTS_GB="$VM_DISK_ACCOUNTS_GB" \
    VM_DISK_SNAPSHOTS_GB="$VM_DISK_SNAPSHOTS_GB" \
    VM_DISK_SYSTEM_PARENT="${disk_parent_prefix}.qcow2" \
    VM_DISK_LEDGER_PARENT="${disk_parent_prefix}-ledger.qcow2" \
    VM_DISK_ACCOUNTS_PARENT="${disk_parent_prefix}-accounts.qcow2" \
    VM_DISK_SNAPSHOTS_PARENT="${disk_parent_prefix}-snapshots.qcow2" \
    "$REPO_ROOT/scripts/vm-test/create-disks.sh" "$VM_ARCH" "$vm_name"
  elif [[ "$reuse_existing_disks" != "true" ]]; then
    WORK_DIR="$vm_dir" \
    VM_DISK_SYSTEM_GB="$VM_DISK_SYSTEM_GB" \
    VM_DISK_LEDGER_GB="$VM_DISK_LEDGER_GB" \
    VM_DISK_ACCOUNTS_GB="$VM_DISK_ACCOUNTS_GB" \
    VM_DISK_SNAPSHOTS_GB="$VM_DISK_SNAPSHOTS_GB" \
    "$REPO_ROOT/scripts/vm-test/create-disks.sh" "$VM_ARCH" "$vm_name" "$base_image"
  else
    echo "[vm-hot-swap] Reusing existing shared entrypoint VM disks from ${vm_dir}" >&2
  fi

  (
    export WORK_DIR="$vm_dir"
    export SSH_PORT="$ssh_port"
    export SSH_PORT_ALT="$ssh_port_alt"
    export EXTRA_HOST_FWDS="$extra_host_fwds"
    export RAM_MB="$VM_RAM_MB"
    export CPUS="$VM_CPUS"
    export QEMU_EFI="$VM_QEMU_EFI"
    export VM_MAC_ADDRESS="$vm_mac_address"
    if vm_uses_shared_bridge; then
      export VM_NETWORK_BACKEND="tap"
      export TAP_IFACE="$tap_iface"
    else
      export VM_NETWORK_BACKEND="user"
      export TAP_IFACE=""
    fi
    nohup "$RUN_SCRIPT" "$vm_name" >"$qemu_log" 2>&1 &
    echo $! >"$pid_file"
  )

  wait_for_ssh_or_qemu_exit "$vm_role" "$ssh_host" "$ssh_wait_port" "$SSH_WAIT_TIMEOUT" "$pid_file" "$qemu_log"

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]] || ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "[vm-hot-swap] QEMU process for $vm_name is not running after startup (port $ssh_wait_port)." >&2
    echo "[vm-hot-swap] Last QEMU log lines:" >&2
    tail -n 80 "$qemu_log" >&2 || true
    exit 4
  fi
}

assert_vm_alive_and_ssh_ready() {
  local label="$1"
  local host="$2"
  local port="$3"
  local pid_file="$4"
  local qemu_log="$5"
  local timeout="${6:-120}"
  local pid

  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]] || ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "[vm-hot-swap] ${label} QEMU process is not running (pid_file=${pid_file})." >&2
    echo "[vm-hot-swap] Last ${label} QEMU log lines:" >&2
    tail -n 120 "$qemu_log" >&2 || true
    exit 4
  fi

  wait_for_ssh_or_qemu_exit "$label" "$host" "$port" "$timeout" "$pid_file" "$qemu_log"
}

export_prepared_vm_disks() {
  local export_dir="$1"
  local source_prefix="$export_dir/source"
  local destination_prefix="$export_dir/destination"
  local quiesce_cmd

  if [[ -z "$export_dir" ]]; then
    echo "VM_PREPARE_EXPORT_DIR must be set when VM_PREPARE_ONLY=true." >&2
    exit 2
  fi

  mkdir -p "$export_dir"

  # Ensure prepared disks are exported from a clean validator state while preserving RBAC ownership.
  quiesce_cmd="set -eu; systemctl stop sol || true; for _ in \$(seq 1 90); do if ! systemctl is-active --quiet sol; then break; fi; sleep 1; done; if systemctl is-active --quiet sol; then systemctl kill sol || true; fi; rm -rf /mnt/ledger/* /mnt/accounts/* /mnt/snapshots/* /opt/validator/logs/*; mkdir -p /mnt/ledger /mnt/accounts /mnt/snapshots/remote /opt/validator/logs; chown -R sol:validator_operators /mnt/ledger /mnt/accounts /mnt/snapshots /opt/validator/logs || true; chmod 2775 /mnt/ledger /mnt/accounts /mnt/snapshots /mnt/snapshots/remote || true; chmod 2770 /opt/validator/logs || true; sync"
  ansible "all" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
    -m shell -a "$quiesce_cmd" -o >/dev/null

  cleanup_vm "$SRC_PID_FILE"
  cleanup_vm "$DST_PID_FILE"

  cp --reflink=auto -f "$SRC_VM_DIR/${SRC_VM_NAME}.qcow2" "${source_prefix}.qcow2"
  cp --reflink=auto -f "$SRC_VM_DIR/${SRC_VM_NAME}-ledger.qcow2" "${source_prefix}-ledger.qcow2"
  cp --reflink=auto -f "$SRC_VM_DIR/${SRC_VM_NAME}-accounts.qcow2" "${source_prefix}-accounts.qcow2"
  if snapshots_disk_enabled; then
    cp --reflink=auto -f "$SRC_VM_DIR/${SRC_VM_NAME}-snapshots.qcow2" "${source_prefix}-snapshots.qcow2"
  fi

  cp --reflink=auto -f "$DST_VM_DIR/${DST_VM_NAME}.qcow2" "${destination_prefix}.qcow2"
  cp --reflink=auto -f "$DST_VM_DIR/${DST_VM_NAME}-ledger.qcow2" "${destination_prefix}-ledger.qcow2"
  cp --reflink=auto -f "$DST_VM_DIR/${DST_VM_NAME}-accounts.qcow2" "${destination_prefix}-accounts.qcow2"
  if snapshots_disk_enabled; then
    cp --reflink=auto -f "$DST_VM_DIR/${DST_VM_NAME}-snapshots.qcow2" "${destination_prefix}-snapshots.qcow2"
  fi

  cat >"$export_dir/metadata.env" <<EOF
source_prefix=${source_prefix}
destination_prefix=${destination_prefix}
vm_arch=${VM_ARCH}
source_flavor=${SOURCE_FLAVOR}
destination_flavor=${DESTINATION_FLAVOR}
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  touch "$export_dir/.ready"
  echo "[vm-hot-swap] Prepared VM disk cache exported at $export_dir" >&2
}

SOURCE_BOOTSTRAP_HOST="$(vm_bootstrap_host_for vm-source)"
DESTINATION_BOOTSTRAP_HOST="$(vm_bootstrap_host_for vm-destination)"
SOURCE_BOOTSTRAP_PORT_EFFECTIVE="$(vm_bootstrap_port_for vm-source)"
DESTINATION_BOOTSTRAP_PORT_EFFECTIVE="$(vm_bootstrap_port_for vm-destination)"
SOURCE_OPERATOR_HOST_EFFECTIVE="$(vm_operator_host_for vm-source)"
DESTINATION_OPERATOR_HOST_EFFECTIVE="$(vm_operator_host_for vm-destination)"
SOURCE_OPERATOR_PORT_EFFECTIVE="$(vm_operator_port_for vm-source)"
DESTINATION_OPERATOR_PORT_EFFECTIVE="$(vm_operator_port_for vm-destination)"
ENTRYPOINT_BOOTSTRAP_HOST_EFFECTIVE="$(vm_bootstrap_host_for vm-entrypoint)"
ENTRYPOINT_BOOTSTRAP_PORT_EFFECTIVE="$(vm_bootstrap_port_for vm-entrypoint)"
ENTRYPOINT_OPERATOR_PORT_EFFECTIVE="$(vm_operator_port_for vm-entrypoint)"
SOURCE_START_WAIT_PORT="$SOURCE_BOOTSTRAP_PORT_EFFECTIVE"
DESTINATION_START_WAIT_PORT="$DESTINATION_BOOTSTRAP_PORT_EFFECTIVE"

if [[ "$PREPARED_VM_REUSE_MODE" == "true" ]]; then
  SOURCE_START_WAIT_PORT="$SOURCE_OPERATOR_PORT_EFFECTIVE"
  DESTINATION_START_WAIT_PORT="$DESTINATION_OPERATOR_PORT_EFFECTIVE"
  echo "[vm-hot-swap] Prepared VM reuse enabled: waiting for operator SSH ports (${SOURCE_START_WAIT_PORT}/${DESTINATION_START_WAIT_PORT}) during VM boot." >&2
fi

if [[ "$AUTO_KILL_CONFLICTING_QEMU" == "true" ]]; then
  for port in "$SOURCE_SSH_PORT" "$SOURCE_SSH_PORT_ALT" "$DESTINATION_SSH_PORT" "$DESTINATION_SSH_PORT_ALT"; do
    kill_conflicting_qemu_listener "$port"
  done
  if entrypoint_mode_uses_vm && ! vm_uses_shared_bridge; then
    for port in "$ENTRYPOINT_VM_SSH_PORT" "$ENTRYPOINT_VM_SSH_PORT_ALT" "$VM_LOCALNET_ENTRYPOINT_RPC_PORT" "$VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT" "$VM_LOCALNET_ENTRYPOINT_FAUCET_PORT"; do
      kill_conflicting_qemu_listener "$port"
    done
  fi
fi

assert_shared_bridge_network_ready

cat >"$ENTRYPOINT_VM_BOOTSTRAP_INVENTORY" <<EOF
all:
  hosts:
    vm-entrypoint:
      ansible_host: ${ENTRYPOINT_BOOTSTRAP_HOST_EFFECTIVE}
      ansible_port: ${ENTRYPOINT_BOOTSTRAP_PORT_EFFECTIVE}
      ansible_user: ${BOOTSTRAP_USER}
      ansible_ssh_private_key_file: ${SSH_PRIVATE_KEY_FILE}
      ansible_ssh_common_args: "${SSH_COMMON_ARGS}"
      ansible_become: true
EOF

if [[ "$VM_ENTRYPOINT_PREPARE_ONLY" == "true" ]]; then
  CURRENT_PHASE="entrypoint cache prepare"
  ensure_entrypoint_vm_localnet_service
  if [[ "$SHARED_ENTRYPOINT_VM" == "true" ]]; then
    touch "$SHARED_ENTRYPOINT_ROOT/.cli-cache-ready"
  fi
  # Flush and power off cleanly so cached disks persist installed CLI artifacts.
  ansible "vm-entrypoint" -i "$ENTRYPOINT_VM_BOOTSTRAP_INVENTORY" -u "$BOOTSTRAP_USER" -b \
    -m shell -a "set -eu; sync; nohup sh -c 'sleep 1; systemctl poweroff' >/dev/null 2>&1 </dev/null &" -o >/dev/null 2>&1 || true
  for _ in $(seq 1 60); do
    entrypoint_prepare_pid="$(cat "$ENTRYPOINT_VM_PID_FILE" 2>/dev/null || true)"
    if [[ -z "$entrypoint_prepare_pid" ]] || ! kill -0 "$entrypoint_prepare_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  cleanup_vm "$ENTRYPOINT_VM_PID_FILE"
  EXEC_OK=true
  REPORT_EMITTED=true
  echo "[vm-hot-swap] Entrypoint VM prepare-only run completed successfully." >&2
  exit 0
fi

# Bring entrypoint up first so prepared validators don't fail startup while entrypoint is still down.
ensure_localnet_entrypoint

echo "[vm-hot-swap] Starting source VM..." >&2
start_vm "vm-source" "$SRC_VM_NAME" "$SRC_VM_DIR" "$SOURCE_BOOTSTRAP_HOST" "$SOURCE_BOOTSTRAP_PORT_EFFECTIVE" "$SOURCE_OPERATOR_PORT_EFFECTIVE" "$SRC_QEMU_LOG" "$SRC_PID_FILE" "$(vm_tap_iface_for vm-source)" "" "${VM_BASE_IMAGE}" "${VM_SOURCE_DISK_PARENT_PREFIX}" "$SOURCE_START_WAIT_PORT"
echo "[vm-hot-swap] Starting destination VM..." >&2
start_vm "vm-destination" "$DST_VM_NAME" "$DST_VM_DIR" "$DESTINATION_BOOTSTRAP_HOST" "$DESTINATION_BOOTSTRAP_PORT_EFFECTIVE" "$DESTINATION_OPERATOR_PORT_EFFECTIVE" "$DST_QEMU_LOG" "$DST_PID_FILE" "$(vm_tap_iface_for vm-destination)" "" "${VM_BASE_IMAGE}" "${VM_DESTINATION_DISK_PARENT_PREFIX}" "$DESTINATION_START_WAIT_PORT"

ensure_local_keyset "$HOME/.validator-keys/$SOURCE_VALIDATOR_KEYSET_NAME" "$SOURCE_HOT_SPARE_IDENTITY_SOURCE"
ensure_local_keyset "$HOME/.validator-keys/$DESTINATION_VALIDATOR_KEYSET_NAME" "$DESTINATION_HOT_SPARE_IDENTITY_SOURCE"

IAM_CSV="$CASE_DIR/iam_setup_vm_validator.csv"
AUTHORIZED_IPS_CSV="$CASE_DIR/authorized_ips_vm.csv"
BOOTSTRAP_INVENTORY="$CASE_DIR/inventory.bootstrap.yml"
OPERATOR_INVENTORY="$CASE_DIR/inventory.operator.yml"
TARGET_HOSTS="vm-source,vm-destination"

cat >"$IAM_CSV" <<EOF
user,key,group_a,group_b,group_c
alice,${SSH_PUBLIC_KEY},sysadmin,,
${VALIDATOR_OPERATOR_USER},${SSH_PUBLIC_KEY},validator_operators,,
carla,${SSH_PUBLIC_KEY},validator_viewers,,
sol,,,,
EOF

{
  printf 'ip,comment\n'
  printf '%s,%s\n' "$VM_AUTHORIZED_IP" "Host control-plane address"
  if vm_uses_shared_bridge && entrypoint_mode_uses_vm \
    && [[ -n "$ENTRYPOINT_VM_BRIDGE_IP" && "$ENTRYPOINT_VM_BRIDGE_IP" != "$VM_AUTHORIZED_IP" ]]; then
    printf '%s,%s\n' "$ENTRYPOINT_VM_BRIDGE_IP" "Entrypoint VM bridge address"
  fi
} >"$AUTHORIZED_IPS_CSV"

cat >"$BOOTSTRAP_INVENTORY" <<EOF
all:
  hosts:
    vm-source:
      ansible_host: ${SOURCE_BOOTSTRAP_HOST}
      ansible_port: ${SOURCE_BOOTSTRAP_PORT_EFFECTIVE}
      ansible_user: ${BOOTSTRAP_USER}
      ansible_ssh_private_key_file: ${SSH_PRIVATE_KEY_FILE}
      ansible_ssh_common_args: "${SSH_COMMON_ARGS}"
      ansible_become: true
    vm-destination:
      ansible_host: ${DESTINATION_BOOTSTRAP_HOST}
      ansible_port: ${DESTINATION_BOOTSTRAP_PORT_EFFECTIVE}
      ansible_user: ${BOOTSTRAP_USER}
      ansible_ssh_private_key_file: ${SSH_PRIVATE_KEY_FILE}
      ansible_ssh_common_args: "${SSH_COMMON_ARGS}"
      ansible_become: true
  children:
    ${CITY_GROUP}:
      hosts:
        vm-source:
        vm-destination:
    solana:
      hosts:
        vm-source:
        vm-destination:
    solana_localnet:
      hosts:
        vm-source:
        vm-destination:
    solana_validator_ha_pair:
      hosts:
        vm-source:
        vm-destination:
EOF

cat >"$OPERATOR_INVENTORY" <<EOF
all:
  vars:
    solana_rpc_url: http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}
  hosts:
    vm-source:
      ansible_host: ${SOURCE_OPERATOR_HOST_EFFECTIVE}
      ansible_port: ${SOURCE_OPERATOR_PORT_EFFECTIVE}
      ansible_user: ${VALIDATOR_OPERATOR_USER}
      ansible_ssh_private_key_file: ${SSH_PRIVATE_KEY_FILE}
      ansible_ssh_common_args: "${SSH_COMMON_ARGS}"
      ansible_become: true
      validator_keyset_name: ${SOURCE_VALIDATOR_KEYSET_NAME}
      solana_validator_ha_client: $(ha_client_for_flavor "$SOURCE_FLAVOR")
      solana_validator_ha_public_ip_value: ${VM_SOURCE_BRIDGE_IP:-$SOURCE_OPERATOR_HOST_EFFECTIVE}
      solana_validator_ha_node_id: ${SOLANA_VALIDATOR_HA_SOURCE_NODE_ID}
      solana_validator_ha_priority: ${SOLANA_VALIDATOR_HA_SOURCE_PRIORITY}
    vm-destination:
      ansible_host: ${DESTINATION_OPERATOR_HOST_EFFECTIVE}
      ansible_port: ${DESTINATION_OPERATOR_PORT_EFFECTIVE}
      ansible_user: ${VALIDATOR_OPERATOR_USER}
      ansible_ssh_private_key_file: ${SSH_PRIVATE_KEY_FILE}
      ansible_ssh_common_args: "${SSH_COMMON_ARGS}"
      ansible_become: true
      validator_keyset_name: ${DESTINATION_VALIDATOR_KEYSET_NAME}
      solana_validator_ha_client: $(ha_client_for_flavor "$DESTINATION_FLAVOR")
      solana_validator_ha_public_ip_value: ${VM_DESTINATION_BRIDGE_IP:-$DESTINATION_OPERATOR_HOST_EFFECTIVE}
      solana_validator_ha_node_id: ${SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID}
      solana_validator_ha_priority: ${SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY}
  children:
    ${CITY_GROUP}:
      hosts:
        vm-source:
        vm-destination:
    solana:
      hosts:
        vm-source:
        vm-destination:
    solana_localnet:
      hosts:
        vm-source:
        vm-destination:
    ha_reconcile_inventory_group_all:
      hosts:
        vm-source:
        vm-destination:
    ${SOLANA_VALIDATOR_HA_RECONCILE_GROUP}:
      vars:
        solana_validator_ha_inventory_group: ${SOLANA_VALIDATOR_HA_RECONCILE_GROUP}
        solana_validator_ha_cluster_name: testnet
        solana_validator_ha_cluster_rpc_urls:
          - http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}
      hosts:
        vm-source:
        vm-destination:
EOF

mkdir -p "$CASE_DIR/group_vars"
cp "$REPO_ROOT/ansible/group_vars/all.yml" "$CASE_DIR/group_vars/all.yml"
cp "$REPO_ROOT/ansible/group_vars/solana.yml" "$CASE_DIR/group_vars/solana.yml"
cp "$SOLANA_CLUSTER_VARS_FILE" "$CASE_DIR/group_vars/$(basename "$SOLANA_CLUSTER_VARS_FILE")"
cp "$CITY_GROUP_VARS_FILE" "$CASE_DIR/group_vars/$(basename "$CITY_GROUP_VARS_FILE")"

phase_start_ts="$(date +%s)"
if [[ "$PREPARED_VM_REUSE_MODE" == "true" ]]; then
  CURRENT_PHASE="prepared-vm operator SSH readiness"
  echo "[vm-hot-swap] Prepared VM reuse: skipping users/metal bootstrap and validating operator SSH..." >&2
else
  CURRENT_PHASE="users-then-metal-box bootstrap"
  echo "[vm-hot-swap] Running users -> metal-box (requested order)..." >&2
  if [[ "$ENABLE_VM_TEST_SYSADMIN_NOPASSWD" == "true" ]]; then
    echo "[vm-hot-swap] Preparing temporary sysadmin sudo policy for VM automation..." >&2
    for vm_target in vm-source vm-destination; do
      echo "[vm-hot-swap] Preparing temporary sysadmin sudo policy on ${vm_target}..." >&2
      ansible-playbook \
        -i "$BOOTSTRAP_INVENTORY" \
        "$REPO_ROOT/test-harness/ansible/pb_prepare_vm_sysadmin_nopasswd.yml" \
        -e "target_hosts=$vm_target" \
        -e "bootstrap_user=$BOOTSTRAP_USER"
    done
  fi

  for vm_target in vm-source vm-destination; do
    echo "[vm-hot-swap] Running users -> metal-box on ${vm_target}..." >&2
    users_metal_args=(
      -i "$BOOTSTRAP_INVENTORY"
      "$REPO_ROOT/test-harness/ansible/pb_vm_users_then_metal_box.yml"
      --skip-tags "$VM_METAL_BOX_SKIP_TAGS"
      "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}"
      -e "target_host=$vm_target"
      -e "bootstrap_user=$BOOTSTRAP_USER"
      -e "metal_box_user=$METAL_BOX_SYSADMIN_USER"
      -e "manage_cpu_governor_service=$CPU_GOVERNOR_MANAGE"
      -e "users_csv_file=$(basename "$IAM_CSV")"
      -e "users_base_dir=$(dirname "$IAM_CSV")"
      -e "authorized_ips_csv_file=$(basename "$AUTHORIZED_IPS_CSV")"
      -e "authorized_access_csv=$AUTHORIZED_IPS_CSV"
      -e "skip_confirmation_pauses=$SKIP_CONFIRMATION_PAUSES"
    )
    ansible-playbook "${users_metal_args[@]}"
  done

  echo "[vm-hot-swap] Waiting for post-metal SSH ports..." >&2
  CURRENT_PHASE="post-metal SSH readiness"
fi

wait_for_ssh_or_qemu_exit "source-post-metal" "$SOURCE_OPERATOR_HOST_EFFECTIVE" "$SOURCE_OPERATOR_PORT_EFFECTIVE" 300 "$SRC_PID_FILE" "$SRC_QEMU_LOG"
wait_for_ssh_or_qemu_exit "destination-post-metal" "$DESTINATION_OPERATOR_HOST_EFFECTIVE" "$DESTINATION_OPERATOR_PORT_EFFECTIVE" 300 "$DST_PID_FILE" "$DST_QEMU_LOG"
USERS_METAL_SETUP_DURATION_SEC=$(( $(date +%s) - phase_start_ts ))

phase_start_ts="$(date +%s)"
CURRENT_PHASE="localnet entrypoint preflight"
echo "[vm-hot-swap] Verifying VM reachability to the localnet entrypoint..." >&2
ensure_localnet_entrypoint
assert_vm_can_reach_localnet_entrypoint "vm-source" "source"
assert_vm_can_reach_localnet_entrypoint "vm-destination" "destination"
ENTRYPOINT_PREFLIGHT_DURATION_SEC=$(( $(date +%s) - phase_start_ts ))

setup_host_flavor() {
  local host="$1"
  local flavor="$2"
  local validator_type="$3"
  local base_args=(
    -i "$OPERATOR_INVENTORY"
    --limit "$host"
    -e "target_host=$host"
    -e "ansible_user=$VALIDATOR_OPERATOR_USER"
    -e "validator_name=$VALIDATOR_NAME"
    -e "validator_type=$validator_type"
    -e "xdp_enabled=true"
    -e "solana_cluster=$SOLANA_CLUSTER"
    -e "build_from_source=$BUILD_FROM_SOURCE"
    -e "force_host_cleanup=$FORCE_HOST_CLEANUP"
  )

  case "$flavor" in
    agave)
      ansible-playbook \
        "${base_args[@]}" \
        "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
        -e "agave_version=$AGAVE_VERSION" \
        "$REPO_ROOT/ansible/playbooks/pb_setup_validator_agave.yml"
      ;;
    jito-shared)
      ansible-playbook \
        "${base_args[@]}" \
        "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
        -e "jito_version=$JITO_VERSION" \
        "$REPO_ROOT/ansible/playbooks/pb_setup_validator_jito_v2.yml"
      ;;
    jito-cohosted)
      ansible-playbook \
        "${base_args[@]}" \
        "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
        -e "jito_version=$JITO_VERSION" \
        "$REPO_ROOT/ansible/playbooks/pb_setup_validator_jito_v2.yml"
      ;;
    jito-bam)
      if [[ -n "$BAM_JITO_VERSION_PATCH" ]]; then
        ansible-playbook \
          "${base_args[@]}" \
          "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
          -e "jito_version=$BAM_JITO_VERSION" \
          -e "jito_version_patch=$BAM_JITO_VERSION_PATCH" \
          "$REPO_ROOT/ansible/playbooks/pb_setup_validator_jito_v2.yml"
      else
        ansible-playbook \
          "${base_args[@]}" \
          "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
          -e "jito_version=$BAM_JITO_VERSION" \
          "$REPO_ROOT/ansible/playbooks/pb_setup_validator_jito_v2.yml"
      fi
      ;;
    *)
      echo "Unsupported flavor: $flavor" >&2
      exit 2
      ;;
  esac
}

reconcile_validator_ha_cluster() {
  local extra_args=()

  if [[ -n "$HA_RECONCILE_INVENTORY_GROUP_ALL" ]]; then
    extra_args+=(-e "ha_reconcile_inventory_group_all=$HA_RECONCILE_INVENTORY_GROUP_ALL")
  fi

  if [[ "$HA_RECONCILE_ALLOW_DECOMMISSION" == "true" ]]; then
    extra_args+=(-e "ha_reconcile_allow_decommission=true")
  fi

  ansible-playbook \
    -i "$OPERATOR_INVENTORY" \
    "$REPO_ROOT/ansible/playbooks/pb_reconcile_validator_ha_cluster.yml" \
    "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
    "${extra_args[@]}" \
    -e "target_ha_group=$SOLANA_VALIDATOR_HA_RECONCILE_GROUP" \
    -e "operator_user=$VALIDATOR_OPERATOR_USER" \
    -e "validator_name=$VALIDATOR_NAME" \
    -e "solana_cluster=$SOLANA_CLUSTER" \
    -e "ha_enforce_hostname_prefix=false"
}

assert_host_client() {
  local host="$1"
  local flavor="$2"
  local expected_regex
  local output
  local version_cmd
  local rc=0
  expected_regex="$(expected_client_regex_for_flavor "$flavor")"
  version_cmd="set -eu; bindir='/opt/solana/active_release/bin'; if [ -x \"\$bindir/agave-validator\" ]; then \"\$bindir/agave-validator\" --version; elif [ -x \"\$bindir/solana-validator\" ]; then \"\$bindir/solana-validator\" --version; elif [ -x \"\$bindir/solana\" ]; then \"\$bindir/solana\" --version; else echo 'No validator version command found in' \"\$bindir\" >&2; exit 1; fi"
  output="$(
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "$version_cmd" -o 2>&1
  )" || rc=$?
  if [[ -z "$output" ]]; then
    output="version probe failed with no output"
  fi
  case "$host" in
    vm-source) HOST_VERSION_VM_SOURCE="$output" ;;
    vm-destination) HOST_VERSION_VM_DESTINATION="$output" ;;
  esac
  if ((rc != 0)) || ! grep -Eq "$expected_regex" <<<"$output"; then
    echo "Host $host does not match expected flavor '$flavor' (pattern: $expected_regex)" >&2
    echo "$output" >&2
    exit 1
  fi
}

assert_host_validator_runtime() {
  local host="$1"
  local service_cmd
  local state_cmd
  local journal_cmd
  local state_output
  local journal_output=""
  local service_check_rc=0
  local rpc_check_rc=0

  service_cmd="set -eu; active=\$(systemctl show sol --property=ActiveState --value --no-pager); sub=\$(systemctl show sol --property=SubState --value --no-pager); exec_status=\$(systemctl show sol --property=ExecMainStatus --value --no-pager); if [ \"\$active\" != 'active' ] || [ \"\$sub\" != 'running' ] || [ \"\$exec_status\" != '0' ]; then echo \"Validator service unhealthy: \${active}/\${sub}/\${exec_status}\" >&2; exit 1; fi"
  state_cmd="set -eu; systemctl show sol --property=ActiveState --property=SubState --property=ExecMainStatus --value --no-pager | tr '\n' '/' | sed 's#/*\$##'"
  journal_cmd="set -eu; journalctl -u sol -n 80 --no-pager || true; printf -- '\n-- validator log tail --\n'; tail -n 80 /opt/validator/logs/agave-validator.log 2>/dev/null || true"

  state_output="$(
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "$state_cmd" -o 2>&1 || true
  )"
  if [[ -z "$state_output" ]]; then
    state_output="service state probe failed with no output"
  fi
  case "$host" in
    vm-source) HOST_SERVICE_VM_SOURCE="$state_output" ;;
    vm-destination) HOST_SERVICE_VM_DESTINATION="$state_output" ;;
  esac

  ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
    -m shell -a "$service_cmd" -o >/dev/null || service_check_rc=$?

  ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
    -m wait_for -a "host=127.0.0.1 port=8899 timeout=60 state=started" -o >/dev/null || rpc_check_rc=$?

  if ((service_check_rc != 0 || rpc_check_rc != 0)); then
    journal_output="$(
      ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
        -m shell -a "$journal_cmd" -o 2>&1 || true
    )"
    if [[ -z "$journal_output" ]]; then
      journal_output="runtime diagnostic probe failed with no output"
    fi
    case "$host" in
      vm-source) HOST_DIAGNOSTIC_VM_SOURCE="$journal_output" ;;
      vm-destination) HOST_DIAGNOSTIC_VM_DESTINATION="$journal_output" ;;
    esac
  fi

  if ((service_check_rc != 0)); then
    echo "Host $host validator service is not healthy." >&2
    echo "$state_output" >&2
    echo "$journal_output" >&2
    exit 1
  fi
  if ((rpc_check_rc != 0)); then
    echo "Host $host validator RPC port 8899 is not listening." >&2
    echo "$state_output" >&2
    echo "$journal_output" >&2
    exit 1
  fi
}

assert_host_ha_runtime_config() {
  local host="$1"
  local expected_node_id="$2"
  local expected_priority="$3"
  local expected_peer_node_id="$4"
  local expected_peer_ip="$5"
  local expected_peer_priority="$6"
  local config_cmd

  config_cmd="set -eu; cfg='/opt/validator/ha/config.yaml'; test -f \"\$cfg\"; grep -F 'name: \"${expected_node_id}\"' \"\$cfg\" >/dev/null; grep -F 'priority: ${expected_priority}' \"\$cfg\" >/dev/null; grep -F '${expected_peer_node_id}:' \"\$cfg\" >/dev/null; grep -F 'ip: \"${expected_peer_ip}\"' \"\$cfg\" >/dev/null; grep -F 'priority: ${expected_peer_priority}' \"\$cfg\" >/dev/null"
  ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
    -m shell -a "$config_cmd" -o >/dev/null
}

wait_for_host_validator_runtime_ready() {
  local host="$1"
  local timeout="${2:-$REUSE_RUNTIME_READY_TIMEOUT_SEC}"
  local first_timeout="$timeout"
  local second_timeout=0
  local service_cmd
  local state_cmd
  local journal_cmd
  local state_output=""
  local journal_output=""
  local rc=0

  service_cmd="set -eu; if ! systemctl is-active --quiet sol; then systemctl start sol; fi"
  state_cmd="set -eu; systemctl show sol --property=ActiveState --property=SubState --property=ExecMainStatus --property=MainPID --no-pager"
  journal_cmd="set -eu; journalctl -u sol -n 120 --no-pager || true; printf -- '\n-- validator log tail --\n'; tail -n 120 /opt/validator/logs/agave-validator.log 2>/dev/null || true"

  if (( timeout >= 120 )); then
    first_timeout=$(( timeout / 2 ))
    if (( first_timeout < 60 )); then
      first_timeout=60
    fi
    second_timeout=$(( timeout - first_timeout ))
  fi

  ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
    -m shell -a "$service_cmd" -o >/dev/null || true

  ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
    -m wait_for -a "host=127.0.0.1 port=8899 timeout=${first_timeout} state=started" -o >/dev/null || rc=$?

  if (( rc == 0 )); then
    return 0
  fi

  state_output="$(
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "$state_cmd" -o 2>&1 || true
  )"
  journal_output="$(
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "$journal_cmd" -o 2>&1 || true
  )"
  if [[ -z "$journal_output" ]]; then
    journal_output="runtime warmup diagnostic probe failed with no output"
  fi
  echo "[vm-hot-swap] Host $host validator RPC warmup attempt 1/${timeout}s failed; restarting sol.service and retrying." >&2
  echo "$state_output" >&2
  echo "$journal_output" >&2

  if (( second_timeout > 0 )); then
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "set -eu; systemctl restart sol" -o >/dev/null || true
    rc=0
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m wait_for -a "host=127.0.0.1 port=8899 timeout=${second_timeout} state=started" -o >/dev/null || rc=$?
    if (( rc == 0 )); then
      return 0
    fi
  fi

  state_output="$(
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "$state_cmd" -o 2>&1 || true
  )"
  journal_output="$(
      ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
        -m shell -a "$journal_cmd" -o 2>&1 || true
  )"
  if [[ -z "$journal_output" ]]; then
    journal_output="runtime warmup diagnostic probe failed with no output"
  fi
  case "$host" in
    vm-source) HOST_DIAGNOSTIC_VM_SOURCE="$journal_output" ;;
    vm-destination) HOST_DIAGNOSTIC_VM_DESTINATION="$journal_output" ;;
  esac
  echo "Host $host validator RPC port 8899 did not become ready within ${timeout}s." >&2
  echo "$state_output" >&2
  echo "$journal_output" >&2
  exit 1
}

promote_host_runtime_identity_to_primary() {
  local host="$1"
  local promote_cmd
  local output
  local attempt
  local rc=0

  promote_cmd="set -eu; kdir='/opt/validator/keys/$VALIDATOR_NAME'; key=\"\$kdir/primary-target-identity.json\"; remaining=180; while [ \"\$remaining\" -gt 0 ]; do if /opt/solana/active_release/bin/agave-validator -l /mnt/ledger set-identity \"\$key\" >/dev/null 2>&1; then exit 0; fi; sleep 2; remaining=\$((remaining - 2)); done; echo 'Timed out promoting runtime identity to primary-target-identity.json' >&2; exit 1"

  for attempt in 1 2 3; do
    rc=0
    output="$(
      ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
        -m shell -a "$promote_cmd" -o 2>&1
    )" || rc=$?
    if (( rc == 0 )); then
      return 0
    fi
    sleep 5
  done

  echo "Failed to promote runtime identity to primary on $host after multiple attempts." >&2
  echo "$output" >&2
  exit 1
}

wait_for_host_validator_catchup() {
  local host="$1"
  local rpc_url
  local catchup_cmd
  local output
  local journal_cmd
  local journal_output=""
  local rc=0

  rpc_url="http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}"
  catchup_cmd="set -eu; export PATH='/opt/solana/active_release/bin:'\"\$PATH\"; timeout ${PRE_SWAP_CATCHUP_TIMEOUT_SEC}s solana catchup -u '${rpc_url}' --our-localhost 8899"
  journal_cmd="set -eu; journalctl -u sol -n 120 --no-pager || true; printf -- '\n-- validator log tail --\n'; tail -n 120 /opt/validator/logs/agave-validator.log 2>/dev/null || true"

  output="$(
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "$catchup_cmd" -o 2>&1
  )" || rc=$?

  if (( rc != 0 )); then
    journal_output="$(
      ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
        -m shell -a "$journal_cmd" -o 2>&1 || true
    )"
    if [[ -z "$journal_output" ]]; then
      journal_output="catchup diagnostic probe failed with no output"
    fi
    case "$host" in
      vm-source) HOST_DIAGNOSTIC_VM_SOURCE="$journal_output" ;;
      vm-destination) HOST_DIAGNOSTIC_VM_DESTINATION="$journal_output" ;;
    esac
    echo "Host $host did not reach catchup against ${rpc_url} within ${PRE_SWAP_CATCHUP_TIMEOUT_SEC}s." >&2
    echo "$output" >&2
    echo "$journal_output" >&2
    exit 1
  fi
}

wait_for_source_tower_file() {
  local tower_cmd
  local journal_cmd
  local output
  local journal_output=""
  local rc=0

  tower_cmd="set -eu; kdir='/opt/validator/keys/$VALIDATOR_NAME'; pub=\$(/opt/solana/active_release/bin/solana-keygen pubkey \"\$kdir/primary-target-identity.json\"); tower=\"/mnt/ledger/tower-1_9-\${pub}.bin\"; remaining=${PRE_SWAP_TOWER_TIMEOUT_SEC}; while [ \"\$remaining\" -gt 0 ]; do if [ -s \"\$tower\" ]; then printf '%s\n' \"\$tower\"; exit 0; fi; sleep 2; remaining=\$((remaining - 2)); done; echo \"Tower file not ready: \$tower\" >&2; ls -l \"\$(dirname \"\$tower\")\" >&2 || true; exit 1"
  journal_cmd="set -eu; journalctl -u sol -n 120 --no-pager || true; printf -- '\n-- validator log tail --\n'; tail -n 120 /opt/validator/logs/agave-validator.log 2>/dev/null || true"

  output="$(
    ansible "vm-source" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "$tower_cmd" -o 2>&1
  )" || rc=$?

  if (( rc != 0 )); then
    journal_output="$(
      ansible "vm-source" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
        -m shell -a "$journal_cmd" -o 2>&1 || true
    )"
    if [[ -z "$journal_output" ]]; then
      journal_output="tower diagnostic probe failed with no output"
    fi
    HOST_DIAGNOSTIC_VM_SOURCE="$journal_output"
    echo "Source validator did not produce a tower file within ${PRE_SWAP_TOWER_TIMEOUT_SEC}s." >&2
    echo "$output" >&2
    echo "$journal_output" >&2
    exit 1
  fi
}

apply_pre_swap_injection() {
  local mode="${PRE_SWAP_INJECTION_MODE:-none}"
  local inject_cmd
  local destination_operator_port

  if [[ -z "$mode" || "$mode" == "none" ]]; then
    return 0
  fi

  echo "[vm-hot-swap] Applying pre-swap injection mode: ${mode}" >&2
  case "$mode" in
    stop_entrypoint_rpc|stop_source_validator_service)
      inject_cmd="set -eu; systemctl stop sol; systemctl is-active --quiet sol && exit 1 || true; echo 'Injected source validator service stop (sol.service)'"
      ansible "vm-source" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
        -m shell -a "$inject_cmd" -o >/dev/null
      ;;
    mismatch_destination_primary_identity)
      inject_cmd="set -eu; kdir='/opt/validator/keys/$VALIDATOR_NAME'; key=\"\$kdir/primary-target-identity.json\"; /opt/solana/active_release/bin/solana-keygen new --no-bip39-passphrase --force -o \"\$key\" >/dev/null"
      ansible "vm-destination" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
        -m shell -a "$inject_cmd" -o >/dev/null
      ;;
    block_source_to_destination_ssh)
      if ! vm_uses_shared_bridge || [[ -z "$VM_SOURCE_BRIDGE_IP" || -z "$VM_DESTINATION_BRIDGE_IP" ]]; then
        echo "PRE_SWAP_INJECTION_MODE=block_source_to_destination_ssh requires VM_NETWORK_MODE=shared-bridge, VM_SOURCE_BRIDGE_IP, and VM_DESTINATION_BRIDGE_IP." >&2
        exit 2
      fi
      destination_operator_port="$(vm_operator_port_for vm-destination)"
      inject_cmd="set -eu; if command -v ufw >/dev/null 2>&1; then ufw --force insert 1 deny out proto tcp to '$VM_DESTINATION_BRIDGE_IP' port '$destination_operator_port' >/dev/null; else iptables -I OUTPUT -p tcp -d '$VM_DESTINATION_BRIDGE_IP' --dport '$destination_operator_port' -j REJECT; fi"
      ansible "vm-source" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
        -m shell -a "$inject_cmd" -o >/dev/null
      ;;
    *)
      echo "Unsupported PRE_SWAP_INJECTION_MODE: $mode" >&2
      exit 2
      ;;
  esac
}

assert_swap_identity_state() {
  local source_cmd
  local destination_cmd
  source_cmd="set -eu; kdir='/opt/validator/keys/$VALIDATOR_NAME'; run=\$(/opt/solana/active_release/bin/agave-validator -l /mnt/ledger contact-info | awk '/^Identity:/ { print \$2; exit }'); hot=\$(/opt/solana/active_release/bin/solana-keygen pubkey \"\$kdir/hot-spare-identity.json\"); test \"\$run\" = \"\$hot\""
  destination_cmd="set -eu; kdir='/opt/validator/keys/$VALIDATOR_NAME'; run=\$(/opt/solana/active_release/bin/agave-validator -l /mnt/ledger contact-info | awk '/^Identity:/ { print \$2; exit }'); primary=\$(/opt/solana/active_release/bin/solana-keygen pubkey \"\$kdir/primary-target-identity.json\"); test \"\$run\" = \"\$primary\""

  ansible "vm-source" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b -m shell -a "$source_cmd" -o

  ansible "vm-destination" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b -m shell -a "$destination_cmd" -o

  SWAP_IDENTITY_VERIFIED=true
}

capture_host_identity_state() {
  local host="$1"
  local stage="$2"
  local cmd
  local output
  local run_key
  local primary_key
  local hot_key

  cmd="set -eu; kdir='/opt/validator/keys/$VALIDATOR_NAME'; pubkey_or_missing() { f=\"\$1\"; if [ -f \"\$f\" ]; then /opt/solana/active_release/bin/solana-keygen pubkey \"\$f\"; else printf 'missing\\n'; fi; }; runtime_or_missing() { runtime=\$(/opt/solana/active_release/bin/agave-validator -l /mnt/ledger contact-info 2>/dev/null | awk '/^Identity:/ { print \$2; exit }' || true); if [ -n \"\$runtime\" ]; then printf '%s\\n' \"\$runtime\"; else printf 'missing\\n'; fi; }; run=\$(runtime_or_missing); primary=\$(pubkey_or_missing \"\$kdir/primary-target-identity.json\"); hot=\$(pubkey_or_missing \"\$kdir/hot-spare-identity.json\"); printf '%s\\t%s\\t%s\\n' \"\$run\" \"\$primary\" \"\$hot\""
  output="$(
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "$cmd" -o 2>/dev/null | awk -F' \\(stdout\\) ' 'NF > 1 { print $2 }' || true
  )"
  if [[ -z "$output" ]]; then
    run_key="unavailable"
    primary_key="unavailable"
    hot_key="unavailable"
  else
    IFS=$'\t' read -r run_key primary_key hot_key <<<"$output"
  fi

  case "${host}:${stage}" in
    vm-source:before)
      SOURCE_IDENTITY_BEFORE="$run_key"
      SOURCE_PRIMARY_TARGET_BEFORE="$primary_key"
      SOURCE_HOT_SPARE_BEFORE="$hot_key"
      ;;
    vm-destination:before)
      DESTINATION_IDENTITY_BEFORE="$run_key"
      DESTINATION_PRIMARY_TARGET_BEFORE="$primary_key"
      DESTINATION_HOT_SPARE_BEFORE="$hot_key"
      ;;
    vm-source:after)
      SOURCE_IDENTITY_AFTER="$run_key"
      SOURCE_PRIMARY_TARGET_AFTER="$primary_key"
      SOURCE_HOT_SPARE_AFTER="$hot_key"
      ;;
    vm-destination:after)
      DESTINATION_IDENTITY_AFTER="$run_key"
      DESTINATION_PRIMARY_TARGET_AFTER="$primary_key"
      DESTINATION_HOT_SPARE_AFTER="$hot_key"
      ;;
    *)
      echo "Unsupported host/stage for capture_host_identity_state: ${host}:${stage}" >&2
      exit 2
      ;;
  esac
}

sanitize_snapshot_output() {
  sed \
    -e 's/\r$//' \
    -e '/Permanently added .* to the list of known hosts\./d'
}

capture_single_host_catchup_snapshot() {
  local host="$1"
  local operator_host=""
  local operator_port=""
  local rpc_url="http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}"
  local output=""

  operator_host="$(vm_operator_host_for "$host")"
  operator_port="$(vm_operator_port_for "$host")"

  output="$(
    timeout 25s ssh $SSH_COMMON_ARGS \
      -o LogLevel=ERROR \
      -i "$SSH_PRIVATE_KEY_FILE" \
      -p "$operator_port" \
      "${VALIDATOR_OPERATOR_USER}@${operator_host}" \
      "export PATH='/opt/solana/active_release/bin:'\"\$PATH\"; timeout 20s solana catchup -u '$rpc_url' --our-localhost 8899" \
      2>&1 | sanitize_snapshot_output | sed -n '1,40p' || true
  )"

  if [[ -z "$output" ]]; then
    output="No catchup output captured."
  fi

  printf '%s\n' "$output"
}

capture_single_gossip_snapshot() {
  local rpc_url="http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}"
  local output=""

  output="$(
    solana gossip -u "$rpc_url" 2>&1 | sanitize_snapshot_output | sed -n '1,60p' || true
  )"

  if [[ -z "$output" ]]; then
    output="No gossip output captured."
  fi

  printf '%s\n' "$output"
}

capture_host_runtime_diagnostic_summary() {
  local host="$1"
  local cmd
  local output

  cmd="set -eu; active=\$(systemctl show sol --property=ActiveState --value --no-pager 2>/dev/null || printf 'unknown'); sub=\$(systemctl show sol --property=SubState --value --no-pager 2>/dev/null || printf 'unknown'); exec_status=\$(systemctl show sol --property=ExecMainStatus --value --no-pager 2>/dev/null || printf 'unknown'); pid=\$(systemctl show sol --property=MainPID --value --no-pager 2>/dev/null || printf 'unknown'); printf 'service=%s/%s/%s pid=%s\n' \"\$active\" \"\$sub\" \"\$exec_status\" \"\$pid\"; ident=\$(/opt/solana/active_release/bin/agave-validator -l /mnt/ledger contact-info 2>/dev/null | head -1 | sed 's/^Identity: //' || true); if [ -n \"\$ident\" ]; then printf 'ledger_identity=%s\n' \"\$ident\"; fi; printf -- '-- recent journal --\n'; journalctl -u sol -n 12 --no-pager 2>/dev/null | tail -n 12 || true; printf -- '\n-- validator log tail --\n'; tail -n 40 /opt/validator/logs/agave-validator.log 2>/dev/null | tail -n 40 || true"
  output="$(
    ansible "$host" -i "$OPERATOR_INVENTORY" -u "$VALIDATOR_OPERATOR_USER" -b \
      -m shell -a "$cmd" -o 2>&1 | awk -F' \\(stdout\\) ' 'NF > 1 { print $2 }' | sed 's/\\\\n/\
/g' || true
  )"

  if [[ -z "$output" ]]; then
    output="runtime diagnostic probe failed with no output"
  fi

  case "$host" in
    vm-source) HOST_DIAGNOSTIC_VM_SOURCE="$output" ;;
    vm-destination) HOST_DIAGNOSTIC_VM_DESTINATION="$output" ;;
  esac
}

capture_runtime_diagnostics_if_possible() {
  [[ -f "$OPERATOR_INVENTORY" ]] || return 0

  if [[ -z "$HOST_DIAGNOSTIC_VM_SOURCE" ]]; then
    capture_host_runtime_diagnostic_summary "vm-source" || true
  fi
  if [[ -z "$HOST_DIAGNOSTIC_VM_DESTINATION" ]]; then
    capture_host_runtime_diagnostic_summary "vm-destination" || true
  fi
}

capture_cluster_snapshots() {
  local stage="$1"
  local catchup_output=""
  local gossip_output=""

  if [[ "$SOLANA_CLUSTER_NORMALIZED" != "localnet" ]]; then
    catchup_output="Not captured for non-localnet cluster (${SOLANA_CLUSTER})."
    gossip_output="Not captured for non-localnet cluster (${SOLANA_CLUSTER})."
  else
    catchup_output="$(
      cat <<EOF
Source:
$(capture_single_host_catchup_snapshot "vm-source")

Destination:
$(capture_single_host_catchup_snapshot "vm-destination")
EOF
    )"
    gossip_output="$(capture_single_gossip_snapshot)"
  fi

  case "$stage" in
    before)
      CATCHUP_SNAPSHOT_BEFORE="${catchup_output:-No catchup output captured.}"
      GOSSIP_SNAPSHOT_BEFORE="${gossip_output:-No gossip output captured.}"
      ;;
    after)
      CATCHUP_SNAPSHOT_AFTER="${catchup_output:-No catchup output captured.}"
      GOSSIP_SNAPSHOT_AFTER="${gossip_output:-No gossip output captured.}"
      ;;
    *)
      echo "Unsupported stage for capture_cluster_snapshots: ${stage}" >&2
      exit 2
      ;;
  esac
}

emit_test_report() {
  local result="${1:-}"
  local report_file="$ARTIFACTS_DIR/test-report.txt"
  local json_report_file="$ARTIFACTS_DIR/test-report.json"
  if [[ -z "$result" ]]; then
    if [[ "$EXEC_OK" == "true" ]]; then
      result="PASS"
    else
      result="FAIL"
    fi
  fi
  TOTAL_DURATION_SEC=$(( $(date +%s) - SCRIPT_START_TS ))

  cat >"$report_file" <<EOF
============================================================
VM Hot Swap Test Report
============================================================
Run ID: ${RUN_ID}
Result: ${result}
Case: ${SOURCE_FLAVOR} -> ${DESTINATION_FLAVOR}
Cluster: ${SOLANA_CLUSTER}
City group: ${CITY_GROUP}
VM arch: ${VM_ARCH}
VM network mode: ${VM_NETWORK_MODE}

Environment
- Source SSH (bootstrap/post-metal): ${SOURCE_SSH_PORT} / ${SOURCE_SSH_PORT_ALT}
- Destination SSH (bootstrap/post-metal): ${DESTINATION_SSH_PORT} / ${DESTINATION_SSH_PORT_ALT}
- Localnet entrypoint mode: ${VM_LOCALNET_ENTRYPOINT_MODE}
- Pre-swap injection mode: ${PRE_SWAP_INJECTION_MODE}
- Localnet RPC: http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}
- Localnet gossip for VMs: ${VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS}:${VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT}
- Localnet genesis hash: ${LOCALNET_ENTRYPOINT_GENESIS_HASH:-unknown}

Phase Durations
- Users + metal-box setup: ${USERS_METAL_SETUP_DURATION_SEC}s
- Localnet entrypoint preflight: ${ENTRYPOINT_PREFLIGHT_DURATION_SEC}s
- Source flavor setup: ${SOURCE_SETUP_DURATION_SEC}s
- Destination flavor setup: ${DESTINATION_SETUP_DURATION_SEC}s
- Pre-swap verification: ${PRE_SWAP_VERIFY_DURATION_SEC}s
- Hot-swap execution: ${HOT_SWAP_DURATION_SEC}s
- Post-swap verification: ${POST_SWAP_VERIFY_DURATION_SEC}s
- Total runtime: ${TOTAL_DURATION_SEC}s

Checks Passed
- Source flavor setup completed
- Destination flavor setup completed
- Localnet entrypoint preflight (source VM): ${ENTRYPOINT_PREFLIGHT_VM_SOURCE}
- Localnet entrypoint preflight (destination VM): ${ENTRYPOINT_PREFLIGHT_VM_DESTINATION}
- Pre-swap runtime verification: ${PRE_SWAP_VERIFIED}
- Hot-swap playbook completed: ${HOT_SWAP_COMPLETED}
- Post-swap identity verification: ${SWAP_IDENTITY_VERIFIED}
- Post-swap runtime verification: ${POST_SWAP_VERIFIED}

Diagnosis
${REPORT_DIAGNOSIS:-No additional diagnosis captured.}

Localnet Entrypoint Reachability
- Source VM: ${ENTRYPOINT_PREFLIGHT_VM_SOURCE} (${ENTRYPOINT_PREFLIGHT_DETAILS_VM_SOURCE:-not checked})
- Destination VM: ${ENTRYPOINT_PREFLIGHT_VM_DESTINATION} (${ENTRYPOINT_PREFLIGHT_DETAILS_VM_DESTINATION:-not checked})

Identity State Before Swap
- Source runtime identity: ${SOURCE_IDENTITY_BEFORE:-not captured}
- Source primary-target-identity.json: ${SOURCE_PRIMARY_TARGET_BEFORE:-not captured}
- Source hot-spare-identity.json: ${SOURCE_HOT_SPARE_BEFORE:-not captured}
- Destination runtime identity: ${DESTINATION_IDENTITY_BEFORE:-not captured}
- Destination primary-target-identity.json: ${DESTINATION_PRIMARY_TARGET_BEFORE:-not captured}
- Destination hot-spare-identity.json: ${DESTINATION_HOT_SPARE_BEFORE:-not captured}

Identity State After Swap
- Source runtime identity: ${SOURCE_IDENTITY_AFTER:-not captured}
- Source primary-target-identity.json: ${SOURCE_PRIMARY_TARGET_AFTER:-not captured}
- Source hot-spare-identity.json: ${SOURCE_HOT_SPARE_AFTER:-not captured}
- Destination runtime identity: ${DESTINATION_IDENTITY_AFTER:-not captured}
- Destination primary-target-identity.json: ${DESTINATION_PRIMARY_TARGET_AFTER:-not captured}
- Destination hot-spare-identity.json: ${DESTINATION_HOT_SPARE_AFTER:-not captured}

Observed State
- Source service: ${HOST_SERVICE_VM_SOURCE:-not captured}
- Source version: ${HOST_VERSION_VM_SOURCE:-not captured}
- Destination service: ${HOST_SERVICE_VM_DESTINATION:-not captured}
- Destination version: ${HOST_VERSION_VM_DESTINATION:-not captured}

Runtime Diagnostics
Source:
${HOST_DIAGNOSTIC_VM_SOURCE:-not captured}

Destination:
${HOST_DIAGNOSTIC_VM_DESTINATION:-not captured}

Catchup Snapshots
Before Swap:
${CATCHUP_SNAPSHOT_BEFORE:-not captured}

After Swap:
${CATCHUP_SNAPSHOT_AFTER:-not captured}

Gossip Snapshots
Before Swap:
${GOSSIP_SNAPSHOT_BEFORE:-not captured}

After Swap:
${GOSSIP_SNAPSHOT_AFTER:-not captured}

Artifacts
- Case directory: ${CASE_DIR}
- Source QEMU log: ${SRC_QEMU_LOG}
- Destination QEMU log: ${DST_QEMU_LOG}
- Entrypoint VM QEMU log (vm mode): ${ENTRYPOINT_VM_QEMU_LOG:-not used}
- Entrypoint container engine: ${LOCALNET_ENTRYPOINT_ENGINE_RESOLVED:-not used}
- Entrypoint container name: ${LOCALNET_ENTRYPOINT_CONTAINER_NAME:-not used}
- Localnet entrypoint log: ${LOCALNET_ENTRYPOINT_LOG:-not used}
- Report file: ${report_file}
- JSON report file: ${json_report_file}
============================================================
EOF

  jq -n \
    --arg run_id "$RUN_ID" \
    --arg result "$result" \
    --arg source_flavor "$SOURCE_FLAVOR" \
    --arg destination_flavor "$DESTINATION_FLAVOR" \
    --arg cluster "$SOLANA_CLUSTER" \
    --arg city_group "$CITY_GROUP" \
    --arg vm_arch "$VM_ARCH" \
    --arg vm_network_mode "$VM_NETWORK_MODE" \
    --argjson users_metal_setup_duration_sec "$USERS_METAL_SETUP_DURATION_SEC" \
    --argjson entrypoint_preflight_duration_sec "$ENTRYPOINT_PREFLIGHT_DURATION_SEC" \
    --argjson source_setup_duration_sec "$SOURCE_SETUP_DURATION_SEC" \
    --argjson destination_setup_duration_sec "$DESTINATION_SETUP_DURATION_SEC" \
    --argjson pre_swap_verify_duration_sec "$PRE_SWAP_VERIFY_DURATION_SEC" \
    --argjson hot_swap_duration_sec "$HOT_SWAP_DURATION_SEC" \
    --argjson post_swap_verify_duration_sec "$POST_SWAP_VERIFY_DURATION_SEC" \
    --argjson total_duration_sec "$TOTAL_DURATION_SEC" \
    --argjson entrypoint_preflight_vm_source "$ENTRYPOINT_PREFLIGHT_VM_SOURCE" \
    --argjson entrypoint_preflight_vm_destination "$ENTRYPOINT_PREFLIGHT_VM_DESTINATION" \
    --argjson pre_swap_verified "$PRE_SWAP_VERIFIED" \
    --argjson hot_swap_completed "$HOT_SWAP_COMPLETED" \
    --argjson swap_identity_verified "$SWAP_IDENTITY_VERIFIED" \
    --argjson post_swap_verified "$POST_SWAP_VERIFIED" \
    --arg source_ssh_port "$SOURCE_SSH_PORT" \
    --arg source_ssh_port_alt "$SOURCE_SSH_PORT_ALT" \
    --arg destination_ssh_port "$DESTINATION_SSH_PORT" \
    --arg destination_ssh_port_alt "$DESTINATION_SSH_PORT_ALT" \
    --arg localnet_entrypoint_mode "$VM_LOCALNET_ENTRYPOINT_MODE" \
    --arg pre_swap_injection_mode "$PRE_SWAP_INJECTION_MODE" \
    --arg localnet_rpc_url "http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}" \
    --arg localnet_gossip_endpoint "${VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS}:${VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT}" \
    --arg localnet_genesis_hash "${LOCALNET_ENTRYPOINT_GENESIS_HASH:-unknown}" \
    --arg entrypoint_preflight_details_vm_source "${ENTRYPOINT_PREFLIGHT_DETAILS_VM_SOURCE:-not checked}" \
    --arg entrypoint_preflight_details_vm_destination "${ENTRYPOINT_PREFLIGHT_DETAILS_VM_DESTINATION:-not checked}" \
    --arg host_service_vm_source "${HOST_SERVICE_VM_SOURCE:-not captured}" \
    --arg host_version_vm_source "${HOST_VERSION_VM_SOURCE:-not captured}" \
    --arg host_diagnostic_vm_source "${HOST_DIAGNOSTIC_VM_SOURCE:-not captured}" \
    --arg host_service_vm_destination "${HOST_SERVICE_VM_DESTINATION:-not captured}" \
    --arg host_version_vm_destination "${HOST_VERSION_VM_DESTINATION:-not captured}" \
    --arg host_diagnostic_vm_destination "${HOST_DIAGNOSTIC_VM_DESTINATION:-not captured}" \
    --arg source_identity_before "${SOURCE_IDENTITY_BEFORE:-not captured}" \
    --arg source_primary_target_before "${SOURCE_PRIMARY_TARGET_BEFORE:-not captured}" \
    --arg source_hot_spare_before "${SOURCE_HOT_SPARE_BEFORE:-not captured}" \
    --arg destination_identity_before "${DESTINATION_IDENTITY_BEFORE:-not captured}" \
    --arg destination_primary_target_before "${DESTINATION_PRIMARY_TARGET_BEFORE:-not captured}" \
    --arg destination_hot_spare_before "${DESTINATION_HOT_SPARE_BEFORE:-not captured}" \
    --arg source_identity_after "${SOURCE_IDENTITY_AFTER:-not captured}" \
    --arg source_primary_target_after "${SOURCE_PRIMARY_TARGET_AFTER:-not captured}" \
    --arg source_hot_spare_after "${SOURCE_HOT_SPARE_AFTER:-not captured}" \
    --arg destination_identity_after "${DESTINATION_IDENTITY_AFTER:-not captured}" \
    --arg destination_primary_target_after "${DESTINATION_PRIMARY_TARGET_AFTER:-not captured}" \
    --arg destination_hot_spare_after "${DESTINATION_HOT_SPARE_AFTER:-not captured}" \
    --arg catchup_snapshot_before "${CATCHUP_SNAPSHOT_BEFORE:-not captured}" \
    --arg catchup_snapshot_after "${CATCHUP_SNAPSHOT_AFTER:-not captured}" \
    --arg gossip_snapshot_before "${GOSSIP_SNAPSHOT_BEFORE:-not captured}" \
    --arg gossip_snapshot_after "${GOSSIP_SNAPSHOT_AFTER:-not captured}" \
    --arg report_diagnosis "${REPORT_DIAGNOSIS:-No additional diagnosis captured.}" \
    --arg case_dir "$CASE_DIR" \
    --arg source_qemu_log "$SRC_QEMU_LOG" \
    --arg destination_qemu_log "$DST_QEMU_LOG" \
    --arg entrypoint_vm_qemu_log "${ENTRYPOINT_VM_QEMU_LOG:-not used}" \
    --arg entrypoint_container_engine "${LOCALNET_ENTRYPOINT_ENGINE_RESOLVED:-not used}" \
    --arg entrypoint_container_name "${LOCALNET_ENTRYPOINT_CONTAINER_NAME:-not used}" \
    --arg localnet_entrypoint_log "${LOCALNET_ENTRYPOINT_LOG:-not used}" \
    --arg text_report_file "$report_file" \
    --arg json_report_file "$json_report_file" \
    '{
      run_id: $run_id,
      result: $result,
      case: {
        source_flavor: $source_flavor,
        destination_flavor: $destination_flavor
      },
      environment: {
        cluster: $cluster,
        city_group: $city_group,
        vm_arch: $vm_arch,
        vm_network_mode: $vm_network_mode,
        ssh_ports: {
          source: {
            bootstrap: $source_ssh_port,
            post_metal: $source_ssh_port_alt
          },
          destination: {
            bootstrap: $destination_ssh_port,
            post_metal: $destination_ssh_port_alt
          }
        },
        localnet_entrypoint: {
          mode: $localnet_entrypoint_mode,
          pre_swap_injection_mode: $pre_swap_injection_mode,
          rpc_url: $localnet_rpc_url,
          gossip_endpoint_for_vms: $localnet_gossip_endpoint,
          genesis_hash: $localnet_genesis_hash
        }
      },
      durations_sec: {
        users_metal_setup: $users_metal_setup_duration_sec,
        localnet_entrypoint_preflight: $entrypoint_preflight_duration_sec,
        source_setup: $source_setup_duration_sec,
        destination_setup: $destination_setup_duration_sec,
        pre_swap_verify: $pre_swap_verify_duration_sec,
        hot_swap: $hot_swap_duration_sec,
        post_swap_verify: $post_swap_verify_duration_sec,
        total: $total_duration_sec
      },
      checks_passed: {
        localnet_entrypoint_preflight_source: $entrypoint_preflight_vm_source,
        localnet_entrypoint_preflight_destination: $entrypoint_preflight_vm_destination,
        pre_swap_runtime_and_client: $pre_swap_verified,
        hot_swap_playbook_completed: $hot_swap_completed,
        post_swap_identity: $swap_identity_verified,
        post_swap_runtime_and_client: $post_swap_verified
      },
      localnet_entrypoint_reachability: {
        source: {
          ok: $entrypoint_preflight_vm_source,
          checked_endpoints: $entrypoint_preflight_details_vm_source
        },
        destination: {
          ok: $entrypoint_preflight_vm_destination,
          checked_endpoints: $entrypoint_preflight_details_vm_destination
        }
      },
      identities: {
        before: {
          source: {
            identity: $source_identity_before,
            primary_target_identity: $source_primary_target_before,
            hot_spare_identity: $source_hot_spare_before
          },
          destination: {
            identity: $destination_identity_before,
            primary_target_identity: $destination_primary_target_before,
            hot_spare_identity: $destination_hot_spare_before
          }
        },
        after: {
          source: {
            identity: $source_identity_after,
            primary_target_identity: $source_primary_target_after,
            hot_spare_identity: $source_hot_spare_after
          },
          destination: {
            identity: $destination_identity_after,
            primary_target_identity: $destination_primary_target_after,
            hot_spare_identity: $destination_hot_spare_after
          }
        }
      },
      observed_state: {
        source: {
          service: $host_service_vm_source,
          version: $host_version_vm_source,
          runtime_diagnostic: $host_diagnostic_vm_source
        },
        destination: {
          service: $host_service_vm_destination,
          version: $host_version_vm_destination,
          runtime_diagnostic: $host_diagnostic_vm_destination
        }
      },
      diagnosis: $report_diagnosis,
      cluster_snapshots: {
        catchup: {
          before: $catchup_snapshot_before,
          after: $catchup_snapshot_after
        },
        gossip: {
          before: $gossip_snapshot_before,
          after: $gossip_snapshot_after
        }
      },
      artifacts: {
        case_dir: $case_dir,
        source_qemu_log: $source_qemu_log,
        destination_qemu_log: $destination_qemu_log,
        entrypoint_vm_qemu_log: $entrypoint_vm_qemu_log,
        entrypoint_container_engine: $entrypoint_container_engine,
        entrypoint_container_name: $entrypoint_container_name,
        localnet_entrypoint_log: $localnet_entrypoint_log,
        text_report_file: $text_report_file,
        json_report_file: $json_report_file
      }
    }' >"$json_report_file"

  echo "[vm-hot-swap] Wrote reports:" >&2
  echo "[vm-hot-swap]   text: $report_file" >&2
  echo "[vm-hot-swap]   json: $json_report_file" >&2
  echo "[vm-hot-swap] --- Begin test report ---" >&2
  cat "$report_file" >&2
  echo "[vm-hot-swap] --- End test report ---" >&2
  REPORT_EMITTED=true
}

if [[ "$PREPARED_VM_REUSE_MODE" == "true" ]]; then
  echo "[vm-hot-swap] Prepared VM reuse: skipping source/destination flavor setup (already baked into prepared disks)." >&2
  assert_vm_alive_and_ssh_ready "source" "$SOURCE_OPERATOR_HOST_EFFECTIVE" "$SOURCE_OPERATOR_PORT_EFFECTIVE" "$SRC_PID_FILE" "$SRC_QEMU_LOG" 180
  assert_vm_alive_and_ssh_ready "destination" "$DESTINATION_OPERATOR_HOST_EFFECTIVE" "$DESTINATION_OPERATOR_PORT_EFFECTIVE" "$DST_PID_FILE" "$DST_QEMU_LOG" 180
  if [[ "$SOLANA_CLUSTER_NORMALIZED" == "localnet" ]]; then
    echo "[vm-hot-swap] Prepared VM reuse: aligning validator expected genesis hash to ${LOCALNET_ENTRYPOINT_GENESIS_HASH}..." >&2
    sync_host_expected_genesis_hash "vm-source"
    sync_host_expected_genesis_hash "vm-destination"
  fi
  echo "[vm-hot-swap] Prepared VM reuse: waiting for validator RPC warmup..." >&2
  wait_for_host_validator_runtime_ready "vm-source" "$REUSE_RUNTIME_READY_TIMEOUT_SEC"
  wait_for_host_validator_runtime_ready "vm-destination" "$REUSE_RUNTIME_READY_TIMEOUT_SEC"
  echo "[vm-hot-swap] Prepared VM reuse: promoting source runtime identity to primary..." >&2
  promote_host_runtime_identity_to_primary "vm-source"
  SOURCE_SETUP_DURATION_SEC=0
  DESTINATION_SETUP_DURATION_SEC=0
else
  phase_start_ts="$(date +%s)"
  CURRENT_PHASE="configure source flavor"
  echo "[vm-hot-swap] Configuring source flavor: $SOURCE_FLAVOR" >&2
  assert_vm_alive_and_ssh_ready "source" "$SOURCE_OPERATOR_HOST_EFFECTIVE" "$SOURCE_OPERATOR_PORT_EFFECTIVE" "$SRC_PID_FILE" "$SRC_QEMU_LOG" 180
  ensure_localnet_entrypoint
  setup_host_flavor "vm-source" "$SOURCE_FLAVOR" "primary"
  assert_host_can_query_localnet_entrypoint "vm-source" "source"
  assert_host_validator_runtime "vm-source"
  echo "[vm-hot-swap] Promoting source runtime identity to primary..." >&2
  promote_host_runtime_identity_to_primary "vm-source"
  SOURCE_SETUP_DURATION_SEC=$(( $(date +%s) - phase_start_ts ))

  phase_start_ts="$(date +%s)"
  CURRENT_PHASE="configure destination flavor"
  echo "[vm-hot-swap] Configuring destination flavor: $DESTINATION_FLAVOR" >&2
  assert_vm_alive_and_ssh_ready "destination" "$DESTINATION_OPERATOR_HOST_EFFECTIVE" "$DESTINATION_OPERATOR_PORT_EFFECTIVE" "$DST_PID_FILE" "$DST_QEMU_LOG" 180
  ensure_localnet_entrypoint
  setup_host_flavor "vm-destination" "$DESTINATION_FLAVOR" "hot-spare"
  assert_host_can_query_localnet_entrypoint "vm-destination" "destination"
  DESTINATION_SETUP_DURATION_SEC=$(( $(date +%s) - phase_start_ts ))
fi

if [[ "$SOLANA_VALIDATOR_HA_RUNTIME_ENABLED" == "true" ]]; then
  CURRENT_PHASE="ha cluster reconcile"
  echo "[vm-hot-swap] Reconciling HA runtime across ${SOLANA_VALIDATOR_HA_RECONCILE_GROUP}..." >&2
  reconcile_validator_ha_cluster
  assert_host_ha_runtime_config "vm-source" "$SOLANA_VALIDATOR_HA_SOURCE_NODE_ID" "$SOLANA_VALIDATOR_HA_SOURCE_PRIORITY" "$SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID" "${VM_DESTINATION_BRIDGE_IP:-$DESTINATION_OPERATOR_HOST_EFFECTIVE}" "$SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY"
  assert_host_ha_runtime_config "vm-destination" "$SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID" "$SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY" "$SOLANA_VALIDATOR_HA_SOURCE_NODE_ID" "${VM_SOURCE_BRIDGE_IP:-$SOURCE_OPERATOR_HOST_EFFECTIVE}" "$SOLANA_VALIDATOR_HA_SOURCE_PRIORITY"
fi

phase_start_ts="$(date +%s)"
CURRENT_PHASE="pre-swap verification"
apply_pre_swap_injection
echo "[vm-hot-swap] Capturing pre-swap identity state..." >&2
capture_host_identity_state "vm-source" "before"
capture_host_identity_state "vm-destination" "before"

echo "[vm-hot-swap] Verifying pre-swap flavors..." >&2
assert_host_validator_runtime "vm-source"
assert_host_validator_runtime "vm-destination"
capture_host_runtime_diagnostic_summary "vm-source"
capture_host_runtime_diagnostic_summary "vm-destination"
assert_host_client "vm-source" "$SOURCE_FLAVOR"
assert_host_client "vm-destination" "$DESTINATION_FLAVOR"
echo "[vm-hot-swap] Waiting for validators to finish catchup..." >&2
wait_for_host_validator_catchup "vm-source"
wait_for_host_validator_catchup "vm-destination"
echo "[vm-hot-swap] Waiting for source validator tower file..." >&2
wait_for_source_tower_file
capture_cluster_snapshots "before"
PRE_SWAP_VERIFIED=true
PRE_SWAP_VERIFY_DURATION_SEC=$(( $(date +%s) - phase_start_ts ))

if [[ "$VM_PREPARE_ONLY" == "true" ]]; then
  CURRENT_PHASE="prepare export"
  export_prepared_vm_disks "$VM_PREPARE_EXPORT_DIR"
  EXEC_OK=true
  emit_test_report
  echo "[vm-hot-swap] Prepare-only run completed successfully." >&2
  exit 0
fi

if [[ "$VM_MANUAL_TEST_ONLY" == "true" ]]; then
  CURRENT_PHASE="manual testing"
  REPORT_DIAGNOSIS="Manual cluster is ready; hot-swap playbook intentionally skipped."
  EXEC_OK=true
  emit_test_report
  echo "[vm-hot-swap] Manual-test-only run completed successfully." >&2
  echo "[vm-hot-swap] Case directory: $CASE_DIR" >&2
  echo "[vm-hot-swap] Bootstrap inventory: $BOOTSTRAP_INVENTORY" >&2
  echo "[vm-hot-swap] Operator inventory: $OPERATOR_INVENTORY" >&2
  echo "[vm-hot-swap] Entrypoint RPC: http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}" >&2
  exit 0
fi

phase_start_ts="$(date +%s)"
CURRENT_PHASE="hot-swap"
echo "[vm-hot-swap] Running hot-swap playbook..." >&2
ensure_localnet_entrypoint
ansible-playbook \
  -i "$OPERATOR_INVENTORY" \
  "$REPO_ROOT/ansible/playbooks/pb_hot_swap_validator_hosts_v2.yml" \
  "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
  -e "source_host=vm-source" \
  -e "destination_host=vm-destination" \
  -e "operator_user=$VALIDATOR_OPERATOR_USER" \
  -e "auto_confirm_swap=true" \
  -e "deprovision_source_host=false" \
  -e "swap_epoch_end_threshold_sec=$SWAP_EPOCH_END_THRESHOLD_SEC"
HOT_SWAP_COMPLETED=true
HOT_SWAP_DURATION_SEC=$(( $(date +%s) - phase_start_ts ))

phase_start_ts="$(date +%s)"
CURRENT_PHASE="post-swap verification"
echo "[vm-hot-swap] Verifying post-swap identity state..." >&2
assert_swap_identity_state
capture_host_identity_state "vm-source" "after"
capture_host_identity_state "vm-destination" "after"

echo "[vm-hot-swap] Verifying post-swap flavors..." >&2
assert_host_validator_runtime "vm-source"
assert_host_validator_runtime "vm-destination"
capture_host_runtime_diagnostic_summary "vm-source"
capture_host_runtime_diagnostic_summary "vm-destination"
assert_host_client "vm-source" "$SOURCE_FLAVOR"
assert_host_client "vm-destination" "$DESTINATION_FLAVOR"
POST_SWAP_VERIFIED=true
capture_cluster_snapshots "after"
POST_SWAP_VERIFY_DURATION_SEC=$(( $(date +%s) - phase_start_ts ))

EXEC_OK=true
emit_test_report
echo "[vm-hot-swap] Case completed successfully: $SOURCE_FLAVOR -> $DESTINATION_FLAVOR" >&2

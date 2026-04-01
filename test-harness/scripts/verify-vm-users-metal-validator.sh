#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

INVENTORY_PATH=""
TARGET_HOST="${TARGET_HOST:-vm-local}"
FLAVOR="${FLAVOR:-agave}"

BOOTSTRAP_USER="${BOOTSTRAP_USER:-}"
METAL_BOX_SYSADMIN_USER="${METAL_BOX_SYSADMIN_USER:-alice}"
VALIDATOR_OPERATOR_USER="${VALIDATOR_OPERATOR_USER:-bob}"
SOLANA_CLUSTER="${SOLANA_CLUSTER:-localnet}"
SOLANA_CLUSTER_NORMALIZED="${SOLANA_CLUSTER#solana_}"
SOLANA_CLUSTER_VARS_FILE="${SOLANA_CLUSTER_VARS_FILE:-$REPO_ROOT/ansible/group_vars/solana_${SOLANA_CLUSTER_NORMALIZED}.yml}"
CITY_GROUP="${CITY_GROUP:-city_dal}"
CITY_GROUP_VARS_FILE="${CITY_GROUP_VARS_FILE:-$REPO_ROOT/ansible/group_vars/${CITY_GROUP}.yml}"
VALIDATOR_NAME="${VALIDATOR_NAME:-vm-validator}"
VALIDATOR_TYPE="${VALIDATOR_TYPE:-primary}"
POST_METAL_SSH_PORT="${POST_METAL_SSH_PORT:-2522}"

AGAVE_VERSION="${AGAVE_VERSION:-3.1.10}"
JITO_VERSION="${JITO_VERSION:-2.3.6}"
BAM_JITO_VERSION="${BAM_JITO_VERSION:-3.1.10}"
BAM_JITO_VERSION_PATCH="${BAM_JITO_VERSION_PATCH:-}"

BUILD_FROM_SOURCE="${BUILD_FROM_SOURCE:-false}"
FORCE_HOST_CLEANUP="${FORCE_HOST_CLEANUP:-true}"
SKIP_CONFIRMATION_PAUSES="${SKIP_CONFIRMATION_PAUSES:-true}"
VM_AUTHORIZED_IP="${VM_AUTHORIZED_IP:-10.0.2.2}"
OPERATOR_SSH_PUBLIC_KEY_FILE="${OPERATOR_SSH_PUBLIC_KEY_FILE:-}"
SSH_COMMON_ARGS="${SSH_COMMON_ARGS:--o IdentitiesOnly=yes -o IdentityAgent=none -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no}"
ENABLE_VM_TEST_SYSADMIN_NOPASSWD="${ENABLE_VM_TEST_SYSADMIN_NOPASSWD:-true}"
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

usage() {
  cat <<'EOF'
Usage:
  verify-vm-users-metal-validator.sh --inventory <path> [options]

Required:
  --inventory <path>

Optional:
  --target-host <name>                  (default: vm-local)
  --flavor <agave|jito-shared|jito-cohosted|jito-bam>   (default: agave)
  --bootstrap-user <name>               (default: inventory ansible_user or ubuntu)
  --validator-operator-user <name>      (default: bob)
  --post-metal-ssh-port <int>           (default: 2522)
  --validator-name <name>               (default: vm-validator)
  --operator-ssh-public-key-file <path> (default: <inventory_private_key>.pub)
EOF
}

while (($# > 0)); do
  case "$1" in
    --inventory)
      INVENTORY_PATH="${2:-}"
      shift 2
      ;;
    --target-host)
      TARGET_HOST="${2:-}"
      shift 2
      ;;
    --flavor)
      FLAVOR="${2:-}"
      shift 2
      ;;
    --bootstrap-user)
      BOOTSTRAP_USER="${2:-}"
      shift 2
      ;;
    --validator-operator-user)
      VALIDATOR_OPERATOR_USER="${2:-}"
      shift 2
      ;;
    --post-metal-ssh-port)
      POST_METAL_SSH_PORT="${2:-}"
      shift 2
      ;;
    --validator-name)
      VALIDATOR_NAME="${2:-}"
      shift 2
      ;;
    --operator-ssh-public-key-file)
      OPERATOR_SSH_PUBLIC_KEY_FILE="${2:-}"
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

if [[ -z "$INVENTORY_PATH" ]]; then
  usage
  exit 2
fi

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    case "$cmd" in
      solana|solana-keygen|solana-test-validator)
        echo "Missing required command: $cmd" >&2
        echo "This VM verifier requires Solana CLI tools on the host PATH for localnet entrypoint operations." >&2
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

resolve_path() {
  local p="$1"
  local base="${2:-}"
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
    return 0
  fi
  if [[ -n "$base" ]]; then
    printf '%s/%s\n' "$base" "$p"
    return 0
  fi
  printf '%s\n' "$p"
}

LOCALNET_ENTRYPOINT_PID_FILE=""
LOCALNET_ENTRYPOINT_LOG=""
LOCALNET_ENTRYPOINT_STARTED_BY_SCRIPT=false
LOCALNET_ENTRYPOINT_GENESIS_HASH=""

is_tcp_port_listening() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1
}

localnet_rpc_ready() {
  local rpc_url="$1"
  solana -u "$rpc_url" genesis-hash >/dev/null 2>&1
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
  local pid cmd
  for pid in $(listener_pids_for_port "$port"); do
    cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if grep -q "solana-test-validator" <<<"$cmd"; then
      echo "[vm-e2e] Stopping stale solana-test-validator listener on port ${port} (pid=${pid})" >&2
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
  done
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

ensure_localnet_entrypoint() {
  if [[ "$SOLANA_CLUSTER_NORMALIZED" != "localnet" ]]; then
    return 0
  fi

  require_cmd solana

  local rpc_url="http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}"
  local rpc_port="$VM_LOCALNET_ENTRYPOINT_RPC_PORT"
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
    echo "[vm-e2e] Reusing healthy localnet entrypoint at ${rpc_url}" >&2
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
    echo "[vm-e2e] Starting localnet entrypoint via solana-test-validator at ${rpc_url} ..." >&2
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
          echo "[vm-e2e] Last entrypoint log lines:" >&2
          tail -n 120 "$LOCALNET_ENTRYPOINT_LOG" >&2 || true
        fi
        exit 4
      fi
    fi
    tries=$((tries + 1))
    if ((tries > 120)); then
      echo "Localnet entrypoint at ${rpc_url} did not become ready in time." >&2
      if [[ -n "$LOCALNET_ENTRYPOINT_LOG" && -f "$LOCALNET_ENTRYPOINT_LOG" ]]; then
        echo "[vm-e2e] Last entrypoint log lines:" >&2
        tail -n 80 "$LOCALNET_ENTRYPOINT_LOG" >&2 || true
      fi
      exit 4
    fi
    sleep 1
  done

  LOCALNET_ENTRYPOINT_GENESIS_HASH="$(solana -u "$rpc_url" genesis-hash)"
  COMMON_ANSIBLE_EXTRA_VARS_ARGS+=(-e "expected_genesis_hash=$LOCALNET_ENTRYPOINT_GENESIS_HASH")
}

cleanup() {
  stop_localnet_entrypoint_if_started
}
trap cleanup EXIT

require_cmd ansible-playbook
require_cmd ansible-inventory
require_cmd jq
require_cmd ssh-keygen

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
    auto|external) ;;
    *)
      echo "Unsupported VM_LOCALNET_ENTRYPOINT_MODE: $VM_LOCALNET_ENTRYPOINT_MODE (expected: auto|external)" >&2
      exit 2
      ;;
  esac
  COMMON_ANSIBLE_EXTRA_VARS_ARGS+=(
    -e "solana_rpc_url=http://${VM_LOCALNET_ENTRYPOINT_RPC_HOST}:${VM_LOCALNET_ENTRYPOINT_RPC_PORT}"
    -e "{\"solana_gossip_entrypoints\":[\"${VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS}:${VM_LOCALNET_ENTRYPOINT_GOSSIP_PORT}\"]}"
  )
fi

CPU_GOVERNOR_MANAGE="true"
if [[ "$VM_DISABLE_CPU_GOVERNOR_SERVICE" == "true" ]]; then
  CPU_GOVERNOR_MANAGE="false"
fi

INVENTORY_PATH="$(resolve_path "$INVENTORY_PATH" "$(pwd)")"
if [[ ! -f "$INVENTORY_PATH" ]]; then
  echo "Inventory file not found: $INVENTORY_PATH" >&2
  exit 2
fi

host_json="$(ansible-inventory -i "$INVENTORY_PATH" --host "$TARGET_HOST")"
VM_HOST="$(jq -r '.ansible_host // "127.0.0.1"' <<<"$host_json")"
BOOTSTRAP_SSH_PORT="$(jq -r '.ansible_port // 22' <<<"$host_json")"
if [[ -z "$BOOTSTRAP_USER" ]]; then
  BOOTSTRAP_USER="$(jq -r '.ansible_user // "ubuntu"' <<<"$host_json")"
fi
VM_SSH_PRIVATE_KEY_FILE="$(jq -r '.ansible_ssh_private_key_file // empty' <<<"$host_json")"
if [[ -z "$VM_SSH_PRIVATE_KEY_FILE" ]]; then
  echo "ansible_ssh_private_key_file is required in inventory host '$TARGET_HOST'" >&2
  exit 2
fi

INV_DIR="$(cd "$(dirname "$INVENTORY_PATH")" && pwd)"
VM_SSH_PRIVATE_KEY_FILE="$(resolve_path "$VM_SSH_PRIVATE_KEY_FILE" "$INV_DIR")"
if [[ ! -r "$VM_SSH_PRIVATE_KEY_FILE" ]]; then
  echo "Private key not readable: $VM_SSH_PRIVATE_KEY_FILE" >&2
  exit 2
fi

if [[ -n "$OPERATOR_SSH_PUBLIC_KEY_FILE" ]]; then
  OPERATOR_SSH_PUBLIC_KEY_FILE="$(resolve_path "$OPERATOR_SSH_PUBLIC_KEY_FILE" "$(pwd)")"
fi
if [[ -z "$OPERATOR_SSH_PUBLIC_KEY_FILE" ]]; then
  if [[ -r "${VM_SSH_PRIVATE_KEY_FILE}.pub" ]]; then
    OPERATOR_SSH_PUBLIC_KEY_FILE="${VM_SSH_PRIVATE_KEY_FILE}.pub"
  fi
fi

if [[ -n "$OPERATOR_SSH_PUBLIC_KEY_FILE" && -r "$OPERATOR_SSH_PUBLIC_KEY_FILE" ]]; then
  OPERATOR_SSH_PUBLIC_KEY="$(cat "$OPERATOR_SSH_PUBLIC_KEY_FILE")"
else
  OPERATOR_SSH_PUBLIC_KEY="$(ssh-keygen -y -f "$VM_SSH_PRIVATE_KEY_FILE")"
fi

WORK_DIR="${VM_VERIFY_WORK_DIR:-$INV_DIR/vm-e2e}"
mkdir -p "$WORK_DIR"
LOCALNET_ENTRYPOINT_PID_FILE="$WORK_DIR/localnet-entrypoint.pid"
LOCALNET_ENTRYPOINT_LOG="$WORK_DIR/localnet-entrypoint.log"

IAM_CSV="$WORK_DIR/iam_setup_vm_validator.csv"
AUTHORIZED_IPS_CSV="$WORK_DIR/authorized_ips_vm.csv"
BOOTSTRAP_INVENTORY="$WORK_DIR/inventory.bootstrap.yml"
OPERATOR_INVENTORY="$WORK_DIR/inventory.operator.yml"

cat >"$IAM_CSV" <<EOF
user,key,group_a,group_b,group_c
alice,${OPERATOR_SSH_PUBLIC_KEY},sysadmin,,
${VALIDATOR_OPERATOR_USER},${OPERATOR_SSH_PUBLIC_KEY},validator_operators,,
carla,${OPERATOR_SSH_PUBLIC_KEY},validator_viewers,,
sol,,,,
EOF

cat >"$AUTHORIZED_IPS_CSV" <<EOF
ip,comment
${VM_AUTHORIZED_IP},Host (QEMU user-mode NAT)
EOF

cat >"$BOOTSTRAP_INVENTORY" <<EOF
all:
  hosts:
    ${TARGET_HOST}:
      ansible_host: ${VM_HOST}
      ansible_port: ${BOOTSTRAP_SSH_PORT}
      ansible_user: ${BOOTSTRAP_USER}
      ansible_ssh_private_key_file: ${VM_SSH_PRIVATE_KEY_FILE}
      ansible_ssh_common_args: "${SSH_COMMON_ARGS}"
      ansible_become: true
  children:
    ${CITY_GROUP}:
      hosts:
        ${TARGET_HOST}:
    solana:
      hosts:
        ${TARGET_HOST}:
    solana_localnet:
      hosts:
        ${TARGET_HOST}:
EOF

cat >"$OPERATOR_INVENTORY" <<EOF
all:
  hosts:
    ${TARGET_HOST}:
      ansible_host: ${VM_HOST}
      ansible_port: ${POST_METAL_SSH_PORT}
      ansible_user: ${VALIDATOR_OPERATOR_USER}
      ansible_ssh_private_key_file: ${VM_SSH_PRIVATE_KEY_FILE}
      ansible_ssh_common_args: "${SSH_COMMON_ARGS}"
      ansible_become: true
  children:
    ${CITY_GROUP}:
      hosts:
        ${TARGET_HOST}:
    solana:
      hosts:
        ${TARGET_HOST}:
    solana_localnet:
      hosts:
        ${TARGET_HOST}:
EOF

ensure_localnet_entrypoint

echo "[vm-e2e] Running shared host bootstrap flow..." >&2
if [[ "$ENABLE_VM_TEST_SYSADMIN_NOPASSWD" == "true" ]]; then
  echo "[vm-e2e] Preparing temporary sysadmin sudo policy for VM automation..." >&2
  echo "[vm-e2e] Preparing temporary sysadmin sudo policy on ${TARGET_HOST}..." >&2
  ansible-playbook \
    -i "$BOOTSTRAP_INVENTORY" \
    "$REPO_ROOT/test-harness/ansible/pb_prepare_vm_sysadmin_nopasswd.yml" \
    -e "target_hosts=$TARGET_HOST" \
    -e "bootstrap_user=$BOOTSTRAP_USER"
fi

setup_common_args=(
  -i "$BOOTSTRAP_INVENTORY"
  --limit "$TARGET_HOST"
  --skip-tags "$VM_METAL_BOX_SKIP_TAGS"
  "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}"
  -e "target_host=$TARGET_HOST"
  -e "bootstrap_user=$BOOTSTRAP_USER"
  -e "metal_box_user=$METAL_BOX_SYSADMIN_USER"
  -e "validator_operator_user=$VALIDATOR_OPERATOR_USER"
  -e "validator_name=$VALIDATOR_NAME"
  -e "validator_type=$VALIDATOR_TYPE"
  -e "password_handoff_mode=assume_ready"
  -e "xdp_enabled=true"
  -e "solana_cluster=$SOLANA_CLUSTER"
  -e "build_from_source=$BUILD_FROM_SOURCE"
  -e "force_host_cleanup=$FORCE_HOST_CLEANUP"
  -e "manage_cpu_governor_service=$CPU_GOVERNOR_MANAGE"
  -e "post_metal_ssh_port=$POST_METAL_SSH_PORT"
  -e "users_csv_file=$(basename "$IAM_CSV")"
  -e "users_base_dir=$(dirname "$IAM_CSV")"
  -e "authorized_ips_csv_file=$(basename "$AUTHORIZED_IPS_CSV")"
  -e "authorized_access_csv=$AUTHORIZED_IPS_CSV"
  -e "skip_confirmation_pauses=$SKIP_CONFIRMATION_PAUSES"
)

echo "[vm-e2e] Running validator setup flavor through shared flow: $FLAVOR..." >&2
case "$FLAVOR" in
  agave)
    ansible-playbook \
      "${setup_common_args[@]}" \
      -e "validator_flavor=agave" \
      -e "agave_version=$AGAVE_VERSION" \
      "$REPO_ROOT/ansible/playbooks/pb_setup_validator_host_common.yml"
    ;;
  jito-shared)
    ansible-playbook \
      "${setup_common_args[@]}" \
      -e "validator_flavor=jito-bam" \
      -e "jito_version=$JITO_VERSION" \
      "$REPO_ROOT/ansible/playbooks/pb_setup_validator_host_common.yml"
    ;;
  jito-cohosted)
    ansible-playbook \
      "${setup_common_args[@]}" \
      -e "validator_flavor=jito-bam" \
      -e "jito_version=$JITO_VERSION" \
      "$REPO_ROOT/ansible/playbooks/pb_setup_validator_host_common.yml"
    ;;
  jito-bam)
    if [[ -n "$BAM_JITO_VERSION_PATCH" ]]; then
      ansible-playbook \
        "${setup_common_args[@]}" \
        -e "validator_flavor=jito-bam" \
        -e "jito_version=$BAM_JITO_VERSION" \
        -e "jito_version_patch=$BAM_JITO_VERSION_PATCH" \
        "$REPO_ROOT/ansible/playbooks/pb_setup_validator_host_common.yml"
    else
      ansible-playbook \
        "${setup_common_args[@]}" \
        -e "validator_flavor=jito-bam" \
        -e "jito_version=$BAM_JITO_VERSION" \
        "$REPO_ROOT/ansible/playbooks/pb_setup_validator_host_common.yml"
    fi
    ;;
  *)
    echo "Unsupported flavor: $FLAVOR" >&2
    exit 2
    ;;
esac

echo "[vm-e2e] Sequence completed: pb_setup_users_validator -> pb_setup_metal_box -> validator setup -> ha install" >&2

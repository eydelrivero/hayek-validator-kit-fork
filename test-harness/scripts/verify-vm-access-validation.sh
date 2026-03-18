#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

INVENTORY_PATH=""
TARGET_HOST="${TARGET_HOST:-vm-local}"
BOOTSTRAP_USER="${BOOTSTRAP_USER:-}"
METAL_BOX_SYSADMIN_USER="${METAL_BOX_SYSADMIN_USER:-alice}"
POST_METAL_SSH_PORT="${POST_METAL_SSH_PORT:-2522}"
CITY_GROUP="${CITY_GROUP:-city_dal}"
CITY_GROUP_VARS_FILE="${CITY_GROUP_VARS_FILE:-$REPO_ROOT/ansible/group_vars/${CITY_GROUP}.yml}"
VM_AUTHORIZED_IP="${VM_AUTHORIZED_IP:-10.0.2.2}"
OPERATOR_SSH_PUBLIC_KEY_FILE="${OPERATOR_SSH_PUBLIC_KEY_FILE:-}"
SSH_COMMON_ARGS="${SSH_COMMON_ARGS:--o IdentitiesOnly=yes -o IdentityAgent=none -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no}"
ENABLE_VM_TEST_SYSADMIN_NOPASSWD="${ENABLE_VM_TEST_SYSADMIN_NOPASSWD:-true}"
SKIP_CONFIRMATION_PAUSES="${SKIP_CONFIRMATION_PAUSES:-true}"
REQUIRE_SSH_SOCKET_PRECONDITION="${REQUIRE_SSH_SOCKET_PRECONDITION:-true}"
HOST_NAME="${HOST_NAME:-}"
WORK_DIR="${VM_ACCESS_VALIDATION_WORK_DIR:-}"

usage() {
  cat <<'EOF'
Usage:
  verify-vm-access-validation.sh --inventory <path> [options]

Required:
  --inventory <path>

Optional:
  --target-host <name>                  (default: vm-local)
  --bootstrap-user <name>               (default: inventory ansible_user or ubuntu)
  --post-metal-ssh-port <int>           (default: 2522)
  --host-name <name>                    (default: unset)
  --operator-ssh-public-key-file <path> (default: <inventory_private_key>.pub)
  --workdir <path>                      (default: <inventory_dir>/vm-access-validation)
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
    --bootstrap-user)
      BOOTSTRAP_USER="${2:-}"
      shift 2
      ;;
    --post-metal-ssh-port)
      POST_METAL_SSH_PORT="${2:-}"
      shift 2
      ;;
    --host-name)
      HOST_NAME="${2:-}"
      shift 2
      ;;
    --operator-ssh-public-key-file)
      OPERATOR_SSH_PUBLIC_KEY_FILE="${2:-}"
      shift 2
      ;;
    --workdir)
      WORK_DIR="${2:-}"
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
    echo "Missing required command: $cmd" >&2
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

resolve_readable_path() {
  local p="$1"
  local base="${2:-}"
  local candidate

  candidate="$(resolve_path "$p" "$base")"
  if [[ -r "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ "$p" != /* ]]; then
    candidate="$(resolve_path "$p" "$REPO_ROOT/ansible")"
    if [[ -r "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  printf '%s\n' "$(resolve_path "$p" "$base")"
}

extract_probe_value() {
  local key="$1"
  local content="$2"
  grep -E "^${key}=" <<<"$content" | tail -n 1 | cut -d= -f2-
}

run_ssh_transition_probe() {
  local inventory="$1"
  local ssh_user="$2"
  local probe_script

  probe_script="$(cat <<EOF
set -eu
service_enabled="\$(systemctl is-enabled ssh.service 2>/dev/null || true)"
service_active="\$(systemctl is-active ssh.service 2>/dev/null || true)"
socket_exists=false
socket_enabled=not-found
socket_active=not-found
if systemctl list-unit-files ssh.socket --no-legend --no-pager 2>/dev/null | awk 'NR == 1 { found = 1 } END { exit found ? 0 : 1 }'; then
  socket_exists=true
  socket_enabled="\$(systemctl is-enabled ssh.socket 2>/dev/null || true)"
  socket_active="\$(systemctl is-active ssh.socket 2>/dev/null || true)"
fi
listen_state=absent
if ss -ltn | awk 'NR > 1 && \$4 ~ /:${POST_METAL_SSH_PORT}\$/ { found = 1 } END { exit found ? 0 : 1 }'; then
  listen_state=present
fi
printf 'ssh_service_enabled=%s\n' "\$service_enabled"
printf 'ssh_service_active=%s\n' "\$service_active"
printf 'ssh_socket_exists=%s\n' "\$socket_exists"
printf 'ssh_socket_enabled=%s\n' "\$socket_enabled"
printf 'ssh_socket_active=%s\n' "\$socket_active"
printf 'ssh_listener=%s\n' "\$listen_state"
EOF
)"

  ansible "$TARGET_HOST" \
    -i "$inventory" \
    -u "$ssh_user" \
    -b \
    -m shell \
    -a "$probe_script" 2>&1
}

assert_preconditions() {
  local probe_output="$1"
  local socket_exists
  local socket_active
  local post_port_listener

  socket_exists="$(extract_probe_value ssh_socket_exists "$probe_output")"
  socket_active="$(extract_probe_value ssh_socket_active "$probe_output")"
  post_port_listener="$(extract_probe_value ssh_listener "$probe_output")"

  if [[ "$BOOTSTRAP_SSH_PORT" == "$POST_METAL_SSH_PORT" ]]; then
    echo "Access-validation requires the bootstrap inventory to stay on the old SSH port." >&2
    echo "Current inventory already uses ${BOOTSTRAP_SSH_PORT}, which matches POST_METAL_SSH_PORT." >&2
    exit 4
  fi

  if [[ "$REQUIRE_SSH_SOCKET_PRECONDITION" == "true" && "$socket_exists" != "true" ]]; then
    echo "Host does not expose an ssh.socket unit, so this VM cannot validate PR #212's socket-to-service migration path." >&2
    echo "Set REQUIRE_SSH_SOCKET_PRECONDITION=false to bypass this guard." >&2
    exit 4
  fi

  if [[ "$REQUIRE_SSH_SOCKET_PRECONDITION" == "true" && "$socket_active" != "active" ]]; then
    echo "Expected ssh.socket to be active before the first access-validation run, but observed: ${socket_active:-unknown}" >&2
    echo "Use a fresh VM snapshot or set REQUIRE_SSH_SOCKET_PRECONDITION=false if you only want post-state validation." >&2
    exit 4
  fi

  if [[ "$post_port_listener" != "absent" ]]; then
    echo "Expected SSH port ${POST_METAL_SSH_PORT} to be closed before the first run, but it is already listening." >&2
    echo "Use a fresh VM snapshot or reset the VM before running access-validation." >&2
    exit 4
  fi
}

assert_post_state() {
  local label="$1"
  local probe_output="$2"
  local service_enabled
  local service_active
  local socket_exists
  local socket_enabled
  local socket_active
  local listener_state

  service_enabled="$(extract_probe_value ssh_service_enabled "$probe_output")"
  service_active="$(extract_probe_value ssh_service_active "$probe_output")"
  socket_exists="$(extract_probe_value ssh_socket_exists "$probe_output")"
  socket_enabled="$(extract_probe_value ssh_socket_enabled "$probe_output")"
  socket_active="$(extract_probe_value ssh_socket_active "$probe_output")"
  listener_state="$(extract_probe_value ssh_listener "$probe_output")"

  if [[ "$service_enabled" != "enabled" ]]; then
    echo "[${label}] Expected ssh.service to be enabled, but observed: ${service_enabled:-unknown}" >&2
    exit 4
  fi

  if [[ "$service_active" != "active" ]]; then
    echo "[${label}] Expected ssh.service to be active, but observed: ${service_active:-unknown}" >&2
    exit 4
  fi

  if [[ "$listener_state" != "present" ]]; then
    echo "[${label}] Expected SSH to listen on port ${POST_METAL_SSH_PORT}, but no listener was detected." >&2
    exit 4
  fi

  if [[ "$socket_exists" == "true" ]]; then
    if [[ "$socket_enabled" != "disabled" ]]; then
      echo "[${label}] Expected ssh.socket to be disabled, but observed: ${socket_enabled:-unknown}" >&2
      exit 4
    fi
    if [[ "$socket_active" != "inactive" ]]; then
      echo "[${label}] Expected ssh.socket to be inactive, but observed: ${socket_active:-unknown}" >&2
      exit 4
    fi
  fi
}

run_access_validation_playbook() {
  local inventory="$1"
  local log_path="$2"
  local host_name_args=()

  if [[ -n "$HOST_NAME" ]]; then
    host_name_args=(-e "host_name=$HOST_NAME")
  fi

  ansible-playbook \
    -i "$inventory" \
    "$REPO_ROOT/ansible/playbooks/pb_setup_metal_box.yml" \
    --tags access-validation \
    "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
    -e "target_host=$TARGET_HOST" \
    -e "ansible_user=$METAL_BOX_SYSADMIN_USER" \
    -e "csv_file=$(basename "$AUTHORIZED_IPS_CSV")" \
    -e "authorized_access_csv=$AUTHORIZED_IPS_CSV" \
    -e "skip_confirmation_pauses=$SKIP_CONFIRMATION_PAUSES" \
    "${host_name_args[@]}" | tee "$log_path"
}

require_cmd ansible
require_cmd ansible-playbook
require_cmd ansible-inventory
require_cmd jq
require_cmd ssh-keygen

export TERM="${TERM:-dumb}"
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"
export ANSIBLE_ROLES_PATH="$REPO_ROOT/ansible/roles"
export ANSIBLE_BECOME_TIMEOUT="${ANSIBLE_BECOME_TIMEOUT:-45}"
export ANSIBLE_TIMEOUT="${ANSIBLE_TIMEOUT:-45}"

if [[ ! -r "$CITY_GROUP_VARS_FILE" ]]; then
  echo "City group vars file is not readable: $CITY_GROUP_VARS_FILE" >&2
  exit 3
fi

COMMON_ANSIBLE_EXTRA_VARS_ARGS=(
  -e "@$REPO_ROOT/ansible/group_vars/all.yml"
  -e "@$REPO_ROOT/ansible/group_vars/solana.yml"
  -e "@$CITY_GROUP_VARS_FILE"
)

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
VM_SSH_PRIVATE_KEY_FILE="$(resolve_readable_path "$VM_SSH_PRIVATE_KEY_FILE" "$INV_DIR")"
if [[ ! -r "$VM_SSH_PRIVATE_KEY_FILE" ]]; then
  echo "Private key not readable: $VM_SSH_PRIVATE_KEY_FILE" >&2
  exit 2
fi

if [[ -n "$OPERATOR_SSH_PUBLIC_KEY_FILE" ]]; then
  OPERATOR_SSH_PUBLIC_KEY_FILE="$(resolve_path "$OPERATOR_SSH_PUBLIC_KEY_FILE" "$(pwd)")"
fi
if [[ -z "$OPERATOR_SSH_PUBLIC_KEY_FILE" && -r "${VM_SSH_PRIVATE_KEY_FILE}.pub" ]]; then
  OPERATOR_SSH_PUBLIC_KEY_FILE="${VM_SSH_PRIVATE_KEY_FILE}.pub"
fi

if [[ -n "$OPERATOR_SSH_PUBLIC_KEY_FILE" && -r "$OPERATOR_SSH_PUBLIC_KEY_FILE" ]]; then
  OPERATOR_SSH_PUBLIC_KEY="$(cat "$OPERATOR_SSH_PUBLIC_KEY_FILE")"
else
  OPERATOR_SSH_PUBLIC_KEY="$(ssh-keygen -y -f "$VM_SSH_PRIVATE_KEY_FILE")"
fi

if [[ -z "$WORK_DIR" ]]; then
  WORK_DIR="$INV_DIR/vm-access-validation"
fi
WORK_DIR="$(resolve_path "$WORK_DIR" "$(pwd)")"
mkdir -p "$WORK_DIR"

IAM_CSV="$WORK_DIR/iam_setup_vm_validator.csv"
AUTHORIZED_IPS_CSV="$WORK_DIR/authorized_ips_vm.csv"
BOOTSTRAP_INVENTORY="$WORK_DIR/inventory.bootstrap.yml"
SYSADMIN_BOOTSTRAP_INVENTORY="$WORK_DIR/inventory.sysadmin-bootstrap.yml"
SYSADMIN_INVENTORY="$WORK_DIR/inventory.sysadmin.yml"
PRECHECK_LOG="$WORK_DIR/precheck-before.txt"
RUN1_LOG="$WORK_DIR/access-validation-run1.log"
RUN1_PROBE="$WORK_DIR/access-validation-run1-probe.txt"
RUN2_LOG="$WORK_DIR/access-validation-run2.log"
RUN2_PROBE="$WORK_DIR/access-validation-run2-probe.txt"

cat >"$IAM_CSV" <<EOF
user,key,group_a,group_b,group_c
alice,${OPERATOR_SSH_PUBLIC_KEY},sysadmin,,
bob,${OPERATOR_SSH_PUBLIC_KEY},validator_operators,,
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
EOF

cat >"$SYSADMIN_BOOTSTRAP_INVENTORY" <<EOF
all:
  hosts:
    ${TARGET_HOST}:
      ansible_host: ${VM_HOST}
      ansible_port: ${BOOTSTRAP_SSH_PORT}
      ansible_user: ${METAL_BOX_SYSADMIN_USER}
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
EOF

cat >"$SYSADMIN_INVENTORY" <<EOF
all:
  hosts:
    ${TARGET_HOST}:
      ansible_host: ${VM_HOST}
      ansible_port: ${POST_METAL_SSH_PORT}
      ansible_user: ${METAL_BOX_SYSADMIN_USER}
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
EOF

if [[ "$ENABLE_VM_TEST_SYSADMIN_NOPASSWD" == "true" ]]; then
  echo "[vm-access-validation] Preparing temporary sysadmin sudo policy on ${TARGET_HOST}..." >&2
  ansible-playbook \
    -i "$BOOTSTRAP_INVENTORY" \
    "$REPO_ROOT/test-harness/ansible/pb_prepare_vm_sysadmin_nopasswd.yml" \
    -e "target_hosts=$TARGET_HOST" \
    -e "bootstrap_user=$BOOTSTRAP_USER"
fi

echo "[vm-access-validation] Running pb_setup_users_validator..." >&2
ansible-playbook \
  -i "$BOOTSTRAP_INVENTORY" \
  "$REPO_ROOT/ansible/playbooks/pb_setup_users_validator.yml" \
  "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
  -e "target_host=$TARGET_HOST" \
  -e "ansible_user=$BOOTSTRAP_USER" \
  -e "csv_file=$(basename "$IAM_CSV")" \
  -e "users_base_dir=$(dirname "$IAM_CSV")" \
  -e "skip_confirmation_pauses=$SKIP_CONFIRMATION_PAUSES"

echo "[vm-access-validation] Probing pre-run SSH/socket state..." >&2
pre_probe_output="$(run_ssh_transition_probe "$SYSADMIN_BOOTSTRAP_INVENTORY" "$METAL_BOX_SYSADMIN_USER")"
printf '%s\n' "$pre_probe_output" >"$PRECHECK_LOG"
assert_preconditions "$pre_probe_output"

echo "[vm-access-validation] Running first access-validation pass (real port switch + reboot)..." >&2
run_access_validation_playbook "$SYSADMIN_BOOTSTRAP_INVENTORY" "$RUN1_LOG"
echo "[vm-access-validation] Waiting for SSH on post-metal port ${POST_METAL_SSH_PORT}..." >&2
"$REPO_ROOT/scripts/vm-test/wait-for-ssh.sh" "$VM_HOST" "$POST_METAL_SSH_PORT" 300

echo "[vm-access-validation] Verifying post-run SSH state after first pass..." >&2
run1_probe_output="$(run_ssh_transition_probe "$SYSADMIN_INVENTORY" "$METAL_BOX_SYSADMIN_USER")"
printf '%s\n' "$run1_probe_output" >"$RUN1_PROBE"
assert_post_state "run1" "$run1_probe_output"

echo "[vm-access-validation] Running second access-validation pass (idempotency)..." >&2
run_access_validation_playbook "$SYSADMIN_INVENTORY" "$RUN2_LOG"
echo "[vm-access-validation] Waiting for SSH on post-metal port ${POST_METAL_SSH_PORT} after second pass..." >&2
"$REPO_ROOT/scripts/vm-test/wait-for-ssh.sh" "$VM_HOST" "$POST_METAL_SSH_PORT" 300

echo "[vm-access-validation] Verifying post-run SSH state after second pass..." >&2
run2_probe_output="$(run_ssh_transition_probe "$SYSADMIN_INVENTORY" "$METAL_BOX_SYSADMIN_USER")"
printf '%s\n' "$run2_probe_output" >"$RUN2_PROBE"
assert_post_state "run2" "$run2_probe_output"

echo "[vm-access-validation] Access-validation completed successfully." >&2
echo "[vm-access-validation] Artifacts written under: $WORK_DIR" >&2

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=test-harness/lib/disposable_host_common.sh
source "$REPO_ROOT/test-harness/lib/disposable_host_common.sh"

INVENTORY_PATH=""
TARGET_HOST="${TARGET_HOST:-latitude-host}"
BOOTSTRAP_USER="${BOOTSTRAP_USER:-}"
METAL_BOX_SYSADMIN_USER="${METAL_BOX_SYSADMIN_USER:-alice}"
POST_METAL_SSH_PORT="${POST_METAL_SSH_PORT:-2522}"
CITY_GROUP="${CITY_GROUP:-dc_latitude}"
CITY_GROUP_VARS_FILE="${CITY_GROUP_VARS_FILE:-$REPO_ROOT/ansible/group_vars/${CITY_GROUP}.yml}"
AUTHORIZED_IPS_INPUT="${AUTHORIZED_IPS_INPUT:-}"
PUBLIC_IP_DETECT_URL="${PUBLIC_IP_DETECT_URL:-https://api.ipify.org}"
OPERATOR_SSH_PUBLIC_KEY_FILE="${OPERATOR_SSH_PUBLIC_KEY_FILE:-}"
SSH_COMMON_ARGS="${SSH_COMMON_ARGS:--o IdentitiesOnly=yes -o IdentityAgent=none -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no}"
ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD="${ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD:-true}"
SKIP_CONFIRMATION_PAUSES="${SKIP_CONFIRMATION_PAUSES:-true}"
HOST_NAME="${HOST_NAME:-}"
WORK_DIR="${LATITUDE_ACCESS_VALIDATION_WORK_DIR:-}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-300}"
WAIT_POLL_INTERVAL_SECONDS="${WAIT_POLL_INTERVAL_SECONDS:-5}"

declare -a EXTRA_AUTHORIZED_IPS=()

usage() {
  cat <<'EOF'
Usage:
  verify-latitude-access-validation.sh --inventory <path> [options]

Required:
  --inventory <path>

Optional:
  --target-host <name>                  (default: latitude-host)
  --bootstrap-user <name>               (default: inventory ansible_user or ubuntu)
  --post-metal-ssh-port <int>           (default: 2522)
  --host-name <name>                    (default: unset)
  --operator-ssh-public-key-file <path> (default: derived from inventory key)
  --authorized-ips-csv <path>           (default: auto-generate from current public IP)
  --authorized-ip <ip>                  (repeatable; adds extra trusted IPs)
  --workdir <path>                      (default: <inventory_dir>/latitude-access-validation)
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
    --authorized-ips-csv)
      AUTHORIZED_IPS_INPUT="${2:-}"
      shift 2
      ;;
    --authorized-ip)
      EXTRA_AUTHORIZED_IPS+=("${2:-}")
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
  local post_port_listener

  post_port_listener="$(extract_probe_value ssh_listener "$probe_output")"

  if [[ "$BOOTSTRAP_SSH_PORT" == "$POST_METAL_SSH_PORT" ]]; then
    echo "Latitude access-validation requires the bootstrap inventory to stay on the old SSH port." >&2
    exit 4
  fi

  if [[ "$post_port_listener" != "absent" ]]; then
    echo "Expected SSH port ${POST_METAL_SSH_PORT} to be closed before the first run, but it is already listening." >&2
    echo "Use a fresh disposable host or reset the canary before running access-validation." >&2
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

build_inventory_children_block() {
  cat <<EOF
  children:
    solana:
      hosts:
        ${TARGET_HOST}:
EOF

  if [[ -n "$CITY_GROUP" ]]; then
    cat <<EOF
    ${CITY_GROUP}:
      hosts:
        ${TARGET_HOST}:
EOF
  fi
}

write_inventory() {
  local path="$1"
  local ssh_user="$2"
  local ssh_port="$3"

  cat >"$path" <<EOF
all:
  hosts:
    ${TARGET_HOST}:
      ansible_host: ${TARGET_IP}
      ansible_port: ${ssh_port}
      ansible_user: ${ssh_user}
      ansible_ssh_private_key_file: ${SSH_PRIVATE_KEY_FILE}
      ansible_ssh_common_args: "${SSH_COMMON_ARGS}"
      ansible_become: true
EOF
  build_inventory_children_block >>"$path"
}

generate_authorized_ips_csv() {
  local output_path="$1"
  local line_no=0
  local detected_ip=""
  local ip=""

  if [[ -n "$AUTHORIZED_IPS_INPUT" ]]; then
    cp "$AUTHORIZED_IPS_INPUT" "$output_path"
    return 0
  fi

  detected_ip="$(th_detect_public_ip "$PUBLIC_IP_DETECT_URL")"

  {
    echo "ip,comment"
    echo "${detected_ip},Detected current operator public IP"
    line_no=1
    for ip in "${EXTRA_AUTHORIZED_IPS[@]}"; do
      if [[ -n "$ip" ]]; then
        line_no=$((line_no + 1))
        echo "${ip},Additional trusted IP ${line_no}"
      fi
    done
  } >"$output_path"
}

th_require_cmd ansible
th_require_cmd ansible-playbook
th_require_cmd ansible-inventory
th_require_cmd jq
th_require_cmd ssh-keygen

export TERM="${TERM:-dumb}"
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"
export ANSIBLE_ROLES_PATH="$REPO_ROOT/ansible/roles"
export ANSIBLE_BECOME_TIMEOUT="${ANSIBLE_BECOME_TIMEOUT:-45}"
export ANSIBLE_TIMEOUT="${ANSIBLE_TIMEOUT:-45}"

COMMON_ANSIBLE_EXTRA_VARS_ARGS=(
  -e "@$REPO_ROOT/ansible/group_vars/all.yml"
  -e "@$REPO_ROOT/ansible/group_vars/solana.yml"
)
if [[ -n "$CITY_GROUP" ]]; then
  if [[ ! -r "$CITY_GROUP_VARS_FILE" ]]; then
    echo "City group vars file is not readable: $CITY_GROUP_VARS_FILE" >&2
    exit 3
  fi
  COMMON_ANSIBLE_EXTRA_VARS_ARGS+=(-e "@$CITY_GROUP_VARS_FILE")
fi

INVENTORY_PATH="$(th_resolve_path "$INVENTORY_PATH" "$(pwd)")"
if [[ ! -f "$INVENTORY_PATH" ]]; then
  echo "Inventory file not found: $INVENTORY_PATH" >&2
  exit 2
fi

if [[ -n "$AUTHORIZED_IPS_INPUT" ]]; then
  AUTHORIZED_IPS_INPUT="$(th_resolve_path "$AUTHORIZED_IPS_INPUT" "$(pwd)")"
  if [[ ! -r "$AUTHORIZED_IPS_INPUT" ]]; then
    echo "Authorized IPs CSV is not readable: $AUTHORIZED_IPS_INPUT" >&2
    exit 2
  fi
fi

host_json="$(ansible-inventory -i "$INVENTORY_PATH" --host "$TARGET_HOST")"
TARGET_IP="$(jq -r '.ansible_host // "127.0.0.1"' <<<"$host_json")"
BOOTSTRAP_SSH_PORT="$(jq -r '.ansible_port // 22' <<<"$host_json")"
if [[ -z "$BOOTSTRAP_USER" ]]; then
  BOOTSTRAP_USER="$(jq -r '.ansible_user // "ubuntu"' <<<"$host_json")"
fi
SSH_PRIVATE_KEY_FILE="$(jq -r '.ansible_ssh_private_key_file // empty' <<<"$host_json")"
if [[ -z "$SSH_PRIVATE_KEY_FILE" ]]; then
  echo "ansible_ssh_private_key_file is required in inventory host '$TARGET_HOST'" >&2
  exit 2
fi

INV_DIR="$(cd "$(dirname "$INVENTORY_PATH")" && pwd)"
SSH_PRIVATE_KEY_FILE="$(th_resolve_readable_path "$SSH_PRIVATE_KEY_FILE" "$INV_DIR" "$REPO_ROOT/ansible")"
if [[ ! -r "$SSH_PRIVATE_KEY_FILE" ]]; then
  echo "Private key not readable: $SSH_PRIVATE_KEY_FILE" >&2
  exit 2
fi

if [[ -n "$OPERATOR_SSH_PUBLIC_KEY_FILE" ]]; then
  OPERATOR_SSH_PUBLIC_KEY_FILE="$(th_resolve_path "$OPERATOR_SSH_PUBLIC_KEY_FILE" "$(pwd)")"
fi
OPERATOR_SSH_PUBLIC_KEY="$(th_public_key_from_private_key "$SSH_PRIVATE_KEY_FILE" "$OPERATOR_SSH_PUBLIC_KEY_FILE")"

if [[ -z "$WORK_DIR" ]]; then
  WORK_DIR="$INV_DIR/latitude-access-validation"
fi
WORK_DIR="$(th_resolve_path "$WORK_DIR" "$(pwd)")"
mkdir -p "$WORK_DIR"

IAM_CSV="$WORK_DIR/iam_setup_latitude_validator.csv"
AUTHORIZED_IPS_CSV="$WORK_DIR/authorized_ips_latitude.csv"
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

generate_authorized_ips_csv "$AUTHORIZED_IPS_CSV"

write_inventory "$BOOTSTRAP_INVENTORY" "$BOOTSTRAP_USER" "$BOOTSTRAP_SSH_PORT"
write_inventory "$SYSADMIN_BOOTSTRAP_INVENTORY" "$METAL_BOX_SYSADMIN_USER" "$BOOTSTRAP_SSH_PORT"
write_inventory "$SYSADMIN_INVENTORY" "$METAL_BOX_SYSADMIN_USER" "$POST_METAL_SSH_PORT"

if [[ "$ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD" == "true" ]]; then
  echo "[latitude-access-validation] Preparing temporary sysadmin sudo policy on ${TARGET_HOST}..." >&2
  ansible-playbook \
    -i "$BOOTSTRAP_INVENTORY" \
    "$REPO_ROOT/test-harness/ansible/pb_prepare_disposable_sysadmin_nopasswd.yml" \
    -e "target_hosts=$TARGET_HOST" \
    -e "bootstrap_user=$BOOTSTRAP_USER"
fi

echo "[latitude-access-validation] Running pb_setup_users_validator..." >&2
ansible-playbook \
  -i "$BOOTSTRAP_INVENTORY" \
  "$REPO_ROOT/ansible/playbooks/pb_setup_users_validator.yml" \
  "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
  -e "target_host=$TARGET_HOST" \
  -e "ansible_user=$BOOTSTRAP_USER" \
  -e "csv_file=$(basename "$IAM_CSV")" \
  -e "users_base_dir=$(dirname "$IAM_CSV")" \
  -e "skip_confirmation_pauses=$SKIP_CONFIRMATION_PAUSES"

echo "[latitude-access-validation] Probing pre-run SSH/socket state..." >&2
pre_probe_output="$(run_ssh_transition_probe "$SYSADMIN_BOOTSTRAP_INVENTORY" "$METAL_BOX_SYSADMIN_USER")"
printf '%s\n' "$pre_probe_output" >"$PRECHECK_LOG"
assert_preconditions "$pre_probe_output"

echo "[latitude-access-validation] Running first access-validation pass (real port switch + reboot)..." >&2
run_access_validation_playbook "$SYSADMIN_BOOTSTRAP_INVENTORY" "$RUN1_LOG"
echo "[latitude-access-validation] Waiting for SSH on post-metal port ${POST_METAL_SSH_PORT}..." >&2
th_wait_for_ssh "$METAL_BOX_SYSADMIN_USER" "$TARGET_IP" "$POST_METAL_SSH_PORT" "$SSH_PRIVATE_KEY_FILE" "$WAIT_TIMEOUT_SECONDS" "$WAIT_POLL_INTERVAL_SECONDS"

echo "[latitude-access-validation] Verifying post-run SSH state after first pass..." >&2
run1_probe_output="$(run_ssh_transition_probe "$SYSADMIN_INVENTORY" "$METAL_BOX_SYSADMIN_USER")"
printf '%s\n' "$run1_probe_output" >"$RUN1_PROBE"
assert_post_state "run1" "$run1_probe_output"

echo "[latitude-access-validation] Running second access-validation pass (idempotency)..." >&2
run_access_validation_playbook "$SYSADMIN_INVENTORY" "$RUN2_LOG"
echo "[latitude-access-validation] Waiting for SSH on post-metal port ${POST_METAL_SSH_PORT} after second pass..." >&2
th_wait_for_ssh "$METAL_BOX_SYSADMIN_USER" "$TARGET_IP" "$POST_METAL_SSH_PORT" "$SSH_PRIVATE_KEY_FILE" "$WAIT_TIMEOUT_SECONDS" "$WAIT_POLL_INTERVAL_SECONDS"

echo "[latitude-access-validation] Verifying post-run SSH state after second pass..." >&2
run2_probe_output="$(run_ssh_transition_probe "$SYSADMIN_INVENTORY" "$METAL_BOX_SYSADMIN_USER")"
printf '%s\n' "$run2_probe_output" >"$RUN2_PROBE"
assert_post_state "run2" "$run2_probe_output"

echo "[latitude-access-validation] Access-validation completed successfully." >&2
echo "[latitude-access-validation] Artifacts written under: $WORK_DIR" >&2

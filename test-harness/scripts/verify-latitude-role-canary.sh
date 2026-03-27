#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=test-harness/lib/disposable_host_common.sh
source "$REPO_ROOT/test-harness/lib/disposable_host_common.sh"

INVENTORY_PATH=""
TARGET_HOST="${TARGET_HOST:-latitude-host}"
MODE="${MODE:-agave-cli}"
POST_METAL_ONLY=false
BOOTSTRAP_USER="${BOOTSTRAP_USER:-}"
METAL_BOX_SYSADMIN_USER="${METAL_BOX_SYSADMIN_USER:-alice}"
VALIDATOR_OPERATOR_USER="${VALIDATOR_OPERATOR_USER:-bob}"
POST_METAL_SSH_PORT="${POST_METAL_SSH_PORT:-2522}"
CITY_GROUP="${CITY_GROUP:-city_dal}"
CITY_GROUP_VARS_FILE="${CITY_GROUP_VARS_FILE:-$REPO_ROOT/ansible/group_vars/${CITY_GROUP}.yml}"
SOLANA_CLUSTER="${SOLANA_CLUSTER:-testnet}"
AUTHORIZED_IPS_INPUT="${AUTHORIZED_IPS_INPUT:-}"
PUBLIC_IP_DETECT_URL="${PUBLIC_IP_DETECT_URL:-https://api.ipify.org}"
OPERATOR_SSH_PUBLIC_KEY_FILE="${OPERATOR_SSH_PUBLIC_KEY_FILE:-}"
SSH_COMMON_ARGS="${SSH_COMMON_ARGS:--o IdentitiesOnly=yes -o IdentityAgent=none -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no}"
ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD="${ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD:-true}"
SKIP_CONFIRMATION_PAUSES="${SKIP_CONFIRMATION_PAUSES:-true}"
HOST_NAME="${HOST_NAME:-}"
WORK_DIR="${LATITUDE_ROLE_CANARY_WORK_DIR:-}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-300}"
WAIT_POLL_INTERVAL_SECONDS="${WAIT_POLL_INTERVAL_SECONDS:-5}"
BUILD_FROM_SOURCE="${BUILD_FROM_SOURCE:-true}"
FORCE_HOST_CLEANUP="${FORCE_HOST_CLEANUP:-true}"
VALIDATOR_NAME="${VALIDATOR_NAME:-latitude-testnet-canary}"
VALIDATOR_TYPE="${VALIDATOR_TYPE:-primary}"
AGAVE_VERSION="${AGAVE_VERSION:-3.1.10}"
JITO_VERSION="${JITO_VERSION:-3.1.10}"
JITO_VERSION_PATCH="${JITO_VERSION_PATCH:-}"
XDP_ENABLED="${XDP_ENABLED:-true}"
USE_OFFICIAL_REPO="${USE_OFFICIAL_REPO:-false}"
METAL_BOX_SKIP_TAGS="${METAL_BOX_SKIP_TAGS:-}"
ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT=false

declare -a EXTRA_AUTHORIZED_IPS=()

usage() {
  cat <<'EOF'
Usage:
  verify-latitude-role-canary.sh --inventory <path> [options]

Required:
  --inventory <path>

Optional:
  --mode <rust|agave-cli|jito-cli|agave-validator|jito-validator>
  --post-metal-only                    Skip users + metal-box and reuse an already hardened host
  --target-host <name>                  (default: latitude-host)
  --bootstrap-user <name>               (default: inventory ansible_user or ubuntu)
  --validator-operator-user <name>      (default: bob)
  --post-metal-ssh-port <int>           (default: 2522)
  --host-name <name>                    (default: unset)
  --operator-ssh-public-key-file <path> (default: derived from inventory key)
  --authorized-ips-csv <path>           (default: auto-generate from current public IP)
  --authorized-ip <ip>                  (repeatable; adds extra trusted IPs)
  --solana-cluster <name>               (default: testnet)
  --agave-version <semver>              (default: 3.1.10)
  --jito-version <semver>               (default: 3.1.10)
  --jito-version-patch <suffix>         (default: empty)
  --validator-name <name>               (default: latitude-testnet-canary)
  --validator-type <primary|hot-spare>  (default: primary)
  --use-official-repo                   (default: use team forked repos)
  --allow-unconventional-testnet-two-disk-layout
                                        Force the special Latitude-safe testnet two-disk layout
  --workdir <path>                      (default: <inventory_dir>/latitude-role-canary)
EOF
}

while (($# > 0)); do
  case "$1" in
    --inventory)
      INVENTORY_PATH="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --post-metal-only)
      POST_METAL_ONLY=true
      shift
      ;;
    --target-host)
      TARGET_HOST="${2:-}"
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
    --solana-cluster)
      SOLANA_CLUSTER="${2:-}"
      shift 2
      ;;
    --agave-version)
      AGAVE_VERSION="${2:-}"
      shift 2
      ;;
    --jito-version)
      JITO_VERSION="${2:-}"
      shift 2
      ;;
    --jito-version-patch)
      JITO_VERSION_PATCH="${2:-}"
      shift 2
      ;;
    --validator-name)
      VALIDATOR_NAME="${2:-}"
      shift 2
      ;;
    --validator-type)
      VALIDATOR_TYPE="${2:-}"
      shift 2
      ;;
    --use-official-repo)
      USE_OFFICIAL_REPO=true
      shift
      ;;
    --allow-unconventional-testnet-two-disk-layout)
      ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT=true
      shift
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

SOLANA_CLUSTER="${SOLANA_CLUSTER#solana_}"

build_inventory_children_block() {
  local cluster_group="solana_${SOLANA_CLUSTER}"

  cat <<EOF
  children:
    solana:
      hosts:
        ${TARGET_HOST}:
    ${cluster_group}:
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
  local detected_ip=""
  local index=1
  local ip=""

  if [[ -n "$AUTHORIZED_IPS_INPUT" ]]; then
    cp "$AUTHORIZED_IPS_INPUT" "$output_path"
    return 0
  fi

  detected_ip="$(th_detect_public_ip "$PUBLIC_IP_DETECT_URL")"

  {
    echo "ip,comment"
    echo "${detected_ip},Detected current operator public IP"
    for ip in "${EXTRA_AUTHORIZED_IPS[@]}"; do
      if [[ -n "$ip" ]]; then
        index=$((index + 1))
        echo "${ip},Additional trusted IP ${index}"
      fi
    done
  } >"$output_path"
}

is_validator_mode() {
  [[ "$MODE" == "agave-validator" || "$MODE" == "jito-validator" ]]
}

detect_allow_unconventional_testnet_two_disk_layout_via_ssh() {
  local ssh_user="$1"
  local ssh_port="$2"
  local ssh_opts=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=10
    -o IdentitiesOnly=yes
    -o IdentityAgent=none
    -i "$SSH_PRIVATE_KEY_FILE"
    -p "$ssh_port"
  )
  local non_root_disk_count=""

  if [[ "$SOLANA_CLUSTER" != "testnet" ]]; then
    return 1
  fi

  non_root_disk_count="$(
    ssh "${ssh_opts[@]}" "${ssh_user}@${TARGET_IP}" '
      root_source=$(findmnt -n -o SOURCE /)
      root_node=$(basename "$(readlink -f "$root_source")")

      while true; do
        parent=$(lsblk -ndo PKNAME "/dev/$root_node" 2>/dev/null | head -n1)
        [ -z "$parent" ] && break
        root_node="$parent"
      done

      root_disk="$root_node"

      lsblk -b -d -o NAME,TYPE,SIZE | awk '"'"'"'"'$2 == "disk" { print $1 }'"'"'"'"' | while read -r name; do
        if [ "$name" != "$root_disk" ] && ! grep -q "/dev/$name" /proc/mounts; then
          echo "$name"
        fi
      done
    ' 2>/dev/null | wc -l | tr -d '[:space:]'
  )"

  [[ "$non_root_disk_count" == "1" ]]
}

detect_allow_unconventional_testnet_two_disk_layout() {
  detect_allow_unconventional_testnet_two_disk_layout_via_ssh "$METAL_BOX_SYSADMIN_USER" "$POST_METAL_SSH_PORT"
}

prepare_post_metal_validator_host() {
  local prep_log="$WORK_DIR/post-metal-validator-host-prep.log"
  local allow_unconventional_testnet_two_disk_layout=false
  local prep_args=(
    -i "$SYSADMIN_INVENTORY"
    "$REPO_ROOT/ansible/playbooks/pb_setup_metal_box.yml"
    --limit "$TARGET_HOST"
    --tags precheck,initial-setup,validator-dir,system-tuning,disk-setup,post-check
    -e "target_host=$TARGET_HOST"
    -e "ansible_user=$METAL_BOX_SYSADMIN_USER"
    -e "solana_cluster=$SOLANA_CLUSTER"
    -e "skip_confirmation_pauses=$SKIP_CONFIRMATION_PAUSES"
    -e "csv_file=$(basename "$AUTHORIZED_IPS_CSV")"
    -e "users_base_dir=$(dirname "$AUTHORIZED_IPS_CSV")"
    -e "authorized_access_csv=$AUTHORIZED_IPS_CSV"
  )

  if [[ "$ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT" == "true" ]]; then
    allow_unconventional_testnet_two_disk_layout=true
    prep_args+=(-e "allow_unconventional_testnet_two_disk_layout=true")
  elif detect_allow_unconventional_testnet_two_disk_layout; then
    allow_unconventional_testnet_two_disk_layout=true
    prep_args+=(-e "allow_unconventional_testnet_two_disk_layout=true")
  fi

  echo "[latitude-role-canary] Preparing post-metal validator host prerequisites..." >&2
  if [[ "$allow_unconventional_testnet_two_disk_layout" == "true" ]]; then
    echo "[latitude-role-canary] Enabling special two-disk testnet layout for this disposable Latitude host." >&2
  fi

  ansible-playbook "${prep_args[@]}" | tee "$prep_log"
}

run_mode_canary() {
  case "$MODE" in
    rust)
      ansible-playbook \
        -i "$OPERATOR_INVENTORY" \
        "$REPO_ROOT/ansible/playbooks/pb_install_rust_v2.yml" \
        -e "target_host=$TARGET_HOST" \
        -e "operator_user=$VALIDATOR_OPERATOR_USER" | tee "$MODE_LOG"
      ;;
    agave-cli)
      ansible-playbook \
        -i "$OPERATOR_INVENTORY" \
        "$REPO_ROOT/ansible/playbooks/pb_install_solana_cli_agave.yml" \
        "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
        -e "target_host=$TARGET_HOST" \
        -e "operator_user=$VALIDATOR_OPERATOR_USER" \
        -e "agave_version=$AGAVE_VERSION" \
        -e "solana_cluster=$SOLANA_CLUSTER" \
        -e "use_official_repo=$USE_OFFICIAL_REPO" \
        -e "build_from_source=$BUILD_FROM_SOURCE" | tee "$MODE_LOG"
      ;;
    jito-cli)
      ansible-playbook \
        -i "$OPERATOR_INVENTORY" \
        "$REPO_ROOT/ansible/playbooks/pb_install_solana_cli_jito.yml" \
        "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
        -e "target_host=$TARGET_HOST" \
        -e "operator_user=$VALIDATOR_OPERATOR_USER" \
        -e "jito_version=$JITO_VERSION" \
        -e "jito_version_patch=$JITO_VERSION_PATCH" \
        -e "solana_cluster=$SOLANA_CLUSTER" \
        -e "use_official_repo=$USE_OFFICIAL_REPO" \
        -e "build_from_source=$BUILD_FROM_SOURCE" | tee "$MODE_LOG"
      ;;
    agave-validator)
      ansible-playbook \
        -i "$OPERATOR_INVENTORY" \
        "$REPO_ROOT/ansible/playbooks/pb_setup_validator_agave.yml" \
        --limit "$TARGET_HOST" \
        "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
        -e "target_host=$TARGET_HOST" \
        -e "ansible_user=$VALIDATOR_OPERATOR_USER" \
        -e "validator_name=$VALIDATOR_NAME" \
        -e "validator_type=$VALIDATOR_TYPE" \
        -e "agave_version=$AGAVE_VERSION" \
        -e "solana_cluster=$SOLANA_CLUSTER" \
        -e "use_official_repo=$USE_OFFICIAL_REPO" \
        -e "build_from_source=$BUILD_FROM_SOURCE" \
        -e "force_host_cleanup=$FORCE_HOST_CLEANUP" \
        -e "xdp_enabled=$XDP_ENABLED" | tee "$MODE_LOG"
      ;;
    jito-validator)
      ansible-playbook \
        -i "$OPERATOR_INVENTORY" \
        "$REPO_ROOT/ansible/playbooks/pb_setup_validator_jito_v2.yml" \
        --limit "$TARGET_HOST" \
        "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
        -e "target_host=$TARGET_HOST" \
        -e "ansible_user=$VALIDATOR_OPERATOR_USER" \
        -e "validator_name=$VALIDATOR_NAME" \
        -e "validator_type=$VALIDATOR_TYPE" \
        -e "jito_version=$JITO_VERSION" \
        -e "jito_version_patch=$JITO_VERSION_PATCH" \
        -e "solana_cluster=$SOLANA_CLUSTER" \
        -e "use_official_repo=$USE_OFFICIAL_REPO" \
        -e "build_from_source=$BUILD_FROM_SOURCE" \
        -e "force_host_cleanup=$FORCE_HOST_CLEANUP" \
        -e "xdp_enabled=$XDP_ENABLED" | tee "$MODE_LOG"
      ;;
    *)
      echo "Unsupported mode: $MODE" >&2
      exit 2
      ;;
  esac
}

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
  if grep -Eq '^[[:space:]]*[^#[:space:]]' "$CITY_GROUP_VARS_FILE"; then
    COMMON_ANSIBLE_EXTRA_VARS_ARGS+=(-e "@$CITY_GROUP_VARS_FILE")
  fi
fi

SOLANA_CLUSTER_NORMALIZED="${SOLANA_CLUSTER}"
SOLANA_CLUSTER_VARS_FILE="$REPO_ROOT/ansible/group_vars/solana_${SOLANA_CLUSTER_NORMALIZED}.yml"
if [[ -r "$SOLANA_CLUSTER_VARS_FILE" ]]; then
  COMMON_ANSIBLE_EXTRA_VARS_ARGS+=(-e "@$SOLANA_CLUSTER_VARS_FILE")
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
  WORK_DIR="$INV_DIR/latitude-role-canary"
fi
WORK_DIR="$(th_resolve_path "$WORK_DIR" "$(pwd)")"
mkdir -p "$WORK_DIR"

IAM_CSV="$WORK_DIR/iam_setup_latitude_validator.csv"
AUTHORIZED_IPS_CSV="$WORK_DIR/authorized_ips_latitude.csv"
BOOTSTRAP_INVENTORY="$WORK_DIR/inventory.bootstrap.yml"
SYSADMIN_INVENTORY="$WORK_DIR/inventory.sysadmin.yml"
OPERATOR_INVENTORY="$WORK_DIR/inventory.operator.yml"
MODE_LOG="$WORK_DIR/${MODE}.log"

cat >"$IAM_CSV" <<EOF
user,key,group_a,group_b,group_c
alice,${OPERATOR_SSH_PUBLIC_KEY},sysadmin,,
${VALIDATOR_OPERATOR_USER},${OPERATOR_SSH_PUBLIC_KEY},validator_operators,,
carla,${OPERATOR_SSH_PUBLIC_KEY},validator_viewers,,
sol,,,,
EOF

generate_authorized_ips_csv "$AUTHORIZED_IPS_CSV"

write_inventory "$BOOTSTRAP_INVENTORY" "$BOOTSTRAP_USER" "$BOOTSTRAP_SSH_PORT"
write_inventory "$SYSADMIN_INVENTORY" "$METAL_BOX_SYSADMIN_USER" "$POST_METAL_SSH_PORT"
write_inventory "$OPERATOR_INVENTORY" "$VALIDATOR_OPERATOR_USER" "$POST_METAL_SSH_PORT"

if [[ "$POST_METAL_ONLY" != "true" ]]; then
  allow_unconventional_testnet_two_disk_layout=false

  if [[ "$ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD" == "true" ]]; then
    echo "[latitude-role-canary] Preparing temporary sysadmin sudo policy on ${TARGET_HOST}..." >&2
    ansible-playbook \
      -i "$BOOTSTRAP_INVENTORY" \
      "$REPO_ROOT/test-harness/ansible/pb_prepare_disposable_sysadmin_nopasswd.yml" \
      -e "target_hosts=$TARGET_HOST" \
      -e "bootstrap_user=$BOOTSTRAP_USER"
  fi

  wrapper_args=(
    -i "$BOOTSTRAP_INVENTORY"
    "$REPO_ROOT/test-harness/ansible/pb_disposable_users_then_metal_box.yml"
    "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}"
    -e "target_host=$TARGET_HOST"
    -e "bootstrap_user=$BOOTSTRAP_USER"
    -e "metal_box_user=$METAL_BOX_SYSADMIN_USER"
    -e "solana_cluster=$SOLANA_CLUSTER"
    -e "users_csv_file=$(basename "$IAM_CSV")"
    -e "users_base_dir=$(dirname "$IAM_CSV")"
    -e "authorized_ips_csv_file=$(basename "$AUTHORIZED_IPS_CSV")"
    -e "authorized_access_csv=$AUTHORIZED_IPS_CSV"
    -e "skip_confirmation_pauses=$SKIP_CONFIRMATION_PAUSES"
  )

  if is_validator_mode && [[ "$ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT" == "true" ]]; then
    allow_unconventional_testnet_two_disk_layout=true
    wrapper_args+=(-e "allow_unconventional_testnet_two_disk_layout=true")
  elif is_validator_mode && detect_allow_unconventional_testnet_two_disk_layout_via_ssh "$BOOTSTRAP_USER" "$BOOTSTRAP_SSH_PORT"; then
    allow_unconventional_testnet_two_disk_layout=true
    wrapper_args+=(-e "allow_unconventional_testnet_two_disk_layout=true")
  fi

  if [[ -n "$HOST_NAME" ]]; then
    wrapper_args+=(-e "host_name=$HOST_NAME")
  fi
  if [[ -n "$METAL_BOX_SKIP_TAGS" ]]; then
    wrapper_args+=(--skip-tags "$METAL_BOX_SKIP_TAGS")
  fi

  echo "[latitude-role-canary] Running users -> metal-box..." >&2
  if [[ "$allow_unconventional_testnet_two_disk_layout" == "true" ]]; then
    echo "[latitude-role-canary] Enabling special two-disk testnet layout for this disposable Latitude host." >&2
  fi
  ansible-playbook "${wrapper_args[@]}" | tee "$WORK_DIR/users-metal-box.log"
fi

if [[ "$POST_METAL_ONLY" == "true" ]] && is_validator_mode; then
  echo "[latitude-role-canary] Waiting for SSH on post-metal sysadmin path ${POST_METAL_SSH_PORT}..." >&2
  th_wait_for_ssh "$METAL_BOX_SYSADMIN_USER" "$TARGET_IP" "$POST_METAL_SSH_PORT" "$SSH_PRIVATE_KEY_FILE" "$WAIT_TIMEOUT_SECONDS" "$WAIT_POLL_INTERVAL_SECONDS"
  prepare_post_metal_validator_host
fi

echo "[latitude-role-canary] Waiting for SSH on post-metal port ${POST_METAL_SSH_PORT}..." >&2
th_wait_for_ssh "$VALIDATOR_OPERATOR_USER" "$TARGET_IP" "$POST_METAL_SSH_PORT" "$SSH_PRIVATE_KEY_FILE" "$WAIT_TIMEOUT_SECONDS" "$WAIT_POLL_INTERVAL_SECONDS"

echo "[latitude-role-canary] Running mode: $MODE" >&2
run_mode_canary

echo "[latitude-role-canary] Mode ${MODE} completed successfully." >&2
echo "[latitude-role-canary] Artifacts written under: $WORK_DIR" >&2

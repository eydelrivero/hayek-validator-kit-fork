#!/usr/bin/env bash
# run-latitude-hot-swap-matrix.sh
#
# Provision two Latitude bare-metal hosts, run a hot-swap identity transfer
# between them, verify the result, and tear both hosts down.
#
# Default matrix covers frankendancer swap cases that cannot run in QEMU VMs
# due to Firedancer's core/tile requirements.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"
export ANSIBLE_ROLES_PATH="$REPO_ROOT/ansible/roles"

WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work/latitude-hot-swap}"
RUN_ID_PREFIX="${RUN_ID_PREFIX:-latitude-hot-swap}"
OPERATOR_NAME="${LATITUDE_OPERATOR_NAME:-}"
OPERATOR_SSH_PUBLIC_KEY_FILE="${LATITUDE_OPERATOR_SSH_PUBLIC_KEY_FILE:-}"
OPERATOR_SSH_PRIVATE_KEY_FILE="${LATITUDE_OPERATOR_SSH_PRIVATE_KEY_FILE:-}"
PLAN="${FIREDANCER_LATITUDE_PLAN:-m4-metal-medium}"
PROJECT="${PROJECT:-ZZZ HVK Test Harness}"
SSH_USER="${SSH_USER:-ubuntu}"
SOLANA_CLUSTER="${SOLANA_CLUSTER:-testnet}"
AGAVE_VERSION="${AGAVE_VERSION:-3.1.10}"
BAM_JITO_VERSION="${BAM_JITO_VERSION:-3.1.10}"
BAM_JITO_VERSION_PATCH="${BAM_JITO_VERSION_PATCH:-}"
FIREDANCER_VERSION="${FIREDANCER_VERSION:-0.910.40000}"
FIREDANCER_XDP_ZERO_COPY="${FIREDANCER_XDP_ZERO_COPY:-false}"
VALIDATOR_NAME="${VALIDATOR_NAME:-hayek-lat-swap}"
AUTHORIZED_IPS_INPUT="${AUTHORIZED_IPS_INPUT:-}"
POST_METAL_SSH_PORT="${POST_METAL_SSH_PORT:-2522}"
CONTINUE_ON_ERROR=false
RETAIN_ON_FAILURE=false
RETAIN_ALWAYS=false
CASE_FILTER=""

usage() {
  cat <<'EOF'
Usage:
  run-latitude-hot-swap-matrix.sh [options]

Provision two Latitude bare-metal hosts and run the Frankendancer hot-swap
identity transfer matrix. Each case provisions a fresh source+destination pair,
runs the hot-swap playbook, verifies identity state, then tears both hosts down.

Options:
  --workdir <path>                       (default: ./test-harness/work/latitude-hot-swap)
  --run-id-prefix <id>                   (default: latitude-hot-swap)
  --operator-name <name>                 (required; or set LATITUDE_OPERATOR_NAME)
  --operator-ssh-public-key-file <path>  (required; or set LATITUDE_OPERATOR_SSH_PUBLIC_KEY_FILE)
  --operator-ssh-private-key-file <path> (required; or set LATITUDE_OPERATOR_SSH_PRIVATE_KEY_FILE)
  --plan <slug>                          Machine plan for Latitude (default: m4-metal-medium)
                                         Override with FIREDANCER_LATITUDE_PLAN env var.
  --project <name>                       (default: ZZZ HVK Test Harness)
  --ssh-user <name>                      (default: ubuntu)
  --solana-cluster <name>                (default: testnet)
  --agave-version <semver>               (default: 3.1.10)
  --bam-jito-version <semver>            (default: 3.1.10)
  --bam-jito-version-patch <suffix>      (default: unset)
  --firedancer-version <version>         (default: 0.910.40000)
  --firedancer-xdp-zero-copy             Enable XDP zero-copy for Frankendancer (default: false)
                                         Verify hardware support first with pb_validate_xdp_shared.yml
  --validator-name <name>                (default: hayek-lat-swap)
  --authorized-ips <csv>                 Comma-separated IPs allowed through firewall
                                         (auto-detected via ifconfig.me if unset)
  --case <name>                          Run only this case (repeatable; default: all cases)
  --continue-on-error                    Continue matrix on case failure
  --retain-on-failure                    Keep servers on failure for debugging
  --retain-always                        Never tear down servers

Cases run (all by default; filter with --case):
  jito_bam_to_frankendancer  (jito-bam -> frankendancer)
  frankendancer_to_jito_bam  (frankendancer -> jito-bam)
EOF
}

while (($# > 0)); do
  case "$1" in
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    --run-id-prefix) RUN_ID_PREFIX="${2:-}"; shift 2 ;;
    --operator-name) OPERATOR_NAME="${2:-}"; shift 2 ;;
    --operator-ssh-public-key-file) OPERATOR_SSH_PUBLIC_KEY_FILE="${2:-}"; shift 2 ;;
    --operator-ssh-private-key-file) OPERATOR_SSH_PRIVATE_KEY_FILE="${2:-}"; shift 2 ;;
    --plan) PLAN="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --ssh-user) SSH_USER="${2:-}"; shift 2 ;;
    --solana-cluster) SOLANA_CLUSTER="${2:-}"; shift 2 ;;
    --agave-version) AGAVE_VERSION="${2:-}"; shift 2 ;;
    --bam-jito-version) BAM_JITO_VERSION="${2:-}"; shift 2 ;;
    --bam-jito-version-patch) BAM_JITO_VERSION_PATCH="${2:-}"; shift 2 ;;
    --firedancer-version) FIREDANCER_VERSION="${2:-}"; shift 2 ;;
    --firedancer-xdp-zero-copy) FIREDANCER_XDP_ZERO_COPY=true; shift ;;
    --validator-name) VALIDATOR_NAME="${2:-}"; shift 2 ;;
    --authorized-ips) AUTHORIZED_IPS_INPUT="${2:-}"; shift 2 ;;
    --case) CASE_FILTER="${CASE_FILTER:+${CASE_FILTER},}${2:-}"; shift 2 ;;
    --continue-on-error) CONTINUE_ON_ERROR=true; shift ;;
    --retain-on-failure) RETAIN_ON_FAILURE=true; shift ;;
    --retain-always) RETAIN_ALWAYS=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

for var in OPERATOR_NAME OPERATOR_SSH_PUBLIC_KEY_FILE OPERATOR_SSH_PRIVATE_KEY_FILE; do
  [[ -n "${!var}" ]] || { echo "ERROR: --${var//_/-} is required" >&2; usage; exit 2; }
done

# Build common group_vars -e "@..." args, mirroring verify-vm-hot-swap.sh's pattern.
# These load all.yml + solana.yml + cluster-specific + city vars regardless of
# where the inventory lives (Ansible only auto-discovers group_vars relative to
# the inventory/playbook directory; ours lives in a temp case dir).
_CLUSTER_NORMALIZED="${SOLANA_CLUSTER}"
_CLUSTER_VARS_FILE="$REPO_ROOT/ansible/group_vars/solana_${_CLUSTER_NORMALIZED}.yml"
_CITY_VARS_FILE="$REPO_ROOT/ansible/group_vars/city_fra.yml"  # Latitude FRA is the default site

if [[ ! -r "$_CLUSTER_VARS_FILE" ]]; then
  echo "ERROR: Cluster vars file not readable: $_CLUSTER_VARS_FILE" >&2; exit 2
fi

COMMON_ANSIBLE_EXTRA_VARS_ARGS=(
  -e "@$REPO_ROOT/ansible/group_vars/all.yml"
  -e "@$REPO_ROOT/ansible/group_vars/solana.yml"
  -e "@$_CLUSTER_VARS_FILE"
  -e "@$_CITY_VARS_FILE"
)

all_cases=(
  "jito_bam_to_frankendancer:jito-bam:frankendancer"
  "frankendancer_to_jito_bam:frankendancer:jito-bam"
)

if [[ -n "$CASE_FILTER" ]]; then
  cases=()
  IFS=',' read -ra _filter_names <<<"$CASE_FILTER"
  for _entry in "${all_cases[@]}"; do
    _name="${_entry%%:*}"
    for _f in "${_filter_names[@]}"; do
      if [[ "$_name" == "$_f" ]]; then
        cases+=("$_entry")
        break
      fi
    done
  done
  if [[ "${#cases[@]}" -eq 0 ]]; then
    echo "ERROR: --case filter matched no cases. Valid cases: $(IFS=', '; echo "${all_cases[*]%%:*}")" >&2
    exit 2
  fi
else
  cases=("${all_cases[@]}")
fi

pass_count=0
fail_count=0

run_case() {
  local case_name="$1"
  local source_flavor="$2"
  local destination_flavor="$3"
  local run_id="${RUN_ID_PREFIX}-${case_name}-$(date +%Y%m%d-%H%M%S)"
  local case_dir="$WORKDIR/$run_id"
  local src_state_dir="$case_dir/source"
  local dst_state_dir="$case_dir/destination"
  local ssh_key_file="$OPERATOR_SSH_PRIVATE_KEY_FILE"
  # Embed the first 8 chars of each server's *flavor* (not the case name) in the scenario.
  # This ensures:
  #  1. Cross-case uniqueness: retained servers don't collide because RUN_ID:0:12 is always
  #     "latitude-hot" (same RUN_ID_PREFIX), so the scenario slug is the only differentiator.
  #  2. Names reflect what runs on each host — jito-bam source gets "jito-bam" in its name,
  #     frankendancer destination gets "frankend", not the same "frankend" for both.
  #
  # Full matrix with --retain-always (all 4 servers live simultaneously):
  #   jito_bam_to_frankendancer: hvk-<op>-hs-src-jito-bam-latitude-hot
  #                              hvk-<op>-hs-dst-frankend-latitude-hot
  #   frankendancer_to_jito_bam: hvk-<op>-hs-src-frankend-latitude-hot
  #                              hvk-<op>-hs-dst-jito-bam-latitude-hot
  local _common_base_args=(
    --operator-name "$OPERATOR_NAME"
    --operator-ssh-public-key-file "$OPERATOR_SSH_PUBLIC_KEY_FILE"
    --operator-ssh-private-key-file "$OPERATOR_SSH_PRIVATE_KEY_FILE"
    --plan "$PLAN"
    --project "$PROJECT"
    --ssh-user "$SSH_USER"
  )
  local src_target_args=(--scenario "hs-src-${source_flavor:0:8}" "${_common_base_args[@]}")
  local dst_target_args=(--scenario "hs-dst-${destination_flavor:0:8}" "${_common_base_args[@]}")

  echo "==> [latitude-hot-swap] Case: $case_name ($source_flavor -> $destination_flavor)" >&2
  mkdir -p "$src_state_dir" "$dst_state_dir"

  # Provision source and destination hosts
  echo "[latitude-hot-swap] Provisioning source host ($source_flavor)..." >&2
  "$REPO_ROOT/test-harness/targets/latitude.sh" up \
    --run-id "${run_id}-source" \
    --workdir "$src_state_dir" \
    "${src_target_args[@]}" >&2 || return 1

  echo "[latitude-hot-swap] Provisioning destination host ($destination_flavor)..." >&2
  "$REPO_ROOT/test-harness/targets/latitude.sh" up \
    --run-id "${run_id}-destination" \
    --workdir "$dst_state_dir" \
    "${dst_target_args[@]}" >&2 || return 1

  # Wait for both hosts to accept SSH on port 22
  "$REPO_ROOT/test-harness/targets/latitude.sh" wait \
    --run-id "${run_id}-source" --workdir "$src_state_dir" "${src_target_args[@]}" >&2 || return 1
  "$REPO_ROOT/test-harness/targets/latitude.sh" wait \
    --run-id "${run_id}-destination" --workdir "$dst_state_dir" "${dst_target_args[@]}" >&2 || return 1

  # Get inventory from each host
  local src_inv_json dst_inv_json
  src_inv_json="$("$REPO_ROOT/test-harness/targets/latitude.sh" inventory \
    --run-id "${run_id}-source" --workdir "$src_state_dir" "${src_target_args[@]}")" || return 1
  dst_inv_json="$("$REPO_ROOT/test-harness/targets/latitude.sh" inventory \
    --run-id "${run_id}-destination" --workdir "$dst_state_dir" "${dst_target_args[@]}")" || return 1

  local src_host dst_host
  src_host="$(echo "$src_inv_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["primary_ip"])')" || return 1
  dst_host="$(echo "$dst_inv_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["primary_ip"])')" || return 1

  echo "[latitude-hot-swap] Source: ${src_host}, Destination: ${dst_host}" >&2

  # Symlink ansible/group_vars into case_dir so Ansible loads them relative to the inventory files.
  # Ansible searches group_vars/ in both the playbook directory and the inventory directory;
  # our inventories live in case_dir, which is outside ansible/, so we need this symlink.
  ln -sfn "$REPO_ROOT/ansible/group_vars" "$case_dir/group_vars"

  # Generate IAM CSV for pb_setup_users_validator (users created during common host setup)
  local operator_ssh_pub_key
  operator_ssh_pub_key="$(cat "$OPERATOR_SSH_PUBLIC_KEY_FILE")"
  local iam_csv="$case_dir/iam.csv"
  cat >"$iam_csv" <<IAM_EOF
user,key,group_a,group_b,group_c
alice,${operator_ssh_pub_key},sysadmin,,
operator,${operator_ssh_pub_key},validator_operators,,
sol,,,,
IAM_EOF

  # Generate authorized IPs CSV for pb_setup_metal_box UFW rules
  local authorized_ips_csv="$case_dir/authorized_ips.csv"
  printf 'ip,comment\n' >"$authorized_ips_csv"
  if [[ -n "$AUTHORIZED_IPS_INPUT" ]]; then
    IFS=',' read -ra _ips <<<"$AUTHORIZED_IPS_INPUT"
    for _ip in "${_ips[@]}"; do
      printf '%s,operator-provided\n' "${_ip// /}" >>"$authorized_ips_csv"
    done
  else
    local _control_ip
    _control_ip="$(curl -sf --max-time 5 https://ifconfig.me 2>/dev/null || true)"
    if [[ -n "$_control_ip" ]]; then
      echo "[latitude-hot-swap] Auto-detected control-plane IP: ${_control_ip}" >&2
      printf '%s,control-plane\n' "$_control_ip" >>"$authorized_ips_csv"
    else
      echo "[latitude-hot-swap] WARNING: Could not detect public IP; firewall may block control-plane access." >&2
    fi
  fi

  # Bootstrap inventory — port 22, initial ubuntu user (pre-metal-box hardening)
  local bootstrap_inventory="$case_dir/bootstrap-inventory.yml"
  cat >"$bootstrap_inventory" <<BOOTSTRAP_EOF
all:
  hosts:
    lat-source:
      ansible_host: ${src_host}
      ansible_port: 22
      ansible_ssh_private_key_file: ${ssh_key_file}
      ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      ansible_become: true
      validator_keyset_name: ${VALIDATOR_NAME}-lat-source
    lat-destination:
      ansible_host: ${dst_host}
      ansible_port: 22
      ansible_ssh_private_key_file: ${ssh_key_file}
      ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      ansible_become: true
      validator_keyset_name: ${VALIDATOR_NAME}-lat-destination
  children:
    solana:
      hosts:
        lat-source:
        lat-destination:
BOOTSTRAP_EOF

  # Operator inventory — port 2522, operator user (post-metal-box hardening)
  local operator_inventory="$case_dir/operator-inventory.yml"
  cat >"$operator_inventory" <<OPERATOR_EOF
all:
  hosts:
    lat-source:
      ansible_host: ${src_host}
      ansible_port: ${POST_METAL_SSH_PORT}
      ansible_user: operator
      ansible_ssh_private_key_file: ${ssh_key_file}
      ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      ansible_become: true
      validator_keyset_name: ${VALIDATOR_NAME}-lat-source
    lat-destination:
      ansible_host: ${dst_host}
      ansible_port: ${POST_METAL_SSH_PORT}
      ansible_user: operator
      ansible_ssh_private_key_file: ${ssh_key_file}
      ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      ansible_become: true
      validator_keyset_name: ${VALIDATOR_NAME}-lat-destination
  children:
    solana:
      hosts:
        lat-source:
        lat-destination:
OPERATOR_EOF

  # Common args for pb_setup_validator_host_common.yml (bootstrap phase)
  # This playbook: creates users → hardens host (SSH→2522, UFW) → installs validator → installs HA
  local _common_setup_base=(
    --limit "REPLACE_HOST"
    -e "target_host=REPLACE_HOST"
    -e "bootstrap_user=${SSH_USER}"
    -e "metal_box_user=alice"
    -e "validator_operator_user=operator"
    -e "validator_name=$VALIDATOR_NAME"
    -e "solana_cluster=$SOLANA_CLUSTER"
    -e "post_metal_ssh_port=$POST_METAL_SSH_PORT"
    -e "password_handoff_mode=assume_ready"
    -e "build_from_source=true"
    -e "use_official_repo=true"
    -e "solana_validator_ha_version=0.1.19"
    -e "solana_validator_ha_install_from_source=false"
    -e "force_host_cleanup=false"
    -e "skip_confirmation_pauses=true"
    -e "xdp_enabled=false"
    -e "manage_cpu_governor_service=false"
    -e "users_csv_file=$(basename "$iam_csv")"
    -e "users_base_dir=$(dirname "$iam_csv")"
    -e "authorized_ips_csv_file=$(basename "$authorized_ips_csv")"
    -e "authorized_access_csv=$authorized_ips_csv"
  )

  local src_common_args=(-i "$bootstrap_inventory")
  local dst_common_args=(-i "$bootstrap_inventory")
  for arg in "${_common_setup_base[@]}"; do
    src_common_args+=("${arg/REPLACE_HOST/lat-source}")
    dst_common_args+=("${arg/REPLACE_HOST/lat-destination}")
  done
  src_common_args+=(-e "validator_keyset_name=${VALIDATOR_NAME}-lat-source")
  dst_common_args+=(-e "validator_keyset_name=${VALIDATOR_NAME}-lat-destination")

  # Stop any in-flight unattended-upgrades and install psmisc before common setup.
  # Two issues on fresh Ubuntu 24.04 Latitude servers:
  #   1) unattended-upgrades starts on first boot and holds the apt lock; server_initial_setup
  #      waits up to 10 min for it to finish. Stopping it here drains that wait immediately.
  #      `systemctl stop` blocks until the service actually exits, so the apt lock is clear
  #      by the time we proceed.
  #   2) server_initial_setup's apt-lock check requires `fuser` (psmisc package) which is
  #      not pre-installed. Without it the check exits rc=2 on every retry and always fails.
  echo "[latitude-hot-swap] Stopping unattended-upgrades on both hosts (blocks until complete)..." >&2
  ansible -i "$bootstrap_inventory" "lat-source,lat-destination" \
    -u "$SSH_USER" --become \
    -m ansible.builtin.systemd \
    -a "name=unattended-upgrades state=stopped" >&2 || true

  echo "[latitude-hot-swap] Installing psmisc (fuser) and jq on both hosts..." >&2
  ansible -i "$bootstrap_inventory" "lat-source,lat-destination" \
    -u "$SSH_USER" --become \
    -m ansible.builtin.apt \
    -a "name=psmisc,jq state=present" >&2 || return 1

  # Grant NOPASSWD sudo to %sysadmin and %validator_operators before user creation.
  # pb_setup_metal_box.yml runs as alice (sysadmin) which needs sudo without a password.
  # Writing the sudoers.d rule now (as ubuntu) means it's in place when alice is created.
  echo "[latitude-hot-swap] Preparing NOPASSWD sudo policy for automation on both hosts..." >&2
  ansible-playbook \
    -i "$bootstrap_inventory" \
    "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
    -e "target_hosts=lat-source,lat-destination" \
    -e "bootstrap_user=${SSH_USER}" \
    "$REPO_ROOT/test-harness/ansible/pb_prepare_vm_sysadmin_nopasswd.yml" || return 1

  # Generate ephemeral keypairs for each host.
  # solana_validator_jito_v2 and solana_validator_firedancer precheck expect:
  #   ~/.validator-keys/<keyset_name>/{primary-target-identity,vote-account,hot-spare-identity}.json
  echo "[latitude-hot-swap] Generating ephemeral keypairs for source and destination..." >&2
  _ensure_keyset "${VALIDATOR_NAME}-lat-source" || return 1
  _ensure_keyset "${VALIDATOR_NAME}-lat-destination" || return 1

  echo "[latitude-hot-swap] Running common host setup for source ($source_flavor)..." >&2
  _run_common_setup "$source_flavor" "${src_common_args[@]}" "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" || return 1

  echo "[latitude-hot-swap] Running common host setup for destination ($destination_flavor)..." >&2
  _run_common_setup "$destination_flavor" "${dst_common_args[@]}" "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" || return 1

  # Derive client values for swap role
  local source_client destination_client
  source_client="$(_ha_client_for_flavor "$source_flavor")"
  destination_client="$(_ha_client_for_flavor "$destination_flavor")"

  echo "[latitude-hot-swap] Running hot-swap playbook ($source_flavor -> $destination_flavor)..." >&2
  ansible-playbook \
    -i "$operator_inventory" \
    "${COMMON_ANSIBLE_EXTRA_VARS_ARGS[@]}" \
    "$REPO_ROOT/ansible/playbooks/pb_hot_swap_validator_hosts_v2.yml" \
    -e "source_host=lat-source" \
    -e "destination_host=lat-destination" \
    -e "source_client=$source_client" \
    -e "destination_client=$destination_client" \
    -e "operator_user=operator" \
    -e "auto_confirm_swap=true" \
    -e "deprovision_source_host=false" \
    -e "swap_epoch_end_threshold_sec=0" \
    -e "manage_destination_ufw_peer_ssh_rule=true" \
    -e "solana_cluster=$SOLANA_CLUSTER" || return 1

  echo "[latitude-hot-swap] PASS: $case_name" >&2
}

_ensure_keyset() {
  local keyset_name="$1"
  local keyset_dir="$HOME/.validator-keys/$keyset_name"
  # primary-target-identity and vote-account are shared across all hosts in a swap pair —
  # they represent the validator being swapped, not the host. Generate them once in the
  # base VALIDATOR_NAME keyset and copy into each host-specific keyset. hot-spare-identity
  # is unique per host (each standby has its own ephemeral identity).
  local shared_dir="$HOME/.validator-keys/$VALIDATOR_NAME"

  mkdir -p "$shared_dir" "$keyset_dir"

  for key in primary-target-identity vote-account; do
    local shared_keyfile="$shared_dir/${key}.json"
    if [[ ! -f "$shared_keyfile" ]]; then
      solana-keygen new --no-bip39-passphrase --force --silent -o "$shared_keyfile"
    fi
    cp -f "$shared_keyfile" "$keyset_dir/${key}.json"
  done

  local hot_spare="$keyset_dir/hot-spare-identity.json"
  if [[ ! -f "$hot_spare" ]]; then
    solana-keygen new --no-bip39-passphrase --force --silent -o "$hot_spare"
  fi

  echo "[latitude-hot-swap] Keypairs ready in $keyset_dir (primary shared from $shared_dir)" >&2
}

_ha_client_for_flavor() {
  local flavor="$1"
  case "$flavor" in
    agave)           echo "agave" ;;
    jito-bam)        echo "jito" ;;
    frankendancer)   echo "firedancer" ;;
    *) echo "agave" ;;
  esac
}

# Run pb_setup_validator_host_common.yml for a given flavor.
# Handles the full bootstrap: users → metal-box hardening → validator install → HA install.
_run_common_setup() {
  local flavor="$1"
  shift
  local base_args=("$@")

  case "$flavor" in
    agave)
      ansible-playbook "${base_args[@]}" \
        -e "validator_flavor=agave" \
        -e "agave_version=$AGAVE_VERSION" \
        "$REPO_ROOT/ansible/playbooks/pb_setup_validator_host_common.yml"
      ;;
    jito-bam)
      if [[ -n "$BAM_JITO_VERSION_PATCH" ]]; then
        ansible-playbook "${base_args[@]}" \
          -e "validator_flavor=jito-bam" \
          -e "jito_version=$BAM_JITO_VERSION" \
          -e "jito_version_patch=$BAM_JITO_VERSION_PATCH" \
          "$REPO_ROOT/ansible/playbooks/pb_setup_validator_host_common.yml"
      else
        ansible-playbook "${base_args[@]}" \
          -e "validator_flavor=jito-bam" \
          -e "jito_version=$BAM_JITO_VERSION" \
          "$REPO_ROOT/ansible/playbooks/pb_setup_validator_host_common.yml"
      fi
      ;;
    frankendancer)
      ansible-playbook "${base_args[@]}" \
        -e "validator_flavor=frankendancer" \
        -e "firedancer_version=$FIREDANCER_VERSION" \
        -e "firedancer_xdp_zero_copy=$FIREDANCER_XDP_ZERO_COPY" \
        "$REPO_ROOT/ansible/playbooks/pb_setup_validator_host_common.yml"
      ;;
    *)
      echo "ERROR: Unsupported flavor: $flavor" >&2
      return 2
      ;;
  esac
}

teardown_case_hosts() {
  local run_id="$1"
  local case_dir="$WORKDIR/$run_id"
  local _base_args=(
    --operator-name "$OPERATOR_NAME"
    --operator-ssh-public-key-file "$OPERATOR_SSH_PUBLIC_KEY_FILE"
    --operator-ssh-private-key-file "$OPERATOR_SSH_PRIVATE_KEY_FILE"
    --plan "$PLAN"
    --project "$PROJECT"
  )

  echo "[latitude-hot-swap] Tearing down case hosts for run $run_id..." >&2
  "$REPO_ROOT/test-harness/targets/latitude.sh" down \
    --run-id "${run_id}-source" \
    --workdir "$case_dir/source" \
    --scenario "hs-src" \
    "${_base_args[@]}" 2>/dev/null || true
  "$REPO_ROOT/test-harness/targets/latitude.sh" down \
    --run-id "${run_id}-destination" \
    --workdir "$case_dir/destination" \
    --scenario "hs-dst" \
    "${_base_args[@]}" 2>/dev/null || true
}

mkdir -p "$WORKDIR"

for case_entry in "${cases[@]}"; do
  IFS=':' read -r case_name source_flavor destination_flavor <<<"$case_entry"
  run_id="${RUN_ID_PREFIX}-${case_name}-$(date +%Y%m%d-%H%M%S)"

  case_passed=false
  if run_case "$case_name" "$source_flavor" "$destination_flavor"; then
    case_passed=true
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $case_name" >&2
  fi

  if [[ "$RETAIN_ALWAYS" == true ]]; then
    echo "[latitude-hot-swap] Retaining hosts (--retain-always)." >&2
  elif [[ "$RETAIN_ON_FAILURE" == true && "$case_passed" == false ]]; then
    echo "[latitude-hot-swap] Retaining hosts after failure (--retain-on-failure)." >&2
  else
    teardown_case_hosts "$run_id"
  fi

  if [[ "$case_passed" == false && "$CONTINUE_ON_ERROR" != true ]]; then
    break
  fi
done

echo "" >&2
echo "==> [latitude-hot-swap] Matrix complete: ${pass_count} passed, ${fail_count} failed." >&2
[[ "$fail_count" -eq 0 ]]

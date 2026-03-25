#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

COMPOSE_ENGINE="${COMPOSE_ENGINE:-docker}"
INVENTORY_PATH=""
SOURCE_HOST="${SOURCE_HOST:-host-alpha}"
DESTINATION_HOST="${DESTINATION_HOST:-host-bravo}"
SOURCE_FLAVOR=""
DESTINATION_FLAVOR=""
VALIDATOR_NAME="${VALIDATOR_NAME:-demo1}"
OPERATOR_USER="${OPERATOR_USER:-ubuntu}"
SOLANA_CLUSTER="${SOLANA_CLUSTER:-localnet}"

AGAVE_VERSION="${AGAVE_VERSION:-3.1.10}"
JITO_VERSION="${JITO_VERSION:-2.3.6}"
BAM_JITO_VERSION="${BAM_JITO_VERSION:-3.1.10}"
BAM_JITO_VERSION_PATCH="${BAM_JITO_VERSION_PATCH:-}"
BAM_EXPECT_CLIENT_REGEX="${BAM_EXPECT_CLIENT_REGEX:-Bam}"

BUILD_FROM_SOURCE="${BUILD_FROM_SOURCE:-false}"
FORCE_HOST_CLEANUP="${FORCE_HOST_CLEANUP:-true}"
SWAP_EPOCH_END_THRESHOLD_SEC="${SWAP_EPOCH_END_THRESHOLD_SEC:-0}"
SOLANA_VALIDATOR_HA_RUNTIME_ENABLED="${SOLANA_VALIDATOR_HA_RUNTIME_ENABLED:-false}"
SOLANA_VALIDATOR_HA_RECONCILE_GROUP="${SOLANA_VALIDATOR_HA_RECONCILE_GROUP:-ha_compose_hot_swap}"
SOLANA_VALIDATOR_HA_SOURCE_NODE_ID="${SOLANA_VALIDATOR_HA_SOURCE_NODE_ID:-ark}"
SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID="${SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID:-fog}"
SOLANA_VALIDATOR_HA_SOURCE_PRIORITY="${SOLANA_VALIDATOR_HA_SOURCE_PRIORITY:-10}"
SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY="${SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY:-20}"
VERIFY_HA_RECONCILE_ONLY="${VERIFY_HA_RECONCILE_ONLY:-false}"
VERIFY_HA_RECONCILE_NOOP="${VERIFY_HA_RECONCILE_NOOP:-false}"

usage() {
  cat <<'EOF'
Usage:
  verify-compose-hot-swap.sh --inventory <path> --source-flavor <flavor> --destination-flavor <flavor> [options]

Required:
  --inventory <path>
  --source-flavor <agave|jito-shared|jito-cohosted|jito-bam>
  --destination-flavor <agave|jito-shared|jito-cohosted|jito-bam>

Optional:
  --compose-engine <docker|podman>      (default: docker)
  --source-host <name>                  (default: host-alpha)
  --destination-host <name>             (default: host-bravo)
  --validator-name <name>               (default: demo1)
  --operator-user <name>                (default: ubuntu)
EOF
}

while (($# > 0)); do
  case "$1" in
    --inventory)
      INVENTORY_PATH="${2:-}"
      shift 2
      ;;
    --compose-engine)
      COMPOSE_ENGINE="${2:-}"
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
    --source-flavor)
      SOURCE_FLAVOR="${2:-}"
      shift 2
      ;;
    --destination-flavor)
      DESTINATION_FLAVOR="${2:-}"
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

if [[ -z "$INVENTORY_PATH" || -z "$SOURCE_FLAVOR" || -z "$DESTINATION_FLAVOR" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$INVENTORY_PATH" ]]; then
  echo "Inventory not found: $INVENTORY_PATH" >&2
  exit 2
fi

INVENTORY_PATH="$(realpath "$INVENTORY_PATH")"

case "$COMPOSE_ENGINE" in
  docker)
    COMPOSE_BIN="docker"
    COMPOSE_OVERRIDE="$REPO_ROOT/solana-localnet/docker-compose.docker.yml"
    ;;
  podman)
    COMPOSE_BIN="podman"
    COMPOSE_OVERRIDE="$REPO_ROOT/solana-localnet/docker-compose.podman.yml"
    ;;
  *)
    echo "Unsupported compose engine: $COMPOSE_ENGINE" >&2
    exit 2
    ;;
esac

COMPOSE_BASE="$REPO_ROOT/solana-localnet/docker-compose.yml"
CONTAINER_REPO_ROOT="/hayek-validator-kit"

compose_exec() {
  "$COMPOSE_BIN" compose -f "$COMPOSE_BASE" -f "$COMPOSE_OVERRIDE" --profile localnet "$@"
}

control_exec() {
  local cmd="$1"
  compose_exec exec -T ansible-control-localnet bash -lc "$cmd"
}

container_path() {
  local host_path="$1"
  if [[ "$host_path" == "$REPO_ROOT/"* ]]; then
    printf '%s/%s\n' "$CONTAINER_REPO_ROOT" "${host_path#"$REPO_ROOT"/}"
  else
    printf '%s\n' "$host_path"
  fi
}

CONTAINER_INVENTORY="$(container_path "$INVENTORY_PATH")"
HA_INVENTORY_PATH=""
CONTAINER_HA_INVENTORY=""

ansible_in_control() {
  local cmd="$1"
  control_exec "cd $CONTAINER_REPO_ROOT/ansible && $cmd"
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

setup_host_flavor() {
  local host="$1"
  local flavor="$2"
  local validator_type="$3"
  local base_extra
  local playbook=""

  base_extra="-e target_host=$host -e ansible_user=$OPERATOR_USER -e validator_name=$VALIDATOR_NAME -e validator_type=$validator_type -e xdp_enabled=true -e solana_cluster=$SOLANA_CLUSTER -e build_from_source=$BUILD_FROM_SOURCE -e force_host_cleanup=$FORCE_HOST_CLEANUP"

  case "$flavor" in
    agave)
      playbook="$CONTAINER_REPO_ROOT/ansible/playbooks/pb_setup_validator_agave.yml"
      ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$playbook' --limit '$host' $base_extra -e agave_version=$AGAVE_VERSION"
      ;;
    jito-shared)
      playbook="$CONTAINER_REPO_ROOT/ansible/playbooks/pb_setup_validator_jito_v2.yml"
      ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$playbook' --limit '$host' $base_extra -e jito_version=$JITO_VERSION"
      ;;
    jito-cohosted)
      playbook="$CONTAINER_REPO_ROOT/ansible/playbooks/pb_setup_validator_jito_v2.yml"
      ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$playbook' --limit '$host' $base_extra -e jito_version=$JITO_VERSION"
      ;;
    jito-bam)
      playbook="$CONTAINER_REPO_ROOT/ansible/playbooks/pb_setup_validator_jito_v2.yml"
      if [[ -n "$BAM_JITO_VERSION_PATCH" ]]; then
        ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$playbook' --limit '$host' $base_extra -e jito_version=$BAM_JITO_VERSION -e jito_version_patch=$BAM_JITO_VERSION_PATCH"
      else
        ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$playbook' --limit '$host' $base_extra -e jito_version=$BAM_JITO_VERSION"
      fi
      ;;
    *)
      echo "Unsupported flavor: $flavor" >&2
      exit 2
      ;;
  esac
}

build_ha_inventory() {
  local source_json destination_json
  local source_host_ip destination_host_ip
  local source_host_port destination_host_port

  source_json="$(ansible_in_control "ansible-inventory -i '$CONTAINER_INVENTORY' --host '$SOURCE_HOST'")"
  destination_json="$(ansible_in_control "ansible-inventory -i '$CONTAINER_INVENTORY' --host '$DESTINATION_HOST'")"

  source_host_ip="$(jq -r '.ansible_host' <<<"$source_json")"
  destination_host_ip="$(jq -r '.ansible_host' <<<"$destination_json")"
  source_host_port="$(jq -r '.ansible_port // 22' <<<"$source_json")"
  destination_host_port="$(jq -r '.ansible_port // 22' <<<"$destination_json")"

  mkdir -p "$REPO_ROOT/ansible"
  HA_INVENTORY_PATH="$(mktemp "$REPO_ROOT/ansible/compose-ha-inventory.XXXXXX.yml")"
  CONTAINER_HA_INVENTORY="$(container_path "$HA_INVENTORY_PATH")"

  cat >"$HA_INVENTORY_PATH" <<EOF
all:
  hosts:
    ${SOURCE_HOST}:
      ansible_host: ${source_host_ip}
      ansible_port: ${source_host_port}
      ansible_user: ${OPERATOR_USER}
      solana_validator_ha_public_ip_value: ${source_host_ip}
      solana_validator_ha_node_id: ${SOLANA_VALIDATOR_HA_SOURCE_NODE_ID}
      solana_validator_ha_priority: ${SOLANA_VALIDATOR_HA_SOURCE_PRIORITY}
    ${DESTINATION_HOST}:
      ansible_host: ${destination_host_ip}
      ansible_port: ${destination_host_port}
      ansible_user: ${OPERATOR_USER}
      solana_validator_ha_public_ip_value: ${destination_host_ip}
      solana_validator_ha_node_id: ${SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID}
      solana_validator_ha_priority: ${SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY}
  children:
    solana:
      hosts:
        ${SOURCE_HOST}:
        ${DESTINATION_HOST}:
    solana_localnet:
      hosts:
        ${SOURCE_HOST}:
        ${DESTINATION_HOST}:
    ${SOLANA_VALIDATOR_HA_RECONCILE_GROUP}:
      vars:
        solana_validator_ha_inventory_group: ${SOLANA_VALIDATOR_HA_RECONCILE_GROUP}
      hosts:
        ${SOURCE_HOST}:
        ${DESTINATION_HOST}:
EOF
}

reconcile_validator_ha_cluster() {
  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$CONTAINER_REPO_ROOT/ansible/playbooks/pb_reconcile_validator_ha_cluster.yml' -e target_ha_group=$SOLANA_VALIDATOR_HA_RECONCILE_GROUP -e operator_user=$OPERATOR_USER -e validator_name=$VALIDATOR_NAME -e solana_cluster=$SOLANA_CLUSTER -e ha_reconcile_mode=in_place -e ha_enforce_hostname_prefix=false"
}

host_systemd_main_pid() {
  local host="$1"
  local service="$2"
  local pid_cmd
  pid_cmd="set -euo pipefail; systemctl show '$service' --property MainPID --value"
  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$host' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m shell -a \"$pid_cmd\" -o" \
    | awk -F' \\(stdout\\) ' 'NF > 1 { print $2 }' \
    | tail -n 1 \
    | tr -d '\r'
}

assert_same_value() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "$label changed unexpectedly: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_host_client() {
  local host="$1"
  local flavor="$2"
  local expected_regex
  local output
  local version_cmd
  expected_regex="$(expected_client_regex_for_flavor "$flavor")"
  version_cmd="set -euo pipefail; bindir='/opt/solana/active_release/bin'; if [ -x \"\$bindir/solana\" ]; then \"\$bindir/solana\" --version; elif [ -x \"\$bindir/agave-validator\" ]; then \"\$bindir/agave-validator\" --version; elif [ -x \"\$bindir/solana-validator\" ]; then \"\$bindir/solana-validator\" --version; else echo 'No validator version command found in' \"\$bindir\" >&2; exit 1; fi"
  output="$(
    ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$host' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m shell -a \"$version_cmd\" -o"
  )"
  if ! grep -Eq "$expected_regex" <<<"$output"; then
    echo "Host $host does not match expected flavor '$flavor' (pattern: $expected_regex)" >&2
    echo "$output" >&2
    exit 1
  fi
}

assert_host_validator_runtime() {
  local host="$1"
  local service_cmd

  service_cmd="set -euo pipefail; systemctl is-active --quiet sol; status=\$(systemctl show sol --property=ActiveState --property=SubState --property=ExecMainStatus --value --no-pager | tr '\n' ' '); case \"\$status\" in *failed*|*inactive* ) echo \"Validator service unhealthy: \$status\" >&2; exit 1 ;; esac"

  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$host' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m shell -a \"$service_cmd\" -o" >/dev/null
  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$host' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m wait_for -a 'host=127.0.0.1 port=8899 timeout=30 state=started' -o" >/dev/null
}

assert_host_ha_runtime_config() {
  local host="$1"
  local expected_node_id="$2"
  local expected_priority="$3"
  local expected_peer_node_id="$4"
  local expected_peer_ip="$5"
  local expected_peer_priority="$6"
  local config_cmd

  config_cmd="set -euo pipefail; cfg='/opt/validator/ha/config.yaml'; test -f \"\$cfg\"; grep -F 'name: \"${expected_node_id}\"' \"\$cfg\" >/dev/null; grep -F 'priority: ${expected_priority}' \"\$cfg\" >/dev/null; grep -F '${expected_peer_node_id}:' \"\$cfg\" >/dev/null; grep -F 'ip: \"${expected_peer_ip}\"' \"\$cfg\" >/dev/null; grep -F 'priority: ${expected_peer_priority}' \"\$cfg\" >/dev/null"
  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$host' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m shell -a \"$config_cmd\" -o" >/dev/null
}

assert_swap_identity_state() {
  local source_cmd
  local destination_cmd
  source_cmd="set -euo pipefail; kdir='/opt/validator/keys/$VALIDATOR_NAME'; run=\$(/opt/solana/active_release/bin/solana-keygen pubkey \"\$kdir/identity.json\"); hot=\$(/opt/solana/active_release/bin/solana-keygen pubkey \"\$kdir/hot-spare-identity.json\"); test \"\$run\" = \"\$hot\""
  destination_cmd="set -euo pipefail; kdir='/opt/validator/keys/$VALIDATOR_NAME'; run=\$(/opt/solana/active_release/bin/solana-keygen pubkey \"\$kdir/identity.json\"); primary=\$(/opt/solana/active_release/bin/solana-keygen pubkey \"\$kdir/primary-target-identity.json\"); test \"\$run\" = \"\$primary\""

  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$SOURCE_HOST' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m shell -a \"$source_cmd\" -o"
  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$DESTINATION_HOST' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m shell -a \"$destination_cmd\" -o"
}

trap '[[ -n "$HA_INVENTORY_PATH" ]] && rm -f "$HA_INVENTORY_PATH"' EXIT
build_ha_inventory

echo "[hot-swap] Preparing host prerequisites..." >&2
ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$CONTAINER_REPO_ROOT/test-harness/ansible/pb_prepare_hot_swap_test_hosts.yml' --limit '$SOURCE_HOST,$DESTINATION_HOST' -e target_hosts='$SOURCE_HOST,$DESTINATION_HOST' -e operator_user=$OPERATOR_USER"

echo "[hot-swap] Configuring source host $SOURCE_HOST ($SOURCE_FLAVOR)..." >&2
setup_host_flavor "$SOURCE_HOST" "$SOURCE_FLAVOR" "primary"

echo "[hot-swap] Configuring destination host $DESTINATION_HOST ($DESTINATION_FLAVOR)..." >&2
setup_host_flavor "$DESTINATION_HOST" "$DESTINATION_FLAVOR" "hot-spare"

if [[ "$SOLANA_VALIDATOR_HA_RUNTIME_ENABLED" == "true" ]]; then
  echo "[hot-swap] Reconciling HA runtime across $SOLANA_VALIDATOR_HA_RECONCILE_GROUP..." >&2
  reconcile_validator_ha_cluster
  assert_host_ha_runtime_config "$SOURCE_HOST" "$SOLANA_VALIDATOR_HA_SOURCE_NODE_ID" "$SOLANA_VALIDATOR_HA_SOURCE_PRIORITY" "$SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID" "$(jq -r '.ansible_host' < <(ansible_in_control "ansible-inventory -i '$CONTAINER_HA_INVENTORY' --host '$DESTINATION_HOST'"))" "$SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY"
  assert_host_ha_runtime_config "$DESTINATION_HOST" "$SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID" "$SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY" "$SOLANA_VALIDATOR_HA_SOURCE_NODE_ID" "$(jq -r '.ansible_host' < <(ansible_in_control "ansible-inventory -i '$CONTAINER_HA_INVENTORY' --host '$SOURCE_HOST'"))" "$SOLANA_VALIDATOR_HA_SOURCE_PRIORITY"

  if [[ "$VERIFY_HA_RECONCILE_NOOP" == "true" ]]; then
    local_source_ha_pid="$(host_systemd_main_pid "$SOURCE_HOST" "solana-validator-ha")"
    local_destination_ha_pid="$(host_systemd_main_pid "$DESTINATION_HOST" "solana-validator-ha")"
    local_source_public_ip_pid="$(host_systemd_main_pid "$SOURCE_HOST" "solana-validator-ha-public-ip")"
    local_destination_public_ip_pid="$(host_systemd_main_pid "$DESTINATION_HOST" "solana-validator-ha-public-ip")"

    echo "[hot-swap] Re-running identical HA reconcile to verify no-op idempotence..." >&2
    reconcile_validator_ha_cluster

    assert_same_value "$SOURCE_HOST solana-validator-ha MainPID" "$local_source_ha_pid" "$(host_systemd_main_pid "$SOURCE_HOST" "solana-validator-ha")"
    assert_same_value "$DESTINATION_HOST solana-validator-ha MainPID" "$local_destination_ha_pid" "$(host_systemd_main_pid "$DESTINATION_HOST" "solana-validator-ha")"
    assert_same_value "$SOURCE_HOST solana-validator-ha-public-ip MainPID" "$local_source_public_ip_pid" "$(host_systemd_main_pid "$SOURCE_HOST" "solana-validator-ha-public-ip")"
    assert_same_value "$DESTINATION_HOST solana-validator-ha-public-ip MainPID" "$local_destination_public_ip_pid" "$(host_systemd_main_pid "$DESTINATION_HOST" "solana-validator-ha-public-ip")"
  fi

  if [[ "$VERIFY_HA_RECONCILE_ONLY" == "true" ]]; then
    echo "[hot-swap] HA reconcile-only verification completed successfully." >&2
    exit 0
  fi
fi

echo "[hot-swap] Verifying pre-swap client flavors..." >&2
assert_host_validator_runtime "$SOURCE_HOST"
assert_host_validator_runtime "$DESTINATION_HOST"
assert_host_client "$SOURCE_HOST" "$SOURCE_FLAVOR"
assert_host_client "$DESTINATION_HOST" "$DESTINATION_FLAVOR"

echo "[hot-swap] Executing pb_hot_swap_validator_hosts_v2..." >&2
ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$CONTAINER_REPO_ROOT/ansible/playbooks/pb_hot_swap_validator_hosts_v2.yml' -e source_host=$SOURCE_HOST -e destination_host=$DESTINATION_HOST -e operator_user=$OPERATOR_USER -e auto_confirm_swap=true -e deprovision_source_host=false -e swap_epoch_end_threshold_sec=$SWAP_EPOCH_END_THRESHOLD_SEC"

echo "[hot-swap] Verifying post-swap identity state..." >&2
assert_swap_identity_state

echo "[hot-swap] Verifying post-swap client flavors remain intact..." >&2
assert_host_validator_runtime "$SOURCE_HOST"
assert_host_validator_runtime "$DESTINATION_HOST"
assert_host_client "$SOURCE_HOST" "$SOURCE_FLAVOR"
assert_host_client "$DESTINATION_HOST" "$DESTINATION_FLAVOR"

echo "[hot-swap] Case completed successfully: $SOURCE_FLAVOR -> $DESTINATION_FLAVOR" >&2

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

COMPOSE_ENGINE="${COMPOSE_ENGINE:-docker}"
INVENTORY_PATH=""
SOURCE_HOST="${SOURCE_HOST:-host-bravo}"
DESTINATION_HOST="${DESTINATION_HOST:-host-charlie}"
SOURCE_FLAVOR="${SOURCE_FLAVOR:-agave}"
DESTINATION_FLAVOR="${DESTINATION_FLAVOR:-agave}"
VALIDATOR_NAME="${VALIDATOR_NAME:-demo2}"
OPERATOR_USER="${OPERATOR_USER:-ubuntu}"
SOLANA_CLUSTER="${SOLANA_CLUSTER:-localnet}"

AGAVE_VERSION="${AGAVE_VERSION:-3.1.10}"
JITO_VERSION="${JITO_VERSION:-2.3.6}"
BAM_JITO_VERSION="${BAM_JITO_VERSION:-3.1.10}"
BAM_JITO_VERSION_PATCH="${BAM_JITO_VERSION_PATCH:-}"

BUILD_FROM_SOURCE="${BUILD_FROM_SOURCE:-false}"
FORCE_HOST_CLEANUP="${FORCE_HOST_CLEANUP:-true}"
SOLANA_VALIDATOR_HA_RECONCILE_GROUP="${SOLANA_VALIDATOR_HA_RECONCILE_GROUP:-ha_compose_hot_swap}"
SOLANA_VALIDATOR_HA_SOURCE_NODE_ID="${SOLANA_VALIDATOR_HA_SOURCE_NODE_ID:-ark}"
SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID="${SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID:-fog}"
SOLANA_VALIDATOR_HA_SOURCE_PRIORITY="${SOLANA_VALIDATOR_HA_SOURCE_PRIORITY:-10}"
SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY="${SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY:-20}"

usage() {
  cat <<'EOF'
Usage:
  verify-compose-ha-reconcile.sh --inventory <path> [options]

Required:
  --inventory <path>

Optional:
  --compose-engine <docker|podman>      (default: docker)
  --source-host <name>                  (default: host-bravo)
  --destination-host <name>             (default: host-charlie)
  --source-flavor <agave|jito-shared|jito-cohosted|jito-bam>      (default: agave)
  --destination-flavor <agave|jito-shared|jito-cohosted|jito-bam> (default: agave)
  --validator-name <name>               (default: demo2)
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

if [[ -z "$INVENTORY_PATH" ]]; then
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
HA_INVENTORY_PATH=""
CONTAINER_HA_INVENTORY=""

compose_exec() {
  "$COMPOSE_BIN" compose -f "$COMPOSE_BASE" -f "$COMPOSE_OVERRIDE" --profile localnet "$@"
}

control_exec() {
  local cmd="$1"
  compose_exec exec -T ansible-control-localnet bash -lc "$cmd"
}

host_exec() {
  local host="$1"
  local cmd="$2"
  compose_exec exec -T "$host" bash -lc "$cmd"
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

ansible_in_control() {
  local cmd="$1"
  control_exec "cd $CONTAINER_REPO_ROOT/ansible && $cmd"
}

assert_host_validator_runtime() {
  local host="$1"
  local service_cmd

  service_cmd="set -eu; systemctl is-active --quiet sol"

  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$host' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m shell -a \"$service_cmd\" -o" >/dev/null
  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$host' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m wait_for -a 'host=127.0.0.1 port=8899 timeout=30 state=started' -o" >/dev/null
}

promote_host_runtime_identity_to_primary() {
  local host="$1"
  local promote_cmd
  local attempt
  local output=""
  local rc=0
  promote_cmd="set -eu; remaining=180; while [ \"\\\$remaining\" -gt 0 ]; do if /opt/solana/active_release/bin/agave-validator -l /mnt/ledger set-identity /opt/validator/keys/$VALIDATOR_NAME/primary-target-identity.json >/dev/null 2>&1; then exit 0; fi; sleep 2; remaining=\\\$((remaining - 2)); done; echo 'Timed out promoting runtime identity to primary-target-identity.json' >&2; exit 1"

  for attempt in 1 2 3; do
    rc=0
    output="$(
      ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$host' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m shell -a \"$promote_cmd\" -o" 2>&1
    )" || rc=$?
    if (( rc == 0 )); then
      return 0
    fi
    sleep 5
  done

  echo "Failed to promote runtime identity to primary on $host after multiple attempts." >&2
  echo "$output" >&2
  return 1
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
    jito-shared|jito-cohosted)
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
  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$CONTAINER_REPO_ROOT/ansible/playbooks/pb_reconcile_validator_ha_cluster.yml' -e ha_reconcile_retained_peers_group=$SOLANA_VALIDATOR_HA_RECONCILE_GROUP -e operator_user=$OPERATOR_USER -e validator_name=$VALIDATOR_NAME -e solana_cluster=$SOLANA_CLUSTER -e ha_enforce_hostname_prefix=false"
}

host_systemd_main_pid() {
  local host="$1"
  local service="$2"
  local pid_cmd
  pid_cmd="set -eu; systemctl show '$service' --property MainPID --value"
  host_exec "$host" "$pid_cmd" | tr -d '\r'
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

assert_host_ha_runtime_config() {
  local host="$1"
  local expected_node_id="$2"
  local expected_priority="$3"
  local expected_peer_node_id="$4"
  local expected_peer_ip="$5"
  local expected_peer_priority="$6"
  local config_cmd

  config_cmd="set -eu; cfg='/opt/validator/ha/config.yaml'; test -f \"\$cfg\"; grep -F 'name: \"${expected_node_id}\"' \"\$cfg\" >/dev/null; grep -F 'priority: ${expected_priority}' \"\$cfg\" >/dev/null; grep -F '${expected_peer_node_id}:' \"\$cfg\" >/dev/null; grep -F 'ip: \"${expected_peer_ip}\"' \"\$cfg\" >/dev/null; grep -F 'priority: ${expected_peer_priority}' \"\$cfg\" >/dev/null"
  host_exec "$host" "$config_cmd" >/dev/null
}

assert_host_service_active() {
  local host="$1"
  local service="$2"
  local cmd
  cmd="set -eu; systemctl is-active --quiet '$service'"
  host_exec "$host" "$cmd"
}

trap '[[ -n "$HA_INVENTORY_PATH" ]] && rm -f "$HA_INVENTORY_PATH"' EXIT

build_ha_inventory

echo "[ha-reconcile] Preparing host prerequisites..." >&2
ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$CONTAINER_REPO_ROOT/test-harness/ansible/pb_prepare_hot_swap_test_hosts.yml' --limit '$SOURCE_HOST,$DESTINATION_HOST' -e target_hosts='$SOURCE_HOST,$DESTINATION_HOST' -e operator_user=$OPERATOR_USER"

echo "[ha-reconcile] Configuring source host $SOURCE_HOST ($SOURCE_FLAVOR)..." >&2
setup_host_flavor "$SOURCE_HOST" "$SOURCE_FLAVOR" "primary"
assert_host_validator_runtime "$SOURCE_HOST"
echo "[ha-reconcile] Promoting source host $SOURCE_HOST to primary runtime identity..." >&2
promote_host_runtime_identity_to_primary "$SOURCE_HOST"

echo "[ha-reconcile] Configuring destination host $DESTINATION_HOST ($DESTINATION_FLAVOR)..." >&2
setup_host_flavor "$DESTINATION_HOST" "$DESTINATION_FLAVOR" "hot-spare"

echo "[ha-reconcile] Reconciling HA runtime across $SOLANA_VALIDATOR_HA_RECONCILE_GROUP..." >&2
reconcile_validator_ha_cluster

source_host_ip="$(jq -r '.ansible_host' < <(ansible_in_control "ansible-inventory -i '$CONTAINER_HA_INVENTORY' --host '$SOURCE_HOST'"))"
destination_host_ip="$(jq -r '.ansible_host' < <(ansible_in_control "ansible-inventory -i '$CONTAINER_HA_INVENTORY' --host '$DESTINATION_HOST'"))"

assert_host_service_active "$SOURCE_HOST" "solana-validator-ha"
assert_host_service_active "$DESTINATION_HOST" "solana-validator-ha"
assert_host_service_active "$SOURCE_HOST" "solana-validator-ha-public-ip"
assert_host_service_active "$DESTINATION_HOST" "solana-validator-ha-public-ip"

assert_host_ha_runtime_config "$SOURCE_HOST" "$SOLANA_VALIDATOR_HA_SOURCE_NODE_ID" "$SOLANA_VALIDATOR_HA_SOURCE_PRIORITY" "$SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID" "$destination_host_ip" "$SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY"
assert_host_ha_runtime_config "$DESTINATION_HOST" "$SOLANA_VALIDATOR_HA_DESTINATION_NODE_ID" "$SOLANA_VALIDATOR_HA_DESTINATION_PRIORITY" "$SOLANA_VALIDATOR_HA_SOURCE_NODE_ID" "$source_host_ip" "$SOLANA_VALIDATOR_HA_SOURCE_PRIORITY"

source_ha_pid="$(host_systemd_main_pid "$SOURCE_HOST" "solana-validator-ha")"
destination_ha_pid="$(host_systemd_main_pid "$DESTINATION_HOST" "solana-validator-ha")"
source_public_ip_pid="$(host_systemd_main_pid "$SOURCE_HOST" "solana-validator-ha-public-ip")"
destination_public_ip_pid="$(host_systemd_main_pid "$DESTINATION_HOST" "solana-validator-ha-public-ip")"

echo "[ha-reconcile] Re-running identical HA reconcile to verify true no-op idempotence..." >&2
reconcile_validator_ha_cluster

assert_same_value "$SOURCE_HOST solana-validator-ha MainPID" "$source_ha_pid" "$(host_systemd_main_pid "$SOURCE_HOST" "solana-validator-ha")"
assert_same_value "$DESTINATION_HOST solana-validator-ha MainPID" "$destination_ha_pid" "$(host_systemd_main_pid "$DESTINATION_HOST" "solana-validator-ha")"
assert_same_value "$SOURCE_HOST solana-validator-ha-public-ip MainPID" "$source_public_ip_pid" "$(host_systemd_main_pid "$SOURCE_HOST" "solana-validator-ha-public-ip")"
assert_same_value "$DESTINATION_HOST solana-validator-ha-public-ip MainPID" "$destination_public_ip_pid" "$(host_systemd_main_pid "$DESTINATION_HOST" "solana-validator-ha-public-ip")"

echo "[ha-reconcile] HA reconcile verification completed successfully." >&2

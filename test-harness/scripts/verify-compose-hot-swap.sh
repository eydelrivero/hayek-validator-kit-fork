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
PRE_SWAP_CATCHUP_TIMEOUT_SEC="${PRE_SWAP_CATCHUP_TIMEOUT_SEC:-180}"
PRE_SWAP_TOWER_TIMEOUT_SEC="${PRE_SWAP_TOWER_TIMEOUT_SEC:-180}"
LOCALNET_ENTRYPOINT_RPC_URL="${LOCALNET_ENTRYPOINT_RPC_URL:-http://gossip-entrypoint:8899}"
PRE_SWAP_CLUSTER_STATE=""
READY_SWAP_CLUSTER_STATE=""
POST_SWAP_CLUSTER_STATE=""

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

host_exec() {
  local host="$1"
  local cmd="$2"
  compose_exec exec -T "$host" bash -lc "$cmd"
}

host_exec_as_solana() {
  local host="$1"
  local cmd="$2"
  local quoted_cmd
  printf -v quoted_cmd '%q' "$cmd"
  host_exec "$host" "sudo -n -u sol bash -lc $quoted_cmd"
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
  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$CONTAINER_REPO_ROOT/ansible/playbooks/pb_reconcile_validator_ha_cluster.yml' -e target_ha_group=$SOLANA_VALIDATOR_HA_RECONCILE_GROUP -e operator_user=$OPERATOR_USER -e validator_name=$VALIDATOR_NAME -e solana_cluster=$SOLANA_CLUSTER -e ha_enforce_hostname_prefix=false"
}

ensure_localnet_demo_validator_accounts() {
  local init_cmd

  if [[ "$SOLANA_CLUSTER" != "localnet" ]]; then
    return 0
  fi

  init_cmd="set -eu; payer_key=\"\$HOME/.config/solana/id.json\"; keys_dir='$CONTAINER_REPO_ROOT/solana-localnet/validator-keys/$VALIDATOR_NAME'; primary_key=\"\$keys_dir/primary-target-identity.json\"; vote_key=\"\$keys_dir/vote-account.json\"; withdrawer_key=\"\$keys_dir/authorized-withdrawer.json\"; stake_key=\"\$keys_dir/stake-account.json\"; vote_pubkey=\$(solana-keygen pubkey \"\$vote_key\"); if solana -u '$LOCALNET_ENTRYPOINT_RPC_URL' account \"\$vote_pubkey\" >/dev/null 2>&1; then exit 0; fi; echo '[hot-swap] Initializing localnet vote/stake accounts for $VALIDATOR_NAME...' >&2; solana -u '$LOCALNET_ENTRYPOINT_RPC_URL' --keypair \"\$payer_key\" airdrop 500000 >/dev/null || true; solana -u '$LOCALNET_ENTRYPOINT_RPC_URL' --keypair \"\$primary_key\" airdrop 42 >/dev/null || true; solana -u '$LOCALNET_ENTRYPOINT_RPC_URL' --keypair \"\$payer_key\" create-vote-account \"\$vote_key\" \"\$primary_key\" \"\$withdrawer_key\" >/dev/null; if [ -f \"\$stake_key\" ]; then stake_pubkey=\$(solana-keygen pubkey \"\$stake_key\"); if ! solana -u '$LOCALNET_ENTRYPOINT_RPC_URL' account \"\$stake_pubkey\" >/dev/null 2>&1; then solana -u '$LOCALNET_ENTRYPOINT_RPC_URL' --keypair \"\$payer_key\" create-stake-account \"\$stake_key\" 200000 >/dev/null || true; fi; if solana -u '$LOCALNET_ENTRYPOINT_RPC_URL' account \"\$stake_pubkey\" >/dev/null 2>&1; then solana -u '$LOCALNET_ENTRYPOINT_RPC_URL' --keypair \"\$payer_key\" delegate-stake \"\$stake_key\" \"\$vote_key\" --force >/dev/null || true; fi; fi; for _ in \$(seq 1 30); do if solana -u '$LOCALNET_ENTRYPOINT_RPC_URL' account \"\$vote_pubkey\" >/dev/null 2>&1; then exit 0; fi; sleep 1; done; echo \"Localnet vote account \$vote_pubkey was not visible on $LOCALNET_ENTRYPOINT_RPC_URL after initialization.\" >&2; exit 1"
  control_exec "$init_cmd"
}

host_systemd_main_pid() {
  local host="$1"
  local service="$2"
  local pid_cmd
  pid_cmd="set -eu; systemctl show '$service' --property MainPID --value"
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
  version_cmd="set -eu; if [ -x /opt/solana/active_release/bin/solana ]; then /opt/solana/active_release/bin/solana --version; elif [ -x /opt/solana/active_release/bin/agave-validator ]; then /opt/solana/active_release/bin/agave-validator --version; elif [ -x /opt/solana/active_release/bin/solana-validator ]; then /opt/solana/active_release/bin/solana-validator --version; else echo 'No validator version command found in /opt/solana/active_release/bin' >&2; exit 1; fi"
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

wait_for_host_validator_catchup() {
  local host="$1"
  local catchup_cmd
  local journal_cmd
  local output=""
  local journal_output=""
  local rc=0

  catchup_cmd="set -eu; export PATH='/opt/solana/active_release/bin:'\"\$PATH\"; timeout ${PRE_SWAP_CATCHUP_TIMEOUT_SEC}s solana catchup -u '$LOCALNET_ENTRYPOINT_RPC_URL' --our-localhost 8899"
  journal_cmd="set -eu; journalctl -u sol -n 120 --no-pager || true; printf -- '\n-- validator log tail --\n'; tail -n 120 /opt/validator/logs/agave-validator.log 2>/dev/null || true"

  output="$(host_exec_as_solana "$host" "$catchup_cmd" 2>&1)" || rc=$?
  if (( rc != 0 )); then
    journal_output="$(host_exec "$host" "$journal_cmd" 2>&1 || true)"
    if [[ -z "$journal_output" ]]; then
      journal_output="catchup diagnostic probe failed with no output"
    fi
    echo "Host $host did not reach catchup against ${LOCALNET_ENTRYPOINT_RPC_URL} within ${PRE_SWAP_CATCHUP_TIMEOUT_SEC}s." >&2
    echo "$output" >&2
    echo "$journal_output" >&2
    return 1
  fi
}

wait_for_source_tower_file() {
  local pubkey_cmd
  local tower_path=""
  local remaining=0
  local test_cmd=""
  local list_cmd=""
  local journal_cmd
  local output=""
  local journal_output=""
  local rc=0

  pubkey_cmd="set -eu; /opt/solana/active_release/bin/solana-keygen pubkey '/opt/validator/keys/$VALIDATOR_NAME/primary-target-identity.json'"
  output="$(host_exec_as_solana "$SOURCE_HOST" "$pubkey_cmd" 2>&1)" || rc=$?
  if (( rc != 0 )); then
    echo "Failed to resolve source primary identity pubkey before tower check." >&2
    echo "$output" >&2
    return 1
  fi

  tower_path="/mnt/ledger/tower-1_9-$(printf '%s\n' "$output" | tail -n 1 | tr -d '\r').bin"
  test_cmd="sudo -n -u sol test -s '$tower_path'"
  list_cmd="sudo -n -u sol ls -l '$(dirname "$tower_path")' 2>/dev/null || true"
  journal_cmd="set -eu; journalctl -u sol -n 120 --no-pager || true; printf -- '\n-- validator log tail --\n'; tail -n 120 /opt/validator/logs/agave-validator.log 2>/dev/null || true"

  remaining=$PRE_SWAP_TOWER_TIMEOUT_SEC
  while (( remaining > 0 )); do
    if host_exec "$SOURCE_HOST" "$test_cmd" >/dev/null 2>&1; then
      echo "[hot-swap] Source tower file ready: $tower_path" >&2
      return 0
    fi
    sleep 2
    remaining=$((remaining - 2))
  done

  output="$tower_path"$'\n'"$(host_exec "$SOURCE_HOST" "$list_cmd" 2>&1 || true)"
  journal_output="$(host_exec "$SOURCE_HOST" "$journal_cmd" 2>&1 || true)"
  if [[ -z "$journal_output" ]]; then
    journal_output="tower diagnostic probe failed with no output"
  fi
  echo "Source validator did not produce a tower file within ${PRE_SWAP_TOWER_TIMEOUT_SEC}s." >&2
  echo "$output" >&2
  echo "$journal_output" >&2
  return 1

}

capture_host_identity_state() {
  local host="$1"
  local cmd
  local output=""
  local run_key="unavailable"
  local primary_key="unavailable"
  local hot_key="unavailable"

  cmd="set -eu; kdir='/opt/validator/keys/$VALIDATOR_NAME'; pubkey_or_missing() { f=\"\$1\"; if [ -f \"\$f\" ]; then /opt/solana/active_release/bin/solana-keygen pubkey \"\$f\"; else printf 'missing\\n'; fi; }; runtime_or_missing() { runtime=\$(/opt/solana/active_release/bin/agave-validator -l /mnt/ledger contact-info 2>/dev/null | awk '/^Identity:/ { print \$2; exit }' || true); if [ -n \"\$runtime\" ]; then printf '%s\\n' \"\$runtime\"; else printf 'missing\\n'; fi; }; run=\$(runtime_or_missing); primary=\$(pubkey_or_missing \"\$kdir/primary-target-identity.json\"); hot=\$(pubkey_or_missing \"\$kdir/hot-spare-identity.json\"); printf '%s\\t%s\\t%s\\n' \"\$run\" \"\$primary\" \"\$hot\""
  output="$(host_exec_as_solana "$host" "$cmd" 2>/dev/null || true)"

  if [[ -n "$output" ]]; then
    IFS=$'\t' read -r run_key primary_key hot_key <<<"$output"
  fi

  printf '%s\t%s\t%s\n' "$run_key" "$primary_key" "$hot_key"
}

capture_single_host_catchup_snapshot() {
  local host="$1"
  local catchup_cmd
  local output=""

  catchup_cmd="set -eu; export PATH='/opt/solana/active_release/bin:'\"\$PATH\"; timeout 20s solana catchup -u '$LOCALNET_ENTRYPOINT_RPC_URL' --our-localhost 8899"
  output="$(host_exec_as_solana "$host" "$catchup_cmd" 2>&1 || true)"
  if [[ -z "$output" ]]; then
    output="No catchup output captured."
  fi

  printf '%s\n' "$output" | sed -n '1,40p'
}

report_host_status() {
  local stage="$1"
  local host="$2"
  local identity_state=""
  local runtime_key=""
  local primary_key=""
  local hot_key=""
  local catchup_snapshot=""

  identity_state="$(capture_host_identity_state "$host")"
  IFS=$'\t' read -r runtime_key primary_key hot_key <<<"$identity_state"
  catchup_snapshot="$(capture_single_host_catchup_snapshot "$host")"

  echo "[hot-swap] ${stage} ${host} identity: runtime=${runtime_key} primary=${primary_key} hot-spare=${hot_key}" >&2
  printf '[hot-swap] %s %s catchup:\n%s\n' "$stage" "$host" "$catchup_snapshot" >&2
}

capture_cluster_state() {
  local genesis_hash=""
  local cluster_slot=""
  local container_id=""
  local container_started_at=""

  genesis_hash="$(control_exec "solana -u '$LOCALNET_ENTRYPOINT_RPC_URL' genesis-hash" | tail -n 1 | tr -d '\r')"
  cluster_slot="$(control_exec "solana -u '$LOCALNET_ENTRYPOINT_RPC_URL' slot" | tail -n 1 | tr -d '\r')"
  container_id="$(compose_exec ps -q gossip-entrypoint | tail -n 1 | tr -d '\r')"
  container_started_at="$("$COMPOSE_BIN" inspect --format '{{.State.StartedAt}}' "$container_id" | tail -n 1 | tr -d '\r')"

  printf '%s\t%s\t%s\t%s\n' "$genesis_hash" "$cluster_slot" "$container_id" "$container_started_at"
}

report_cluster_state() {
  local stage="$1"
  local cluster_state="$2"
  local genesis_hash=""
  local cluster_slot=""
  local container_id=""
  local container_started_at=""

  IFS=$'\t' read -r genesis_hash cluster_slot container_id container_started_at <<<"$cluster_state"
  echo "[hot-swap] ${stage} cluster: genesis=${genesis_hash} slot=${cluster_slot} entrypoint=${container_id} started_at=${container_started_at}" >&2
}

assert_cluster_continuity() {
  local previous_label="$1"
  local previous_state="$2"
  local current_label="$3"
  local current_state="$4"
  local previous_genesis=""
  local previous_slot=""
  local previous_container_id=""
  local previous_container_started_at=""
  local current_genesis=""
  local current_slot=""
  local current_container_id=""
  local current_container_started_at=""

  IFS=$'\t' read -r previous_genesis previous_slot previous_container_id previous_container_started_at <<<"$previous_state"
  IFS=$'\t' read -r current_genesis current_slot current_container_id current_container_started_at <<<"$current_state"

  if [[ "$current_genesis" != "$previous_genesis" ]]; then
    echo "Cluster genesis hash changed between ${previous_label} and ${current_label}: ${previous_genesis} -> ${current_genesis}" >&2
    exit 1
  fi

  if [[ "$current_container_id" != "$previous_container_id" ]]; then
    echo "Gossip entrypoint container changed between ${previous_label} and ${current_label}: ${previous_container_id} -> ${current_container_id}" >&2
    exit 1
  fi

  if [[ "$current_container_started_at" != "$previous_container_started_at" ]]; then
    echo "Gossip entrypoint start time changed between ${previous_label} and ${current_label}: ${previous_container_started_at} -> ${current_container_started_at}" >&2
    exit 1
  fi

  if ! [[ "$previous_slot" =~ ^[0-9]+$ && "$current_slot" =~ ^[0-9]+$ ]]; then
    echo "Cluster slot snapshots were not numeric between ${previous_label} and ${current_label}: ${previous_slot} -> ${current_slot}" >&2
    exit 1
  fi

  if (( current_slot < previous_slot )); then
    echo "Cluster slot went backwards between ${previous_label} and ${current_label}: ${previous_slot} -> ${current_slot}" >&2
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
  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$host' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m shell -a \"$config_cmd\" -o" >/dev/null
}

assert_swap_identity_state() {
  local source_cmd
  local destination_cmd
  source_cmd="set -eu; kdir='/opt/validator/keys/$VALIDATOR_NAME'; run=\$(/opt/solana/active_release/bin/agave-validator -l /mnt/ledger contact-info | awk '/^Identity:/ { print \$2; exit }'); hot=\$(/opt/solana/active_release/bin/solana-keygen pubkey \"\$kdir/hot-spare-identity.json\"); test \"\$run\" = \"\$hot\""
  destination_cmd="set -eu; kdir='/opt/validator/keys/$VALIDATOR_NAME'; run=\$(/opt/solana/active_release/bin/agave-validator -l /mnt/ledger contact-info | awk '/^Identity:/ { print \$2; exit }'); primary=\$(/opt/solana/active_release/bin/solana-keygen pubkey \"\$kdir/primary-target-identity.json\"); test \"\$run\" = \"\$primary\""

  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$SOURCE_HOST' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m shell -a \"$source_cmd\" -o"
  ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible '$DESTINATION_HOST' -i '$CONTAINER_HA_INVENTORY' -u '$OPERATOR_USER' -b -m shell -a \"$destination_cmd\" -o"
}

trap '[[ -n "$HA_INVENTORY_PATH" ]] && rm -f "$HA_INVENTORY_PATH"' EXIT
build_ha_inventory
ensure_localnet_demo_validator_accounts

echo "[hot-swap] Preparing host prerequisites..." >&2
ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$CONTAINER_REPO_ROOT/test-harness/ansible/pb_prepare_hot_swap_test_hosts.yml' --limit '$SOURCE_HOST,$DESTINATION_HOST' -e target_hosts='$SOURCE_HOST,$DESTINATION_HOST' -e operator_user=$OPERATOR_USER"

echo "[hot-swap] Configuring source host $SOURCE_HOST ($SOURCE_FLAVOR)..." >&2
setup_host_flavor "$SOURCE_HOST" "$SOURCE_FLAVOR" "primary"
assert_host_validator_runtime "$SOURCE_HOST"
echo "[hot-swap] Promoting source host $SOURCE_HOST to primary runtime identity..." >&2
promote_host_runtime_identity_to_primary "$SOURCE_HOST"

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
echo "[hot-swap] Reporting pre-swap identity and catchup status..." >&2
report_host_status "pre-swap" "$SOURCE_HOST"
report_host_status "pre-swap" "$DESTINATION_HOST"
PRE_SWAP_CLUSTER_STATE="$(capture_cluster_state)"
report_cluster_state "pre-swap" "$PRE_SWAP_CLUSTER_STATE"
echo "[hot-swap] Waiting for validators to finish catchup..." >&2
wait_for_host_validator_catchup "$SOURCE_HOST"
wait_for_host_validator_catchup "$DESTINATION_HOST"
echo "[hot-swap] Waiting for source validator tower file..." >&2
wait_for_source_tower_file
echo "[hot-swap] Reporting ready-to-swap identity and catchup status..." >&2
report_host_status "ready" "$SOURCE_HOST"
report_host_status "ready" "$DESTINATION_HOST"
READY_SWAP_CLUSTER_STATE="$(capture_cluster_state)"
report_cluster_state "ready" "$READY_SWAP_CLUSTER_STATE"
assert_cluster_continuity "pre-swap" "$PRE_SWAP_CLUSTER_STATE" "ready" "$READY_SWAP_CLUSTER_STATE"

echo "[hot-swap] Executing pb_hot_swap_validator_hosts_v2..." >&2
ansible_in_control "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i '$CONTAINER_HA_INVENTORY' '$CONTAINER_REPO_ROOT/ansible/playbooks/pb_hot_swap_validator_hosts_v2.yml' -e source_host=$SOURCE_HOST -e destination_host=$DESTINATION_HOST -e operator_user=$OPERATOR_USER -e auto_confirm_swap=true -e deprovision_source_host=false -e swap_epoch_end_threshold_sec=$SWAP_EPOCH_END_THRESHOLD_SEC -e manage_destination_ufw_peer_ssh_rule=false"

echo "[hot-swap] Verifying post-swap identity state..." >&2
assert_swap_identity_state
echo "[hot-swap] Reporting post-swap identity and catchup status..." >&2
report_host_status "post-swap" "$SOURCE_HOST"
report_host_status "post-swap" "$DESTINATION_HOST"
POST_SWAP_CLUSTER_STATE="$(capture_cluster_state)"
report_cluster_state "post-swap" "$POST_SWAP_CLUSTER_STATE"
assert_cluster_continuity "ready" "$READY_SWAP_CLUSTER_STATE" "post-swap" "$POST_SWAP_CLUSTER_STATE"

echo "[hot-swap] Verifying post-swap client flavors remain intact..." >&2
assert_host_validator_runtime "$SOURCE_HOST"
assert_host_validator_runtime "$DESTINATION_HOST"
assert_host_client "$SOURCE_HOST" "$SOURCE_FLAVOR"
assert_host_client "$DESTINATION_HOST" "$DESTINATION_FLAVOR"

echo "[hot-swap] Case completed successfully: $SOURCE_FLAVOR -> $DESTINATION_FLAVOR" >&2

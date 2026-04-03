#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLAYBOOK="$ANSIBLE_DIR/playbooks/pb_setup_real_validator_host.yml"

if [[ -t 1 ]]; then
  COLOR_PHASE=$'\033[1;36m'
  COLOR_SECTION=$'\033[1;33m'
  COLOR_META=$'\033[0;36m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_PHASE=""
  COLOR_SECTION=""
  COLOR_META=""
  COLOR_RESET=""
fi

usage() {
  cat <<'EOF'
Usage:
  run_setup_real_validator_host.sh [options]

Options:
  --inventory <path>                        Required. Inventory file path.
  --target-host <name>                      Required. Inventory hostname to configure.
  --host-name <name>                        Optional. Hostname to set during metal-box setup.
  --bootstrap-user <name>                   Required. Initial SSH user (typically ubuntu).
  --metal-box-user <name>                   Required. Sysadmin user for metal-box hardening.
  --validator-operator-user <name>          Required. Validator operator SSH user.
  --users-csv-file <name>                   Required. Users CSV filename.
  --users-base-dir <path>                   Required. Directory containing the users CSV.
  --authorized-ips-csv-file <name>          Required. Authorized IP CSV filename.
  --authorized-access-csv <path>            Required. Full path to the authorized IP CSV.
  --validator-flavor <agave|jito-bam>       Required. Validator client flavor.
  --validator-name <name>                   Required. Validator keyset name.
  --validator-type <primary|hot-spare>      Optional. Defaults to playbook/role default.
  --solana-cluster <name>                   Required. Cluster name, e.g. testnet.
  --agave-version <version>                 Optional. Agave version.
  --jito-version <version>                  Optional. Jito version.
  --jito-version-patch <value>              Optional. Jito patch suffix/version patch.
  --solana-validator-ha-version <version>   Optional. HA binary version.
  --resume-from-metal-box                   Optional. Skip the users phase and resume from metal-box.
  --resume-from-validator                   Optional. Skip directly to validator + HA setup.
  --resume-from-monitoring                  Optional. Skip directly to validator startup monitoring.
  --allow-unconventional-testnet-two-disk-layout
                                            Optional. Enable the special testnet two-disk mode.
  --build-from-source <true|false>          Optional. Passed through to the playbook.
  --use-official-repo <true|false>          Optional. Passed through to the playbook.
  --monitor-interval <seconds>              Optional. Poll interval for startup monitoring (default: 20).
  -h, --help                                Show this help.

Examples:
  run_setup_real_validator_host.sh \
    --inventory ./latitude-hayek-testnet.yml \
    --target-host latitude-host \
    --host-name mud-lat-lax \
    --bootstrap-user ubuntu \
    --metal-box-user eydel_admin \
    --validator-operator-user eydel \
    --users-csv-file iam_setup_prod.csv \
    --users-base-dir "$HOME/new-metal-box" \
    --authorized-ips-csv-file authorized_ips_prod.csv \
    --authorized-access-csv "$HOME/new-metal-box/authorized_ips_prod.csv" \
    --validator-flavor jito-bam \
    --validator-name hayek-testnet \
    --validator-type hot-spare \
    --solana-cluster testnet \
    --jito-version 4.0.0-beta.4 \
    --build-from-source true \
    --use-official-repo true \
    --solana-validator-ha-version 0.1.19 \
    --allow-unconventional-testnet-two-disk-layout
EOF
}

require_arg() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "Missing required option: $name" >&2
    usage >&2
    exit 2
  fi
}

INVENTORY=""
TARGET_HOST=""
HOST_NAME=""
BOOTSTRAP_USER=""
METAL_BOX_USER=""
VALIDATOR_OPERATOR_USER=""
USERS_CSV_FILE=""
USERS_BASE_DIR=""
AUTHORIZED_IPS_CSV_FILE=""
AUTHORIZED_ACCESS_CSV=""
VALIDATOR_FLAVOR=""
VALIDATOR_NAME=""
VALIDATOR_TYPE=""
SOLANA_CLUSTER=""
AGAVE_VERSION=""
JITO_VERSION=""
JITO_VERSION_PATCH=""
SOLANA_VALIDATOR_HA_VERSION=""
BUILD_FROM_SOURCE=""
USE_OFFICIAL_REPO=""
ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT=false
RESUME_FROM_METAL_BOX=false
RESUME_FROM_VALIDATOR=false
RESUME_FROM_MONITORING=false
MONITOR_INTERVAL=20

while (($# > 0)); do
  case "$1" in
    --inventory)
      INVENTORY="${2:-}"
      shift 2
      ;;
    --target-host)
      TARGET_HOST="${2:-}"
      shift 2
      ;;
    --host-name)
      HOST_NAME="${2:-}"
      shift 2
      ;;
    --bootstrap-user)
      BOOTSTRAP_USER="${2:-}"
      shift 2
      ;;
    --metal-box-user)
      METAL_BOX_USER="${2:-}"
      shift 2
      ;;
    --validator-operator-user)
      VALIDATOR_OPERATOR_USER="${2:-}"
      shift 2
      ;;
    --users-csv-file)
      USERS_CSV_FILE="${2:-}"
      shift 2
      ;;
    --users-base-dir)
      USERS_BASE_DIR="${2:-}"
      shift 2
      ;;
    --authorized-ips-csv-file)
      AUTHORIZED_IPS_CSV_FILE="${2:-}"
      shift 2
      ;;
    --authorized-access-csv)
      AUTHORIZED_ACCESS_CSV="${2:-}"
      shift 2
      ;;
    --validator-flavor)
      VALIDATOR_FLAVOR="${2:-}"
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
    --solana-validator-ha-version)
      SOLANA_VALIDATOR_HA_VERSION="${2:-}"
      shift 2
      ;;
    --build-from-source)
      BUILD_FROM_SOURCE="${2:-}"
      shift 2
      ;;
    --use-official-repo)
      USE_OFFICIAL_REPO="${2:-}"
      shift 2
      ;;
    --allow-unconventional-testnet-two-disk-layout)
      ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT=true
      shift
      ;;
    --resume-from-metal-box)
      RESUME_FROM_METAL_BOX=true
      shift
      ;;
    --resume-from-validator)
      RESUME_FROM_VALIDATOR=true
      shift
      ;;
    --resume-from-monitoring)
      RESUME_FROM_MONITORING=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --monitor-interval)
      MONITOR_INTERVAL="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_arg --inventory "$INVENTORY"
require_arg --target-host "$TARGET_HOST"
require_arg --bootstrap-user "$BOOTSTRAP_USER"
require_arg --metal-box-user "$METAL_BOX_USER"
require_arg --validator-operator-user "$VALIDATOR_OPERATOR_USER"
require_arg --users-csv-file "$USERS_CSV_FILE"
require_arg --users-base-dir "$USERS_BASE_DIR"
require_arg --authorized-ips-csv-file "$AUTHORIZED_IPS_CSV_FILE"
require_arg --authorized-access-csv "$AUTHORIZED_ACCESS_CSV"
require_arg --validator-flavor "$VALIDATOR_FLAVOR"
require_arg --validator-name "$VALIDATOR_NAME"
require_arg --solana-cluster "$SOLANA_CLUSTER"

if ! [[ "$MONITOR_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$MONITOR_INTERVAL" -lt 1 ]]; then
  echo "--monitor-interval must be a positive integer" >&2
  exit 2
fi

COMMON_ARGS=(
  "$PLAYBOOK"
  -i "$INVENTORY"
  --limit "$TARGET_HOST"
  -e "target_host=$TARGET_HOST"
  -e "bootstrap_user=$BOOTSTRAP_USER"
  -e "metal_box_user=$METAL_BOX_USER"
  -e "validator_operator_user=$VALIDATOR_OPERATOR_USER"
  -e "users_csv_file=$USERS_CSV_FILE"
  -e "users_base_dir=$USERS_BASE_DIR"
  -e "authorized_ips_csv_file=$AUTHORIZED_IPS_CSV_FILE"
  -e "authorized_access_csv=$AUTHORIZED_ACCESS_CSV"
  -e "validator_flavor=$VALIDATOR_FLAVOR"
  -e "validator_name=$VALIDATOR_NAME"
  -e "solana_cluster=$SOLANA_CLUSTER"
)

if [[ -n "$HOST_NAME" ]]; then
  COMMON_ARGS+=(-e "host_name=$HOST_NAME")
fi
if [[ -n "$VALIDATOR_TYPE" ]]; then
  COMMON_ARGS+=(-e "validator_type=$VALIDATOR_TYPE")
fi
if [[ -n "$AGAVE_VERSION" ]]; then
  COMMON_ARGS+=(-e "agave_version=$AGAVE_VERSION")
fi
if [[ -n "$JITO_VERSION" ]]; then
  COMMON_ARGS+=(-e "jito_version=$JITO_VERSION")
fi
if [[ -n "$JITO_VERSION_PATCH" ]]; then
  COMMON_ARGS+=(-e "jito_version_patch=$JITO_VERSION_PATCH")
fi
if [[ -n "$SOLANA_VALIDATOR_HA_VERSION" ]]; then
  COMMON_ARGS+=(-e "solana_validator_ha_version=$SOLANA_VALIDATOR_HA_VERSION")
fi
if [[ -n "$BUILD_FROM_SOURCE" ]]; then
  COMMON_ARGS+=(-e "build_from_source=$BUILD_FROM_SOURCE")
fi
if [[ -n "$USE_OFFICIAL_REPO" ]]; then
  COMMON_ARGS+=(-e "use_official_repo=$USE_OFFICIAL_REPO")
fi
if [[ "$ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT" == true ]]; then
  COMMON_ARGS+=(-e "allow_unconventional_testnet_two_disk_layout=true")
fi

cd "$ANSIBLE_DIR"

resolve_host_ssh() {
  local host="$1"

  ansible-inventory -i "$INVENTORY" --host "$host" \
    | python3 -c '
import json, shlex, sys

data = json.load(sys.stdin)
for key in (
    "ansible_host",
    "ansible_port",
    "ansible_user",
    "ansible_ssh_private_key_file",
    "ansible_ssh_common_args",
):
    value = data.get(key, "")
    print(f"{key}={shlex.quote(str(value))}")
'
}

run_remote_command() {
  local remote_cmd="$1"
  local ansible_host=""
  local ansible_port=""
  local ansible_user=""
  local ansible_ssh_private_key_file=""
  local ansible_ssh_common_args=""
  local -a ssh_cmd=(ssh)

  eval "$(resolve_host_ssh "$TARGET_HOST")"

  if [[ -z "$ansible_host" ]]; then
    echo "Missing ansible_host for $TARGET_HOST in $INVENTORY" >&2
    exit 1
  fi

  if [[ -z "$ansible_user" ]]; then
    ansible_user="$VALIDATOR_OPERATOR_USER"
  fi

  if [[ -z "$ansible_port" || "$ansible_port" == "22" ]]; then
    ansible_port="2522"
  fi

  if [[ -n "$ansible_ssh_private_key_file" ]]; then
    ssh_cmd+=(-i "$ansible_ssh_private_key_file")
  fi

  ssh_cmd+=(
    -p "${ansible_port:-22}"
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=3
  )

  if [[ -n "$ansible_ssh_common_args" ]]; then
    # shellcheck disable=SC2206
    local extra_args=( $ansible_ssh_common_args )
    ssh_cmd+=("${extra_args[@]}")
  fi

  ssh_cmd+=("${ansible_user}@${ansible_host}" "$remote_cmd")
  "${ssh_cmd[@]}"
}

resolve_remote_solana_bin_dir() {
  local raw_output=""

  raw_output="$(run_remote_command "bash -lc '
if [[ -x /opt/solana/active_release/bin/agave-validator ]]; then
  printf \"%s\\n\" /opt/solana/active_release/bin
elif [[ -x /home/sol/.local/share/solana/install/active_release/bin/agave-validator ]]; then
  printf \"%s\\n\" /home/sol/.local/share/solana/install/active_release/bin
else
  exit 1
fi
'")" || return 1

  printf '%s\n' "$raw_output" \
    | grep -E '^/(opt/solana/active_release/bin|home/sol/\.local/share/solana/install/active_release/bin)$' \
    | tail -n 1
}

resolved_monitor_ssh_target() {
  local ansible_host=""
  local ansible_port=""
  local ansible_user=""
  local ansible_ssh_private_key_file=""
  local ansible_ssh_common_args=""

  eval "$(resolve_host_ssh "$TARGET_HOST")"

  if [[ -z "$ansible_host" ]]; then
    echo "unknown-host"
    return
  fi
  if [[ -z "$ansible_user" ]]; then
    ansible_user="$VALIDATOR_OPERATOR_USER"
  fi
  if [[ -z "$ansible_port" || "$ansible_port" == "22" ]]; then
    ansible_port="2522"
  fi

  printf '%s@%s:%s\n' "$ansible_user" "$ansible_host" "$ansible_port"
}

monitor_validator_startup() {
  local remote_solana_bin_dir=""

  if ! remote_solana_bin_dir="$(resolve_remote_solana_bin_dir)"; then
    echo "Failed to resolve remote Solana binary directory on $TARGET_HOST" >&2
    exit 1
  fi

  printf '\n\n%s== Phase 4: monitor validator startup ==%s\n' "$COLOR_PHASE" "$COLOR_RESET"
  printf '%sTarget host:%s %s\n' "$COLOR_META" "$COLOR_RESET" "$TARGET_HOST"
  printf '%sSSH target:%s %s\n' "$COLOR_META" "$COLOR_RESET" "$(resolved_monitor_ssh_target)"
  printf '%sSolana bin dir:%s %s\n' "$COLOR_META" "$COLOR_RESET" "$remote_solana_bin_dir"
  printf '%sPress Ctrl+C to stop monitoring.%s\n\n' "$COLOR_META" "$COLOR_RESET"
  while true; do
    printf '%s[%s] getIdentity%s\n' "$COLOR_SECTION" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$COLOR_RESET"
    run_remote_command "curl -s http://127.0.0.1:8899 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getIdentity\"}' | jq . || true"

    printf '\n%s[%s] catchup%s\n' "$COLOR_SECTION" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$COLOR_RESET"
    run_remote_command "sudo -u sol HOME=/home/sol ${remote_solana_bin_dir}/solana -ut catchup --our-localhost 8899 || true"

    printf '\n%s[%s] agave-validator monitor%s\n' "$COLOR_SECTION" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$COLOR_RESET"
    run_remote_command "timeout 20s sudo -u sol HOME=/home/sol ${remote_solana_bin_dir}/agave-validator -l /mnt/ledger/ monitor || true"

    printf '\n%sSleeping %ss before next probe...%s\n\n' "$COLOR_META" "$MONITOR_INTERVAL" "$COLOR_RESET"
    sleep "$MONITOR_INTERVAL"
  done
}

if [[ "$RESUME_FROM_METAL_BOX" == true && "$RESUME_FROM_VALIDATOR" == true ]] \
  || [[ "$RESUME_FROM_METAL_BOX" == true && "$RESUME_FROM_MONITORING" == true ]] \
  || [[ "$RESUME_FROM_VALIDATOR" == true && "$RESUME_FROM_MONITORING" == true ]]; then
  echo "Use only one resume mode: --resume-from-metal-box, --resume-from-validator, or --resume-from-monitoring" >&2
  exit 2
fi

if [[ "$RESUME_FROM_METAL_BOX" == true ]]; then
  echo "== Resuming real validator host bootstrap from metal-box =="
  ansible-playbook -K "${COMMON_ARGS[@]}" \
    -e "validator_host_bootstrap_start_at=metal_box" \
    -e "password_handoff_mode=assume_ready"

  echo
  if [[ "$METAL_BOX_USER" == "$VALIDATOR_OPERATOR_USER" ]]; then
    echo "Metal-box stage finished."
    echo "The validator setup will reuse the same sudo password for $VALIDATOR_OPERATOR_USER."
  else
    echo "Metal-box stage finished."
    echo "Before validator setup, SSH as $VALIDATOR_OPERATOR_USER and run:"
    echo "  sudo reset-my-password"
    echo "Then confirm:"
    echo "  sudo -v"
  fi
  echo
  read -r -p "Press Enter when the validator-operator password handoff is complete..."

  echo
  echo "== Phase 3: validator + HA =="
  ansible-playbook -K "${COMMON_ARGS[@]}" \
    -e "validator_host_bootstrap_start_at=validator" \
    -e "password_handoff_mode=assume_ready"
  echo
  monitor_validator_startup
  exit 0
fi

if [[ "$RESUME_FROM_VALIDATOR" == true ]]; then
  echo "== Resuming real validator host bootstrap from validator =="
  ansible-playbook -K "${COMMON_ARGS[@]}" \
    -e "validator_host_bootstrap_start_at=validator" \
    -e "password_handoff_mode=assume_ready"
  echo
  monitor_validator_startup
  exit 0
fi

if [[ "$RESUME_FROM_MONITORING" == true ]]; then
  monitor_validator_startup
  exit 0
fi

echo "== Phase 1: users + manual password handoff =="
ansible-playbook "${COMMON_ARGS[@]}"

echo
echo "Phase 1 finished."
echo "Complete the manual password handoff now:"
echo "  1. SSH as $METAL_BOX_USER"
echo "  2. Run: sudo reset-my-password"
echo "  3. Verify: sudo -v"
if [[ "$METAL_BOX_USER" != "$VALIDATOR_OPERATOR_USER" ]]; then
  echo
  echo "Then also prepare the validator operator sudo password:"
  echo "  4. SSH as $VALIDATOR_OPERATOR_USER"
  echo "  5. Run: sudo reset-my-password"
  echo "  6. Verify: sudo -v"
fi
echo
read -r -p "Press Enter when the manual password handoff is complete..."

echo
echo "== Phase 2: metal-box =="
ansible-playbook -K "${COMMON_ARGS[@]}" \
  -e "validator_host_bootstrap_start_at=metal_box" \
  -e "password_handoff_mode=assume_ready"

echo
if [[ "$METAL_BOX_USER" == "$VALIDATOR_OPERATOR_USER" ]]; then
  echo "Metal-box stage finished."
  echo "The validator setup will reuse the same sudo password for $VALIDATOR_OPERATOR_USER."
else
  echo "Metal-box stage finished."
  echo "If you have not already done so, SSH as $VALIDATOR_OPERATOR_USER and run:"
  echo "  sudo reset-my-password"
  echo "Then confirm:"
  echo "  sudo -v"
fi
echo
read -r -p "Press Enter when the validator-operator password handoff is complete..."

echo
echo "== Phase 3: validator + HA =="
ansible-playbook -K "${COMMON_ARGS[@]}" \
  -e "validator_host_bootstrap_start_at=validator" \
  -e "password_handoff_mode=assume_ready"

echo
monitor_validator_startup

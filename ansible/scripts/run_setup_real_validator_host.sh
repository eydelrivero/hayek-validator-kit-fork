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
  --users-csv <path>                        Required. Full path to the users CSV.
  --authorized-ips-csv <path>               Required. Full path to the authorized IP CSV.
  --validator-flavor <agave|jito-bam|firedancer>
                                            Required. Validator client flavor.
  --validator-name <name>                   Required. Validator keyset name.
  --validator-type <primary|hot-spare>      Optional. Defaults to playbook/role default.
  --solana-cluster <name>                   Required. Cluster name, e.g. testnet.
  --agave-version <version>                 Optional. Agave version (agave/jito-bam flavors).
                                            For firedancer: auto-detected from submodule; use to override.
  --firedancer-version <version>            Required for firedancer. Firedancer version (e.g. 0.1001.40101).
  --jito-version <version>                  Optional. Jito version.
  --jito-version-patch <value>              Optional. Jito patch suffix/version patch.
  --solana-validator-ha-version <version>   Optional. HA binary version.
  --resume-from-metal-box                   Optional. Skip the users phase and resume from metal-box.
  --resume-from-validator                   Optional. Skip directly to validator + HA setup.
  --resume-from-monitoring                  Optional. Skip directly to validator startup monitoring.
  --allow-unconventional-testnet-two-disk-layout
                                            Optional. Force the special testnet two-disk mode.
                                            Auto-detected when the host has 1 root + 1 non-root
                                            disk on testnet; use this only to force it.
  --build-from-source <true|false>          Optional. Passed through to the playbook.
  --use-official-repo <true|false>          Optional. Passed through to the playbook.
  --firedancer-park-ht-siblings-on-start <true|false>
                                            Optional (firedancer). Auto-offline the HT siblings
                                            firedancer flags, as an ExecStartPost on each start.
                                            Default false (park manually with the deployed script).
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
    --users-csv "$HOME/new-metal-box/iam_setup_prod.csv" \
    --authorized-ips-csv "$HOME/new-metal-box/authorized_ips_prod.csv" \
    --validator-flavor jito-bam \
    --validator-name hayek-testnet \
    --validator-type hot-spare \
    --solana-cluster testnet \
    --jito-version 4.0.0-beta.4 \
    --build-from-source true \
    --use-official-repo true \
    --solana-validator-ha-version 0.1.19
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
USERS_CSV=""
AUTHORIZED_IPS_CSV=""
VALIDATOR_FLAVOR=""
VALIDATOR_NAME=""
VALIDATOR_TYPE=""
SOLANA_CLUSTER=""
AGAVE_VERSION=""
FIREDANCER_VERSION=""
JITO_VERSION=""
JITO_VERSION_PATCH=""
SOLANA_VALIDATOR_HA_VERSION=""
BUILD_FROM_SOURCE=""
USE_OFFICIAL_REPO=""
FIREDANCER_PARK_HT_SIBLINGS_ON_START=""
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
    --users-csv)
      USERS_CSV="${2:-}"
      shift 2
      ;;
    --authorized-ips-csv)
      AUTHORIZED_IPS_CSV="${2:-}"
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
    --firedancer-version)
      FIREDANCER_VERSION="${2:-}"
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
    --firedancer-park-ht-siblings-on-start)
      FIREDANCER_PARK_HT_SIBLINGS_ON_START="${2:-}"
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
require_arg --users-csv "$USERS_CSV"
require_arg --authorized-ips-csv "$AUTHORIZED_IPS_CSV"
require_arg --validator-flavor "$VALIDATOR_FLAVOR"
require_arg --validator-name "$VALIDATOR_NAME"
require_arg --solana-cluster "$SOLANA_CLUSTER"

# The roles still consume the CSV path as a filename + directory (iam_manager) and as
# a full path (server_initial_setup), so derive those pieces from the single-path flags.
USERS_CSV_FILE="$(basename "$USERS_CSV")"
USERS_BASE_DIR="$(dirname "$USERS_CSV")"
AUTHORIZED_ACCESS_CSV="$AUTHORIZED_IPS_CSV"
AUTHORIZED_IPS_CSV_FILE="$(basename "$AUTHORIZED_IPS_CSV")"

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
if [[ -n "$FIREDANCER_VERSION" ]]; then
  COMMON_ARGS+=(-e "firedancer_version=$FIREDANCER_VERSION")
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
if [[ -n "$FIREDANCER_PARK_HT_SIBLINGS_ON_START" ]]; then
  COMMON_ARGS+=(-e "firedancer_park_ht_siblings_on_start=$FIREDANCER_PARK_HT_SIBLINGS_ON_START")
fi
# allow_unconventional_testnet_two_disk_layout is appended later, after
# maybe_autodetect_two_disk_layout has had a chance to enable it.

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

remote_total_disk_count() {
  local ansible_host=""
  local ansible_port=""
  local ansible_user=""
  local ansible_ssh_private_key_file=""
  local ansible_ssh_common_args=""

  REMOTE_DISK_PROBE_TARGETS=()
  eval "$(resolve_host_ssh "$TARGET_HOST")"
  [[ -z "$ansible_host" ]] && return 1
  local inv_port="${ansible_port:-22}"
  [[ -z "$inv_port" ]] && inv_port=22

  # Mirrors server_initial_setup precheck: resolve the root disk, then count
  # whole disks (lsblk TYPE==disk) excluding it. Total = non-root + 1.
  # Single-line so quoting through ssh -> bash -lc stays simple.
  local detect='root_node=$(basename "$(readlink -f "$(findmnt -n -o SOURCE /)")"); while p=$(lsblk -ndo PKNAME "/dev/$root_node" 2>/dev/null | head -n1); [ -n "$p" ]; do root_node="$p"; done; c=$(lsblk -dn -o NAME,TYPE | while read -r n t; do [ "$t" = disk ] && [ "$n" != "$root_node" ] && echo x; done | wc -l); echo $((c+1))'

  # Try a deduped (user x port) matrix: the disk count is identical regardless of
  # which login succeeds, so the first reachable candidate wins. This covers fresh
  # hosts (sshd on :22) and hardened hosts (sshd on :2522) no matter the inventory
  # port or which operator user can currently log in.
  local -a users=("$BOOTSTRAP_USER" "$METAL_BOX_USER" "$VALIDATOR_OPERATOR_USER")
  local -a ports=("$inv_port" 2522 22)

  local -a common_args=()
  if [[ -n "$ansible_ssh_common_args" ]]; then
    # shellcheck disable=SC2206
    common_args=( $ansible_ssh_common_args )
  fi

  local -A seen=()
  local user port target out
  local -a ssh_cmd
  for user in "${users[@]}"; do
    [[ -z "$user" ]] && continue
    for port in "${ports[@]}"; do
      [[ -z "$port" ]] && continue
      target="${user}@${ansible_host}:${port}"
      [[ -n "${seen[$target]:-}" ]] && continue
      seen[$target]=1
      REMOTE_DISK_PROBE_TARGETS+=("$target")

      ssh_cmd=(ssh -p "$port"
        -o BatchMode=yes -o ConnectTimeout=6
        -o StrictHostKeyChecking=accept-new)
      [[ -n "$ansible_ssh_private_key_file" ]] && ssh_cmd+=(-i "$ansible_ssh_private_key_file")
      [[ ${#common_args[@]} -gt 0 ]] && ssh_cmd+=("${common_args[@]}")
      ssh_cmd+=("${user}@${ansible_host}" "bash -lc $(printf '%q' "$detect")")

      out="$("${ssh_cmd[@]}" 2>/dev/null)" || continue
      out="$(printf '%s\n' "$out" | grep -E '^[0-9]+$' | tail -n1)"
      [[ -n "$out" ]] && { printf '%s\n' "$out"; return 0; }
    done
  done
  return 1
}

ssh_login_hint() {
  local user="$1"
  local force_port="${2:-}"
  local ansible_host=""
  local ansible_port=""
  local ansible_user=""
  local ansible_ssh_private_key_file=""
  local ansible_ssh_common_args=""

  eval "$(resolve_host_ssh "$TARGET_HOST")"

  local port="${force_port:-${ansible_port:-22}}"
  [[ -z "$port" ]] && port=22

  # No -i: the inventory key is the automation key, not the operators' personal keys.
  printf 'ssh -p %s %s@%s' "$port" "$user" "${ansible_host:-<host-unresolved>}"
}

announce_become_user() {
  local user="$1"
  printf '%sThis stage runs as %s and will prompt for %s'\''s sudo (BECOME) password.%s\n' \
    "$COLOR_META" "$user" "$user" "$COLOR_RESET"
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
    run_remote_command "curl -s http://127.0.0.1:8899 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getIdentity\"}' | { jq . 2>/dev/null || cat; } || true"

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

maybe_autodetect_two_disk_layout() {
  [[ "$ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT" == true ]] && return   # operator forced it
  [[ "$SOLANA_CLUSTER" != "testnet" ]] && return                            # flag only valid on testnet
  [[ "$RESUME_FROM_VALIDATOR" == true || "$RESUME_FROM_MONITORING" == true ]] && return  # disk setup not re-run

  local total=""
  if total="$(remote_total_disk_count)"; then
    if [[ "$total" == "2" ]]; then
      ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT=true
      printf '%s[disk auto-detect] %s has 2 disks (1 root + 1 non-root) on testnet; enabling special two-disk layout.%s\n' \
        "$COLOR_META" "$TARGET_HOST" "$COLOR_RESET"
    else
      printf '%s[disk auto-detect] %s has %s disks; using standard multi-disk layout.%s\n' \
        "$COLOR_META" "$TARGET_HOST" "$total" "$COLOR_RESET"
    fi
    return
  fi

  # Probe could not reach the host on any candidate. Make it loud and offer a
  # manual decision instead of silently failing at the role's 3-disk assertion.
  printf '\n%s[disk auto-detect] WARNING: could not inspect disks on %s.%s\n' \
    "$COLOR_SECTION" "$TARGET_HOST" "$COLOR_RESET" >&2
  printf '%sTried: %s%s\n' \
    "$COLOR_META" "${REMOTE_DISK_PROBE_TARGETS[*]:-none}" "$COLOR_RESET" >&2

  if [[ -t 0 ]]; then
    local reply=""
    read -r -p "Enable the special testnet two-disk layout for $TARGET_HOST? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT=true
      printf '%s[disk auto-detect] Two-disk layout enabled by operator.%s\n' \
        "$COLOR_META" "$COLOR_RESET"
      return
    fi
  fi
  printf '%s[disk auto-detect] Proceeding with standard layout. Re-run with --allow-unconventional-testnet-two-disk-layout to force the two-disk layout.%s\n' \
    "$COLOR_META" "$COLOR_RESET" >&2
}

maybe_autodetect_two_disk_layout

if [[ "$ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT" == true ]]; then
  COMMON_ARGS+=(-e "allow_unconventional_testnet_two_disk_layout=true")
fi

if [[ "$RESUME_FROM_METAL_BOX" == true ]]; then
  echo "== Resuming real validator host bootstrap from metal-box =="
  announce_become_user "$METAL_BOX_USER"
  ansible-playbook -K "${COMMON_ARGS[@]}" \
    -e "validator_host_bootstrap_start_at=metal_box" \
    -e "password_handoff_mode=assume_ready"

  echo
  if [[ "$METAL_BOX_USER" == "$VALIDATOR_OPERATOR_USER" ]]; then
    echo "Metal-box stage finished."
    echo "The validator setup will reuse the same sudo password for $VALIDATOR_OPERATOR_USER."
  else
    echo "Metal-box stage finished."
    echo "Before validator setup, SSH in and run the password reset:"
    echo "  $(ssh_login_hint "$VALIDATOR_OPERATOR_USER" 2522)"
    echo "  sudo reset-my-password"
    echo "Then confirm:"
    echo "  sudo -v"
  fi
  echo
  read -r -p "Press Enter when the validator-operator password handoff is complete..."

  echo
  echo "== Phase 3: validator + HA =="
  announce_become_user "$VALIDATOR_OPERATOR_USER"
  ansible-playbook -K "${COMMON_ARGS[@]}" \
    -e "validator_host_bootstrap_start_at=validator" \
    -e "password_handoff_mode=assume_ready"
  echo
  monitor_validator_startup
  exit 0
fi

if [[ "$RESUME_FROM_VALIDATOR" == true ]]; then
  echo "== Resuming real validator host bootstrap from validator =="
  announce_become_user "$VALIDATOR_OPERATOR_USER"
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
echo "  1. SSH in: $(ssh_login_hint "$METAL_BOX_USER")"
echo "  2. Run: sudo reset-my-password"
echo "  3. Verify: sudo -v"
if [[ "$METAL_BOX_USER" != "$VALIDATOR_OPERATOR_USER" ]]; then
  echo
  echo "Then also prepare the validator operator sudo password:"
  echo "  4. SSH in: $(ssh_login_hint "$VALIDATOR_OPERATOR_USER")"
  echo "  5. Run: sudo reset-my-password"
  echo "  6. Verify: sudo -v"
fi
echo
read -r -p "Press Enter when the manual password handoff is complete..."

echo
echo "== Phase 2: metal-box =="
announce_become_user "$METAL_BOX_USER"
ansible-playbook -K "${COMMON_ARGS[@]}" \
  -e "validator_host_bootstrap_start_at=metal_box" \
  -e "password_handoff_mode=assume_ready"

echo
if [[ "$METAL_BOX_USER" == "$VALIDATOR_OPERATOR_USER" ]]; then
  echo "Metal-box stage finished."
  echo "The validator setup will reuse the same sudo password for $VALIDATOR_OPERATOR_USER."
else
  echo "Metal-box stage finished."
  echo "If you have not already done so, SSH in and run the password reset:"
  echo "  $(ssh_login_hint "$VALIDATOR_OPERATOR_USER" 2522)"
  echo "  sudo reset-my-password"
  echo "Then confirm:"
  echo "  sudo -v"
fi
echo
read -r -p "Press Enter when the validator-operator password handoff is complete..."

echo
echo "== Phase 3: validator + HA =="
announce_become_user "$VALIDATOR_OPERATOR_USER"
ansible-playbook -K "${COMMON_ARGS[@]}" \
  -e "validator_host_bootstrap_start_at=validator" \
  -e "password_handoff_mode=assume_ready"

echo
monitor_validator_startup

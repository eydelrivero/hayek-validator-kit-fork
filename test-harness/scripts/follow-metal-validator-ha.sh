#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INVENTORY_PATH="${INVENTORY_PATH:-}"
HA_GROUP="${HA_GROUP:-}"
HOST_SELECTOR="${HOST_SELECTOR:-all}"
SSH_USER="${SSH_USER:-}"
SSH_PORT="${SSH_PORT:-2522}"
USE_SUDO=false
FORCE_TTY=false
ASK_BECOME_PASS=false
BECOME_PASSWORD="${BECOME_PASSWORD:-}"
SERVICE_NAME="${SERVICE_NAME:-solana-validator-ha}"
JOURNAL_LINES="${JOURNAL_LINES:-50}"
JOURNAL_SINCE="${JOURNAL_SINCE:-}"
FOLLOW_MODE=true

usage() {
  cat <<'EOF'
Usage:
  follow-metal-validator-ha.sh --inventory <path> [options]

Follow solana-validator-ha service logs from a real HA validator inventory.

Options:
  --inventory <path>         Ansible inventory file for the HA cluster
  --ha-group <name>          Explicit HA inventory group (auto-detected by default)
  --host <primary|secondary|tertiary|all|inventory-host|node-id>
  --ssh-user <user>          SSH user override for all target hosts
  --ssh-port <port>          SSH port for all target hosts (default: 2522)
  --sudo                     Run journalctl via sudo
  -K, --ask-become-pass      Prompt once locally and pass the sudo password to each host
  --tty                      Force ssh -tt for interactive remote commands
  --service <name>           systemd unit to stream (default: solana-validator-ha)
  -n, --lines <n>            Journal lines to show before following (default: 50)
  --since <expr>             journalctl --since value (for example: "10 min ago")
  --no-follow                Print recent logs and exit
  -h, --help                 Show this help

Examples:
  follow-metal-validator-ha.sh --inventory ansible/setup_ha_testnet.yml
  follow-metal-validator-ha.sh --inventory ansible/setup_ha_mainnet.yml --host primary
  follow-metal-validator-ha.sh --inventory ansible/setup_ha_mainnet.yml --host ark
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

while (($# > 0)); do
  case "$1" in
    --inventory)
      INVENTORY_PATH="${2:-}"
      shift 2
      ;;
    --ha-group)
      HA_GROUP="${2:-}"
      shift 2
      ;;
    --host)
      HOST_SELECTOR="${2:-}"
      shift 2
      ;;
    --ssh-user)
      SSH_USER="${2:-}"
      shift 2
      ;;
    --ssh-port)
      SSH_PORT="${2:-}"
      shift 2
      ;;
    --sudo)
      USE_SUDO=true
      shift
      ;;
    -K|--ask-become-pass)
      ASK_BECOME_PASS=true
      shift
      ;;
    --tty)
      FORCE_TTY=true
      shift
      ;;
    --service)
      SERVICE_NAME="${2:-}"
      shift 2
      ;;
    -n|--lines)
      JOURNAL_LINES="${2:-}"
      shift 2
      ;;
    --since)
      JOURNAL_SINCE="${2:-}"
      shift 2
      ;;
    --no-follow)
      FOLLOW_MODE=false
      shift
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

if [[ ! -r "$INVENTORY_PATH" ]]; then
  echo "Inventory file is not readable: $INVENTORY_PATH" >&2
  exit 1
fi

if ! [[ "$JOURNAL_LINES" =~ ^[0-9]+$ ]]; then
  echo "--lines must be a non-negative integer" >&2
  exit 2
fi

if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$SSH_PORT" -lt 1 || "$SSH_PORT" -gt 65535 ]]; then
  echo "--ssh-port must be an integer between 1 and 65535" >&2
  exit 2
fi

require_cmd ansible-inventory
require_cmd python3
require_cmd ssh
require_cmd stdbuf
require_cmd awk

build_remote_command() {
  local unit="$1"
  local lines="$2"
  local since="$3"
  local follow="$4"
  local use_sudo="$5"
  local ask_become_pass="$6"
  local args=("-u" "$unit" "-n" "$lines" "--no-pager" "-o" "short-iso" "-q")

  if [[ -n "$since" ]]; then
    args+=("--since" "$since")
  fi
  if [[ "$follow" == "true" ]]; then
    args+=("-f")
  fi

  if [[ "$use_sudo" == "true" ]]; then
    if [[ "$ask_become_pass" == "true" ]]; then
      printf 'sudo -S -p "" journalctl'
    elif [[ "$FORCE_TTY" == "true" ]]; then
      printf 'sudo journalctl'
    else
      printf 'sudo -n journalctl'
    fi
  else
    printf 'journalctl'
  fi
  local arg
  for arg in "${args[@]}"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

resolve_ha_layout() {
  local inventory_path="$1"
  local requested_group="$2"

  python3 - "$inventory_path" "$requested_group" <<'PY'
import json
import shlex
import subprocess
import sys

inventory_path = sys.argv[1]
requested_group = sys.argv[2]
raw = subprocess.run(
    ["ansible-inventory", "-i", inventory_path, "--list"],
    check=True,
    capture_output=True,
    text=True,
).stdout
data = json.loads(raw)
groups = {name: value for name, value in data.items() if isinstance(value, dict)}
hostvars = data.get("_meta", {}).get("hostvars", {})

def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)

def quote(value):
    return shlex.quote(str(value))

def group_hosts(name):
    hosts = groups.get(name, {}).get("hosts", [])
    return hosts if isinstance(hosts, list) else []

if requested_group:
    candidate_groups = [requested_group]
else:
    candidate_groups = []
    seen = set()
    for host_name, vars_for_host in sorted(hostvars.items()):
        group_name = vars_for_host.get("solana_validator_ha_inventory_group")
        if not group_name or group_name in seen:
            continue
        if group_name in groups and group_hosts(group_name):
            candidate_groups.append(group_name)
            seen.add(group_name)
    if len(candidate_groups) != 1:
        candidate_groups = sorted(
            name
            for name in groups
            if name.startswith("ha_")
            and name != "ha_reconcile_inventory_group_all"
            and group_hosts(name)
        )

if len(candidate_groups) != 1:
    fail(
        "Unable to determine a unique HA group from inventory. "
        f"Candidates: {', '.join(candidate_groups) or 'none'}. "
        "Pass --ha-group explicitly."
    )

ha_group = candidate_groups[0]
hosts = group_hosts(ha_group)

if len(hosts) < 2:
    fail(
        f"HA group {ha_group} must contain at least 2 hosts; found {len(hosts)}: "
        f"{', '.join(hosts) or 'none'}"
    )

def priority(host_name):
    raw = hostvars.get(host_name, {}).get("solana_validator_ha_priority", 0)
    try:
        return int(raw)
    except (TypeError, ValueError):
        return 0

hosts = sorted(hosts, key=lambda host_name: (-priority(host_name), host_name))

def label(host_name):
    host_data = hostvars.get(host_name, {})
    return host_data.get("solana_validator_ha_node_id") or host_name

print(f"HA_GROUP={quote(ha_group)}")
print("HA_HOSTS=(" + " ".join(quote(host_name) for host_name in hosts) + ")")
print("HA_LABELS=(" + " ".join(quote(label(host_name)) for host_name in hosts) + ")")

ordinal_names = ["primary", "secondary", "tertiary"]
for idx, host_name in enumerate(hosts):
    host_label = label(host_name)
    if idx < len(ordinal_names):
        ordinal = ordinal_names[idx]
        print(f"HA_{ordinal.upper()}_HOST={quote(host_name)}")
        print(f"HA_{ordinal.upper()}_LABEL={quote(host_label)}")
PY
}

resolve_host_ssh() {
  local inventory_path="$1"
  local host="$2"

  python3 - "$inventory_path" "$host" <<'PY'
import json
import shlex
import subprocess
import sys

inventory_path = sys.argv[1]
inventory_host = sys.argv[2]
raw = subprocess.run(
    ["ansible-inventory", "-i", inventory_path, "--host", inventory_host],
    check=True,
    capture_output=True,
    text=True,
).stdout
data = json.loads(raw)

def quote(value):
    return shlex.quote(str(value))

ansible_host = data.get("ansible_host") or inventory_host
ansible_user = data.get("ansible_user") or data.get("operator_user") or ""
ansible_ssh_private_key_file = data.get("ansible_ssh_private_key_file") or ""
common_args_raw = str(data.get("ansible_ssh_common_args") or "").strip()
common_args = shlex.split(common_args_raw) if common_args_raw else []

print(f"ansible_host={quote(ansible_host)}")
print(f"inventory_ssh_user={quote(ansible_user)}")
print(f"ansible_ssh_private_key_file={quote(ansible_ssh_private_key_file)}")
print("ansible_ssh_common_args=(" + " ".join(quote(arg) for arg in common_args) + ")")
PY
}

eval "$(resolve_ha_layout "$INVENTORY_PATH" "$HA_GROUP")"

declare -a TARGET_HOSTS=()
case "$HOST_SELECTOR" in
  all)
    TARGET_HOSTS=("${HA_HOSTS[@]}")
    ;;
  primary)
    TARGET_HOSTS=("$HA_PRIMARY_HOST")
    ;;
  secondary)
    TARGET_HOSTS=("$HA_SECONDARY_HOST")
    ;;
  tertiary)
    if [[ -z "${HA_TERTIARY_HOST:-}" ]]; then
      echo "Host target 'tertiary' is not available for HA group $HA_GROUP" >&2
      exit 2
    fi
    TARGET_HOSTS=("$HA_TERTIARY_HOST")
    ;;
  *)
    for idx in "${!HA_HOSTS[@]}"; do
      if [[ "$HOST_SELECTOR" == "${HA_HOSTS[$idx]}" || "$HOST_SELECTOR" == "${HA_LABELS[$idx]}" ]]; then
        TARGET_HOSTS=("${HA_HOSTS[$idx]}")
        break
      fi
    done
    if ((${#TARGET_HOSTS[@]} == 0)); then
      echo "Unsupported host target: $HOST_SELECTOR" >&2
      supported_values=("primary" "secondary")
      if [[ -n "${HA_TERTIARY_HOST:-}" ]]; then
        supported_values+=("tertiary")
      fi
      supported_values+=("all")
      supported_values+=("${HA_HOSTS[@]}")
      supported_values+=("${HA_LABELS[@]}")
      echo "Supported values: ${supported_values[*]}" >&2
      exit 2
    fi
    ;;
esac

host_label() {
  local host="$1"
  local idx
  for idx in "${!HA_HOSTS[@]}"; do
    if [[ "$host" == "${HA_HOSTS[$idx]}" ]]; then
      printf '%s\n' "${HA_LABELS[$idx]}"
      return 0
    fi
  done
  printf '%s\n' "$host"
}

host_color() {
  local host="$1"
  local idx
  for idx in "${!HA_HOSTS[@]}"; do
    if [[ "$host" == "${HA_HOSTS[$idx]}" ]]; then
      case "$idx" in
        0) printf '%s' $'\033[1;36m' ;;
        1) printf '%s' $'\033[1;33m' ;;
        2) printf '%s' $'\033[1;35m' ;;
        *) printf '%s' $'\033[1;32m' ;;
      esac
      return 0
    fi
  done
  printf '%s' $'\033[1;37m'
}

stream_host() {
  local host="$1"
  local remote_cmd="$2"
  local prefix="$3"
  local ansi_color="$4"
  local force_tty="$5"
  local ask_become_pass="$6"
  local ansible_host=""
  local inventory_ssh_user=""
  local ansible_ssh_private_key_file=""
  local -a ansible_ssh_common_args=()

  eval "$(resolve_host_ssh "$INVENTORY_PATH" "$host")"

  local effective_ssh_user="${SSH_USER:-$inventory_ssh_user}"

  if [[ -z "$ansible_host" || -z "$effective_ssh_user" ]]; then
    echo "Missing SSH fields for $host in $INVENTORY_PATH" >&2
    return 1
  fi

  local -a ssh_cmd=(
    ssh
    -p "$SSH_PORT"
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=3
  )

  if [[ "$force_tty" == "true" ]]; then
    ssh_cmd+=(-tt)
  fi

  if [[ -n "$ansible_ssh_private_key_file" ]]; then
    ssh_cmd+=(-i "$ansible_ssh_private_key_file")
  fi

  if ((${#ansible_ssh_common_args[@]} > 0)); then
    ssh_cmd+=("${ansible_ssh_common_args[@]}")
  fi

  ssh_cmd+=("${effective_ssh_user}@${ansible_host}" "$remote_cmd")

  if [[ "$force_tty" == "true" ]]; then
    "${ssh_cmd[@]}"
    return $?
  fi

  if [[ "$ask_become_pass" == "true" ]]; then
    printf '%s\n' "$BECOME_PASSWORD" \
      | stdbuf -oL -eL "${ssh_cmd[@]}" 2>&1 \
      | awk -v label="$prefix" -v color="$ansi_color" '
          {
            reset = "\033[0m"
            printf "%s[%s]%s %s\n", color, label, reset, $0
            fflush()
          }'
    return "${PIPESTATUS[1]}"
  fi

  stdbuf -oL -eL "${ssh_cmd[@]}" 2>&1 \
    | awk -v label="$prefix" -v color="$ansi_color" '
        {
          reset = "\033[0m"
          printf "%s[%s]%s %s\n", color, label, reset, $0
          fflush()
        }'
}

if [[ "$FORCE_TTY" == "true" && "${#TARGET_HOSTS[@]}" -ne 1 ]]; then
  echo "--tty is only supported when targeting a single host" >&2
  exit 2
fi

if [[ "$ASK_BECOME_PASS" == "true" && "$USE_SUDO" != "true" ]]; then
  echo "--ask-become-pass requires --sudo" >&2
  exit 2
fi

if [[ "$ASK_BECOME_PASS" == "true" && "$FORCE_TTY" == "true" ]]; then
  echo "--ask-become-pass cannot be combined with --tty; use interactive sudo over the allocated TTY instead" >&2
  exit 2
fi

if [[ "$ASK_BECOME_PASS" == "true" && -z "$BECOME_PASSWORD" ]]; then
  if [[ ! -t 0 ]]; then
    echo "Cannot prompt for sudo password without a TTY; set BECOME_PASSWORD or omit --ask-become-pass" >&2
    exit 2
  fi
  read -rsp 'BECOME password: ' BECOME_PASSWORD
  printf '\n' >&2
fi

REMOTE_CMD="$(build_remote_command "$SERVICE_NAME" "$JOURNAL_LINES" "$JOURNAL_SINCE" "$FOLLOW_MODE" "$USE_SUDO" "$ASK_BECOME_PASS")"

declare -a PIDS=()
cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

for host in "${TARGET_HOSTS[@]}"; do
  if [[ "$FORCE_TTY" == "true" ]]; then
    stream_host "$host" "$REMOTE_CMD" "$(host_label "$host")" "$(host_color "$host")" "$FORCE_TTY" "$ASK_BECOME_PASS"
  else
    stream_host "$host" "$REMOTE_CMD" "$(host_label "$host")" "$(host_color "$host")" "$FORCE_TTY" "$ASK_BECOME_PASS" &
    PIDS+=("$!")
  fi
done

if ((${#PIDS[@]} > 0)); then
  wait "${PIDS[@]}"
fi

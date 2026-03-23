#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

STATE_FILE="${STATE_FILE:-$REPO_ROOT/test-harness/work/manual-vm-cluster/current.env}"
SERVICE_NAME="${SERVICE_NAME:-solana-validator-ha}"
TARGET_HOSTS=("vm-source" "vm-destination")
JOURNAL_LINES="${JOURNAL_LINES:-50}"
JOURNAL_SINCE="${JOURNAL_SINCE:-}"
FOLLOW_MODE=true

usage() {
  cat <<'EOF'
Usage:
  follow-vm-validator-ha.sh [options]

Follow solana-validator-ha service logs from the current manual VM cluster.

Options:
  --state-file <path>        Manual-cluster state file (default: ./test-harness/work/manual-vm-cluster/current.env)
  --host <vm-source|vm-destination|all>
  --service <name>           systemd unit to stream (default: solana-validator-ha)
  -n, --lines <n>            Journal lines to show before following (default: 50)
  --since <expr>             journalctl --since value (for example: "10 min ago")
  --no-follow                Print recent logs and exit
  -h, --help                 Show this help
EOF
}

while (($# > 0)); do
  case "$1" in
    --state-file)
      STATE_FILE="${2:-}"
      shift 2
      ;;
    --host)
      case "${2:-}" in
        vm-source|vm-destination)
          TARGET_HOSTS=("${2}")
          ;;
        all)
          TARGET_HOSTS=("vm-source" "vm-destination")
          ;;
        *)
          echo "Unsupported host target: ${2:-}" >&2
          usage
          exit 2
          ;;
      esac
      shift 2
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

if [[ ! -r "$STATE_FILE" ]]; then
  echo "Manual cluster state file is not readable: $STATE_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$STATE_FILE"

if [[ -z "${OPERATOR_INVENTORY:-}" || ! -r "${OPERATOR_INVENTORY:-}" ]]; then
  echo "Operator inventory is not readable: ${OPERATOR_INVENTORY:-unset}" >&2
  exit 1
fi

if ! command -v ansible-inventory >/dev/null 2>&1; then
  echo "Missing required command: ansible-inventory" >&2
  exit 1
fi

build_remote_command() {
  local unit="$1"
  local lines="$2"
  local since="$3"
  local follow="$4"
  local args=("-u" "$unit" "-n" "$lines" "--no-pager" "-o" "short-iso")

  if [[ -n "$since" ]]; then
    args+=("--since" "$since")
  fi
  if [[ "$follow" == "true" ]]; then
    args+=("-f")
  fi

  printf 'sudo journalctl'
  local arg
  for arg in "${args[@]}"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

resolve_host_ssh() {
  local host="$1"

  ansible-inventory -i "$OPERATOR_INVENTORY" --host "$host" \
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

stream_host() {
  local host="$1"
  local remote_cmd="$2"
  local prefix="$3"
  local ansi_color="$4"
  local ansible_host=""
  local ansible_port=""
  local ansible_user=""
  local ansible_ssh_private_key_file=""
  local ansible_ssh_common_args=""

  eval "$(resolve_host_ssh "$host")"

  if [[ -z "$ansible_host" || -z "$ansible_user" || -z "$ansible_ssh_private_key_file" ]]; then
    echo "Missing SSH fields for $host in $OPERATOR_INVENTORY" >&2
    return 1
  fi

  local -a ssh_cmd=(
    ssh
    -i "$ansible_ssh_private_key_file"
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

  stdbuf -oL -eL "${ssh_cmd[@]}" \
    | awk -v label="$prefix" -v color="$ansi_color" '
        {
          reset = "\033[0m"
          printf "%s[%s]%s %s\n", color, label, reset, $0
          fflush()
        }'
}

REMOTE_CMD="$(build_remote_command "$SERVICE_NAME" "$JOURNAL_LINES" "$JOURNAL_SINCE" "$FOLLOW_MODE")"

declare -a PIDS=()
cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

for host in "${TARGET_HOSTS[@]}"; do
  case "$host" in
    vm-source)
      stream_host "$host" "$REMOTE_CMD" "source" $'\033[1;36m' &
      ;;
    vm-destination)
      stream_host "$host" "$REMOTE_CMD" "destination" $'\033[1;33m' &
      ;;
  esac
  PIDS+=("$!")
done

wait "${PIDS[@]}"

#!/usr/bin/env bash
# follow-latitude-hot-swap.sh
#
# Stream identity-change log lines from both hosts in a Latitude hot-swap run.
# Opens two parallel SSH sessions, prefixes each line with a colored host label.
#
# Usage:
#   follow-latitude-hot-swap.sh --workdir <case-dir> [options]
#
# The case-dir is the per-run directory created by run-latitude-hot-swap-matrix.sh,
# e.g. test-harness/work/latitude-hot-swap/latitude-hot-swap-jito_bam_to_frankendancer-20260529-123456
# It must contain operator-inventory.yml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"

WORKDIR=""
INVENTORY=""
SOURCE_CLIENT="jito"        # agave | jito | frankendancer
DESTINATION_CLIENT="frankendancer"
JOURNAL_LINES=50
FOLLOW_MODE=true

usage() {
  cat <<'EOF'
Usage:
  follow-latitude-hot-swap.sh --workdir <case-dir> [options]
  follow-latitude-hot-swap.sh --inventory <path>   [options]

Stream identity-change log lines from both hosts in a Latitude hot-swap run.
Opens two parallel SSH sessions (lat-source and lat-destination).

Options:
  --workdir <path>            Per-run case directory (contains operator-inventory.yml)
  --inventory <path>          Explicit path to operator inventory file
  --source-client <client>    Client on lat-source: agave | jito | frankendancer (default: jito)
  --destination-client <c>    Client on lat-destination: agave | jito | frankendancer (default: frankendancer)
  -n, --lines <n>             Journal lines to show before following (default: 50)
  --no-follow                 Print recent matching lines and exit
  -h, --help                  Show this help

Examples:
  # jito-bam -> frankendancer run (defaults)
  follow-latitude-hot-swap.sh --workdir test-harness/work/latitude-hot-swap/latitude-hot-swap-jito_bam_to_frankendancer-20260529-123456

  # frankendancer -> jito-bam run (swap client labels)
  follow-latitude-hot-swap.sh --workdir <dir> --source-client frankendancer --destination-client jito
EOF
}

while (($# > 0)); do
  case "$1" in
    --workdir)             WORKDIR="${2:-}";             shift 2 ;;
    --inventory)           INVENTORY="${2:-}";           shift 2 ;;
    --source-client)       SOURCE_CLIENT="${2:-}";       shift 2 ;;
    --destination-client)  DESTINATION_CLIENT="${2:-}";  shift 2 ;;
    -n|--lines)            JOURNAL_LINES="${2:-}";       shift 2 ;;
    --no-follow)           FOLLOW_MODE=false;            shift   ;;
    -h|--help)             usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -n "$WORKDIR" && -z "$INVENTORY" ]]; then
  INVENTORY="$WORKDIR/operator-inventory.yml"
fi

if [[ -z "$INVENTORY" ]]; then
  echo "ERROR: --workdir or --inventory is required" >&2; usage; exit 2
fi

if [[ ! -r "$INVENTORY" ]]; then
  echo "ERROR: inventory not readable: $INVENTORY" >&2; exit 1
fi

if ! command -v ansible-inventory >/dev/null 2>&1; then
  echo "ERROR: ansible-inventory not found" >&2; exit 1
fi

# Build the journalctl grep command for a given client type.
# Agave/Jito logs the identity change as "Identity set to <pubkey>".
# Firedancer logs it as a structured line containing "validator-set_identity".
build_identity_watch_cmd() {
  local client="$1"
  local lines="$2"
  local follow="$3"

  local journal_args=("-u" "sol" "-n" "$lines" "--no-pager" "-o" "short-iso")
  [[ "$follow" == "true" ]] && journal_args+=("-f")

  local grep_pattern
  case "$client" in
    agave|jito)      grep_pattern='[Ii]dentity' ;;
    frankendancer)   grep_pattern='set.identity\|validator.set.identity\|identity' ;;
    *)               grep_pattern='[Ii]dentity' ;;
  esac

  local cmd="sudo journalctl"
  for arg in "${journal_args[@]}"; do
    cmd+=" $(printf '%q' "$arg")"
  done
  cmd+=" | grep --line-buffered -i $(printf '%q' "$grep_pattern")"
  printf '%s\n' "$cmd"
}

# Resolve Ansible inventory vars for a host into shell variable assignments.
resolve_host_ssh() {
  local host="$1"
  ansible-inventory -i "$INVENTORY" --host "$host" \
    | python3 -c '
import json, shlex, sys
data = json.load(sys.stdin)
for key in ("ansible_host","ansible_port","ansible_user","ansible_ssh_private_key_file","ansible_ssh_common_args"):
    print(f"{key}={shlex.quote(str(data.get(key, \"\")))}")
'
}

# Open an SSH session to a host, prefix every output line with a colored label.
stream_host() {
  local host="$1"
  local remote_cmd="$2"
  local label="$3"
  local color="$4"
  local ansible_host="" ansible_port="" ansible_user=""
  local ansible_ssh_private_key_file="" ansible_ssh_common_args=""

  eval "$(resolve_host_ssh "$host")"

  if [[ -z "$ansible_host" || -z "$ansible_user" || -z "$ansible_ssh_private_key_file" ]]; then
    echo "ERROR: missing SSH fields for $host in $INVENTORY" >&2
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
    ssh_cmd+=( $ansible_ssh_common_args )
  fi
  ssh_cmd+=("${ansible_user}@${ansible_host}" "$remote_cmd")

  stdbuf -oL -eL "${ssh_cmd[@]}" \
    | awk -v label="$label" -v color="$color" '
        { reset="\033[0m"; printf "%s[%s]%s %s\n", color, label, reset, $0; fflush() }'
}

SRC_CMD="$(build_identity_watch_cmd "$SOURCE_CLIENT"      "$JOURNAL_LINES" "$FOLLOW_MODE")"
DST_CMD="$(build_identity_watch_cmd "$DESTINATION_CLIENT" "$JOURNAL_LINES" "$FOLLOW_MODE")"

echo "Streaming identity changes:" >&2
echo "  lat-source      ($SOURCE_CLIENT):      $SRC_CMD" >&2
echo "  lat-destination ($DESTINATION_CLIENT): $DST_CMD" >&2
echo "" >&2

declare -a PIDS=()
cleanup() { for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

stream_host "lat-source"      "$SRC_CMD" "source      ($SOURCE_CLIENT)"      $'\033[1;36m' &
PIDS+=("$!")
stream_host "lat-destination" "$DST_CMD" "destination ($DESTINATION_CLIENT)" $'\033[1;33m' &
PIDS+=("$!")

wait "${PIDS[@]}"

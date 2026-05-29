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
SOURCE_CLIENT=""            # auto-detected from workdir name; override with --source-client
DESTINATION_CLIENT=""       # auto-detected from workdir name; override with --destination-client
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
  --workdir <path>            Per-run case directory (contains operator-inventory.yml).
                              Client types are auto-detected from the directory name.
  --inventory <path>          Explicit path to operator inventory file
  --source-client <client>    Override client on lat-source: agave | jito | frankendancer
  --destination-client <c>    Override client on lat-destination: agave | jito | frankendancer
  -n, --lines <n>             Journal lines to show before following (default: 50)
  --no-follow                 Print recent matching lines and exit
  -h, --help                  Show this help

Examples:
  # Client types auto-detected from workdir name (no extra flags needed)
  follow-latitude-hot-swap.sh --workdir test-harness/work/latitude-hot-swap/latitude-hot-swap-jito_bam_to_frankendancer-20260529-123456
  follow-latitude-hot-swap.sh --workdir test-harness/work/latitude-hot-swap/latitude-hot-swap-frankendancer_to_jito_bam-20260529-123456

  # Explicit override when using --inventory directly
  follow-latitude-hot-swap.sh --inventory /path/to/operator-inventory.yml \
    --source-client frankendancer --destination-client jito
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

# Auto-detect client types from the workdir basename (e.g. latitude-hot-swap-CASE-YYYYMMDD-HHMMSS).
# Explicit --source-client / --destination-client flags always take precedence.
if [[ -n "$WORKDIR" && ( -z "$SOURCE_CLIENT" || -z "$DESTINATION_CLIENT" ) ]]; then
  _basename="$(basename "$WORKDIR")"
  # Strip trailing -YYYYMMDD-HHMMSS timestamp
  _no_ts="${_basename%-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]}"
  # Strip leading run-id prefix up to and including the first dash-separated segment pair
  _case="${_no_ts#latitude-hot-swap-}"
  case "$_case" in
    jito_bam_to_frankendancer)
      [[ -z "$SOURCE_CLIENT" ]]      && SOURCE_CLIENT="jito"
      [[ -z "$DESTINATION_CLIENT" ]] && DESTINATION_CLIENT="frankendancer"
      ;;
    frankendancer_to_jito_bam)
      [[ -z "$SOURCE_CLIENT" ]]      && SOURCE_CLIENT="frankendancer"
      [[ -z "$DESTINATION_CLIENT" ]] && DESTINATION_CLIENT="jito"
      ;;
    *)
      # Unknown case name — fall back to safe defaults and warn
      echo "WARNING: could not detect client types from workdir name '$_basename'" >&2
      echo "         Use --source-client and --destination-client to set them explicitly." >&2
      ;;
  esac
fi

# Final fallback if still unset (e.g. --inventory used without client flags)
SOURCE_CLIENT="${SOURCE_CLIENT:-jito}"
DESTINATION_CLIENT="${DESTINATION_CLIENT:-frankendancer}"

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

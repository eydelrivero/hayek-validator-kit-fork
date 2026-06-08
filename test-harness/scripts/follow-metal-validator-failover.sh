#!/usr/bin/env bash
# follow-metal-validator-failover.sh
#
# Unified, color-annotated real-time watcher for HA failover / hot-swap events on
# a metal (Latitude) HA validator cluster. For every host in the HA group it pulls
# from TWO sources and merges them into a single time-ordered, annotated feed:
#
#   * ha  -> journalctl -u solana-validator-ha   (failover decisions, delinquency)
#   * val -> the validator file-log              (identity-set, duplicate-instance,
#            tower rebuild, dead slots, partitions, "behind by N slots")
#
# The validator log path and grep pattern are chosen per host from the
# `validator_flavor` inventory variable (firedancer vs jito-bam/jito/agave).
#
# Ordering:
#   * Backfill (recent history) from ALL sources is collected, then sorted by each
#     line's embedded timestamp, so ha and val events from both hosts interleave
#     chronologically instead of appearing grouped per source.
#   * Live follow then appends events from every source in arrival order.
#
# Each line is prefixed with a colored [node·src] tag and, unless --raw is given,
# a semantic marker (icon + SEVERITY).
#
# Modeled on follow-metal-validator-ha.sh (inventory/SSH/become-pass plumbing) and
# follow-latitude-hot-swap.sh (per-client validator-log grep).

set -euo pipefail

INVENTORY_PATH="${INVENTORY_PATH:-}"
HA_GROUP="${HA_GROUP:-}"
HOST_SELECTOR="${HOST_SELECTOR:-all}"
SSH_USER="${SSH_USER:-}"
SSH_PORT="${SSH_PORT:-2522}"
USE_SUDO=false
ASK_BECOME_PASS=false
BECOME_PASSWORD="${BECOME_PASSWORD:-}"
SERVICE_NAME="${SERVICE_NAME:-solana-validator-ha}"
JOURNAL_LINES="${JOURNAL_LINES:-50}"
JOURNAL_SINCE="${JOURNAL_SINCE:-}"
FOLLOW_MODE=true
SOURCE_FILTER="both"            # ha | val | both
RAW_MODE=false                  # true -> colorize-only, no semantic markers
VALIDATOR_LOGS_DIR="${VALIDATOR_LOGS_DIR:-/opt/validator/logs}"

# Unit separator delimits the normalized record fields (never appears in logs).
DELIM=$'\x1f'

usage() {
  cat <<'EOF'
Usage:
  follow-metal-validator-failover.sh --inventory <path> [options]

Stream and annotate HA failover + validator hot-swap events from every host in a
metal HA cluster (solana-validator-ha journald + validator file-log together),
merged into one time-ordered feed.

Options:
  --inventory <path>          Ansible inventory file for the HA cluster (required)
  --ha-group <name>           Explicit HA inventory group (auto-detected by default)
  --host <primary|secondary|tertiary|all|inventory-host|node-id>
  --ssh-user <user>           SSH user override for all target hosts
  --ssh-port <port>           SSH port for all target hosts (default: 2522)
  --sudo                      Run journalctl (ha stream) via sudo
  -K, --ask-become-pass       Prompt once locally and feed the sudo password to the ha stream
  --service <name>            HA systemd unit to stream (default: solana-validator-ha)
  --source <ha|val|both>      Which sources to include per host (default: both)
  --raw                       Disable semantic markers; colorized labels only
  --validator-logs-dir <dir>  Validator log directory (default: /opt/validator/logs)
  -n, --lines <n>             Recent lines/events per source in the backfill (default: 50)
  --since <expr>              Only backfill events at/after this time, for BOTH ha and
                              val (any `date -d` expression, e.g. "2026-06-03 15:00",
                              "2 hours ago"). Great for reviewing a past incident.
  --no-follow                 Print the merged backfill and exit
  -h, --help                  Show this help

Examples:
  # Live, both hosts, both sources, sudo for the ha journal:
  follow-metal-validator-failover.sh \
    --inventory ansible/latitude-hayek-testnet-ha.yml \
    --ha-group solana_testnet --ssh-port 2522 --ssh-user eydel_admin --sudo -K

  # Review a past swap: merged, time-ordered, no live follow:
  follow-metal-validator-failover.sh \
    --inventory ansible/latitude-hayek-testnet-ha.yml \
    --ha-group solana_testnet --ssh-port 2522 --ssh-user eydel_admin --sudo -K \
    --since "2026-06-03 15:50" -n 500 --no-follow
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
    --inventory)            INVENTORY_PATH="${2:-}";        shift 2 ;;
    --ha-group)             HA_GROUP="${2:-}";              shift 2 ;;
    --host)                 HOST_SELECTOR="${2:-}";         shift 2 ;;
    --ssh-user)             SSH_USER="${2:-}";              shift 2 ;;
    --ssh-port)             SSH_PORT="${2:-}";              shift 2 ;;
    --sudo)                 USE_SUDO=true;                  shift   ;;
    -K|--ask-become-pass)   ASK_BECOME_PASS=true;           shift   ;;
    --service)              SERVICE_NAME="${2:-}";          shift 2 ;;
    --source)               SOURCE_FILTER="${2:-}";         shift 2 ;;
    --raw)                  RAW_MODE=true;                  shift   ;;
    --validator-logs-dir)   VALIDATOR_LOGS_DIR="${2:-}";    shift 2 ;;
    -n|--lines)             JOURNAL_LINES="${2:-}";         shift 2 ;;
    --since)                JOURNAL_SINCE="${2:-}";         shift 2 ;;
    --no-follow)            FOLLOW_MODE=false;              shift   ;;
    -h|--help)              usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
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
case "$SOURCE_FILTER" in
  ha|val|both) ;;
  *) echo "--source must be one of: ha, val, both" >&2; exit 2 ;;
esac
if [[ "$ASK_BECOME_PASS" == "true" && "$USE_SUDO" != "true" ]]; then
  echo "--ask-become-pass requires --sudo" >&2
  exit 2
fi

require_cmd ansible-inventory
require_cmd python3
require_cmd ssh
require_cmd stdbuf
require_cmd awk
require_cmd sort
require_cmd mktemp

# Resolve --since into a 14-digit YYYYMMDDHHMMSS cutoff key (UTC) used to filter
# the validator file-logs server-side. journalctl handles --since natively.
SINCE_KEY=""
if [[ -n "$JOURNAL_SINCE" ]]; then
  require_cmd date
  if ! SINCE_KEY="$(date -u -d "$JOURNAL_SINCE" +%Y%m%d%H%M%S 2>/dev/null)"; then
    echo "--since value not understood by 'date -d': $JOURNAL_SINCE" >&2
    exit 2
  fi
fi

# --- Remote command builders -------------------------------------------------

# journalctl command for the solana-validator-ha unit.
#   mode=follow            -> -n 0 -f (from now on)
#   mode=backfill, no since -> most recent N lines
#   mode=backfill, --since  -> first N lines at/after the cutoff (chronological)
build_ha_command() {
  local mode="$1"
  local args=("-u" "$SERVICE_NAME")
  local suffix=""
  if [[ "$mode" == "follow" ]]; then
    args+=("-n" "0" "-f")
  elif [[ -n "$JOURNAL_SINCE" ]]; then
    args+=("--since" "$JOURNAL_SINCE")
    suffix=" | head -n $(printf '%q' "$JOURNAL_LINES")"
  else
    args+=("-n" "$JOURNAL_LINES")
  fi
  args+=("--no-pager" "-o" "short-iso" "-q")

  if [[ "$USE_SUDO" == "true" ]]; then
    if [[ "$ASK_BECOME_PASS" == "true" ]]; then
      printf 'sudo -S -p "" journalctl'
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
  printf '%s\n' "$suffix"
}

# Server-side awk that keeps validator-log lines whose first embedded timestamp
# (YYYY-MM-DD[ T]HH:MM:SS) is at/after the SINCE_KEY cutoff. Regex is written
# without interval expressions for maximum awk portability on the remote hosts.
VAL_SINCE_AWK='{ if (match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ T][0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)) { k=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",k); if (k>=c) print } else { print } }'

# tail|grep command for the validator file-log.
build_val_command() {
  local mode="$1" logfile="$2" pattern="$3"
  local q_log q_pat q_lines q_key q_prog q_dir base
  q_log=$(printf '%q' "$logfile")
  q_pat=$(printf '%q' "$pattern")
  q_lines=$(printf '%q' "$JOURNAL_LINES")
  if [[ "$mode" == "follow" ]]; then
    printf 'tail -F -n 0 %s 2>/dev/null | grep --line-buffered -E %s\n' "$q_log" "$q_pat"
  elif [[ -n "$SINCE_KEY" ]]; then
    # Scoped to an incident: span rotated logs (the live file plus any
    # firedancer.log.1.gz / agave-validator.log.1[.gz]) oldest-first, decompress
    # .gz, then keep the first N matching events at/after the cutoff. journald
    # spans its own rotation; the validator text log does not, so we do it here.
    # NOTE: the directory is %q-quoted but the trailing '*' is left literal so
    # the remote shell globs it (a %q-escaped star would be treated literally).
    q_dir=$(printf '%q' "$VALIDATOR_LOGS_DIR")
    base=$(basename "$logfile")
    q_key=$(printf '%q' "$SINCE_KEY")
    q_prog=$(printf '%q' "$VAL_SINCE_AWK")
    printf 'for f in $(ls -1tr %s/%s* 2>/dev/null); do case "$f" in *.gz) zcat -- "$f" 2>/dev/null ;; *) cat -- "$f" 2>/dev/null ;; esac; done | grep -E %s | awk -v c=%s %s | head -n %s\n' \
      "$q_dir" "$base" "$q_pat" "$q_key" "$q_prog" "$q_lines"
  else
    # Live default: most recent N matching events from the live file only.
    printf 'grep -E %s %s 2>/dev/null | tail -n %s\n' "$q_pat" "$q_log" "$q_lines"
  fi
}

client_logfile() {
  local client="$1"
  case "$client" in
    firedancer) printf '%s/firedancer.log' "$VALIDATOR_LOGS_DIR" ;;
    *)          printf '%s/agave-validator.log' "$VALIDATOR_LOGS_DIR" ;;
  esac
}

client_pattern() {
  local client="$1"
  case "$client" in
    firedancer)
      printf '%s' 'validator-set_identity|duplicate running instances|Rebuilding a new tower|Starting validator with|replay-stage-mark_dead_slot|PARTITION (DETECTED|resolved)|Node is behind|Identity set to'
      ;;
    *)
      printf '%s' 'Identity set to|Rebuilding a new tower|Starting validator|mark_dead_slot|behind'
      ;;
  esac
}

# --- Inventory resolution ----------------------------------------------------

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
            and name != "ha_reconcile_peers"
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

def client(host_name):
    host_data = hostvars.get(host_name, {})
    return host_data.get("validator_flavor") or ""

print(f"HA_GROUP={quote(ha_group)}")
print("HA_HOSTS=(" + " ".join(quote(host_name) for host_name in hosts) + ")")
print("HA_LABELS=(" + " ".join(quote(label(host_name)) for host_name in hosts) + ")")
print("HA_CLIENTS=(" + " ".join(quote(client(host_name)) for host_name in hosts) + ")")

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
  all)       TARGET_HOSTS=("${HA_HOSTS[@]}") ;;
  primary)   TARGET_HOSTS=("$HA_PRIMARY_HOST") ;;
  secondary) TARGET_HOSTS=("$HA_SECONDARY_HOST") ;;
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
      exit 2
    fi
    ;;
esac

host_label() {
  local host="$1" idx
  for idx in "${!HA_HOSTS[@]}"; do
    if [[ "$host" == "${HA_HOSTS[$idx]}" ]]; then
      printf '%s\n' "${HA_LABELS[$idx]}"
      return 0
    fi
  done
  printf '%s\n' "$host"
}

host_coloridx() {
  local host="$1" idx
  for idx in "${!HA_HOSTS[@]}"; do
    if [[ "$host" == "${HA_HOSTS[$idx]}" ]]; then
      printf '%s' "$idx"
      return 0
    fi
  done
  printf '%s' "99"
}

client_for() {
  local host="$1" idx
  for idx in "${!HA_HOSTS[@]}"; do
    if [[ "$host" == "${HA_HOSTS[$idx]}" ]]; then
      printf '%s' "${HA_CLIENTS[$idx]}"
      return 0
    fi
  done
  printf '%s' ""
}

# --- Normalizer + annotation engine ------------------------------------------

# Normalizer: prepend a fixed-width sort key (extracted timestamp) plus the
# node/src/coloridx metadata, so records from every source can be merged and
# sorted chronologically. Output record: KEY<DELIM>node<DELIM>src<DELIM>ci<DELIM>raw
read -r -d '' NORMALIZE_AWK <<'AWK' || true
BEGIN { OFS="\x1f" }
{
  key="00000000000000000000000"
  if (match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?/)) {
    ts = substr($0, RSTART, RLENGTH)
    base = ts; sub(/\..*/, "", base); gsub(/[^0-9]/, "", base)   # YYYYMMDDHHMMSS
    frac = ""
    if (match(ts, /\.[0-9]+/)) frac = substr(ts, RSTART + 1, RLENGTH - 1)
    frac = substr(frac "000000000", 1, 9)
    key = base frac
  }
  print key, node, src, coloridx, $0
}
AWK

# Annotator: read normalized records, colorize the [node·src] tag and prepend a
# semantic marker, then the raw line.
read -r -d '' ANNOTATE_AWK <<'AWK' || true
function digits(s, re,   t) {
  if (match(s, re)) {
    t = substr(s, RSTART, RLENGTH)
    if (match(t, /[0-9]+/)) return substr(t, RSTART, RLENGTH)
  }
  return ""
}
function pk8(s, re,   t, last) {
  # First 8 chars of the LAST 8+ char alnum run in the match (the trailing pubkey).
  if (match(s, re)) {
    t = substr(s, RSTART, RLENGTH)
    last = ""
    while (match(t, /[A-Za-z0-9]{8,}/)) {
      last = substr(t, RSTART, RLENGTH)
      t = substr(t, RSTART + RLENGTH)
    }
    if (last != "") return substr(last, 1, 8)
  }
  return ""
}
BEGIN {
  FS="\x1f"
  RESET="\033[0m"; DIM="\033[2m"
  RED="\033[0;31m"; BRED="\033[1;31m"
  GRN="\033[0;32m"; BGRN="\033[1;32m"
  YEL="\033[0;33m"; BLU="\033[1;34m"; MAG="\033[0;35m"; CYN="\033[0;36m"; WHT="\033[1;37m"
  COL[0]="\033[1;36m"; COL[1]="\033[1;33m"; COL[2]="\033[1;35m"
}
{
  node=$2; src=$3; ci=$4+0; line=$5
  hcolor = (ci in COL) ? COL[ci] : WHT

  marker=""; mcolor=""; n=""; p=""
  if (line ~ /no active peer found.*failover required/)       { marker="🚨 FAILOVER-TRIGGER"; mcolor=BRED }
  else if (line ~ /becoming active/)                          { marker="🔴 TAKEOVER"; mcolor=BRED }
  else if (line ~ /we are confirmed to be active/)            { marker="🟢 NOW-ACTIVE"; mcolor=BGRN }
  else if (line ~ /active peer changed/)                      { marker="🔂 ROLE-CHANGE"; mcolor=CYN }
  else if (line ~ /duplicate running instances/)              { marker="💀 DUPLICATE-INSTANCE (self-kill)"; mcolor=BRED }
  else if (line ~ /Rebuilding a new tower/)                   { marker="🗼 TOWER-REBUILD"; mcolor=YEL }
  else if (line ~ /Starting validator with/)                  { marker="🚀 VALIDATOR-START"; mcolor=BLU }
  else if (line ~ /mark_dead_slot/)                           { n=digits(line, "slot=[0-9]+"); marker="☠️ DEAD-SLOT" (n?" "n:""); mcolor=RED }
  else if (line ~ /delinquent \(behind [0-9]+ slots/)         { n=digits(line, "behind [0-9]+ slots"); marker="⏱️ DELINQUENT" (n?" "n"s":""); mcolor=YEL }
  else if (line ~ /[Nn]ode is behind by [0-9]+ slots/)        { n=digits(line, "behind by [0-9]+ slots"); marker="🐢 BEHIND" (n?" "n"s":""); mcolor=YEL }
  else if (line ~ /Identity set to [A-Za-z0-9]+/)             { p=pk8(line, "Identity set to [A-Za-z0-9]+"); marker="🪪 IDENTITY-SET" (p?" "p:""); mcolor=GRN }
  else if (line ~ /validator-set_identity/)                   { p=pk8(line, "new_id=\"[A-Za-z0-9]+"); marker="🪪 IDENTITY-SET" (p?" "p:""); mcolor=GRN }
  else if (line ~ /PARTITION DETECTED/)                       { marker="⚠️ PARTITION"; mcolor=YEL }
  else if (line ~ /PARTITION resolved/)                       { marker="✅ PARTITION-OK"; mcolor=GRN }
  else if (line ~ /eligible for failover/)                    { marker="💚 HEALTHY-ELIGIBLE"; mcolor=GRN }
  else if (line ~ /should be added to failover\.peers/)       { marker="📋 UNDECLARED-PEER"; mcolor=MAG }
  else if (line ~ /we are unhealthy/)                         { marker="🤕 UNHEALTHY"; mcolor=YEL }

  tag = hcolor "[" node "·" RESET DIM src RESET hcolor "]" RESET
  if (raw == "1" || marker == "") {
    printf "%s %s\n", tag, line
  } else {
    printf "%s %s%s%s  %s\n", tag, mcolor, marker, RESET, line
  }
  fflush()
}
AWK

annotate() {
  local raw=0
  [[ "$RAW_MODE" == "true" ]] && raw=1
  awk -v raw="$raw" "$ANNOTATE_AWK"
}

# Open an SSH session to `host`, run `remote_cmd`, and emit normalized records
# (KEY|node|src|coloridx|rawline) on stdout.
emit_stream() {
  local host="$1" remote_cmd="$2" node="$3" src="$4" coloridx="$5" feed_pw="$6"
  local ansible_host="" inventory_ssh_user="" ansible_ssh_private_key_file=""
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
  [[ -n "$ansible_ssh_private_key_file" ]] && ssh_cmd+=(-i "$ansible_ssh_private_key_file")
  ((${#ansible_ssh_common_args[@]} > 0)) && ssh_cmd+=("${ansible_ssh_common_args[@]}")
  ssh_cmd+=("${effective_ssh_user}@${ansible_host}" "$remote_cmd")

  if [[ "$feed_pw" == "true" ]]; then
    printf '%s\n' "$BECOME_PASSWORD" \
      | stdbuf -oL -eL "${ssh_cmd[@]}" 2>&1 \
      | stdbuf -oL awk -v node="$node" -v src="$src" -v coloridx="$coloridx" "$NORMALIZE_AWK"
  else
    stdbuf -oL -eL "${ssh_cmd[@]}" 2>&1 \
      | stdbuf -oL awk -v node="$node" -v src="$src" -v coloridx="$coloridx" "$NORMALIZE_AWK"
  fi
}

# --- Build the per-source task list ------------------------------------------

want_ha() { [[ "$SOURCE_FILTER" == "ha" || "$SOURCE_FILTER" == "both" ]]; }
want_val() { [[ "$SOURCE_FILTER" == "val" || "$SOURCE_FILTER" == "both" ]]; }

# --- Become password prompt (only if an ha stream will actually run) ---------

if [[ "$ASK_BECOME_PASS" == "true" ]] && want_ha && [[ -z "$BECOME_PASSWORD" ]]; then
  if [[ ! -t 0 ]]; then
    echo "Cannot prompt for sudo password without a TTY; set BECOME_PASSWORD or omit --ask-become-pass" >&2
    exit 2
  fi
  read -rsp 'BECOME password: ' BECOME_PASSWORD
  printf '\n' >&2
fi

declare -a PIDS=()
declare -a BF_TMPS=()
cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  local f
  for f in "${BF_TMPS[@]:-}"; do
    rm -f "$f" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

ha_feed_pw=false
[[ "$ASK_BECOME_PASS" == "true" ]] && ha_feed_pw=true

# --- Phase 1: collect backfill from all sources, merge, sort, annotate -------

for host in "${TARGET_HOSTS[@]}"; do
  node="$(host_label "$host")"
  ci="$(host_coloridx "$host")"
  client="$(client_for "$host")"

  if want_ha; then
    t="$(mktemp)"; BF_TMPS+=("$t")
    emit_stream "$host" "$(build_ha_command backfill)" "$node" "ha " "$ci" "$ha_feed_pw" >"$t" &
    PIDS+=("$!")
  fi
  if want_val; then
    logfile="$(client_logfile "$client")"
    pattern="$(client_pattern "$client")"
    t="$(mktemp)"; BF_TMPS+=("$t")
    emit_stream "$host" "$(build_val_command backfill "$logfile" "$pattern")" "$node" "val" "$ci" "false" >"$t" &
    PIDS+=("$!")
  fi
done

if ((${#PIDS[@]} > 0)); then
  wait "${PIDS[@]}"
fi
PIDS=()

if ((${#BF_TMPS[@]} > 0)); then
  LC_ALL=C sort -t "$DELIM" -k1,1 -- "${BF_TMPS[@]}" | annotate
fi
for f in "${BF_TMPS[@]:-}"; do rm -f "$f" 2>/dev/null || true; done
BF_TMPS=()

if [[ "$FOLLOW_MODE" != "true" ]]; then
  exit 0
fi

# --- Phase 2: live follow; each source annotates and prints in arrival order --

for host in "${TARGET_HOSTS[@]}"; do
  node="$(host_label "$host")"
  ci="$(host_coloridx "$host")"
  client="$(client_for "$host")"

  if want_ha; then
    emit_stream "$host" "$(build_ha_command follow)" "$node" "ha " "$ci" "$ha_feed_pw" | annotate &
    PIDS+=("$!")
  fi
  if want_val; then
    logfile="$(client_logfile "$client")"
    pattern="$(client_pattern "$client")"
    emit_stream "$host" "$(build_val_command follow "$logfile" "$pattern")" "$node" "val" "$ci" "false" | annotate &
    PIDS+=("$!")
  fi
done

if ((${#PIDS[@]} > 0)); then
  wait "${PIDS[@]}"
fi

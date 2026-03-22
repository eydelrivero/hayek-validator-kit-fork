#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
EXPECTED_QEMU_ROOT="${REPO_ROOT}/test-harness/work/"
ENTRYPOINT_VM_IP="192.168.100.13"
SOURCE_VM_IP="192.168.100.11"
DESTINATION_VM_IP="192.168.100.12"
SOLANA_RPC_URL="http://${ENTRYPOINT_VM_IP}:8899"
PRIMARY_TARGET_IDENTITY="demoneTKvfN3Bx2jhZoAHhNbJAzt2rom61xyqMe5Fcw"
WATCH_ENABLED=0
WATCH_INTERVAL=30
WATCH_DEBUG=0
WATCH_DEBUG_ROOT="${EXPECTED_QEMU_ROOT}/status-debug"
WATCH_DEBUG_RUN_DIR=""
WATCH_SSH_KEY="${REPO_ROOT}/scripts/vm-test/work/id_ed25519"
WATCH_VALIDATOR_OPERATOR_USER="bob"
WATCH_SOURCE_SSH_PORT=2522
WATCH_DESTINATION_SSH_PORT=2522
WATCH_CATCHUP_TIMEOUT_SEC=8
WATCH_SAMPLE_HISTORY=()
WATCH_SCREEN_INITIALIZED=0
WATCH_PREV_ENT_PID=""
WATCH_TESTCASE_BOUNDARY_MARKER="__WATCH_TESTCASE_BOUNDARY__"
WATCH_TABLE_WIDTH=0

# Colors
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  GRAY=$'\033[90m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  BLUE=$'\033[34m'
  MAGENTA=$'\033[35m'
  CYAN=$'\033[36m'
  RESET=$'\033[0m'
else
  BOLD=""
  DIM=""
  GRAY=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  CYAN=""
  RESET=""
fi

CAN_COLOR=0
if [[ -t 1 ]]; then
  CAN_COLOR=1
fi

line() {
  printf '%s\n' "──────────────────────────────────────────────────────────────────────────────"
}

watch_line() {
  local width="${1:-78}"
  awk -v n="$width" 'BEGIN { for (i = 0; i < n; i++) printf "─"; printf "\n" }'
}

strip_ansi() {
  sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g'
}

visible_length() {
  local text="${1:-}"
  printf '%s' "$text" | strip_ansi | awk '{ print length }'
}

gray_middle_dots() {
  local text="${1:-}"

  if (( ! CAN_COLOR )); then
    printf '%s' "$text"
    return 0
  fi

  printf '%s' "${text// · / ${GRAY}·${RESET} }"
}

blue_ip_in_header() {
  local text="${1:-}"
  local ip="${2:-}"

  if (( ! CAN_COLOR )) || [[ -z "$ip" ]]; then
    printf '%s' "$text"
    return 0
  fi

  printf '%s' "${text/"$ip"/"${BLUE}${ip}${RESET}"}"
}

header() {
  local title="$1"
  echo
  line
  printf '%b%s%b\n' "${BOLD}${CYAN}" "$title" "${RESET}"
  line
}

subtle() {
  printf '%b%s%b\n' "${DIM}" "$1" "${RESET}"
}

ok() {
  printf '%b%s%b\n' "${GREEN}" "$1" "${RESET}"
}

warn() {
  printf '%b%s%b\n' "${YELLOW}" "$1" "${RESET}"
}

err() {
  printf '%b%s%b\n' "${RED}" "$1" "${RESET}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

discover_latest_operator_inventory() {
  find "$EXPECTED_QEMU_ROOT" -type f -name 'inventory.operator.yml' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | awk 'NR==1 { print $2 }'
}

load_watch_ssh_targets_from_inventory() {
  local inventory_file="${1:-}"
  local parsed=""

  [[ -n "$inventory_file" && -r "$inventory_file" ]] || return 0

  parsed="$(
    awk '
      $1 == "vm-source:" { host="src"; next }
      $1 == "vm-destination:" { host="dst"; next }
      host == "src" && $1 == "ansible_host:" { src_host=$2; next }
      host == "src" && $1 == "ansible_port:" { src_port=$2; host=""; next }
      host == "dst" && $1 == "ansible_host:" { dst_host=$2; next }
      host == "dst" && $1 == "ansible_port:" { dst_port=$2; host=""; next }
      END {
        print src_host
        print src_port
        print dst_host
        print dst_port
      }
    ' "$inventory_file"
  )"

  if [[ -n "$(sed -n '1p' <<< "$parsed")" ]]; then
    SOURCE_VM_IP="$(sed -n '1p' <<< "$parsed")"
  fi
  if [[ "$(sed -n '2p' <<< "$parsed")" =~ ^[0-9]+$ ]]; then
    WATCH_SOURCE_SSH_PORT="$(sed -n '2p' <<< "$parsed")"
  fi
  if [[ -n "$(sed -n '3p' <<< "$parsed")" ]]; then
    DESTINATION_VM_IP="$(sed -n '3p' <<< "$parsed")"
  fi
  if [[ "$(sed -n '4p' <<< "$parsed")" =~ ^[0-9]+$ ]]; then
    WATCH_DESTINATION_SSH_PORT="$(sed -n '4p' <<< "$parsed")"
  fi
}

run_solana() {
  if command_exists solana; then
    solana -u "$SOLANA_RPC_URL" "$@" 2>&1 || true
  else
    return 127
  fi
}

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--watch [SECONDS]] [--debug]

Options:
  --watch           Repeat every 30 seconds until Ctrl+C
  --watch SECONDS   Repeat every SECONDS until Ctrl+C
  --watch=SECONDS   Same as above
  --watch off       Run once
  --watch 0         Run once
  --debug           Write raw catchup probe output under test-harness/work/status-debug/
  -h, --help        Show this help

Default behavior:
  Run once
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --watch)
        WATCH_ENABLED=1
        if (($# >= 2)) && [[ ! "$2" =~ ^- ]]; then
          case "$2" in
            off|0)
              WATCH_ENABLED=0
              WATCH_INTERVAL=30
              ;;
            *)
              if [[ "$2" =~ ^[0-9]+$ ]]; then
                WATCH_INTERVAL="$2"
                WATCH_ENABLED=1
              else
                err "Invalid value for --watch: $2"
                exit 1
              fi
              ;;
          esac
          shift 2
        else
          WATCH_INTERVAL=30
          shift
        fi
        ;;
      --watch=*)
        local value="${1#*=}"
        case "$value" in
          off|0)
            WATCH_ENABLED=0
            WATCH_INTERVAL=30
            ;;
          *)
            if [[ "$value" =~ ^[0-9]+$ ]]; then
              WATCH_INTERVAL="$value"
              WATCH_ENABLED=1
            else
              err "Invalid value for --watch: $value"
              exit 1
            fi
            ;;
        esac
        shift
        ;;
      --debug)
        WATCH_DEBUG=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unknown argument: $1"
        echo
        usage
        exit 1
        ;;
    esac
  done
}

longest_common_prefix() {
  local prefix="$1"
  shift || true
  local s

  for s in "$@"; do
    while [[ "${s#"$prefix"}" == "$s" && -n "$prefix" ]]; do
      prefix="${prefix%?}"
    done
    [[ -z "$prefix" ]] && break
  done

  printf '%s' "$prefix"
}

trim_prefix_to_dir_boundary() {
  local p="$1"
  [[ "$p" == */* ]] && printf '%s' "${p%/*}/" || printf ''
}

pressure_color() {
  local pct="$1"
  if (( pct >= 90 )); then
    printf '%s' "$RED"
  elif (( pct >= 75 )); then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

print_resource_pressure() {
  header "Resource Pressure"

  print_cpu_pressure
  echo
  print_ram_pressure
  echo
  print_disk_pressure
}

print_cpu_pressure() {
  local load1 load5 load15 cpu_count
  load1="?"
  load5="?"
  load15="?"
  cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo '?')"

  if [[ -r /proc/loadavg ]]; then
    read -r load1 load5 load15 _ < /proc/loadavg
  fi

  printf '%bCPU%b\n' "$BOLD" "$RESET"
  printf '  Cores: %s\n' "$cpu_count"
  printf '  Load average: %s %s %s (1m, 5m, 15m)\n' "$load1" "$load5" "$load15"

  if [[ "$cpu_count" =~ ^[0-9]+$ ]] && command_exists awk && [[ "$load1" != "?" ]]; then
    local pct color
    pct="$(awk -v l="$load1" -v c="$cpu_count" 'BEGIN { if (c > 0) printf "%.0f", (l/c)*100; else print "0" }')"
    color="$(pressure_color "$pct")"
    printf '  Pressure: %b%s%%%b of total core capacity (based on 1m load)\n' "$color" "$pct" "$RESET"
  fi
}

print_ram_pressure() {
  printf '%bRAM%b\n' "$BOLD" "$RESET"

  if command_exists free; then
    local mem_line total used free_mem shared buff_cache available used_pct color
    mem_line="$(free -m | awk '/^Mem:/ {print $2, $3, $4, $5, $6, $7}')"
    read -r total used free_mem shared buff_cache available <<< "$mem_line"

    if [[ -n "${total:-}" && "$total" -gt 0 ]]; then
      used_pct="$(( (used * 100) / total ))"
      color="$(pressure_color "$used_pct")"

      printf '  Total:      %s MiB\n' "$total"
      printf '  Used:       %b%s MiB (%s%%)%b\n' "$color" "$used" "$used_pct" "$RESET"
      printf '  Available:  %s MiB\n' "$available"
      printf '  Free:       %s MiB\n' "$free_mem"
      printf '  Buff/Cache: %s MiB\n' "$buff_cache"
    else
      warn "Could not parse RAM usage."
    fi
  else
    warn "'free' command not found."
  fi
}

print_disk_pressure() {
  printf '%bDisk%b\n' "$BOLD" "$RESET"

  if command_exists df; then
    df -hP / 2>/dev/null | awk 'NR==1 {next} NR==2 {print $1, $2, $3, $4, $5, $6}' | while read -r fs size used avail usep mount; do
      local pct color num
      num="${usep%%%}"
      if [[ "$num" =~ ^[0-9]+$ ]]; then
        color="$(pressure_color "$num")"
        printf '  Root FS:    %s mounted on %s\n' "$fs" "$mount"
        printf '  Size:       %s\n' "$size"
        printf '  Used:       %b%s (%s)%b\n' "$color" "$used" "$usep" "$RESET"
        printf '  Available:  %s\n' "$avail"
      else
        printf '  Root FS:    %s mounted on %s\n' "$fs" "$mount"
        printf '  Size:       %s\n' "$size"
        printf '  Used:       %s (%s)\n' "$used" "$usep"
        printf '  Available:  %s\n' "$avail"
      fi
    done
  else
    warn "'df' command not found."
  fi
}

normalize_qemu_file_path() {
  local p="$1"
  local role="$2"
  local scenario_root="$3"
  local scenario_leaf=""
  local stem=""
  local dir=""
  local base=""

  p="${p#"$EXPECTED_QEMU_ROOT"}"
  [[ -n "$scenario_root" ]] && p="${p#"$scenario_root"}"

  dir="${p%/*}"
  base="${p##*/}"
  [[ "$dir" == "$base" ]] && dir=""

  scenario_leaf="${scenario_root%/}"
  scenario_leaf="${scenario_leaf##*/}"

  case "$role" in
    entrypoint) stem="hvk-entry-${scenario_leaf}" ;;
    source) stem="hvk-src-${scenario_leaf}" ;;
    destination) stem="hvk-dst-${scenario_leaf}" ;;
    *) stem="" ;;
  esac

  if [[ -n "$stem" ]]; then
    case "$base" in
      "${stem}.qcow2") base="root.qcow2" ;;
      "${stem}-ledger.qcow2") base="ledger.qcow2" ;;
      "${stem}-accounts.qcow2") base="accounts.qcow2" ;;
      "${stem}-snapshots.qcow2") base="snapshots.qcow2" ;;
      "${stem}-seed.iso") base="seed.iso" ;;
    esac
  fi

  if [[ -n "$dir" ]]; then
    printf '%s/%s' "$dir" "$base"
  else
    printf '%s' "$base"
  fi
}

print_qemu_processes() {
  header "QEMU VMs"

  local ps_out
  ps_out="$(
    ps -eo pid=,args= \
    | awk '
      /qemu-system-(x86_64|aarch64)/ &&
      (/ifname=tap-hvk-src/ || /ifname=tap-hvk-dst/ || /ifname=tap-hvk-ent/)
    ' 2>/dev/null || true
  )"

  if [[ -z "${ps_out// }" ]]; then
    warn "No matching QEMU processes found."
    return 0
  fi

  local -a extracted_paths=()
  local -a relative_paths=()
  local -a nonmatching_paths=()
  local row pid cmd role p

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    cmd="${row#* }"

    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      extracted_paths+=("$p")

      if [[ "$p" == "$EXPECTED_QEMU_ROOT"* ]]; then
        relative_paths+=("${p#"$EXPECTED_QEMU_ROOT"}")
      else
        nonmatching_paths+=("$p")
      fi
    done < <(grep -o 'file=[^, ]*' <<< "$cmd" | sed 's/^file=//')
  done <<< "$ps_out"

  if ((${#extracted_paths[@]} == 0)); then
    warn "No file= paths were found in the matching QEMU commands."
  else
    printf '%bWork root:%b %s\n' "$BOLD" "$RESET" "$EXPECTED_QEMU_ROOT"
  fi

  if ((${#nonmatching_paths[@]} > 0)); then
    warn "Some QEMU file paths do not match the expected work root:"
    printf '%s\n' "${nonmatching_paths[@]}" | sed 's/^/  - /'
    echo
  else
    ok "All extracted QEMU file paths match the expected work root."
    echo
  fi

  local scenario_root=""
  if ((${#relative_paths[@]} > 0)); then
    scenario_root="$(longest_common_prefix "${relative_paths[0]}" "${relative_paths[@]:1}")"
    scenario_root="$(trim_prefix_to_dir_boundary "$scenario_root")"

    if [[ -n "$scenario_root" ]]; then
      printf '%bScenario root:%b %s\n\n' "$BOLD" "$RESET" "$scenario_root"
    else
      warn "Could not determine a shared scenario root under the work root."
      echo
    fi
  fi

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue

    pid="${row%% *}"
    cmd="${row#* }"

    case "$cmd" in
      *ifname=tap-hvk-src*) role="source" ;;
      *ifname=tap-hvk-dst*) role="destination" ;;
      *ifname=tap-hvk-ent*) role="entrypoint" ;;
      *) role="unknown" ;;
    esac

    printf '%bPID:%b %s  %bROLE:%b %s\n' \
      "$BOLD" "$RESET" "$pid" "$BOLD" "$RESET" "$role"

    local token out=""
    for token in $cmd; do
      if [[ "$token" == file=* ]]; then
        local f="${token#file=}"
        token="file=$(normalize_qemu_file_path "$f" "$role" "$scenario_root")"
      fi
      out+="${token} "
    done
    out="${out% }"

    printf '%s\n' "$out" \
      | sed 's/ -/\n    -/g' \
      | sed '1s/^/    /'

    echo
  done <<< "$ps_out"
}

print_solana_epoch_info() {
  header "Solana Epoch Info"

  if ! command_exists solana; then
    err "solana CLI not found in PATH."
    return 0
  fi

  local out
  out="$(run_solana epoch-info)"

  if [[ -z "${out// }" ]]; then
    warn "No output."
    return 0
  fi

  printf '%s\n' "$out" | sed 's/^/  /'
}

print_solana_gossip() {
  header "Solana Gossip"

  if ! command_exists solana; then
    err "solana CLI not found in PATH."
    return 0
  fi

  local out
  out="$(run_solana gossip)"

  if [[ -z "${out// }" ]]; then
    warn "No output."
    return 0
  fi

  printf '%s\n' "$out" | sed 's/^/  /'
}

print_solana_validators() {
  header "Solana Validator Summary"

  if ! command_exists solana; then
    err "solana CLI not found in PATH."
    return 0
  fi

  local out
  out="$(run_solana validators --keep-unstaked-delinquents)"

  if [[ -z "${out// }" ]]; then
    warn "No output."
    return 0
  fi

  if grep -qiE 'error:|failed|unable|connection refused|rpc error|json_rpc' <<< "$out"; then
    warn "Could not get validator summary."
    printf '%s\n' "$out" | sed 's/^/  /'
    return 0
  fi

  printf '%s\n' "$out" | sed 's/^/  /'
}

reset_watch_metrics() {
  WATCH_TS="?"
  WATCH_VM_COUNT="?"
  WATCH_CPU_PCT="?"
  WATCH_RAM_PCT="?"
  WATCH_DISK_PCT="?"
  WATCH_ENT_PID="?"
  WATCH_SRC_PID="?"
  WATCH_DST_PID="?"
  WATCH_EPOCH="?"
  WATCH_SLOT="?"
  WATCH_EPOCH_PCT="?"
  WATCH_EPOCH_TIME="?"
  WATCH_GOSSIP_NODES="?"
  WATCH_ENT_IP="$ENTRYPOINT_VM_IP"
  WATCH_ENT_IDENTITY="?"
  WATCH_ENT_VERSION="?"
  WATCH_ENT_LAST_VOTE="?"
  WATCH_ENT_ACTIVE_STAKE="?"
  WATCH_SRC_IP="$SOURCE_VM_IP"
  WATCH_SRC_IDENTITY="?"
  WATCH_SRC_VERSION="?"
  WATCH_SRC_ACTIVE_STAKE="?"
  WATCH_SRC_CATCHUP="?"
  WATCH_DST_IP="$DESTINATION_VM_IP"
  WATCH_DST_IDENTITY="?"
  WATCH_DST_VERSION="?"
  WATCH_DST_ACTIVE_STAKE="?"
  WATCH_DST_CATCHUP="?"
}

collect_cpu_watch_metrics() {
  WATCH_CPU_PCT="?"

  local cpu_count
  cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo '?')"

  local load1="?"
  if [[ -r /proc/loadavg ]]; then
    read -r load1 _ < /proc/loadavg
  fi

  if [[ "$cpu_count" =~ ^[0-9]+$ ]] && [[ "$load1" != "?" ]] && command_exists awk; then
    WATCH_CPU_PCT="$(awk -v l="$load1" -v c="$cpu_count" 'BEGIN { if (c > 0) printf "%.0f%%", (l/c)*100; else print "?" }')"
  fi
}

collect_ram_watch_metrics() {
  WATCH_RAM_PCT="?"

  if command_exists free; then
    local mem_line total used
    mem_line="$(free -m | awk '/^Mem:/ {print $2, $3}')"
    read -r total used <<< "$mem_line"

    if [[ -n "${total:-}" && "$total" =~ ^[0-9]+$ && "$total" -gt 0 && -n "${used:-}" && "$used" =~ ^[0-9]+$ ]]; then
      WATCH_RAM_PCT="$(( (used * 100) / total ))%"
    fi
  fi
}

collect_disk_watch_metrics() {
  WATCH_DISK_PCT="?"

  if command_exists df; then
    local usep
    usep="$(df -hP / 2>/dev/null | awk 'NR==2 {print $5}')"
    [[ -n "${usep:-}" ]] && WATCH_DISK_PCT="$usep"
  fi
}

collect_qemu_watch_metrics() {
  local parsed
  parsed="$(
    ps -eo pid=,args= \
    | awk '
      /qemu-system-(x86_64|aarch64)/ &&
      (/ifname=tap-hvk-src/ || /ifname=tap-hvk-dst/ || /ifname=tap-hvk-ent/) {
        count++
        pid = $1
        if ($0 ~ /ifname=tap-hvk-ent/ && ent_pid == "") ent_pid = pid
        if ($0 ~ /ifname=tap-hvk-src/ && src_pid == "") src_pid = pid
        if ($0 ~ /ifname=tap-hvk-dst/ && dst_pid == "") dst_pid = pid
      }
      END {
        print count + 0
        print ent_pid
        print src_pid
        print dst_pid
      }
    ' 2>/dev/null || true
  )"

  WATCH_VM_COUNT="$(sed -n '1p' <<< "$parsed")"
  WATCH_ENT_PID="$(sed -n '2p' <<< "$parsed")"
  WATCH_SRC_PID="$(sed -n '3p' <<< "$parsed")"
  WATCH_DST_PID="$(sed -n '4p' <<< "$parsed")"

  [[ -z "${WATCH_VM_COUNT// }" ]] && WATCH_VM_COUNT="?"
  [[ -z "${WATCH_ENT_PID// }" ]] && WATCH_ENT_PID="?"
  [[ -z "${WATCH_SRC_PID// }" ]] && WATCH_SRC_PID="?"
  [[ -z "${WATCH_DST_PID// }" ]] && WATCH_DST_PID="?"
}

collect_epoch_watch_metrics() {
  WATCH_EPOCH="?"
  WATCH_SLOT="?"
  WATCH_EPOCH_PCT="?"
  WATCH_EPOCH_TIME="?"

  command_exists solana || return 0

  local out
  out="$(run_solana epoch-info)"

  if [[ -z "${out// }" ]] || grep -qiE 'error:|failed|unable|connection refused|rpc error|json_rpc' <<< "$out"; then
    return 0
  fi

  local parsed
  parsed="$(
    awk -F ': *' '
      /^[[:space:]]*Epoch:/ { epoch = $2 }
      /^[[:space:]]*Slot:/ { slot = $2 }
      /^[[:space:]]*Epoch Completed Percent:/ { epoch_pct = $2 }
      /^[[:space:]]*Epoch Completed Time:/ { epoch_time = $2 }
      END {
        print epoch
        print slot
        print epoch_pct
        print epoch_time
      }
    ' <<< "$out"
  )"

  WATCH_EPOCH="$(sed -n '1p' <<< "$parsed")"
  WATCH_SLOT="$(sed -n '2p' <<< "$parsed")"
  WATCH_EPOCH_PCT="$(sed -n '3p' <<< "$parsed")"
  WATCH_EPOCH_TIME="$(sed -n '4p' <<< "$parsed")"

  if [[ "$WATCH_EPOCH_PCT" =~ ^[0-9]+([.][0-9]+)?%$ ]] && command_exists awk; then
    WATCH_EPOCH_PCT="$(
      awk -v pct="${WATCH_EPOCH_PCT%%%}" 'BEGIN { printf "%.2f%%", pct + 0 }'
    )"
  fi

  [[ -z "${WATCH_EPOCH// }" ]] && WATCH_EPOCH="?"
  [[ -z "${WATCH_SLOT// }" ]] && WATCH_SLOT="?"
  [[ -z "${WATCH_EPOCH_PCT// }" ]] && WATCH_EPOCH_PCT="?"
  [[ -z "${WATCH_EPOCH_TIME// }" ]] && WATCH_EPOCH_TIME="?"
}

collect_gossip_watch_metrics() {
  WATCH_GOSSIP_NODES="?"
  WATCH_ENT_IDENTITY="?"
  WATCH_ENT_VERSION="?"
  WATCH_SRC_IDENTITY="?"
  WATCH_SRC_VERSION="?"
  WATCH_DST_IDENTITY="?"
  WATCH_DST_VERSION="?"

  command_exists solana || return 0

  local out
  out="$(run_solana gossip)"

  if [[ -z "${out// }" ]] || grep -qiE 'error:|failed|unable|connection refused|rpc error|json_rpc' <<< "$out"; then
    return 0
  fi

  local parsed
  parsed="$(
    awk -v ent_ip="$ENTRYPOINT_VM_IP" -v src_ip="$SOURCE_VM_IP" -v dst_ip="$DESTINATION_VM_IP" '
      function trim(s) {
        sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        return s
      }

      function column_index(name,    i) {
        for (i = 1; i <= header_count; i++) {
          if (header[i] == name) {
            return i
          }
        }
        return 0
      }

      /^[[:space:]]*Nodes:/ {
        nodes = trim(substr($0, index($0, ":") + 1))
        next
      }

      /\|/ {
        n = split($0, cols, /\|/)
        if (n < 2) {
          next
        }

        for (i = 1; i <= n; i++) {
          cols[i] = trim(cols[i])
        }

        if (cols[1] == "IP Address" || cols[1] == "IP Address        " || cols[1] == "IP") {
          delete header
          header_count = 0
          for (i = 1; i <= n; i++) {
            if (cols[i] != "") {
              header[++header_count] = cols[i]
            }
          }
          next
        }

        if (cols[1] ~ /^-+$/) {
          next
        }

        ip_idx = column_index("IP Address")
        identity_idx = column_index("Identity")
        version_idx = column_index("Version")

        if (!ip_idx) ip_idx = 1
        if (!identity_idx) identity_idx = 2

        ip = cols[ip_idx]
        identity = cols[identity_idx]
        version = version_idx ? cols[version_idx] : "?"

        if (ip == "" || ip ~ /^-+$/ || identity == "") {
          next
        }

        if (ip == ent_ip) {
          ent_identity = identity
          ent_version = version
        } else if (ip == src_ip) {
          src_identity = identity
          src_version = version
        } else if (ip == dst_ip) {
          dst_identity = identity
          dst_version = version
        }
      }

      END {
        print nodes
        print ent_identity
        print ent_version
        print src_identity
        print src_version
        print dst_identity
        print dst_version
      }
    ' <<< "$out"
  )"

  WATCH_GOSSIP_NODES="$(sed -n '1p' <<< "$parsed")"
  WATCH_ENT_IDENTITY="$(sed -n '2p' <<< "$parsed")"
  WATCH_ENT_VERSION="$(sed -n '3p' <<< "$parsed")"
  WATCH_SRC_IDENTITY="$(sed -n '4p' <<< "$parsed")"
  WATCH_SRC_VERSION="$(sed -n '5p' <<< "$parsed")"
  WATCH_DST_IDENTITY="$(sed -n '6p' <<< "$parsed")"
  WATCH_DST_VERSION="$(sed -n '7p' <<< "$parsed")"

  [[ -z "${WATCH_GOSSIP_NODES// }" ]] && WATCH_GOSSIP_NODES="?"
  [[ -z "${WATCH_ENT_IDENTITY// }" ]] && WATCH_ENT_IDENTITY="?"
  [[ -z "${WATCH_ENT_VERSION// }" ]] && WATCH_ENT_VERSION="?"
  [[ -z "${WATCH_SRC_IDENTITY// }" ]] && WATCH_SRC_IDENTITY="?"
  [[ -z "${WATCH_SRC_VERSION// }" ]] && WATCH_SRC_VERSION="?"
  [[ -z "${WATCH_DST_IDENTITY// }" ]] && WATCH_DST_IDENTITY="?"
  [[ -z "${WATCH_DST_VERSION// }" ]] && WATCH_DST_VERSION="?"
}

collect_validator_watch_metrics() {
  WATCH_ENT_LAST_VOTE="?"
  WATCH_ENT_ACTIVE_STAKE="?"
  WATCH_SRC_ACTIVE_STAKE="?"
  WATCH_DST_ACTIVE_STAKE="?"

  command_exists solana || return 0

  local out
  out="$(run_solana validators --keep-unstaked-delinquents)"

  if [[ -z "${out// }" ]] || grep -qiE 'error:|failed|unable|connection refused|rpc error|json_rpc' <<< "$out"; then
    return 0
  fi

  local parsed
  parsed="$(
    awk -v ent_id="$WATCH_ENT_IDENTITY" -v src_id="$WATCH_SRC_IDENTITY" -v dst_id="$WATCH_DST_IDENTITY" '
      function trim(s) {
        sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        return s
      }

      function is_base58(s) {
        return s ~ /^[1-9A-HJ-NP-Za-km-z]{32,}$/
      }

      {
        line = trim($0)

        if (line == "" ||
            line ~ /^Identity[[:space:]]+/ ||
            line ~ /^Average / ||
            line ~ /^(Current Stake|Active Stake|Delinquent Stake):/ ||
            line ~ /^Stake By Version:/) {
          next
        }

        token_count = split(line, parts, /[[:space:]]+/)
        start = 1

        while (start <= token_count && !is_base58(parts[start])) {
          start++
        }

        if (start + 2 > token_count || !is_base58(parts[start]) || !is_base58(parts[start + 1]) || parts[start + 2] !~ /^[0-9]+%$/) {
          next
        }

        identity = parts[start]

        tail = ""
        for (i = start + 3; i <= token_count; i++) {
          tail = tail (tail == "" ? "" : " ") parts[i]
        }
        tail = trim(tail)

        active_stake = "?"
        if (match(tail, /[0-9][0-9.,]* SOL \([^)]*\)$/)) {
          active_stake = substr(tail, RSTART, RLENGTH)
          tail = trim(substr(tail, 1, RSTART - 1))
        }

        if (match(tail, /[^[:space:]]+$/)) {
          tail = trim(substr(tail, 1, RSTART - 1))
        }

        if (match(tail, /[0-9]+$/)) {
          tail = trim(substr(tail, 1, RSTART - 1))
        }

        if (match(tail, /([^[:space:]]+%|-)$/)) {
          tail = trim(substr(tail, 1, RSTART - 1))
        }

        if (match(tail, /-$/)) {
          tail = trim(substr(tail, 1, RSTART - 1))
        } else if (match(tail, /[0-9]+ \([[:space:]]*[0-9]+[[:space:]]*\)$/)) {
          tail = trim(substr(tail, 1, RSTART - 1))
        } else if (match(tail, /[0-9]+$/)) {
          tail = trim(substr(tail, 1, RSTART - 1))
        }

        last_vote = trim(tail)

        if (identity == ent_id) {
          ent_last_vote = last_vote
          ent_active_stake = active_stake
        }
        if (identity == src_id) {
          src_active_stake = active_stake
        }
        if (identity == dst_id) {
          dst_active_stake = active_stake
        }
      }

      END {
        print ent_last_vote
        print ent_active_stake
        print src_active_stake
        print dst_active_stake
      }
    ' <<< "$out"
  )"

  WATCH_ENT_LAST_VOTE="$(sed -n '1p' <<< "$parsed")"
  WATCH_ENT_ACTIVE_STAKE="$(sed -n '2p' <<< "$parsed")"
  WATCH_SRC_ACTIVE_STAKE="$(sed -n '3p' <<< "$parsed")"
  WATCH_DST_ACTIVE_STAKE="$(sed -n '4p' <<< "$parsed")"

  [[ -z "${WATCH_ENT_LAST_VOTE// }" ]] && WATCH_ENT_LAST_VOTE="?"
  [[ -z "${WATCH_ENT_ACTIVE_STAKE// }" ]] && WATCH_ENT_ACTIVE_STAKE="?"
  [[ -z "${WATCH_SRC_ACTIVE_STAKE// }" ]] && WATCH_SRC_ACTIVE_STAKE="?"
  [[ -z "${WATCH_DST_ACTIVE_STAKE// }" ]] && WATCH_DST_ACTIVE_STAKE="?"
}

collect_single_catchup_marker() {
  local host_ip="$1"
  local host_port="$2"
  local probe_label="${3:-probe}"
  local output=""
  local marker="?"

  if ! command_exists ssh || [[ ! -r "$WATCH_SSH_KEY" ]]; then
    printf '?'
    return 0
  fi

  output="$(
    (
      timeout "$WATCH_CATCHUP_TIMEOUT_SEC" \
        ssh \
          -n \
          -o BatchMode=yes \
          -o ConnectTimeout=5 \
          -o IdentitiesOnly=yes \
          -o IdentityAgent=none \
          -o LogLevel=ERROR \
          -o UserKnownHostsFile=/dev/null \
          -o StrictHostKeyChecking=no \
          -i "$WATCH_SSH_KEY" \
          -p "$host_port" \
          "${WATCH_VALIDATOR_OPERATOR_USER}@${host_ip}" \
          "script -qefc \"/opt/solana/active_release/bin/solana -u '$SOLANA_RPC_URL' catchup --our-localhost 8899\" /dev/null" \
        2>&1 || true
    ) | tr '\r' '\n' | sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g'
  )"

  if grep -qiE 'caught up|0 slot\(s\) behind' <<< "$output"; then
    marker='C'
  elif grep -qiE '[1-9][0-9]* slot\(s\) behind|has not caught up|falling behind|gaining at|ETA:|behind at|behind \(us:|us:[0-9]+ them:[0-9]+' <<< "$output"; then
    marker='~'
  elif [[ -n "${output// }" ]]; then
    marker='!'
  else
    marker='?'
  fi

  if (( WATCH_DEBUG )) && [[ -n "$WATCH_DEBUG_RUN_DIR" ]]; then
    {
      printf 'timestamp=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      printf 'label=%s\n' "$probe_label"
      printf 'host=%s\n' "$host_ip"
      printf 'port=%s\n' "$host_port"
      printf 'marker=%s\n' "$marker"
      printf -- '--- raw output ---\n'
      printf '%s\n' "$output"
    } > "${WATCH_DEBUG_RUN_DIR}/${probe_label}.latest.log"

    {
      printf 'timestamp=%s label=%s host=%s port=%s marker=%s\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$probe_label" "$host_ip" "$host_port" "$marker"
      printf '%s\n' "$output"
      printf -- '---\n'
    } >> "${WATCH_DEBUG_RUN_DIR}/${probe_label}.history.log"
  fi

  printf '%s' "$marker"
}

collect_catchup_watch_metrics() {
  local temp_dir="" src_file="" dst_file=""
  local src_probe_pid="" dst_probe_pid=""

  temp_dir="$(mktemp -d 2>/dev/null || true)"
  if [[ -z "$temp_dir" || ! -d "$temp_dir" ]]; then
    if [[ "$WATCH_SRC_PID" == "?" ]]; then
      WATCH_SRC_CATCHUP="?"
    else
      WATCH_SRC_CATCHUP="$(collect_single_catchup_marker "$SOURCE_VM_IP" "$WATCH_SOURCE_SSH_PORT" "src")"
    fi

    if [[ "$WATCH_DST_PID" == "?" ]]; then
      WATCH_DST_CATCHUP="?"
    else
      WATCH_DST_CATCHUP="$(collect_single_catchup_marker "$DESTINATION_VM_IP" "$WATCH_DESTINATION_SSH_PORT" "dst")"
    fi
    return 0
  fi

  src_file="${temp_dir}/src.marker"
  dst_file="${temp_dir}/dst.marker"

  if [[ "$WATCH_SRC_PID" == "?" ]]; then
    WATCH_SRC_CATCHUP="?"
  else
    (
      collect_single_catchup_marker "$SOURCE_VM_IP" "$WATCH_SOURCE_SSH_PORT" "src" >"$src_file"
    ) &
    src_probe_pid=$!
  fi

  if [[ "$WATCH_DST_PID" == "?" ]]; then
    WATCH_DST_CATCHUP="?"
  else
    (
      collect_single_catchup_marker "$DESTINATION_VM_IP" "$WATCH_DESTINATION_SSH_PORT" "dst" >"$dst_file"
    ) &
    dst_probe_pid=$!
  fi

  if [[ -n "$src_probe_pid" ]]; then
    wait "$src_probe_pid" 2>/dev/null || true
    if [[ -r "$src_file" ]]; then
      WATCH_SRC_CATCHUP="$(<"$src_file")"
    else
      WATCH_SRC_CATCHUP="?"
    fi
  fi

  if [[ -n "$dst_probe_pid" ]]; then
    wait "$dst_probe_pid" 2>/dev/null || true
    if [[ -r "$dst_file" ]]; then
      WATCH_DST_CATCHUP="$(<"$dst_file")"
    else
      WATCH_DST_CATCHUP="?"
    fi
  fi

  rm -rf "$temp_dir"
}

collect_watch_metrics() {
  reset_watch_metrics
  WATCH_TS="$(date '+%H:%M:%S')"

  collect_qemu_watch_metrics
  collect_cpu_watch_metrics
  collect_ram_watch_metrics
  collect_disk_watch_metrics
  collect_epoch_watch_metrics
  collect_gossip_watch_metrics
  collect_validator_watch_metrics
  collect_catchup_watch_metrics
}

shorten_middle() {
  local value="${1:-}"
  local max_len="${2:-12}"

  if ((${#value} <= max_len)); then
    printf '%s' "$value"
    return 0
  fi

  if (( max_len <= 4 )); then
    printf '%s' "${value:0:max_len}"
    return 0
  fi

  local prefix_len=$(( (max_len - 2) / 2 ))
  local suffix_len=$(( max_len - 2 - prefix_len ))
  printf '%s..%s' "${value:0:prefix_len}" "${value: -suffix_len}"
}

shorten_address() {
  local value="${1:-?}"

  if [[ "$value" == "?" || ${#value} -le 11 ]]; then
    printf '%s' "$value"
    return 0
  fi

  printf '%s...%s' "${value:0:4}" "${value: -4}"
}

fit_cell() {
  local width="$1"
  local value="${2:-?}"
  printf "%-${width}.${width}s" "$value"
}

format_usage_cell() {
  local width="$1"
  local value="${2:-?}"
  local padded color pct

  padded="$(fit_cell "$width" "$value")"
  pct="${value%%%}"

  if (( CAN_COLOR )) && [[ "$pct" =~ ^[0-9]+$ ]]; then
    color="$(pressure_color "$pct")"
    printf '%s%s%s' "$color" "$padded" "$RESET"
  else
    printf '%s' "$padded"
  fi
}

compact_stake() {
  local value="${1:-?}"
  if [[ "$value" == "?" ]]; then
    printf '?'
    return 0
  fi

  value="${value/ SOL / }"
  value="${value// \(/(}"
  printf '%s' "$value"
}

rounded_stake() {
  local value="${1:-?}"
  if [[ "$value" == "?" ]]; then
    printf '?'
    return 0
  fi

  awk -v s="$value" '
    BEGIN {
      if (match(s, /^([0-9][0-9.,]*) SOL \(([^)]*)\)$/, a)) {
        pct = a[2]
        sub(/%$/, "", pct)
        printf "%.1f%%", pct + 0
      } else {
        printf "%s", s
      }
    }
  '
}

build_role_cell() {
  local pid="$1"
  local identity="$2"
  local version="$3"
  local stake="$4"
  local catchup_marker="${5:-}"

  if [[ -n "$catchup_marker" ]]; then
    printf '%s · %s · %s · %s · %s' \
      "${pid:-?}" \
      "${catchup_marker:-?}" \
      "${version:-?}" \
      "$(shorten_address "${identity:-?}")" \
      "$(rounded_stake "$stake")"
  else
    printf '%s · %s · %s · %s' \
      "${pid:-?}" \
      "$(shorten_address "${identity:-?}")" \
      "${version:-?}" \
      "$(rounded_stake "$stake")"
  fi
}

format_role_cell() {
  local width="$1"
  local pid="$2"
  local identity="$3"
  local version="$4"
  local stake="$5"
  local catchup_marker="${6:-}"
  local padded="" shortened_identity="" highlighted_identity="" marker_color="" highlighted_marker=""

  padded="$(fit_cell "$width" "$(build_role_cell "$pid" "$identity" "$version" "$stake" "$catchup_marker")")"

  if (( ! CAN_COLOR )); then
    printf '%s' "$padded"
    return 0
  fi

  if [[ "$identity" == "$PRIMARY_TARGET_IDENTITY" ]]; then
    shortened_identity="$(shorten_address "$identity")"
    highlighted_identity="${BOLD}${YELLOW}${shortened_identity}${RESET}"
    padded="${padded/"$shortened_identity"/"$highlighted_identity"}"
  fi

  if [[ -n "$catchup_marker" ]]; then
    case "$catchup_marker" in
      C) marker_color="${BOLD}${GREEN}" ;;
      '~') marker_color="${BOLD}${YELLOW}" ;;
      '!') marker_color="${BOLD}${RED}" ;;
      '?') marker_color="${DIM}" ;;
      *) marker_color="" ;;
    esac

    if [[ -n "$marker_color" ]]; then
      highlighted_marker="${marker_color}${catchup_marker}${RESET}"
      padded="${padded/ · $catchup_marker · / · $highlighted_marker · }"
    fi
  fi

  printf '%s' "$(gray_middle_dots "$padded")"
}

clear_watch_screen() {
  if (( CAN_COLOR )); then
    printf '\033[H\033[2J'
  fi
}

move_watch_cursor_to_rows() {
  if (( CAN_COLOR )); then
    printf '\033[3;1H'
  fi
}

format_catchup_legend() {
  local c_caught='C'
  local c_catching='~'
  local c_failed='!'
  local c_unknown='?'

  if (( CAN_COLOR )); then
    c_caught="${BOLD}${GREEN}C${RESET}"
    c_catching="${BOLD}${YELLOW}~${RESET}"
    c_failed="${BOLD}${RED}!${RESET}"
    c_unknown="${DIM}?${RESET}"
  fi

  printf 'Catchup marker: %s=caught up  %s=catching up  %s=probe failed  %s=unavailable' \
    "$c_caught" "$c_catching" "$c_failed" "$c_unknown"
}

initialize_watch_screen() {
  if (( CAN_COLOR )) && (( ! WATCH_SCREEN_INITIALIZED )); then
    clear_watch_screen
    printf 'Live updates every %ss. Newest sample last.\n' "$WATCH_INTERVAL"
    printf '%s\n' "$(format_catchup_legend)"
    WATCH_SCREEN_INITIALIZED=1
  fi
}

get_terminal_lines() {
  if command_exists tput && (( CAN_COLOR )); then
    tput lines 2>/dev/null && return 0
  fi
  printf '24\n'
}

build_watch_sample_block() {
  local line1
  local sample_width=0
  local role_width_ep=42
  local role_width_validator=45

  line1="$(
    printf ' %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s ' \
      "$(fit_cell 8 "$WATCH_TS")" \
      "$(format_usage_cell 4 "$WATCH_CPU_PCT")" \
      "$(format_usage_cell 4 "$WATCH_RAM_PCT")" \
      "$(format_usage_cell 5 "$WATCH_DISK_PCT")" \
      "$(fit_cell 3 "$WATCH_VM_COUNT")" \
      "$(fit_cell 6 "$WATCH_SLOT")" \
      "$(fit_cell 5 "$WATCH_EPOCH")" \
      "$(fit_cell 8 "$WATCH_EPOCH_PCT")" \
      "$(fit_cell 9 "$WATCH_GOSSIP_NODES")" \
      "$(format_role_cell "$role_width_ep" "$WATCH_ENT_PID" "$WATCH_ENT_IDENTITY" "$WATCH_ENT_VERSION" "$WATCH_ENT_ACTIVE_STAKE")" \
      "$(format_role_cell "$role_width_validator" "$WATCH_SRC_PID" "$WATCH_SRC_IDENTITY" "$WATCH_SRC_VERSION" "$WATCH_SRC_ACTIVE_STAKE" "$WATCH_SRC_CATCHUP")" \
      "$(format_role_cell "$role_width_validator" "$WATCH_DST_PID" "$WATCH_DST_IDENTITY" "$WATCH_DST_VERSION" "$WATCH_DST_ACTIVE_STAKE" "$WATCH_DST_CATCHUP")"
  )"

  sample_width="$(visible_length "$line1")"
  if (( sample_width > WATCH_TABLE_WIDTH )); then
    WATCH_TABLE_WIDTH="$sample_width"
  fi

  WATCH_SAMPLE_HISTORY+=("$line1")
}

render_watch_screen() {
  local term_lines top_lines header_lines row_lines available_lines max_samples total_samples start i
  local watch_header_plain watch_header watch_header_ip watch_width legend_line updates_line
  local role1_pos=0 role2_pos=0 role3_pos=0
  local role_width_ep=42
  local role_width_validator=45
  term_lines="$(get_terminal_lines)"
  [[ "$term_lines" =~ ^[0-9]+$ ]] || term_lines=24

  top_lines=2
  header_lines=3
  row_lines=1
  available_lines=$((term_lines - top_lines - header_lines))
  (( available_lines < row_lines )) && available_lines=$row_lines
  max_samples=$((available_lines / row_lines))
  (( max_samples < 1 )) && max_samples=1

  total_samples=${#WATCH_SAMPLE_HISTORY[@]}
  start=0
  if (( total_samples > max_samples )); then
    start=$((total_samples - max_samples))
  fi

  watch_header_plain="$(
    printf ' %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s ' \
      "$(fit_cell 8 "Time")" \
      "$(fit_cell 4 "CPU%")" \
      "$(fit_cell 4 "RAM%")" \
      "$(fit_cell 5 "Disk%")" \
      "$(fit_cell 3 "VMs")" \
      "$(fit_cell 6 "Slot")" \
      "$(fit_cell 5 "Epoch")" \
      "$(fit_cell 8 "Epoch%")" \
      "$(fit_cell 9 "In gossip")" \
      "$(fit_cell "$role_width_ep" "pid · id · ver · stake")" \
      "$(fit_cell "$role_width_validator" "pid · c · ver · id · stake")" \
      "$(fit_cell "$role_width_validator" "pid · c · ver · id · stake")"
  )"
  watch_header="$(gray_middle_dots "$watch_header_plain")"

  read -r role1_pos role2_pos role3_pos <<EOF
$(awk -v s="$watch_header_plain" '
  BEGIN {
    p1 = index(s, "pid · id · ver · stake");
    p2 = index(substr(s, p1 + 1), "pid · c · ver · id · stake");
    if (p2 > 0) {
      p2 += p1;
    }
    p3 = index(substr(s, p2 + 1), "pid · c · ver · id · stake");
    if (p3 > 0) {
      p3 += p2;
    }
    print p1, p2, p3;
  }
')
EOF

  watch_header_ip="$(printf '%*s' "$(visible_length "$watch_header_plain")" "")"
  watch_header_ip="${watch_header_ip:0:$((role1_pos - 1))}ep ${ENTRYPOINT_VM_IP}${watch_header_ip:$((role1_pos - 1 + ${#ENTRYPOINT_VM_IP} + 3))}"
  watch_header_ip="${watch_header_ip:0:$((role2_pos - 1))}src ${SOURCE_VM_IP}${watch_header_ip:$((role2_pos - 1 + ${#SOURCE_VM_IP} + 4))}"
  watch_header_ip="${watch_header_ip:0:$((role3_pos - 1))}dst ${DESTINATION_VM_IP}${watch_header_ip:$((role3_pos - 1 + ${#DESTINATION_VM_IP} + 4))}"
  watch_header_ip="$(blue_ip_in_header "$watch_header_ip" "$ENTRYPOINT_VM_IP")"
  watch_header_ip="$(blue_ip_in_header "$watch_header_ip" "$SOURCE_VM_IP")"
  watch_header_ip="$(blue_ip_in_header "$watch_header_ip" "$DESTINATION_VM_IP")"

  updates_line="Live updates every ${WATCH_INTERVAL}s. Newest sample last."
  legend_line="$(format_catchup_legend)"
  watch_width="$(visible_length "$watch_header")"
  if (( $(visible_length "$watch_header_ip") > watch_width )); then
    watch_width="$(visible_length "$watch_header_ip")"
  fi
  if (( WATCH_TABLE_WIDTH > watch_width )); then
    watch_width="$WATCH_TABLE_WIDTH"
  fi
  if (( $(visible_length "$updates_line") > watch_width )); then
    watch_width="$(visible_length "$updates_line")"
  fi
  if (( $(visible_length "$legend_line") > watch_width )); then
    watch_width="$(visible_length "$legend_line")"
  fi

  if (( CAN_COLOR )); then
    initialize_watch_screen
    move_watch_cursor_to_rows
    printf '\033[J'
  else
    clear_watch_screen
    printf '%s\n' "$updates_line"
    printf '%s\n' "$legend_line"
  fi

  for ((i = start; i < total_samples; i++)); do
    if [[ "${WATCH_SAMPLE_HISTORY[i]}" == "$WATCH_TESTCASE_BOUNDARY_MARKER" ]]; then
      watch_line "$watch_width"
    else
      printf '%s\n' "${WATCH_SAMPLE_HISTORY[i]}"
    fi
  done

  watch_line "$watch_width"
  printf '%b%s%b\n' "$BOLD" \
    "$watch_header" \
    "$RESET"
  printf '%s\n' "$watch_header_ip"
}

print_watch_sample() {
  collect_watch_metrics
  if [[ -n "$WATCH_PREV_ENT_PID" && -n "$WATCH_ENT_PID" && "$WATCH_PREV_ENT_PID" != "?" && "$WATCH_ENT_PID" != "?" && "$WATCH_PREV_ENT_PID" != "$WATCH_ENT_PID" ]]; then
    WATCH_SAMPLE_HISTORY+=("$WATCH_TESTCASE_BOUNDARY_MARKER")
  fi
  build_watch_sample_block
  if [[ -n "$WATCH_ENT_PID" ]]; then
    WATCH_PREV_ENT_PID="$WATCH_ENT_PID"
  fi
  render_watch_screen
}

watch_loop() {
  WATCH_SAMPLE_HISTORY=()
  WATCH_SCREEN_INITIALIZED=0
  WATCH_PREV_ENT_PID=""

  while true; do
    print_watch_sample
    sleep "$WATCH_INTERVAL"
  done
}

run_once() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S %Z')"

  echo
  line
  subtle "New run: $ts"
  line

  header "Hayek Validator VM / Solana Status Report"
  subtle "Generated at: $ts"

  if (( WATCH_ENABLED )); then
    subtle "Watch interval: ${WATCH_INTERVAL}s (Ctrl+C to stop)"
  else
    subtle "Watch mode: off"
  fi

  print_resource_pressure
  print_qemu_processes
  print_solana_epoch_info
  print_solana_gossip
  print_solana_validators

  echo
  ok "Done."
}

main() {
  local latest_inventory=""

  parse_args "$@"
  if (( WATCH_DEBUG )); then
    WATCH_DEBUG_RUN_DIR="${WATCH_DEBUG_ROOT}/latest"
    mkdir -p "$WATCH_DEBUG_RUN_DIR"
    rm -f "${WATCH_DEBUG_RUN_DIR}/src.latest.log" \
      "${WATCH_DEBUG_RUN_DIR}/src.history.log" \
      "${WATCH_DEBUG_RUN_DIR}/dst.latest.log" \
      "${WATCH_DEBUG_RUN_DIR}/dst.history.log"
  fi
  latest_inventory="$(discover_latest_operator_inventory)"
  load_watch_ssh_targets_from_inventory "$latest_inventory"

  if (( WATCH_ENABLED )); then
    trap 'echo; warn "Stopped."; exit 0' INT TERM
    run_once
    watch_loop
  else
    run_once
  fi
}

main "$@"

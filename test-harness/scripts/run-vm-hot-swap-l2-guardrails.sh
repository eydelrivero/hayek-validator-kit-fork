#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work/vm-hot-swap-l2}"
RUN_ID_PREFIX="${RUN_ID_PREFIX:-vm-hot-swap-l2}"
VM_ARCH="${VM_ARCH:-}"
VM_BASE_IMAGE="${VM_BASE_IMAGE:-}"
VM_DISK_SYSTEM_GB="${VM_DISK_SYSTEM_GB:-40}"
VM_DISK_LEDGER_GB="${VM_DISK_LEDGER_GB:-20}"
VM_DISK_ACCOUNTS_GB="${VM_DISK_ACCOUNTS_GB:-10}"
VM_DISK_SNAPSHOTS_GB="${VM_DISK_SNAPSHOTS_GB:-0}"
SOURCE_FLAVOR="${SOURCE_FLAVOR:-agave}"
DESTINATION_FLAVOR="${DESTINATION_FLAVOR:-jito-bam}"
ONLY_CASE="${ONLY_CASE:-}"
CONTINUE_ON_ERROR=true
RETAIN_ON_FAILURE=false
RETAIN_ALWAYS=false
PRUNE_OLD_RUNS="${PRUNE_OLD_RUNS:-true}"
PRUNE_KEEP_RUNS="${PRUNE_KEEP_RUNS:-6}"
PRUNE_MIN_FREE_GB="${PRUNE_MIN_FREE_GB:-40}"
PRUNE_MUTABLE_CACHE_DIRS="${PRUNE_MUTABLE_CACHE_DIRS:-auto}"
KILL_STALE_QEMU="${KILL_STALE_QEMU:-true}"
REUSE_PREPARED_VMS="${REUSE_PREPARED_VMS:-true}"
REFRESH_PREPARED_VMS=false
PREPARED_CACHE_KEY_OVERRIDE="${PREPARED_CACHE_KEY_OVERRIDE:-}"
IMMUTABLE_VM_CACHE_ROOT="${IMMUTABLE_VM_CACHE_ROOT:-$REPO_ROOT/test-harness/work/_vm-immutable-cache}"
ENTRYPOINT_CLI_IMMUTABLE_CACHE_ROOT="${ENTRYPOINT_CLI_IMMUTABLE_CACHE_ROOT:-$IMMUTABLE_VM_CACHE_ROOT/entrypoint-vm-cli}"
ALLOW_FALLBACK_PREPARED_CACHE="${ALLOW_FALLBACK_PREPARED_CACHE:-false}"
PROGRESS_INTERVAL_SEC="${PROGRESS_INTERVAL_SEC:-30}"
AUTO_REFRESH_ON_PREINJECTION_WARMUP_FAILURE="${AUTO_REFRESH_ON_PREINJECTION_WARMUP_FAILURE:-true}"
INSPECT_ON_INSTABILITY="${INSPECT_ON_INSTABILITY:-false}"
INSPECT_WAIT_SEC="${INSPECT_WAIT_SEC:-0}"

VM_NETWORK_MODE="${VM_NETWORK_MODE:-shared-bridge}"
VM_LOCALNET_ENTRYPOINT_MODE="${VM_LOCALNET_ENTRYPOINT_MODE:-vm}"
VM_SOURCE_BRIDGE_IP="${VM_SOURCE_BRIDGE_IP:-192.168.100.11}"
VM_DESTINATION_BRIDGE_IP="${VM_DESTINATION_BRIDGE_IP:-192.168.100.12}"
ENTRYPOINT_VM_BRIDGE_IP="${ENTRYPOINT_VM_BRIDGE_IP:-192.168.100.13}"
VM_BRIDGE_GATEWAY_IP="${VM_BRIDGE_GATEWAY_IP:-192.168.100.1}"
VM_SOURCE_TAP_IFACE="${VM_SOURCE_TAP_IFACE:-tap-hvk-src}"
VM_DESTINATION_TAP_IFACE="${VM_DESTINATION_TAP_IFACE:-tap-hvk-dst}"
ENTRYPOINT_VM_TAP_IFACE="${ENTRYPOINT_VM_TAP_IFACE:-tap-hvk-ent}"
ENTRYPOINT_VM_SKIP_CLI_INSTALL="${ENTRYPOINT_VM_SKIP_CLI_INSTALL:-auto}"
SHARED_ENTRYPOINT_VM="${SHARED_ENTRYPOINT_VM:-false}"
PRE_SWAP_CATCHUP_TIMEOUT_SEC="${PRE_SWAP_CATCHUP_TIMEOUT_SEC:-900}"
PRE_SWAP_TOWER_TIMEOUT_SEC="${PRE_SWAP_TOWER_TIMEOUT_SEC:-120}"
REUSE_RUNTIME_READY_TIMEOUT_SEC="${REUSE_RUNTIME_READY_TIMEOUT_SEC:-300}"
AGAVE_VERSION="${AGAVE_VERSION:-3.1.10}"
BAM_JITO_VERSION="${BAM_JITO_VERSION:-3.1.10}"
BUILD_FROM_SOURCE="${BUILD_FROM_SOURCE:-false}"
CITY_GROUP="${CITY_GROUP:-city_dal}"
ENTRYPOINT_CLI_CACHE_PREFIX=""

usage() {
  cat <<'EOF'
Usage:
  run-vm-hot-swap-l2-guardrails.sh [options]

Options:
  --workdir <path>                 (default: ./test-harness/work/vm-hot-swap-l2)
  --run-id-prefix <id>             (default: vm-hot-swap-l2)
  --vm-arch <amd64|arm64>
  --vm-base-image <path>
  --source-flavor <flavor>         (default: agave)
  --destination-flavor <flavor>    (default: jito-bam)
  --only-case <name>               Run a single case by name
  --continue-on-error              (default: true)
  --stop-on-error
  --retain-on-failure
  --retain-always
  --no-prune
  --prune-keep-runs <n>            (default: 6)
  --prune-min-free-gb <n>          (default: 40)
  --prune-mutable-caches           Remove mutable legacy caches (_shared-entrypoint-vm, _prepared-vms) before runs
  --no-prune-mutable-caches        Keep mutable legacy caches
  --no-kill-stale-qemu
  --shared-entrypoint              Reuse a single mutable entrypoint VM across cases (opt-in)
  --no-shared-entrypoint
  --no-vm-reuse
  --refresh-vm-reuse
  --no-auto-refresh-on-warmup-failure
  --inspect-on-instability          Pause before auto-refresh on recoverable instability
  --inspect-wait-sec <n>            Non-interactive pause duration before auto-refresh (default: 0)
  --prepared-cache-key <text>      Override prepared VM cache key namespace
EOF
}

while (($# > 0)); do
  case "$1" in
    --workdir)
      WORKDIR="${2:-}"
      shift 2
      ;;
    --run-id-prefix)
      RUN_ID_PREFIX="${2:-}"
      shift 2
      ;;
    --vm-arch)
      VM_ARCH="${2:-}"
      shift 2
      ;;
    --vm-base-image)
      VM_BASE_IMAGE="${2:-}"
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
    --only-case)
      ONLY_CASE="${2:-}"
      shift 2
      ;;
    --continue-on-error)
      CONTINUE_ON_ERROR=true
      shift
      ;;
    --stop-on-error)
      CONTINUE_ON_ERROR=false
      shift
      ;;
    --retain-on-failure)
      RETAIN_ON_FAILURE=true
      shift
      ;;
    --retain-always)
      RETAIN_ALWAYS=true
      shift
      ;;
    --no-prune)
      PRUNE_OLD_RUNS=false
      shift
      ;;
    --prune-keep-runs)
      PRUNE_KEEP_RUNS="${2:-}"
      shift 2
      ;;
    --prune-min-free-gb)
      PRUNE_MIN_FREE_GB="${2:-}"
      shift 2
      ;;
    --prune-mutable-caches)
      PRUNE_MUTABLE_CACHE_DIRS=true
      shift
      ;;
    --no-prune-mutable-caches)
      PRUNE_MUTABLE_CACHE_DIRS=false
      shift
      ;;
    --no-kill-stale-qemu)
      KILL_STALE_QEMU=false
      shift
      ;;
    --shared-entrypoint)
      SHARED_ENTRYPOINT_VM=true
      shift
      ;;
    --no-shared-entrypoint)
      SHARED_ENTRYPOINT_VM=false
      shift
      ;;
    --no-vm-reuse)
      REUSE_PREPARED_VMS=false
      shift
      ;;
    --refresh-vm-reuse)
      REFRESH_PREPARED_VMS=true
      shift
      ;;
    --no-auto-refresh-on-warmup-failure)
      AUTO_REFRESH_ON_PREINJECTION_WARMUP_FAILURE=false
      shift
      ;;
    --inspect-on-instability)
      INSPECT_ON_INSTABILITY=true
      shift
      ;;
    --inspect-wait-sec)
      INSPECT_WAIT_SEC="${2:-}"
      shift 2
      ;;
    --prepared-cache-key)
      PREPARED_CACHE_KEY_OVERRIDE="${2:-}"
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

if [[ ! "$INSPECT_WAIT_SEC" =~ ^[0-9]+$ ]]; then
  echo "Invalid --inspect-wait-sec value: $INSPECT_WAIT_SEC (must be a non-negative integer)" >&2
  exit 2
fi

format_duration() {
  local total="${1:-0}"
  local d h m s
  local out=""

  if [[ ! "$total" =~ ^[0-9]+$ ]]; then
    printf '%ss' "$total"
    return
  fi

  d=$((total / 86400))
  h=$(((total % 86400) / 3600))
  m=$(((total % 3600) / 60))
  s=$((total % 60))

  if ((d > 0)); then out+="${d}d"; fi
  if ((h > 0)); then out+="${h}h"; fi
  if ((m > 0)); then out+="${m}m"; fi
  if ((s > 0 || ${#out} == 0)); then out+="${s}s"; fi

  printf '%s' "$out"
}

format_duration_aligned() {
  local human
  human="$(format_duration "$1")"
  printf '%-8s' "$human"
}

resolve_default_vm_config() {
  if [[ -z "$VM_ARCH" ]]; then
    case "$(uname -m)" in
      arm64|aarch64) VM_ARCH="arm64" ;;
      *) VM_ARCH="amd64" ;;
    esac
  fi

  if [[ -z "$VM_BASE_IMAGE" ]]; then
    VM_BASE_IMAGE="$REPO_ROOT/scripts/vm-test/work/ubuntu-${VM_ARCH}.img"
  fi
}

resolve_shared_entrypoint_source_prefix() {
  local build_workdir="$1"
  local candidate

  candidate="$build_workdir/_shared-entrypoint-vm/vm/hvk-entry-shared-${VM_ARCH}"
  if [[ -r "${candidate}.qcow2" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$(
    find "$build_workdir/_shared-entrypoint-vm/vm" -maxdepth 1 -type f \
      -name 'hvk-entry-shared-*.qcow2' \
      ! -name '*-ledger.qcow2' \
      ! -name '*-accounts.qcow2' \
      ! -name '*-snapshots.qcow2' \
      | LC_ALL=C sort \
      | head -n 1
  )"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "${candidate%.qcow2}"
    return 0
  fi

  printf '\n'
}

is_verify_run_alive() {
  local pid="$1"
  local run_id="$2"
  local args
  args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
  [[ -n "$args" ]] || return 1
  [[ "$args" == *"verify-vm-hot-swap.sh"* ]] || return 1
  [[ "$args" == *"--run-id ${run_id}"* ]] || return 1
}

effective_entrypoint_skip_cli_install() {
  local requested="$ENTRYPOINT_VM_SKIP_CLI_INSTALL"
  if [[ "$requested" == "auto" \
    && "$VM_LOCALNET_ENTRYPOINT_MODE" == "vm" \
    && -n "$ENTRYPOINT_CLI_CACHE_PREFIX" ]]; then
    printf 'true\n'
    return 0
  fi
  printf '%s\n' "$requested"
}

inspection_action_on_recoverable_failure() {
  local case_name="$1"
  local reason="$2"
  local run_id="$3"
  local case_dir="$4"
  local log_file="$5"
  local action="refresh"
  local answer=""
  local source_ssh_cmd=""
  local destination_ssh_cmd=""
  local entrypoint_ssh_cmd=""

  if [[ "$INSPECT_ON_INSTABILITY" != "true" ]]; then
    printf '%s\n' "$action"
    return 0
  fi

  source_ssh_cmd="ssh -p 2522 bob@${VM_SOURCE_BRIDGE_IP}"
  destination_ssh_cmd="ssh -p 2522 bob@${VM_DESTINATION_BRIDGE_IP}"
  entrypoint_ssh_cmd="ssh -p 2522 bob@${ENTRYPOINT_VM_BRIDGE_IP}"

  echo "    [L2] ${case_name}: recoverable instability detected; pausing before auto-refresh." >&2
  echo "    [L2] reason: ${reason}" >&2
  echo "    [L2] run_id: ${run_id}" >&2
  echo "    [L2] case dir: ${case_dir}" >&2
  echo "    [L2] runner log: ${log_file}" >&2
  echo "    [L2] source ssh: ${source_ssh_cmd}" >&2
  echo "    [L2] destination ssh: ${destination_ssh_cmd}" >&2
  echo "    [L2] entrypoint ssh: ${entrypoint_ssh_cmd}" >&2
  echo "    [L2] note: inspect mode forces --retain-on-failure so failed-attempt VMs stay up for SSH/debug." >&2

  if [[ -t 0 ]]; then
    while true; do
      read -r -p "    [L2] Press Enter to auto-refresh+retry, or type 'stop' to stop here: " answer
      case "$answer" in
        ""|retry|refresh)
          action="refresh"
          break
          ;;
        stop|quit|q)
          action="stop"
          break
          ;;
        *)
          echo "    [L2] Invalid input. Use Enter to retry, or 'stop' to stop." >&2
          ;;
      esac
    done
  elif ((INSPECT_WAIT_SEC > 0)); then
    echo "    [L2] non-interactive session; sleeping ${INSPECT_WAIT_SEC}s before auto-refresh..." >&2
    sleep "$INSPECT_WAIT_SEC"
  else
    echo "    [L2] non-interactive session and inspect wait is 0; auto-refreshing immediately." >&2
  fi

  printf '%s\n' "$action"
}

kill_qemu_using_tap_iface() {
  local tap_iface="$1"
  local pids
  local pid

  if [[ -z "$tap_iface" ]]; then
    return 0
  fi

  pids="$(pgrep -f "qemu-system-.*ifname=${tap_iface}" || true)"
  if [[ -z "$pids" ]]; then
    return 0
  fi

  for pid in $pids; do
    kill "$pid" >/dev/null 2>&1 || true
    sleep 1
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  done
}

build_entrypoint_cache_key() {
  local verifier_hash
  local disk_sizes

  verifier_hash="$(
    sha256sum "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh" \
      | awk '{print substr($1, 1, 16)}'
  )"
  disk_sizes="${VM_DISK_SYSTEM_GB}|${VM_DISK_LEDGER_GB}|${VM_DISK_ACCOUNTS_GB}|${VM_DISK_SNAPSHOTS_GB}"
  printf '%s' "${VM_ARCH}|${VM_BASE_IMAGE}|${AGAVE_VERSION}|${BUILD_FROM_SOURCE}|${disk_sizes}|${verifier_hash}" \
    | sha256sum | awk '{print substr($1, 1, 16)}'
}

snapshots_disk_enabled() {
  [[ "${VM_DISK_SNAPSHOTS_GB:-0}" =~ ^[0-9]+$ ]] || return 1
  (( VM_DISK_SNAPSHOTS_GB > 0 ))
}

entrypoint_cli_cache_ready() {
  local cache_root="$1"
  local expected_key="${2:-}"
  local vm_dir="$cache_root/vm"
  local key_file="$cache_root/.cli-cache-key"

  [[ -f "$cache_root/.cli-cache-ready" ]] || return 1
  if [[ -n "$expected_key" ]]; then
    [[ -r "$key_file" ]] || return 1
    [[ "$(cat "$key_file" 2>/dev/null)" == "$expected_key" ]] || return 1
  fi
  ls "$vm_dir"/hvk-entry-shared-*.qcow2 >/dev/null 2>&1 || return 1
  ls "$vm_dir"/hvk-entry-shared-*-ledger.qcow2 >/dev/null 2>&1 || return 1
  ls "$vm_dir"/hvk-entry-shared-*-accounts.qcow2 >/dev/null 2>&1 || return 1
  if snapshots_disk_enabled; then
    ls "$vm_dir"/hvk-entry-shared-*-snapshots.qcow2 >/dev/null 2>&1 || return 1
  fi
}

ensure_shared_entrypoint_cli_cache() {
  local cache_root="$WORKDIR/_shared-entrypoint-vm"
  local cache_key
  local run_id
  local log_file
  local args=()
  local rc=0
  local start_ts
  local elapsed_now
  local elapsed_aligned
  local progress_line
  local pid

  if [[ "$SHARED_ENTRYPOINT_VM" != "true" || "$VM_LOCALNET_ENTRYPOINT_MODE" != "vm" ]]; then
    return 0
  fi

  cache_key="$(build_entrypoint_cache_key)"
  if [[ "$REFRESH_PREPARED_VMS" != "true" ]] && entrypoint_cli_cache_ready "$cache_root" "$cache_key"; then
    echo "==> [L2] Reusing shared entrypoint CLI cache: $cache_root" >&2
    return 0
  fi

  if [[ "$KILL_STALE_QEMU" == true ]]; then
    kill_qemu_using_tap_iface "$ENTRYPOINT_VM_TAP_IFACE"
  fi

  rm -rf "$cache_root"
  mkdir -p "$WORKDIR/logs"

  run_id="${RUN_ID_PREFIX}-prepare-entrypoint-$(date +%Y%m%d-%H%M%S)"
  log_file="$WORKDIR/logs/${run_id}.log"

  args=(
    "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh"
    --run-id "$run_id"
    --workdir "$WORKDIR"
    --source-flavor "$SOURCE_FLAVOR"
    --destination-flavor "$DESTINATION_FLAVOR"
  )
  if [[ -n "$VM_ARCH" ]]; then args+=(--vm-arch "$VM_ARCH"); fi
  if [[ -n "$VM_BASE_IMAGE" ]]; then args+=(--vm-base-image "$VM_BASE_IMAGE"); fi

  echo "==> [L2] Preparing shared entrypoint VM cache (CLI only)..." >&2
  start_ts="$(date +%s)"
  set +e
  env \
    VM_NETWORK_MODE="$VM_NETWORK_MODE" \
    VM_LOCALNET_ENTRYPOINT_MODE="$VM_LOCALNET_ENTRYPOINT_MODE" \
    VM_SOURCE_BRIDGE_IP="$VM_SOURCE_BRIDGE_IP" \
    VM_DESTINATION_BRIDGE_IP="$VM_DESTINATION_BRIDGE_IP" \
    ENTRYPOINT_VM_BRIDGE_IP="$ENTRYPOINT_VM_BRIDGE_IP" \
    VM_BRIDGE_GATEWAY_IP="$VM_BRIDGE_GATEWAY_IP" \
    VM_SOURCE_TAP_IFACE="$VM_SOURCE_TAP_IFACE" \
    VM_DESTINATION_TAP_IFACE="$VM_DESTINATION_TAP_IFACE" \
    ENTRYPOINT_VM_TAP_IFACE="$ENTRYPOINT_VM_TAP_IFACE" \
    ENTRYPOINT_VM_SKIP_CLI_INSTALL="false" \
    SHARED_ENTRYPOINT_VM="true" \
    AGAVE_VERSION="$AGAVE_VERSION" \
    BUILD_FROM_SOURCE="$BUILD_FROM_SOURCE" \
    CITY_GROUP="$CITY_GROUP" \
    VM_ENTRYPOINT_PREPARE_ONLY="true" \
    PRE_SWAP_INJECTION_MODE="none" \
    "${args[@]}" >"$log_file" 2>&1 &
  pid=$!

  while is_verify_run_alive "$pid" "$run_id"; do
    sleep "$PROGRESS_INTERVAL_SEC"
    if ! is_verify_run_alive "$pid" "$run_id"; then
      break
    fi
    elapsed_now=$(( $(date +%s) - start_ts ))
    elapsed_aligned="$(format_duration_aligned "$elapsed_now")"
    progress_line="$(
      tail -n 80 "$log_file" 2>/dev/null \
        | awk '/^\[vm-hot-swap\]/ {line=$0} END {print line}' \
        || true
    )"
    if [[ -z "$progress_line" ]]; then
      progress_line="$(tail -n 1 "$log_file" 2>/dev/null || true)"
    fi
    echo "    [L2] entrypoint-cache elapsed=${elapsed_aligned} ${progress_line}" >&2
  done

  wait "$pid"
  rc=$?
  set -e
  if (( rc != 0 )) || ! entrypoint_cli_cache_ready "$cache_root"; then
    echo "FAIL: L2 shared entrypoint cache prepare failed (log: $log_file)" >&2
    return 1
  fi

  printf '%s\n' "$cache_key" >"$cache_root/.cli-cache-key"
  touch "$cache_root/.cli-cache-ready"
  rm -rf "$WORKDIR/$run_id"
  echo "==> [L2] Shared entrypoint CLI cache ready: $cache_root ($(format_duration "$(( $(date +%s) - start_ts ))"))" >&2
}

entrypoint_immutable_cache_ready() {
  local cache_dir="$1"
  local expected_key="${2:-}"
  local key_file="$cache_dir/.cache-key"

  [[ -f "$cache_dir/.ready" ]] || return 1
  if [[ -n "$expected_key" ]]; then
    [[ -r "$key_file" ]] || return 1
    [[ "$(cat "$key_file" 2>/dev/null)" == "$expected_key" ]] || return 1
  fi
  [[ -r "$cache_dir/entrypoint.qcow2" ]] || return 1
  [[ -r "$cache_dir/entrypoint-ledger.qcow2" ]] || return 1
  [[ -r "$cache_dir/entrypoint-accounts.qcow2" ]] || return 1
  if snapshots_disk_enabled; then
    [[ -r "$cache_dir/entrypoint-snapshots.qcow2" ]] || return 1
  fi
}

ensure_stateless_entrypoint_cli_cache() {
  local cache_key
  local cache_dir
  local cache_prefix
  local build_workdir
  local run_id
  local log_file
  local source_prefix
  local args=()
  local rc=0
  local start_ts
  local elapsed_now
  local elapsed_aligned
  local progress_line
  local pid

  ENTRYPOINT_CLI_CACHE_PREFIX=""

  if [[ "$VM_LOCALNET_ENTRYPOINT_MODE" != "vm" ]]; then
    return 0
  fi

  cache_key="$(build_entrypoint_cache_key)"
  cache_dir="$ENTRYPOINT_CLI_IMMUTABLE_CACHE_ROOT/${VM_ARCH:-auto}-${cache_key}"
  cache_prefix="$cache_dir/entrypoint"
  ENTRYPOINT_CLI_CACHE_PREFIX="$cache_prefix"

  if [[ "$REFRESH_PREPARED_VMS" != "true" ]] && entrypoint_immutable_cache_ready "$cache_dir" "$cache_key"; then
    echo "==> [L2] Reusing immutable entrypoint CLI cache: $cache_dir" >&2
    return 0
  fi

  rm -rf "$cache_dir"
  mkdir -p "$cache_dir" "$WORKDIR/logs"
  build_workdir="$WORKDIR/_entrypoint-cli-cache-build"
  rm -rf "$build_workdir"
  mkdir -p "$build_workdir"

  if [[ "$KILL_STALE_QEMU" == true ]]; then
    kill_qemu_using_tap_iface "$ENTRYPOINT_VM_TAP_IFACE"
  fi

  run_id="${RUN_ID_PREFIX}-prepare-entrypoint-cli-$(date +%Y%m%d-%H%M%S)"
  log_file="$WORKDIR/logs/${run_id}.log"
  args=(
    "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh"
    --run-id "$run_id"
    --workdir "$build_workdir"
    --source-flavor "$SOURCE_FLAVOR"
    --destination-flavor "$DESTINATION_FLAVOR"
  )
  if [[ -n "$VM_ARCH" ]]; then args+=(--vm-arch "$VM_ARCH"); fi
  if [[ -n "$VM_BASE_IMAGE" ]]; then args+=(--vm-base-image "$VM_BASE_IMAGE"); fi

  echo "==> [L2] Preparing immutable entrypoint CLI cache (stateless)..." >&2
  start_ts="$(date +%s)"
  set +e
  env \
    VM_NETWORK_MODE="$VM_NETWORK_MODE" \
    VM_LOCALNET_ENTRYPOINT_MODE="$VM_LOCALNET_ENTRYPOINT_MODE" \
    VM_SOURCE_BRIDGE_IP="$VM_SOURCE_BRIDGE_IP" \
    VM_DESTINATION_BRIDGE_IP="$VM_DESTINATION_BRIDGE_IP" \
    ENTRYPOINT_VM_BRIDGE_IP="$ENTRYPOINT_VM_BRIDGE_IP" \
    VM_BRIDGE_GATEWAY_IP="$VM_BRIDGE_GATEWAY_IP" \
    VM_SOURCE_TAP_IFACE="$VM_SOURCE_TAP_IFACE" \
    VM_DESTINATION_TAP_IFACE="$VM_DESTINATION_TAP_IFACE" \
    ENTRYPOINT_VM_TAP_IFACE="$ENTRYPOINT_VM_TAP_IFACE" \
    ENTRYPOINT_VM_SKIP_CLI_INSTALL="false" \
    SHARED_ENTRYPOINT_VM="true" \
    AGAVE_VERSION="$AGAVE_VERSION" \
    BUILD_FROM_SOURCE="$BUILD_FROM_SOURCE" \
    CITY_GROUP="$CITY_GROUP" \
    VM_ENTRYPOINT_PREPARE_ONLY="true" \
    PRE_SWAP_INJECTION_MODE="none" \
    "${args[@]}" >"$log_file" 2>&1 &
  pid=$!

  while is_verify_run_alive "$pid" "$run_id"; do
    sleep "$PROGRESS_INTERVAL_SEC"
    if ! is_verify_run_alive "$pid" "$run_id"; then
      break
    fi
    elapsed_now=$(( $(date +%s) - start_ts ))
    elapsed_aligned="$(format_duration_aligned "$elapsed_now")"
    progress_line="$(
      tail -n 80 "$log_file" 2>/dev/null \
        | awk '/^\[vm-hot-swap\]/ {line=$0} END {print line}' \
        || true
    )"
    if [[ -z "$progress_line" ]]; then
      progress_line="$(tail -n 1 "$log_file" 2>/dev/null || true)"
    fi
    echo "    [L2] entrypoint-immutable-cache elapsed=${elapsed_aligned} ${progress_line}" >&2
  done

  wait "$pid"
  rc=$?
  set -e
  if (( rc != 0 )); then
    echo "FAIL: L2 immutable entrypoint cache prepare failed (log: $log_file)" >&2
    return 1
  fi

  source_prefix="$(resolve_shared_entrypoint_source_prefix "$build_workdir")"
  if [[ -z "$source_prefix" ]]; then
    echo "FAIL: L2 immutable entrypoint cache source prefix not found under $build_workdir/_shared-entrypoint-vm/vm" >&2
    return 1
  fi
  for suffix in ".qcow2" "-ledger.qcow2" "-accounts.qcow2"; do
    if [[ ! -r "${source_prefix}${suffix}" ]]; then
      echo "FAIL: L2 immutable entrypoint cache source disk missing: ${source_prefix}${suffix}" >&2
      return 1
    fi
  done
  if snapshots_disk_enabled && [[ ! -r "${source_prefix}-snapshots.qcow2" ]]; then
    echo "FAIL: L2 immutable entrypoint cache source disk missing: ${source_prefix}-snapshots.qcow2" >&2
    return 1
  fi

  cp --reflink=auto -f "${source_prefix}.qcow2" "${cache_prefix}.qcow2"
  cp --reflink=auto -f "${source_prefix}-ledger.qcow2" "${cache_prefix}-ledger.qcow2"
  cp --reflink=auto -f "${source_prefix}-accounts.qcow2" "${cache_prefix}-accounts.qcow2"
  if snapshots_disk_enabled; then
    cp --reflink=auto -f "${source_prefix}-snapshots.qcow2" "${cache_prefix}-snapshots.qcow2"
  fi
  printf '%s\n' "$cache_key" >"$cache_dir/.cache-key"
  touch "$cache_dir/.ready"
  rm -rf "$build_workdir"

  echo "==> [L2] Immutable entrypoint CLI cache ready: $cache_dir ($(format_duration "$(( $(date +%s) - start_ts ))"))" >&2
}

build_prepared_cache_key() {
  local raw
  local verifier_hash
  local disk_sizes

  disk_sizes="${VM_DISK_SYSTEM_GB}|${VM_DISK_LEDGER_GB}|${VM_DISK_ACCOUNTS_GB}|${VM_DISK_SNAPSHOTS_GB}"
  if [[ -n "$PREPARED_CACHE_KEY_OVERRIDE" ]]; then
    raw="$PREPARED_CACHE_KEY_OVERRIDE|$disk_sizes"
  else
    verifier_hash="$(
      sha256sum "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh" \
        | awk '{print substr($1, 1, 16)}'
    )"
    raw="$VM_ARCH|$VM_BASE_IMAGE|$SOURCE_FLAVOR|$DESTINATION_FLAVOR|$AGAVE_VERSION|$BAM_JITO_VERSION|$BUILD_FROM_SOURCE|$CITY_GROUP|$VM_NETWORK_MODE|$disk_sizes|$verifier_hash"
  fi
  printf '%s' "$raw" | sha256sum | awk '{print substr($1, 1, 16)}'
}

prepared_cache_ready() {
  local dir="$1"
  [[ -f "$dir/.ready" ]] || return 1
  [[ -r "$dir/source.qcow2" ]] || return 1
  [[ -r "$dir/source-ledger.qcow2" ]] || return 1
  [[ -r "$dir/source-accounts.qcow2" ]] || return 1
  [[ -r "$dir/destination.qcow2" ]] || return 1
  [[ -r "$dir/destination-ledger.qcow2" ]] || return 1
  [[ -r "$dir/destination-accounts.qcow2" ]] || return 1
  if snapshots_disk_enabled; then
    [[ -r "$dir/source-snapshots.qcow2" ]] || return 1
    [[ -r "$dir/destination-snapshots.qcow2" ]] || return 1
  fi
}

find_fallback_prepared_cache_dir() {
  local prefix="$1"
  local dir
  for dir in $(ls -1dt "${prefix}"* 2>/dev/null || true); do
    if prepared_cache_ready "$dir"; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
  return 1
}

ensure_prepared_vm_cache() {
  local prepared_dir="$1"
  local prepare_run_id
  local prepare_log_file
  local prepare_case_dir
  local prepare_args=()
  local prepare_start_ts
  local prepare_elapsed_now
  local prepare_elapsed_human
  local prepare_elapsed_aligned
  local prepare_progress_line
  local prepare_pid
  local prepare_elapsed_sec
  local stale_pattern
  local retry_depth="${PREPARE_CACHE_RETRY_DEPTH:-0}"
  local retry_rc=0
  local rc=0
  local resolved_entrypoint_skip_cli_install

  if [[ "$REUSE_PREPARED_VMS" != "true" ]]; then
    return 0
  fi

  if [[ "$REFRESH_PREPARED_VMS" != "true" ]] && prepared_cache_ready "$prepared_dir"; then
    echo "==> [L2] Reusing prepared source/destination cache: $prepared_dir" >&2
    return 0
  fi

  rm -rf "$prepared_dir"
  mkdir -p "$prepared_dir"

  if [[ "$KILL_STALE_QEMU" == true ]]; then
    stale_pattern="qemu-system-.*ifname=${VM_SOURCE_TAP_IFACE}|qemu-system-.*ifname=${VM_DESTINATION_TAP_IFACE}"
    if [[ "$SHARED_ENTRYPOINT_VM" != "true" ]]; then
      stale_pattern="${stale_pattern}|qemu-system-.*ifname=${ENTRYPOINT_VM_TAP_IFACE}"
    fi
    pkill -f "$stale_pattern" >/dev/null 2>&1 || true
    sleep 1
  fi

  prepare_run_id="${RUN_ID_PREFIX}-prepare-$(date +%Y%m%d-%H%M%S)"
  prepare_log_file="$WORKDIR/logs/${prepare_run_id}.log"
  prepare_case_dir="$WORKDIR/$prepare_run_id"

  prepare_args=(
    "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh"
    --run-id "$prepare_run_id"
    --workdir "$WORKDIR"
    --source-flavor "$SOURCE_FLAVOR"
    --destination-flavor "$DESTINATION_FLAVOR"
  )
  if [[ -n "$VM_ARCH" ]]; then prepare_args+=(--vm-arch "$VM_ARCH"); fi
  if [[ -n "$VM_BASE_IMAGE" ]]; then prepare_args+=(--vm-base-image "$VM_BASE_IMAGE"); fi

  echo "==> [L2] Preparing reusable source/destination VM cache..." >&2
  resolved_entrypoint_skip_cli_install="$(effective_entrypoint_skip_cli_install)"
  prepare_start_ts="$(date +%s)"
  set +e
  env \
    VM_NETWORK_MODE="$VM_NETWORK_MODE" \
    VM_LOCALNET_ENTRYPOINT_MODE="$VM_LOCALNET_ENTRYPOINT_MODE" \
    VM_SOURCE_BRIDGE_IP="$VM_SOURCE_BRIDGE_IP" \
    VM_DESTINATION_BRIDGE_IP="$VM_DESTINATION_BRIDGE_IP" \
    ENTRYPOINT_VM_BRIDGE_IP="$ENTRYPOINT_VM_BRIDGE_IP" \
    VM_BRIDGE_GATEWAY_IP="$VM_BRIDGE_GATEWAY_IP" \
    VM_SOURCE_TAP_IFACE="$VM_SOURCE_TAP_IFACE" \
    VM_DESTINATION_TAP_IFACE="$VM_DESTINATION_TAP_IFACE" \
    ENTRYPOINT_VM_TAP_IFACE="$ENTRYPOINT_VM_TAP_IFACE" \
    ENTRYPOINT_VM_SKIP_CLI_INSTALL="$resolved_entrypoint_skip_cli_install" \
    VM_ENTRYPOINT_DISK_PARENT_PREFIX="$ENTRYPOINT_CLI_CACHE_PREFIX" \
    SHARED_ENTRYPOINT_VM="$SHARED_ENTRYPOINT_VM" \
    PRE_SWAP_CATCHUP_TIMEOUT_SEC="$PRE_SWAP_CATCHUP_TIMEOUT_SEC" \
    PRE_SWAP_TOWER_TIMEOUT_SEC="$PRE_SWAP_TOWER_TIMEOUT_SEC" \
    REUSE_RUNTIME_READY_TIMEOUT_SEC="$REUSE_RUNTIME_READY_TIMEOUT_SEC" \
    AGAVE_VERSION="$AGAVE_VERSION" \
    BAM_JITO_VERSION="$BAM_JITO_VERSION" \
    BUILD_FROM_SOURCE="$BUILD_FROM_SOURCE" \
    CITY_GROUP="$CITY_GROUP" \
    PRE_SWAP_INJECTION_MODE="none" \
    VM_PREPARE_ONLY="true" \
    VM_PREPARE_EXPORT_DIR="$prepared_dir" \
    "${prepare_args[@]}" >"$prepare_log_file" 2>&1 &
  prepare_pid=$!

  while is_verify_run_alive "$prepare_pid" "$prepare_run_id"; do
    sleep "$PROGRESS_INTERVAL_SEC"
    if ! is_verify_run_alive "$prepare_pid" "$prepare_run_id"; then
      break
    fi
    prepare_elapsed_now=$(( $(date +%s) - prepare_start_ts ))
    prepare_elapsed_human="$(format_duration "$prepare_elapsed_now")"
    prepare_elapsed_aligned="$(format_duration_aligned "$prepare_elapsed_now")"
    prepare_progress_line="$(
      tail -n 80 "$prepare_log_file" 2>/dev/null \
        | awk '/^\[vm-hot-swap\]/ {line=$0} END {print line}' \
        || true
    )"
    if [[ -z "$prepare_progress_line" ]]; then
      prepare_progress_line="$(tail -n 1 "$prepare_log_file" 2>/dev/null || true)"
    fi
    echo "    [L2] prepare elapsed=${prepare_elapsed_aligned} ${prepare_progress_line}" >&2
  done

  wait "$prepare_pid"
  rc=$?
  set -e
  prepare_elapsed_sec=$(( $(date +%s) - prepare_start_ts ))
  prepare_elapsed_human="$(format_duration "$prepare_elapsed_sec")"

  if ((rc != 0)) || ! prepared_cache_ready "$prepared_dir"; then
    if (( retry_depth < 1 )) && rg -q "404[[:space:]]+Not Found|Unable to fetch some archives" "$prepare_log_file"; then
      echo "WARN: prepare cache failed due apt mirror 404; retrying once..." >&2
      PREPARE_CACHE_RETRY_DEPTH=$((retry_depth + 1))
      ensure_prepared_vm_cache "$prepared_dir"
      retry_rc=$?
      PREPARE_CACHE_RETRY_DEPTH="$retry_depth"
      return $retry_rc
    fi
    echo "FAIL: L2 prepare cache step failed (log: $prepare_log_file)" >&2
    return 1
  fi

  rm -rf "$prepare_case_dir"
  if (( retry_depth == 0 )); then
    PREPARE_CACHE_RETRY_DEPTH=0
  fi
  echo "==> [L2] Prepared cache ready: $prepared_dir (${prepare_elapsed_human})" >&2
}

is_preinjection_warmup_failure() {
  local reason="$1"
  grep -Eiq "did not become ready within|RPC warmup|validator RPC port 8899 did not become ready|did not reach catchup against|vm-entrypoint QEMU process exited before SSH|Device or resource busy|could not configure /dev/net/tun" <<<"$reason"
}

# case_name|injection_mode|expected_failure_regex|expected_pre_swap|expected_hot_swap
cases=(
  "swap_precheck_identity_mismatch|mismatch_destination_primary_identity|Identity keypairs don't match between hosts|true|false"
  "swap_precheck_interhost_ssh_blocked|block_source_to_destination_ssh|SSH connection from vm-source to vm-destination|true|false"
  "catchup_guard_entrypoint_down|stop_source_validator_service|Host vm-source validator service is not healthy.|false|false"
)

pass_count=0
fail_count=0
selected_count=0
case_timings=()
mkdir -p "$WORKDIR/logs"

PREPARED_CACHE_ROOT="$IMMUTABLE_VM_CACHE_ROOT/prepared-vms"
resolve_default_vm_config
PREPARED_CACHE_KEY="$(build_prepared_cache_key)"
PREPARED_CACHE_DIR="$PREPARED_CACHE_ROOT/${VM_ARCH:-auto}-${SOURCE_FLAVOR}-${DESTINATION_FLAVOR}-${PREPARED_CACHE_KEY}"
PREPARED_SOURCE_PREFIX="$PREPARED_CACHE_DIR/source"
PREPARED_DESTINATION_PREFIX="$PREPARED_CACHE_DIR/destination"

if [[ "$ALLOW_FALLBACK_PREPARED_CACHE" == "true" \
  && "$REUSE_PREPARED_VMS" == "true" && "$REFRESH_PREPARED_VMS" != "true" ]] \
  && ! prepared_cache_ready "$PREPARED_CACHE_DIR"; then
  cache_prefix="$PREPARED_CACHE_ROOT/${VM_ARCH:-auto}-${SOURCE_FLAVOR}-${DESTINATION_FLAVOR}-"
  fallback_cache_dir="$(find_fallback_prepared_cache_dir "$cache_prefix" || true)"
  if [[ -n "$fallback_cache_dir" ]]; then
    echo "==> [L2] Reusing fallback prepared cache: $fallback_cache_dir" >&2
    PREPARED_CACHE_DIR="$fallback_cache_dir"
    PREPARED_SOURCE_PREFIX="$PREPARED_CACHE_DIR/source"
    PREPARED_DESTINATION_PREFIX="$PREPARED_CACHE_DIR/destination"
  fi
fi

if [[ "$SHARED_ENTRYPOINT_VM" == "true" && "$VM_LOCALNET_ENTRYPOINT_MODE" == "vm" ]]; then
  ensure_shared_entrypoint_cli_cache
fi
if [[ "$SHARED_ENTRYPOINT_VM" != "true" ]]; then
  ensure_stateless_entrypoint_cli_cache
fi

if [[ "$REUSE_PREPARED_VMS" == "true" ]]; then
  ensure_prepared_vm_cache "$PREPARED_CACHE_DIR"
fi

for case_entry in "${cases[@]}"; do
  IFS='|' read -r case_name injection_mode expected_regex expected_pre_swap expected_hot_swap <<<"$case_entry"

  if [[ -n "$ONLY_CASE" && "$case_name" != "$ONLY_CASE" ]]; then
    continue
  fi
  selected_count=$((selected_count + 1))

  case_attempt=1
  case_finished=false
  case_stop_run=false
  refreshed_case_cache=false

  while [[ "$case_finished" != "true" ]]; do
    run_id="${RUN_ID_PREFIX}-${case_name}-$(date +%Y%m%d-%H%M%S)"
    if ((case_attempt > 1)); then
      run_id="${run_id}-retry${case_attempt}"
    fi
    case_dir="$WORKDIR/$run_id"
    log_file="$WORKDIR/logs/${run_id}.log"
    report_json="$case_dir/artifacts/test-report.json"
    report_text="$case_dir/artifacts/test-report.txt"

    if [[ "$PRUNE_OLD_RUNS" == true ]]; then
      prune_args=(
        --work-root "$REPO_ROOT/test-harness/work"
        --keep-runs "$PRUNE_KEEP_RUNS"
        --min-free-gb "$PRUNE_MIN_FREE_GB"
      )
      if [[ "$PRUNE_MUTABLE_CACHE_DIRS" == "true" ]] \
        || [[ "$PRUNE_MUTABLE_CACHE_DIRS" == "auto" && "$SHARED_ENTRYPOINT_VM" != "true" ]]; then
        prune_args+=(--prune-mutable-cache-dirs)
      fi
      "$REPO_ROOT/test-harness/scripts/prune-vm-test-runs.sh" "${prune_args[@]}" >/dev/null
    fi

    if [[ "$KILL_STALE_QEMU" == true ]]; then
      stale_pattern="qemu-system-.*ifname=${VM_SOURCE_TAP_IFACE}|qemu-system-.*ifname=${VM_DESTINATION_TAP_IFACE}"
      if [[ "$SHARED_ENTRYPOINT_VM" != "true" ]]; then
        stale_pattern="${stale_pattern}|qemu-system-.*ifname=${ENTRYPOINT_VM_TAP_IFACE}"
      fi
      pkill -f "$stale_pattern" >/dev/null 2>&1 || true
      sleep 1
    fi

    args=(
      "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh"
      --run-id "$run_id"
      --workdir "$WORKDIR"
      --source-flavor "$SOURCE_FLAVOR"
      --destination-flavor "$DESTINATION_FLAVOR"
    )
    if [[ -n "$VM_ARCH" ]]; then args+=(--vm-arch "$VM_ARCH"); fi
    if [[ -n "$VM_BASE_IMAGE" ]]; then args+=(--vm-base-image "$VM_BASE_IMAGE"); fi
    if [[ "$RETAIN_ON_FAILURE" == true || "$INSPECT_ON_INSTABILITY" == "true" ]]; then
      args+=(--retain-on-failure)
    fi
    if [[ "$RETAIN_ALWAYS" == true ]]; then args+=(--retain-always); fi

    source_disk_parent_prefix=""
    destination_disk_parent_prefix=""
    if [[ "$REUSE_PREPARED_VMS" == "true" ]]; then
      source_disk_parent_prefix="$PREPARED_SOURCE_PREFIX"
      destination_disk_parent_prefix="$PREPARED_DESTINATION_PREFIX"
    fi

    if ((case_attempt > 1)); then
      echo "==> [L2] Re-running case: $case_name attempt=${case_attempt} (injection=$injection_mode)" >&2
    else
      echo "==> [L2] Running case: $case_name (injection=$injection_mode)" >&2
    fi

    case_start_ts="$(date +%s)"
    resolved_entrypoint_skip_cli_install="$(effective_entrypoint_skip_cli_install)"
    set +e
    env \
      VM_NETWORK_MODE="$VM_NETWORK_MODE" \
      VM_LOCALNET_ENTRYPOINT_MODE="$VM_LOCALNET_ENTRYPOINT_MODE" \
      VM_SOURCE_BRIDGE_IP="$VM_SOURCE_BRIDGE_IP" \
      VM_DESTINATION_BRIDGE_IP="$VM_DESTINATION_BRIDGE_IP" \
      ENTRYPOINT_VM_BRIDGE_IP="$ENTRYPOINT_VM_BRIDGE_IP" \
      VM_BRIDGE_GATEWAY_IP="$VM_BRIDGE_GATEWAY_IP" \
      VM_SOURCE_TAP_IFACE="$VM_SOURCE_TAP_IFACE" \
      VM_DESTINATION_TAP_IFACE="$VM_DESTINATION_TAP_IFACE" \
      ENTRYPOINT_VM_TAP_IFACE="$ENTRYPOINT_VM_TAP_IFACE" \
      ENTRYPOINT_VM_SKIP_CLI_INSTALL="$resolved_entrypoint_skip_cli_install" \
      VM_ENTRYPOINT_DISK_PARENT_PREFIX="$ENTRYPOINT_CLI_CACHE_PREFIX" \
      SHARED_ENTRYPOINT_VM="$SHARED_ENTRYPOINT_VM" \
      PRE_SWAP_CATCHUP_TIMEOUT_SEC="$PRE_SWAP_CATCHUP_TIMEOUT_SEC" \
      PRE_SWAP_TOWER_TIMEOUT_SEC="$PRE_SWAP_TOWER_TIMEOUT_SEC" \
      REUSE_RUNTIME_READY_TIMEOUT_SEC="$REUSE_RUNTIME_READY_TIMEOUT_SEC" \
      AGAVE_VERSION="$AGAVE_VERSION" \
      BAM_JITO_VERSION="$BAM_JITO_VERSION" \
      BUILD_FROM_SOURCE="$BUILD_FROM_SOURCE" \
      CITY_GROUP="$CITY_GROUP" \
      PRE_SWAP_INJECTION_MODE="$injection_mode" \
      VM_SOURCE_DISK_PARENT_PREFIX="$source_disk_parent_prefix" \
      VM_DESTINATION_DISK_PARENT_PREFIX="$destination_disk_parent_prefix" \
      "${args[@]}" >"$log_file" 2>&1 &
    case_pid=$!

    while is_verify_run_alive "$case_pid" "$run_id"; do
      sleep "$PROGRESS_INTERVAL_SEC"
      if ! is_verify_run_alive "$case_pid" "$run_id"; then
        break
      fi
      case_elapsed_now=$(( $(date +%s) - case_start_ts ))
      case_elapsed_aligned_now="$(format_duration_aligned "$case_elapsed_now")"
      progress_line="$(
        tail -n 80 "$log_file" 2>/dev/null \
          | awk '/^\[vm-hot-swap\]/ {line=$0} END {print line}' \
          || true
      )"
      if [[ -z "$progress_line" ]]; then
        progress_line="$(tail -n 1 "$log_file" 2>/dev/null || true)"
      fi
      echo "    [L2] ${case_name} elapsed=${case_elapsed_aligned_now} ${progress_line}" >&2
    done

    wait "$case_pid"
    rc=$?
    set -e
    case_elapsed_sec=$(( $(date +%s) - case_start_ts ))
    case_elapsed_human="$(format_duration "$case_elapsed_sec")"

    case_failed=false
    injection_exercised=true
    actual_pre_swap="missing"
    actual_hot_swap="missing"
    failure_signal_line=""
    injection_marker_line=""
    pre_injection_reason=""
    early_reason=""

    if ((rc == 0)); then
      echo "FAIL: $case_name expected non-zero exit but command succeeded" >&2
      case_failed=true
    fi

    if [[ ! -f "$report_json" ]]; then
      echo "FAIL: $case_name missing report json: $report_json" >&2
      case_failed=true
      pre_injection_reason="missing report json"
    else
      actual_pre_swap="$(
        jq -r '
          if .checks_passed | has("pre_swap_runtime_and_client") then
            .checks_passed.pre_swap_runtime_and_client
          elif .checks_passed | has("pre_swap_runtime_verification") then
            .checks_passed.pre_swap_runtime_verification
          else
            "missing"
          end
        ' "$report_json"
      )"
      actual_hot_swap="$(
        jq -r '
          if .checks_passed | has("hot_swap_playbook_completed") then
            .checks_passed.hot_swap_playbook_completed
          else
            "missing"
          end
        ' "$report_json"
      )"
      early_reason="$(jq -r '.early_failure.reason // empty' "$report_json")"
      if [[ -n "$early_reason" && "$early_reason" != "not captured" ]]; then
        injection_exercised=false
        echo "FAIL: $case_name harness failed before guardrail injection: $early_reason" >&2
        case_failed=true
      fi
      if [[ "$injection_exercised" == true ]]; then
        if [[ "$actual_pre_swap" != "$expected_pre_swap" ]]; then
          echo "FAIL: $case_name expected pre_swap=$expected_pre_swap got $actual_pre_swap" >&2
          case_failed=true
        fi
        if [[ "$actual_hot_swap" != "$expected_hot_swap" ]]; then
          echo "FAIL: $case_name expected hot_swap=$expected_hot_swap got $actual_hot_swap" >&2
          case_failed=true
        fi
      fi
    fi

    if [[ "$injection_mode" != "none" ]]; then
      injection_marker_line="$(
        grep -Einm1 "Applying pre-swap injection mode: ${injection_mode}" "$log_file" 2>/dev/null || true
      )"
      if [[ -z "$injection_marker_line" ]]; then
        injection_exercised=false
        pre_injection_reason="$(
          grep -Eim1 "did not become ready within|QEMU process exited before SSH|Shared bridge/tap networking is not ready|Device or resource busy|could not configure /dev/net/tun|missing report json" "$log_file" 2>/dev/null || true
        )"
        if [[ -z "$pre_injection_reason" ]]; then
          pre_injection_reason="injection marker not found in log"
        fi
        echo "FAIL: $case_name harness failed before guardrail injection: ${pre_injection_reason}" >&2
        case_failed=true
      fi
    fi

    if [[ "$injection_exercised" == true ]]; then
      failure_signal_line="$(
        grep -Einm1 "$expected_regex" "$log_file" "$report_text" 2>/dev/null || true
      )"
      if [[ -z "$failure_signal_line" ]]; then
        echo "FAIL: $case_name missing expected failure signal regex: $expected_regex" >&2
        case_failed=true
      fi
    fi

    reason_for_retry="$pre_injection_reason"
    if [[ -z "$reason_for_retry" && -n "$early_reason" && "$early_reason" != "not captured" ]]; then
      reason_for_retry="$early_reason"
    fi
    if [[ -z "$reason_for_retry" ]] && [[ "$expected_pre_swap" == "true" && "$actual_pre_swap" != "true" ]]; then
      reason_for_retry="$(
        grep -Eim1 "did not reach catchup against|validator RPC port 8899 did not become ready|error sending request for url \(http://localhost:8899/\)" "$log_file" "$report_text" 2>/dev/null || true
      )"
    fi
    recoverable_environment_failure=false
    if [[ -n "$reason_for_retry" ]] && is_preinjection_warmup_failure "$reason_for_retry"; then
      if [[ "$injection_exercised" != "true" ]]; then
        recoverable_environment_failure=true
      elif [[ "$expected_pre_swap" == "true" && "$actual_pre_swap" != "$expected_pre_swap" ]]; then
        recoverable_environment_failure=true
      fi
    fi

    if [[ "$case_failed" == true \
      && "$AUTO_REFRESH_ON_PREINJECTION_WARMUP_FAILURE" == "true" \
      && "$REUSE_PREPARED_VMS" == "true" \
      && "$refreshed_case_cache" != "true" \
      && "$recoverable_environment_failure" == "true" ]]; then
      refresh_action="$(inspection_action_on_recoverable_failure "$case_name" "$reason_for_retry" "$run_id" "$case_dir" "$log_file")"
      if [[ "$refresh_action" == "stop" ]]; then
        echo "    [L2] ${case_name}: auto-refresh skipped by operator request." >&2
      else
      echo "    [L2] ${case_name}: environment became unstable (${reason_for_retry}); refreshing prepared cache and retrying once..." >&2
      refresh_saved="$REFRESH_PREPARED_VMS"
      REFRESH_PREPARED_VMS=true
      if ! ensure_prepared_vm_cache "$PREPARED_CACHE_DIR"; then
        echo "FAIL: $case_name auto-refresh retry could not rebuild prepared cache." >&2
      else
        REFRESH_PREPARED_VMS="$refresh_saved"
        refreshed_case_cache=true
        case_attempt=$((case_attempt + 1))
        continue
      fi
      REFRESH_PREPARED_VMS="$refresh_saved"
      fi
    fi

    case_timings+=("${case_name}:${case_elapsed_human}")
    if [[ "$case_failed" == true ]]; then
      fail_count=$((fail_count + 1))
      echo "FAIL: $case_name (${case_elapsed_human}, log: $log_file)" >&2
      if [[ "$CONTINUE_ON_ERROR" != true ]]; then
        case_stop_run=true
      fi
    else
      pass_count=$((pass_count + 1))
      if [[ -n "$failure_signal_line" ]]; then
        failure_signal_line="${failure_signal_line#$WORKDIR/}"
        echo "PASS: $case_name (${case_elapsed_human}) pre_swap=${actual_pre_swap} hot_swap=${actual_hot_swap}" >&2
        echo "      evidence: ${failure_signal_line}" >&2
      else
        echo "PASS: $case_name (${case_elapsed_human}) pre_swap=${actual_pre_swap} hot_swap=${actual_hot_swap}" >&2
      fi
    fi
    case_finished=true
  done

  if [[ "$case_stop_run" == "true" ]]; then
    break
  fi
done

if ((selected_count == 0)); then
  echo "No L2 cases selected. Available: catchup_guard_entrypoint_down, swap_precheck_identity_mismatch, swap_precheck_interhost_ssh_blocked" >&2
  exit 2
fi

echo "L2 guardrail summary: passed=$pass_count failed=$fail_count" >&2
if ((${#case_timings[@]} > 0)); then
  echo "L2 case timings: ${case_timings[*]}" >&2
fi
if ((fail_count > 0)); then
  exit 1
fi

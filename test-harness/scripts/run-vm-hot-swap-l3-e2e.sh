#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work/vm-hot-swap-l3}"
RUN_ID_PREFIX="${RUN_ID_PREFIX:-vm-hot-swap-l3}"
MODE="${MODE:-canary}"
VM_ARCH="${VM_ARCH:-}"
VM_BASE_IMAGE="${VM_BASE_IMAGE:-}"
SOURCE_FLAVOR="${SOURCE_FLAVOR:-agave}"
DESTINATION_FLAVOR="${DESTINATION_FLAVOR:-jito-bam}"
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
PROGRESS_INTERVAL_SEC="${PROGRESS_INTERVAL_SEC:-30}"

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
  run-vm-hot-swap-l3-e2e.sh [options]

Options:
  --mode <canary|matrix>           (default: canary)
  --workdir <path>                 (default: ./test-harness/work/vm-hot-swap-l3)
  --run-id-prefix <id>             (default: vm-hot-swap-l3)
  --vm-arch <amd64|arm64>
  --vm-base-image <path>
  --source-flavor <flavor>         (canary mode; default: agave)
  --destination-flavor <flavor>    (canary mode; default: jito-bam)
  --retain-on-failure
  --retain-always
  --no-prune
  --prune-keep-runs <n>            (default: 6)
  --prune-min-free-gb <n>          (default: 40)
  --prune-mutable-caches           Remove mutable legacy caches (_shared-entrypoint-vm, _prepared-vms) before runs
  --no-prune-mutable-caches        Keep mutable legacy caches
  --no-kill-stale-qemu
  --shared-entrypoint
  --no-shared-entrypoint
  --no-vm-reuse
  --refresh-vm-reuse
  --prepared-cache-key <text>      Override prepared VM cache key namespace
EOF
}

while (($# > 0)); do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
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

build_prepared_cache_key() {
  local source_flavor="$1"
  local destination_flavor="$2"
  local raw
  local verifier_hash

  if [[ -n "$PREPARED_CACHE_KEY_OVERRIDE" ]]; then
    raw="$PREPARED_CACHE_KEY_OVERRIDE|$source_flavor|$destination_flavor"
  else
    verifier_hash="$(
      sha256sum "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh" \
        | awk '{print substr($1, 1, 16)}'
    )"
    raw="$VM_ARCH|$VM_BASE_IMAGE|$source_flavor|$destination_flavor|$AGAVE_VERSION|$BAM_JITO_VERSION|$BUILD_FROM_SOURCE|$CITY_GROUP|$VM_NETWORK_MODE|$verifier_hash"
  fi
  printf '%s' "$raw" | sha256sum | awk '{print substr($1, 1, 16)}'
}

prepared_cache_ready() {
  local dir="$1"
  [[ -f "$dir/.ready" ]] || return 1
  [[ -r "$dir/source.qcow2" ]] || return 1
  [[ -r "$dir/source-ledger.qcow2" ]] || return 1
  [[ -r "$dir/source-accounts.qcow2" ]] || return 1
  [[ -r "$dir/source-snapshots.qcow2" ]] || return 1
  [[ -r "$dir/destination.qcow2" ]] || return 1
  [[ -r "$dir/destination-ledger.qcow2" ]] || return 1
  [[ -r "$dir/destination-accounts.qcow2" ]] || return 1
  [[ -r "$dir/destination-snapshots.qcow2" ]] || return 1
}

build_entrypoint_cache_key() {
  local verifier_hash
  verifier_hash="$(
    sha256sum "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh" \
      | awk '{print substr($1, 1, 16)}'
  )"
  printf '%s' "${VM_ARCH}|${VM_BASE_IMAGE}|${AGAVE_VERSION}|${BUILD_FROM_SOURCE}|${verifier_hash}" \
    | sha256sum | awk '{print substr($1, 1, 16)}'
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
  [[ -r "$cache_dir/entrypoint-snapshots.qcow2" ]] || return 1
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
  local start_ts
  local elapsed_now
  local elapsed_aligned
  local progress_line
  local pid
  local rc=0

  ENTRYPOINT_CLI_CACHE_PREFIX=""

  if [[ "$VM_LOCALNET_ENTRYPOINT_MODE" != "vm" ]]; then
    return 0
  fi

  cache_key="$(build_entrypoint_cache_key)"
  cache_dir="$ENTRYPOINT_CLI_IMMUTABLE_CACHE_ROOT/${VM_ARCH:-auto}-${cache_key}"
  cache_prefix="$cache_dir/entrypoint"
  ENTRYPOINT_CLI_CACHE_PREFIX="$cache_prefix"

  if [[ "$REFRESH_PREPARED_VMS" != "true" ]] && entrypoint_immutable_cache_ready "$cache_dir" "$cache_key"; then
    echo "==> [L3] Reusing immutable entrypoint CLI cache: $cache_dir" >&2
    return 0
  fi

  rm -rf "$cache_dir"
  mkdir -p "$cache_dir" "$WORKDIR/logs"
  build_workdir="$WORKDIR/_entrypoint-cli-cache-build"
  rm -rf "$build_workdir"
  mkdir -p "$build_workdir"

  if [[ "$KILL_STALE_QEMU" == true ]]; then
    pkill -f "qemu-system-.*ifname=${ENTRYPOINT_VM_TAP_IFACE}" >/dev/null 2>&1 || true
    sleep 1
  fi

  run_id="${RUN_ID_PREFIX}-prepare-entrypoint-cli-$(date +%Y%m%d-%H%M%S)"
  log_file="$WORKDIR/logs/${run_id}.log"
  args=(
    "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh"
    --run-id "$run_id"
    --workdir "$build_workdir"
    --source-flavor "${SOURCE_FLAVOR}"
    --destination-flavor "${DESTINATION_FLAVOR}"
  )
  if [[ -n "$VM_ARCH" ]]; then args+=(--vm-arch "$VM_ARCH"); fi
  if [[ -n "$VM_BASE_IMAGE" ]]; then args+=(--vm-base-image "$VM_BASE_IMAGE"); fi

  echo "==> [L3] Preparing immutable entrypoint CLI cache (stateless)..." >&2
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

  while is_verify_prepare_alive "$pid" "$run_id"; do
    sleep "$PROGRESS_INTERVAL_SEC"
    if ! is_verify_prepare_alive "$pid" "$run_id"; then
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
    echo "    [L3] entrypoint-immutable-cache elapsed=${elapsed_aligned} ${progress_line}" >&2
  done

  wait "$pid"
  rc=$?
  set -e
  if (( rc != 0 )); then
    echo "FAIL: L3 immutable entrypoint cache prepare failed (log: $log_file)" >&2
    return 1
  fi

  source_prefix="$(resolve_shared_entrypoint_source_prefix "$build_workdir")"
  if [[ -z "$source_prefix" ]]; then
    echo "FAIL: L3 immutable entrypoint cache source prefix not found under $build_workdir/_shared-entrypoint-vm/vm" >&2
    return 1
  fi

  for suffix in ".qcow2" "-ledger.qcow2" "-accounts.qcow2" "-snapshots.qcow2"; do
    if [[ ! -r "${source_prefix}${suffix}" ]]; then
      echo "FAIL: L3 immutable entrypoint cache source disk missing: ${source_prefix}${suffix}" >&2
      return 1
    fi
  done

  cp --reflink=auto -f "${source_prefix}.qcow2" "${cache_prefix}.qcow2"
  cp --reflink=auto -f "${source_prefix}-ledger.qcow2" "${cache_prefix}-ledger.qcow2"
  cp --reflink=auto -f "${source_prefix}-accounts.qcow2" "${cache_prefix}-accounts.qcow2"
  cp --reflink=auto -f "${source_prefix}-snapshots.qcow2" "${cache_prefix}-snapshots.qcow2"
  printf '%s\n' "$cache_key" >"$cache_dir/.cache-key"
  touch "$cache_dir/.ready"
  rm -rf "$build_workdir"

  echo "==> [L3] Immutable entrypoint CLI cache ready: $cache_dir ($(format_duration "$(( $(date +%s) - start_ts ))"))" >&2
}

is_verify_prepare_alive() {
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

ensure_prepared_vm_cache() {
  local source_flavor="$1"
  local destination_flavor="$2"
  local cache_key
  local prepared_dir
  local prepare_run_id
  local prepare_log_file
  local prepare_case_dir
  local prepare_pid
  local prepare_start_ts
  local prepare_elapsed_now
  local prepare_elapsed_human
  local prepare_elapsed_aligned
  local progress_line
  local rc
  local resolved_entrypoint_skip_cli_install
  local prepare_args=()

  if [[ "$REUSE_PREPARED_VMS" != "true" ]]; then
    return 0
  fi

  cache_key="$(build_prepared_cache_key "$source_flavor" "$destination_flavor")"
  prepared_dir="$IMMUTABLE_VM_CACHE_ROOT/prepared-vms/${VM_ARCH:-auto}-${source_flavor}-${destination_flavor}-${cache_key}"

  PREPARED_CACHE_DIR="$prepared_dir"
  PREPARED_SOURCE_PREFIX="$prepared_dir/source"
  PREPARED_DESTINATION_PREFIX="$prepared_dir/destination"

  if [[ "$REFRESH_PREPARED_VMS" != "true" ]] && prepared_cache_ready "$prepared_dir"; then
    echo "==> [L3] Reusing prepared cache for ${source_flavor}->${destination_flavor}: $prepared_dir" >&2
    return 0
  fi

  mkdir -p "$WORKDIR/logs"
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

  prepare_run_id="${RUN_ID_PREFIX}-prepare-${source_flavor}-to-${destination_flavor}-$(date +%Y%m%d-%H%M%S)"
  prepare_log_file="$WORKDIR/logs/${prepare_run_id}.log"
  prepare_case_dir="$WORKDIR/$prepare_run_id"

  echo "==> [L3] Preparing cache for ${source_flavor}->${destination_flavor}..." >&2
  prepare_args=(
    "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh"
    --run-id "$prepare_run_id"
    --workdir "$WORKDIR"
    --source-flavor "$source_flavor"
    --destination-flavor "$destination_flavor"
  )
  if [[ -n "$VM_ARCH" ]]; then
    prepare_args+=(--vm-arch "$VM_ARCH")
  fi
  if [[ -n "$VM_BASE_IMAGE" ]]; then
    prepare_args+=(--vm-base-image "$VM_BASE_IMAGE")
  fi

  prepare_start_ts="$(date +%s)"
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
    PRE_SWAP_INJECTION_MODE="none" \
    VM_PREPARE_ONLY="true" \
    VM_PREPARE_EXPORT_DIR="$prepared_dir" \
    "${prepare_args[@]}" >"$prepare_log_file" 2>&1 &
  prepare_pid=$!

  while is_verify_prepare_alive "$prepare_pid" "$prepare_run_id"; do
    sleep "$PROGRESS_INTERVAL_SEC"
    if ! is_verify_prepare_alive "$prepare_pid" "$prepare_run_id"; then
      break
    fi
    prepare_elapsed_now=$(( $(date +%s) - prepare_start_ts ))
    prepare_elapsed_aligned="$(format_duration_aligned "$prepare_elapsed_now")"
    progress_line="$(
      tail -n 80 "$prepare_log_file" 2>/dev/null \
        | awk '/^\[vm-hot-swap\]/ {line=$0} END {print line}' \
        || true
    )"
    if [[ -z "$progress_line" ]]; then
      progress_line="$(tail -n 1 "$prepare_log_file" 2>/dev/null || true)"
    fi
    echo "    [L3] prepare ${source_flavor}->${destination_flavor} elapsed=${prepare_elapsed_aligned} ${progress_line}" >&2
  done

  wait "$prepare_pid"
  rc=$?
  set -e
  prepare_elapsed_human="$(format_duration "$(( $(date +%s) - prepare_start_ts ))")"

  if ((rc != 0)) || ! prepared_cache_ready "$prepared_dir"; then
    echo "FAIL: L3 cache prepare failed for ${source_flavor}->${destination_flavor} (log: $prepare_log_file)" >&2
    return 1
  fi

  rm -rf "$prepare_case_dir"
  echo "==> [L3] Prepared cache ready for ${source_flavor}->${destination_flavor}: $prepared_dir (${prepare_elapsed_human})" >&2
}

if [[ "$KILL_STALE_QEMU" == true ]]; then
  stale_pattern="qemu-system-.*ifname=${VM_SOURCE_TAP_IFACE}|qemu-system-.*ifname=${VM_DESTINATION_TAP_IFACE}"
  if [[ "$SHARED_ENTRYPOINT_VM" != "true" ]]; then
    stale_pattern="${stale_pattern}|qemu-system-.*ifname=${ENTRYPOINT_VM_TAP_IFACE}"
  fi
  pkill -f "$stale_pattern" >/dev/null 2>&1 || true
  sleep 1
fi

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

resolve_default_vm_config

if [[ "$SHARED_ENTRYPOINT_VM" != "true" ]]; then
  ensure_stateless_entrypoint_cli_cache
fi

run_single_case() {
  local run_id="$1"
  local source_flavor="$2"
  local destination_flavor="$3"
  local source_parent_prefix=""
  local destination_parent_prefix=""
  local resolved_entrypoint_skip_cli_install
  local args=()

  if [[ "$REUSE_PREPARED_VMS" == "true" ]]; then
    source_parent_prefix="$PREPARED_SOURCE_PREFIX"
    destination_parent_prefix="$PREPARED_DESTINATION_PREFIX"
  fi

  args=(
    "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh"
    --run-id "$run_id"
    --workdir "$WORKDIR"
    --source-flavor "$source_flavor"
    --destination-flavor "$destination_flavor"
  )
  if [[ -n "$VM_ARCH" ]]; then
    args+=(--vm-arch "$VM_ARCH")
  fi
  if [[ -n "$VM_BASE_IMAGE" ]]; then
    args+=(--vm-base-image "$VM_BASE_IMAGE")
  fi
  if [[ "$RETAIN_ON_FAILURE" == true ]]; then
    args+=(--retain-on-failure)
  fi
  if [[ "$RETAIN_ALWAYS" == true ]]; then
    args+=(--retain-always)
  fi

  resolved_entrypoint_skip_cli_install="$(effective_entrypoint_skip_cli_install)"

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
    VM_SOURCE_DISK_PARENT_PREFIX="$source_parent_prefix" \
    VM_DESTINATION_DISK_PARENT_PREFIX="$destination_parent_prefix" \
    "${args[@]}"
}

case "$MODE" in
  canary)
    if [[ "$REUSE_PREPARED_VMS" == "true" ]]; then
      ensure_prepared_vm_cache "$SOURCE_FLAVOR" "$DESTINATION_FLAVOR"
    fi
    run_id="${RUN_ID_PREFIX}-canary-${SOURCE_FLAVOR}-to-${DESTINATION_FLAVOR}-$(date +%Y%m%d-%H%M%S)"
    run_single_case "$run_id" "$SOURCE_FLAVOR" "$DESTINATION_FLAVOR"
    ;;
  matrix)
    cases=(
      "agave_to_agave:agave:agave"
      "agave_to_jito_bam:agave:jito-bam"
      "jito_bam_to_agave:jito-bam:agave"
      "jito_bam_to_jito_bam:jito-bam:jito-bam"
    )
    pass_count=0
    fail_count=0
    for case_entry in "${cases[@]}"; do
      IFS=':' read -r case_name source_flavor destination_flavor <<<"$case_entry"
      if [[ "$REUSE_PREPARED_VMS" == "true" ]]; then
        ensure_prepared_vm_cache "$source_flavor" "$destination_flavor"
      fi
      run_id="${RUN_ID_PREFIX}-matrix-${case_name}-$(date +%Y%m%d-%H%M%S)"
      echo "==> [L3] Running matrix case: ${case_name} (${source_flavor} -> ${destination_flavor})" >&2
      if run_single_case "$run_id" "$source_flavor" "$destination_flavor"; then
        pass_count=$((pass_count + 1))
        echo "PASS: $case_name" >&2
      else
        fail_count=$((fail_count + 1))
        echo "FAIL: $case_name" >&2
        break
      fi
    done
    echo "VM hot-swap L3 matrix summary: passed=$pass_count failed=$fail_count" >&2
    if ((fail_count > 0)); then
      exit 1
    fi
    ;;
  *)
    echo "Unsupported mode: $MODE (expected: canary|matrix)" >&2
    exit 2
    ;;
esac

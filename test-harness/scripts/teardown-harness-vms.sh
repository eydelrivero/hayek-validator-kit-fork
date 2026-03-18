#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

STATE_FILE="${STATE_FILE:-$REPO_ROOT/test-harness/work/manual-vm-cluster/current.env}"
WORK_ROOT="${WORK_ROOT:-$REPO_ROOT/test-harness/work}"
PURGE_CASE_DIR=false
MANUAL_STATE_ONLY=false

usage() {
  cat <<'EOF'
Usage:
  teardown-harness-vms.sh [options]

Stops harness-owned VM hot-swap and access-validation processes.

By default this script:
- tears down the current manual cluster if its state file exists
- scans ./test-harness/work for retained harness PID files
- kills the referenced QEMU/localnet processes

Options:
  --state-file <path>     (default: ./test-harness/work/manual-vm-cluster/current.env)
  --work-root <path>      (default: ./test-harness/work)
  --manual-state-only     Only tear down processes referenced by the manual state file
  --purge-case-dir        Remove the manual cluster case directory after stopping it
EOF
}

while (($# > 0)); do
  case "$1" in
    --state-file)
      STATE_FILE="${2:-}"
      shift 2
      ;;
    --work-root)
      WORK_ROOT="${2:-}"
      shift 2
      ;;
    --manual-state-only)
      MANUAL_STATE_ONLY=true
      shift
      ;;
    --purge-case-dir)
      PURGE_CASE_DIR=true
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

declare -A SEEN_PID_FILES=()
declare -A STOPPED_PIDS=()
declare -A DISCOVERED_CASE_DIRS=()
declare -a PID_FILE_TARGETS=()
declare -a MANUAL_CASE_DIRS=()
manual_state_loaded=false
cleanup_count=0

register_pid_file() {
  local pid_file="${1:-}"
  local label="${2:-process}"

  if [[ -z "$pid_file" ]]; then
    return 0
  fi

  if [[ -n "${SEEN_PID_FILES["$pid_file"]+x}" ]]; then
    return 0
  fi
  SEEN_PID_FILES["$pid_file"]="$label"
  PID_FILE_TARGETS+=("${pid_file}"$'\t'"${label}")
}

load_manual_state_if_present() {
  if [[ ! -r "$STATE_FILE" ]]; then
    if [[ "$MANUAL_STATE_ONLY" == "true" ]]; then
      echo "Manual cluster state file not found: $STATE_FILE" >&2
      exit 1
    fi
    echo "[harness-teardown] manual state file not found, continuing with work-root scan: $STATE_FILE" >&2
    return 0
  fi

  # shellcheck disable=SC1090
  source "$STATE_FILE"
  manual_state_loaded=true

  register_pid_file "${LOCALNET_ENTRYPOINT_PID_FILE:-}" "localnet-entrypoint"
  register_pid_file "${SRC_PID_FILE:-}" "source-qemu"
  register_pid_file "${DST_PID_FILE:-}" "destination-qemu"
  register_pid_file "${ENTRYPOINT_VM_PID_FILE:-}" "entrypoint-qemu"

  if [[ -n "${CASE_DIR:-}" ]]; then
    MANUAL_CASE_DIRS+=("$CASE_DIR")
  fi
}

label_for_discovered_pid_file() {
  local pid_file="$1"
  local label
  local run_dir
  local run_name

  label="$(basename "$pid_file")"
  run_dir="$(dirname "$pid_file")"
  run_name="$(basename "$run_dir")"

  case "$(basename "$pid_file")" in
    source-qemu.pid) label="source-qemu" ;;
    destination-qemu.pid) label="destination-qemu" ;;
    entrypoint-qemu.pid) label="entrypoint-qemu" ;;
    localnet-entrypoint.pid) label="localnet-entrypoint" ;;
    qemu.pid)
      if [[ "$run_dir" == */adapter/artifacts/vm/* || "$run_dir" == */adapter/state/vm/* ]]; then
        label="access-validation-qemu"
      else
        label="qemu"
      fi
      ;;
  esac

  printf '%s (%s)\n' "$label" "$run_name"
}

discover_harness_pid_files() {
  local pid_file

  while IFS= read -r pid_file; do
    [[ -n "$pid_file" ]] || continue
    register_pid_file "$pid_file" "$(label_for_discovered_pid_file "$pid_file")"
    DISCOVERED_CASE_DIRS["$(dirname "$(dirname "$pid_file")")"]=1
  done < <(
    find "$WORK_ROOT" -type f \
      \( -name 'qemu.pid' \
      -o -name 'source-qemu.pid' \
      -o -name 'destination-qemu.pid' \
      -o -name 'entrypoint-qemu.pid' \
      -o -name 'localnet-entrypoint.pid' \) \
      | LC_ALL=C sort
  )
}

cleanup_pid_file() {
  local pid_file="${1:-}"
  local label="${2:-process}"
  local pid=""

  if [[ -z "$pid_file" || ! -f "$pid_file" ]]; then
    echo "[harness-teardown] ${label}: pid file not present, skipping (${pid_file:-unset})" >&2
    return 0
  fi

  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    echo "[harness-teardown] ${label}: empty pid file, skipping (${pid_file})" >&2
    return 0
  fi

  if [[ -n "${STOPPED_PIDS["$pid"]+x}" ]]; then
    echo "[harness-teardown] ${label}: pid ${pid} already handled via ${STOPPED_PIDS["$pid"]}" >&2
    return 0
  fi

  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "[harness-teardown] ${label}: pid ${pid} is already stopped" >&2
    STOPPED_PIDS["$pid"]="$label"
    return 0
  fi

  echo "[harness-teardown] stopping ${label} pid=${pid}" >&2
  kill "$pid" >/dev/null 2>&1 || true
  sleep 1
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi
  STOPPED_PIDS["$pid"]="$label"
  cleanup_count=$((cleanup_count + 1))
}

load_manual_state_if_present

if [[ "$MANUAL_STATE_ONLY" != "true" ]]; then
  discover_harness_pid_files
fi

if (( ${#PID_FILE_TARGETS[@]} == 0 )); then
  echo "[harness-teardown] no harness-owned VM pid files found" >&2
else
  for target in "${PID_FILE_TARGETS[@]}"; do
    IFS=$'\t' read -r pid_file label <<<"$target"
    cleanup_pid_file "$pid_file" "$label"
  done
fi

if [[ "$PURGE_CASE_DIR" == "true" ]]; then
  for case_dir in "${MANUAL_CASE_DIRS[@]}"; do
    if [[ -n "$case_dir" && -d "$case_dir" ]]; then
      echo "[harness-teardown] removing case directory ${case_dir}" >&2
      rm -rf "$case_dir"
    fi
  done
fi

if [[ "$manual_state_loaded" == "true" ]]; then
  rm -f "$STATE_FILE"
fi

echo "[harness-teardown] stopped ${cleanup_count} harness process(es)" >&2

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

STATE_FILE="${STATE_FILE:-$REPO_ROOT/test-harness/work/manual-vm-cluster/current.env}"
PURGE_CASE_DIR=false

usage() {
  cat <<'EOF'
Usage:
  teardown-vm-hot-swap-manual-cluster.sh [options]

Stops the VM cluster previously launched by run-vm-hot-swap-manual-cluster.sh.

Options:
  --state-file <path>   (default: ./test-harness/work/manual-vm-cluster/current.env)
  --purge-case-dir      Remove the retained case directory after stopping the cluster
EOF
}

while (($# > 0)); do
  case "$1" in
    --state-file)
      STATE_FILE="${2:-}"
      shift 2
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

if [[ ! -r "$STATE_FILE" ]]; then
  echo "Manual cluster state file not found: $STATE_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$STATE_FILE"

cleanup_pid_file() {
  local pid_file="${1:-}"
  local label="${2:-process}"
  local pid=""

  if [[ -z "$pid_file" || ! -f "$pid_file" ]]; then
    echo "[manual-teardown] ${label}: pid file not present, skipping (${pid_file:-unset})" >&2
    return 0
  fi

  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    echo "[manual-teardown] ${label}: empty pid file, skipping (${pid_file})" >&2
    return 0
  fi

  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "[manual-teardown] ${label}: pid ${pid} is already stopped" >&2
    return 0
  fi

  echo "[manual-teardown] stopping ${label} pid=${pid}" >&2
  kill "$pid" >/dev/null 2>&1 || true
  sleep 1
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi
}

cleanup_pid_file "${LOCALNET_ENTRYPOINT_PID_FILE:-}" "localnet-entrypoint"
cleanup_pid_file "${SRC_PID_FILE:-}" "source-qemu"
cleanup_pid_file "${DST_PID_FILE:-}" "destination-qemu"
cleanup_pid_file "${ENTRYPOINT_VM_PID_FILE:-}" "entrypoint-qemu"

if [[ "$PURGE_CASE_DIR" == "true" && -n "${CASE_DIR:-}" && -d "${CASE_DIR:-}" ]]; then
  echo "[manual-teardown] removing case directory ${CASE_DIR}" >&2
  rm -rf "$CASE_DIR"
fi

rm -f "$STATE_FILE"
echo "[manual-teardown] manual cluster stopped" >&2

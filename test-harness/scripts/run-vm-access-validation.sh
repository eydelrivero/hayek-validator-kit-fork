#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work/vm-access-validation}"
RUN_ID_PREFIX="${RUN_ID_PREFIX:-vm-access-validation}"
RUN_ID="${RUN_ID:-}"
VM_ARCH="${VM_ARCH:-}"
VM_BASE_IMAGE="${VM_BASE_IMAGE:-}"
VM_PROFILE="${VM_PROFILE:-small}"
VM_CPUS="${VM_CPUS:-}"
VM_RAM_MB="${VM_RAM_MB:-}"
VM_DISK_SYSTEM_GB="${VM_DISK_SYSTEM_GB:-}"
VM_DISK_LEDGER_GB="${VM_DISK_LEDGER_GB:-}"
VM_DISK_ACCOUNTS_GB="${VM_DISK_ACCOUNTS_GB:-}"
VM_DISK_SNAPSHOTS_GB="${VM_DISK_SNAPSHOTS_GB:-}"
VM_SSH_PUBLIC_KEY_FILE="${VM_SSH_PUBLIC_KEY_FILE:-$REPO_ROOT/scripts/vm-test/work/id_ed25519.pub}"
VM_SSH_PRIVATE_KEY_FILE="${VM_SSH_PRIVATE_KEY_FILE:-$REPO_ROOT/scripts/vm-test/work/id_ed25519}"
VM_QEMU_EFI="${VM_QEMU_EFI:-}"
HOST_NAME="${HOST_NAME:-}"
POST_METAL_SSH_PORT="${POST_METAL_SSH_PORT:-2522}"
BOOTSTRAP_SSH_PORT="${BOOTSTRAP_SSH_PORT:-2222}"
RETAIN_ON_FAILURE=false
RETAIN_ALWAYS=false
REQUIRE_SSH_SOCKET_PRECONDITION="${REQUIRE_SSH_SOCKET_PRECONDITION:-true}"
ENABLE_VM_TEST_SYSADMIN_NOPASSWD="${ENABLE_VM_TEST_SYSADMIN_NOPASSWD:-true}"

usage() {
  cat <<'EOF'
Usage:
  run-vm-access-validation.sh [options]

Starts a disposable VM, runs verify-vm-access-validation.sh against it, and
tears the VM down automatically unless retention is requested.

Options:
  --workdir <path>                  (default: ./test-harness/work/vm-access-validation)
  --run-id-prefix <id>              (default: vm-access-validation)
  --run-id <id>                     (default: <prefix>-<timestamp>)
  --vm-arch <amd64|arm64>
  --vm-base-image <path>
  --vm-profile <small|medium|large|perf>  (default: small)
  --vm-cpus <n>
  --vm-ram-mb <n>
  --vm-disk-system-gb <n>
  --vm-disk-ledger-gb <n>
  --vm-disk-accounts-gb <n>
  --vm-disk-snapshots-gb <n>
  --vm-ssh-public-key-file <path>
  --vm-ssh-private-key-file <path>
  --vm-qemu-efi <path>
  --host-name <name>
  --post-metal-ssh-port <port>      (default: 2522)
  --bootstrap-ssh-port <port>       (default: 2222)
  --retain-on-failure
  --retain-always
  --no-require-ssh-socket-precondition
  --disable-vm-test-sysadmin-nopasswd
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
    --run-id)
      RUN_ID="${2:-}"
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
    --vm-profile)
      VM_PROFILE="${2:-}"
      shift 2
      ;;
    --vm-cpus)
      VM_CPUS="${2:-}"
      shift 2
      ;;
    --vm-ram-mb)
      VM_RAM_MB="${2:-}"
      shift 2
      ;;
    --vm-disk-system-gb)
      VM_DISK_SYSTEM_GB="${2:-}"
      shift 2
      ;;
    --vm-disk-ledger-gb)
      VM_DISK_LEDGER_GB="${2:-}"
      shift 2
      ;;
    --vm-disk-accounts-gb)
      VM_DISK_ACCOUNTS_GB="${2:-}"
      shift 2
      ;;
    --vm-disk-snapshots-gb)
      VM_DISK_SNAPSHOTS_GB="${2:-}"
      shift 2
      ;;
    --vm-ssh-public-key-file)
      VM_SSH_PUBLIC_KEY_FILE="${2:-}"
      shift 2
      ;;
    --vm-ssh-private-key-file)
      VM_SSH_PRIVATE_KEY_FILE="${2:-}"
      shift 2
      ;;
    --vm-qemu-efi)
      VM_QEMU_EFI="${2:-}"
      shift 2
      ;;
    --host-name)
      HOST_NAME="${2:-}"
      shift 2
      ;;
    --post-metal-ssh-port)
      POST_METAL_SSH_PORT="${2:-}"
      shift 2
      ;;
    --bootstrap-ssh-port)
      BOOTSTRAP_SSH_PORT="${2:-}"
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
    --no-require-ssh-socket-precondition)
      REQUIRE_SSH_SOCKET_PRECONDITION=false
      shift
      ;;
    --disable-vm-test-sysadmin-nopasswd)
      ENABLE_VM_TEST_SYSADMIN_NOPASSWD=false
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

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 3
  fi
}

ensure_ssh_keypair() {
  local private_key="$1"
  local public_key="$2"

  mkdir -p "$(dirname "$private_key")"
  if [[ ! -r "$private_key" ]]; then
    ssh-keygen -t ed25519 -f "$private_key" -N "" >/dev/null
  fi
  if [[ ! -r "$public_key" ]]; then
    ssh-keygen -y -f "$private_key" >"$public_key"
  fi
}

listener_lines_for_port() {
  local port="$1"
  ss -ltnp "( sport = :${port} )" 2>/dev/null | awk 'NR > 1'
}

assert_host_port_available() {
  local port="$1"
  local label="$2"
  local listeners

  listeners="$(listener_lines_for_port "$port")"
  if [[ -n "$listeners" ]]; then
    echo "[vm-access-validation] Cannot start disposable VM: ${label} port ${port} is already in use." >&2
    echo "[vm-access-validation] Free that port or tear down the conflicting VM/process first." >&2
    printf '%s\n' "$listeners" >&2
    exit 4
  fi
}

qemu_log_path() {
  printf '%s\n' "$ADAPTER_WORKDIR/artifacts/vm/$RUN_ID/qemu.log"
}

qemu_pid_path() {
  printf '%s\n' "$ADAPTER_WORKDIR/state/vm/$RUN_ID/qemu.pid"
}

assert_vm_started() {
  local pid_file
  local qemu_log
  local pid=""

  pid_file="$(qemu_pid_path)"
  qemu_log="$(qemu_log_path)"
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
  fi

  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    return 0
  fi

  echo "[vm-access-validation] Disposable VM failed to stay up long enough for SSH readiness checks." >&2
  if [[ -f "$qemu_log" ]]; then
    echo "[vm-access-validation] Recent QEMU log:" >&2
    tail -n 20 "$qemu_log" >&2 || true
  fi
  exit 4
}

cleanup() {
  local exit_code="$1"

  if [[ -n "${VM_RUN_ID:-}" ]]; then
    "$REPO_ROOT/test-harness/targets/vm.sh" artifacts "${VM_TARGET_ARGS[@]}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${VM_RUN_ID:-}" && "$RETAIN_ALWAYS" != "true" ]]; then
    if [[ "$exit_code" -eq 0 || "$RETAIN_ON_FAILURE" != "true" ]]; then
      echo "[vm-access-validation] Stopping disposable VM..." >&2
      "$REPO_ROOT/test-harness/targets/vm.sh" down "${VM_TARGET_ARGS[@]}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "${CASE_DIR:-}" ]]; then
    if [[ "$RETAIN_ALWAYS" == "true" || ( "$exit_code" -ne 0 && "$RETAIN_ON_FAILURE" == "true" ) ]]; then
      echo "[vm-access-validation] Retained artifacts under: $CASE_DIR" >&2
    else
      echo "[vm-access-validation] Artifacts written under: $CASE_DIR" >&2
    fi
  fi
}

trap 'cleanup $?' EXIT

require_cmd jq
require_cmd ss
require_cmd ssh-keygen
require_cmd qemu-img
require_cmd ansible-playbook

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="${RUN_ID_PREFIX}-$(date +%Y%m%d-%H%M%S)"
fi

CASE_DIR="$WORKDIR/$RUN_ID"
ADAPTER_WORKDIR="$CASE_DIR/adapter"
VERIFY_WORKDIR="$CASE_DIR/verify"
mkdir -p "$CASE_DIR" "$ADAPTER_WORKDIR" "$VERIFY_WORKDIR"

ensure_ssh_keypair "$VM_SSH_PRIVATE_KEY_FILE" "$VM_SSH_PUBLIC_KEY_FILE"

assert_host_port_available "$BOOTSTRAP_SSH_PORT" "bootstrap SSH"
assert_host_port_available "$POST_METAL_SSH_PORT" "post-metal SSH"

VM_TARGET_ARGS=(
  --scenario access_validation
  --run-id "$RUN_ID"
  --workdir "$ADAPTER_WORKDIR"
  --vm-profile "$VM_PROFILE"
  --vm-ssh-port "$BOOTSTRAP_SSH_PORT"
  --vm-ssh-port-alt "$POST_METAL_SSH_PORT"
  --vm-ssh-public-key-file "$VM_SSH_PUBLIC_KEY_FILE"
  --vm-ssh-private-key-file "$VM_SSH_PRIVATE_KEY_FILE"
)

if [[ -n "$VM_ARCH" ]]; then
  VM_TARGET_ARGS+=(--vm-arch "$VM_ARCH")
fi
if [[ -n "$VM_BASE_IMAGE" ]]; then
  VM_TARGET_ARGS+=(--vm-base-image "$VM_BASE_IMAGE")
fi
if [[ -n "$VM_CPUS" ]]; then
  VM_TARGET_ARGS+=(--vm-cpus "$VM_CPUS")
fi
if [[ -n "$VM_RAM_MB" ]]; then
  VM_TARGET_ARGS+=(--vm-ram-mb "$VM_RAM_MB")
fi
if [[ -n "$VM_DISK_SYSTEM_GB" ]]; then
  VM_TARGET_ARGS+=(--vm-disk-system-gb "$VM_DISK_SYSTEM_GB")
fi
if [[ -n "$VM_DISK_LEDGER_GB" ]]; then
  VM_TARGET_ARGS+=(--vm-disk-ledger-gb "$VM_DISK_LEDGER_GB")
fi
if [[ -n "$VM_DISK_ACCOUNTS_GB" ]]; then
  VM_TARGET_ARGS+=(--vm-disk-accounts-gb "$VM_DISK_ACCOUNTS_GB")
fi
if [[ -n "$VM_DISK_SNAPSHOTS_GB" ]]; then
  VM_TARGET_ARGS+=(--vm-disk-snapshots-gb "$VM_DISK_SNAPSHOTS_GB")
fi
if [[ -n "$VM_QEMU_EFI" ]]; then
  VM_TARGET_ARGS+=(--vm-qemu-efi "$VM_QEMU_EFI")
fi

echo "[vm-access-validation] Launching disposable VM for run id: $RUN_ID" >&2
"$REPO_ROOT/test-harness/targets/vm.sh" up "${VM_TARGET_ARGS[@]}" >/dev/null
VM_RUN_ID="$RUN_ID"
sleep 1
assert_vm_started

inventory_json="$("$REPO_ROOT/test-harness/targets/vm.sh" inventory "${VM_TARGET_ARGS[@]}")"
inventory_path="$(jq -r '.inventory_path // empty' <<<"$inventory_json")"
if [[ -z "$inventory_path" || ! -r "$inventory_path" ]]; then
  echo "Failed to locate generated inventory for run id $RUN_ID" >&2
  exit 1
fi

echo "[vm-access-validation] Waiting for bootstrap SSH..." >&2
"$REPO_ROOT/test-harness/targets/vm.sh" wait "${VM_TARGET_ARGS[@]}" >/dev/null

verify_args=(
  --inventory "$inventory_path"
  --workdir "$VERIFY_WORKDIR"
  --post-metal-ssh-port "$POST_METAL_SSH_PORT"
)
if [[ -n "$HOST_NAME" ]]; then
  verify_args+=(--host-name "$HOST_NAME")
fi

echo "[vm-access-validation] Running access-validation verifier..." >&2
REQUIRE_SSH_SOCKET_PRECONDITION="$REQUIRE_SSH_SOCKET_PRECONDITION" \
ENABLE_VM_TEST_SYSADMIN_NOPASSWD="$ENABLE_VM_TEST_SYSADMIN_NOPASSWD" \
"$REPO_ROOT/test-harness/scripts/verify-vm-access-validation.sh" \
  "${verify_args[@]}"

echo "[vm-access-validation] Completed successfully." >&2

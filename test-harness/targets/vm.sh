#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=test-harness/lib/common.sh
source "$REPO_ROOT/test-harness/lib/common.sh"

ADAPTER="vm"
ACTION="${1:-}"
shift || true

SCENARIO=""
RUN_ID="$(hvk_default_run_id)"
WORKDIR="$REPO_ROOT/test-harness/work"
TIMEOUT_SECONDS=300
POLL_INTERVAL_SECONDS=5

VM_PROFILE="small"
VM_ARCH="${VM_ARCH:-}"
VM_NAME=""
VM_BASE_IMAGE=""
VM_CPUS=""
VM_RAM_MB=""
VM_DISK_SYSTEM_GB=""
VM_DISK_LEDGER_GB=""
VM_DISK_ACCOUNTS_GB=""
VM_DISK_SNAPSHOTS_GB=""
VM_SSH_PORT=2222
VM_SSH_PORT_ALT=2522
VM_SSH_USER="${VM_SSH_USER:-ubuntu}"
VM_SSH_PUBLIC_KEY_FILE="${VM_SSH_PUBLIC_KEY_FILE:-$REPO_ROOT/scripts/vm-test/work/id_ed25519.pub}"
VM_SSH_PRIVATE_KEY_FILE="${VM_SSH_PRIVATE_KEY_FILE:-$REPO_ROOT/scripts/vm-test/work/id_ed25519}"
VM_QEMU_EFI="${VM_QEMU_EFI:-}"

while (($# > 0)); do
  case "$1" in
    --scenario)
      SCENARIO="${2:-}"
      shift 2
      ;;
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --workdir)
      WORKDIR="${2:-}"
      shift 2
      ;;
    --timeout-seconds)
      TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --poll-interval-seconds)
      POLL_INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    --vm-profile)
      VM_PROFILE="${2:-}"
      shift 2
      ;;
    --vm-arch)
      VM_ARCH="${2:-}"
      shift 2
      ;;
    --vm-name)
      VM_NAME="${2:-}"
      shift 2
      ;;
    --vm-base-image)
      VM_BASE_IMAGE="${2:-}"
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
    --vm-ssh-port)
      VM_SSH_PORT="${2:-}"
      shift 2
      ;;
    --vm-ssh-port-alt)
      VM_SSH_PORT_ALT="${2:-}"
      shift 2
      ;;
    --vm-ssh-user)
      VM_SSH_USER="${2:-}"
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
    *)
      hvk_emit_err_and_exit "$ADAPTER" "${ACTION:-unknown}" "$RUN_ID" "invalid_args" "Unknown option: $1" 2
      ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  hvk_emit_err_and_exit "$ADAPTER" "unknown" "$RUN_ID" "invalid_args" "Missing action" 2
fi

STATE_DIR="$WORKDIR/state/$ADAPTER/$RUN_ID"
ARTIFACT_DIR="$WORKDIR/artifacts/$ADAPTER/$RUN_ID"
VM_WORK_DIR="$STATE_DIR/work"
INVENTORY_PATH="$STATE_DIR/inventory.yml"

hvk_mkdir "$STATE_DIR"
hvk_mkdir "$ARTIFACT_DIR"
hvk_mkdir "$VM_WORK_DIR"

if [[ -z "$VM_ARCH" ]]; then
  case "$(uname -m)" in
    arm64|aarch64) VM_ARCH="arm64" ;;
    *) VM_ARCH="amd64" ;;
  esac
fi

if [[ -z "$VM_NAME" ]]; then
  VM_NAME="hvk-${RUN_ID}"
fi

if [[ -z "$VM_BASE_IMAGE" ]]; then
  VM_BASE_IMAGE="$REPO_ROOT/scripts/vm-test/work/ubuntu-${VM_ARCH}.img"
fi

PROFILE_FILE="$REPO_ROOT/test-harness/profiles/vm/${VM_PROFILE}.env"
if [[ -f "$PROFILE_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$PROFILE_FILE"
fi

VM_CPUS="${VM_CPUS:-${PROFILE_VM_CPUS:-4}}"
VM_RAM_MB="${VM_RAM_MB:-${PROFILE_VM_RAM_MB:-4096}}"
VM_DISK_SYSTEM_GB="${VM_DISK_SYSTEM_GB:-${PROFILE_VM_DISK_SYSTEM_GB:-40}}"
VM_DISK_LEDGER_GB="${VM_DISK_LEDGER_GB:-${PROFILE_VM_DISK_LEDGER_GB:-20}}"
VM_DISK_ACCOUNTS_GB="${VM_DISK_ACCOUNTS_GB:-${PROFILE_VM_DISK_ACCOUNTS_GB:-10}}"
VM_DISK_SNAPSHOTS_GB="${VM_DISK_SNAPSHOTS_GB:-${PROFILE_VM_DISK_SNAPSHOTS_GB:-5}}"

RUN_SCRIPT="$REPO_ROOT/scripts/vm-test/run-qemu-${VM_ARCH}.sh"
if [[ "$VM_ARCH" == "amd64" ]]; then
  RUN_SCRIPT="$REPO_ROOT/scripts/vm-test/run-qemu-amd64.sh"
elif [[ "$VM_ARCH" == "arm64" ]]; then
  RUN_SCRIPT="$REPO_ROOT/scripts/vm-test/run-qemu-arm64.sh"
fi

PID_FILE="$STATE_DIR/qemu.pid"
QEMU_LOG="$ARTIFACT_DIR/qemu.log"

validate_common() {
  hvk_require_cmd jq || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_dependency" "jq not found" 3
}

validate_provisioning() {
  if [[ -z "$SCENARIO" ]]; then
    hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "invalid_args" "Missing required --scenario" 2
  fi
  validate_common
  hvk_require_cmd qemu-img || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_dependency" "qemu-img not found" 3
  hvk_require_cmd ssh || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_dependency" "ssh not found" 3
  hvk_require_cmd ssh-keyscan || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_dependency" "ssh-keyscan not found" 3
  [[ -x "$REPO_ROOT/scripts/vm-test/make-seed.sh" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "Missing executable make-seed.sh" 3
  [[ -x "$REPO_ROOT/scripts/vm-test/create-disks.sh" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "Missing executable create-disks.sh" 3
  [[ -x "$RUN_SCRIPT" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "Missing executable run script: $RUN_SCRIPT" 3
  [[ -x "$REPO_ROOT/scripts/vm-test/wait-for-ssh.sh" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "Missing executable wait-for-ssh.sh" 3
  [[ -r "$VM_BASE_IMAGE" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "VM base image is not readable: $VM_BASE_IMAGE" 3
  [[ -r "$VM_SSH_PUBLIC_KEY_FILE" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "VM SSH public key file is not readable: $VM_SSH_PUBLIC_KEY_FILE" 3
  [[ -r "$VM_SSH_PRIVATE_KEY_FILE" ]] || hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "missing_file" "VM SSH private key file is not readable: $VM_SSH_PRIVATE_KEY_FILE" 3
}

validate() {
  validate_provisioning

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "VM adapter validation passed" \
    "$(jq -cn --arg arch "$VM_ARCH" --arg profile "$VM_PROFILE" --arg base_image "$VM_BASE_IMAGE" '{arch: $arch, profile: $profile, base_image: $base_image}')"
}

up() {
  validate_provisioning >/dev/null
  local ssh_key
  ssh_key="$(cat "$VM_SSH_PUBLIC_KEY_FILE")"

  echo "[$ADAPTER] Creating cloud-init seed..." >&2
  WORK_DIR="$VM_WORK_DIR" "$REPO_ROOT/scripts/vm-test/make-seed.sh" "$VM_NAME" "$ssh_key"

  echo "[$ADAPTER] Creating VM disks..." >&2
  WORK_DIR="$VM_WORK_DIR" \
  VM_DISK_SYSTEM_GB="$VM_DISK_SYSTEM_GB" \
  VM_DISK_LEDGER_GB="$VM_DISK_LEDGER_GB" \
  VM_DISK_ACCOUNTS_GB="$VM_DISK_ACCOUNTS_GB" \
  VM_DISK_SNAPSHOTS_GB="$VM_DISK_SNAPSHOTS_GB" \
  "$REPO_ROOT/scripts/vm-test/create-disks.sh" "$VM_ARCH" "$VM_NAME" "$VM_BASE_IMAGE"

  echo "[$ADAPTER] Starting VM in background..." >&2
  (
    export WORK_DIR="$VM_WORK_DIR"
    export SSH_PORT="$VM_SSH_PORT"
    export SSH_PORT_ALT="$VM_SSH_PORT_ALT"
    export RAM_MB="$VM_RAM_MB"
    export CPUS="$VM_CPUS"
    export QEMU_EFI="$VM_QEMU_EFI"
    nohup "$RUN_SCRIPT" "$VM_NAME" >"$QEMU_LOG" 2>&1 &
    echo $! >"$PID_FILE"
  )

  jq -cn \
    --arg scenario "$SCENARIO" \
    --arg vm_name "$VM_NAME" \
    --arg vm_arch "$VM_ARCH" \
    --arg vm_profile "$VM_PROFILE" \
    --arg vm_base_image "$VM_BASE_IMAGE" \
    --arg vm_work_dir "$VM_WORK_DIR" \
    --arg vm_ssh_user "$VM_SSH_USER" \
    --arg vm_ssh_private_key_file "$VM_SSH_PRIVATE_KEY_FILE" \
    --argjson vm_ssh_port "$VM_SSH_PORT" \
    --argjson vm_ssh_port_alt "$VM_SSH_PORT_ALT" \
    --argjson vm_cpus "$VM_CPUS" \
    --argjson vm_ram_mb "$VM_RAM_MB" \
    --argjson vm_disk_system_gb "$VM_DISK_SYSTEM_GB" \
    --argjson vm_disk_ledger_gb "$VM_DISK_LEDGER_GB" \
    --argjson vm_disk_accounts_gb "$VM_DISK_ACCOUNTS_GB" \
    --argjson vm_disk_snapshots_gb "$VM_DISK_SNAPSHOTS_GB" \
    '{
      scenario: $scenario,
      vm_name: $vm_name,
      vm_arch: $vm_arch,
      vm_profile: $vm_profile,
      vm_base_image: $vm_base_image,
      vm_work_dir: $vm_work_dir,
      vm_ssh_user: $vm_ssh_user,
      vm_ssh_private_key_file: $vm_ssh_private_key_file,
      vm_ssh_port: $vm_ssh_port,
      vm_ssh_port_alt: $vm_ssh_port_alt,
      vm_cpus: $vm_cpus,
      vm_ram_mb: $vm_ram_mb,
      vm_disk_system_gb: $vm_disk_system_gb,
      vm_disk_ledger_gb: $vm_disk_ledger_gb,
      vm_disk_accounts_gb: $vm_disk_accounts_gb,
      vm_disk_snapshots_gb: $vm_disk_snapshots_gb
    }' >"$STATE_DIR/metadata.json"

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "VM started in background" \
    "$(jq -cn --arg pid_file "$PID_FILE" --arg qemu_log "$QEMU_LOG" '{pid_file: $pid_file, qemu_log: $qemu_log}')"
}

inventory() {
  validate_provisioning >/dev/null

  cat >"$INVENTORY_PATH" <<EOF
all:
  hosts:
    vm-local:
      ansible_host: 127.0.0.1
      ansible_port: ${VM_SSH_PORT}
      ansible_user: ${VM_SSH_USER}
      ansible_ssh_private_key_file: ${VM_SSH_PRIVATE_KEY_FILE}
      ansible_become: true
EOF

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "VM inventory generated" \
    "$(jq -cn --arg inventory_path "$INVENTORY_PATH" --argjson hosts "[{\"name\":\"vm-local\",\"ansible_host\":\"127.0.0.1\",\"ansible_port\":$VM_SSH_PORT}]" '{inventory_path: $inventory_path, hosts: $hosts}')"
}

wait_ready() {
  validate_provisioning >/dev/null

  echo "[$ADAPTER] waiting for SSH with timeout=${TIMEOUT_SECONDS}s poll_interval=${POLL_INTERVAL_SECONDS}s..." >&2
  "$REPO_ROOT/scripts/vm-test/wait-for-ssh.sh" "127.0.0.1" "$VM_SSH_PORT" "$TIMEOUT_SECONDS" >/dev/null

  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "VM SSH is reachable" \
    "$(jq -cn --arg host "127.0.0.1" --argjson port "$VM_SSH_PORT" '{host: $host, port: $port}')"
}

down() {
  validate_common >/dev/null
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE")"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
  fi
  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "VM process stopped (if running)"
}

artifacts() {
  validate_common >/dev/null
  if [[ -f "$STATE_DIR/metadata.json" ]]; then
    cp "$STATE_DIR/metadata.json" "$ARTIFACT_DIR/metadata.json"
  fi
  if [[ -f "$PID_FILE" ]]; then
    cp "$PID_FILE" "$ARTIFACT_DIR/qemu.pid"
  fi
  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "VM artifacts collected" \
    "$(jq -cn --arg artifacts_path "$ARTIFACT_DIR" '{artifacts_path: $artifacts_path}')"
}

describe() {
  hvk_json_ok "$ADAPTER" "$ACTION" "$RUN_ID" "VM adapter capabilities" \
    "$(jq -cn '{
      capabilities: {
        supports_destroy: true,
        supports_artifacts: true,
        supports_multi_host: false,
        supports_resource_profiles: true,
        supports_scenario_matrix: true
      }
    }')"
}

case "$ACTION" in
  validate) validate ;;
  up) up ;;
  inventory) inventory ;;
  wait) wait_ready ;;
  down) down ;;
  artifacts) artifacts ;;
  describe) describe ;;
  *)
    hvk_emit_err_and_exit "$ADAPTER" "$ACTION" "$RUN_ID" "invalid_action" "Unsupported action: $ACTION" 2
    ;;
esac

#!/usr/bin/env bash
set -euo pipefail

VM_NAME=${1:-}
WORK_DIR=${WORK_DIR:-"$(pwd)/scripts/vm-test/work"}
SSH_PORT=${SSH_PORT:-2222}
SSH_PORT_ALT=${SSH_PORT_ALT:-2522}
GUEST_SSH_PORT_ALT=${GUEST_SSH_PORT_ALT:-2522}
RAM_MB=${RAM_MB:-4096}
CPUS=${CPUS:-4}
QEMU_EFI=${QEMU_EFI:-}
EXTRA_HOST_FWDS=${EXTRA_HOST_FWDS:-}
VM_NETWORK_BACKEND=${VM_NETWORK_BACKEND:-user}
TAP_IFACE=${TAP_IFACE:-}

if [[ -z "$VM_NAME" ]]; then
  echo "Usage: $0 <vm-name>" >&2
  exit 1
fi

SYSTEM_DISK="$WORK_DIR/${VM_NAME}.qcow2"
LEDGER_DISK="$WORK_DIR/${VM_NAME}-ledger.qcow2"
ACCOUNTS_DISK="$WORK_DIR/${VM_NAME}-accounts.qcow2"
SNAPSHOTS_DISK="$WORK_DIR/${VM_NAME}-snapshots.qcow2"
SEED_ISO="$WORK_DIR/${VM_NAME}-seed.iso"

if [[ -z "$QEMU_EFI" ]]; then
  for candidate in \
    /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
    /usr/local/share/qemu/edk2-aarch64-code.fd; do
    if [[ -f "$candidate" ]]; then
      QEMU_EFI="$candidate"
      break
    fi
  done
fi

EFI_ARGS=()
if [[ -n "$QEMU_EFI" ]]; then
  EFI_ARGS=(-bios "$QEMU_EFI")
else
  echo "Warning: UEFI firmware not found; set QEMU_EFI to edk2-aarch64-code.fd if the VM does not boot." >&2
fi

NET_ARGS=()
case "$VM_NETWORK_BACKEND" in
  user)
    NIC_ARGS="user,model=virtio-net-pci,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${SSH_PORT_ALT}-:${GUEST_SSH_PORT_ALT}"
    if [[ -n "$EXTRA_HOST_FWDS" ]]; then
      NIC_ARGS+=",${EXTRA_HOST_FWDS}"
    fi
    NET_ARGS=(-nic "$NIC_ARGS")
    ;;
  tap)
    if [[ -z "$TAP_IFACE" ]]; then
      echo "TAP_IFACE is required when VM_NETWORK_BACKEND=tap" >&2
      exit 2
    fi
    if [[ -n "$EXTRA_HOST_FWDS" ]]; then
      echo "Warning: EXTRA_HOST_FWDS ignored when VM_NETWORK_BACKEND=tap" >&2
    fi
    NET_ARGS=(
      -netdev "tap,id=net0,ifname=${TAP_IFACE},script=no,downscript=no"
      -device "virtio-net-pci,netdev=net0"
    )
    ;;
  *)
    echo "Unsupported VM_NETWORK_BACKEND: $VM_NETWORK_BACKEND (expected user|tap)" >&2
    exit 2
    ;;
esac

qemu-system-aarch64 \
  -machine virt,accel=hvf \
  -cpu host \
  -smp "$CPUS" \
  -m "$RAM_MB" \
  "${EFI_ARGS[@]}" \
  -drive file="$SYSTEM_DISK",if=virtio \
  -drive file="$LEDGER_DISK",if=virtio \
  -drive file="$ACCOUNTS_DISK",if=virtio \
  -drive file="$SNAPSHOTS_DISK",if=virtio \
  -drive file="$SEED_ISO",media=cdrom \
  "${NET_ARGS[@]}" \
  -serial mon:stdio \
  -nographic

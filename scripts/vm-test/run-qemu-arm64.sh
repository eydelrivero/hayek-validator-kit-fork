#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME=${1:-}
WORK_DIR=${WORK_DIR:-"$SCRIPT_DIR/work"}
SSH_PORT=${SSH_PORT:-2222}
SSH_PORT_ALT=${SSH_PORT_ALT:-2522}
GUEST_SSH_PORT_ALT=${GUEST_SSH_PORT_ALT:-2522}
RAM_MB=${RAM_MB:-4096}
CPUS=${CPUS:-4}
QEMU_EFI=${QEMU_EFI:-}
EXTRA_HOST_FWDS=${EXTRA_HOST_FWDS:-}
VM_NETWORK_BACKEND=${VM_NETWORK_BACKEND:-user}
TAP_IFACE=${TAP_IFACE:-}
VM_MAC_ADDRESS=${VM_MAC_ADDRESS:-}
QEMU_BIN=${QEMU_BIN:-qemu-system-aarch64}
QEMU_ACCEL=${QEMU_ACCEL:-auto}
QEMU_CPU=${QEMU_CPU:-auto}

if [[ -z "$VM_NAME" ]]; then
  echo "Usage: $0 <vm-name>" >&2
  exit 1
fi

SYSTEM_DISK="$WORK_DIR/${VM_NAME}.qcow2"
LEDGER_DISK="$WORK_DIR/${VM_NAME}-ledger.qcow2"
ACCOUNTS_DISK="$WORK_DIR/${VM_NAME}-accounts.qcow2"
SNAPSHOTS_DISK="$WORK_DIR/${VM_NAME}-snapshots.qcow2"
SEED_ISO="$WORK_DIR/${VM_NAME}-seed.iso"
SNAPSHOTS_DRIVE_ARGS=()

if [[ -r "$SNAPSHOTS_DISK" ]]; then
  SNAPSHOTS_DRIVE_ARGS=(-drive file="$SNAPSHOTS_DISK",if=virtio)
fi

HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"
MACHINE_ACCEL="tcg"
CPU_MODEL="max"

case "$HOST_OS" in
  Darwin)
    if [[ "$HOST_ARCH" == "arm64" || "$HOST_ARCH" == "aarch64" ]]; then
      MACHINE_ACCEL="hvf"
      CPU_MODEL="host"
    fi
    ;;
  Linux)
    if [[ "$HOST_ARCH" == "arm64" || "$HOST_ARCH" == "aarch64" ]]; then
      if [[ -r /dev/kvm && -w /dev/kvm ]]; then
        MACHINE_ACCEL="kvm"
        CPU_MODEL="host"
      elif [[ -e /dev/kvm ]]; then
        echo "Warning: /dev/kvm exists but is not accessible to user $(id -un); falling back to slow TCG emulation." >&2
        echo "Hint: add this user to the 'kvm' group (for example: sudo usermod -aG kvm $(id -un)) and start a new login session." >&2
      fi
    fi
    ;;
esac

if [[ "$QEMU_ACCEL" != "auto" ]]; then
  MACHINE_ACCEL="$QEMU_ACCEL"
fi
if [[ "$QEMU_CPU" != "auto" ]]; then
  CPU_MODEL="$QEMU_CPU"
fi

if [[ -z "$QEMU_EFI" ]]; then
  for candidate in \
    /usr/share/AAVMF/AAVMF_CODE.fd \
    /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
    /usr/share/edk2/aarch64/QEMU_EFI.fd \
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
    if [[ -n "$VM_MAC_ADDRESS" ]]; then
      NIC_ARGS+=",mac=${VM_MAC_ADDRESS}"
    fi
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
      -device "virtio-net-pci,netdev=net0${VM_MAC_ADDRESS:+,mac=${VM_MAC_ADDRESS}}"
    )
    ;;
  *)
    echo "Unsupported VM_NETWORK_BACKEND: $VM_NETWORK_BACKEND (expected user|tap)" >&2
    exit 2
    ;;
esac

exec "$QEMU_BIN" \
  -machine "virt,accel=${MACHINE_ACCEL}" \
  -cpu "$CPU_MODEL" \
  -smp "$CPUS" \
  -m "$RAM_MB" \
  "${EFI_ARGS[@]}" \
  -drive file="$SYSTEM_DISK",if=virtio \
  -drive file="$LEDGER_DISK",if=virtio \
  -drive file="$ACCOUNTS_DISK",if=virtio \
  "${SNAPSHOTS_DRIVE_ARGS[@]}" \
  -drive file="$SEED_ISO",media=cdrom \
  "${NET_ARGS[@]}" \
  -serial mon:stdio \
  -nographic

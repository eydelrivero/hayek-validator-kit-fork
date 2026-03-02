#!/usr/bin/env bash
set -euo pipefail

ARCH=${1:-}
VM_NAME=${2:-}
BASE_IMAGE=${3:-}
WORK_DIR=${WORK_DIR:-"$(pwd)/scripts/vm-test/work"}
VM_DISK_SYSTEM_GB=${VM_DISK_SYSTEM_GB:-40}
VM_DISK_LEDGER_GB=${VM_DISK_LEDGER_GB:-20}
VM_DISK_ACCOUNTS_GB=${VM_DISK_ACCOUNTS_GB:-10}
VM_DISK_SNAPSHOTS_GB=${VM_DISK_SNAPSHOTS_GB:-5}

if [[ -z "$ARCH" || -z "$VM_NAME" || -z "$BASE_IMAGE" ]]; then
  echo "Usage: $0 <arch> <vm-name> <base-image-path>" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"

BASE_IMAGE_ABS=$(python3 - "$BASE_IMAGE" <<'PY'
import os, sys
path = sys.argv[1]
print(os.path.abspath(path))
PY
)

if [[ ! -r "$BASE_IMAGE_ABS" ]]; then
  echo "Base image not found or not readable: $BASE_IMAGE_ABS" >&2
  exit 1
fi

SYSTEM_DISK="$WORK_DIR/${VM_NAME}.qcow2"
LEDGER_DISK="$WORK_DIR/${VM_NAME}-ledger.qcow2"
ACCOUNTS_DISK="$WORK_DIR/${VM_NAME}-accounts.qcow2"
SNAPSHOTS_DISK="$WORK_DIR/${VM_NAME}-snapshots.qcow2"

qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE_ABS" "$SYSTEM_DISK" "${VM_DISK_SYSTEM_GB}G"
qemu-img create -f qcow2 "$LEDGER_DISK" "${VM_DISK_LEDGER_GB}G"
qemu-img create -f qcow2 "$ACCOUNTS_DISK" "${VM_DISK_ACCOUNTS_GB}G"
qemu-img create -f qcow2 "$SNAPSHOTS_DISK" "${VM_DISK_SNAPSHOTS_GB}G"

echo "Created disks in $WORK_DIR for $VM_NAME ($ARCH): system=${VM_DISK_SYSTEM_GB}G ledger=${VM_DISK_LEDGER_GB}G accounts=${VM_DISK_ACCOUNTS_GB}G snapshots=${VM_DISK_SNAPSHOTS_GB}G"

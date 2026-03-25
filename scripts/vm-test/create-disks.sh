#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH=${1:-}
VM_NAME=${2:-}
BASE_IMAGE=${3:-}
WORK_DIR=${WORK_DIR:-"$SCRIPT_DIR/work"}
VM_DISK_SYSTEM_GB=${VM_DISK_SYSTEM_GB:-40}
VM_DISK_LEDGER_GB=${VM_DISK_LEDGER_GB:-20}
VM_DISK_ACCOUNTS_GB=${VM_DISK_ACCOUNTS_GB:-10}
VM_DISK_SNAPSHOTS_GB=${VM_DISK_SNAPSHOTS_GB:-0}
VM_DISK_SYSTEM_PARENT=${VM_DISK_SYSTEM_PARENT:-}
VM_DISK_LEDGER_PARENT=${VM_DISK_LEDGER_PARENT:-}
VM_DISK_ACCOUNTS_PARENT=${VM_DISK_ACCOUNTS_PARENT:-}
VM_DISK_SNAPSHOTS_PARENT=${VM_DISK_SNAPSHOTS_PARENT:-}

if [[ -z "$ARCH" || -z "$VM_NAME" ]]; then
  echo "Usage: $0 <arch> <vm-name> [base-image-path]" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"

SYSTEM_DISK="$WORK_DIR/${VM_NAME}.qcow2"
LEDGER_DISK="$WORK_DIR/${VM_NAME}-ledger.qcow2"
ACCOUNTS_DISK="$WORK_DIR/${VM_NAME}-accounts.qcow2"
SNAPSHOTS_DISK="$WORK_DIR/${VM_NAME}-snapshots.qcow2"
SNAPSHOTS_DISK_ENABLED=false

if [[ "$VM_DISK_SNAPSHOTS_GB" =~ ^[0-9]+$ ]] && (( VM_DISK_SNAPSHOTS_GB > 0 )); then
  SNAPSHOTS_DISK_ENABLED=true
fi

parent_overlay_mode=false
if [[ -n "$VM_DISK_SYSTEM_PARENT" || -n "$VM_DISK_LEDGER_PARENT" || -n "$VM_DISK_ACCOUNTS_PARENT" || -n "$VM_DISK_SNAPSHOTS_PARENT" ]]; then
  parent_overlay_mode=true
fi

if [[ "$parent_overlay_mode" == true ]]; then
  for parent_path in \
    "$VM_DISK_SYSTEM_PARENT" \
    "$VM_DISK_LEDGER_PARENT" \
    "$VM_DISK_ACCOUNTS_PARENT"; do
    if [[ -z "$parent_path" ]]; then
      echo "System, ledger, and accounts parent disks must be set when parent overlay mode is enabled." >&2
      exit 1
    fi
    if [[ ! -r "$parent_path" ]]; then
      echo "Parent disk not found or not readable: $parent_path" >&2
      exit 1
    fi
  done

  if [[ "$SNAPSHOTS_DISK_ENABLED" == true ]]; then
    if [[ -z "$VM_DISK_SNAPSHOTS_PARENT" ]]; then
      echo "VM_DISK_SNAPSHOTS_PARENT must be set when snapshots disk overlays are enabled." >&2
      exit 1
    fi
    if [[ ! -r "$VM_DISK_SNAPSHOTS_PARENT" ]]; then
      echo "Parent disk not found or not readable: $VM_DISK_SNAPSHOTS_PARENT" >&2
      exit 1
    fi
  fi

  qemu-img create -f qcow2 -F qcow2 -b "$VM_DISK_SYSTEM_PARENT" "$SYSTEM_DISK" "${VM_DISK_SYSTEM_GB}G"
  qemu-img create -f qcow2 -F qcow2 -b "$VM_DISK_LEDGER_PARENT" "$LEDGER_DISK" "${VM_DISK_LEDGER_GB}G"
  qemu-img create -f qcow2 -F qcow2 -b "$VM_DISK_ACCOUNTS_PARENT" "$ACCOUNTS_DISK" "${VM_DISK_ACCOUNTS_GB}G"
  if [[ "$SNAPSHOTS_DISK_ENABLED" == true ]]; then
    qemu-img create -f qcow2 -F qcow2 -b "$VM_DISK_SNAPSHOTS_PARENT" "$SNAPSHOTS_DISK" "${VM_DISK_SNAPSHOTS_GB}G"
  else
    rm -f "$SNAPSHOTS_DISK"
  fi
else
  if [[ -z "$BASE_IMAGE" ]]; then
    echo "BASE_IMAGE is required when VM_DISK_*_PARENT overlays are not provided." >&2
    exit 1
  fi

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

  qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE_ABS" "$SYSTEM_DISK" "${VM_DISK_SYSTEM_GB}G"
  qemu-img create -f qcow2 "$LEDGER_DISK" "${VM_DISK_LEDGER_GB}G"
  qemu-img create -f qcow2 "$ACCOUNTS_DISK" "${VM_DISK_ACCOUNTS_GB}G"
  if [[ "$SNAPSHOTS_DISK_ENABLED" == true ]]; then
    qemu-img create -f qcow2 "$SNAPSHOTS_DISK" "${VM_DISK_SNAPSHOTS_GB}G"
  else
    rm -f "$SNAPSHOTS_DISK"
  fi
fi

echo "Created disks in $WORK_DIR for $VM_NAME ($ARCH): system=${VM_DISK_SYSTEM_GB}G ledger=${VM_DISK_LEDGER_GB}G accounts=${VM_DISK_ACCOUNTS_GB}G snapshots=${VM_DISK_SNAPSHOTS_GB}G"

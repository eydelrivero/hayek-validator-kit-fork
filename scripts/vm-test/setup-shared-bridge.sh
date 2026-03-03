#!/usr/bin/env bash
set -euo pipefail

BRIDGE_NAME=${VM_BRIDGE_NAME:-br-hvk}
BRIDGE_GATEWAY_CIDR=${VM_BRIDGE_GATEWAY_CIDR:-192.168.100.1/24}
SOURCE_TAP_IFACE=${VM_SOURCE_TAP_IFACE:-tap-hvk-src}
DESTINATION_TAP_IFACE=${VM_DESTINATION_TAP_IFACE:-tap-hvk-dst}
ENTRYPOINT_TAP_IFACE=${ENTRYPOINT_VM_TAP_IFACE:-tap-hvk-ent}

if ! command -v sudo >/dev/null 2>&1; then
  echo "Missing required command: sudo" >&2
  exit 1
fi
if ! command -v ip >/dev/null 2>&1; then
  echo "Missing required command: ip" >&2
  exit 1
fi

ensure_bridge() {
  if ! sudo ip link show "$BRIDGE_NAME" >/dev/null 2>&1; then
    sudo ip link add name "$BRIDGE_NAME" type bridge
  fi
  sudo ip addr replace "$BRIDGE_GATEWAY_CIDR" dev "$BRIDGE_NAME"
  sudo ip link set "$BRIDGE_NAME" up
}

ensure_tap() {
  local tap_iface="$1"

  if ! sudo ip link show "$tap_iface" >/dev/null 2>&1; then
    sudo ip tuntap add dev "$tap_iface" mode tap user "$USER"
  fi
  sudo ip link set "$tap_iface" master "$BRIDGE_NAME"
  sudo ip link set "$tap_iface" up
}

ensure_bridge
ensure_tap "$SOURCE_TAP_IFACE"
ensure_tap "$DESTINATION_TAP_IFACE"
ensure_tap "$ENTRYPOINT_TAP_IFACE"

cat <<EOF
Bridge/tap network is ready.

Export these before running the VM hot-swap harness:
  export VM_NETWORK_MODE=shared-bridge
  export VM_LOCALNET_ENTRYPOINT_MODE=vm
  export VM_BRIDGE_GATEWAY_IP=${BRIDGE_GATEWAY_CIDR%/*}
  export VM_SOURCE_BRIDGE_IP=192.168.100.11
  export VM_DESTINATION_BRIDGE_IP=192.168.100.12
  export ENTRYPOINT_VM_BRIDGE_IP=192.168.100.13
  export VM_SOURCE_TAP_IFACE=${SOURCE_TAP_IFACE}
  export VM_DESTINATION_TAP_IFACE=${DESTINATION_TAP_IFACE}
  export ENTRYPOINT_VM_TAP_IFACE=${ENTRYPOINT_TAP_IFACE}
EOF

#!/usr/bin/env bash
set -euo pipefail

BRIDGE_NAME=${VM_BRIDGE_NAME:-br-hvk}
BRIDGE_GATEWAY_CIDR=${VM_BRIDGE_GATEWAY_CIDR:-192.168.100.1/24}
SOURCE_TAP_IFACE=${VM_SOURCE_TAP_IFACE:-tap-hvk-src}
DESTINATION_TAP_IFACE=${VM_DESTINATION_TAP_IFACE:-tap-hvk-dst}
ENTRYPOINT_TAP_IFACE=${ENTRYPOINT_VM_TAP_IFACE:-tap-hvk-ent}
UPLINK_IFACE=${VM_BRIDGE_UPLINK_IFACE:-}
DNS_SERVER_IPV4=${VM_BRIDGE_DNS_IP:-}
ENABLE_NAT=${VM_BRIDGE_ENABLE_NAT:-true}
BRIDGE_SUBNET_CIDR=${VM_BRIDGE_SUBNET_CIDR:-}

if ! command -v sudo >/dev/null 2>&1; then
  echo "Missing required command: sudo" >&2
  exit 1
fi
if ! command -v ip >/dev/null 2>&1; then
  echo "Missing required command: ip" >&2
  exit 1
fi
if ! command -v iptables >/dev/null 2>&1; then
  echo "Missing required command: iptables" >&2
  exit 1
fi

if [[ -z "$BRIDGE_SUBNET_CIDR" ]]; then
  BRIDGE_SUBNET_CIDR="$(awk -F'[ /]+' 'NR==1 { print $1 "/" $2 }' <<<"$BRIDGE_GATEWAY_CIDR")"
fi

detect_uplink_iface() {
  ip route show default 2>/dev/null | awk '/^default/ { print $5; exit }'
}

detect_dns_server() {
  if command -v resolvectl >/dev/null 2>&1; then
    resolvectl dns "$UPLINK_IFACE" 2>/dev/null | awk '{ for (i = 3; i <= NF; i++) if ($i ~ /^[0-9.]+$/) { print $i; exit } }'
    return 0
  fi

  awk '/^nameserver[[:space:]]+[0-9.]+$/ { print $2; exit }' /etc/resolv.conf 2>/dev/null
}

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

ensure_nat() {
  local subnet_cidr="$1"
  local uplink_iface="$2"

  sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

  sudo iptables -t nat -C POSTROUTING -s "$subnet_cidr" -o "$uplink_iface" -j MASQUERADE 2>/dev/null \
    || sudo iptables -t nat -A POSTROUTING -s "$subnet_cidr" -o "$uplink_iface" -j MASQUERADE
  sudo iptables -C FORWARD -i "$BRIDGE_NAME" -o "$uplink_iface" -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -i "$BRIDGE_NAME" -o "$uplink_iface" -j ACCEPT
  sudo iptables -C FORWARD -i "$uplink_iface" -o "$BRIDGE_NAME" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -i "$uplink_iface" -o "$BRIDGE_NAME" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
}

if [[ -z "$UPLINK_IFACE" ]]; then
  UPLINK_IFACE="$(detect_uplink_iface)"
fi
if [[ -z "$DNS_SERVER_IPV4" ]]; then
  DNS_SERVER_IPV4="$(detect_dns_server)"
fi

if [[ "$ENABLE_NAT" == "true" ]] && [[ -z "$UPLINK_IFACE" ]]; then
  echo "Unable to detect uplink interface for shared-bridge NAT. Set VM_BRIDGE_UPLINK_IFACE." >&2
  exit 1
fi

ensure_bridge
ensure_tap "$SOURCE_TAP_IFACE"
ensure_tap "$DESTINATION_TAP_IFACE"
ensure_tap "$ENTRYPOINT_TAP_IFACE"
if [[ "$ENABLE_NAT" == "true" ]]; then
  ensure_nat "$BRIDGE_SUBNET_CIDR" "$UPLINK_IFACE"
fi

cat <<EOF
Bridge/tap network is ready.

Host bridge settings:
  bridge: ${BRIDGE_NAME}
  gateway: ${BRIDGE_GATEWAY_CIDR}
  subnet: ${BRIDGE_SUBNET_CIDR}
  uplink: ${UPLINK_IFACE:-not configured}
  dns: ${DNS_SERVER_IPV4:-${BRIDGE_GATEWAY_CIDR%/*}}
  nat: ${ENABLE_NAT}

Note:
  NAT/forward rules are applied to the live host firewall. Re-run this helper
  after reboot unless you persist equivalent rules separately.

Export these before running the VM hot-swap harness:
  export VM_NETWORK_MODE=shared-bridge
  export VM_LOCALNET_ENTRYPOINT_MODE=vm
  export VM_BRIDGE_GATEWAY_IP=${BRIDGE_GATEWAY_CIDR%/*}
  export VM_BRIDGE_DNS_IP=${DNS_SERVER_IPV4:-${BRIDGE_GATEWAY_CIDR%/*}}
  export VM_SOURCE_BRIDGE_IP=192.168.100.11
  export VM_DESTINATION_BRIDGE_IP=192.168.100.12
  export ENTRYPOINT_VM_BRIDGE_IP=192.168.100.13
  export VM_SOURCE_TAP_IFACE=${SOURCE_TAP_IFACE}
  export VM_DESTINATION_TAP_IFACE=${DESTINATION_TAP_IFACE}
  export ENTRYPOINT_VM_TAP_IFACE=${ENTRYPOINT_TAP_IFACE}
EOF

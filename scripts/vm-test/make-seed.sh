#!/usr/bin/env bash
set -euo pipefail

VM_NAME=${1:-}
SSH_PUBLIC_KEY=${2:-}
WORK_DIR=${WORK_DIR:-"$(pwd)/scripts/vm-test/work"}
TEMPLATE_DIR=${TEMPLATE_DIR:-"$(pwd)/scripts/vm-test/cloud-init"}
VM_STATIC_IPV4=${VM_STATIC_IPV4:-}
VM_GATEWAY_IPV4=${VM_GATEWAY_IPV4:-}
VM_DNS_IPV4=${VM_DNS_IPV4:-}
VM_CIDR_PREFIX=${VM_CIDR_PREFIX:-24}
VM_NETWORK_MATCH_NAME=${VM_NETWORK_MATCH_NAME:-e*}

if [[ -z "$VM_NAME" || -z "$SSH_PUBLIC_KEY" ]]; then
  echo "Usage: $0 <vm-name> <ssh-public-key>" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"

USER_DATA_TMP="$WORK_DIR/user-data"
META_DATA_TMP="$WORK_DIR/meta-data"
SEED_ISO="$WORK_DIR/${VM_NAME}-seed.iso"
NETWORK_CONFIG_TMP="$WORK_DIR/network-config"

sed "s#__SSH_PUBLIC_KEY__#${SSH_PUBLIC_KEY}#" "$TEMPLATE_DIR/user-data" > "$USER_DATA_TMP"
sed "s#__VM_NAME__#${VM_NAME}#" "$TEMPLATE_DIR/meta-data" > "$META_DATA_TMP"

NETWORK_CONFIG_ARGS=()
if [[ -n "$VM_STATIC_IPV4" && -n "$VM_GATEWAY_IPV4" ]]; then
  dns_value="$VM_DNS_IPV4"
  if [[ -z "$dns_value" ]]; then
    dns_value="$VM_GATEWAY_IPV4"
  fi
  cat > "$NETWORK_CONFIG_TMP" <<EOF
version: 2
ethernets:
  primary:
    match:
      name: "${VM_NETWORK_MATCH_NAME}"
    dhcp4: false
    addresses:
      - ${VM_STATIC_IPV4}/${VM_CIDR_PREFIX}
    routes:
      - to: default
        via: ${VM_GATEWAY_IPV4}
    nameservers:
      addresses:
        - ${dns_value}
EOF
  NETWORK_CONFIG_ARGS=("$NETWORK_CONFIG_TMP")
fi

if command -v cloud-localds >/dev/null 2>&1; then
  cloud_localds_args=("$SEED_ISO" "$USER_DATA_TMP" "$META_DATA_TMP")
  if ((${#NETWORK_CONFIG_ARGS[@]} > 0)); then
    cloud_localds_args+=(-N "${NETWORK_CONFIG_ARGS[0]}")
  fi
  cloud-localds "${cloud_localds_args[@]}"
elif command -v xorriso >/dev/null 2>&1; then
  xorriso -as mkisofs -output "$SEED_ISO" -volid cidata -joliet -rock "$USER_DATA_TMP" "$META_DATA_TMP" "${NETWORK_CONFIG_ARGS[@]}"
else
  echo "Missing cloud-localds or xorriso. Install one of them to build the seed ISO." >&2
  exit 1
fi

echo "Created seed ISO at $SEED_ISO"

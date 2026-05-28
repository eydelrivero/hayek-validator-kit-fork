#!/bin/bash

set -euo pipefail

is_physical_nic() {
  local nic_name="$1"

  case "${nic_name}" in
    lo|veth*|docker*|br-*|virbr*|tun*|tap*|ifb*)
      return 1
      ;;
  esac

  [[ -d "/sys/class/net/${nic_name}/device" ]]
}

ring_value() {
  local section="$1"
  local field="$2"

  awk -v section="${section}" -v field="${field}" '
    $0 ~ section { in_section = 1; next }
    in_section && /^[^[:space:]]/ && $0 !~ /^[[:space:]]*(RX|Tx|TX|Rx):/ { in_section = 0 }
    in_section {
      token = $1
      sub(/:$/, "", token)
      if (tolower(token) == tolower(field)) {
        print $2
        exit
      }
    }
  '
}

is_uint() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

for nic_path in /sys/class/net/*; do
  nic_name="$(basename "${nic_path}")"

  if ! is_physical_nic "${nic_name}"; then
    continue
  fi

  ring_info="$(ethtool -g "${nic_name}" 2>/dev/null || true)"
  if [[ -z "${ring_info}" ]]; then
    echo "Skipping ${nic_name}: ring buffer information unavailable"
    continue
  fi

  rx_max="$(ring_value "Pre-set maximums:" "RX" <<< "${ring_info}")"
  rx_current="$(ring_value "Current hardware settings:" "RX" <<< "${ring_info}")"
  tx_max="$(ring_value "Pre-set maximums:" "TX" <<< "${ring_info}")"
  tx_current="$(ring_value "Current hardware settings:" "TX" <<< "${ring_info}")"

  # Empty or nonnumeric ring values are expected on some drivers and are ignored.
  set_args=()
  if is_uint "${rx_max}" && is_uint "${rx_current}" && ((rx_current < rx_max)); then
    set_args+=(rx "${rx_max}")
  fi

  if is_uint "${tx_max}" && is_uint "${tx_current}" && ((tx_current < tx_max)); then
    set_args+=(tx "${tx_max}")
  fi

  if [[ ${#set_args[@]} -eq 0 ]]; then
    echo "No ring buffer changes needed for ${nic_name}"
    continue
  fi

  echo "Setting ${nic_name} ring buffers: ${set_args[*]}"
  if ! ethtool -G "${nic_name}" "${set_args[@]}"; then
    echo "Warning: failed to set ring buffers for ${nic_name}" >&2
  fi
done

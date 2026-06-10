#!/bin/bash

set -euo pipefail

SYS_CLASS_NET="${SYS_CLASS_NET:-/sys/class/net}"
ETHTOOL_BIN="${ETHTOOL_BIN:-ethtool}"

is_physical_nic() {
  local nic_name="$1"

  case "${nic_name}" in
    lo|veth*|docker*|br-*|virbr*|tun*|tap*|ifb*)
      return 1
      ;;
  esac

  [[ -d "${SYS_CLASS_NET}/${nic_name}/device" ]]
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

is_power_of_two() {
  local value="$1"
  is_uint "${value}" && ((value > 0)) && (((value & (value - 1)) == 0))
}

largest_power_of_two_at_or_below() {
  local value="$1"
  local power=1

  if ! is_uint "${value}" || ((value < 1)); then
    echo ""
    return
  fi

  while ((power * 2 <= value)); do
    power=$((power * 2))
  done

  echo "${power}"
}

preferred_power_of_two_ring() {
  local max_value="$1"

  if ! is_uint "${max_value}" || ((max_value < 1)); then
    echo ""
    return
  fi

  if is_power_of_two "${max_value}"; then
    echo "${max_value}"
    return
  fi

  # Some NICs report 511 while accepting 512; other non-power-of-two maxima round down.
  if ((max_value == 511)); then
    echo 512
    return
  fi

  largest_power_of_two_at_or_below "${max_value}"
}

apply_ring_value() {
  local nic_name="$1"
  local direction="$2"
  local current_value="$3"
  local max_value="$4"
  local desired_value fallback_value

  if ! is_uint "${max_value}" || ! is_uint "${current_value}"; then
    echo "Skipping ${nic_name} ${direction}: nonnumeric current/max ring values (current=${current_value:-unknown}, max=${max_value:-unknown})"
    return 0
  fi

  desired_value="$(preferred_power_of_two_ring "${max_value}")"
  if [[ -z "${desired_value}" ]]; then
    echo "Skipping ${nic_name} ${direction}: unable to derive power-of-two target from max=${max_value}"
    return 0
  fi

  if ((current_value >= desired_value)); then
    echo "No ring buffer increase needed for ${nic_name} ${direction}: current=${current_value}, max=${max_value}, target=${desired_value}"
    return 0
  fi

  echo "Setting ${nic_name} ${direction} ring: current=${current_value}, max=${max_value}, target=${desired_value}"
  if "${ETHTOOL_BIN}" -G "${nic_name}" "${direction}" "${desired_value}"; then
    echo "Set ${nic_name} ${direction} ring to ${desired_value}"
    return 0
  fi

  fallback_value=$((desired_value / 2))
  if ((fallback_value < 1)); then
    echo "Warning: failed to set ${nic_name} ${direction} ring to ${desired_value}; no lower power-of-two fallback is available" >&2
    return 0
  fi

  if ((current_value >= fallback_value)); then
    echo "Keeping ${nic_name} ${direction} ring at current=${current_value} after target=${desired_value} was rejected; fallback=${fallback_value} would not increase the ring"
    return 0
  fi

  echo "Retrying ${nic_name} ${direction} ring with fallback=${fallback_value} after target=${desired_value} was rejected"
  if "${ETHTOOL_BIN}" -G "${nic_name}" "${direction}" "${fallback_value}"; then
    echo "Set ${nic_name} ${direction} ring to fallback ${fallback_value}"
  else
    echo "Warning: failed to set ${nic_name} ${direction} ring to target=${desired_value} or fallback=${fallback_value}" >&2
  fi

  return 0
}

shopt -s nullglob
for nic_path in "${SYS_CLASS_NET}"/*; do
  nic_name="$(basename "${nic_path}")"

  if ! is_physical_nic "${nic_name}"; then
    continue
  fi

  ring_info="$("${ETHTOOL_BIN}" -g "${nic_name}" 2>/dev/null || true)"
  if [[ -z "${ring_info}" ]]; then
    echo "Skipping ${nic_name}: ring buffer information unavailable"
    continue
  fi

  rx_max="$(ring_value "Pre-set maximums:" "RX" <<< "${ring_info}")"
  rx_current="$(ring_value "Current hardware settings:" "RX" <<< "${ring_info}")"
  tx_max="$(ring_value "Pre-set maximums:" "TX" <<< "${ring_info}")"
  tx_current="$(ring_value "Current hardware settings:" "TX" <<< "${ring_info}")"

  apply_ring_value "${nic_name}" rx "${rx_current}" "${rx_max}"
  apply_ring_value "${nic_name}" tx "${tx_current}" "${tx_max}"
done

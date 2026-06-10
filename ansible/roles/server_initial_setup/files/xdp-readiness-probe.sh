#!/bin/bash
set -u

# Environment overrides:
#   XDP_SYS_CLASS_NET=/sys/class/net
#   XDP_SYS_CPU=/sys/devices/system/cpu
#   XDP_PROC_MOUNTS=/proc/mounts
#   XDP_PROC_NET_BONDING=/proc/net/bonding
#   XDP_ROUTE_IFACE=
#   XDP_TARGET_INTERFACE=  # explicit escape hatch for indirect interface topologies
#   XDP_CPU_CORES=1
#   XDP_POH_CORE=
#   XDP_ZERO_COPY_EXPECTED=true
#   XDP_UNSUPPORTED_DRIVERS=virtio_net
#   XDP_ZERO_COPY_UNSUPPORTED_DRIVERS=bnxt_en ice
#
# Output contract: emits key=value lines only, always exits 0, and reports
# readiness through probe_status=ok|degraded plus warnings=<csv>.
SYS_CLASS_NET="${XDP_SYS_CLASS_NET:-/sys/class/net}"
SYS_CPU="${XDP_SYS_CPU:-/sys/devices/system/cpu}"
PROC_MOUNTS="${XDP_PROC_MOUNTS:-/proc/mounts}"
PROC_NET_BONDING="${XDP_PROC_NET_BONDING:-/proc/net/bonding}"
OVERRIDE_IFACE="${XDP_TARGET_INTERFACE:-}"
XDP_CORES_RAW="${XDP_CPU_CORES:-1}"
POH_CORE_RAW="${XDP_POH_CORE:-}"
ZERO_COPY_EXPECTED="${XDP_ZERO_COPY_EXPECTED:-true}"
UNSUPPORTED_DRIVERS="${XDP_UNSUPPORTED_DRIVERS:-virtio_net}"
ZERO_COPY_UNSUPPORTED_DRIVERS="${XDP_ZERO_COPY_UNSUPPORTED_DRIVERS:-bnxt_en ice}"
CPU_LIST_EXPANSION_LIMIT=4096
LSCPU_MAP=""
have_tool() {
  command -v "$1" >/dev/null 2>&1
}
append_csv() {
  local current="$1"
  local value="$2"
  if [[ -z "${current}" ]]; then
    printf '%s' "${value}"
  else
    printf '%s,%s' "${current}" "${value}"
  fi
}
contains_list_word() {
  local needle="$1"
  local values="$2"
  local value
  values="${values//,/ }"
  read -r -a words <<< "${values}"
  for value in "${words[@]}"; do
    [[ "${value}" == "${needle}" ]] && return 0
  done
  return 1
}
get_route_iface() {
  local iface
  if [[ -n "${XDP_ROUTE_IFACE:-}" ]]; then
    echo "${XDP_ROUTE_IFACE}"
    return
  fi
  iface="$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
  if [[ -z "${iface}" ]]; then
    iface="$(ip route show default 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
  fi
  echo "${iface}"
}
is_physical_iface() {
  local iface="$1"
  [[ -n "${iface}" && -e "${SYS_CLASS_NET}/${iface}/device/driver" ]]
}
resolve_lower_iface() {
  local iface="$1"
  local lower_names=()
  local lower_count=0
  local path lower
  shopt -s nullglob
  for path in "${SYS_CLASS_NET}/${iface}"/lower_*; do
    lower="$(basename "${path}" | sed 's/^lower_//')"
    lower_names+=("${lower}")
    lower_count=$((lower_count + 1))
  done
  shopt -u nullglob
  if [[ "${lower_count}" == "1" ]]; then
    echo "${lower_names[0]}"
  fi
}
resolve_bond_slave() {
  local bond="$1"
  local bond_file="${PROC_NET_BONDING}/${bond}"
  local active active_lc first_up first
  [[ -r "${bond_file}" ]] || return 0
  active="$(awk -F': ' '/^Currently Active Slave:/ {print $2; exit}' "${bond_file}")"
  active="$(printf '%s' "${active}" | xargs)"
  active_lc="$(printf '%s' "${active}" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "${active}" && "${active_lc}" != "none" ]]; then
    echo "bond_active_slave:${active}"
    return
  fi
  first_up="$(awk -F': ' '
    /^Slave Interface:/ {iface=$2}
    /^MII Status:/ && iface != "" && $2 == "up" {print iface; exit}
  ' "${bond_file}")"
  if [[ -n "${first_up}" ]]; then
    echo "bond_first_up_slave:${first_up}"
    return
  fi
  first="$(awk -F': ' '/^Slave Interface:/ {print $2; exit}' "${bond_file}")"
  if [[ -n "${first}" ]]; then
    echo "bond_first_slave:${first}"
  fi
}
expand_cpu_list() {
  local raw="$1"
  local out="" part start end i count=0
  if [[ -z "${raw}" || "${raw}" == *, || "${raw}" == ,* || "${raw}" == *,,* ]]; then
    return 1
  fi
  IFS=',' read -r -a parts <<< "${raw}"
  for part in "${parts[@]}"; do
    if [[ "${part}" =~ ^[0-9]+$ ]]; then
      out="${out} ${part}"
      count=$((count + 1))
    elif [[ "${part}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      if (( start > end )); then
        return 1
      fi
      for ((i=start; i<=end; i++)); do
        out="${out} ${i}"
        count=$((count + 1))
        if (( count > CPU_LIST_EXPANSION_LIMIT )); then
          return 1
        fi
      done
    else
      return 1
    fi
    if (( count > CPU_LIST_EXPANSION_LIMIT )); then
      return 1
    fi
  done
  echo "${out}" | xargs
}
normalize_csv() {
  local value="$1"
  if [[ -z "${value}" ]]; then
    echo ""
    return
  fi
  echo "${value}" | tr ' ' '\n' | sed '/^$/d' | awk '!seen[$0]++' | paste -sd, -
}
get_cpu_node() {
  local cpu="$1"
  awk -F, -v c="${cpu}" 'BEGIN { found=0 } /^[^#]/ && $1 == c { print $2; found=1; exit } END { if (!found) print "NA" }' <<< "${LSCPU_MAP}"
}
is_bpffs_mounted() {
  [[ -r "${PROC_MOUNTS}" ]] || return 1
  awk '$2 == "/sys/fs/bpf" && $3 == "bpf" { found=1 } END { exit found ? 0 : 1 }' "${PROC_MOUNTS}"
}
MISSING_TOOLS=""
for tool in ip ethtool lscpu; do
  if ! have_tool "${tool}"; then
    MISSING_TOOLS="$(append_csv "${MISSING_TOOLS}" "${tool}")"
  fi
done
ROUTE_IFACE=""
SELECTED_IFACE=""
SELECTION_SOURCE="unresolved"
SELECTION_REASON="interface_unresolved"
ZERO_COPY_SAFE=false
ZERO_COPY_REASON="not_evaluated"
if have_tool ip; then
  ROUTE_IFACE="$(get_route_iface)"
fi
if [[ -n "${OVERRIDE_IFACE}" ]]; then
  SELECTED_IFACE="${OVERRIDE_IFACE}"
  SELECTION_SOURCE="override"
  SELECTION_REASON="operator_override"
elif [[ -z "${ROUTE_IFACE}" ]]; then
  SELECTION_REASON="route_interface_unresolved"
elif [[ -r "${PROC_NET_BONDING}/${ROUTE_IFACE}" ]]; then
  bond_result="$(resolve_bond_slave "${ROUTE_IFACE}")"
  if [[ "${bond_result}" == bond_active_slave:* ]]; then
    SELECTED_IFACE="$(printf '%s' "${bond_result}" | cut -d: -f2-)"
    SELECTION_SOURCE="bond_active_slave"
    SELECTION_REASON="bond_active_slave"
  elif [[ "${bond_result}" == bond_first_up_slave:* || "${bond_result}" == bond_first_slave:* ]]; then
    SELECTED_IFACE="$(printf '%s' "${bond_result}" | cut -d: -f2-)"
    SELECTION_SOURCE="bond_first_slave"
    SELECTION_REASON="bond_first_slave"
  else
    SELECTION_REASON="bond_slave_unresolved"
  fi
elif is_physical_iface "${ROUTE_IFACE}"; then
  SELECTED_IFACE="${ROUTE_IFACE}"
  SELECTION_SOURCE="route_physical"
  SELECTION_REASON="route_interface_is_physical"
else
  lower_iface="$(resolve_lower_iface "${ROUTE_IFACE}")"
  if [[ -n "${lower_iface}" ]]; then
    SELECTED_IFACE="${lower_iface}"
    SELECTION_SOURCE="lower_device"
    SELECTION_REASON="single_lower_device"
  else
    SELECTION_REASON="no_unambiguous_physical_interface"
  fi
fi
IFACE_PRESENT=false
IFACE_DRIVER_LINK_PRESENT=false
IFACE_DRIVER_NAME=""
if [[ -n "${SELECTED_IFACE}" && -e "${SYS_CLASS_NET}/${SELECTED_IFACE}" ]]; then
  IFACE_PRESENT=true
fi
if [[ -n "${SELECTED_IFACE}" && -e "${SYS_CLASS_NET}/${SELECTED_IFACE}/device/driver" ]]; then
  IFACE_DRIVER_LINK_PRESENT=true
  driver_link="$(readlink -f "${SYS_CLASS_NET}/${SELECTED_IFACE}/device/driver" 2>/dev/null || true)"
  if [[ -n "${driver_link}" ]]; then
    IFACE_DRIVER_NAME="$(basename "${driver_link}")"
  fi
fi
if [[ "${ZERO_COPY_EXPECTED}" != "true" ]]; then
  ZERO_COPY_SAFE=true
  ZERO_COPY_REASON="not_expected"
elif [[ -z "${SELECTED_IFACE}" || "${IFACE_PRESENT}" != "true" || "${IFACE_DRIVER_LINK_PRESENT}" != "true" ]]; then
  ZERO_COPY_REASON="physical_interface_unresolved"
elif [[ "${SELECTION_SOURCE}" == bond_* ]]; then
  ZERO_COPY_REASON="route_uses_bond"
elif [[ -n "${IFACE_DRIVER_NAME}" ]] && contains_list_word "${IFACE_DRIVER_NAME}" "${ZERO_COPY_UNSUPPORTED_DRIVERS}"; then
  ZERO_COPY_REASON="driver_unsupported_${IFACE_DRIVER_NAME}"
else
  ZERO_COPY_SAFE=true
  ZERO_COPY_REASON="direct_physical_interface"
fi
KERNEL_SEMVER="$(uname -r | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+' || true)"
if [[ -z "${KERNEL_SEMVER}" ]]; then
  KERNEL_SEMVER="0.0.0"
fi
BPFFS_PRESENT=false
if is_bpffs_mounted; then
  BPFFS_PRESENT=true
fi
NUMA_STATUS="skip"
NUMA_REASON="lscpu_missing"
POH_NODE=""
XDP_CORES=""
XDP_NODES=""
SAME_CPU=""
SAME_SMT=""
SAME_NODE=""
if have_tool lscpu; then
  if [[ -z "${POH_CORE_RAW}" ]]; then
    NUMA_REASON="poh_core_unset"
  elif ! [[ "${POH_CORE_RAW}" =~ ^[0-9]+$ ]]; then
    NUMA_REASON="poh_core_invalid"
  else
    LSCPU_MAP="$(lscpu -p=CPU,NODE 2>/dev/null || true)"
    if [[ -z "${LSCPU_MAP}" ]]; then
      NUMA_REASON="lscpu_topology_unavailable"
    else
      XDP_CORES_SPACE="$(expand_cpu_list "${XDP_CORES_RAW}" || true)"
      if [[ -z "${XDP_CORES_SPACE}" ]]; then
        NUMA_REASON="xdp_cpu_list_invalid"
      else
        SAME_CPU=false
        SAME_SMT=false
        SAME_NODE=false
        UNIQUE_NODE_COUNT="$(awk -F, '/^[^#]/ && $2 != "" && $2 != "-" {print $2}' <<< "${LSCPU_MAP}" | sort -u | wc -l | tr -d ' ')"
        if [[ -z "${UNIQUE_NODE_COUNT}" ]]; then
          UNIQUE_NODE_COUNT=0
        fi
        SINGLE_NUMA=false
        if (( UNIQUE_NODE_COUNT <= 1 )); then
          SINGLE_NUMA=true
        fi
        POH_NODE="$(get_cpu_node "${POH_CORE_RAW}")"
        if [[ -z "${POH_NODE}" || "${POH_NODE}" == "NA" || "${POH_NODE}" == "-" ]]; then
          NUMA_REASON="poh_node_unknown"
        else
          XDP_NODES_SPACE=""
          XDP_NODE_UNKNOWN=false
          for cpu in ${XDP_CORES_SPACE}; do
            node="$(get_cpu_node "${cpu}")"
            if [[ -z "${node}" || "${node}" == "NA" || "${node}" == "-" ]]; then
              XDP_NODE_UNKNOWN=true
            else
              XDP_NODES_SPACE="${XDP_NODES_SPACE} ${node}"
            fi
            if [[ "${cpu}" == "${POH_CORE_RAW}" ]]; then
              SAME_CPU=true
            fi
          done
          XDP_CORES="$(normalize_csv "${XDP_CORES_SPACE}")"
          XDP_NODES="$(normalize_csv "${XDP_NODES_SPACE}")"
          if [[ "${XDP_NODE_UNKNOWN}" == "true" ]]; then
            NUMA_REASON="xdp_node_unknown"
          else
            for node in ${XDP_NODES_SPACE}; do
              if [[ "${node}" == "${POH_NODE}" ]]; then
                SAME_NODE=true
              fi
            done
            POH_SIBLINGS_RAW="$(cat "${SYS_CPU}/cpu${POH_CORE_RAW}/topology/thread_siblings_list" 2>/dev/null || true)"
            if [[ -n "${POH_SIBLINGS_RAW}" ]]; then
              POH_SIBLINGS_SPACE="$(expand_cpu_list "${POH_SIBLINGS_RAW}" || true)"
              if [[ -n "${POH_SIBLINGS_SPACE}" ]]; then
                for cpu in ${XDP_CORES_SPACE}; do
                  for sibling in ${POH_SIBLINGS_SPACE}; do
                    if [[ "${cpu}" == "${sibling}" && "${cpu}" != "${POH_CORE_RAW}" ]]; then
                      SAME_SMT=true
                    fi
                  done
                done
              fi
            fi
            WARN_REASONS=""
            if [[ "${SAME_CPU}" == "true" ]]; then
              WARN_REASONS="$(append_csv "${WARN_REASONS}" "same_cpu")"
            fi
            if [[ "${SAME_SMT}" == "true" ]]; then
              WARN_REASONS="$(append_csv "${WARN_REASONS}" "shared_physical_core")"
            fi
            if [[ "${SAME_NODE}" == "true" && "${SINGLE_NUMA}" != "true" ]]; then
              WARN_REASONS="$(append_csv "${WARN_REASONS}" "same_numa_node")"
            fi
            if [[ -n "${WARN_REASONS}" ]]; then
              NUMA_STATUS="warn"
              NUMA_REASON="${WARN_REASONS}"
            elif [[ "${SINGLE_NUMA}" == "true" ]]; then
              NUMA_STATUS="skip"
              NUMA_REASON="single_numa_host"
            else
              NUMA_STATUS="ok"
              NUMA_REASON="none"
            fi
          fi
        fi
      fi
    fi
  fi
fi
WARNINGS=""
if [[ -n "${MISSING_TOOLS}" ]]; then
  WARNINGS="$(append_csv "${WARNINGS}" "missing_tools_${MISSING_TOOLS//,/_}")"
fi
if [[ -z "${SELECTED_IFACE}" ]]; then
  WARNINGS="$(append_csv "${WARNINGS}" "xdp_interface_unresolved")"
elif [[ "${IFACE_PRESENT}" != "true" ]]; then
  WARNINGS="$(append_csv "${WARNINGS}" "xdp_interface_missing_${SELECTED_IFACE}")"
elif [[ "${IFACE_DRIVER_LINK_PRESENT}" != "true" ]]; then
  WARNINGS="$(append_csv "${WARNINGS}" "xdp_interface_driver_unavailable_${SELECTED_IFACE}")"
fi
if [[ -n "${IFACE_DRIVER_NAME}" ]] && contains_list_word "${IFACE_DRIVER_NAME}" "${UNSUPPORTED_DRIVERS}"; then
  WARNINGS="$(append_csv "${WARNINGS}" "xdp_driver_unsupported_${IFACE_DRIVER_NAME}")"
fi
if [[ "${BPFFS_PRESENT}" != "true" ]]; then
  WARNINGS="$(append_csv "${WARNINGS}" "bpffs_unavailable")"
fi
if [[ "${ZERO_COPY_EXPECTED}" == "true" && "${ZERO_COPY_SAFE}" != "true" ]]; then
  WARNINGS="$(append_csv "${WARNINGS}" "xdp_zero_copy_${ZERO_COPY_REASON}")"
fi
if [[ "${NUMA_STATUS}" == "warn" ]]; then
  WARNINGS="$(append_csv "${WARNINGS}" "numa_${NUMA_REASON//,/_}")"
fi
if [[ -n "${WARNINGS}" ]]; then
  PROBE_STATUS="degraded"
else
  PROBE_STATUS="ok"
fi
echo "probe_status=${PROBE_STATUS}"
echo "route_iface=${ROUTE_IFACE}"
echo "selected_iface=${SELECTED_IFACE}"
echo "selection_source=${SELECTION_SOURCE}"
echo "selection_reason=${SELECTION_REASON}"
echo "iface_present=${IFACE_PRESENT}"
echo "iface_driver_link_present=${IFACE_DRIVER_LINK_PRESENT}"
echo "iface_driver_name=${IFACE_DRIVER_NAME}"
echo "kernel_semver=${KERNEL_SEMVER}"
echo "bpffs_present=${BPFFS_PRESENT}"
echo "missing_tools=${MISSING_TOOLS}"
echo "zero_copy_safe=${ZERO_COPY_SAFE}"
echo "zero_copy_reason=${ZERO_COPY_REASON}"
echo "numa_status=${NUMA_STATUS}"
echo "numa_reason=${NUMA_REASON}"
echo "numa_poh_core=${POH_CORE_RAW}"
echo "numa_poh_node=${POH_NODE}"
echo "numa_xdp_cores=${XDP_CORES}"
echo "numa_xdp_nodes=${XDP_NODES}"
echo "numa_same_cpu=${SAME_CPU}"
echo "numa_same_smt=${SAME_SMT}"
echo "numa_same_node=${SAME_NODE}"
echo "warnings=${WARNINGS}"

#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RING_SCRIPT="${REPO_ROOT}/ansible/roles/server_initial_setup/files/set-ethtool-ring-buffers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SYS_CLASS_NET="${TMP_DIR}/sys/class/net"
FAKE_BIN="${TMP_DIR}/bin"
LOG_FILE="${TMP_DIR}/ethtool.log"
OUT_FILE="${TMP_DIR}/ring-test.out"
ERR_FILE="${TMP_DIR}/ring-test.err"
mkdir -p "${SYS_CLASS_NET}/eno1/device" "${FAKE_BIN}"

cat > "${FAKE_BIN}/ethtool" <<'EOF'
#!/bin/bash
set -euo pipefail

LOG_FILE="${FAKE_ETHTOOL_LOG}"
MODE="${FAKE_RING_MODE}"

if [[ "${1:-}" == "-g" ]]; then
  case "${MODE}" in
    max511)
      cat <<'RINGS'
Ring parameters for eno1:
Pre-set maximums:
RX:		511
TX:		511
Current hardware settings:
RX:		128
TX:		128
RINGS
      ;;
    max511_current511)
      cat <<'RINGS'
Ring parameters for eno1:
Pre-set maximums:
RX:		511
TX:		511
Current hardware settings:
RX:		511
TX:		511
RINGS
      ;;
    max512)
      cat <<'RINGS'
Ring parameters for eno1:
Pre-set maximums:
RX:		512
TX:		512
Current hardware settings:
RX:		128
TX:		128
RINGS
      ;;
    max1023)
      cat <<'RINGS'
Ring parameters for eno1:
Pre-set maximums:
RX:		1023
TX:		1023
Current hardware settings:
RX:		128
TX:		128
RINGS
      ;;
    max1023_current900)
      cat <<'RINGS'
Ring parameters for eno1:
Pre-set maximums:
RX:		1023
TX:		1023
Current hardware settings:
RX:		900
TX:		900
RINGS
      ;;
    max1)
      cat <<'RINGS'
Ring parameters for eno1:
Pre-set maximums:
RX:		1
TX:		1
Current hardware settings:
RX:		0
TX:		0
RINGS
      ;;
    nonnumeric)
      cat <<'RINGS'
Ring parameters for eno1:
Pre-set maximums:
RX:		n/a
TX:		n/a
Current hardware settings:
RX:		n/a
TX:		n/a
RINGS
      ;;
    unsupported)
      exit 1
      ;;
    *)
      echo "unknown FAKE_RING_MODE=${MODE}" >&2
      exit 2
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "-G" ]]; then
  echo "$*" >> "${LOG_FILE}"
  if [[ "${FAKE_REJECT_512:-false}" == "true" && "${4:-}" == "512" ]]; then
    exit 1
  fi
  if [[ "${FAKE_REJECT_256:-false}" == "true" && "${4:-}" == "256" ]]; then
    exit 1
  fi
  if [[ "${FAKE_REJECT_1:-false}" == "true" && "${4:-}" == "1" ]]; then
    exit 1
  fi
  exit 0
fi

exit 2
EOF
chmod +x "${FAKE_BIN}/ethtool"

run_case() {
  local mode="$1"
  local reject_512="$2"
  local reject_256="${3:-false}"
  local reject_1="${4:-false}"
  : > "${LOG_FILE}"
  : > "${OUT_FILE}"
  : > "${ERR_FILE}"
  FAKE_RING_MODE="${mode}" \
    FAKE_REJECT_512="${reject_512}" \
    FAKE_REJECT_256="${reject_256}" \
    FAKE_REJECT_1="${reject_1}" \
    FAKE_ETHTOOL_LOG="${LOG_FILE}" \
    SYS_CLASS_NET="${SYS_CLASS_NET}" \
    ETHTOOL_BIN="${FAKE_BIN}/ethtool" \
    "${RING_SCRIPT}" >"${OUT_FILE}" 2>"${ERR_FILE}"
}

assert_log_contains() {
  local expected="$1"
  if ! grep -Fq -- "${expected}" "${LOG_FILE}"; then
    echo "Expected ethtool log to contain: ${expected}" >&2
    echo "Actual log:" >&2
    cat "${LOG_FILE}" >&2
    exit 1
  fi
}

assert_log_not_contains() {
  local unexpected="$1"
  if grep -Fq -- "${unexpected}" "${LOG_FILE}"; then
    echo "Expected ethtool log not to contain: ${unexpected}" >&2
    echo "Actual log:" >&2
    cat "${LOG_FILE}" >&2
    exit 1
  fi
}

assert_log_empty() {
  if [[ -s "${LOG_FILE}" ]]; then
    echo "Expected empty ethtool log, got:" >&2
    cat "${LOG_FILE}" >&2
    exit 1
  fi
}

assert_err_contains() {
  local expected="$1"
  if ! grep -Fq -- "${expected}" "${ERR_FILE}"; then
    echo "Expected stderr to contain: ${expected}" >&2
    echo "Actual stderr:" >&2
    cat "${ERR_FILE}" >&2
    exit 1
  fi
}

run_case_expect_success() {
  local mode="$1"
  local reject_512="$2"
  local reject_256="${3:-false}"
  local reject_1="${4:-false}"
  if ! run_case "${mode}" "${reject_512}" "${reject_256}" "${reject_1}"; then
    echo "Expected ring script to exit successfully for mode=${mode}" >&2
    cat "${ERR_FILE}" >&2
    exit 1
  fi
}

run_case_expect_success max511 true
assert_log_contains "-G eno1 rx 512"
assert_log_contains "-G eno1 rx 256"
assert_log_contains "-G eno1 tx 512"
assert_log_contains "-G eno1 tx 256"

run_case_expect_success max511 true true
assert_log_contains "-G eno1 rx 512"
assert_log_contains "-G eno1 rx 256"
assert_log_contains "-G eno1 tx 512"
assert_log_contains "-G eno1 tx 256"
assert_err_contains "failed to set eno1 rx ring to target=512 or fallback=256"
assert_err_contains "failed to set eno1 tx ring to target=512 or fallback=256"

run_case_expect_success max511_current511 true
assert_log_contains "-G eno1 rx 512"
assert_log_not_contains "-G eno1 rx 256"
assert_log_contains "-G eno1 tx 512"
assert_log_not_contains "-G eno1 tx 256"

run_case_expect_success max512 false
assert_log_contains "-G eno1 rx 512"
assert_log_contains "-G eno1 tx 512"

run_case_expect_success max512 true
assert_log_contains "-G eno1 rx 512"
assert_log_contains "-G eno1 rx 256"
assert_log_contains "-G eno1 tx 512"
assert_log_contains "-G eno1 tx 256"

run_case_expect_success max1023 false
assert_log_contains "-G eno1 rx 512"
assert_log_contains "-G eno1 tx 512"
assert_log_not_contains "-G eno1 rx 1024"
assert_log_not_contains "-G eno1 tx 1024"

run_case_expect_success max1023_current900 false
assert_log_empty

run_case_expect_success max1 false false true
assert_log_contains "-G eno1 rx 1"
assert_log_contains "-G eno1 tx 1"
assert_err_contains "no lower power-of-two fallback is available"

run_case_expect_success nonnumeric false
assert_log_empty

run_case_expect_success unsupported false
assert_log_empty

echo "set-ethtool-ring-buffers tests passed"

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=test-harness/lib/disposable_host_common.sh
source "$REPO_ROOT/test-harness/lib/disposable_host_common.sh"

WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work/latitude-role-canary}"
RUN_ID_PREFIX="${RUN_ID_PREFIX:-latitude-role-canary}"
RUN_ID="${RUN_ID:-}"
MODE="${MODE:-agave-cli}"
OPERATOR_NAME="${LATITUDE_OPERATOR_NAME:-}"
OPERATOR_SSH_PUBLIC_KEY_FILE="${LATITUDE_OPERATOR_SSH_PUBLIC_KEY_FILE:-}"
OPERATOR_SSH_PRIVATE_KEY_FILE="${LATITUDE_OPERATOR_SSH_PRIVATE_KEY_FILE:-}"
PLAN="${LATITUDE_PLAN:-m4-metal-small}"
PROJECT="${PROJECT:-Automated Provisioning}"
SSH_USER="${SSH_USER:-ubuntu}"
HOST_NAME="${HOST_NAME:-}"
POST_METAL_SSH_PORT="${POST_METAL_SSH_PORT:-2522}"
AUTHORIZED_IPS_INPUT="${AUTHORIZED_IPS_INPUT:-}"
RETAIN_ON_FAILURE=false
RETAIN_ALWAYS=false

usage() {
  cat <<'EOF'
Usage:
  run-latitude-role-canary.sh [options]

Provisions one disposable Latitude host, runs the requested role canary flow,
and tears the host down automatically unless retention is requested.

Options:
  --workdir <path>                      (default: ./test-harness/work/latitude-role-canary)
  --run-id-prefix <id>                  (default: latitude-role-canary)
  --run-id <id>                         (default: <prefix>-<timestamp>)
  --mode <rust|agave-cli|jito-cli|agave-validator|jito-validator>
  --operator-name <name>                (required)
  --operator-ssh-public-key-file <path> (required)
  --operator-ssh-private-key-file <path> (required)
  --plan <slug>                         (default: m4-metal-small)
  --project <name>                      (default: Automated Provisioning)
  --ssh-user <name>                     (default: ubuntu)
  --host-name <name>                    (default: unset)
  --authorized-ips-csv <path>           (default: auto-generate from current public IP)
  --retain-on-failure
  --retain-always
EOF
}

while (($# > 0)); do
  case "$1" in
    --workdir)
      WORKDIR="${2:-}"
      shift 2
      ;;
    --run-id-prefix)
      RUN_ID_PREFIX="${2:-}"
      shift 2
      ;;
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --operator-name)
      OPERATOR_NAME="${2:-}"
      shift 2
      ;;
    --operator-ssh-public-key-file)
      OPERATOR_SSH_PUBLIC_KEY_FILE="${2:-}"
      shift 2
      ;;
    --operator-ssh-private-key-file)
      OPERATOR_SSH_PRIVATE_KEY_FILE="${2:-}"
      shift 2
      ;;
    --plan)
      PLAN="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --ssh-user)
      SSH_USER="${2:-}"
      shift 2
      ;;
    --host-name)
      HOST_NAME="${2:-}"
      shift 2
      ;;
    --authorized-ips-csv)
      AUTHORIZED_IPS_INPUT="${2:-}"
      shift 2
      ;;
    --retain-on-failure)
      RETAIN_ON_FAILURE=true
      shift
      ;;
    --retain-always)
      RETAIN_ALWAYS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

cleanup() {
  local exit_code="$1"

  if [[ -n "${LATITUDE_RUN_ID:-}" ]]; then
    "$REPO_ROOT/test-harness/targets/latitude.sh" artifacts "${LATITUDE_TARGET_ARGS[@]}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${LATITUDE_RUN_ID:-}" && "$RETAIN_ALWAYS" != "true" ]]; then
    if [[ "$exit_code" -eq 0 || "$RETAIN_ON_FAILURE" != "true" ]]; then
      echo "[latitude-role-canary] Tearing down disposable bare-metal host..." >&2
      "$REPO_ROOT/test-harness/targets/latitude.sh" down "${LATITUDE_TARGET_ARGS[@]}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "${CASE_DIR:-}" ]]; then
    if [[ "$RETAIN_ALWAYS" == "true" || ( "$exit_code" -ne 0 && "$RETAIN_ON_FAILURE" == "true" ) ]]; then
      echo "[latitude-role-canary] Retained artifacts under: $CASE_DIR" >&2
    else
      echo "[latitude-role-canary] Artifacts written under: $CASE_DIR" >&2
    fi
  fi
}

trap 'cleanup $?' EXIT

th_require_cmd jq
th_require_cmd ansible-playbook

if [[ -z "$OPERATOR_NAME" ]]; then
  echo "Missing required option: --operator-name" >&2
  exit 2
fi
if [[ -z "$OPERATOR_SSH_PUBLIC_KEY_FILE" || ! -r "$OPERATOR_SSH_PUBLIC_KEY_FILE" ]]; then
  echo "Missing readable operator public key file: $OPERATOR_SSH_PUBLIC_KEY_FILE" >&2
  exit 2
fi
if [[ -z "$OPERATOR_SSH_PRIVATE_KEY_FILE" || ! -r "$OPERATOR_SSH_PRIVATE_KEY_FILE" ]]; then
  echo "Missing readable operator private key file: $OPERATOR_SSH_PRIVATE_KEY_FILE" >&2
  exit 2
fi
if [[ -n "$AUTHORIZED_IPS_INPUT" ]]; then
  AUTHORIZED_IPS_INPUT="$(th_resolve_path "$AUTHORIZED_IPS_INPUT" "$(pwd)")"
  [[ -r "$AUTHORIZED_IPS_INPUT" ]] || { echo "Authorized IPs CSV is not readable: $AUTHORIZED_IPS_INPUT" >&2; exit 2; }
fi

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="${RUN_ID_PREFIX}-$(date +%Y%m%d-%H%M%S)"
fi

CASE_DIR="$WORKDIR/$RUN_ID"
ADAPTER_WORKDIR="$CASE_DIR/adapter"
VERIFY_WORKDIR="$CASE_DIR/verify"
mkdir -p "$CASE_DIR" "$ADAPTER_WORKDIR" "$VERIFY_WORKDIR"

LATITUDE_TARGET_ARGS=(
  --scenario "$MODE"
  --run-id "$RUN_ID"
  --workdir "$ADAPTER_WORKDIR"
  --operator-name "$OPERATOR_NAME"
  --operator-ssh-public-key-file "$OPERATOR_SSH_PUBLIC_KEY_FILE"
  --operator-ssh-private-key-file "$OPERATOR_SSH_PRIVATE_KEY_FILE"
  --plan "$PLAN"
  --project "$PROJECT"
  --ssh-user "$SSH_USER"
)

echo "[latitude-role-canary] Launching disposable Latitude host for run id: $RUN_ID" >&2
"$REPO_ROOT/test-harness/targets/latitude.sh" up "${LATITUDE_TARGET_ARGS[@]}" >/dev/null
LATITUDE_RUN_ID="$RUN_ID"

inventory_json="$("$REPO_ROOT/test-harness/targets/latitude.sh" inventory "${LATITUDE_TARGET_ARGS[@]}")"
inventory_path="$(jq -r '.inventory_path // empty' <<<"$inventory_json")"
if [[ -z "$inventory_path" || ! -r "$inventory_path" ]]; then
  echo "Failed to locate generated Latitude inventory for run id $RUN_ID" >&2
  exit 1
fi

echo "[latitude-role-canary] Waiting for bootstrap SSH..." >&2
"$REPO_ROOT/test-harness/targets/latitude.sh" wait "${LATITUDE_TARGET_ARGS[@]}" >/dev/null

verify_args=(
  --inventory "$inventory_path"
  --workdir "$VERIFY_WORKDIR"
  --mode "$MODE"
  --post-metal-ssh-port "$POST_METAL_SSH_PORT"
  --operator-ssh-public-key-file "$OPERATOR_SSH_PUBLIC_KEY_FILE"
)
if [[ -n "$HOST_NAME" ]]; then
  verify_args+=(--host-name "$HOST_NAME")
fi
if [[ -n "$AUTHORIZED_IPS_INPUT" ]]; then
  verify_args+=(--authorized-ips-csv "$AUTHORIZED_IPS_INPUT")
fi

echo "[latitude-role-canary] Running role canary verifier..." >&2
ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD="${ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD:-true}" \
"$REPO_ROOT/test-harness/scripts/verify-latitude-role-canary.sh" \
  "${verify_args[@]}"

echo "[latitude-role-canary] Completed successfully." >&2

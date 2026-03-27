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
PROJECT="${PROJECT:-ZZZ HVK Test Harness}"
SSH_USER="${SSH_USER:-ubuntu}"
HOST_NAME="${HOST_NAME:-}"
POST_METAL_SSH_PORT="${POST_METAL_SSH_PORT:-2522}"
AUTHORIZED_IPS_INPUT="${AUTHORIZED_IPS_INPUT:-}"
SOLANA_CLUSTER="${SOLANA_CLUSTER:-}"
AGAVE_VERSION="${AGAVE_VERSION:-}"
JITO_VERSION="${JITO_VERSION:-}"
JITO_VERSION_PATCH="${JITO_VERSION_PATCH:-}"
VALIDATOR_NAME="${VALIDATOR_NAME:-}"
VALIDATOR_TYPE="${VALIDATOR_TYPE:-}"
USE_OFFICIAL_REPO=false
ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT=false
RETAIN_ON_FAILURE=false
RETAIN_ALWAYS=false

print_retained_server_destroy_commands() {
  local state_dir="$ADAPTER_WORKDIR/state/latitude/$RUN_ID"
  local server_id_file="$state_dir/server_id.txt"
  local server_id=""

  if [[ ! -r "$server_id_file" ]]; then
    return 0
  fi

  server_id="$(<"$server_id_file")"
  if [[ -z "$server_id" ]]; then
    return 0
  fi

  cat >&2 <<EOF
[latitude-role-canary] Destroy retained server directly:
./bare-metal/latitudesh/destroy_latitude_server.sh \\
  --server-id $server_id \\
  --project "$PROJECT"

[latitude-role-canary] Or via the harness wrapper:
./test-harness/targets/latitude.sh down \\
  --scenario "$MODE" \\
  --run-id "$RUN_ID" \\
  --workdir "$ADAPTER_WORKDIR" \\
  --operator-name "$OPERATOR_NAME" \\
  --operator-ssh-public-key-file "$OPERATOR_SSH_PUBLIC_KEY_FILE" \\
  --operator-ssh-private-key-file "$OPERATOR_SSH_PRIVATE_KEY_FILE"
EOF
}

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
  --project <name>                      (default: ZZZ HVK Test Harness)
  --ssh-user <name>                     (default: ubuntu)
  --host-name <name>                    (default: unset)
  --solana-cluster <name>               (default: verify script default)
  --agave-version <semver>              (default: verify script default)
  --jito-version <semver>               (default: verify script default)
  --jito-version-patch <suffix>         (default: verify script default)
  --validator-name <name>               (default: verify script default)
  --validator-type <primary|hot-spare>  (default: verify script default)
  --use-official-repo                   (default: use team forked repos)
  --allow-unconventional-testnet-two-disk-layout
                                        Force the special Latitude-safe testnet two-disk layout
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
    --solana-cluster)
      SOLANA_CLUSTER="${2:-}"
      shift 2
      ;;
    --agave-version)
      AGAVE_VERSION="${2:-}"
      shift 2
      ;;
    --jito-version)
      JITO_VERSION="${2:-}"
      shift 2
      ;;
    --jito-version-patch)
      JITO_VERSION_PATCH="${2:-}"
      shift 2
      ;;
    --validator-name)
      VALIDATOR_NAME="${2:-}"
      shift 2
      ;;
    --validator-type)
      VALIDATOR_TYPE="${2:-}"
      shift 2
      ;;
    --use-official-repo)
      USE_OFFICIAL_REPO=true
      shift
      ;;
    --allow-unconventional-testnet-two-disk-layout)
      ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT=true
      shift
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
      print_retained_server_destroy_commands
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
if [[ -n "$SOLANA_CLUSTER" ]]; then
  verify_args+=(--solana-cluster "$SOLANA_CLUSTER")
fi
if [[ -n "$AGAVE_VERSION" ]]; then
  verify_args+=(--agave-version "$AGAVE_VERSION")
fi
if [[ -n "$JITO_VERSION" ]]; then
  verify_args+=(--jito-version "$JITO_VERSION")
fi
if [[ -n "$JITO_VERSION_PATCH" ]]; then
  verify_args+=(--jito-version-patch "$JITO_VERSION_PATCH")
fi
if [[ -n "$VALIDATOR_NAME" ]]; then
  verify_args+=(--validator-name "$VALIDATOR_NAME")
fi
if [[ -n "$VALIDATOR_TYPE" ]]; then
  verify_args+=(--validator-type "$VALIDATOR_TYPE")
fi
if [[ "$USE_OFFICIAL_REPO" == "true" ]]; then
  verify_args+=(--use-official-repo)
fi
if [[ "$ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT" == "true" ]]; then
  verify_args+=(--allow-unconventional-testnet-two-disk-layout)
fi
if [[ -n "$AUTHORIZED_IPS_INPUT" ]]; then
  verify_args+=(--authorized-ips-csv "$AUTHORIZED_IPS_INPUT")
fi

echo "[latitude-role-canary] Running role canary verifier..." >&2
ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD="${ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD:-true}" \
"$REPO_ROOT/test-harness/scripts/verify-latitude-role-canary.sh" \
  "${verify_args[@]}"

echo "[latitude-role-canary] Completed successfully." >&2

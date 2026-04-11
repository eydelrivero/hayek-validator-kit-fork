#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=test-harness/lib/disposable_host_common.sh
source "$REPO_ROOT/test-harness/lib/disposable_host_common.sh"

WORKDIR="${WORKDIR:-$REPO_ROOT/test-harness/work/latitude-combined-canary}"
RUN_ID_PREFIX="${RUN_ID_PREFIX:-latitude-combined-canary}"
RUN_ID="${RUN_ID:-}"
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
declare -a MODES=()

usage() {
  cat <<'EOF'
Usage:
  run-latitude-combined-canary.sh [options]

Provision one disposable Latitude bare-metal host, run L2 access-validation,
then reuse the same host for one or more L3 role canaries before teardown.

Options:
  --workdir <path>                      (default: ./test-harness/work/latitude-combined-canary)
  --run-id-prefix <id>                  (default: latitude-combined-canary)
  --run-id <id>                         (default: <prefix>-<timestamp>)
  --mode <rust|agave-cli|jito-cli|agave-validator|jito-validator>
                                        Repeatable. Default: rust, agave-cli, jito-cli
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
[latitude-combined-canary] Destroy retained server directly:
./bare-metal/latitudesh/destroy_latitude_server.sh \\
  --server-id $server_id \\
  --project "$PROJECT"

[latitude-combined-canary] Or via the harness wrapper:
./test-harness/targets/latitude.sh down \\
  --scenario "combined_canary" \\
  --run-id "$RUN_ID" \\
  --workdir "$ADAPTER_WORKDIR" \\
  --operator-name "$OPERATOR_NAME" \\
  --operator-ssh-public-key-file "$OPERATOR_SSH_PUBLIC_KEY_FILE" \\
  --operator-ssh-private-key-file "$OPERATOR_SSH_PRIVATE_KEY_FILE"
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
      MODES+=("${2:-}")
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
  local teardown_failed=false

  if [[ -n "${LATITUDE_RUN_ID:-}" ]]; then
    "$REPO_ROOT/test-harness/targets/latitude.sh" artifacts "${LATITUDE_TARGET_ARGS[@]}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${LATITUDE_RUN_ID:-}" && "$RETAIN_ALWAYS" != "true" ]]; then
    if [[ "$exit_code" -eq 0 || "$RETAIN_ON_FAILURE" != "true" ]]; then
      echo "[latitude-combined-canary] Tearing down disposable bare-metal host..." >&2
      if ! "$REPO_ROOT/test-harness/targets/latitude.sh" down "${LATITUDE_TARGET_ARGS[@]}"; then
        teardown_failed=true
        if [[ "$exit_code" -eq 0 ]]; then
          echo "[latitude-combined-canary] ERROR: automatic teardown failed after a successful run." >&2
          print_retained_server_destroy_commands
          exit_code=1
        else
          echo "[latitude-combined-canary] WARNING: teardown failed after the main run already failed." >&2
          print_retained_server_destroy_commands
        fi
      fi
    fi
  fi

  if [[ -n "${CASE_DIR:-}" ]]; then
    if [[ "$RETAIN_ALWAYS" == "true" || ( "$exit_code" -ne 0 && "$RETAIN_ON_FAILURE" == "true" ) || "$teardown_failed" == "true" ]]; then
      echo "[latitude-combined-canary] Retained artifacts under: $CASE_DIR" >&2
    else
      echo "[latitude-combined-canary] Artifacts written under: $CASE_DIR" >&2
    fi
  fi

  return "$exit_code"
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

if ((${#MODES[@]} == 0)); then
  MODES=(rust agave-cli jito-cli)
fi

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="${RUN_ID_PREFIX}-$(date +%Y%m%d-%H%M%S)"
fi

CASE_DIR="$WORKDIR/$RUN_ID"
ADAPTER_WORKDIR="$CASE_DIR/adapter"
ACCESS_WORKDIR="$CASE_DIR/access-validation"
ROLE_WORKDIR="$CASE_DIR/role-canary"
mkdir -p "$CASE_DIR" "$ADAPTER_WORKDIR" "$ACCESS_WORKDIR" "$ROLE_WORKDIR"

LATITUDE_TARGET_ARGS=(
  --scenario combined_canary
  --run-id "$RUN_ID"
  --workdir "$ADAPTER_WORKDIR"
  --operator-name "$OPERATOR_NAME"
  --operator-ssh-public-key-file "$OPERATOR_SSH_PUBLIC_KEY_FILE"
  --operator-ssh-private-key-file "$OPERATOR_SSH_PRIVATE_KEY_FILE"
  --plan "$PLAN"
  --project "$PROJECT"
  --ssh-user "$SSH_USER"
)

echo "[latitude-combined-canary] Launching disposable Latitude host for run id: $RUN_ID" >&2
"$REPO_ROOT/test-harness/targets/latitude.sh" up "${LATITUDE_TARGET_ARGS[@]}" >/dev/null
LATITUDE_RUN_ID="$RUN_ID"

inventory_json="$("$REPO_ROOT/test-harness/targets/latitude.sh" inventory "${LATITUDE_TARGET_ARGS[@]}")"
inventory_path="$(jq -r '.inventory_path // empty' <<<"$inventory_json")"
if [[ -z "$inventory_path" || ! -r "$inventory_path" ]]; then
  echo "Failed to locate generated Latitude inventory for run id $RUN_ID" >&2
  exit 1
fi

echo "[latitude-combined-canary] Waiting for bootstrap SSH..." >&2
"$REPO_ROOT/test-harness/targets/latitude.sh" wait "${LATITUDE_TARGET_ARGS[@]}" >/dev/null

access_args=(
  --inventory "$inventory_path"
  --workdir "$ACCESS_WORKDIR"
  --post-metal-ssh-port "$POST_METAL_SSH_PORT"
  --operator-ssh-public-key-file "$OPERATOR_SSH_PUBLIC_KEY_FILE"
)
if [[ -n "$HOST_NAME" ]]; then
  access_args+=(--host-name "$HOST_NAME")
fi
if [[ -n "$AUTHORIZED_IPS_INPUT" ]]; then
  access_args+=(--authorized-ips-csv "$AUTHORIZED_IPS_INPUT")
fi

echo "[latitude-combined-canary] Running L2 access-validation..." >&2
ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD="${ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD:-true}" \
"$REPO_ROOT/test-harness/scripts/verify-latitude-access-validation.sh" \
  "${access_args[@]}"

POST_METAL_INVENTORY="$ACCESS_WORKDIR/inventory.sysadmin.yml"
if [[ ! -r "$POST_METAL_INVENTORY" ]]; then
  echo "Missing post-metal inventory after access-validation: $POST_METAL_INVENTORY" >&2
  exit 1
fi

for mode in "${MODES[@]}"; do
  mode_workdir="$ROLE_WORKDIR/$mode"
  mkdir -p "$mode_workdir"
  role_args=(
    --post-metal-only
    --inventory "$POST_METAL_INVENTORY"
    --workdir "$mode_workdir"
    --mode "$mode"
    --post-metal-ssh-port "$POST_METAL_SSH_PORT"
    --operator-ssh-public-key-file "$OPERATOR_SSH_PUBLIC_KEY_FILE"
  )
  if [[ -n "$HOST_NAME" ]]; then
    role_args+=(--host-name "$HOST_NAME")
  fi
  if [[ -n "$AUTHORIZED_IPS_INPUT" ]]; then
    role_args+=(--authorized-ips-csv "$AUTHORIZED_IPS_INPUT")
  fi
  if [[ -n "$SOLANA_CLUSTER" ]]; then
    role_args+=(--solana-cluster "$SOLANA_CLUSTER")
  fi
  if [[ -n "$AGAVE_VERSION" ]]; then
    role_args+=(--agave-version "$AGAVE_VERSION")
  fi
  if [[ -n "$JITO_VERSION" ]]; then
    role_args+=(--jito-version "$JITO_VERSION")
  fi
  if [[ -n "$JITO_VERSION_PATCH" ]]; then
    role_args+=(--jito-version-patch "$JITO_VERSION_PATCH")
  fi
  if [[ -n "$VALIDATOR_NAME" ]]; then
    role_args+=(--validator-name "$VALIDATOR_NAME")
  fi
  if [[ -n "$VALIDATOR_TYPE" ]]; then
    role_args+=(--validator-type "$VALIDATOR_TYPE")
  fi
  if [[ "$USE_OFFICIAL_REPO" == "true" ]]; then
    role_args+=(--use-official-repo)
  fi
  if [[ "$ALLOW_UNCONVENTIONAL_TESTNET_TWO_DISK_LAYOUT" == "true" ]]; then
    role_args+=(--allow-unconventional-testnet-two-disk-layout)
  fi

  echo "[latitude-combined-canary] Running L3 role canary mode: $mode" >&2
  ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD="${ENABLE_DISPOSABLE_SYSADMIN_NOPASSWD:-true}" \
  "$REPO_ROOT/test-harness/scripts/verify-latitude-role-canary.sh" \
    "${role_args[@]}"
done

printf '%s\n' "${MODES[@]}" >"$CASE_DIR/modes.txt"
echo "[latitude-combined-canary] Completed successfully." >&2

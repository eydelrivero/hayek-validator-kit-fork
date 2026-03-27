#!/usr/bin/env bash

# Provision a bare-metal server at Latitude.sh using the lsh CLI.
# This script can:
# - Ensure the target project exists
# - Ensure the operator SSH key exists in the project
# - Reuse an existing server by hostname or create a new one
# - Wait until the server is active and export the public IP
# - Run optional post-provision checks over SSH

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./provision_latitude_server.sh \
    --operator-name <name> \
    --operator-ssh-public-key "<ssh-pub-key>" \
    [--hostname <hostname>] \
    [--plan <plan-slug>] \
    [--dry-run] \
    [--skip-post-checks]

Options:
  --operator-name              Required. Used for hostname and SSH key naming.
  --operator-ssh-public-key    Required. Public key to upload/reuse in Latitude.
  --hostname                   Optional. Exact hostname to create. Safer for harness use.
  --plan                       Optional. Defaults to m4-metal-small.
  --dry-run                    Optional. Show create command and exit before provisioning.
  --skip-post-checks           Optional. Skip SSH post-provision validations.
  -h, --help                   Show this help.

Environment variables:
  PROJECT                      Latitude project name (default: "ZZZ HVK Test Harness")
  OS                           Latitude OS slug (default: ubuntu_24_04_x64_lts)
  HOSTNAME_SUFFIX              Hostname suffix (default: test-server)
  PROJECT_DESCRIPTION_SENTINEL Sentinel required on the project description (default: "managed-by-hvk-test-harness")
  PROJECT_ENVIRONMENT          Expected Latitude project environment (default: Development)
  ALLOW_PROJECT_CREATE_IF_MISSING
                               Set to true to create the harness project if absent (default: false)
  DANGEROUS_PROJECT_NAMES_REGEX
                               Refuse to operate on matching project names
                               (default: "^(Automated Provisioning|Solana Validator)$")
  PREFERRED_SITES_CSV          Comma-separated site preference order (default: FRA,NYC)
  WAIT_MAX_POLLS               Server status polls before timeout (default: 60)
  WAIT_INTERVAL_SECONDS        Seconds between server status polls (default: 30)
  SSH_USER                     SSH user for post checks (default: ubuntu)
  SSH_PRIVATE_KEY              Optional private key path for post checks
  SSH_WAIT_POLLS               SSH reachability polls (default: 30)
  SSH_WAIT_INTERVAL_SECONDS    Seconds between SSH polls (default: 10)
  OUTPUT_IP_FILE               Where to write resulting IP (default: ~/.config/latitude_server_ip.txt)
  OUTPUT_SERVER_ID_FILE        Optional path to write resulting server ID

Examples:
  ./provision_latitude_server.sh \
    --operator-name eydel \
    --operator-ssh-public-key "$(cat ~/.ssh/id_ed25519.pub)" \
    --plan m4-metal-medium

  ./provision_latitude_server.sh \
    --operator-name eydel \
    --operator-ssh-public-key "$MY_SSH_PUBLIC_KEY" \
    --dry-run
EOF
}

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Missing required command: $1"
  fi
}

is_empty_or_null() {
  local value="${1:-}"
  [[ -z "$value" || "$value" == "null" ]]
}

extract_first_item() {
  jq -c '
    if type == "array" then .[0]
    elif (type == "object" and (.data? | type == "array")) then .data[0]
    else .
    end
  '
}

normalize_to_list() {
  jq -c '
    if type == "array" then .
    elif (type == "object" and (.data? | type == "array")) then .data
    else [.]
    end
  '
}

DRY_RUN=false
SKIP_POST_CHECKS=false
OPERATOR_SSH_PUBLIC_KEY=""
PLAN="m4-metal-small"
OPERATOR_NAME=""
EXACT_HOSTNAME=""

PROJECT="${PROJECT:-ZZZ HVK Test Harness}"
OS="${OS:-ubuntu_24_04_x64_lts}"
HOSTNAME_SUFFIX="${HOSTNAME_SUFFIX:-test-server}"
PROJECT_DESCRIPTION_SENTINEL="${PROJECT_DESCRIPTION_SENTINEL:-managed-by-hvk-test-harness}"
PROJECT_ENVIRONMENT="${PROJECT_ENVIRONMENT:-Development}"
ALLOW_PROJECT_CREATE_IF_MISSING="${ALLOW_PROJECT_CREATE_IF_MISSING:-false}"
DANGEROUS_PROJECT_NAMES_REGEX="${DANGEROUS_PROJECT_NAMES_REGEX:-^(Automated Provisioning|Solana Validator)$}"
PREFERRED_SITES_CSV="${PREFERRED_SITES_CSV:-FRA,NYC}"
WAIT_MAX_POLLS="${WAIT_MAX_POLLS:-60}"
WAIT_INTERVAL_SECONDS="${WAIT_INTERVAL_SECONDS:-30}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-}"
SSH_WAIT_POLLS="${SSH_WAIT_POLLS:-30}"
SSH_WAIT_INTERVAL_SECONDS="${SSH_WAIT_INTERVAL_SECONDS:-10}"
OUTPUT_IP_FILE="${OUTPUT_IP_FILE:-$HOME/.config/latitude_server_ip.txt}"

while (($# > 0)); do
  case "$1" in
    --operator-ssh-public-key)
      [[ $# -ge 2 ]] || fail "Missing value for $1"
      OPERATOR_SSH_PUBLIC_KEY="$2"
      shift 2
      ;;
    --plan)
      [[ $# -ge 2 ]] || fail "Missing value for $1"
      PLAN="$2"
      shift 2
      ;;
    --hostname)
      [[ $# -ge 2 ]] || fail "Missing value for $1"
      EXACT_HOSTNAME="$2"
      shift 2
      ;;
    --operator-name)
      [[ $# -ge 2 ]] || fail "Missing value for $1"
      OPERATOR_NAME="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-post-checks)
      SKIP_POST_CHECKS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

if is_empty_or_null "$OPERATOR_SSH_PUBLIC_KEY"; then
  fail "--operator-ssh-public-key is required"
fi
if is_empty_or_null "$OPERATOR_NAME"; then
  fail "--operator-name is required"
fi

HOSTNAME="${EXACT_HOSTNAME:-${OPERATOR_NAME}-${HOSTNAME_SUFFIX}}"
KEY_NAME="${OPERATOR_NAME}-key"

require_cmd lsh
require_cmd jq
require_cmd ssh
require_cmd scp

log "Project: $PROJECT"
if [[ "$PROJECT" =~ $DANGEROUS_PROJECT_NAMES_REGEX ]]; then
  fail "Refusing to operate on project '$PROJECT' because it matches DANGEROUS_PROJECT_NAMES_REGEX"
fi

if ! PROJECTS_JSON="$(lsh projects list --json)"; then
  fail "Failed to list Latitude projects"
fi

PROJECT_JSON="$(
  normalize_to_list <<<"$PROJECTS_JSON" | jq -c --arg project "$PROJECT" '
    map(select(.attributes.name == $project)) | .[0] // empty
  '
)"
PROJECT_ID="$(
  jq -r '.id // empty' <<<"$PROJECT_JSON"
)"

if is_empty_or_null "$PROJECT_ID"; then
  if [[ "$ALLOW_PROJECT_CREATE_IF_MISSING" != "true" ]]; then
    fail "Project '$PROJECT' not found. Refusing to auto-create it unless ALLOW_PROJECT_CREATE_IF_MISSING=true."
  fi
  log "Project '$PROJECT' not found. Creating it..."
  if ! CREATE_OUTPUT="$(lsh projects create --name "$PROJECT" --provisioning_type on_demand --description "$PROJECT_DESCRIPTION_SENTINEL" --environment "$PROJECT_ENVIRONMENT" --json 2>&1)"; then
    fail "Failed to create project '$PROJECT': $CREATE_OUTPUT"
  fi

  PROJECT_ID="$(
    normalize_to_list <<<"$CREATE_OUTPUT" 2>/dev/null | jq -r '.[0].id // empty' 2>/dev/null || true
  )"
  if is_empty_or_null "$PROJECT_ID"; then
    fail "Failed to parse project ID from create output: $CREATE_OUTPUT"
  fi
  log "Created project. Project ID: $PROJECT_ID"
else
  EXISTING_PROJECT_DESCRIPTION="$(jq -r '.attributes.description // empty' <<<"$PROJECT_JSON")"
  EXISTING_PROJECT_ENVIRONMENT="$(jq -r '.attributes.environment // empty' <<<"$PROJECT_JSON")"
  if [[ "$EXISTING_PROJECT_DESCRIPTION" != *"$PROJECT_DESCRIPTION_SENTINEL"* ]]; then
    fail "Refusing to use project '$PROJECT' because it is missing sentinel '$PROJECT_DESCRIPTION_SENTINEL' in its description"
  fi
  if [[ "$EXISTING_PROJECT_ENVIRONMENT" != "$PROJECT_ENVIRONMENT" ]]; then
    fail "Refusing to use project '$PROJECT' because its environment is '$EXISTING_PROJECT_ENVIRONMENT', expected '$PROJECT_ENVIRONMENT'"
  fi
  log "Using existing project ID: $PROJECT_ID"
fi

if ! PLANS_JSON="$(lsh plans list --json)"; then
  fail "Failed to list Latitude plans"
fi

PLAN_ID="$(
  normalize_to_list <<<"$PLANS_JSON" | jq -r --arg plan "$PLAN" '
    map(select((.slug // .attributes.slug // empty) == $plan)) | .[0].id // empty
  '
)"
if is_empty_or_null "$PLAN_ID"; then
  fail "Could not find plan with slug '$PLAN'"
fi
log "Plan: $PLAN (id: $PLAN_ID)"

if ! PLAN_RAW_JSON="$(lsh plans get --id "$PLAN_ID" --json)"; then
  fail "Failed to fetch plan details for id '$PLAN_ID'"
fi
PLAN_JSON="$(extract_first_item <<<"$PLAN_RAW_JSON")"

SITE=""
IFS=',' read -r -a PREFERRED_SITES <<<"$PREFERRED_SITES_CSV"
for candidate in "${PREFERRED_SITES[@]}"; do
  candidate="$(xargs <<<"$candidate")"
  [[ -z "$candidate" ]] && continue
  SITE="$(
    jq -r --arg site "$candidate" '
      .attributes.regions[]?.locations.in_stock[]? | select(. == $site)
    ' <<<"$PLAN_JSON" | head -n1
  )"
  if ! is_empty_or_null "$SITE"; then
    log "Selected preferred site: $SITE"
    break
  fi
done

if is_empty_or_null "$SITE"; then
  SITE="$(jq -r '.attributes.regions[]?.locations.in_stock[]?' <<<"$PLAN_JSON" | head -n1)"
  if is_empty_or_null "$SITE"; then
    fail "No in-stock sites found for plan '$PLAN'"
  fi
  log "Preferred sites unavailable. Using first in-stock site: $SITE"
fi

if ! KEYS_JSON="$(lsh ssh_keys list --project "$PROJECT_ID" --json)"; then
  fail "Failed to list SSH keys in project '$PROJECT_ID'"
fi

KEY_ID="$(
  normalize_to_list <<<"$KEYS_JSON" | jq -r --arg key "$OPERATOR_SSH_PUBLIC_KEY" '
    map(select((.public_key // .attributes.public_key // empty) == $key)) | .[0].id // empty
  '
)"

if is_empty_or_null "$KEY_ID"; then
  log "SSH key not found in project. Uploading key '$KEY_NAME'..."
  if ! KEY_CREATE_JSON="$(lsh ssh_keys create --project "$PROJECT_ID" --name "$KEY_NAME" --public_key "$OPERATOR_SSH_PUBLIC_KEY" --no-input --json 2>&1)"; then
    fail "Failed to create SSH key: $KEY_CREATE_JSON"
  fi
  KEY_ID="$(
    normalize_to_list <<<"$KEY_CREATE_JSON" 2>/dev/null | jq -r '.[0].id // empty' 2>/dev/null || true
  )"
  if is_empty_or_null "$KEY_ID"; then
    fail "Failed to parse SSH key ID from create output: $KEY_CREATE_JSON"
  fi
  log "SSH key uploaded. ID: $KEY_ID"
else
  log "Reusing existing SSH key ID: $KEY_ID"
fi

if ! EXISTING_SERVERS_JSON="$(lsh servers list --project "$PROJECT_ID" --json)"; then
  fail "Failed to list servers in project '$PROJECT_ID'"
fi
EXISTING_SERVER_ID="$(
  normalize_to_list <<<"$EXISTING_SERVERS_JSON" | jq -r --arg hostname "$HOSTNAME" '
    map(select((.attributes.hostname // empty) == $hostname)) | .[0].id // empty
  '
)"

SERVER_ID=""
if ! is_empty_or_null "$EXISTING_SERVER_ID"; then
  fail "Refusing to reuse existing server '$HOSTNAME' (id=$EXISTING_SERVER_ID). Pick a unique hostname or clean up the previous harness server first."
else
  log "No server named '$HOSTNAME' found. Creating a new server..."
  if [[ "$DRY_RUN" == true ]]; then
    cat <<EOF
[DRY RUN] Would execute:
lsh servers create \
  --project "$PROJECT_ID" \
  --plan "$PLAN" \
  --operating_system "$OS" \
  --hostname "$HOSTNAME" \
  --site "$SITE" \
  --ssh_keys "$KEY_ID" \
  --billing hourly \
  --raid "" \
  --no-input \
  --json
EOF
    exit 0
  fi

  if ! SERVER_CREATE_JSON="$(
    lsh servers create \
      --project "$PROJECT_ID" \
      --plan "$PLAN" \
      --operating_system "$OS" \
      --hostname "$HOSTNAME" \
      --site "$SITE" \
      --ssh_keys "$KEY_ID" \
      --billing hourly \
      --raid "" \
      --no-input \
      --json 2>&1
  )"; then
    fail "Server creation failed: $SERVER_CREATE_JSON"
  fi

  SERVER_ID="$(
    normalize_to_list <<<"$SERVER_CREATE_JSON" 2>/dev/null | jq -r '.[0].id // empty' 2>/dev/null || true
  )"
  if is_empty_or_null "$SERVER_ID"; then
    fail "Could not parse server ID from create output: $SERVER_CREATE_JSON"
  fi
  log "Server provision request accepted. Server ID: $SERVER_ID"
fi

log "Waiting for server to become active..."
STATUS=""
for ((i = 1; i <= WAIT_MAX_POLLS; i++)); do
  if ! SERVER_STATUS_JSON="$(lsh servers get --id "$SERVER_ID" --json)"; then
    fail "Failed to query server status for '$SERVER_ID'"
  fi

  STATUS="$(
    extract_first_item <<<"$SERVER_STATUS_JSON" | jq -r '.attributes.status // empty'
  )"
  if [[ "$STATUS" == "active" || "$STATUS" == "on" ]]; then
    log "Server is active (status: $STATUS)."
    break
  fi

  log "Status: ${STATUS:-unknown}. Sleeping ${WAIT_INTERVAL_SECONDS}s... (${i}/${WAIT_MAX_POLLS})"
  sleep "$WAIT_INTERVAL_SECONDS"
done

if [[ "$STATUS" != "active" && "$STATUS" != "on" ]]; then
  fail "Server did not become active within timeout"
fi

if ! SERVER_IP_JSON="$(lsh servers get --id "$SERVER_ID" --json)"; then
  fail "Failed to fetch server details for '$SERVER_ID'"
fi
PUBLIC_IP="$(
  extract_first_item <<<"$SERVER_IP_JSON" | jq -r '.attributes.primary_ipv4 // .attributes.primary_ip // empty'
)"
if is_empty_or_null "$PUBLIC_IP"; then
  fail "Could not retrieve server public IP"
fi
log "Server public IP: $PUBLIC_IP"

mkdir -p "$(dirname "$OUTPUT_IP_FILE")"
printf '%s\n' "$PUBLIC_IP" >"$OUTPUT_IP_FILE"
log "Server IP written to: $OUTPUT_IP_FILE"

if [[ -n "${OUTPUT_SERVER_ID_FILE:-}" ]]; then
  mkdir -p "$(dirname "$OUTPUT_SERVER_ID_FILE")"
  printf '%s\n' "$SERVER_ID" >"$OUTPUT_SERVER_ID_FILE"
  log "Server ID written to: $OUTPUT_SERVER_ID_FILE"
fi

if [[ "$SKIP_POST_CHECKS" == true ]]; then
  log "Skipping post-provision checks (--skip-post-checks)."
  exit 0
fi

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)
if [[ -n "$SSH_PRIVATE_KEY" ]]; then
  SSH_OPTS+=(-i "$SSH_PRIVATE_KEY" -o IdentitiesOnly=yes -o IdentityAgent=none)
fi

log "Waiting for SSH reachability on ${SSH_USER}@${PUBLIC_IP}..."
SSH_READY=false
for ((i = 1; i <= SSH_WAIT_POLLS; i++)); do
  if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${PUBLIC_IP}" 'true' >/dev/null 2>&1; then
    SSH_READY=true
    break
  fi
  sleep "$SSH_WAIT_INTERVAL_SECONDS"
done
if [[ "$SSH_READY" != true ]]; then
  fail "SSH did not become reachable on ${SSH_USER}@${PUBLIC_IP}"
fi

LOCAL_POST_CHECKS_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/latitude-post-checks.XXXXXX.sh")"
cleanup() {
  [[ -n "${LOCAL_POST_CHECKS_SCRIPT:-}" && -f "${LOCAL_POST_CHECKS_SCRIPT:-}" ]] && rm -f "${LOCAL_POST_CHECKS_SCRIPT}"
}
trap cleanup EXIT

cat >"$LOCAL_POST_CHECKS_SCRIPT" <<'EOF_POSTCHECKS'
#!/usr/bin/env bash
set -euo pipefail

echo "[1/3] Verifying RAID configuration..."
lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT
echo
cat /proc/mdstat
echo
if grep -Eq '^md.* : active raid' /proc/mdstat; then
  echo "WARNING: RAID appears active. Contact your provider to disable RAID."
else
  echo "OK: No active RAID arrays detected."
fi
echo

echo "[2/3] Verifying SMT (Simultaneous Multithreading)..."
if command -v lscpu >/dev/null 2>&1; then
  CORES="$(lscpu | awk '/^Core\(s\) per socket:/ {print $4}')"
  SOCKETS="$(lscpu | awk '/^Socket\(s\):/ {print $2}')"
  THREADS="$(lscpu | awk '/^CPU\(s\):/ {print $2}')"
  echo "Physical cores: $((CORES * SOCKETS))"
  echo "Logical CPUs (threads): $THREADS"
  if [[ "$((CORES * SOCKETS))" -lt "$THREADS" ]]; then
    echo "OK: SMT appears active."
  else
    echo "WARNING: SMT does not appear active."
  fi
else
  echo "WARNING: lscpu not found; cannot verify SMT."
fi
echo

echo "[3/3] Verifying CPU governor driver..."
if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
  ls /sys/devices/system/cpu/cpu0/cpufreq
  if ls /sys/devices/system/cpu/cpu0/cpufreq | grep -q 'amd_pstate'; then
    echo "OK: amd_pstate driver found."
  else
    echo "WARNING: amd_pstate driver not found. Confirm BIOS settings with provider."
  fi
else
  echo "WARNING: cpufreq path not found; cannot verify CPU governor driver."
fi
EOF_POSTCHECKS
chmod +x "$LOCAL_POST_CHECKS_SCRIPT"

REMOTE_POST_CHECKS_SCRIPT="/tmp/post_provision_checks.sh"
log "Running post-provision checks on the server..."
scp "${SSH_OPTS[@]}" "$LOCAL_POST_CHECKS_SCRIPT" "${SSH_USER}@${PUBLIC_IP}:${REMOTE_POST_CHECKS_SCRIPT}"
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${PUBLIC_IP}" \
  "bash '$REMOTE_POST_CHECKS_SCRIPT'; rc=\$?; rm -f '$REMOTE_POST_CHECKS_SCRIPT'; exit \$rc"

log "All post-provisioning verifications completed."

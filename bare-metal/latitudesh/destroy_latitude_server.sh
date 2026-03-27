#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./destroy_latitude_server.sh --server-id <id> [--project <name>] [--dry-run]
  ./destroy_latitude_server.sh --hostname <name> --project <name> --allow-hostname-lookup [--dry-run]

Options:
  --server-id <id>             Latitude server ID to destroy.
  --hostname <name>            Server hostname lookup fallback. Requires --allow-hostname-lookup.
  --allow-hostname-lookup      Opt in to hostname-based lookup. Use only for manual cleanup.
  --allow-unsafe-destroy       Bypass harness hostname/project safety checks.
  --project <name>             Project name used for hostname lookup (default: "ZZZ HVK Test Harness").
  --dry-run            Print what would be destroyed and exit.
  -h, --help           Show this help.
EOF
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

normalize_to_list() {
  jq -c '
    if type == "array" then .
    elif (type == "object" and (.data? | type == "array")) then .data
    else [.]
    end
  '
}

SERVER_ID=""
HOSTNAME=""
PROJECT="${PROJECT:-ZZZ HVK Test Harness}"
PROJECT_ENVIRONMENT="${PROJECT_ENVIRONMENT:-Development}"
HARNESS_HOSTNAME_PREFIX="${HARNESS_HOSTNAME_PREFIX:-hvk-}"
DRY_RUN=false
ALLOW_HOSTNAME_LOOKUP=false
ALLOW_UNSAFE_DESTROY=false

while (($# > 0)); do
  case "$1" in
    --server-id)
      SERVER_ID="${2:-}"
      shift 2
      ;;
    --hostname)
      HOSTNAME="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --allow-hostname-lookup)
      ALLOW_HOSTNAME_LOOKUP=true
      shift
      ;;
    --allow-unsafe-destroy)
      ALLOW_UNSAFE_DESTROY=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
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

require_cmd lsh
require_cmd jq

if is_empty_or_null "$SERVER_ID" && is_empty_or_null "$HOSTNAME"; then
  fail "Provide --server-id. Hostname lookup is only available with --allow-hostname-lookup"
fi

PROJECT_ID=""
if ! is_empty_or_null "$HOSTNAME"; then
  [[ "$ALLOW_HOSTNAME_LOOKUP" == true ]] || fail "Refusing hostname lookup without --allow-hostname-lookup"
  PROJECTS_JSON="$(lsh projects list --json)" || fail "Failed to list projects"
  PROJECT_ID="$(
    normalize_to_list <<<"$PROJECTS_JSON" | jq -r --arg project "$PROJECT" '
      map(select(.attributes.name == $project)) | .[0].id // empty
    '
  )"
  is_empty_or_null "$PROJECT_ID" && fail "Could not resolve project '$PROJECT'"
fi

if is_empty_or_null "$SERVER_ID"; then
  SERVERS_JSON="$(lsh servers list --project "$PROJECT_ID" --json)" || fail "Failed to list servers for project '$PROJECT_ID'"
  SERVER_ID="$(
    normalize_to_list <<<"$SERVERS_JSON" | jq -r --arg hostname "$HOSTNAME" '
      map(select((.attributes.hostname // empty) == $hostname)) | .[0].id // empty
    '
  )"
fi

is_empty_or_null "$SERVER_ID" && fail "Could not resolve server ID to destroy"

SERVER_JSON="$(lsh servers get --id "$SERVER_ID" --json | jq '.[0]')" || fail "Failed to fetch server '$SERVER_ID'"
SERVER_HOSTNAME="$(jq -r '.attributes.hostname // empty' <<<"$SERVER_JSON")"
SERVER_PROJECT_NAME="$(jq -r '.attributes.project.name // empty' <<<"$SERVER_JSON")"
SERVER_PROJECT_ENVIRONMENT="$(jq -r '.attributes.project.environment // empty' <<<"$SERVER_JSON")"

if [[ "$ALLOW_UNSAFE_DESTROY" != "true" ]]; then
  [[ "$SERVER_PROJECT_NAME" == "$PROJECT" ]] || fail "Refusing to destroy server '$SERVER_ID' because it belongs to project '$SERVER_PROJECT_NAME', expected '$PROJECT'"
  [[ "$SERVER_PROJECT_ENVIRONMENT" == "$PROJECT_ENVIRONMENT" ]] || fail "Refusing to destroy server '$SERVER_ID' because project environment is '$SERVER_PROJECT_ENVIRONMENT', expected '$PROJECT_ENVIRONMENT'"
  [[ "$SERVER_HOSTNAME" == ${HARNESS_HOSTNAME_PREFIX}* ]] || fail "Refusing to destroy server '$SERVER_ID' because hostname '$SERVER_HOSTNAME' does not start with '$HARNESS_HOSTNAME_PREFIX'"
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[DRY RUN] Would destroy Latitude server id=%s\n' "$SERVER_ID"
  exit 0
fi

run_delete() {
  local cmd=("$@")
  printf 'Trying: %s\n' "${cmd[*]}" >&2
  if "${cmd[@]}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

if run_delete lsh servers destroy --id "$SERVER_ID" --json; then
  :
elif run_delete lsh servers delete --id "$SERVER_ID" --yes --json; then
  :
elif run_delete lsh servers delete --id "$SERVER_ID" --force --json; then
  :
elif run_delete lsh servers delete --id "$SERVER_ID" --json; then
  :
elif run_delete lsh servers delete "$SERVER_ID"; then
  :
else
  fail "Failed to destroy server '$SERVER_ID' with known CLI variants"
fi

printf 'Destroyed server id=%s\n' "$SERVER_ID"

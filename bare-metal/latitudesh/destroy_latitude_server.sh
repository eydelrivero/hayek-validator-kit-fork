#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./destroy_latitude_server.sh [--server-id <id> | --hostname <name>] [--project <name>] [--dry-run]

Options:
  --server-id <id>     Latitude server ID to destroy.
  --hostname <name>    Server hostname lookup fallback if server-id is not provided.
  --project <name>     Project name used for hostname lookup (default: "Automated Provisioning").
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
PROJECT="${PROJECT:-Automated Provisioning}"
DRY_RUN=false

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
  fail "Provide either --server-id or --hostname"
fi

PROJECT_ID=""
if ! is_empty_or_null "$HOSTNAME"; then
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

if run_delete lsh servers delete --id "$SERVER_ID" --yes --json; then
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

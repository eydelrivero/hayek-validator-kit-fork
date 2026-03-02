#!/usr/bin/env bash

set -euo pipefail

hvk_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  cd "$script_dir/.." && pwd
}

hvk_require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$cmd" >&2
    return 1
  fi
}

hvk_json_ok() {
  local adapter="$1"
  local action="$2"
  local run_id="$3"
  local message="$4"
  local extra_json="${5:-}"
  if [[ -z "$extra_json" ]]; then
    extra_json='{}'
  fi

  jq -cn \
    --arg adapter "$adapter" \
    --arg action "$action" \
    --arg run_id "$run_id" \
    --arg message "$message" \
    --argjson extra "$extra_json" \
    '{
      ok: true,
      adapter: $adapter,
      action: $action,
      run_id: $run_id,
      message: $message
    } + $extra'
}

hvk_json_err() {
  local adapter="$1"
  local action="$2"
  local run_id="$3"
  local code="$4"
  local message="$5"

  jq -cn \
    --arg adapter "$adapter" \
    --arg action "$action" \
    --arg run_id "$run_id" \
    --arg code "$code" \
    --arg message "$message" \
    '{
      ok: false,
      adapter: $adapter,
      action: $action,
      run_id: $run_id,
      error: {
        code: $code,
        message: $message
      }
    }'
}

hvk_emit_err_and_exit() {
  local adapter="$1"
  local action="$2"
  local run_id="$3"
  local code="$4"
  local message="$5"
  local exit_code="${6:-1}"

  hvk_json_err "$adapter" "$action" "$run_id" "$code" "$message"
  exit "$exit_code"
}

hvk_mkdir() {
  mkdir -p "$1"
}

hvk_default_run_id() {
  date +%Y%m%d-%H%M%S
}

hvk_bool() {
  local value="${1:-false}"
  if [[ "$value" == "true" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

#!/usr/bin/env bash

set -euo pipefail

th_require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$cmd" >&2
    return 1
  fi
}

th_resolve_path() {
  local path="$1"
  local base="${2:-}"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
    return 0
  fi
  if [[ -n "$base" ]]; then
    printf '%s/%s\n' "$base" "$path"
    return 0
  fi
  printf '%s\n' "$path"
}

th_resolve_readable_path() {
  local path="$1"
  local base="${2:-}"
  local fallback_base="${3:-}"
  local candidate

  candidate="$(th_resolve_path "$path" "$base")"
  if [[ -r "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ -n "$fallback_base" && "$path" != /* ]]; then
    candidate="$(th_resolve_path "$path" "$fallback_base")"
    if [[ -r "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  printf '%s\n' "$(th_resolve_path "$path" "$base")"
}

th_public_key_from_private_key() {
  local private_key="$1"
  local public_key_file="${2:-}"

  if [[ -n "$public_key_file" && -r "$public_key_file" ]]; then
    cat "$public_key_file"
    return 0
  fi

  if [[ -r "${private_key}.pub" ]]; then
    cat "${private_key}.pub"
    return 0
  fi

  ssh-keygen -y -f "$private_key"
}

th_detect_public_ip() {
  local detect_url="${1:-https://api.ipify.org}"
  local detected_ip

  th_require_cmd curl
  detected_ip="$(curl -fsS --max-time 10 "$detect_url" | tr -d '[:space:]')"
  if [[ -z "$detected_ip" ]]; then
    printf 'Failed to detect current public IP via %s\n' "$detect_url" >&2
    return 1
  fi

  printf '%s\n' "$detected_ip"
}

th_extract_inventory_host_value() {
  local inventory="$1"
  local host="$2"
  local jq_filter="$3"
  ansible-inventory -i "$inventory" --host "$host" | jq -r "$jq_filter"
}

th_wait_for_ssh() {
  local ssh_user="$1"
  local ssh_host="$2"
  local ssh_port="$3"
  local private_key="$4"
  local timeout_seconds="${5:-300}"
  local poll_interval_seconds="${6:-5}"

  local deadline=$((SECONDS + timeout_seconds))
  local ssh_opts=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=10
    -o IdentitiesOnly=yes
    -o IdentityAgent=none
    -i "$private_key"
    -p "$ssh_port"
  )

  while true; do
    if ssh "${ssh_opts[@]}" "${ssh_user}@${ssh_host}" 'true' >/dev/null 2>&1; then
      return 0
    fi
    if ((SECONDS >= deadline)); then
      printf 'Timed out waiting for SSH on %s@%s:%s\n' "$ssh_user" "$ssh_host" "$ssh_port" >&2
      return 1
    fi
    sleep "$poll_interval_seconds"
  done
}

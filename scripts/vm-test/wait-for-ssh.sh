#!/usr/bin/env bash
set -euo pipefail

HOST=${1:-127.0.0.1}
PORT=${2:-2222}
TIMEOUT_SECS=${3:-180}

if ! command -v ssh-keyscan >/dev/null 2>&1; then
  echo "Missing dependency: ssh-keyscan" >&2
  exit 1
fi

echo "Waiting for SSH on ${HOST}:${PORT} (timeout ${TIMEOUT_SECS}s)..."

start_ts=$(date +%s)
while true; do
  if ssh-keyscan -T 5 -p "$PORT" "$HOST" >/dev/null 2>&1; then
    echo "SSH port is reachable on ${HOST}:${PORT}"
    exit 0
  fi

  now_ts=$(date +%s)
  elapsed=$((now_ts - start_ts))
  if [[ "$elapsed" -ge "$TIMEOUT_SECS" ]]; then
    echo "Timeout waiting for SSH on ${HOST}:${PORT}" >&2
    exit 1
  fi

  sleep 1
done

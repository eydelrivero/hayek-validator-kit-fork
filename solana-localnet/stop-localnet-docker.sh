#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

docker compose -f "$SCRIPT_DIR/docker-compose.yml" -f "$SCRIPT_DIR/docker-compose.podman.yml" --profile localnet down --remove-orphans --volumes

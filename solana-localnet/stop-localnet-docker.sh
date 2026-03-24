#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

docker compose -f "$SCRIPT_DIR/docker-compose.yml" -f "$SCRIPT_DIR/docker-compose.docker.yml" --profile localnet down --remove-orphans --volumes
"$SCRIPT_DIR/cleanup-generated-localnet-dirs.sh" docker

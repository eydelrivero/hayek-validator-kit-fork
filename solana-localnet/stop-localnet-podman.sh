#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

podman compose -f "$SCRIPT_DIR/docker-compose.yml" -f "$SCRIPT_DIR/docker-compose.podman.yml" --profile localnet stop && \
  (podman rm ansible-control-localnet host-alpha gossip-entrypoint keygen-init || true) && \
  (podman compose -f "$SCRIPT_DIR/docker-compose.yml" -f "$SCRIPT_DIR/docker-compose.podman.yml"  down --remove-orphans --volumes || true)

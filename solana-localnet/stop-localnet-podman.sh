#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$SCRIPT_DIR")}"
COMPOSE_CMD=(podman compose -f "$SCRIPT_DIR/docker-compose.yml" -f "$SCRIPT_DIR/docker-compose.podman.yml" --profile localnet)

"${COMPOSE_CMD[@]}" stop || true

# depends_on only affects startup order. The Compose spec never promised teardown order, and Podman Compose doesn’t
# reconstruct the dependency graph when calling down. It just asks libpod to remove the containers it knows about;
# libpod then refuses when a container still has dependents, which is why you see “has dependent containers” and
# “container already exists.” If there are orphaned containers/volumes from prior runs, Podman Compose also won’t
# clean them up automatically.
# What to do:
# Remove in reverse dependency order yourself (podman rm dependents first)
podman rm ansible-control-localnet host-alpha host-bravo host-charlie gossip-entrypoint keygen-init || true

volumes=$(podman volume ls -q --filter "label=io.podman.compose.project=${PROJECT_NAME}")
if [[ -n "$volumes" ]]; then
  podman volume rm $volumes || true
fi

"${COMPOSE_CMD[@]}" down --remove-orphans --volumes || true
"$SCRIPT_DIR/cleanup-generated-localnet-dirs.sh" podman

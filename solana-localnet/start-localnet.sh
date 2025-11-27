#!/usr/bin/env bash
set -euo pipefail

# Usage: ./start-localnet.sh [podman|docker]
ENGINE="${1:-podman}"
PROFILE="localnet"
COMPOSE_BASE="./docker-compose.yml"

case "$ENGINE" in
  podman)
    OVERRIDE="./docker-compose.podman.yml"
    COMPOSE_BIN="podman compose"
    export BUILDAH_FORMAT=${BUILDAH_FORMAT:-docker}
    ;;
  docker)
    OVERRIDE="./docker-compose.docker.yml"
    COMPOSE_BIN="docker compose"
    ;;
  *)
    echo "Unknown engine '$ENGINE' (use podman or docker)" >&2
    exit 1
    ;;
esac

SERVICE="ansible-control-localnet"

compose() { $COMPOSE_BIN -f "$COMPOSE_BASE" -f "$OVERRIDE" --profile "$PROFILE" "$@"; }

echo "Starting localnet with $ENGINE..."
compose up -d

echo "Waiting for $SERVICE container to be ready..."
until compose exec -T "$SERVICE" true >/dev/null 2>&1; do
  sleep 2
done

echo "$ENGINE compose version:"
$COMPOSE_BIN --version

compose exec "$SERVICE" bash -l -c "cd /hayek-validator-kit && ./solana-localnet/container-setup/scripts/initialize-localnet-and-demo-validators.sh"

echo "Localnet started. Attach with:"
echo "$COMPOSE_BIN -f $COMPOSE_BASE -f $OVERRIDE --profile $PROFILE exec -w /hayek-validator-kit $SERVICE bash -l"

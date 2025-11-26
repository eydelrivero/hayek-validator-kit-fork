#!/bin/bash
# filepath: ./start-localnet-from-outside-ide.sh

set -e

# Path to your docker-compose file
COMPOSE_FILE="./docker-compose.yml"
SERVICE="ansible-control-localnet"
WORKSPACE_FOLDER="$(pwd)"

# Start docker compose in detached mode
podman compose -f "$COMPOSE_FILE" --profile localnet up -d

# Wait for the ansible-control container to be healthy/up
echo "Waiting for $SERVICE container to be ready..."
until podman compose -f "$COMPOSE_FILE" --profile localnet exec -T $SERVICE true 2>/dev/null; do
  sleep 2
done

echo "Podman Compose version:"
podman compose --version

# Run the postStartCommand inside the container
podman compose -f "$COMPOSE_FILE" --profile localnet exec $SERVICE bash -l -c "cd /hayek-validator-kit && ./solana-localnet/container-setup/scripts/initialize-localnet-and-demo-validators.sh"

echo "Localnet started. Attach to the container with:"
echo "podman compose -f $COMPOSE_FILE --profile localnet exec -w /hayek-validator-kit $SERVICE bash -l"
#!/bin/bash
# filepath: ./start-localnet-from-outside-ide.sh

set -e

# Path to your docker-compose file
COMPOSE_FILE="./docker-compose.yml"
SERVICE="ansible-control-prod"
WORKSPACE_FOLDER="$(pwd)"

# Start docker compose in detached mode
docker compose -f "$COMPOSE_FILE" --profile prod up -d

# Wait for the ansible-control container to be healthy/up
echo "Waiting for $SERVICE container to be ready..."
until docker compose -f "$COMPOSE_FILE" --profile prod exec -T $SERVICE true 2>/dev/null; do
  sleep 2
done

echo "Docker Compose version:"
docker compose --version

echo "Localnet started. Attach to the container with:"
echo "docker compose -f $COMPOSE_FILE --profile prod exec -w /hayek-validator-kit $SERVICE bash -l"
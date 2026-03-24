#!/usr/bin/env bash
set -euo pipefail

# Usage: ./test-localnet.sh [podman|docker]
ENGINE="${1:-podman}"
PROFILE="localnet"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(realpath "$SCRIPT_DIR/../..")"
COMPOSE_BASE="$REPO_ROOT/solana-localnet/docker-compose.yml"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$(dirname "$COMPOSE_BASE")")}"

case "$ENGINE" in
  podman)
    OVERRIDE="$REPO_ROOT/solana-localnet/docker-compose.podman.yml"
    COMPOSE_BIN="podman compose"
    export BUILDAH_FORMAT=${BUILDAH_FORMAT:-docker}
    ;;
  docker)
    OVERRIDE="$REPO_ROOT/solana-localnet/docker-compose.docker.yml"
    COMPOSE_BIN="docker compose"
    :
    ;;
  *)
    echo "Unknown engine '$ENGINE' (use podman or docker)" >&2
    exit 1
    ;;
esac

SERVICE_CTRL="ansible-control-localnet"
SERVICES=("gossip-entrypoint" "host-alpha" "host-bravo" "host-charlie" "$SERVICE_CTRL")

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
compose() { $COMPOSE_BIN -f "$COMPOSE_BASE" -f "$OVERRIDE" --profile "$PROFILE" "$@"; }

cleanup_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Pre-clean docker stack to free ports..."
    local dc=(docker compose -f "$COMPOSE_BASE" -f "$REPO_ROOT/solana-localnet/docker-compose.docker.yml" --profile "$PROFILE")
    "${dc[@]}" down --remove-orphans --volumes || true
    local containers
    containers=$(docker ps -aq --filter "label=com.docker.compose.project=${PROJECT_NAME}")
    if [ -n "$containers" ]; then
      docker rm -f $containers || true
    fi
    local volumes
    volumes=$(docker volume ls -q --filter "label=com.docker.compose.project=${PROJECT_NAME}")
    if [ -n "$volumes" ]; then
      docker volume rm $volumes || true
    fi
  fi
}

cleanup_podman() {
  if command -v podman >/dev/null 2>&1; then
    log "Pre-clean podman stack to free ports..."
    local pcmd=(podman compose -f "$COMPOSE_BASE" -f "$REPO_ROOT/solana-localnet/docker-compose.podman.yml" --profile "$PROFILE")
    "${pcmd[@]}" down --remove-orphans --volumes || true
    local containers
    containers=$(podman ps -aq --filter "label=io.podman.compose.project=${PROJECT_NAME}")
    if [ -n "$containers" ]; then
      podman rm -f $containers || true
    fi
    local volumes
    volumes=$(podman volume ls -q --filter "label=io.podman.compose.project=${PROJECT_NAME}")
    if [ -n "$volumes" ]; then
      podman volume rm $volumes || true
    fi
  fi
}

if [ "$ENGINE" = "podman" ]; then
  log "Validating podman machine sysctl/limits for agave validator..."
  check_expect() {
    local label="$1" cmd="$2" expected="$3"
    local val
    val=$(podman machine ssh -- $cmd | tr -d '\r')
    if [ "$val" != "$expected" ]; then
      echo "Podman VM check failed: $label expected '$expected' got '$val'" >&2
      exit 1
    fi
  }
  check_expect "net.core.rmem_max" "sysctl -n net.core.rmem_max" "134217728"
  check_expect "net.core.wmem_max" "sysctl -n net.core.wmem_max" "134217728"
  check_expect "vm.max_map_count" "sysctl -n vm.max_map_count" "1000000"
  check_expect "fs.nr_open" "sysctl -n fs.nr_open" "1000000"
  check_expect "system.conf DefaultLimitNOFILE" "awk -F= '/^DefaultLimitNOFILE/ {print \$2}' /etc/systemd/system.conf" "1000000"
  check_expect "system.conf DefaultLimitMEMLOCK" "awk -F= '/^DefaultLimitMEMLOCK/ {print \$2}' /etc/systemd/system.conf" "2000000000"
  if ! podman machine ssh -- test -f /etc/security/limits.d/90-solana-nofiles.conf; then
    echo "Podman VM check failed: /etc/security/limits.d/90-solana-nofiles.conf not found" >&2
    exit 1
  fi
  podman machine ssh -- "sudo grep -q 'nofile 1000000' /etc/security/limits.d/90-solana-nofiles.conf"
  podman machine ssh -- "sudo grep -q 'memlock 2000000' /etc/security/limits.d/90-solana-nofiles.conf"
fi

log "Stopping and removing existing stack (ignore errors)..."
cleanup_docker
cleanup_podman
compose down --remove-orphans --volumes || true

log "Removing generated key and IAM files..."
# These directories are created by initialize-localnet-and-demo-validators.sh and must be regenerated for each test run.
"$REPO_ROOT/solana-localnet/cleanup-generated-localnet-dirs.sh" "$ENGINE"

log "Starting stack with $ENGINE..."
compose up -d

log "Waiting for core containers to be reachable..."
for svc in "${SERVICES[@]}"; do
  printf "  - %s " "$svc"
  until compose exec -T "$svc" true >/dev/null 2>&1; do
    printf "."
    sleep 2
  done
  printf " ok\n"
done

log "Running initializer inside control node..."
compose exec "$SERVICE_CTRL" bash -lc "cd /hayek-validator-kit && ./solana-localnet/container-setup/scripts/initialize-localnet-and-demo-validators.sh"

log "Port checks on gossip-entrypoint (8899 TCP, 8001 UDP)..."
compose exec gossip-entrypoint ss -tulpn | grep 8899 || { echo "Missing 8899 listener" >&2; exit 1; }
compose exec gossip-entrypoint ss -uap | grep 8001 || { echo "Missing 8001 listener" >&2; exit 1; }

log "Systemd service symlinks on host-alpha..."
echo "  Checking /etc/systemd/system..."
compose exec host-alpha bash -lc "ls -l /etc/systemd/system | grep -E 'ssh-key|sol'"
echo "  Checking multi-user.target.wants..."
compose exec host-alpha bash -lc "ls -l /etc/systemd/system/multi-user.target.wants | grep -E 'ssh-key|sol'"

log "Service status for key setup units on host-alpha..."
compose exec host-alpha bash -lc "systemctl status set-container-default-user-ssh-key --no-pager"
compose exec host-alpha bash -lc "systemctl status set-validator-service-user-ssh-key --no-pager"

log "Validator port 8899 on host-alpha..."
for i in {1..20}; do
  if compose exec host-alpha ss -tulpn | grep 8899 >/dev/null 2>&1; then
    echo "port 8899 ready"
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "host-alpha missing 8899 listener" >&2
    exit 1
  fi
  sleep 2
done

log "Genesis hash sanity check (gossip-entrypoint vs host-alpha)..."
compose exec host-alpha bash -lc "sudo -u sol -H bash -lc 'solana -u http://gossip-entrypoint:8899 genesis-hash'"
compose exec gossip-entrypoint bash -lc "sudo -H bash -lc 'solana -u http://localhost:8899 genesis-hash'"

log "Basic RPC catchup check..."
compose exec host-alpha bash -lc "sudo -u sol -H bash -lc 'solana -u http://gossip-entrypoint:8899 catchup --our-localhost 8899 || true'"

log "Localnet test completed on $ENGINE."

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/solana-localnet/docker-compose.vm-harness.yml"

ACTION="${1:-}"

if [[ -z "$ACTION" ]]; then
  echo "Usage: manage-vm-control-plane.sh <up|down|logs|ps>" >&2
  exit 2
fi

VMH_ENGINE="${VMH_ENGINE:-docker}"
VMH_PROJECT_NAME="${VMH_PROJECT_NAME:-hvk-vmctl}"
VMH_SOLANA_RELEASE="${VMH_SOLANA_RELEASE:-3.1.9}"
VMH_RPC_PORT="${VMH_RPC_PORT:-28899}"
VMH_GOSSIP_PORT="${VMH_GOSSIP_PORT:-28001}"
VMH_FAUCET_PORT="${VMH_FAUCET_PORT:-29901}"
VMH_DYNAMIC_PORT_RANGE="${VMH_DYNAMIC_PORT_RANGE:-28002-28032}"
VMH_GOSSIP_HOST="${VMH_GOSSIP_HOST:-10.0.2.2}"
VMH_SLOTS_PER_EPOCH="${VMH_SLOTS_PER_EPOCH:-750}"
VMH_LIMIT_LEDGER_SIZE="${VMH_LIMIT_LEDGER_SIZE:-50000000}"
VMH_MIN_FINALIZED_SLOT="${VMH_MIN_FINALIZED_SLOT:-5}"
VMH_REBUILD="${VMH_REBUILD:-false}"

case "$VMH_ENGINE" in
  docker)
    COMPOSE_BIN=(docker compose)
    ENGINE_BIN=(docker)
    ;;
  podman)
    COMPOSE_BIN=(podman compose)
    ENGINE_BIN=(podman)
    ;;
  *)
    echo "Unsupported VMH_ENGINE: $VMH_ENGINE (expected docker|podman)" >&2
    exit 2
    ;;
esac

compose() {
  "${COMPOSE_BIN[@]}" -p "$VMH_PROJECT_NAME" -f "$COMPOSE_FILE" "$@"
}

container_id_for_service() {
  compose ps -q "$1" 2>/dev/null || true
}

print_logs() {
  local cid=""
  local tmp_root=""
  local tmp_log=""

  compose logs --no-color --tail 200 gossip-entrypoint-vm ansible-control-vm 2>&1 || true
  cid="$(container_id_for_service gossip-entrypoint-vm)"
  if [[ -n "$cid" ]]; then
    tmp_root="$(mktemp -d)"
    if "${ENGINE_BIN[@]}" cp "${cid}:/var/tmp/test-ledger" "$tmp_root" >/dev/null 2>&1; then
      tmp_log="$tmp_root/test-ledger/validator.log"
      if [[ -L "$tmp_log" ]]; then
        local link_target
        link_target="$(readlink "$tmp_log" 2>/dev/null || true)"
        if [[ -n "$link_target" ]]; then
          tmp_log="$tmp_root/test-ledger/${link_target}"
        fi
      fi
    elif "${ENGINE_BIN[@]}" cp "${cid}:/var/tmp/test-ledger/validator.log" "$tmp_root" >/dev/null 2>&1; then
      tmp_log="$tmp_root/validator.log"
    fi
    if [[ -n "$tmp_log" && -f "$tmp_log" ]]; then
      echo
      echo "--- /var/tmp/test-ledger/validator.log ---"
      cat "$tmp_log" || true
    fi
    rm -rf "$tmp_root"
  fi
}

wait_for_control_plane() {
  local tries=0
  local finalized_slot=0

  until compose exec -T ansible-control-vm true >/dev/null 2>&1; do
    tries=$((tries + 1))
    if (( tries > 90 )); then
      echo "ansible-control-vm did not become ready" >&2
      compose ps >&2 || true
      print_logs >&2 || true
      exit 4
    fi
    sleep 2
  done

  tries=0
  until curl -fsS "http://127.0.0.1:${VMH_RPC_PORT}/health" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if (( tries > 90 )); then
      echo "gossip-entrypoint-vm did not expose a healthy RPC endpoint at http://127.0.0.1:${VMH_RPC_PORT}/health" >&2
      compose ps >&2 || true
      print_logs >&2 || true
      exit 4
    fi
    sleep 2
  done

  tries=0
  while true; do
    finalized_slot="$(
      compose exec -T ansible-control-vm bash -lc \
        "solana -ul --commitment finalized block --output json 2>/dev/null | jq -r '.parentSlot // 0'" \
        2>/dev/null || echo 0
    )"
    if [[ "$finalized_slot" =~ ^[0-9]+$ ]] && (( finalized_slot > VMH_MIN_FINALIZED_SLOT )); then
      break
    fi
    tries=$((tries + 1))
    if (( tries > 120 )); then
      echo "gossip-entrypoint-vm did not reach finalized slot > ${VMH_MIN_FINALIZED_SLOT}" >&2
      compose ps >&2 || true
      print_logs >&2 || true
      exit 4
    fi
    sleep 1
  done
}

case "$ACTION" in
  up)
    if [[ "$VMH_REBUILD" == "true" ]]; then
      compose build --no-cache gossip-entrypoint-vm ansible-control-vm
    else
      compose build gossip-entrypoint-vm ansible-control-vm
    fi
    compose up -d gossip-entrypoint-vm ansible-control-vm
    wait_for_control_plane
    ;;
  down)
    compose down --remove-orphans --volumes
    ;;
  logs)
    print_logs
    ;;
  ps)
    compose ps
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    exit 2
    ;;
esac

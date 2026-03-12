#!/usr/bin/env bash
set -euo pipefail

SLOTS_PER_EPOCH="${SLOTS_PER_EPOCH:-750}"
LIMIT_LEDGER_SIZE="${LIMIT_LEDGER_SIZE:-50000000}"
DYNAMIC_PORT_RANGE="${DYNAMIC_PORT_RANGE:-8000-8030}"
RPC_PORT="${RPC_PORT:-8899}"
GOSSIP_PORT="${GOSSIP_PORT:-8001}"
FAUCET_PORT="${FAUCET_PORT:-9900}"
BIND_ADDRESS="${BIND_ADDRESS:-0.0.0.0}"
GOSSIP_HOST="${GOSSIP_HOST:-$(hostname -i | awk '{print $1}')}"
LEDGER_DIR="${LEDGER_DIR:-}"
RESET_FLAG="${RESET_FLAG:---reset}"
TEST_VALIDATOR_BIN="${TEST_VALIDATOR_BIN:-}"
RESOLVED_BIND_ADDRESS="$BIND_ADDRESS"

if [[ -z "$TEST_VALIDATOR_BIN" ]]; then
  if command -v solana-test-validator >/dev/null 2>&1; then
    TEST_VALIDATOR_BIN="$(command -v solana-test-validator)"
  else
    echo "solana-test-validator is not available on PATH." >&2
    exit 1
  fi
fi

resolve_non_loopback_ipv4() {
  local candidate=""

  if command -v ip >/dev/null 2>&1; then
    candidate="$(ip -o -4 addr show scope global up | awk '{print $4}' | cut -d/ -f1 | head -n1)"
  fi

  if [[ -z "$candidate" ]]; then
    candidate="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi

  if [[ -z "$candidate" || "$candidate" == 127.* ]]; then
    candidate="$(hostname -i 2>/dev/null | awk '{print $1}')"
  fi

  printf '%s' "$candidate"
}

args=(
  --slots-per-epoch "$SLOTS_PER_EPOCH"
  --limit-ledger-size "$LIMIT_LEDGER_SIZE"
  --dynamic-port-range "$DYNAMIC_PORT_RANGE"
  --rpc-port "$RPC_PORT"
  --faucet-port "$FAUCET_PORT"
  --gossip-port "$GOSSIP_PORT"
)

if "$TEST_VALIDATOR_BIN" --help 2>&1 | grep -q -- '--gossip-host'; then
  args+=(--gossip-host "$GOSSIP_HOST")
elif [[ "$RESOLVED_BIND_ADDRESS" == "0.0.0.0" ]]; then
  # Older solana-test-validator builds use --bind-address as the external
  # gossip address when --gossip-host is unavailable, and they panic if it is
  # still 0.0.0.0. Prefer configured gossip host, then resolve a non-loopback
  # interface IP; fallback to hostname lookup as a last resort.
  if [[ -n "$GOSSIP_HOST" && "$GOSSIP_HOST" != "0.0.0.0" && "$GOSSIP_HOST" != 127.* ]]; then
    RESOLVED_BIND_ADDRESS="$GOSSIP_HOST"
  else
    RESOLVED_BIND_ADDRESS="$(resolve_non_loopback_ipv4)"
  fi
fi

args+=(--bind-address "$RESOLVED_BIND_ADDRESS")

if [[ -n "$LEDGER_DIR" ]]; then
  mkdir -p "$LEDGER_DIR"
  args+=(--ledger "$LEDGER_DIR")
fi

if [[ -n "$RESET_FLAG" ]]; then
  args+=("$RESET_FLAG")
fi

exec "$TEST_VALIDATOR_BIN" "${args[@]}"

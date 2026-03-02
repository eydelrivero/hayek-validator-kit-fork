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
  elif command -v agave-test-validator >/dev/null 2>&1; then
    TEST_VALIDATOR_BIN="$(command -v agave-test-validator)"
  else
    echo "Neither solana-test-validator nor agave-test-validator is available on PATH." >&2
    exit 1
  fi
fi

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
  # still 0.0.0.0. Bind to a concrete container-local IP instead.
  RESOLVED_BIND_ADDRESS="$(hostname -i | awk '{print $1}')"
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

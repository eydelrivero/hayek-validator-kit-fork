#!/usr/bin/env bats

setup() {
  # Run tests from repo root to keep paths stable
  cd "$(dirname "$BATS_TEST_FILENAME")/../.."
}

@test "podman localnet end-to-end" {
  if ! command -v podman >/dev/null; then
    skip "podman not installed"
  fi
  run bash ./solana-localnet/tests/test-localnet.sh podman
  [ "$status" -eq 0 ]
}

@test "docker localnet end-to-end" {
  if ! command -v docker >/dev/null; then
    skip "docker not installed"
  fi
  run bash ./solana-localnet/tests/test-localnet.sh docker
  [ "$status" -eq 0 ]
}

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOLANA_LOCALNET_DIR="$SCRIPT_DIR"

TARGETS=(
  "$SOLANA_LOCALNET_DIR/localnet-ssh-keys"
  "$SOLANA_LOCALNET_DIR/localnet-new-metal-box"
)

remove_targets_directly() {
  rm -rf "${TARGETS[@]}"
  mkdir -p "${TARGETS[@]}"
}

cleanup_with_container() {
  local engine="$1"
  local uid gid image shell_cmd
  uid="$(id -u)"
  gid="$(id -g)"
  image="alpine:3.20"
  shell_cmd="
    set -eu
    rm -rf /work/localnet-ssh-keys /work/localnet-new-metal-box
    mkdir -p /work/localnet-ssh-keys /work/localnet-new-metal-box
    chown -R ${uid}:${gid} /work/localnet-ssh-keys /work/localnet-new-metal-box
    chmod 0755 /work/localnet-ssh-keys /work/localnet-new-metal-box
  "

  case "$engine" in
    docker)
      docker run --rm -v "$SOLANA_LOCALNET_DIR:/work" "$image" sh -lc "$shell_cmd"
      ;;
    podman)
      podman run --rm -v "$SOLANA_LOCALNET_DIR:/work" "$image" sh -lc "$shell_cmd"
      ;;
    *)
      echo "Unsupported engine: $engine" >&2
      return 1
      ;;
  esac
}

ENGINE="${1:-auto}"

if remove_targets_directly 2>/dev/null; then
  exit 0
fi

case "$ENGINE" in
  docker|podman)
    cleanup_with_container "$ENGINE"
    ;;
  auto)
    if command -v docker >/dev/null 2>&1; then
      cleanup_with_container docker
    elif command -v podman >/dev/null 2>&1; then
      cleanup_with_container podman
    else
      echo "Unable to clean generated localnet directories: neither docker nor podman is available." >&2
      exit 1
    fi
    ;;
  *)
    echo "Unsupported engine: $ENGINE" >&2
    exit 1
    ;;
esac

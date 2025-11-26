#!/usr/bin/env bash
set -euo pipefail

# Start an ssh-agent inside ansible-control-localnet and load the dev keys.
SOCK="/tmp/ssh-agent.sock"

# Clean up any stale socket so ssh-agent can start cleanly.
if [ -S "$SOCK" ]; then
  rm -f "$SOCK"
fi

eval "$(ssh-agent -a "$SOCK")"
export SSH_AUTH_SOCK="$SOCK"

ADDED_ANY=0
for key in /localnet-ssh-keys/*_ed25519; do
  if [ -f "$key" ]; then
    ssh-add "$key" >/dev/null
    ADDED_ANY=1
  fi
done

if [ "$ADDED_ANY" -eq 0 ]; then
  echo "No keys found under /localnet-ssh-keys to add to ssh-agent."
else
  echo "ssh-agent started at $SSH_AUTH_SOCK with keys from /localnet-ssh-keys."
fi

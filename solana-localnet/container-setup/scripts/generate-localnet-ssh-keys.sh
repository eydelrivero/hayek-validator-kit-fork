#!/usr/bin/env bash
set -euo pipefail

mkdir -p /localnet-ssh-keys
chmod 700 /localnet-ssh-keys

for user in ubuntu sol alice bob carla; do
  key_path="/localnet-ssh-keys/${user}_ed25519"
  if [ ! -f "${key_path}" ]; then
    echo "Generating dev key for ${user}..."
    ssh-keygen -t ed25519 -N "" -C "localnet-${user}" -f "${key_path}"
  fi

  chmod 600 "${key_path}"
  chmod 644 "${key_path}.pub"
done

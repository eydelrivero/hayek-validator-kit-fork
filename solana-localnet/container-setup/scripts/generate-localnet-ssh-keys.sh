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

# Generate IAM CSV files alongside the keys for Ansible consumption.
mkdir -p /localnet-new-metal-box
chmod 700 /localnet-new-metal-box

# Extract public key bodies (second field) to avoid carrying comments into CSVs.
alice_pub=$(cut -d' ' -f2 /localnet-ssh-keys/alice_ed25519.pub)
bob_pub=$(cut -d' ' -f2 /localnet-ssh-keys/bob_ed25519.pub)
carla_pub=$(cut -d' ' -f2 /localnet-ssh-keys/carla_ed25519.pub)

cat > /localnet-new-metal-box/iam_setup_dev.csv <<EOF
user,key,group_a,group_b,group_c
alice,ssh-ed25519 ${alice_pub} alice@admins,sysadmin,,
bob,ssh-ed25519 ${bob_pub} bob@operators,validator_operators,,
carla,ssh-ed25519 ${carla_pub} carla@viewers,validator_viewers,,
sol,,,,
EOF

cat > /localnet-new-metal-box/iam_setup_monitor.csv <<EOF
user,key,group_a,group_b,group_c
alice,ssh-ed25519 ${alice_pub} alice@admins,,,sysadmin
bob,ssh-ed25519 ${bob_pub} bob@operators,sysadmin,,
carla,ssh-ed25519 ${carla_pub} carla@viewers,,sysadmin,
EOF

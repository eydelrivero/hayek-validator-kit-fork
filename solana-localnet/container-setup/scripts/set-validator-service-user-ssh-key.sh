#!/usr/bin/env bash
set -euo pipefail


rm -rf /home/$VALIDATOR_SERVICE_USER/.ssh
mkdir -p /home/$VALIDATOR_SERVICE_USER/.ssh
chmod 700 /home/$VALIDATOR_SERVICE_USER/.ssh

> /home/${VALIDATOR_SERVICE_USER}/.ssh/authorized_keys
cat /localnet-ssh-keys/${VALIDATOR_SERVICE_USER}_ed25519.pub > /home/${VALIDATOR_SERVICE_USER}/.ssh/authorized_keys

chmod 600 /home/${VALIDATOR_SERVICE_USER}/.ssh/authorized_keys
chown -R ${VALIDATOR_SERVICE_USER}:${VALIDATOR_SERVICE_USER} /home/${VALIDATOR_SERVICE_USER}/.ssh

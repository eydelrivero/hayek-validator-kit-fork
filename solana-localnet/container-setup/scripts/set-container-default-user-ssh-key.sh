#!/usr/bin/env bash
set -euo pipefail

# cat /tmp/id_ed25519.pub >> /home/$VALIDATOR_SERVICE_USER/.ssh/authorized_keys


# default user
rm -rf /home/$HOST_DEFAULT_USER/.ssh
mkdir -p /home/$HOST_DEFAULT_USER/.ssh
chmod 700 /home/$HOST_DEFAULT_USER/.ssh

# # Clear authorized_keys before appending to avoid duplicates
# > /home/$$HOST_DEFAULT_USER/.ssh/authorized_keys
# for file in /tmp/team_ssh_public_keys/*; do
#     cat $$file >> /home/$$HOST_DEFAULT_USER/.ssh/authorized_keys
#     # Adding an empty line after each key is not strictly necessary for authorized_keys parsing,
#     # but it improves readability and maintains consistency with other containers.
#     echo "" >> /home/$$HOST_DEFAULT_USER/.ssh/authorized_keys
# done
# # Deduplicate authorized_keys entries
# TEMP_AUTH_KEYS="/home/$$HOST_DEFAULT_USER/.ssh/authorized_keys.tmp"
# awk '!seen[$0]++' /home/$$HOST_DEFAULT_USER/.ssh/authorized_keys > $$TEMP_AUTH_KEYS
# mv $$TEMP_AUTH_KEYS /home/$$HOST_DEFAULT_USER/.ssh/authorized_keys

> /home/${HOST_DEFAULT_USER}/.ssh/authorized_keys
cat /localnet-ssh-keys/${HOST_DEFAULT_USER}_ed25519.pub > /home/${HOST_DEFAULT_USER}/.ssh/authorized_keys

chmod 600 /home/${HOST_DEFAULT_USER}/.ssh/authorized_keys
chown -R ${HOST_DEFAULT_USER}:${HOST_DEFAULT_USER} /home/${HOST_DEFAULT_USER}/.ssh
# end default user


# echo "VALIDATOR_SERVICE_USER=${VALIDATOR_SERVICE_USER:-unset}"

# # set sol service user ssh authorized_keys
# rm -rf /home/$VALIDATOR_SERVICE_USER/.ssh
# mkdir -p /home/$VALIDATOR_SERVICE_USER/.ssh
# chmod 700 /home/$VALIDATOR_SERVICE_USER/.ssh

# for file in /tmp/team_ssh_public_keys/*; do
#     echo \"Adding public key from $file\"
#     cat $file >> /home/$VALIDATOR_SERVICE_USER/.ssh/authorized_keys
#     echo "" >> /home/$VALIDATOR_SERVICE_USER/.ssh/authorized_keys
# done

# chmod 600 /home/$VALIDATOR_SERVICE_USER/.ssh/authorized_keys
# chown -R $VALIDATOR_SERVICE_USER:$VALIDATOR_SERVICE_USER /home/$VALIDATOR_SERVICE_USER/.ssh
# # set sol service as owner of ledger, accounts, and snapshots directories
# chown -R $VALIDATOR_SERVICE_USER:$VALIDATOR_SERVICE_USER /mnt/ledger
# chown -R $VALIDATOR_SERVICE_USER:$VALIDATOR_SERVICE_USER /mnt/accounts
# chown -R $VALIDATOR_SERVICE_USER:$VALIDATOR_SERVICE_USER /mnt/snapshots
# # set team member user
# id -u $VALIDATOR_OPERATOR_USER || adduser --disabled-password --gecos \"\" $VALIDATOR_OPERATOR_USER && echo \"$VALIDATOR_OPERATOR_USER:${VALIDATOR_OPERATOR_USER}pw\" | chpasswd && usermod -aG sudo $VALIDATOR_OPERATOR_USER

# # set team member user ssh authorized_keys
# rm -rf /home/$VALIDATOR_OPERATOR_USER/.ssh
# mkdir -p /home/$VALIDATOR_OPERATOR_USER/.ssh
# chmod 700 /home/$VALIDATOR_OPERATOR_USER/.ssh

# for file in /tmp/team_ssh_public_keys/*; do
#     echo \"Adding public key from $file\"
#     cat $file >> /home/$VALIDATOR_OPERATOR_USER/.ssh/authorized_keys
#     echo "" >> /home/$VALIDATOR_OPERATOR_USER/.ssh/authorized_keys
# done

# chmod 600 /home/$VALIDATOR_OPERATOR_USER/.ssh/authorized_keys
# chown -R $VALIDATOR_OPERATOR_USER:$VALIDATOR_OPERATOR_USER /home/$VALIDATOR_OPERATOR_USER/.ssh

# set RPC_URL globally for all users
echo \"export RPC_URL=$RPC_URL\" >> /etc/environment
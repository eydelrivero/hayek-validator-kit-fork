#!/bin/bash
# Not to be called directly, but called by devcontainer or start-localnet-from-outside-ide.sh to configure the localnet

set -e

echo "✅ All containers are healthy."
echo "🚀 Running solana-localnet initialization tasks..."
echo

LABEL="SOLANA LOCALNET"
echolog() {
  echo
  echo "$LABEL: $1"
  echo
}

HERE="$(dirname "$0")"
readlink_cmd="readlink"
echo "OSTYPE IS: $OSTYPE"
if [[ $OSTYPE == darwin* ]]; then
  # Mac OS X's version of `readlink` does not support the -f option,
  # But `greadlink` does, which you can get with `brew install coreutils`
  readlink_cmd="greadlink"

  if ! command -v ${readlink_cmd} &>/dev/null; then
    echo "${readlink_cmd} could not be found. You may need to install coreutils: \`brew install coreutils\`"
    exit 1
  fi
fi

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
CURRENT_SCRIPT_RUNTIME_DIR="$("${readlink_cmd}" -f "${HERE}")"

# setup solana cli default signer
if [ ! -f ~/.config/solana/id.json ]; then
  echo -e "${YELLOW}Generating default solana cli signer...${NC}"
  solana-keygen new -s --no-bip39-passphrase -o ~/.config/solana/id.json
else
  echo "Default solana cli signer already exists at ~/.config/solana/id.json"
fi
echo -e "${RED}WARNING: THIS SIGNER ($(solana-keygen pubkey ~/.config/solana/id.json)) IS EPHEMERAL AND WILL BE DESTROYED WHEN THE ansible-control CONTAINER IS STOPPED OR DELETED!${NC}"

MAX_SLEEP_SECONDS=120
CURRENT_SLEEP_SECONDS=0
MIN_FINALIZED_SLOT=20 # Recommended value is 100. See https://github.com/mvines/validator-Identity-transition-demo?tab=readme-ov-file#start-a-test-validator-to-simulate-the-overall-solana-cluster

# # authorized host to ssh into the validators using ssh key
# if [ ! -f ~/.ssh/id_ed25519 ]; then
#   echo "Generating SSH key..."
#   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
# fi
# if [ ! -f ~/.ssh/id_ed25519.pub ]; then
#   echo "Public SSH key not found. Exiting..."
#   exit 1
# fi

# the following is not needed because it is done in the docker-compose file
# OPERATOR_AUTHORIZED_SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
# docker exec -it alpha bash -c "sudo echo $OPERATOR_AUTHORIZED_SSH_KEY >> /home/sol/.ssh/authorized_keys"
# docker exec -it secondary bash -c "sudo echo $OPERATOR_AUTHORIZED_SSH_KEY >> /home/sol/.ssh/authorized_keys"

echolog "Waiting for $MIN_FINALIZED_SLOT finalized slots..."

while [ $CURRENT_SLEEP_SECONDS -lt $MAX_SLEEP_SECONDS ]; do
  LATEST_FINALIZED_SLOT=$(solana -ul --commitment finalized block --output json | jq -r ".parentSlot" || 0)
  echo "Finalized Slot: $LATEST_FINALIZED_SLOT | Elapsed: $CURRENT_SLEEP_SECONDS seconds"
  if [ ! -z "$LATEST_FINALIZED_SLOT" ] && [ $LATEST_FINALIZED_SLOT -gt $MIN_FINALIZED_SLOT ]; then
    break
  fi
  sleep 1
  CURRENT_SLEEP_SECONDS=$((CURRENT_SLEEP_SECONDS + 1))
done

if [ ! $LATEST_FINALIZED_SLOT -ge $MIN_FINALIZED_SLOT ]; then
  echo "Entry point didn't reach $MIN_FINALIZED_SLOT finalized slots after $MAX_SLEEP_SECONDS seconds. Exiting..."
  exit 1
fi

CLUSTER_RPC=http://localhost:8899

# Get the identity public key of the gossip entrypoint validator by:
# 1. Querying the local validator list with --keep-unstaked-delinquents to include all validators
# 2. Getting JSON output and using jq to extract the first validator's identity pubkey
# This will be used later to configure other validators to connect to the gossip-entrypoint
ENTRYPOINT_IDENTITY_PUBKEY=$(solana -ul validators --keep-unstaked-delinquents --output json | jq -r ".validators | .[0].identityPubkey")

ANSIBLE_WORKSPACE_DIR="/hayek-validator-kit" # Should match the ansible-control volume where the repo is mounted in docker-compose.yml
ANSIBLE_VALIDATORS_KEYS_DIR="$ANSIBLE_WORKSPACE_DIR/solana-localnet/validator-keys"
ANSIBLE_DEMO_KEYS_DIR="$ANSIBLE_VALIDATORS_KEYS_DIR/demo1"
ALPHA_DEMO_KEYS_DIR="/home/sol/keys/demo1"
# We have the HOST-ALPHA SERVER BOX
# We have the DEMO VALIDATOR KEY SET
# We could have the DEMO VALIDATOR KEY SET deployed on the HOST-ALPHA SERVER BOX

MOUNT_ROOT_DIR=/mnt
LEDGER_DIR="${MOUNT_ROOT_DIR}/ledger"
ACCOUNTS_DIR="${MOUNT_ROOT_DIR}/accounts"
SNAPSHOTS_DIR="${MOUNT_ROOT_DIR}/snapshots"
LOGS_DIR="~/logs"
BIN_DIR="~/bin"

solana -u $CLUSTER_RPC epoch-info
# Airdrop 500k SOL to the default CLI signer at ~/.config/solana/id.json
solana -u $CLUSTER_RPC airdrop 500000

# Provision the demo Accounts and Keys on the Ansible Control.
# They'll be used to configure the host-alpha node in the script below.
# The demo keys are pre-generated with all addresses starting with "DEMO"
# to facilitate communication and debugging between team members. This 
# allows deterministic behavior and documentation. For example, localnet
# blockchain explorer urls in the documentation are the same for all team
# members.

# WARNING: The demo keys are under source control and should not be used in 
# any other cluster other than localnet. They are meant for development and
# testing only.

echo ">>> ANSIBLE_DEMO_KEYS_DIR: $ANSIBLE_DEMO_KEYS_DIR"
echo ">>> ANSIBLE_VALIDATORS_KEYS_DIR: $ANSIBLE_VALIDATORS_KEYS_DIR"
cd "$ANSIBLE_DEMO_KEYS_DIR"
#Airdrop 42 localnet SOL to the demo validator
solana -u $CLUSTER_RPC --keypair primary-target-identity.json airdrop 42
#Create a vote account for the demo validator
solana -u $CLUSTER_RPC create-vote-account vote-account.json primary-target-identity.json authorized-withdrawer.json
#Create a stake account with 200k SOL in it
solana -u $CLUSTER_RPC create-stake-account stake-account.json 200000
#Delegate the stake account to the vote account of the demo validator
solana -u $CLUSTER_RPC delegate-stake stake-account.json vote-account.json --force

# Generate ALPHA DEMO validator startup script
echo "---   SETTING UP DEMO VALIDATOR SCRIPT WITH ACCOUNT KEYS...   ---"
VOTE_ACCOUNT_PUBKEY=$(solana address -k $ANSIBLE_DEMO_KEYS_DIR/vote-account.json)
EXPECTED_GENESIS_HASH=$(solana -u $CLUSTER_RPC genesis-hash)

CLUSTER_NAME=localnet
TMP_DIR=$(mktemp --directory)

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to handle errors
handle_error() {
    log "ERROR: $1"
    rm -rf "$TMP_DIR"
    exit 1
}

# Function to generate validator config
generate_tmp_validator_startup_script() {
    local output_file="${TMP_DIR}/agave-validator-$CLUSTER_NAME.sh"
    # Create the configuration file
    cat > "$output_file" << EOF
#!/bin/bash
agave-validator \\
    --identity ${ALPHA_DEMO_KEYS_DIR}/identity.json \\
    --vote-account ${VOTE_ACCOUNT_PUBKEY} \\
    --authorized-voter ${ALPHA_DEMO_KEYS_DIR}/primary-target-identity.json \\
    --known-validator ${ENTRYPOINT_IDENTITY_PUBKEY} \\
    --only-known-rpc \\
    --log /home/sol/logs/agave-validator.log \\
    --ledger /mnt/ledger \\
    --accounts /mnt/accounts \\
    --snapshots /mnt/snapshots \\
    --entrypoint gossip-entrypoint:8001 \\
    --expected-genesis-hash ${EXPECTED_GENESIS_HASH} \\
    --allow-private-addr \\
    --rpc-port 8899 \\
    --no-os-network-limits-test \\
    --limit-ledger-size 50000000
EOF
}

cleanup-tmp-dir() {
  trap 'rm -rf "$TMP_DIR"' EXIT
}


VALIDATOR_SERVICE_USER_SSH_KEY_PATH=/localnet-ssh-keys/sol_ed25519

# Cleanup the host of the validator
# Parameters: HOST, SSH_PORT, USER
# USE: cleanup-host HOST SSH_PORT USER
cleanup-host() {
  USER=sol
  SSH_PORT=22
  : ${1?"Requires HOST"}
  HOST=$1

  # cleanup existing sol service
  ssh -i $VALIDATOR_SERVICE_USER_SSH_KEY_PATH -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" "$USER@$HOST" -p $SSH_PORT "
    set -e

    sudo systemctl stop sol 2> /dev/null || true
    sudo systemctl disable sol 2> /dev/null || true
    sudo rm /etc/systemd/system/sol.service 2> /dev/null || true
    sudo rm /etc/systemd/system/sol.service 2> /dev/null || true # and symlinks that might be related
    sudo systemctl daemon-reload
    sudo systemctl reset-failed
  "
}

# Configure the validator on the host
# USE: configure-demo-in-host HOST
configure-demo-in-host() {
  USER=sol
  SSH_PORT=22
  : ${1?"Requires HOST"}
  HOST=$1

  VALIDATOR_SERVICE_USER=sol
  HOST_SOLANA_BIN="~/.local/share/solana/install/active_release/bin"

  # Copy the primary-target-identity.json from the Ansible Control to the host
  scp -i $VALIDATOR_SERVICE_USER_SSH_KEY_PATH -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -P $SSH_PORT $ANSIBLE_DEMO_KEYS_DIR/primary-target-identity.json "$USER@$HOST:~/primary-target-identity.json"

  # Generate the validator startup script
  ANSIBLE_DEMO_STARTUP_SCRIPT=$CURRENT_SCRIPT_RUNTIME_DIR/agave-validator-localnet.sh
  generate_tmp_validator_startup_script
  cp -f $TMP_DIR/agave-validator-localnet.sh $ANSIBLE_DEMO_STARTUP_SCRIPT
  chmod +x $ANSIBLE_DEMO_STARTUP_SCRIPT
  if [ ! -f $ANSIBLE_DEMO_STARTUP_SCRIPT ]; then
    echo "Validator startup script could not be created."
    exit 1
  fi

  echo "cat validator startup script at $ANSIBLE_DEMO_STARTUP_SCRIPT"
  cat $ANSIBLE_DEMO_STARTUP_SCRIPT
  echo

  # Transfer the validator startup script from Ansible to the Host's sol user's bin directory
  ssh -i $VALIDATOR_SERVICE_USER_SSH_KEY_PATH -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" "$USER@$HOST" -p $SSH_PORT "mkdir -p ~/bin && chmod 754 ~/bin"
  scp -i $VALIDATOR_SERVICE_USER_SSH_KEY_PATH -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -P $SSH_PORT $ANSIBLE_DEMO_STARTUP_SCRIPT "$USER@$HOST:~/bin/run-validator-demo.sh"
  rm -rf $ANSIBLE_DEMO_STARTUP_SCRIPT

  # Transfer the validator keys from Ansible to the Host's sol user's keys directory and create symlinks for identity.json
  ssh -i $VALIDATOR_SERVICE_USER_SSH_KEY_PATH -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" "$USER@$HOST" -p $SSH_PORT "
    set -e
    # source ~/.profile
    PATH=$HOST_SOLANA_BIN:$PATH
    mkdir -p $ALPHA_DEMO_KEYS_DIR && chmod 755 $ALPHA_DEMO_KEYS_DIR
    mkdir -p ~/logs && chmod 755 ~/logs
    mv ~/primary-target-identity.json $ALPHA_DEMO_KEYS_DIR/primary-target-identity.json
    ln -sf "$ALPHA_DEMO_KEYS_DIR/primary-target-identity.json" "$ALPHA_DEMO_KEYS_DIR/identity.json"

    if [ ! -f "$ALPHA_DEMO_KEYS_DIR/hot-spare-identity.json" ]; then
      echo "Generating hot-spare-identity.json..."
      solana-keygen new -s --no-bip39-passphrase -o "$ALPHA_DEMO_KEYS_DIR/hot-spare-identity.json"
    fi

(cat | sudo tee -a /etc/systemd/system/sol.service) <<EOF
[Unit]
Description=Solana Validator
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=5
User=sol
LimitNOFILE=1000000
LimitMEMLOCK=2000000000
LogRateLimitIntervalSec=0
Environment="PATH=/bin:/usr/bin:$HOST_SOLANA_BIN"
ExecStart=/home/sol/bin/run-validator-demo.sh

[Install]
WantedBy=multi-user.target
EOF

    # set sol service as owner of ledger, accounts, and snapshots directories
    sudo chown -R $VALIDATOR_SERVICE_USER:$VALIDATOR_SERVICE_USER /mnt/ledger
    sudo chown -R $VALIDATOR_SERVICE_USER:$VALIDATOR_SERVICE_USER /mnt/accounts
    sudo chown -R $VALIDATOR_SERVICE_USER:$VALIDATOR_SERVICE_USER /mnt/snapshots

    sudo systemctl enable --now sol
  "
}

echo
echo "---   Configuring host-alpha with the demo validator key set   ---"
echo
cleanup-host host-alpha
# docker exec -it primary bash -c 'sudo chown -R sol:sol /mnt/ledger && sudo chown -R sol:sol /mnt/accounts && sudo chown -R sol:sol /mnt/snapshots'
configure-demo-in-host host-alpha

echo
echo "---   Configuring Bravo Host as a server that is ready for, but NOT running a validator   ---"
echo
cleanup-host host-bravo
# docker exec -it secondary bash -c 'sudo chown -R sol:sol /mnt/ledger && sudo chown -R sol:sol /mnt/accounts && sudo chown -R sol:sol /mnt/snapshots'
echo "---   ALL DONE. LOCALNET IS RUNNING.   ---"
echo

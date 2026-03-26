# Bare-Metal Canary Runbook

This runbook describes a repeatable way to validate changes against a real disposable bare-metal host before merging PRs that affect production-oriented Ansible workflows.

The goal is to keep the canary path:

- close to the repo's real operator workflow
- cheap enough to run for high-risk PRs
- scoped enough that we only test what a given PR can actually break

## When To Use This

Use a real bare-metal canary when a PR changes behavior that VM or localnet validation cannot fully prove.

Typical examples:

- `pb_setup_users_validator.yml`
- `pb_setup_metal_box.yml`
- `server_initial_setup`
- `iam_manager`
- SSH / firewall / fail2ban changes
- reboot and reconnect logic
- architecture / host fact detection
- provider-specific provisioning assumptions

## Confidence Ladder

Move up the ladder only as far as the PR risk requires.

### Level 0: Static Validation

Run for every PR.

- `git diff --check`
- `ansible-playbook --syntax-check`
- `ansible-playbook --list-tasks` for touched playbooks/paths

This catches obvious YAML, templating, and role wiring issues.

### Level 1: Disposable VM Validation

Use for fast feedback on access-path and reboot changes.

Recommended paths:

- `--tags restart`
- `--tags access-validation`

This is the right level for:

- SSH port changes
- `ssh.socket` vs `ssh.service`
- UFW and fail2ban wiring
- reconnect logic
- hostname + reboot validation

### Level 2: Real Bare-Metal Bootstrap Canary

Use for PRs that touch host bootstrap and hardening.

Run only:

1. `pb_setup_users_validator.yml`
2. manual password self-service once for a disposable sysadmin user
3. `pb_setup_metal_box.yml`

This is the minimum real-host proof for bootstrap-sensitive PRs.

### Level 3: Real Bare-Metal Role Canary

Use narrow install/setup playbooks before attempting full validator setup.

Examples:

- `pb_install_rust_v2.yml`
- `pb_install_solana_cli_agave.yml`
- `pb_install_solana_cli_jito.yml`

Use this for PRs that change Rust or Solana CLI installation behavior.

### Level 4: Full Validator Host Canary

Reserve full validator setup for PRs that actually touch validator-role behavior.

Examples:

- `pb_setup_validator_agave.yml`
- `pb_setup_validator_jito_v2.yml`

Do not use this level by default for bootstrap-only changes.

## Recommended Canary Layout

Use one disposable canary ID per run.

Example:

```text
canary-20260326-bootstrap-01
```

Store all local artifacts for the run under one directory:

```bash
export CANARY_ID="canary-20260326-bootstrap-01"
export CANARY_DIR="$HOME/new-metal-box/$CANARY_ID"
mkdir -p "$CANARY_DIR"
```

Keep these local files in that directory:

- `inventory.bootstrap.yml`
- `inventory.posthardening.yml`
- `authorized_ips.csv`
- `iam_setup.csv`
- `notes.txt` or `results.md`

## Disposable Host Requirements

The disposable host should be:

- bare metal, not a VM
- Ubuntu 24.04 unless intentionally validating another OS image
- provisioned with SSH access for the initial bootstrap user, usually `ubuntu`
- disposable enough to destroy immediately after validation

Latitude is a good default provider because the repo already assumes that path operationally.

## Access Safety Rules

Before running the canary, make sure `authorized_ips.csv` includes every IP that might legitimately access the host during setup.

At minimum include:

- your current public IP
- your VPN egress IP if applicable
- any bastion IP
- any backup access path IP you may rely on

Remember that this CSV feeds both:

- UFW SSH allow rules
- fail2ban `ignoreip`

If this file is incomplete, the canary can fail for access reasons unrelated to the PR under test.

## Local CSV Preparation

### Users / Roles CSV

For canaries, it is usually simplest to reuse the same SSH public key for all disposable users so role verification stays easy.

You can generate a starting users CSV with:

```bash
./ansible-tests/scripts/generate-test-csv.sh
cp "$HOME/new-metal-box/iam_setup.csv" "$CANARY_DIR/iam_setup.csv"
```

You can also create it manually.

Example:

```csv
user,key,group_a,group_b,group_c
alice,ssh-ed25519 AAAA...,sysadmin,,
bob,ssh-ed25519 AAAA...,,validator_operators,
carla,ssh-ed25519 AAAA...,validator_viewers,,
```

### Authorized IPs CSV

Create:

```bash
cat > "$CANARY_DIR/authorized_ips.csv" <<'EOF'
ip,comment
203.0.113.10,Operator laptop
198.51.100.20,VPN egress
192.0.2.30,Bastion
EOF
```

Replace the example IPs with the real source IPs that must remain allowed.

## Inventory Templates

Use temporary inventories rather than editing committed repo inventories.

### Bootstrap Inventory

This is used before SSH hardening, while the host is still on port `22`.

```yaml
---
all:
  hosts:
    new-metal-box:
      ansible_host: <SERVER_IP>
      ansible_port: 22

  children:
    solana:
      hosts:
        new-metal-box:
```

### Post-Hardening Inventory

This is used after `pb_setup_metal_box.yml` changes the SSH port and hostname.

```yaml
---
all:
  hosts:
    <HOSTNAME>:
      ansible_host: <SERVER_IP>
      ansible_port: 2522

  children:
    solana:
      hosts:
        <HOSTNAME>:

    solana_mainnet:
      hosts:
        <HOSTNAME>:
```

If you are canarying a testnet-specific path, use `solana_testnet` instead of `solana_mainnet`.

## Bootstrap Canary Flow

Run these commands from `ansible/` unless noted otherwise.

### 1. Syntax-check the exact playbooks first

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ANSIBLE_ROLES_PATH=ansible/roles ansible-playbook \
  -i ansible/solana_localnet.yml ansible/playbooks/pb_setup_users_validator.yml \
  --syntax-check -e target_host=host-alpha -e ansible_user=bob

ANSIBLE_CONFIG=ansible/ansible.cfg ANSIBLE_ROLES_PATH=ansible/roles ansible-playbook \
  -i ansible/solana_localnet.yml ansible/playbooks/pb_setup_metal_box.yml \
  --syntax-check -e target_host=host-alpha -e ansible_user=bob
```

### 2. Create the bootstrap inventory

```bash
cat > "$CANARY_DIR/inventory.bootstrap.yml" <<EOF
---
all:
  hosts:
    new-metal-box:
      ansible_host: ${SERVER_IP}
      ansible_port: 22

  children:
    solana:
      hosts:
        new-metal-box:
EOF
```

### 3. Run user bootstrap

```bash
cd ansible
ANSIBLE_CONFIG=ansible.cfg ANSIBLE_ROLES_PATH=roles ansible-playbook \
  playbooks/pb_setup_users_validator.yml \
  -i "$CANARY_DIR/inventory.bootstrap.yml" \
  -e "target_host=new-metal-box" \
  -e "ansible_user=ubuntu" \
  -e "csv_file=$(basename "$CANARY_DIR/iam_setup.csv")" \
  -e "users_base_dir=$CANARY_DIR"
```

### 4. Perform the one manual step

SSH to the disposable sysadmin user created by the users CSV and initialize password self-service once:

```bash
ssh <sysadmin_user>@${SERVER_IP}
sudo reset-my-password
```

This is required before using `-K` on `pb_setup_metal_box.yml`.

### 5. Run metal-box hardening

```bash
ANSIBLE_CONFIG=ansible.cfg ANSIBLE_ROLES_PATH=roles ansible-playbook \
  playbooks/pb_setup_metal_box.yml \
  -i "$CANARY_DIR/inventory.bootstrap.yml" \
  -e "target_host=new-metal-box" \
  -e "ansible_user=<sysadmin_user>" \
  -e "csv_file=$(basename "$CANARY_DIR/authorized_ips.csv")" \
  -e "host_name=$CANARY_ID" \
  -K
```

### 6. Create the post-hardening inventory

```bash
cat > "$CANARY_DIR/inventory.posthardening.yml" <<EOF
---
all:
  hosts:
    ${CANARY_ID}:
      ansible_host: ${SERVER_IP}
      ansible_port: 2522

  children:
    solana:
      hosts:
        ${CANARY_ID}:

    solana_mainnet:
      hosts:
        ${CANARY_ID}:
EOF
```

### 7. Verify the hardened access path

```bash
ssh -p 2522 <sysadmin_user>@${SERVER_IP}
```

Then verify these on-host expectations:

- `ssh.service` is enabled and active
- `ssh.socket` is disabled and inactive
- SSH is listening on `2522`
- hostname matches the requested `host_name`
- `health_check.sh` exists

Suggested checks:

```bash
systemctl is-enabled ssh.service
systemctl is-active ssh.service
systemctl is-enabled ssh.socket || true
systemctl is-active ssh.socket || true
ss -ltnp | grep ':2522 '
hostnamectl --static
command -v health_check.sh
```

## Role-Specific Canary Flow

Only continue if the PR risk justifies it.

### Rust install canary

```bash
ANSIBLE_CONFIG=ansible.cfg ANSIBLE_ROLES_PATH=roles ansible-playbook \
  playbooks/pb_install_rust_v2.yml \
  -i "$CANARY_DIR/inventory.posthardening.yml" \
  -e "target_host=$CANARY_ID" \
  -e "operator_user=<validator_operator_user>"
```

### Agave CLI canary

```bash
ANSIBLE_CONFIG=ansible.cfg ANSIBLE_ROLES_PATH=roles ansible-playbook \
  playbooks/pb_install_solana_cli_agave.yml \
  -i "$CANARY_DIR/inventory.posthardening.yml" \
  -e "target_host=$CANARY_ID" \
  -e "operator_user=<validator_operator_user>" \
  -e "agave_version=<VERSION>" \
  -e "solana_cluster=mainnet" \
  -e "build_from_source=true"
```

### Jito CLI canary

```bash
ANSIBLE_CONFIG=ansible.cfg ANSIBLE_ROLES_PATH=roles ansible-playbook \
  playbooks/pb_install_solana_cli_jito.yml \
  -i "$CANARY_DIR/inventory.posthardening.yml" \
  -e "target_host=$CANARY_ID" \
  -e "operator_user=<validator_operator_user>" \
  -e "jito_version=<VERSION>" \
  -e "solana_cluster=mainnet" \
  -e "build_from_source=true"
```

## PR-Type Recommendations

Use this table to decide the minimum canary level.

| PR area | Minimum level |
| --- | --- |
| YAML / templating / docs only | Level 0 |
| SSH / firewall / reboot / hostname | Level 1 |
| bootstrap facts / IAM / metal box | Level 2 |
| Rust / Solana CLI install logic | Level 3 |
| validator role behavior | Level 4 |

Examples:

- `stack/01-ansible-bootstrap-hardening`: Level 2
- server hardening or SSH port path changes: Level 1, then Level 2 if risk is high
- Solana CLI binary download/install changes: Level 3
- validator runtime or startup template changes: Level 4

## Recording Results

For each canary run, capture:

- canary ID
- provider / plan / region
- OS image
- PR number
- commit SHA
- exact playbooks run
- whether each level passed
- any manual observations
- destroy confirmation / server teardown timestamp

This can live in:

- a local `results.md` in the canary directory
- the PR comments
- a follow-up issue if something fails

## Teardown

Destroy the host as soon as validation is complete.

If you provision manually through the provider UI, destroy it there.

If you provision through future repo-native Latitude helper scripts, prefer the scripted destroy path so the run stays auditable and repeatable.

## What This Runbook Does Not Try To Do

This runbook is intentionally narrow.

It does not:

- replace the normal VM-based validation loops
- require full validator setup for every PR
- assume a permanent canary environment
- remove the one-time manual password self-service step required by the current workflow

The purpose is to make the real-host validation path disciplined and repeatable, not fully hands-off.

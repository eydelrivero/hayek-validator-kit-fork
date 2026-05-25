# Requirements: CSV Files for Users/Roles and Authorized IPs

For testing, you will need two CSV files:

- A CSV containing the users and their roles
- A CSV containing the IPs authorized to connect to the server

These CSVs should be placed in your **local computer**:

   ~/new-metal-box/

## Example: Users and Roles CSV (`~/new-metal-box/iam_setup_dev.csv`)

> **Testing Tip:** For testing purposes only, it is recommended to use the same public key for all users in the CSV. This allows you to access the server as each user and verify their roles and permissions work as expected. Use a public key you have access to.

```csv
user,key,group_a,group_b,group_c
alice,ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexamplekeyforalice alice@example.com,sysadmin,,
bob,ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexamplekeyforbob bob@example.com,,validator_operators,
carla,ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEexamplekeyforcarla carla@example.com,validator_viewers,,
```

### Example: Authorized IPs CSV (`~/new-metal-box/authorized_ips.csv`)

```csv
ip,comment
203.0.113.1,Admin Office
198.51.100.2,VPN Gateway
192.0.2.10,Bastion Host
203.0.113.25,Emergency Access Host
203.0.113.5,Home Office
```

## Getting Started: Acquire Bare Metal

The first step is to acquire a bare metal server. It is recommended to use Latitude as a provider for best compatibility.

You can follow the necessary documentation here:
<https://docs.hayek.fi/dev-public-goods/validator-operations/host-infrastructure/choosing-your-metal#latitude-complete-provisioning>

## For testing, you can use the m4.metal.medium server

## Post-Provisioning Verifications

Once you have selected the necessary server for your tests, you should run a quick check to ensure the server meets the minimum requirements. You can follow this documentation:
<https://docs.hayek.fi/dev-public-goods/validator-operations/host-infrastructure/choosing-your-metal#post-provisioning-verifications>

## Update Inventory

**Inventory Required:**
 Before running the playbooks, edit your inventory file (`solana_new_metal_box.yml`) to set the correct IP and port for your target host:

 ```yaml
 all:
   hosts:
     new-metal-box:
       ansible_host: 192.168.1.200  # Replace with your server's IP
       ansible_port: 22
 ```

## User and Role Setup

After updating your inventory with the IP of the server to be provisioned and verifying that the server meets the minimum requirements (no RAID enabled and SMT is active), you need to create the users and roles using the playbook `pb_setup_server_users.yml`.

To execute this playbook, follow the documentation here:
<https://docs.hayek.fi/dev-public-goods/validator-operations/host-infrastructure/user-access#user-setup>

Once the users have been created on the server, to continue with the setup and testing, you must access the server with a user that belongs to the sysadmin group and provision a password using the Password Self-Service system.
See the documentation here:
<https://docs.hayek.fi/dev-public-goods/validator-operations/host-infrastructure/user-access#password-self-service>

## Server Configuration and Hardening

At this point, the server is ready to be configured.

This role automates the initial configuration and hardening of a Solana validator server, including:

- System tuning
- Disk and mount setup
- SSH and firewall configuration
- Fail2ban setup
- Pre- and post-configuration checks

For SSH, the role standardizes on `ssh.service` and disables `ssh.socket` if present, so port changes are controlled only through `/etc/ssh/sshd_config`. On Ubuntu-style socket-activated hosts, it also removes the socket-activation generator/drop-in state before starting `ssh.service`.

## Running the Playbook

1. **Prepare the authorized IPs CSV:**
   - Ensure you have the authorized IPs CSV as described in the [Requirements](#requirements-csv-files-for-usersroles-and-authorized-ips) section at the top of this documentation.
   - Include every SSH source that must never be banned during setup: bastion hosts, operator public IPs, and the real source or egress IP of any fallback access client you may need to use.
   - The same CSV is used for both the SSH firewall allowlist and fail2ban `ignoreip`.
   - Do **not** use real IPs or sensitive names in your public documentation.

2. **Run the playbook:**

 ```sh
ansible-playbook playbooks/pb_setup_metal_box.yml \
   -i solana_new_metal_box.yml \
   -e "target_host=new-metal-box" \
   -e "ansible_user=alice" \
   -e "csv_file=authorized_ips.csv" \
   -e "host_name=validator-nyc-01" \
   -K
```

> **Note:** Before running the playbook, users with the `sysadmin` role must have previously logged in and provisioned a password using the Password Self-Service system. This is required for privilege escalation (`-K` flag).
> **Note:** `host_name` is optional. If omitted, the existing hostname is kept.

## Local SSH Client Safety

Before connecting to a hardened host, pin the correct key in your local `~/.ssh/config` entry for that server:

```sshconfig
Host your-target-server
    HostName <server-ip>
    User <username>
    IdentityFile ~/.ssh/the_specific_correct_key
    IdentitiesOnly yes
```

`IdentitiesOnly yes` is important because it stops SSH, 1Password, and other agent-managed keys from being tried automatically. Repeated wrong-key attempts can hit the fail2ban retry limit and temporarily lock out your source IP.

## Reviewer Health Check Install

Use the `health-check` tag to install only the maintained-fork validator health
check script and config through the normal metal-box playbook. This gives
reviewers a small, repeatable path for testing the script without running the
full server setup.

1. Validate task selection:

   ```sh
   cd ansible
   ansible-playbook playbooks/pb_setup_metal_box.yml \
     -i <inventory> \
     -e "target_host=<host> ansible_user=<user>" \
     --list-tasks --tags health-check
   ```

   Expected: health check install tasks only.

1. Install the script and config:

   ```sh
   ansible-playbook playbooks/pb_setup_metal_box.yml \
     -i <inventory> \
     -e "target_host=<host> ansible_user=<user>" \
     -K --tags health-check
   ```

1. Verify the installed files:

   ```bash
   ansible new-metal-box \
     -i solana_new_metal_box.yml \
     -u <admin_user> \
     -b -K \
     -m stat \
     -a "path=/usr/local/bin/config.json"

   ansible new-metal-box \
     -i solana_new_metal_box.yml \
     -u <admin_user> \
     -b -K \
     -m stat \
     -a "path=/usr/local/bin/health_check.sh"

   ansible new-metal-box \
     -i solana_new_metal_box.yml \
     -u <admin_user> \
     -m command \
     -a "/usr/local/bin/health_check.sh" \
     -b -K
   ```

   The script should run on the remote host and report findings. Ansible marks
   the command red when the script returns a non-zero exit code.

The final command intentionally runs the health check. It may return a non-zero
exit code when the host has failing health checks, such as worn NVMe drives or
missing validator prerequisites. For install validation, confirm that the script
loads `/usr/local/bin/config.json` and reaches the health-check report instead of
failing with missing file, permission, or invalid config errors.

Override `health_check_ref`, `health_check_script_url`, or
`health_check_config_url` with `-e` when testing a specific branch, tag, or
artifact URL.

## Special Testnet Two-Disk Mode (Opt-In)

For exceptional testnet hosts with exactly two disks (`1 root + 1 data`), you can enable a special disk setup mode.

- Required conditions:
  - `solana_cluster=testnet`
  - `allow_unconventional_testnet_two_disk_layout=true`
- Safety rules:
  - This mode is rejected outside testnet.
  - This mode requires exactly 2 disks total.
  - Default disk setup remains unchanged unless this mode is explicitly enabled.
- Resulting layout:
  - `/mnt/accounts` is mounted on the non-root data disk.
  - `/mnt/ledger` and `/mnt/snapshots` remain on the root filesystem.

Example:

```sh
ansible-playbook playbooks/pb_setup_metal_box.yml \
  -i solana_new_metal_box.yml \
  -e "target_host=new-metal-box" \
  -e "ansible_user=alice" \
  -e "csv_file=authorized_ips.csv" \
  -e "solana_cluster=testnet" \
  -e "allow_unconventional_testnet_two_disk_layout=true" \
  -K
```

Upon running the playbook, you will see a confirmation asking you to verify the IP of the host you are about to change:

```text
TASK [Show server IP and location for confirmation] ******************************
[Show server IP and location for confirmation]
IMPORTANT: You are about to run this playbook on the server with IP: 192.168.1.100

Location Information:
- City: Unknown
- Country: Unknown
- Organization: Unknown

To continue, please type exactly this IP: 192.168.1.100

If you are not sure, press Ctrl+C to cancel.

Type IP here
```

This step is a safety measure to ensure you are provisioning the correct server. Type the IP address shown to continue. If you are not sure, press Ctrl+C to cancel the process.

## Server Reboot Countdown

At the end of the playbook, reboot is automatic after a 10-second countdown:

- Press `Ctrl+C` during the countdown to abort before reboot.
- If not aborted, the host reboots and Ansible waits for it to come back.

## Tag-Scoped Reboot and Hostname Testing

You can validate reboot-path changes on disposable VMs without running the full role.

- `host_name` remains optional and is now applied in the pre-reboot stage.
- New tag: `pre-reboot-hostname`
- Hostname pre-reboot tasks also carry `restart`, so `--tags restart` is enough.
- This restart-only path validates reboot/hostname behavior and does not apply SSH/firewall changes.

### Test Matrix (Runbook)

- Scenario A: Reboot only, no hostname change requested.
- Scenario B: Reboot with valid hostname.
- Scenario C: Reboot with invalid hostname (must fail before reboot).
- Scenario D: Idempotency spot-check by running Scenario B twice.

### Commands

1. Validate task selection:

```sh
cd ansible
ansible-playbook playbooks/pb_setup_metal_box.yml \
  -i <inventory> \
  -e "target_host=<vm_host> ansible_user=<user> csv_file=<any>.csv host_name=validator-test-01" \
  --list-tasks --tags restart
```

Expected: pre-reboot hostname tasks plus reboot tasks only.

1. Functional reboot plus hostname:

```sh
ansible-playbook playbooks/pb_setup_metal_box.yml \
  -i <inventory> \
  -e "target_host=<vm_host> ansible_user=<user> csv_file=<any>.csv host_name=validator-test-01" \
  -K --tags restart
```

1. Post-checks:

```sh
ansible <vm_host> -i <inventory> -b -m command -a "hostnamectl --static"
ansible <vm_host> -i <inventory> -b -m shell -a "grep -E '^127\.0\.1\.1[[:space:]]+validator-test-01$' /etc/hosts"
ansible <vm_host> -i <inventory> -b -m shell -a "test \"$(grep -Ec '^127\.0\.1\.1[[:space:]]+' /etc/hosts)\" -eq 1"
```

Expected: `hostnamectl --static` returns the requested hostname and `/etc/hosts` contains exactly one `127.0.1.1` entry with no stale aliases.

1. Negative validation:

```sh
ansible-playbook playbooks/pb_setup_metal_box.yml \
  -i <inventory> \
  -e "target_host=<vm_host> ansible_user=<user> csv_file=<any>.csv host_name=-badname-" \
  -K --tags restart
```

Expected: hostname assertion fails and reboot is not triggered.

## VM Access-Path Validation for SSH / Firewall Changes

Use the dedicated `access-validation` tag to exercise the SSH/firewall/reboot flow on a disposable VM without pulling in the Solana hardware prechecks.

- This path includes the CSV access precheck, security tasks, and restart tasks.
- It intentionally skips the CPU and disk validation blocks that are meant for production-grade validator hosts.
- It is the recommended way to validate the `flush_handlers` plus `ssh.socket` fix on VirtualBox-style test machines.

### Before You Run

- Take a VM snapshot first.
- Ensure `authorized_ips.csv` contains the IP you are connecting from, any bastion IPs, and the real source or egress IP of any fallback access client, such as a bastion, VPN, or Instance Connect path.
- Keep your inventory on the VM's current SSH port before the first run so Ansible has to perform the real port switch.
- If the VM has `ssh.socket`, leave it enabled before the first run so the fix is exercised.
- Add a host entry in your local `~/.ssh/config` with `IdentityFile` and `IdentitiesOnly yes` so your SSH client does not burn retries by offering unrelated keys.

### SSH / Firewall Changes Commands

1. Validate task selection:

```sh
cd ansible
ansible-playbook playbooks/pb_setup_metal_box.yml \
  -i <inventory> \
  -e "target_host=<vm_host> ansible_user=<user> csv_file=<any>.csv host_name=validator-test-01" \
  --list-tasks --tags access-validation
```

Expected: CSV access precheck tasks, SSH/firewall tasks, and restart tasks only.

1. Functional access-path run:

```sh
ansible-playbook playbooks/pb_setup_metal_box.yml \
  -i <inventory> \
  -e "target_host=<vm_host> ansible_user=<user> csv_file=<any>.csv host_name=validator-test-01" \
  -K --tags access-validation
```

1. Post-run verification:

```sh
ansible <vm_host> -i <inventory_after_port_change> -b -m command -a "systemctl is-enabled ssh.service"
ansible <vm_host> -i <inventory_after_port_change> -b -m command -a "systemctl is-active ssh.service"
ansible <vm_host> -i <inventory_after_port_change> -b -m command -a "systemctl is-enabled ssh.socket"
ansible <vm_host> -i <inventory_after_port_change> -b -m command -a "systemctl is-active ssh.socket"
ansible <vm_host> -i <inventory_after_port_change> -b -m command -a "ss -ltnp | grep ':2522 '"
ansible <vm_host> -i <inventory_after_port_change> -b -m command -a "grep '^ignoreip =' /etc/fail2ban/jail.d/defaults-debian.conf"
```

Expected:

- `ssh.service` is enabled and active.
- `ssh.socket` is disabled and not active.
- SSH is listening on the configured nonstandard port.
- `ignoreip` contains localhost plus every IP from `authorized_ips.csv`.

1. Idempotency spot-check:

```sh
ansible-playbook playbooks/pb_setup_metal_box.yml \
  -i <inventory_after_port_change> \
  -e "target_host=<vm_host> ansible_user=<user> csv_file=<any>.csv host_name=validator-test-01" \
  -K --tags access-validation
```

Expected: the second run completes cleanly with no reconnect drama even though the host is already on the target SSH port.

## CPU Isolation Validation

Use the dedicated validation playbook to compute and display the CPU-isolation
GRUB line without modifying the host.

- Playbook: `playbooks/pb_validate_cpu_isolation.yml`
- This path reuses `tasks/set_cpu_isolation.yml` from the `server_initial_setup`
  role.
- It gathers the live CPU topology from the target host, computes the PoH SMT
  sibling and `irqaffinity`, and prints the exact
  `GRUB_CMDLINE_LINUX_DEFAULT="..."` line that a real run would write.
- It does not install packages, edit `/etc/default/grub`, or run `update-grub`.
- It supports `--check` because the topology-gathering tasks are explicitly
  allowed to run in check mode.

### CPU Isolation Commands

1. Validate task selection:

```sh
cd ansible
ansible-playbook playbooks/pb_validate_cpu_isolation.yml \
  -i <inventory> \
  -e "target_host=<host> ansible_user=<user>" \
  --list-tasks
```

Expected: preflight assertions plus CPU-isolation tasks only.

1. Functional validation run:

```sh
ansible-playbook playbooks/pb_validate_cpu_isolation.yml \
  -i <inventory> \
  -e "target_host=<host> ansible_user=<user>" \
  -K
```

1. Validation run in check mode:

```sh
ansible-playbook playbooks/pb_validate_cpu_isolation.yml \
  -i <inventory> \
  -e "target_host=<host> ansible_user=<user>" \
  -K --check
```

Expected output includes:

- PoH core
- HT sibling
- Total logical CPUs
- Computed `irqaffinity`
- Final rendered `GRUB_CMDLINE_LINUX_DEFAULT="..."`

Example expected output on the AMD EPYC 9374F case with `cpu_config.poh_core=2`:

- PoH core: `2`
- HT sibling: `34`
- Total logical CPUs: `64`
- IRQ affinity: `0-1,3-33,35-63`
- Final line:
  `GRUB_CMDLINE_LINUX_DEFAULT="quiet audit=1 audit_backlog_limit=8192 intel_idle.max_cstate=0 processor.max_cstate=0 amd_pstate=active nohz_full=2,34 isolcpus=domain,managed_irq,2,34 irqaffinity=0-1,3-33,35-63"`

## After Playbook Completion

At the end of the playbook, the server will be rebooted automatically. You must reconnect using:

```sh
ssh alice@203.0.113.10 -p 2522
```

Replace the example values with your actual user, server IP, and port as configured.

Note: If your user belongs to the `validator_operators` or `sysadmin` group, you will be able to use the Password Self-Service by following the instructions on the welcome screen after logging in.

To verify that the server has the optimal configuration for a Solana validator, you can use the health_check script:

```sh
health_check.sh
```

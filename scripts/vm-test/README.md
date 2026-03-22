# VM test harness (macOS + Linux)

This harness spins up disposable Ubuntu VMs with extra disks so you can run the full metal-box playbook safely. It supports:
- Intel macOS: amd64 Ubuntu images
- Apple Silicon macOS: arm64 Ubuntu images
- Linux x86_64: amd64 Ubuntu images (KVM when available)
- Linux arm64: arm64 Ubuntu images (KVM when available)

Note: `cpu-isolation` is already skipped on non-x86_64, so arm64 runs will not try to modify GRUB.

## Prereqs

- QEMU (via Homebrew or UTM)
- cloud-init ISO tooling (`cloud-localds` or `xorriso`)
- ssh client
- ansible

Ubuntu 24.04 package install:

```bash
sudo apt update
sudo apt install -y qemu-system-x86 qemu-system-arm qemu-utils cloud-image-utils ansible
```

If you use UTM, make sure `qemu-system-*` binaries are on your PATH (UTM ships them).

Common Homebrew install:

```bash
brew install qemu xorriso
```

If you already have `cloud-localds` (Linux package `cloud-utils`), the harness will use it. Otherwise it falls back to `xorriso`.

## Files created by this harness

All VM artifacts live in `scripts/vm-test/work/` and are ignored by git.

## Quick start (Intel macOS / amd64)

1) Download an Ubuntu amd64 cloud image:

```bash
mkdir -p scripts/vm-test/work
curl -L -o scripts/vm-test/work/ubuntu-amd64.img \
  https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

2) Create an SSH key for the VM:

```bash
ssh-keygen -t ed25519 -f scripts/vm-test/work/id_ed25519 -N ""
```

3) Create the seed ISO and disks:

```bash
./scripts/vm-test/make-seed.sh vm-amd64 "$(cat scripts/vm-test/work/id_ed25519.pub)"
./scripts/vm-test/create-disks.sh amd64 vm-amd64 scripts/vm-test/work/ubuntu-amd64.img
```

Optional disk size overrides (GiB):

```bash
VM_DISK_SYSTEM_GB=80 \
VM_DISK_LEDGER_GB=200 \
VM_DISK_ACCOUNTS_GB=100 \
VM_DISK_SNAPSHOTS_GB=50 \
./scripts/vm-test/create-disks.sh amd64 vm-amd64 scripts/vm-test/work/ubuntu-amd64.img
```

4) Boot the VM:

```bash
./scripts/vm-test/run-qemu-amd64.sh vm-amd64
```

5) SSH in:

```bash
./scripts/vm-test/wait-for-ssh.sh 127.0.0.1 2222
ssh -i scripts/vm-test/work/id_ed25519 -p 2222 ubuntu@127.0.0.1
```

## Quick start (Apple Silicon / arm64)

1) Download an Ubuntu arm64 cloud image:

```bash
mkdir -p scripts/vm-test/work
curl -L -o scripts/vm-test/work/ubuntu-arm64.img \
  https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img
```

2) Create an SSH key for the VM:

```bash
ssh-keygen -t ed25519 -f scripts/vm-test/work/id_ed25519 -N ""
```

3) Create the seed ISO and disks:

```bash
./scripts/vm-test/make-seed.sh vm-arm64 "$(cat scripts/vm-test/work/id_ed25519.pub)"
./scripts/vm-test/create-disks.sh arm64 vm-arm64 scripts/vm-test/work/ubuntu-arm64.img
```

Optional disk size overrides (GiB):

```bash
VM_DISK_SYSTEM_GB=80 \
VM_DISK_LEDGER_GB=200 \
VM_DISK_ACCOUNTS_GB=100 \
VM_DISK_SNAPSHOTS_GB=50 \
./scripts/vm-test/create-disks.sh arm64 vm-arm64 scripts/vm-test/work/ubuntu-arm64.img
```

4) Boot the VM:

```bash
./scripts/vm-test/run-qemu-arm64.sh vm-arm64
```

5) SSH in:

```bash
./scripts/vm-test/wait-for-ssh.sh 127.0.0.1 2222
ssh -i scripts/vm-test/work/id_ed25519 -p 2222 ubuntu@127.0.0.1
# if you get: Received disconnect from 127.0.0.1 port 2222:2: Too many authentication failures
ssh -o IdentitiesOnly=yes -o IdentityAgent=none \
  -i scripts/vm-test/work/id_ed25519 -p 2222 ubuntu@127.0.0.1
```

## Quick start (Ubuntu 24.04 / shared bridge)

1) Install the Linux prereqs:

```bash
sudo apt update
sudo apt install -y qemu-system-x86 qemu-system-arm qemu-utils cloud-image-utils ansible
```

For VM hot-swap and localnet-backed verifier flows, the host also needs Solana
CLI tools on `PATH`:
- `solana`
- `solana-keygen`
- `solana-test-validator`

These are host-side harness dependencies used for localnet control-plane work
and key generation. They are separate from the Solana CLI that gets installed
inside the disposable VMs.

2) Download a same-arch cloud image for the host. On x86_64, prefer amd64:

```bash
mkdir -p scripts/vm-test/work
curl -L -o scripts/vm-test/work/ubuntu-amd64.img \
  https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

3) Create the host-only bridge and tap devices.

This helper also enables IPv4 forwarding and installs idempotent `iptables`
NAT/forward rules so bridge-attached guests can reach the internet through the
host uplink. It auto-detects the default-route interface and a host DNS server,
and prints the `VM_BRIDGE_DNS_IP` export to use for guests.

```bash
./scripts/vm-test/setup-shared-bridge.sh
```

If auto-detection picks the wrong uplink or DNS server, override them:

```bash
VM_BRIDGE_UPLINK_IFACE=enp3s0 \
VM_BRIDGE_DNS_IP=1.1.1.1 \
./scripts/vm-test/setup-shared-bridge.sh
```

The helper applies live host firewall/NAT state; rerun it after reboot unless
you persist equivalent rules separately.

4) Run the hot-swap verifier with the dedicated entrypoint VM on the same bridge:

```bash
VM_NETWORK_MODE=shared-bridge \
VM_LOCALNET_ENTRYPOINT_MODE=vm \
VM_SOURCE_BRIDGE_IP=192.168.100.11 \
VM_DESTINATION_BRIDGE_IP=192.168.100.12 \
ENTRYPOINT_VM_BRIDGE_IP=192.168.100.13 \
VM_BRIDGE_GATEWAY_IP=192.168.100.1 \
VM_BRIDGE_DNS_IP=1.1.1.1 \
VM_SOURCE_TAP_IFACE=tap-hvk-src \
VM_DESTINATION_TAP_IFACE=tap-hvk-dst \
ENTRYPOINT_VM_TAP_IFACE=tap-hvk-ent \
ENTRYPOINT_VM_SKIP_CLI_INSTALL=auto \
AGAVE_VERSION=3.1.10 \
BAM_JITO_VERSION=3.1.10 \
BUILD_FROM_SOURCE=false \
./test-harness/scripts/verify-vm-hot-swap.sh \
  --source-flavor agave \
  --destination-flavor jito-bam \
  --vm-arch amd64 \
  --vm-base-image scripts/vm-test/work/ubuntu-amd64.img
```

Before running, confirm the host-side Solana CLI tools are available:

```bash
solana --version
solana-keygen --version
solana-test-validator --version
```

If you intentionally run `--vm-arch arm64` on an x86_64 host, QEMU falls back to TCG emulation. That works only after installing `qemu-system-arm`, and it is materially slower than using an amd64 guest on an amd64 host.

## Troubleshooting

- If bridge-attached guests fail DNS lookups or cannot reach the internet, rerun `./scripts/vm-test/setup-shared-bridge.sh` and confirm it selected the correct uplink and DNS server. The shared-bridge path requires host-side NAT/forwarding plus a reachable `VM_BRIDGE_DNS_IP`.
- QEMU runs in the foreground; use a second terminal for SSH. To stop QEMU, press `Ctrl+A` then `X`.
- Use `./scripts/vm-test/wait-for-ssh.sh` before SSH/Ansible to avoid transient connection resets while `sshd`, UFW, or fail2ban are still settling.
- If the arm64 VM shows no boot logs, you likely need UEFI firmware. The script auto-detects it, but you can set it explicitly:

```bash
QEMU_EFI=/opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  ./scripts/vm-test/run-qemu-arm64.sh vm-arm64
```

- If SSH hangs, wait 60–120 seconds for cloud-init to finish on first boot and retry.
- If SSH says `REMOTE HOST IDENTIFICATION HAS CHANGED`, remove stale entries for the forwarded localhost ports and reconnect:

```bash
ssh-keygen -R "[127.0.0.1]:2222"
ssh-keygen -R "[127.0.0.1]:2522"
```

## Prepare the authorized IPs CSV

The `security` tasks enforce UFW allow rules for SSH. With QEMU user-mode networking, the host shows up as `10.0.2.2` inside the VM. This repo includes a sample CSV:

```
cp scripts/vm-test/sample-authorized-ips.csv scripts/vm-test/work/authorized_ips.csv
```

Copy it into the VM:

```bash
./scripts/vm-test/wait-for-ssh.sh 127.0.0.1 2222
ssh -i scripts/vm-test/work/id_ed25519 -p 2222 ubuntu@127.0.0.1 "mkdir -p /home/ubuntu/new-metal-box"
scp -i scripts/vm-test/work/id_ed25519 -P 2222 \
  scripts/vm-test/work/authorized_ips.csv \
  ubuntu@127.0.0.1:/home/ubuntu/new-metal-box/authorized_ips.csv
```

## Run the playbook

Update the inventory to match your SSH port (defaults to 2222 and 2522 forwarded):

```bash
sed -n '1,20p' scripts/vm-test/inventory.vm.yml
```

Run the full playbook:

```bash
./scripts/vm-test/wait-for-ssh.sh 127.0.0.1 2222
ansible-playbook playbooks/pb_setup_metal_box.yml \
  -i scripts/vm-test/inventory.vm.yml \
  -e "target_host=vm-local" \
  -e "ansible_user=ubuntu" \
  -e "csv_file=authorized_ips.csv" \
  -K
```

After the SSH port changes to 2522, use:

```bash
./scripts/vm-test/wait-for-ssh.sh 127.0.0.1 2522
ssh -i scripts/vm-test/work/id_ed25519 -p 2522 ubuntu@127.0.0.1
```

If you re-run Ansible after the port change, update `ansible_port` in `scripts/vm-test/inventory.vm.yml` to `2522`.

## FAQ

- Is `10.0.2.2` another VM? No. With QEMU user-mode NAT, `10.0.2.2` is the host machine as seen from inside the VM. It is not a separate VM.
- Where do I run the playbook? On your host machine, from the repo root (the same place you run the scripts). The inventory points to the VM via `127.0.0.1:2222`.
- Why copy the authorized IPs CSV into the VM? The role reads the CSV from the target host (`~/new-metal-box/{{ csv_file }}`), so it must exist on the VM.
- What password does `-K` use? The VM user (`ubuntu`) password. In this harness the user is configured for passwordless sudo, so you can enter an empty password or just press Enter. If that fails, confirm `/etc/sudoers` in the VM allows passwordless sudo.

## Verify

```bash
ansible-playbook -i scripts/vm-test/inventory.vm.yml scripts/vm-test/verify.yml -K
```

## Notes

- The QEMU run scripts forward both `2222 -> 22` and `2522 -> 2522` to avoid lockout after the SSH port changes.
- If you want different ports, set `SSH_PORT` and `SSH_PORT_ALT` when running the VM scripts.
- Default VM resources are `CPUS=4`, `RAM_MB=4096`, and disk sizes `40/20/10/5` GiB. Override with env vars as needed.
- The QEMU launcher scripts now auto-select `hvf` on macOS, `kvm` on same-arch Linux when `/dev/kvm` is usable, and `tcg` otherwise. Override with `QEMU_ACCEL` or `QEMU_CPU` if you need to force a mode.

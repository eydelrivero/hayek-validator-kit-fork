# Test Harness

This directory contains a substrate-agnostic harness to run validator scenarios across:
- `compose`
- `vm`
- `latitude`

The harness wraps existing workflows from:
- `solana-localnet/tests/`
- `scripts/vm-test/`
- `bare-metal/latitudesh/`

Host-side prerequisites for VM localnet and hot-swap flows include:
- QEMU + cloud-init tooling + Ansible
- Docker for compose-backed control-plane paths when used
- Solana CLI tools on the host `PATH`: `solana`, `solana-keygen`, `solana-test-validator`

Host-side prerequisites for Latitude flows include:
- Latitude CLI `lsh`
- Ansible
- `jq`
- one SSH keypair that can be uploaded for the disposable host

## Entry Point

```bash
./test-harness/bin/hvk-test --help
```

## Quick Examples

List supported targets/scenarios/profiles:

```bash
./test-harness/bin/hvk-test list
```

Describe target capabilities:

```bash
./test-harness/bin/hvk-test describe --target vm --scenario agave_only --json
```

Run compose with teardown:

```bash
./test-harness/bin/hvk-test run \
  --target compose \
  --scenario agave_only
```

Run VM with explicit resources:

```bash
./test-harness/bin/hvk-test run \
  --target vm \
  --scenario agave_only \
  --vm-profile medium \
  --vm-cpus 8 \
  --vm-ram-mb 16384 \
  --vm-disk-system-gb 80 \
  --vm-disk-ledger-gb 200 \
  --vm-disk-accounts-gb 100 \
  --vm-disk-snapshots-gb 50
```

For VM target scenarios, `hvk-test run` now applies default verification when
`--verify-cmd` is omitted:
- `pb_setup_users_validator` (first)
- `pb_setup_metal_box` (second)
- `pb_setup_validator_agave` or `pb_setup_validator_jito_v2` (by scenario flavor)

This order is intentional to preserve the current operational workflow.

### VM Access-Validation Suite

For focused VM coverage of PR #212 (`server_initial_setup` SSH/firewall/reboot
transition), the recommended one-command entrypoint is:

```bash
./test-harness/scripts/run-vm-access-validation.sh \
  --vm-arch amd64 \
  --vm-base-image scripts/vm-test/work/ubuntu-amd64.img
```

This wrapper:
- boots a disposable VM in the background
- waits for bootstrap SSH
- runs `verify-vm-access-validation.sh`
- tears the VM down automatically on success
- retains the VM only when `--retain-on-failure` or `--retain-always` is used

Useful options:

```bash
./test-harness/scripts/run-vm-access-validation.sh \
  --vm-arch amd64 \
  --vm-base-image scripts/vm-test/work/ubuntu-amd64.img \
  --host-name validator-test-01 \
  --retain-on-failure
```

If you already have a VM inventory and only want the verifier, use:

```bash
./test-harness/scripts/verify-vm-access-validation.sh \
  --inventory <path-to-vm-inventory>
```

If you are using the stock VM test flow, this works directly with
`scripts/vm-test/inventory.vm.yml`:

```bash
./test-harness/scripts/verify-vm-access-validation.sh \
  --inventory scripts/vm-test/inventory.vm.yml
```

Optional examples:

```bash
./test-harness/scripts/verify-vm-access-validation.sh \
  --inventory <path-to-vm-inventory> \
  --target-host vm-local \
  --host-name validator-test-01
```

This verifier intentionally stays separate from the existing hot-swap suites. It:
- runs `pb_setup_users_validator` once
- runs `pb_setup_metal_box --tags access-validation` twice
- asserts `ssh.service` is enabled and active after each run
- asserts `ssh.socket` is disabled and inactive after each run when the unit exists
- asserts SSH is listening on the configured post-metal port (`2522` by default)
- requires a real first-run port switch by keeping the bootstrap inventory on the old SSH port

By default it also requires the VM to start with an active `ssh.socket`, because
that is the upstream regression path PR #212 is fixing. You can relax that guard
for post-state-only checks with:

```bash
REQUIRE_SSH_SOCKET_PRECONDITION=false \
./test-harness/scripts/verify-vm-access-validation.sh \
  --inventory <path-to-vm-inventory>
```

Artifacts and probe output are written under `vm-access-validation/` next to the
inventory by default, or under `--workdir <path>` if provided.

### Latitude L2 Access-Validation Suite

For disposable real bare-metal coverage of the same SSH / firewall / reboot path,
use the Latitude wrapper:

```bash
./test-harness/scripts/run-latitude-access-validation.sh \
  --operator-name <operator-name> \
  --operator-ssh-public-key-file ~/.ssh/id_ed25519.pub \
  --operator-ssh-private-key-file ~/.ssh/id_ed25519
```

This flow:

- provisions one disposable Latitude host
- generates a trusted-IP CSV from the current public IP by default
- runs `pb_setup_users_validator`
- applies a disposable-host-only temporary `NOPASSWD` sudo policy for harness automation
- runs `pb_setup_metal_box --tags access-validation` twice
- asserts the post-hardening SSH state after each pass
- tears the host down automatically unless retention is requested

Useful options:

```bash
./test-harness/scripts/run-latitude-access-validation.sh \
  --operator-name <operator-name> \
  --operator-ssh-public-key-file ~/.ssh/id_ed25519.pub \
  --operator-ssh-private-key-file ~/.ssh/id_ed25519 \
  --plan m4-metal-medium \
  --retain-on-failure
```

If you already have a Latitude inventory and only want the verifier:

```bash
./test-harness/scripts/verify-latitude-access-validation.sh \
  --inventory <path-to-latitude-inventory>
```

Optional trusted IP handling:

```bash
./test-harness/scripts/verify-latitude-access-validation.sh \
  --inventory <path-to-latitude-inventory> \
  --authorized-ip <bastion-ip> \
  --authorized-ip <vpn-egress-ip>
```

If `--authorized-ips-csv` is omitted, the verifier auto-detects the current
public IP and writes a temporary CSV for the canary run.

### Latitude L3 Role Canary Suite

For disposable real bare-metal role-level canaries after users + metal-box
bootstrap, use:

```bash
./test-harness/scripts/run-latitude-role-canary.sh \
  --operator-name <operator-name> \
  --operator-ssh-public-key-file ~/.ssh/id_ed25519.pub \
  --operator-ssh-private-key-file ~/.ssh/id_ed25519 \
  --mode agave-cli
```

Supported modes:

- `rust`
- `agave-cli`
- `jito-cli`
- `agave-validator`
- `jito-validator`

Current recommendation:

- use `rust`, `agave-cli`, and `jito-cli` as the default real-metal L3 confidence path
- use `agave-validator` and `jito-validator` only when the disposable host has the
  usual validator key material and cluster-specific inputs available

This keeps the real-metal harness useful immediately without pretending full
validator bring-up is always possible on a disposable host.

### VM Two-Host Hot-Swap Matrix

To run full two-host VM identity-transfer tests (including
`pb_hot_swap_validator_hosts_v2`), use:

```bash
./test-harness/scripts/run-vm-hot-swap-matrix.sh \
  --vm-arch arm64 \
  --vm-base-image scripts/vm-test/work/ubuntu-arm64.img
```

This flow performs:
- `pb_setup_users_validator`
- `pb_setup_metal_box`
- flavor setup (`pb_setup_validator_agave` / `pb_setup_validator_jito_v2`)
- `pb_hot_swap_validator_hosts_v2`

### VM L2 Guardrail Suite

For adversarial VM checks that assert swap guardrails (expected failures), use:

```bash
./test-harness/scripts/run-vm-hot-swap-l2-guardrails.sh \
  --vm-arch amd64 \
  --vm-base-image scripts/vm-test/work/ubuntu-amd64.img
```

To run a single adversarial case during iteration:

```bash
./test-harness/scripts/run-vm-hot-swap-l2-guardrails.sh \
  --only-case catchup_guard_entrypoint_down \
  --stop-on-error \
  --vm-arch amd64 \
  --vm-base-image scripts/vm-test/work/ubuntu-amd64.img
```

L2 defaults to:
- `VM_NETWORK_MODE=shared-bridge`
- `VM_LOCALNET_ENTRYPOINT_MODE=vm`
- `SHARED_ENTRYPOINT_VM=false` (default: do not reuse mutable entrypoint runtime across cases)
- `ENTRYPOINT_CLI_IMMUTABLE_CACHE_ROOT=./test-harness/work/_vm-immutable-cache/entrypoint-vm-cli` (reuse stateless entrypoint CLI-only VM disks across L2/L3 runs)
- `REUSE_PREPARED_VMS=true` (prepare source/destination once, then run each case from qcow2 overlays)
- `IMMUTABLE_VM_CACHE_ROOT=./test-harness/work/_vm-immutable-cache` (shared immutable prepared-cache root reused by L2/L3)
- `PRUNE_MUTABLE_CACHE_DIRS=auto` (when `SHARED_ENTRYPOINT_VM=false`, prune legacy mutable caches before runs)
- bridge/tap tuple:
  - source `192.168.100.11` / `tap-hvk-src`
  - destination `192.168.100.12` / `tap-hvk-dst`
  - entrypoint `192.168.100.13` / `tap-hvk-ent`
  - gateway `192.168.100.1`

These can still be overridden via environment variables.
Use `--shared-entrypoint` to opt into reusing a single mutable entrypoint VM across cases.
Without `--shared-entrypoint`, each case still gets an isolated entrypoint VM runtime, but the VM boots from immutable CLI-prepared parent disks so CLI reinstall is skipped.
Use `--no-vm-reuse` to disable prepared source/destination cache reuse.
Use `--refresh-vm-reuse` to rebuild the prepared cache before running cases.
Use `--inspect-on-instability` to pause before the automatic cache-refresh retry when a recoverable warmup/catchup instability is detected.
In inspect mode, L2 forces `--retain-on-failure` for that run so failed-attempt VMs remain reachable for SSH inspection.

Example debug run (single case):

```bash
./test-harness/scripts/run-vm-hot-swap-l2-guardrails.sh \
  --only-case swap_precheck_interhost_ssh_blocked \
  --stop-on-error \
  --inspect-on-instability \
  --vm-arch amd64 \
  --vm-base-image scripts/vm-test/work/ubuntu-amd64.img
```

Current L2 cases:
- Catchup gate blocks swap when entrypoint RPC is intentionally stopped before pre-swap checks.
- Swap precheck fails when destination `primary-target-identity.json` is intentionally mismatched.
- Swap precheck fails when source-to-destination SSH (`:2522`) is intentionally blocked.

These tests rely on `PRE_SWAP_INJECTION_MODE` hooks in `verify-vm-hot-swap.sh` and assert:
- harness exits non-zero
- `checks_passed.pre_swap_runtime_and_client` matches expectation
- `checks_passed.hot_swap_playbook_completed` matches expectation
- expected failure signal appears in console/report output

### VM L3 End-to-End Suite

For slow end-to-end regression runs:

Canary single case:

```bash
./test-harness/scripts/run-vm-hot-swap-l3-e2e.sh \
  --mode canary \
  --source-flavor agave \
  --destination-flavor jito-bam \
  --vm-arch amd64 \
  --vm-base-image scripts/vm-test/work/ubuntu-amd64.img
```

Full flavor matrix:

```bash
./test-harness/scripts/run-vm-hot-swap-l3-e2e.sh \
  --mode matrix \
  --vm-arch amd64 \
  --vm-base-image scripts/vm-test/work/ubuntu-amd64.img
```

L3 uses the same shared-bridge + entrypoint-VM defaults as L2, including `SHARED_ENTRYPOINT_VM=false`.
L3 now reuses prepared source/destination VM caches by default (per flavor-pair and image/arch key):
- disable with `--no-vm-reuse`
- force rebuild with `--refresh-vm-reuse`
- override cache namespace with `--prepared-cache-key <text>`
- immutable cache root is shared with L2 via `IMMUTABLE_VM_CACHE_ROOT` (default: `./test-harness/work/_vm-immutable-cache`)
- immutable stateless entrypoint CLI cache is also shared with L2 via `ENTRYPOINT_CLI_IMMUTABLE_CACHE_ROOT` (default: `./test-harness/work/_vm-immutable-cache/entrypoint-vm-cli`)
- `PRUNE_MUTABLE_CACHE_DIRS=auto` by default (with `SHARED_ENTRYPOINT_VM=false`, this prunes legacy mutable caches before runs)
- on same-arch Linux hosts, L3 now fails fast if QEMU would fall back to slow TCG emulation instead of KVM; if you intentionally want that slow path, override with `ALLOW_SAME_ARCH_TCG=true`

### VM Manual Cluster Bring-Up / Teardown

To bring up the same VM environment used by the L3 canary flow, but stop before
the hot-swap playbook so you can test manually:

```bash
./test-harness/scripts/run-vm-hot-swap-manual-cluster.sh \
  --vm-arch amd64 \
  --vm-base-image scripts/vm-test/work/ubuntu-amd64.img
```

This script:
- reuses the same immutable entrypoint and prepared validator caches as L3
- retains the case automatically
- writes the current cluster state to `./test-harness/work/manual-vm-cluster/current.env`

To tear down that retained cluster, or any other harness-owned retained VMs:

```bash
./test-harness/scripts/teardown-harness-vms.sh
```

Add `--purge-case-dir` if you also want to remove the retained run directory
after manual-cluster shutdown.

### VM Run Retention / Disk Control

To avoid manual cleanup during repeated VM runs, L2/L3 now auto-prune old run directories before execution:
- keep newest `6` runs per suite root
- keep newest `1` manual-cluster run under `test-harness/work/vm-hot-swap-manual`
- additionally prune oldest runs until at least `40GB` is free under `test-harness/work`
- suite roots are auto-discovered from top-level `test-harness/work/vm-*` directories
- cache directories prefixed with `_` (for example `_shared-entrypoint-vm`, `_prepared-vms`) are preserved by the pruner

Override via environment or flags:
- `PRUNE_OLD_RUNS=false` or `--no-prune`
- `PRUNE_KEEP_RUNS=<n>` or `--prune-keep-runs <n>`
- `MANUAL_KEEP_RUNS=<n>` or `--manual-keep-runs <n>`
- `PRUNE_MIN_FREE_GB=<n>` or `--prune-min-free-gb <n>`
- `PRUNE_MUTABLE_CACHE_DIRS=true|false|auto` or `--prune-mutable-caches` / `--no-prune-mutable-caches`
- `KILL_STALE_QEMU=false` or `--no-kill-stale-qemu` (default behavior is to clear stale QEMU processes that still hold the shared tap interfaces)

You can also run the pruner directly:

```bash
./test-harness/scripts/prune-vm-test-runs.sh \
  --work-root test-harness/work \
  --keep-runs 6 \
  --manual-keep-runs 1 \
  --min-free-gb 40 \
  --prune-mutable-cache-dirs
```

### VM Directory Ownership

Current split is intentional and should stay for now:
- `scripts/vm-test/`: substrate primitives (qemu launchers, disk/seed/network helpers, cloud-init assets).
- `test-harness/`: suite orchestration (scenarios, profiles, matrix/suite runners, reporting, CI-facing entrypoints).

This keeps VM runtime mechanics reusable outside harness flows while letting the
harness evolve independently as a test suite.

### VM Localnet Entrypoint Behavior

For `SOLANA_CLUSTER=localnet`, VM verifier scripts now load cluster-specific vars from:
- `ansible/group_vars/solana_localnet.yml` (or `solana_<cluster>.yml` for other clusters)

They also support localnet entrypoint modes:
- `VM_LOCALNET_ENTRYPOINT_MODE=auto` (default): use a compose-managed control plane on the host (`gossip-entrypoint-vm` + `ansible-control-vm`).
- `VM_LOCALNET_ENTRYPOINT_MODE=container`: force the same compose-managed control-plane path.
- `VM_LOCALNET_ENTRYPOINT_MODE=vm`: use the legacy isolated entrypoint VM path.
- `VM_LOCALNET_ENTRYPOINT_MODE=host`: use the older host-local `solana-test-validator` path.
- `VM_LOCALNET_ENTRYPOINT_MODE=external`: require an already-running entrypoint; do not start one.

Compose-managed entrypoint mode uses Docker or Podman on the host and reuses the
same `gossip-entrypoint` and `ansible-control` image contracts as the compose stack.
The harness auto-detects:
- `docker` first
- `podman` second

You can override that with:
- `VM_LOCALNET_ENTRYPOINT_ENGINE=docker`
- `VM_LOCALNET_ENTRYPOINT_ENGINE=podman`

Default VM-facing entrypoint values:
- RPC for control-plane commands: `http://127.0.0.1:8899`
- Gossip entrypoint passed to validators: `10.0.2.2:8001`

When using the host-local `solana-test-validator` path, the harness uses a separate host-side
gossip bind/advertise address by default:
- `VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_PROCESS=127.0.0.1`

When using the compose-managed or isolated entrypoint path, validators still connect to the VM-facing
gateway address by default:
- `VM_LOCALNET_ENTRYPOINT_GOSSIP_HOST_FOR_VMS=10.0.2.2`

In compose-managed mode, the harness publishes the selected entrypoint ports on the host and
maps them into the standard localnet service ports inside `gossip-entrypoint-vm`, while
`ansible-control-vm` shares that network namespace and provides the same control-plane
readiness checks used by the existing compose stack.

### Shared-Bridge VM Networking

The VM harness also supports a bridge-oriented mode for validator VMs:
- `VM_NETWORK_MODE=shared-bridge`

This is intended to avoid the current double-NAT path:
- `QEMU usernet -> host -> Docker Desktop -> control plane`

When `VM_NETWORK_MODE=shared-bridge` is used, the validator VMs can boot with:
- static guest IPs via cloud-init network-config
- QEMU `tap` networking instead of `-nic user`
- direct host-to-guest SSH over the bridge (no localhost port-forward dependency)
- host-routed outbound egress when the host bridge is configured with NAT/forwarding

Required environment for this mode:
- `VM_SOURCE_BRIDGE_IP`
- `VM_DESTINATION_BRIDGE_IP`
- `VM_BRIDGE_GATEWAY_IP`
- `VM_SOURCE_TAP_IFACE`
- `VM_DESTINATION_TAP_IFACE`

Optional:
- `VM_BRIDGE_DNS_IP`
- `VM_BRIDGE_CIDR_PREFIX` (default: `24`)
- `VM_NETWORK_MATCH_NAME` (default: `e*`)

Host requirement:
- The bridge host must provide IPv4 forwarding/NAT from the bridge subnet to the real uplink, and guests need a reachable DNS server. `./scripts/vm-test/setup-shared-bridge.sh` configures idempotent `iptables` NAT/forward rules for the detected default-route interface and prints the `VM_BRIDGE_DNS_IP` export to use.
- For localnet-backed VM verifier flows, the host also needs `solana`, `solana-keygen`, and `solana-test-validator` available on `PATH`.

Current limitation:
- `VM_NETWORK_MODE=shared-bridge` supports `VM_LOCALNET_ENTRYPOINT_MODE=host`, `external`, or `vm`.
- The compose-managed control plane (`auto` / `container`) remains behind Docker Desktop NAT and is not attached to the same bridge.

For a dedicated bridge-attached entrypoint VM, also set:
- `VM_LOCALNET_ENTRYPOINT_MODE=vm`
- `ENTRYPOINT_VM_BRIDGE_IP`
- `ENTRYPOINT_VM_TAP_IFACE`

Fast-start option for the entrypoint VM:
- `ENTRYPOINT_VM_BASE_IMAGE` can point to a pre-baked qcow2 image with Solana CLI already installed.
- `ENTRYPOINT_VM_SKIP_CLI_INSTALL=auto` (default) reuses the preinstalled binaries if they exist.
- `ENTRYPOINT_VM_SKIP_CLI_INSTALL=true` forces the harness to skip reinstalling Solana CLI.

Run Latitude (operator credentials required):

```bash
./test-harness/bin/hvk-test run \
  --target latitude \
  --scenario agave_only \
  --operator-name "$USER" \
  --operator-ssh-public-key-file ~/.ssh/id_ed25519.pub \
  --operator-ssh-private-key-file ~/.ssh/id_ed25519 \
  --plan m4-metal-small
```

## Hot-Swap Flavor Matrix (Compose)

Run full identity transfer tests for:
- `agave -> agave`
- `agave -> jito-bam`
- `jito-bam -> agave`
- `jito-bam -> jito-bam`

```bash
./test-harness/scripts/run-compose-hot-swap-matrix.sh \
  --compose-engine docker \
  --operator-user ubuntu
```

Tunable environment variables:
- `AGAVE_VERSION` (default `3.1.10`)
- `JITO_VERSION` (default `2.3.6`)
- `BAM_JITO_VERSION` (default `3.1.10`)
- `BAM_JITO_VERSION_PATCH` (optional)
- `BAM_RELAYER_TYPE` (default `shared`)
- `BAM_EXPECT_CLIENT_REGEX` (default `Bam`)

## Notes

- The harness is additive and does not replace existing direct scripts.
- Adapter state/artifacts default to `test-harness/work/`.
- `run` supports `--retain-on-failure` and `--retain-always` for debugging.

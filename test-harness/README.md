# Test Harness

This directory contains a substrate-agnostic harness to run validator scenarios across:
- `compose`
- `vm`
- `latitude`

The harness wraps existing workflows from:
- `solana-localnet/tests/`
- `scripts/vm-test/`
- `bare-metal/latitudesh/`

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
- `AGAVE_VERSION` (default `2.3.11`)
- `JITO_VERSION` (default `2.3.6`)
- `BAM_JITO_VERSION` (default `2.2.16`)
- `BAM_JITO_VERSION_PATCH` (optional)
- `BAM_RELAYER_TYPE` (default `shared`)
- `BAM_EXPECT_CLIENT_REGEX` (default `Bam`)

## Notes

- The harness is additive and does not replace existing direct scripts.
- Adapter state/artifacts default to `test-harness/work/`.
- `run` supports `--retain-on-failure` and `--retain-always` for debugging.

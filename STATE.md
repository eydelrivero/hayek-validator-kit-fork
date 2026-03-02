# STATE

Last updated: 2026-03-02

Read this file first in any new thread before making harness changes.

## Current Goal
Unify validator test execution across `compose`, `vm`, and `latitude` targets with one additive harness interface, while preserving existing scripts and enabling incremental, reviewable PRs.

## Current Status (VM Hot-Swap)
- macOS + QEMU `usernet` + host-side or compose-managed entrypoint is not a reliable topology for the VM hot-swap harness.
- The compose-managed `gossip-entrypoint-vm + ansible-control-vm` control plane can now start and run, but with validator VMs on `usernet` it still fails at Solana public-IP discovery because the path is effectively double NAT:
  - `QEMU usernet -> host -> Docker Desktop -> compose control plane`
- The current realistic path forward is Linux-hosted VM testing with:
  - `VM_NETWORK_MODE=shared-bridge`
  - a dedicated bridge-attached entrypoint VM (`VM_LOCALNET_ENTRYPOINT_MODE=vm`)
  - source + destination validator VMs on the same bridge/tap network
- Current `shared-bridge` implementation is Linux-style `tap` networking. It is intended for Linux hosts and is not a good native fit for stock macOS.

## Constraints
- Keep PRs small and focused (follow `.github/pull_request_template.md` + `docs/PR_BEST_PRACTICES.md`).
- Minimize churn in existing directories to reduce merge conflicts while teammates land parallel PRs.
- Keep existing direct workflows working (`solana-localnet/`, `scripts/vm-test/`, `bare-metal/latitudesh/`, `ansible-tests/`).
- VM provisioning must support variable CPU, RAM, and disk sizing.

## Assumptions
- Test harness stays in this repository for now (no split to separate repo yet).
- New orchestration remains additive; legacy entrypoints are still first-class.
- Primary near-term integration scenario is full validator host hot swap using `pb_hot_swap_validator_hosts_v2`.
- Team binary policy:
  - local/manual and automated tests prefer pre-built binaries (`build_from_source=false`) for speed,
  - with explicit version pins (`agave_version`, `jito_version`, later firedancer version),
  - and artifacts served from company S3 (architecture-specific tarballs).
- Production policy:
  - for `testnet` and `mainnet`, always run with `build_from_source=true`.
- Current binary production process is manual and host-architecture-dependent; this should be replaced by a reproducible, centralized build+publish pipeline.

## Key Decisions (Why)
- Keep orchestration in `test-harness/` with adapter model (`compose`, `vm`, `latitude`).
  Reason: low-risk unification without moving authoritative code.
- Wrap existing substrate scripts instead of rewriting them.
  Reason: faster delivery, lower conflict surface, easier rollback.
- For VM bootstrap, keep playbook order:
  1. `pb_setup_users_validator`
  2. `pb_setup_metal_box`
  3. validator flavor setup (`pb_setup_validator_agave` or `pb_setup_validator_jito_v2`)
  4. `pb_hot_swap_validator_hosts_v2` (for matrix/hot-swap flows)
  Reason: matches current operations and provider handoff realities.

## Current TODO / Next Steps
1. Keep PR stack incremental and linear (docs/spec -> adapter hardening -> test coverage -> CI rollout).
2. Add/expand contract tests for adapter JSON contract and error codes.
3. Add guarded CI matrix jobs by target/scenario (start small, then expand).
4. Add explicit safety docs for host-risk boundaries per target (compose/vm/latitude).
5. Add future flavor extensions (Frankendancer/Firedancer) as new scenarios without changing adapter contract.
6. Validate the new Linux-only `shared-bridge + vm` topology on an Ubuntu host.
7. After Linux validation, decide whether to keep the dedicated entrypoint VM or replace it with a bridge-attached compose service.
7. Binary pipeline PR status:
   - PR-1 scaffold completed.
   - PR-2 build+manifest completed (no S3 publish yet).
   - PR-3 staging S3 publish + checksums completed.
   - PR-4 staging->release promotion workflow completed (no rebuild).
   - PR-5 CI-only publishing enforcement + production guardrails completed.

## Immediate Next Step (Ubuntu 24.04 Host)
Use the Ubuntu box as the harness host and run the VM hot-swap harness with a real bridge/tap network.

Example bridge plan:
- bridge: `br-hvk`
- gateway: `192.168.100.1/24`
- source VM: `192.168.100.11`
- destination VM: `192.168.100.12`
- entrypoint VM: `192.168.100.13`
- tap ifaces:
  - `tap-hvk-src`
  - `tap-hvk-dst`
  - `tap-hvk-ent`

Example run command:
- `VM_NETWORK_MODE=shared-bridge`
- `VM_LOCALNET_ENTRYPOINT_MODE=vm`
- `VM_SOURCE_BRIDGE_IP=192.168.100.11`
- `VM_DESTINATION_BRIDGE_IP=192.168.100.12`
- `ENTRYPOINT_VM_BRIDGE_IP=192.168.100.13`
- `VM_BRIDGE_GATEWAY_IP=192.168.100.1`
- `VM_SOURCE_TAP_IFACE=tap-hvk-src`
- `VM_DESTINATION_TAP_IFACE=tap-hvk-dst`
- `ENTRYPOINT_VM_TAP_IFACE=tap-hvk-ent`
- `ENTRYPOINT_VM_SKIP_CLI_INSTALL=auto`

Keep `AGAVE_VERSION=3.1.9`, `BAM_JITO_VERSION=3.1.9`, `BUILD_FROM_SOURCE=false` unless intentionally testing another binary source/version.

## Do-Not-Break Invariants
- Harness command surface: `test-harness/bin/hvk-test` remains stable and additive.
- Adapter contract semantics remain stable (`validate`, `up`, `inventory`, `wait`, `artifacts`, `down`, `describe`).
- VM hot-swap sequence must preserve current order (`users -> metal-box -> setup -> swap`).
- VM harness Ansible invocations must set deterministic config/role paths (`ANSIBLE_CONFIG=ansible/ansible.cfg`, `ANSIBLE_ROLES_PATH=ansible/roles`) independent of caller CWD.
- VM loopback inventories must force deterministic SSH behavior (`IdentitiesOnly=yes`, `IdentityAgent=none`, isolated known_hosts) to avoid host key churn and agent auth-failure loops.
- `confirm_target_host` must be non-interactive when `skip_confirmation_pauses=true`, and validation must guard against undefined `ip_confirmation`.
- VM harness Ansible commands must include baseline vars from `ansible/group_vars/{all,solana}.yml` so `iam_manager`/validator setup prechecks do not fail.
- VM harness Ansible commands must also include `ansible/group_vars/solana_<cluster>.yml` so cluster-specific settings (for example `expected_genesis_hash`) are always defined.
- Because VM harness injects group vars via `-e @...`, path variables in `ansible/group_vars/solana.yml` must stay aligned with system install paths (`/opt/solana/...`) to avoid overriding role vars with stale per-user paths.
- For list-shaped vars passed via `-e` (for example `solana_gossip_entrypoints`), pass JSON objects (`-e '{"solana_gossip_entrypoints":["host:port"]}'`) rather than string values; otherwise Jinja loops iterate characters and produce invalid validator flags.
- For production clusters (`testnet`, `mainnet`), do not allow `build_from_source=false`.
- CLI role prechecks enforce the production policy: if `solana_cluster` is `testnet/mainnet` and `build_from_source=false`, the play fails fast.
- Binary pipeline workflow can optionally publish to staging only (`publish_staging=true`).
- Release-path publish is automated only through the dedicated promotion workflow (`solana-binary-promote.yml`) that copies staging objects (no rebuild).
- Workflow S3 operations use AWS OIDC role assumption (`aws_role_to_assume`) and should not use static AWS access keys.
- VM users->metal flow must switch to designated sysadmin for `pb_setup_metal_box`; harness seeds temporary `%sysadmin NOPASSWD: ALL` in ephemeral VMs to avoid interactive `reset-my-password` during automation.
- VM hot-swap runner must avoid stale port/session reuse: reclaim only conflicting `qemu-system-*` listeners on test ports and fail fast if a newly launched QEMU process exits.
- For VM localnet runs, a reachable gossip/RPC entrypoint is required.
- On macOS, `VM_LOCALNET_ENTRYPOINT_MODE=auto` with default `VM_NETWORK_MODE=usernet` is not considered a correct topology for public-IP discovery.
- On Linux, prefer:
  - `VM_NETWORK_MODE=shared-bridge`
  - `VM_LOCALNET_ENTRYPOINT_MODE=vm`
  - dedicated bridge-attached entrypoint VM
- The harness supports a faster entrypoint VM path via:
  - `ENTRYPOINT_VM_BASE_IMAGE` (optional separate pre-baked qcow2)
  - `ENTRYPOINT_VM_SKIP_CLI_INSTALL=auto|true|false`
- VM runners re-check localnet entrypoint health immediately before source setup, destination setup, and hot-swap to avoid long-run flake from entrypoint process loss.
- VM harness should keep `system-tuning` for validator-required settings, but disable only CPU-governor service management in VM runs (`manage_cpu_governor_service=false`); default VM skip tags are now `restart,cpu-isolation`.
- VM ephemeral sudo bootstrap grants temporary `NOPASSWD: ALL` to both `%sysadmin` and `%validator_operators` so non-interactive validator setup/hot-swap can run without `-K`.
- `server_initial_setup` vars must avoid self-referential dict templating (e.g., `health_check.dest_path` referencing `health_check.script_name`) to prevent recursive Jinja rendering failures.
- Compose and VM matrix flavors supported:
  - `agave -> agave`
  - `agave -> jito-bam`
  - `jito-bam -> agave`
  - `jito-bam -> jito-bam`
- Retain flags continue to work for debugging (`--retain-on-failure`, `--retain-always`).

## Reference Test Commands
- Contract/listing smoke:
  - `./test-harness/bin/hvk-test list`
  - `./test-harness/bin/hvk-test describe --target vm --scenario agave_only --json`
- Compose hot-swap matrix:
  - `./test-harness/scripts/run-compose-hot-swap-matrix.sh --compose-engine docker --operator-user ubuntu`
- VM users+metal+validator flow (single host):
  - `./test-harness/scripts/verify-vm-users-metal-validator.sh --inventory <path> --flavor agave`
- VM full hot-swap matrix (two hosts):
  - `./test-harness/scripts/run-vm-hot-swap-matrix.sh --vm-arch <amd64|arm64> --vm-base-image <path>`
- Recommended Linux bridge/tap hot-swap run:
  - `VM_NETWORK_MODE=shared-bridge VM_LOCALNET_ENTRYPOINT_MODE=vm VM_SOURCE_BRIDGE_IP=192.168.100.11 VM_DESTINATION_BRIDGE_IP=192.168.100.12 ENTRYPOINT_VM_BRIDGE_IP=192.168.100.13 VM_BRIDGE_GATEWAY_IP=192.168.100.1 VM_SOURCE_TAP_IFACE=tap-hvk-src VM_DESTINATION_TAP_IFACE=tap-hvk-dst ENTRYPOINT_VM_TAP_IFACE=tap-hvk-ent ENTRYPOINT_VM_SKIP_CLI_INSTALL=auto CITY_GROUP=city_dal ANSIBLE_BECOME_TIMEOUT=60 ANSIBLE_TIMEOUT=60 AGAVE_VERSION=3.1.9 BAM_JITO_VERSION=3.1.9 BUILD_FROM_SOURCE=false ./test-harness/scripts/verify-vm-hot-swap.sh --source-flavor agave --destination-flavor jito-bam --vm-arch arm64 --vm-base-image scripts/vm-test/work/ubuntu-arm64.img`

## Resume Checklist For Next Session
Read these first:
1. `STATE.md`
2. `test-harness/README.md`
3. `test-harness/scripts/verify-vm-hot-swap.sh`
4. `scripts/vm-test/run-qemu-arm64.sh`
5. `scripts/vm-test/make-seed.sh`

Goal for the next session:
- run the VM hot-swap harness on Ubuntu 24.04 using Linux bridge/tap networking and the dedicated entrypoint VM
- verify the source validator no longer fails Solana public-IP discovery before attempting further control-plane changes

## Working Agreement
- On checkpoint requests: update this file and `docs/decision-log.md` before continuing implementation.

# Test Harness Decision Log

## 2026-02-25

### D-001: Keep harness in this repo (not split now)
- Decision: Keep `test-harness/` co-located with hayek validator automation.
- Rationale: lower coordination cost, direct access to playbooks/scripts, simpler incremental PR workflow.
- Revisit trigger: if harness reuse by external repos becomes dominant and release cadence diverges.

### D-002: Use additive adapter architecture
- Decision: unify via adapter contract (`compose`, `vm`, `latitude`) and keep existing substrate scripts authoritative.
- Rationale: reduces rewrite risk and merge conflicts; supports staged rollout.

### D-003: Preserve VM bootstrap order
- Decision: keep VM setup as `pb_setup_users_validator` then `pb_setup_metal_box`.
- Rationale: operational requirement for immediate credential hardening on provider-delivered hosts.

### D-004: Hot-swap validation is full-flow
- Decision: treat hot-swap tests as incomplete unless they include setup + `pb_hot_swap_validator_hosts_v2`.
- Rationale: this is the behavior that matters operationally for validator identity transfer.

### D-005: VM resource configuration is first-class
- Decision: support profile defaults and per-run overrides for CPU, RAM, and disk sizes.
- Rationale: needed for realistic environment parity and reproducible test classes.

### D-006: VM localnet uses host-side entrypoint by default
- Decision: for VM runs on `solana_cluster=localnet`, default to a host-side `solana-test-validator` entrypoint (`VM_LOCALNET_ENTRYPOINT_MODE=auto`) rather than adding a third VM immediately.
- Rationale: smallest additive change, lower conflict risk, and immediate compatibility with existing playbooks that query local RPC/genesis during setup and swap.

### D-007: GitHub Actions becomes canonical binary publisher
- Decision: move Agave/Jito/Firedancer artifact publishing from laptop/manual process to GitHub workflow pipeline in incremental PRs.
- Rationale: reproducibility, architecture consistency, controlled credentials, and reduced operational drift across teammates.

## 2026-02-26

### D-008: PR-2 builds artifacts and manifest before enabling publish
- Decision: implement CI matrix builds first (`agave|jito-solana` x `x86_64|aarch64`) and publish only build artifacts + manifest in GitHub Actions artifacts.
- Rationale: validates reproducibility and version/arch metadata contract before introducing S3 side effects and IAM policy coupling.

### D-009: PR-3 publishes to staging only, with checksum sidecars
- Decision: add optional staging S3 publish to `staging/` prefixed keys and publish `.sha256` sidecars + staging manifest, while keeping release-path publish disabled.
- Rationale: enables end-to-end artifact distribution testing with low blast radius before promotion/release automation.

### D-010: PR-4 promotes by S3 copy only (no rebuild)
- Decision: add a dedicated promotion workflow to copy artifacts from staging keys to release keys, plus publish a release manifest from promotion metadata.
- Rationale: preserves artifact immutability across environments, avoids drift from rebuilds, and provides auditable promotion records.

### D-011: PR-5 enforces OIDC workflow publishing and production source builds
- Decision: require workflow publishing credentials through `aws_role_to_assume` (OIDC) and add AWS policy templates for CI-only write paths.
- Rationale: removes long-lived key dependency from CI workflow paths and enables bucket-level enforcement of CI-only publishing.
- Decision: fail Ansible CLI setup roles when `solana_cluster` is `testnet` or `mainnet` and `build_from_source=false`.
- Rationale: aligns automation with production policy that binaries must be built from source.

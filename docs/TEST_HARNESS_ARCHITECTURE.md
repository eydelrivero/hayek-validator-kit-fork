# Test Harness Architecture (PR-1 Scaffold)

Documentation and interface definitions only. No runtime behavior changes.

## Context

This repository currently has multiple test and provisioning entry points:
- `solana-localnet/` for local compose-based multi-host stack tests.
- `scripts/vm-test/` for local QEMU VM-based playbook testing.
- `bare-metal/latitudesh/` for short-lived bare-metal provisioning.
- `ansible-tests/` for Molecule-based role and host tests.

These are useful, but they are not yet unified under a single test orchestration interface.

## Goals

- Reuse existing workflows with minimal code churn.
- Support one scenario running on multiple targets:
  - `compose`
  - `vm`
  - `latitude`
- Keep Molecule for fast role-level testing.
- Add a target-agnostic integration harness for stack lifecycle + inventory generation.
- Make manual runs and CI runs call the same command surface.

## Non-Goals

- No migration of existing scripts in this PR.
- No refactor of Dockerfiles or compose files in this PR.
- No new CI jobs in this PR.
- No changes to current `ansible-tests` behavior.

## Layered Model

### 1) Scenario Layer (what to test)

Scenarios describe intent and assertions, for example:
- `agave_only`
- `agave_jito_shared_relayer`
- `agave_jito_cohosted_relayer`
- `agave_jito_bam`

Scenario metadata is target-agnostic.

### 2) Target Adapter Layer (where to run)

Adapters manage lifecycle for one substrate:
- `compose`: wraps existing localnet compose lifecycle.
- `vm`: wraps existing `scripts/vm-test` lifecycle.
- `latitude`: wraps existing Latitude provisioning lifecycle.

All adapters expose the same contract (see `TEST_HARNESS_ADAPTER_CONTRACT.md`).

### 3) Execution Layer (how tests run)

Execution is the common flow:
1. `up`
2. `inventory`
3. `wait`
4. `ansible-playbook` / verification suite
5. `down` (or retain for debugging)

This layer calls adapters and consumes generated inventory.

## Inventory Strategy

Adapters must output an inventory artifact path plus metadata:
- Stable output location under workspace (for reproducibility).
- Compatible with existing Ansible inventory structure.
- Target tags (`compose`, `vm`, `latitude`) included in metadata.

## VM Resource Profiles

VM target must support configurable resources:
- CPU
- RAM
- disk sizes (system, ledger, accounts, snapshots)

Profiles should be supported (`small`, `medium`, `large`, `perf`) with per-run overrides.

## Proposed Incremental Rollout

1. PR-1 (this): docs/spec scaffold only.
2. PR-2: VM resource profile and disk-size parameterization.
3. PR-3: compose adapter wrapper around existing localnet test scripts.
4. PR-4: lightweight unified command entrypoint.
5. PR-5: Molecule bridge for selected integration scenarios.
6. PR-6: latitude adapter integration with cleanup semantics.
7. PR-7: CI matrix rollout by target and scenario.

## Ownership Boundaries

- `solana-localnet/`: topology definition and compose stack behavior.
- `scripts/vm-test/`: VM substrate lifecycle primitives.
- `bare-metal/latitudesh/`: bare-metal lifecycle primitives.
- `ansible-tests/`: role-level Molecule tests.
- `test-harness` (future): orchestration API and target adapters.

This keeps existing code authoritative in-place and avoids high-conflict moves.

# Test Harness Architecture

## Context

This repository currently has multiple test and provisioning entry points:
- `solana-localnet/` for local compose-based multi-host stack tests.
- `scripts/vm-test/` for local QEMU VM-based playbook testing.
- `bare-metal/latitudesh/` for short-lived bare-metal provisioning.
- `ansible-tests/` for Molecule-based role and host tests.

The test harness adds a shared orchestration layer on top of those existing
substrates so the same scenario can be driven through `compose`, `vm`, or
`latitude` with one entrypoint and one adapter contract.

## Goals

- Reuse existing workflows with minimal code churn.
- Support one scenario running on multiple targets:
  - `compose`
  - `vm`
  - `latitude`
- Keep Molecule for fast role-level testing.
- Add a target-agnostic integration harness for stack lifecycle + inventory generation.
- Make manual runs and CI runs call the same command surface.

## Layered Model

### 1) Scenario Layer (what to test)

Scenarios describe target-agnostic test intent. Current shared scenarios include:
- `agave_only`
- `agave_jito_shared_relayer`
- `agave_jito_cohosted_relayer`
- `agave_jito_bam`
- `hot_swap_matrix`

Scenario definitions live under `test-harness/scenarios/`.

### 2) Target Adapter Layer (where to run)

Adapters manage lifecycle for one substrate:
- `compose`: wraps existing localnet compose lifecycle.
- `vm`: wraps existing `scripts/vm-test` lifecycle.
- `latitude`: wraps existing Latitude provisioning lifecycle.

Adapters are implemented under `test-harness/targets/` and expose the same
contract (see `TEST_HARNESS_ADAPTER_CONTRACT.md`).

### 3) Execution Layer (how tests run)

The shared entrypoint is `test-harness/bin/hvk-test`. Its common orchestration
flow is:
1. `up`
2. `inventory`
3. `wait`
4. verification command or default verifier
5. `artifacts`
6. `down` (unless retained)

For VM scenarios with a known default mapping, `hvk-test run` can execute the
default verifier automatically when `--verify-cmd` is omitted.

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

## Current Implemented Surface

- `hvk-test list` exposes the supported targets, shared scenarios, and VM
  profiles.
- `hvk-test describe` returns static capability metadata for each adapter.
- `hvk-test run`, `validate`, `up`, `inventory`, `wait`, `artifacts`, and
  `down` dispatch through the adapter contract.
- Higher-level suites continue to live under `test-harness/scripts/`, including
  compose hot-swap, VM access-validation and hot-swap flows, and Latitude
  access-validation and canary flows.
- CI and regression coverage consume the same harness surface rather than
  inventing a separate orchestration layer.

## Ownership Boundaries

- `solana-localnet/`: topology definition and compose stack behavior.
- `scripts/vm-test/`: VM substrate lifecycle primitives.
- `bare-metal/latitudesh/`: bare-metal lifecycle primitives.
- `ansible-tests/`: role-level Molecule tests.
- `test-harness/`: orchestration API, target adapters, and shared verification entrypoints.

This keeps existing code authoritative in-place and avoids high-conflict moves.

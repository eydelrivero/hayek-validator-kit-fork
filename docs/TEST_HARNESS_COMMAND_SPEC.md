# Test Harness Command Spec

## Objective

Define a single command surface for manual and CI flows while preserving existing underlying scripts.

Entrypoint:
- `hvk-test`

## Command Groups

### `hvk-test run`

End-to-end orchestration:
1. validate
2. up
3. inventory
4. wait
5. execute verification command
6. collect artifacts
7. down (unless retained)

VM default verify behavior (when `--verify-cmd` is omitted and scenario is mapped):
1. `pb_setup_users_validator`
2. `pb_setup_metal_box`
3. validator setup playbook by flavor (`agave` or `jito_v2`)

### `hvk-test up`

Calls adapter `up` only.

### `hvk-test down`

Calls adapter `down` only.

### `hvk-test inventory`

Calls adapter `inventory` and emits the standard adapter JSON/object output,
including `inventory_path` and host metadata.

### `hvk-test wait`

Calls adapter `wait` only.

### `hvk-test artifacts`

Calls adapter `artifacts`.

### `hvk-test validate`

Calls adapter `validate`.

### `hvk-test list`

Lists:
- targets
- scenarios
- profiles (for `vm`)

## Matrix Helpers

For higher-level scenario matrices that compose multiple `hvk-test run` executions,
helper scripts may live under `test-harness/scripts/`.

Current helper suites include:
- `run-compose-hot-swap-matrix.sh`
  - Executes full validator identity transfer matrix for compose target.
  - Uses `hvk-test run --target compose ...` per case.
- `run-compose-ha-reconcile-e2e.sh`
  - Executes compose-backed HA reconcile verification flows.
- `run-vm-access-validation.sh`
  - Executes the focused VM access-validation wrapper and teardown flow.
- `run-vm-hot-swap-matrix.sh`
  - Executes full validator identity transfer matrix for two QEMU VMs.
  - Runs ordered host bootstrap:
    1. `pb_setup_users_validator`
    2. `pb_setup_metal_box`
    3. flavor setup
    4. `pb_hot_swap_validator_hosts_v2`
- `run-vm-ha-reconcile-e2e.sh`
  - Exercises VM HA reconcile coverage.
- `run-latitude-access-validation.sh`
  - Exercises disposable-host Latitude access-validation coverage.
- `run-latitude-role-canary.sh`
  - Exercises disposable-host Latitude role canaries.
- `run-latitude-combined-canary.sh`
  - Reuses one disposable host for combined L2 and L3 Latitude checks.

## Global Flags

- `--target <compose|vm|latitude>`
- `--scenario <name>`
- `--run-id <id>`
- `--workdir <abs-path>`
- `--timeout-seconds <int>`
- `--poll-interval-seconds <int>`
- `--json` (structured output)
- `--verbose`

## Run-Specific Flags

- `--verify-cmd "<shell command>"`
- `--retain-on-failure`
- `--retain-always`
- `--skip-artifacts`
- `--skip-down`

## VM Flags

- `--vm-profile <small|medium|large|perf>`
- `--vm-cpus <int>`
- `--vm-ram-mb <int>`
- `--vm-disk-system-gb <int>`
- `--vm-disk-ledger-gb <int>`
- `--vm-disk-accounts-gb <int>`
- `--vm-disk-snapshots-gb <int>`

## Exit Codes

- `0`: success
- `1`: generic failure
- `2`: invalid usage/arguments
- `3`: validation/prerequisite failure
- `4`: infrastructure lifecycle failure
- `5`: verification/test failure

## Standard Output Modes

### Human Mode (default)

- Step-by-step status lines.
- Final summary with target, scenario, duration, and result.

### JSON Mode (`--json`)

Commands emit one JSON object for CI parsing. For `run`, the summary object has
the form:

```json
{
  "ok": true,
  "target": "compose",
  "scenario": "agave_only",
  "run_id": "20260224-abc123",
  "inventory_path": "/abs/path/to/generated.yml",
  "artifacts_path": "/abs/path/to/artifacts",
  "duration_seconds": 187
}
```

## Compatibility Requirements

- Existing direct commands remain valid and supported:
  - `solana-localnet/tests/test-localnet.sh ...`
  - `scripts/vm-test/...`
  - `bare-metal/latitudesh/provision_latitude_server.sh ...`
  - existing `ansible-tests` Molecule commands
- `hvk-test` should initially orchestrate those commands rather than replacing them.

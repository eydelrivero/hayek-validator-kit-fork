# Test Harness Command Spec (PR-1 Scaffold)
Command specification only. No new executable behavior in this PR.

## Objective

Define a single command surface for manual and CI flows while preserving existing underlying scripts.

Proposed entrypoint:
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

Calls adapter `inventory` and prints inventory path.

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

Current helper:
- `run-compose-hot-swap-matrix.sh`
  - Executes full validator identity transfer matrix for compose target.
  - Uses `hvk-test run --target compose ...` per case.
- `run-vm-hot-swap-matrix.sh`
  - Executes full validator identity transfer matrix for two QEMU VMs.
  - Runs ordered host bootstrap:
    1. `pb_setup_users_validator`
    2. `pb_setup_metal_box`
    3. flavor setup
    4. `pb_hot_swap_validator_hosts_v2`

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

One JSON summary object, for CI parsing:

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

## Phased Adoption

1. PR-1: this spec (docs only).
2. PR-2+: adapter wrappers and command implementation with no breaking workflow changes.

# Test Harness Adapter Contract (PR-1 Scaffold)
Contract definition only. No adapter implementation changes.

## Purpose

Define a stable interface for substrate adapters so that `compose`, `vm`, and `latitude` targets can be driven by one orchestration command without changing test intent.

## Adapter Identity

- Adapter ID: one of `compose`, `vm`, `latitude`.
- Adapter implementation path (proposed): `test-harness/targets/<adapter>.sh`

## Command Shape

Each adapter exposes:

```bash
<adapter> <action> [options]
```

Where `<action>` is:
- `validate`
- `up`
- `inventory`
- `wait`
- `down`
- `artifacts`
- `describe`

## Common Required Options

- `--scenario <name>`
- `--run-id <id>`
- `--workdir <abs-path>`

## Action Semantics

### `validate`

Checks prerequisites only (tools, credentials, required files, environment).

Must not mutate infrastructure.

### `up`

Creates or starts target resources for the scenario.

Idempotency:
- If resources already exist for `run-id`, return success and report them.

### `inventory`

Generates an Ansible inventory artifact and prints machine-readable metadata.

Required output keys:
- `ok` (boolean)
- `adapter` (string)
- `run_id` (string)
- `inventory_path` (absolute path)
- `hosts` (array of host summary objects)

### `wait`

Blocks until target hosts are reachable and base readiness conditions pass.

### `down`

Destroys target resources created by `up` for this run.

Must be safe to call repeatedly.

### `artifacts`

Collects logs and diagnostics into a deterministic artifact directory.

### `describe`

Returns static capability metadata for the adapter.

## Output Contract

For machine-readable actions (`validate`, `up`, `inventory`, `wait`, `down`, `artifacts`, `describe`):
- Print one JSON object to stdout.
- Print logs to stderr.

Minimal JSON envelope:

```json
{
  "ok": true,
  "adapter": "vm",
  "action": "up",
  "run_id": "20260224-abc123",
  "message": "human-readable summary"
}
```

On failure:
- exit code != 0
- `ok: false`
- include `error.code` and `error.message`

## Capability Flags (`describe`)

Adapters should declare capability flags, for example:
- `supports_destroy`
- `supports_artifacts`
- `supports_multi_host`
- `supports_resource_profiles`
- `supports_scenario_matrix`

## VM Resource Profile Contract

For adapter `vm`, the following options must be supported by `up`:
- `--vm-profile <small|medium|large|perf>`
- `--vm-cpus <int>`
- `--vm-ram-mb <int>`
- `--vm-disk-system-gb <int>`
- `--vm-disk-ledger-gb <int>`
- `--vm-disk-accounts-gb <int>`
- `--vm-disk-snapshots-gb <int>`

Override behavior:
- Explicit per-run flags override profile defaults.

## Timeout Controls

Adapters should support:
- `--timeout-seconds <int>`
- `--poll-interval-seconds <int>`

## State and Artifacts

- Adapter state path (proposed): `<workdir>/state/<adapter>/<run-id>/`
- Artifact path (proposed): `<workdir>/artifacts/<adapter>/<run-id>/`

No state should be written outside workspace and configured user paths.

## Security and Safety

- Never print secrets in stdout JSON.
- Redact sensitive values in stderr logs.
- `down` must only destroy resources associated with the adapter run-id.
- Avoid destructive broad filters (project-wide delete without run scoping).

## Compatibility Mapping (Current Code)

This contract is intended to wrap existing behavior:
- `compose`: `solana-localnet/tests/test-localnet.sh` flow.
- `vm`: `scripts/vm-test/*` flow.
- `latitude`: `bare-metal/latitudesh/provision_latitude_server.sh` flow.

Implementations should initially call existing scripts instead of replacing them.

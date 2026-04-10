# Test Harness Adapter Contract

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

## Common Options

- `--run-id <id>`
- `--workdir <abs-path>`
- `--timeout-seconds <int>`
- `--poll-interval-seconds <int>`

## Action Semantics

### `validate`

Checks prerequisites only (tools, credentials, required files, environment).

Must not mutate infrastructure.

Required inputs:
- `--scenario`

### `up`

Creates or starts target resources for the scenario.

Required inputs:
- `--scenario`

### `inventory`

Generates an Ansible inventory artifact and returns machine-readable metadata.

Required inputs:
- `--scenario`

Required output keys:
- `ok` (boolean)
- `adapter` (string)
- `action` (string)
- `run_id` (string)
- `message` (string)
- `inventory_path` (absolute path)
- `hosts` (array of host summary objects)

### `wait`

Blocks until target hosts are reachable and base readiness conditions pass.

Required inputs:
- `--scenario`

### `down`

Destroys target resources created by `up` for this run.

Must be safe to call repeatedly.

`down` should work from run-scoped adapter state and does not need the same
scenario-specific validation contract as `up` or `inventory`.

### `artifacts`

Collects logs and diagnostics into a deterministic artifact directory.

Required output keys:
- `ok`
- `adapter`
- `action`
- `run_id`
- `message`
- `artifacts_path`

### `describe`

Returns static capability metadata for the adapter.

`describe` requires `--target` through the shared `hvk-test` entrypoint, but it
does not require `--scenario`.

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

Adapters should accept:
- `--timeout-seconds <int>`
- `--poll-interval-seconds <int>`

## State and Artifacts

- Adapter state path: `<workdir>/state/<adapter>/<run-id>/`
- Artifact path: `<workdir>/artifacts/<adapter>/<run-id>/`

No state should be written outside workspace and configured user paths.

## Security and Safety

- Never print secrets in stdout JSON.
- Redact sensitive values in stderr logs.
- `down` must only destroy resources associated with the adapter run-id.
- Avoid destructive broad filters (project-wide delete without run scoping).

## Compatibility Mapping (Current Code)

This contract currently wraps existing behavior:
- `compose`: `solana-localnet/tests/test-localnet.sh` plus compose-backed helper flows.
- `vm`: `scripts/vm-test/*` plus harness-side VM verification entrypoints.
- `latitude`: `bare-metal/latitudesh/*` plus harness-side disposable-host verification entrypoints.

Implementations should initially call existing scripts instead of replacing them.

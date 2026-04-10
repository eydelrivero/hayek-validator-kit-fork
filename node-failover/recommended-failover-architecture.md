# Recommended Failover Architecture for Hayek Validator Kit

## Executive Summary

Hayek already has a strong, repo-native solution for **planned validator identity transfer**:

- validators are installed with both `primary-target-identity.json` and `hot-spare-identity.json`
- the runtime identity is controlled through an `identity.json` symlink
- the hot-swap playbook demotes the source, transfers tower, and then promotes the destination
- the test harness already exercises this workflow across flavors and guardrail cases

Because of that, Hayek should **keep its current hot-swap workflow as the canonical path for planned failover** and add a separate, smaller solution for **unexpected failover**.

The best overall fit for this repo is:

1. **Planned failover / maintenance / host replacement**
   Keep using `pb_hot_swap_validator_hosts_v2` as the source of truth.
2. **Unexpected failover / primary host outage**
   Add `SOL-Strategies/solana-validator-ha` as an emergency-only automation layer, with Hayek-specific role scripts.

This is a hybrid architecture, but it matches the repo better than trying to force one external tool to solve both problems.

## Why This Fits Hayek

Hayek already encodes several important failover assumptions:

- `identity.json` is a symlink that points to either the primary or the hot-spare identity.
- Validator installs always include a dedicated hot-spare identity.
- Planned swap logic waits for a safe restart window, demotes the source, copies tower, and promotes the destination with `--require-tower`.
- Fast rollback is already documented if promotion fails after demotion.
- The VM and compose harnesses already verify hot-swap success and guardrail failures.

Relevant repo implementation:

- `ansible/roles/solana_validator_shared/tasks/install_validator_keyset_rbac.yml`
- `ansible/roles/solana_swap_validator_hosts_v2/tasks/swap.yml`
- `ansible/roles/solana_swap_validator_hosts_v2/FAST_ROLLBACK.md`
- `test-harness/scripts/verify-vm-hot-swap.sh`

That means Hayek's real gap is not planned swaps. The gap is **unexpected failover when the old primary is unreachable or degraded**.

## Recommended Architecture

### 1. Baseline Host Model

Every validator pair should follow this baseline:

- One shared `primary-target-identity.json` for the vote identity.
- One unique `hot-spare-identity.json` per host.
- `identity.json` symlink determines which identity the validator starts with.
- Primary host normally runs with `identity.json -> primary-target-identity.json`.
- Standby host normally runs with `identity.json -> hot-spare-identity.json`.
- On restart or reboot, each host comes back using whatever `identity.json` currently points to.

For Hayek, this model already exists and should remain unchanged.

### 2. Planned Failover Path

Use Hayek's current hot-swap playbook for:

- scheduled maintenance
- client flavor migration
- data center migration
- hardware replacement
- rehearsed operator-driven failover

The existing sequence is correct for planned operations:

1. Wait for a safe restart window.
2. Demote the source to hot-spare identity.
3. Update source `identity.json` symlink.
4. Transfer tower from source to destination.
5. Promote destination to the primary identity with `--require-tower`.
6. Update destination `identity.json` symlink.

This minimizes vote credit loss and matches Solana operational guidance better than emergency automation.

### 3. Unexpected Failover Path

For emergency automation, add a lightweight node-local HA agent on both validator hosts.

Recommended upstream choice:

- `SOL-Strategies/solana-validator-ha`

Recommended Hayek usage:

- install the HA agent on each validator host
- keep configuration and role scripts in-repo
- use Hayek-specific promote/demote scripts that understand:
  - RBAC paths under `/opt/validator`
  - `identity.json` symlink management
  - Agave vs Jito vs future Firedancer command differences
  - hard demotion behavior if the unhealthy node cannot safely remain primary

Important constraint:

- emergency failover should be treated as an **availability-first path**
- planned failover should remain the **credit-preserving path**

In other words:

- use hot-swap for planned work
- use HA automation only when the primary is actually unhealthy or unreachable

### 4. Fencing and Safety Rules

Regardless of tool choice, Hayek should adopt these rules:

- Backups must boot passive by default.
- Promotion must never assume duplicate-identity suicide is sufficient protection.
- Demotion logic must be stronger than promotion logic.
- If a node is unhealthy, it should either:
  - successfully switch to hot-spare identity, or
  - stop the validator service, or
  - restart into passive mode
- Any promoted standby must alert immediately so operators verify the old primary does not return in active mode.

This directly addresses the failure mode described repeatedly in the research notes: a recovered primary can disrupt the newly promoted backup even if it is far behind.

### 5. Client Flavor Strategy

Hayek should split client support into two categories:

#### Planned Agave/Jito/Firedancer transitions

Use the existing Hayek hot-swap workflow.

This is the safer place to support:

- Agave -> Jito
- Jito -> Agave
- Agave -> Firedancer
- Firedancer -> Agave

because the operator can explicitly control:

- restart timing
- tower movement
- binary-specific commands
- service validation before cutover

#### Unexpected failover between mixed clients

Only support this if Hayek provides client-aware promote/demote scripts for both sides.

The HA layer should not directly assume `agave-validator` forever. Instead, Hayek should define wrapper scripts such as:

- `validator-make-passive`
- `validator-make-active`
- `validator-health-check`

and let each host flavor implement those wrappers using the correct local client tooling.

This keeps the failover control plane stable even if the validator binary changes.

## Upstream Tool Comparison

### 1. `SOL-Strategies/solana-validator-ha`

Best use in Hayek:

- unexpected failover automation

Strengths:

- no extra control server required
- designed for automatic failover
- node-local and gossip-oriented
- flexible enough to plug in custom role scripts
- aligns well with Hayek's existing passive/active identity model

Weaknesses for Hayek:

- not the right canonical path for planned tower-preserving swaps
- race behavior and takeover timing still need careful testing
- wrapper scripts are needed to abstract client-specific commands

Fit verdict:

- **Best emergency failover fit**

### 2. `SOL-Strategies/solana-validator-failover`

Best use in Hayek:

- reference material for planned failover mechanics

Strengths:

- explicitly oriented toward planned failover / identity transfer
- same conceptual model as Hayek's current hot-swap flow
- tower-aware
- designed around configurable commands and validator clients

Weaknesses for Hayek:

- Hayek already has this capability natively in Ansible and test harnesses
- replacing the current playbook would create churn without clear payoff
- less compelling as an answer to unexpected outage recovery

Fit verdict:

- **Conceptually aligned, but redundant for Hayek**

### 3. `schmiatz/solana-validator-automatic-failover`

Best use in Hayek:

- possible alternative for two-node automatic failover experiments

Strengths:

- focused automatic failover client
- reported support for Agave and Frankendancer-style setups
- built-in alerting

Weaknesses for Hayek:

- less aligned with Hayek's existing Ansible-driven orchestration
- more opinionated around its own client behavior and thresholds
- unclear advantage over `solana-validator-ha` once Hayek-specific wrapper scripts exist

Fit verdict:

- **Interesting, but not the best architectural fit**

### 4. `StakeNode777/solana-node-manager`

Best use in Hayek:

- not recommended as the default Hayek direction

Strengths:

- supports a separate control server
- centralizes credentials and orchestration
- can manage multiple servers

Weaknesses for Hayek:

- introduces an extra control-plane host
- centralizes sensitive credentials away from Hayek's current host-local keyset model
- heavier operational footprint than the repo currently assumes

Fit verdict:

- **Too heavyweight and too different from current Hayek assumptions**

### 5. `monster2048/validator-ha`

Best use in Hayek:

- reference for deterministic takeover ideas

Strengths:

- deterministic promotion ordering
- no extra control host

Weaknesses for Hayek:

- less battle-tested in the repo context than the SOL-Strategies path
- would still require Hayek-specific wrappers and validation
- smaller ecosystem and less obvious fit with Hayek's current tooling

Fit verdict:

- **Promising ideas, but not the first choice**

## Recommendation Matrix

### Planned Failover

Recommended choice:

- **Keep Hayek native hot-swap**

Reason:

- it already matches Hayek's file layout, RBAC model, tower handling, rollback docs, and test harness

### Unexpected Failover

Recommended choice:

- **Adopt `solana-validator-ha` with Hayek wrapper scripts**

Reason:

- it adds automation where Hayek is currently weakest without replacing the mature planned-swap workflow

### Mixed Client Support

Recommended choice:

- **Support mixed clients only through Hayek-owned wrapper scripts**

Reason:

- this keeps the control logic stable while binary-specific behavior changes underneath

## Proposed Hayek Implementation Phases

### Phase 1: Documented Hybrid Model

- Keep `pb_hot_swap_validator_hosts_v2` as the official planned failover path.
- Document that unexpected failover is availability-first and may not preserve credits as well as planned swap.
- Define the wrapper-script contract for promote, demote, and health checks.

### Phase 2: Emergency Automation Prototype

- Integrate `solana-validator-ha` into localnet and VM harness scenarios.
- Add Hayek wrapper scripts for:
  - make passive
  - make active
  - validate runtime identity
  - stop service on unsafe conditions
- Test:
  - primary process crash
  - primary network isolation
  - standby promotion
  - recovered primary rejoining
  - false positive gossip samples

### Phase 3: Mixed-Flavor Validation

- Exercise Agave/Jito combinations first.
- Add Firedancer-specific wrappers only after planned hot-swap across those flavors is verified.
- Do not advertise mixed-client automatic failover until recovered-primary behavior is validated end to end.

## Final Recommendation

If the question is "which upstream solution fits Hayek best?", the answer is:

- **For planned failover: none of the upstream tools is a better fit than Hayek's existing hot-swap playbook.**
- **For unexpected failover: `solana-validator-ha` is the best fit to add on top of Hayek's current design.**

So the recommended Hayek architecture is:

- **Hayek native hot-swap for planned operations**
- **`solana-validator-ha` plus Hayek wrapper scripts for emergency automatic failover**

That gives Hayek both planned and unexpected failover capability without discarding the repo's current, already-tested identity-transfer workflow.

## Sources

Repo sources:

- `ansible/roles/solana_validator_shared/tasks/install_validator_keyset_rbac.yml`
- `ansible/roles/solana_swap_validator_hosts_v2/tasks/swap.yml`
- `ansible/roles/solana_swap_validator_hosts_v2/FAST_ROLLBACK.md`
- `test-harness/README.md`
- `/work/repos/hvk-external-docs/node-failover/node-failover-instructions.md`

Upstream references:

- `https://github.com/SOL-Strategies/solana-validator-ha`
- `https://github.com/SOL-Strategies/solana-validator-failover`
- `https://github.com/schmiatz/solana-validator-automatic-failover`
- `https://github.com/StakeNode777/solana-node-manager`
- `https://github.com/monster2048/validator-ha`
- `https://docs.anza.xyz/operations/guides/validator-failover`

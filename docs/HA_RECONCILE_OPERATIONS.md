# HA Reconcile Operations

A field guide to [`ansible/playbooks/pb_reconcile_validator_ha_cluster.yml`](../ansible/playbooks/pb_reconcile_validator_ha_cluster.yml).

The playbook reads as a long chain of `set_fact` / `assert` controller logic, which hides a very
simple idea. This doc explains that idea and walks through every HA topology change — initial,
contract, expand — with the matching **inventory** and **reconcile command**, plus concrete Testnet
examples.

## The one idea to hold onto

You never tell reconcile *"add this host"* or *"remove that host."* You **declare the final
membership** of the HA cluster, and reconcile computes the diff and makes reality match.

Three derived sets (all computed on `localhost` near the top of the playbook):

| Set | How it's derived | Knob |
|-----|------------------|------|
| **Retained** — who should remain in the cluster | `groups[ha_reconcile_retained_peers_group]` | `-e ha_reconcile_retained_peers_group=<group>` (required) |
| **Universe** — every host reconcile is allowed to consider | `ha_reconcile_peers_group` if given, **else all inventory hosts** (minus `localhost`) | `-e ha_reconcile_peers_group=<group>` (optional) |
| **Removed** — to be decommissioned | `Universe − Retained` | inferred; acting on it needs `-e ha_reconcile_allow_decommission=true` |

Rules the controller enforces (the asserts that make the file long):

- **Retained ⊆ Universe** — you can't retain a host outside the universe.
- **Retained must have ≥ 2 hosts** — *unless* `ha_reconcile_experimental_fake_peer_enabled=true`,
  which requires **exactly 1** retained host and synthesizes a second "peer" so the HA config
  (which needs ≥ 1 peer) is valid for a singleton.
- Any **Removed** host aborts with a clear message unless `ha_reconcile_allow_decommission=true`.
- Every retained host must declare a **unique** `solana_validator_ha_node_id` and a **unique**
  `solana_validator_ha_priority`; node ids must not collide with other `ha_*` groups in the
  inventory.

Execution order once the sets are computed:

1. **Stage** runtime artifacts on *all* retained hosts (`any_errors_fatal`) — [`stage_runtime.yml`](../ansible/roles/solana_validator_ha/tasks/stage_runtime.yml).
2. **Commit** serially (`serial: 1`); if a host fails, roll it back, then roll back every
   already-committed peer — [`commit_staged_runtime.yml`](../ansible/roles/solana_validator_ha/tasks/commit_staged_runtime.yml) / [`rollback_staged_runtime.yml`](../ansible/roles/solana_validator_ha/tasks/rollback_staged_runtime.yml).
3. **Decommission** the Removed set (only if commit succeeded) — [`decommission_runtime.yml`](../ansible/roles/solana_validator_ha/tasks/decommission_runtime.yml).
4. **Finalize** on localhost: fail loudly if any rollback happened, else report success.

Key consequence of "Universe defaults to all inventory hosts": **a host you want to drop must stay
in the inventory** (so it lands in Universe and gets decommissioned) but be **left out of the
retained group**. A host you want to add must be **present in the inventory AND in the retained
group**. If your inventory also contains non-HA hosts (e.g. monitoring), scope the universe with
`ha_reconcile_peers_group` so they aren't mistaken for "Removed".

Base command shared by every scenario:

```bash
ansible-playbook playbooks/pb_reconcile_validator_ha_cluster.yml \
  -i <inventory>.yml \
  -e "ha_reconcile_retained_peers_group=<retained-group>" \
  -e "operator_user=<operator>"
```

Scenarios differ only by **which hosts are in the retained group** and **which extra `-e` flags**
you add. Testnet examples use the live pair from
[`ansible/latitude-hayek-testnet-ha.yml`](../ansible/latitude-hayek-testnet-ha.yml):
`zoe-lat-dal` (node_id `zoe`, priority 10) and `mud-lat-lax` (node_id `mud`, priority 15).

## Scenario 1 — Initial cluster reconcile (stand up a 2-node HA cluster)

Retained = both hosts · Universe = both · Removed = none. No special flags.

Inventory (retained group lists *both* members):

```yaml
ha_testnet_peers:
  vars:
    solana_validator_ha_inventory_group: ha_testnet_peers
  hosts:
    zoe-lat-dal:
    mud-lat-lax:
```

Command:

```bash
ansible-playbook playbooks/pb_reconcile_validator_ha_cluster.yml \
  -i latitude-hayek-testnet-ha.yml \
  -e "ha_reconcile_retained_peers_group=ha_testnet_peers" \
  -e "operator_user=eydel"
```

Reconcile computes: retained `[zoe, mud]`, universe `[zoe, mud]`, removed `[]` → stage both, commit
serially, nothing decommissioned.

## Scenario 2 — Contract 2 → 1 + experimental fake peer (zoe stays, mud leaves)

Retained = 1 real host (zoe) · Universe = both (mud still in inventory) · Removed = `[mud]`.
Singleton retained requires the **fake peer**; dropping mud requires **allow_decommission**.

Inventory — retained group now lists **only zoe**; **mud stays defined** in the inventory so it
lands in the universe and gets decommissioned:

```yaml
ha_testnet_peers:
  vars:
    solana_validator_ha_inventory_group: ha_testnet_peers
  hosts:
    zoe-lat-dal:          # mud-lat-lax intentionally NOT listed here
```

Command:

```bash
ansible-playbook playbooks/pb_reconcile_validator_ha_cluster.yml \
  -i latitude-hayek-testnet-ha.yml \
  -e "ha_reconcile_retained_peers_group=ha_testnet_peers" \
  -e "operator_user=eydel" \
  -e "ha_reconcile_experimental_fake_peer_enabled=true" \
  -e "ha_reconcile_allow_decommission=true"
  # optional fake-peer overrides (defaults: synthetic-peer / 192.0.2.254 / priority 9999):
  # -e "ha_reconcile_experimental_fake_peer_name=standby"
  # -e "ha_reconcile_experimental_fake_peer_ip=192.0.2.10"
  # -e "ha_reconcile_experimental_fake_peer_priority=9999"
```

Reconcile computes: retained `[zoe]`, universe `[zoe, mud]`, removed `[mud]`. zoe is
staged/committed with a synthesized peer map (`ha_reconcile_injected_peer_map`); mud is
decommissioned. The fake peer's IP/name must not collide with zoe's real IP/node_id.

## Scenario 3 — Expand 1 + experimental fake → 2 nodes (add mud back as a real peer)

Retained = both real hosts · Universe = both · Removed = none. Fake peer **disabled** — it simply
disappears once a real second peer exists. No decommission.

Inventory — put both hosts back in the retained group (identical to Scenario 1):

```yaml
ha_testnet_peers:
  vars:
    solana_validator_ha_inventory_group: ha_testnet_peers
  hosts:
    zoe-lat-dal:
    mud-lat-lax:
```

Command (back to the base command — note **no** fake-peer flag, **no** decommission):

```bash
ansible-playbook playbooks/pb_reconcile_validator_ha_cluster.yml \
  -i latitude-hayek-testnet-ha.yml \
  -e "ha_reconcile_retained_peers_group=ha_testnet_peers" \
  -e "operator_user=eydel"
```

Reconcile computes: retained `[zoe, mud]`, universe `[zoe, mud]`, removed `[]`. Both staged with a
real derived peer map; the synthetic peer from Scenario 2 is overwritten on zoe.

## Scenario 4 — Expand 2 → 3 nodes (add a third host)

Retained = 3 hosts · Universe = 3 · Removed = none. Just add the new host to the inventory **and**
the retained group, give it a unique node_id + priority, then run the base command.

Inventory — add the third host definition and list all three in the retained group:

```yaml
# under all.hosts:
ari-lat-nyc:
  ansible_host: 203.0.113.40
  ansible_port: 2522
  validator_flavor: firedancer
  solana_validator_ha_public_ip_value: 203.0.113.40
  solana_validator_ha_node_id: ari          # unique
  solana_validator_ha_priority: 20           # unique across the group

ha_testnet_peers:
  vars:
    solana_validator_ha_inventory_group: ha_testnet_peers
  hosts:
    zoe-lat-dal:
    mud-lat-lax:
    ari-lat-nyc:
```

Command (base command, unchanged):

```bash
ansible-playbook playbooks/pb_reconcile_validator_ha_cluster.yml \
  -i latitude-hayek-testnet-ha.yml \
  -e "ha_reconcile_retained_peers_group=ha_testnet_peers" \
  -e "operator_user=eydel"
```

Reconcile computes: retained `[zoe, mud, ari]`, universe `[zoe, mud, ari]`, removed `[]`. All three
staged with a 2-peer map each; committed serially.

## Scenario 5 — Contract 3 → 2 nodes (drop the third host)

Retained = 2 hosts · Universe = 3 (dropped host still in inventory) · Removed = 1 → decommission.
Above the singleton threshold, so **no fake peer**; just **allow_decommission**.

Inventory — keep `ari-lat-nyc` **defined** in the inventory, but **remove it from the retained
group**:

```yaml
ha_testnet_peers:
  vars:
    solana_validator_ha_inventory_group: ha_testnet_peers
  hosts:
    zoe-lat-dal:
    mud-lat-lax:          # ari-lat-nyc dropped from the group, still defined under all.hosts
```

Command:

```bash
ansible-playbook playbooks/pb_reconcile_validator_ha_cluster.yml \
  -i latitude-hayek-testnet-ha.yml \
  -e "ha_reconcile_retained_peers_group=ha_testnet_peers" \
  -e "operator_user=eydel" \
  -e "ha_reconcile_allow_decommission=true"
```

Reconcile computes: retained `[zoe, mud]`, universe `[zoe, mud, ari]`, removed `[ari]`. zoe+mud
re-staged/committed with each other as the only peer; ari decommissioned last.

## Quick decision table

| From → To | Retained group contents | `experimental_fake_peer_enabled` | `allow_decommission` |
|-----------|-------------------------|----------------------------------|----------------------|
| Initial 2-node | both | — | — |
| 2 → 1 + fake | the one survivor | **true** | **true** |
| 1 + fake → 2 | both | — | — |
| 2 → 3 | all three | — | — |
| 3 → 2 | the two survivors | — | **true** |

Rule of thumb: **fake peer** only when the retained group would have exactly 1 host;
**allow_decommission** whenever a host disappears from the retained group while still in the
inventory.

## Living examples

The test harness already drives reconcile and serves as executable references for the command
shapes above:

- [`test-harness/scripts/verify-vm-hot-swap.sh`](../test-harness/scripts/verify-vm-hot-swap.sh) — `reconcile_validator_ha_cluster()`.
- [`test-harness/scripts/verify-compose-ha-reconcile.sh`](../test-harness/scripts/verify-compose-ha-reconcile.sh).

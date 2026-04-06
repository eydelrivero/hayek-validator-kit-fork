#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANSIBLE_DIR="$REPO_ROOT/ansible"

COMPOSE_ENGINE="${COMPOSE_ENGINE:-docker}"
WITH_COMPOSE_HOT_SWAP_MATRIX=false
WITH_VM_L2=false
SKIP_CONTRACT=false
SKIP_SYNTAX=false
SKIP_IDENTITY_MODEL=false
VM_ARCH="${VM_ARCH:-}"
VM_BASE_IMAGE="${VM_BASE_IMAGE:-}"

FAILURES=()

usage() {
  cat <<'EOF'
Usage:
  run-pr-228-regression-smoke.sh [options]

Default behavior:
  Runs a lightweight regression suite you can execute both before and after
  merging PR 228:
  - harness contract checks
  - ansible syntax checks for validator/swap/HA playbooks
  - identity-model consistency checks around hot-spare startup and runtime identity

Optional heavier checks:
  --with-compose-hot-swap-matrix    Run compose hot-swap matrix smoke
  --with-vm-l2                      Run VM hot-swap L2 guardrail suite

Options:
  --compose-engine <docker|podman>  (default: docker)
  --with-compose-hot-swap-matrix
  --with-vm-l2
  --vm-arch <amd64|arm64>           Required with --with-vm-l2
  --vm-base-image <path>            Required with --with-vm-l2
  --skip-contract
  --skip-syntax
  --skip-identity-model
  -h, --help
EOF
}

log_step() {
  printf '\n==> %s\n' "$*" >&2
}

note() {
  printf '    %s\n' "$*" >&2
}

fail() {
  FAILURES+=("$1")
  printf '    FAIL: %s\n' "$1" >&2
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$cmd" >&2
    exit 2
  fi
}

while (($# > 0)); do
  case "$1" in
    --compose-engine)
      COMPOSE_ENGINE="${2:-}"
      shift 2
      ;;
    --with-compose-hot-swap-matrix)
      WITH_COMPOSE_HOT_SWAP_MATRIX=true
      shift
      ;;
    --with-vm-l2)
      WITH_VM_L2=true
      shift
      ;;
    --vm-arch)
      VM_ARCH="${2:-}"
      shift 2
      ;;
    --vm-base-image)
      VM_BASE_IMAGE="${2:-}"
      shift 2
      ;;
    --skip-contract)
      SKIP_CONTRACT=true
      shift
      ;;
    --skip-syntax)
      SKIP_SYNTAX=true
      shift
      ;;
    --skip-identity-model)
      SKIP_IDENTITY_MODEL=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

syntax_inventory_file() {
  local inv
  inv="$(mktemp)"
  cat >"$inv" <<EOF
[validator_hosts]
host-alpha ansible_connection=local ansible_host=127.0.0.1
host-bravo ansible_connection=local ansible_host=127.0.0.1

[ha_pair]
host-alpha
host-bravo
EOF
  printf '%s\n' "$inv"
}

run_contract_checks() {
  log_step "Harness contract checks"
  if [[ ! -x "$REPO_ROOT/test-harness/bin/hvk-test" ]]; then
    note "Skipping harness contract checks: test-harness/bin/hvk-test is not present in this checkout."
    return 0
  fi
  require_cmd jq
  chmod +x "$REPO_ROOT/test-harness/bin/hvk-test"
  chmod +x "$REPO_ROOT/test-harness/targets/"*.sh
  chmod +x "$REPO_ROOT/ansible-tests/scripts/run-harness-contract-tests.sh"
  "$REPO_ROOT/ansible-tests/scripts/run-harness-contract-tests.sh"
}

run_syntax_checks() {
  log_step "Ansible syntax checks"
  require_cmd ansible-playbook

  local inventory
  inventory="$(syntax_inventory_file)"

  (
    cd "$ANSIBLE_DIR"
    export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
    export ANSIBLE_ROLES_PATH="$ANSIBLE_DIR/roles"
    local operator_user
    operator_user="$(id -un)"

    ansible-playbook --syntax-check \
      -i "$inventory" \
      --limit host-alpha \
      -e "target_host=host-alpha" \
      -e "ansible_user=$operator_user" \
      playbooks/pb_setup_validator_agave.yml

    ansible-playbook --syntax-check \
      -i "$inventory" \
      --limit host-alpha \
      -e "target_host=host-alpha" \
      -e "ansible_user=$operator_user" \
      -e "jito_version=3.1.10" \
      playbooks/pb_setup_validator_jito_v2.yml

    ansible-playbook --syntax-check \
      -i "$inventory" \
      -e "source_host=host-alpha" \
      -e "destination_host=host-bravo" \
      -e "operator_user=$operator_user" \
      playbooks/pb_hot_swap_validator_hosts_v2.yml

    ansible-playbook --syntax-check \
      -i "$inventory" \
      -e "target_ha_group=ha_pair" \
      -e "operator_user=$operator_user" \
      -e "ha_reconcile_inventory_group_all=validator_hosts" \
      playbooks/pb_reconcile_validator_ha_cluster.yml
  )

  rm -f "$inventory"
}

extract_startup_identity_mode() {
  local file="$1"
  if rg -q -- '--identity .*hot-spare-identity\.json' "$file"; then
    printf 'hot-spare\n'
    return
  fi
  if rg -q -- '--identity .*identity\.json' "$file"; then
    printf 'identity-link\n'
    return
  fi
  printf 'unknown\n'
}

yes_no_from_rg() {
  local pattern="$1"
  shift
  if rg -q -- "$pattern" "$@"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

run_identity_model_checks() {
  log_step "Identity model consistency checks"

  local agave_mode
  local jito_mode
  local install_creates_symlink
  local compose_harness_reads_identity_link
  local vm_harness_reads_identity_link
  local swap_verify_reads_identity_link
  local localnet_bootstrap_uses_identity_link
  local ha_runtime_reads_identity_link

  agave_mode="$(extract_startup_identity_mode "$REPO_ROOT/ansible/roles/solana_validator_agave/templates/validator.startup.j2")"
  jito_mode="$(extract_startup_identity_mode "$REPO_ROOT/ansible/roles/solana_validator_jito_v2/templates/validator.startup.j2")"
  install_creates_symlink="$(yes_no_from_rg 'Create identity\.json symlink' "$REPO_ROOT/ansible/roles/solana_validator_shared/tasks/install_validator_keyset.yml")"
  compose_harness_reads_identity_link="$(yes_no_from_rg '/identity\.json' "$REPO_ROOT/test-harness/scripts/verify-compose-hot-swap.sh")"
  vm_harness_reads_identity_link="$(yes_no_from_rg '/identity\.json' "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh")"
  swap_verify_reads_identity_link="$(yes_no_from_rg 'source_host_identity_link_path|destination_host_identity_link_path' "$REPO_ROOT/ansible/roles/solana_swap_validator_hosts_v2/tasks/verify.yml" "$REPO_ROOT/ansible/roles/solana_swap_validator_hosts_v2/vars/main.yml")"
  localnet_bootstrap_uses_identity_link="$(yes_no_from_rg '(/identity\.json|ln -sf .*identity\.json)' "$REPO_ROOT/solana-localnet/container-setup/scripts/initialize-localnet-and-demo-validators.sh")"
  ha_runtime_reads_identity_link="$(yes_no_from_rg 'state: link|ln -s .*identity\.json|set_identity_symlink|follow: false' "$REPO_ROOT/ansible/roles/solana_validator_ha/tasks/configure_runtime.yml" "$REPO_ROOT/ansible/roles/solana_validator_ha/tasks/stage_runtime.yml" "$REPO_ROOT/ansible/roles/solana_validator_ha/templates/ha-set-role.sh.j2")"

  note "Agave startup mode: $agave_mode"
  note "Jito startup mode: $jito_mode"
  note "Shared install creates identity symlink: $install_creates_symlink"
  note "Compose hot-swap harness reads identity.json: $compose_harness_reads_identity_link"
  note "VM hot-swap harness reads identity.json: $vm_harness_reads_identity_link"
  note "Swap role verify reads identity.json paths: $swap_verify_reads_identity_link"
  note "Localnet bootstrap uses identity.json: $localnet_bootstrap_uses_identity_link"
  note "HA runtime reads identity.json: $ha_runtime_reads_identity_link"

  if [[ "$agave_mode" != "$jito_mode" ]]; then
    fail "Agave and Jito startup templates disagree on the validator identity source ($agave_mode vs $jito_mode)."
  fi

  case "$agave_mode" in
    identity-link)
      if [[ "$install_creates_symlink" != "yes" ]]; then
        fail "Startup scripts still use identity.json, but install_validator_keyset no longer creates the identity.json symlink."
      fi
      ;;
    hot-spare)
      if [[ "$install_creates_symlink" == "yes" ]]; then
        fail "install_validator_keyset still creates identity.json even though startup now points directly at hot-spare-identity.json."
      fi
      if [[ "$compose_harness_reads_identity_link" == "yes" ]]; then
        fail "Compose hot-swap verifier still reads identity.json even though validator startup now points directly at hot-spare-identity.json."
      fi
      if [[ "$vm_harness_reads_identity_link" == "yes" ]]; then
        fail "VM hot-swap verifier still reads identity.json even though validator startup now points directly at hot-spare-identity.json."
      fi
      if [[ "$swap_verify_reads_identity_link" == "yes" ]]; then
        fail "solana_swap_validator_hosts_v2 verify tasks still rely on identity.json after startup moved to hot-spare-identity.json."
      fi
      if [[ "$localnet_bootstrap_uses_identity_link" == "yes" ]]; then
        fail "Localnet/demo bootstrap still uses identity.json while validator roles use hot-spare-identity.json."
      fi
      if [[ "$ha_runtime_reads_identity_link" == "yes" ]]; then
        fail "HA runtime still manages identity.json even though validator startup no longer reads it."
      fi
      ;;
    *)
      fail "Unable to determine validator startup identity mode from the Agave/Jito startup templates."
      ;;
  esac
}

run_hot_swap_contract_checks() {
  log_step "Hot-swap role and caller contract checks"

  local ufw_gate_present
  local vm_caller_enables_ufw_gate
  local compose_caller_disables_ufw_gate
  local debug_hold_removed
  local verify_localhost_delegate_removed

  ufw_gate_present="$(yes_no_from_rg 'manage_destination_ufw_peer_ssh_rule' \
    "$REPO_ROOT/ansible/roles/solana_swap_validator_hosts_v2/meta/argument_specs.yml" \
    "$REPO_ROOT/ansible/roles/solana_swap_validator_hosts_v2/tasks/prepare.yml")"
  vm_caller_enables_ufw_gate="$(yes_no_from_rg 'manage_destination_ufw_peer_ssh_rule=true' \
    "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh")"
  compose_caller_disables_ufw_gate="$(yes_no_from_rg 'manage_destination_ufw_peer_ssh_rule=false' \
    "$REPO_ROOT/test-harness/scripts/verify-compose-hot-swap.sh")"
  debug_hold_removed="$(yes_no_from_rg 'hot_swap_debug_hold_before_interhost_ssh_probe_sec|VM_HOT_SWAP_DEBUG_HOLD_BEFORE_INTERHOST_SSH_PROBE_SEC' \
    "$REPO_ROOT/ansible/roles/solana_swap_validator_hosts_v2" \
    "$REPO_ROOT/test-harness/scripts/verify-vm-hot-swap.sh" \
    "$REPO_ROOT/test-harness/scripts/verify-compose-hot-swap.sh" \
    "$REPO_ROOT/test-harness/scripts/run-vm-hot-swap-l3-e2e.sh")"
  verify_localhost_delegate_removed="$(yes_no_from_rg 'delegate_to:\\s*localhost' \
    "$REPO_ROOT/ansible/roles/solana_swap_validator_hosts_v2/tasks/verify.yml")"

  note "Hot-swap UFW gate present: $ufw_gate_present"
  note "VM caller enables UFW gate: $vm_caller_enables_ufw_gate"
  note "Compose caller disables UFW gate: $compose_caller_disables_ufw_gate"
  note "Debug hold references present: $debug_hold_removed"
  note "verify.yml still delegates to localhost: $verify_localhost_delegate_removed"

  if [[ "$ufw_gate_present" != "yes" ]]; then
    fail "solana_swap_validator_hosts_v2 no longer exposes manage_destination_ufw_peer_ssh_rule in the role/task contract."
  fi

  if [[ "$vm_caller_enables_ufw_gate" != "yes" ]]; then
    fail "verify-vm-hot-swap.sh no longer opts into manage_destination_ufw_peer_ssh_rule=true."
  fi

  if [[ "$compose_caller_disables_ufw_gate" != "yes" ]]; then
    fail "verify-compose-hot-swap.sh no longer opts out with manage_destination_ufw_peer_ssh_rule=false."
  fi

  if [[ "$debug_hold_removed" != "no" ]]; then
    fail "Debug hold references still exist after the PR 230 rebase cleanup."
  fi

  if [[ "$verify_localhost_delegate_removed" != "no" ]]; then
    fail "solana_swap_validator_hosts_v2 verify.yml still delegates destination-side verification to localhost."
  fi
}

run_compose_hot_swap_matrix() {
  log_step "Compose hot-swap matrix"
  require_cmd "$COMPOSE_ENGINE"
  chmod +x "$REPO_ROOT/test-harness/targets/"*.sh
  chmod +x "$REPO_ROOT/test-harness/scripts/run-compose-hot-swap-matrix.sh"
  "$REPO_ROOT/test-harness/scripts/run-compose-hot-swap-matrix.sh" \
    --compose-engine "$COMPOSE_ENGINE"
}

run_vm_l2_suite() {
  log_step "VM hot-swap L2 guardrails"
  require_cmd ansible
  require_cmd qemu-img
  if [[ -z "$VM_ARCH" || -z "$VM_BASE_IMAGE" ]]; then
    printf '%s\n' "--with-vm-l2 requires --vm-arch and --vm-base-image" >&2
    exit 2
  fi
  chmod +x "$REPO_ROOT/test-harness/scripts/run-vm-hot-swap-l2-guardrails.sh"
  "$REPO_ROOT/test-harness/scripts/run-vm-hot-swap-l2-guardrails.sh" \
    --stop-on-error \
    --vm-arch "$VM_ARCH" \
    --vm-base-image "$VM_BASE_IMAGE"
}

main() {
  require_cmd rg

  if [[ "$SKIP_CONTRACT" != true ]]; then
    run_contract_checks
  fi

  if [[ "$SKIP_SYNTAX" != true ]]; then
    run_syntax_checks
  fi

  if [[ "$SKIP_IDENTITY_MODEL" != true ]]; then
    run_identity_model_checks
    run_hot_swap_contract_checks
  fi

  if [[ "$WITH_COMPOSE_HOT_SWAP_MATRIX" == true ]]; then
    run_compose_hot_swap_matrix
  fi

  if [[ "$WITH_VM_L2" == true ]]; then
    run_vm_l2_suite
  fi

  if ((${#FAILURES[@]} > 0)); then
    printf '\nRegression suite completed with %d failure(s):\n' "${#FAILURES[@]}" >&2
    printf '  - %s\n' "${FAILURES[@]}" >&2
    exit 1
  fi

  printf '\nRegression suite passed.\n' >&2
}

main "$@"

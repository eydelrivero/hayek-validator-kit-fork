# Hayek Validator Kit - Test Runner

## Getting Started

### Prerequisites

- Docker and Docker Compose installed
- SSH agent running (for SSH key forwarding)

### Starting the Test Environment

The tests run in a Docker container environment. You can start it in two ways:

#### Option 1: Command Line (Recommended for CLI users)

```bash
# Navigate to the ansible-tests directory
cd ansible-tests

# Start the test environment (this builds and starts the test-runner container)
docker compose up -d

# Enter the test-runner container
docker compose exec test-runner bash
```

#### Option 2: VSCode Dev Container (Recommended for VSCode users)

1. Open the project in VSCode
2. Press `F1` (or `Cmd+Shift+P` on Mac, `Ctrl+Shift+P` on Windows/Linux)
3. Type "Dev Containers: Reopen in Container"
4. Select **"Ansible tests cluster devcontainer"** (uses the `test-runner` service)

This will automatically:

- Build and start the docker-compose environment
- Open VSCode inside the `test-runner` container
- Mount the project at `/hayek-validator-kit`
- Set up all the necessary tools and environment

**Note:** The devcontainer configuration is located at `.devcontainer/ansible-tests-cluster/devcontainer.json` and uses the `test-runner` service from `ansible-tests/docker-compose.yml`.

#### What You Get Inside the Container

Once inside the test-runner container (either method), you'll have:

- Molecule and Ansible pre-installed
- The project mounted at `/hayek-validator-kit`
- Helper commands available (see below)
- CSV files location: `~/new-metal-box/iam_setup.csv`

### Stopping the Test Environment

```bash
# Stop containers (from host machine)
docker compose down

# Stop and remove volumes (clean slate)
docker compose down -v
```

## Quick Start (Inside Test-Runner Container)

1. **Check current scenario:**

   ```bash
   echo $MOLECULE_SCENARIO
   # or
   scenarios    # List all scenarios with current one marked
   ```

2. **Select scenario (if needed):**

   ```bash
   select       # Interactive scenario picker
   ```

3. **Run tests:**

   ```bash
   help         # Show available commands for current scenario
   run          # Interactive test runner
   ```

## Available Test Scenarios

- **iam_manager_tests** - IAM Manager Testing with CSV configuration
- **common_tests** - Common system and architecture compatibility testing
- **monitoring_agent_tests** - Monitoring agent installation and idempotency testing
- **rust_env_v2_tests** - Rust Environment v2 (RBAC-enabled) role testing

## Common Commands

### IAM Manager Tests (Default)

```bash
# Full test suite
molecule test -s iam_manager_tests -- -e csv_file=iam_setup.csv

# Setup only
molecule converge -s iam_manager_tests -- -e csv_file=iam_setup.csv

# Verify only
molecule verify -s iam_manager_tests

# Access container
molecule login -s iam_manager_tests

# Cleanup
molecule destroy -s iam_manager_tests
```

### Rust Environment v2 Tests

```bash
# Full test suite (requires CSV file with users)
molecule test -s rust_env_v2_tests -- -e csv_file=iam_setup.csv

# Setup only
molecule converge -s rust_env_v2_tests -- -e csv_file=iam_setup.csv

# Verify only
molecule verify -s rust_env_v2_tests

# Access container
molecule login -s rust_env_v2_tests

# Cleanup
molecule destroy -s rust_env_v2_tests
```

**Note:** This test scenario first runs the `iam_manager` role to set up RBAC-enabled hosts (users, groups, sudoers), then runs the `rust_env_v2` role to install Rust system-wide. This ensures the role is tested in the correct RBAC-enabled environment.

### Other Scenarios

```bash
molecule test -s common_tests
```

## Interactive Commands

- `help` - Show available commands
- `scenarios` - List all scenarios
- `select` - Choose scenario interactively
- `run` - Execute tests interactively

## Important Paths

- `/hayek-validator-kit/` - Main project directory
- `/new-metal-box/` - CSV configuration files
- `/hayek-validator-kit/ansible-tests/molecule/` - All test scenarios

## CI/CD Scripts

### Run All Tests

```bash
# Run all scenarios (stops on first failure)
./scripts/run-all-tests.sh

# Run all scenarios (continue on errors)
./scripts/run-all-tests.sh --continue-on-error
```

### Individual Scenario Scripts

```bash
# IAM Manager tests
./scripts/run-iam-manager-tests.sh

# Common tests
./scripts/run-common-tests.sh

# Monitoring agent tests
./scripts/run-monitoring-agent-tests.sh

# Rust Environment v2 tests
./scripts/run-rust-env-v2-tests.sh
```

### Harness Contract Smoke Test

```bash
# Verifies the cross-target harness command/adapter contract surface
./scripts/run-harness-contract-tests.sh
```

### Features

- **Smart parameter handling** - Applies correct parameters per scenario
- **Detailed reporting** - Shows execution times and results summary
- **CI/CD friendly** - Proper exit codes for pipeline integration
- **Error handling** - Continue on error mode for comprehensive testing

## CSV Generation

CSV file: `/new-metal-box/iam_setup.csv`

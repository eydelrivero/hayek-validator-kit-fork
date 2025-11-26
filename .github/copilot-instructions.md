# Hayek Validator Kit

The Hayek Validator Kit is an infrastructure automation toolkit for deploying and managing Solana blockchain validators. It uses Ansible for remote provisioning and Docker Compose for local development and testing environments.

**Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## Working Effectively

### Bootstrap, Build, and Test the Repository

1. **Install Python dependencies for pre-commit hooks:**
   ```bash
   pip install pre-commit
   pre-commit install
   ```
   - Takes ~7 seconds for installation
   - Takes ~9 seconds for initial hook setup

2. **Run pre-commit checks (ALWAYS run before committing):**
   ```bash
   pre-commit run --all-files
   ```
   - Takes ~9 seconds to complete
   - **CRITICAL**: This WILL fail on first run due to shell script formatting issues - this is expected
   - **NEVER CANCEL**: Always let pre-commit complete even when it shows failures
   - Failures are mostly shellcheck warnings that should be addressed

3. **Validate Ansible playbook syntax:**
   ```bash
   cd ansible
   ansible-playbook --syntax-check playbooks/pb_setup_metal_box.yml
   # Or check the main playbooks in ansible root:
   ansible-playbook --syntax-check solana_setup_host.yml
   ansible-playbook --syntax-check solana_new_metal_box.yml
   ```
   - Takes ~1 second when run from ansible/ directory
   - **IMPORTANT**: Must run from ansible/ directory for roles to be found
   - Main playbooks are now in both ansible/playbooks/ and ansible/ root directories

4. **Setup Docker environment for local development:**
   ```bash
   cd solana-localnet
   export COMPOSE_PROJECT_NAME=hayek-localnet
   export ANSIBLE_REMOTE_USER=testuser
   export SSH_AUTH_SOCK=/dev/null
   docker compose config --quiet
   ```
   - Takes <1 second for configuration validation
   - **REQUIRED**: All three environment variables must be set

5. **Build Docker images (time-intensive):**
   ```bash
   docker compose build
   ```
   - **NEVER CANCEL**: Takes 10-20 minutes depending on network and system. Set timeout to 30+ minutes.
   - Builds multiple Ubuntu-based containers with Solana tooling pre-installed

### Solana CLI Build Process (EXTREMELY TIME-INTENSIVE)

**WARNING**: Building Solana CLI from source is the most time-consuming operation in this repository.

1. **Install build dependencies:**
   ```bash
   sudo apt-get update
   sudo apt-get install -y build-essential pkg-config libudev-dev llvm libclang-dev protobuf-compiler
   ```
   - Takes 2-5 minutes depending on system

2. **Download and build Solana CLI:**
   **Option A: Using provided build scripts (RECOMMENDED):**
   ```bash
   cd solana-localnet/build-solana-cli
   ./run-build-in-container.sh
   ```
   - Uses containerized build environment
   - Includes S3 upload functionality for pre-built binaries
   - See docs.hayek.fi for detailed build instructions
   
   **Option B: Manual build (if needed):**
   ```bash
   export SOLANA_RELEASE=2.1.13
   mkdir -p /tmp/solana-build && cd /tmp/solana-build
   curl -L -O "https://github.com/anza-xyz/agave/archive/refs/tags/v${SOLANA_RELEASE}.tar.gz"
   tar -xzf "v${SOLANA_RELEASE}.tar.gz"
   cd "agave-${SOLANA_RELEASE}"
   rustup toolchain install 1.81.0
   rustup override set 1.81.0
   ./scripts/cargo-install-all.sh . --validator-only
   ```
   - **NEVER CANCEL**: Build takes 45-60 minutes to complete. Set timeout to 90+ minutes.
   - **CRITICAL**: Uses Rust 1.81.0 specifically - do not use other versions
   - **MEMORY INTENSIVE**: Requires significant RAM and CPU resources

### Local Development Environment

1. **Start the complete local Solana network:**
   ```bash
   cd solana-localnet
   export COMPOSE_PROJECT_NAME=hayek-localnet
   export ANSIBLE_REMOTE_USER=testuser
   export SSH_AUTH_SOCK=/dev/null
   docker compose up -d
   ```
   - Takes 2-5 minutes for initial startup
   - Creates a multi-node Solana testnet with gossip entrypoint and validator nodes

2. **Access the Ansible control container:**
   ```bash
   docker compose exec ansible-control bash
   ```
   - Use this container for running Ansible playbooks against the local environment

3. **Check container health:**
   ```bash
   docker compose ps
   ```
   - All containers should show "healthy" status

4. **View logs:**
   ```bash
   docker compose logs -f [service-name]
   ```
   - Available services: gossip-entrypoint, host-alpha, host-bravo, host-charlie, ansible-control
   
5. **Use convenient startup scripts:**
   ```bash
   # Start localnet from outside IDE
   ./start-localnet-from-outside-ide.sh
   
   # Standard localnet startup from ansible-control container
   ./container-setup/scripts/initialize-localnet-and-demo-validators.sh
   
   # Add penetration testing tools
   ./add-pentest-to-localnet.sh
   ```

## Validation

### Manual Testing Requirements
After making any changes to Ansible roles or Docker configurations:

1. **Always run complete syntax validation:**
   ```bash
   pre-commit run --all-files
   cd ansible && ansible-playbook --syntax-check playbooks/pb_setup_metal_box.yml
   # Also check main playbooks:
   cd ansible && ansible-playbook --syntax-check solana_setup_host.yml
   cd ansible && ansible-playbook --syntax-check solana_new_metal_box.yml
   ```

2. **Test Docker environment startup:**
   ```bash
   cd solana-localnet
   export COMPOSE_PROJECT_NAME=hayek-localnet ANSIBLE_REMOTE_USER=testuser SSH_AUTH_SOCK=/dev/null
   docker compose up -d --build
   docker compose ps  # Verify all containers are healthy
   ```

3. **Test key generation (if Solana CLI is available):**
   ```bash
   # Inside a container with Solana CLI installed:
   solana-keygen new --no-bip39-passphrase -o test-keypair.json
   solana-keygen pubkey test-keypair.json
   ```

### Code Quality Validation
- **ALWAYS run pre-commit hooks before committing**: `pre-commit run --all-files`
- **Address shellcheck warnings**: The codebase has existing shellcheck issues that should be fixed when working on shell scripts
- **Ansible syntax**: Use `ansible-playbook --syntax-check` for all modified playbooks

## Common Tasks

### Repository Structure
```
.
├── ansible/                     # Ansible roles and playbooks for remote provisioning
│   ├── playbooks/              # Specialized Ansible playbooks
│   ├── roles/                  # Reusable Ansible roles
│   ├── group_vars/             # Environment-specific variables
│   ├── host_vars/              # Host-specific variables
│   ├── iam/                    # IAM and user management files
│   ├── scripts/                # Utility scripts for operations
│   ├── solana_setup_host.yml   # Main host setup playbook
│   ├── solana_new_metal_box.yml # New server provisioning
│   └── solana_two_host_operations.yml # Multi-host operations
├── solana-localnet/            # Docker-based local development environment
│   ├── container-setup/        # Container setup scripts and systemd units
│   │   ├── scripts/            # Container setup scripts
│   │   │   └── initialize-localnet-and-demo-validators.sh       # Localnet startup script from ansible-control container
│   │   └── systemd/            # Systemd unit files for containers
│   ├── docker-compose.yml      # Multi-container Solana testnet
│   ├── Dockerfile              # Container build definitions
│   ├── build-solana-cli/       # Solana CLI build automation
│   ├── validator-keys/         # Pre-generated validator keypairs
│   ├── start-localnet-from-outside-ide.sh # IDE-independent startup
│   └── add-pentest-to-localnet.sh # Add security testing tools
├── .devcontainer/              # VS Code dev container configuration
├── .pre-commit-config.yaml     # Code quality hooks
├── CONTRIBUTING.md             # Contribution guidelines
├── ansible_health_check_prompt.md # Ansible diagnostics guide
└── README.md                   # Basic project information
```

### Key Environment Variables
- `COMPOSE_PROJECT_NAME`: Docker compose project identifier (use "hayek-localnet")
- `ANSIBLE_REMOTE_USER`: Target user for Ansible operations (use "testuser" for local dev)
- `SSH_AUTH_SOCK`: SSH agent socket (use "/dev/null" if SSH agent not available)
- `SOLANA_RELEASE`: Solana/Agave version to build (currently "2.1.13")

### Important Commands Reference
```bash
# Quick environment check
docker --version && docker compose version && ansible --version && python3 --version

# Ansible from project root - check various playbooks
cd ansible && ansible-playbook --syntax-check playbooks/pb_setup_metal_box.yml
cd ansible && ansible-playbook --syntax-check solana_setup_host.yml

# Docker development environment
cd solana-localnet && export COMPOSE_PROJECT_NAME=hayek-localnet ANSIBLE_REMOTE_USER=testuser SSH_AUTH_SOCK=/dev/null

# Pre-commit validation (run from project root)
pre-commit run --all-files

# View container logs
docker compose logs -f gossip-entrypoint
```

### Timeout Guidelines and Never Cancel Warnings
- **Pre-commit hooks**: 30 seconds (normal), allow up to 2 minutes for first run
- **Ansible syntax check**: 5 seconds
- **Docker config validation**: 5 seconds
- **Docker image builds**: **NEVER CANCEL** - 10-20 minutes, set timeout to 30+ minutes
- **Solana CLI compilation**: **NEVER CANCEL** - 45-60 minutes, set timeout to 90+ minutes
- **Docker container startup**: 2-5 minutes, set timeout to 10 minutes

### Troubleshooting Common Issues
1. **Docker build failures**: Usually network-related. Retry with `docker compose build --no-cache`
2. **Ansible role not found**: Ensure you're running playbooks from the `ansible/` directory
3. **Pre-commit hook failures**: Most failures are shellcheck warnings - review and address them
4. **Environment variable issues**: Always set the three required vars: `COMPOSE_PROJECT_NAME`, `ANSIBLE_REMOTE_USER`, `SSH_AUTH_SOCK`
5. **Solana build failures**: Ensure Rust 1.81.0 is installed and active: `rustup override set 1.81.0`

## Network and External Dependencies
- **GitHub**: Downloads Agave/Solana source code releases
- **Docker Hub**: Base Ubuntu and Alpine images
- **Rust/Cargo**: Crate dependencies for Solana CLI builds
- **Alpine package mirrors**: For container dependency installation
- **S3**: Pre-built Solana binaries for ARM64 architecture (configured in build-solana-cli/)
- **docs.hayek.fi**: External documentation for detailed setup instructions

**Note**: Network connectivity issues may cause Docker builds or Solana CLI compilation to fail. This is environmental and not related to code changes.

## Additional Resources
- **External Documentation**: https://docs.hayek.fi/dev-public-goods/hayek-validator-kit/
- **Contributing Guidelines**: See CONTRIBUTING.md for code standards and submission process
- **Ansible Health Checks**: Use ansible_health_check_prompt.md for comprehensive codebase analysis
- **Build Documentation**: See solana-localnet/build-solana-cli/README.md for CLI build instructions

ARG SOLANA_RELEASE=3.1.10
ARG SOLANA_DOWNLOAD_ROOT=https://solv-store.s3.us-east-1.amazonaws.com/agave/releases/download

# Base Ubuntu with common tooling
FROM ubuntu:24.04 AS ubuntu-base
ARG SOLANA_RELEASE
LABEL maintainer="hayek-validator-kit"

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
       apt-utils \
       locales \
       python3-dev \
       python3-setuptools \
       python3-pip \
       software-properties-common \
       rsyslog sudo iproute2 \
       openssh-client openssh-server git curl nano openssl tar jq less tree \
       at cron logrotate \
    && apt-get purge -y --auto-remove \
    && apt-get clean \
    && rm -Rf /var/lib/apt/lists/* \
    && rm -Rf /usr/share/doc && rm -Rf /usr/share/man

# Fix potential UTF-8 errors with ansible-test.
RUN locale-gen en_US.UTF-8

# Remove useless Python environment warning flag.
RUN rm -rf /usr/lib/python3.12/EXTERNALLY-MANAGED || true


# Download Solana/Agave binaries (used by ansible-control)
FROM alpine AS solana-binaries
ARG SOLANA_RELEASE
ARG SOLANA_DOWNLOAD_ROOT

RUN CPU_TYPE="$(uname -m)" \
  && case "$CPU_TYPE" in \
    x86_64) ;; \
    aarch64) ;; \
    *) echo "unsupported architecture"; exit 1 ;; \
  esac \
  && SOLANA_DOWNLOAD_URL="$SOLANA_DOWNLOAD_ROOT/v${SOLANA_RELEASE}/solana-release-${CPU_TYPE}-unknown-linux-gnu.tar.bz2" \
  && apk add --no-cache curl tar \
  && mkdir -p "/downloads" \
  && echo "Downloading ${SOLANA_DOWNLOAD_URL}..." \
  && curl -sSfL "$SOLANA_DOWNLOAD_URL" -o "/downloads/${SOLANA_RELEASE}.tar.bz2"

RUN --mount=type=cache,target=/root/.cache \
    tar -xvjf "/downloads/${SOLANA_RELEASE}.tar.bz2" --directory "/"


# Molecule runner image
FROM ubuntu-base AS molecule-runner
ARG SOLANA_RELEASE
ARG SOLANA_DOWNLOAD_ROOT
ARG DEFAULT_SCENARIO=iam_manager_tests

# Install Docker CLI and Ansible/Molecule via Pip
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates gnupg lsb-release curl \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
      docker-ce-cli docker-compose-plugin docker-buildx-plugin \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PIP_PACKAGES="ansible passlib molecule molecule-plugins[docker] ansible-lint yamllint"
RUN pip3 install $PIP_PACKAGES

RUN mkdir -p /opt/code/tools
WORKDIR /hayek-validator-kit/ansible-tests/

SHELL [ "/bin/bash", "-c" ]
ENV LANG=C.UTF-8

ENV SOLANA_INSTALL_DIR=/root/.local/share/solana/install

RUN --mount=type=cache,target=/root/.cache \
    mkdir -p ~/.ssh \
    && mkdir -p "$SOLANA_INSTALL_DIR/releases/$SOLANA_RELEASE"

COPY --from=solana-binaries --chown=root:root "/solana-release" "$SOLANA_INSTALL_DIR/releases/$SOLANA_RELEASE/solana-release"

RUN --mount=type=cache,target=/root/.cache \
    ln -sf "$SOLANA_INSTALL_DIR/releases/$SOLANA_RELEASE/solana-release" "$SOLANA_INSTALL_DIR/active_release" \
    && export PATH=$SOLANA_INSTALL_DIR/active_release/bin:$PATH \
    && solana --version \
    && agave-validator --version \
    && echo "export PATH=$SOLANA_INSTALL_DIR/active_release/bin:"'$PATH' >> ~/.profile \
    && echo 'if [ -f ~/.bashrc ]; then source ~/.bashrc; fi' >> ~/.profile \
    && echo 'export PS1="\[\e[0;32m\]test-runner\[\e[m\]:\w\$ "' >> ~/.bashrc

# Copy and execute welcome setup script
COPY scripts/setup-welcome.sh /opt/scripts/setup-welcome.sh
RUN chmod +x /opt/scripts/setup-welcome.sh \
    && /opt/scripts/setup-welcome.sh ${DEFAULT_SCENARIO} /hayek-validator-kit /root/new-metal-box

CMD [ "bash" ]


# Pristine Ubuntu with systemd and ssh (host-charlie)
FROM ubuntu-base AS naked-builder

# Set workdir
RUN mkdir -p /opt/code/tools
WORKDIR /opt/code/tools

# Copy SSH setup script
RUN mkdir -p /opt/scripts
COPY scripts/setup-ssh-keys.sh /opt/scripts/setup-ssh-keys.sh
RUN chmod +x /opt/scripts/setup-ssh-keys.sh

# Give ubuntu passwordless sudo access for ansible playbooks testing
RUN touch /etc/sudoers.d/90-cloud-init-users
RUN echo "ubuntu ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/90-cloud-init-users

SHELL [ "/bin/bash", "-c" ]
ENV LANG=C.UTF-8

# Start ssh server on boot
RUN --mount=type=cache,target=/root/.cache \
    systemctl enable ssh

CMD [ "bash" ]

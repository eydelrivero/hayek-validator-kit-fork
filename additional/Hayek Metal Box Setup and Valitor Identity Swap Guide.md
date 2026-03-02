# New Metal Box Setup (Solana / Jito / DoubleZero)

## 1. Create CSV files for users and authorized IPs

```bash
# Create a ~/new-metal-box/iam_setup.csv
# Create a ~/new-metal-box/authorized_ips.csv
```

For docker based localnet test we use `solana-localnet/localnet-new-metal-box/iam_setup_dev.csv` and no `authorized_ips.csv` because we don't run ufw on docker. This can also be auto generated for the tests to avoid hardcoding.

## 2. Provision new metal box
Then we go into a bare-metal provider and rent a server.

### Verify metal box (skip for VM tests)
https://docs.hayek.fi/dev-public-goods/validator-operations/host-infrastructure/choosing-your-metal#verify-cpu-governor

```sh
ssh ubuntu@SOURCE_SERVER_IP

ls /sys/devices/system/cpu/cpu0/cpufreq | grep -E "amd_pstate"
# should show amd_pstate

cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
# should acpi-cpufreq
```

- `box_ip_address`: `SOURCE_SERVER_IP`
- `hostname`: `hyk-edg-dal2`

## 3. Update `repo_root/ansible/solana_new_metal_box.yml`

```yaml
---
all:
  hosts:
    new-metal-box:
      ansible_host: SOURCE_SERVER_IP # <-- Replace with your box ip
      ansible_port: 22
```

```bash
cd ansible
```

## 4. Setup server users

```bash
ansible-playbook playbooks/pb_setup_users_validator.yml \
  -i solana_new_metal_box.yml \
  -e "target_host=new-metal-box" \
  -e "ansible_user=ubuntu" \
  -e "csv_file=iam_setup_prod.csv"
```

## 5. Manually set passwords for the operator admin and non-admin users


```bash
ssh eydel_admin@SOURCE_SERVER_IP
sudo reset-my-password # and follow the instructions
```

```
ssh eydel@SOURCE_SERVER_IP
sudo reset-my-password # and follow the instructions
```

## 6. Run bare metal box setup

```bash
ansible-playbook playbooks/pb_setup_metal_box.yml \
  -i solana_new_metal_box.yml \
  -e "target_host=new-metal-box" \
  -e "ansible_user=eydel_admin" \
  -e "csv_file=authorized_ips_prod.csv" \
  -K
```

- After this, SSH port is `2522`.

## 7. Update `ansible/solana_setup_host.yml`

```yaml
all:
  hosts:
    hyk-edg-dal2:
      ansible_host: SOURCE_SERVER_IP
      ansible_port: 2522

  children:
    solana:
      hosts:
        hyk-edg-dal2:

    solana_mainnet:
      hosts:
        hyk-edg-dal2:

    city_dal:
      hosts:
        hyk-edg-dal2:
```

## 8. Change hostname manually

```bash
sudo hostnamectl set-hostname hyk-edg-dal2
sudo nano /etc/hostname
sudo nano /etc/hosts
```

## 9. Download validator keys. For localnet tests we use demo and demo1 keys under `solana-localnet/validator-keys` in this repo, not keys from `~/.validator-keys/`.

```bash
mkdir -p ~/.validator-keys/hayek-mainnet/

# Manually download keys from 1Password and check they have been downloaded
ll ~/.validator-keys/hayek-mainnet/
```

Expected files:

- `dz-id.json`
- `jito-relayer-block-eng.json`
- `primary-target-identity.json`
- `vote-account.json`

`dz` in `dz-id.json` stands for DoubleZero. For localnet tests we don't have DoubleZero identity json.

## 10. Start and enter prod ansible-control

```bash
./start-prod-ansible-control.sh
docker compose -f /Users/eydel/workdir/repos/hayek-validator-kit/solana-localnet/docker-compose.yml --profile prod exec -w /hayek-validator-kit ansible-control-prod bash -l

cd ansible
```

### For localnet tests using docker/podman this is the process
```sh
cd solana-localnet
./start-localnet-docker.sh
```
The `start-localnet-docker.sh` command will spin-off the following containers:
```
docker ps
CONTAINER ID   IMAGE                               COMMAND                  CREATED         STATUS                   PORTS                                                                                                                                                                       NAMES
a307cb921455   solana-localnet-ansible-control     "/bin/bash -lc '/hay…"   4 minutes ago   Up 3 minutes                                                                                                                                                                                         ansible-control-localnet
630c64c6e5ca   solana-localnet-validator           "/lib/systemd/system…"   4 minutes ago   Up 3 minutes             0.0.0.0:9122->22/tcp, [::]:9122->22/tcp                                                                                                                                     host-alpha
53c554976555   solana-localnet-ubuntu-naked        "/lib/systemd/system…"   4 minutes ago   Up 4 minutes             0.0.0.0:9322->22/tcp, [::]:9322->22/tcp                                                                                                                                     host-charlie
ee9c34209b1e   solana-localnet-ubuntu-naked        "/lib/systemd/system…"   4 minutes ago   Up 4 minutes             0.0.0.0:9222->22/tcp, [::]:9222->22/tcp                                                                                                                                     host-bravo
d367de1bf1f8   solana-localnet-gossip-entrypoint   "/bin/bash -c /usr/b…"   4 minutes ago   Up 4 minutes (healthy)   0.0.0.0:8000-8020->8000-8020/tcp, [::]:8000-8020->8000-8020/tcp, 0.0.0.0:8899-8900->8899-8900/tcp, [::]:8899-8900->8899-8900/tcp, 0.0.0.0:9022->22/tcp, [::]:9022->22/tcp   gossip-entrypoint
```

The output of `start-localnet-docker.sh` is something like:
```
Starting localnet with docker...
[+] Building 15.3s (12/43)                                                                                                                                                                              
[+] Building 66.5s (51/51) FINISHED                                                                                                                                                                     
 => [internal] load local bake definitions                                                                                                                                                         0.0s
 => => reading from stdin 2.41kB                                                                                                                                                                   0.0s
 => [host-alpha internal] load build definition from Dockerfile                                                                                                                                    0.0s
 => => transferring dockerfile: 9.70kB                                                                                                                                                             0.0s
 => [ansible-control-localnet internal] load metadata for docker.io/library/ubuntu:24.04                                                                                                           1.7s
 => [gossip-entrypoint internal] load metadata for docker.io/library/alpine:latest                                                                                                                 0.9s
 => [gossip-entrypoint internal] load .dockerignore                                                                                                                                                0.0s
 => => transferring context: 2B                                                                                                                                                                    0.0s
 => [gossip-entrypoint ubuntu-base 1/3] FROM docker.io/library/ubuntu:24.04@sha256:d1e2e92c075e5ca139d51a140fff46f84315c0fdce203eab2807c7e495eff4f9                                                1.2s
 => => resolve docker.io/library/ubuntu:24.04@sha256:d1e2e92c075e5ca139d51a140fff46f84315c0fdce203eab2807c7e495eff4f9                                                                              0.0s
 => => sha256:66a4bbbfab887561d75f1fdb3c6221c974346f82c9229f5ef99f96b7e6c25704 28.87MB / 28.87MB                                                                                                   0.7s
 => => extracting sha256:66a4bbbfab887561d75f1fdb3c6221c974346f82c9229f5ef99f96b7e6c25704                                                                                                          0.4s
 => [host-bravo internal] load build context                                                                                                                                                       0.0s
 => => transferring context: 166B                                                                                                                                                                  0.0s
 => [host-alpha solana-binaries 1/3] FROM docker.io/library/alpine:latest@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659                                                  0.0s
 => => resolve docker.io/library/alpine:latest@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659                                                                             0.0s
 => [host-alpha internal] load build context                                                                                                                                                       0.0s
 => => transferring context: 252B                                                                                                                                                                  0.0s
 => [gossip-entrypoint internal] load build context                                                                                                                                                0.0s
 => => transferring context: 159B                                                                                                                                                                  0.0s
 => CACHED [ansible-control-localnet solana-binaries 2/3] RUN CPU_TYPE="$(uname -m)"   && SOLANA_DOWNLOAD_ROOT=   && case "$CPU_TYPE" in     x86_64) ;;     aarch64) ;;     *) echo "unsupported   0.0s
 => CACHED [ansible-control-localnet solana-binaries 3/3] RUN --mount=type=cache,target=/root/.cache     tar -xvjf "/downloads/2.2.20.tar.bz2" --directory "/"                                     0.0s
 => [host-alpha ubuntu-base 2/3] RUN rm -f /var/cache/apt/archives/lock &&      apt-get update && apt-get install -y --no-install-recommends          apt-utils          locales          python  21.9s
 => [gossip-entrypoint ubuntu-base 3/3] RUN sudo rm -rf /usr/lib/python3.12/EXTERNALLY-MANAGED                                                                                                     0.1s
 => [host-bravo naked-builder 1/6] RUN mkdir -p /opt/code/tools                                                                                                                                    0.1s 
 => [ansible-control-localnet ansible-control-builder 1/7] RUN locale-gen en_US.UTF-8                                                                                                              1.2s 
 => [host-alpha validator-builder  1/11] RUN mkdir -p /opt/code/tools                                                                                                                              0.3s 
 => [host-bravo naked-builder 2/6] WORKDIR /opt/code/tools                                                                                                                                         0.0s 
 => [host-bravo naked-builder 3/6] RUN echo "ubuntu ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers                                                                                                       0.2s 
 => [host-alpha validator-builder  2/11] WORKDIR /opt/code/tools                                                                                                                                   0.0s
 => [host-alpha validator-builder  3/11] COPY ./container-setup/systemd/set-container-default-user-ssh-key.service /etc/systemd/system/set-container-default-user-ssh-key.service                  0.0s
 => [gossip-entrypoint gossip-entrypoint-builder 3/7] RUN --mount=type=cache,target=/root/.cache     sudo systemctl enable ssh                                                                     0.2s
 => [host-alpha validator-builder  4/11] RUN systemctl enable set-container-default-user-ssh-key.service                                                                                           0.3s
 => [host-bravo naked-builder 4/6] COPY ./container-setup/systemd/set-container-default-user-ssh-key.service /etc/systemd/system/set-container-default-user-ssh-key.service                        0.0s
 => [host-bravo naked-builder 5/6] RUN systemctl enable set-container-default-user-ssh-key.service                                                                                                 0.3s
 => [gossip-entrypoint gossip-entrypoint-builder 4/7] RUN --mount=type=cache,target=/root/.cache     mkdir -p ~/.ssh     && mkdir -p "/root/.local/share/solana/install/releases/2.2.20"           0.4s
 => [host-alpha validator-builder  5/11] COPY ./container-setup/systemd/set-validator-service-user-ssh-key.service /etc/systemd/system/set-validator-service-user-ssh-key.service                  0.0s
 => [host-alpha validator-builder  6/11] RUN systemctl enable set-validator-service-user-ssh-key.service                                                                                           0.4s
 => [host-bravo naked-builder 6/6] RUN --mount=type=cache,target=/root/.cache     sudo systemctl enable ssh                                                                                        0.5s
 => [gossip-entrypoint gossip-entrypoint-builder 5/7] COPY --from=solana-binaries /solana-release /root/.local/share/solana/install/releases/2.2.20/solana-release                                 0.9s
 => [host-alpha validator-builder  7/11] RUN --mount=type=cache,target=/root/.cache     sudo systemctl enable ssh                                                                                  0.4s
 => [host-bravo] exporting to image                                                                                                                                                               10.0s
 => => exporting layers                                                                                                                                                                            8.4s
 => => exporting manifest sha256:74c77bbc2590f852367e6fdf52e7c6c132e54a6763b3a4c5e5c148d9160f465f                                                                                                  0.0s 
 => => exporting config sha256:0b21e7ab42f6d82e71a303c221620c431f0c1f058fc6dcb864f2eb56e5b915ea                                                                                                    0.0s 
 => => exporting attestation manifest sha256:e85e5eecc9651021dd940c125acefd5b54d8b6d8bc3ec3cf6b9fd5659f847bb9                                                                                      0.0s 
 => => exporting manifest list sha256:30ddee6713f1c12a2b0f4485ea3269f090e51982bfa4945517dbc5001b4f0678                                                                                             0.0s 
 => => naming to docker.io/library/solana-localnet-ubuntu-naked:latest                                                                                                                             0.0s 
 => => unpacking to docker.io/library/solana-localnet-ubuntu-naked:latest                                                                                                                          1.6s 
 => [ansible-control-localnet ansible-control-builder 2/7] RUN pip3 install ansible passlib                                                                                                       20.8s
 => [host-alpha validator-builder  8/11] RUN --mount=type=cache,target=/root/.cache     adduser --disabled-password --gecos "" sol     && echo "sol:solpw" | chpasswd     && usermod -aG sudo sol  0.5s
 => [gossip-entrypoint gossip-entrypoint-builder 6/7] RUN --mount=type=cache,target=/root/.cache     ln -sf "/root/.local/share/solana/install/releases/2.2.20/solana-release" "/root/.local/shar  0.2s
 => [host-alpha validator-builder  9/11] RUN --mount=type=cache,target=/root/.cache     mkdir -p ~/.ssh     && mkdir -p "/home/sol/.local/share/solana/install/releases/2.2.20"                    0.2s
 => [gossip-entrypoint gossip-entrypoint-builder 7/7] COPY ./container-setup/scripts/localnet-gossip-entrypoint-setup.sh /usr/bin                                                                  0.0s
 => [gossip-entrypoint] exporting to image                                                                                                                                                        14.1s
 => => exporting layers                                                                                                                                                                           12.0s
 => => exporting manifest sha256:d8aa4a57fcde2b6faeb32181719c6b557f14a5a0c198906331c4b29d093d5ab9                                                                                                  0.0s
 => => exporting config sha256:4b99d5c6d0399d2fde7f4a670e71aa61492abaa08912b265e824bb1301a515c4                                                                                                    0.0s
 => => exporting attestation manifest sha256:e2309cbe2175d887b35e6c992ac9a2f24a423ce7054b4650465d2ad767549fcb                                                                                      0.0s
 => => exporting manifest list sha256:79eb6629cde89937bfd7c3133bc07a038e562a61b599ed9d6fe4e1fde3718bb7                                                                                             0.0s
 => => naming to docker.io/library/solana-localnet-gossip-entrypoint:latest                                                                                                                        0.0s
 => => unpacking to docker.io/library/solana-localnet-gossip-entrypoint:latest                                                                                                                     2.1s
 => [host-alpha validator-builder 10/11] COPY --from=solana-binaries --chown=sol:sol /solana-release /home/sol/.local/share/solana/install/releases/2.2.20/solana-release                          0.7s
 => [host-alpha validator-builder 11/11] RUN --mount=type=cache,target=/root/.cache     ln -sf "/home/sol/.local/share/solana/install/releases/2.2.20/solana-release" "/home/sol/.local/share/sol  0.2s
 => [host-alpha] exporting to image                                                                                                                                                               14.3s
 => => exporting layers                                                                                                                                                                           12.1s
 => => exporting manifest sha256:d47e98f40cd65271615e1f447971a016db257c8e77118c718113fea815dce502                                                                                                  0.0s
 => => exporting config sha256:f77d10b3953d672bd82776616f8d3da6383c40d8168e9fde3a7bcb97b0db0153                                                                                                    0.0s
 => => exporting attestation manifest sha256:46fe493050280357f9129e873e16b1931e3aad12b8976972d12d96f35ce4e100                                                                                      0.0s
 => => exporting manifest list sha256:83a3c52630cf887614c7aa85a35517bf1be480576678e4f11f5041eb35066080                                                                                             0.0s
 => => naming to docker.io/library/solana-localnet-validator:latest                                                                                                                                0.0s
 => => unpacking to docker.io/library/solana-localnet-validator:latest                                                                                                                             2.2s
 => [host-bravo] resolving provenance for metadata file                                                                                                                                            0.0s
 => [gossip-entrypoint] resolving provenance for metadata file                                                                                                                                     0.0s
 => [host-alpha] resolving provenance for metadata file                                                                                                                                            0.0s
 => [ansible-control-localnet ansible-control-builder 3/7] RUN mkdir -p /opt/code/tools                                                                                                            0.3s
 => [ansible-control-localnet ansible-control-builder 4/7] WORKDIR /opt/code/tools                                                                                                                 0.0s
 => [ansible-control-localnet ansible-control-builder 5/7] RUN --mount=type=cache,target=/root/.cache     mkdir -p ~/.ssh     && mkdir -p "/root/.local/share/solana/install/releases/2.2.20"      0.6s
 => [ansible-control-localnet ansible-control-builder 6/7] COPY --from=solana-binaries /solana-release /root/.local/share/solana/install/releases/2.2.20/solana-release                            0.7s
 => [ansible-control-localnet ansible-control-builder 7/7] RUN --mount=type=cache,target=/root/.cache     ln -sf "/root/.local/share/solana/install/releases/2.2.20/solana-release" "/root/.local  0.1s
 => [ansible-control-localnet] exporting to image                                                                                                                                                 17.5s
 => => exporting layers                                                                                                                                                                           11.7s
 => => exporting manifest sha256:5a000ffa79d2323310656e2a247726b3a835a7894dbf409aa7f6635cd636f1e8                                                                                                  0.0s
 => => exporting config sha256:1861d100dae377a6b6fa7d669a6fb07aaa4ac9f147b48e3e98e8caf04e37d4f0                                                                                                    0.0s
 => => exporting attestation manifest sha256:632ed657b8a2e4ff454a571d186c6a77ea77494615d915560a35f5f18b552ba0                                                                                      0.0s
 => => exporting manifest list sha256:4d53349c334d94bd259b469feeb53a2511c74aaf2dafb9b89f7e42d00f3c4b5b                                                                                             0.0s
 => => naming to docker.io/library/solana-localnet-ansible-control:latest                                                                                                                          0.0s
 => => unpacking to docker.io/library/solana-localnet-ansible-control:latest                                                                                                                       5.7s
 => [ansible-control-localnet] resolving provenance for metadata file                                                                                                                              0.0s
[+] Building 4/4
 ✔ solana-localnet-ansible-control    Built                                                                                                                                                        0.0s 
 ✔ solana-localnet-gossip-entrypoint  Built                                                                                                                                                        0.0s 
 ✔ solana-localnet-validator          Built                                                                                                                                                        0.0s 
 ✔ solana-localnet-ubuntu-naked       Built                                                                                                                                                        0.0s 
[+] Running 8/8
 ✔ Network solana-localnet_solana_network  Created                                                                                                                                                 0.0s 
 ✔ Network solana-localnet_default         Created                                                                                                                                                 0.0s 
 ✔ Container keygen-init                   Exited                                                                                                                                                  6.6s 
 ✔ Container gossip-entrypoint             Healthy                                                                                                                                                32.7s 
 ✔ Container host-bravo                    Started                                                                                                                                                 5.5s 
 ✔ Container host-charlie                  Started                                                                                                                                                 5.5s 
 ✔ Container host-alpha                    Started                                                                                                                                                31.0s 
 ✔ Container ansible-control-localnet      Started                                                                                                                                                31.5s 
Waiting for ansible-control-localnet container to be ready...
✅ All containers are healthy.
🚀 Running solana-localnet initialization tasks...

OSTYPE IS: linux-gnu
Generating default solana cli signer...
Wrote new keypair to /root/.config/solana/id.json
WARNING: THIS SIGNER (HhFiLSbCHAKDtdWXsKMdRPTPvoAEgfwDDLK6Qu7g48nW) IS EPHEMERAL AND WILL BE DESTROYED WHEN THE ansible-control CONTAINER IS STOPPED OR DELETED!

SOLANA LOCALNET: Waiting for 20 finalized slots...

Finalized Slot: 31 | Elapsed: 0 seconds

Block height: 63
Slot: 63
Epoch: 0
Transaction Count: 62
Epoch Slot Range: [0..750)
Epoch Completed Percent: 8.400%
Epoch Completed Slots: 63/750 (687 remaining)
Epoch Completed Time: 30s/5m 4s (4m 34s remaining)

Requesting airdrop of 500000 SOL

Signature: 3ouHNa6kKupiGW7YQd4sJ5iU8BzqLP8fHAcV2zsJWVQrTUzM62wdJDjBbgQjKPbskyXRJzYgvZ5azxEu5teW7Ycb

500000 SOL
>>> ANSIBLE_DEMO_KEYS_DIR: /hayek-validator-kit/solana-localnet/validator-keys/demo1
>>> ANSIBLE_VALIDATORS_KEYS_DIR: /hayek-validator-kit/solana-localnet/validator-keys
Requesting airdrop of 42 SOL

Signature: hDDAV1zYrMx6F76YeRSsYpLGCaF6ETiW6vPAmJxkqeLx53x1LE4esgoNuqQwicDy12iAE2LuTzw8gJSfgVwPDB9

42 SOL

Signature: 5NRuamvuH3UD2NVHvsEuiykdDtkay71gwsiZ1vgHaJTfY9j3H37re1VYHM881cAjnSgngAnxDDCUKggERH647Gax


Signature: 5JRpkX6n6Z5VetXhum3Zev9bpXxuYGj7qdA8QEpP7NgJPbUiMog46EaE5r4QZ7vJj8NomDC1zcJSaPhfaDKX7rt5


Signature: 2FbLys8a2sss3SDy5kRXfZhSQXNSYmHSvhGsPFKcb99N1MPHE27AAae22MBFaKar78YTQcxAeskuDZb4PAnqzVHv

---   SETTING UP DEMO VALIDATOR SCRIPT WITH ACCOUNT KEYS...   ---

---   Configuring host-alpha with the demo validator key set   ---

primary-target-identity.json                                                                                                                                          100%  227   578.0KB/s   00:00    
cat validator startup script at /hayek-validator-kit/solana-localnet/container-setup/scripts/agave-validator-localnet.sh
#!/bin/bash
agave-validator \
    --identity /home/sol/keys/demo1/identity.json \
    --vote-account demo52s9s1foFXgnbVa8vYQM8GS9XRsJ3aMpus1rNnb \
    --authorized-voter /home/sol/keys/demo1/primary-target-identity.json \
    --known-validator C1PsbwP4ay8iwC6pyis1x27GmnC6RaepbwQ6LVrZe8qo \
    --only-known-rpc \
    --log /home/sol/logs/agave-validator.log \
    --ledger /mnt/ledger \
    --accounts /mnt/accounts \
    --snapshots /mnt/snapshots \
    --entrypoint gossip-entrypoint:8001 \
    --expected-genesis-hash BG3DCAXJCHujLx6Ytanf2xu7JzrWR9MyrVBGXNBwYfkp \
    --allow-private-addr \
    --rpc-port 8899 \
    --no-os-network-limits-test \
    --limit-ledger-size 50000000

agave-validator-localnet.sh                                                                                                                                           100%  685   247.8KB/s   00:00    
Generating hot-spare-identity.json...
Wrote new keypair to /home/sol/keys/demo1/hot-spare-identity.json
[Unit]
Description=Solana Validator
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=5
User=sol
LimitNOFILE=1000000
LimitMEMLOCK=2000000000
LogRateLimitIntervalSec=0
Environment=PATH=/bin:/usr/bin:~/.local/share/solana/install/active_release/bin
ExecStart=/home/sol/bin/run-validator-demo.sh

[Install]
WantedBy=multi-user.target
Created symlink /etc/systemd/system/multi-user.target.wants/sol.service → /etc/systemd/system/sol.service.
---   ALL DONE. LOCALNET IS RUNNING.   ---

Localnet started. Attach with:
docker compose -f /Users/eydel/workdir/repos/hayek-validator-kit/solana-localnet/docker-compose.yml -f /Users/eydel/workdir/repos/hayek-validator-kit/solana-localnet/docker-compose.docker.yml --profile localnet exec -w /hayek-validator-kit ansible-control-localnet bash -l
```

The we do
```
docker compose -f /Users/eydel/workdir/repos/hayek-validator-kit/solana-localnet/docker-compose.yml -f /Users/eydel/workdir/repos/hayek-validator-kit/solana-localnet/docker-compose.docker.yml --profile localnet exec -w /hayek-validator-kit ansible-control-localnet bash -l

cd ansible
```

Add target host fingerprint to container known_hosts:

```bash
ssh -p 2522 eydel@DESTINATION_SERVER_IP
```

## 11. (Optional) Clean up Jito relayer

```bash
sudo systemctl stop jito-relayer
sudo systemctl disable jito-relayer
sudo rm /etc/systemd/system/jito-relayer.service
sudo systemctl daemon-reload
sudo systemctl reset-failed
```

## 12. Setup validator

```bash
ansible-playbook playbooks/pb_setup_validator_jito_v2.yml \
  -i solana_setup_host.yml \
  --limit hyk-edg-dal2 \
  -e "target_host=hyk-edg-dal2" \
  -e "ansible_user=eydel" \
  -e "validator_name=hayek-mainnet" \
  -e "validator_type=hot-spare" \
  -e "solana_cluster=mainnet" \
  -e "jito_version=3.1.8" \
  -e "jito_relayer_type=co-hosted" \
  -e "jito_relayer_version=0.4.2" \
  -e "build_from_source=true" \
  -e "use_official_repo=true" \
  -e "force_host_cleanup=true" \
  -K
```

## 13. Monitor validator startup

```bash
tail -f /opt/validator/logs/agave-validator.log
agave-validator -l /mnt/ledger/ monitor
# download snapshot -> download incremental snapshot -> load ledger -> block processing -> CTRL+C

solana catchup --our-localhost 8899
```

## 14. Temporary BAM opt-in/out

Monitor BAM logs:

```bash
tail -f /opt/validator/logs/agave-validator.log | grep -E 'bam_|ERROR|WARN'
```

Opt-in:

```bash
agave-validator --ledger /mnt/ledger set-bam-config --bam-url http://dallas.mainnet.bam.jito.wtf
# Output: INFO  solana_core::bam_manager] BAM connection established
```

Opt-out:

```bash
agave-validator --ledger /mnt/ledger set-bam-config --bam-url
# Output: WARN  solana_core::bam_manager] BAM connection not healthy after waiting for 6s, disconnecting and will retry
```

If repurposing Testnet/Mainnet host:

```bash
doublezero disconnect
```

DoubleZero is not enabled for localnet tests althoug installation and configuration will be good to test.

## 15. Update `ansible/solana_two_host_operations.yml`

```yaml
---
all:
  hosts:
    hyk-edg-dal2:
      ansible_host: SOURCE_SERVER_IP
      ansible_port: 2522
    hyk-lat-dal:
      ansible_host: DESTINATION_SERVER_IP
      ansible_port: 2522

  children:
    city_dal:
      hosts:
        hyk-edg-dal2:
        hyk-lat-dal:

    solana:
      hosts:
        hyk-edg-dal2:
        hyk-lat-dal:

    solana_mainnet:
      hosts:
        hyk-edg-dal2:
        hyk-lat-dal:
```

## 16. Prepare and run host swap

Before swap we watch live the exact moment when the validator identity is tranfer by doing on both servers either:

```bash
tail -f /opt/validator/logs/agave-validator.log | grep "Identity set to"
```

or

```sh
sudo -u sol -i
agave-validator -l /mnt/ledger monitor
```

The we do the swap (validator identity transfer):

```bash
ansible-playbook playbooks/pb_hot_swap_validator_hosts_v2.yml \
  -i solana_two_host_operations.yml \
  -e "source_host=hyk-lat-dal" \
  -e "destination_host=hyk-edg-dal2" \
  -e "operator_user=eydel" \
  -K
```

- `deprovision_source_host` is currently not working.

## 17. Install DoubleZero (currently manually)
This is currently a manual process and haven't been tested on localnet tests. The validator idenitty needs to be registered with DoubleZero first so we still don't know how much of this can be tested in localnet.

Reference: [DZ Mainnet-beta Connection](https://docs.malbeclabs.com/DZ%20Mainnet-beta%20Connection/)

```bash
# switch to an admin user
# must happen after primary identity is in place (not hot-spare identity)

curl -1sLf https://dl.cloudsmith.io/public/malbeclabs/doublezero/setup.deb.sh | sudo -E bash
sudo apt-get install doublezero
sudo systemctl status doublezerod
```

Configure firewall for GRE/BGP:

```bash
sudo ufw allow proto gre from any to any
sudo ufw allow in on doublezero0 from 169.254.0.0/16 to 169.254.0.0/16 port 179 proto tcp
sudo ufw allow out on doublezero0 from 169.254.0.0/16 to 169.254.0.0/16 port 179 proto tcp
exit
```

## 18. Copy DoubleZero identity

```bash
ssh -p 2522 eydel_admin@SOURCE_SERVER_IP
sudo -u sol -i
mkdir -p ~/.config/doublezero
exit

scp -P 2522 ~/.validator-keys/hayek-mainnet/dz-id.json eydel_admin@SOURCE_SERVER_IP:/tmp/dz-id.json
ssh -p 2522 eydel_admin@SOURCE_SERVER_IP 
sudo chown sol:sol /tmp/dz-id.json
sudo -u sol -i
cp /tmp/dz-id.json ~/.config/doublezero/id.json

doublezero address
doublezero latency
doublezero status

# only run next if status is connected
doublezero disconnect
exit
```

## 19. Set DoubleZero environment to mainnet-beta

As admin user:

```bash
DESIRED_DOUBLEZERO_ENV=mainnet-beta \
    && sudo mkdir -p /etc/systemd/system/doublezerod.service.d \
    && echo -e "[Service]\nExecStart=\nExecStart=/usr/bin/doublezerod -sock-file /run/doublezerod/doublezerod.sock -env $DESIRED_DOUBLEZERO_ENV" | sudo tee /etc/systemd/system/doublezerod.service.d/override.conf > /dev/null \
    && sudo systemctl daemon-reload \
    && sudo systemctl restart doublezerod
```

As `sol` user:

```bash
sudo -u sol -i
DESIRED_DOUBLEZERO_ENV=mainnet-beta \
    && doublezero config set --env $DESIRED_DOUBLEZERO_ENV  > /dev/null \
    && echo "✅ doublezerod configured for environment $DESIRED_DOUBLEZERO_ENV"
```

Check devices (wait ~30 seconds):

```bash
doublezero latency
exit
```

## 20. Open DoubleZero UDP port

```bash
sudo ufw allow in on doublezero0 to any port 44880 proto udp
sudo ufw allow out on doublezero0 to any port 44880 proto udp
```

## 21. Attest validator ownership / request access

```bash
sudo -u sol -i
doublezero-solana passport find-validator -u mainnet-beta
```

```bash
doublezero-solana passport prepare-validator-access -u mainnet-beta \
  --doublezero-address 9nxWixzZih86YrKapEiG3AZigQBpoUX9Avn5pS1GWMqX \
  --primary-validator-id hykfH9jUQqe2yqv3VqVAK5AmMYqrmMWmdwDcbfsm6My
```

Generate signature:

```bash
solana sign-offchain-message \
   service_key=9nxWixzZih86YrKapEiG3AZigQBpoUX9Avn5pS1GWMqX \
   -k /opt/validator/keys/hayek-mainnet/primary-target-identity.json
```

Submit request (replace signature):

```bash
doublezero-solana passport request-validator-access -k /opt/validator/keys/hayek-mainnet/primary-target-identity.json -u mainnet-beta \
--primary-validator-id hykfH9jUQqe2yqv3VqVAK5AmMYqrmMWmdwDcbfsm6My \
--signature SIGNATURE_HERE \
--doublezero-address 9nxWixzZih86YrKapEiG3AZigQBpoUX9Avn5pS1GWMqX
```

Connect in IBRL mode:

```bash
doublezero connect ibrl
```

## 22. Verify connection

```bash
doublezero status
ip route
```

## 23. Fix core affinity for PoH (not tested in localnet tests)

```bash
sudo -u sol -i
cd /opt/validator/scripts
bash fix_core_affinity_bug_for_poh.sh
exit
```


# Troubleshooting docker/podman localnet

This docker/podman setup has the following containers:
 - gossip-entrypint (this is where solana-test-validator is running)
 - host-alpha (a validator host)
 - host-bravo (a validator host)
 - host-charlie (a validator host)

The IP address of the containers are different from the ones used for VMs.

## After starting the validator service in each host, check this

1. [possible issue] ensure gossip-entrypoint ports 8899 and 8001 are open
# You might see error: Connection refused (os error 111) when doing "solana catchup" or "agave-validator monitor"
```sh
podman exec -it gossip-entrypoint ss -tulpn | grep 8899`
podman exec -it gossip-entrypoint ss -uap | grep 8001
```

2. [possible issue] ensure validator host port 8899 is open. I'll take a few seconds after container start to show up
`podman exec -it host-alpha ss -tulpn | grep 8899`

3. login into the validator host and debug
```sh
podman compose --profile localnet exec ansible-control-localnet bash -l
ansible-control$ ssh -i /localnet-ssh-keys/sol_ed25519 sol@host-alpha
# confirm LimitNOFILE and LimitNOFILESoft are set for sol service
sol@host-alpha:~$ sudo systemctl show sol | grep LimitNOFILE

# confirm demo validator in host-alpha is catching up or already caught up
sol@host-alpha:~$ solana -u http://gossip-entrypoint:8899 catchup --our-localhost 8899

# confirm demo validator is processing transactions
sol@host-alpha:~$ agave-validator -l /mnt/ledger/ monitor

# check the logs for any errors
sol@host-alpha:~$ tail -f logs/agave-validator.log
```

4. [potential issue] ensure gossip-entrypoint genesis hash matches the validator expected genesis hash
```sh
# ensure the gossip-entrypoint hostname resolves to container with IP 172.25.0.10
sol@host-alpha:~$ getent hosts gossip-entrypoint || grep -w gossip-entrypoint /etc/hosts

# In the validator logs you might see error: Genesis hash mismatch: expected DRip9gZY2gc1u8MhyED1MP2XkuwRjiyHw5bs1nDhfjk4 but downloaded genesis hash is 8Np1DCFV73CEyZc6wXQ9gcvQvrPuybDNRqNDgibpbvbH
# Ensure the gossip-entrypoint genesis hash matches the host-alpha validator genesis hash
sol@host-alpha:~$ solana -u http://172.25.0.10:8899 genesis-hash
sol@host-alpha:~$ solana -u http://gossip-entrypoint:8899 genesis-hash
sol@host-alpha:~$ agave-ledger-tool --ledger /mnt/ledger genesis-hash
sol@host-alpha:~$ ps aux | grep 'agave-validator' | grep -v grep
```


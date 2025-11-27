# Localnet tests

These shell-based checks are driven by [Bats](https://github.com/bats-core/bats-core).

## Install Bats

- macOS (Homebrew): `brew install bats-core`
- npm: `npm install -g bats`

## Run

From repo root:

```sh
bats solana-localnet/tests/localnet.bats
```

You can also run the helpers directly:

```sh
bash solana-localnet/tests/test-localnet.sh podman   # or docker
```

# sudo /lib/systemd/systemd # FIXME
solana-test-validator \
    --slots-per-epoch 750 \
    --limit-ledger-size 10000000 \
    --dynamic-port-range 8000-8030 \
    --rpc-port 8899 \
    --bind-address 0.0.0.0 \
    --gossip-host $(hostname -i | awk '{print $1}') \
    --gossip-port 8001 \
    --reset

# changes:
# see https://solana.stackexchange.com/questions/6654/my-hard-drive-is-full-when-running-solana-test-validator
# --limit-ledger-size: from 500000000 to 10000000

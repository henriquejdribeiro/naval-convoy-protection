# besu-l1 — Hyperledger Besu QBFT L1 (settlement layer)

Single-node Besu in **QBFT** (Byzantine-fault-tolerant PoA) mode — the convoy
stack's L1. Replaces the ephemeral geth+Prysm PoS devnet: one process,
persistent chaindata, modern EVM (PUSH0/MCOPY), instant BFT finality.

## Why Besu-QBFT
- **1 process** vs geth+Prysm's 3 (no beacon, no validator, no Engine API/JWT).
- **Persistent** — resumes its datadir on restart (no auto-wipe), so the deployed
  Starknet core + convoy contracts survive reboots.
- **Modern EVM** — `shanghaiTime:0` (PUSH0) + `cancunTime:0` (MCOPY) run the real
  StarkWare core.
- **Instant BFT finality** — `latest` is final (~2s blocks).

## Run
    docker compose up -d
    curl -s localhost:8545 -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'

RPC: `localhost:8545` (HTTP) / `8546` (WS). The convoy stack reaches it via
`host.docker.internal:8545` (see `docker-compose.l2.yml` + `infrastructure/l1-shim`).

## Regenerate genesis (only if qbftConfigFile.json changes)
    rm -rf networkFiles key
    docker run --rm -v "$PWD:/data" -w /data hyperledger/besu:26.7.1 \
      operator generate-blockchain-config \
      --config-file=/data/qbftConfigFile.json --to=/data/networkFiles --private-key-file-name=key
    cp networkFiles/keys/*/key ./key

## ⚠️ Dev-only keys
`key` (the QBFT validator private key) and the `qbftConfigFile.json` alloc
(anvil `0xf39F…`/`0x14dC…` + `0x123463a4…`) are **local-devnet keys, committed on
purpose for reproducibility**. Never use this chain or these keys for anything real.

## Notes
- Cancun on PoA needs the **EIP-4788** beacon-roots contract predeployed
  (`0x000F3df6…Beac02` in the alloc) or Besu errors every block.
- Besu-QBFT does **not** expose the `finalized` RPC tag; the l1-shim rewrites
  madara's `finalized` filter to `latest` (already final under QBFT).
# Geth keystores — dev keys for the 6 PoA validators + commander

**These are the well-known anvil/foundry test keys** (deterministic from the
test mnemonic `test test test test test test test test test test test junk`).
**Do not use any of these on a real network.** Each key has a fixed,
publicly-known private key — anyone can spend funds at these addresses on
mainnet.

## Mapping

| Anvil idx | Address                                   | Role in convoy            |
|-----------|-------------------------------------------|---------------------------|
| `[0]`     | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | Ship A — validator + initial deployer |
| `[1]`     | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | Ship B — validator + bravo lane relay |
| `[2]`     | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | Ship C — validator |
| `[3]`     | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | Ship D — validator (regular ship key) |
| `[4]`     | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | Ship E — validator |
| `[5]`     | `0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc` | Ship F — validator + alpha lane relay |
| `[7]`     | `0x14dC79964da2C08b23698B3D3cc7Ca32193d9955` | **Commander key** — D's separate signing key for `Registry.deploy` and `CommandLog.advance` (uses anvil[7], not anvil[6]) |

## Generating the keystore JSON files

Run this once before `docker compose up` to populate `keys/`. Requires `geth`:

```bash
cd infrastructure/geth/keys

# Anvil's first 7 private keys (Foundry's deterministic test mnemonic)
ANVIL_KEYS=(
    "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    "59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
    "5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
    "7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"
    "47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"
    "8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba"
    "4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356"
)
SHIP_LABELS=(A B C D E F D-commander)

for i in "${!ANVIL_KEYS[@]}"; do
    label="${SHIP_LABELS[$i]}"
    pk="${ANVIL_KEYS[$i]}"
    echo "${pk}" > /tmp/key-${label}.txt
    geth account import \
        --datadir /tmp/geth-${label} \
        --password ../password.txt \
        /tmp/key-${label}.txt
    cp /tmp/geth-${label}/keystore/UTC--* "${label}.json"
    rm -rf /tmp/geth-${label} /tmp/key-${label}.txt
done

ls -la
```

After this, you should have 7 files: `A.json`, `B.json`, …, `F.json`, `D-commander.json`.

## Why anvil keys?

For Phase 2 development the threat model is dev-host-only. Using anvil keys
means:
- Tests, scripts, and docs can hardcode addresses without secret management.
- The same keys work for both local Geth (this project) and any Foundry/Hardhat tooling.
- Anyone reading the repo can reproduce the chain exactly.

For Phase 4 (chaos / SITL) we generate fresh keys per deployment.

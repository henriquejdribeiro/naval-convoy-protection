# L1 contracts (Phase 2)

The four Solidity contracts that drive the convoy mission protocol on the
Geth Clique PoA chain. Implements Pattern B — D explicitly triggers the
advance, the Verifier does not auto-fire.

## Contracts

| Contract            | Purpose |
|---------------------|---------|
| `StarknetCoreStub`  | Madara settles into this — minimal stub of StarkWare's Starknet core. |
| `Registry`          | Mission specs (`MissionSpec`) + per-(mid, droneId) verdicts. `onlyCommander` on `deploy`, `onlyVerifier` on `setVerdict`. |
| `Verifier`          | GPS Statement Verifier pattern — registers facts after off-chain `cpu_air_verifier` succeeds. `onlyRelay` on `registerSafeProof`. |
| `CommandLog`        | Records `ConvoyAdvance`. `onlyCommander` + dual-SAFE precondition. |

## Setup

Requires Foundry (`forge`, `cast`). Install deps:

```bash
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install starkware-libs/cairo-lang --no-commit
```

(The `cairo-lang` install is for the `starkware/solidity/components/FactRegistry.sol` path mapping — currently we inline the FactRegistry pattern in `Verifier.sol` so this is forward-compat for switching to the upstream component.)

## Build

```bash
forge build
```

## Test (Phase 2 acceptance gate)

```bash
forge test --match-contract Phase2Acceptance -vv
```

Expected output: 9 passing tests covering the full `docs/specs/acceptance.md` Phase 2 scenario.

## Deploy to local Geth

After bringing up the 6-validator chain (`docker compose -f ../docker-compose.l1.yml up`):

```bash
export COMMANDER_ADDR=0x14dC79964da2C08b23698B3D3cc7Ca32193d9955  # anvil[6]
export ALPHA_RELAY_ADDR=0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc  # anvil[5] = ship F
export BRAVO_RELAY_ADDR=0x70997970C51812dc3A010C7d01b50e0d17dc79C8  # anvil[1] = ship B

forge script script/DeployL1.s.sol \
    --rpc-url http://127.0.0.1:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast
```

Output prints all four contract addresses + the wired commander / relay addresses. Save these for the orchestrator config in Phase 3.

### `advance(...)` — speed argument

`CommandLog.advance(alphaMid, betaMid, speed)` takes any `uint256` for the
`speed` field. The value is opaque to the protocol — it rides along inside
the `ConvoyAdvance` event for off-chain interpretation. The convention this
project uses is **`speed = 100`** (≈ "full ahead"), but any non-zero value
is accepted. The `docker-compose.l1.yml` deploy service exposes
`CONVOY_SPEED` (default `100`) for scripted demos.

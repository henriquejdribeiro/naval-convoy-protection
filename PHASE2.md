# Phase 2 — L1 mechanics (build instructions)

What's in this commit:
- 4 Solidity contracts (`contracts/src/`)
- Foundry profile + tests + deploy script (`contracts/`)
- 6-validator Geth Clique PoA chain config (`infrastructure/geth/`)
- `docker-compose.l1.yml` orchestrating all 6 ships + a Foundry deploy service

What "working" means: the steps below run end-to-end on a clean dev host
and `Phase2Acceptance` passes.

---

## Prerequisites

- Docker Desktop with Compose v2
- ~4 GB free RAM, 1 GB free disk
- (Optional, for running tests outside Docker) Foundry installed locally

---

## Step 1 — Generate the keystores

```bash
cd infrastructure/geth/keys
# Follow the script in README.md to import the 7 anvil keys (6 ship validators + 1 commander)
# This produces A.json, B.json, …, F.json, D-commander.json
```

Or, easier: use any existing Foundry / anvil keystore for the same anvil
private keys — the JSON format is interchangeable.

## Step 2 — Bring up the 6-validator chain

```bash
docker compose -f docker-compose.l1.yml up -d
```

Wait ~30 seconds for the Clique mesh to form. Verify:

```bash
# Block height should be increasing
curl -s http://localhost:8545 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Peer count from ship A — should be 5
curl -s http://localhost:8545 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

Expected: `peerCount = 0x5` once the mesh is established.

## Step 3 — Run the Phase 2 acceptance test suite

This deploys the contracts, runs all 9 acceptance tests, then broadcasts the
deploy to ship A's RPC (so the contracts are live for Phase 3 work):

```bash
docker compose -f docker-compose.l1.yml --profile deploy run --rm deploy-l1
```

Expected output:

```
Compiler run successful!

Running 9 tests for test/Phase2Acceptance.t.sol:Phase2AcceptanceTest
[PASS] test_01_commanderDeploysBothMissions()
[PASS] test_02_nonCommanderDeployReverts()
[PASS] test_03_alphaRelayRegistersSafeProof()
[PASS] test_04_bothLanesVerified_dualSafeReached()
[PASS] test_05_nonRelayCallerReverts()
[PASS] test_06_commanderFiresAdvance_emitsConvoyAdvance()
[PASS] test_07_nonCommanderAdvanceReverts()
[PASS] test_08_preDualSafeAdvanceReverts()
[PASS] test_09_thresholdViolationsRevert()

Test result: ok. 9 passed; 0 failed
...
StarknetCoreStub deployed at: 0x...
Registry         deployed at: 0x...
Verifier         deployed at: 0x...
CommandLog       deployed at: 0x...
```

Save the four addresses for the Phase 3 orchestrator config.

## Step 4 — Walk the protocol manually with `cast`

Drop this into a shell to walk the Phase 2 acceptance scenario from `acceptance.md`
against the deployed contracts:

```bash
# Replace these with the addresses from Step 3
REGISTRY=0x...
VERIFIER=0x...
COMMANDLOG=0x...

# D's commander key
COMMANDER_PK=0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e
ALPHA_RELAY_PK=0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba   # ship F
BRAVO_RELAY_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d   # ship B
RPC=http://127.0.0.1:8545

# 1. D deploys α-mission (mid=1, droneId=1)
cast send $REGISTRY \
    "deploy(uint256,(bytes32,uint16,uint16,uint64))" \
    1 "(0x0000...areahash,950,7000,360)" \
    --private-key $COMMANDER_PK --rpc-url $RPC

# 2. D deploys β-mission (mid=2, droneId=2)
cast send $REGISTRY \
    "deploy(uint256,(bytes32,uint16,uint16,uint64))" \
    2 "(0x0000...areahash,950,7000,360)" \
    --private-key $COMMANDER_PK --rpc-url $RPC

# 3. Ship F (alpha relay) registers a SAFE proof for (mid=1, droneId=1)
# (use the SafeProofInputs tuple shape per Verifier.sol)
# ...

# 4. Ship B (bravo relay) registers a SAFE proof for (mid=2, droneId=2)
# ...

# 5. D fires advance — only succeeds because both verdicts are SAFE
cast send $COMMANDLOG \
    "advance(uint256,uint256,uint256)" 1 2 100 \
    --private-key $COMMANDER_PK --rpc-url $RPC
```

If step 5 emits a `ConvoyAdvance` event in the receipt, **Phase 2 is working
end-to-end**.

---

## Troubleshooting

**Geth nodes don't peer** — Check `--bootnodes` resolves to the right enode.
For dev, every other ship bootstraps from `enode://ship-a:30303`. If ship-a's
container name resolves but enode doesn't connect, verify Geth picked up the
P2P port from the env var.

**`forge install` fails** — The `deploy-l1` service runs `forge install` on
first invocation; if the container has no internet (corporate network),
mount your local `~/.foundry` cache instead.

**Tests fail with `Verifier: onlyRelay`** — Make sure `ALPHA_RELAY_ADDR` and
`BRAVO_RELAY_ADDR` env vars match the actual ship F / ship B addresses (from
the genesis allocation).

---

## What's next (Phase 3)

Phase 3 = drone telemetry → Cairo proof → SAFE fact on L1.

Reuses everything in this commit:
- The 4 deployed L1 contracts
- The 6-validator chain
- Foundry tooling

Adds:
- `convoy_protocol.cairo` (Cairo 1, on Madara) — `submit_telemetry`, `submit_sweep_commitment`
- `safe_area_verify.cairo` (Cairo 0, for Stone) — provable SAFE_AREA enforcement
- Two L2 stacks (Madara α + β) with their own Pathfinder + SNOS + Stone
- Orchestrator daemon — runs cpu_air_verifier locally, calls `Verifier.registerSafeProof`
- `docker-compose.l2.yml` extending this file

When Phase 3 lands, the same `Verifier.registerSafeProof` calls in this Phase 2
will be made by the orchestrator with **real** STARK-derived facts instead of
the hand-crafted ones used in tests.

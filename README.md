# Naval Convoy Protection

## Provenance

This project's architecture derives from the author's Master's thesis at Instituto Superior Técnico (2026):

> **Modular blockchain architectures applied to drone swarms with low computational resources**
> *Execution of smart contracts and analysis of consensus time*

The repository is a standalone mission archetype, with its own contracts, container topology, and visualisation.

## What this is

A verifiable naval-drone mission-compliance system on a modular blockchain stack. Two 5-drone swarms (alpha, bravo) sweep an assigned zone; each drone proves it stayed inside its strip and met coverage/detection/time thresholds. The verdict is anchored on a settlement L1.

- **L1 — Hyperledger Besu QBFT.** 6 validators (ships A–F), BFT finality. The settlement layer.
- **Real StarkWare Starknet cores.** One genuine `Starknet.sol` messaging core **per swarm**, deployed on L1 at bring-up by the [madara-bootstrapper](https://github.com/madara-alliance/madara) (`bootstrapper-v2`). Not a stub — the real proxied core, initialized with a per-chain config hash.
- **L2 — two Madara Starknet appchains** (`convoy_alpha`, `convoy_bravo`), v0.9.1. Each is a `--sequencer` with L1 sync enabled, watching **its own** core, plus 4 `--full` follower nodes (one per drone).
- **`convoy_protocol` (Cairo).** Per-drone `submit_telemetry` + the `safe_area` compliance predicate. When a swarm's 5 drones all pass, it emits `MissionSafe`.
- **The L1→L2 bridge (trustless, working).** A commander opens a mission on L1 via `Registry.deploy`, which sends a real `LogMessageToL2` through that swarm's core. Each Madara **auto-consumes** it and runs the `#[l1_handler] open_mission` on L2. No dev fallback — the mission only opens if the message really crossed the bridge, authorised by the L1 commander.

`Registry` holds both cores and dispatches each mission to the right one (`_coreFor(mission_id)`), so alpha's sequencer only ever sees alpha's messages and bravo's only bravo's — clean, no cross-chain handlers.

## Project status

In-progress thesis project. The L1→L2 direction is fully wired and trustless for both swarms, and the L2→L1 verdict is settled trustlessly — each drone's `safe_area` compliance proof is verified on L1 by the **genuine StarkWare STARK verifier** before the convoy `Verifier` records the verdict.

| Component | Status |
|---|---|
| L1 — Hyperledger Besu QBFT, 6 validators | ✅ Working |
| Real StarkWare Starknet cores (1 per swarm, via madara-bootstrapper) | ✅ Deployed on L1 at bring-up |
| L1 convoy contracts (Registry, Verifier, CommandLog) | ✅ Deploy + wired |
| L2 — Madara α + β (v0.9.1), 1 sequencer + 4 followers each | ✅ Both healthy |
| `convoy_protocol` on each L2 | ✅ Declared + deployed |
| 5 drone accounts per swarm | ✅ Deployed + auto-funded |
| **L1→L2 `open_mission` auto-consume (both swarms)** | ✅ **Trustless via the real cores** |
| Per-drone `submit_telemetry` | ✅ Signed by each drone's own key |
| Real StarkWare STARK verifier on L1 (`GpsStatementVerifier_2023_9`) | ✅ **Deployed on Besu, byte-identical to mainnet** |
| Off-chain prover pipeline (Cairo → Stone → EVM proof) | ✅ Working |
| **L2→L1 verdict — `safe_area` proof verified trustlessly on L1** | ✅ **`Verifier.registerSafeProof`, gated on `isValid(factHash)`** |
| Web visualizer | ✅ Static animation |

## Getting started

End-to-end from a fresh clone to both missions live on L2 via the real bridge, in one terminal session.

**Prerequisites** — Docker + Docker Compose v2, git, Python 3.10+, ~16 GB free RAM, and internet on first run (the bootstrapper and Madara images pull from ghcr). Host ports that must be free: `8545`/`8546` (Besu L1 RPC/WS), `19944`–`19948` (Madara alpha + 4 followers), `29944`–`29948` (Madara bravo + 4 followers), `9545`/`9645` (leader pathfinders), `8888` (Dozzle).

### 1. Clone

```bash
git clone --recurse-submodules https://github.com/henriquejdribeiro/naval-convoy-protection.git
cd naval-convoy-protection
```

### 2. Build the cairo-builder image (first time only)

Bundles scarb, starkli, and the `starknet-sierra-compile` / `compute-casm-hash` helpers — all Cairo/Starknet tooling runs inside it, so nothing Cairo-related is installed on the host.

```bash
docker build -t convoy-cairo-builder infrastructure/cairo-builder/
```

### 3. Bring up the stack

```bash
./scripts/up.sh            # add --no-debugger to skip the Dozzle log viewer
```

One idempotent command. It:

1. starts the **6-validator Besu QBFT** L1,
2. runs the **madara-bootstrapper twice** — one real Starknet core per swarm (alpha via `ALPHA_RELAY`, bravo via `BRAVO_RELAY`; configs `bootstrap/config.json` + `bootstrap/config-bravo.json`),
3. deploys the L1 convoy contracts (`Registry` bound to both cores, `Verifier`, `CommandLog`),
4. **seeds** each sequencer's genesis (`--devnet` one-shot) then brings the L2 up as **`--sequencer` with L1 sync** — this two-phase boot is required, because `--devnet` creates the predeployed accounts but disables L1 sync, while `--sequencer` runs the L1→L2 messaging worker,
5. starts the 4 `--full` follower drones per swarm + the leader pathfinders + Dozzle (<http://localhost:8888>).

### 4. Compile + deploy the L2 protocol

```bash
# recompile only if you've changed the Cairo source; artifacts are committed
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd)/cairo/convoy_protocol:/work" -w /work convoy-cairo-builder scarb build

./scripts/deploy-l2.sh --swarm both                 # declare + deploy convoy_protocol on both Madaras
./scripts/generate-drone-accounts.sh --swarm both   # 10 drone accounts, auto-funded STRK + ETH
./scripts/register-missions.sh --swarm both          # commander opens both missions → real L1→L2 bridge
```

`register-missions.sh` is the whole point: `Registry.deploy(mission_id, …)` sends a real `LogMessageToL2` through that swarm's core, and each sequencer's L1 sync **auto-consumes** it (after a 10-block finality wait) and runs `open_mission` on L2. No `open-missions.sh` — the mission opens *only* because the L1 message crossed the bridge.

Confirm it landed:

```bash
sleep 90   # 10-block finality + processing
docker logs convoy-madara-alpha 2>&1 | grep -iE "Processing L1→L2|nonce=" | tail -3
docker logs convoy-madara-bravo 2>&1 | grep -iE "Processing L1→L2|nonce=" | tail -3
```

Both should show `Processing L1→L2 message: … nonce=0`. To read the anchored spec on L2 (returns the 12-felt `MissionSpec`, reverts if not deployed):

```bash
CONV=$(grep CONVOY_PROTOCOL_ADDR_ALPHA .tmp-l2/convoy_l2.env | cut -d= -f2)
MSYS_NO_PATHCONV=1 docker run --rm -i --network convoy-l1 \
  convoy-cairo-builder:latest \
  starkli call "$CONV" get_mission 1 --rpc http://convoy-madara-alpha:9944/rpc/v0.8.1
```

### 5. Run a mission

Generate per-drone telemetry, then fire all 10 submissions:

```bash
python3 scripts/generate-mission.py --scenario both-safe --output-dir .tmp-l2/missions/
for swarm in alpha bravo; do
  for did in 1 2 3 4 5; do
    f=.tmp-l2/missions/both-safe/${swarm}_${did}.json
    [ -f "$f" ] && ./scripts/submit-telemetry.sh "$swarm" "$did" "$f"
  done
done
```

Scenarios (see [`scripts/generate-mission.py`](scripts/generate-mission.py)): `both-safe`, `both-unsafe`, `mixed`, `alpha-dropout-vanish`, `alpha-dropout-midflight`, `dual-dropout`. Dropout scenarios omit the affected drone's file; the loop skips missing files, modelling real loss-of-comms.

When the 5th SAFE submission lands in a swarm, `convoy_protocol` emits `MissionSafe` and fires `send_message_to_l1_syscall` with payload `[mission_id, n_drones]`.

> **L2→L1 verdict.** The verdict is settled on L1 by verifying a `safe_area` STARK proof on the real StarkWare verifier — see [§6, Verify a compliance proof on L1](#6-verify-a-compliance-proof-on-l1).

### 6. Verify a compliance proof on L1

`up.sh` deploys the **genuine StarkWare STARK verifier** on Besu — the real
`GpsStatementVerifier_2023_9` (7-builtin `starknet`), byte-identical to Ethereum
mainnet, from vendored bytecode under
[`contracts/starkware-verifier/`](contracts/starkware-verifier/) — and points the
convoy `Verifier` at it. A drone's `safe_area` proof is then verified trustlessly
on L1, and the verdict recorded only if the STARK proof backs it.

Build the submitter and run it against the bundled example proof:

```bash
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd):/work" -w /work/infrastructure/submitter \
  rust:latest cargo build --release

set -a; source deployments/local.env; source .tmp-l1/stark-verifier.env; set +a
MSYS_NO_PATHCONV=1 docker run --rm --network convoy-l1 -v "$(pwd):/work" -w /work \
  -e URL=http://ship-a:8545 \
  -e PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
  -e ANNOTATED_PROOF=/work/docs/examples/proof/evm_proof.json \
  -e FACT_TOPOLOGIES=/work/docs/examples/proof/fact_topologies.json \
  -e SAFE_AREA_VERIFY_JSON=/work/docs/examples/proof/safe_area_verify.json \
  -e GPS_STATEMENT_VERIFIER_ADDR=$GPS_STATEMENT_VERIFIER_ADDR \
  -e CONVOY_VERIFIER_ADDR=$CONVOY_VERIFIER_ADDR \
  -e MERKLE_STATEMENT_CONTRACT_ADDR=$MERKLE_STATEMENT_CONTRACT_ADDR \
  -e FRI_STATEMENT_CONTRACT_ADDR=$FRI_STATEMENT_CONTRACT_ADDR \
  -e MEMORY_PAGE_FACT_REGISTRY_ADDR=$MEMORY_PAGE_FACT_REGISTRY_ADDR \
  rust:latest \
  /work/infrastructure/submitter/target/release/convoy-submitter
```

Expected output — the four StarkWare phases, then the convoy verdict:

```
Phase 1: trace Merkle commits    ✓ Trace 0/1/2
Phase 2: FRI commits             ✓ FRI 0..7
Phase 3: memory pages            ✓ memory page 0
Phase 4a: verifyProofAndRegister ✓   ← STARK proof verified on L1 by the real StarkWare verifier
Phase 4b: registerSafeProof      ✓   ← verdict recorded (mission 2, drone 3 → SAFE)
```

**Phase 4a** is the trustless verification: the real StarkWare `GpsStatementVerifier`
re-checks every Merkle/FRI/OODS constraint and registers the proof's fact on-chain.
**Phase 4b** gates the convoy verdict on that fact — a SAFE result is unforgeable, since
no relay can register it without a STARK proof the verifier accepts. (The bravo relay key
is used because the example proof is for mission 2; alpha proofs use the alpha relay.)

To generate your own proof from live telemetry instead of the fixture, see the prover-api
under [`infrastructure/prover-api/`](infrastructure/prover-api/).

### 7. Teardown

```bash
docker compose -f docker-compose.l1.yml -f docker-compose.l2.yml \
    --profile l2 --profile seed --profile proving --profile proving-direct --profile deploy \
    down -v --remove-orphans
docker compose -f debugger/docker-compose.yml down -v --remove-orphans
```

## Drone telemetry — what `submit-telemetry.sh` does

Takes a swarm, a drone id (1..5), and a JSON file with the four per-cell arrays (`cells_x`, `cells_y`, `cells_p_contact`, `cells_ts`). It loads the matching drone keystore, serialises the arrays into starkli calldata, and fires `submit_telemetry` **signed by the drone's own key** — so `get_caller_address()` inside the contract resolves to the drone's registered account, satisfying the per-drone authentication check.

For hand-written UNSAFE scenarios, copy [`docs/examples/alpha_drone_3_cells.json`](docs/examples/alpha_drone_3_cells.json) and modify the arrays:

- Drop coverage below 95% → `FAIL_COVERAGE`
- Push one `p_contact` to ≥ 7000 → `FAIL_DETECTION`
- Push one `ts` beyond `ts_start + 360` → `FAIL_TIME`
- Move one `(x, y)` outside the drone's strip → `FAIL_STRIP`

## Ports

| URL | What |
|---|---|
| <http://localhost:8545> | Besu L1 JSON-RPC (ship A) |
| <http://localhost:19944> / <http://localhost:29944> | Madara alpha / bravo JSON-RPC |
| <http://localhost:8888> | Dozzle log viewer (grouped by drone) |
| <http://localhost:8000> | Web visualiser (`python -m http.server` in `webapp/`) |

## License

Apache-2.0 — see `LICENSE`.

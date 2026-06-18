# Naval Convoy Protection

Verifiable mission compliance for naval drone escort operations, built on a per-swarm zk-rollup architecture.

A six-ship naval convoy holds position while **two five-drone swarms** independently sweep the frontal sectors ahead. Each swarm runs its own Layer-2 chain; the drones submit telemetry on L2; the L2 contract evaluates four `SAFE_AREA` predicates **in-contract**; when all five drones in a swarm pass, the L2 emits an L1 message; once **both swarms** emit their SAFE message on L1, the convoy commander (ship D) is permitted to issue the advance order.

## The two swarms

| Swarm | Mission ID | Frontal sector | L2 chain    | Drones                   | Strip layout |
|-------|-----------:|----------------|-------------|--------------------------|--------------|
| **Alpha** | `1`    | Left           | `L2-Alpha`  | drone 1..5 of mission 1 | zone 15×8, 5 strips of width 3 |
| **Bravo** | `2`    | Right corridor | `L2-Bravo`  | drone 1..5 of mission 2 | zone 20×8, 5 strips of width 4 |

Each swarm's 5 drones each cover a **vertical strip** of the swarm's zone. Drone *i* sweeps strip *i*; the strip bounds are derived deterministically by the L2 contract from the mission spec (`x_start = zone_x + (i-1)·strip_width`, etc.) so the drone-side software can't claim coverage of someone else's strip.

## The four `SAFE_AREA` predicates

The L2 `convoy_protocol` contract checks each drone's raw telemetry against four conditions:

```
① Strip bounds:   every cell ∈ [strip.x_start, strip.x_end) × [strip.y_start, strip.y_end)
② Detection:     every cell.p_contact < mission.p_min               (basis points)
③ Time window:   max(cell.ts) − ts_start ≤ mission.time_window      (seconds)
④ Coverage:      n_cells × 1000 / strip_total_cells ≥ coverage_min  (permille)
```

If all four hold → verdict = `SAFE`. Otherwise → `UNSAFE`, with the failing predicate recorded on chain (`FAIL_STRIP`, `FAIL_DETECTION`, `FAIL_TIME`, `FAIL_COVERAGE`).

## Convoy formation

```
                A (front)
              ╱   │   ╲
             F    │    B
             │   ▓▓    │     ← three high-value ships (▓) protected in the centre
             E   ▓▓    C
              ╲   │   ╱
                D (rear, commander)
```

All six ships (A, B, C, D, E, F) are validators of the same L1 Clique-PoA chain. Ship D additionally holds the **commander key** — distinct from D's validator key — which is the only signer accepted by both `Registry.deploy()` (mission deployment) and `CommandLog.advance()` (the convoy-advance order). The commander key is immutable; the design fails closed by intent (no rotation path).

## End-to-end data flow

```
[Per drone, off-chain]            [L2 — Madara α or β]                     [L1 — Geth Clique PoA]
                                                                            
Drone keystore signs              convoy_protocol.submit_telemetry()        Registry.deploy(spec)
   invoke txs                          ├ Caller check:                          (mission registered)
        │                              │   get_caller_address()
        │  submit_telemetry(           │   == drone_addr[(mid, did)]?
        ▼  mid, did, cells_x[],        │
                cells_y[],             ├ Run 4 SAFE_AREA predicates             ┌──────────────────┐
                p_contact[],           │   on the raw cells                     │  StarknetCoreStub│
                cells_ts[])            │                                        │  (L1 ↔ L2 bridge │
                                       ├ Store verdict + n_cells                │   message queue) │
                                       │                                        └────────┬─────────┘
                                       └ if safe_count == 5:                             │
                                              send_message_to_l1_syscall ───────────────►│
                                              (L1 verifier addr, payload)               │
                                                                                          │
                                                                                          ▼
                                                                            Verifier.consumeL2Message()
                                                                                          │
                                                                                          ├─► Registry.setVerdict
                                                                                          │   (per-drone, when proof
                                                                                          │    pipeline lands per-drone
                                                                                          │    messages — future)
                                                                                          │
                                                                                          └─► Registry.setMissionSafe
                                                                                              (per-mission aggregate)
                                                                                          │
                                                                                          ▼
                                                              Commander (ship D) waits for
                                                              both missionSafe[1] && missionSafe[2]
                                                              then signs:
                                                                  CommandLog.advance(1, 2, speed)
                                                                       │
                                                                       └─► appends AdvanceRecord
                                                                           emits ConvoyAdvance
```

**Telemetry is public on L2** (chosen explicitly — see the architecture note in `cairo/convoy_protocol/src/lib.cairo`). The predicate check runs against the raw cells in the same L2 transaction that submitted them. The SAFE/UNSAFE verdict + which predicate failed are stored on L2; only the aggregate "all 5 SAFE → trigger L1 message" crosses the L2→L1 boundary.

## Where each layer's contracts live

### L1 (shared by both swarms)

| Contract | Source | What it does |
|---|---|---|
| `StarknetCoreStub` | [contracts/src/StarknetCoreStub.sol](contracts/src/StarknetCoreStub.sol) | Minimal L1↔L2 message bridge — same interface as StarkWare's real `StarknetCore`, gutted of cryptographic checks for dev use |
| `Registry` | [contracts/src/Registry.sol](contracts/src/Registry.sol) | Stores per-mission specs (zone geometry, thresholds), per-drone verdicts, per-mission `missionSafe` aggregate |
| `Verifier` | [contracts/src/Verifier.sol](contracts/src/Verifier.sol) | Application-layer STARK-proof checker + Registry bookkeeping orchestrator |
| `CommandLog` | [contracts/src/CommandLog.sol](contracts/src/CommandLog.sol) | Append-only log of convoy-advance orders; reverts unless both missions are SAFE and caller is commander |
| StarkWare verifier stack | [contracts/lib/starkware-mainnet/](contracts/lib/starkware-mainnet/) | 17 vendored mainnet-source contracts: `GpsStatementVerifier`, `CpuFrilessVerifier`, `MerkleStatementContract`, `FriStatementContract`, `MemoryPageFactRegistry`, `CpuOods`, `CairoBootloaderProgram`, + 10 periodic-column constant contracts |

### L2 (one deployment per swarm, on different Madara chains)

| Contract | Source | Per-swarm |
|---|---|---|
| `convoy_protocol` (Cairo 1) | [cairo/convoy_protocol/src/lib.cairo](cairo/convoy_protocol/src/lib.cairo) | Same source, declared and deployed independently on each Madara — different storage state, different address |
| 5× drone OZ accounts | Madara devnet's pre-declared OZ class | One ContractAddress per drone, registered in `convoy_protocol.open_mission(spec, drone_addresses)` |
| Predeclared on Madara | UDC, ETH/STRK ERC20, OZ Account class, 10 pre-funded accounts | Standard Madara devnet genesis |

### Off-chain (out of the proof-of-record path)

| Tool | Source | What it does |
|---|---|---|
| `convoy-cairo-builder` Docker image | [infrastructure/cairo-builder/](infrastructure/cairo-builder/) | scarb 2.11.4, starkli 0.4.1, `starknet-sierra-compile` v2.12.3, `compute-casm-hash` (custom) — together bridge the version gap between scarb's CASM emit and Madara's CASM hash function |
| `scripts/deploy-l2.sh` | [scripts/deploy-l2.sh](scripts/deploy-l2.sh) | Declares + deploys `convoy_protocol` to both Madaras |
| `scripts/generate-drone-accounts.sh` | [scripts/generate-drone-accounts.sh](scripts/generate-drone-accounts.sh) | Generates 5 fresh keypairs per swarm, deploys OZ account contracts on each Madara via UDC signed by account #1 |

## Per-swarm topology — what runs in Docker

The "blue region" is duplicated per swarm; only the red L1 layer is shared.

```
┌─────────────────────────────────────┐   ┌─────────────────────────────────────┐
│  Alpha lane                          │   │  Bravo lane                          │
│  ─────────────                       │   │  ─────────────                       │
│  madara-alpha    (chain_id=convoy_α) │   │  madara-bravo   (chain_id=convoy_β)  │
│  pathfinder-alpha                    │   │  pathfinder-bravo                    │
│  orchestrator-alpha   (port 13000)   │   │  orchestrator-bravo  (port 13001)    │
│  prover-api-alpha                    │   │  prover-api-bravo                    │
│  snos-alpha                          │   │  snos-bravo                          │
└────────────────┬────────────────────┘   └────────────────┬────────────────────┘
                 │                                          │
                 │     ┌────────────────────────────────────┐
                 └─────┤      L1 — shared layer             ├─────┘
                       │  ship-{a,b,c,d,e,f} (Geth Clique)  │
                       │  StarknetCoreStub                  │
                       │  Registry, Verifier, CommandLog    │
                       │  StarkWare 17-contract verifier    │
                       │  stack                              │
                       │  mongo + localstack (shared infra) │
                       └────────────────────────────────────┘
```

Per-swarm isolation:
- Different `chain_id` (`convoy_alpha` vs `convoy_bravo`) — proofs of one swarm's blocks can't be replayed on the other
- Different signer key on each orchestrator (`ALPHA_RELAY = anvil[5]` / `BRAVO_RELAY = anvil[1]`)
- Different MongoDB database names (`orchestrator_alpha` / `orchestrator_bravo`) inside the shared mongo
- Different SQS queue prefixes (`mo_alpha_*` / `mo_bravo_*`) inside the shared localstack

A compromise of one swarm's sequencer or orchestrator can't tamper with the other swarm's verdict.

## Project status

This is an in-progress thesis project. The architecture diagram above shows the **target state**; not every box is wired end-to-end yet.

| Component | Status |
|---|---|
| L1 chain (6 ships, Clique PoA, mesh) | ✅ Working |
| L1 contracts (StarknetCoreStub, Registry, Verifier, CommandLog) | ✅ Compile + deploy |
| StarkWare verifier stack on L1 | ✅ Deploys (note: deploy-script address-prediction quirk under audit) |
| L2 chains (Madara α + β, v0.9.1) | ✅ Both come up healthy |
| `convoy_protocol` contract on each L2 | ✅ Declared + deployed |
| 5 fresh OZ drone accounts per swarm | ✅ Deployed via UDC signed by account #1 |
| Per-drone `submit_telemetry` invokes | ⚠️ Drones can sign; mission-open path (L1→L2 `open_mission`) not yet wired |
| L1 `Verifier.sol` rewrite for L2 messages | ⏳ Pending |
| `generate-mission.py` rewrite for invoke calldata | ⏳ Pending |
| Mission scenario runs (`run-scenario.sh`) | ⏳ Will follow once above two land |
| Off-chain prover pipeline (SNOS → Stone → L1) | ⏳ Phase 3.a shortcut deprecated; per-block L2 proof flow needs implementing |
| Web visualizer | ✅ Static animation (not a live dashboard) |

## Bring-up

```bash
# 1. L1 chain
docker compose -f docker-compose.l1.yml up -d

# 2. L1 contracts (StarknetCoreStub, Registry, Verifier, CommandLog)
docker compose -f docker-compose.l1.yml --profile deploy run --rm deploy-l1

# 3. L2 sequencers + indexers (both swarms)
docker compose -f docker-compose.l1.yml -f docker-compose.l2.yml --profile l2 \
    up -d madara-alpha madara-bravo pathfinder-alpha pathfinder-bravo

# 4. Compile + deploy convoy_protocol on both Madaras
docker build -t convoy-cairo-builder infrastructure/cairo-builder/      # first time only
docker run --rm -v "$(pwd)/cairo/convoy_protocol:/work" -w /work convoy-cairo-builder scarb build
./scripts/deploy-l2.sh

# 5. Generate + deploy 5 drone OZ accounts per swarm
./scripts/generate-drone-accounts.sh
```

Each step writes its outputs into either `deployments/` (L1) or `.tmp-l2/` (L2). The deploy log files name every deployed address.

## Cloning the repo

The StarkWare evm-verifier source is vendored directly under [`contracts/lib/starkware-mainnet/`](contracts/lib/starkware-mainnet/) (with the architectural divergence documented in [`PATCH.md`](contracts/lib/starkware-mainnet/PATCH.md)). The zksecurity stark-evm-adapter is vendored under [`vendor/stark-evm-adapter/`](vendor/stark-evm-adapter/).

```bash
git clone https://github.com/henriquejdribeiro/naval-convoy-protection.git
```

No submodules — the vendored trees are committed directly so the cryptographic stack stays bit-reproducible without dependence on third-party hosting.

## Ports

| URL | What |
|---|---|
| <http://localhost:8000> | Web visualiser (`python -m http.server` in `webapp/`) |

## Technology stack

| Layer | Component | Pinned version |
|---|---|---|
| L1 chain | Geth (Clique PoA, 6 validators) | `ethereum/client-go:v1.10.17` |
| L1 contracts | Solidity + Foundry | `^0.8.20` (convoy), `^0.6.12` (vendored StarkWare) |
| L2 sequencer | Madara | `v0.9.1` (cairo-lang-sierra-to-casm 2.12.3) |
| L2 indexer | Pathfinder | `v0.21.3` |
| Cairo contract | Cairo 1 (Sierra 1.7.0) | scarb 2.11.4 |
| L2 tooling | starkli + custom `starknet-sierra-compile` + `compute-casm-hash` | 0.4.1 + cairo-lang 2.12.3 |
| Off-chain prover (when wired) | Stone (Atlantic mock) | via `ghcr.io/madara-alliance/orchestrator:nightly` |
| Visualisation | Vanilla JS + SVG (no framework) | — |

## License

Apache-2.0 — see `LICENSE`.

## Provenance

This project's architecture derives from the author's Master's thesis at Instituto Superior Técnico (2026):

> **Modular blockchain architectures applied to drone swarms with low computational resources**
> *Execution of smart contracts and analysis of consensus time*

The repository is a standalone mission archetype, with its own contracts, container topology, and visualisation.

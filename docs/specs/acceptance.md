# Acceptance criteria — per phase

> Each phase has **one concrete scenario** with a measurable pass/fail.
> If the scenario passes end-to-end, the phase is done. The bar mirrors
> what `verifiable_grid` already proves out (mission registration → STARK
> proof → on-chain fact → event-driven UI), adapted to the convoy mission.

## Phase 1 — Visualisation-first ✅

**State:** completed (this is what you're looking at now).

**Pass conditions** (verifiable on the live site):
- [x] Mission brief renders with thresholds, transparency-vs-privacy block, and SAFE_AREA criterion.
- [x] Interactive simulation plays through all 68 frames without console errors.
- [x] Architecture diagram renders 8 Docker containers + 3 HVUs, supports drag-pan / wheel-zoom / click-to-inspect.
- [x] Code-components and References sections link to GitHub.
- [x] No backend, no Docker — opens by serving the `webapp/` folder over HTTP.

## Phase 2 — L1 mechanics

**Goal:** prove the L1 settlement layer works end-to-end with the new contracts.

**Pass scenario:**

```
1. docker compose up geth-clique             # 6-validator Clique chain comes up
2. forge script DeployL1.s.sol               # deploys Verifier + Registry + CommandLog
3. cast send Registry "deploy(uint256,...)"  # from D's commander key
   → MissionDeployed(EX-010) event observed in eth_getLogs
4. cast send Registry "deploy(...)"          # from any other ship's key
   → tx REVERTS (onlyOwner enforced)
5. cast send Verifier "registerSafeProof(...)" with a HARDCODED valid fact for EX-010
   → MissionVerified(EX-010, …) event observed
6. cast send Verifier "registerSafeProof(...)" with HARDCODED valid fact for EX-011
   → MissionVerified(EX-011, …) event observed
   → AND in the SAME tx: ConvoyAdvance(firedBy=verifier) event observed (auto-fire)
```

**Pass criteria** (every line measurable, all must hold):
- [ ] All 6 ship containers come up with `peerCount == 5` (Clique mesh formed).
- [ ] First Clique block is sealed within 10 s of chain start.
- [ ] Step 3 succeeds; step 4 reverts with `Ownable: caller is not the owner`.
- [ ] Steps 5 + 6 produce exactly **3 events on L1** (2 × `MissionVerified`, 1 × `ConvoyAdvance`).
- [ ] `ConvoyAdvance.firedBy == address(Verifier)` (the auto-fire path, not D).
- [ ] Total time from step 5 → step 6's atomic advance event ≤ 5 s (one block).
- [ ] If only **one** mission has registered, no `ConvoyAdvance` fires (the dual-SAFE check holds).

**Out of scope for Phase 2:** no real STARK proof — the fact in steps 5–6 is hand-crafted (programHash + outputHash hard-coded). Real proofs come in Phase 3.

## Phase 3 — L2 + drones + real proofs

**Goal:** the L1 fact submitted in Phase 2 step 5 is now produced by an actual end-to-end run of the prover stack against simulated drone telemetry.

**Pass scenario:**

```
1. docker compose --profile proving up
2. POST telemetry to L2-Alpha for 5 simulated drones; they sweep a 20×20 cell area
3. Wait until convoy_protocol.cairo on L2-A emits SweepCommitment(EX-010, …)
4. Orchestrator polls Pathfinder, picks up the L2 block
5. Orchestrator runs SNOS → Stone → stark_evm_adapter
6. Orchestrator submits registerSafeProof to L1 via Ship F's RPC endpoint
7. Repeat steps 2–6 for L2-Bravo and EX-011 via Ship B's endpoint
8. Both MissionVerified events land; ConvoyAdvance fires atomically with the second
```

**Pass criteria:**
- [ ] STARK proof size ≤ 1 MB (the verifiable_grid baseline is ~677 KB; we expect a similar order).
- [ ] Total time from "telemetry submitted" to "MissionVerified on L1" ≤ 4 minutes per mission. (Stone proving on a 16 GB host is the bottleneck — see `verifiable_grid` benchmarks.)
- [ ] When run with **deliberately bad telemetry** (coverage = 80 %, below 95 % threshold), the Cairo 0 program aborts inside `check_coverage` and the orchestrator never produces a fact. Nothing lands on L1. Verified by `eth_getLogs` showing no `MissionVerified`.
- [ ] When run with **good telemetry**, the L1 fact's `coveragePermille ≥ 950`, `maxContact < 7000`, `elapsedSeconds ≤ 360`. Verified by reading the `proofs[]` array via `eth_call`.
- [ ] If Ship F's RPC is unreachable, orchestrator falls over to Ship A within 30 s and the mission still completes (relay-redundancy test).

### Phase 3 deliverable: `mission-replay.json` — the recorded full-pipeline capture

The capstone artefact for Phase 3 (and the file the webapp's simulation will eventually replay in place of its hand-authored 68 frames) is **a single timestamped JSON log of one complete successful run**, captured from `docker compose up` through to convoy advance.

**Required entries (each with `t_ms` since `compose up`):**

```
1.  build:start, build:end                            (per service: geth, madara-α, madara-β, pathfinder-α, pathfinder-β, snos-α, snos-β, stone-α, stone-β, orchestrator-α, orchestrator-β)
2.  container:up                                      (per service)
3.  geth:genesis-loaded, geth:first-block-sealed
4.  registry:deploy(EX-010)  — tx_hash, block, gas
5.  registry:deploy(EX-011)  — tx_hash, block, gas
6.  L2-α:telemetry-tx(cell_id, drone_id)              (one entry per cell, ×N cells)
7.  L2-β:telemetry-tx(...)                             (same)
8.  L2-α:sweep-commitment(EX-010, commitment, n_cells)
9.  L2-β:sweep-commitment(EX-011, ...)
10. pathfinder-α:block-synced(block_number)
11. orch-α:picked-up-block(block_number)
12. snos-α:pie-generated(elapsed_ms, pie_size_bytes)
13. stone-α:proof-generated(elapsed_ms, proof_size_bytes, n_steps)
14. orch-α:adapter-ran(elapsed_ms)
15. L1:registerSafeProof(EX-010, relay=F, tx_hash, gas, block)
16. L1:MissionVerified(EX-010, …)                     event log
17. (steps 10–16 repeat for L2-β and EX-011)
18. L1:MissionVerified(EX-011, …)                     event log — SAME TX as ConvoyAdvance
19. L1:ConvoyAdvance(firedBy=verifier)                event log
20. radio:F→L2-α(advance)                             timestamp only
21. radio:B→L2-β(advance)                             timestamp only
22. radio:D→HVU-{1,2,3}(advance)                      timestamp only
23. mission:complete                                  end-of-run marker
```

**Pass criteria for the deliverable:**
- [ ] `mission-replay.json` is committed to the repo (probably under `webapp/data/`).
- [ ] Every entry has a monotonic `t_ms` field; gaps reflect real wall-clock latency.
- [ ] Total span (entry 1 → entry 23) ≤ 8 minutes for a clean run on a 16 GB dev host.
- [ ] The webapp's simulation, when pointed at this file, renders the run frame-by-frame with the recorded timings — replacing `convoy-sim.js`'s hand-authored 68-frame script.
- [ ] A thesis-defence audience can watch the JSON play back and see, at the right wall-clock moments: container builds, L1 deploys, drone telemetry, prover progress (with proof size + step count), on-chain verification, the atomic auto-fire of advance, and the final radio relays.

This is the artefact that **proves the architecture works end-to-end**. Until this file exists and the simulation is driven by it, "simulation = real run" is aspirational; once it exists, the simulation panel becomes a faithful replay of operational truth.

## Phase 4 — Polish (SITL + chaos + live bridge)

**Goal:** drones are no longer simulated by a `curl` loop — they're ArduPilot SITL instances flying real flight-controller code, and the radio links between L2 ↔ ship ↔ L1 have realistic latency / jitter / loss.

**Pass scenario:**

```
1. Start the Phase 3 stack PLUS:
   - 5 ArduPilot SITL containers per L2 swarm (10 SITL instances total)
   - tc/netem profile applied to the docker network: 100 ms latency,
     20 ms jitter, 5 % packet loss between L2 and ships
2. SITL drones fly the prescribed sweep pattern under simulated wind
3. Telemetry flows: SITL → swarm aggregator → L2 sequencer → … (as Phase 3)
4. The webapp's simulation view subscribes to a WebSocket and renders the
   real run in place of the hand-authored 68-frame script
```

**Pass criteria:**
- [ ] Mission completes successfully under the chaos profile — i.e. the same Phase 3 pass criteria hold even with 5 % packet loss.
- [ ] Mission **fails gracefully** under heavier chaos (30 % loss): the orchestrator times out, no false `MissionVerified` is submitted, the convoy does not advance.
- [ ] WebSocket bridge replays a real run on the webapp at < 1 s lag.
- [ ] No code change required between the Phase 3 simulated-drone pipeline and the Phase 4 SITL pipeline — the L2 contract sees the same `submit_telemetry` shape regardless of source.

## Cross-phase: thesis defence readiness

**Pass criteria (orthogonal to Phase 2/3/4):**
- [ ] All five spec docs in `docs/specs/` are filled in: `threat-model.md`, `interfaces.md`, `cairo-safe-area.md`, `acceptance.md` (this file), and `versions.md` (root).
- [ ] Every Phase 2/3 contract / program exists in source AND has at least one passing unit test (Foundry for Solidity, `cairo_run` for Cairo).
- [ ] The site at `localhost:8081` correctly summarises the threat model, public function signatures, and per-phase acceptance.
- [ ] The end-to-end smoke run in Phase 3 produces logs / artifacts that can be replayed in the simulation as a real-data demo for the defence panel.

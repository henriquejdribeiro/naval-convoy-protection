# Acceptance criteria — per phase

> Each phase has **one concrete scenario** with a measurable pass/fail.
> If the scenario passes end-to-end, the phase is done.

## Phase 1 — Visualisation-first ✅

**State:** completed (this is what you're looking at now).

**Pass conditions** (verifiable on the live site):
- [x] Mission brief renders with thresholds, transparency-vs-privacy block, and SAFE_AREA criterion.
- [x] Interactive simulation plays through all 68 frames without console errors.
- [x] Architecture diagram renders 8 Docker containers + 3 HVUs, supports drag-pan / wheel-zoom / click-to-inspect.
- [x] Code-components and References sections link to GitHub.
- [x] No backend, no Docker — opens by serving the `webapp/` folder over HTTP.

## Phase 2 — L1 mechanics

**Goal:** prove the L1 settlement layer works end-to-end with the four contracts (`Registry`, `Verifier`, `CommandLog`, `StarknetCoreStub`). Pattern B — **D explicitly triggers the advance**, the Verifier does NOT auto-fire.

**Pass scenario:**

```
1. docker compose up geth-clique                         # 6-validator Clique chain comes up
2. forge script DeployL1.s.sol                           # deploys all 4 contracts
3. cast send Registry "deploy(MissionSpec)" from D's COMMANDER key (EX-011, drone_id=β)
   → MissionDeployed(11, β, spec) event observed (drone_id is indexed)
4. cast send Registry "deploy(MissionSpec)" from a non-commander ship key
   → tx REVERTS (onlyCommander)
5. cast send Verifier "registerSafeProof(programHash, outputHash, mission_id=10, drone=α, ...)"
   from ship F's relay key (whitelisted as alpha relay)
   → factHash = keccak256(programHash, outputHash) added to Verifier.verifiedFacts
   → Registry.verdict[10][α] == SAFE  (cross-contract setVerdict)
   → FactRegistered + MissionVerified events emitted
   → no ConvoyAdvance event yet (only one verdict so far)
6. cast send Verifier "registerSafeProof(programHash, outputHash, mission_id=11, drone=β, ...)"
   from ship B's relay key (whitelisted as bravo relay)
   → Registry.verdict[11][β] == SAFE
   → still no ConvoyAdvance event (Verifier does NOT auto-fire — Pattern B)
7. cast send CommandLog "advance(MAX_SPEED)" from D's COMMANDER key
   → ConvoyAdvance(block_number, MAX_SPEED, commander) event emitted
8. cast send CommandLog "advance(MAX_SPEED)" from a non-commander key
   → tx REVERTS (onlyCommander)
9. (Negative test)  Reset chain.  Run steps 1–4 only, then attempt step 7
   → tx REVERTS (CommandLog re-checks Registry.verdict[α] && verdict[β]; missing → revert)
```

**Pass criteria** (every line measurable, all must hold):
- [ ] All 6 ship containers come up with `peerCount == 5` (Clique mesh formed).
- [ ] First Clique block is sealed within 10 s of chain start.
- [ ] Step 3 succeeds; step 4 reverts with `onlyCommander`.
- [ ] Step 5 leaves `Verifier.verifiedFacts[β-factHash] == true`, `Registry.verdict[10][α] == SAFE`, emits `FactRegistered` + `MissionVerified`, NO `ConvoyAdvance`.
- [ ] Step 6 leaves `Verifier.verifiedFacts[β-factHash] == true`, `Registry.verdict[11][β] == SAFE`, emits `FactRegistered` + `MissionVerified`, still NO `ConvoyAdvance` (proves no auto-fire).
- [ ] If a non-relay key calls `registerSafeProof`, tx reverts with `onlyRelay`.
- [ ] Step 7 emits `ConvoyAdvance(block, MAX_SPEED, D)` where `commander == D's address`.
- [ ] Step 8 reverts with `onlyCommander`.
- [ ] Step 9 reverts with `dualSafeRequired` (or equivalent — the dual-SAFE precondition holds).
- [ ] Total time from step 5 to step 7's `ConvoyAdvance` event ≤ 15 s (three blocks at 5 s slot time).

**Out of scope for Phase 2:** no real STARK proof — the fact in steps 5–6 is hand-crafted (`programHash` + `outputHash` hard-coded). Real proofs come in Phase 3.

## Phase 3 — L2 + drone + real proofs

**Goal:** the hand-crafted fact submitted in Phase 2 step 5/6 is now produced by an actual end-to-end run of the prover stack against simulated drone telemetry. **One drone per L2** (drone β on L2-B, drone α on L2-A).

**Pass scenario:**

```
1. docker compose --profile proving up
2. POST telemetry to L2-Bravo for drone β (24×24-cell area, ~50 cells swept)
   → drone β signs each submit_telemetry tx with its Stark-curve key
3. drone β calls submit_sweep_commitment(EX-011, H_β = Poseidon(cells))
4. Madara β seals block N including all telemetry + commitment txs
5. Pathfinder β indexes block N
6. Orchestrator-β polls Pathfinder, picks up block N, runs SNOS → Stone
   → SNOS asserts SAFE_AREA inside Cairo VM; Stone produces π_β
7. Orchestrator-β verifies π_β locally with cpu_air_verifier → runs
   stark_evm_adapter → produces (programHash, outputHash) fact +
   public outputs (coveragePermille, maxContactBp, elapsedSeconds, H_β)
8. Orchestrator-β hands the fact bundle to ship B over radio (RPC) —
   raw proof bytes do NOT travel to L1
9. Ship B writes Verifier.registerSafeProof(programHash, outputHash,
   mission_id=EX-011, drone=β, ...public outputs) to L1 with the ship's key
10. PoA fan-out propagates the tx; every Geth registers the fact in
    Verifier.verifiedFacts, calls Registry.setVerdict(EX-011, β, SAFE),
    emits FactRegistered + MissionVerified events
11. Repeat steps 2–10 for L2-Alpha (drone α, EX-010, ship F as relay)
12. D's orchestrator polls Registry, sees both verdicts SAFE
13. D writes CommandLog.advance(MAX_SPEED) from the commander key
    → ConvoyAdvance event emitted (Pattern B — D triggers, not auto-fire)
14. Both relays bridge the advance event over radio to their L2 drones
```

**Pass criteria:**
- [ ] STARK proof size on the order of 1 MB (Stone proofs for similar-shape Cairo 0 programs are typically 500 KB – 1 MB).
- [ ] Total time from "drone β starts sweep" to "Registry.verdict[11][β] == SAFE on L1" ≤ 4 minutes per lane. Stone proving on a 16 GB host is the bottleneck; budget accordingly.
- [ ] When run with **deliberately bad telemetry** (coverage = 80 %, below 95 % threshold), SNOS replay aborts inside `safe_area_verify.cairo` and Stone never produces a proof. Nothing lands on L1. Verified by `eth_getLogs` showing no `setVerdict` write for that mission.
- [ ] When run with **good telemetry**, the L1 verdict carries `coveragePermille ≥ 950`, `maxContactBp < 7000`, `elapsedSeconds ≤ 360`. Verified by reading Registry storage via `eth_call`.
- [ ] If ship B's relay endpoint is unreachable, Orchestrator-β falls over to ship C (next-best signal for the bravo lane per `orchestrator.toml`) within 30 s and the mission still completes (relay-redundancy test).
- [ ] D's `advance(MAX_SPEED)` tx fires only once both verdicts are SAFE; if D fires it earlier, the tx reverts (`CommandLog` dual-SAFE precondition).

### Phase 3 deliverable: `mission-replay.json` — the recorded full-pipeline capture

The capstone artefact for Phase 3 (and the file the webapp's simulation will eventually replay in place of its hand-authored 68 frames) is **a single timestamped JSON log of one complete successful run**, captured from `docker compose up` through to convoy advance.

**Required entries (each with `t_ms` since `compose up`):**

```
1.  build:start, build:end                            (per service: geth, madara-α, madara-β, pathfinder-α, pathfinder-β, snos-α, snos-β, stone-α, stone-β, orchestrator-α, orchestrator-β)
2.  container:up                                      (per service)
3.  geth:genesis-loaded, geth:first-block-sealed
4.  registry:deploy(EX-010, drone_id=α)               — tx_hash, block, gas
5.  registry:MissionDeployed(EX-010, α)               event log (indexed)
6.  registry:deploy(EX-011, drone_id=β)               — tx_hash, block, gas
7.  registry:MissionDeployed(EX-011, β)               event log
8.  relay-F:radio-dispatch(EX-010, L2-A)              event filter fired on F's orchestrator
9.  relay-B:radio-dispatch(EX-011, L2-B)
10. L2-α:submit_telemetry-tx(cell_id, drone_id=α)     (one entry per cell, ×N cells)
11. L2-β:submit_telemetry-tx(cell_id, drone_id=β)     (same shape, ×N)
12. L2-α:submit_sweep_commitment(EX-010, H_α, n_cells)
13. L2-β:submit_sweep_commitment(EX-011, H_β, n_cells)
14. madara-α:block-sealed(block_number)               sealed Starknet block N
15. madara-β:block-sealed(block_number)
16. pathfinder-α:block-indexed(block_number)
17. pathfinder-β:block-indexed(block_number)
18. orch-α:picked-up-block(block_number)
19. snos-α:pie-generated(elapsed_ms, pie_size_bytes)  — replay asserted SAFE_AREA
20. stone-α:proof-generated(elapsed_ms, proof_size_bytes, n_steps)  → π_α
21. orch-α:cpu-air-verifier-ok(elapsed_ms)             off-chain verification
22. orch-α:stark-evm-adapter-ran(elapsed_ms, programHash, outputHash)
23. orch-α:relay-handoff(ship=F, fact_bundle)         radio RPC (fact, not raw proof)
24. ship-F:registerSafeProof-tx(EX-010, α, tx_hash, block)  L1 tx written
25. L1:FactRegistered(α-factHash, programHash, outputHash)
26. L1:MissionVerified(EX-010, α, factHash, coveragePermille, maxContactBp, elapsedSeconds)
27. L1:setVerdict(EX-010, α, SAFE)                    side-effect of registerSafeProof
28. (steps 18–27 repeat for L2-β / orch-β / ship-B / EX-011)
29. L1:setVerdict(EX-011, β, SAFE)
30. D:dual-safe-detected(t_ms_after_second_setVerdict) D's orchestrator polls Registry
31. D:advance-tx(MAX_SPEED, tx_hash, block)           D writes CommandLog.advance
32. L1:ConvoyAdvance(block, MAX_SPEED, commander=D)   event log (Pattern B — D triggers)
33. relay-B:radio-advance(L2-B)                       advance command bridged to drone β
34. relay-F:radio-advance(L2-A)                       advance command bridged to drone α
35. mission:complete                                  end-of-run marker
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
- [ ] All six spec docs in `docs/specs/` are filled in and consistent with each other: `protocol.md` (the canonical 24-message spec), `threat-model.md`, `interfaces.md`, `cairo-safe-area.md`, `acceptance.md` (this file), and `versions.md` (root).
- [ ] **`protocol.md` and `acceptance.md` agree** — every contract endpoint, event name, payload field, and trust-boundary classification matches between the two. If they ever drift, `protocol.md` wins.
- [ ] Every Phase 2/3 contract / program exists in source AND has at least one passing unit test (Foundry for Solidity, `cairo_run` for Cairo).
- [ ] The site at `localhost:8081` correctly summarises the threat model, public function signatures, and per-phase acceptance.
- [ ] The end-to-end smoke run in Phase 3 produces logs / artifacts that can be replayed in the simulation as a real-data demo for the defence panel.

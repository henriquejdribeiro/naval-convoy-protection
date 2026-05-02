# Architecture

Naval Convoy Protection is a four-tier modular zk-STARK rollup with **two parallel L2 chains** settling to a **shared L1**. This document describes the topology, the data flow, and the trust model. It complements `mission-spec.md` (which defines what each mission verifies) and the visualization at `webapp/index.html` (which shows the eight phases playing out).

## Topology

```
                       ┌──────────────────────────────────────────────────┐
                       │  L1 — Geth Clique PoA (chain_id: convoy_l1)      │
                       │  6 validators: ships A, B, C, D, E, F            │
                       │                                                  │
                       │   ConvoyProofVerifier_α  ConvoyProofVerifier_β   │
                       │   ConvoyMissionRegistry  ConvoyCommandLog        │
                       │   ShipRegistry                                   │
                       └────┬───────────────────────────────────────┬─────┘
                            │ proof tx by ship F or A               │ proof tx by ship A or B
                            │                                       │
        ┌───────────────────┴──────────┐         ┌──────────────────┴───────────┐
        │  L2-Alpha                    │         │  L2-Bravo                    │
        │  (Madara α, chain_id α)      │         │  (Madara β, chain_id β)      │
        │                              │         │                              │
        │  Pathfinder α                │         │  Pathfinder β                │
        │  SNOS α                      │         │  SNOS β                      │
        │  Stone α                     │         │  Stone β                     │
        │  Orchestrator α              │         │  Orchestrator β              │
        │                              │         │                              │
        │  Cairo: convoy_alpha_verify  │         │  Cairo: convoy_bravo_verify  │
        └────────────┬─────────────────┘         └────────────┬─────────────────┘
                     │                                         │
            5 Alpha drones submit                       5 Bravo drones submit
            sweep telemetry transactions                 sweep telemetry transactions
                     │                                         │
                     ▼                                         ▼
                [LEFT FRONTAL AREA]                  [RIGHT FRONTAL CORRIDOR]
```

## Component inventory (Phase 3 target)

| Group | Containers | Purpose |
|---|---|---|
| L1 | `geth-A` … `geth-F` (6) | One Geth Clique-PoA validator per ship |
| L2-Alpha stack | `madara-alpha`, `pathfinder-alpha`, `snos-alpha`, `stone-alpha`, `orchestrator-alpha`, `mongo-alpha` (6) | Left-area proving pipeline |
| L2-Bravo stack | `madara-bravo`, `pathfinder-bravo`, `snos-bravo`, `stone-bravo`, `orchestrator-bravo`, `mongo-bravo` (6) | Right-area proving pipeline |
| Shared infra | `localstack` (1) | AWS mock for both orchestrators |
| Ships | `ship-A` … `ship-F` (6) | Ship-orchestrator agents (D is commander) |
| Drones | `alpha-1` … `alpha-5`, `bravo-1` … `bravo-5` (10) | Telemetry-submitting agents |
| Frontend | `convoy-webapp` (1) | Static web visualization |
| **Total** | **~31 containers** | |

## Data flow — one mission cycle

The diagram tracks one cycle of the system, from the convoy commander issuing missions to the convoy advancing.

1. **Mission deployment (Phase 1).** Ship D issues two L1 transactions:
   - `ConvoyMissionRegistry.deploy(EX-010, alpha_chain_id, area_α, threshold_α)`
   - `ConvoyMissionRegistry.deploy(EX-011, bravo_chain_id, area_β, threshold_β)`
   
   The respective L2 sequencers observe these L1 events and broadcast the mission spec to their drone swarm.

2. **Drone sweeps (Phase 2).** Each drone follows its assigned sweep path (zig-zag for Alpha, corridor for Bravo). Per cell, the drone submits an L2 transaction:
   - `AlphaProtocol.submitTelemetry(cell_id, x, y, t, sensor_hash)`
   
   Madara α/β sequence these transactions into L2 blocks.

3. **Commitment (Phase 3).** Once all sweep cells are submitted, each L2 computes:
   - `H_α = poseidon_chain(cell_0 ∥ cell_1 ∥ … ∥ cell_n)` — left area
   - `H_β = poseidon_chain(...)` — right area

4. **Proof generation (Phase 4).** SNOS re-executes the L2 block in Cairo, generating a proof input. Stone consumes the input and produces a STARK proof:
   - `π_α = stone_prove(convoy_alpha_verify, public={H_α, area, threshold}, witness={telemetry})`
   
   The Cairo program enforces all SAFE conditions inside the proof (coverage ≥ threshold, no contacts above probability, time within window). If any condition fails, the proof cannot be produced.

5. **Best-signal proof relay (Phase 5).** The orchestrator does **not** submit to L1 directly. Instead, it publishes the proof to a queue that ship-orchestrator agents poll. Each ship agent decides whether it has best signal for the originating L2:
   - Ship F or A relays Alpha proofs (forward-left and forward positions cover the left area)
   - Ship A or B relays Bravo proofs (forward and forward-right positions cover the right area)
   
   The selected ship submits an L1 transaction:
   - `ConvoyProofVerifier_α.verifyProof(π_α, public_inputs)`
   
   The ship's own PoA key signs the L1 transaction envelope (network-level authentication). The cryptographic check happens **inside the contract**, not by the ship.

6. **On-chain verification (Phase 6).** `ConvoyProofVerifier` runs the STARK verifier in Solidity (mirroring StarkWare's `FactRegistry` pattern). On success:
   - `ConvoyMissionRegistry.statuses["EX-010"].safe_outcome = true`
   - `ConvoyMissionRegistry.statuses["EX-010"].relay_ship = msg.sender`
   - emit event `MissionVerified(EX-010, F, block.timestamp)`

7. **Commander gate (Phase 7).** Ship D's commander agent listens for `MissionVerified` events. When both `EX-010` and `EX-011` show `safe_outcome = true`, ship D submits:
   - `ConvoyCommandLog.advance(maxSpeed = true)`
   
   The contract enforces both preconditions and that `msg.sender == COMMANDER_D`.

8. **Convoy advance (Phase 8).** All six ships' validators see the `ConvoyAdvance` L1 event in the next block and execute the maneuver locally. Mission cycle complete.

## Trust model

The architecture has four distinct authority types:

| Role | Held by | Power |
|------|---------|-------|
| **L1 protocol authority** (block production) | All 6 ships' PoA keys | Sign L1 blocks; cannot bypass contract checks |
| **L2 sequencer authority** (transaction ordering) | One Madara process per L2 (centralised in Phase 3; multi-sequencer deferred) | Order L2 transactions |
| **Mission proof authority** (cryptographic) | Stone prover + L1 STARK verifier contract | The only authority that can mark a mission `SAFE` |
| **Commander authority** (advance command) | Ship D's PoA key + the two-of-two precondition | Issue convoy advance |

Compromising one of these does not compromise the others:

- Compromising a single PoA key (e.g., ship E's) → no mission can be falsely marked SAFE; the L1 verifier checks the proof itself.
- Compromising the L2 sequencer → cannot forge a valid STARK proof; the prover would refuse to prove a constraint-violating trace.
- Compromising the prover → still can't sneak a bad proof past the L1 verifier (the verifier re-runs FRI queries).
- Compromising ship D → can issue advance only when both genuine proofs are on L1, so no false advance is possible.

The only single point of failure is **the genesis-time deployment**: whoever deploys the contracts and registers the validator set has full control. After that, the protocol is bound by what the contracts enforce.

## Why two L2s, not one

A single L2 with two missions would be simpler to deploy but worse for resilience. With two L2s:

- A failure in Madara α (left-area sequencer) does not delay EX-011 — Madara β continues independently.
- The two proving pipelines run in parallel on separate hardware → wall-clock time bounded by the slower of the two, not their sum.
- Each L2 has its own genesis and validator set, allowing independent upgrade and rollback paths.
- Different missions can use different Cairo program versions without coupling.

Cost: doubled infrastructure (two Madara, two Pathfinder, two Stone, two Orchestrator). For a naval deployment where mission criticality is high and hardware budget is not the binding constraint, the doubled cost is the right trade-off.

## What "best-signal relay" actually models

In Phase 1 (the visualization), best-signal selection is deterministic:

- Alpha proofs always go via ship F.
- Bravo proofs always go via ship B.

In Phase 4 (network chaos), this is replaced with a probabilistic model:

- Each ship has a position-dependent "signal strength" to each L2 area.
- Failures are injected via `tc`/`netem` — a partition between the L2 orchestrator and ship A simulates a radio outage.
- Ship-orchestrator agents detect the failure (timeout) and a secondary ship takes over relay duty.

The Phase 1 visualization shows the ideal case. The thesis-style measurement in Phase 4 quantifies how well the architecture degrades when primary relays fail.

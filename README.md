# Naval Convoy Protection

Verifiable mission compliance for naval drone escort operations, built on a modular zk-STARK rollup architecture.

This project demonstrates how a six-ship naval convoy can use **two parallel Layer 2 chains** and a shared **Layer 1 settlement layer** to verify, in zero knowledge, that two drone swarms have completed their assigned frontal-area sweeps before the convoy advances. Each L2 produces a STARK proof of mission compliance; the closest reachable ship relays that proof to L1; the L1 verifier contract cryptographically checks it; and only after **both** proofs land on L1 does the convoy commander issue the advance command.

## The mission

The convoy holds while two simultaneous reconnaissance missions complete:

| Mission ID | Drone swarm | Area     | L2 chain     | Primary relay ships |
|-----------:|------------:|---------:|-------------:|--------------------:|
| **EX-010** |       Alpha | Left frontal area  | `L2-Alpha`   | A or F              |
| **EX-011** |       Bravo | Right frontal corridor | `L2-Bravo`   | A or B              |

Each mission specifies:

- a **reference area** (polygon or grid) to be covered,
- a **minimum coverage percentage**,
- a **detection threshold** for contacts above probability `x`,
- a **maximum execution time window**.

A mission concludes with `SAFE_AREA` if and only if total coverage ≥ threshold, execution time ≤ window, and no relevant threats were detected.

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

All six ships (A, B, C, D, E, F) are validators of the same Layer 1 PoA chain. Ship D is the commander — it watches L1 for both `EX-010 SAFE` and `EX-011 SAFE` confirmations and, only when both arrive, issues a single L1 transaction: `Convoy ADVANCE maximum speed`.

## Architecture in one diagram

```
       ┌──────────────────────────────┐         ┌──────────────────────────────┐
       │  L2-Alpha (Madara α)         │         │  L2-Bravo (Madara β)         │
       │  Alpha drones submit         │         │  Bravo drones submit         │
       │  per-cell sweep commitments  │         │  per-cell sweep commitments  │
       │  → STARK proof π_α           │         │  → STARK proof π_β           │
       └──────────────┬───────────────┘         └──────────────┬───────────────┘
                      │                                         │
        relay via best-signal ship                relay via best-signal ship
                      │                                         │
                      ▼                                         ▼
                  ┌───────┐                                 ┌───────┐
                  │ A or F│                                 │ A or B│
                  └───┬───┘                                 └───┬───┘
                      │                                         │
                      ▼            ┌──────────────┐             ▼
                                   │  L1 (Geth    │
                                   │   Clique     │
                                   │   PoA, 6     │
                                   │   validators)│
                                   ├──────────────┤
                                   │ ConvoyProof  │  ← cryptographic verification
                                   │ Verifier × 2 │     happens HERE, on-chain
                                   ├──────────────┤
                                   │ ConvoyMission│
                                   │ Registry     │
                                   ├──────────────┤
                                   │ ConvoyCommand│
                                   │ Log          │
                                   └──────┬───────┘
                                          │
                                          │  events: EX-010 SAFE, EX-011 SAFE
                                          ▼
                                  ┌─────────────────┐
                                  │ Ship D          │
                                  │ (commander)     │
                                  │                 │
                                  │ if both SAFE →  │
                                  │ tx: ADVANCE     │
                                  └─────────────────┘
```

The cryptographic ground truth is held by the L1 verifier contract — ships are *relays*, not authoritative validators of the proof. A ship's PoA signature on the relay transaction provides only network-level authentication; the proof's validity is established by the on-chain STARK verifier.

## Project status

This repository follows a phased build:

- **Phase 1 — Visualization first** *(current)* — interactive single-page web demo of the full mission flow, animated end-to-end. No Docker required; open `webapp/index.html` in a browser.
- **Phase 2 — L1 mechanics** — six Geth Clique-PoA containers, four Solidity contracts, ship-D commander logic working without real proofs.
- **Phase 3 — Two L2 stacks + drones** — Madara α and β, Pathfinder, SNOS, Stone, orchestrators, ten drone containers (5 Alpha + 5 Bravo), real STARK proofs flowing.
- **Phase 4 — Polish** — ArduPilot SITL flight dynamics per drone, network impairment chaos (`tc`/`netem`), live-data WebSocket bridge into the visualization.

## Cloning the repo

Two upstream projects are vendored as **git submodules**, each pinned to a specific commit so the cryptographic stack stays reproducible:

| Submodule | Path | What it provides |
|---|---|---|
| [`starkware-libs/starkex-contracts`](https://github.com/starkware-libs/starkex-contracts) | `contracts/lib/starkex-contracts/` | L1 STARK verifier contracts (`GpsStatementVerifier`, `FactRegistry`) that `GpsStarkVerifierAdapter` wraps |
| [`zksecurity/stark-evm-adapter`](https://github.com/zksecurity/stark-evm-adapter) | `vendor/stark-evm-adapter/` | The `stark_evm_adapter` binary the prover-api container runs at step 5 of the proof pipeline — converts a Stone-prover annotated proof into the EVM-format calldata the L1 verifier consumes |

Clone with `--recurse-submodules`, or fetch them after a normal clone:

```bash
# Fresh clone (recommended)
git clone --recurse-submodules https://github.com/henriquejdribeiro/naval-convoy-protection.git

# Already cloned without --recurse-submodules?
git submodule update --init --recursive
```

Without the submodules, `forge build` still works for Phase 2 (the convoy contracts) because the StarkWare contracts aren't imported into the build graph yet — but the `GpsStarkVerifierAdapter` (and any production deployment of the on-chain STARK verifier) requires the `starkex-contracts` submodule present, and the `stark_evm_adapter` binary built from the `vendor/` submodule is consumed by `infrastructure/prover-api/entrypoint.sh` at runtime.

## Quickstart (Phase 1)

No installation. Open `webapp/index.html` directly in a modern browser, or serve the folder over HTTP if your browser blocks local module imports:

```bash
cd webapp
python -m http.server 8080
# then open http://localhost:8080
```

Click **▶ Play Demonstration** in the simulation widget to watch the eight phases of the convoy mission play out end-to-end.

## Technology stack

| Layer | Component | Phase |
|-------|-----------|-------|
| L1 settlement | Go-Ethereum (Clique PoA, 6 validators) | 2 |
| L2 sequencing | Madara appchain ×2 (Alpha, Bravo) | 3 |
| L2 indexing | Pathfinder ×2 | 3 |
| Proving | StarkWare Stone (via SNOS) ×2 | 3 |
| Settlement | Solidity STARK verifier contracts | 2 |
| Mission programs | Cairo 2.x (`convoy_alpha_verify.cairo`, `convoy_bravo_verify.cairo`) | 3 |
| Mission control | Python ship-orchestrator agents | 2 |
| Drone agents | Python (Phase 3) → ArduPilot SITL (Phase 4) | 3–4 |
| Visualization | Vanilla JS + SVG (no framework) | 1 |

## License

Apache-2.0 — see `LICENSE`.

## Provenance

This project's STARK pipeline derives from the architecture developed in the author's Master's thesis on modular blockchain architectures for resource-constrained drone swarms (Instituto Superior Técnico, 2026). Naval Convoy Protection is a self-contained mission archetype extracted as a standalone deliverable, with its own contracts, container topology, and visualization. No code dependency on the thesis repository exists.

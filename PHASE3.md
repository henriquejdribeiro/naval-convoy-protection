# Phase 3 — L2 + STARK proofs (in-flight)

Building the proving pipeline on top of the working Phase 2 L1 stack.
Adapted from `verifiable_grid/`'s working configuration — same pinned
versions, same multi-stage Stone build.

## Phase 3.a — Direct prover (this commit)

Smallest vertical slice that produces a real STARK proof and lands its
fact on L1. **Skips Madara/Pathfinder/SNOS for now** — that's Phase 3.b.

```
                     ┌─────────────────────────────────┐
                     │ infrastructure/prover-api       │
                     │                                 │
  sample_input.json ─┼──► safe_area_verify.cairo       │
                     │           │                     │
                     │           ▼                     │
                     │    cairo-run --proof_mode       │
                     │           │                     │
                     │           ▼                     │
                     │    cpu_air_prover  ──► proof    │
                     │           │                     │
                     │           ▼                     │
                     │    cpu_air_verifier (gate ✓)    │
                     │           │                     │
                     │           ▼                     │
                     │    stark_evm_adapter            │
                     │           │                     │
                     │           ▼                     │
                     │  submit_proof_l1.py             │
                     │           │                     │
                     └───────────┼─────────────────────┘
                                 │
                                 ▼
              Verifier.registerSafeProof((..., factHash))
                                 │
                                 ▼
                          Phase 2's L1 chain
                          (already running)
```

## Files in this commit

```
cairo/
└── safe_area_verify/                ← (also lives at infrastructure/prover-api/)
infrastructure/prover-api/
├── Dockerfile                       ← Stone (Bazel) + cairo-lang 0.14.0.1
│                                       + stone-prover-cli + stark_evm_adapter
├── safe_area_verify.cairo           ← Cairo 0 program: proves SAFE_AREA criterion
├── sample_input.json                ← canonical SAFE input (50 cells, satisfies
│                                       coverage 952‰, max_p 4500bp, elapsed 340s)
├── prove_pie.py                     ← future use: re-prove SNOS PIEs
├── submit_proof_l1.py               ← cast-based L1 submission, picks the
│                                       right relay key based on drone_id
└── entrypoint.sh                    ← compile → run → prove → verify → adapt → submit
docker-compose.l2.yml                ← extends docker-compose.l1.yml
PHASE3.md                            ← this file
```

## SAFE_AREA criterion encoded in safe_area_verify.cairo

The Cairo 0 program enforces three constraints; **any failure aborts the
replay so no proof is produced**:

| Field        | Encoding         | Constraint                              |
|--------------|------------------|-----------------------------------------|
| coverage     | permille (uint16)| `(n_cells × 1000) / area_total ≥ coverage_min` |
| p_contact    | basis points     | every cell `p_contact < p_min`          |
| time_window  | seconds          | `max(cell.ts) − ts_start ≤ time_window` |

Public outputs (in order, written by `serialize_word`):

```
[mission_id, drone_id, coverage_permille, max_p_contact, elapsed_seconds, commitment]
```

These six felts are extracted by `submit_proof_l1.py` and passed verbatim
to `Verifier.registerSafeProof(SafeProofInputs(...))` on L1. The
contract re-asserts the threshold checks against the on-chain
`MissionSpec` so a tampered fact can't smuggle in lower thresholds.

## How to run (when ready to test)

The L1 chain from Phase 2 must be up first:

```bash
# (one-time) generate keystores
./scripts/generate-keys.sh

# (one-time) bring up the L1 chain + deploy contracts
docker compose -f docker-compose.l1.yml up -d
docker compose -f docker-compose.l1.yml --profile deploy run --rm deploy-l1
```

Then bring up the prover service:

```bash
docker compose -f docker-compose.l1.yml -f docker-compose.l2.yml up -d prover-api
```

Watch the prover work on the boot-time sample input:

```bash
docker logs -f convoy-prover-api
```

Expected sequence:
1. Compile `safe_area_verify.cairo` (~10s)
2. Run cairo-run on `sample_input.json` (~5s)
3. cpu_air_prover (1–3 minutes — the heavy step)
4. cpu_air_verifier passes
5. stark_evm_adapter produces `evm_proof.json`
6. `submit_proof_l1.py` calls Verifier on ship-a → `FactRegistered` + `MissionVerified` events emitted

After completion, query the live state:

```bash
# Check the verdict was written
cast call $VERIFIER_ADDR "verifiedFacts(bytes32)(bool)" $FACT_HASH \
    --rpc-url http://127.0.0.1:18545

# Check the registry verdict
cast call $REGISTRY_ADDR "verdict(uint256,uint256)(bool)" 11 2 \
    --rpc-url http://127.0.0.1:18545
```

## Phase 3.b — Madara + Pathfinder + SNOS (pending)

Next slice will:

1. Bring up `ghcr.io/madara-alliance/madara:nightly` configured to settle
   into the existing `StarknetCoreStub` at the deterministic address.
2. Bring up `eqlabs/pathfinder:v0.21.3` indexing Madara's blocks.
3. Build the SNOS image (Karnot fork with the tx-hash patches from
   verifiable_grid).
4. Write `convoy_protocol.cairo` (Cairo 1) — the L2 contract drone β
   submits telemetry to.
5. Replace the prover-api's "boot the sample input" flow with a
   "watch-pathfinder-for-new-block" loop.

The L1 contracts and Cairo 0 program in this commit DON'T need to change
when Phase 3.b lands — `submit_proof_l1.py` already accepts proofs from
any source.

## Acceptance gate

Phase 3.a is done when:

- [ ] `docker compose -f docker-compose.l2.yml up prover-api` produces a
      `proof.json` of ~500 KB to 1 MB.
- [ ] `cpu_air_verifier` passes locally.
- [ ] `Verifier.registerSafeProof` succeeds on-chain; `FactRegistered`
      and `MissionVerified` events visible via `cast logs`.
- [ ] `Registry.verdict[11][2]` reads `true` (β SAFE).
- [ ] Submitting deliberately bad input (coverage 80%, or p_contact 8000)
      makes cairo-run abort; **no proof produced, nothing lands on L1**.

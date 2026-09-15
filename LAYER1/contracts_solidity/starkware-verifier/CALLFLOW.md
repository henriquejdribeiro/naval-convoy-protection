# CALLFLOW — from drone telemetry to an accepted L1 proof

A guided tour of the whole pipeline, across both contract layers: **our** contracts
(L2 `convoy_protocol`, the Cairo predicate, the Rust submitter, the L1 `Verifier`/
`Registry`) and the **vendored StarkWare** GPS verifier suite. Every hop names the
exact file + function so you can jump straight to it.

## The 30-second version


## Stage 1 — the drone signs & submits (L2)

**File:** `LAYER2/contracts_cairo/convoy_protocol/src/lib.cairo` → `fn submit_telemetry`

- **Identity gate #1 (L2):** `assert(get_caller_address() == drone_addr[(mission,drone)])`
  — only the account registered for that drone may submit. The address map is written by
  `open_mission`, which itself asserts the unforgeable L1 relay sender.
- **Custody:** the drone's STARK-curve key is born in and never leaves its machine volume;
  it signs (`sign_telemetry.py`) and submits from its own account, so `get_caller_address()`
  *is* that drone.
- `commitment_h` = Pedersen(cells, nonce) — a hiding commitment the drone publishes on L2.

## Stage 2 — bridge L2 → prover input

**File:** `PROOF/prover-api/fetch_l2_cells.py`

Pulls the submitted cells for `(mission, drone)` back off L2 via Pathfinder RPC and writes
the Cairo `program_input` the predicate will be proved against.

## Stage 3 — prove the predicate (off-chain)

**Predicate:** `PROOF/prover-api/safe_area_verify.cairo` (Cairo 0; builtins `output pedersen
range_check ecdsa`). Proves the drone's vertical strip is SAFE under a few constraints
(all cells inside the assigned strip, contact-probability bound, coverage threshold) **plus
an in-circuit ECDSA check** (`verify_ecdsa_signature`) over the commitment.

**9 public outputs** (in this exact `serialize_word` order):
`mission_id, drone_id, strip_x_start, strip_x_end, strip_y_start, strip_y_end,
verdict_bool, commitment_H, drone_pubkey`.

> **In-proof binding:** because the proof itself verifies the drone's signature over the
> commitment, the `drone_pubkey` output is provably the *actual signer's* key — not an
> attacker-chosen value.

**Pipeline** (`PROOF/prover-api/entrypoint.sh`, 6 steps):
`cairo-compile` → `cairo-run` (PIE) → `stone-cli prove-bootloader` → `stone-cli verify` →
`stone-cli serialize-proof --network ethereum` → `convoy-submitter`.

## Stage 4 — submit the STARK proof to L1

**File:** `PROOF/submitter/src/main.rs` (`convoy-submitter`). Reads the annotated proof,
runs `split_fri_merkle_statements`, then drives StarkWare's four phases:

| Phase | Call | Vendored source |
|---|---|---|
| 1 | `MerkleStatementContract.verifyMerkle()` | `starkware-verifier/src/Merkle/…/MerkleStatementContract.sol` |
| 2 | `FriStatementContract.verifyFRI()` | `starkware-verifier/src/Fri/…/FriStatementContract.sol` |
| 3 | `MemoryPageFactRegistry.registerContinuousMemoryPage()` | `starkware-verifier/src/MemoryPage/…/MemoryPageFactRegistry.sol` |
| 4a | `GpsStatementVerifier.verifyProofAndRegister(proofParams, proof, taskMetadata, cairoAuxInput, cairoVerifierId=6)` | `starkware-verifier/src/GpsStatementVerifier/…/gps/GpsStatementVerifier.sol` |

## Stage 5 — inside the StarkWare GPS suite (vendored, byte-verified)

`GpsStatementVerifier.verifyProofAndRegister`:
1. selects `cairoVerifierContractAddresses[6]` = `CpuFrilessVerifier` (our deploy wires slot 6);
2. `cairoVerifier.verifyProofExternal(...)` → `CpuFrilessVerifier` → `StarkVerifier`
   (`starkware-verifier/src/CpuFrilessVerifier/…/layout6/{CpuFrilessVerifier,StarkVerifier}.sol`):
   consumes the Merkle + FRI + memory-page facts from phases 1-3, checks OODS (`CpuOods`), the
   AIR constraints (`CpuConstraintPoly` + the Pedersen / ECDSA / Poseidon periodic columns) and
   FRI folding (`Fri`) against the bootloader program (`CairoBootloaderProgram`);
3. `registerGpsFacts(...)` records the `(programHash, output)` fact.

> Every contract in this suite is the **verified mainnet source** — see
> `LAYER1/contracts_solidity/starkware-verifier/SOURCE.md` for the byte-exact provenance
> (17/17 recompile match) and the reproduce/verify commands.

## Stage 6 — our identity-gated verdict (L1)

**File:** `LAYER1/contracts_solidity/src/Verifier.sol` → `registerSafeProof(SafeProofInputs)`.
Gates, in order:

1. **onlyRelay:** `msg.sender == relayOf[missionId]`.
2. **known mission:** `Registry` spec exists, `droneIndex ∈ [1, nDrones]`, `verdictBool ≤ 1`.
3. **strip-bounds:** the proof's `stripX/Y` must equal the bounds derived from the `Registry`
   `MissionSpec` + `droneIndex` (so a drone can only prove *its* assigned strip).
4. **Identity gate #2 (L1):** `inputs.dronePubkey == registeredDronePubkey[mission][drone]`.
5. **STARK fact:** `starkVerifier.isValid(factHash)` — the GPS fact registered in Phase 4a
   must exist, tying the on-chain STARK verification to this verdict.

On success it records the per-drone SAFE tally (`safeCount` / `droneSafeCounted`) and the
mission-level aggregation. `Registry` (`LAYER1/contracts_solidity/src/Registry.sol`) holds the
`MissionSpec` (zone, strip width, drone count) that gates 2-3 read from.

## The security spine — identity binding (Route B)

Three independent checks bind a SAFE verdict to an authorised drone:

- **L2 (Stage 1):** only the registered drone account can submit (`get_caller_address`).
- **In-proof (Stage 3):** the STARK proof verifies the drone's ECDSA signature over the
  commitment, so the `drone_pubkey` output is the real signer's.
- **L1 (Stage 6):** the verdict is accepted only if that pubkey equals the pubkey registered
  for `(mission, drone)`.

The STARK proof attests **compliance of the committed data**; it does **not** attest the
honesty of the underlying sensor readings — that is the explicit trust boundary of the design.

## File index

**Our code**
- L2 contract: `LAYER2/contracts_cairo/convoy_protocol/src/lib.cairo`
- predicate: `PROOF/prover-api/safe_area_verify.cairo`
- prover pipeline: `PROOF/prover-api/entrypoint.sh`, `PROOF/prover-api/fetch_l2_cells.py`
- submitter: `PROOF/submitter/src/main.rs`
- L1 verifier + registry: `LAYER1/contracts_solidity/src/Verifier.sol`, `Registry.sol`

**Vendored StarkWare** (Apache-2.0, byte-verified)
- `LAYER1/contracts_solidity/starkware-verifier/src/**` (+ `SOURCE.md`, `CALLFLOW` reference above)
MD
echo "written."
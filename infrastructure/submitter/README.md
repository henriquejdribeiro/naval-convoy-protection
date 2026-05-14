# convoy-submitter

Rust binary that submits a Stone-generated STARK proof of
`safe_area_verify.cairo` through the full StarkWare layout-6 on-chain
verifier pipeline.

This is the convoy-protocol-specific adaptation of
`stark_evm_adapter`'s `examples/verify_stone_proof.rs`. The three
substitutions versus the upstream example:

1. Mainnet contract addresses replaced with env vars that match the
   deployment produced by `contracts/script/DeployStarkVerifier.s.sol`.
2. The final `verifyProofAndRegister` call is re-routed from
   `GpsStatementVerifier` directly to **our** `Verifier.registerSafeProof`,
   so the relay-whitelist + threshold-reassertion + Registry verdict
   write happens on top of StarkWare's audited verification math.
3. The Cairo program's six public outputs
   `(mission_id, drone_id, coverage, max_p_contact, elapsed, commitment)`
   are extracted from the proof's public memory and packaged into the
   `SafeProofInputs` tuple our Verifier expects.

The cryptographic core (the proof splitting, the FRI/Merkle/memory-page
submission shape, the contract argument formatting) all comes from
`stark_evm_adapter`'s library — we add no new crypto.

## Build

One-time, takes a few minutes on first build to fetch ethers and
related dependencies:

```bash
cd infrastructure/submitter
cargo build --release
# binary at target/release/convoy-submitter
```

Requires a working Rust toolchain (1.75+ recommended). If you're running
inside the convoy-prover-api container, install rustup first:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env
```

## Run

Before invoking, you need:

- A working Stone-prover output (`proof.json`, `evm_proof.json`,
  `fact_topologies.json`, plus the compiled `safe_area_verify.json`) —
  produced by `infrastructure/prover-api/entrypoint.sh`.
- A live L1 deployment of `DeployStarkVerifier` and `DeployL1`. The
  four StarkWare contract addresses + our Verifier address are needed
  as env vars.
- A relay-ship private key (alpha = ship F's anvil[5]; bravo = ship B's
  anvil[1]).
- The bootloader-hash constants sourced from
  `scripts/bootloader-hashes.env` *before* deploying — otherwise the
  GPS verifier rejects any proof at `registerPublicMemoryMainPage`.

Example invocation:

```bash
source scripts/bootloader-hashes.env       # required once before DeployStarkVerifier

export URL=http://localhost:18545
export PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d  # anvil[1] = ship B
export ANNOTATED_PROOF=/proofs/evm_proof.json
export FACT_TOPOLOGIES=/proofs/fact_topologies.json
export SAFE_AREA_VERIFY_JSON=/proofs/safe_area_verify.json
export CONVOY_VERIFIER_ADDR=0x...                  # from DeployL1 logs
export MERKLE_STATEMENT_CONTRACT_ADDR=0x...        # from DeployStarkVerifier
export FRI_STATEMENT_CONTRACT_ADDR=0x...           # from DeployStarkVerifier
export MEMORY_PAGE_FACT_REGISTRY_ADDR=0x...        # from DeployStarkVerifier

./target/release/convoy-submitter
```

## Phases

The binary runs **four phases** in sequence. Each phase commits
intermediate state to L1 that the final phase references. The split is
required because a single all-in-one call would exceed EVM gas limits.

```
1. Trace Merkle commits  → MerkleStatementContract.verifyMerkle()      (N calls)
2. FRI layer commits     → FriStatementContract.verifyFRI()            (N calls)
3. Memory page registers → MemoryPageFactRegistry.registerContinuous() (N calls)
4. Final verification    → OUR Verifier.registerSafeProof(...)         (1 call)
```

Only Phase 4 talks to *our* Verifier. Phases 1–3 talk directly to the
StarkWare contracts deployed by `DeployStarkVerifier`. Phase 4 wraps
the underlying `GpsStatementVerifier.verifyProofAndRegister` call
inside our authorisation + threshold-reassertion logic.

## Why this exists instead of doing it from Python

The split logic (`stark_evm_adapter::annotation_parser::
split_fri_merkle_statements`) is a Rust library function with no CLI
exposure. Re-implementing it in Python would be impractical (hundreds
of lines of complex field-element arithmetic and Merkle accounting).
The thinnest wrapper around the existing library is a small Rust
binary; that is what this crate is.

`infrastructure/prover-api/submit_proof_l1.py` is now used **only**
for Phase 4 alone, against the mock verifier — it cannot perform
Phases 1–3. With the real `GpsStatementVerifier`, you must use this
binary.

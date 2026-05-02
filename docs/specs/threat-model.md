# Threat Model

**Status:** v0.1 — pre-implementation. Will be revised once Phase 2 and Phase 3 are running.

## 1. What we're claiming

> The convoy advances **if and only if** the L1 chain has recorded a `SAFE` verdict for both `EX-010` (Alpha sweep) and `EX-011` (Bravo sweep), where each verdict is the result of a STARK proof passing on-chain FRI verification against the published mission spec.

Equivalently: an attacker who wants to make the convoy advance into unswept water — *without* having actually swept it — must either forge a STARK proof, compromise a quorum of L1 validators, or break the cryptographic primitives we rely on.

## 2. Cryptographic ground

| Primitive | Used for | Soundness |
|---|---|---|
| STARK / FRI (Stone prover) | Attesting the SAFE_AREA computation over private telemetry | ~100-bit conjectured soundness, parameter-tunable to 128-bit. Post-quantum secure. |
| Poseidon | Telemetry commitment `H_α`, `H_β` | ~128-bit collision resistance over the STARK-friendly field |
| Keccak-256 | Solidity event hashing, EIP-55 addresses | ~128-bit collision resistance |
| secp256k1 ECDSA | L1 transaction signatures, Clique block sealing | ~128-bit classical security. **NOT post-quantum.** See § 6. |
| Clique PoA (EIP-225) | L1 block production by 6 ships | Liveness with ≥ 4 honest signers; safety with < 4 divergent signers (BFT-style ⌊(N-1)/2⌋ = 2 fault tolerance). |

## 3. Adversaries (in scope)

### 3.1 External passive observer (hostile sub / aircraft scraping L1)
- **Capabilities:** reads any L1 transaction, block, or event; sees the mission spec, the proof bytes, the SAFE verdict, and which ship relayed.
- **Cannot:** read L2 telemetry (lives on the L2 sequencer + the prover's witness, never on L1); reconstruct sweep paths from public commitments alone (Poseidon is hiding under standard assumptions).
- **Outcome:** learns *that* a sweep happened and *that* the area cleared; learns nothing about *how* (drone trajectories, sensor density, blind spots).

### 3.2 Compromised relay ship (e.g. captured F or B)
- **Capabilities:** holds one PoA validator key; can sign blocks, refuse to relay a proof, attempt to submit a fabricated proof.
- **Cannot:** forge a valid STARK proof (would have to break FRI). Cannot drive the chain alone — Clique requires ≥ 4 of 6 signatures for finality.
- **Outcome:** at worst, denial-of-service on its own relay duty (the orchestrator falls over to the secondary relay, e.g. F → A or B → A).

### 3.3 Compromised commander (D)
- **Capabilities:** holds the commander key; can deploy fake mission specs (bogus area / threshold / window), can refuse to deploy real ones, can manually call `CommandLog.advance()` on the override path.
- **Cannot:** manufacture a SAFE verdict — the auto-advance path is gated by the on-chain dual-SAFE check, which depends on real proofs. Even the manual override only fires the advance event; it cannot retroactively rewrite a SAFE verdict that wasn't produced by a valid proof.
- **Outcome:** can DoS the mission (deploy malformed specs, or refuse to deploy at all) but cannot manufacture a false advance into hostile water — the L1 verifier is the hard gate, not D's say-so.

### 3.4 Up to two byzantine ships (any combination)
- Clique PoA tolerates ⌊(6−1)/2⌋ = 2 byzantine signers.
- With 2 ships compromised, the chain still advances safely under 4 honest signers.
- With 3+ ships compromised, the chain halts (no quorum). **This is a safe failure**: the convoy does not advance.

### 3.5 Compromised L2 sequencer (Madara α or β)
- **Capabilities:** can refuse to sequence telemetry txs; can construct an L2 block embedding fabricated telemetry; can run the prover over the fabricated trace and produce a *cryptographically valid* STARK proof of that trace.
- **Cannot:** make the verifier accept a proof whose Cairo program output disagrees with the public inputs (the proof commits to the public inputs).
- **Limit of the model:** if the sequencer can also dictate what the drones report (i.e. the drones are not independent sensors), then the sequencer can construct a proof that "the area is clear" because the witness it ran the prover over says so. **This collapses to "the drones must be honest sensors"** — see § 4 / drone honesty.

## 4. Trust assumptions (must hold for the security claim)

1. **Drones are honest sensors.** Each drone reports its own telemetry truthfully. The current design has *no* cross-attestation between drones, so a fully compromised drone fleet collapses the claim. *Mitigation (future work):* k-of-n drone signatures on each cell's telemetry, verified inside the Cairo program.
2. **At most 2 ships are simultaneously compromised** — required for Clique PoA safety.
3. **The Cairo program is correct.** A bug in `safe_area_verify.cairo` (e.g. a subtly broken coverage check) lets an honest prover produce a SAFE proof for unsafe telemetry. *Mitigation:* formal verification of the Cairo program, or at minimum exhaustive property-based testing.
4. **The Solidity verifier matches the prover** — a bug in the FRI re-implementation on L1 would let invalid proofs through. *Mitigation:* use the StarkWare-audited reference verifier; do not roll our own.
5. **Genesis is honestly distributed** — the 6 ship validator keys are loaded onto the right hulls before the mission. Out-of-band physical security problem, not a cryptographic one.

## 5. Out of scope

- **Quantum adversary** (see § 6). Acknowledged limitation.
- **Side-channel attacks** on the prover, the keystore, or the Geth process (timing, EM, cold-boot).
- **Physical seizure** of three or more ships simultaneously.
- **RF jamming, spoofing, or denial** of the radio links between ships, between ships and L2 swarms, or between L2 swarms and drones. This is a Layer-1 (physical) concern; the Phase 4 SITL + `tc/netem` chaos rig is meant to *characterise* this layer, not defend it cryptographically.
- **Drone collusion with the L2 sequencer** to falsify sensor data, as noted in § 4.
- **Long-range adversaries with off-chain compromise of the development chain** (i.e. an attacker who replaces a binary in CI). Standard supply-chain hygiene assumed.

## 6. Known cryptographic limitation: post-quantum

The system has an asymmetry in its quantum security posture:

- **STARK / FRI / Poseidon** layer is post-quantum secure.
- **secp256k1 ECDSA** signatures (L1 transactions, Clique block sealing) are *not*. Shor's algorithm on a sufficiently large quantum computer breaks the discrete-log problem the curve relies on.

**Implication:** a future quantum adversary can forge L1 transactions (e.g. fabricate a `ConvoyAdvance` event from any validator's address), even though it still cannot forge the STARK proofs underneath.

**Future work:** a fully post-quantum convoy would replace ECDSA signatures with a hash-based scheme (Winternitz / SPHINCS+) or a lattice-based scheme; the STARK side already meets that bar.

## 7. Soundness targets (concrete numbers)

| Property | Target | Source |
|---|---|---|
| Per-proof STARK soundness | 80-bit conjectured (Phase 2 default) → 100–128-bit (Phase 3 onwards) | FRI parameters in `cairo/prover_config.json` |
| L1 block finality | 4 of 6 PoA signatures | EIP-225 / Clique config |
| Time to advance after dual SAFE | ≤ 1 L1 block (~5 s with our Clique block time) | The verifier auto-fires advance in the same tx |
| Mission replay protection | One mission ID per `Registry.deploy(...)`, registry rejects re-use | Solidity storage check |
| Telemetry-to-proof binding | Poseidon commitment `H_α` / `H_β` checked inside the Cairo program | `safe_area_verify.cairo`, see `docs/specs/cairo-safe-area.md` |

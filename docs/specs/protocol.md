# Convoy mission protocol

The authoritative specification of the 24-message protocol that drives one
full mission cycle. The webapp's *Transaction flow diagram* visualises this
document; the spec lives here. **If the visualisation and this document
disagree, this document wins.**

The protocol is described for the **L2-Bravo lane** (drone β, ship B as
primary relay, mission `EX-011`). The **L2-Alpha lane** (drone α, ship F,
mission `EX-010`) is structurally identical — wherever a step has a
*Parallel lane* note, the alpha-lane equivalent runs simultaneously with
its own substituted symbols (α / `H_α` / `π_α`).

---

## Actors

| Lifeline | Role | Domain |
|---|---|---|
| **D** | Commander ship — holds the commander key | L1 |
| **L1 cluster** | All 6 PoA validator Geth nodes (A, B, C, D, E, F) | L1 |
| **B** | Bravo-lane primary relay (one of the 6 ships) | L1 |
| **F** | Alpha-lane primary relay (one of the 6 ships) | L1 |
| **drone β** (off-chain client) | The single Bravo drone — only client of L2-B | drone-trust |
| **Madara β** | Starknet sequencer for L2-B | L2 |
| **Pathfinder** (β) | Starknet full-node + JSON-RPC for L2-B | L2 |
| **Orchestrator** (β) | Settlement orchestrator for L2-B | L2 |
| **SNOS** (β) | StarkNet OS — produces PIE traces from sealed blocks | L2 |
| **Stone** (β) | STARK prover — runs FRI over the PIE | L2 |
| **HVUs** (3) | Protected ships in the convoy interior | off-network |

**L1 contracts** (replicated state across all 6 Geth nodes):
- `Registry.sol` — mission specs + verdicts
- `Verifier.sol` — STARK proof FRI re-verification
- `CommandLog.sol` — advance command log

---

## Trust boundaries

Four boundary crossings. Every other call is intra-domain.

| # | Crossing | What gates it |
|---|---|---|
| 1 | **commander → L1** (step 1) | `secp256k1` ECDSA over the commander key + `onlyCommander` modifier |
| 2 | **L1 → L2** (step 4 dispatch) | TLS over the convoy radio link; relay key whitelisted on Madara |
| 3 | **drone → L2** (steps 5–6) | Stark-curve ECDSA via the OZ account contract on Madara; Cairo program enforces `SAFE_AREA` on the witness |
| 4 | **L2 → L1** (step 19 relay handoff) | Off-chain RPC over radio; **soundness rests on the on-chain FRI re-check inside step 21**, not on the relay's honesty |
| 5 | **L1 → L2** (step 24 advance bridge) | TLS over radio; same channel as step 4, opposite direction |

---

## Encoding conventions

| Quantity | Type | Encoding | Example |
|---|---|---|---|
| Coverage threshold | `uint16` | permille | `950` = ≥ 95.0 % cells |
| Detection threshold (`p_min`) | `uint16` | basis points | `7000` = `p_contact ≥ 0.7` |
| `p_contact` per cell | `uint16` | basis points | `0`–`10000` |
| Time window | `uint64` | seconds | `360` = 6 min |
| Cell index `(x, y)` | `uint16` × 2 | grid index | `(24, 17)` |
| Timestamp | `uint64` | unix seconds | `1700000010` |
| Mission id | `uint256` (L1) / `u128` (L2) | opaque | `EX-010` = 10, `EX-011` = 11 |
| Drone id | `uint256` (L1) / `felt252` (L2) | enum-like | `α` = 1, `β` = 2 |
| Sweep commitment hash `H_β` | `felt252` | `Poseidon(cells)` | — |
| Proof bytes `π_β` | `bytes` (L1) | Stone output | ~100–500 KB |

---

## Phase 1 — Mission deploy & L2 dispatch (steps 1–4)

### Step 1 — D writes the deploy tx

- **Self-action** on ship D
- **Endpoint signature**:
  ```solidity
  function deploy(MissionSpec spec)
      external
      onlyCommander
      returns (uint256 mid);
  ```
- **Payload**:
  - `spec.area_hash` — `bytes32` Poseidon hash of polygon vertices
  - `spec.coverage_min` — `uint16` permille (`950` = ≥ 95 % cells)
  - `spec.p_min` — `uint16` basis points (`7000` = `p_contact ≥ 0.7`)
  - `spec.time_window` — `uint64` seconds (`360` = 6 min)
- **Authentication**: `secp256k1` ECDSA, signed by D with the **commander
  key** (separate keystore entry from the regular ship key). The
  `onlyCommander` modifier on `Registry.deploy` checks
  `msg.sender == storedCommander`.
- **Trust boundary**: commander → L1 (no crossing — same actor, same
  domain; the commander key is the gate)
- **What happens**: D submits the deploy tx onto its own Geth node. The
  tx names mission `EX-011` (Bravo lane) and includes the full `MissionSpec`.

### Step 2 — PoA fan-out + Registry stores + emits `MissionDeployed`

- **Message**: D → L1 cluster (all 5 other ships)
- **Endpoint signature**:
  ```
  Clique PoA peer broadcast
    → Registry state write
    → emit MissionDeployed(mid, drone_id, spec)
  ```
- **Payload**:
  - `block N` — sealed PoA block including the deploy tx
  - `signer` — rotating among the 6 ship validators (EIP-225)
  - `state Δ` — Registry storage updated with `(mid → MissionSpec)`
  - `event MissionDeployed(uint256 indexed mid, uint256 indexed drone_id, MissionSpec spec)`
  - `drone_id` is **indexed** so off-chain subscribers (relay ships) can
    filter on it
- **Authentication**: `secp256k1` — block sealer signs the block header.
  Other validators verify against the pre-baked validator list in
  `genesis.json`.
- **Trust boundary**: L1 internal (no crossing)
- **What happens**: The deploy tx propagates to all 6 ships via Clique
  PoA peer fan-out. As the same block executes on every Geth node,
  `Registry.sol` stores the spec and emits `MissionDeployed`. After this
  block, A, B, C, D, E, F all see the same Registry state and event log.

### Step 3 — Event filter dispatches mission to relay (B for β, F for α)

- **Self-action** on ship B (with ship F highlighted in parallel)
- **Endpoint signature** (off-chain):
  ```
  web3.eth.subscribe("logs", {
    address: Registry,
    topics: [MissionDeployed, mid, drone_id]
  })
  ```
- **Payload**:
  - B's subscription: `topic[0]=MissionDeployed`, `topic[2]=β` →
    B's `onMission(spec)` handler runs
  - F's subscription: `topic[0]=MissionDeployed`, `topic[2]=α` →
    F's `onMission(spec)` handler runs
  - A, C, D, E: no relay subscription — observe only
  - Extracted: `mid + drone_id + MissionSpec` passed to the matching
    handler
- **Authentication**: No cryptographic auth on the read path — Geth's
  event log is local to each node. **The relay assignment is enforced by
  which `drone_id` each ship's orchestrator subscribes to** (configured
  in `orchestrator.toml` at deployment, not on-chain).
- **Trust boundary**: L1 internal (no crossing)
- **What happens**: The `emit` in step 2 fires every event subscription
  that matches. B is configured to listen for `drone_id == β` and F for
  `drone_id == α`; their orchestrator handlers run automatically. This
  is how the contract "tells" the relay ships they have a job to do —
  without any direct on-chain call to a specific ship. A, C, D, E have
  the same Registry state but no relay subscription, so nothing fires.

### Step 4 — Radio dispatch to L2 (B → L2-B, F → L2-A)

- **Message**: ship B → L2-B banner (parallel lane: ship F → L2-A banner)
- **Endpoint signature** (off-chain):
  ```
  POST /l2-{bravo|alpha}/admin/deploy_mission
  body: { spec, mid }   (over convoy radio link)
  ```
- **Payload**:
  - `spec` — `MissionSpec` relayed verbatim
  - `mid` — `uint256` same mission id as on L1 (`EX-010` for α, `EX-011`
    for β)
  - Bravo lane: `B → L2-B` with `mid = EX-011`
  - Alpha lane: `F → L2-A` with `mid = EX-010`
- **Authentication**: TLS + relay-to-L2 mutual auth. Ship B's relay key
  is whitelisted on Madara β; ship F's on Madara α. **Each relay is the
  only off-chain dispatcher for its lane** (per `orchestrator.toml`).
- **Trust boundary**: **L1 → L2 (radio handoff) — TRUST CROSSING**
- **What happens**: Both relay ships dispatch in parallel. B forwards
  `EX-011` to L2-B over the convoy radio link; F forwards `EX-010` to
  L2-A. Drones α and β now have their respective mission specs.
- **Parallel lane**: F → L2-A (mid = `EX-010`)

---

## Phase 2 — Drone sweep + commitment + block sealing (steps 5–7)

### Step 5 — `submit_telemetry(...)` × N (drone-signed)

- **Self-action** on Madara β (with parallel on Madara α). Logically the
  drone is the caller; visually we treat the call as Madara processing
  it because the drone is the L2's only client.
- **Endpoint signature** (Cairo on L2):
  ```cairo
  fn submit_telemetry(
      mission_id: u128,
      cells: Array<TelemetryCell>
  ) external
  ```
- **`TelemetryCell`** struct:
  - `x: u16`, `y: u16` — cell index in the area grid
  - `p_contact: u16` — basis points (max-prob hit observed in this cell,
    `0`–`10000`)
  - `ts: u64` — unix seconds
- **Payload (per call)**:
  - `mission_id` — same `mid` the dispatch carried
  - `cells: Array<TelemetryCell>` — one tx per cell, dozens per sweep
- **Authentication**: **Stark-curve ECDSA**. Drone β signs each L2 tx
  hash with its private key (`keystore/bravo.json`). The OpenZeppelin
  account contract on Madara recovers the public key and verifies it
  against its stored hash before letting the tx execute.
- **Trust boundary**: **drone → L2 — TRUST CROSSING**. Note that the
  signature only proves the drone *signed* the data, not that the data
  is *real*. A compromised drone could sign fake-low `p_contact` values.
  The actual `SAFE_AREA` enforcement happens later, inside the Cairo
  proof program (step 14).
- **What happens**: As drone β sweeps the right corridor, it sends one
  `submit_telemetry` tx per cell. Madara queues these into block N.
- **Parallel lane**: drone α calls `submit_telemetry` on Madara α with
  its own swept cells.

### Step 6 — `submit_sweep_commitment(mid, H_β)`

- **Self-action** on Madara β (parallel on Madara α with `H_α`)
- **Endpoint signature** (Cairo on L2):
  ```cairo
  fn submit_sweep_commitment(
      mission_id: u128,
      h: felt252
  ) external
  ```
- **Payload**:
  - `mission_id: u128`
  - `h: felt252` — `H_β = Poseidon(cells)` over all cells submitted in
    step 5
- **Authentication**: Stark-curve ECDSA — same signing path as
  `submit_telemetry`. **The Cairo contract recomputes Poseidon over the
  witness cells and reverts if `h ≠ Poseidon(cells)`.** The drone can't
  lie about the hash.
- **Trust boundary**: **drone → L2 — TRUST CROSSING**
- **What happens**: Drone β closes the sweep. After this call, the
  Cairo contract holds `H_β` in storage as the public commitment that
  will eventually land on L1 as part of the proof's public inputs.
- **Parallel lane**: drone α commits `H_α = Poseidon(α-cells)` on
  Madara α.

### Step 7 — Madara seals block N

- **Self-action** on Madara β (parallel on Madara α)
- **Endpoint signature**: internal — Madara sequencer block production
- **Payload**:
  - `block N` — sealed Starknet block (header + tx list)
  - `state diff` — includes the `H_β` storage write
- **Authentication**: Sequencer signs the block with its own Madara
  identity key. **No STARK is generated yet** — that happens in the
  orchestrator pipeline below.
- **Trust boundary**: L2 internal (no crossing)
- **What happens**: Madara β bundles the telemetry + commitment txs
  into block N, executes them, computes the state diff, seals.
- **Parallel lane**: Madara α seals its own block in parallel.

---

## Phase 3 — Indexing (step 8)

### Step 8 — Madara → Pathfinder feeder gateway sync

- **Message**: Madara β → Pathfinder β (parallel on alpha lane)
- **Endpoint signature** (HTTP):
  ```
  GET /feeder_gateway/get_block?blockNumber=N
  ```
- **Payload**:
  - `block` — sealed Starknet block N
  - `state_diff` — storage updates
- **Authentication**: No cryptographic auth — internal HTTP between L2
  services on the same Docker network.
- **Trust boundary**: L2 internal (no crossing)
- **What happens**: Pathfinder pulls block N from Madara, indexes it,
  exposes via Starknet JSON-RPC.

---

## Phase 4 — Proof-generation pipeline (steps 9–18)

All steps in this phase run inside the L2 docker network. No trust
crossings; soundness comes from the cryptographic gates inside SNOS
(step 14, Cairo VM constraint system) and Stone (step 17, FRI). All
mirror on the alpha lane.

### Step 9 — Orchestrator → Pathfinder: `starknet_getBlockWithTxs(N)`

- **Endpoint**: JSON-RPC `starknet_getBlockWithTxs({"block_number": N})`
- **Payload**: `block_number: u64`
- **What happens**: Orchestrator notices a block with a sweep commitment
  and pulls it from Pathfinder.

### Step 10 — Pathfinder → Orchestrator: `block + state_diff`

- **Payload**: header + tx list, `state_diff`, class hashes (contracts
  touched, needed for SNOS replay)
- **What happens**: Pathfinder returns everything SNOS will need.

### Step 11 — Orchestrator → SNOS: request proof input

- **Endpoint**: `snos.generate_pie(block, state_diff, class_hashes)`
- **What happens**: Orchestrator hands the block to SNOS and asks for a
  Cairo program input (PIE).

### Step 12 — SNOS → Pathfinder: state + receipts queries

- **Endpoint**: JSON-RPC: `starknet_getStateUpdate`,
  `starknet_getTransactionReceipt`, `starknet_call`
- **What happens**: SNOS needs more than the block — it queries
  Pathfinder for full state context.

### Step 13 — Pathfinder → SNOS: state + receipts

- **Payload**:
  - `state_update` — storage proof at block N-1
  - `receipts` — tx receipts for replay validation
  - `class defs` — Sierra/CASM class definitions

### Step 14 — SNOS replay (Cairo VM) — assert `SAFE_AREA`

- **Self-action** on SNOS (parallel on SNOS-α)
- **Endpoint**: `cairo_run(starknet_os.cairo, input=block + state)`
- **Payload outputs**:
  - execution trace — every Cairo opcode executed
  - memory access log — reads/writes for FRI proof generation
  - **PIE** — Program-Independent Executable
- **Authentication**: **The cryptographic gate is the Cairo VM
  constraint system itself.** If any constraint fails (e.g. `SAFE_AREA`
  assertion), the replay aborts and no PIE is produced.
- **What happens**: SNOS replays block N inside lambdaclass `cairo-vm`.
  The `SAFE_AREA` assertion in `safe_area_verify.cairo` runs here. If
  any of `{coverage ≥ 95%, time ≤ 360s, all p_contact < 7000}` fails,
  the replay aborts. **No proof can be generated for invalid telemetry.**

### Step 15 — SNOS → Orchestrator: PIE

- **Payload**: PIE struct + public_input (`mission_id`, `H_β`,
  `area_hash`, thresholds)

### Step 16 — Orchestrator → Stone: `prove(PIE + config)`

- **Endpoint**:
  ```
  stone-prover-cli prove --pie <pie.zip> --config <prover.json>
  ```
- **Payload**: PIE from step 15 + prover params (field, blowup, FRI
  queries, security level)

### Step 17 — Stone runs FRI → π_β (parallel: π_α)

- **Self-action** on Stone (parallel on Stone-α)
- **Endpoint**: internal Stone prover
- **Payload outputs**:
  - AIR encoding — Algebraic Intermediate Representation of Cairo VM trace
  - FRI commit phase — Reed-Solomon commitments to the trace polynomial
  - FRI query phase — random sampling, Merkle decommitments → yields π_β
- **Authentication**: **The cryptographic gate IS the proof.** STARK
  soundness rests on collision-resistance of the hash and the FRI
  argument; no trusted setup.
- **What happens**: Stone produces the STARK proof bytes plus public
  inputs.

### Step 18 — Stone → Orchestrator: π_β + public inputs

- **Payload**:
  - `π_β` — proof bytes (~100–500 KB)
  - `public_input` — `mid`, `H_β`, `area_hash`, thresholds, `drone_id=β`

---

## Phase 5 — Relay back to L1 + on-chain verification (steps 19–21)

### Step 19 — Orchestrator → ship B (radio)

- **Message**: Orchestrator → ship B (parallel: Orchestrator-α → ship F)
- **Endpoint signature** (off-chain):
  ```
  POST /relay/submit
  body: { proof: π_β, public_input, mid, drone_id=β }
  ```
- **Payload**:
  - `proof: bytes` — π_β
  - `public_input` — from step 18
  - `mid: uint256`
  - `drone_id: felt252` — β
- **Authentication**: Off-chain RPC over the convoy radio link. **The
  relay ship trusts the Orchestrator only insofar as it forwards
  whatever proof it receives** — soundness rests on the on-chain
  re-check (step 21), not on the relay's honesty.
- **Trust boundary**: **L2 → L1 (relay handoff) — TRUST CROSSING**
- **What happens**: Orchestrator hands the proof bundle to ship B. The
  proof leaves the L2 perimeter at this point.
- **Parallel lane**: Orchestrator-α → ship F with π_α.

### Step 20 — `submitProof(...)` tx (B for π_β, F for π_α)

- **Self-action** on ship B (parallel on ship F)
- **Endpoint signature** (Solidity on L1):
  ```solidity
  function submitProof(
      bytes proof,
      bytes32[] public_inputs,
      uint256 mid,
      uint256 drone_id
  ) external;
  ```
- **Payload**:
  - `proof (β)` — `bytes` π_β (signed by B)
  - `proof (α)` — `bytes` π_α (signed by F)
  - `public_inputs: bytes32[]` — recomputed from each proof's public input array
  - `mid: uint256` — `EX-011` for β, `EX-010` for α
  - `drone_id: uint256` — β or α
- **Authentication**: **`secp256k1` ECDSA** — each relay signs its own
  L1 tx envelope. B signs π_β's tx, F signs π_α's tx. The signature only
  authenticates "this ship submitted this tx" — proof correctness is
  checked by the contract logic, **not the signature**. **Relay ships
  are deliberately not trusted to vouch for proof validity.**
- **Trust boundary**: L1 internal (no crossing — the trust crossing was
  in step 19; from here on the proof is on the chain)
- **What happens**: In parallel, ship B writes its `submitProof` tx for
  π_β onto its Geth node, and ship F writes its `submitProof` tx for
  π_α onto its Geth node. Both call `Verifier.sol`.

### Step 21 — PoA fan-out → both proofs verify on-chain → verdicts written

- **Message**: ship B → L1 cluster (parallel: ship F → L1 cluster)
- **Endpoint**: Clique PoA peer broadcast
- **Payload**:
  - `block N+k` — sealed PoA block including B's `submitProof` tx
  - `block N+k+1` — sealed PoA block including F's `submitProof` tx
    (may be the same block if same signer slot)
- **Authentication**: `secp256k1` — block sealer signs the header. Same
  PoA fan-out as step 2.
- **Trust boundary**: L1 internal (no crossing)
- **What happens**: Both `submitProof` txs propagate to all 6 ships via
  Clique PoA. **As each block executes on every Geth in lockstep,
  `Verifier.submitProof` internally runs FRI re-verification (the
  cryptographic gate — invalid proofs revert here) and writes the SAFE
  verdict to Registry under `(mid, drone_id)`.** After this step,
  Registry holds `verdict[α] = SAFE` and `verdict[β] = SAFE` on every
  node. (FRI re-run + `setVerdict` happen as side-effects of the
  `submitProof` tx execution; no separate steps in this protocol.)

---

## Phase 6 — Commander activates advance (steps 22–23)

### Step 22 — D sees dual-SAFE → `advance(MAX_SPEED)` tx

- **Self-action** on ship D
- **Endpoint signature** (Solidity on L1):
  ```solidity
  function advance(uint256 speed)
      external
      onlyCommander;
  ```
- **Payload**:
  - `verdict_α: uint8` — `SAFE` (read from Registry by D's orchestrator)
  - `verdict_β: uint8` — `SAFE` (read from Registry by D's orchestrator)
  - `speed: uint256` — `MAX_SPEED` constant
- **Authentication**: **`secp256k1` ECDSA** — D signs the L1 tx with the
  **commander key** (separate keystore from the regular ship key). The
  `onlyCommander` modifier on `CommandLog.advance` checks
  `msg.sender == storedCommander`. **`CommandLog` also re-checks
  Registry to ensure dual-SAFE before accepting the call.**
- **Trust boundary**: L1 internal
- **What happens**: Ship D's orchestrator polls Registry. Once it sees
  both α and β verdicts SAFE for the same mission, D signs an
  `advance(MAX_SPEED)` tx with the commander key and writes it to its
  Geth node. **This is the explicit go-ahead from the commander; the
  contract refuses the call if either verdict is missing.** (Pattern B —
  D triggers; verifier does NOT auto-fire. See `docs/decisions/`.)

### Step 23 — PoA fan-out → CommandLog stores + emits ConvoyAdvance

- **Message**: D → L1 cluster
- **Endpoint signature**:
  ```
  Clique PoA peer broadcast
    → CommandLog.advance executes
    → emit ConvoyAdvance(block_number, speed, commander)
  ```
- **Payload**:
  - `block N+m` — sealed PoA block including D's advance tx
  - `state Δ` — `CommandLog` stores `(block_number, speed, commander)` record
  - `event ConvoyAdvance(uint256 indexed block_number, uint256 speed, address commander)`
- **Authentication**: `secp256k1` — block sealer signs the header. The
  advance tx itself was signed by D with the commander key.
  `CommandLog.advance` re-checks the `onlyCommander` modifier + dual-SAFE
  precondition before accepting.
- **Trust boundary**: L1 internal (no crossing)
- **What happens**: D's advance tx propagates to all 6 ships. As each
  Geth executes the tx, `CommandLog` stores the advance record and emits
  `ConvoyAdvance`. After this block, every ship's Geth has the same event
  log. (`CommandLog` storage write + event emission happen as
  side-effects of the advance tx execution; no separate steps.)

---

## Phase 7 — Radio bridge to drones (step 24)

### Step 24 — Radio advance to L2 drones (B → L2-B, F → L2-A)

- **Message**: ship B → L2-B banner (parallel: ship F → L2-A banner)
- **Endpoint signature** (off-chain):
  ```
  POST /l2-{bravo|alpha}/admin/advance
  body: { event: "ConvoyAdvance", block_number, speed }
  ```
- **Payload**:
  - `event: "ConvoyAdvance"`
  - `block_number: uint256` — L1 block where the advance was recorded
  - `speed: uint256` — `MAX_SPEED`
- **Authentication**: TLS + relay-to-L2 mutual auth (same channel as
  step 4, opposite direction). **No decision-making on B or F** — they
  are pure event-bridges (L1 event → radio frame). The decision was
  already made by D in step 22 and recorded on L1 in step 23.
- **Trust boundary**: **L1 → L2 (radio) — TRUST CROSSING**
- **What happens**: Final messages of the cycle. Both relays bridge the
  L1 advance event over radio to their L2 drones: B → L2-B (drone β),
  F → L2-A (drone α). A, C, D, E observe the same event in their L1
  event log but take no message-level action.

**Note on HVUs**: This protocol does NOT include a separate radio path
for HVUs. HVUs follow their escorts in formation; no separate command
channel is needed at the protocol level. (See `docs/decisions/`.)

---

## Mission lifecycle summary

| # | Phase | Sender | Receiver | Kind | Crossing | Brief |
|---|---|---|---|---|---|---|
| 1 | 1 | D | D | self | — | write `deploy(EX-011)` tx |
| 2 | 1 | D | L1 cluster | msg | — | PoA fan-out → Registry stores + emits `MissionDeployed` |
| 3 | 1 | B (also F) | self | self | — | event filter dispatches mission to relay |
| 4 | 1 | B (and F) | L2-B (and L2-A) | msg | ⚠ L1→L2 | radio dispatch of spec |
| 5 | 2 | drone β (and α) | Madara β (and α) | self | ⚠ drone→L2 | `submit_telemetry(...)` × N |
| 6 | 2 | drone β (and α) | Madara β (and α) | self | ⚠ drone→L2 | `submit_sweep_commitment(mid, H_β)` |
| 7 | 2 | Madara | Madara | self | — | seal block N |
| 8 | 3 | Madara | Pathfinder | msg | — | feeder gateway sync |
| 9 | 4 | Orch | Pathfinder | msg | — | `starknet_getBlockWithTxs(N)` |
| 10 | 4 | Pathfinder | Orch | msg | — | block + state_diff |
| 11 | 4 | Orch | SNOS | msg | — | request proof input |
| 12 | 4 | SNOS | Pathfinder | msg | — | state + receipts queries |
| 13 | 4 | Pathfinder | SNOS | msg | — | state + receipts |
| 14 | 4 | SNOS | SNOS | self | — | replay (Cairo VM) — assert `SAFE_AREA` |
| 15 | 4 | SNOS | Orch | msg | — | PIE |
| 16 | 4 | Orch | Stone | msg | — | send PIE + config |
| 17 | 4 | Stone | Stone | self | — | run FRI → π_β |
| 18 | 4 | Stone | Orch | msg | — | π_β + public inputs |
| 19 | 5 | Orch | ship B (and F) | msg | ⚠ L2→L1 | hand off π over radio |
| 20 | 5 | ship B (and F) | self | self | — | `submitProof(...)` tx |
| 21 | 5 | ship B (and F) | L1 cluster | msg | — | PoA fan-out → FRI re-run + verdict |
| 22 | 6 | D | D | self | — | `advance(MAX_SPEED)` tx |
| 23 | 6 | D | L1 cluster | msg | — | PoA fan-out → CommandLog + `ConvoyAdvance` |
| 24 | 7 | ship B (and F) | L2-B (and L2-A) | msg | ⚠ L1→L2 | radio advance to drones |

---

## Implementation cross-references

| Phase | Files | Tested by |
|---|---|---|
| L1 contracts (steps 1–3, 20–23) | `contracts/{Registry,Verifier,CommandLog}.sol` | Foundry tests in `tests/contracts/` |
| Cairo programs (steps 5, 6, 14) | `cairo/convoy_protocol.cairo`, `cairo/safe_area_verify.cairo` | `tests/cairo/` |
| Orchestrator pipeline (steps 9–18, 19) | `docker/l2-{alpha,bravo}/orchestrator.toml`, in-house Rust adaptation | `tests/orchestrator/` |
| Radio dispatch (steps 4, 24) | Off-chain Rust daemon on each relay ship | `tests/relay/` |
| Mission fixtures (canonical SAFE/UNSAFE cases) | `tests/fixtures/mission-cases.json` | All of the above |

---

## Versioning

This document is the **v1** of the protocol. Changes require:
1. Updating this file
2. Bumping the version header below
3. Updating `tests/fixtures/mission-cases.json` if encoding or call shapes
   change
4. Re-running the Phase 3 mission-replay smoke test against the change
5. Recording the rationale in `docs/decisions/`

**Protocol version: 1.0**
**Last updated: when this file lands in main.**

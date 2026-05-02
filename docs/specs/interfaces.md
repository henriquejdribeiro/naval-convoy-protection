# Interface contracts (data model)

> The contract between layers. Solidity follows the StarkWare
> **FactRegistry** pattern — the same base used by the production
> GPS Statement Verifier on Ethereum mainnet. Reference implementation:
> [`starkware-libs/starkex-contracts`](https://github.com/starkware-libs/starkex-contracts)
> (`evm-verifier/FactRegistry`, `MemoryPageFactRegistry`).
> Cairo 1 lives on the L2 as a Madara contract; Cairo 0 runs once per
> mission inside the Stone prover. Starknet protocol target throughout:
> **v0.14.1**.

## Layer split

```
                ┌─────────────────────────────────────┐
                │   L1 (Geth Clique PoA, 6 ships)    │
                │                                     │
                │   ConvoyProofVerifier.sol          │   ← extends StarkWare FactRegistry
                │   ConvoyMissionRegistry.sol        │
                │   ConvoyCommandLog.sol             │
                └──────────────┬──────────────────────┘
                               │ JSON-RPC (eth_*)
                               │ STARK fact submission
                               │
                ┌──────────────┴──────────────────────┐
                │   Orchestrator (Rust, off-chain)    │
                │   - polls Pathfinder for L2 blocks  │
                │   - drives SNOS → Stone pipeline    │
                │   - calls stark_evm_adapter         │
                │   - relays via primary ship's RPC   │
                └──────────────┬──────────────────────┘
                               │ JSON-RPC (starknet_*)
                               │
                ┌──────────────┴──────────────────────┐
                │   L2 (Madara α / β, one per swarm)  │
                │                                     │
                │   convoy_protocol.cairo (Cairo 1)   │   ← contract on L2
                │     fn submit_telemetry(...)        │
                │     fn submit_sweep_commitment(...) │
                │   ────────────────────────────────  │
                │   safe_area_verify.cairo (Cairo 0)  │   ← prover program
                │     PROVES: SAFE_AREA criterion     │
                └─────────────────────────────────────┘
```

The two Cairo dialects are not interchangeable:
- **Cairo 1** (Sierra → CASM) — runs on the Madara L2 as a smart contract; holds state, charges fees, has the `#[starknet::interface]` ABI machinery.
- **Cairo 0** (legacy, hint-based) — runs once per mission inside the **prover** to produce the STARK. Its output becomes the `outputHash` half of the L1 fact.

This dual-Cairo layout is forced by the StarkWare prover stack — Stone consumes Cairo 0 PIE traces, while Madara executes Cairo 1 contracts. Don't try to merge them.

---

## 1. Solidity contracts (L1)

### `ConvoyProofVerifier.sol`

Inherits StarkWare's [`FactRegistry`](https://github.com/starkware-libs/starkex-contracts) (the production base for the GPS Statement Verifier on mainnet) and OpenZeppelin's `Ownable` for access control.

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "starkware/solidity/components/FactRegistry.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ConvoyProofVerifier is FactRegistry, Ownable {

    /// One per verified mission proof (EX-010 or EX-011).
    struct ConvoySafeProof {
        bytes32 programHash;          // keccak256 of compiled safe_area_verify.cairo
        bytes32 outputHash;            // keccak256 of ABI-encoded program output
        uint256 missionId;             // EX-010 (Alpha) or EX-011 (Bravo)
        uint256 telemetryCommitment;   // Poseidon over per-cell telemetry
        uint256 coveragePermille;      // 0..1000 (e.g. 950 = 95.0 %)
        uint256 maxContact;            // 0..10000 (basis points; 7000 = p=0.7)
        uint256 elapsedSeconds;        // span between earliest and latest cell ts
        uint256 nCells;                // number of swept cells
        uint256 proofSize;             // STARK proof size in bytes
        uint256 nSteps;                // Cairo VM steps proven
        uint256 timestamp;             // L1 block timestamp at registration
        uint256 blockNumber;           // L1 block number at registration
        address relay;                 // ship that submitted the fact
    }

    ConvoySafeProof[] public proofs;
    mapping(uint256 => uint256) public proofByMission;  // missionId → proofs index + 1
    address public registry;
    address public commandLog;

    event MissionVerified(
        uint256 indexed proofId,
        uint256 indexed missionId,
        bytes32 indexed factHash,
        address relay,
        uint256 coveragePermille,
        uint256 maxContact,
        uint256 elapsedSeconds
    );

    constructor(address initialOwner, address _registry, address _commandLog) Ownable(initialOwner) {
        registry = _registry;
        commandLog = _commandLog;
    }

    /// Called by the relay ship after off-chain proof verification + adaptation.
    /// Pattern mirrors StarkWare's GPS verifier flow: proof checked off-chain,
    /// fact registered on-chain.
    function registerSafeProof(
        bytes32 programHash,
        bytes32 outputHash,
        ConvoySafeProof calldata meta
    ) external onlyOwner {
        bytes32 factHash = keccak256(abi.encodePacked(programHash, outputHash));
        registerFact(factHash);     // inherited from FactRegistry

        proofs.push(meta);
        proofByMission[meta.missionId] = proofs.length;  // 1-based; 0 = "not seen"

        emit MissionVerified(
            proofs.length - 1, meta.missionId, factHash,
            meta.relay, meta.coveragePermille, meta.maxContact, meta.elapsedSeconds
        );

        // Pattern A — auto-fire advance on dual SAFE.
        // Both EX-010 and EX-011 must have a registered, currently-valid fact.
        if (proofByMission[0xEX010] != 0 && proofByMission[0xEX011] != 0) {
            ConvoyCommandLog(commandLog).advance();
        }
    }
}
```

### `ConvoyMissionRegistry.sol`

Stores the immutable mission spec for each `EX-0xx`. Only D's commander key can deploy.

```solidity
contract ConvoyMissionRegistry is Ownable {
    struct MissionSpec {
        bytes32 areaPolygonHash;       // Poseidon hash of the area corner list
        uint256 coverageThresholdPermille;   // e.g. 950 = 95.0 %
        uint256 contactThresholdBps;          // e.g. 7000 = p=0.7
        uint256 timeWindowSeconds;            // e.g. 360
        uint256 deadlineBlock;                // mission expires after this L1 block
    }

    mapping(uint256 => MissionSpec) public specs;
    mapping(uint256 => bool) public deployed;

    event MissionDeployed(uint256 indexed missionId, MissionSpec spec, uint256 block);

    /// @dev onlyOwner = commander key (Ship D).
    function deploy(uint256 missionId, MissionSpec calldata spec) external onlyOwner {
        require(!deployed[missionId], "mission ID already used");
        specs[missionId] = spec;
        deployed[missionId] = true;
        emit MissionDeployed(missionId, spec, block.number);
    }
}
```

### `ConvoyCommandLog.sol`

Records advance events. Permits two senders: the `Verifier` (auto-fire path) and the commander key (manual override).

```solidity
contract ConvoyCommandLog {
    address public immutable verifier;
    address public immutable commander;

    event ConvoyAdvance(uint256 timestamp, uint256 indexed blockNumber, address indexed firedBy);

    constructor(address _verifier, address _commander) {
        verifier = _verifier;
        commander = _commander;
    }

    /// Called atomically by the Verifier on dual SAFE,
    /// or manually by D's commander key as override.
    function advance() external {
        require(msg.sender == verifier || msg.sender == commander, "unauthorised");
        emit ConvoyAdvance(block.timestamp, block.number, msg.sender);
    }
}
```

---

## 2. Cairo 1 contract on L2 — `convoy_protocol.cairo`

A standard `#[starknet::interface]` trait. `felt252` IDs (cheapest type
on Starknet, no range check needed). Entry points are shaped around the
**sweep-and-commit** flow — drones submit per-cell telemetry, the swarm's
lead drone publishes the Poseidon commitment over all of it.

```cairo
#[starknet::interface]
trait IConvoyProtocol<TContractState> {
    /// Drones submit one telemetry frame per swept cell.
    fn submit_telemetry(
        ref self: TContractState,
        drone_id: felt252,
        cell_id: u32,
        x: u8, y: u8,         // grid coords
        t: u32,                // seconds since mission deploy
        p_contact: u16,        // 0..10000 (bps)
        bearing: u16,          // 0..3599 (degrees × 10)
        signal: u8,            // sensor signal strength
        resweep: u8            // 0/1 — was this cell re-swept?
    );

    /// Once the swarm has finished, the lead drone submits the Poseidon
    /// commitment over all telemetry. The Cairo 0 prover program will
    /// later verify against this commitment.
    fn submit_sweep_commitment(
        ref self: TContractState,
        mission_id: felt252,         // EX-010 or EX-011
        commitment: felt252,         // Poseidon root over telemetry array
        n_cells: u32
    );

    // Read-only.
    fn get_commitment(self: @TContractState, mission_id: felt252) -> felt252;
    fn get_n_cells(self: @TContractState, mission_id: felt252) -> u32;
}
```

Storage layout:

```cairo
#[storage]
struct Storage {
    commitment_by_mission: LegacyMap<felt252, felt252>,
    n_cells_by_mission:    LegacyMap<felt252, u32>,
    telemetry_count:       LegacyMap<felt252, u32>,    // monotonic per drone
}
```

Per-cell telemetry encoding (the bytes the prover sees as input):

| Field | Type | Width (bits) | Range / Notes |
|---|---|---|---|
| `cell_id` | `u32` | 32 | encoded as `y * grid_w + x`; unique within a sweep |
| `x`, `y` | `u8`, `u8` | 8, 8 | grid coords; 0..(grid_dim − 1) |
| `t` | `u32` | 32 | seconds since `MissionDeployed.timestamp` |
| `p_contact` | `u16` | 16 | bps; 0..10000 |
| `bearing` | `u16` | 16 | degrees × 10; 0..3599 |
| `signal` | `u8` | 8 | 0..255 |
| `resweep` | `u8` | 8 | 0 or 1 |

One cell = 116 bits ≈ packed into **2 felts** (252-bit field) per cell. The
Poseidon hash chain over the cell array defines `telemetry_commitment`.

---

## 3. Cairo 0 prover program — `safe_area_verify.cairo`

Full pseudocode lives in [`cairo-safe-area.md`](./cairo-safe-area.md). The
public surface (what the prover commits to and what L1 sees) is:

**Public inputs (passed via the program's "output" segment, becomes part of `outputHash`):**

```
[
  mission_id                  // felt: EX-010 or EX-011
  area_polygon_hash           // felt: Poseidon over corners
  coverage_threshold_permille // felt: 950
  contact_threshold_bps       // felt: 7000
  time_window_seconds         // felt: 360
  telemetry_commitment        // felt: from L2 contract
  n_cells                     // felt
  // --- output values, one per assertion ---
  coverage_permille           // felt: actual coverage achieved
  max_contact_bps             // felt: max over all cells
  elapsed_seconds             // felt: latest_t - earliest_t
  safe                        // felt: 0 or 1
]
```

**Private witness (read via Cairo 0 `%{ ... %}` hints, never on chain):**

```
[
  cells: array<TelemetryCell>     // n_cells * 7 felts (per the layout above)
  total_cells_in_area: felt        // grid size of the polygon for coverage %
]
```

**Output schema** is what becomes `outputHash = keccak256(abi.encodePacked(...))` on L1. The Solidity verifier requires the program hash + output hash combination to match the registered fact — same pattern as StarkWare's GPS verifier.

---

## 4. Off-chain JSON-RPC contracts

No custom JSON-RPC. We use the standard methods provided by:

| Endpoint | Method | Used by |
|---|---|---|
| Geth (L1) | `eth_call`, `eth_sendRawTransaction`, `eth_getLogs`, `eth_subscribe(logs)` | Orchestrator (proof submission), commander (mission deploy), all ships (event watching) |
| Pathfinder (L2 RPC) | `starknet_getBlockWithTxs`, `starknet_getStateUpdate`, `starknet_call` | Orchestrator (block polling), drones (state queries) |
| Madara (L2 sequencer feeder gateway) | feeder gateway sync API | Pathfinder (block + state sync) |

All match Starknet protocol **v0.14.1** as pinned in [`versions.md`](../../versions.md).

---

## 5. Event sequencing (the wire-level contract between layers)

The exact order in which events appear on L1, and which sender produces them:

```
1. MissionDeployed(EX-010)          ← from D's commander key, via Registry.deploy()
2. MissionDeployed(EX-011)          ← same
3. … off-chain: drones sweep, L2 sequences telemetry, prover runs ...
4. MissionVerified(EX-010, …)       ← from F's relay key (or A as fallback)
5. MissionVerified(EX-011, …)       ← from B's relay key (or A as fallback)
6. ConvoyAdvance(…, firedBy=verifier) ← atomically with step 5, same tx
```

Steps 4 and 5 are independent — order between Alpha and Bravo doesn't
matter. Whichever arrives second is the one whose tx triggers the
`Verifier`'s atomic dual-SAFE check and the `CommandLog.advance()` call.

If the manual override path runs instead (D fires advance directly), step 6
is replaced by `ConvoyAdvance(…, firedBy=commander)` and the `verifier`
auto-call branch is skipped.

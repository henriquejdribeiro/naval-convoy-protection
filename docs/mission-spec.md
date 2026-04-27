# Mission specification

This document defines the two parallel reconnaissance missions that gate the convoy advance command. The mission Cairo programs (Phase 3) translate this specification into proof-system constraints; the L1 verifier contracts check the resulting STARK proofs against the published mission parameters.

## EX-010 — Left frontal area (Alpha drones, L2-Alpha)

| Parameter | Value | Encoding in Cairo |
|---|---|---|
| Mission ID | `EX-010` | felt252 |
| L2 chain | `L2-Alpha` (Madara α, chain_id `convoy_alpha_v1`) | — |
| Sweep pattern | Zig-zag area coverage (5 drones × 8 cells per drone × 2 axes = 80 telemetry felts per cycle) | array of `(x, y, t)` triples |
| Reference area | Polygon defined in `mission/ex010_alpha.json` | sequence of `(x, y)` corner felts, fixed at deploy |
| Coverage threshold | ≥ 95 % of cells visited within tolerance ε | comparison after summing visited-cell flags |
| Detection threshold | No contact reported with probability ≥ 0.7 | per-cell flag; assert all zero |
| Time window | ≤ 360 seconds total mission duration | `t_last − t_first ≤ 360` |
| Primary relay | Ship A or F (closest to left area) | encoded in deploy tx, not in the proof |

### Outcome

A mission concludes with `SAFE_AREA` if and only if all four numeric conditions pass inside `convoy_alpha_verify.cairo`. The proof attests these conditions held; the actual telemetry remains private.

## EX-011 — Right frontal area (Bravo drones, L2-Bravo)

| Parameter | Value | Encoding in Cairo |
|---|---|---|
| Mission ID | `EX-011` | felt252 |
| L2 chain | `L2-Bravo` (Madara β, chain_id `convoy_bravo_v1`) | — |
| Sweep pattern | Corridor (5 drones × 7 lengthwise points × 2 axes = 70 telemetry felts per cycle); width 2*a* | array of `(x, y, t)` triples |
| Reference corridor | Rectangle of width 2*a*, length defined in `mission/ex011_bravo.json` | corner felts |
| Coverage threshold | ≥ 95 % of corridor length traversed | as above |
| Detection threshold | No contact ≥ 0.7 probability | as above |
| Time window | ≤ 360 seconds | as above |
| Primary relay | Ship A or B (closest to right area) | — |

## Public vs private inputs

For both missions, the **public** inputs that flow into the L1 verifier contract are:

```
H_swarm        — Poseidon hash chain over all cell telemetry felts
mission_spec   — area polygon, coverage threshold, detection threshold, time window
relay_ship_id  — which ship submitted the L1 transaction
public_outcome — SAFE_AREA flag (boolean)
```

The **private witness** (visible only to the prover, never reaching L1) consists of:

```
telemetry[]    — full per-cell telemetry from all drones
sensor_logs[]  — sensor signatures (when Phase 4 hardware attestation lands)
random_seeds   — STARK blinding factors
```

## Two-of-two governance precondition

The `ConvoyMissionRegistry` contract on L1 maintains a struct per mission:

```solidity
struct MissionStatus {
    bytes32 commitment_H;       // public input from L2
    bool    safe_outcome;       // set to true after STARK verification passes
    address relay_ship;         // ship that submitted the proof tx
    uint256 verified_at_block;  // L1 block when verified
}
mapping(bytes32 => MissionStatus) public statuses;   // missionId → status
```

`ConvoyCommandLog.advance()` enforces:

```solidity
require(statuses["EX-010"].safe_outcome, "Left area not SAFE");
require(statuses["EX-011"].safe_outcome, "Right area not SAFE");
require(msg.sender == COMMANDER_SHIP_D, "Only commander can advance");
require(!alreadyAdvanced[currentMissionWindow], "Already issued");
emit ConvoyAdvance(currentMissionWindow, block.timestamp, "MAX_SPEED");
```

The contract guarantees the convoy advance command can only fire when both proofs have landed and only ship D's PoA-signed transaction can authorise it. Compromising any single ship cannot trigger a false advance; an attacker would need both a valid STARK proof for each L2 *and* control of ship D's PoA key.

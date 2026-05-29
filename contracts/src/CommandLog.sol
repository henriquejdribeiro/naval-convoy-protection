// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./Registry.sol";

/**
 * @title  CommandLog
 * @notice Records the convoy advance command. Pattern B — D explicitly
 *         triggers, the Verifier does NOT auto-fire.
 *
 * Two preconditions enforced on-chain when D calls `advance`:
 *   1. `msg.sender == commander` (the commander key, NOT D's validator key)
 *   2. Both the α-mission and the β-mission listed in the call must have
 *      `Registry.missionSafe[missionId] == true` — meaning ALL `nDrones`
 *      drones in each swarm have landed valid SAFE STARK proofs and the
 *      Verifier has written the mission-level aggregate (missionSafe +
 *      aggH). This is strictly stronger than the previous per-drone
 *      `verdict` check used in the 2-drone-per-swarm rev: a single drone
 *      passing is no longer enough — the whole 5-drone strip cover must
 *      be proved.
 *
 * The `commander` slot is set once at deployment and is **immutable**.
 * The protocol provides no on-chain rotation path: if the commander
 * key is lost or compromised, the entire contract suite must be
 * re-deployed. This is a deliberate fail-closed semantic chosen to
 * remove any administrative-vector attack on the highest-privilege
 * role; the convoy commits at deploy time to a single, unambiguous
 * authority for issuing the advance order.
 *
 * Emits `ConvoyAdvance` after a successful call. Event includes the L1
 * block where the advance was recorded — relay ships use this as the
 * "context" field when they bridge the advance over radio (replay-attack
 * defence).
 */
contract CommandLog {
    // ───────────────────────────────────────────────────────────────────
    //  External binding
    // ───────────────────────────────────────────────────────────────────
    Registry public immutable registry;
    /// @dev D's commander key, set once at deployment. No rotation path.
    address public immutable commander;

    // ───────────────────────────────────────────────────────────────────
    //  Stored advance records
    // ───────────────────────────────────────────────────────────────────
    struct AdvanceRecord {
        uint256 alphaMissionId;
        uint256 bravoMissionId;
        uint256 speed;
        uint256 blockNumber;
        uint256 timestamp;
        address commander;
    }

    AdvanceRecord[] public advances;

    // ───────────────────────────────────────────────────────────────────
    //  Events
    // ───────────────────────────────────────────────────────────────────
    event ConvoyAdvance(
        uint256 indexed blockNumber,
        uint256 indexed alphaMissionId,
        uint256 indexed bravoMissionId,
        uint256         speed,
        address         commander
    );

    // ───────────────────────────────────────────────────────────────────
    //  Modifiers
    // ───────────────────────────────────────────────────────────────────

    /// @dev Restricts a function to the commander key (ship D's
    ///      tactical-command signing key, distinct from D's validator
    ///      key). The single authority allowed to issue convoy advance.
    modifier onlyCommander() {
        require(msg.sender == commander, "CommandLog: onlyCommander");
        _;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Constructor
    // ───────────────────────────────────────────────────────────────────

    /**
     * @param registryAddr     Registry contract — read for dual-SAFE check
     * @param commanderAddress D's commander key (NOT D's validator key).
     *                         Set once and immutable; the protocol does
     *                         not provide a rotation path.
     */
    constructor(
        address registryAddr,
        address commanderAddress
    ) {
        require(registryAddr     != address(0), "CommandLog: registry = 0x0");
        require(commanderAddress != address(0), "CommandLog: commander = 0x0");
        registry  = Registry(registryAddr);
        commander = commanderAddress;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Core: advance the convoy (Pattern B — Phase 6 step 22 of protocol)
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Record the convoy advance. Reverts unless:
     *         (1) caller is the commander, and
     *         (2) Registry.missionSafe is true for BOTH alphaMissionId AND
     *             bravoMissionId — i.e. every drone in both swarms has
     *             landed a valid SAFE STARK proof and the Verifier has
     *             aggregated the per-drone commitments.
     *
     * @param alphaMissionId  α-swarm mission id (must be missionSafe == true)
     * @param bravoMissionId  β-swarm mission id (must be missionSafe == true)
     * @param speed           opaque speed value carried in the event
     *                        (convention: 100 = full ahead; any non-zero
     *                        uint256 is accepted)
     */
    function advance(uint256 alphaMissionId, uint256 bravoMissionId, uint256 speed)
        external
        onlyCommander
    {
        require(speed > 0, "CommandLog: speed must be > 0");

        // Dual-SAFE precondition — both swarms must have ALL nDrones drones
        // SAFE before the convoy may move. Re-checked on every node as the
        // tx executes; a single call to `isDualSafe` keeps the gas profile
        // close to the previous per-drone check.
        require(
            registry.isDualSafe(alphaMissionId, bravoMissionId),
            "CommandLog: dual-mission not SAFE"
        );

        // Record the advance
        advances.push(AdvanceRecord({
            alphaMissionId:    alphaMissionId,
            bravoMissionId:     bravoMissionId,
            speed:       speed,
            blockNumber: block.number,
            timestamp:   block.timestamp,
            commander:   msg.sender
        }));

        emit ConvoyAdvance(block.number, alphaMissionId, bravoMissionId, speed, msg.sender);
    }

    // ───────────────────────────────────────────────────────────────────
    //  Read helpers
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Number of convoy-advance orders ever recorded.
     * @dev    Useful as a quick sanity counter for front-ends and tests;
     *         each successful `advance()` increments by exactly one.
     * @return the length of the internal `advances[]` array
     */
    function advanceCount() external view returns (uint256) {
        return advances.length;
    }

    /**
     * @notice Read a specific advance record by index.
     * @dev    Records are append-only; `idx == 0` is the first ever
     *         advance. Reverts on out-of-range to surface index bugs
     *         rather than silently return an all-zero record.
     * @param  idx position in the `advances[]` array
     * @return the AdvanceRecord (alphaMissionId, bravoMissionId, speed, L1 block
     *         number, L1 timestamp, commander address)
     */
    function getAdvance(uint256 idx) external view returns (AdvanceRecord memory) {
        require(idx < advances.length, "CommandLog: invalid idx");
        return advances[idx];
    }
}

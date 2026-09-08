// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./Registry.sol";

/**
 * @title  CommandLog
 * @notice Records the convoy ADVANCE command. Pattern B: the commander (D)
 *         EXPLICITLY triggers advance() — the Verifier does NOT auto-fire.
 *         The on-chain check GATES the advance (both swarms must be SAFE), but a
 *         human commander gives the final order. Machine verifies; human commands.
 *
 * advance() preconditions:
 *   1. msg.sender == commander (commander key, NOT D's validator key)
 *   2. Registry.missionSafe == true for BOTH α and β (via isDualSafe)
 *   NOTE: missionSafe is set from the aggregate L2→L1 message
 *   (aggH == 0).
 *
 * commander is immutable — no rotation path (fail-closed): lost/compromised key
 * ⇒ redeploy the whole suite. Deliberate: removes any admin attack vector on the
 * top authority.
 *
 * Emits `ConvoyAdvance` after a successful call. Event includes the L1
 * block where the advance was recorded — relay ships use this as the
 * "context" field when they bridge the advance over radio (replay-attack
 * defence).
 */
contract CommandLog {  // ← NOT Ownable (simplest L1 contract)
    // ───────────────────────────────────────────────────────────────────
    //  External binding
    // ───────────────────────────────────────────────────────────────────

    Registry public immutable registry; // for isDualSafe()

    /// @dev D's commander key, set once at deployment. No rotation path.
    address public immutable commander; // the advance authority

    // ───────────────────────────────────────────────────────────────────
    //  Stored advance records
    //
    //  One AdvanceRecord is written per advance() call: a permanent, immutable,
    //  auditable entry answering who / what / when / under-what-verification.
    // ───────────────────────────────────────────────────────────────────
    struct AdvanceRecord {
        uint256 alphaMissionId;  // ┐ UNDER WHAT verification —
        uint256 bravoMissionId;  // ┘ the two missions that were SAFE to gate this advance
        uint256 speed;           //   WHAT was ordered — the convoy's advance speed
        uint256 blockNumber;     // ┐ WHEN — L1 block height (+ replay-defence context)
        uint256 timestamp;       // ┘ WHEN — wall-clock (block.timestamp)
        address commander;       //   WHO — the authority that issued the order
    }

    AdvanceRecord[] public advances;

    // ───────────────────────────────────────────────────────────────────
    //  Events
    // ───────────────────────────────────────────────────────────────────

    /// @notice THE system's final output: the convoy is cleared and ordered to
    ///         advance. Relay ships watch for this and broadcast the order to the
    ///         fleet over radio; blockNumber is the replay-defence "context".
    ///         Mirrors the stored AdvanceRecord.
    ///         3 indexed topics: blockNumber (replay context) + both mission ids
    ///         (filter by mission). speed/commander are data.
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
        // Fail fast: both become immutable → 0x0 would brick the contract.
        require(registryAddr     != address(0), "CommandLog: registry = 0x0");
        require(commanderAddress != address(0), "CommandLog: commander = 0x0");
        registry  = Registry(registryAddr);  // cast to typed handle (for isDualSafe)
        commander = commanderAddress;        // already an address, no cast
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
        require(speed > 0, "CommandLog: speed must be > 0"); // 100 = full ahead; any non-zero ok

        // Dual-SAFE precondition — both swarms must have ALL nDrones drones
        // SAFE before the convoy may move. Re-checked on every node as the
        // tx executes; a single call to `isDualSafe` keeps the gas profile
        // close to the previous per-drone check.
        require(
            registry.isDualSafe(alphaMissionId, bravoMissionId),
            "CommandLog: dual-mission not SAFE"
        );

        // Permanent audit record of the order (who/what/when/under-what-verification).
        advances.push(AdvanceRecord({
            alphaMissionId:    alphaMissionId,
            bravoMissionId:     bravoMissionId,
            speed:       speed,
            blockNumber: block.number,
            timestamp:   block.timestamp,
            commander:   msg.sender
        }));

        // Final signal: relay ships broadcast this to the fleet (block.number = replay context).
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

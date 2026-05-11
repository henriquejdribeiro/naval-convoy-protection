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
 *      `Registry.verdict[missionId][droneId] == true` (dual-SAFE)
 *
 * The contract also retains a manual override path: if the commander
 * key is ever rotated (lost or compromised key recovery scenario), the
 * owner can update the `commander` slot. This mirrors the role
 * separation D has on the validator side (regular ship key for sealing,
 * commander key for issuing commands).
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
    address  public           commander;       // D's commander key
    address  public           owner;           // operational owner (rotates commander)

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
    event CommanderRotated(address indexed previous, address indexed current);

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

    /// @dev Restricts a function to the operational owner. Owner power
    ///      is limited to commander-key rotation (key-loss / compromise
    ///      recovery); the owner cannot issue an advance themselves.
    modifier onlyOwner() {
        require(msg.sender == owner, "CommandLog: onlyOwner");
        _;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Constructor
    // ───────────────────────────────────────────────────────────────────

    /**
     * @param initialOwner     operational owner (can rotate commander)
     * @param registryAddr     Registry contract — read for dual-SAFE check
     * @param commanderAddress D's commander key (NOT D's validator key)
     */
    constructor(
        address initialOwner,
        address registryAddr,
        address commanderAddress
    ) {
        require(initialOwner     != address(0), "CommandLog: owner = 0x0");
        require(registryAddr     != address(0), "CommandLog: registry = 0x0");
        require(commanderAddress != address(0), "CommandLog: commander = 0x0");
        owner     = initialOwner;
        registry  = Registry(registryAddr);
        commander = commanderAddress;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Operational: rotate the commander address
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Replace the commander key. Owner-only — used when the
     *         existing commander key is lost, suspected compromised, or
     *         the tactical-command role is transferred to another ship.
     * @dev    Emits CommanderRotated for off-chain auditing. The new
     *         commander takes effect immediately on the next
     *         `advance()` call.
     * @param  newCommander the new commander key's L1 address
     */
    function rotateCommander(address newCommander) external onlyOwner {
        require(newCommander != address(0), "CommandLog: commander = 0x0");
        emit CommanderRotated(commander, newCommander);
        commander = newCommander;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Core: advance the convoy (Pattern B — Phase 6 step 22 of protocol)
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Record the convoy advance. Reverts unless:
     *         (1) caller is the commander, and
     *         (2) Registry.verdict is SAFE for both (alphaMissionId, α) AND (bravoMissionId, β).
     *
     * @param alphaMissionId  α-lane mission id whose verdict must be SAFE
     * @param bravoMissionId   β-lane mission id whose verdict must be SAFE
     * @param speed     opaque speed value carried in the event (convention: 100 = full ahead; any non-zero uint256 is accepted)
     */
    function advance(uint256 alphaMissionId, uint256 bravoMissionId, uint256 speed)
        external
        onlyCommander
    {
        require(speed > 0, "CommandLog: speed must be > 0");

        // Dual-SAFE precondition (re-checked on every Geth as the tx executes)
        require(
            registry.verdict(alphaMissionId, registry.DRONE_ALPHA()),
            "CommandLog: alpha not SAFE"
        );
        require(
            registry.verdict(bravoMissionId, registry.DRONE_BRAVO()),
            "CommandLog: bravo not SAFE"
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

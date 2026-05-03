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
 *      `Registry.verdict[mid][droneId] == true` (dual-SAFE)
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
        uint256 alphaMid;
        uint256 betaMid;
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
        uint256 indexed alphaMid,
        uint256 indexed betaMid,
        uint256         speed,
        address         commander
    );
    event CommanderRotated(address indexed previous, address indexed current);

    // ───────────────────────────────────────────────────────────────────
    //  Modifiers
    // ───────────────────────────────────────────────────────────────────
    modifier onlyCommander() {
        require(msg.sender == commander, "CommandLog: onlyCommander");
        _;
    }

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
     *         (2) Registry.verdict is SAFE for both (alphaMid, α) AND (betaMid, β).
     *
     * @param alphaMid  α-lane mission id whose verdict must be SAFE
     * @param betaMid   β-lane mission id whose verdict must be SAFE
     * @param speed     opaque speed value carried in the event (convention: 100 = full ahead; any non-zero uint256 is accepted)
     */
    function advance(uint256 alphaMid, uint256 betaMid, uint256 speed)
        external
        onlyCommander
    {
        require(speed > 0, "CommandLog: speed must be > 0");

        // Dual-SAFE precondition (re-checked on every Geth as the tx executes)
        require(
            registry.verdict(alphaMid, registry.DRONE_ALPHA()),
            "CommandLog: alpha not SAFE"
        );
        require(
            registry.verdict(betaMid, registry.DRONE_BRAVO()),
            "CommandLog: beta not SAFE"
        );

        // Record the advance
        advances.push(AdvanceRecord({
            alphaMid:    alphaMid,
            betaMid:     betaMid,
            speed:       speed,
            blockNumber: block.number,
            timestamp:   block.timestamp,
            commander:   msg.sender
        }));

        emit ConvoyAdvance(block.number, alphaMid, betaMid, speed, msg.sender);
    }

    // ───────────────────────────────────────────────────────────────────
    //  Read helpers
    // ───────────────────────────────────────────────────────────────────
    function advanceCount() external view returns (uint256) {
        return advances.length;
    }

    function getAdvance(uint256 idx) external view returns (AdvanceRecord memory) {
        require(idx < advances.length, "CommandLog: invalid idx");
        return advances[idx];
    }
}

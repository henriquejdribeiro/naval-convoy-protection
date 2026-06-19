// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./Registry.sol";

/// Minimal interface to StarknetCoreStub's L2 → L1 consumption side.
/// Real `StarknetMessaging.sol` exposes the same signature.
interface IStarknetMessagingConsumer {
    function consumeMessageFromL2(
        uint256          fromAddress,
        uint256[] calldata payload
    ) external returns (bytes32 msgHash);
}

/**
 * @title  Verifier
 * @notice L1 endpoint that consumes the "all drones SAFE" message a swarm's
 *         L2 convoy_protocol emits when its 5th drone lands SAFE.
 *
 * # Architecture (rev 2026-06, raw-telemetry-on-L2)
 *
 * The previous Verifier was the L1 endpoint of the per-drone-STARK-proof
 * flow — it accepted 11-field SafeProofInputs structs, recomputed factHash,
 * checked GpsStatementVerifier.isValid, and aggregated per-drone Pedersen
 * commitments. That entire pipeline was retired when telemetry moved to L2
 * (commit 4fa6ad4): predicates now run inside `convoy_protocol.cairo`
 * directly against the raw cells, and the only cross-chain signal is one
 * L2 → L1 message per swarm containing `[mission_id, n_drones]`.
 *
 * # What this contract does
 *
 *   1. Consume the L2 → L1 message via StarknetCoreStub.consumeMessageFromL2
 *      (hash binds msg.sender, so only this Verifier address can claim
 *      messages addressed to it from a swarm's convoy_protocol)
 *   2. Sanity-check the payload and the L2 sender (must match the
 *      convoy_protocol address bound for that mission_id via
 *      setConvoyProtocolL2)
 *   3. Call Registry.setMissionSafe(missionId, bytes32(0))
 *      - aggH is bytes32(0) because the new design no longer aggregates
 *        per-drone commitments at the application layer (cells are public
 *        on L2; the audit trail is the L2 chain history). The Registry
 *        kept the aggH field for ABI continuity; we just pass zero.
 *
 * # The advance gate (unchanged)
 *
 *   - Registry.missionSafe[1] = true  ← consumed alpha message
 *   - Registry.missionSafe[2] = true  ← consumed bravo message
 *   - CommandLog.advance(1, 2, speed) reads Registry.isDualSafe and lets
 *     the commander emit ConvoyAdvance — unchanged from the previous rev.
 */
contract Verifier is Ownable {
    // ───────────────────────────────────────────────────────────────────
    //  Immutable bindings
    // ───────────────────────────────────────────────────────────────────
    Registry                   public immutable registry;
    IStarknetMessagingConsumer public immutable starknetCore;

    // ───────────────────────────────────────────────────────────────────
    //  Storage
    //
    //  `expectedL2Sender[missionId]` is the L2 convoy_protocol contract
    //  address for that mission — i.e. the only L2 contract authorised
    //  to emit the "all-SAFE" message for that mission. Different per
    //  swarm because alpha and bravo deploy on different Madara chains
    //  (different chain_ids → different addresses for the same source).
    // ───────────────────────────────────────────────────────────────────
    mapping(uint256 => uint256) public expectedL2Sender;

    // ───────────────────────────────────────────────────────────────────
    //  Events
    // ───────────────────────────────────────────────────────────────────
    event ConvoyProtocolL2Bound(uint256 indexed missionId, uint256 l2Sender);
    event MissionSafeConsumed(
        uint256 indexed missionId,
        uint8           nDrones,
        bytes32         msgHash
    );

    // ───────────────────────────────────────────────────────────────────
    //  Constructor
    // ───────────────────────────────────────────────────────────────────

    /**
     * @param initialOwner       address that may bind convoy_protocol
     *                           addresses per mission (deploy-time wiring)
     * @param registryAddr       L1 Registry contract — Verifier writes
     *                           setMissionSafe on it
     * @param starknetCoreAddr   StarknetCoreStub (dev) / StarknetMessaging
     *                           (mainnet) — Verifier claims L2 messages here
     */
    constructor(
        address initialOwner,
        address registryAddr,
        address starknetCoreAddr
    ) Ownable(initialOwner) {
        require(registryAddr     != address(0), "Verifier: registry = 0x0");
        require(starknetCoreAddr != address(0), "Verifier: starknetCore = 0x0");
        registry     = Registry(registryAddr);
        starknetCore = IStarknetMessagingConsumer(starknetCoreAddr);
    }

    // ───────────────────────────────────────────────────────────────────
    //  Owner-only wiring
    // ───────────────────────────────────────────────────────────────────

    /// @notice Bind a mission-id to its L2 convoy_protocol contract address.
    /// @dev    Owner-only because the L2 address comes from `deploy-l2.sh`
    ///         output, not known at construction time. Set this for each
    ///         mission BEFORE the first consumeL2Message call, otherwise
    ///         consume will revert with "Verifier: L2 sender not bound".
    function setConvoyProtocolL2(uint256 missionId, uint256 l2Sender) external onlyOwner {
        require(l2Sender != 0, "Verifier: l2Sender = 0");
        expectedL2Sender[missionId] = l2Sender;
        emit ConvoyProtocolL2Bound(missionId, l2Sender);
    }

    // ───────────────────────────────────────────────────────────────────
    //  L2 → L1 message consumption
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Claim one queued L2 → L1 "MissionSafe" message and propagate
     *         the verdict to Registry. Callable by anyone — the security
     *         property is that StarknetCoreStub.consumeMessageFromL2's
     *         hash binds `msg.sender` to this Verifier address, so only
     *         a message that the L2 explicitly addressed here can be
     *         consumed. The payload's mission_id is then matched against
     *         the configured L2 sender for that mission.
     *
     * @param fromAddress L2 convoy_protocol address that emitted the message
     * @param payload     Exactly [mission_id, n_drones]
     */
    function consumeL2Message(
        uint256          fromAddress,
        uint256[] calldata payload
    ) external {
        require(payload.length == 2, "Verifier: bad payload length");

        uint256 missionId = payload[0];
        uint256 nDrones   = payload[1];

        require(expectedL2Sender[missionId] == fromAddress,
                "Verifier: L2 sender not bound or wrong");

        // Cross-check drone count against L1 Registry spec (defence in
        // depth: catches a corrupted L2 sending a wrong nDrones).
        Registry.MissionSpec memory spec = registry.getSpec(missionId);
        require(nDrones == uint256(spec.nDrones),
                "Verifier: drone-count mismatch");

        // Claim the message — reverts if not queued (gap 1: queue is empty
        // until updateState or injectL2Message populates it).
        bytes32 msgHash = starknetCore.consumeMessageFromL2(fromAddress, payload);

        // Flip the mission-level aggregate on Registry. aggH is bytes32(0)
        // in the new design — cells are public on L2; the audit trail is
        // the L2 chain history, not an on-L1 Pedersen aggregate.
        registry.setMissionSafe(missionId, bytes32(0));

        // Cast is safe — we required `nDrones == spec.nDrones` above and
        // spec.nDrones is already uint8 (max value 255).
        // forge-lint: disable-next-line(unsafe-typecast)
        emit MissionSafeConsumed(missionId, uint8(nDrones), msgHash);
    }
}

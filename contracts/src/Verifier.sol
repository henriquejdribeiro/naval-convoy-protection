// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;   // same as all convoy contracts; NOTE: real StarkWare
                           // contracts are 0.6.12 — hence the interface below.

import "@openzeppelin/contracts/access/Ownable.sol"; // Verifier is Ownable (owner-only
                                                    // wiring: setConvoyProtocolL2)

import "./Registry.sol"; // DIRECT import — Verifier calls Registry.setMissionSafe/getSpec.
                        // Fine because both are ^0.8.20 (unlike the Core).

/// Minimal, self-declared interface to the Core's L2→L1 consume function.
/// Only ONE function is needed, so we declare only that. Talking to the Core
/// through THIS interface (by address, not by import) decouples the Verifier
/// from the concrete Core: it works against StarknetCoreStub in dev and the
/// real Starknet.sol in prod, UNCHANGED — the 0.6.12/0.8.20 version skew is
/// irrelevant because an interface is an ABI shape, not code. Swapping to the
/// real bridge = just repoint the Core address; this stays identical.
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
 * Predicates run inside `convoy_protocol.cairo`
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
contract Verifier is Ownable {  // Ownable → owner does the deploy-time wiring (setConvoyProtocolL2)

    // ───────────────────────────────────────────────────────────────────
    //  Immutable bindings
    //
    //  The two contracts this Verifier talks to, LOCKED at deployment ──
    //  immutable = set once in constructor, baked into bytecode (cheap reads,
    //  and un-repointable → the trust anchors can never be swapped).
    // ───────────────────────────────────────────────────────────────────
    Registry                   public immutable registry;           // typed import; calls setMissionSafe/getSpec
    IStarknetMessagingConsumer public immutable starknetCore;       // INTERFACE type → Core-agnostic.

    // ───────────────────────────────────────────────────────────────────
    //  Storage
    //
    // mission_id → the L2 convoy_protocol address allowed to emit that mission's
    // all-SAFE message. Per-mission because alpha/bravo run on different Madara
    // chains (different chain_id → different address). uint256, not address,
    // because it's an L2 (felt) address. This is security layer 2: only the
    // REGISTERED L2 sender's message is accepted (layer 1 is the Core binding
    // msg.sender to this Verifier). Set by setConvoyProtocolL2 (owner-only).
    // ───────────────────────────────────────────────────────────────────
    mapping(uint256 => uint256) public expectedL2Sender;

    // ───────────────────────────────────────────────────────────────────
    //  Events — audit trail for the two things this contract does:
    //  (1) get wired to a swarm's L2 sender, and (2) consume its verdict.
    // ───────────────────────────────────────────────────────────────────
    
    /// @notice Emitted by `setConvoyProtocolL2` when a mission is bound to the
    ///         L2 convoy_protocol address allowed to emit its all-SAFE message.
    ///         This is deploy-time wiring (register-missions step 1b) — the
    ///         on-chain record of which L2 sender is trusted for this mission.
    /// @param  missionId Mission being wired (indexed so you can filter by mission).
    /// @param  l2Sender  The L2 convoy_protocol contract address (a felt, hence
    ///                   uint256) now authorised as this mission's sole sender.
    event ConvoyProtocolL2Bound(uint256 indexed missionId, uint256 l2Sender);

    /// @notice Emitted by `consumeL2Message` when a swarm's "all drones SAFE"
    ///         verdict is successfully claimed on L1 (right before Registry.
    ///         setMissionSafe flips the mission safe). The proof-of-delivery
    ///         that the L2→L1 message crossed and was accepted.
    /// @param  missionId Mission whose verdict was consumed (indexed for filtering).
    /// @param  nDrones   Drone count carried in the message payload (= the swarm's
    ///                   n_drones; cross-checked against the Registry spec).
    /// @param  msgHash   Hash returned by StarknetCore.consumeMessageFromL2 —
    ///                   uniquely identifies the exact message consumed, for
    ///                   traceability / replay auditing.
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
    ) Ownable(initialOwner) {  // set the owner via the parent constructor
        // Fail fast: these become immutable, so a 0x0 here would brick the
        // contract permanently. Reject at deploy rather than ship a dead Verifier.
        require(registryAddr     != address(0), "Verifier: registry = 0x0");
        require(starknetCoreAddr != address(0), "Verifier: starknetCore = 0x0");

        // Cast raw addresses to typed handles (compile-time only, no runtime
        // check). starknetCore uses the INTERFACE type → Core-agnostic. These
        // assign the immutables: the one and only place they can be set.
        registry     = Registry(registryAddr);
        starknetCore = IStarknetMessagingConsumer(starknetCoreAddr);
    }

    // ───────────────────────────────────────────────────────────────────
    //  Owner-only wiring
    // ───────────────────────────────────────────────────────────────────

    /// @notice Bind a mission to the ONE L2 convoy_protocol address whose
    ///         all-SAFE message this Verifier will accept (security layer 2,
    ///         checked in consumeL2Message against the message's fromAddress).
    /// @dev    Separate from the constructor because the L2 address only exists
    ///         AFTER deploy-l2.sh runs — L1 is deployed first. This is
    ///         register-missions step 1b. Must run BEFORE the first consume, or
    ///         consume reverts "L2 sender not bound or wrong".
    ///
    ///         onlyOwner is load-bearing: whoever can call this decides which L2
    ///         contract is trusted for a mission — an unrestricted version would
    ///         let anyone rebind to a malicious L2 and forge verdicts.
    ///
    ///         NOTE (hardening): no re-bind guard — the owner can overwrite a
    ///         mission's sender at any time. Flexible, but it centralises the
    ///         L2→L1 trust anchor in the owner key. Production: immutable-after-set
    ///         or a multisig/timelock owner.
    function setConvoyProtocolL2(uint256 missionId, uint256 l2Sender) external onlyOwner {
        require(l2Sender != 0, "Verifier: l2Sender = 0");        // reject invalid/empty binding
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
        // Shape check.
        require(payload.length == 2, "Verifier: bad payload length");

        uint256 missionId = payload[0];
        uint256 nDrones   = payload[1];

        // Layer 2: message must come from the REGISTERED L2 sender for this mission.
        require(expectedL2Sender[missionId] == fromAddress,
                "Verifier: L2 sender not bound or wrong");

        // Layer 3: drone count in the message must match the L1 Registry spec
        // (defence in depth against a corrupted L2).
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

// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title  StarknetCoreStub
 * @notice Minimal stub of the Starknet Core contract that Madara checks for
 *         on startup. Implements just enough of the surface area to satisfy
 *         the sequencer and the L1↔L2 message queue. Replace with the full
 *         Starknet.sol once multi-version solc compilation is set up
 *         (production GPS/Starknet contracts target Solidity 0.6.12).
 *
 * Roles in the convoy protocol:
 *   - Madara reads `stateBlockNumber()`, `stateRoot()`, `stateBlockHash()`,
 *     and `identify()` on startup to confirm the L1 settlement contract is
 *     reachable.
 *   - The orchestrator daemon calls `updateState(...)` after each L2 block
 *     it settles (Phase 3+). For Phase 2 (hardcoded facts), this stays at
 *     genesis values.
 *   - `sendMessageToL2(...)` is the L1 → L2 message hook. The convoy
 *     protocol does NOT use it for the core flow (Pattern B uses radio
 *     dispatch via the relay ships, not the bridge), but Madara's startup
 *     checks expect the function to exist.
 *
 * Pattern matches the StarkWare reference implementation; the surface here
 * is the minimum needed to bring up Madara devnet and is NOT a full
 * settlement contract. See the StarkWare `Starknet.sol` for the production
 * version with proof verification, state diffs, and message timeouts.
 */
contract StarknetCoreStub {
    // ───────────────────────────────────────────────────────────────────
    //  State (read by Madara on startup + after each settlement round)
    //
    //  All three slots are public, so Solidity auto-generates an
    //  external view getter for each. The orchestrator (and any
    //  off-chain observer) reads them to learn the L1-anchored view
    //  of L2 state:
    //
    //    stateRoot         — Patricia trie root of L2 storage after the
    //                        most-recently-settled block.
    //    stateBlockNumber  — int256 to allow the StarkWare convention
    //                        of -1 = "no L2 block settled yet" (i.e.
    //                        pre-genesis). Increases monotonically as
    //                        the orchestrator settles each block.
    //    stateBlockHash    — Poseidon block hash of the
    //                        most-recently-settled L2 block. Together
    //                        with `stateBlockNumber` it uniquely
    //                        identifies the settled chain head.
    // ───────────────────────────────────────────────────────────────────
    uint256 public stateRoot;
    int256  public stateBlockNumber;
    uint256 public stateBlockHash;

    // ───────────────────────────────────────────────────────────────────
    //  L1 ↔ L2 message tracking (kept as a queue for Madara compatibility)
    // ───────────────────────────────────────────────────────────────────
    mapping(bytes32 => uint256) public l1ToL2Messages;
    mapping(bytes32 => uint256) public l2ToL1Messages;

    // ───────────────────────────────────────────────────────────────────
    //  Events
    // ───────────────────────────────────────────────────────────────────
    event LogStateUpdate(uint256 globalRoot, int256 blockNumber, uint256 blockHash);
    event LogMessageToL2(
        address indexed fromAddress,
        uint256 indexed toAddress,
        uint256 indexed selector,
        uint256[]       payload,
        uint256         nonce,
        uint256         fee
    );
    /// @notice Emitted by `consumeMessageFromL2` when an L1 contract
    ///         successfully claims a message queued from L2.
    /// @param  fromAddress L2 sender (the convoy_protocol address that
    ///                     called `send_message_to_l1_syscall`)
    /// @param  toAddress   L1 consumer (msg.sender of consumeMessageFromL2)
    /// @param  payload     The arbitrary felt array L2 attached to the
    ///                     message — for the convoy flow this is
    ///                     `[mission_id, n_drones]`.
    event ConsumedMessageToL1(
        uint256 indexed fromAddress,
        address indexed toAddress,
        uint256[]       payload
    );

    // ───────────────────────────────────────────────────────────────────
    //  Madara startup checks
    // ───────────────────────────────────────────────────────────────────

    /// @notice Identifier string Madara checks against during startup.
    function identify() external pure returns (string memory) {
        return "StarkWare_Starknet_2025_10";
    }

    // ───────────────────────────────────────────────────────────────────
    //  State settlement (called by the orchestrator post-Phase 3)
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Update L2 state — called by the orchestrator after each L2
     *         block is settled.
     * @dev    For Phase 2 this is unused; Phase 3 wires the orchestrator
     *         daemon to call this after each successful proof verification.
     */
    function updateState(
        uint256 globalRoot_,
        int256  blockNumber_,
        uint256 blockHash_
    ) external {
        stateRoot        = globalRoot_;
        stateBlockNumber = blockNumber_;
        stateBlockHash   = blockHash_;
        emit LogStateUpdate(globalRoot_, blockNumber_, blockHash_);
    }

    // ───────────────────────────────────────────────────────────────────
    //  L1 → L2 message bridge
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Queue an L1 → L2 message (Madara consumes the queue).
     * @dev    NOT used by the convoy protocol's main flow — relay ships
     *         dispatch over radio, not via this bridge. Kept for Madara
     *         compatibility and future extensibility.
     */
    function sendMessageToL2(
        uint256          toAddress,
        uint256          selector,
        uint256[] calldata payload
    )
        external payable returns (bytes32 msgHash, uint256 nonce)
    {
        nonce   = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, toAddress)));
        msgHash = keccak256(
            abi.encodePacked(
                uint256(uint160(msg.sender)),
                toAddress,
                nonce,
                selector,
                uint256(payload.length),
                payload
            )
        );
        l1ToL2Messages[msgHash] += 1;
        emit LogMessageToL2(msg.sender, toAddress, selector, payload, nonce, msg.value);
    }

    // ───────────────────────────────────────────────────────────────────
    //  L2 → L1 message bridge
    //
    //  The producer side of this queue (`l2ToL1Messages`) is supposed to
    //  be written by a settlement step — in real `Starknet.sol`, the
    //  orchestrator's call to `updateState(...)` iterates the proved
    //  block's "messages-to-L1" segment and credits each hash here.
    //  Our `updateState` is currently a stub that only updates the three
    //  state-root slots — populating `l2ToL1Messages` from a verified
    //  block is gap 1 (settlement pipeline), tracked separately.
    //
    //  The consumer side — `consumeMessageFromL2` — is symmetrically
    //  mirrored from `Starknet.sol`. Once gap 1 lands (or a dev-only
    //  injection helper is added), an L1 contract can claim its
    //  messages here without further changes to this surface.
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Consume one queued L2 → L1 message. Mirrors
     *         StarkWare's production `Starknet.sol` signature, hash
     *         formula, and revert string verbatim, so an L1 contract
     *         written against this stub will compile + behave
     *         identically against the real Starknet contract on mainnet.
     *
     * @dev    The msgHash binds three things:
     *           - the L2 sender (`fromAddress`)
     *           - the L1 consumer (`msg.sender` — i.e. the caller of
     *             this function, NOT a parameter)
     *           - the payload (length-prefixed)
     *         Only the contract whose address matches the L2 sender's
     *         declared destination can therefore consume the message.
     *         The L2-side `send_message_to_l1_syscall(to_address,
     *         payload)` sets `to_address` to the intended L1 consumer,
     *         and the orchestrator's `updateState` (when implemented)
     *         must compute the same hash using the L2-recorded
     *         destination — so an unauthorised L1 contract calling here
     *         with the right (fromAddress, payload) but a different
     *         `msg.sender` will compute a hash whose count in
     *         `l2ToL1Messages` is 0 and revert.
     *
     * @param  fromAddress L2 contract that emitted the message (felt252
     *                     widened to uint256)
     * @param  payload     The felt array L2 attached to the message
     * @return msgHash     Hash of the consumed message (handy for caller
     *                     logging / replay-defence)
     */
    function consumeMessageFromL2(
        uint256          fromAddress,
        uint256[] calldata payload
    )
        external returns (bytes32 msgHash)
    {
        msgHash = keccak256(
            abi.encodePacked(
                fromAddress,
                uint256(uint160(msg.sender)),
                payload.length,
                payload
            )
        );

        require(l2ToL1Messages[msgHash] > 0, "INVALID_MESSAGE_TO_CONSUME");

        emit ConsumedMessageToL1(fromAddress, msg.sender, payload);
        l2ToL1Messages[msgHash] -= 1;
    }

    // ───────────────────────────────────────────────────────────────────
    //  DEV-ONLY: hand-credit an L2 → L1 message into the queue
    //
    //  Real `Starknet.sol` populates `l2ToL1Messages` from
    //  `updateState(...)` after a verified STARK proof of the L2 block.
    //  Until our SNOS + Stone + orchestrator pipeline is wired (gap 1
    //  in the L2→L1 path), nothing on chain credits the queue, so
    //  `consumeMessageFromL2` would always revert
    //  "INVALID_MESSAGE_TO_CONSUME" — making the entire consume API dead.
    //
    //  This helper closes that gap for dev/test runs: it lets an
    //  off-chain script that watches Madara for `MissionSafe` events
    //  hand-deliver them to L1, bypassing the proof pipeline. It is NOT
    //  in real `Starknet.sol` and MUST be removed before any production
    //  deployment.
    //
    //  No access control on purpose — devnet only.
    // ───────────────────────────────────────────────────────────────────

    /// @notice Emitted when a message is hand-credited via `injectL2Message`.
    ///         Distinct from the production settlement path so audit
    ///         tooling can flag dev-injected vs proof-anchored messages.
    event DevInjectedL2Message(
        uint256 indexed fromAddress,
        address indexed toAddress,
        uint256[]       payload,
        bytes32         msgHash
    );

    /**
     * @notice Hand-credit one L2 → L1 message into the consume queue,
     *         WITHOUT requiring a STARK proof or block settlement.
     *
     * @dev    Computes msgHash using the same formula as
     *         `consumeMessageFromL2`, so the eventual consumer (whose
     *         address must equal `toAddress`) sees a matching hash and
     *         the consume call passes.
     *
     * @param fromAddress L2 sender (convoy_protocol contract address)
     * @param toAddress   L1 consumer (Verifier contract address)
     * @param payload     Felts the L2 attached to the message
     */
    function injectL2Message(
        uint256          fromAddress,
        address          toAddress,
        uint256[] calldata payload
    ) external returns (bytes32 msgHash) {
        msgHash = keccak256(
            abi.encodePacked(
                fromAddress,
                uint256(uint160(toAddress)),
                payload.length,
                payload
            )
        );
        l2ToL1Messages[msgHash] += 1;
        emit DevInjectedL2Message(fromAddress, toAddress, payload, msgHash);
    }
}

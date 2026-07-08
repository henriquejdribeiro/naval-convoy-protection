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
 *   - Madara reads stateBlockNumber(), stateRoot(), stateBlockHash(), and
 *     identify() on startup to confirm the L1 settlement contract is reachable.
 *   - updateState(...) is the settlement hook the orchestrator WOULD call after
 *     proving each block (it should also credit l2ToL1Messages from the proven
 *     block — currently it only sets the 3 state slots; that gap is why the
 *     L2→L1 queue is fed by injectL2Message instead). Unused pre-proving-pipeline.
 *   - L2→L1 (the CORE convoy path): a swarm's convoy_protocol emits the
 *     "all SAFE" message; injectL2Message (DEV) hand-credits it into
 *     l2ToL1Messages, then the Verifier claims it via consumeMessageFromL2.
 *   - L1→L2: sendMessageToL2 is fired by Registry.deploy to queue the
 *     open_mission message, but Madara runs --l1-sync-disabled so it's never
 *     consumed — the working flow bypasses it with open_mission_local.
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
    uint256 public stateRoot;         // fingerprint of the whole L2 State
    int256  public stateBlockNumber;  // -1 = no L2 block settled yet, 0 = genesis, 1 = first block, ...
    uint256 public stateBlockHash;    // Poseidon hash of the most-recently-settled L2 block (uniquely identifies the block)

    // ───────────────────────────────────────────────────────────────────
    // ── L1↔L2 message mailboxes: hash → COUNT (a multiset, not a bool, so the
    //    SAME message can be queued/consumed N times). The queue stores only a
    //    HASH commitment (cheap); the consumer re-supplies the message data and
    //    the hash is recomputed to authorize consumption. The hash binds
    //    sender+recipient+payload, so ONLY the addressed recipient computes a
    //    matching hash — that binding IS the access control (no modifier needed).
    // ───────────────────────────────────────────────────────────────────
    mapping(bytes32 => uint256) public l1ToL2Messages;  // L1→L2; filled by sendMessageToL2
    mapping(bytes32 => uint256) public l2ToL1Messages;  // L2→L1 (convoy verdict path);
                                                        // real: filled by proven updateState
                                                        // stub: filled by injectL2Message, drained by consumeMessageFromL2                         

    // ───────────────────────────────────────────────────────────────────
    //  Events: off-chain broadcast signals (contracts can't read these).
    //    `indexed` = filterable topic (like Cairo's #[key]); max 3 per event.
    // ───────────────────────────────────────────────────────────────────

    /// @notice Emitted by `updateState` when L1 accepts a newly-settled L2
    ///         state. Off-chain observers and the orchestrator watch this to
    ///         track L2→L1 finality (in production it fires once per proven block).
    /// @param  globalRoot  New L2 state root — the Patricia trie root committing
    ///                     to ALL L2 storage after the settled block.
    /// @param  blockNumber Settled L2 block height (int256; -1 = none settled yet).
    /// @param  blockHash   Poseidon hash of the settled L2 block; with
    ///                     `blockNumber` it pins the exact settled chain head.
    event LogStateUpdate(uint256 globalRoot, int256 blockNumber, uint256 blockHash);

    /// @notice Emitted by `sendMessageToL2` to queue an L1 → L2 message. This is
    ///         the L1→L2 trigger: a real Madara L1-sync WATCHES this event and,
    ///         on seeing one, injects a matching `l1_handler` transaction into
    ///         L2. (Here Madara runs --l1-sync-disabled, so it's ignored and the
    ///         flow bypasses with open_mission_local.) The 3 indexed fields are
    ///         exactly the keys Madara filters on.
    /// @param  fromAddress L1 sender — becomes the handler's `from_address` arg.
    /// @param  toAddress   Target L2 contract to receive the message.
    /// @param  selector    Which `l1_handler` entry point to invoke.
    /// @param  payload     Felt args passed to the handler.
    /// @param  nonce       Unique per-message nonce (ordering / replay defence).
    /// @param  fee         L1 fee paid (msg.value) to incentivise delivery.
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
    ///                     called `send_message_to_l1_syscall`).
    /// @param  toAddress   L1 consumer (msg.sender of consumeMessageFromL2).
    /// @param  payload     The arbitrary felt array L2 attached to the
    ///                     message — for the convoy flow this is
    ///                     `[mission_id, n_drones]`.
    event ConsumedMessageToL1(
        uint256 indexed fromAddress,
        address indexed toAddress,
        uint256[]       payload
    );

    // ── Madara startup checks ────────────────────────────────────────────
    // Together with the stateRoot/stateBlockNumber/stateBlockHash getters,
    // these are what Madara's L1-sync reads on boot to validate + locate its
    // settlement contract. (Only exercised when L1-sync is ON — currently
    // Madara runs --l1-sync-disabled, so this isn't called yet.)

    /// @notice Identity/version handshake Madara calls on startup to confirm
    ///         this is a genuine Starknet Core contract before trusting it as
    ///         the settlement layer. The stub returns a plausible version string
    ///         to impersonate the real contract. `pure` = touches no state, so
    ///         it's a free call. NOT a bridge gap: the real Starknet.sol
    ///         implements this too (with its real version), so it becomes
    ///         production-ready for free.
    function identify() external pure returns (string memory) {
        return "StarkWare_Starknet_2025_10";
    }

    // ───────────────────────────────────────────────────────────────────
    //  State settlement THE settlement hook (currently gutted = "gap 1")
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Settle a proven L2 block on L1. In real Starknet.sol the
     *         orchestrator calls this after proving a block, and it (a) checks
     *         the block's proof was verified (verifier.isValid(factHash) over the
     *         program output), (b) advances the state slots, and (c) credits the
     *         block's L2→L1 messages into l2ToL1Messages — all from ONE proof.
     *
     * @dev    THIS STUB DOES NONE OF THAT. It just assigns the 3 slots and emits.
     *         Missing: proof verification (no security!), l2ToL1Messages crediting
     *         (why the L2→L1 queue is empty → injectL2Message fakes it), operator
     *         access control, and the program-output/proof argument. Making the
     *         L2→L1 bridge real = making THIS function real + wiring the
     *         orchestrator to call it, after which injectL2Message can be deleted.
     *         Currently unused (nothing calls it → state sits at genesis).
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
     * @notice Queue an L1 → L2 message. An L1 contract calls this to invoke an
     *         l1_handler on an L2 contract. Emits LogMessageToL2, which a real
     *         Madara L1-sync WATCHES to inject the matching l1_handler tx on L2
     *         (with msg.sender as the handler's from_address).
     * @dev    Called by Registry.deploy to queue the open_mission message — but
     *         Madara runs --l1-sync-disabled, so nothing consumes it and the flow
     *         bypasses with open_mission_local. Making L1→L2 real = deploy a real
     *         Core + enable L1-sync (no proof needed), then drop open_mission_local.
     *         payable: real Starknet.sol requires a delivery FEE (msg.value); the
     *         stub only records it. NONCE CAVEAT: real Starknet.sol uses a stored
     *         monotonic counter; this timestamp-derived nonce can collide within
     *         one block (fine for devnet, not faithful to production).
     * @param toAddress L2 target contract (felt as uint256).
     * @param selector  Which l1_handler entry point to call.
     * @param payload   Felt args for the handler.
     * @return msgHash  Hash tracked in l1ToL2Messages.
     * @return nonce    Per-message nonce (uniqueness).
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
        // Recompute the message hash. msg.sender (the caller) is baked in as the
        // recipient — so this only matches a queued message that L2 ADDRESSED to
        // this exact caller. That binding IS the access control (no modifier).
        msgHash = keccak256(
            abi.encodePacked(
                fromAddress,
                uint256(uint160(msg.sender)),   // L1 consumer = caller, the caller is forced to be the recipient
                payload.length,
                payload
            )
        );

        // Reverts if not queued: never sent, wrong caller (hash mismatch), or
        // already consumed. Revert string is verbatim from real Starknet.sol.
        require(l2ToL1Messages[msgHash] > 0, "INVALID_MESSAGE_TO_CONSUME");

        emit ConsumedMessageToL1(fromAddress, msg.sender, payload);
        l2ToL1Messages[msgHash] -= 1;   // consume one copy (multiset)
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
                uint256(uint160(toAddress)),  // the caller declares who the recipient is
                payload.length,
                payload
            )
        );
        l2ToL1Messages[msgHash] += 1;  // hand-credit, NO proof
        emit DevInjectedL2Message(fromAddress, toAddress, payload, msgHash);
    }
}

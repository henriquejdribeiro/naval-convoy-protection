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
}

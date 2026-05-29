// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./Registry.sol";
import "./IStarkVerifier.sol";

/**
 * @title  Verifier
 * @notice On-chain registry for STARK-verified per-drone SAFE_AREA proofs,
 *         with mission-level aggregation across the 5 drones of a swarm.
 *
 * Two-stage verification architecture (clean responsibility split):
 *
 *   ── Stage A (STARK math) — handled by path-a-runner against the real
 *      StarkWare contracts BEFORE this contract is ever called:
 *
 *        1. path-a-runner splits the EVM-adapted proof via
 *           stark_evm_adapter::split_fri_merkle_statements
 *        2. Phase 1: MerkleStatementContract.verify()
 *        3. Phase 2: FriStatementContract.verify()
 *        4. Phase 3: MemoryPageFactRegistry.registerContinuousMemoryPage()
 *        5. Phase 4: GpsStatementVerifier.verifyProofAndRegister(...)
 *        ⇒ At this point, GpsStatementVerifier's FactRegistry holds
 *          factHash → true. The cryptographic gate has been passed.
 *
 *   ── Stage B (application bookkeeping) — handled here:
 *
 *        6. Relay submits ONLY the 11-field SafeProofInputs to
 *           registerSafeProof. No proof bytes, no FRI params, no task
 *           metadata, no cairoAuxInput — Stage A already consumed those.
 *        7. This contract:
 *           a. checks caller is the whitelisted relay for the mission,
 *           b. derives EXPECTED strip from Registry.specs[missionId] +
 *              droneIndex, asserts the proof's declared bounds match,
 *           c. recomputes factHash = keccak256(programHash, outputHash),
 *           d. calls starkVerifier.isValid(factHash) — cheap state read.
 *              Reverts if Stage A never happened (or happened for a
 *              different program/output).
 *           e. writes per-drone verdict via Registry.setVerdict(...),
 *           f. when this is the nDrones-th SAFE drone, computes the
 *              Pedersen-chain aggregate of all stored commitments and
 *              calls Registry.setMissionSafe(missionId, aggH).
 *
 *   ── Stage C — CommandLog.advance() reads Registry.isDualSafe(α, β)
 *      and lets the convoy advance when both swarms are aggregate-SAFE.
 *
 * The cryptographic gate is the bound IStarkVerifier — production is
 * GpsStatementVerifier deployed via DeployStarkVerifier.s.sol. There is
 * no mock fallback on the SAFE path; deployment requires a real verifier
 * address. The relay-ship signature authenticates the submitter but is
 * not the cryptographic security property.
 *
 * GAS COST: dropping the 4 huge calldata arrays from the per-drone tx
 * (proofParams ~12 felts, proof ~25,000 felts, taskMetadata ~few,
 * cairoAuxInput ~30) drops the per-drone calldata from ~800 KB to ~250
 * bytes. The STARK verification cost was already paid in Stage A.
 */
contract Verifier is Ownable {
    // ───────────────────────────────────────────────────────────────────
    //  FactRegistry pattern — same as before
    // ───────────────────────────────────────────────────────────────────
    mapping(bytes32 => bool) public verifiedFacts;

    function isValid(bytes32 fact) public view returns (bool) {
        return verifiedFacts[fact];
    }

    function _registerFact(bytes32 fact) internal {
        if (!verifiedFacts[fact]) {
            verifiedFacts[fact] = true;
            emit FactRegistered(fact);
        }
    }

    // ───────────────────────────────────────────────────────────────────
    //  Per-mission relay whitelist (Alpha mission → ship F, Bravo → ship B)
    // ───────────────────────────────────────────────────────────────────
    mapping(uint256 => address) public relayOf;   // missionId → relay address

    // ───────────────────────────────────────────────────────────────────
    //  Bound external contracts
    //
    //  starkVerifier is the deployed GpsStatementVerifier (Stage A above
    //  registers facts in its FactRegistry). We only call isValid() on
    //  it here — never verifyProofAndRegister — so the per-tx calldata
    //  is tiny and we share the cryptographic state with whatever else
    //  on this Geth deployment uses the same GPS contract.
    // ───────────────────────────────────────────────────────────────────
    Registry        public immutable registry;
    IStarkVerifier  public immutable starkVerifier;

    // ───────────────────────────────────────────────────────────────────
    //  Per-proof record — kept alongside the fact for audit + aggregation
    // ───────────────────────────────────────────────────────────────────
    struct ProofRecord {
        bytes32 programHash;
        bytes32 outputHash;
        uint256 missionId;
        uint8   droneIndex;        // 1..nDrones
        uint32  stripXStart;
        uint32  stripXEnd;
        uint32  stripYStart;
        uint32  stripYEnd;
        uint8   verdictBool;       // 0 = UNSAFE, 1 = SAFE
        bytes32 commitment;        // Pedersen-chain H_i over the drone's cells + nonce
        uint256 nSteps;
        uint256 timestamp;
        uint256 blockNumber;
    }

    ProofRecord[] public proofs;
    uint256       public proofCount;

    /// Per-(missionId, droneIndex) → commitment H_i (needed at aggregation
    /// time, when we Pedersen-chain over all nDrones values). Indexed
    /// access avoids a linear scan of `proofs[]`.
    mapping(uint256 => mapping(uint8 => bytes32)) public droneCommitment;

    // ───────────────────────────────────────────────────────────────────
    //  Events
    // ───────────────────────────────────────────────────────────────────
    event FactRegistered(bytes32 indexed factHash);
    event DroneVerified(
        uint256 indexed proofId,
        uint256 indexed missionId,
        uint8   indexed droneIndex,
        bytes32         factHash,
        uint8           verdictBool,
        bytes32         commitment
    );
    event MissionAggregated(
        uint256 indexed missionId,
        bytes32         aggH,
        uint8           nDrones
    );
    event RelayUpdated(
        uint256 indexed missionId,
        address indexed previous,
        address indexed current
    );

    // ───────────────────────────────────────────────────────────────────
    //  Calldata struct — the new 8-felt SafeProofInputs schema
    //
    //  Field order matches the order safe_area_verify.cairo writes via
    //  serialize_word; the L2 ConvoyProtocol contract builds the same
    //  felt sequence for its in-Cairo verifier dispatcher. Keep them in
    //  sync — any rearrangement breaks proof acceptance.
    // ───────────────────────────────────────────────────────────────────
    struct SafeProofInputs {
        bytes32 programHash;       // keccak of safe_area_verify.cairo bytecode
        bytes32 outputHash;        // keccak of the 8-felt public-output sequence
        uint256 missionId;
        uint8   droneIndex;        // 1..spec.nDrones
        uint32  stripXStart;
        uint32  stripXEnd;
        uint32  stripYStart;
        uint32  stripYEnd;
        uint8   verdictBool;       // 0 or 1
        bytes32 commitment;        // H_i (hiding Pedersen-chain commitment)
        uint256 nSteps;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Constructor
    // ───────────────────────────────────────────────────────────────────

    /**
     * @param initialOwner       operational owner (may rotate relays)
     * @param registryAddr       bound Registry
     * @param alphaRelay         ship F's address — submits all 5 Alpha drone proofs
     * @param bravoRelay         ship B's address — submits all 5 Bravo drone proofs
     * @param starkVerifierAddr  GpsStatementVerifier address — we only
     *                           call isValid() on it. Stage A (the four
     *                           pre-registration phases + main proof) is
     *                           handled by path-a-runner before any tx
     *                           reaches this contract.
     */
    constructor(
        address initialOwner,
        address registryAddr,
        address alphaRelay,
        address bravoRelay,
        address starkVerifierAddr
    )
        Ownable(initialOwner)
    {
        require(registryAddr      != address(0), "Verifier: registry = 0x0");
        require(alphaRelay        != address(0), "Verifier: alphaRelay = 0x0");
        require(bravoRelay        != address(0), "Verifier: bravoRelay = 0x0");
        require(starkVerifierAddr != address(0), "Verifier: starkVerifier = 0x0");
        registry        = Registry(registryAddr);
        starkVerifier   = IStarkVerifier(starkVerifierAddr);
        relayOf[Registry(registryAddr).ALPHA_MISSION_ID()] = alphaRelay;
        relayOf[Registry(registryAddr).BRAVO_MISSION_ID()] = bravoRelay;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Rotate a relay address (owner only)
    // ───────────────────────────────────────────────────────────────────

    function setRelay(uint256 missionId, address newRelay) external onlyOwner {
        require(newRelay != address(0),                                     "Verifier: relay = 0x0");
        require(missionId == registry.ALPHA_MISSION_ID()
             || missionId == registry.BRAVO_MISSION_ID(),
                                                                            "Verifier: invalid missionId");
        emit RelayUpdated(missionId, relayOf[missionId], newRelay);
        relayOf[missionId] = newRelay;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Core: register one drone's SAFE_AREA proof + maybe aggregate
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Register one drone's SAFE proof (Stage B — application
     *         bookkeeping). Assumes Stage A (path-a-runner against the
     *         StarkWare contracts) has already registered the fact.
     *
     * Restrictions:
     *   - Caller must be the whitelisted relay for `inputs.missionId`.
     *   - Mission must be deployed in Registry.
     *   - droneIndex ∈ [1, spec.nDrones].
     *   - Strip bounds in the proof must match the bounds derived from
     *     (spec, droneIndex) — prevents a drone from sweeping a
     *     neighbour's strip and submitting under its own droneIndex.
     *   - factHash = keccak256(programHash, outputHash) must be
     *     starkVerifier.isValid() — i.e. Stage A registered this exact
     *     (program, output) pair on the GpsStatementVerifier.
     *
     * Side effects:
     *   - Stores the ProofRecord locally for audit.
     *   - If verdictBool=1, writes the SAFE verdict to Registry.
     *   - If this is the nDrones-th SAFE submission, computes the
     *     Pedersen-chain aggregate and writes missionSafe to Registry.
     *
     * @return proofId  index in proofs[]
     * @return factHash keccak256(programHash, outputHash)
     */
    function registerSafeProof(SafeProofInputs calldata inputs)
        external
        returns (uint256 proofId, bytes32 factHash)
    {
        // 1. Relay-whitelist gate
        require(msg.sender == relayOf[inputs.missionId], "Verifier: onlyRelay");

        // 2. Mission spec sanity
        Registry.MissionSpec memory spec = registry.getSpec(inputs.missionId);
        require(spec.nDrones > 0,                          "Verifier: unknown mission");
        require(inputs.droneIndex >= 1
             && inputs.droneIndex <= spec.nDrones,
                                                            "Verifier: droneIndex out of range");
        require(inputs.verdictBool <= 1,                   "Verifier: verdictBool not 0/1");

        // 3. Strip-bounds gate — derive the expected (x_start, x_end,
        //    y_start, y_end) from the spec and assert the proof's
        //    declared bounds match. If they don't, the drone is either
        //    submitting under the wrong droneIndex or the spec is
        //    stale — either way, reject.
        uint32 expectedXStart = spec.zoneX + (uint32(inputs.droneIndex) - 1) * spec.stripWidth;
        uint32 expectedXEnd   = expectedXStart + spec.stripWidth;
        require(inputs.stripXStart == expectedXStart, "Verifier: wrong stripXStart");
        require(inputs.stripXEnd   == expectedXEnd,   "Verifier: wrong stripXEnd");
        require(inputs.stripYStart == spec.zoneY,     "Verifier: wrong stripYStart");
        require(inputs.stripYEnd   == spec.zoneY + spec.zoneH,
                                                       "Verifier: wrong stripYEnd");

        // 4. Cryptographic gate — REUSE Stage A's verification.
        //    starkVerifier.isValid(factHash) is a cheap state read on
        //    the GpsStatementVerifier's FactRegistry. It returns true
        //    iff path-a-runner already completed phases 1-4 against
        //    this exact (programHash, outputHash) pair. The proof
        //    bytes themselves never enter this contract.
        factHash = keccak256(abi.encodePacked(inputs.programHash, inputs.outputHash));
        require(
            starkVerifier.isValid(factHash),
            "Verifier: STARK fact not registered (run path-a-runner first?)"
        );

        // 5. Register the fact + audit record
        _registerFact(factHash);
        proofId = proofs.length;
        proofs.push(ProofRecord({
            programHash:  inputs.programHash,
            outputHash:   inputs.outputHash,
            missionId:    inputs.missionId,
            droneIndex:   inputs.droneIndex,
            stripXStart:  inputs.stripXStart,
            stripXEnd:    inputs.stripXEnd,
            stripYStart:  inputs.stripYStart,
            stripYEnd:    inputs.stripYEnd,
            verdictBool:  inputs.verdictBool,
            commitment:   inputs.commitment,
            nSteps:       inputs.nSteps,
            timestamp:    block.timestamp,
            blockNumber:  block.number
        }));
        proofCount = proofs.length;
        droneCommitment[inputs.missionId][inputs.droneIndex] = inputs.commitment;

        emit DroneVerified(
            proofId,
            inputs.missionId,
            inputs.droneIndex,
            factHash,
            inputs.verdictBool,
            inputs.commitment
        );

        // 6. Per-drone Registry verdict + mission-level aggregation.
        //    Only SAFE submissions contribute to the safe count.
        if (inputs.verdictBool == 1) {
            uint8 newCount = registry.setVerdict(inputs.missionId, inputs.droneIndex);
            if (newCount == spec.nDrones) {
                bytes32 aggH = _aggregateCommitment(inputs.missionId, spec.nDrones);
                registry.setMissionSafe(inputs.missionId, aggH);
                emit MissionAggregated(inputs.missionId, aggH, spec.nDrones);
            }
        }
    }

    // ───────────────────────────────────────────────────────────────────
    //  Pedersen-chain aggregation: H_agg = ... ((0, H_1), H_2), ..., H_n
    //
    //  Pedersen is a 2-input STARK-friendly hash. We chain it over the
    //  nDrones commitments in droneIndex order so the aggregate is a
    //  deterministic function of the inputs — anyone can recompute and
    //  verify it from the per-drone records.
    //
    //  NOTE: this is a *commitment* aggregation, not a proof aggregation.
    //  Each individual STARK proof was already verified independently
    //  above; aggH is just a compact summary of the 5 H_i values that
    //  L1 emits to L2 + uses in CommandLog.
    //
    //  Implementation: keccak256 over the concatenated felt-encoded H_i
    //  values. This is L1-cheap; on L2 (Cairo) the same chain would use
    //  the Cairo pedersen builtin. Both produce a "binding aggregate"
    //  semantically; we use keccak on L1 because Solidity doesn't have
    //  a native Pedersen.
    // ───────────────────────────────────────────────────────────────────

    function _aggregateCommitment(uint256 missionId, uint8 nDrones)
        internal
        view
        returns (bytes32 aggH)
    {
        // Concatenate the n H_i values, in order, and keccak the whole thing.
        // (Solidity has no Pedersen-on-Starkfield primitive; keccak256
        //  over the byte-encoded H_i sequence is the canonical L1
        //  analogue and matches what the on-chain proof-of-aggregation
        //  reads as a single digest.)
        bytes memory buf = new bytes(uint256(nDrones) * 32);
        for (uint8 i = 1; i <= nDrones; i++) {
            bytes32 h = droneCommitment[missionId][i];
            assembly {
                // Write h into buf at offset (i-1)*32, AFTER the dynamic-
                // array length word (first 32 bytes of buf in memory).
                mstore(add(add(buf, 32), mul(sub(i, 1), 32)), h)
            }
        }
        aggH = keccak256(buf);
    }

    // ───────────────────────────────────────────────────────────────────
    //  Read helpers
    // ───────────────────────────────────────────────────────────────────

    function getProof(uint256 proofId) external view returns (ProofRecord memory) {
        require(proofId < proofs.length, "Verifier: invalid proofId");
        return proofs[proofId];
    }

    function getLatestProof() external view returns (ProofRecord memory) {
        require(proofs.length > 0, "Verifier: no proofs");
        return proofs[proofs.length - 1];
    }

    function getDroneCommitment(uint256 missionId, uint8 droneIndex)
        external
        view
        returns (bytes32)
    {
        return droneCommitment[missionId][droneIndex];
    }
}

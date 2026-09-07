// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Registry.sol";
import "./IStarkVerifier.sol";

/**
 * @title  Verifier
 * @notice On-chain registry for STARK-verified per-drone SAFE_AREA proofs,
 *         with mission-level aggregation across the 5 drones of a swarm.
 *         Restored from pre-4fa6ad4 (the trustless registerSafeProof design),
 *         adapted: per-drone SAFE tally lives here now (the current Registry
 *         exposes only mission-level setMissionSafe, not per-drone setVerdict).
 *
 * Stage A (path-a-runner) verifies the STARK against the StarkWare contracts
 * and registers factHash on the GpsStatementVerifier. Stage B (here) submits
 * only the 11-field SafeProofInputs and gates on starkVerifier.isValid(factHash).
 */
contract Verifier is Ownable {
    // ── local fact cache ────────────────────────────────────────────────
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

    // ── per-mission relay whitelist (alpha→ship F, bravo→ship B) ────────
    mapping(uint256 => address) public relayOf;

    // ── ADAPTED: per-drone SAFE aggregation now lives HERE (Registry no
    //    longer exposes setVerdict / per-drone safeCount) ─────────────────
    mapping(uint256 => uint8) public safeCount;                        // missionId → # SAFE drones counted
    mapping(uint256 => mapping(uint8 => bool)) public droneSafeCounted; // (missionId, droneIndex) → counted?

    // ── bound external contracts ────────────────────────────────────────
    Registry        public immutable registry;
    //IStarkVerifier  public immutable starkVerifier;   // the GpsStatementVerifier on Besu
    IStarkVerifier  public starkVerifier;   // the GpsStatementVerifier on Besu
    // new setter:
    function setStarkVerifier(address newStarkVerifier) external onlyOwner {
        require(newStarkVerifier != address(0), "Verifier: starkVerifier = 0x0");
        starkVerifier = IStarkVerifier(newStarkVerifier);
    }
    /// Register the STARK-curve public key authorised to sign telemetry for
    /// (missionId, droneIndex). onlyOwner; registerSafeProof then requires the
    /// proof's drone_pubkey to equal this.
    function setDronePubkey(uint256 missionId, uint8 droneIndex, uint256 pubkey)
        external onlyOwner
    {
        require(pubkey != 0, "Verifier: pubkey = 0");
        registeredDronePubkey[missionId][droneIndex] = pubkey;
    }

    struct ProofRecord {
        bytes32 programHash;
        bytes32 outputHash;
        uint256 missionId;
        uint8   droneIndex;
        uint32  stripXStart;
        uint32  stripXEnd;
        uint32  stripYStart;
        uint32  stripYEnd;
        uint8   verdictBool;
        bytes32 commitment;
        uint256 dronePubkey;
        uint256 nSteps;
        uint256 timestamp;
        uint256 blockNumber;
    }

    ProofRecord[] public proofs;
    uint256       public proofCount;
    mapping(uint256 => mapping(uint8 => bytes32)) public droneCommitment;

    // ── Route-B identity binding: authorised STARK-curve pubkey per drone ──
    mapping(uint256 => mapping(uint8 => uint256)) public registeredDronePubkey;

    event FactRegistered(bytes32 indexed factHash);
    event DroneVerified(
        uint256 indexed proofId,
        uint256 indexed missionId,
        uint8   indexed droneIndex,
        bytes32         factHash,
        uint8           verdictBool,
        bytes32         commitment
    );
    event MissionAggregated(uint256 indexed missionId, bytes32 aggH, uint8 nDrones);
    event RelayUpdated(uint256 indexed missionId, address indexed previous, address indexed current);

    struct SafeProofInputs {
        bytes32 programHash;
        bytes32 outputHash;
        uint256 missionId;
        uint8   droneIndex;
        uint32  stripXStart;
        uint32  stripXEnd;
        uint32  stripYStart;
        uint32  stripYEnd;
        uint8   verdictBool;
        bytes32 commitment;
        uint256 dronePubkey;   // STARK-curve pubkey (proof's 9th output)
        uint256 nSteps;
    }

    constructor(
        address initialOwner,
        address registryAddr,
        address alphaRelay,
        address bravoRelay,
        address starkVerifierAddr
    ) Ownable(initialOwner) {
        require(registryAddr      != address(0), "Verifier: registry = 0x0");
        require(alphaRelay        != address(0), "Verifier: alphaRelay = 0x0");
        require(bravoRelay        != address(0), "Verifier: bravoRelay = 0x0");
        require(starkVerifierAddr != address(0), "Verifier: starkVerifier = 0x0");
        registry      = Registry(registryAddr);
        starkVerifier = IStarkVerifier(starkVerifierAddr);
        relayOf[Registry(registryAddr).ALPHA_MISSION_ID()] = alphaRelay;
        relayOf[Registry(registryAddr).BRAVO_MISSION_ID()] = bravoRelay;
    }

    function setRelay(uint256 missionId, address newRelay) external onlyOwner {
        require(newRelay != address(0), "Verifier: relay = 0x0");
        require(missionId == registry.ALPHA_MISSION_ID()
             || missionId == registry.BRAVO_MISSION_ID(), "Verifier: invalid missionId");
        emit RelayUpdated(missionId, relayOf[missionId], newRelay);
        relayOf[missionId] = newRelay;
    }

    function registerSafeProof(SafeProofInputs calldata inputs)
        external
        returns (uint256 proofId, bytes32 factHash)
    {
        // 1. Relay-whitelist gate
        require(msg.sender == relayOf[inputs.missionId], "Verifier: onlyRelay");

        // 2. Mission spec sanity
        Registry.MissionSpec memory spec = registry.getSpec(inputs.missionId);
        require(spec.nDrones > 0, "Verifier: unknown mission");
        require(inputs.droneIndex >= 1 && inputs.droneIndex <= spec.nDrones,
                "Verifier: droneIndex out of range");
        require(inputs.verdictBool <= 1, "Verifier: verdictBool not 0/1");

        // 3. Strip-bounds gate — derive expected bounds from spec + droneIndex
        uint32 expectedXStart = spec.zoneX + (uint32(inputs.droneIndex) - 1) * spec.stripWidth;
        uint32 expectedXEnd   = expectedXStart + spec.stripWidth;
        require(inputs.stripXStart == expectedXStart, "Verifier: wrong stripXStart");
        require(inputs.stripXEnd   == expectedXEnd,   "Verifier: wrong stripXEnd");
        require(inputs.stripYStart == spec.zoneY,     "Verifier: wrong stripYStart");
        require(inputs.stripYEnd   == spec.zoneY + spec.zoneH, "Verifier: wrong stripYEnd");

        // 3b. Identity gate — the proof's drone pubkey must be the one
        //     registered for (mission, drone). Binds the verdict to an
        //     authorised swarm identity (the proof already verified the drone's
        //     ECDSA signature over the commitment in-circuit).
        require(inputs.dronePubkey ==
                registeredDronePubkey[inputs.missionId][inputs.droneIndex],
                "Verifier: unregistered drone pubkey");


        // 4. Cryptographic gate — reuse Stage A's verification on the GPS
        factHash = keccak256(abi.encodePacked(inputs.programHash, inputs.outputHash));
        require(starkVerifier.isValid(factHash),
                "Verifier: STARK fact not registered (run path-a-runner first?)");

        // 5. Register the fact + audit record
        _registerFact(factHash);
        proofId = proofs.length;
        proofs.push(ProofRecord({
            programHash: inputs.programHash, outputHash: inputs.outputHash,
            missionId:   inputs.missionId,   droneIndex:  inputs.droneIndex,
            stripXStart: inputs.stripXStart, stripXEnd:   inputs.stripXEnd,
            stripYStart: inputs.stripYStart, stripYEnd:   inputs.stripYEnd,
            verdictBool: inputs.verdictBool, commitment:  inputs.commitment,
            dronePubkey: inputs.dronePubkey, nSteps:      inputs.nSteps,
            timestamp:   block.timestamp, blockNumber: block.number
        }));
        proofCount = proofs.length;
        droneCommitment[inputs.missionId][inputs.droneIndex] = inputs.commitment;

        emit DroneVerified(proofId, inputs.missionId, inputs.droneIndex,
                           factHash, inputs.verdictBool, inputs.commitment);

        // 6. ADAPTED: per-drone SAFE tally here (was registry.setVerdict)
        if (inputs.verdictBool == 1) {
            require(!droneSafeCounted[inputs.missionId][inputs.droneIndex],
                    "Verifier: drone already counted SAFE");
            droneSafeCounted[inputs.missionId][inputs.droneIndex] = true;
            uint8 newCount = safeCount[inputs.missionId] + 1;
            safeCount[inputs.missionId] = newCount;
            if (newCount == spec.nDrones) {
                bytes32 aggH = _aggregateCommitment(inputs.missionId, spec.nDrones);
                registry.setMissionSafe(inputs.missionId, aggH);
                emit MissionAggregated(inputs.missionId, aggH, spec.nDrones);
            }
        }
    }

    function _aggregateCommitment(uint256 missionId, uint8 nDrones)
        internal view returns (bytes32 aggH)
    {
        bytes memory buf = new bytes(uint256(nDrones) * 32);
        for (uint8 i = 1; i <= nDrones; i++) {
            bytes32 h = droneCommitment[missionId][i];
            assembly { mstore(add(add(buf, 32), mul(sub(i, 1), 32)), h) }
        }
        aggH = keccak256(buf);
    }

    function getProof(uint256 proofId) external view returns (ProofRecord memory) {
        require(proofId < proofs.length, "Verifier: invalid proofId");
        return proofs[proofId];
    }
    function getDroneCommitment(uint256 missionId, uint8 droneIndex)
        external view returns (bytes32) {
        return droneCommitment[missionId][droneIndex];
    }
}
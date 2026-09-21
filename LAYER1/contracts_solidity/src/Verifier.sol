// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Registry.sol";
import "./IStarkVerifier.sol";

/**
 * @title  Verifier
 * @notice On-chain gate for STARK-verified PER-SWARM SAFE_AREA coverage proofs.
 *
 *         Each swarm's leader (a1 / b1) produces ONE proof over all 5 of its
 *         drones with safe_area_verify_{alpha,bravo}.cairo; the swarm's relay
 *         ship (alpha→ship F, bravo→ship B) submits it here via convoy-submitter
 *         after the StarkWare GPS verification has registered the fact.
 *
 *         When BOTH swarm proofs verify SAFE, the whole green+purple area is
 *         certified — the two swarm hashes fold into a single PRINCIPAL hash and
 *         both Registry.missionSafe flags flip, so Registry.isDualSafe(1,2) opens
 *         the advance gate (CommandLog.advance()).
 *
 *         13-hash tree: each proof carries 5 in-circuit drone hashes folded into
 *         its swarm hash (this contract's input); the two swarm hashes fold into
 *         principalHash here. 5+5 drone + 2 swarm + 1 principal = 13.
 *
 *         Sensor-class pinning: the two Cairo programs bake their footprint
 *         (alpha 0.1° → 1 block, bravo 0.2° → 4 blocks) into their constants, so
 *         each program HASH certifies a sensor class. registeredSwarmProgram pins
 *         the expected hash per mission, so a relay cannot pass off the other
 *         swarm's program.
 *
 * Stage A (convoy-submitter, phases 1-4a) verifies the STARK against the
 * StarkWare suite and registers factHash on the GpsStatementVerifier. Stage B
 * (registerSwarmProof, phase 4b) submits the 13-field SwarmProofInputs and gates
 * on starkVerifier.isValid(factHash).
 */
contract Verifier is Ownable {
    uint8 public constant N_DRONES = 5;

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

    // ── bound external contracts ────────────────────────────────────────
    Registry        public immutable registry;
    IStarkVerifier  public starkVerifier;   // the GpsStatementVerifier on Besu

    function setStarkVerifier(address newStarkVerifier) external onlyOwner {
        require(newStarkVerifier != address(0), "Verifier: starkVerifier = 0x0");
        starkVerifier = IStarkVerifier(newStarkVerifier);
    }

    // ── Route-B identity binding: authorised STARK-curve pubkey per drone ──
    //    registerSwarmProof requires the proof's 5 drone pubkeys to equal the
    //    ones registered for (missionId, 1..5).
    mapping(uint256 => mapping(uint8 => uint256)) public registeredDronePubkey;

    function setDronePubkey(uint256 missionId, uint8 droneIndex, uint256 pubkey)
        external onlyOwner
    {
        require(pubkey != 0, "Verifier: pubkey = 0");
        registeredDronePubkey[missionId][droneIndex] = pubkey;
    }

    // ── sensor-class pinning: expected Cairo program hash per swarm ──────
    //    Set to the cairo program hash of safe_area_verify_alpha (mission 1) /
    //    _bravo (mission 2). registerSwarmProof requires an exact match.
    mapping(uint256 => bytes32) public registeredSwarmProgram;

    function setSwarmProgram(uint256 missionId, bytes32 programHash)
        external onlyOwner
    {
        require(programHash != bytes32(0), "Verifier: programHash = 0");
        registeredSwarmProgram[missionId] = programHash;
    }

    // ── verified swarm hashes + principal ───────────────────────────────
    mapping(uint256 => bytes32) public swarmHashOf;   // missionId → swarm hash (once SAFE)
    bytes32 public principalHash;                     // keccak(alphaHash, bravoHash) once both SAFE

    struct SwarmProofRecord {
        bytes32 programHash;
        bytes32 outputHash;
        uint256 missionId;
        uint256 swarmId;
        uint32  zoneX;
        uint32  zoneY;
        uint32  zoneW;
        uint32  zoneH;
        uint8   swarmVerdict;
        bytes32 swarmHash;
        uint256 nSteps;
        uint256 timestamp;
        uint256 blockNumber;
    }

    SwarmProofRecord[] public proofs;
    uint256            public proofCount;

    // ── the 13 public outputs of safe_area_verify_{alpha,bravo}.cairo,
    //    plus the two hashes convoy-submitter derives (programHash, outputHash)
    //    and nSteps. Order/names must stay in lockstep with the submitter abigen.
    struct SwarmProofInputs {
        bytes32     programHash;
        bytes32     outputHash;
        uint256     missionId;
        uint256     swarmId;
        uint32      zoneX;
        uint32      zoneY;
        uint32      zoneW;
        uint32      zoneH;
        uint8       swarmVerdict;
        bytes32     swarmHash;
        uint256[5]  dronePubkeys;   // proof outputs 9..13
        uint256     nSteps;
    }

    event FactRegistered(bytes32 indexed factHash);
    event SwarmVerified(
        uint256 indexed proofId,
        uint256 indexed missionId,
        bytes32         factHash,
        uint8           swarmVerdict,
        bytes32         swarmHash
    );
    event PrincipalCertified(bytes32 principalHash, bytes32 alphaHash, bytes32 bravoHash);
    event RelayUpdated(uint256 indexed missionId, address indexed previous, address indexed current);

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

    /**
     * @notice Verify one swarm's coverage proof and, if SAFE, flip that mission's
     *         L1 flag. When both swarms are SAFE, certify the principal hash.
     * @dev    Called by the swarm's relay ship (via convoy-submitter) AFTER the
     *         StarkWare GPS verification has registered the fact.
     */
    function registerSwarmProof(SwarmProofInputs calldata inputs)
        external
        returns (uint256 proofId, bytes32 factHash)
    {
        // 1. Relay-whitelist gate — only the swarm's relay ship may submit.
        require(msg.sender == relayOf[inputs.missionId], "Verifier: onlyRelay");

        // 2. Mission sanity + swarm-id convention (alpha=1, bravo=2).
        Registry.MissionSpec memory spec = registry.getSpec(inputs.missionId);
        require(spec.nDrones == N_DRONES, "Verifier: unknown/incomplete mission");
        require(inputs.swarmId == inputs.missionId, "Verifier: swarmId != missionId");
        require(inputs.swarmVerdict <= 1, "Verifier: verdict not 0/1");

        // 3. Zone gate — the proof must cover THIS mission's registered zone.
        //    zoneX/zoneY come from the proof inputs (drone location); zoneW/zoneH
        //    are also baked in the program, checked here belt-and-suspenders.
        require(inputs.zoneX == spec.zoneX, "Verifier: wrong zoneX");
        require(inputs.zoneY == spec.zoneY, "Verifier: wrong zoneY");
        require(inputs.zoneW == spec.zoneW, "Verifier: wrong zoneW");
        require(inputs.zoneH == spec.zoneH, "Verifier: wrong zoneH");

        // 4. Sensor-class gate — the proof's program hash must be the one pinned
        //    for this swarm (alpha 0.1° vs bravo 0.2° footprint). Stops a relay
        //    swapping in the other swarm's (easier) program.
        bytes32 expectedProgram = registeredSwarmProgram[inputs.missionId];
        require(expectedProgram != bytes32(0), "Verifier: swarm program not set");
        require(inputs.programHash == expectedProgram, "Verifier: wrong swarm program");

        // 5. Identity gate — all 5 drone pubkeys must be the registered swarm
        //    identities (the proof already verified each drone's ECDSA in-circuit).
        for (uint8 i = 1; i <= N_DRONES; i++) {
            require(inputs.dronePubkeys[i - 1] == registeredDronePubkey[inputs.missionId][i],
                    "Verifier: unregistered drone pubkey");
        }

        // 6. Cryptographic gate — reuse the GPS verification convoy-submitter just
        //    ran (phases 1-4a): the fact for (program, output) must be registered.
        factHash = keccak256(abi.encodePacked(inputs.programHash, inputs.outputHash));
        require(starkVerifier.isValid(factHash),
                "Verifier: STARK fact not registered (run GPS phases first?)");

        // 7. Register the fact + audit record.
        _registerFact(factHash);
        proofId = proofs.length;
        proofs.push(SwarmProofRecord({
            programHash: inputs.programHash, outputHash: inputs.outputHash,
            missionId:   inputs.missionId,   swarmId:     inputs.swarmId,
            zoneX:       inputs.zoneX,        zoneY:      inputs.zoneY,
            zoneW:       inputs.zoneW,        zoneH:      inputs.zoneH,
            swarmVerdict: inputs.swarmVerdict, swarmHash:  inputs.swarmHash,
            nSteps:      inputs.nSteps,
            timestamp:   block.timestamp,     blockNumber: block.number
        }));
        proofCount = proofs.length;
        emit SwarmVerified(proofId, inputs.missionId, factHash,
                           inputs.swarmVerdict, inputs.swarmHash);

        // 8. SAFE swarm → flip the mission flag; certify the principal when both in.
        if (inputs.swarmVerdict == 1) {
            swarmHashOf[inputs.missionId] = inputs.swarmHash;
            registry.setMissionSafe(inputs.missionId, inputs.swarmHash);  // reverts if already SAFE

            uint256 alphaId = registry.ALPHA_MISSION_ID();
            uint256 bravoId = registry.BRAVO_MISSION_ID();
            if (registry.isDualSafe(alphaId, bravoId)) {
                // principal = keccak(swarm_alpha, swarm_bravo) — the single hash
                // certifying the whole green+purple area is clear.
                principalHash = keccak256(
                    abi.encodePacked(swarmHashOf[alphaId], swarmHashOf[bravoId]));
                emit PrincipalCertified(principalHash, swarmHashOf[alphaId], swarmHashOf[bravoId]);
            }
        }
    }

    function getProof(uint256 proofId) external view returns (SwarmProofRecord memory) {
        require(proofId < proofs.length, "Verifier: invalid proofId");
        return proofs[proofId];
    }
}

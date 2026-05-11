// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./Registry.sol";

/**
 * @title  Verifier
 * @notice On-chain registry for STARK-verified SAFE_AREA proofs.
 *
 * Implements the GPS Statement Verifier pattern (StarkWare's production
 * approach used by mainnet Cairo proofs):
 *
 *   1. The Cairo proof program (`safe_area_verify.cairo`) executes off-chain
 *      under SNOS replay; Stone produces the STARK proof π.
 *   2. The orchestrator daemon (running on the relay ship) verifies π
 *      locally with `cpu_air_verifier`, then runs `stark_evm_adapter` to
 *      produce the EVM-compatible **fact** = `keccak256(programHash, outputHash)`.
 *   3. The relay ship calls `registerSafeProof(...)` with the fact
 *      components + extracted public outputs.
 *   4. This contract registers the fact (`verifiedFacts[factHash] = true`),
 *      stores extended proof metadata, and writes the SAFE verdict to the
 *      Registry.
 *   5. D's orchestrator polls Registry for dual-SAFE; on observing it,
 *      D fires `CommandLog.advance(...)` with a chosen speed (Pattern B).
 *
 * The cryptographic gate is the **off-chain `cpu_air_verifier`** — same
 * verifier used by the GPS Statement Verifier on Ethereum mainnet. The
 * relay ship's tx envelope signature only authenticates the submitter;
 * proof correctness is established before the fact reaches L1.
 *
 * Inheritance:
 *   - `Ownable` (OpenZeppelin) — operational ownership; the owner may
 *     update the relay-ship whitelist if a ship is replaced or
 *     compromised. Phase 2 deployer keeps ownership.
 *
 * @dev Inlines the FactRegistry pattern (StarkWare's
 *      `solidity/components/FactRegistry.sol` is small and stable —
 *      keeping it inline removes an external dep without losing the
 *      production-grade pattern).
 */
contract Verifier is Ownable {
    // ───────────────────────────────────────────────────────────────────
    //  FactRegistry pattern (inline — mirrors StarkWare's component)
    // ───────────────────────────────────────────────────────────────────
    mapping(bytes32 => bool) public verifiedFacts;

    /**
     * @notice External entry point of the inline FactRegistry — mirrors
     *         StarkWare's `FactRegistry.sol` `isValid(bytes32)` API.
     * @dev    Read-only; off-chain orchestrators poll this to confirm a
     *         fact has landed before issuing dependent transactions.
     * @param  fact keccak256(programHash || outputHash)
     * @return true iff the fact has been registered via a successful
     *         `registerSafeProof()` call.
     */
    function isValid(bytes32 fact) public view returns (bool) {
        return verifiedFacts[fact];
    }

    /**
     * @dev Internal write path of the inline FactRegistry. Idempotent —
     *      a duplicate registration is a no-op (no revert, no second
     *      event). Only callable from within `registerSafeProof()` so
     *      every registered fact is necessarily backed by validated
     *      public outputs.
     * @param fact keccak256(programHash || outputHash)
     */
    function _registerFact(bytes32 fact) internal {
        if (!verifiedFacts[fact]) {
            verifiedFacts[fact] = true;
            emit FactRegistered(fact);
        }
    }

    // ───────────────────────────────────────────────────────────────────
    //  Per-lane relay whitelist — only these addresses may submit facts
    //  for the corresponding drone_id (set in constructor; updatable by
    //  owner for ship replacement scenarios).
    // ───────────────────────────────────────────────────────────────────
    mapping(uint256 => address) public relayOf;     // droneId → relay address

    // ───────────────────────────────────────────────────────────────────
    //  Bound Registry contract — destination for setVerdict cross-calls
    // ───────────────────────────────────────────────────────────────────
    Registry public immutable registry;

    // ───────────────────────────────────────────────────────────────────
    //  Per-proof metadata (kept alongside the fact for audit + replay)
    // ───────────────────────────────────────────────────────────────────
    struct ProofRecord {
        bytes32 programHash;       // keccak256 of safe_area_verify.cairo bytecode
        bytes32 outputHash;        // keccak256 of ABI-encoded program output
        uint256 mid;               // mission id (matches Registry)
        uint256 droneId;           // 1 = α, 2 = β
        uint256 coveragePermille;  // public output: ≥ MissionSpec.coverageMin
        uint256 maxContactBp;      // public output: < MissionSpec.pMin
        uint256 elapsedSeconds;    // public output: ≤ MissionSpec.timeWindow
        bytes32 commitment;        // Poseidon H_β / H_α from L2
        uint256 nSteps;            // Cairo VM step count (provenance)
        uint256 timestamp;         // L1 block.timestamp at registration
        uint256 blockNumber;       // L1 block.number at registration
    }

    ProofRecord[] public proofs;
    uint256       public proofCount;

    // ───────────────────────────────────────────────────────────────────
    //  Events
    // ───────────────────────────────────────────────────────────────────
    event FactRegistered(bytes32 indexed factHash);
    event MissionVerified(
        uint256 indexed proofId,
        uint256 indexed mid,
        uint256 indexed droneId,
        bytes32         factHash,
        uint256         coveragePermille,
        uint256         maxContactBp,
        uint256         elapsedSeconds
    );
    event RelayUpdated(uint256 indexed droneId, address indexed previous, address indexed current);

    // ───────────────────────────────────────────────────────────────────
    //  Calldata struct — cleaner ABI for the 9-arg registerSafeProof call
    // ───────────────────────────────────────────────────────────────────
    struct SafeProofInputs {
        bytes32 programHash;
        bytes32 outputHash;
        uint256 mid;
        uint256 droneId;
        uint256 coveragePermille;
        uint256 maxContactBp;
        uint256 elapsedSeconds;
        bytes32 commitment;
        uint256 nSteps;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Constructor
    // ───────────────────────────────────────────────────────────────────

    /**
     * @param initialOwner  operational owner (may rotate relay whitelist)
     * @param registryAddr  the Registry contract this Verifier writes verdicts to
     * @param alphaRelay    ship F's address — only this address may submit α facts
     * @param bravoRelay    ship B's address — only this address may submit β facts
     */
    constructor(
        address initialOwner,
        address registryAddr,
        address alphaRelay,
        address bravoRelay
    )
        Ownable(initialOwner)
    {
        require(registryAddr != address(0), "Verifier: registry = 0x0");
        require(alphaRelay   != address(0), "Verifier: alphaRelay = 0x0");
        require(bravoRelay   != address(0), "Verifier: bravoRelay = 0x0");
        registry            = Registry(registryAddr);
        relayOf[Registry(registryAddr).DRONE_ALPHA()] = alphaRelay;
        relayOf[Registry(registryAddr).DRONE_BRAVO()] = bravoRelay;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Operational: rotate a relay address (owner only)
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Rotate the whitelisted relay address for a given drone
     *         lane. Used for ship replacement (e.g. ship F sunk → another
     *         escort assumes the α-relay role) without a full redeploy.
     * @dev    Only the contract owner may call. The relay change takes
     *         effect on the next `registerSafeProof()` call; in-flight
     *         transactions from the prior relay address are unaffected
     *         until they reach the mempool revert.
     * @param  droneId  DRONE_ALPHA (1) or DRONE_BRAVO (2)
     * @param  newRelay the L1 address authorised to submit facts for
     *                  this drone going forward
     */
    function setRelay(uint256 droneId, address newRelay) external onlyOwner {
        require(newRelay != address(0), "Verifier: relay = 0x0");
        require(droneId == registry.DRONE_ALPHA() || droneId == registry.DRONE_BRAVO(),
                "Verifier: invalid droneId");
        emit RelayUpdated(droneId, relayOf[droneId], newRelay);
        relayOf[droneId] = newRelay;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Core: register a SAFE proof fact (Phase 5 step 20 of the protocol)
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Register a verified SAFE_AREA proof's fact + write SAFE
     *         verdict to Registry.
     *
     * Restrictions enforced on-chain:
     *   - Caller must be the whitelisted relay for `inputs.droneId`.
     *   - Mission must exist in Registry (spec written by `Registry.deploy`).
     *   - Public outputs must satisfy the mission's thresholds:
     *     * `coveragePermille ≥ spec.coverageMin`
     *     * `maxContactBp     <  spec.pMin`
     *     * `elapsedSeconds   ≤  spec.timeWindow`
     *
     * @return proofId index in the `proofs[]` array (audit trail)
     * @return factHash the `keccak256(programHash, outputHash)` fact registered
     */
    function registerSafeProof(SafeProofInputs calldata inputs)
        external
        returns (uint256 proofId, bytes32 factHash)
    {
        require(msg.sender == relayOf[inputs.droneId], "Verifier: onlyRelay");

        Registry.MissionSpec memory spec = registry.getSpec(inputs.mid, inputs.droneId);
        require(spec.coverageMin > 0, "Verifier: unknown mission");

        // Threshold checks — these are exactly the SAFE_AREA criterion
        // re-asserted on-chain. The Cairo program already enforced them
        // off-chain (otherwise no proof would exist), but re-asserting
        // here means tampered facts can't smuggle in lower thresholds.
        require(
            inputs.coveragePermille >= spec.coverageMin,
            "Verifier: coverage < threshold"
        );
        require(
            inputs.maxContactBp < spec.pMin,
            "Verifier: maxContact >= pMin"
        );
        require(
            inputs.elapsedSeconds <= spec.timeWindow,
            "Verifier: time > window"
        );

        // 1. Register the fact (idempotent)
        factHash = keccak256(abi.encodePacked(inputs.programHash, inputs.outputHash));
        _registerFact(factHash);

        // 2. Store extended metadata
        proofId = proofs.length;
        proofs.push(ProofRecord({
            programHash:      inputs.programHash,
            outputHash:       inputs.outputHash,
            mid:              inputs.mid,
            droneId:          inputs.droneId,
            coveragePermille: inputs.coveragePermille,
            maxContactBp:     inputs.maxContactBp,
            elapsedSeconds:   inputs.elapsedSeconds,
            commitment:       inputs.commitment,
            nSteps:           inputs.nSteps,
            timestamp:        block.timestamp,
            blockNumber:      block.number
        }));
        proofCount = proofs.length;

        // 3. Write the verdict to Registry (cross-contract call gated by
        //    onlyVerifier modifier on Registry.setVerdict)
        registry.setVerdict(inputs.mid, inputs.droneId, true);

        // 4. Emit MissionVerified for D's orchestrator + frontend listeners
        emit MissionVerified(
            proofId,
            inputs.mid,
            inputs.droneId,
            factHash,
            inputs.coveragePermille,
            inputs.maxContactBp,
            inputs.elapsedSeconds
        );
    }

    // ───────────────────────────────────────────────────────────────────
    //  Read helpers (used by frontends + the dual-SAFE detector)
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Read the full audit record for a previously registered
     *         proof.
     * @dev    Records are append-only; `proofId` is the index in the
     *         `proofs[]` array and is also the value returned by
     *         `registerSafeProof()`. Reverts on out-of-range index so
     *         callers don't see an all-zero record by mistake.
     * @param  proofId  index into `proofs[]`
     * @return the 11-field ProofRecord (hashes, public outputs,
     *         commitment, L1 timestamp + block number)
     */
    function getProof(uint256 proofId) external view returns (ProofRecord memory) {
        require(proofId < proofs.length, "Verifier: invalid proofId");
        return proofs[proofId];
    }

    /**
     * @notice Convenience accessor for the most recent proof record.
     * @dev    Used by the front-end and by D's orchestrator to display
     *         the latest verification status without paginating through
     *         the full `proofs[]` array.
     * @return the ProofRecord at `proofs[proofs.length - 1]`
     */
    function getLatestProof() external view returns (ProofRecord memory) {
        require(proofs.length > 0, "Verifier: no proofs");
        return proofs[proofs.length - 1];
    }
}

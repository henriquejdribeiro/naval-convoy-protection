// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title  Registry
 * @notice Mission specs and per-(missionId, droneIndex) verdicts for the
 *         5-drone-per-swarm architecture.
 *
 * Two responsibilities:
 *
 *   1. **Mission deployment** — only the commander (D) may call
 *      `deploy()`. The mission spec now encodes the SAFE_AREA criterion
 *      thresholds AND the zone partition (zoneX/Y/W/H, nDrones,
 *      stripWidth) so the L1 Verifier can derive each drone's expected
 *      strip from `(missionId, droneIndex)`.
 *
 *   2. **Verdict storage** — only the Verifier contract may call
 *      `setVerdict()`. The Verifier writes a per-(missionId, droneIndex)
 *      flag as a side-effect of each successful STARK-proof
 *      registration. When all `nDrones` of a mission are SAFE, the
 *      Verifier additionally calls `setMissionSafe()` which writes the
 *      mission-level aggregate (missionSafe + aggH) — CommandLog reads
 *      that to gate `advance()`.
 *
 * Mission-id convention (preserved from the prior 2-drone-per-swarm rev
 * so off-chain tooling that filters by topic keeps working):
 *   - missionId = 1 → Alpha swarm  (relay ship F)
 *   - missionId = 2 → Bravo swarm  (relay ship B)
 *
 * The `MissionDeployed` event uses **indexed** `missionId` so each
 * relay-ship orchestrator can subscribe only to its own swarm.
 *
 * @dev Drone index within a mission is 1..nDrones (typically 1..5).
 *      Mission IDs are felt252-friendly small constants so they
 *      round-trip cleanly to L2 (felt252) without conversion.
 */
contract Registry is Ownable {
    // ───────────────────────────────────────────────────────────────────
    //  Mission-id convention constants (mirror L2 ConvoyProtocol)
    // ───────────────────────────────────────────────────────────────────
    uint256 public constant ALPHA_MISSION_ID = 1;
    uint256 public constant BRAVO_MISSION_ID = 2;

    // Back-compat aliases for legacy tests/scripts still referring to the
    // old per-drone naming. Same numeric values; semantics now is mission-id.
    uint256 public constant DRONE_ALPHA = ALPHA_MISSION_ID;
    uint256 public constant DRONE_BRAVO = BRAVO_MISSION_ID;

    // ───────────────────────────────────────────────────────────────────
    //  Mission spec — full zone + thresholds. The Verifier derives each
    //  drone's strip from (zoneX, zoneY, zoneW, zoneH, stripWidth)
    //  and droneIndex, so we DO NOT store per-drone strip bounds here
    //  (the spec captures everything needed to compute them).
    // ───────────────────────────────────────────────────────────────────
    struct MissionSpec {
        bytes32 areaHash;          // Poseidon hash of polygon vertices (provenance)
        uint32  zoneX;             // grid origin x
        uint32  zoneY;             // grid origin y
        uint32  zoneW;             // 15 (Alpha) or 20 (Bravo)
        uint32  zoneH;             // 8 (both swarms)
        uint8   nDrones;           // 5
        uint32  stripWidth;        // = zoneW / nDrones (must be exact; enforced at deploy)
        uint16  coverageMin;       // permille; 950 = ≥ 95% strip coverage
        uint16  pMin;              // basis points; 7000 = p_contact < 0.7
        uint64  timeWindow;        // seconds; 360 = 6 minutes
    }

    // ───────────────────────────────────────────────────────────────────
    //  Storage
    // ───────────────────────────────────────────────────────────────────

    /// @dev D's commander key; set once at deployment, no rotation path.
    ///      Fail-closed by design — see Verifier.sol commentary.
    address public immutable commander;

    /// @dev Bound Verifier contract; only it may write verdicts.
    address public verifier;

    uint256 public nextMissionId = 1;        // 0 reserved as "missing"

    /// missionId → spec.
    mapping(uint256 => MissionSpec) public specs;

    /// missionId → droneIndex (1..nDrones) → SAFE flag.
    mapping(uint256 => mapping(uint8 => bool)) public droneVerdict;

    /// missionId → number of drones that have flipped to SAFE.
    /// Updated by Verifier; capped at spec.nDrones.
    mapping(uint256 => uint8) public safeCount;

    /// missionId → all-drones-safe aggregate flag.
    ///   Flipped true exactly once, by Verifier, the moment the
    ///   nDrones-th SAFE submission lands.
    mapping(uint256 => bool) public missionSafe;

    /// missionId → aggregate Pedersen-chain of all nDrones commitments.
    ///   Computed off-chain by the Verifier (Pedersen chain over the H_i
    ///   values stored in its own ProofRecord[]) and written here at the
    ///   same time as missionSafe flips true.
    mapping(uint256 => bytes32) public missionAggH;

    // ───────────────────────────────────────────────────────────────────
    //  Events
    // ───────────────────────────────────────────────────────────────────
    event MissionDeployed(
        uint256 indexed missionId,
        MissionSpec     spec
    );
    event VerdictSet(
        uint256 indexed missionId,
        uint8   indexed droneIndex,
        bool            safe
    );
    event MissionSafe(
        uint256 indexed missionId,
        bytes32         aggH
    );
    event VerifierUpdated(address indexed previous, address indexed current);

    // ───────────────────────────────────────────────────────────────────
    //  Modifiers
    // ───────────────────────────────────────────────────────────────────

    /// @dev Restricts a function to the convoy commander key (ship D's
    ///      separate signing key, NOT D's validator key).
    modifier onlyCommander() {
        require(msg.sender == commander, "Registry: onlyCommander");
        _;
    }

    /// @dev Restricts a function to the bound Verifier contract.
    modifier onlyVerifier() {
        require(msg.sender == verifier, "Registry: onlyVerifier");
        _;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Constructor
    // ───────────────────────────────────────────────────────────────────

    /**
     * @param initialOwner      address that may update the verifier later
     * @param commanderAddress  D's commander key address.
     */
    constructor(address initialOwner, address commanderAddress) Ownable(initialOwner) {
        require(commanderAddress != address(0), "Registry: commander = 0x0");
        commander = commanderAddress;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Verifier wiring — set once after Verifier is deployed
    // ───────────────────────────────────────────────────────────────────

    function setVerifier(address verifierAddress) external onlyOwner {
        require(verifierAddress != address(0), "Registry: verifier = 0x0");
        emit VerifierUpdated(verifier, verifierAddress);
        verifier = verifierAddress;
    }

    // ───────────────────────────────────────────────────────────────────
    //  deploy(missionId, spec) — Phase 1 step 1 of the protocol
    //
    //  Caller supplies the missionId explicitly (must be 1 for Alpha,
    //  2 for Bravo per the convention) — this lets the off-chain
    //  generator pre-commit to which mission-id maps to which swarm
    //  without depending on call ordering. The first attempted re-deploy
    //  of a missionId reverts (idempotency at the contract level).
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Register a new mission spec (one call per swarm — one
     *         spec covers all `spec.nDrones` drones in that swarm).
     * @dev    Only the commander (D) may call. Each mission-id can only
     *         be deployed once.
     */
    function deploy(uint256 missionId, MissionSpec calldata spec)
        external
        onlyCommander
    {
        require(missionId == ALPHA_MISSION_ID || missionId == BRAVO_MISSION_ID,
                "Registry: invalid missionId");
        require(specs[missionId].nDrones == 0, "Registry: mission already deployed");

        // Spec sanity
        require(spec.nDrones > 0,                                  "Registry: nDrones = 0");
        require(spec.zoneW > 0 && spec.zoneH > 0,                  "Registry: zone dims = 0");
        require(spec.stripWidth > 0,                               "Registry: stripWidth = 0");
        require(spec.zoneW == spec.stripWidth * uint32(spec.nDrones),
                "Registry: zoneW != stripWidth * nDrones");
        require(spec.coverageMin > 0 && spec.coverageMin <= 1000,  "Registry: bad coverageMin");
        require(spec.pMin > 0 && spec.pMin <= 10000,               "Registry: bad pMin");
        require(spec.timeWindow > 0,                               "Registry: bad timeWindow");

        specs[missionId] = spec;

        // Keep nextMissionId monotone for any callers that still use it
        // as a "deployed missions count" probe.
        if (missionId >= nextMissionId) {
            nextMissionId = missionId + 1;
        }

        emit MissionDeployed(missionId, spec);
    }

    // ───────────────────────────────────────────────────────────────────
    //  setVerdict — Verifier writes one drone's verdict after STARK pass
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Mark a (missionId, droneIndex) verdict as SAFE.
     * @dev    Only the bound Verifier may call. Reverts if:
     *           - mission not deployed
     *           - droneIndex out of range [1, nDrones]
     *           - already SAFE (idempotent fast-path returns rather than
     *             reverting, so re-submission attempts don't break the
     *             aggregation)
     * @return drones now SAFE for this mission (= old safeCount + 1 unless
     *         idempotent no-op, in which case == old safeCount)
     */
    function setVerdict(uint256 missionId, uint8 droneIndex)
        external
        onlyVerifier
        returns (uint8)
    {
        MissionSpec storage spec = specs[missionId];
        require(spec.nDrones > 0,                          "Registry: unknown mission");
        require(droneIndex >= 1 && droneIndex <= spec.nDrones,
                                                            "Registry: droneIndex out of range");

        if (droneVerdict[missionId][droneIndex]) {
            // Idempotent re-submission — no double-counting.
            return safeCount[missionId];
        }

        droneVerdict[missionId][droneIndex] = true;
        uint8 newCount = safeCount[missionId] + 1;
        safeCount[missionId] = newCount;
        emit VerdictSet(missionId, droneIndex, true);
        return newCount;
    }

    /**
     * @notice Write the mission-level aggregate after all `nDrones` have
     *         landed SAFE.
     * @dev    Only the bound Verifier may call. Reverts if missionSafe is
     *         already set (idempotent), or if safeCount != nDrones.
     */
    function setMissionSafe(uint256 missionId, bytes32 aggH) external onlyVerifier {
        MissionSpec storage spec = specs[missionId];
        require(spec.nDrones > 0,                "Registry: unknown mission");
        require(safeCount[missionId] == spec.nDrones,
                                                  "Registry: not all drones SAFE");
        require(!missionSafe[missionId],         "Registry: mission already SAFE");

        missionSafe[missionId] = true;
        missionAggH[missionId] = aggH;
        emit MissionSafe(missionId, aggH);
    }

    // ───────────────────────────────────────────────────────────────────
    //  View helpers (used by CommandLog + frontends)
    // ───────────────────────────────────────────────────────────────────

    function getSpec(uint256 missionId) external view returns (MissionSpec memory) {
        return specs[missionId];
    }

    function isMissionSafe(uint256 missionId) external view returns (bool) {
        return missionSafe[missionId];
    }

    function isDroneSafe(uint256 missionId, uint8 droneIndex) external view returns (bool) {
        return droneVerdict[missionId][droneIndex];
    }

    /**
     * @notice Dual-mission SAFE — convoy advance precondition.
     * @dev    CommandLog.advance() calls this to enforce that both swarms
     *         have ALL nDrones SAFE before the convoy may move.
     */
    function isDualSafe(uint256 alphaMissionId, uint256 bravoMissionId)
        external
        view
        returns (bool)
    {
        return missionSafe[alphaMissionId] && missionSafe[bravoMissionId];
    }
}

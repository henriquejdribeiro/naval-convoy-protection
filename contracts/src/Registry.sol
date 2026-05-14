// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title  Registry
 * @notice Mission specs and per-(missionId, drone_id) verdicts.
 *
 * Two responsibilities:
 *
 *   1. **Mission deployment** — only the commander (D) may call
 *      `deploy()`. The mission spec encodes the SAFE_AREA criterion
 *      thresholds (coverage, p_min, time_window) plus the polygon hash.
 *      Each deploy mints a fresh `missionId`.
 *
 *   2. **Verdict storage** — only the Verifier contract may call
 *      `setVerdict()`. The Verifier writes here as a side-effect of
 *      successfully registering a SAFE proof; D's orchestrator polls
 *      `verdict[missionId][drone_id]` to know when both lanes are SAFE before
 *      firing the convoy advance (Pattern B).
 *
 * The `MissionDeployed` event uses **indexed** `missionId` and `drone_id` so the
 * relay-ship orchestrators (B for β, F for α) can subscribe to just their
 * own lane via topic filtering. No on-chain dispatch — the contract emits;
 * off-chain handlers act per `orchestrator.toml` config.
 *
 * @dev Drone ids are felt252-friendly small constants (1 = α, 2 = β) so
 *      the same value round-trips between L1 (uint256) and L2 (felt252)
 *      without conversion.
 */
contract Registry is Ownable {
    // ───────────────────────────────────────────────────────────────────
    //  Drone id constants (mirror the Cairo contract on L2)
    // ───────────────────────────────────────────────────────────────────
    uint256 public constant DRONE_ALPHA = 1;
    uint256 public constant DRONE_BRAVO = 2;

    // ───────────────────────────────────────────────────────────────────
    //  Mission spec — per protocol.md encodings
    // ───────────────────────────────────────────────────────────────────
    struct MissionSpec {
        bytes32 areaHash;          // Poseidon hash of polygon vertices
        uint16  coverageMin;       // permille: 950 = ≥ 95% cells
        uint16  pMin;              // basis points: 7000 = p_contact ≥ 0.7
        uint64  timeWindow;        // seconds: 360 = 6 min
    }

    // ───────────────────────────────────────────────────────────────────
    //  Storage
    // ───────────────────────────────────────────────────────────────────
    /// @dev D's commander key, distinct from D's validator key. Set
    ///      once at deployment and immutable thereafter — by design,
    ///      the protocol provides no on-chain rotation path. If the
    ///      commander key is lost or compromised, the entire contract
    ///      suite must be re-deployed. This is a deliberate fail-closed
    ///      semantic: it removes any administrative-vector attack on
    ///      the highest-privilege role and gives the convoy a single,
    ///      unambiguous authority for mission deployment.
    address public immutable commander;
    address public verifier;        // Verifier contract address (set after Verifier deploy)

    uint256 public nextMissionId = 1;        // 0 reserved as "missing"

    // missionId → (drone_id → spec).  Storing per-(missionId, drone) keeps the schema
    // identical for both lanes; the deploy() call writes one slot per
    // (missionId, drone_id) tuple.
    mapping(uint256 => mapping(uint256 => MissionSpec)) public specs;

    // missionId → (drone_id → SAFE flag).  False until Verifier sets it true.
    mapping(uint256 => mapping(uint256 => bool)) public verdict;

    // ───────────────────────────────────────────────────────────────────
    //  Events
    // ───────────────────────────────────────────────────────────────────
    event MissionDeployed(
        uint256 indexed missionId,
        uint256 indexed droneId,
        MissionSpec     spec
    );
    event VerdictSet(
        uint256 indexed missionId,
        uint256 indexed droneId,
        bool            safe
    );
    event VerifierUpdated(address indexed previous, address indexed current);

    // ───────────────────────────────────────────────────────────────────
    //  Modifiers
    // ───────────────────────────────────────────────────────────────────

    /// @dev Restricts a function to the convoy commander key (ship D's
    ///      separate signing key, NOT D's validator key). Used to gate
    ///      `deploy()` so only the tactical commander may register
    ///      missions.
    modifier onlyCommander() {
        require(msg.sender == commander, "Registry: onlyCommander");
        _;
    }

    /// @dev Restricts a function to the bound Verifier contract. Used to
    ///      gate `setVerdict()`: the Verifier is the only authority that
    ///      may flip a (missionId, drone_id) verdict to SAFE, and only after a
    ///      successful STARK-proof registration.
    modifier onlyVerifier() {
        require(msg.sender == verifier, "Registry: onlyVerifier");
        _;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Constructor
    // ───────────────────────────────────────────────────────────────────

    /**
     * @param initialOwner address that may update the verifier later
     *        (kept under Ownable for operational hygiene; not needed for
     *        Phase 2 acceptance).
     * @param commanderAddress D's commander key address.
     */
    constructor(address initialOwner, address commanderAddress) Ownable(initialOwner) {
        require(commanderAddress != address(0), "Registry: commander = 0x0");
        commander = commanderAddress;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Verifier wiring — set once after Verifier is deployed
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Bind the Verifier contract that may write verdicts.
     * @dev    Idempotent: callable multiple times by the owner if the
     *         Verifier needs to be redeployed during Phase 2 development.
     *         In production this would be locked after first set.
     */
    function setVerifier(address verifierAddress) external onlyOwner {
        require(verifierAddress != address(0), "Registry: verifier = 0x0");
        emit VerifierUpdated(verifier, verifierAddress);
        verifier = verifierAddress;
    }

    // ───────────────────────────────────────────────────────────────────
    //  deploy(droneId, spec) — Phase 1 step 1 of the protocol
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Register a new mission for a specific drone lane.
     * @dev    Only the commander (D) may call. Each call increments
     *         `nextMissionId` and stores the spec under (missionId, droneId).
     * @return missionId the freshly-minted mission id.
     */
    function deploy(uint256 droneId, MissionSpec calldata spec)
        external
        onlyCommander
        returns (uint256 missionId)
    {
        require(
            droneId == DRONE_ALPHA || droneId == DRONE_BRAVO,
            "Registry: invalid droneId"
        );
        require(spec.coverageMin > 0 && spec.coverageMin <= 1000, "Registry: bad coverageMin");
        require(spec.pMin > 0 && spec.pMin <= 10000, "Registry: bad pMin");
        require(spec.timeWindow > 0, "Registry: bad timeWindow");

        missionId = nextMissionId++;
        specs[missionId][droneId] = spec;

        emit MissionDeployed(missionId, droneId, spec);
    }

    // ───────────────────────────────────────────────────────────────────
    //  setVerdict — called by Verifier after registerSafeProof succeeds
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Mark a (missionId, droneId) verdict as SAFE.
     * @dev    Only the bound Verifier contract may call. Idempotent —
     *         re-setting an already-SAFE verdict is a no-op.
     */
    function setVerdict(uint256 missionId, uint256 droneId, bool safe) external onlyVerifier {
        require(specs[missionId][droneId].coverageMin > 0, "Registry: unknown mission");
        require(safe, "Registry: only SAFE verdicts written");
        verdict[missionId][droneId] = true;
        emit VerdictSet(missionId, droneId, true);
    }

    // ───────────────────────────────────────────────────────────────────
    //  View helpers (used by CommandLog.advance + frontends)
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Read the spec a mission was deployed with.
     * @dev    Returned by value (memory copy). The Verifier reads this
     *         to re-assert SAFE_AREA thresholds before flipping a
     *         verdict; UI front-ends read it to render mission cards.
     * @param  missionId     mission id minted by `deploy()`
     * @param  droneId DRONE_ALPHA (1) or DRONE_BRAVO (2)
     * @return the full MissionSpec; all fields are zero if the mission
     *         does not exist.
     */
    function getSpec(uint256 missionId, uint256 droneId) external view returns (MissionSpec memory) {
        return specs[missionId][droneId];
    }

    /**
     * @notice Whether a single lane's verdict has been written to SAFE.
     * @dev    The verdict is only flipped to true by the Verifier after
     *         a successful proof registration; there is no path to
     *         unset it.
     * @param  missionId     mission id
     * @param  droneId DRONE_ALPHA (1) or DRONE_BRAVO (2)
     * @return true iff the proof for (missionId, droneId) has been verified
     *         on-chain and the verdict written.
     */
    function isSafe(uint256 missionId, uint256 droneId) external view returns (bool) {
        return verdict[missionId][droneId];
    }

    /**
     * @notice Dual-SAFE convenience: both lanes SAFE for the convoy
     *         advance precondition.
     * @dev    Called by CommandLog.advance() to enforce that the
     *         convoy only moves once both α and β lanes have
     *         cryptographic SAFE verdicts. Pattern B — the commander
     *         still has to explicitly invoke advance(); this view does
     *         not auto-fire anything.
     * @param  alphaMissionId mission id for the α lane
     * @param  bravoMissionId  mission id for the β lane
     * @return true iff verdict[alphaMissionId][α] AND verdict[bravoMissionId][β]
     *         are both SAFE.
     */
    function isDualSafe(uint256 alphaMissionId, uint256 bravoMissionId) external view returns (bool) {
        return verdict[alphaMissionId][DRONE_ALPHA] && verdict[bravoMissionId][DRONE_BRAVO];
    }
}

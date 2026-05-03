// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title  Registry
 * @notice Mission specs and per-(mid, drone_id) verdicts.
 *
 * Two responsibilities:
 *
 *   1. **Mission deployment** — only the commander (D) may call
 *      `deploy()`. The mission spec encodes the SAFE_AREA criterion
 *      thresholds (coverage, p_min, time_window) plus the polygon hash.
 *      Each deploy mints a fresh `mid`.
 *
 *   2. **Verdict storage** — only the Verifier contract may call
 *      `setVerdict()`. The Verifier writes here as a side-effect of
 *      successfully registering a SAFE proof; D's orchestrator polls
 *      `verdict[mid][drone_id]` to know when both lanes are SAFE before
 *      firing the convoy advance (Pattern B).
 *
 * The `MissionDeployed` event uses **indexed** `mid` and `drone_id` so the
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
    address public commander;       // D's commander key (separate from validator key)
    address public verifier;        // Verifier contract address (set after Verifier deploy)

    uint256 public nextMissionId = 1;        // 0 reserved as "missing"

    // mid → (drone_id → spec).  Storing per-(mid, drone) keeps the schema
    // identical for both lanes; the deploy() call writes one slot per
    // (mid, drone_id) tuple.
    mapping(uint256 => mapping(uint256 => MissionSpec)) public specs;

    // mid → (drone_id → SAFE flag).  False until Verifier sets it true.
    mapping(uint256 => mapping(uint256 => bool)) public verdict;

    // ───────────────────────────────────────────────────────────────────
    //  Events
    // ───────────────────────────────────────────────────────────────────
    event MissionDeployed(
        uint256 indexed mid,
        uint256 indexed droneId,
        MissionSpec     spec
    );
    event VerdictSet(
        uint256 indexed mid,
        uint256 indexed droneId,
        bool            safe
    );
    event VerifierUpdated(address indexed previous, address indexed current);

    // ───────────────────────────────────────────────────────────────────
    //  Modifiers
    // ───────────────────────────────────────────────────────────────────
    modifier onlyCommander() {
        require(msg.sender == commander, "Registry: onlyCommander");
        _;
    }

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
     *         `nextMissionId` and stores the spec under (mid, droneId).
     * @return mid the freshly-minted mission id.
     */
    function deploy(uint256 droneId, MissionSpec calldata spec)
        external
        onlyCommander
        returns (uint256 mid)
    {
        require(
            droneId == DRONE_ALPHA || droneId == DRONE_BRAVO,
            "Registry: invalid droneId"
        );
        require(spec.coverageMin > 0 && spec.coverageMin <= 1000, "Registry: bad coverageMin");
        require(spec.pMin > 0 && spec.pMin <= 10000, "Registry: bad pMin");
        require(spec.timeWindow > 0, "Registry: bad timeWindow");

        mid = nextMissionId++;
        specs[mid][droneId] = spec;

        emit MissionDeployed(mid, droneId, spec);
    }

    // ───────────────────────────────────────────────────────────────────
    //  setVerdict — called by Verifier after registerSafeProof succeeds
    // ───────────────────────────────────────────────────────────────────

    /**
     * @notice Mark a (mid, droneId) verdict as SAFE.
     * @dev    Only the bound Verifier contract may call. Idempotent —
     *         re-setting an already-SAFE verdict is a no-op.
     */
    function setVerdict(uint256 mid, uint256 droneId, bool safe) external onlyVerifier {
        require(specs[mid][droneId].coverageMin > 0, "Registry: unknown mission");
        require(safe, "Registry: only SAFE verdicts written");
        verdict[mid][droneId] = true;
        emit VerdictSet(mid, droneId, true);
    }

    // ───────────────────────────────────────────────────────────────────
    //  View helpers (used by CommandLog.advance + frontends)
    // ───────────────────────────────────────────────────────────────────

    function getSpec(uint256 mid, uint256 droneId) external view returns (MissionSpec memory) {
        return specs[mid][droneId];
    }

    function isSafe(uint256 mid, uint256 droneId) external view returns (bool) {
        return verdict[mid][droneId];
    }

    function isDualSafe(uint256 alphaMid, uint256 betaMid) external view returns (bool) {
        return verdict[alphaMid][DRONE_ALPHA] && verdict[betaMid][DRONE_BRAVO];
    }
}

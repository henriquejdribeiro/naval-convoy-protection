// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// Minimal interface to the L1↔L2 message bridge (StarknetCoreStub in dev,
/// real StarknetMessaging.sol on mainnet). Only the L1→L2 path is used
/// from this contract.
interface IStarknetMessaging {
    function sendMessageToL2(
        uint256          toAddress,
        uint256          selector,
        uint256[] calldata payload
    ) external payable returns (bytes32 msgHash, uint256 nonce);
}

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

    // Starknet selector for the L2 `open_mission` #[l1_handler]. Madara
    // routes any L1→L2 message whose `selector` field equals this value
    // to the convoy_protocol contract's `open_mission(from_address, spec,
    // drone_addresses)` handler. Computed as `starknet_keccak("open_mission")`.
    uint256 public constant OPEN_MISSION_SELECTOR =
        0x01381a5270fc622706a5aab78c38befa97ad661a0b93c5ca016ad2581862b2df;

    // Number of drones per swarm — matches the L2 contract's hard-coded
    // expectation. Used to size the drone_addresses array in the L1→L2
    // payload.
    uint8 public constant N_DRONES = 5;

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

    /// @dev L1↔L2 message bridge (StarknetCoreStub in dev, real
    ///      StarknetMessaging on mainnet). Bound at construction; deploy()
    ///      sends the L1→L2 open_mission message through this contract so
    ///      every mission deployment is anchored on the L1 chain with a
    ///      verifiable LogMessageToL2 event.
    IStarknetMessaging public immutable starknetCore;

    /// @dev Bound Verifier contract; only it may write verdicts.
    address public verifier;

    /// @dev Per-mission L2 convoy_protocol address — different on alpha
    ///      vs bravo because they're deployed on different Madara chains.
    ///      Set by the commander before deploy() so the L1→L2 message
    ///      knows which L2 contract address to dispatch open_mission to.
    mapping(uint256 => uint256) public convoyProtocolL2;

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
     * @param initialOwner       address that may update the verifier + L2 addresses
     * @param commanderAddress   D's commander key address (signs deploy + advance)
     * @param starknetCoreAddr   StarknetCoreStub (dev) or StarknetMessaging (mainnet)
     */
    constructor(
        address initialOwner,
        address commanderAddress,
        address starknetCoreAddr
    ) Ownable(initialOwner) {
        require(commanderAddress != address(0), "Registry: commander = 0x0");
        require(starknetCoreAddr != address(0), "Registry: starknetCore = 0x0");
        commander    = commanderAddress;
        starknetCore = IStarknetMessaging(starknetCoreAddr);
    }

    /// @notice Bind a mission-id to its L2 convoy_protocol contract address.
    /// @dev    Owner-only because the L2 address comes from `deploy-l2.sh`
    ///         output and isn't known at contract-construction time. Must be
    ///         set before `deploy()` so the L1→L2 message knows where to go.
    function setConvoyProtocolL2(uint256 missionId, uint256 l2Addr) external onlyOwner {
        require(l2Addr != 0, "Registry: l2Addr = 0");
        convoyProtocolL2[missionId] = l2Addr;
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
     * @notice Register a new mission spec AND dispatch the L1→L2 message
     *         that opens the matching mission on the swarm's Madara.
     *
     * @dev    Only the commander (D) may call. Each mission-id can only
     *         be deployed once. The L1 store is the audit trail; the L1→L2
     *         message is the protocol's authoritative mission-open
     *         instruction — when Madara's L1 sync is active, it routes
     *         this message to `convoy_protocol.open_mission(from_address,
     *         spec, drone_addresses)` and the L2 state mirrors L1's.
     *
     * @param missionId        1 = Alpha, 2 = Bravo
     * @param spec             Mission spec (zone geometry + thresholds).
     *                         The L1 store keeps only this struct; the
     *                         (mission_id, swarm_id, ts_start) extras
     *                         needed by the L2 spec are reconstructed in
     *                         the payload-building step.
     * @param droneAddresses   The 5 L2 ContractAddresses (as uint256) that
     *                         will be authorised as drones for this
     *                         mission, in order — index 0 → drone_id 1,
     *                         index 4 → drone_id 5. The L2 contract
     *                         registers each against (mission_id, drone_id).
     * @param tsStart          Mission start timestamp (unix seconds). All
     *                         cell timestamps the drones submit must fall
     *                         within [tsStart, tsStart + spec.timeWindow].
     */
    function deploy(
        uint256 missionId,
        MissionSpec calldata spec,
        uint256[N_DRONES] calldata droneAddresses,
        uint256 tsStart
    )
        external payable
        onlyCommander
    {
        require(missionId == ALPHA_MISSION_ID || missionId == BRAVO_MISSION_ID,
                "Registry: invalid missionId");
        require(specs[missionId].nDrones == 0, "Registry: mission already deployed");
        require(convoyProtocolL2[missionId] != 0,
                "Registry: L2 contract addr not set");

        // Spec sanity
        require(spec.nDrones == N_DRONES,                          "Registry: nDrones must be 5");
        require(spec.zoneW > 0 && spec.zoneH > 0,                  "Registry: zone dims = 0");
        require(spec.stripWidth > 0,                               "Registry: stripWidth = 0");
        require(spec.zoneW == spec.stripWidth * uint32(spec.nDrones),
                "Registry: zoneW != stripWidth * nDrones");
        require(spec.coverageMin > 0 && spec.coverageMin <= 1000,  "Registry: bad coverageMin");
        require(spec.pMin > 0 && spec.pMin <= 10000,               "Registry: bad pMin");
        require(spec.timeWindow > 0,                               "Registry: bad timeWindow");
        require(tsStart > 0,                                       "Registry: tsStart = 0");

        specs[missionId] = spec;

        // Keep nextMissionId monotone for any callers that still use it
        // as a "deployed missions count" probe.
        if (missionId >= nextMissionId) {
            nextMissionId = missionId + 1;
        }

        emit MissionDeployed(missionId, spec);

        // ────────── L1 → L2 mission-open message ──────────
        //
        // Payload layout matches the Cairo Serde for the L2 handler's args:
        //   open_mission(from_address: felt252,         (auto-set by Madara,
        //                                                NOT in payload)
        //                spec:            MissionSpec,  (12 felts)
        //                drone_addresses: Array<CA>)    (1 length + 5 elements)
        //
        // L2 MissionSpec field order — must match cairo/convoy_protocol/src/lib.cairo:
        //   mission_id, swarm_id, zone_x, zone_y, zone_w, zone_h,
        //   n_drones, strip_width, coverage_min, p_min, time_window, ts_start
        //
        // swarm_id == mission_id in our convention (alpha=1, bravo=2).
        uint256[] memory payload = new uint256[](18);
        payload[0]  = missionId;                       // spec.mission_id
        payload[1]  = missionId;                       // spec.swarm_id (= mission_id)
        payload[2]  = uint256(spec.zoneX);
        payload[3]  = uint256(spec.zoneY);
        payload[4]  = uint256(spec.zoneW);
        payload[5]  = uint256(spec.zoneH);
        payload[6]  = uint256(spec.nDrones);
        payload[7]  = uint256(spec.stripWidth);
        payload[8]  = uint256(spec.coverageMin);
        payload[9]  = uint256(spec.pMin);
        payload[10] = uint256(spec.timeWindow);
        payload[11] = tsStart;
        payload[12] = N_DRONES;                        // Array<ContractAddress> length
        payload[13] = droneAddresses[0];
        payload[14] = droneAddresses[1];
        payload[15] = droneAddresses[2];
        payload[16] = droneAddresses[3];
        payload[17] = droneAddresses[4];

        starknetCore.sendMessageToL2{value: msg.value}(
            convoyProtocolL2[missionId],
            OPEN_MISSION_SELECTOR,
            payload
        );
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

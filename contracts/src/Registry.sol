// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";  // Registry is Ownable (owner-only config)

/// Minimal, self-declared interface to the Core's L1→L2 SEND path. Parallels the
/// Verifier's IStarknetMessagingConsumer, but for the opposite direction: the
/// Registry SENDS (Registry.deploy → sendMessageToL2 queues the open_mission
/// order to L2), whereas the Verifier CONSUMES. Only sendMessageToL2 is declared
/// because that's the only Core function this contract uses. Talking to the Core
/// by interface+address (not import) keeps it Core-agnostic: StarknetCoreStub in
/// dev, real StarknetMessaging.sol in prod, unchanged. payable = the real Core
/// charges an L1→L2 delivery fee (msg.value).
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
 *      `setVerdict()`. When mission SAFE, the
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

    // ── Mission spec — L1's record of a mission (Registry.specs[missionId]).
    //    L1 counterpart to convoy_protocol.MissionSpec, but a DIFFERENT schema:
    //    shares the geometry+thresholds, ADDS areaHash (L1-only provenance), and
    //    OMITS mission_id (it's the map key), ts_start (a separate deploy arg),
    //    and swarm_id (implied by mission_id: 1=Alpha, 2=Bravo).
    //
    //    NOTE: L1 reads only nDrones (Verifier's cross-check); the rest is stored
    //    as the anchor + forwarded to L2 in the open_mission payload.
    // ───────────────────────────────────────────────────────────────────
    struct MissionSpec {
        bytes32 areaHash;          // L1-ONLY: Poseidon hash of the zone polygon (provenance); not sent to L2
        uint32  zoneX;             // grid origin x
        uint32  zoneY;             // grid origin y
        uint32  zoneW;             // 15 (Alpha) or 20 (Bravo)
        uint32  zoneH;             // 8 (both swarms)
        uint8   nDrones;           // 5 — the ONLY field L1 logic reads (drone-count cross-check)
        uint32  stripWidth;        // = zoneW / nDrones (must be exact; enforced at deploy)
        uint16  coverageMin;       // permille; 950 = ≥ 95% strip coverage
        uint16  pMin;              // basis points; 7000 = p_contact < 0.7
        uint64  timeWindow;        // seconds; 360 = 6 minutes
    }

    // ───────────────────────────────────────────────────────────────────
    //  Storage
    // ───────────────────────────────────────────────────────────────────

    // ── Immutable anchors (locked at deployment) ────────────────────────
    /// @dev Commander (ship D) key — the only caller allowed to deploy() a
    ///      mission. No rotation path (fail-closed; see CommandLog.sol).
    address public immutable commander;

    /// @dev L1↔L2 message bridges — ONE per swarm. Each swarm is its own Madara
    ///      L2 chain, so each settles on its OWN StarkWare core. deploy(missionId)
    ///      routes the open_mission message to that swarm's core, so each
    ///      sequencer's L1 sync sees only the messages for its chain.
    IStarknetMessaging public immutable alphaCore;
    IStarknetMessaging public immutable bravoCore;

    // ── Mutable bindings (set AFTER deploy, cross-contract ordering) ─────
    /// @dev Bound Verifier — only it may write verdicts. Not immutable: Verifier
    ///      is deployed after Registry, so it's wired later via setVerifier.
    address public verifier;

    /// @dev Per-mission L2 convoy_protocol address — different on alpha
    ///      vs bravo because they're deployed on different Madara chains.
    ///      Set by the commander before deploy() so the L1→L2 message
    ///      knows which L2 contract address to dispatch open_mission to.
    mapping(uint256 => uint256) public convoyProtocolL2;

    uint256 public nextMissionId = 1;        // 0 reserved as "missing"

    /// missionId → spec.
    mapping(uint256 => MissionSpec) public specs;

    // ── Per-mission state ───────────────────────────────────────────────
    /// @dev THE live flag: all-drones-safe. Flipped once by setMissionSafe;
    ///      read by isDualSafe / CommandLog. This is the real state-of-truth.
    mapping(uint256 => bool) public missionSafe;

    mapping(uint256 => bytes32) public missionAggH;

    // ───────────────────────────────────────────────────────────────────
    //  Events
    // ───────────────────────────────────────────────────────────────────

    /// @notice Emitted by deploy() when the commander issues a mission order.
    ///         Carries the FULL spec as data so off-chain can reconstruct it from
    ///         the log. indexed missionId → relay orchestrators filter by swarm.
    event MissionDeployed(
        uint256 indexed missionId,
        MissionSpec     spec
    );

    /// @notice Emitted by setMissionSafe when a mission flips SAFE on L1. The live
    ///         "verified" event. NOTE: aggH is always bytes32(0) now (vestigial).
    ///         Distinct from L2's MissionSafe and Verifier's MissionSafeConsumed.
    event MissionSafe(
        uint256 indexed missionId,
        bytes32         aggH
    );

    /// @notice Emitted by setVerifier when the bound Verifier changes — security
    ///         audit trail of who is trusted to write verdicts.
    event VerifierUpdated(address indexed previous, address indexed current);

    // ───────────────────────────────────────────────────────────────────
    //  Modifiers - authority model
    // ───────────────────────────────────────────────────────────────────

    /// @dev Only the commander (ship D's SEPARATE commander key, NOT its geth
    ///      validator key) may call — used on deploy(). Separating the keys means
    ///      commanding the convoy ≠ validating blocks (defense in depth).
    ///      `commander` is immutable → this authority is locked (fail-closed).
    modifier onlyCommander() {
        require(msg.sender == commander, "Registry: onlyCommander");
        _;
    }

    /// @dev Only the bound Verifier CONTRACT may call — used on setMissionSafe/
    ///      setVerdict. msg.sender is the Verifier itself (contract-call semantics).
    ///      So verdicts can be WRITTEN only by the Verifier, even though anyone can
    ///      TRIGGER the Verifier's consumeL2Message. NOTE: `verifier` is mutable
    ///      (owner rebindable) → this trust is as strong as the owner key.
    modifier onlyVerifier() {
        require(msg.sender == verifier, "Registry: onlyVerifier");
        _;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Constructor
    // ───────────────────────────────────────────────────────────────────

    /*
     * @param initialOwner       address that may update the verifier + L2 addresses
     * @param commanderAddress   D's commander key address (signs deploy + advance)
     * @param alphaCoreAddr      alpha swarm's L1 StarkWare messaging core (real Starknet.sol)
     * @param bravoCoreAddr      bravo swarm's L1 StarkWare messaging core (real Starknet.sol)
     */
    constructor(
        address initialOwner,
        address commanderAddress,
        address alphaCoreAddr,
        address bravoCoreAddr
    ) Ownable(initialOwner) {
        require(commanderAddress != address(0), "Registry: commander = 0x0");
        require(alphaCoreAddr    != address(0), "Registry: alphaCore = 0x0");
        require(bravoCoreAddr    != address(0), "Registry: bravoCore = 0x0");
        commander = commanderAddress;
        alphaCore = IStarknetMessaging(alphaCoreAddr);   // alpha swarm's L1→L2 core
        bravoCore = IStarknetMessaging(bravoCoreAddr);   // bravo swarm's L1→L2 core
    }

    /// @dev The L1↔L2 core for a mission's swarm (bravo=2 → bravoCore, else alphaCore).
    function _coreFor(uint256 missionId) internal view returns (IStarknetMessaging) {
        return missionId == BRAVO_MISSION_ID ? bravoCore : alphaCore;
    }

    /// @notice Bind a mission to its L2 convoy_protocol address = the DESTINATION
    ///         of the L1→L2 open_mission send in deploy(). (Pairs with the
    ///         Verifier's expectedL2Sender, the receive-from side.)
    /// @dev    onlyOwner; late-bound because the L2 address only exists after
    ///         deploy-l2.sh. Must run before deploy(). register-missions step 1a.
    ///         (Owner-mutable, and — unlike the Verifier's version — emits no event.)
    function setConvoyProtocolL2(uint256 missionId, uint256 l2Addr) external onlyOwner {
        require(l2Addr != 0, "Registry: l2Addr = 0");
        convoyProtocolL2[missionId] = l2Addr;
    }

    // ───────────────────────────────────────────────────────────────────
    //  Verifier wiring — set once after Verifier is deployed
    // ───────────────────────────────────────────────────────────────────

    /// @notice Bind the Verifier contract that's allowed to write verdicts
    ///         (onlyVerifier). Separate from the constructor because the Verifier
    ///         is deployed AFTER the Registry — this is DeployL1's last step.
    /// @dev    onlyOwner: guards the verdict-writer trust anchor (an unrestricted
    ///         version would let anyone bind a malicious "verifier" and forge SAFE).
    ///         Emits BEFORE the write so VerifierUpdated captures the OLD value as
    ///         `previous`. No re-bind guard → owner CAN rebind (the event exists to
    ///         audit exactly that); owner-mutable trust — harden for prod.
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
        uint256[N_DRONES] calldata droneAddresses, // fixed-size → ABI enforces exactly 5
        uint256 tsStart                            // separate: L1 spec doesn't store ts_start
    )
        external payable // payable: forwards the L1→L2 fee
        onlyCommander
    {
        require(missionId == ALPHA_MISSION_ID || missionId == BRAVO_MISSION_ID,
                "Registry: invalid missionId");  // only 1 or 2
        require(specs[missionId].nDrones == 0, "Registry: mission already deployed"); // idempotency
        require(convoyProtocolL2[missionId] != 0, 
                "Registry: L2 contract addr not set"); // ordering

        // Spec sanity
        require(spec.nDrones == N_DRONES,                          "Registry: nDrones must be 5"); // exactly 5
        require(spec.zoneW > 0 && spec.zoneH > 0,                  "Registry: zone dims = 0");     // TILING INVARIANT
        require(spec.stripWidth > 0,                               "Registry: stripWidth = 0");    // permille range
        require(spec.zoneW == spec.stripWidth * uint32(spec.nDrones),
                "Registry: zoneW != stripWidth * nDrones");  // basis-points range
        require(spec.coverageMin > 0 && spec.coverageMin <= 1000,  "Registry: bad coverageMin");
        require(spec.pMin > 0 && spec.pMin <= 10000,               "Registry: bad pMin");
        require(spec.timeWindow > 0,                               "Registry: bad timeWindow");
        require(tsStart > 0,                                       "Registry: tsStart = 0");

        specs[missionId] = spec; // the L1 ANCHOR

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

        // Fire the L1→L2 message: toAddress=L2 convoy_protocol, selector=open_mission.
        // Emits LogMessageToL2 (which a live Madara L1-sync would route to open_mission).
        // THIS is the convoy protocol's use of sendMessageToL2 (cf. the stub's header).
        _coreFor(missionId).sendMessageToL2{value: msg.value}(
            convoyProtocolL2[missionId],   // toAddress = the L2 convoy_protocol
            OPEN_MISSION_SELECTOR,         // selector → routes to open_mission
            payload                        // the 18 felts
        );
    }

    /**
     * @notice Write the mission-level aggregate after all `nDrones` have
     *         landed SAFE.
     * @dev    Only the bound Verifier may call. Reverts if the mission is unknown
     *         or already SAFE.
     */
    function setMissionSafe(uint256 missionId, bytes32 aggH) external onlyVerifier {
        MissionSpec storage spec = specs[missionId];
        require(spec.nDrones > 0,                "Registry: unknown mission");
        require(!missionSafe[missionId],         "Registry: mission already SAFE");

        missionSafe[missionId] = true;
        missionAggH[missionId] = aggH;
        emit MissionSafe(missionId, aggH);
    }

    // ───────────────────────────────────────────────────────────────────
    //  View helpers (used by CommandLog + frontends)
    // ───────────────────────────────────────────────────────────────────

    /// @notice Full spec AS A STRUCT (the auto-getter returns a tuple). Used by
    ///         the Verifier's drone-count cross-check in consumeL2Message.
    function getSpec(uint256 missionId) external view returns (MissionSpec memory) {
        return specs[missionId];
    }

    /// @notice Is one mission SAFE (reads the flag setMissionSafe flips).
    function isMissionSafe(uint256 missionId) external view returns (bool) {
        return missionSafe[missionId];
    }

    /// @notice THE advance gate: both swarms must be SAFE before the convoy moves.
    ///         CommandLog.advance() enforces this. isDualSafe(1,2)==true is the
    ///         end-to-end "it worked" signal after both relays.
    function isDualSafe(uint256 alphaMissionId, uint256 bravoMissionId)
        external
        view
        returns (bool)
    {
        return missionSafe[alphaMissionId] && missionSafe[bravoMissionId];
    }
}

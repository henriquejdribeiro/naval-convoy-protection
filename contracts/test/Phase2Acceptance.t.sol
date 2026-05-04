// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/Registry.sol";
import "../src/Verifier.sol";
import "../src/CommandLog.sol";
import "../src/StarknetCoreStub.sol";

/**
 * @title  Phase2Acceptance
 * @notice End-to-end integration test of the Phase 2 acceptance scenario
 *         from `docs/specs/acceptance.md`.
 *
 * Walks the full L1 happy path with hardcoded valid facts:
 *
 *   1. Deploy all 4 contracts in the correct order (mirrors DeployL1.s.sol)
 *   2. D deploys mission EX-010 for drone α → MissionDeployed(10, α, spec)
 *   3. D deploys mission EX-011 for drone β → MissionDeployed(11, β, spec)
 *   4. Non-commander deploy attempt reverts (onlyCommander)
 *   5. Ship F (alpha relay) registers a SAFE proof for (10, α)
 *      → FactRegistered + MissionVerified, Registry.verdict[10][α] = true
 *      → NO ConvoyAdvance event yet (Pattern B — Verifier doesn't auto-fire)
 *   6. Ship B (bravo relay) registers a SAFE proof for (11, β)
 *      → Registry.verdict[11][β] = true; still no ConvoyAdvance
 *   7. Non-relay caller hits onlyRelay revert
 *   8. D fires CommandLog.advance(alphaMid, betaMid, 100) → ConvoyAdvance event
 *   9. Non-commander advance attempt reverts
 *  10. Pre-dual-SAFE advance attempt reverts (using a fresh CommandLog
 *      against unverified mids)
 *
 * This single test file is the Phase 2 acceptance gate. If `forge test
 * --match-contract Phase2Acceptance` passes, Phase 2 is done.
 */
contract Phase2AcceptanceTest is Test {
    StarknetCoreStub internal starknet;
    Registry         internal registry;
    Verifier         internal verifier;
    CommandLog       internal commandLog;

    address internal deployer  = address(0xA11CE);     // ship A — owner
    address internal commander = address(0xC0DE);      // D's commander key
    address internal alphaRelay= address(0xF000F);     // ship F
    address internal bravoRelay= address(0xB000B);     // ship B
    address internal stranger  = address(0xDEAD);      // a non-privileged caller

    // Cached drone-id constants. Public Solidity constants are exposed as
    // auto-generated external getter functions, so reading them mid-test
    // (e.g. registry.DRONE_ALPHA()) consumes any in-flight vm.prank.
    // Cache once in setUp() to avoid that footgun.
    uint256 internal ALPHA;
    uint256 internal BRAVO;

    // Mission ids (deploy() auto-increments starting at 1; each lane's
    // mid will be different per call)
    uint256 internal mid_alpha;
    uint256 internal mid_beta;

    // ───────────────────────────────────────────────────────────────────
    //  setUp — deploy the full stack just like DeployL1.s.sol does
    // ───────────────────────────────────────────────────────────────────
    function setUp() public {
        vm.startPrank(deployer);

        starknet   = new StarknetCoreStub();
        registry   = new Registry(deployer, commander);
        verifier   = new Verifier(deployer, address(registry), alphaRelay, bravoRelay);
        commandLog = new CommandLog(deployer, address(registry), commander);

        registry.setVerifier(address(verifier));

        vm.stopPrank();

        ALPHA = registry.DRONE_ALPHA();
        BRAVO = registry.DRONE_BRAVO();
    }

    // ───────────────────────────────────────────────────────────────────
    //  Helper: build a representative MissionSpec
    // ───────────────────────────────────────────────────────────────────
    function _spec() internal pure returns (Registry.MissionSpec memory) {
        return Registry.MissionSpec({
            areaHash:    keccak256("convoy_left_frontal_area"),
            coverageMin: 950,    // ≥ 95.0%
            pMin:        7000,   // p_contact ≥ 0.7
            timeWindow:  360     // 6 min
        });
    }

    // Helper: build a representative SafeProofInputs that satisfies the spec.
    function _validInputs(uint256 mid, uint256 droneId)
        internal pure returns (Verifier.SafeProofInputs memory)
    {
        return Verifier.SafeProofInputs({
            programHash:      keccak256(abi.encodePacked("safe_area_verify.cairo", droneId)),
            outputHash:       keccak256(abi.encodePacked("output", mid, droneId)),
            mid:              mid,
            droneId:          droneId,
            coveragePermille: 952,    // satisfies ≥ 950
            maxContactBp:     4500,   // satisfies < 7000
            elapsedSeconds:   340,    // satisfies ≤ 360
            commitment:       keccak256(abi.encodePacked("H_", droneId)),
            nSteps:           1234567
        });
    }

    // ───────────────────────────────────────────────────────────────────
    //  Step 2/3 — D deploys both missions
    // ───────────────────────────────────────────────────────────────────
    function test_01_commanderDeploysBothMissions() public {
        Registry.MissionSpec memory spec = _spec();

        vm.expectEmit(true, true, false, true, address(registry));
        emit Registry.MissionDeployed(1, ALPHA, spec);
        vm.prank(commander);
        mid_alpha = registry.deploy(ALPHA, spec);
        assertEq(mid_alpha, 1, "first mission should mint mid=1");

        vm.expectEmit(true, true, false, true, address(registry));
        emit Registry.MissionDeployed(2, BRAVO, spec);
        vm.prank(commander);
        mid_beta = registry.deploy(BRAVO, spec);
        assertEq(mid_beta, 2, "second mission should mint mid=2");

        // Specs persisted under (mid, droneId)
        Registry.MissionSpec memory got = registry.getSpec(1, ALPHA);
        assertEq(got.coverageMin, 950);
        assertEq(got.pMin,        7000);
        assertEq(got.timeWindow,  360);
    }

    // ───────────────────────────────────────────────────────────────────
    //  Step 4 — non-commander attempt reverts
    // ───────────────────────────────────────────────────────────────────
    function test_02_nonCommanderDeployReverts() public {
        vm.prank(stranger);
        vm.expectRevert(bytes("Registry: onlyCommander"));
        registry.deploy(ALPHA, _spec());
    }

    // ───────────────────────────────────────────────────────────────────
    //  Step 5 — α-fact registration: alpha relay submits, verdict written
    // ───────────────────────────────────────────────────────────────────
    function test_03_alphaRelayRegistersSafeProof() public {
        // Deploy mission first (mirrors test_01)
        vm.startPrank(commander);
        uint256 mA = registry.deploy(ALPHA, _spec());
        uint256 mB = registry.deploy(BRAVO, _spec());
        vm.stopPrank();

        Verifier.SafeProofInputs memory inputs = _validInputs(mA, ALPHA);

        vm.prank(alphaRelay);
        (uint256 proofId, bytes32 factHash) = verifier.registerSafeProof(inputs);

        assertEq(proofId, 0,                "first proof should be id 0");
        assertTrue(verifier.isValid(factHash), "fact should be registered");
        assertTrue(registry.isSafe(mA, ALPHA),
                   "alpha verdict should be SAFE");
        // β not yet verified — dual-SAFE precondition must still fail
        assertFalse(registry.isDualSafe(mA, mB), "dual-SAFE should be false");

        // Sanity: re-registering the same fact is idempotent (no revert,
        // verifiedFacts stays true)
        vm.prank(alphaRelay);
        verifier.registerSafeProof(inputs);
        assertTrue(verifier.isValid(factHash));
    }

    // ───────────────────────────────────────────────────────────────────
    //  Step 6 — β-fact registration: bravo relay submits, dual-SAFE achieved
    // ───────────────────────────────────────────────────────────────────
    function test_04_bothLanesVerified_dualSafeReached() public {
        vm.startPrank(commander);
        uint256 mA = registry.deploy(ALPHA, _spec());
        uint256 mB = registry.deploy(BRAVO, _spec());
        vm.stopPrank();

        // α-fact via ship F
        vm.prank(alphaRelay);
        verifier.registerSafeProof(_validInputs(mA, ALPHA));

        // β-fact via ship B
        vm.prank(bravoRelay);
        verifier.registerSafeProof(_validInputs(mB, BRAVO));

        assertTrue(registry.isSafe(mA, ALPHA));
        assertTrue(registry.isSafe(mB, BRAVO));
        assertTrue(registry.isDualSafe(mA, mB), "dual-SAFE should be true");

        // Pattern B: still NO ConvoyAdvance event from Verifier alone
        assertEq(commandLog.advanceCount(), 0,
                 "no advance event without explicit D call");
    }

    // ───────────────────────────────────────────────────────────────────
    //  Step 7 — non-relay caller cannot register a fact
    // ───────────────────────────────────────────────────────────────────
    function test_05_nonRelayCallerReverts() public {
        vm.prank(commander);
        uint256 mA = registry.deploy(ALPHA, _spec());

        vm.prank(stranger);
        vm.expectRevert(bytes("Verifier: onlyRelay"));
        verifier.registerSafeProof(_validInputs(mA, ALPHA));

        // Also: bravo relay cannot submit α-facts (wrong lane)
        vm.prank(bravoRelay);
        vm.expectRevert(bytes("Verifier: onlyRelay"));
        verifier.registerSafeProof(_validInputs(mA, ALPHA));
    }

    // ───────────────────────────────────────────────────────────────────
    //  Step 8 — D fires advance after dual-SAFE → ConvoyAdvance event
    // ───────────────────────────────────────────────────────────────────
    function test_06_commanderFiresAdvance_emitsConvoyAdvance() public {
        vm.startPrank(commander);
        uint256 mA = registry.deploy(ALPHA, _spec());
        uint256 mB = registry.deploy(BRAVO, _spec());
        vm.stopPrank();

        vm.prank(alphaRelay);
        verifier.registerSafeProof(_validInputs(mA, ALPHA));
        vm.prank(bravoRelay);
        verifier.registerSafeProof(_validInputs(mB, BRAVO));

        // Roll forward a block so block.number is past the verifier txs
        vm.roll(block.number + 1);

        vm.expectEmit(true, true, true, true, address(commandLog));
        emit CommandLog.ConvoyAdvance(
            block.number,
            mA,
            mB,
            100,
            commander
        );
        vm.prank(commander);
        commandLog.advance(mA, mB, 100);

        assertEq(commandLog.advanceCount(), 1, "advance recorded");
        CommandLog.AdvanceRecord memory rec = commandLog.getAdvance(0);
        assertEq(rec.alphaMid,  mA);
        assertEq(rec.betaMid,   mB);
        assertEq(rec.commander, commander);
        assertEq(rec.speed,     100);
    }

    // ───────────────────────────────────────────────────────────────────
    //  Step 9 — non-commander advance reverts
    // ───────────────────────────────────────────────────────────────────
    function test_07_nonCommanderAdvanceReverts() public {
        vm.prank(stranger);
        vm.expectRevert(bytes("CommandLog: onlyCommander"));
        commandLog.advance(1, 2, 100);
    }

    // ───────────────────────────────────────────────────────────────────
    //  Step 10 — pre-dual-SAFE advance reverts
    // ───────────────────────────────────────────────────────────────────
    function test_08_preDualSafeAdvanceReverts() public {
        vm.startPrank(commander);
        uint256 mA = registry.deploy(ALPHA, _spec());
        uint256 mB = registry.deploy(BRAVO, _spec());
        vm.stopPrank();

        // Verify ONLY alpha
        vm.prank(alphaRelay);
        verifier.registerSafeProof(_validInputs(mA, ALPHA));

        // D tries to advance — must revert because β isn't SAFE yet
        vm.prank(commander);
        vm.expectRevert(bytes("CommandLog: beta not SAFE"));
        commandLog.advance(mA, mB, 100);

        // Now verify beta
        vm.prank(bravoRelay);
        verifier.registerSafeProof(_validInputs(mB, BRAVO));

        // Now the same call must succeed
        vm.prank(commander);
        commandLog.advance(mA, mB, 100);
        assertEq(commandLog.advanceCount(), 1);
    }

    // ───────────────────────────────────────────────────────────────────
    //  Threshold violation: bad public outputs revert at the Verifier
    // ───────────────────────────────────────────────────────────────────
    function test_09_thresholdViolationsRevert() public {
        vm.prank(commander);
        uint256 mA = registry.deploy(ALPHA, _spec());

        // Coverage too low (940 permille < 950)
        Verifier.SafeProofInputs memory bad = _validInputs(mA, ALPHA);
        bad.coveragePermille = 940;
        vm.prank(alphaRelay);
        vm.expectRevert(bytes("Verifier: coverage < threshold"));
        verifier.registerSafeProof(bad);

        // Contact too high (8000 bp >= 7000)
        bad = _validInputs(mA, ALPHA);
        bad.maxContactBp = 8000;
        vm.prank(alphaRelay);
        vm.expectRevert(bytes("Verifier: maxContact >= pMin"));
        verifier.registerSafeProof(bad);

        // Time over window (400 > 360)
        bad = _validInputs(mA, ALPHA);
        bad.elapsedSeconds = 400;
        vm.prank(alphaRelay);
        vm.expectRevert(bytes("Verifier: time > window"));
        verifier.registerSafeProof(bad);

        // Verdict was never set
        assertFalse(registry.isSafe(mA, ALPHA));
    }
}

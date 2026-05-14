// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/Registry.sol";
import "../src/Verifier.sol";
import "../src/CommandLog.sol";
import "../src/StarknetCoreStub.sol";
import "../src/MockStarkVerifier.sol";

/**
 * @title  Phase3Acceptance
 * @notice End-to-end gate for Phase 3.a — the Stone-prover slice.
 *
 * Anchors the off-chain ↔ on-chain encoding with **real values from a
 * successful prover-api run** captured against the live Phase 2 chain
 * (commit `c266c60`):
 *
 *   programHash  0x974f1b4422464370d8d2d7b7bc19a9421fca2df08f6ecf4cb384f5e3a39d9be9
 *   outputHash   0xd8c56e2c4e4826426c446b712170944096b8992cf54ede3f2e63238624454f3c
 *   factHash     0xeee829d9db1bd7d7a9531da2c40599d1548de4d936a342245b8ef7f127d4ced1
 *
 *   public outputs (β lane, missionId=2)
 *     missionId                = 2
 *     drone_id           = 2
 *     coverage_permille  = 960   (≥ 950)
 *     max_p_contact      = 4500  (<  7000)
 *     elapsed_seconds    = 340   (≤  360)
 *     commitment         = 0x055d4a0e56c1875e13e8eff57589305bc5bcda38cce164d6bf2343f76c2ea427
 *     n_steps            = 65536
 *
 * Tests:
 *   01 factHash matches keccak256(abi.encodePacked(programHash, outputHash))
 *      — anchors `submit_proof_l1.py`'s hash construction.
 *   02 outputHash matches keccak256 over abi.encodePacked of the 6 felt
 *      outputs (32 bytes each, big-endian) — anchors the public-output
 *      encoding the Cairo program emits via `serialize_word`.
 *   03 The β lane SafeProofInputs reproduced from the cairo run is
 *      accepted by Verifier.registerSafeProof and yields the same factHash.
 *   04 After registering BOTH α (synthetic) and β (real) proofs, the
 *      commander can fire CommandLog.advance — full Pattern B happy path.
 *   05 Threshold checks still bite when fed real-shaped inputs that
 *      barely violate the mission spec.
 *
 * If `forge test --match-contract Phase3Acceptance` passes, Phase 3.a is
 * provably end-to-end: the on-chain Verifier accepts what the off-chain
 * Stone prover emits, and dual-SAFE flows through to ConvoyAdvance.
 */
contract Phase3AcceptanceTest is Test {
    Registry   internal registry;
    Verifier   internal verifier;
    CommandLog internal commandLog;

    address internal deployer  = address(0xA11CE);
    address internal commander = address(0xC0DE);
    address internal alphaRelay= address(0xF000F);
    address internal bravoRelay= address(0xB000B);

    uint256 internal ALPHA;
    uint256 internal BRAVO;

    // ─── Real values from prover-api run (β lane, missionId=2) ────────────────
    bytes32 constant REAL_PROGRAM_HASH =
        0x974f1b4422464370d8d2d7b7bc19a9421fca2df08f6ecf4cb384f5e3a39d9be9;
    bytes32 constant REAL_OUTPUT_HASH =
        0xd8c56e2c4e4826426c446b712170944096b8992cf54ede3f2e63238624454f3c;
    bytes32 constant REAL_FACT_HASH =
        0xeee829d9db1bd7d7a9531da2c40599d1548de4d936a342245b8ef7f127d4ced1;
    bytes32 constant REAL_COMMITMENT =
        0x055d4a0e56c1875e13e8eff57589305bc5bcda38cce164d6bf2343f76c2ea427;

    uint256 constant REAL_MISSION_ID            = 2;
    uint256 constant REAL_DRONE_ID       = 2;          // β
    uint256 constant REAL_COVERAGE       = 960;
    uint256 constant REAL_MAX_P          = 4500;
    uint256 constant REAL_ELAPSED        = 340;
    uint256 constant REAL_NSTEPS         = 65536;

    MockStarkVerifier internal mockStark;

    function setUp() public {
        vm.startPrank(deployer);
        registry   = new Registry(deployer, commander);
        mockStark  = new MockStarkVerifier();
        verifier   = new Verifier(
            deployer,
            address(registry),
            alphaRelay,
            bravoRelay,
            address(mockStark),
            0
        );
        commandLog = new CommandLog(address(registry), commander);
        registry.setVerifier(address(verifier));
        vm.stopPrank();

        ALPHA = registry.DRONE_ALPHA();
        BRAVO = registry.DRONE_BRAVO();

        // Mint missions matching the prover-api run: deploy ALPHA first
        // (missionId=1), then BRAVO (missionId=2). This mirrors docker-compose.l1.yml's
        // deploy-l1 service.
        Registry.MissionSpec memory spec = _spec();
        vm.startPrank(commander);
        registry.deploy(ALPHA, spec);   // mints missionId=1
        registry.deploy(BRAVO, spec);   // mints missionId=2
        vm.stopPrank();
    }

    /// @dev Build the proof-bytes args MockStarkVerifier expects
    ///      (cairoAuxInput[0,1] = programHash, outputHash).
    function _doRegister(Verifier.SafeProofInputs memory inputs)
        internal
        returns (uint256 proofId, bytes32 factHash)
    {
        uint256[] memory empty = new uint256[](0);
        uint256[] memory aux   = new uint256[](2);
        aux[0] = uint256(inputs.programHash);
        aux[1] = uint256(inputs.outputHash);
        return verifier.registerSafeProof(inputs, empty, empty, empty, aux);
    }

    function _spec() internal pure returns (Registry.MissionSpec memory) {
        // Same thresholds as infrastructure/prover-api/sample_input.json
        return Registry.MissionSpec({
            // matches docker-compose.l1.yml deploy-l1 SPEC argument
            areaHash:    0x6172656172656172656172656172656172656172656172656172656172656131,
            coverageMin: 950,
            pMin:        7000,
            timeWindow:  360
        });
    }

    // ───────────────────────────────────────────────────────────────────
    //  01 — factHash construction matches submit_proof_l1.py
    // ───────────────────────────────────────────────────────────────────
    function test_01_factHashAnchorsOffChainEncoding() public pure {
        bytes32 computed = keccak256(abi.encodePacked(
            REAL_PROGRAM_HASH,
            REAL_OUTPUT_HASH
        ));
        assertEq(computed, REAL_FACT_HASH,
                 "Solidity factHash must match python keccak256(programHash || outputHash)");
    }

    // ───────────────────────────────────────────────────────────────────
    //  02 — outputHash matches the 6-felt public-memory encoding
    // ───────────────────────────────────────────────────────────────────
    function test_02_outputHashAnchorsCairoSerializeWord() public pure {
        // submit_proof_l1.py:
        //     output_bytes = b"".join(v.to_bytes(32, "big") for v in outputs)
        //     output_hash  = keccak256(output_bytes)
        // = abi.encodePacked of six uint256s in (missionId, drone_id, coverage,
        //   max_p, elapsed, commitment) order.
        bytes32 computed = keccak256(abi.encodePacked(
            REAL_MISSION_ID,
            REAL_DRONE_ID,
            REAL_COVERAGE,
            REAL_MAX_P,
            REAL_ELAPSED,
            uint256(REAL_COMMITMENT)
        ));
        assertEq(computed, REAL_OUTPUT_HASH,
                 "Solidity outputHash must match python keccak256(serialize_word outputs)");
    }

    // ───────────────────────────────────────────────────────────────────
    //  03 — Real β-lane SafeProofInputs is accepted on-chain
    // ───────────────────────────────────────────────────────────────────
    function test_03_realBravoProofRegisters() public {
        Verifier.SafeProofInputs memory inputs = _realBravoInputs();

        vm.expectEmit(true, false, false, true, address(verifier));
        emit Verifier.FactRegistered(REAL_FACT_HASH);
        vm.prank(bravoRelay);
        (uint256 proofId, bytes32 factHash) = _doRegister(inputs);

        assertEq(proofId, 0,                "first proof on this chain");
        assertEq(factHash, REAL_FACT_HASH,  "on-chain factHash must equal off-chain factHash");
        assertTrue(verifier.isValid(factHash),       "fact registered");
        assertTrue(registry.isSafe(REAL_MISSION_ID, BRAVO), "bravo verdict SAFE");

        // Sanity: re-submitting the same fact stays idempotent
        vm.prank(bravoRelay);
        _doRegister(inputs);
        assertTrue(verifier.isValid(factHash));
    }

    // ───────────────────────────────────────────────────────────────────
    //  04 — Full Pattern B: dual-SAFE → commander advance → ConvoyAdvance
    // ───────────────────────────────────────────────────────────────────
    function test_04_dualSafeFromRealBravoFiresAdvance() public {
        // Real β proof
        vm.prank(bravoRelay);
        _doRegister(_realBravoInputs());

        // Synthetic α proof against missionId=1 (a real α proof would be the
        // same shape; we only have one Stone run captured. Same encoding,
        // different lane.)
        Verifier.SafeProofInputs memory alpha = Verifier.SafeProofInputs({
            programHash:      keccak256("alpha-program"),
            outputHash:       keccak256("alpha-output"),
            missionId:              1,
            droneId:          ALPHA,
            coveragePermille: 955,
            maxContactBp:     3800,
            elapsedSeconds:   320,
            commitment:       keccak256("alpha-commitment"),
            nSteps:           65536
        });
        vm.prank(alphaRelay);
        _doRegister(alpha);

        assertTrue(registry.isDualSafe(1, REAL_MISSION_ID), "dual-SAFE must hold");

        // D fires advance — this is the moment Pattern B closes.
        uint256 startBlock = block.number;
        vm.roll(startBlock + 1);

        vm.expectEmit(true, true, true, true, address(commandLog));
        emit CommandLog.ConvoyAdvance(startBlock + 1, 1, REAL_MISSION_ID, 100, commander);
        vm.prank(commander);
        commandLog.advance(1, REAL_MISSION_ID, 100);

        assertEq(commandLog.advanceCount(), 1, "advance recorded");
        CommandLog.AdvanceRecord memory rec = commandLog.getAdvance(0);
        assertEq(rec.alphaMissionId, 1);
        assertEq(rec.bravoMissionId,  REAL_MISSION_ID);
        assertEq(rec.speed,    100);
    }

    // ───────────────────────────────────────────────────────────────────
    //  05 — Real-shaped inputs that violate by 1 unit are still rejected
    // ───────────────────────────────────────────────────────────────────
    function test_05_realShapedViolationsRevert() public {
        Verifier.SafeProofInputs memory inputs;

        // coverage 949 = barely below 950 threshold
        inputs = _realBravoInputs();
        inputs.coveragePermille = 949;
        vm.prank(bravoRelay);
        vm.expectRevert(bytes("Verifier: coverage < threshold"));
        _doRegister(inputs);

        // max_p 7000 = exactly at threshold (Cairo enforces strict <, so this
        // case is unreachable from a real prover, but the on-chain check
        // belt-and-suspenders against tampered submissions.)
        inputs = _realBravoInputs();
        inputs.maxContactBp = 7000;
        vm.prank(bravoRelay);
        vm.expectRevert(bytes("Verifier: maxContact >= pMin"));
        _doRegister(inputs);

        // elapsed 361 = 1 second over the 360 window
        inputs = _realBravoInputs();
        inputs.elapsedSeconds = 361;
        vm.prank(bravoRelay);
        vm.expectRevert(bytes("Verifier: time > window"));
        _doRegister(inputs);

        assertFalse(registry.isSafe(REAL_MISSION_ID, BRAVO),
                    "no verdict written for any rejected proof");
    }

    // ───────────────────────────────────────────────────────────────────
    //  Helpers
    // ───────────────────────────────────────────────────────────────────
    function _realBravoInputs()
        internal pure returns (Verifier.SafeProofInputs memory)
    {
        return Verifier.SafeProofInputs({
            programHash:      REAL_PROGRAM_HASH,
            outputHash:       REAL_OUTPUT_HASH,
            missionId:              REAL_MISSION_ID,
            droneId:          REAL_DRONE_ID,
            coveragePermille: REAL_COVERAGE,
            maxContactBp:     REAL_MAX_P,
            elapsedSeconds:   REAL_ELAPSED,
            commitment:       REAL_COMMITMENT,
            nSteps:           REAL_NSTEPS
        });
    }
}

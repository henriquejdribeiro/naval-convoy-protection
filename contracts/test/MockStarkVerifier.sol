// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../src/IStarkVerifier.sol";

/**
 * @title  MockStarkVerifier (test-only)
 * @notice Development-only STARK verifier that unconditionally
 *         registers any fact passed to it.
 *
 * After the Stage A / Stage B refactor (real GpsStatementVerifier is
 * required on every non-test deployment), this contract has no
 * production role. It lives under contracts/test/ so Foundry includes
 * it when running the unit suite but does NOT compile it into the
 * production deployment artefacts.
 *
 * Two callable surfaces:
 *
 *   1. verifyProofAndRegister(...) — the IStarkVerifier method. Tests
 *      that exercise the OLD per-tx flow (where the convoy Verifier
 *      called this directly) still work. Reconstructs factHash from
 *      cairoAuxInput[0..1] and flips verifiedFacts[factHash] = true.
 *
 *   2. setFactValid(factHash, true) — Stage-A simulator. Lets a unit
 *      test stand in for path-a-runner: write the factHash directly,
 *      then call Verifier.registerSafeProof and watch the isValid()
 *      assertion succeed without going through Stage A at all.
 *
 * **WARNING**: deploying this contract on any chain you care about
 * defeats the purpose of the STARK proof. Use only in tests.
 */
contract MockStarkVerifier is IStarkVerifier {
    mapping(bytes32 => bool) public verifiedFacts;
    bool public alwaysAccept = true;

    event MockFactRegistered(bytes32 indexed factHash);

    /**
     * @notice Legacy IStarkVerifier path — accept any proof, register
     *         the implied fact. Reconstructs factHash from cairoAuxInput.
     */
    function verifyProofAndRegister(
        uint256[] calldata /* proofParams */,
        uint256[] calldata /* proof */,
        uint256[] calldata /* taskMetadata */,
        uint256[] calldata cairoAuxInput,
        uint256            /* cairoVerifierId */
    ) external override {
        require(alwaysAccept, "MockStarkVerifier: rejection forced");
        require(cairoAuxInput.length >= 2, "MockStarkVerifier: bad aux input");

        bytes32 programHash = bytes32(cairoAuxInput[0]);
        bytes32 outputHash  = bytes32(cairoAuxInput[1]);
        bytes32 factHash    = keccak256(abi.encodePacked(programHash, outputHash));

        verifiedFacts[factHash] = true;
        emit MockFactRegistered(factHash);
    }

    function isValid(bytes32 factHash) external view override returns (bool) {
        return verifiedFacts[factHash];
    }

    /// @dev test-only: simulate a verifier that rejects everything.
    function setAlwaysAccept(bool v) external {
        alwaysAccept = v;
    }

    /**
     * @notice Stage-A simulator — write a fact directly without going
     *         through verifyProofAndRegister. Mirrors what path-a-runner
     *         does in production. Use this in any test that exercises
     *         the new convoy Verifier.registerSafeProof (which only
     *         reads isValid, not verifyProofAndRegister).
     */
    function setFactValid(bytes32 factHash, bool valid) external {
        verifiedFacts[factHash] = valid;
        if (valid) emit MockFactRegistered(factHash);
    }
}

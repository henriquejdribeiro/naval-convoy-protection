// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./IStarkVerifier.sol";

/**
 * @title  MockStarkVerifier
 * @notice Development-only STARK verifier that unconditionally
 *         registers any fact passed to it.
 *
 * The convoy `Verifier.sol` delegates real STARK verification to an
 * `IStarkVerifier` implementation injected at construction time. In
 * production this is the `GpsStarkVerifierAdapter` wrapping
 * StarkWare's `GpsStatementVerifier` (solc 0.6.12, layout6, ~3 M gas
 * per verification). For the existing acceptance test suite, and for
 * the demo while the GPS verifier stack is still being deployed, the
 * mock here is used in its place so the test fixtures don't need to
 * carry real proof bytes.
 *
 * **WARNING**: this contract performs no cryptographic verification.
 * Deploying it on any chain you care about defeats the purpose of the
 * STARK proof. The convoy `Verifier.sol` retains its own
 * threshold-re-assertion `require` statements as defence in depth,
 * but those are not a substitute for real STARK validation.
 */
contract MockStarkVerifier is IStarkVerifier {
    mapping(bytes32 => bool) public verifiedFacts;
    bool public alwaysAccept = true;

    event MockFactRegistered(bytes32 indexed factHash);

    /**
     * @notice Accept any proof; register the implied fact.
     * @dev    The factHash is reconstructed from the caller-supplied
     *         `cairoAuxInput`'s first two words (which carry
     *         programHash and outputHash by convention in
     *         StarkWare's GPS shape). This mirrors what the real
     *         GpsStatementVerifier does so callers see the same
     *         interface from both implementations.
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
}

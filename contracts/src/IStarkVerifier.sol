// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title  IStarkVerifier
 * @notice Abstract interface to the on-chain STARK verifier the convoy
 *         protocol delegates cryptographic verification to.
 *
 * The convoy `Verifier.sol` calls `verifyAndRegister(...)` and then
 * polls `isValid(factHash)` to confirm the verifier accepted the
 * proof. Two concrete implementations are intended:
 *
 *   1. **GpsStarkVerifierAdapter** (production path) — thin shim around
 *      StarkWare's `GpsStatementVerifier` at
 *      `lib/starkex-contracts/evm-verifier/solidity/contracts/gps/
 *      GpsStatementVerifier.sol`. Forwards proof bytes verbatim and
 *      reads back the registered fact via the FactRegistry interface.
 *
 *   2. **MockStarkVerifier** (development path) — unconditionally
 *      registers any fact passed to it. Used by the existing test
 *      suite and during demos while the layout-6 deployment of the
 *      StarkWare verifier stack is being brought up.
 *
 * The interface lives at the 0.8.20 pragma so the convoy contracts can
 * import it cleanly. The underlying GpsStatementVerifier compiles
 * under 0.6.12; deployment happens via a separate Foundry script and
 * the address is injected into Verifier.sol at construction time. The
 * solc-version split is transparent to this interface --- ABI calls
 * cross pragma boundaries without any Solidity-level coupling.
 */
interface IStarkVerifier {
    /**
     * @notice Submit a STARK proof for cryptographic verification.
     *         On success, the underlying verifier registers the
     *         corresponding fact in its FactRegistry; on failure, the
     *         entire transaction reverts.
     *
     * @dev    Wraps StarkWare's
     *         `GpsStatementVerifier.verifyProofAndRegister`. The
     *         calldata shape is layout-specific (we target layout6 =
     *         "starknet", with builtins
     *         {output, range_check, poseidon}). Adaptation between
     *         our convoy domain shape and the GPS shape is the
     *         adapter's responsibility, not this interface's.
     *
     * @param  proofParams  FRI configuration (step list, n_queries,
     *                      proof_of_work_bits, log_n_cosets, ...)
     * @param  proof        the raw STARK proof bytes packed as
     *                      uint256[]; typically ~25k words (~800 KB)
     * @param  taskMetadata memory-page layout metadata produced by
     *                      `stark_evm_adapter`
     * @param  cairoAuxInput Cairo public-input array — includes
     *                      programHash, output hash, builtin pointers
     * @param  cairoVerifierId identifier of the registered
     *                      `CpuVerifier` instance (one per layout)
     */
    function verifyProofAndRegister(
        uint256[] calldata proofParams,
        uint256[] calldata proof,
        uint256[] calldata taskMetadata,
        uint256[] calldata cairoAuxInput,
        uint256            cairoVerifierId
    ) external;

    /**
     * @notice FactRegistry-pattern read: has this fact been registered?
     * @param  factHash keccak256(programHash || outputHash)
     * @return true iff the fact has been validated by a prior
     *         `verifyProofAndRegister` call.
     */
    function isValid(bytes32 factHash) external view returns (bool);
}

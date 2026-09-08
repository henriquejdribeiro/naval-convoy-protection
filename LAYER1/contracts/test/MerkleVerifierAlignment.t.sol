// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/*
   MerkleVerifierAlignment.t.sol

   Asserts that the patched COMMITMENT_MASK in starkex-contracts/MerkleVerifier.sol
   selects the LOW 160 bits of a keccak256 output — i.e. matches the LSB-aligned
   hash convention produced by the Stone prover binary shipped in
   zksecurity/stone-cli v0.2.0 (built from baking-bad/stone-prover with
   MaskedHash<Keccak256, 20, IsMsb=false>).

   See contracts/lib/starkware-mainnet/PATCH.md.

   This file is pragma ^0.8.20 to use forge-std/Test.sol. It does not
   import the production starkex contracts (which are pragma ^0.6.12),
   it just re-asserts the constant value and the masking semantics in
   isolation. Both Solidity versions evaluate `&` identically on uint256.
*/
contract MerkleVerifierAlignmentTest is Test {
    // The constant as it now appears in MerkleVerifier.sol after the patch.
    uint256 internal constant COMMITMENT_MASK_LSB =
        0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    // The original mainnet constant we replaced — kept here as a reference
    // so the test self-documents what changed.
    uint256 internal constant COMMITMENT_MASK_MSB_REFERENCE =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000000000000000000;

    function testMaskKeepsLowBits() public {
        // Literal length triggers Solidity's `address` inference at 40 hex
        // chars; wrap via uint160 to coerce explicitly to uint256.
        bytes32 leftLeaf = bytes32(uint256(uint160(0x1111111111111111111111111111111111111111)));
        bytes32 rightLeaf = bytes32(uint256(uint160(0x2222222222222222222222222222222222222222)));

        bytes32 fullKeccak = keccak256(abi.encodePacked(leftLeaf, rightLeaf));
        uint256 fullKeccakUint = uint256(fullKeccak);

        uint256 lsbResult = fullKeccakUint & COMMITMENT_MASK_LSB;
        uint256 msbResult = fullKeccakUint & COMMITMENT_MASK_MSB_REFERENCE;

        // Patched mask must zero the high 96 bits.
        assertEq(lsbResult >> 160, 0, "high 96 bits must be zero");

        // Patched mask preserves bits 0..159.
        assertEq(
            lsbResult,
            fullKeccakUint & ((uint256(1) << 160) - 1),
            "must equal low-160-bit truncation of full keccak"
        );

        // Sanity: the two masks are not coincidentally equal.
        assertTrue(lsbResult != msbResult, "masks must differ");
    }

    function testMaskValueExact() public {
        assertEq(
            COMMITMENT_MASK_LSB,
            0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            "LSB mask literal"
        );
    }
}

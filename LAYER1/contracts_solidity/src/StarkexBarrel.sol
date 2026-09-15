// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.6.12;

/**
 * @title  StarkexBarrel
 * @notice Forces forge to compile the StarkWare mainnet `starknet`
 *         (Layout 6, 7 builtins) verifier source so
 *         DeployStarkVerifier.s.sol can deploy each contract by
 *         artifact name via `vm.deployCode("File.sol:Contract")`.
 *
 *         Sources here are Sourcify-verified mainnet contracts.
 *         The canonical addresses on Ethereum mainnet are:
 *
 *           GpsStatementVerifier   0x9fb7F48dCB26b7bFA4e580b2dEFf637B13751942
 *           CpuFrilessVerifier (cairoVerifierId=6)
 *                                  0xe155154845950573ec5f518fc0d4950ab71303ff
 *           CairoBootloaderProgram 0x58600a1dc51dcf7d4f541a8f1f5c6c6aa86cc515
 *
 *         stark-evm-adapter targets cairoVerifierId=6 by default and
 *         its annotated_proof.json fixture uses layout="starknet" --
 *         the 7-builtin layout (no keccak). Our deploy mirrors that
 *         configuration locally.
 */

// ── Layout-6 (starknet, 7 builtins) specifics ──
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/layout6/CpuConstraintPoly.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/layout6/CpuFrilessVerifier.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/layout6/CpuOods.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/layout6/PoseidonPoseidonFullRoundKey0Column.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/layout6/PoseidonPoseidonFullRoundKey1Column.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/layout6/PoseidonPoseidonFullRoundKey2Column.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/layout6/PoseidonPoseidonPartialRoundKey0Column.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/layout6/PoseidonPoseidonPartialRoundKey1Column.sol";

// ── Periodic columns shared with other layouts ───────────────────────
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/periodic_columns/PedersenHashPointsXColumn.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/periodic_columns/PedersenHashPointsYColumn.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/periodic_columns/EcdsaPointsXColumn.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/periodic_columns/EcdsaPointsYColumn.sol";

// ── Bootloader + fact registries ──────────────────────────────────────
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/CairoBootloaderProgram.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/cpu/MemoryPageFactRegistry.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/MerkleStatementContract.sol";
import "../lib/starkware-mainnet/starkware/solidity/verifier/FriStatementContract.sol";

// ── Top-level public entry point ──────────────────────────────────────
import "../lib/starkware-mainnet/starkware/solidity/verifier/gps/GpsStatementVerifier.sol";

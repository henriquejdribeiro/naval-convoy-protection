// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.6.12;

/**
 * @title  StarkexBarrel
 * @notice Forces forge to compile the vendored StarkWare layout-6 verifier
 *         stack so DeployStarkVerifier.s.sol can deploy each contract by
 *         artifact name via `vm.deployCode("File.sol:Contract")`.
 *
 *         Without these imports, forge sees no compilation dependency on
 *         the starkex-contracts submodule (we never `import` from our
 *         0.8.x sources — that would be a cross-solc-version error — and
 *         `vm.deployCode` is a runtime lookup, not a compile-time dep).
 *         The contracts would be left out of `out/`, and the deploy
 *         script would revert at the first `vm.deployCode` call with
 *         "no matching artifact".
 *
 *         This file is pragma ^0.6.12 to match the StarkWare contracts;
 *         it produces no deployable bytecode of its own (no contract
 *         declaration). Each imported symbol is unused — solc will warn,
 *         the warning is harmless and expected.
 *
 *         If you bump the starkex-contracts submodule and a contract is
 *         renamed/moved upstream, the corresponding import here breaks
 *         immediately at `forge build` — that's the point. This file is
 *         the compile-time canary for the vendored verifier path.
 *
 *         Order doesn't matter — solc resolves transitive imports.
 */

// ── Layout-6 specifics (round-key columns + OODS + constraint poly) ──
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/layout6/CpuConstraintPoly.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/layout6/CpuFrilessVerifier.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/layout6/CpuOods.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/layout6/PoseidonPoseidonFullRoundKey0Column.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/layout6/PoseidonPoseidonFullRoundKey1Column.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/layout6/PoseidonPoseidonFullRoundKey2Column.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/layout6/PoseidonPoseidonPartialRoundKey0Column.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/layout6/PoseidonPoseidonPartialRoundKey1Column.sol";

// ── Periodic columns shared across layouts ───────────────────────────
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/periodic_columns/PedersenHashPointsXColumn.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/periodic_columns/PedersenHashPointsYColumn.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/periodic_columns/EcdsaPointsXColumn.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/periodic_columns/EcdsaPointsYColumn.sol";

// ── Bootloader + fact registries ──────────────────────────────────────
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/CairoBootloaderProgram.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/MemoryPageFactRegistry.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/MerkleStatementContract.sol";
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/FriStatementContract.sol";

// ── Top-level public entry point ──────────────────────────────────────
import "../lib/starkex-contracts/evm-verifier/solidity/contracts/gps/GpsStatementVerifier.sol";

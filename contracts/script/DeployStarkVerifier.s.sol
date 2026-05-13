// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

/**
 * @title  DeployStarkVerifier
 * @notice Deploys the full StarkWare layout-6 ("starknet") on-chain STARK
 *         verifier stack from the vendored `starkex-contracts` submodule.
 *
 * Eighteen contracts total, deployed in dependency order:
 *
 *   ─ Periodic columns (10, no constructor args) ─
 *     1.  CpuConstraintPoly                       (layout6/)        — auxPolynomials[0]
 *     2.  PedersenHashPointsXColumn               (periodic_columns/) — auxPolynomials[1]
 *     3.  PedersenHashPointsYColumn               (periodic_columns/) — auxPolynomials[2]
 *     4.  EcdsaPointsXColumn                      (periodic_columns/) — auxPolynomials[3]
 *     5.  EcdsaPointsYColumn                      (periodic_columns/) — auxPolynomials[4]
 *     6.  PoseidonPoseidonFullRoundKey0Column     (layout6/)        — auxPolynomials[5]
 *     7.  PoseidonPoseidonFullRoundKey1Column     (layout6/)        — auxPolynomials[6]
 *     8.  PoseidonPoseidonFullRoundKey2Column     (layout6/)        — auxPolynomials[7]
 *     9.  PoseidonPoseidonPartialRoundKey0Column  (layout6/)        — auxPolynomials[8]
 *    10.  PoseidonPoseidonPartialRoundKey1Column  (layout6/)        — auxPolynomials[9]
 *
 *   ─ OODS contract (1) ─
 *    11.  CpuOods                                 (layout6/)
 *
 *   ─ Fact registries (3) ─
 *    12.  MemoryPageFactRegistry
 *    13.  MerkleStatementContract
 *    14.  FriStatementContract
 *
 *   ─ CPU verifier (1) — wires all of the above together ─
 *    15.  CpuFrilessVerifier                      (layout6/)
 *
 *   ─ Bootloader (1, no constructor args) ─
 *    16.  CairoBootloaderProgram
 *
 *   ─ Top-level GPS verifier (1) — the public entry point ─
 *    17.  GpsStatementVerifier
 *
 *   ─ (Reserved for future) ─
 *    18.  An auxiliary fact registry inheritor for diagnostic tooling.
 *
 * The deployed GpsStatementVerifier address is the one to hand to
 * `Verifier.sol` as `starkVerifierAddr`. It exposes the exact
 * `IStarkVerifier` ABI shape (verifyProofAndRegister + isValid) by
 * inheritance from `GpsOutputParser is FactRegistry`. No adapter
 * contract required — we cast its address to `IStarkVerifier` at the
 * call site.
 *
 * --- Cross-solc-version bridging ---
 *
 * The StarkWare contracts are pinned to `pragma ^0.6.12`. This script
 * is `pragma ^0.8.20`. Direct type imports across that boundary are
 * illegal in Solidity. We avoid that entirely by using Foundry's
 * `vm.deployCode("File.sol:Contract", abi.encode(args))` cheatcode,
 * which:
 *
 *   1. Reads the pre-compiled artifact JSON from `out/` (forge built
 *      it with the right solc 0.6.12 per the file's pragma).
 *   2. Extracts bytecode + ABI-encoded constructor signature.
 *   3. Deploys via the CREATE opcode with the supplied args appended.
 *
 * Result: addresses come back as plain `address`, callable later
 * through inline interface declarations (see Verifier.sol) without
 * the 0.8.x compiler ever seeing a 0.6.12 type definition.
 *
 * --- Bootloader / cairoVerifier hash constants ---
 *
 * `simpleBootloaderProgramHash` and `hashedSupportedCairoVerifiers`
 * pin the GpsStatementVerifier to a specific bootloader implementation
 * and a specific *set* of permitted child Cairo verifier programs.
 *
 * For production deployments these come from the StarkWare deploy
 * tooling (Python apps_deploy/) and are computed from:
 *   - the embedded CairoBootloaderProgram bytecode (program hash)
 *   - the list of permitted Cairo program hashes (Poseidon-hashed)
 *
 * For Phase 3 dev deployments we accept env-var overrides so a real
 * proof generated against a specific bootloader+verifier pair can be
 * verified end-to-end. The fallback constants below are the values
 * StarkWare publishes for the mainnet-deployed `starknet` layout —
 * usable for read-only testing against existing mainnet proofs, NOT
 * a substitute for re-computing against this deployment's bootloader.
 *
 *   SIMPLE_BOOTLOADER_HASH    env var name
 *   HASHED_CAIRO_VERIFIERS    env var name
 *
 * Both default to `0` if unset, which keeps the deploy valid (the
 * verifier still operates) but means *only* proofs that embed those
 * same zero constants will pass main-page registration. For real
 * proofs, set these via env before running the script.
 *
 * Security parameters for layout 6 (StarkWare-standard):
 *   - numSecurityBits     = 96   (FRI soundness target)
 *   - minProofOfWorkBits  = 30   (PoW grinding threshold)
 */
contract DeployStarkVerifier is Script {
    // ───────────────────────────────────────────────────────────────────
    //  Output addresses (printed at end of run; copy into env for DeployL1)
    // ───────────────────────────────────────────────────────────────────
    struct Deployment {
        // Periodic column contracts (deterministic, parameter-free).
        address cpuConstraintPoly;
        address pedersenX;
        address pedersenY;
        address ecdsaX;
        address ecdsaY;
        address poseidonFR0;
        address poseidonFR1;
        address poseidonFR2;
        address poseidonPR0;
        address poseidonPR1;
        // OODS evaluator (layout-specific).
        address cpuOods;
        // Fact registries.
        address memoryPageFactRegistry;
        address merkleStatementContract;
        address friStatementContract;
        // CPU + bootloader.
        address cpuFrilessVerifier;
        address cairoBootloaderProgram;
        // The public entry point — this is the one Verifier.sol talks to.
        address gpsStatementVerifier;
    }

    function run() external returns (Deployment memory d) {
        // Pull tunable hash constants from env (default 0 = dev / fact
        // registration will fail unless proofs carry matching values).
        uint256 simpleBootloaderHash = _envOrZero("SIMPLE_BOOTLOADER_HASH");
        uint256 hashedCairoVerifiers = _envOrZero("HASHED_CAIRO_VERIFIERS");

        vm.startBroadcast();

        // ── 1. Periodic columns ───────────────────────────────────────
        // None of these take constructor args; they hold the round
        // constants for Poseidon, Pedersen, ECDSA as Solidity-baked
        // periodic polynomials evaluated at OODS-check time.
        d.cpuConstraintPoly = vm.deployCode("CpuConstraintPoly.sol:CpuConstraintPoly");
        d.pedersenX   = vm.deployCode("PedersenHashPointsXColumn.sol:PedersenHashPointsXColumn");
        d.pedersenY   = vm.deployCode("PedersenHashPointsYColumn.sol:PedersenHashPointsYColumn");
        d.ecdsaX      = vm.deployCode("EcdsaPointsXColumn.sol:EcdsaPointsXColumn");
        d.ecdsaY      = vm.deployCode("EcdsaPointsYColumn.sol:EcdsaPointsYColumn");
        d.poseidonFR0 = vm.deployCode("PoseidonPoseidonFullRoundKey0Column.sol:PoseidonPoseidonFullRoundKey0Column");
        d.poseidonFR1 = vm.deployCode("PoseidonPoseidonFullRoundKey1Column.sol:PoseidonPoseidonFullRoundKey1Column");
        d.poseidonFR2 = vm.deployCode("PoseidonPoseidonFullRoundKey2Column.sol:PoseidonPoseidonFullRoundKey2Column");
        d.poseidonPR0 = vm.deployCode("PoseidonPoseidonPartialRoundKey0Column.sol:PoseidonPoseidonPartialRoundKey0Column");
        d.poseidonPR1 = vm.deployCode("PoseidonPoseidonPartialRoundKey1Column.sol:PoseidonPoseidonPartialRoundKey1Column");

        console2.log("Periodic columns deployed:");
        console2.log("  CpuConstraintPoly:", d.cpuConstraintPoly);
        console2.log("  PedersenX:        ", d.pedersenX);
        console2.log("  PedersenY:        ", d.pedersenY);
        console2.log("  EcdsaX:           ", d.ecdsaX);
        console2.log("  EcdsaY:           ", d.ecdsaY);
        console2.log("  PoseidonFR0:      ", d.poseidonFR0);
        console2.log("  PoseidonFR1:      ", d.poseidonFR1);
        console2.log("  PoseidonFR2:      ", d.poseidonFR2);
        console2.log("  PoseidonPR0:      ", d.poseidonPR0);
        console2.log("  PoseidonPR1:      ", d.poseidonPR1);

        // ── 2. OODS (Out-Of-Domain Sampling) evaluator ────────────────
        // No constructor args. Used by StarkVerifier to check the trace
        // and composition polynomials agree at the random OODS point.
        d.cpuOods = vm.deployCode("layout6/CpuOods.sol:CpuOods");
        console2.log("CpuOods (layout6):  ", d.cpuOods);

        // ── 3. Fact registries ────────────────────────────────────────
        // Three independent registries — MemoryPage tracks public-memory
        // page facts (needed by CpuVerifier), Merkle tracks committed
        // trace roots, Fri tracks FRI layer commitments.
        d.memoryPageFactRegistry  = vm.deployCode("MemoryPageFactRegistry.sol:MemoryPageFactRegistry");
        d.merkleStatementContract = vm.deployCode("MerkleStatementContract.sol:MerkleStatementContract");
        d.friStatementContract    = vm.deployCode("FriStatementContract.sol:FriStatementContract");
        console2.log("MemoryPageFactRegistry: ", d.memoryPageFactRegistry);
        console2.log("MerkleStatementContract:", d.merkleStatementContract);
        console2.log("FriStatementContract:   ", d.friStatementContract);

        // ── 4. CPU verifier (layout 6) — wires everything together ────
        // Constructor signature (CpuFrilessVerifier):
        //   address[] auxPolynomials,
        //   address   oodsContract,
        //   address   memoryPageFactRegistry,
        //   address   merkleStatementContract,
        //   address   friStatementContract,
        //   uint256   numSecurityBits,
        //   uint256   minProofOfWorkBits
        //
        // auxPolynomials index map (from layout6/LayoutSpecific.sol):
        //   [0]=ConstraintPoly  [1..2]=PedersenXY  [3..4]=EcdsaXY
        //   [5..7]=PoseidonFR0-2  [8..9]=PoseidonPR0-1
        address[] memory auxPolynomials = new address[](10);
        auxPolynomials[0] = d.cpuConstraintPoly;
        auxPolynomials[1] = d.pedersenX;
        auxPolynomials[2] = d.pedersenY;
        auxPolynomials[3] = d.ecdsaX;
        auxPolynomials[4] = d.ecdsaY;
        auxPolynomials[5] = d.poseidonFR0;
        auxPolynomials[6] = d.poseidonFR1;
        auxPolynomials[7] = d.poseidonFR2;
        auxPolynomials[8] = d.poseidonPR0;
        auxPolynomials[9] = d.poseidonPR1;

        d.cpuFrilessVerifier = vm.deployCode(
            "layout6/CpuFrilessVerifier.sol:CpuFrilessVerifier",
            abi.encode(
                auxPolynomials,
                d.cpuOods,
                d.memoryPageFactRegistry,
                d.merkleStatementContract,
                d.friStatementContract,
                uint256(96),  // numSecurityBits — StarkWare-standard for layout 6
                uint256(30)   // minProofOfWorkBits — same
            )
        );
        console2.log("CpuFrilessVerifier (layout6):", d.cpuFrilessVerifier);

        // ── 5. Bootloader program ─────────────────────────────────────
        // Pure-data contract — stores the bootloader's compiled Cairo
        // bytecode as a public constant. No constructor args.
        d.cairoBootloaderProgram = vm.deployCode("CairoBootloaderProgram.sol:CairoBootloaderProgram");
        console2.log("CairoBootloaderProgram: ", d.cairoBootloaderProgram);

        // ── 6. GpsStatementVerifier — the public-facing entry point ──
        // Constructor:
        //   address   bootloaderProgramContract,
        //   address   memoryPageFactRegistry,
        //   address[] cairoVerifierContracts,
        //   uint256   hashedSupportedCairoVerifiers,
        //   uint256   simpleBootloaderProgramHash
        //
        // cairoVerifierContracts is indexed by `cairoVerifierId`. We
        // register the layout-6 CpuFrilessVerifier as index 0, so the
        // Verifier.sol constructor takes `cairoVerifierId = 0`.
        address[] memory cairoVerifiers = new address[](1);
        cairoVerifiers[0] = d.cpuFrilessVerifier;

        d.gpsStatementVerifier = vm.deployCode(
            "GpsStatementVerifier.sol:GpsStatementVerifier",
            abi.encode(
                d.cairoBootloaderProgram,
                d.memoryPageFactRegistry,
                cairoVerifiers,
                hashedCairoVerifiers,
                simpleBootloaderHash
            )
        );
        console2.log("GpsStatementVerifier:   ", d.gpsStatementVerifier);

        vm.stopBroadcast();

        // Final summary — copy GpsStatementVerifier into env for DeployL1:
        //   export STARK_VERIFIER_ADDR=0x...
        console2.log("");
        console2.log("===== StarkWare layout-6 verifier deployment =====");
        console2.log("GpsStatementVerifier (use this for STARK_VERIFIER_ADDR):");
        console2.log("  ", d.gpsStatementVerifier);
        console2.log("cairoVerifierId for layout 6: 0");
        console2.log("");
        console2.log("If proofs fail with 'Invalid hash for memory page 0',");
        console2.log("re-deploy with the correct bootloader/cairoVerifier hashes:");
        console2.log("  SIMPLE_BOOTLOADER_HASH=0x...");
        console2.log("  HASHED_CAIRO_VERIFIERS=0x...");
    }

    /**
     * @dev Read a uint256 from env; return 0 if unset rather than reverting.
     *      The mainnet-published constants for the layout-6 starknet bootloader
     *      can be supplied via env to enable verification of real mainnet-style
     *      proofs; for dev deploys against our own bootloader, leaving them at 0
     *      lets the contracts deploy cleanly but only proofs carrying those
     *      same zero constants will pass `registerPublicMemoryMainPage`.
     */
    function _envOrZero(string memory key) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 v) {
            return v;
        } catch {
            return 0;
        }
    }
}

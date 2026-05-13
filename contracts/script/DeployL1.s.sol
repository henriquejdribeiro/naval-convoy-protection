// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import "../src/StarknetCoreStub.sol";
import "../src/Registry.sol";
import "../src/Verifier.sol";
import "../src/CommandLog.sol";
import "../src/MockStarkVerifier.sol";

/**
 * @title  DeployL1
 * @notice Deploys the four Phase 2 contracts in dependency order:
 *         1. StarknetCoreStub  — bridge stub Madara checks on startup
 *         2. Registry          — mission specs + verdicts
 *         3. Verifier          — fact registry, depends on Registry
 *         4. CommandLog        — advance command, depends on Registry
 *
 * Then wires them together:
 *   - Registry.setVerifier(address(verifier))
 *
 * Required env vars (loaded via forge's `--env-file` or `vm.envAddress`):
 *
 *   COMMANDER_ADDR     D's commander key address
 *   ALPHA_RELAY_ADDR   ship F's address (alpha lane relay)
 *   BRAVO_RELAY_ADDR   ship B's address (bravo lane relay)
 *
 * Optional env vars — STARK verifier mode switch:
 *
 *   STARK_VERIFIER_ADDR   if set, points to an already-deployed
 *                         GpsStatementVerifier (run DeployStarkVerifier
 *                         first to obtain it). Verifier.sol delegates
 *                         real STARK math to that address — every byte
 *                         of the submitted proof goes through audited
 *                         StarkWare layout-6 verification on-chain.
 *                         **Production / thesis-defence deploys should
 *                         always set this.**
 *
 *                         If unset, a MockStarkVerifier is deployed and
 *                         used instead. The mock accepts any proof
 *                         unconditionally — useful for fast unit tests
 *                         that don't carry real proof bytes.
 *
 *   CAIRO_VERIFIER_ID     index of the CpuFrilessVerifier inside the
 *                         GpsStatementVerifier's `cairoVerifierContracts`
 *                         array. Defaults to 0 (DeployStarkVerifier
 *                         registers layout-6 at index 0). Ignored when
 *                         STARK_VERIFIER_ADDR is unset.
 *
 * The deploy account (loaded via --private-key or --keystore) becomes the
 * initial owner of Registry, Verifier, and CommandLog. In Phase 2 dev this
 * is typically anvil[0] / ship A's key.
 */
contract DeployL1 is Script {
    function run() external {
        address commanderAddr   = vm.envAddress("COMMANDER_ADDR");
        address alphaRelayAddr  = vm.envAddress("ALPHA_RELAY_ADDR");
        address bravoRelayAddr  = vm.envAddress("BRAVO_RELAY_ADDR");

        vm.startBroadcast();
        address deployer = msg.sender;

        // 1. StarknetCoreStub — the L1↔L2 bridge stub Madara needs
        StarknetCoreStub starknet = new StarknetCoreStub();
        console2.log("StarknetCoreStub deployed at:", address(starknet));

        // 2. Registry — owner is the deployer; commander is D's key
        Registry registry = new Registry(deployer, commanderAddr);
        console2.log("Registry         deployed at:", address(registry));

        // 3a. STARK verifier delegate — production GpsStatementVerifier
        //     (supplied via STARK_VERIFIER_ADDR after running
        //     DeployStarkVerifier) or a fresh MockStarkVerifier as
        //     fallback for fast unit tests. The Gps address is castable
        //     to our IStarkVerifier directly: GpsStatementVerifier
        //     inherits FactRegistry via GpsOutputParser, so it natively
        //     exposes both verifyProofAndRegister(...) and
        //     isValid(bytes32) at the ABI level — no adapter needed.
        (address starkVerifierAddr, uint256 cairoVerifierId) = _resolveStarkVerifier();

        // 3b. Verifier — owner is deployer; binds Registry; whitelists relay ships;
        //     delegates STARK math to whichever verifier we resolved above.
        Verifier verifier = new Verifier(
            deployer,
            address(registry),
            alphaRelayAddr,
            bravoRelayAddr,
            starkVerifierAddr,
            cairoVerifierId
        );
        console2.log("Verifier         deployed at:", address(verifier));

        // 4. CommandLog — owner is deployer; binds Registry; commander is D's key
        CommandLog commandLog = new CommandLog(
            deployer,
            address(registry),
            commanderAddr
        );
        console2.log("CommandLog       deployed at:", address(commandLog));

        // 5. Wire Verifier into Registry so registerSafeProof can write verdicts
        registry.setVerifier(address(verifier));
        console2.log("Registry.verifier set to Verifier address");

        vm.stopBroadcast();

        // Summary block — handy for piping into deploy logs
        console2.log("");
        console2.log("======== L1 deployment summary ========");
        console2.log("StarknetCoreStub:", address(starknet));
        console2.log("Registry:        ", address(registry));
        console2.log("Verifier:        ", address(verifier));
        console2.log("CommandLog:      ", address(commandLog));
        console2.log("STARK verifier:  ", starkVerifierAddr);
        console2.log("cairoVerifierId: ", cairoVerifierId);
        console2.log("Owner / deployer:", deployer);
        console2.log("Commander (D):   ", commanderAddr);
        console2.log("Alpha relay (F): ", alphaRelayAddr);
        console2.log("Bravo relay (B): ", bravoRelayAddr);
    }

    /**
     * @dev Resolves which STARK verifier address to wire into Verifier.sol.
     *      Three branches:
     *
     *      A. STARK_VERIFIER_ADDR set → production path. Use the
     *         supplied GpsStatementVerifier address. Optional
     *         CAIRO_VERIFIER_ID overrides the index (defaults to 0).
     *         Emits a log noting we're using real on-chain verification.
     *
     *      B. STARK_VERIFIER_ADDR unset → dev/test path. Deploy a fresh
     *         MockStarkVerifier and return its address. cairoVerifierId
     *         is forced to 0 (the mock ignores it). Logs a clear warning
     *         that proofs are NOT cryptographically verified.
     */
    function _resolveStarkVerifier()
        internal
        returns (address starkVerifierAddr, uint256 cairoVerifierId)
    {
        try vm.envAddress("STARK_VERIFIER_ADDR") returns (address production) {
            starkVerifierAddr = production;
            // CAIRO_VERIFIER_ID is optional; default to 0 (layout-6
            // is the only CpuFrilessVerifier our DeployStarkVerifier
            // registers, and it's at index 0).
            try vm.envUint("CAIRO_VERIFIER_ID") returns (uint256 id) {
                cairoVerifierId = id;
            } catch {
                cairoVerifierId = 0;
            }
            console2.log("Using production STARK verifier at:", starkVerifierAddr);
            console2.log("cairoVerifierId:                  ", cairoVerifierId);
        } catch {
            MockStarkVerifier mockStark = new MockStarkVerifier();
            starkVerifierAddr = address(mockStark);
            cairoVerifierId   = 0;
            console2.log("==============================================");
            console2.log("WARNING: STARK_VERIFIER_ADDR not set - using MockStarkVerifier.");
            console2.log("Proofs will NOT be cryptographically verified.");
            console2.log("For thesis-defence deploys, run DeployStarkVerifier first.");
            console2.log("MockStarkVerifier deployed at:", starkVerifierAddr);
            console2.log("==============================================");
        }
    }
}

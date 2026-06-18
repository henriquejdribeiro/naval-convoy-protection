// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import "../src/StarknetCoreStub.sol";
import "../src/Registry.sol";
import "../src/Verifier.sol";
import "../src/CommandLog.sol";

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
 *   COMMANDER_ADDR        D's commander key address
 *   ALPHA_RELAY_ADDR      ship F's address (alpha lane relay)
 *   BRAVO_RELAY_ADDR      ship B's address (bravo lane relay)
 *
 *   STARK_VERIFIER_ADDR   GpsStatementVerifier address from a prior
 *                         DeployStarkVerifier run. **REQUIRED.** No
 *                         mock fallback — production / thesis-defence
 *                         posture is real STARK verification end-to-end.
 *                         Verifier.sol only calls isValid(factHash)
 *                         on this address; verifyProofAndRegister is
 *                         called separately by path-a-runner during
 *                         Stage A of the two-stage verification model.
 *
 * The deploy account (loaded via --private-key or --keystore) becomes the
 * initial owner of Registry, Verifier, and CommandLog. In dev this is
 * typically anvil[0] / ship A's key.
 */
contract DeployL1 is Script {
    function run() external {
        address commanderAddr   = vm.envAddress("COMMANDER_ADDR");
        address alphaRelayAddr  = vm.envAddress("ALPHA_RELAY_ADDR");
        address bravoRelayAddr  = vm.envAddress("BRAVO_RELAY_ADDR");
        // Fail-loud: no mock fallback. Run DeployStarkVerifier first and
        // pipe its GpsStatementVerifier address into STARK_VERIFIER_ADDR.
        address starkVerifierAddr = vm.envAddress("STARK_VERIFIER_ADDR");
        require(
            starkVerifierAddr != address(0),
            "DeployL1: STARK_VERIFIER_ADDR must be set (run DeployStarkVerifier first)"
        );

        vm.startBroadcast();
        address deployer = msg.sender;

        // 1. StarknetCoreStub — the L1↔L2 bridge stub Madara needs
        StarknetCoreStub starknet = new StarknetCoreStub();
        console2.log("StarknetCoreStub deployed at:", address(starknet));

        // 2. Registry — owner is the deployer; commander is D's key;
        //    starknetCore is the L1↔L2 bridge it will dispatch the
        //    open_mission L1→L2 message through during deploy().
        Registry registry = new Registry(deployer, commanderAddr, address(starknet));
        console2.log("Registry         deployed at:", address(registry));

        // 3. Verifier — Stage B of the two-stage verification model.
        //    Only calls starkVerifier.isValid(factHash); never sees the
        //    proof bytes. Path-a-runner (Stage A) is what actually
        //    submits the proof to GpsStatementVerifier off-chain via
        //    the Rust binary.
        Verifier verifier = new Verifier(
            deployer,
            address(registry),
            alphaRelayAddr,
            bravoRelayAddr,
            starkVerifierAddr
        );
        console2.log("Verifier         deployed at:", address(verifier));

        // 4. CommandLog — binds Registry; commander is D's key, set
        //    immutably at deployment (no rotation path on-chain).
        CommandLog commandLog = new CommandLog(
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
        console2.log("Owner / deployer:", deployer);
        console2.log("Commander (D):   ", commanderAddr);
        console2.log("Alpha relay (F): ", alphaRelayAddr);
        console2.log("Bravo relay (B): ", bravoRelayAddr);
    }
}

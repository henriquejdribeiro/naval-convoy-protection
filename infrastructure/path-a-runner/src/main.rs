// Adapted from vendor/stark-evm-adapter/examples/verify_stone_proof.rs
// with the four StarkWare contract addresses changed to the ones produced
// by our DeployStarkVerifier.s.sol on the local Geth Clique-PoA chain.
//
// Required env vars:
//
//     URL                                  L1 RPC, e.g. http://ship-a:8545
//     PRIVATE_KEY                          relay-ship key (hex, 0x-prefixed)
//     ANNOTATED_PROOF                      path to evm_proof.json
//     FACT_TOPOLOGIES                      path to fact_topologies.json
//
// Hard-coded contract addresses below match our deployment summary in
// deployments/local.env.

use ethers::{
    contract::ContractError,
    core::k256::ecdsa::SigningKey,
    middleware::SignerMiddleware,
    providers::{Http, Middleware, Provider},
    signers::{LocalWallet, Signer, Wallet},
    types::{Address, U64},
    utils::hex,
};
use stark_evm_adapter::{
    annotated_proof::AnnotatedProof,
    annotation_parser::{split_fri_merkle_statements, SplitProofs},
    oods_statement::FactTopology,
    ContractFunctionCall,
};
use std::{convert::TryFrom, env, fs::read_to_string, str::FromStr, sync::Arc};

// ── Deployed addresses on the local Geth Clique chain (DeployStarkVerifier) ──
// Updated after re-deploy with v0.13.0-aligned CairoBootloaderProgram
// (PROGRAM_SIZE = 718) and bootloader hash matching the cairo-bootloader
// library's bundled bytecode.
const MERKLE_STATEMENT_CONTRACT: &str = "0x4EE6eCAD1c2Dae9f525404De8555724e3c35d07B";
const FRI_STATEMENT_CONTRACT:    &str = "0xBEc49fA140aCaA83533fB00A2BB19bDdd0290f25";
const MEMORY_PAGE_FACT_REGISTRY: &str = "0x172076E0166D1F9Cc711C77Adf8488051744980C";
const GPS_STATEMENT_VERIFIER:    &str = "0xfbC22278A96299D91d41C453234d97b4F5Eb9B2d";

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let url = env::var("URL").expect("URL env var required");
    let provider: Provider<Http> = Provider::try_from(url.as_str())?;

    let private_key = env::var("PRIVATE_KEY")
        .expect("PRIVATE_KEY env var required");
    let from_key_bytes = hex::decode(private_key.trim_start_matches("0x")).unwrap();
    let from_signing_key = SigningKey::from_bytes(from_key_bytes.as_slice().into()).unwrap();
    let from_wallet: LocalWallet = LocalWallet::from(from_signing_key);
    println!("Test wallet address: {:?}", from_wallet.address());

    let chain_id = provider.get_chainid().await?.as_u32();
    let signer: Arc<SignerMiddleware<_, _>> = Arc::new(SignerMiddleware::new(
        provider.clone(),
        from_wallet.with_chain_id(chain_id),
    ));

    // Load annotated proof
    let origin_proof_file = read_to_string(env::var("ANNOTATED_PROOF")?)?;
    let annotated_proof: AnnotatedProof = serde_json::from_str(&origin_proof_file)?;
    // Generate split proofs
    let split_proofs: SplitProofs = split_fri_merkle_statements(annotated_proof.clone()).unwrap();

    let topologies_file = read_to_string(env::var("FACT_TOPOLOGIES")?)?;
    let topology_json: serde_json::Value = serde_json::from_str(&topologies_file).unwrap();
    let fact_topologies: Vec<FactTopology> =
        serde_json::from_value(topology_json.get("fact_topologies").unwrap().clone()).unwrap();

    println!("───────────────────────────────────────────────────────────────");
    println!("Phase 1: trace Merkle decommitments");
    println!("───────────────────────────────────────────────────────────────");
    let contract_address = Address::from_str(MERKLE_STATEMENT_CONTRACT).unwrap();
    for i in 0..split_proofs.merkle_statements.len() {
        let key = format!("Trace {}", i);
        let trace_merkle = split_proofs.merkle_statements.get(&key).unwrap();
        let call = trace_merkle.verify(contract_address, signer.clone());
        assert_call(call, &key).await?;
    }

    println!("───────────────────────────────────────────────────────────────");
    println!("Phase 2: FRI decommitments");
    println!("───────────────────────────────────────────────────────────────");
    let contract_address = Address::from_str(FRI_STATEMENT_CONTRACT).unwrap();
    for (i, fri_statement) in split_proofs.fri_merkle_statements.iter().enumerate() {
        let call = fri_statement.verify(contract_address, signer.clone());
        assert_call(call, &format!("FRI statement: {}", i)).await?;
    }

    println!("───────────────────────────────────────────────────────────────");
    println!("Phase 3: memory page registrations");
    println!("───────────────────────────────────────────────────────────────");
    let (_, continuous_pages) = split_proofs.main_proof.memory_page_registration_args();
    let memory_fact_registry_address = Address::from_str(MEMORY_PAGE_FACT_REGISTRY).unwrap();
    for (index, page) in continuous_pages.iter().enumerate() {
        let register_continuous_pages_call =
            split_proofs.main_proof.register_continuous_memory_page(
                memory_fact_registry_address,
                signer.clone(),
                page.clone(),
            );
        let name = format!("register continuous page: {}", index);
        assert_call(register_continuous_pages_call, &name).await?;
    }

    println!("───────────────────────────────────────────────────────────────");
    println!("Phase 4: GpsStatementVerifier.verifyProofAndRegister");
    println!("───────────────────────────────────────────────────────────────");
    let contract_address = Address::from_str(GPS_STATEMENT_VERIFIER).unwrap();
    let task_metadata = split_proofs
        .main_proof
        .generate_tasks_metadata(true, fact_topologies)
        .unwrap();
    let call = split_proofs
        .main_proof
        .verify(contract_address, signer, task_metadata);
    assert_call(call, "Main proof").await?;

    println!("───────────────────────────────────────────────────────────────");
    println!("DONE: proof verified on L1 by deployed StarkWare contracts.");
    println!("───────────────────────────────────────────────────────────────");
    Ok(())
}

async fn assert_call(
    call: ContractFunctionCall,
    name: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    match call.send().await {
        Ok(pending_tx) => match pending_tx.await {
            Ok(mined_tx) => {
                let tx_receipt = mined_tx.unwrap();
                if tx_receipt.status.unwrap_or_default() == U64::from(1) {
                    println!("  ✓ Verified: {}", name);
                    Ok(())
                } else {
                    Err(format!("Transaction failed: {}, but did not revert.", name).into())
                }
            }
            Err(e) => Err(decode_revert_message(e.into()).into()),
        },
        Err(e) => Err(decode_revert_message(e).into()),
    }
}

fn decode_revert_message(
    e: ContractError<SignerMiddleware<Provider<Http>, Wallet<SigningKey>>>,
) -> String {
    match e {
        ContractError::Revert(err) => {
            println!("Revert data: {:?}", err.0);
            err.to_string()
        }
        _ => format!("Transaction failed: {:?}", e),
    }
}

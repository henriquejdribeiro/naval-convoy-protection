// path-a-runner — STAGE A of the two-stage verification model.
//
// Runs the four StarkWare pre-registration phases + main GPS proof
// against a deployed StarkWare mainnet verifier stack on our local
// Geth Clique-PoA chain. After this binary returns success, the fact
// `keccak256(programHash || outputHash)` is registered as valid in
// GpsStatementVerifier's FactRegistry; the convoy Verifier.sol can
// then read that as a cheap state lookup in Stage B.
//
// Adapted from vendor/stark-evm-adapter/examples/verify_stone_proof.rs.
//
// Required env vars:
//
//     URL                                  L1 RPC, e.g. http://ship-a:8545
//     PRIVATE_KEY                          relay-ship key (hex, 0x-prefixed)
//     ANNOTATED_PROOF                      path to evm_proof.json
//     FACT_TOPOLOGIES                      path to fact_topologies.json
//
//     MERKLE_STATEMENT_CONTRACT_ADDR       all four StarkWare contract
//     FRI_STATEMENT_CONTRACT_ADDR          addresses are env-driven so
//     MEMORY_PAGE_FACT_REGISTRY_ADDR       a re-deploy doesn't require
//     GPS_STATEMENT_VERIFIER_ADDR          a rebuild of this binary.
//                                          Source from the deployment
//                                          summary (deployments/local.env)
//                                          that DeployStarkVerifier.s.sol
//                                          writes.

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

fn env_addr(key: &str) -> Address {
    let raw = env::var(key)
        .unwrap_or_else(|_| panic!("required env var {key} not set"));
    Address::from_str(raw.trim())
        .unwrap_or_else(|e| panic!("env var {key} not a valid address: {e}"))
}

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

    // Resolve all four contract addresses from env vars at startup.
    // Fail loud rather than spend tx gas just to discover a typo.
    let merkle_addr = env_addr("MERKLE_STATEMENT_CONTRACT_ADDR");
    let fri_addr    = env_addr("FRI_STATEMENT_CONTRACT_ADDR");
    let mem_addr    = env_addr("MEMORY_PAGE_FACT_REGISTRY_ADDR");
    let gps_addr    = env_addr("GPS_STATEMENT_VERIFIER_ADDR");

    println!("StarkWare contract addresses (from env):");
    println!("  Merkle         : {:?}", merkle_addr);
    println!("  FRI            : {:?}", fri_addr);
    println!("  MemoryPageFact : {:?}", mem_addr);
    println!("  GPS            : {:?}", gps_addr);

    println!("───────────────────────────────────────────────────────────────");
    println!("Phase 1: trace Merkle decommitments");
    println!("───────────────────────────────────────────────────────────────");
    for i in 0..split_proofs.merkle_statements.len() {
        let key = format!("Trace {}", i);
        let trace_merkle = split_proofs.merkle_statements.get(&key).unwrap();
        let call = trace_merkle.verify(merkle_addr, signer.clone());
        assert_call(call, &key).await?;
    }

    println!("───────────────────────────────────────────────────────────────");
    println!("Phase 2: FRI decommitments");
    println!("───────────────────────────────────────────────────────────────");
    for (i, fri_statement) in split_proofs.fri_merkle_statements.iter().enumerate() {
        let call = fri_statement.verify(fri_addr, signer.clone());
        assert_call(call, &format!("FRI statement: {}", i)).await?;
    }

    println!("───────────────────────────────────────────────────────────────");
    println!("Phase 3: memory page registrations");
    println!("───────────────────────────────────────────────────────────────");
    let (_, continuous_pages) = split_proofs.main_proof.memory_page_registration_args();
    for (index, page) in continuous_pages.iter().enumerate() {
        let register_continuous_pages_call =
            split_proofs.main_proof.register_continuous_memory_page(
                mem_addr,
                signer.clone(),
                page.clone(),
            );
        let name = format!("register continuous page: {}", index);
        assert_call(register_continuous_pages_call, &name).await?;
    }

    println!("───────────────────────────────────────────────────────────────");
    println!("Phase 4: GpsStatementVerifier.verifyProofAndRegister");
    println!("───────────────────────────────────────────────────────────────");
    let task_metadata = split_proofs
        .main_proof
        .generate_tasks_metadata(true, fact_topologies)
        .unwrap();
    let call = split_proofs
        .main_proof
        .verify(gps_addr, signer, task_metadata);
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
                // Convoy: dump diagnostic logs (ConvoyDebug* events) when the
                // call is to GpsStatementVerifier — the tx may succeed (when
                // we've bypassed reverts for diagnosis) and we need to see
                // the emitted (publicInputHash, traceCommitment, z, alpha,
                // factHash, composition) values.
                for log in &tx_receipt.logs {
                    // Format: tx_hash topic[0] addr  data(hex)
                    let topic0 = log.topics.first().map(|h| format!("{:?}", h)).unwrap_or_default();
                    let data_hex = format!("0x{}", hex::encode(&log.data));
                    println!(
                        "    [log] addr={:?} topic0={} data={}",
                        log.address, topic0, data_hex
                    );
                }
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

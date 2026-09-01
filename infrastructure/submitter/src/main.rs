//! convoy-submitter — submit a stone-prover STARK proof of
//! safe_area_verify.cairo to the L1 convoy stack through the full
//! StarkWare layout-6 verifier pipeline.
//!
//! Adapted from stark_evm_adapter's examples/verify_stone_proof.rs;
//! retains the four-phase submission shape (trace Merkle, FRI, memory
//! pages, main proof) but re-routes the final call from
//! GpsStatementVerifier directly to our Verifier.registerSafeProof so
//! the relay-whitelist + threshold-reassertion + Registry verdict path
//! runs on top of StarkWare's audited verification math.
//!
//! Environment variables (all required for a real run):
//!
//!     URL                                  L1 RPC endpoint (Geth ship A)
//!     PRIVATE_KEY                          relay-ship key (alpha=ship F, bravo=ship B)
//!     ANNOTATED_PROOF                      path to evm_proof.json (gen-annotated-proof output)
//!     FACT_TOPOLOGIES                      path to fact_topologies.json
//!     CONVOY_VERIFIER_ADDR                 our Verifier (from DeployL1)
//!     MERKLE_STATEMENT_CONTRACT_ADDR       from DeployStarkVerifier
//!     FRI_STATEMENT_CONTRACT_ADDR          from DeployStarkVerifier
//!     MEMORY_PAGE_FACT_REGISTRY_ADDR       from DeployStarkVerifier
//!
//! Public-output extraction:
//!
//!     The Cairo program safe_area_verify.cairo writes six felts to the
//!     output segment via serialize_word, in this order:
//!         [mission_id, drone_id, coverage_permille, max_p_contact,
//!          elapsed_seconds, commitment]
//!     This binary parses those from the annotated proof's public memory
//!     to populate the SafeProofInputs tuple, then derives programHash
//!     and outputHash by keccak-hashing the appropriate inputs (matching
//!     submit_proof_l1.py's logic so the on-chain fact hash agrees).
//!
//! Build (one-time, ~3–5 min on first build to fetch ethers + dependencies):
//!
//!     cd infrastructure/submitter
//!     cargo build --release
//!
//! Then invoke from entrypoint.sh after gen-annotated-proof has produced
//! evm_proof.json and fact_topologies.json.

use anyhow::{anyhow, bail, Context, Result};
use ethers::{
    contract::abigen,
    core::k256::ecdsa::SigningKey,
    middleware::SignerMiddleware,
    providers::{Http, Middleware, Provider},
    signers::{LocalWallet, Signer as SignerTrait},
    types::{Address, Bytes, H256, U256, U64},
};
use stark_evm_adapter::{
    annotated_proof::AnnotatedProof,
    annotation_parser::{split_fri_merkle_statements, SplitProofs},
    oods_statement::FactTopology,
};
use std::{env, fs::read_to_string, str::FromStr, sync::Arc};

// Our convoy Verifier's ABI for `registerSafeProof`. The struct mirrors
// the SafeProofInputs declared in contracts/src/Verifier.sol; ordering
// and field names must stay in lockstep with that definition.
abigen!(
    ConvoyVerifier,
    r#"[
        {
            "type": "function",
            "name": "registerSafeProof",
            "stateMutability": "nonpayable",
            "inputs": [
                {
                    "name": "inputs",
                    "type": "tuple",
                    "internalType": "struct SafeProofInputs",
                    "components": [
                        {"name": "programHash", "type": "bytes32"},
                        {"name": "outputHash",  "type": "bytes32"},
                        {"name": "missionId",   "type": "uint256"},
                        {"name": "droneIndex",  "type": "uint8"},
                        {"name": "stripXStart", "type": "uint32"},
                        {"name": "stripXEnd",   "type": "uint32"},
                        {"name": "stripYStart", "type": "uint32"},
                        {"name": "stripYEnd",   "type": "uint32"},
                        {"name": "verdictBool", "type": "uint8"},
                        {"name": "commitment",  "type": "bytes32"},
                        {"name": "nSteps",      "type": "uint256"}
                    ]
                }
            ],
            "outputs": [
                {"name": "proofId",  "type": "uint256"},
                {"name": "factHash", "type": "bytes32"}
            ]
        }
    ]"#
);
abigen!(
    GpsStatementVerifier,
    r#"[
        function verifyProofAndRegister(uint256[] proofParams, uint256[] proof, uint256[] taskMetadata, uint256[] cairoAuxInput, uint256 cairoVerifierId)
    ]"#
);

type Signer = SignerMiddleware<Provider<Http>, LocalWallet>;

fn env_address(key: &str) -> Result<Address> {
    let raw = env::var(key).with_context(|| format!("env var {} not set", key))?;
    Address::from_str(&raw).with_context(|| format!("env var {} not a valid address: {}", key, raw))
}

fn keccak256(data: &[u8]) -> [u8; 32] {
    use sha3::{Digest, Keccak256};
    let mut hasher = Keccak256::new();
    hasher.update(data);
    let result = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&result);
    out
}

/// Extract the six felts safe_area_verify.cairo writes via serialize_word.
/// Returns them in declaration order: (mission_id, drone_id, coverage_permille,
/// max_p_contact, elapsed_seconds, commitment).
fn extract_public_outputs(annotated_proof: &AnnotatedProof) -> Result<([U256; 8], U256)> {
    // The annotated proof carries the public_input shape Stone emitted;
    // its memory_segments map names a region called "output" with begin
    // and stop addresses, and public_memory is a list of (address, value)
    // pairs covering the entire public memory.
    let public_input = serde_json::to_value(&annotated_proof.public_input)
        .context("serialize public_input to value")?;
    let segments = public_input
        .as_object()
        .and_then(|o| o.get("memory_segments"))
        .and_then(|o| o.as_object())
        .ok_or_else(|| anyhow!("public_input has no memory_segments"))?;
    let output_seg = segments
        .get("output")
        .ok_or_else(|| anyhow!("memory_segments has no 'output' entry"))?;
    let begin = output_seg
        .get("begin_addr")
        .and_then(|v| v.as_u64())
        .ok_or_else(|| anyhow!("output.begin_addr missing"))?;
    let stop = output_seg
        .get("stop_ptr")
        .and_then(|v| v.as_u64())
        .ok_or_else(|| anyhow!("output.stop_ptr missing"))?;
    let public_memory = public_input
        .as_object()
        .and_then(|o| o.get("public_memory"))
        .and_then(|v| v.as_array())
        .ok_or_else(|| anyhow!("public_memory missing"))?;

    let mut pairs: Vec<(u64, U256)> = Vec::new();
    for entry in public_memory {
        let addr = entry
            .get("address")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| anyhow!("public_memory entry missing address"))?;
        if addr < begin || addr >= stop {
            continue;
        }
        let val_str = entry
            .get("value")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("public_memory entry missing value"))?;
        let value = U256::from_str_radix(val_str.trim_start_matches("0x"), 16)
            .with_context(|| format!("public_memory entry value not hex: {}", val_str))?;
        pairs.push((addr, value));
    }
    pairs.sort_by_key(|p| p.0);

    // Bootloader-wrapped output: [simpleBootloaderProgramHash,
    // hashedSupportedCairoVerifiers, nTasks, taskOutputSize, cairoProgramHash,
    // <8 safe_area outputs>]. We need the 8 outputs (last 8) and the Cairo
    // program hash (word just before them) — the GPS registers its fact under
    // that Cairo hash, not keccak-of-JSON.
    if pairs.len() < 9 {
        bail!(
            "expected at least 9 output words (program hash + 8 outputs), got {}: {:?}",
            pairs.len(),
            pairs
        );
    }
    let cairo_program_hash = pairs[pairs.len() - 9].1;
    let values: [U256; 8] = pairs[pairs.len() - 8..]
        .iter()
        .map(|p| p.1)
        .collect::<Vec<_>>()
        .try_into()
        .map_err(|_| anyhow!("could not coerce to [U256; 8]"))?;
    Ok((values, cairo_program_hash))
}

/// Reconstruct the programHash by keccak-hashing the compact JSON encoding
/// of the `data` field in the compiled Cairo program. Matches
/// submit_proof_l1.py's logic exactly.
fn compute_program_hash(safe_area_verify_json: &str) -> Result<[u8; 32]> {
    let parsed: serde_json::Value =
        serde_json::from_str(safe_area_verify_json).context("safe_area_verify.json not JSON")?;
    let data = parsed
        .get("data")
        .ok_or_else(|| anyhow!("safe_area_verify.json missing data field"))?;
    // serde_json::to_string produces compact (no whitespace) encoding,
    // matching json.dumps(..., separators=(",", ":")) in Python.
    let data_compact = serde_json::to_string(data).context("re-encode data array")?;
    Ok(keccak256(data_compact.as_bytes()))
}

/// outputHash = keccak256(abi.encodePacked of the 8 output felts, each 32 bytes big-endian).
fn compute_output_hash(outputs: &[U256; 8]) -> [u8; 32] {
    let mut buf = Vec::with_capacity(32 * 8);
    for v in outputs {
        let mut be = [0u8; 32];
        v.to_big_endian(&mut be);
        buf.extend_from_slice(&be);
    }
    keccak256(&buf)
}

#[tokio::main]
async fn main() -> Result<()> {
    // ── Provider + signer ──────────────────────────────────────────────
    let url = env::var("URL").context("URL env var (L1 RPC) not set")?;
    let provider = Provider::<Http>::try_from(url.as_str())?;

    let pk_raw = env::var("PRIVATE_KEY").context("PRIVATE_KEY env var not set")?;
    let pk_bytes =
        hex::decode(pk_raw.trim_start_matches("0x")).context("PRIVATE_KEY not valid hex")?;
    let signing_key = SigningKey::from_bytes(pk_bytes.as_slice().into())
        .map_err(|e| anyhow!("invalid private key: {:?}", e))?;
    let wallet: LocalWallet = LocalWallet::from(signing_key);
    println!("[submitter] relay wallet: {:?}", wallet.address());

    let chain_id = provider.get_chainid().await?.as_u32();
    let signer: Arc<Signer> = Arc::new(SignerMiddleware::new(
        provider.clone(),
        wallet.with_chain_id(chain_id),
    ));

    // ── Inputs ─────────────────────────────────────────────────────────
    let annotated_proof_path = env::var("ANNOTATED_PROOF")
        .context("ANNOTATED_PROOF env var (path to evm_proof.json) not set")?;
    let annotated_proof_raw = read_to_string(&annotated_proof_path)
        .with_context(|| format!("cannot read ANNOTATED_PROOF at {}", annotated_proof_path))?;
    let annotated_proof: AnnotatedProof = serde_json::from_str(&annotated_proof_raw)
        .context("annotated proof JSON failed to deserialise")?;

    let fact_topologies_path =
        env::var("FACT_TOPOLOGIES").context("FACT_TOPOLOGIES env var not set")?;
    let topologies_raw = read_to_string(&fact_topologies_path)
        .with_context(|| format!("cannot read FACT_TOPOLOGIES at {}", fact_topologies_path))?;
    let topology_json: serde_json::Value =
        serde_json::from_str(&topologies_raw).context("fact topologies not JSON")?;
    let fact_topologies: Vec<FactTopology> = serde_json::from_value(
        topology_json
            .get("fact_topologies")
            .ok_or_else(|| anyhow!("fact_topologies key missing"))?
            .clone(),
    )?;

    // Compiled Cairo program (needed for programHash derivation).
    let safe_area_verify_path = env::var("SAFE_AREA_VERIFY_JSON")
        .context("SAFE_AREA_VERIFY_JSON env var (path to compiled safe_area_verify.json) not set")?;
    let safe_area_verify_raw = read_to_string(&safe_area_verify_path)
        .with_context(|| format!("cannot read {}", safe_area_verify_path))?;

    // ── Split the proof into per-phase contract args ───────────────────
    let split_proofs: SplitProofs = split_fri_merkle_statements(annotated_proof.clone())
        .map_err(|e| anyhow!("split_fri_merkle_statements failed: {:?}", e))?;

    // ── Phase 1: trace Merkle commits ──────────────────────────────────
    let merkle_addr = env_address("MERKLE_STATEMENT_CONTRACT_ADDR")?;
    println!(
        "[submitter] Phase 1: trace Merkle commits → {:?}",
        merkle_addr
    );
    for i in 0..split_proofs.merkle_statements.len() {
        let key = format!("Trace {}", i);
        let trace_merkle = split_proofs
            .merkle_statements
            .get(&key)
            .ok_or_else(|| anyhow!("missing merkle_statements key '{}'", key))?;
        let call = trace_merkle.verify(merkle_addr, signer.clone());
        await_tx(call.send().await?, &key).await?;
    }

    // ── Phase 2: FRI layer commits ─────────────────────────────────────
    let fri_addr = env_address("FRI_STATEMENT_CONTRACT_ADDR")?;
    println!("[submitter] Phase 2: FRI commits → {:?}", fri_addr);
    for (i, fri_statement) in split_proofs.fri_merkle_statements.iter().enumerate() {
        let call = fri_statement.verify(fri_addr, signer.clone());
        await_tx(call.send().await?, &format!("FRI {}", i)).await?;
    }

    // ── Phase 3: continuous memory pages ───────────────────────────────
    let memory_addr = env_address("MEMORY_PAGE_FACT_REGISTRY_ADDR")?;
    println!(
        "[submitter] Phase 3: memory page registrations → {:?}",
        memory_addr
    );
    let (_, continuous_pages) = split_proofs.main_proof.memory_page_registration_args();
    for (i, page) in continuous_pages.iter().enumerate() {
        let call = split_proofs.main_proof.register_continuous_memory_page(
            memory_addr,
            signer.clone(),
            page.clone(),
        );
        await_tx(call.send().await?, &format!("memory page {}", i)).await?;
    }

    // ── Phase 4: register the STARK fact on the GPS, then gate the verdict ──
    let task_metadata = split_proofs
        .main_proof
        .generate_tasks_metadata(true, fact_topologies)
        .map_err(|e| anyhow!("generate_tasks_metadata failed: {:?}", e))?;
    let args = split_proofs.main_proof.contract_function_call(task_metadata);

    // ── Phase 4a: register the fact on the StarkWare GPS (as verify_stone_proof.rs does) ──
    let gps_addr = env_address("GPS_STATEMENT_VERIFIER_ADDR")?;
    println!("[submitter] Phase 4a: GpsStatementVerifier.verifyProofAndRegister → {:?}", gps_addr);
    let gps = GpsStatementVerifier::new(gps_addr, signer.clone());
    let gps_call = gps.verify_proof_and_register(
        args.proof_params.clone(),
        args.proof.clone(),
        args.task_metadata.clone(),
        args.cairo_aux_input.clone(),
        args.cairo_verifier_id,
    ).gas(30_000_000u64);
    let gps_pending = gps_call.send().await?;
    let gps_tx_hash = gps_pending.tx_hash();
    let gps_receipt = gps_pending
        .await?
        .ok_or_else(|| anyhow!("no receipt for verifyProofAndRegister"))?;
    if gps_receipt.status != Some(U64::from(1)) {
        bail!("verifyProofAndRegister reverted: tx {:?}", gps_tx_hash);
    }
    println!("[submitter]   ✓ verifyProofAndRegister: tx {:?}", gps_tx_hash);

    // GPS emits LogMemoryPagesHashes(bytes32 programOutputFact, bytes32[] pagesHashes)
    // when it registers the fact; programOutputFact is the first 32 bytes of the data.
    let lmph_topic = H256::from(keccak256(b"LogMemoryPagesHashes(bytes32,bytes32[])"));
    let program_output_fact: [u8; 32] = gps_receipt
        .logs
        .iter()
        .find(|log| log.topics.first() == Some(&lmph_topic))
        .and_then(|log| log.data.get(0..32))
        .map(|b| {
            let mut o = [0u8; 32];
            o.copy_from_slice(b);
            o
        })
        .ok_or_else(|| anyhow!("LogMemoryPagesHashes event not found in GPS receipt"))?;

    // ── Phase 4b: gate the verdict on the verified fact (our Verifier, 1-arg) ──
    let convoy_verifier_addr = env_address("CONVOY_VERIFIER_ADDR")?;
    println!("[submitter] Phase 4b: Verifier.registerSafeProof → {:?}", convoy_verifier_addr);

    let (outputs, cairo_program_hash) = extract_public_outputs(&annotated_proof)?;
    let [mission_id, drone_id, sx0, sx1, sy0, sy1, verdict, commitment] = outputs;

    // Match the GPS fact = keccak256(abi.encode(cairoProgramHash, programOutputFact)):
    // program hash is the Cairo hash felt, output hash is the node-stack fact from the event.
    let mut program_hash = [0u8; 32];
    cairo_program_hash.to_big_endian(&mut program_hash);
    let output_hash = program_output_fact;

    let pi_value = serde_json::to_value(&annotated_proof.public_input)
        .context("serialize public_input")?;
    let n_steps: U256 = pi_value
        .as_object()
        .and_then(|o| o.get("n_steps"))
        .and_then(|v| v.as_u64())
        .map(U256::from)
        .ok_or_else(|| anyhow!("public_input.n_steps missing"))?;

    let mut commitment_bytes = [0u8; 32];
    commitment.to_big_endian(&mut commitment_bytes);

    let inputs = SafeProofInputs {
        program_hash,
        output_hash,
        mission_id,
        drone_index: drone_id.as_u32() as u8,
        strip_x_start: sx0.as_u32(),
        strip_x_end: sx1.as_u32(),
        strip_y_start: sy0.as_u32(),
        strip_y_end: sy1.as_u32(),
        verdict_bool: verdict.as_u32() as u8,
        commitment: commitment_bytes,
        n_steps,
    };

    println!("[submitter]   programHash: 0x{}", hex::encode(program_hash));
    println!("[submitter]   outputHash:  0x{}", hex::encode(output_hash));
    println!("[submitter]   mission {} drone {} verdict {}", mission_id, drone_id, verdict);
    println!("[submitter]   strip x[{},{}] y[{},{}]", sx0, sx1, sy0, sy1);

    let verifier = ConvoyVerifier::new(convoy_verifier_addr, signer.clone());
    await_tx(verifier.register_safe_proof(inputs).send().await?, "registerSafeProof").await?;

    println!("[submitter] DONE.");
    Ok(())
}

async fn await_tx(
    pending: ethers::providers::PendingTransaction<'_, Http>,
    name: &str,
) -> Result<()> {
    let tx_hash = pending.tx_hash();
    let receipt = pending
        .await
        .with_context(|| format!("await pending tx for {}", name))?
        .ok_or_else(|| anyhow!("no receipt for {}", name))?;
    if receipt.status == Some(U64::from(1)) {
        println!("[submitter]   ✓ {}: tx {:?}", name, tx_hash);
        Ok(())
    } else {
        bail!("[submitter] {} reverted: tx {:?}", name, tx_hash)
    }
}

// Silence unused warning on Bytes — kept in case downstream callers want raw bytes
#[allow(dead_code)]
fn _bytes_to_hex(b: &Bytes) -> String {
    format!("0x{}", hex::encode(&b.0))
}

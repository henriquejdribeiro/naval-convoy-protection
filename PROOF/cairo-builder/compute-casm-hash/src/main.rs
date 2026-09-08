// compute-casm-hash <casm-file.json>
//
// Reads a CASM contract class JSON and prints its compiled_class_hash
// as 0x-prefixed lowercase hex.
//
// Uses cairo-lang-starknet-classes v2.12.3 — the exact version Madara
// v0.10.0 uses internally — so the hash we print matches what madara
// computes when validating a DECLARE transaction. starkli's bundled
// version is 2.11.4, which produces a different hash for the same CASM.

use anyhow::{Context, Result};
use cairo_lang_starknet_classes::casm_contract_class::CasmContractClass;
use std::env;
use std::fs;

fn main() -> Result<()> {
    let path = env::args().nth(1).context("usage: compute-casm-hash <casm-file.json>")?;
    let raw = fs::read_to_string(&path).with_context(|| format!("read {}", path))?;
    let casm: CasmContractClass = serde_json::from_str(&raw).context("parse CASM JSON")?;
    let hash = casm.compiled_class_hash();
    println!("{:#066x}", hash.to_biguint());
    Ok(())
}

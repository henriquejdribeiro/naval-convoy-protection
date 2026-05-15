//! convoy-bootloader-cli — wrap a compiled Cairo task in the simple
//! bootloader and emit the proof-mode artefacts Stone consumes.
//!
//! Replaces the `cairo-run` step in entrypoint.sh. Output files
//! (trace.bin, memory.bin, public_input.json, private_input.json,
//! fact_topologies.json) are byte-compatible with what `cairo-run
//! --proof_mode` produces, except that the public_input now reflects
//! the bootloader's envelope on top of the task's output — which is
//! what GpsStatementVerifier on L1 expects.
//!
//! Usage:
//!     convoy-bootloader-cli \
//!         --task /proofs/safe_area_verify.json \
//!         --task-input /proofs/program_input.json \
//!         --output-dir /proofs \
//!         --layout starknet \
//!         --bootloader-hash 0xd875840ac697dbeedb3d4c8f2a61889bc1d5f1af91e67a7cc7360e8faf35bf

use std::{fs, fs::File, io::Write, path::PathBuf};

use anyhow::{anyhow, Context, Result};
use bincode::{enc::write::Writer as BincodeWriter, error::EncodeError};
use cairo_bootloader::{
    bootloaders::load_bootloader,
    insert_bootloader_input,
    tasks::make_bootloader_tasks,
    BootloaderConfig, BootloaderHintProcessor, BootloaderInput, PackedOutput,
    SimpleBootloaderInput,
};
use cairo_vm::{
    cairo_run::{cairo_run_program_with_initial_scope, write_encoded_memory, write_encoded_trace, CairoRunConfig},
    serde::deserialize_program::Identifier,
    types::{exec_scope::ExecutionScopes, layout_name::LayoutName},
    Felt252,
};
use clap::Parser;
use std::collections::HashMap;

#[derive(Parser, Debug)]
#[command(name = "convoy-bootloader-cli")]
#[command(about = "Wrap a Cairo task in the simple bootloader and produce Stone-compatible artefacts")]
struct Args {
    /// Path to the task as a Cairo PIE (Position-Independent Executable).
    /// Produced by `cairo-run --cairo_pie_output <path>` with the task's
    /// program_input.json baked in. The bootloader expects PIE form when
    /// the task program reads from program_input via hints (as our
    /// safe_area_verify.cairo does).
    #[arg(long)]
    task_pie: PathBuf,

    /// Directory to dump artefacts into. Created if it doesn't exist.
    #[arg(long)]
    output_dir: PathBuf,

    /// Cairo VM layout. Use "starknet" to match the layout-6 verifier
    /// deployed by DeployStarkVerifier.s.sol.
    #[arg(long, default_value = "starknet")]
    layout: String,

    /// Bootloader program hash to embed in the bootloader's public output.
    /// MUST match the SIMPLE_BOOTLOADER_HASH constant the on-chain
    /// GpsStatementVerifier was deployed with (scripts/bootloader-hashes.env).
    #[arg(long, default_value = "0x3106b7628a3cbddadb733ea96284977cc21e890d61aa6dee00badcbd90065ce")]
    bootloader_hash: String,
}

/// Bridge from std::io::Write to bincode 2.x's Writer trait. cairo-vm's
/// write_encoded_trace / write_encoded_memory take `&mut impl Writer`, and
/// bincode does not auto-implement Writer for std::io::Write types (only
/// for &mut T, SizeWriter, and SliceWriter). This is the smallest adapter
/// that lets us stream the bincode output of those functions into a File.
struct IoWriter<W: Write>(W);

impl<W: Write> BincodeWriter for IoWriter<W> {
    fn write(&mut self, bytes: &[u8]) -> Result<(), EncodeError> {
        self.0
            .write_all(bytes)
            .map_err(|e| EncodeError::Io { inner: e, index: 0 })
    }
}

fn parse_layout(s: &str) -> Result<LayoutName> {
    Ok(match s {
        "plain" => LayoutName::plain,
        "small" => LayoutName::small,
        "dex" => LayoutName::dex,
        "recursive" => LayoutName::recursive,
        "starknet" => LayoutName::starknet,
        "starknet_with_keccak" => LayoutName::starknet_with_keccak,
        "recursive_large_output" => LayoutName::recursive_large_output,
        "recursive_with_poseidon" => LayoutName::recursive_with_poseidon,
        "all_solidity" => LayoutName::all_solidity,
        "all_cairo" => LayoutName::all_cairo,
        _ => return Err(anyhow!("unknown layout: {}", s)),
    })
}

fn parse_felt(hex_str: &str) -> Result<Felt252> {
    let trimmed = hex_str.trim_start_matches("0x");
    Felt252::from_hex(&format!("0x{}", trimmed))
        .map_err(|e| anyhow!("invalid felt252 hex {}: {:?}", hex_str, e))
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Ensure output directory exists.
    fs::create_dir_all(&args.output_dir)
        .with_context(|| format!("create output dir {:?}", args.output_dir))?;

    // 1. Load the bootloader (embedded in the cairo-bootloader crate at
    //    vendor/cairo-bootloader/resources/bootloader-0.13.0.json).
    println!("[bootloader-cli] loading simple bootloader v0.13.0");
    let bootloader_program = load_bootloader().context("failed to load embedded bootloader")?;

    // 2. Load the task as a PIE file. PIE (Position-Independent Executable)
    //    is a zip-like format produced by `cairo-run --cairo_pie_output`
    //    that bundles the compiled program with the runtime state it
    //    needs (program_input baked in, memory layout, builtin segments).
    //    The bootloader requires this form for any task that reads
    //    program_input via Cairo hints.
    println!("[bootloader-cli] loading task PIE: {:?}", args.task_pie);
    let pie_bytes = fs::read(&args.task_pie)
        .with_context(|| format!("read task PIE at {:?}", args.task_pie))?;

    // 3. Wrap the PIE in a TaskSpec for the bootloader. make_bootloader_tasks
    //    takes programs and PIEs as separate slices; we have one PIE, no
    //    raw programs.
    let tasks = make_bootloader_tasks(&[], &[&pie_bytes])
        .map_err(|e| anyhow!("make_bootloader_tasks failed: {:?}", e))?;

    // 4. Wire the bootloader input. fact_topologies_path tells the
    //    bootloader where to dump fact_topologies.json — the file the
    //    Rust submitter needs for the L1 phases 1–3.
    let fact_topologies_path = args.output_dir.join("fact_topologies.json");
    let bootloader_hash = parse_felt(&args.bootloader_hash)?;

    let n_tasks = tasks.len();
    let bootloader_input = BootloaderInput {
        simple_bootloader_input: SimpleBootloaderInput {
            fact_topologies_path: Some(fact_topologies_path.clone()),
            single_page: false,
            tasks,
        },
        bootloader_config: BootloaderConfig {
            simple_bootloader_program_hash: bootloader_hash,
            // Non-recursive deployment: no supported recursive verifiers.
            // This must agree with the HASHED_CAIRO_VERIFIERS = 0 the
            // GpsStatementVerifier was deployed with (which is the hash
            // of an empty list).
            supported_cairo_verifier_program_hashes: vec![],
        },
        packed_outputs: vec![PackedOutput::Plain(vec![]); n_tasks],
    };

    let mut exec_scopes = ExecutionScopes::new();
    insert_bootloader_input(&mut exec_scopes, bootloader_input);

    // The execute_task hints inside the bootloader expect the bootloader's
    // own identifiers to be in scope under "bootloader_program_identifiers".
    // The cairo-bootloader crate only sets this in its test fixtures; in
    // production use the caller is responsible. ProgramIdentifiers is just
    // HashMap<String, Identifier> — both standard cairo-vm types.
    let bootloader_identifiers: HashMap<String, Identifier> = bootloader_program
        .iter_identifiers()
        .map(|(name, ident)| (name.to_string(), ident.clone()))
        .collect();
    exec_scopes.insert_value("bootloader_program_identifiers", bootloader_identifiers);

    // 5. Run.
    let layout = parse_layout(&args.layout)?;
    println!("[bootloader-cli] running bootloader on {} task(s), layout={}", n_tasks, args.layout);

    let cairo_run_config = CairoRunConfig {
        entrypoint: "main",
        trace_enabled: true,
        relocate_mem: true,
        layout,
        proof_mode: true,
        secure_run: None,
        disable_trace_padding: false,
        allow_missing_builtins: None,
    };

    let mut hint_processor = BootloaderHintProcessor::new();
    let runner = cairo_run_program_with_initial_scope(
        &bootloader_program,
        &cairo_run_config,
        &mut hint_processor,
        exec_scopes,
    )
    .map_err(|e| anyhow!("cairo_run_program_with_initial_scope failed: {:?}", e))?;

    // 6. Dump artefacts. The serialisation here matches cairo-run --proof_mode
    //    so cpu_air_prover doesn't see any difference.
    let trace_path = args.output_dir.join("trace.bin");
    let memory_path = args.output_dir.join("memory.bin");
    let public_input_path = args.output_dir.join("public_input.json");
    let private_input_path = args.output_dir.join("private_input.json");

    // Trace: bincode-encoded RelocatedTraceEntry stream, streamed to disk
    // through our IoWriter shim (bincode 2.x doesn't auto-impl Writer for
    // std::io::Write types).
    {
        let relocated_trace = runner
            .relocated_trace
            .as_ref()
            .ok_or_else(|| anyhow!("relocated_trace missing — proof_mode should have populated it"))?;
        let file = File::create(&trace_path)
            .with_context(|| format!("create {:?}", trace_path))?;
        let mut writer = IoWriter(file);
        write_encoded_trace(relocated_trace, &mut writer)
            .map_err(|e| anyhow!("write_encoded_trace failed: {:?}", e))?;
    }

    // Memory: same pattern.
    {
        let file = File::create(&memory_path)
            .with_context(|| format!("create {:?}", memory_path))?;
        let mut writer = IoWriter(file);
        write_encoded_memory(&runner.relocated_memory, &mut writer)
            .map_err(|e| anyhow!("write_encoded_memory failed: {:?}", e))?;
    }

    // Public input: cairo-vm's AirPublicInput has its own `serialize_json`
    // (it doesn't implement serde::Serialize directly because internal
    // representations vary by builtin layout).
    {
        let public_input = runner
            .get_air_public_input()
            .map_err(|e| anyhow!("get_air_public_input failed: {:?}", e))?;
        let public_input_json = public_input
            .serialize_json()
            .map_err(|e| anyhow!("serialize_json on public_input failed: {:?}", e))?;
        fs::write(&public_input_path, public_input_json)
            .with_context(|| format!("write {:?}", public_input_path))?;
    }

    // Private input: AirPrivateInput doesn't have serialize_json — it has
    // `to_serializable(trace_path, memory_path)` which produces a
    // serde-Serialize wrapper carrying the artefact paths so a downstream
    // verifier can locate trace.bin and memory.bin alongside the JSON.
    {
        let private_input = runner.get_air_private_input();
        let trace_path_str = trace_path.to_string_lossy().to_string();
        let memory_path_str = memory_path.to_string_lossy().to_string();
        let serializable = private_input.to_serializable(trace_path_str, memory_path_str);
        let private_input_json =
            serde_json::to_string_pretty(&serializable).context("serialize private_input")?;
        fs::write(&private_input_path, private_input_json)
            .with_context(|| format!("write {:?}", private_input_path))?;
    }

    println!("[bootloader-cli] DONE");
    println!("  trace:           {:?}", trace_path);
    println!("  memory:          {:?}", memory_path);
    println!("  public_input:    {:?}", public_input_path);
    println!("  private_input:   {:?}", private_input_path);
    println!("  fact_topologies: {:?}", fact_topologies_path);
    Ok(())
}

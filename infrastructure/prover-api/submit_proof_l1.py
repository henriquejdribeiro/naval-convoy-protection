#!/usr/bin/env python3
"""
submit_proof_l1.py — submit a Stone proof's fact to the convoy Verifier on L1.

Calls Verifier.registerSafeProof(SafeProofInputs, uint256[] proofParams,
uint256[] proof, uint256[] taskMetadata, uint256[] cairoAuxInput) on the L1
Verifier contract. The first argument is the 9-field SafeProofInputs struct
extracted from the Cairo program's public outputs; the remaining four arrays
are the EVM-format proof payload produced by `stark_evm_adapter`.

Pipeline this script sits at the end of:

  1. cairo-compile + cairo-run               (cairo-lang)
  2. cpu_air_prover                          (Stone)
  3. cpu_air_verifier                        (Stone off-chain sanity check)
  4. stark_evm_adapter gen-annotated-proof   → /proofs/evm_proof.json
  5. SPLIT STEP — produces:
        /proofs/main_proof_contract_args.json
     containing fields { proof_params, proof, task_metadata,
     cairo_aux_input, cairo_verifier_id }. Today this file must be
     produced by an external tool (the stark_evm_adapter Rust crate's
     `split_fri_merkle_statements()` library function, exposed via a
     small Rust helper binary planned alongside this script). Once
     that helper lands, entrypoint.sh will run it automatically; for
     now this script errors clearly if the file is missing.
  6. *this script*: reads the contract-args JSON, builds the cast
     send call to Verifier.registerSafeProof with the full 5-arg
     ABI, and writes submit_log.json.

NOTE: this is step 6 (the final, application-level call). For a real
proof to verify on-chain against StarkWare's GpsStatementVerifier, three
additional pre-registration phases must run *before* this script:

  (a) Trace Merkle commits → MerkleStatementContract.verifyMerkle()
  (b) FRI layer commits    → FriStatementContract.verifyFRI()
  (c) Memory page facts    → MemoryPageFactRegistry.registerContinuousMemoryPage()

Those calls are also planned in the same Rust helper binary; they target
StarkWare contracts directly, not the convoy Verifier. The MockStarkVerifier
path does not require them (it accepts any contract-args payload). The real
GpsStatementVerifier path will fail at registerPublicMemoryMainPage until
phases (a)-(c) are wired.

Usage:
    python3 submit_proof_l1.py <proofs_dir> <program_input_path>

Required env vars:
    GETH_RPC_URL          default http://ship-a:8545
    VERIFIER_ADDR         deployed Verifier contract address (no default)
    ALPHA_RELAY_PK        ship F's private key (default: anvil[5])
    BRAVO_RELAY_PK        ship B's private key (default: anvil[1])
"""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# ── Defaults (anvil[1] = ship B = bravo relay; anvil[5] = ship F = alpha relay) ───
ANVIL_BRAVO_PK = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
ANVIL_ALPHA_PK = "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba"

DRONE_ALPHA = 1
DRONE_BRAVO = 2


def keccak256(data: bytes) -> str:
    """Keccak-256 hash → 0x-prefixed hex string."""
    try:
        from sha3 import keccak_256  # type: ignore
    except ImportError:
        # eth-utils ships keccak too
        from eth_utils.crypto import keccak  # type: ignore
        return "0x" + keccak(data).hex()
    k = keccak_256()
    k.update(data)
    return "0x" + k.hexdigest()


def cast_send(rpc: str, pk: str, contract: str, sig: str, *args: str, label: str = "tx") -> str:
    """Run `cast send`; return the broadcast tx hash."""
    cmd = [
        "cast", "send",
        "--rpc-url", rpc,
        "--private-key", pk,
        contract, sig,
        *args,
        "--json",
    ]
    print(f"[submit] {label}: cast send {sig}")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"[submit] {label} FAILED")
        print(r.stderr[:1500])
        raise SystemExit(1)
    receipt = json.loads(r.stdout)
    return receipt.get("transactionHash", "")


def cast_call(rpc: str, contract: str, sig: str, *args: str) -> str:
    """Run `cast call` and return raw stdout (hex)."""
    cmd = ["cast", "call", "--rpc-url", rpc, contract, sig, *args]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"[submit] cast call failed: {r.stderr[:300]}")
        return ""
    return r.stdout.strip()


def load_contract_args(contract_args_path: Path) -> dict[str, list[str]]:
    """
    Read the 4 calldata arrays Verifier.registerSafeProof requires, from the
    JSON produced by stark_evm_adapter's split step.

    Expected file shape (matches stark-evm-adapter's main_proof_contract_args):

        {
          "proof_params":      [<12 hex strings>],
          "proof":             [<hundreds of hex strings>],
          "task_metadata":     [<few hex strings>],
          "cairo_aux_input":   [<~30 hex strings>],
          "cairo_verifier_id": "0x6"           # informational only;
                                               # Verifier.sol stores its
                                               # cairoVerifierId immutably
                                               # at deploy time, so this
                                               # field is NOT passed in
                                               # the per-call args.
        }

    Returns a dict with normalised hex strings for the four arrays we need.
    Raises SystemExit with a clear message if the file is missing or malformed,
    so the caller can be steered toward the Rust split-helper that produces it.
    """
    if not contract_args_path.exists():
        raise SystemExit(
            f"[submit] missing {contract_args_path}\n"
            "        Run the stark_evm_adapter split helper before this script.\n"
            "        The helper takes evm_proof.json (annotated) and emits the\n"
            "        per-task contract-args JSONs; without it, registerSafeProof\n"
            "        cannot be called with the correct ABI."
        )

    args = json.loads(contract_args_path.read_text())
    for key in ("proof_params", "proof", "task_metadata", "cairo_aux_input"):
        if key not in args:
            raise SystemExit(
                f"[submit] {contract_args_path} missing field '{key}' "
                "— is this the right file format?"
            )

    def norm(v: str | int) -> str:
        """Coerce element to 0x-prefixed lowercase hex for cast."""
        if isinstance(v, int):
            return f"0x{v:x}"
        s = str(v).strip().lower()
        return s if s.startswith("0x") else f"0x{s}"

    return {
        "proof_params":    [norm(x) for x in args["proof_params"]],
        "proof":           [norm(x) for x in args["proof"]],
        "task_metadata":   [norm(x) for x in args["task_metadata"]],
        "cairo_aux_input": [norm(x) for x in args["cairo_aux_input"]],
    }


def format_uint256_array(arr: list[str]) -> str:
    """Format a list of hex strings as the bracket notation cast expects for uint256[]."""
    return "[" + ",".join(arr) + "]"


def extract_public_outputs(public_input_path: Path, evm_proof_path: Path | None) -> list[int]:
    """
    Pull the 6 felt252 public outputs serialized by safe_area_verify.cairo.

    Order (must match the Cairo program's serialize_word calls):
       [mission_id, drone_id, coverage_permille, max_p_contact, elapsed_seconds, commitment]

    The values live in the output segment of public memory. We prefer
    evm_proof.json if available (clean public_memory list), falling back
    to public_input.json's memory_segments.output addresses.
    """
    if evm_proof_path and evm_proof_path.exists():
        ep = json.loads(evm_proof_path.read_text())
        public_memory = ep.get("public_input", {}).get("public_memory", [])
        segs = ep.get("public_input", {}).get("memory_segments", {})
    else:
        ep = json.loads(public_input_path.read_text())
        public_memory = ep.get("public_memory", [])
        segs = ep.get("memory_segments", {})

    out_seg = segs.get("output", {})
    begin, stop = out_seg.get("begin_addr"), out_seg.get("stop_ptr")
    if begin is None or stop is None:
        raise SystemExit("[submit] no output segment in public memory")

    # Collect (addr, value) pairs in [begin, stop)
    pairs = []
    for entry in public_memory:
        addr = entry["address"]
        if begin <= addr < stop:
            pairs.append((addr, int(entry["value"], 16) if isinstance(entry["value"], str) else entry["value"]))
    pairs.sort(key=lambda p: p[0])
    values = [v for _, v in pairs]
    if len(values) != 6:
        raise SystemExit(
            f"[submit] expected 6 public outputs, got {len(values)}: {values}"
        )
    return values


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    proofs_dir = Path(sys.argv[1])
    input_path = Path(sys.argv[2])

    rpc = os.environ.get("GETH_RPC_URL", "http://ship-a:8545")
    verifier_addr = os.environ.get("VERIFIER_ADDR", "")
    alpha_pk = os.environ.get("ALPHA_RELAY_PK", ANVIL_ALPHA_PK)
    bravo_pk = os.environ.get("BRAVO_RELAY_PK", ANVIL_BRAVO_PK)
    if not verifier_addr:
        raise SystemExit("[submit] VERIFIER_ADDR env var required")

    program_path        = proofs_dir / "safe_area_verify.json"
    public_input_path   = proofs_dir / "public_input.json"
    proof_path          = proofs_dir / "proof.json"
    evm_proof_path      = proofs_dir / "evm_proof.json"
    contract_args_path  = proofs_dir / "main_proof_contract_args.json"

    if not program_path.exists() or not public_input_path.exists():
        raise SystemExit("[submit] required artefacts missing — has the prover run?")

    # Load the four calldata arrays for Verifier.registerSafeProof.
    # See load_contract_args() docstring for where this file comes from.
    contract_args = load_contract_args(contract_args_path)

    # ── Compute fact hashes ───────────────────────────────────────────
    program_data = json.loads(program_path.read_text()).get("data", [])
    program_bytes = json.dumps(program_data, separators=(",", ":")).encode()
    program_hash = keccak256(program_bytes)

    outputs = extract_public_outputs(public_input_path, evm_proof_path)
    mission_id, drone_id, coverage_permille, max_p, elapsed, commitment = outputs

    # outputHash = keccak256(abi.encodePacked of all 6 output values, 32 bytes each)
    output_bytes = b"".join(v.to_bytes(32, "big") for v in outputs)
    output_hash = keccak256(output_bytes)

    fact_data = bytes.fromhex(program_hash[2:]) + bytes.fromhex(output_hash[2:])
    fact_hash = keccak256(fact_data)

    n_steps = json.loads(public_input_path.read_text())["n_steps"]
    proof_size = proof_path.stat().st_size if proof_path.exists() else 0

    print("[submit] ── public outputs from Cairo program ─────────")
    print(f"  mission_id                {mission_id}")
    print(f"  drone_id           {drone_id}")
    print(f"  coverage_permille  {coverage_permille}")
    print(f"  max_p_contact      {max_p}")
    print(f"  elapsed_seconds    {elapsed}")
    print(f"  commitment         0x{commitment:064x}")
    print()
    print("[submit] ── fact components ───────────────────────────")
    print(f"  programHash  {program_hash}")
    print(f"  outputHash   {output_hash}")
    print(f"  factHash     {fact_hash}")
    print(f"  proofSize    {proof_size} bytes")
    print(f"  nSteps       {n_steps}")

    # ── Pick the relay key for this lane ──────────────────────────────
    if drone_id == DRONE_ALPHA:
        pk = alpha_pk
        lane = "alpha (F)"
    elif drone_id == DRONE_BRAVO:
        pk = bravo_pk
        lane = "bravo (B)"
    else:
        raise SystemExit(f"[submit] invalid drone_id from program output: {drone_id}")

    # ── Build the SafeProofInputs tuple + the four uint256[] arrays ──
    #
    # Verifier.registerSafeProof signature (Verifier.sol):
    #
    #   registerSafeProof(
    #       SafeProofInputs calldata inputs,        // 9-field struct
    #       uint256[]       calldata proofParams,   // FRI configuration
    #       uint256[]       calldata proof,         // STARK proof body
    #       uint256[]       calldata taskMetadata,  // per-task metadata
    #       uint256[]       calldata cairoAuxInput  // Cairo public inputs
    #   )
    #
    # cairoVerifierId is NOT passed per-call — it lives as an immutable
    # state variable on the Verifier, set at deploy time to the layout
    # index (0 for our single layout-6 CpuFrilessVerifier).
    commitment_hex = f"0x{commitment:064x}"
    tuple_args = (
        f"({program_hash},{output_hash},"
        f"{mission_id},{drone_id},"
        f"{coverage_permille},{max_p},{elapsed},"
        f"{commitment_hex},{n_steps})"
    )
    proof_params_arr   = format_uint256_array(contract_args["proof_params"])
    proof_arr          = format_uint256_array(contract_args["proof"])
    task_metadata_arr  = format_uint256_array(contract_args["task_metadata"])
    cairo_aux_input_arr = format_uint256_array(contract_args["cairo_aux_input"])

    sig = (
        "registerSafeProof("
        "(bytes32,bytes32,uint256,uint256,uint256,uint256,uint256,bytes32,uint256),"
        "uint256[],"
        "uint256[],"
        "uint256[],"
        "uint256[])"
    )

    print(f"\n[submit] sending registerSafeProof from {lane} relay key")
    print(f"[submit]   proofParams:    {len(contract_args['proof_params'])} elements")
    print(f"[submit]   proof:          {len(contract_args['proof'])} elements")
    print(f"[submit]   taskMetadata:   {len(contract_args['task_metadata'])} elements")
    print(f"[submit]   cairoAuxInput:  {len(contract_args['cairo_aux_input'])} elements")
    tx_hash = cast_send(
        rpc, pk, verifier_addr, sig,
        tuple_args,
        proof_params_arr,
        proof_arr,
        task_metadata_arr,
        cairo_aux_input_arr,
        label=f"{lane} fact",
    )

    # Confirm fact registered
    is_valid_raw = cast_call(rpc, verifier_addr, "isValid(bytes32)(bool)", fact_hash)
    is_valid = is_valid_raw.lower().strip() in ("true", "0x1", "1")

    log = {
        "lane":             lane,
        "rpc":              rpc,
        "verifierAddr":     verifier_addr,
        "txHash":           tx_hash,
        "factHash":         fact_hash,
        "factVerifiedOnChain": is_valid,
        "programHash":      program_hash,
        "outputHash":       output_hash,
        "publicOutputs": {
            "mission_id":              mission_id,
            "drone_id":         drone_id,
            "coveragePermille": coverage_permille,
            "maxContactBp":     max_p,
            "elapsedSeconds":   elapsed,
            "commitment":       commitment_hex,
        },
        "proofSize":        proof_size,
        "nSteps":           n_steps,
        "submittedAt":      datetime.now(timezone.utc).isoformat(),
    }
    log_path = proofs_dir / "submit_log.json"
    log_path.write_text(json.dumps(log, indent=2))

    print()
    print("====================================================")
    print(f"  REGISTERED SAFE PROOF ON L1 — {lane}")
    print(f"  tx:        {tx_hash}")
    print(f"  factHash:  {fact_hash}")
    print(f"  isValid:   {is_valid}")
    print(f"  log:       {log_path}")
    print("====================================================")
    return 0


if __name__ == "__main__":
    sys.exit(main())

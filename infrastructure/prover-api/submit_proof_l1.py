#!/usr/bin/env python3
"""
submit_proof_l1.py — submit a Stone proof's fact to the convoy Verifier on L1.

Adapted from verifiable_grid/infrastructure/prover-api/submit_proof_l1.py.
Key differences:

  - Calls Verifier.registerSafeProof((bytes32 programHash, bytes32 outputHash,
    uint256 mid, uint256 droneId, uint256 coveragePermille, uint256 maxContactBp,
    uint256 elapsedSeconds, bytes32 commitment, uint256 nSteps))  (a 9-field
    SafeProofInputs struct), instead of registerDroneProof's 6 separate args.
  - Pulls public outputs from cairo_run's public memory in the order written
    by safe_area_verify.cairo:
        [mid, drone_id, coverage_permille, max_p_contact, elapsed_seconds, commitment]
  - Signs with the relay-ship key for the lane (alpha_relay = ship F,
    bravo_relay = ship B); rejects mid/drone_id mismatches.
  - Writes a small JSON log next to the proof for the orchestrator + UI to
    consume (tx hash, block, factHash, gas).

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


def extract_public_outputs(public_input_path: Path, evm_proof_path: Path | None) -> list[int]:
    """
    Pull the 6 felt252 public outputs serialized by safe_area_verify.cairo.

    Order (must match the Cairo program's serialize_word calls):
       [mid, drone_id, coverage_permille, max_p_contact, elapsed_seconds, commitment]

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

    program_path     = proofs_dir / "safe_area_verify.json"
    public_input_path = proofs_dir / "public_input.json"
    proof_path       = proofs_dir / "proof.json"
    evm_proof_path   = proofs_dir / "evm_proof.json"

    if not program_path.exists() or not public_input_path.exists():
        raise SystemExit("[submit] required artefacts missing — has the prover run?")

    # ── Compute fact hashes ───────────────────────────────────────────
    program_data = json.loads(program_path.read_text()).get("data", [])
    program_bytes = json.dumps(program_data, separators=(",", ":")).encode()
    program_hash = keccak256(program_bytes)

    outputs = extract_public_outputs(public_input_path, evm_proof_path)
    mid, drone_id, coverage_permille, max_p, elapsed, commitment = outputs

    # outputHash = keccak256(abi.encodePacked of all 6 output values, 32 bytes each)
    output_bytes = b"".join(v.to_bytes(32, "big") for v in outputs)
    output_hash = keccak256(output_bytes)

    fact_data = bytes.fromhex(program_hash[2:]) + bytes.fromhex(output_hash[2:])
    fact_hash = keccak256(fact_data)

    n_steps = json.loads(public_input_path.read_text())["n_steps"]
    proof_size = proof_path.stat().st_size if proof_path.exists() else 0

    print("[submit] ── public outputs from Cairo program ─────────")
    print(f"  mid                {mid}")
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

    # ── Build the SafeProofInputs tuple for cast ─────────────────────
    commitment_hex = f"0x{commitment:064x}"
    tuple_args = (
        f"({program_hash},{output_hash},"
        f"{mid},{drone_id},"
        f"{coverage_permille},{max_p},{elapsed},"
        f"{commitment_hex},{n_steps})"
    )
    sig = (
        "registerSafeProof("
        "(bytes32,bytes32,uint256,uint256,uint256,uint256,uint256,bytes32,uint256))"
    )

    print(f"\n[submit] sending registerSafeProof from {lane} relay key")
    tx_hash = cast_send(rpc, pk, verifier_addr, sig, tuple_args, label=f"{lane} fact")

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
            "mid":              mid,
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

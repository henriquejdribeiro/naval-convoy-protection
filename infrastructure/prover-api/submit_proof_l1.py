#!/usr/bin/env python3
"""
submit_proof_l1.py — Stage B: register a Stone proof's APPLICATION-LEVEL
verdict with the convoy Verifier on L1.

Two-stage verification model (see Verifier.sol for the canonical narrative):

  STAGE A — STARK math.
      path-a-runner registers the fact with the StarkWare contracts:
        Phase 1: MerkleStatementContract.verify()
        Phase 2: FriStatementContract.verify()
        Phase 3: MemoryPageFactRegistry.registerContinuousMemoryPage()
        Phase 4: GpsStatementVerifier.verifyProofAndRegister()
      ⇒ GpsStatementVerifier.isValid(factHash) returns true.

  STAGE B — APPLICATION BOOKKEEPING (this script).
      Calls Verifier.registerSafeProof(SafeProofInputs inputs) on the convoy
      Verifier contract. NO proof bytes, NO FRI params, NO task metadata,
      NO cairoAuxInput are passed — Stage A already consumed all of those
      and recorded the result in the StarkWare FactRegistry.
      The convoy Verifier:
        - checks msg.sender is the whitelisted relay,
        - asserts the strip bounds in the inputs match the spec,
        - asserts starkVerifier.isValid(factHash) == true
          (i.e. Stage A actually happened for this exact program/output),
        - writes the verdict to Registry and aggregates if this is the
          nDrones-th SAFE drone.

Per-drone calldata size dropped from ~800 KB (Stage A's proof payload was
sent twice — once via path-a-runner, once via this script) to ~250 bytes.
That's the architectural win: STARK math happens once, in the place
designed for it; application bookkeeping happens once, in the place
designed for it.

Public-output schema (must match safe_area_verify.cairo's serialize_word
calls in this exact order — Verifier.sol assumes it byte-for-byte):

   [ mission_id, drone_id, x_start, x_end, y_start, y_end,
     verdict_bool, H ]

   - mission_id ∈ {1 (Alpha), 2 (Bravo)}                — Registry convention
   - drone_id   ∈ [1, spec.nDrones]                      — drone index within swarm
   - (x_start, x_end, y_start, y_end)                    — strip bounds (zone units)
   - verdict_bool ∈ {0, 1}                               — 1 ⇒ SAFE
   - H — Pedersen-chain commitment over the drone's cells + nonce
         (hiding ONLY because the nonce is included in the chain, NOT
         because the prover is zero-knowledge: see thesis §3.4 on the
         distinction).

Pipeline this script sits at the end of:

  1. cairo-compile + cairo-run               (cairo-lang)
  2. cpu_air_prover                          (Stone)
  3. cpu_air_verifier                        (Stone off-chain sanity check)
  4. stark_evm_adapter gen-annotated-proof   → /proofs/evm_proof.json
  5. path-a-runner                           → STAGE A (4 phases) against
                                               the real StarkWare stack
                                               on our local Geth. Leaves
                                               factHash → true in the
                                               GpsStatementVerifier's
                                               FactRegistry.
  6. *this script*                           → STAGE B. Single tiny
                                               tx to Verifier.registerSafeProof
                                               on the convoy Verifier.

Relay-key selection:
  Verifier.sol whitelists ONE relay per mission_id via `relayOf[missionId]`:
       missionId == 1 (Alpha) → ALPHA_RELAY_PK (ship F)
       missionId == 2 (Bravo) → BRAVO_RELAY_PK (ship B)
  Picking the wrong key reverts at the `onlyRelay` modifier on-chain.

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

# Mission-id convention — mirrors Registry.sol's ALPHA_MISSION_ID / BRAVO_MISSION_ID.
ALPHA_MISSION_ID = 1
BRAVO_MISSION_ID = 2

# Number of felt252 outputs the Cairo program emits via serialize_word.
N_PUBLIC_OUTPUTS = 8


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
    Pull the 8 felt252 public outputs serialized by safe_area_verify.cairo.

    Order (must match the Cairo program's serialize_word calls):
       [mission_id, drone_id, x_start, x_end, y_start, y_end, verdict_bool, H]

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
    if len(values) != N_PUBLIC_OUTPUTS:
        raise SystemExit(
            f"[submit] expected {N_PUBLIC_OUTPUTS} public outputs "
            f"(mid, did, x_start, x_end, y_start, y_end, verdict, H), "
            f"got {len(values)}: {values}"
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

    if not program_path.exists() or not public_input_path.exists():
        raise SystemExit("[submit] required artefacts missing — has the prover run?")

    # ── Compute fact hashes ───────────────────────────────────────────
    program_data = json.loads(program_path.read_text()).get("data", [])
    program_bytes = json.dumps(program_data, separators=(",", ":")).encode()
    program_hash = keccak256(program_bytes)

    outputs = extract_public_outputs(public_input_path, evm_proof_path)
    (
        mission_id,
        drone_id,
        x_start,
        x_end,
        y_start,
        y_end,
        verdict_bool,
        commitment,
    ) = outputs

    # outputHash = keccak256 over the 8 output felts, 32 bytes each, big-endian.
    # Must match the encoding the Verifier reconstructs at registerSafeProof().
    output_bytes = b"".join(v.to_bytes(32, "big") for v in outputs)
    output_hash = keccak256(output_bytes)

    fact_data = bytes.fromhex(program_hash[2:]) + bytes.fromhex(output_hash[2:])
    fact_hash = keccak256(fact_data)

    n_steps = json.loads(public_input_path.read_text())["n_steps"]
    proof_size = proof_path.stat().st_size if proof_path.exists() else 0

    print("[submit] ── public outputs from Cairo program ─────────")
    print(f"  mission_id     {mission_id}")
    print(f"  drone_id       {drone_id}")
    print(f"  strip_x_start  {x_start}")
    print(f"  strip_x_end    {x_end}")
    print(f"  strip_y_start  {y_start}")
    print(f"  strip_y_end    {y_end}")
    print(f"  verdict_bool   {verdict_bool}")
    print(f"  commitment     0x{commitment:064x}")
    print()
    print("[submit] ── fact components ───────────────────────────")
    print(f"  programHash  {program_hash}")
    print(f"  outputHash   {output_hash}")
    print(f"  factHash     {fact_hash}")
    print(f"  proofSize    {proof_size} bytes")
    print(f"  nSteps       {n_steps}")

    # ── Pick the relay key for this mission ───────────────────────────
    # Verifier.relayOf[missionId] gates the call. We mirror that mapping
    # client-side so the relay can't accidentally submit for the wrong
    # swarm (which would revert at the modifier and waste gas).
    if mission_id == ALPHA_MISSION_ID:
        pk = alpha_pk
        lane = "alpha (F)"
    elif mission_id == BRAVO_MISSION_ID:
        pk = bravo_pk
        lane = "bravo (B)"
    else:
        raise SystemExit(f"[submit] invalid mission_id from program output: {mission_id}")

    # ── Build the 11-field SafeProofInputs tuple ──────────────────────
    #
    # Verifier.registerSafeProof signature (Verifier.sol Stage B):
    #
    #   registerSafeProof(SafeProofInputs calldata inputs)
    #
    # SafeProofInputs field order (must match Verifier.sol exactly):
    #
    #     (bytes32 programHash,
    #      bytes32 outputHash,
    #      uint256 missionId,
    #      uint8   droneIndex,
    #      uint32  stripXStart,
    #      uint32  stripXEnd,
    #      uint32  stripYStart,
    #      uint32  stripYEnd,
    #      uint8   verdictBool,
    #      bytes32 commitment,
    #      uint256 nSteps)
    #
    # No proof bytes, no FRI params, no task metadata. path-a-runner
    # already pushed those into the StarkWare FactRegistry via Stage A.
    # The convoy Verifier just asserts starkVerifier.isValid(factHash).
    commitment_hex = f"0x{commitment:064x}"
    tuple_args = (
        f"({program_hash},{output_hash},"
        f"{mission_id},{drone_id},"
        f"{x_start},{x_end},{y_start},{y_end},"
        f"{verdict_bool},{commitment_hex},{n_steps})"
    )

    sig = (
        "registerSafeProof("
        "(bytes32,bytes32,uint256,uint8,uint32,uint32,uint32,uint32,uint8,bytes32,uint256))"
    )

    print(f"\n[submit] Stage B: registerSafeProof from {lane} relay key")
    print( "[submit]   (proof bytes NOT sent — Stage A already verified them)")
    tx_hash = cast_send(
        rpc, pk, verifier_addr, sig,
        tuple_args,
        label=f"{lane} fact",
    )

    # Confirm fact registered
    is_valid_raw = cast_call(rpc, verifier_addr, "isValid(bytes32)(bool)", fact_hash)
    is_valid = is_valid_raw.lower().strip() in ("true", "0x1", "1")

    # Best-effort: read the per-mission safeCount so the operator sees
    # aggregation progress directly. The Registry exposes safeCount as
    # a `mapping(uint256 => uint8) public`, so the auto-generated getter
    # is just `safeCount(uint256)`. If REGISTRY_ADDR isn't wired in the
    # env we skip the lookup — purely informational.
    registry_addr = os.environ.get("REGISTRY_ADDR", "")
    safe_count_after: int | None = None
    mission_safe_after: bool | None = None
    if registry_addr:
        sc_raw = cast_call(rpc, registry_addr, "safeCount(uint256)(uint8)", str(mission_id))
        if sc_raw:
            try:
                safe_count_after = int(sc_raw.split()[0], 0)
            except (ValueError, IndexError):
                pass
        ms_raw = cast_call(rpc, registry_addr, "isMissionSafe(uint256)(bool)", str(mission_id))
        mission_safe_after = ms_raw.lower().strip() in ("true", "0x1", "1")

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
            "mission_id":   mission_id,
            "drone_id":     drone_id,
            "strip": {
                "x_start": x_start,
                "x_end":   x_end,
                "y_start": y_start,
                "y_end":   y_end,
            },
            "verdict_bool": verdict_bool,
            "commitment":   commitment_hex,
        },
        "aggregation": {
            "registryAddr":   registry_addr or None,
            "safeCountAfter": safe_count_after,
            "missionSafe":    mission_safe_after,
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
    if safe_count_after is not None:
        print(f"  safeCount: {safe_count_after}")
    if mission_safe_after is not None:
        print(f"  mission_safe: {mission_safe_after}")
    print(f"  log:       {log_path}")
    print("====================================================")
    return 0


if __name__ == "__main__":
    sys.exit(main())

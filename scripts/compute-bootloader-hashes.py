#!/usr/bin/env python3
"""
compute-bootloader-hashes.py — VERIFY the SIMPLE_BOOTLOADER_HASH constant
shipped in scripts/bootloader-hashes.env.

The canonical values are already committed in scripts/bootloader-hashes.env;
they are the on-chain constants used by StarkWare's mainnet GPS verifier
and republished by zksecurity in vendor/stark-evm-adapter/examples/bootloader/
test_bootloader_fib.py with the label `# on-chain hash`.

This script exists for **independent verification**: if you have access to
the compiled simple_bootloader JSON (older cairo-lang versions used to
bundle it under starkware/cairo/bootloaders/simple_bootloader/; newer ones
do not), the script will recompute the Pedersen-chain program hash and
compare against the published constant. A mismatch means the cairo-lang
version in use ships a different bootloader than the one StarkWare
embedded in CairoBootloaderProgram.sol --- in that case the deploy must
target a different on-chain verifier.

For everyday use, just `source scripts/bootloader-hashes.env` before
deploy; no recomputation needed.

Usage (verification only)
-------------------------

Pass the path to a compiled simple_bootloader JSON:

    docker run --rm -v "$PWD:/work" -w /work \\
        --entrypoint python3 convoy-prover-api:latest \\
        scripts/compute-bootloader-hashes.py /path/to/simple_bootloader_compiled.json
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


EXPECTED_PROGRAM_SIZE = 566  # matches CairoBootloaderProgram.sol's PROGRAM_SIZE
PUBLISHED_SIMPLE_BOOTLOADER_HASH = (
    0xd875840ac697dbeedb3d4c8f2a61889bc1d5f1af91e67a7cc7360e8faf35bf
)


def compute_bootloader_hash(json_path: Path) -> tuple[int, int]:
    """
    Run StarkWare's program-hash function on the bootloader JSON.
    Returns (hash, data_length).
    """
    from starkware.cairo.bootloaders.hash_program import compute_program_hash_chain, HashFunction
    from starkware.cairo.lang.compiler.program import Program

    with open(json_path) as f:
        program_data = json.load(f)

    program = Program.load(data=program_data)
    data_length = len(program.data)
    h = compute_program_hash_chain(program, HashFunction.PEDERSEN)
    return h, data_length


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "Usage: compute-bootloader-hashes.py <simple_bootloader_compiled.json>\n\n"
            "For the canonical published value (no verification needed), just\n"
            "source scripts/bootloader-hashes.env. This script is for cross-\n"
            "checking against an independently-compiled bootloader JSON.\n\n"
            f"Published constant:  0x{PUBLISHED_SIMPLE_BOOTLOADER_HASH:x}",
            file=sys.stderr,
        )
        return 2

    json_path = Path(sys.argv[1])
    if not json_path.exists():
        sys.exit(f"[hash] {json_path} not found")

    h, data_length = compute_bootloader_hash(json_path)

    print(f"# Source bootloader JSON: {json_path}")
    print(f"# Bootloader data length: {data_length} felts")
    print(f"# Computed (Pedersen-chain) hash: 0x{h:x}")
    print(f"# Published constant:             0x{PUBLISHED_SIMPLE_BOOTLOADER_HASH:x}")

    size_ok = data_length == EXPECTED_PROGRAM_SIZE
    hash_ok = h == PUBLISHED_SIMPLE_BOOTLOADER_HASH

    if size_ok and hash_ok:
        print("# ✓ Verified: this bootloader matches the published constant.")
        print()
        print(f"export SIMPLE_BOOTLOADER_HASH=0x{h:x}")
        print("export HASHED_CAIRO_VERIFIERS=0x0")
        return 0

    if not size_ok:
        sys.stderr.write(
            f"[hash] FAIL: data length {data_length} != expected {EXPECTED_PROGRAM_SIZE}.\n"
            "       This JSON is NOT the simple bootloader that the on-chain\n"
            "       CairoBootloaderProgram.sol embeds. Find the correct JSON.\n"
        )
    if not hash_ok:
        sys.stderr.write(
            "[hash] FAIL: computed hash does not match published constant.\n"
            "       Either this JSON is a different bootloader version, or\n"
            "       the published constant is wrong. Do not deploy with the\n"
            "       computed value unless the on-chain CairoBootloaderProgram\n"
            "       has been re-vendored from a matching source.\n"
        )
    return 1


if __name__ == "__main__":
    sys.exit(main())

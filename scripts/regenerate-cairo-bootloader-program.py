#!/usr/bin/env python3
"""
regenerate-cairo-bootloader-program.py — patch the vendored
CairoBootloaderProgram.sol in-place so its embedded bytecode and
PROGRAM_SIZE match the v0.13.0 bootloader shipped with
vendor/cairo-bootloader/resources/bootloader-0.13.0.json.

Why this exists
---------------

The vendored starkex-contracts (StarkPerpetual-v3.2 era) embeds an older
"simple bootloader" with 566 felts. Moonsong-Labs' cairo-bootloader,
which we use proving-side, ships a v0.13.0 bootloader with 718 felts.
At proof submission time, GpsStatementVerifier computes the expected
public-memory layout using its own PROGRAM_SIZE constant; if the
proving-side bootloader is a different size, that arithmetic
disagrees and the proof reverts with "Invalid size for memory page 0."
(See the precise revert from infrastructure/path-a-runner, Phase 4.)

This script closes the gap by regenerating the auto-generated
CairoBootloaderProgram.sol with the v0.13.0 bytecode in place. Both
PROGRAM_SIZE (= 718) and the embedded `data` array are updated.

Affected file (modified in the submodule's working tree, NOT in its
tracked index — .gitmodules has ignore = dirty for this submodule):

    contracts/lib/starkex-contracts/evm-verifier/solidity/contracts/
        cpu/CairoBootloaderProgram.sol

After running this script you must also:
    1. Recompute SIMPLE_BOOTLOADER_HASH against bootloader-0.13.0.json
       (use scripts/compute-bootloader-hashes.py) and update
       scripts/bootloader-hashes.env.
    2. Re-run forge build to recompile GpsStatementVerifier with the
       new PROGRAM_SIZE (CairoBootloaderProgramSize is inherited).
    3. Re-deploy: forge script DeployStarkVerifier.s.sol.
    4. Update path-a-runner addresses.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


SRC = Path("vendor/cairo-bootloader/resources/bootloader-0.13.0.json")
DST = Path("contracts/lib/starkex-contracts/evm-verifier/solidity/contracts/cpu/CairoBootloaderProgram.sol")


HEADER = """// ---------- The following code was auto-generated. PLEASE DO NOT EDIT. ----------
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.6.12;

// Regenerated from vendor/cairo-bootloader/resources/bootloader-0.13.0.json
// by scripts/regenerate-cairo-bootloader-program.py. Replaces the older
// 566-felt simple bootloader that ships with starkex-contracts
// (StarkPerpetual-v3.2) with the v0.13.0 bootloader Moonsong-Labs'
// cairo-bootloader uses at proof time. This is the alignment needed for
// GpsStatementVerifier to accept bootloader-wrapped proofs end-to-end.

contract CairoBootloaderProgramSize {
    uint256 internal constant PROGRAM_SIZE = {program_size};
}

contract CairoBootloaderProgram is CairoBootloaderProgramSize {
    function getCompiledProgram()
        external pure
        returns (uint256[PROGRAM_SIZE] memory)
    {
        return [
"""

FOOTER = """        ];
    }
}
"""


def main() -> int:
    if not SRC.exists():
        sys.exit(f"[regen] source bootloader JSON missing: {SRC}")
    if not DST.exists():
        sys.exit(f"[regen] target Solidity file missing: {DST}")

    bootloader = json.loads(SRC.read_text())
    data = bootloader.get("data")
    if not isinstance(data, list):
        sys.exit(f"[regen] {SRC} has no `data` array")

    # Each entry is a 0x-prefixed hex string in the JSON; convert to decimal
    # so the Solidity array literal stays uniform (matches StarkWare's
    # auto-generated style — decimal felts, one per line).
    felts: list[int] = []
    for entry in data:
        if isinstance(entry, str):
            felts.append(int(entry, 0))
        elif isinstance(entry, int):
            felts.append(entry)
        else:
            sys.exit(f"[regen] unsupported data entry type: {type(entry)}")

    program_size = len(felts)
    print(f"[regen] source: {SRC}", file=sys.stderr)
    print(f"[regen] target: {DST}", file=sys.stderr)
    print(f"[regen] PROGRAM_SIZE: {program_size}", file=sys.stderr)

    out: list[str] = []
    out.append(HEADER.replace("{program_size}", str(program_size)))
    for i, felt in enumerate(felts):
        sep = "," if i < program_size - 1 else ""
        out.append(f"            {felt}{sep}\n")
    out.append(FOOTER)
    DST.write_text("".join(out))

    print(f"[regen] wrote {DST} ({DST.stat().st_size} bytes)", file=sys.stderr)
    print(f"[regen] next: update scripts/bootloader-hashes.env with the v0.13.0 hash", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

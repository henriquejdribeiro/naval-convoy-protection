#!/usr/bin/env python3
"""
prove_pie.py — wrap stone-prover-cli to prove an SNOS-emitted PIE.

For Phase 3 with the full Madara → Pathfinder → SNOS pipeline, SNOS emits
a PIE (Program-Independent Executable) representing the L2 block replay.
Stone consumes that PIE to produce the STARK proof.

In the bare prover-api Phase (no SNOS yet), entrypoint.sh runs
cairo-run + cpu_air_prover directly against safe_area_verify.cairo with a
program_input. This script is wired in for the day SNOS lands.

Usage:
    python3 prove_pie.py /input/cairo_pie.zip /proofs/proof.json
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    pie_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])

    if not pie_path.exists():
        print(f"[prove_pie] PIE not found: {pie_path}", file=sys.stderr)
        return 1
    out_path.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        "stone-prover-cli", "prove",
        "--pie", str(pie_path),
        "--output", str(out_path),
    ]
    print(f"[prove_pie] running: {' '.join(cmd)}")
    r = subprocess.run(cmd)
    if r.returncode != 0:
        print(f"[prove_pie] stone-prover-cli failed (exit {r.returncode})", file=sys.stderr)
        return r.returncode
    print(f"[prove_pie] proof written to {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

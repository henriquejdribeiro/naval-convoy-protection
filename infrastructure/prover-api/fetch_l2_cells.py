#!/usr/bin/env python3
"""
fetch_l2_cells.py — pull telemetry cells + commitment for (mid, drone_id)
out of convoy_protocol's storage on Madara, via starkli (which calls
Pathfinder JSON-RPC under the hood).

Builds a Cairo input.json the prover-api can consume so the trace's
witness comes from the L2 chain (not a synthetic file). The on-chain
commitment value is also written into `expected_commitment`, which
safe_area_verify.cairo asserts equals the Poseidon hash chain it
recomputes from the cells. That assertion is the cryptographic bridge
from L2 storage to the L1 Verifier.

Usage:
    python3 fetch_l2_cells.py \\
        --rpc http://convoy-pathfinder:9545/rpc/v0_8 \\
        --contract 0x04f37310...ad09 \\
        --mid 2 --drone-id 2 \\
        --coverage-min 950 --p-min 7000 --time-window 360 \\
        --area-total-cells 50 --ts-start 1700000000 \\
        --output /proofs/l2_input.json

Requires `starkli` on PATH (the prover-api container has it).
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys


def starkli_call(rpc: str, contract: str, method: str, args: list[str]) -> list[int]:
    """Run `starkli call`, return the list of returned felts as ints."""
    cmd = ["starkli", "call", "--rpc", rpc, contract, method, *args]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"[fetch] starkli call {method} failed: {r.stderr.strip()}")
    # starkli prints each returned felt as a 0x... hex on its own line, wrapped in []
    out = r.stdout.strip()
    # Strip JSON-array brackets if present and split on commas/newlines
    out = out.replace("[", "").replace("]", "").replace('"', '')
    felts = [tok.strip() for tok in out.replace(",", "\n").splitlines() if tok.strip()]
    return [int(f, 16) for f in felts]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rpc", required=True,
                    help="Pathfinder RPC URL including /rpc/vX_Y suffix")
    ap.add_argument("--contract", required=True)
    ap.add_argument("--mid", type=int, required=True)
    ap.add_argument("--drone-id", type=int, required=True)
    ap.add_argument("--coverage-min", type=int, required=True)
    ap.add_argument("--p-min", type=int, required=True)
    ap.add_argument("--time-window", type=int, required=True)
    ap.add_argument("--area-total-cells", type=int, required=True)
    ap.add_argument("--ts-start", type=int, required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--allow-no-commitment", action="store_true",
                    help="Don't fail if get_commitment returns 0")
    args = ap.parse_args()

    if not shutil.which("starkli"):
        raise SystemExit("[fetch] starkli not on PATH — install or run from cairo-builder")

    # 1. cell_count(mid, drone_id)
    print(f"[fetch] reading get_cell_count({args.mid}, {args.drone_id}) "
          f"from {args.contract} via {args.rpc}")
    n_cells = starkli_call(
        args.rpc, args.contract, "get_cell_count",
        [str(args.mid), str(args.drone_id)],
    )[0]
    print(f"[fetch]   n_cells = {n_cells}")
    if n_cells == 0:
        raise SystemExit("[fetch] no telemetry on L2 for this (mid, drone_id)")

    # 2. each cell via get_cell(mid, drone_id, i) -> (x, y, p, ts)
    cells_x, cells_y, cells_p, cells_ts = [], [], [], []
    for i in range(n_cells):
        x, y, p, ts = starkli_call(
            args.rpc, args.contract, "get_cell",
            [str(args.mid), str(args.drone_id), str(i)],
        )[:4]
        cells_x.append(x)
        cells_y.append(y)
        cells_p.append(p)
        cells_ts.append(ts)
    print(f"[fetch]   pulled {n_cells} cells from L2 storage")

    # 3. on-chain commitment (felt252)
    commitment = starkli_call(
        args.rpc, args.contract, "get_commitment",
        [str(args.mid), str(args.drone_id)],
    )[0]
    if commitment == 0:
        msg = ("[fetch] convoy_protocol.get_commitment is 0 — the drone hasn't "
               "called submit_sweep_commitment yet.")
        if args.allow_no_commitment:
            print(msg + " Continuing with expected_commitment=0 (no L2 binding).")
        else:
            raise SystemExit(msg + "\n  Pass --allow-no-commitment to skip the L2 binding.")
    print(f"[fetch]   expected_commitment = 0x{commitment:064x}")

    out = {
        "_source":             "L2 (Madara) — fetched via Pathfinder",
        "_contract":           args.contract,
        "_l2_block":           "latest",

        "mid":                 args.mid,
        "drone_id":            args.drone_id,
        "area_total_cells":    args.area_total_cells,
        "coverage_min":        args.coverage_min,
        "p_min":               args.p_min,
        "time_window":         args.time_window,
        "ts_start":            args.ts_start,
        "n_cells":             n_cells,
        "expected_commitment": commitment,

        "cells_x":             cells_x,
        "cells_y":             cells_y,
        "cells_p_contact":     cells_p,
        "cells_ts":            cells_ts,
    }

    with open(args.output, "w") as f:
        json.dump(out, f, indent=2)
    print(f"[fetch] wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

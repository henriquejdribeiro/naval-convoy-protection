#!/usr/bin/env python3
"""
fetch_l2_cells.py — pull a drone's SIGNED telemetry out of convoy_protocol on
Madara (via Pathfinder) and build the program_input.json the prover consumes.

Everything the proof needs is read from L2 — the witness comes from the chain,
not a synthetic file:
  - mission thresholds + geometry     get_mission / get_strip
  - the per-cell telemetry            get_n_cells / get_cell
  - the Route-B identity binding       get_nonce / get_pubkey / get_signature

The drone signed H = Pedersen(cells, nonce) at submit time; safe_area_verify
re-derives H from these cells+nonce and verifies (sig_r,sig_s) under
drone_pubkey in-proof, binding the L1 verdict to the drone's identity.

Usage:
    python3 fetch_l2_cells.py \\
        --rpc http://convoy-pathfinder-bravo-1:9545/rpc/v0_8 \\
        --contract 0x... --mission_id 2 --drone-id 3 \\
        --output /proofs/l2_input.json
"""
from __future__ import annotations
import argparse, json, shutil, subprocess, sys


def starkli_call(rpc, contract, method, args):
    cmd = ["starkli", "call", "--rpc", rpc, contract, method, *args]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"[fetch] starkli call {method} failed: {r.stderr.strip()}")
    out = r.stdout.strip().replace("[", "").replace("]", "").replace('"', '')
    felts = [t.strip() for t in out.replace(",", "\n").splitlines() if t.strip()]
    return [int(f, 16) for f in felts]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rpc", required=True, help="Pathfinder RPC incl /rpc/vX_Y")
    ap.add_argument("--contract", required=True)
    ap.add_argument("--mission_id", type=int, required=True)
    ap.add_argument("--drone-id", type=int, required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    if not shutil.which("starkli"):
        raise SystemExit("[fetch] starkli not on PATH")

    mid, did, C, RPC = args.mission_id, args.drone_id, args.contract, args.rpc

    # 1. Mission spec — field order mirrors MissionSpec in lib.cairo:
    #    [0]mission_id [1]swarm_id [2]zone_x [3]zone_y [4]zone_w [5]zone_h
    #    [6]n_drones [7]strip_width [8]coverage_min [9]p_min [10]time_window [11]ts_start
    spec = starkli_call(RPC, C, "get_mission", [str(mid)])
    coverage_min, p_min, time_window, ts_start = spec[8], spec[9], spec[10], spec[11]

    # 2. This drone's assigned strip (derived in-contract).
    x_start, x_end, y_start, y_end = starkli_call(
        RPC, C, "get_strip", [str(mid), str(did)])[:4]
    strip_total_cells = (x_end - x_start) * (y_end - y_start)

    # 3. Telemetry cells.
    n_cells = starkli_call(RPC, C, "get_n_cells", [str(mid), str(did)])[0]
    if n_cells == 0:
        raise SystemExit(f"[fetch] no telemetry on L2 for mission {mid}, drone {did}")
    cells_x, cells_y, cells_p, cells_ts = [], [], [], []
    for i in range(n_cells):
        x, y, p, ts = starkli_call(RPC, C, "get_cell", [str(mid), str(did), str(i)])[:4]
        cells_x.append(x); cells_y.append(y); cells_p.append(p); cells_ts.append(ts)
    print(f"[fetch] pulled {n_cells} cells for mission {mid}, drone {did}")

    # 4. Route-B identity binding: nonce + pubkey + signature.
    cells_nonce  = starkli_call(RPC, C, "get_nonce",     [str(mid), str(did)])[0]
    drone_pubkey = starkli_call(RPC, C, "get_pubkey",    [str(mid), str(did)])[0]
    sig_r, sig_s = starkli_call(RPC, C, "get_signature", [str(mid), str(did)])[:2]
    if drone_pubkey == 0 or (sig_r == 0 and sig_s == 0):
        raise SystemExit("[fetch] no signature on L2 — did the drone submit via the "
                         "signed submit-telemetry.sh? (get_pubkey/get_signature are 0)")
    print(f"[fetch] drone_pubkey = 0x{drone_pubkey:064x}")

    out = {
        "_source":   "L2 (Madara) — signed telemetry via Pathfinder",
        "_contract": C,

        "mission_id":        mid,
        "drone_id":          did,
        "strip_x_start":     x_start,
        "strip_x_end":       x_end,
        "strip_y_start":     y_start,
        "strip_y_end":       y_end,
        "strip_total_cells": strip_total_cells,
        "coverage_min":      coverage_min,
        "p_min":             p_min,
        "time_window":       time_window,
        "ts_start":          ts_start,
        "n_cells":           n_cells,

        "cells_x":           cells_x,
        "cells_y":           cells_y,
        "cells_p_contact":   cells_p,
        "cells_ts":          cells_ts,

        "cells_nonce":       cells_nonce,
        "drone_pubkey":      drone_pubkey,
        "sig_r":             sig_r,
        "sig_s":             sig_s,
    }
    with open(args.output, "w") as f:
        json.dump(out, f, indent=2)
    print(f"[fetch] wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
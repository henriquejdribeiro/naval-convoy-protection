#!/usr/bin/env python3
"""
fetch_l2_swarm.py — pull a WHOLE SWARM's signed telemetry (all 5 drones) out of
convoy_protocol on Madara and build the nested program_input.json that
safe_area_verify_{alpha,bravo}.cairo consumes.

The per-drone rev (fetch_l2_cells.py) built one drone's input; the swarm proof
aggregates all 5, so this loops drones 1..N and nests them under "drones".

Everything is read from L2 — the witness comes from the chain:
  - mission thresholds + geometry     get_mission        (once)
  - each drone's per-cell telemetry    get_n_cells / get_cell
  - each drone's Route-B binding        get_nonce / get_pubkey / get_signature

Usage (run inside the prover image — it has starkli):
    python3 fetch_l2_swarm.py \\
        --rpc http://convoy-madara-alpha:9944/rpc/v0.8.1 \\
        --contract 0x... --mission_id 1 --output /proofs/program_input.json
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


def fetch_drone(rpc, contract, mid, did):
    """One drone's telemetry + identity binding as the nested dict the Cairo reads."""
    n_cells = starkli_call(rpc, contract, "get_n_cells", [str(mid), str(did)])[0]
    if n_cells == 0:
        raise SystemExit(f"[fetch] no telemetry on L2 for mission {mid}, drone {did} "
                         f"— did all 5 drones run script6_submit-telemetry.sh?")
    cx, cy, cp, cts = [], [], [], []
    for i in range(n_cells):
        x, y, p, ts = starkli_call(rpc, contract, "get_cell", [str(mid), str(did), str(i)])[:4]
        cx.append(x); cy.append(y); cp.append(p); cts.append(ts)

    nonce  = starkli_call(rpc, contract, "get_nonce",     [str(mid), str(did)])[0]
    pubkey = starkli_call(rpc, contract, "get_pubkey",    [str(mid), str(did)])[0]
    sig_r, sig_s = starkli_call(rpc, contract, "get_signature", [str(mid), str(did)])[:2]
    if pubkey == 0 or (sig_r == 0 and sig_s == 0):
        raise SystemExit(f"[fetch] drone {did}: no signature on L2 — submit via the "
                         f"signed script6_submit-telemetry.sh (get_pubkey/get_signature are 0)")
    print(f"[fetch]  drone {did}: {n_cells} cells, pubkey=0x{pubkey:064x}")
    return dict(n_cells=n_cells, cells_x=cx, cells_y=cy, cells_p_contact=cp, cells_ts=cts,
                cells_nonce=nonce, drone_pubkey=pubkey, sig_r=sig_r, sig_s=sig_s)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rpc", required=True, help="Madara/Pathfinder RPC incl /rpc/vX_Y")
    ap.add_argument("--contract", required=True)
    ap.add_argument("--mission_id", type=int, required=True)
    ap.add_argument("--n-drones", type=int, default=5)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    if not shutil.which("starkli"):
        raise SystemExit("[fetch] starkli not on PATH")

    mid, C, RPC = args.mission_id, args.contract, args.rpc

    # Mission spec — field order mirrors MissionSpec in lib.cairo (14 felts now):
    #  [0]mission_id [1]swarm_id [2]zone_x [3]zone_y [4]zone_w [5]zone_h [6]n_drones
    #  [7]strip_width [8]coverage_min [9]p_min [10]time_window [11]ts_start
    #  [12]block_size [13]sensor_half
    # The swarm program bakes zone_w/zone_h/strip_width/block_size/sensor_half as
    # constants, so it only needs the LOCATION (zone_x/zone_y) + thresholds here.
    spec = starkli_call(RPC, C, "get_mission", [str(mid)])
    zone_x, zone_y = spec[2], spec[3]
    coverage_min, p_min, time_window, ts_start = spec[8], spec[9], spec[10], spec[11]
    print(f"[fetch] mission {mid}: zone_x={zone_x} zone_y={zone_y} "
          f"coverage_min={coverage_min} p_min={p_min} window={time_window} ts_start={ts_start}")

    drones = [fetch_drone(RPC, C, mid, did) for did in range(1, args.n_drones + 1)]

    out = {
        "_source":     "L2 (Madara) — signed swarm telemetry via starkli",
        "_contract":   C,
        "mission_id":   mid,
        "zone_x":       zone_x,
        "zone_y":       zone_y,
        "coverage_min": coverage_min,
        "p_min":        p_min,
        "time_window":  time_window,
        "ts_start":     ts_start,
        "drones":       drones,
    }
    with open(args.output, "w") as f:
        json.dump(out, f, indent=2)
    print(f"[fetch] wrote {args.output} ({args.n_drones} drones)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

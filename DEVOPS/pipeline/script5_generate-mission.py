#!/usr/bin/env python3
"""
generate-mission.py — canonical mission generator for the convoy
proof-of-concept (5-drone-per-swarm, per-swarm coverage-proof rev).

Writes one cells.json per drone (10 total: alpha1..5 + bravo1..5) in the schema
`SIMULATOR/demo/scripts/script6_submit-telemetry.sh` consumes:

    {
      "_comment":         <human-readable label>,
      "home":             {"lon_e7": u32, "lat_e7": u32},   # convoy berth (start)
      "path":             [ {lon_e7,lat_e7,ts,phase}, ... ],# FULL flight track
      "returned":         bool,                             # flew back to the fleet?
      "cells_x":          [u32, ...],       # E7 |lon|·1e7 — reading CENTRES
      "cells_y":          [u32, ...],       # E7  lat·1e7  — reading CENTRES
      "cells_p_contact":  [u16, ...],       # basis points
      "cells_ts":         [u64, ...]        # unix seconds
    }

REALISTIC FULL PATH vs PROOF READINGS
-------------------------------------
`cells_*` are the ONLY thing the STARK proof consumes — the coverage circuit runs
a strip-bounds check on every reading (each must lie inside the drone's strip) and
counts coverage. So transit points (which sit OUTSIDE the strip, down at the
convoy) can NOT go into `cells_*` or the proof would reject them.

Instead every drone also logs its full realistic flight track in `path`:

    home (convoy berth) → transit out → sweep the strip → transit back → home

`path` phases: "transit" (out/back legs, outside the zone) and "sweep" (the in-zone
readings, identical to cells_*). The webapp demo replays this; the proof ignores it.
A drone that drops out mid-flight (`returned=false`) has no transit-back leg. A
"vanish" drone writes no file at all.

E7 + SENSOR FOOTPRINT MODEL
---------------------------
Each cell is a SENSOR READING whose CENTRE is (cells_x, cells_y) and which clears a
square footprint of side 2·sensor_half. Readings tile the drone's strip:

  - alpha (green 37–38°N, 15–16°W): sensor_half = 0.05° → 0.1° footprint = 1 block.
    2×10 = 20 readings (20 blocks).
  - bravo (purple 37–38°N, 13–15°W): sensor_half = 0.1° → 0.2° footprint = 2×2 = 4
    blocks. 2×5 = 10 readings (40 blocks).

Readings are emitted in a SERPENTINE order (up column 0, down column 1) so the
replayed flight is smooth — the proof is order-independent (bounds + coverage count
+ monotonic timestamps), so serpentine is as valid as raster.

Coverage = n_cells · footprint_blocks, checked against strip_total_blocks
(alpha 20, bravo 40) — so a full sweep is 20 alpha readings / 10 bravo readings.

Scenarios (mirror the L1 Registry's dual-flank outcomes):

  --scenario both-safe    -> every drone SAFE  -> both swarm proofs verdict=1
                                                  -> principal certified -> ADVANCE
  --scenario both-unsafe  -> alpha[3]=low-coverage, bravo[3]=high-contact -> HOLD
  --scenario mixed        -> alpha all SAFE, bravo[4]=high-contact -> HOLD
  --scenario alpha-dropout-vanish     -> alpha[3] writes NO file -> HOLD
  --scenario alpha-dropout-midflight  -> alpha[3] ~40% swept, verdict=0 -> HOLD
  --scenario dual-dropout             -> alpha[3] vanish + bravo[4] midflight -> HOLD

Usage:
  python3 SIMULATOR/demo/scripts/script5_generate-mission.py --scenario both-safe --output-dir SIMULATOR/demo/scenarios/

Output layout (one subdirectory per scenario):
  <output-dir>/<scenario>/alpha_1.json .. alpha_5.json
  <output-dir>/<scenario>/bravo_1.json .. bravo_5.json
  <output-dir>/<scenario>/vanish_manifest.json
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path
from dataclasses import dataclass


# ---------------------------------------------------------------------------
# Mission constants — MUST match L1 Registry.MissionSpec + L2 ConvoyProtocol
# MissionSpec + script4_register-missions.sh.
# ---------------------------------------------------------------------------
COVERAGE_MIN = 950        # permille; ≥ 95% strip coverage (bravo needs full 10/10)
P_MIN        = 7000       # basis points; per-cell p_contact < 70%
TIME_WINDOW  = 360        # seconds
TS_START     = 1700000000

TRANSIT_STEPS = 6         # interpolated points per transit leg (home↔strip)


# ---------------------------------------------------------------------------
# Drone home berths in the convoy formation — MUST mirror SIMULATOR/webapp/js/
# world3d.js so the webapp demo replays the same track:
#   cLon=-15.0, cLat=36.01, SX=0.025, SY=0.03;  P(col,row)=(cLon+col*SX, cLat+row*SY)
#   Alpha wing (left):  a1..a5 = P(-6,2),P(-5,2),P(-6,1),P(-5,1),P(-6,0)
#   Bravo wing (right): b1..b5 = P( 6,2),P( 5,2),P( 6,1),P( 5,1),P( 6,0)
# ---------------------------------------------------------------------------
C_LON, C_LAT, SX_, SY_ = -15.0, 36.01, 0.025, 0.03
_HOME_COLROW = {
    "alpha": [(-6, 2), (-5, 2), (-6, 1), (-5, 1), (-6, 0)],
    "bravo": [(6, 2), (5, 2), (6, 1), (5, 1), (6, 0)],
}


def home_e7(prefix: str, drone_id: int) -> tuple[int, int]:
    """Convoy berth of a drone as (lon_e7 = |lon|·1e7, lat_e7 = lat·1e7)."""
    col, row = _HOME_COLROW[prefix][drone_id - 1]
    lon = C_LON + col * SX_
    lat = C_LAT + row * SY_
    return (round(abs(lon) * 1e7), round(lat * 1e7))


# ---------------------------------------------------------------------------
# Swarm specs (E7). block = 0.1° = 1_000_000. sensor_half is the footprint
# half-edge (alpha 0.05°, bravo 0.1°). These MUST match the baked constants in
# safe_area_verify_{alpha,bravo}.cairo and the values script4 registers.
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class SwarmSpec:
    mission_id:  int
    n_drones:    int
    zone_x:      int     # E7 |lon|·1e7 (SW/eastern edge): alpha 15°W, bravo 13°W
    zone_y:      int     # E7  lat·1e7 : 37°N
    zone_w:      int     # E7 width : alpha 1°, bravo 2°
    zone_h:      int     # E7 height: 1°
    strip_width: int     # E7 = zone_w / n_drones
    block:       int     # E7 per 0.1° coverage block
    sensor_half: int     # E7 footprint half-edge


ALPHA = SwarmSpec(mission_id=1, n_drones=5,
                  zone_x=150_000_000, zone_y=370_000_000,
                  zone_w=10_000_000,  zone_h=10_000_000,
                  strip_width=2_000_000, block=1_000_000, sensor_half=500_000)

BRAVO = SwarmSpec(mission_id=2, n_drones=5,
                  zone_x=130_000_000, zone_y=370_000_000,
                  zone_w=20_000_000,  zone_h=10_000_000,
                  strip_width=4_000_000, block=1_000_000, sensor_half=1_000_000)

BY_PREFIX = {"alpha": ALPHA, "bravo": BRAVO}


def strip_bounds(swarm: SwarmSpec, drone_id: int) -> tuple[int, int, int, int]:
    """(x_start, x_end, y_start, y_end) for drone_id ∈ [1, n_drones] (E7)."""
    i = drone_id - 1
    x_start = swarm.zone_x + i * swarm.strip_width
    x_end   = x_start + swarm.strip_width
    y_start = swarm.zone_y
    y_end   = swarm.zone_y + swarm.zone_h
    return x_start, x_end, y_start, y_end


def footprint_blocks(swarm: SwarmSpec) -> int:
    """Blocks cleared per reading = (2·sensor_half / block)²  (alpha 1, bravo 4)."""
    edge = (2 * swarm.sensor_half) // swarm.block
    return edge * edge


def strip_total_blocks(swarm: SwarmSpec) -> int:
    """Blocks in one drone's strip = (strip_width/block)·(zone_h/block) (20 / 40)."""
    return (swarm.strip_width // swarm.block) * (swarm.zone_h // swarm.block)


# ---------------------------------------------------------------------------
# Footprint-centre lattice — the reading CENTRES that tile a strip with no
# gap/overlap. Centres are spaced one footprint apart (step = 2·sensor_half) and
# offset by sensor_half so each footprint sits flush inside the strip. Emitted in
# a SERPENTINE order (column 0 south→north, column 1 north→south) so the replayed
# flight is smooth.
#   alpha: step 0.1° → 2×10 = 20 centres at cell centres (…5e5)
#   bravo: step 0.2° → 2×5  = 10 centres at grid vertices (…e6)
# ---------------------------------------------------------------------------
def footprint_centres(swarm, x_start, x_end, y_start, y_end):
    step = 2 * swarm.sensor_half
    half = swarm.sensor_half
    nx = (x_end - x_start) // step
    ny = (y_end - y_start) // step
    out = []
    for ix in range(nx):
        cx = x_start + half + ix * step
        rows = range(ny) if ix % 2 == 0 else range(ny - 1, -1, -1)   # serpentine
        for iy in rows:
            cy = y_start + half + iy * step
            out.append((cx, cy))
    return out


def _emit(centres, rng, threat_idx=None):
    """Turn a list of (x, y) centres into the four parallel cell arrays."""
    cx, cy, cp, cts = [], [], [], []
    for i, (x, y) in enumerate(centres):
        cx.append(x)
        cy.append(y)
        cp.append(8500 if (threat_idx is not None and i == threat_idx)
                  else rng.randint(1000, 6500))     # 8500 > P_MIN=7000 → detection fail
        cts.append(TS_START + 10 + i * 7)            # ≤ TIME_WINDOW for ≤ ~50 readings
    return cx, cy, cp, cts


# ---------------------------------------------------------------------------
# Full realistic flight track: home → transit out → sweep → transit back → home.
# Only "sweep" points are proof readings (== cells_*); "transit" points are the
# out/back legs outside the zone. A drone that dropped out mid-flight never
# returns (no back leg).
# ---------------------------------------------------------------------------
def _lerp_e7(a, b, t):
    return (round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t))


def build_path(home, sweep_centres, cells_ts, returned, n=TRANSIT_STEPS):
    if not sweep_centres:
        return []
    path = []
    entry, exit_ = sweep_centres[0], sweep_centres[-1]
    t_first, t_last = cells_ts[0], cells_ts[-1]

    # transit OUT: home → strip entry (ts ramps from TS_START up to the 1st reading)
    for j in range(n):
        t = j / n
        x, y = _lerp_e7(home, entry, t)
        path.append({"lon_e7": x, "lat_e7": y,
                     "ts": TS_START + round((t_first - TS_START) * t), "phase": "transit"})

    # SWEEP: the in-zone readings (identical to cells_*, same timestamps)
    for (x, y), ts in zip(sweep_centres, cells_ts):
        path.append({"lon_e7": x, "lat_e7": y, "ts": ts, "phase": "sweep"})

    # transit BACK: strip exit → home (only if the drone made it back)
    if returned:
        for j in range(1, n + 1):
            t = j / n
            x, y = _lerp_e7(exit_, home, t)
            path.append({"lon_e7": x, "lat_e7": y, "ts": t_last + j * 7, "phase": "transit"})
    return path


# ---------------------------------------------------------------------------
# Cell generators — each takes the FULL footprint-centre lattice and produces
# a variant. (safe = all; low-coverage = half; contact = all + one threat;
# dropout = first ~40%.)
# ---------------------------------------------------------------------------
def make_safe_cells(rng, centres):
    return _emit(centres, rng)


def make_unsafe_cells_low_coverage(rng, centres):
    return _emit(centres[: len(centres) // 2], rng)


def make_unsafe_cells_high_contact(rng, centres):
    return _emit(centres, rng, threat_idx=len(centres) // 2)


def make_dropout_midflight_cells(rng, centres):
    cutoff = max(1, (len(centres) * 4) // 10)
    return _emit(centres[:cutoff], rng)


# Sentinel: a "vanish" drone produces NO input JSON at all.
KIND_VANISH = "vanish"

_KIND_TO_GENERATOR = {
    "safe":              (make_safe_cells,                "full strip, all predicates pass"),
    "unsafe-coverage":   (make_unsafe_cells_low_coverage, "only first half of strip swept"),
    "unsafe-contact":    (make_unsafe_cells_high_contact, "full strip but one reading p_contact=8500"),
    "dropout-midflight": (make_dropout_midflight_cells,   "drone disappeared after sweeping ~40% of strip"),
}

# Did the drone fly back to the convoy? A mid-flight dropout vanished en route.
_KIND_RETURNS = {
    "safe":              True,
    "unsafe-coverage":   True,
    "unsafe-contact":    True,
    "dropout-midflight": False,
}


# ---------------------------------------------------------------------------
# JSON assembly — the per-drone telemetry: full path + the proof readings.
# ---------------------------------------------------------------------------
def make_input_json(cells_x, cells_y, cells_p, cells_ts, label, home, path, returned):
    return {
        "_comment":        label,
        "home":            {"lon_e7": home[0], "lat_e7": home[1]},
        "path":            path,
        "returned":        returned,
        "cells_x":         cells_x,
        "cells_y":         cells_y,
        "cells_p_contact": cells_p,
        "cells_ts":        cells_ts,
    }


# ---------------------------------------------------------------------------
# Scenarios — which drones in each swarm get which kind (default "safe").
# ---------------------------------------------------------------------------
SCENARIOS = {
    "both-safe": {
        "summary":     "all 10 drones SAFE -> both swarm proofs verdict=1 -> principal certified -> ADVANCE",
        "alpha_kinds": ["safe"] * 5,
        "bravo_kinds": ["safe"] * 5,
    },
    "both-unsafe": {
        "summary":     "alpha[3]=unsafe-coverage, bravo[3]=unsafe-contact -> both swarms fail -> HOLD",
        "alpha_kinds": ["safe", "safe", "unsafe-coverage", "safe", "safe"],
        "bravo_kinds": ["safe", "safe", "unsafe-contact",  "safe", "safe"],
    },
    "mixed": {
        "summary":     "alpha all SAFE, bravo[4]=unsafe-contact -> single-flank fail -> HOLD",
        "alpha_kinds": ["safe"] * 5,
        "bravo_kinds": ["safe", "safe", "safe", "unsafe-contact", "safe"],
    },
    "alpha-dropout-vanish": {
        "summary":     "alpha[3] VANISHES (no input file, no proof) -> alpha swarm never proves -> HOLD",
        "alpha_kinds": ["safe", "safe", KIND_VANISH, "safe", "safe"],
        "bravo_kinds": ["safe"] * 5,
    },
    "alpha-dropout-midflight": {
        "summary":     "alpha[3] disappears mid-sortie (~40% swept) -> swarm verdict=0 -> HOLD",
        "alpha_kinds": ["safe", "safe", "dropout-midflight", "safe", "safe"],
        "bravo_kinds": ["safe"] * 5,
    },
    "dual-dropout": {
        "summary":     "alpha[3] vanishes, bravo[4] midflight-dropout -> neither swarm completes -> HOLD",
        "alpha_kinds": ["safe", "safe", KIND_VANISH,         "safe", "safe"],
        "bravo_kinds": ["safe", "safe", "safe", "dropout-midflight", "safe"],
    },
}


# ---------------------------------------------------------------------------
# Generator entry
# ---------------------------------------------------------------------------
def generate(scenario, seed):
    sc = SCENARIOS[scenario]
    results = []
    vanished = []

    for swarm, kinds, prefix in (
        (ALPHA, sc["alpha_kinds"], "alpha"),
        (BRAVO, sc["bravo_kinds"], "bravo"),
    ):
        for idx, kind in enumerate(kinds):
            drone_id = idx + 1
            x_start, x_end, y_start, y_end = strip_bounds(swarm, drone_id)

            if kind == KIND_VANISH:
                vanished.append({
                    "swarm":         prefix,
                    "mission_id":    swarm.mission_id,
                    "drone_id":      drone_id,
                    "strip_x_start": x_start,
                    "strip_x_end":   x_end,
                    "strip_y_start": y_start,
                    "strip_y_end":   y_end,
                    "reason":        "vanished (no telemetry recovered)",
                })
                continue

            rng = random.Random(seed + 1000 * swarm.mission_id + drone_id)
            centres = footprint_centres(swarm, x_start, x_end, y_start, y_end)
            gen, _label = _KIND_TO_GENERATOR[kind]
            cells = gen(rng, centres)
            used_centres = list(zip(cells[0], cells[1]))     # the readings actually emitted
            home = home_e7(prefix, drone_id)
            returned = _KIND_RETURNS[kind]
            path = build_path(home, used_centres, cells[3], returned)
            label = (
                f"{prefix} drone {drone_id} ({kind}): "
                f"strip x=[{x_start},{x_end}) y=[{y_start},{y_end}), "
                f"n_cells={len(cells[0])}"
            )
            results.append((f"{prefix}_{drone_id}.json",
                            make_input_json(*cells, label, home, path, returned)))

    return results, vanished


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--scenario", choices=sorted(SCENARIOS.keys()), required=True,
                    help="which dual-flank outcome to generate")
    ap.add_argument("--output-dir", type=Path, default=Path("SIMULATOR/demo/scenarios"),
                    help="directory to write the per-drone input JSONs")
    ap.add_argument("--seed", type=int, default=42,
                    help="base RNG seed for deterministic generation (default: 42)")
    args = ap.parse_args()

    scenario_dir = args.output_dir / args.scenario
    scenario_dir.mkdir(parents=True, exist_ok=True)
    files, vanished = generate(args.scenario, args.seed)

    print(f"[generate-mission] scenario={args.scenario}, seed={args.seed}")
    print(f"[generate-mission] {SCENARIOS[args.scenario]['summary']}")
    for fname, payload in files:
        path = scenario_dir / fname
        path.write_text(json.dumps(payload, indent=2))
        swarm = BY_PREFIX[fname.split("_", 1)[0]]
        n_cells = len(payload["cells_x"])
        covered = n_cells * footprint_blocks(swarm)
        cov_per = covered * 1000 // strip_total_blocks(swarm)
        elapsed = payload["cells_ts"][-1] - TS_START if payload["cells_ts"] else 0
        max_p   = max(payload["cells_p_contact"]) if payload["cells_p_contact"] else 0
        print(f"  {path}: n_cells={n_cells} covered={covered}/{strip_total_blocks(swarm)} "
              f"blocks cov={cov_per}/1000 max_p={max_p} elapsed={elapsed}s "
              f"path_pts={len(payload['path'])} returned={payload['returned']}")

    manifest_path = scenario_dir / "vanish_manifest.json"
    manifest_path.write_text(json.dumps({
        "scenario": args.scenario,
        "summary":  SCENARIOS[args.scenario]["summary"],
        "vanished": vanished,
    }, indent=2))
    if vanished:
        print()
        print(f"[generate-mission] VANISH MANIFEST ({len(vanished)} drone(s)):")
        for v in vanished:
            print(f"  {v['swarm']}{v['drone_id']} — sector "
                  f"x=[{v['strip_x_start']},{v['strip_x_end']}) "
                  f"y=[{v['strip_y_start']},{v['strip_y_end']}) BLIND")
        print(f"  -> manifest written to {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

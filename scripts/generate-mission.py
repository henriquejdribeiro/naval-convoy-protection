#!/usr/bin/env python3
"""
generate-mission.py — canonical mission generator for the convoy
proof-of-concept (5-drone-per-swarm rev, 2026-05).

Writes one input JSON per drone (10 total: alpha1..5 + bravo1..5),
each carrying the public inputs for `safe_area_verify.cairo`:

    {mission_id, drone_id,
     strip_x_start, strip_x_end, strip_y_start, strip_y_end,
     strip_total_cells, coverage_min, p_min, time_window,
     ts_start, n_cells,
     cells_x[], cells_y[], cells_p_contact[], cells_ts[]}

The Cairo program reads these via program_input and writes
(mid, did, strip..., verdict_bool, H) to [output_ptr]. The L2
ConvoyProtocol verifies the proof against those same eight
public-input felts.

Scenarios (mirror the L1 Registry's dual-flank outcomes):

  --scenario both-safe    -> every drone SAFE  -> swarm mission_safe = true
                                                  -> L2 emits message to L1
                                                  -> CommandLog.advance fires

  --scenario both-unsafe  -> alpha drone 3 = low-coverage,
                              bravo drone 3 = high-contact
                              -> safe_count < n_drones for both swarms
                              -> no L1 message -> convoy holds

  --scenario mixed        -> alpha all SAFE,
                              bravo drone 4 = high-contact
                              -> only alpha completes -> convoy still holds

  --scenario alpha-dropout-vanish
                          -> alpha drone 3 LITERALLY DISAPPEARS - no input
                              JSON is written at all, no proof is generated
                              -> safeCount[alpha] reaches at most 4
                              -> alpha missionSafe stays false -> convoy HOLDS

  --scenario alpha-dropout-midflight
                          -> alpha drone 3 takes off, sweeps the first half
                              of its strip, then vanishes - a partial-coverage
                              proof CAN be submitted (verdict_bool = 0)
                              -> the proof lands but doesn't bump safeCount
                              -> alpha missionSafe stays false -> convoy HOLDS

  --scenario dual-dropout -> alpha drone 3 vanishes entirely,
                              bravo drone 4 disappears mid-flight
                              -> neither mission completes -> convoy HOLDS

The dropout scenarios are the operational stress test: they verify the
chain of failure handling - L1 leaves missionSafe false, CommandLog.advance
reverts with "CommandLog: dual-mission not SAFE", and the relay ships
never receive an advance event over radio.

Usage:
  python3 scripts/generate-mission.py --scenario both-safe              --output-dir /tmp/sweeps/
  python3 scripts/generate-mission.py --scenario both-unsafe            --output-dir /tmp/sweeps/
  python3 scripts/generate-mission.py --scenario mixed                  --output-dir /tmp/sweeps/
  python3 scripts/generate-mission.py --scenario alpha-dropout-vanish   --output-dir /tmp/sweeps/
  python3 scripts/generate-mission.py --scenario alpha-dropout-midflight --output-dir /tmp/sweeps/
  python3 scripts/generate-mission.py --scenario dual-dropout           --output-dir /tmp/sweeps/

Output filenames (one per drone that actually existed):
  alpha1_input.json .. alpha5_input.json
  bravo1_input.json .. bravo5_input.json

A vanished drone produces NO file at all - downstream tooling
(entrypoint.sh ALL_* loops, submit_proof_l1.py) is expected to log the
missing input and proceed.
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path
from dataclasses import dataclass


# ---------------------------------------------------------------------------
# Mission constants — MUST match L1 Registry.MissionSpec + the L2
# ConvoyProtocol.MissionSpec.
# ---------------------------------------------------------------------------
COVERAGE_MIN = 950        # permille; ≥ 95% strip coverage
P_MIN        = 7000       # basis points; per-cell p_contact < 70%
TIME_WINDOW  = 360        # seconds
TS_START     = 1700000000


# ---------------------------------------------------------------------------
# Swarm specs — drives strip dimensions per drone.
#   zone is 8 cells tall in both swarms; widths differ (15 / 20) so
#   strip_width is 3 (Alpha) or 4 (Bravo).
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class SwarmSpec:
    mission_id:   int
    n_drones:     int
    zone_x:       int       # absolute origin (Alpha:0..14, Bravo:0..19)
    zone_y:       int
    zone_w:       int
    zone_h:       int
    strip_width:  int       # = zone_w / n_drones (exact)


ALPHA = SwarmSpec(mission_id=1, n_drones=5, zone_x=0, zone_y=0,
                  zone_w=15, zone_h=8, strip_width=3)

BRAVO = SwarmSpec(mission_id=2, n_drones=5, zone_x=0, zone_y=0,
                  zone_w=20, zone_h=8, strip_width=4)


def strip_bounds(swarm: SwarmSpec, drone_id: int) -> tuple[int, int, int, int]:
    """Derive (x_start, x_end, y_start, y_end) for drone_id ∈ [1, n_drones]."""
    i = drone_id - 1
    x_start = swarm.zone_x + i * swarm.strip_width
    x_end   = x_start + swarm.strip_width
    y_start = swarm.zone_y
    y_end   = swarm.zone_y + swarm.zone_h
    return x_start, x_end, y_start, y_end


# ---------------------------------------------------------------------------
# Cell generators — strip-aware. Each takes the strip rectangle and
# returns four parallel arrays of cell field values.
# ---------------------------------------------------------------------------

def _full_strip_coords(x_start: int, x_end: int, y_start: int, y_end: int):
    """Iterate every (x, y) in the rectangle, row-major."""
    for y in range(y_start, y_end):
        for x in range(x_start, x_end):
            yield x, y


def make_safe_cells(rng: random.Random, x_start, x_end, y_start, y_end):
    """
    Full strip coverage. All p_contact ∈ [1000, 6500] (below P_MIN=7000).
    Timestamps spaced ~10s apart; max elapsed ≤ TIME_WINDOW.
    """
    coords = list(_full_strip_coords(x_start, x_end, y_start, y_end))
    cells_x, cells_y, cells_p, cells_ts = [], [], [], []
    for i, (x, y) in enumerate(coords):
        cells_x.append(x)
        cells_y.append(y)
        cells_p.append(rng.randint(1000, 6500))         # safely below P_MIN
        cells_ts.append(TS_START + 10 + i * 7)          # 7s between cells
    return cells_x, cells_y, cells_p, cells_ts


def make_unsafe_cells_low_coverage(rng: random.Random, x_start, x_end, y_start, y_end):
    """
    Drone sweeps only the first half of its strip — coverage fails.
    All other fields well-formed.
    """
    coords = list(_full_strip_coords(x_start, x_end, y_start, y_end))
    half   = len(coords) // 2
    cells_x, cells_y, cells_p, cells_ts = [], [], [], []
    for i, (x, y) in enumerate(coords[:half]):
        cells_x.append(x)
        cells_y.append(y)
        cells_p.append(rng.randint(1000, 6500))
        cells_ts.append(TS_START + 10 + i * 7)
    return cells_x, cells_y, cells_p, cells_ts


def make_unsafe_cells_high_contact(rng: random.Random, x_start, x_end, y_start, y_end):
    """
    Full strip coverage BUT one cell has p_contact = 8500 (> P_MIN).
    The detection predicate fires; verdict_bool = 0.
    """
    coords = list(_full_strip_coords(x_start, x_end, y_start, y_end))
    threat_idx = len(coords) // 2          # mid-strip threat
    cells_x, cells_y, cells_p, cells_ts = [], [], [], []
    for i, (x, y) in enumerate(coords):
        cells_x.append(x)
        cells_y.append(y)
        if i == threat_idx:
            cells_p.append(8500)            # ← above P_MIN=7000
        else:
            cells_p.append(rng.randint(1000, 6500))
        cells_ts.append(TS_START + 10 + i * 7)
    return cells_x, cells_y, cells_p, cells_ts


def make_dropout_midflight_cells(rng: random.Random, x_start, x_end, y_start, y_end):
    """
    Drone takes off, sweeps the first ~40% of its strip, then VANISHES
    (lost radio, sea wave, mechanical failure). Telemetry is preserved
    up to the disappearance point - the drone's relay holds a partial
    cell-list that a Cairo proof can still be generated against.

    The resulting proof is *valid* (verdict_bool = 0 because coverage
    fails the >= 95% gate) and lands on L1, but it does NOT bump
    Registry.safeCount so the mission stays in pending state.

    This is operationally distinct from `unsafe-coverage`: that
    scenario models a drone that finished its sortie but the spec was
    set too aggressively. `dropout-midflight` models a drone that
    physically disappeared, with all the implications for SAR + replay
    that the operations doctrine handles. Same predicate failure
    (coverage), different operational story.

    Timestamps still spaced ~10s apart but stop earlier (matching the
    truncated cell list) so the elapsed-window predicate also reflects
    that the drone never reported again.
    """
    coords = list(_full_strip_coords(x_start, x_end, y_start, y_end))
    # 40% of strip swept before disappearance. floor() so even a small
    # strip yields at least 1 cell of telemetry.
    cutoff = max(1, (len(coords) * 4) // 10)
    cells_x, cells_y, cells_p, cells_ts = [], [], [], []
    for i, (x, y) in enumerate(coords[:cutoff]):
        cells_x.append(x)
        cells_y.append(y)
        cells_p.append(rng.randint(1000, 6500))
        cells_ts.append(TS_START + 10 + i * 7)
    return cells_x, cells_y, cells_p, cells_ts


# Sentinel: a drone slot tagged "vanish" produces NO input JSON. The
# generator returns nothing for that drone - downstream tooling sees
# the file as absent and logs accordingly. This models a complete
# loss-of-comms (or loss-of-drone) where not even partial telemetry
# was recovered.
KIND_VANISH = "vanish"

_KIND_TO_GENERATOR = {
    "safe":               (make_safe_cells,                  "full strip, all predicates pass"),
    "unsafe-coverage":    (make_unsafe_cells_low_coverage,   "only first half of strip swept"),
    "unsafe-contact":     (make_unsafe_cells_high_contact,   "full strip but one cell p_contact=8500"),
    "dropout-midflight":  (make_dropout_midflight_cells,     "drone disappeared mid-flight after sweeping ~40% of strip"),
    # KIND_VANISH is handled specially - no entry here.
}


# ---------------------------------------------------------------------------
# JSON assembly — matches safe_area_verify.cairo's program_input schema.
# ---------------------------------------------------------------------------

def make_input_json(swarm: SwarmSpec, drone_id: int, cells_x, cells_y,
                    cells_p, cells_ts, label: str):
    x_start, x_end, y_start, y_end = strip_bounds(swarm, drone_id)
    strip_total_cells = (x_end - x_start) * (y_end - y_start)
    return {
        "_comment":          label,
        "mission_id":        swarm.mission_id,
        "drone_id":          drone_id,
        "strip_x_start":     x_start,
        "strip_x_end":       x_end,
        "strip_y_start":     y_start,
        "strip_y_end":       y_end,
        "strip_total_cells": strip_total_cells,
        "coverage_min":      COVERAGE_MIN,
        "p_min":             P_MIN,
        "time_window":       TIME_WINDOW,
        "ts_start":          TS_START,
        "n_cells":           len(cells_x),
        "cells_x":           cells_x,
        "cells_y":           cells_y,
        "cells_p_contact":   cells_p,
        "cells_ts":          cells_ts,
    }


# ---------------------------------------------------------------------------
# Scenarios — define which drones in each swarm get which kind.
# Per-drone kind lists; default fallback = "safe".
# ---------------------------------------------------------------------------

SCENARIOS = {
    "both-safe": {
        "summary":     "all 10 drones SAFE -> both swarms complete -> convoy ADVANCES",
        "alpha_kinds": ["safe"] * 5,
        "bravo_kinds": ["safe"] * 5,
    },
    "both-unsafe": {
        "summary":     "alpha[3]=unsafe-coverage, bravo[3]=unsafe-contact -> both swarms fail -> convoy HOLDS",
        "alpha_kinds": ["safe", "safe", "unsafe-coverage", "safe", "safe"],
        "bravo_kinds": ["safe", "safe", "unsafe-contact",  "safe", "safe"],
    },
    "mixed": {
        "summary":     "alpha all SAFE, bravo[4]=unsafe-contact -> single-flank fail -> convoy HOLDS",
        "alpha_kinds": ["safe"] * 5,
        "bravo_kinds": ["safe", "safe", "safe", "unsafe-contact", "safe"],
    },
    # ────────── DROPOUT SCENARIOS — operational stress test ──────────
    # These verify that a missing or partial drone leaves the mission
    # in pending state and CommandLog.advance reverts cleanly.
    "alpha-dropout-vanish": {
        "summary":     "alpha[3] VANISHES (no input file, no proof) -> alpha safeCount caps at 4 -> convoy HOLDS",
        "alpha_kinds": ["safe", "safe", KIND_VANISH,        "safe", "safe"],
        "bravo_kinds": ["safe"] * 5,
    },
    "alpha-dropout-midflight": {
        "summary":     "alpha[3] disappears mid-sortie (~40% strip swept) -> verdict=0 proof lands -> convoy HOLDS",
        "alpha_kinds": ["safe", "safe", "dropout-midflight", "safe", "safe"],
        "bravo_kinds": ["safe"] * 5,
    },
    "dual-dropout": {
        "summary":     "alpha[3] vanishes, bravo[4] midflight-dropout -> neither mission completes -> convoy HOLDS",
        "alpha_kinds": ["safe", "safe", KIND_VANISH,         "safe", "safe"],
        "bravo_kinds": ["safe", "safe", "safe", "dropout-midflight", "safe"],
    },
}


# ---------------------------------------------------------------------------
# Generator entry
# ---------------------------------------------------------------------------

def generate(scenario: str, seed: int) -> tuple[list[tuple[str, dict]], list[dict]]:
    """
    Returns (input_files, vanish_manifest).

    input_files     — (filename, json_dict) pairs, one per drone whose
                      telemetry was recovered. Excludes vanished drones.
    vanish_manifest — one entry per drone tagged KIND_VANISH. Carries
                      mission_id + drone_id + expected strip bounds, so
                      downstream tools can render "WANTED" notices and
                      operators can see exactly which sectors are blind.

    Deterministic for a given seed (each drone seeded from base seed +
    drone-stride so swarms don't share RNG state).
    """
    sc = SCENARIOS[scenario]
    results: list[tuple[str, dict]] = []
    vanished: list[dict] = []

    for swarm, kinds, prefix in (
        (ALPHA, sc["alpha_kinds"], "alpha"),
        (BRAVO, sc["bravo_kinds"], "bravo"),
    ):
        for idx, kind in enumerate(kinds):
            drone_id = idx + 1
            x_start, x_end, y_start, y_end = strip_bounds(swarm, drone_id)

            if kind == KIND_VANISH:
                # No input file is written for a vanished drone — the
                # whole point is that nothing was recovered. We do
                # record the gap so the operator and the auditor know
                # exactly which sector was left blind.
                vanished.append({
                    "swarm":        prefix,
                    "mission_id":   swarm.mission_id,
                    "drone_id":     drone_id,
                    "strip_x_start": x_start,
                    "strip_x_end":   x_end,
                    "strip_y_start": y_start,
                    "strip_y_end":   y_end,
                    "reason":       "vanished (no telemetry recovered)",
                })
                continue

            rng = random.Random(seed + 1000 * swarm.mission_id + drone_id)
            gen, _kind_label = _KIND_TO_GENERATOR[kind]
            cells = gen(rng, x_start, x_end, y_start, y_end)
            label = (
                f"{prefix} drone {drone_id} ({kind}): "
                f"strip x=[{x_start},{x_end}) y=[{y_start},{y_end}), "
                f"n_cells={len(cells[0])}"
            )
            payload = make_input_json(swarm, drone_id, *cells, label=label)
            results.append((f"{prefix}{drone_id}_input.json", payload))

    return results, vanished


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument(
        "--scenario",
        choices=sorted(SCENARIOS.keys()),
        required=True,
        help="which dual-flank outcome to generate",
    )
    ap.add_argument(
        "--output-dir",
        type=Path,
        default=Path("."),
        help="directory to write the 10 input JSONs (default: cwd)",
    )
    ap.add_argument(
        "--seed",
        type=int,
        default=42,
        help="base RNG seed for deterministic generation (default: 42)",
    )
    args = ap.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    files, vanished = generate(args.scenario, args.seed)

    print(f"[generate-mission] scenario={args.scenario}, seed={args.seed}")
    print(f"[generate-mission] {SCENARIOS[args.scenario]['summary']}")
    for fname, payload in files:
        path = args.output_dir / fname
        path.write_text(json.dumps(payload, indent=2))
        elapsed = payload["cells_ts"][-1] - TS_START if payload["cells_ts"] else 0
        cov_per = payload["n_cells"] * 1000 // payload["strip_total_cells"]
        max_p   = max(payload["cells_p_contact"]) if payload["cells_p_contact"] else 0
        print(
            f"  {path}: "
            f"strip x=[{payload['strip_x_start']},{payload['strip_x_end']}) "
            f"n_cells={payload['n_cells']} cov={cov_per}/1000 "
            f"max_p={max_p} elapsed={elapsed}s"
        )

    # Emit a vanish_manifest.json alongside the input files so
    # downstream tooling (entrypoint.sh, audit dashboards, the thesis
    # appendix) can render "WANTED — last seen never reported" notices
    # for the missing sectors. Always written (empty list when no
    # drones vanished) so consumers can rely on the file existing.
    manifest_path = args.output_dir / "vanish_manifest.json"
    manifest_path.write_text(json.dumps({
        "scenario":  args.scenario,
        "summary":   SCENARIOS[args.scenario]["summary"],
        "vanished":  vanished,
    }, indent=2))
    if vanished:
        print()
        print(f"[generate-mission] VANISH MANIFEST ({len(vanished)} drone(s)):")
        for v in vanished:
            print(
                f"  {v['swarm']}{v['drone_id']} — "
                f"sector x=[{v['strip_x_start']},{v['strip_x_end']}) "
                f"y=[{v['strip_y_start']},{v['strip_y_end']}) BLIND"
            )
        print(f"  -> manifest written to {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

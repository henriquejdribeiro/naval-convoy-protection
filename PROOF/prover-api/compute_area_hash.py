#!/usr/bin/env python3
"""
compute_area_hash.py — off-chain Pedersen computation of the expected SWARM AREA
hash that Registry.deploy stores in spec.areaHash, and that the circuit's
swarm_hash output must equal (checked by Verifier.registerSwarmProof).

It MUST match the A_d fold in safe_area_verify_<swarm>.cairo EXACTLY:

    A_d      = Pedersen(Pedersen(Pedersen(Pedersen(x_start, y_start), width), height), cover_map)
    areaHash = acc = 0 ; for d in 0..n-1 : acc = Pedersen(acc, A_d)

with, for drone d (0-based):
    x_start   = zone_x + d * strip_width      (SW corner, |lon|·1e7)
    y_start   = zone_y                        (SW corner,  lat·1e7)
    width     = strip_width                   (E7)
    height    = zone_h                        (E7)
    cover_map = FULL_MASK for the swarm       (100% coverage: all bits set)

FULL_MASK must match the circuit's constant:
    alpha strip = 4×20 = 80 cells  → 2**80 - 1
    bravo strip = 4×10 = 40 cells  → 2**40 - 1

Runs in the prover image (convoy-prover-api), which ships cairo-lang 0.14.0.1 and
therefore starkware.crypto.signature.fast_pedersen_hash. Prints 0x + 64 hex
(a bytes32) for cast.

Example:
    python3 /app/compute_area_hash.py --swarm alpha \
        --zone-x 150000000 --zone-y 370000000 \
        --strip-width 2000000 --zone-h 10000000 --n-drones 5
"""
import argparse
from starkware.crypto.signature.fast_pedersen_hash import pedersen_hash

# ── Coverage target per swarm — KEEP IN SYNC with FULL_MASK in
#    safe_area_verify_<swarm>.cairo (and FULL_MASK_{ALPHA,BRAVO} in Registry.sol).
FULL_MASK = {
    "alpha": (1 << 80) - 1,   # 80 accounting cells (4×20)
    "bravo": (1 << 40) - 1,   # 40 accounting cells (4×10)
}


def area_hash(swarm, zone_x, zone_y, strip_width, zone_h, n_drones):
    cover = FULL_MASK[swarm]
    acc = 0
    for d in range(n_drones):
        x_start = zone_x + d * strip_width
        y_start = zone_y
        h = pedersen_hash(x_start, y_start)   # Pedersen(x_start, y_start)
        h = pedersen_hash(h, strip_width)     # ...   , width
        h = pedersen_hash(h, zone_h)          # ...   , height
        a_d = pedersen_hash(h, cover)         # ...   , cover_map  → A_d
        acc = pedersen_hash(acc, a_d)         # fold A_d into the swarm chain
    return acc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--swarm", required=True, choices=["alpha", "bravo"])
    ap.add_argument("--zone-x",      type=int, required=True)
    ap.add_argument("--zone-y",      type=int, required=True)
    ap.add_argument("--strip-width", type=int, required=True)
    ap.add_argument("--zone-h",      type=int, required=True)
    ap.add_argument("--n-drones",    type=int, default=5)
    a = ap.parse_args()
    print("0x%064x" % area_hash(
        a.swarm, a.zone_x, a.zone_y, a.strip_width, a.zone_h, a.n_drones))


if __name__ == "__main__":
    main()

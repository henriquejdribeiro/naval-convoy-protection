#!/usr/bin/env python3
"""
sign_telemetry.py — drone-side signing for the Route-B identity binding.

Computes H = Pedersen-chain(cells, nonce) EXACTLY as safe_area_verify.cairo's
hash_cells_with_nonce does (acc0=0, per-cell x,y,p,ts interleave, then a final
Pedersen with the nonce), signs H with the drone's STARK-curve key (pulled from
its starkli keystore), and emits the five extra felts submit_telemetry now
takes: cells_nonce, commitment_h (=H), drone_pubkey, sig_r, sig_s.

Runs inside the prover-api image (has cairo-lang for Pedersen+sign AND starkli
to decrypt the keystore). Example:

    docker run --rm --entrypoint python3 -v "$(pwd):/work" -w /work \
        convoy-prover-api:latest infrastructure/prover-api/sign_telemetry.py \
            --cells cells.json \
            --keystore .tmp-l2/drones/bravo/3/keystore.json \
            --password convoy --out /dev/stdout
"""
from __future__ import annotations
import argparse, json, secrets, subprocess, sys

from starkware.crypto.signature.fast_pedersen_hash import pedersen_hash
from starkware.crypto.signature.signature import sign, private_to_stark_key

# STARK ECDSA requires the signed message to fit in 251 bits. Pedersen output
# lives in [0, P) with P just above 2**251, so on the (astronomically rare)
# occasion H >= 2**251 we simply pick a new nonce.
BOUND = 2 ** 251


def pedersen_chain(cx, cy, cp, cts, nonce: int) -> int:
    """Mirror safe_area_verify.cairo:hash_cells_with_nonce exactly."""
    acc = 0
    for x, y, p, ts in zip(cx, cy, cp, cts):
        acc = pedersen_hash(acc, int(x))
        acc = pedersen_hash(acc, int(y))
        acc = pedersen_hash(acc, int(p))
        acc = pedersen_hash(acc, int(ts))
    return pedersen_hash(acc, nonce)


def keystore_private_key(keystore: str, password: str) -> int:
    """Decrypt the drone's starkli keystore → raw private key (int)."""
    out = subprocess.run(
        ["starkli", "signer", "keystore", "inspect-private",
         "--raw", "--password", password, keystore],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        raise SystemExit(f"[sign] starkli inspect-private-key failed: {out.stderr.strip()}")
    return int(out.stdout.strip().splitlines()[-1].strip(), 16)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cells", required=True, help="JSON with cells_x/y/p_contact/ts arrays")
    ap.add_argument("--keystore", required=True)
    ap.add_argument("--password", default="convoy")
    ap.add_argument("--nonce", help="felt (dec or 0x); default = fresh random")
    ap.add_argument("--out", default="/dev/stdout")
    ap.add_argument("--emit-calldata", action="store_true",
                    help="print only the space-separated felt tail for starkli calldata")
    args = ap.parse_args()

    d = json.load(open(args.cells))
    cx, cy, cp, cts = d["cells_x"], d["cells_y"], d["cells_p_contact"], d["cells_ts"]
    n = len(cx)
    for name, arr in (("cells_y", cy), ("cells_p_contact", cp), ("cells_ts", cts)):
        if len(arr) != n:
            raise SystemExit(f"[sign] {name} length {len(arr)} != cells_x length {n}")

    priv = keystore_private_key(args.keystore, args.password)
    pub = private_to_stark_key(priv)

    if args.nonce is not None:
        nonce = int(args.nonce, 0)
        H = pedersen_chain(cx, cy, cp, cts, nonce)
        if H >= BOUND:
            raise SystemExit("[sign] supplied --nonce yields H >= 2**251; drop --nonce to auto-pick")
    else:
        while True:
            nonce = secrets.randbelow(BOUND)
            H = pedersen_chain(cx, cy, cp, cts, nonce)
            if H < BOUND:
                break

    r, s = sign(msg_hash=H, priv_key=priv)

    result = {
        "cells_nonce":  nonce,
        "commitment_h": H,
        "drone_pubkey": pub,
        "sig_r":        r,
        "sig_s":        s,
        # calldata-ready tail for submit_telemetry (decimals, in ABI order)
        "calldata_tail": [str(nonce), str(H), str(pub), str(r), str(s)],
    }
    if args.emit_calldata:
        print(" ".join(result["calldata_tail"]))
        return 0
    with open(args.out, "w") as f:
        json.dump(result, f, indent=2)
        f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
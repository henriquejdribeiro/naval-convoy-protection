#!/usr/bin/env python3
"""
extract-sources.py — regenerate starkware-verifier/src/ from the Sourcify
source bundles under LAYER1/tmp-etherscan/sources/.

Each bundle is a Sourcify /files/any response:
    {"status": ..., "files": [{"name","path","content"}, ...]}
where `path` = contracts/<match>/1/0x<addr>/sources/<realpath>   (a .sol)
           or  contracts/<match>/1/0x<addr>/metadata.json         (compiler settings)

For every deployed verifier contract we write a self-contained, byte-exact
source tree under src/<name>/ (plus its metadata.json), so each folder
recompiles to the matching bytecode/<name>.hex. The folder name equals the
bytecode/*.hex basename (CFV/GPS map to the two *_creation.hex).

Address-driven: the expected mainnet address is asserted against the address
embedded in each bundle's paths — this is what pins the *_OLDgps_idx6 variants
as the real deployed suite (cairoVerifierId = 6, StarkWare 2023_9) and rejects
the _REAL / _NEW / _layout6 / _layout7 exploration leftovers.

Read-only w.r.t. the bundles; only writes under src/. Idempotent.
"""
import json, re, sys
from pathlib import Path

HERE    = Path(__file__).resolve().parent
SOURCES = HERE.parent.parent / "tmp-etherscan" / "sources"   # LAYER1/tmp-etherscan/sources
OUT     = HERE / "src"

# folder (== bytecode/*.hex basename) -> (bundle json, expected mainnet address)
MAPPING = {
    "GpsStatementVerifier": ("GpsStatementVerifier.json",                    "0xd51a3d50d4d2f99a345a66971e650eea064dd8df"),
    "CpuFrilessVerifier":   ("CpuFrilessVerifier_OLDgps_idx6_starknet.json", "0xaa2c9cdd4ceaebe9a35873b77f57fb47c3ef11b9"),
    "Merkle":               ("MerkleStatementContract.json",                 "0x634dcf4f1421fc4d95a968a559a450ad0245804c"),
    "Fri":                  ("FriStatementContract.json",                    "0xdef8a3b280a54ee7ed4f72e1c7d6098ad8df44fb"),
    "MemoryPage":           ("MemoryPageFactRegistry.json",                  "0x40864568f679c10ac9e72211500096a5130770fa"),
    "CpuConstraintPoly":    ("CpuConstraintPoly_OLDgps_idx6.json",           "0xdd4cbe8cc7f420a9576f93e1d1ccc501495b5253"),
    "CpuOods":              ("CpuOods_OLDgps_idx6.json",                     "0x367b337aa4a056cb78fd74f94e283a73b27dfbb6"),
    "Bootloader":           ("CairoBootloaderProgram.json",                  "0xb4c61d092ecf1b69f1965f9d8de639148ea26a40"),
    "PedersenX":            ("PedersenPointsX.json",                         "0x3d571a45d2b14ff423d2dc4a0e7a46e07d9682bb"),
    "PedersenY":            ("PedersenPointsY.json",                         "0xfd12a123ecf4326e70a4d8b2bc260ec730bbe7fd"),
    "EcdsaX":               ("EcdsaX_OLDgps_idx6.json",                      "0xcb799cbbd4f5f0a3b6bbd9b55f59e8b301a0286b"),
    "EcdsaY":               ("EcdsaY_OLDgps_idx6.json",                      "0x9e4fdd8ff1b11e8f788af77caa4b0037c137ecc1"),
    "PoseidonFR0":          ("PoseidonFR0_OLDgps_idx6.json",                 "0xe7b835ea7e348b25af2480272c4ca28429573293"),
    "PoseidonFR1":          ("PoseidonFR1_OLDgps_idx6.json",                 "0xc2969a099f22430e20bce237f469ac6f3101ac5f"),
    "PoseidonFR2":          ("PoseidonFR2_OLDgps_idx6.json",                 "0xb5a5759dd063899f213eb9699906b445f855660d"),
    "PoseidonPR0":          ("PoseidonPR0_OLDgps_idx6.json",                 "0x1db84e79e8daec762d6adaa5bf358a4ba001e975"),
    "PoseidonPR1":          ("PoseidonPR1_OLDgps_idx6.json",                 "0x62960c874379653d7bbe3644ac653736da2eda12"),
}

ADDR_RE = re.compile(r'/(?:partial|full)_match/1/(0x[0-9a-fA-F]{40})/')

def rel_target(path):
    """Path inside the bundle -> path relative to the contract root, else None."""
    if "/sources/" in path:
        return path.split("/sources/", 1)[1]
    if path.endswith("/metadata.json"):
        return "metadata.json"
    return None  # creator-tx-hash.txt, constructor-args.txt, library map, ...

def main():
    if not SOURCES.is_dir():
        sys.exit(f"[extract] sources dir not found: {SOURCES}")
    total = 0
    for name, (bundle, expect) in MAPPING.items():
        bp = SOURCES / bundle
        if not bp.is_file():
            sys.exit(f"[extract] missing bundle: {bp}")
        files = json.loads(bp.read_text(encoding="utf-8")).get("files", [])
        addrs = {m.group(1).lower()
                 for f in files
                 for m in [ADDR_RE.search(f.get("path", ""))] if m}
        if addrs != {expect}:
            sys.exit(f"[extract] {name}: address mismatch — bundle={addrs} expected={{{expect}}}")
        dest_root = (OUT / name).resolve()
        n = 0
        for f in files:
            rel = rel_target(f.get("path", ""))
            if rel is None:
                continue
            target = (dest_root / rel).resolve()
            if not str(target).startswith(str(dest_root)):
                sys.exit(f"[extract] refusing path traversal: {f.get('path')}")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(f["content"].encode("utf-8"))  # LF preserved -> byte-exact
            n += 1
        total += n
        print(f"  {name:22s} {expect}  ({n} files)")
    print(f"[extract] wrote {total} files under {OUT}")

if __name__ == "__main__":
    main()

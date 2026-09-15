#!/usr/bin/env python3
"""
verify-bytecode.py — recompile each starkware-verifier/src/<name>/ with the
exact compiler pinned in its metadata.json (solc 0.6.12, istanbul, optimizer
1e6) and compare the result to the deployed bytecode.

  15 stateless contracts : solc deployedBytecode  vs  bytecode/<name>.hex
                           (== mainnet eth_getCode)
  CFV, GPS (constructor)  : solc creation bytecode vs  {cfv,gps}_creation.hex

Verdict:
  FULL — byte-identical.
  CODE — identical except the trailing CBOR metadata hash (expected for a
         Sourcify 'partial match'); the executable logic is identical.
  DIFF — differs in the code itself -> investigate.

solc runs in docker (ethereum/solc:0.6.12) via --standard-json on stdin; the
input is built straight from each contract's metadata (compilationTarget +
settings) + the extracted sources, i.e. exactly how Sourcify verified it.
"""
import json, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC  = HERE / "src"
SOLC_IMAGE = "ethereum/solc:0.6.12"

# folder -> (hex file relative to HERE, kind)   kind: runtime | creation
TARGETS = {
    "Merkle":              ("bytecode/Merkle.hex",            "runtime"),
    "Fri":                 ("bytecode/Fri.hex",               "runtime"),
    "MemoryPage":          ("bytecode/MemoryPage.hex",        "runtime"),
    "CpuConstraintPoly":   ("bytecode/CpuConstraintPoly.hex", "runtime"),
    "CpuOods":             ("bytecode/CpuOods.hex",           "runtime"),
    "Bootloader":          ("bytecode/Bootloader.hex",        "runtime"),
    "PedersenX":           ("bytecode/PedersenX.hex",         "runtime"),
    "PedersenY":           ("bytecode/PedersenY.hex",         "runtime"),
    "EcdsaX":              ("bytecode/EcdsaX.hex",            "runtime"),
    "EcdsaY":              ("bytecode/EcdsaY.hex",            "runtime"),
    "PoseidonFR0":         ("bytecode/PoseidonFR0.hex",       "runtime"),
    "PoseidonFR1":         ("bytecode/PoseidonFR1.hex",       "runtime"),
    "PoseidonFR2":         ("bytecode/PoseidonFR2.hex",       "runtime"),
    "PoseidonPR0":         ("bytecode/PoseidonPR0.hex",       "runtime"),
    "PoseidonPR1":         ("bytecode/PoseidonPR1.hex",       "runtime"),
    "CpuFrilessVerifier":  ("cfv_creation.hex",               "creation"),
    "GpsStatementVerifier":("gps_creation.hex",               "creation"),
}

def norm(h):
    h = h.strip().lower()
    return h[2:] if h.startswith("0x") else h

def strip_metadata(code):
    # trailing CBOR: last 2 bytes = length of the metadata blob (in bytes)
    if len(code) < 4:
        return code
    cut = int(code[-4:], 16) * 2 + 4
    return code[:-cut] if 0 < cut < len(code) else code

def build_standard_json(folder):
    meta = json.loads((SRC / folder / "metadata.json").read_text(encoding="utf-8"))
    s = meta["settings"]
    (tgt_path, tgt_name), = s["compilationTarget"].items()
    sources = {}
    for path in meta["sources"]:
        f = SRC / folder / path
        if not f.is_file():
            sys.exit(f"[verify] {folder}: metadata lists {path} but it's not on disk")
        sources[path] = {"content": f.read_bytes().decode("utf-8")}
    settings = {
        "optimizer":  s.get("optimizer", {}),
        "evmVersion": s.get("evmVersion"),
        "libraries":  s.get("libraries", {}),
        "remappings": s.get("remappings", []),
        "metadata":   s.get("metadata", {}),
        "outputSelection": {"*": {"*": ["evm.bytecode.object", "evm.deployedBytecode.object"]}},
    }
    settings = {k: v for k, v in settings.items() if v is not None}
    return {"language": meta.get("language", "Solidity"), "sources": sources, "settings": settings}, tgt_path, tgt_name

def solc(std):
    p = subprocess.run(["docker", "run", "--rm", "-i", SOLC_IMAGE, "--standard-json"],
                       input=json.dumps(std).encode("utf-8"),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        sys.exit(f"[verify] solc docker failed:\n{p.stderr.decode(errors='replace')[:1000]}")
    return json.loads(p.stdout)

def main():
    rows = []
    for folder, (hexrel, kind) in TARGETS.items():
        std, tgt_path, tgt_name = build_standard_json(folder)
        out = solc(std)
        errs = [e for e in out.get("errors", []) if e.get("severity") == "error"]
        if errs:
            sys.exit(f"[verify] {folder}: solc errors:\n" + "\n".join(e.get("formattedMessage","") for e in errs))
        evm = out["contracts"][tgt_path][tgt_name]["evm"]
        obj = evm["bytecode"]["object"] if kind == "creation" else evm["deployedBytecode"]["object"]
        got, want = norm(obj), norm((HERE / hexrel).read_text(encoding="utf-8"))
        verdict = "FULL" if got == want else ("CODE" if strip_metadata(got) == strip_metadata(want) else "DIFF")
        rows.append(verdict)
        print(f"  {folder:22s} {kind:8s} -> {verdict:4s}  (deployed {len(want)//2}B, recompiled {len(got)//2}B)")
    print()
    for v in ("FULL", "CODE", "DIFF"):
        print(f"[verify] {v}: {rows.count(v)}")
    sys.exit(1 if "DIFF" in rows else 0)

if __name__ == "__main__":
    main()

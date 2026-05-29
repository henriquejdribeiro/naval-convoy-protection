#!/usr/bin/env python3
"""
strip-poseidon-from-bootloader.py — additionally remove the `poseidon`
builtin from the v0.13.x bootloader source so the resulting compiled
bytecode matches Layout 3 (6 builtins: output, pedersen, range_check,
ecdsa, bitwise, ec_op).

This is the follow-on to scripts/strip-keccak-from-bootloader.py.
Run that first, then this one. They are not idempotent across each other
because the keccak strip changes line counts.

Why poseidon needs special handling
-----------------------------------

`keccak` and `range_check96` are declared in the bootloader's
`%builtins` line but never actually USED in the bootloader's own
Cairo logic — they're declared so tasks running inside the bootloader
can use them. So the keccak strip just deletes any line mentioning
those tokens (struct field, function arg, hint label).

`poseidon` is different. The bootloader USES it in
`compute_program_hash` to optionally hash the inner task's program
with Poseidon instead of Pedersen (governed by the `use_poseidon`
flag). The cairo-bootloader Rust integration we use forces
`use_poseidon = 0` (the SIMPLE_BOOTLOADER_ZERO hint), so the
Poseidon branch is dead at runtime — but the source still references
PoseidonBuiltin, imports it, holds a `poseidon: felt` slot in
BuiltinData, etc. We need to surgically replace those references
with a Pedersen-only flow (and drop the now-unreachable Poseidon
branch in compute_program_hash) rather than just deleting lines.

What this script does
---------------------

Four source files are edited (the same set as the keccak strip):

    bootloader/bootloader.cairo
    simple_bootloader/simple_bootloader.cairo
    simple_bootloader/execute_task.cairo
    simple_bootloader/run_simple_bootloader.cairo

For each:

  1. Drop `poseidon` from the `%builtins` declaration.
  2. Drop the `PoseidonBuiltin` and `poseidon_hash_many` imports.
  3. Drop `poseidon_ptr: PoseidonBuiltin*` from function parameter
     blocks and func{...} implicit-argument lists.
  4. Drop the `poseidon: felt` field from the `BuiltinData` struct.
  5. Drop the `poseidon=...` field from BuiltinData(...) constructor
     calls (output/pedersen/range_check/ecdsa/bitwise/ec_op/poseidon).
  6. In `compute_program_hash`, replace the `if (use_poseidon == 1)`
     branch with an unconditional Pedersen hash chain and drop the
     `poseidon_ptr` implicit arg.
  7. Drop lines that pure-handle poseidon: cast(...,PoseidonBuiltin*),
     PoseidonBuiltin imports, `local poseidon_ptr: ...` declarations,
     `with pedersen_ptr, poseidon_ptr {` → `with pedersen_ptr {`, etc.

The edits are textual but pattern-driven. The script reports
before/after line counts.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


BOOTLOADER_ROOT = Path(
    "vendor/cairo-bootloader/dependencies/cairo-lang/src/starkware/cairo/bootloaders"
)

FILES = [
    BOOTLOADER_ROOT / "bootloader" / "bootloader.cairo",
    BOOTLOADER_ROOT / "simple_bootloader" / "simple_bootloader.cairo",
    BOOTLOADER_ROOT / "simple_bootloader" / "execute_task.cairo",
    BOOTLOADER_ROOT / "simple_bootloader" / "run_simple_bootloader.cairo",
]


def strip_builtins_line(text: str) -> str:
    """Drop `poseidon` from `%builtins` declarations."""
    def repl(match: re.Match) -> str:
        tokens = match.group(1).split()
        kept = [t for t in tokens if t != "poseidon"]
        return "%builtins " + " ".join(kept)

    return re.sub(r"^%builtins\s+(.+)$", repl, text, flags=re.MULTILINE)


def drop_lines_containing(text: str, tokens: list[str]) -> str:
    """Delete entire lines that contain any of the substrings."""
    out: list[str] = []
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if any(tok in stripped for tok in tokens):
            continue
        out.append(line)
    return "".join(out)


def edit_execute_task(text: str) -> str:
    """
    execute_task.cairo: the heaviest surgery file. It defines
    compute_program_hash (which has the use_poseidon branch) and the
    BuiltinData struct that the cairo-bootloader Rust hints index into.
    """
    # 1. Drop the PoseidonBuiltin import line.
    text = re.sub(
        r"from starkware\.cairo\.common\.builtin_poseidon\.poseidon "
        r"import PoseidonBuiltin, poseidon_hash_many\n",
        "",
        text,
    )

    # 2. Drop the `poseidon: felt,` field from BuiltinData. There are
    #    THREE BuiltinData definitions/constructors in this file:
    #    - the struct itself
    #    - pre_execution_builtin_ptrs BuiltinData(...)
    #    - return_builtin_ptrs / builtin_encodings / builtin_instance_sizes
    #    The pattern is uniform: a line of the form `    poseidon=...` or
    #    `    poseidon: felt,`. Drop them.
    text = re.sub(r"^\s*poseidon\s*[:=][^\n]*\n", "", text, flags=re.MULTILINE)

    # 3. The compute_program_hash function: replace the entire
    #    if/else use_poseidon branch with a single unconditional
    #    hash_chain call, and drop the poseidon_ptr implicit arg.
    text = re.sub(
        r"func compute_program_hash\{pedersen_ptr: HashBuiltin\*, "
        r"poseidon_ptr: PoseidonBuiltin\*\}\(\n"
        r"    program_data_ptr: felt\*, use_poseidon: felt\n"
        r"\) -> \(hash: felt\) \{\n"
        r"    if \(use_poseidon == 1\) \{\n"
        r"        let \(hash\) = poseidon_hash_many\{poseidon_ptr=poseidon_ptr\}\(\n"
        r"            n=program_data_ptr\[0\], elements=&program_data_ptr\[1\]\n"
        r"        \);\n"
        r"        return \(hash=hash\);\n"
        r"    \} else \{\n"
        r"        let \(hash\) = hash_chain\{hash_ptr=pedersen_ptr\}\(data_ptr=program_data_ptr\);\n"
        r"        return \(hash=hash\);\n"
        r"    \}\n"
        r"\}",
        "func compute_program_hash{pedersen_ptr: HashBuiltin*}(\n"
        "    program_data_ptr: felt*, use_poseidon: felt\n"
        ") -> (hash: felt) {\n"
        "    // Convoy: Layout 3 has no Poseidon builtin. The bootloader's\n"
        "    // use_poseidon flag is forced to 0 by the SIMPLE_BOOTLOADER_ZERO\n"
        "    // hint, so the Poseidon branch is dead — collapse to pedersen.\n"
        "    let (hash) = hash_chain{hash_ptr=pedersen_ptr}(data_ptr=program_data_ptr);\n"
        "    return (hash=hash);\n"
        "}",
        text,
    )

    # 4. The call site for compute_program_hash uses
    #    `with pedersen_ptr, poseidon_ptr {`. Drop poseidon_ptr from it.
    text = text.replace(
        "with pedersen_ptr, poseidon_ptr {",
        "with pedersen_ptr {",
    )

    # 5. Drop lines that handle poseidon_ptr locally
    #    (local poseidon_ptr declarations, casts, etc.).
    text = drop_lines_containing(
        text,
        [
            "let poseidon_ptr = cast",
            "PoseidonBuiltin*",
            "poseidon_ptr: PoseidonBuiltin",
            "poseidon_ptr: felt",  # in case some signatures use felt form
        ],
    )

    return text


def edit_run_simple_bootloader(text: str) -> str:
    """run_simple_bootloader.cairo — drop poseidon from the BuiltinData
    constructors, function signatures, and local conversions."""
    text = re.sub(
        r"from starkware\.cairo\.common\.cairo_builtins "
        r"import HashBuiltin, PoseidonBuiltin\n",
        "from starkware.cairo.common.cairo_builtins import HashBuiltin\n",
        text,
    )

    # Drop `poseidon=...` and `poseidon_ptr: PoseidonBuiltin*,` lines.
    text = re.sub(r"^\s*poseidon\s*[:=][^\n]*\n", "", text, flags=re.MULTILINE)
    text = drop_lines_containing(
        text,
        [
            "poseidon_ptr: PoseidonBuiltin",
            "let poseidon_ptr = cast",
            "poseidon_ptr = cast(builtin_ptrs.poseidon",
        ],
    )

    return text


def edit_simple_bootloader(text: str) -> str:
    """simple_bootloader.cairo — main() declares poseidon_ptr; drop it."""
    text = re.sub(
        r"from starkware\.cairo\.common\.cairo_builtins "
        r"import HashBuiltin, PoseidonBuiltin\n",
        "from starkware.cairo.common.cairo_builtins import HashBuiltin\n",
        text,
    )
    text = drop_lines_containing(
        text,
        ["poseidon_ptr: PoseidonBuiltin"],
    )
    return text


def edit_bootloader(text: str) -> str:
    """bootloader.cairo — same as simple_bootloader plus an extra
    `local poseidon_ptr: PoseidonBuiltin* = poseidon_ptr;` line and
    similar."""
    text = re.sub(
        r"from starkware\.cairo\.common\.cairo_builtins "
        r"import HashBuiltin, PoseidonBuiltin\n",
        "from starkware.cairo.common.cairo_builtins import HashBuiltin\n",
        text,
    )
    # Also drop the poseidon_hash_many import if present (used by parse_tasks
    # for composite output unpacking — we don't support composite tasks
    # since HASHED_CAIRO_VERIFIERS=empty, so this branch is unreachable).
    text = re.sub(
        r"from starkware\.cairo\.common\.builtin_poseidon\.poseidon "
        r"import poseidon_hash_many\n",
        "",
        text,
    )
    text = drop_lines_containing(
        text,
        [
            "poseidon_ptr: PoseidonBuiltin",
            "local poseidon_ptr: PoseidonBuiltin",
            "PoseidonBuiltin*,",
        ],
    )
    # Also replace the parse_tasks call's poseidon_hash_many in
    # unpack_composite_packed_task — but since we don't use composite
    # packed tasks, the entire unpack_composite_packed_task function
    # body can stay as-is; it'll never be executed. We DO need to
    # drop poseidon_ptr from its implicit-args list though.
    text = re.sub(
        r"^\s*poseidon_ptr:\s*PoseidonBuiltin\*,\s*\n",
        "",
        text,
        flags=re.MULTILINE,
    )

    return text


EDITORS = {
    "bootloader/bootloader.cairo": edit_bootloader,
    "simple_bootloader/simple_bootloader.cairo": edit_simple_bootloader,
    "simple_bootloader/execute_task.cairo": edit_execute_task,
    "simple_bootloader/run_simple_bootloader.cairo": edit_run_simple_bootloader,
}


def main() -> int:
    if not BOOTLOADER_ROOT.exists():
        sys.exit(f"[strip-poseidon] bootloader source not found at {BOOTLOADER_ROOT}")

    print("[strip-poseidon] removing poseidon from bootloader sources")
    print(f"[strip-poseidon] target: {BOOTLOADER_ROOT}")
    print()

    for f in FILES:
        rel = f.relative_to(BOOTLOADER_ROOT).as_posix()
        if rel not in EDITORS:
            sys.exit(f"[strip-poseidon] no editor registered for {rel}")

        before = f.read_text()
        # First strip the `%builtins` poseidon token (uniform across files).
        text = strip_builtins_line(before)
        # Then apply file-specific surgery.
        text = EDITORS[rel](text)
        f.write_text(text)

        lines_before = before.count("\n")
        lines_after = text.count("\n")
        removed = lines_before - lines_after
        print(
            f"  {rel:55s}  {lines_before:4d} -> {lines_after:4d}  ({removed:+d} lines)"
        )

    print()
    print("[strip-poseidon] done. Now recompile the bootloader:")
    print("  cd /tmp/cairo_src && cairo-compile starkware/cairo/bootloaders/bootloader/bootloader.cairo \\")
    print("      --output /tmp/bootloader-rebuilt.json --proof_mode")
    return 0


if __name__ == "__main__":
    sys.exit(main())

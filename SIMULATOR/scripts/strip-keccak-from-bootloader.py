#!/usr/bin/env python3
"""
strip-keccak-from-bootloader.py — remove the `keccak` and `range_check96`
builtins from the v0.13.x bootloader source so the resulting compiled
bytecode matches Layout 6 (7 builtins: output, pedersen, range_check,
ecdsa, bitwise, ec_op, poseidon).

Why
---

Our deployed StarkWare evm-verifier (starkex-contracts @ StarkPerpetual-v3.2,
Layout 6) supports 7 builtins. The cairo-bootloader library bundles a v0.13.x
bootloader compiled with 9 builtins (extra: keccak, range_check96). At
Phase-4 verification on L1 the verifier reconstructs the public memory's
execute segment using 7 builtin slots, while the proof carries 9.
Hashes diverge — "Invalid hash for memory page 0."

The bootloader doesn't *use* keccak or range_check96 in its own logic; it
just declares them so tasks running inside it can. Our convoy task
(safe_area_verify.cairo) declares only `output range_check poseidon`, so
dropping these two builtins from the bootloader is safe at the application
layer — no task ever touches the removed builtins.

What this script does
---------------------

Four source files in the inner cairo-lang submodule are edited:

    bootloader/bootloader.cairo
    simple_bootloader/simple_bootloader.cairo
    simple_bootloader/execute_task.cairo
    simple_bootloader/run_simple_bootloader.cairo

For each:

  - The `%builtins` declaration on line 1: remove the two tokens.
  - Every other line containing `keccak` or `range_check96` (struct
    field, function parameter, assignment, local declaration, hint
    label, builtin-ratio entry): delete the whole line.

The edits are idempotent — running the script twice has the same effect
as running it once.

After running this, run the cairo-bootloader's own compile script
(scripts/compile-bootloader.sh) to produce the new compiled JSON.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


BOOTLOADER_ROOT = Path("vendor/cairo-bootloader/dependencies/cairo-lang/src/starkware/cairo/bootloaders")

FILES = [
    BOOTLOADER_ROOT / "bootloader" / "bootloader.cairo",
    BOOTLOADER_ROOT / "simple_bootloader" / "simple_bootloader.cairo",
    BOOTLOADER_ROOT / "simple_bootloader" / "execute_task.cairo",
    BOOTLOADER_ROOT / "simple_bootloader" / "run_simple_bootloader.cairo",
]

# Tokens that mark a line for deletion when they appear anywhere on it
# (except the %builtins line, which we handle separately).
#
# Note: NOT using \b word boundaries because `_` counts as a word character
# in Python's `re`, so `\bkeccak\b` fails to match `keccak_ptr`. We instead
# match the literal substring anywhere on the line. For this codebase there
# are no false-positive occurrences of either token.
DELETE_IF_LINE_CONTAINS = re.compile(r"(keccak|range_check96)")

# %builtins-line surgery: remove these two tokens from the space-separated list.
BUILTINS_LINE = re.compile(r"^%builtins\s+(.+)$")


def edit_file(path: Path) -> tuple[int, int]:
    """
    Return (lines_before, lines_after) for sanity reporting.
    """
    if not path.exists():
        sys.exit(f"[strip] missing file: {path}")

    original = path.read_text().splitlines(keepends=True)
    output: list[str] = []

    for line in original:
        stripped = line.rstrip("\n").rstrip("\r")

        # Handle %builtins line: strip the two tokens, keep the rest.
        m = BUILTINS_LINE.match(stripped)
        if m:
            tokens = m.group(1).split()
            kept = [t for t in tokens if t not in ("keccak", "range_check96")]
            new_line = "%builtins " + " ".join(kept)
            # Preserve the line ending convention.
            ending = line[len(stripped):]
            output.append(new_line + ending)
            continue

        # Otherwise, drop the line entirely if it mentions either token.
        if DELETE_IF_LINE_CONTAINS.search(stripped):
            continue

        output.append(line)

    path.write_text("".join(output))
    return len(original), len(output)


def main() -> int:
    if not BOOTLOADER_ROOT.exists():
        sys.exit(
            f"[strip] bootloader source not found at {BOOTLOADER_ROOT}.\n"
            "        Run `git -C vendor/cairo-bootloader submodule update --init\n"
            "        dependencies/cairo-lang` first to fetch the inner submodule."
        )

    print("[strip] removing keccak and range_check96 from bootloader sources")
    print(f"[strip] target: {BOOTLOADER_ROOT}")
    print()

    for f in FILES:
        before, after = edit_file(f)
        removed = before - after
        rel = f.relative_to(BOOTLOADER_ROOT)
        print(f"  {rel!s:55s}  {before:4d} -> {after:4d}  ({removed:+d} lines)")

    print()
    print("[strip] done. Now recompile the bootloader to pick up the changes:")
    print("        cd vendor/cairo-bootloader && bash scripts/compile-bootloader.sh")
    print("        (requires cairo-lang in PATH; run inside convoy-prover-api)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

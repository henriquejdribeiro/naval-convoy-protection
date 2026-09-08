#!/usr/bin/env bash
# =============================================================================
# Materialise the broken symlinks in contracts/lib/starkex-contracts/.
#
# Why this exists
# ---------------
# The upstream `starkware-libs/starkex-contracts` repo uses filesystem
# symlinks to share files between sub-trees (evm-verifier/, scalable-dex/,
# common-contracts/). On Linux those resolve transparently. On Windows
# without `core.symlinks` enabled at clone time (which itself requires
# Developer Mode or admin to actually create symlinks), git checks them out
# as plain text files whose content is the target's relative path. There
# are 69 such broken files at the pinned commit, and `forge build` cannot
# follow them.
#
# This script walks every file with git mode 120000 in the submodule's
# index, reads the path stored as the "fake symlink" content, resolves it,
# and overwrites the file with a real copy of the target's content.
#
# After running, the submodule's working tree shows those 69 files as
# "modified" relative to its index — that's expected and harmless. Our
# parent repo is configured (in .gitmodules) with `ignore = dirty` so
# `git status` in the parent doesn't flag the submodule as dirty.
#
# Run once after cloning on Windows. On Linux it's a no-op (the symlinks
# resolve naturally; this script detects that and skips).
# =============================================================================
set -euo pipefail

SUBMODULE="contracts/lib/starkex-contracts"

if [[ ! -d "$SUBMODULE" ]]; then
    echo "error: $SUBMODULE not found — run from repo root, and ensure submodules are initialised" >&2
    exit 1
fi

cd "$SUBMODULE"

count_materialised=0
count_skipped=0
count_errors=0

while IFS= read -r link_path; do
    # The git index says this is a symlink. Two possibilities at the
    # filesystem level:
    #   1. Real symlink (Linux / Windows-with-Developer-Mode) — skip.
    #   2. Tiny text file containing the target path (Windows default).
    if [[ -L "$link_path" ]]; then
        count_skipped=$((count_skipped + 1))
        continue
    fi

    if [[ ! -f "$link_path" ]]; then
        echo "  ! missing entirely: $link_path" >&2
        count_errors=$((count_errors + 1))
        continue
    fi

    # Read the stored target path (typically a relative path like
    # "../../../../scalable-dex/contracts/src/components/FactRegistry.sol").
    target_rel=$(cat "$link_path")

    # Resolve relative to the symlink's containing directory.
    link_dir=$(dirname "$link_path")
    target_abs=$(realpath -m "$link_dir/$target_rel")

    if [[ ! -f "$target_abs" ]] || [[ -L "$target_abs" ]]; then
        # Either target doesn't exist or target is itself a (possibly
        # broken) symlink. Bail loudly so we don't propagate corruption.
        echo "  ! cannot resolve: $link_path → $target_rel → $target_abs" >&2
        count_errors=$((count_errors + 1))
        continue
    fi

    cp "$target_abs" "$link_path"
    count_materialised=$((count_materialised + 1))
done < <(git ls-files --stage | awk '$1 == "120000" { print $4 }')

echo ""
echo "materialised:  $count_materialised"
echo "already real:  $count_skipped"
echo "errors:        $count_errors"

if [[ $count_errors -gt 0 ]]; then
    exit 1
fi

echo ""
echo "Done. forge build should now resolve all imports."
echo "The submodule's working tree shows these files as modified — expected."
echo "Parent repo is configured to ignore that via .gitmodules (ignore = dirty)."

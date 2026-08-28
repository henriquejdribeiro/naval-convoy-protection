#!/usr/bin/env bash
# =============================================================================
# submit-all-telemetry.sh — submit every drone's telemetry for one scenario.
#
# Wraps the per-drone scripts/submit-telemetry.sh in a loop over both swarms'
# 5 drones, reading the cells.json files produced by generate-mission.py.
#
# Handles two real-world wrinkles:
#   - Dropout scenarios intentionally OMIT some drone files → a missing file
#     means that drone "vanished", so we skip it (correct for those scenarios).
#   - The 5th drone fires the L2→L1 syscall and occasionally loses a
#     fee-estimate race → we retry once before giving up.
#
# Usage:
#   ./scripts/submit-all-telemetry.sh [scenario] [missions-dir]
#     scenario      default: both-safe
#     missions-dir  default: .tmp-l2/missions
#
# Prereqs: missions open on L2
# =============================================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

SCENARIO="${1:-both-safe}"
MISSIONS_DIR="${2:-.tmp-l2/missions}"
SCEN_DIR="${MISSIONS_DIR}/${SCENARIO}"

# Generate the telemetry if it isn't there yet (idempotent — skips if present).
if [ ! -d "${SCEN_DIR}" ]; then
    echo "[submit-all] ${SCEN_DIR} missing — generating scenario '${SCENARIO}'"
    python3 scripts/generate-mission.py --scenario "${SCENARIO}" --output-dir "${MISSIONS_DIR}"
fi

for swarm in alpha bravo; do
    for did in 1 2 3 4 5; do
        f="${SCEN_DIR}/${swarm}_${did}.json"
        # Missing file = a vanished drone in this scenario → skip, don't fail.
        if [ ! -f "${f}" ]; then
            echo "[submit-all] ${swarm}/${did}: no cells file (dropout) — skipping"
            continue
        fi
        echo "[submit-all] ── ${swarm} drone ${did} ──"
        # Retry once: the 5th drone's L2→L1 syscall can revert on a fee-estimate
        # race; a re-run clears it (the reverted tx changed no state).
        if ! ./scripts/submit-telemetry.sh "${swarm}" "${did}" "${f}"; then
            echo "[submit-all] ${swarm}/${did} failed — retrying once..."
            ./scripts/submit-telemetry.sh "${swarm}" "${did}" "${f}" \
                || echo "[submit-all] ${swarm}/${did} FAILED again — fix manually"
        fi
    done
done

echo "[submit-all] done"
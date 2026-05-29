#!/usr/bin/env bash
# =============================================================================
# run-all-scenarios.sh — run every scenario and emit a pass/fail summary.
#
# Calls scripts/run-scenario.sh for each scenario in turn. Continues on
# failure so you get a complete picture rather than stopping at the first
# regression.
#
# Exit code is 0 iff every scenario passed.
# =============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
SCENARIOS=(
    both-safe
    both-unsafe
    mixed
    alpha-dropout-vanish
    alpha-dropout-midflight
    dual-dropout
)

PASSED=()
FAILED=()

for s in "${SCENARIOS[@]}"; do
    echo
    echo "███████████████████████████████████████████████████████████████"
    echo "  Running: ${s}"
    echo "███████████████████████████████████████████████████████████████"
    if "${SCRIPT_DIR}/run-scenario.sh" "${s}"; then
        PASSED+=("${s}")
    else
        FAILED+=("${s}")
    fi
done

echo
echo "==============================================================="
echo "  SUMMARY"
echo "==============================================================="
printf "  PASSED (%d):\n" "${#PASSED[@]}"
for s in "${PASSED[@]:-}"; do printf "    [OK] %s\n" "${s}"; done
printf "  FAILED (%d):\n" "${#FAILED[@]}"
for s in "${FAILED[@]:-}"; do printf "    [FAIL] %s\n" "${s}"; done
echo "==============================================================="

if [ ${#FAILED[@]} -eq 0 ]; then
    exit 0
else
    exit 1
fi

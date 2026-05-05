#!/usr/bin/env bash
# =============================================================================
# prove-from-l2.sh — full L2-to-L1 STARK proof with continuity binding.
#
# This is the "the proof comes from the L2 block" flow. It:
#
#   1. Picks a fresh (mid, drone_id) on convoy_protocol so we don't collide
#      with state from earlier smoke tests.
#   2. Submits N telemetry cells via submit_telemetry on Madara (one tx
#      per cell — Madara block_time is 30 s so this takes a few minutes).
#   3. Runs safe_area_verify.cairo locally with expected_commitment=0 to
#      learn what Poseidon hash chain the drone should publish.
#   4. Publishes that commitment on L2 via submit_sweep_commitment.
#      L2 storage now holds (cells, commitment) — both signed by the
#      drone's Madara account.
#   5. fetch_l2_cells.py reads cells + commitment back from Pathfinder and
#      writes /proofs/l2_input.json.
#   6. Re-runs the prover-api with l2_input.json — this time the cairo
#      program asserts its computed commitment equals expected_commitment
#      (so a tampered cell array fails the trace).
#   7. Stone produces the STARK proof; submit_proof_l1 lands the fact on
#      L1 with the same commitment that's in L2 storage.
#
# After this runs, the cryptographic chain is:
#   L2 tx (drone-signed) → cells in convoy_protocol storage → L2 sealed
#   commitment → safe_area_verify proof bound to it → L1 fact recording
#   the same commitment. Anyone can read L2 storage and check.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/.tmp-l2/convoy_l2.env"   # provides CONVOY_PROTOCOL_ADDR + ACCOUNT_ADDR

CONTRACT="${CONVOY_PROTOCOL_ADDR}"
RPC="http://convoy-pathfinder:9545/rpc/v0_8"
MADARA_RPC="http://convoy-madara:9944/rpc/v0.8.1"

# Fresh slot — pick a (mid, drone_id) the contract has never seen
MID="${MID:-100}"
DRONE_ID="${DRONE_ID:-2}"     # bravo lane

# Compact 8-cell sweep so the demo runs in a few minutes (8 * 30s = 4 min
# of L2 sealing instead of 48 * 30s = 24 min). All thresholds satisfied.
AREA_TOTAL_CELLS=8
COVERAGE_MIN=950
P_MIN=7000
TIME_WINDOW=360
TS_START=1700000000

CELLS_X=(1 2 3 4 5 6 7 0)
CELLS_Y=(0 0 0 0 0 0 0 1)
CELLS_P=(1100 1500 1800 2100 2400 2700 3000 3300)
CELLS_TS=(1700000010 1700000020 1700000030 1700000040 1700000050 1700000060 1700000070 1700000080)

starkli() {
    MSYS_NO_PATHCONV=1 docker run --rm \
        --network convoy-l1 \
        -v "${REPO_ROOT}:/work" \
        -e STARKNET_RPC="${MADARA_RPC}" \
        -e STARKNET_ACCOUNT=/work/.tmp-l2/account.json \
        -e STARKNET_KEYSTORE=/work/.tmp-l2/keystore.json \
        -e STARKNET_KEYSTORE_PASSWORD=convoy \
        -w /work \
        convoy-cairo-builder:latest \
        starkli "$@"
}

starkli_pf() {
    # Same as starkli, but pointing at Pathfinder for read-only calls.
    MSYS_NO_PATHCONV=1 docker run --rm \
        --network convoy-l1 \
        -v "${REPO_ROOT}:/work" \
        -w /work \
        convoy-cairo-builder:latest \
        starkli "$@" --rpc "${RPC}"
}

echo "================================================================"
echo "  prove-from-l2.sh"
echo "  contract:  ${CONTRACT}"
echo "  (mid, drone_id) = (${MID}, ${DRONE_ID})"
echo "  cells:     ${#CELLS_X[@]}"
echo "================================================================"

# ── 1. Confirm slot is empty (no prior commitment) ───────────────────
existing=$(starkli_pf call "${CONTRACT}" get_commitment "${MID}" "${DRONE_ID}" 2>/dev/null \
    | tr -d ' \n[]"' | head -c 66)
if [ -n "${existing}" ] && [ "${existing}" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
    echo "[!] slot already has a commitment ${existing} — pick a different MID/DRONE_ID"
    exit 2
fi

# ── 2. Submit cells ──────────────────────────────────────────────────
echo
echo "── Step 1/6: submit ${#CELLS_X[@]} telemetry cells to L2 ────────"
for i in "${!CELLS_X[@]}"; do
    echo "[L2] submit_telemetry(mid=${MID}, drone=${DRONE_ID}, x=${CELLS_X[$i]}, y=${CELLS_Y[$i]}, p=${CELLS_P[$i]}, ts=${CELLS_TS[$i]})"
    starkli invoke "${CONTRACT}" submit_telemetry \
        "${MID}" "${DRONE_ID}" "${CELLS_X[$i]}" "${CELLS_Y[$i]}" "${CELLS_P[$i]}" "${CELLS_TS[$i]}" \
        --watch 2>&1 | tail -2
done

# ── 3. Build a "no binding" input.json so cairo-run prints the commitment
echo
echo "── Step 2/6: compute the Poseidon commitment locally via cairo-run ──"
INPUT_NOBIND="$(mktemp /tmp/l2_input_nobind.XXXXXX.json)"
python3 - <<EOF > "${INPUT_NOBIND}"
import json
print(json.dumps({
    "mid":              ${MID},
    "drone_id":         ${DRONE_ID},
    "area_total_cells": ${AREA_TOTAL_CELLS},
    "coverage_min":     ${COVERAGE_MIN},
    "p_min":            ${P_MIN},
    "time_window":      ${TIME_WINDOW},
    "ts_start":         ${TS_START},
    "n_cells":          ${#CELLS_X[@]},
    "expected_commitment": 0,
    "cells_x":          [${CELLS_X[@]}],
    "cells_y":          [${CELLS_Y[@]}],
    "cells_p_contact":  [${CELLS_P[@]}],
    "cells_ts":         [${CELLS_TS[@]}],
}))
EOF

# Run the prover container's cairo-compile + cairo-run to get the commitment
docker cp "${INPUT_NOBIND}" convoy-prover-api:/proofs/_nobind_input.json
docker exec convoy-prover-api bash -c "
cairo-compile /app/safe_area_verify.cairo --output /proofs/safe_area_verify.json --proof_mode > /dev/null 2>&1
cairo-run --program=/proofs/safe_area_verify.json --layout=starknet_with_keccak \
    --program_input=/proofs/_nobind_input.json --print_output \
    --proof_mode --trace_file=/tmp/_t --memory_file=/tmp/_m \
    --air_public_input=/tmp/_pub.json --air_private_input=/tmp/_priv.json \
    2>/dev/null | grep -A 100 'Program output' | tail -10
" | tee /tmp/cairo_local_run.txt

# Extract the 6th output (commitment)
COMMITMENT=$(grep -E '^\s+(-?[0-9]+)' /tmp/cairo_local_run.txt | tail -1 | awk '{print $1}')
if [ -z "${COMMITMENT}" ]; then
    echo "[!] failed to extract commitment from cairo-run output"
    exit 3
fi

# Cairo prints felts as signed numbers; convert to unsigned felt252
COMMITMENT_HEX=$(python3 -c "
v = int('${COMMITMENT}')
P = 3618502788666131213697322783095070105623107215331596699973092056135872020481
v %= P
print(hex(v))
")
echo "[L2] commitment = ${COMMITMENT_HEX}"

# ── 4. Publish commitment on L2 ─────────────────────────────────────
echo
echo "── Step 3/6: submit_sweep_commitment(${MID}, ${DRONE_ID}, ${COMMITMENT_HEX}) ──"
starkli invoke "${CONTRACT}" submit_sweep_commitment \
    "${MID}" "${DRONE_ID}" "${COMMITMENT_HEX}" \
    --watch 2>&1 | tail -3

# ── 5. Fetch from L2 to build the bound input.json ──────────────────
echo
echo "── Step 4/6: fetch cells + commitment from L2 via Pathfinder ──"
docker exec convoy-prover-api python3 /app/fetch_l2_cells.py \
    --rpc "${RPC}" \
    --contract "${CONTRACT}" \
    --mid "${MID}" --drone-id "${DRONE_ID}" \
    --coverage-min "${COVERAGE_MIN}" --p-min "${P_MIN}" --time-window "${TIME_WINDOW}" \
    --area-total-cells "${AREA_TOTAL_CELLS}" --ts-start "${TS_START}" \
    --output /proofs/l2_input.json

# ── 6. Run the prover with the L2-bound input ───────────────────────
echo
echo "── Step 5/6: trigger Stone prover with L2-bound input ──"
docker exec convoy-prover-api bash -c "
cp /proofs/l2_input.json /proofs/program_input.json
echo l2-bound > /proofs/prove_trigger
"
echo "[wait] proving (~1-3 min)..."
until docker exec convoy-prover-api test -f /proofs/prove_result 2>&1 ; do
    sleep 8
done
docker exec convoy-prover-api rm -f /proofs/prove_result

echo
echo "── Step 6/6: verify L1 fact's commitment == L2 storage's commitment ──"
docker exec convoy-prover-api bash -c "
cat /proofs/submit_log.json | python3 -c '
import sys, json
log = json.load(sys.stdin)
on_chain_commitment = int(log[\"publicOutputs\"][\"commitment\"], 16)
print(f\"L1 fact commitment (from registerSafeProof): {hex(on_chain_commitment)}\")
print(f\"L2 storage commitment (from convoy_protocol): ${COMMITMENT_HEX}\")
print(f\"Match: {hex(on_chain_commitment) == \\\"${COMMITMENT_HEX}\\\"}\")
print()
print(\"L1 tx hash :\", log[\"txHash\"])
print(\"L1 factHash:\", log[\"factHash\"])
'
"

echo
echo "================================================================"
echo "  PROOF FROM L2 — COMPLETE"
echo "  L2 contract storage and L1 Verifier record now bound by commitment."
echo "================================================================"

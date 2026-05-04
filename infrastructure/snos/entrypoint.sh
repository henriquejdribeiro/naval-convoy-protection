#!/bin/bash
# =============================================================================
# infrastructure/snos/entrypoint.sh — SNOS replay loop
#
# Watches Pathfinder for new sealed L2 blocks, replays each in the Cairo VM
# via SNOS, and writes the resulting PIE to /output. The prover-api picks
# up the PIE and runs cpu_air_prover on it.
#
# Phase 3.c only — gated behind the `proving` profile in docker-compose.l2.yml.
# Until Madara + Pathfinder are wired in (Phase 3.b), this script doesn't run.
#
# Adapted from verifiable_grid/infrastructure/snos/entrypoint.sh.
# =============================================================================
set -e

OUTPUT_DIR="${SNOS_OUTPUT_DIR:-/output}"
RPC="${SNOS_RPC_PROVIDER:-http://convoy-pathfinder:9545}"
GATEWAY="${SNOS_GATEWAY_URL:-http://convoy-madara:8080}"
START_BLOCK="${SNOS_BLOCK_NUMBER:-1}"

mkdir -p "${OUTPUT_DIR}"

echo "[snos] waiting for Pathfinder at ${RPC}"
until curl -fs "${RPC}" >/dev/null 2>&1; do sleep 5; done
echo "[snos] Pathfinder reachable"

# Activate the cairo-lang venv installed in the Dockerfile
. /app/snos/.venv/bin/activate
export PATH="/app/snos/venv/bin:/app/snos/.venv/bin:${PATH}"

cd /app/snos

replay_block() {
    local BLOCK="$1"
    echo "[snos] replaying block ${BLOCK}"
    cargo run --release -p rpc-replay -- \
        --rpc-provider "${RPC}" \
        --block-number "${BLOCK}" \
        --output-dir "${OUTPUT_DIR}/block_${BLOCK}" \
        2>&1 | tee "${OUTPUT_DIR}/block_${BLOCK}.log"
    echo "[snos] block ${BLOCK} replayed; PIE at ${OUTPUT_DIR}/block_${BLOCK}/cairo_pie.zip"
}

# Initial run — replay the configured start block
replay_block "${START_BLOCK}" || echo "[snos] initial replay failed (block may not exist yet)"

# Watch loop — poll Pathfinder for new finalised blocks
LAST_PROVEN="${START_BLOCK}"
while true; do
    HEAD=$(curl -fs "${RPC}" -X POST -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"starknet_blockNumber","params":[],"id":1}' \
        | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', 0))" 2>/dev/null || echo 0)
    if [ "${HEAD}" -gt "${LAST_PROVEN}" ]; then
        NEXT=$((LAST_PROVEN + 1))
        echo "[snos] Pathfinder head=${HEAD}, replaying block ${NEXT}"
        replay_block "${NEXT}" && LAST_PROVEN="${NEXT}"
    fi
    sleep 30
done

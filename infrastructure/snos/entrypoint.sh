#!/bin/bash
# =============================================================================
# infrastructure/snos/entrypoint.sh — SNOS replay loop (single-block mode)
#
# rpc-replay v0.14.1-alpha.0 has two modes:
#   1. Sequential — infinite loop from --start-block, advancing forever.
#   2. JSON-file — replay just the blocks listed in a JSON manifest.
#
# We use JSON-file mode because we want to prove ONE specific block (the
# one where the drone's submit_sweep_commitment landed). The watch loop
# below regenerates the manifest each time a trigger file is written.
#
# Output layout (/output):
#   block_<N>/cairo_pie_blocks_<N>.zip    the PIE Stone consumes
#   logs/block_<N>.log                    rpc-replay stdout/stderr
#   logs/error_blocks_<N>.txt             rpc-replay error report on failure
# =============================================================================
set -e

OUTPUT_DIR="${SNOS_OUTPUT_DIR:-/output}"
RPC="${SNOS_RPC_URL:-http://convoy-pathfinder:9545}"
START_BLOCK="${SNOS_BLOCK_NUMBER:-1}"
CHAIN="${SNOS_CHAIN:-convoy_devnet}"

mkdir -p "${OUTPUT_DIR}/logs"

echo "[snos] config:"
echo "    rpc       : ${RPC}"
echo "    chain     : ${CHAIN}"
echo "    start_blk : ${START_BLOCK}"
echo "    output    : ${OUTPUT_DIR}"

echo "[snos] waiting for Pathfinder at ${RPC}/rpc/v0_10"
until curl -fs -X POST "${RPC}/rpc/v0_10" \
        -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"starknet_blockNumber","params":[],"id":1}' \
        >/dev/null 2>&1; do
    sleep 5
done
echo "[snos] Pathfinder /rpc/v0_10 reachable"

# Activate the cairo-lang venv that vg-snos:latest pre-installed
. /app/snos/.venv/bin/activate
export PATH="/app/snos/venv/bin:/app/snos/.venv/bin:${PATH}"

REPLAY_BIN=/app/snos/target/release/rpc-replay

replay_block() {
    local BLOCK="$1"
    local PIE_PATH="${OUTPUT_DIR}/cairo_pie_block_${BLOCK}.zip"
    local MANIFEST="${OUTPUT_DIR}/logs/manifest_${BLOCK}.json"

    # Single-block JSON manifest (rpc-replay's "FromJson" mode runs the
    # listed blocks and stops; the alternative Sequential mode loops
    # forever, which we don't want.)
    cat > "${MANIFEST}" <<EOF
{ "error_blocks": [${BLOCK}], "total_count": 1 }
EOF

    echo "[snos] replaying block ${BLOCK} → ${PIE_PATH}"
    # Despite the name, --output-dir is the OUTPUT FILE path (rpc-replay
    # internally calls cairo_pie.write_zip_file(Path::new(output_dir)),
    # which means we must give it a .zip path, not a directory).
    "${REPLAY_BIN}" \
        --rpc-url    "${RPC}" \
        --chain      "${CHAIN}" \
        --json-file  "${MANIFEST}" \
        --output-dir "${PIE_PATH}" \
        --log-dir    "${OUTPUT_DIR}/logs" \
        2>&1 | tee "${OUTPUT_DIR}/logs/block_${BLOCK}.log"

    if [ -f "${PIE_PATH}" ]; then
        echo "[snos] block ${BLOCK} replayed — PIE: ${PIE_PATH} ($(stat -c%s "${PIE_PATH}") bytes)"
        return 0
    else
        echo "[snos] block ${BLOCK} produced no PIE; see ${OUTPUT_DIR}/logs/block_${BLOCK}.log"
        return 1
    fi
}

# Initial replay of the configured block
replay_block "${START_BLOCK}" || \
    echo "[snos] initial replay failed; container stays alive for triggers"

echo
echo "[snos] watch loop — re-prove a block via:"
echo "    docker exec convoy-snos sh -c 'echo BLOCK > /output/replay_trigger'"

while true; do
    if [ -f "${OUTPUT_DIR}/replay_trigger" ]; then
        BLOCK=$(cat "${OUTPUT_DIR}/replay_trigger" 2>/dev/null || true)
        rm -f "${OUTPUT_DIR}/replay_trigger"
        if [ -n "${BLOCK}" ]; then
            replay_block "${BLOCK}" || echo "[snos] replay failed for block ${BLOCK}"
            echo "DONE" > "${OUTPUT_DIR}/replay_result_${BLOCK}"
        fi
    fi
    sleep 3
done

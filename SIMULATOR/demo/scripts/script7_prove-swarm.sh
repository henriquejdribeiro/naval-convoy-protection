#!/usr/bin/env bash
# =============================================================================
# script7_prove-swarm.sh <swarm> — per-swarm coverage proof.
#
# The swarm leader (a1 / b1, container convoy-prover-api-<swarm>) fetches its 5
# drones' signed telemetry from L2, produces ONE STARK proof over the swarm with
# safe_area_verify_<swarm>.cairo, and the swarm's relay ship (alpha→ship F,
# bravo→ship B, whose key is already in the prover container) submits the proof
# to the L1 Verifier via convoy-submitter → registerSwarmProof.
#
# Run AFTER all 5 drones of the swarm have submitted signed telemetry
# (5× script6_submit-telemetry.sh <swarm> <1..5> <cells.json>).
#
# Usage:
#   ./SIMULATOR/demo/scripts/script7_prove-swarm.sh alpha
#   ./SIMULATOR/demo/scripts/script7_prove-swarm.sh bravo
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
RPC_VERSION="0.8.1"

SWARM="${1:?usage: $0 <alpha|bravo>}"
case "${SWARM}" in alpha|bravo) ;; *) echo "swarm must be alpha|bravo"; exit 2;; esac

MISSION_ID=$( [ "${SWARM}" = "alpha" ] && echo 1 || echo 2 )
PROVER="convoy-prover-api-${SWARM}"
RPC_URL="http://convoy-madara-${SWARM}:9944/rpc/v${RPC_VERSION}"
CONV_ENV="${REPO_ROOT}/SIMULATOR/demo/.tmp-l2/convoy_l2_${SWARM}.env"
UP="${SWARM^^}"

docker ps --format '{{.Names}}' | grep -qx "${PROVER}" \
    || { echo "prover ${PROVER} not running — bring the stack up first"; exit 1; }
[ -f "${CONV_ENV}" ] || { echo "missing ${CONV_ENV}"; exit 1; }
CONV_ADDR=$(grep "^CONVOY_PROTOCOL_ADDR_${UP}=" "${CONV_ENV}" | cut -d= -f2)
[ -z "${CONV_ADDR}" ] && { echo "no convoy_protocol address in ${CONV_ENV}"; exit 1; }

echo "[prove/${SWARM}] fetch 5-drone swarm telemetry from L2 (${CONV_ADDR})"
MSYS_NO_PATHCONV=1 docker exec "${PROVER}" python3 /app/fetch_l2_swarm.py \
    --rpc       "${RPC_URL}" \
    --contract  "${CONV_ADDR}" \
    --mission_id "${MISSION_ID}" \
    --output    /proofs/program_input.json

echo "[prove/${SWARM}] trigger swarm proof + L1 submission on ${PROVER}"
MSYS_NO_PATHCONV=1 docker exec "${PROVER}" sh -c "echo ${SWARM} > /proofs/prove_trigger"

echo "[prove/${SWARM}] proving started — follow it with:"
echo "    docker logs -f ${PROVER}"

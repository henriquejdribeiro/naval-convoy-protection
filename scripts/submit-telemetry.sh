#!/usr/bin/env bash
# =============================================================================
# submit-telemetry.sh — fire `convoy_protocol.submit_telemetry` as one drone.
#
# Usage:
#   ./scripts/submit-telemetry.sh <swarm> <drone_id> <cells.json>
#
# Args:
#   swarm     alpha | bravo
#   drone_id  1..5
#   cells.json  JSON file with the per-cell arrays (see format below)
#
# cells.json format:
#   {
#     "cells_x":         [6, 6, 6, 7, 7, ...],
#     "cells_y":         [0, 1, 2, 0, 1, ...],
#     "cells_p_contact": [4500, 5000, 4200, ...],
#     "cells_ts":        [1700000340, 1700000346, ...]
#   }
#
#   All four arrays MUST have the same length. Sample inputs live in
#   .tmp-l2/missions/<scenario>/ (produced by scripts/generate-mission.py
#   when that's rewritten — for now hand-write them or use the example
#   below).
#
# What happens:
#   1. Loads the drone's keystore + account file (written by
#      scripts/generate-drone-accounts.sh into .tmp-l2/drones/<swarm>/<i>/)
#   2. Reads convoy_protocol address for that swarm from
#      .tmp-l2/convoy_l2_<swarm>.env
#   3. Serialises the 4 arrays into starkli calldata
#   4. Fires `starkli invoke <conv_addr> submit_telemetry mission_id drone_id
#      <cells_x array> <cells_y array> <cells_p_contact array> <cells_ts array>`
#      signed with the drone's key.
#
# After the tx confirms, the contract has:
#   - Stored the drone's verdict (SAFE if all 4 predicates passed)
#   - Recorded n_cells and the fail_reason (if any) under
#     (mission_id, drone_id)
#   - Emitted TelemetrySubmitted event
#   - If this was the 5th drone to land SAFE in the mission, also emitted
#     send_message_to_l1_syscall → MissionSafe event
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RPC_VERSION="0.8.1"
KEYSTORE_PWD="convoy"

# ── Arg parsing ─────────────────────────────────────────────────────────────
if [ $# -lt 3 ]; then
    echo "usage: $0 <swarm> <drone_id> <cells.json>" >&2
    exit 2
fi
SWARM="$1"
DRONE_ID="$2"
CELLS_JSON="$3"

case "${SWARM}" in alpha|bravo) ;; *) echo "swarm must be alpha|bravo"; exit 2;; esac
if ! [[ "${DRONE_ID}" =~ ^[1-5]$ ]]; then
    echo "drone_id must be 1..5" >&2; exit 2
fi
[ -f "${CELLS_JSON}" ] || { echo "missing cells file: ${CELLS_JSON}"; exit 2; }

MISSION_ID=$( [ "${SWARM}" = "alpha" ] && echo 1 || echo 2 )
MADARA_HOST="convoy-madara-${SWARM}"
RPC_URL="http://${MADARA_HOST}:9944/rpc/v${RPC_VERSION}"
CONV_ENV="${REPO_ROOT}/.tmp-l2/convoy_l2_${SWARM}.env"
DRONE_KS=".tmp-l2/drones/${SWARM}/${DRONE_ID}/keystore.json"
DRONE_ACC=".tmp-l2/drones/${SWARM}/${DRONE_ID}/account.json"

[ -f "${REPO_ROOT}/${DRONE_KS}" ]  || { echo "missing keystore: ${DRONE_KS}"; exit 1; }
[ -f "${REPO_ROOT}/${DRONE_ACC}" ] || { echo "missing account file: ${DRONE_ACC}"; exit 1; }
[ -f "${CONV_ENV}" ]                || { echo "missing ${CONV_ENV}"; exit 1; }

UP="${SWARM^^}"
CONV_ADDR=$(grep "^CONVOY_PROTOCOL_ADDR_${UP}=" "${CONV_ENV}" | cut -d= -f2)
[ -z "${CONV_ADDR}" ] && { echo "no convoy_protocol address"; exit 1; }

# ── Serialise the 4 arrays into starkli's <len> e1 e2 … en format ──────────
# We hand the JSON to python inside cairo-builder (avoids depending on
# host-side jq).
CALLDATA=$(MSYS_NO_PATHCONV=1 docker run --rm -i \
    -v "${REPO_ROOT}:/work" -w /work \
    convoy-cairo-builder \
    python3 - <<EOF
import json, sys
d = json.load(open("${CELLS_JSON}"))
fields = ["cells_x", "cells_y", "cells_p_contact", "cells_ts"]
n = len(d[fields[0]])
for f in fields:
    assert len(d[f]) == n, f"array length mismatch on {f}: {len(d[f])} vs {n}"
parts = []
for f in fields:
    parts.append(str(n))
    parts.extend(str(x) for x in d[f])
print(" ".join(parts))
EOF
)

CALL_ARGS="${MISSION_ID} ${DRONE_ID} ${CALLDATA}"

echo
echo "[submit/${SWARM}/${DRONE_ID}] submitting telemetry"
echo "  mission_id:  ${MISSION_ID}"
echo "  drone_id:    ${DRONE_ID}"
echo "  contract:    ${CONV_ADDR}"
echo "  RPC:         ${RPC_URL}"
echo "  cells_file:  ${CELLS_JSON}"
echo

MSYS_NO_PATHCONV=1 docker run --rm \
    --network convoy-l1 \
    -v "${REPO_ROOT}:/work" -w /work \
    -e STARKNET_RPC="${RPC_URL}" \
    -e STARKNET_ACCOUNT="/work/${DRONE_ACC}" \
    -e STARKNET_KEYSTORE="/work/${DRONE_KS}" \
    -e STARKNET_KEYSTORE_PASSWORD="${KEYSTORE_PWD}" \
    convoy-cairo-builder \
    starkli invoke "${CONV_ADDR}" submit_telemetry ${CALL_ARGS} \
        --rpc "${RPC_URL}" \
        --watch 2>&1 | tail -10

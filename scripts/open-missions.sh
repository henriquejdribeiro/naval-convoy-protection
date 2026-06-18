#!/usr/bin/env bash
# =============================================================================
# open-missions.sh — register both swarms' missions on their L2 contracts.
#
# Calls `convoy_protocol.open_mission_local(spec, drone_addresses)` on each
# Madara, with:
#   - spec = the canonical MissionSpec for that swarm (Alpha = 5×3 strips,
#     Bravo = 5×4 strips, both 8 cells tall, same thresholds)
#   - drone_addresses = the 5 OZ account addresses written by
#     scripts/generate-drone-accounts.sh into .tmp-l2/drones-{swarm}.env
#
# After this runs, each drone account is registered as the authorised
# caller for (mission_id, drone_id), and submit_telemetry will accept its
# signed invokes.
#
# Why open_mission_local (not the #[l1_handler] open_mission)?
#   Both Madaras run with --l1-sync-disabled, so the L1→L2 message bridge
#   isn't active. The contract exposes open_mission_local as a dev-mode
#   companion that takes the same args but doesn't require an L1 sender.
#   When the production L1 bridge is wired, switch back to the l1_handler
#   path and drop this script.
#
# Prereqs:
#   - convoy_protocol deployed on both Madaras (scripts/deploy-l2.sh)
#   - 5 OZ drone accounts per swarm (scripts/generate-drone-accounts.sh)
#   - .tmp-l2/convoy_l2_{alpha,bravo}.env present
#   - .tmp-l2/drones-{alpha,bravo}.env present
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RPC_VERSION="0.8.1"
KEYSTORE_PWD="convoy"

# Account #1 (Madara devnet pre-funded) issues the open_mission_local invoke.
DEPLOYER_DIR_TEMPLATE=".tmp-l2/drones/{SWARM}/_deployer"

# Mission spec — identical thresholds for both swarms; geometry differs.
# Field order must match cairo/convoy_protocol/src/lib.cairo's MissionSpec.
AREA_HASH="0x6172656172656172656172656172656172656172656172656172656172656131"

# Per-swarm spec parameters
declare -A SPEC_ZONE_W=( [alpha]=15 [bravo]=20 )
declare -A SPEC_STRIP_WIDTH=( [alpha]=3 [bravo]=4 )
declare -A MISSION_ID=( [alpha]=1 [bravo]=2 )
declare -A SWARM_ID=( [alpha]=1 [bravo]=2 )

# Shared thresholds
ZONE_X=0
ZONE_Y=0
ZONE_H=8
N_DRONES=5
COVERAGE_MIN=950      # 950 / 1000 = 95%
P_MIN=7000            # 7000 / 10000 = 70% basis points
TIME_WINDOW=360       # seconds
TS_START=$(date +%s)  # use wall clock now; drones' cell ts must be ≥ this

open_mission_for_swarm() {
    local swarm="$1"
    local madara_host="convoy-madara-${swarm}"
    local rpc_url="http://${madara_host}:9944/rpc/v${RPC_VERSION}"
    local conv_env="${REPO_ROOT}/.tmp-l2/convoy_l2_${swarm}.env"
    local drone_env="${REPO_ROOT}/.tmp-l2/drones-${swarm}.env"

    [ -f "${conv_env}" ]  || { echo "[open/${swarm}] missing ${conv_env}";  return 1; }
    [ -f "${drone_env}" ] || { echo "[open/${swarm}] missing ${drone_env}"; return 1; }

    # convoy_protocol contract address for this swarm
    local up="${swarm^^}"
    local conv_addr
    conv_addr=$(grep "^CONVOY_PROTOCOL_ADDR_${up}=" "${conv_env}" | cut -d= -f2)
    [ -z "${conv_addr}" ] && { echo "[open/${swarm}] no contract address"; return 1; }

    # 5 drone account addresses, in order
    local drones=()
    for did in 1 2 3 4 5; do
        local addr
        addr=$(grep "^${up}_DRONE_${did}_ADDR=" "${drone_env}" | cut -d= -f2)
        [ -z "${addr}" ] && { echo "[open/${swarm}] no addr for drone ${did}"; return 1; }
        drones+=("${addr}")
    done

    # Build the calldata in the order expected by IConvoyProtocol.open_mission_local
    #
    #   spec.mission_id      felt252      uint
    #   spec.swarm_id        felt252      uint
    #   spec.zone_x          u32          uint
    #   spec.zone_y          u32          uint
    #   spec.zone_w          u32          uint
    #   spec.zone_h          u32          uint
    #   spec.n_drones        u8           uint
    #   spec.strip_width     u32          uint
    #   spec.coverage_min    u16          uint
    #   spec.p_min           u16          uint
    #   spec.time_window     u64          uint
    #   spec.ts_start        u64          uint
    #   drone_addresses      Array<CA>    <len> <e1> <e2> <e3> <e4> <e5>
    local calldata=(
        "${MISSION_ID[$swarm]}"
        "${SWARM_ID[$swarm]}"
        "${ZONE_X}"
        "${ZONE_Y}"
        "${SPEC_ZONE_W[$swarm]}"
        "${ZONE_H}"
        "${N_DRONES}"
        "${SPEC_STRIP_WIDTH[$swarm]}"
        "${COVERAGE_MIN}"
        "${P_MIN}"
        "${TIME_WINDOW}"
        "${TS_START}"
        "5"                              # array length
        "${drones[0]}" "${drones[1]}" "${drones[2]}" "${drones[3]}" "${drones[4]}"
    )

    echo
    echo "[open/${swarm}] opening mission ${MISSION_ID[$swarm]} on ${madara_host}"
    echo "[open/${swarm}]   convoy_protocol: ${conv_addr}"
    echo "[open/${swarm}]   zone: ${SPEC_ZONE_W[$swarm]}×${ZONE_H}, strip_width=${SPEC_STRIP_WIDTH[$swarm]}"
    echo "[open/${swarm}]   drones: ${drones[*]}"

    MSYS_NO_PATHCONV=1 docker run --rm \
        --network convoy-l1 \
        -v "${REPO_ROOT}:/work" -w /work \
        -e STARKNET_RPC="${rpc_url}" \
        -e STARKNET_ACCOUNT="/work/.tmp-l2/drones/${swarm}/_deployer/account.json" \
        -e STARKNET_KEYSTORE="/work/.tmp-l2/drones/${swarm}/_deployer/keystore.json" \
        -e STARKNET_KEYSTORE_PASSWORD="${KEYSTORE_PWD}" \
        convoy-cairo-builder \
        starkli invoke "${conv_addr}" open_mission_local "${calldata[@]}" \
            --rpc "${rpc_url}" \
            --watch 2>&1 | tail -8

    echo "[open/${swarm}] OK"
}

# ── Arg parsing ─────────────────────────────────────────────────────────────
SWARM_FILTER="both"
while [ $# -gt 0 ]; do
    case "$1" in
        --swarm) SWARM_FILTER="$2"; shift 2 ;;
        --swarm=*) SWARM_FILTER="${1#--swarm=}"; shift ;;
        *) echo "[open] unknown arg: $1"; exit 2 ;;
    esac
done

case "${SWARM_FILTER}" in
    alpha) open_mission_for_swarm alpha ;;
    bravo) open_mission_for_swarm bravo ;;
    both)
        open_mission_for_swarm alpha
        open_mission_for_swarm bravo
        ;;
    *) echo "[open] --swarm must be alpha | bravo | both"; exit 2 ;;
esac

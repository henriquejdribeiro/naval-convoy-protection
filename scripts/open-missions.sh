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


# Strict mode — fail fast and loud:
#   -e           exit immediately if any command returns non-zero
#   -u           treat use of an unset variable as an error (catches typos)
#   -o pipefail  a pipeline fails if ANY stage fails, not just the last one
set -euo pipefail

# Absolute path to the repo root (one level up from this script in scripts/).
# Kept absolute — passed to `docker run -v "${REPO_ROOT}:/work"` (Docker needs
# an absolute host path) and used to read the .tmp-l2/*.env files written by
# deploy-l2.sh and generate-drone-accounts.sh.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Starknet JSON-RPC spec version. Madara serves /rpc/v0.7.1, v0.8.1, v0.9.0;
# starkli targets 0.8.x, so we hit the /rpc/v0.8.1 endpoint.
RPC_VERSION="0.8.1"

# Keystore password to DECRYPT the signing key. open-missions calls
# open_mission_local on L2, signed via starkli — so it needs to unlock a
# keystore, hence this password (the dev constant used across all keystores).
KEYSTORE_PWD="convoy"

# Account #1 (Madara devnet pre-funded) issues the open_mission_local invoke.
DEPLOYER_DIR_TEMPLATE=".tmp-l2/drones/{SWARM}/_deployer"

# ── Mission spec ────────────────────────────────────────────────────────────
# DUPLICATE of register-missions.sh's spec, ON PURPOSE: this is the L2 copy.
# register-missions wrote the spec to L1 (Registry); this writes it to L2
# (convoy_protocol via open_mission_local). They MUST match exactly — and must
# match generate-mission.py too — or L1/L2 disagree or telemetry fails the
# predicates. In a working bridge the L1→L2 message would carry the spec and
# this duplication would vanish; it exists only because the bridge is bypassed.
# Field order here must match cairo/convoy_protocol/src/lib.cairo's MissionSpec.
AREA_HASH="0x6172656172656172656172656172656172656172656172656172656172656131"

# Per-swarm values (geometry differs by swarm):
declare -A SPEC_ZONE_W=( [alpha]=15 [bravo]=20 )            # zone width in cells
declare -A SPEC_STRIP_WIDTH=( [alpha]=3 [bravo]=4 )         # per-drone lane width = zone_w / n_drones
declare -A MISSION_ID=( [alpha]=1 [bravo]=2 )               # on-chain mission id
declare -A SWARM_ID=( [alpha]=1 [bravo]=2 )                 # swarm id (L2 spec field; not in the L1 tuple)

# Shared thresholds — identical for both swarms (the SAFE-area rules):
ZONE_X=0              # zone origin x
ZONE_Y=0              # zone origin y
ZONE_H=8              # zone height in cells → each strip is strip_width × 8
N_DRONES=5            # drones per swarm = number of strips
COVERAGE_MIN=950      # min coverage, permille (950/1000 = 95% of strip cells must be swept) → predicate ① Coverage
P_MIN=7000            # detection threshold, basis points (cell p_contact must be < 7000/10000 = 70%) → predicate ② Detection
TIME_WINDOW=360        # seconds; every cell ts must be within [ts_start, ts_start+360] → predicate ③ Time

# Fixed mission start timestamp — matches generate-mission.py's TS_START so
# its generated cells_ts values fall within [ts_start, ts_start + time_window]
# and satisfy predicate ③ (Time). Set to 2023-11-14 22:13:20 UTC.
TS_START=1700000000

# Open one swarm's mission on L2 — the BYPASS for the broken L1→L2 bridge.
# In production, register-missions' Registry.deploy → sendMessageToL2 would
# trigger the #[l1_handler] open_mission automatically (carrying this spec,
# validated as coming from the commander's Registry). Since Madara doesn't
# consume that message from the barebones stub, we call open_mission_local
# directly here instead.
open_mission_for_swarm() {

    # Target the swarm's MADARA (L2) RPC — this is an L2 script (cf. register
    # which used ship-a/L1).
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

    # Invoke open_mission_local on L2, signed by the DEPLOYER (account #1) — NOT
    # the commander. open_mission_local is the dev door: callable directly, with
    # NO L1-sender validation, so it loses the commander-authority check that the
    # production open_mission (#[l1_handler]) enforces. Dev-only; remove for prod.
    # After this, the mission exists on L2 + drones are registered → submit_telemetry works.
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

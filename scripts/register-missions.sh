#!/usr/bin/env bash
# =============================================================================
# register-missions.sh — anchor mission deployment on L1 + dispatch L1→L2
#                        open_mission message via StarknetCoreStub.
#
# For each swarm:
#   1. Reads convoy_protocol L2 address from .tmp-l2/convoy_l2_<swarm>.env
#   2. Reads 5 drone L2 addresses from .tmp-l2/drones-<swarm>.env
#   3. cast send Registry.setConvoyProtocolL2(missionId, l2Addr)
#         signed with the deployer (owner) key
#   4. cast send Registry.deploy(missionId, spec, droneAddresses, tsStart)
#         signed with the commander key
#      → This call ALSO fires StarknetCoreStub.sendMessageToL2(
#            convoy_protocol_l2_addr, OPEN_MISSION_SELECTOR, payload)
#        so the mission is now L1-anchored AND queued for L2 consumption.
#
# Why this is a separate script (not part of docker-compose deploy-l1):
#   Mission deployment needs the L2 convoy_protocol contract addresses
#   and the 5 drone L2 ContractAddresses per swarm. Both come from
#   scripts run AFTER deploy-l1: deploy-l2.sh + generate-drone-accounts.sh.
#   So mission registration moves to its own step that runs late in the
#   bring-up sequence.
#
# Prereqs:
#   - L1 chain up + L1 contracts deployed (docker compose ... deploy-l1)
#   - L2 chains up + convoy_protocol deployed (scripts/deploy-l2.sh)
#   - 5 OZ drone accounts per swarm (scripts/generate-drone-accounts.sh)
#   - deployments/local.env populated with Registry address (or set
#     REGISTRY_ADDR env var explicitly)
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Tunables ────────────────────────────────────────────────────────────────
L1_RPC="${L1_RPC:-http://ship-a:8545}"
DEPLOYER_PK="${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}" # anvil[0]
COMMANDER_PK="${COMMANDER_PK:-0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356}" # anvil[7]
TS_START=1700000000   # matches generate-mission.py + open-missions.sh

# Resolve contract addresses — env vars win, else deployments/local.env, else fail.
REGISTRY_ADDR="${REGISTRY_ADDR:-}"
VERIFIER_ADDR="${VERIFIER_ADDR:-${CONVOY_VERIFIER_ADDR:-}}"
if [ -f "${REPO_ROOT}/deployments/local.env" ]; then
    [ -z "${REGISTRY_ADDR}" ] && REGISTRY_ADDR=$(grep -E "^export REGISTRY_ADDR="        "${REPO_ROOT}/deployments/local.env" | cut -d= -f2 | tr -d ' ')
    [ -z "${VERIFIER_ADDR}" ] && VERIFIER_ADDR=$(grep -E "^export CONVOY_VERIFIER_ADDR=" "${REPO_ROOT}/deployments/local.env" | cut -d= -f2 | tr -d ' ')
fi
[ -z "${REGISTRY_ADDR}" ] && { echo "[register] REGISTRY_ADDR missing"; exit 1; }
[ -z "${VERIFIER_ADDR}" ] && { echo "[register] VERIFIER_ADDR (or CONVOY_VERIFIER_ADDR) missing"; exit 1; }

# Per-swarm geometry — matches the constants generate-mission.py uses.
AREA_HASH="0x6172656172656172656172656172656172656172656172656172656172656131"
declare -A SPEC_ZONE_W=( [alpha]=15 [bravo]=20 )
declare -A SPEC_STRIP_WIDTH=( [alpha]=3 [bravo]=4 )
declare -A MISSION_ID=( [alpha]=1 [bravo]=2 )
SHARED_ZONE_X=0
SHARED_ZONE_Y=0
SHARED_ZONE_H=8
SHARED_N_DRONES=5
SHARED_COVERAGE_MIN=950
SHARED_P_MIN=7000
SHARED_TIME_WINDOW=360

# Run `cast` inside foundry container with the convoy-l1 network so we
# can hit ship-a by hostname. --entrypoint cast bypasses /bin/sh -c
# entirely, so we don't have to escape parens in the MissionSpec tuple.
CAST() {
    MSYS_NO_PATHCONV=1 docker run --rm --network convoy-l1 \
        --entrypoint cast \
        -v "${REPO_ROOT}/contracts:/workspace" -w /workspace \
        ghcr.io/foundry-rs/foundry:latest \
        "$@"
}

register_swarm() {
    local swarm="$1"
    local up="${swarm^^}"
    local conv_env="${REPO_ROOT}/.tmp-l2/convoy_l2_${swarm}.env"
    local drone_env="${REPO_ROOT}/.tmp-l2/drones-${swarm}.env"

    [ -f "${conv_env}" ]  || { echo "[register/${swarm}] missing ${conv_env}";  return 1; }
    [ -f "${drone_env}" ] || { echo "[register/${swarm}] missing ${drone_env}"; return 1; }

    local conv_addr
    conv_addr=$(grep "^CONVOY_PROTOCOL_ADDR_${up}=" "${conv_env}" | cut -d= -f2)
    [ -z "${conv_addr}" ] && { echo "[register/${swarm}] no convoy_protocol address"; return 1; }

    local drone_addrs=()
    for did in 1 2 3 4 5; do
        local d
        d=$(grep "^${up}_DRONE_${did}_ADDR=" "${drone_env}" | cut -d= -f2)
        [ -z "${d}" ] && { echo "[register/${swarm}] no addr for drone ${did}"; return 1; }
        drone_addrs+=("${d}")
    done

    local mid="${MISSION_ID[$swarm]}"
    local zone_w="${SPEC_ZONE_W[$swarm]}"
    local strip_width="${SPEC_STRIP_WIDTH[$swarm]}"

    echo
    echo "[register/${swarm}] mission ${mid} on Registry ${REGISTRY_ADDR}"
    echo "[register/${swarm}]   convoy_protocol L2 addr: ${conv_addr}"
    echo "[register/${swarm}]   drones: ${drone_addrs[*]}"

    # 1a. Bind missionId → L2 contract address on Registry (so Registry.deploy
    #     knows where to dispatch the L1→L2 open_mission message)
    echo "[register/${swarm}] step 1a: Registry.setConvoyProtocolL2(${mid}, ${conv_addr})"
    CAST send "${REGISTRY_ADDR}" \
        "setConvoyProtocolL2(uint256,uint256)" \
        "${mid}" "${conv_addr}" \
        --rpc-url "${L1_RPC}" \
        --private-key "${DEPLOYER_PK}" \
        --legacy \
        2>&1 | tail -3

    # 1b. Bind missionId → L2 sender on Verifier (so Verifier.consumeL2Message
    #     accepts MissionSafe messages from this L2 contract for this mission)
    echo "[register/${swarm}] step 1b: Verifier.setConvoyProtocolL2(${mid}, ${conv_addr})"
    CAST send "${VERIFIER_ADDR}" \
        "setConvoyProtocolL2(uint256,uint256)" \
        "${mid}" "${conv_addr}" \
        --rpc-url "${L1_RPC}" \
        --private-key "${DEPLOYER_PK}" \
        --legacy \
        2>&1 | tail -3

    # 2. Build MissionSpec tuple — order must match Registry.sol's struct:
    #    (areaHash, zoneX, zoneY, zoneW, zoneH, nDrones, stripWidth,
    #     coverageMin, pMin, timeWindow)
    local spec="(${AREA_HASH},${SHARED_ZONE_X},${SHARED_ZONE_Y},${zone_w},${SHARED_ZONE_H},${SHARED_N_DRONES},${strip_width},${SHARED_COVERAGE_MIN},${SHARED_P_MIN},${SHARED_TIME_WINDOW})"

    # 3. Build the uint256[5] drone-addresses fixed array literal:
    #    [0x..., 0x..., 0x..., 0x..., 0x...]
    local drones="[${drone_addrs[0]},${drone_addrs[1]},${drone_addrs[2]},${drone_addrs[3]},${drone_addrs[4]}]"

    echo "[register/${swarm}] step 2: Registry.deploy(${mid}, spec, drones, ${TS_START})"
    echo "[register/${swarm}]   → also fires StarknetCoreStub.sendMessageToL2(...) for L1→L2 open_mission"
    CAST send "${REGISTRY_ADDR}" \
        "deploy(uint256,(bytes32,uint32,uint32,uint32,uint32,uint8,uint32,uint16,uint16,uint64),uint256[5],uint256)" \
        "${mid}" "${spec}" "${drones}" "${TS_START}" \
        --rpc-url "${L1_RPC}" \
        --private-key "${COMMANDER_PK}" \
        --legacy \
        2>&1 | tail -3

    echo "[register/${swarm}] OK"
}

# ── Arg parsing ─────────────────────────────────────────────────────────────
SWARM_FILTER="both"
while [ $# -gt 0 ]; do
    case "$1" in
        --swarm) SWARM_FILTER="$2"; shift 2 ;;
        --swarm=*) SWARM_FILTER="${1#--swarm=}"; shift ;;
        *) echo "[register] unknown arg: $1"; exit 2 ;;
    esac
done

case "${SWARM_FILTER}" in
    alpha) register_swarm alpha ;;
    bravo) register_swarm bravo ;;
    both)
        register_swarm alpha
        register_swarm bravo
        ;;
    *) echo "[register] --swarm must be alpha | bravo | both"; exit 2 ;;
esac

echo
echo "[register] both missions anchored on L1 + L1→L2 messages queued in StarknetCoreStub"
echo "[register] (Madara won't pick them up while --l1-sync-disabled — run open-missions.sh as the dev fallback)"

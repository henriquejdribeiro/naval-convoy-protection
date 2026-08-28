#!/usr/bin/env bash
# =============================================================================
# register-missions.sh — anchor mission deployment on L1 + dispatch L1→L2
#                        open_mission message via StarknetCore.
#
# For each swarm:
#   1. Reads convoy_protocol L2 address from .tmp-l2/convoy_l2_<swarm>.env
#   2. Reads 5 drone L2 addresses from .tmp-l2/drones-<swarm>.env
#   3. cast send Registry.setConvoyProtocolL2(missionId, l2Addr)
#         signed with the deployer (owner) key
#   4. cast send Registry.deploy(missionId, spec, droneAddresses, tsStart)
#         signed with the commander key
#      → This call ALSO fires StarknetCore.sendMessageToL2(
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


# Strict mode — fail fast and loud:
#   -e           exit immediately if any command returns non-zero
#   -u           treat use of an unset variable as an error (catches typos)
#   -o pipefail  a pipeline fails if ANY stage fails, not just the last one
set -euo pipefail


# Absolute path to the repo root (one level up from this script in scripts/).
# Kept absolute — it's passed to `docker run -v "${REPO_ROOT}:/work"` (Docker
# requires an absolute host path) and used to read the .tmp-l2/*.env files
# written by deploy-l2.sh and generate-drone-accounts.sh.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Tunables ──────────────────────────────────────────────────────────────
# Every value is ${VAR:-default}: set the env var to override, else use the
# dev default. This is what lets the script point at a real L1 / real keys
# in production without editing it.
L1_RPC="${L1_RPC:-http://ship-a:8545}" # L1 node RPC — Docker DNS in dev, real URL in prod

# Two distinct roles, two keys (override via env in prod with managed secrets):
DEPLOYER_PK="${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}" # anvil[0] — contract OWNER; signs the onlyOwner setConvoyProtocolL2 bindings
COMMANDER_PK="${COMMANDER_PK:-0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356}" # anvil[7] — COMMANDER; signs Registry.deploy (the mission order itself)
TS_START=1700000000   # mission start timestamp (unix). MUST match generate-mission.py
                       # or the telemetry cells_ts will fall outside the time window and fail the time predicate.

# Resolve contract addresses — env vars win, else deployments/local.env, else fail.
REGISTRY_ADDR="${REGISTRY_ADDR:-}"
if [ -f "${REPO_ROOT}/deployments/local.env" ]; then
    [ -z "${REGISTRY_ADDR}" ] && REGISTRY_ADDR=$(grep -E "^export REGISTRY_ADDR="        "${REPO_ROOT}/deployments/local.env" | cut -d= -f2 | tr -d ' ')
fi
[ -z "${REGISTRY_ADDR}" ] && { echo "[register] REGISTRY_ADDR missing"; exit 1; }

# ── Per-swarm mission geometry ──────────────────────────────────────────────
# Defines the "area" each swarm must clear: a 2D grid of cells, sliced into
# one vertical strip per drone. These values MUST stay identical to
# generate-mission.py (which makes telemetry that fits)
# (which sends the same spec to L2) — if they drift, good sweeps fail the
# predicates or L1 and L2 disagree on the mission.

# Operational-area identifier (ASCII "areareare…a1" packed into a felt).
# Placeholder in dev; in prod this would commit to the real zone definition.
AREA_HASH="0x6172656172656172656172656172656172656172656172656172656172656131"

# declare -A = associative array (map keyed by swarm: ${SPEC_ZONE_W[alpha]} → 15).
declare -A SPEC_ZONE_W=( [alpha]=15 [bravo]=20 )          # zone width in cells (the area is zone_w × zone_h)
declare -A SPEC_STRIP_WIDTH=( [alpha]=3 [bravo]=4 )       # per-drone lane width = zone_w / n_drones (15/5=3, 20/5=4)
declare -A MISSION_ID=( [alpha]=1 [bravo]=2 )             # on-chain mission id per swarm

# SHARED_* — identical for both swarms (the area shape + the SAFE thresholds):
SHARED_ZONE_X=0                # zone origin x (bottom-left corner)
SHARED_ZONE_Y=0                # zone origin y
SHARED_ZONE_H=8                # zone height in cells → each strip is strip_width × 8
SHARED_N_DRONES=5              # drones per swarm = number of strips the zone is split into
SHARED_COVERAGE_MIN=950        # min coverage, permille (950/1000 = 95% of the strip's cells must be swept)
SHARED_P_MIN=7000              # detection threshold, basis points (cell p_contact must be < 7000/10000 = 70%)
SHARED_TIME_WINDOW=360         # seconds; every cell's timestamp must be within ts_start + 360s

# L1 transaction wrapper — runs `cast` (Foundry's Ethereum CLI) in the foundry
# container, the L1 counterpart to the SK() starkli wrapper.
#   --network convoy-l1  → so --rpc-url http://ship-a:8545 resolves by hostname
#   --entrypoint cast    → run the cast binary DIRECTLY, bypassing /bin/sh -c,
#                          so the parens in the MissionSpec tuple signature
#                          (e.g. deploy(uint256,(bytes32,...),...)) aren't
#                          mangled by the shell — no escaping needed.
#   -v contracts:/workspace → cast can see the repo's contracts dir
CAST() {
    MSYS_NO_PATHCONV=1 docker run --rm --network convoy-l1 \
        --entrypoint cast \
        -v "${REPO_ROOT}/contracts:/workspace" -w /workspace \
        ghcr.io/foundry-rs/foundry:latest \
        "$@"
}

register_swarm() {
    
    # Per-swarm registration. swarm = "alpha" | "bravo".
    local swarm="$1"
    local up="${swarm^^}"

    # Inputs come from earlier pipeline steps:
    #   convoy_l2_<swarm>.env  ← written by deploy-l2.sh            (the L2 contract address)
    #   drones-<swarm>.env     ← written by generate-drone-accounts (the 5 drone addresses)
    local conv_env="${REPO_ROOT}/.tmp-l2/convoy_l2_${swarm}.env"
    local drone_env="${REPO_ROOT}/.tmp-l2/drones-${swarm}.env"

    # Pipeline-order guard: bail if either prior step hasn't run for this swarm.
    [ -f "${conv_env}" ]  || { echo "[register/${swarm}] missing ${conv_env}";  return 1; }
    [ -f "${drone_env}" ] || { echo "[register/${swarm}] missing ${drone_env}"; return 1; }

    # Read this swarm's convoy_protocol L2 address (grep the line, take the value after '=').
    local conv_addr
    conv_addr=$(grep "^CONVOY_PROTOCOL_ADDR_${up}=" "${conv_env}" | cut -d= -f2)
    [ -z "${conv_addr}" ] && { echo "[register/${swarm}] no convoy_protocol address"; return 1; }

    # Collect all 5 drone addresses into an array. Each must be present — if a swarm
    # is only partially provisioned (e.g. 1 of 5 drones), this bails at the missing one.
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

    # ── Step 1a: bind missionId → L2 contract on the Registry ──────────────
    # Tells the Registry "mission ${mid} lives at L2 contract ${conv_addr}", so
    # the Registry.deploy call below knows which L2 contract to address when it
    # fires the L1→L2 open_mission message. This is the L1→L2 dispatch binding.
    #
    # setConvoyProtocolL2 is onlyOwner → signed with DEPLOYER_PK (the contract
    # owner), NOT the commander key. (Config is the owner's job; the order is
    # the commander's — that comes in step 2.)
    #
    # --legacy: this Clique-PoA geth doesn't seal EIP-1559 (type-2) txs, so send
    # a legacy type-0 tx. 2>&1 | tail -3: keep just the last lines of cast's
    # receipt output.
    echo "[register/${swarm}] step 1a: Registry.setConvoyProtocolL2(${mid}, ${conv_addr})"
    CAST send "${REGISTRY_ADDR}" \
        "setConvoyProtocolL2(uint256,uint256)" \
        "${mid}" "${conv_addr}" \
        --rpc-url "${L1_RPC}" \
        --private-key "${DEPLOYER_PK}" \
        --legacy \
        2>&1 | tail -3

    # ── Build the MissionSpec tuple as a cast literal ──────────────────────
    # cast fills tuple fields POSITIONALLY, so the order here must match
    # Registry.sol's MissionSpec struct exactly — a wrong order silently puts
    # values in the wrong fields (no error, just a corrupt spec on-chain):
    #   (areaHash, zoneX, zoneY, zoneW, zoneH, nDrones, stripWidth,
    #    coverageMin, pMin, timeWindow)
    # Mixes per-swarm values (zone_w, strip_width) with the SHARED_* constants.
    # The parens + commas are why CAST() uses --entrypoint cast (no shell to
    # mangle them).
    local spec="(${AREA_HASH},${SHARED_ZONE_X},${SHARED_ZONE_Y},${zone_w},${SHARED_ZONE_H},${SHARED_N_DRONES},${strip_width},${SHARED_COVERAGE_MIN},${SHARED_P_MIN},${SHARED_TIME_WINDOW})"

    # ── Build the uint256[5] drone-addresses literal ───────────────────────
    # The 5 drone addresses as a fixed-size Solidity array: [0x…, 0x…, …].
    # Passed as uint256 because Starknet addresses are felts (>20 bytes), so
    # they don't fit Solidity's `address` (160-bit) — uint256 holds the full
    # value. The [ ] brackets are also why CAST() needs --entrypoint cast.
    local drones="[${drone_addrs[0]},${drone_addrs[1]},${drone_addrs[2]},${drone_addrs[3]},${drone_addrs[4]}]"


    # ── Step 2: deploy the mission — the commander's order + the L1→L2 send ──
    # This single call does TWO things on-chain:
    #   1. Records the mission (spec + drones + ts_start) in the Registry — the
    #      permanent L1 audit anchor: the commander's order, on the base chain.
    #   2. Internally calls StarknetCore.sendMessageToL2(...) — queuing the
    #      L1→L2 open_mission message + emitting LogMessageToL2.
    #
    # Signed with COMMANDER_PK (NOT the owner): steps 1a are owner CONFIG;
    # this is the commander's ORDER. That's the deployer/commander role split.
    #
    # The deploy(...) signature carries the MissionSpec (tuple) — its parens are
    # exactly why CAST() runs via --entrypoint cast.
    #
    # Bridge status: the L1→L2 message goes through each swarm's REAL StarkWare
    #   core (deployed by madara-bootstrapper). Both alpha and bravo run
    #   --sequencer with L1 sync, so Madara auto-consumes open_mission on each
    #   chain from its own core.
    echo "[register/${swarm}] step 2: Registry.deploy(${mid}, spec, drones, ${TS_START})"
    echo "[register/${swarm}]   → also fires the real Starknet core sendMessageToL2(...) → L1→L2 open_mission"
    CAST send "${REGISTRY_ADDR}" \
        "deploy(uint256,(bytes32,uint32,uint32,uint32,uint32,uint8,uint32,uint16,uint16,uint64),uint256[5],uint256)" \
        "${mid}" "${spec}" "${drones}" "${TS_START}" \
        --value 0.01ether \
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

echo "[register] missions anchored on L1 + L1→L2 open_mission sent through the real Starknet core"
echo "[register] both swarms auto-consume open_mission via their own core (--sequencer L1 sync)"
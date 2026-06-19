#!/usr/bin/env bash
# =============================================================================
# relay-l2-messages.sh — dev-only L2→L1 message relay.
#
# Watches each Madara for `MissionSafe` events emitted by convoy_protocol
# and, when found, hand-credits the corresponding L2→L1 message into
# StarknetCoreStub.l2ToL1Messages via the dev-only `injectL2Message`
# helper. After that the Verifier can claim it via consumeL2Message.
#
# Why this exists (gap 1 of the L2→L1 path):
#   Real Starknet credits l2ToL1Messages from `updateState(stateRoot,
#   blockNumber, blockHash)` calls made by the orchestrator after a STARK
#   proof verifies. Until our SNOS + Stone + orchestrator pipeline is
#   wired (which is blocked on the cairo-lang version-skew we hit during
#   the L1 verifier-stack deploy), this script substitutes for that step.
#
#   ⚠ DEV ONLY. The injectL2Message stub function lets ANYONE hand-credit
#   the queue with no proof — completely unsafe for mainnet. Production
#   deployment must use a real settled L2 block.
#
# Usage:
#   ./scripts/relay-l2-messages.sh                  # one-shot scan for both swarms
#   ./scripts/relay-l2-messages.sh --swarm alpha    # alpha only
#
# Prereqs:
#   - L1 + both Madaras running
#   - L1 Verifier deployed and bound to the swarms' L2 contracts (via
#     register-missions.sh's Verifier.setConvoyProtocolL2 step)
#   - L2 contracts have actually emitted MissionSafe — i.e. all 5 drones
#     of the swarm submitted SAFE telemetry
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RPC_VERSION="0.8.1"
L1_RPC="${L1_RPC:-http://ship-a:8545}"
DEPLOYER_PK="${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

# Resolve StarknetCoreStub + Verifier addresses
STARKNET_CORE_STUB_ADDR="${STARKNET_CORE_STUB_ADDR:-}"
VERIFIER_ADDR="${VERIFIER_ADDR:-${CONVOY_VERIFIER_ADDR:-}}"
if [ -f "${REPO_ROOT}/deployments/local.env" ]; then
    [ -z "${STARKNET_CORE_STUB_ADDR}" ] && STARKNET_CORE_STUB_ADDR=$(grep -E "^export STARKNET_CORE_STUB_ADDR=" "${REPO_ROOT}/deployments/local.env" | cut -d= -f2 | tr -d ' ')
    [ -z "${VERIFIER_ADDR}" ]           && VERIFIER_ADDR=$(grep -E "^export CONVOY_VERIFIER_ADDR=" "${REPO_ROOT}/deployments/local.env" | cut -d= -f2 | tr -d ' ')
fi
[ -z "${STARKNET_CORE_STUB_ADDR}" ] && { echo "[relay] STARKNET_CORE_STUB_ADDR missing"; exit 1; }
[ -z "${VERIFIER_ADDR}" ]           && { echo "[relay] VERIFIER_ADDR missing"; exit 1; }

declare -A MISSION_ID=( [alpha]=1 [bravo]=2 )

# starknet_keccak("MissionSafe") — the L2-side event key Madara
# indexes by. Pre-computed via `starkli selector MissionSafe`.
MISSION_SAFE_SELECTOR="0x027a07cea48d6c7e7f4dee9586e6ae9c1ef9a86927a4a5d8b66dde17c842cc26"

# Run cast inside foundry container with the convoy-l1 network
CAST() {
    MSYS_NO_PATHCONV=1 docker run --rm --network convoy-l1 \
        -v "${REPO_ROOT}/contracts:/workspace" -w /workspace \
        ghcr.io/foundry-rs/foundry:latest \
        -c "cast $*"
}

# Run starkli inside cairo-builder against the swarm's Madara RPC
SK() {
    local rpc="$1"; shift
    MSYS_NO_PATHCONV=1 docker run --rm --network convoy-l1 \
        -v "${REPO_ROOT}:/work" -w /work \
        -e STARKNET_RPC="${rpc}" \
        convoy-cairo-builder starkli "$@"
}

relay_swarm() {
    local swarm="$1"
    local up="${swarm^^}"
    local mid="${MISSION_ID[$swarm]}"
    local madara_host="convoy-madara-${swarm}"
    local rpc_url="http://${madara_host}:9944/rpc/v${RPC_VERSION}"
    local conv_env="${REPO_ROOT}/.tmp-l2/convoy_l2_${swarm}.env"
    [ -f "${conv_env}" ] || { echo "[relay/${swarm}] missing ${conv_env}"; return 1; }
    local conv_addr
    conv_addr=$(grep "^CONVOY_PROTOCOL_ADDR_${up}=" "${conv_env}" | cut -d= -f2)
    [ -z "${conv_addr}" ] && { echo "[relay/${swarm}] no convoy_protocol address"; return 1; }

    echo
    echo "[relay/${swarm}] checking ${madara_host} for MissionSafe events on ${conv_addr}"

    # Has convoy_protocol seen the all-SAFE state on chain?
    local safe_count
    safe_count=$(SK "${rpc_url}" call "${conv_addr}" safe_count "${mid}" 2>/dev/null | tail -n1 | tr -d '[:space:]' || true)
    if [ "${safe_count}" != "0x0000000000000000000000000000000000000000000000000000000000000005" ]; then
        echo "[relay/${swarm}] safe_count(${mid}) = ${safe_count} (not 5 — skipping; nothing to relay yet)"
        return 0
    fi

    # Hand-credit the message into StarknetCoreStub. Payload format must
    # match what convoy_protocol passed to send_message_to_l1_syscall:
    #   [mission_id, n_drones]
    local payload="[${mid},5]"

    echo "[relay/${swarm}] safe_count(${mid}) = 5 → injecting MissionSafe(${mid}, 5) on L1"
    CAST send "${STARKNET_CORE_STUB_ADDR}" \
        "'injectL2Message(uint256,address,uint256[])'" \
        "${conv_addr}" "${VERIFIER_ADDR}" "${payload}" \
        --rpc-url "${L1_RPC}" \
        --private-key "${DEPLOYER_PK}" \
        --legacy \
        2>&1 | tail -3

    echo "[relay/${swarm}] now consuming on L1 Verifier"
    CAST send "${VERIFIER_ADDR}" \
        "'consumeL2Message(uint256,uint256[])'" \
        "${conv_addr}" "${payload}" \
        --rpc-url "${L1_RPC}" \
        --private-key "${DEPLOYER_PK}" \
        --legacy \
        2>&1 | tail -3

    echo "[relay/${swarm}] OK — Registry.missionSafe[${mid}] should now be true"
}

# ── Arg parsing ─────────────────────────────────────────────────────────────
SWARM_FILTER="both"
while [ $# -gt 0 ]; do
    case "$1" in
        --swarm) SWARM_FILTER="$2"; shift 2 ;;
        --swarm=*) SWARM_FILTER="${1#--swarm=}"; shift ;;
        *) echo "[relay] unknown arg: $1"; exit 2 ;;
    esac
done

case "${SWARM_FILTER}" in
    alpha) relay_swarm alpha ;;
    bravo) relay_swarm bravo ;;
    both)
        relay_swarm alpha
        relay_swarm bravo
        ;;
    *) echo "[relay] --swarm must be alpha | bravo | both"; exit 2 ;;
esac

echo
echo "[relay] done — commander can now call CommandLog.advance(1, 2, speed) if both swarms went SAFE"

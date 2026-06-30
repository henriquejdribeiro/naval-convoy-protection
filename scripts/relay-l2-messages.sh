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

# Strict mode — fail fast:
#   -e  exit on any non-zero command
#   -u  unset variable is an error
#   -o pipefail  a pipeline fails if ANY stage fails (so a failed cast/starkli
#                inside a `… | tail -n` pipe still aborts, instead of being
#                masked by tail's success)
set -euo pipefail


# Repo root (one level up from scripts/). Kept absolute — passed to
# `docker run -v "${REPO_ROOT}:/work"` (Docker needs absolute host paths) and
# used to read .tmp-l2/convoy_l2_*.env and deployments/local.env.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── L2 side (read) ───────────────────────────────────────────────────────────
# Starknet JSON-RPC spec version for the starkli `safe_count` read against
# Madara. Madara v0.10.0 serves /rpc/v0.8.1; starkli 0.4.2 targets 0.8.x.
RPC_VERSION="0.8.1"

# ── L1 side (write) ──────────────────────────────────────────────────────────
# L1 (geth) RPC for the two cast sends. Defaults to ship-a inside the
# convoy-l1 docker network; override with `L1_RPC=… ./relay-l2-messages.sh`
# to point at a different node (e.g. host-mapped localhost:18545).
L1_RPC="${L1_RPC:-http://ship-a:8545}"

# Operator key (anvil account[0]) that SIGNS both L1 transactions:
#   - injectL2Message on the StarknetCoreStub (dev hand-credit)
#   - consumeL2Message on the Verifier (claim → Registry.setMissionSafe)
# Publicly-known dev key; overridable via env. In production the deployer
# signs neither: injectL2Message is gone (replaced by proven updateState),
# and consumeL2Message is callable by anyone.
DEPLOYER_PK="${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

# ── Resolve the two L1 contracts this relay writes to ───────────────────────
# Three-tier cascade: (1) env override, (2) deployments/local.env, (3) fail.
# We touch BOTH: injectL2Message on the StarknetCoreStub, then consumeL2Message
# on the Verifier. (Registry isn't resolved — the Verifier calls it internally.)

# Tier 1 — honour an env override if present. The `:-}` default is required
# under `set -u`: it lets us test a maybe-unset var without aborting. The
# Verifier accepts either VERIFIER_ADDR or the CONVOY_VERIFIER_ADDR alias
# (the name local.env actually exports).
STARKNET_CORE_STUB_ADDR="${STARKNET_CORE_STUB_ADDR:-}"
VERIFIER_ADDR="${VERIFIER_ADDR:-${CONVOY_VERIFIER_ADDR:-}}"

# Tier 2 — fall back to the deploy-output file, but only for vars still empty
# (`[ -z … ] && …` = assign-if-unset). grep the `export NAME=` line, take the
# value after `=`, strip spaces. Note the name mismatch: our VERIFIER_ADDR is
# read from the file's CONVOY_VERIFIER_ADDR.
if [ -f "${REPO_ROOT}/deployments/local.env" ]; then
    [ -z "${STARKNET_CORE_STUB_ADDR}" ] && STARKNET_CORE_STUB_ADDR=$(grep -E "^export STARKNET_CORE_STUB_ADDR=" "${REPO_ROOT}/deployments/local.env" | cut -d= -f2 | tr -d ' ')
    [ -z "${VERIFIER_ADDR}" ]           && VERIFIER_ADDR=$(grep -E "^export CONVOY_VERIFIER_ADDR=" "${REPO_ROOT}/deployments/local.env" | cut -d= -f2 | tr -d ' ')
fi

# Tier 3 — refuse to run with an empty address (fail loud, not a cryptic cast error).
[ -z "${STARKNET_CORE_STUB_ADDR}" ] && { echo "[relay] STARKNET_CORE_STUB_ADDR missing"; exit 1; }
[ -z "${VERIFIER_ADDR}" ]           && { echo "[relay] VERIFIER_ADDR missing"; exit 1; }

# Per-swarm mission id (matches register/open-missions): alpha→1, bravo→2.
declare -A MISSION_ID=( [alpha]=1 [bravo]=2 )

# starknet_keccak("MissionSafe") — the felt252 key Madara indexes that event
# under (Keccak-256 masked to 250 bits to fit a field element). Pre-computed
# via `starkli selector MissionSafe`.
# NOTE: currently UNUSED — the trigger logic polls safe_count rather than
#       filtering events. Vestigial; matches the (aspirational) "watches for
#       events" header. Safe to remove or to wire up real event filtering.
MISSION_SAFE_SELECTOR="0x027a07cea48d6c7e7f4dee9586e6ae9c1ef9a86927a4a5d8b66dde17c842cc26"

# Run Foundry's `cast` in a throwaway container on the convoy-l1 network.
#   MSYS_NO_PATHCONV=1  stop Git Bash rewriting /workspace into a Windows path
#   --rm                delete the container after the command
#   --network convoy-l1 so the `ship-a` hostname in L1_RPC resolves
#   -v …/contracts -w   mount + cd into contracts (ABIs / working dir)
#   -c "cast $*"        run cast THROUGH the image's shell ($* = all CAST args)
# Because cast runs through sh -c here, call sites must SINGLE-QUOTE Solidity
# signatures (e.g. "'injectL2Message(uint256,address,uint256[])'") so the
# parens survive the inner shell. (register-missions avoids this with
# --entrypoint cast, which skips the shell entirely.)
CAST() {
    MSYS_NO_PATHCONV=1 docker run --rm --network convoy-l1 \
        -v "${REPO_ROOT}/contracts:/workspace" -w /workspace \
        ghcr.io/foundry-rs/foundry:latest \
        -c "cast $*"
}

# Run starkli in the version-pinned cairo-builder image against an L2 (Madara)
# RPC. Unlike CAST (fixed L1_RPC), the target node is the FIRST argument —
# because the relay reads from a different Madara per swarm (alpha vs bravo).
#   local rpc="$1"; shift  capture the per-swarm RPC, leave the rest in "$@"
#   MSYS_NO_PATHCONV=1     stop Git Bash rewriting /work into a Windows path
#   --rm                   delete the container afterwards
#   --network convoy-l1    so convoy-madara-{alpha,bravo} hostnames resolve
#   -v REPO_ROOT:/work     mount the WHOLE repo (starkli needs .tmp-l2 keystores,
#                          cairo target, etc. — not just contracts/)
#   -e STARKNET_RPC        how starkli learns which node to hit (= $rpc)
#   convoy-cairo-builder   our pinned scarb/starkli/sierra-compile image
#   starkli "$@"           run starkli with the remaining args. No `-c`/shell:
#                          the image has no ENTRYPOINT, so args go straight to
#                          starkli as ARGV — no parens-mangling, and "$@"
#                          preserves arg boundaries (cf. CAST's $* which joins).
SK() {
    local rpc="$1"; shift
    MSYS_NO_PATHCONV=1 docker run --rm --network convoy-l1 \
        -v "${REPO_ROOT}:/work" -w /work \
        -e STARKNET_RPC="${rpc}" \
        convoy-cairo-builder starkli "$@"
}

relay_swarm() {

    # ── Setup: derive per-swarm identifiers ────────────────────────────────
    local swarm="$1"
    local up="${swarm^^}"                                # alpha → ALPHA (for the env var name)
    local mid="${MISSION_ID[$swarm]}"                    # alpha→1, bravo→2
    local madara_host="convoy-madara-${swarm}"
    local rpc_url="http://${madara_host}:9944/rpc/v${RPC_VERSION}"                    # L2 read endpoint
    local conv_env="${REPO_ROOT}/.tmp-l2/convoy_l2_${swarm}.env"
    [ -f "${conv_env}" ] || { echo "[relay/${swarm}] missing ${conv_env}"; return 1; }

    # ── Read the swarm's L2 convoy_protocol address ────────────────────────
    local conv_addr
    conv_addr=$(grep "^CONVOY_PROTOCOL_ADDR_${up}=" "${conv_env}" | cut -d= -f2)
    [ -z "${conv_addr}" ] && { echo "[relay/${swarm}] no convoy_protocol address"; return 1; }

    echo
    echo "[relay/${swarm}] checking ${madara_host} for MissionSafe events on ${conv_addr}"

    # ── Trigger check: has the L2 reached all-SAFE? ────────────────────────
    # Read safe_count(mid) from L2 via starkli. Parse robustly:
    #   2>/dev/null              drop starkli's noise
    #   grep -oiE '0x[0-9a-f]+'  pull the felt value (NOT `tail`, which grabs
    #                            the array's closing `]` — that was the bug)
    #   head -n1                 first match; || true so no-match won't abort
    # Compare numerically: $((0x..05)) = 5, :-0 guards an empty read.
    # safe_count != 5 → not ready yet → return 0 (skip, NOT an error, so a
    # both-swarm run still proceeds to the other swarm).
    local safe_count
    safe_count=$(SK "${rpc_url}" call "${conv_addr}" safe_count "${mid}" 2>/dev/null | grep -oiE '0x[0-9a-f]+' | head -n1 || true)
    if [ "$(( ${safe_count:-0} ))" -ne 5 ]; then
        echo "[relay/${swarm}] safe_count(${mid}) = ${safe_count} (not 5 — skipping; nothing to relay yet)"
        return 0
    fi

    # Hand-credit the message into StarknetCoreStub. Payload format must
    # match what convoy_protocol passed to send_message_to_l1_syscall:
    #   [mission_id, n_drones]
    local payload="[${mid},5]"

    # ── Step 1 — hand-credit the L2→L1 message into the StarknetCoreStub.
    #    DEV SUBSTITUTE for proven settlement: real Starknet credits this via
    #    updateState after a STARK proof verifies; injectL2Message fakes it.
    #    Signature single-quoted because CAST runs through sh -c (parens).
    #    --legacy: Clique geth seals type-0 txs only. 2>&1|tail -3 trims output.
    echo "[relay/${swarm}] safe_count(${mid}) = 5 → injecting MissionSafe(${mid}, 5) on L1"
    CAST send "${STARKNET_CORE_STUB_ADDR}" \
        "'injectL2Message(uint256,address,uint256[])'" \
        "${conv_addr}" "${VERIFIER_ADDR}" "${payload}" \
        --rpc-url "${L1_RPC}" \
        --private-key "${DEPLOYER_PK}" \
        --legacy \
        2>&1 | tail -3

    # ── Step 2 — the GENUINE consume: Verifier claims the now-queued message
    #    (consumeMessageFromL2 binds msg.sender) and calls Registry.setMissionSafe.
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

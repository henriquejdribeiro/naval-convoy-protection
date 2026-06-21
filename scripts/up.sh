#!/usr/bin/env bash
# =============================================================================
# up.sh — bring the full convoy stack online in one command.
#
# Composes the four bring-up phases that every demo / dev session needs:
#
#   [1/4] L1 chain          6 geth ships (Clique PoA) + wire-mesh
#   [2/4] L1 contracts      StarknetCoreStub, Registry, Verifier, CommandLog
#                           (deterministic anvil-style addresses on a fresh
#                            chain — match deployments/local.env)
#   [3/4] L2 stack          10 Madara nodes (1 sequencer + 4 --full followers
#                           per swarm) + 2 leader pathfinders + 2 prover APIs
#   [4/4] Debugger          Dozzle log viewer at http://localhost:8888,
#                           sidebar grouped by drone hardware (Alpha 1..5,
#                           Bravo 1..5, L1 fleet)
#
# Healthcheck-gated: each phase blocks on its dependencies coming up before
# moving on. Re-running the script is safe — `docker compose up -d` is
# idempotent and the healthchecks short-circuit if everything's already up.
#
# Usage:
#   ./scripts/up.sh                  # bring up everything including Dozzle
#   ./scripts/up.sh --no-debugger    # skip Dozzle (saves a container)
#
# After this exits the next step is:
#   ./scripts/deploy-l2.sh
#   ./scripts/generate-drone-accounts.sh --swarm both
#   ./scripts/register-missions.sh
#   ./scripts/open-missions.sh
# then submit telemetry per drone. See README for the full sequence.
# =============================================================================

# -e (errexit) exit on any error
# -u (nounset) error on undefined variables
# -o pipefail  a pipe fails if any stage fails
set -euo pipefail

# parse arguments
NO_DEBUGGER=false
while [ $# -gt 0 ]; do
    case "$1" in
        --no-debugger) NO_DEBUGGER=true; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "[up] unknown arg: $1" >&2; exit 2 ;;
    esac
done

# root directory 
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

# Wait for a docker container to reach the healthy state. Polls every 3s.
wait_healthy() {
    local name="$1"
    local label="$2"
    printf "  waiting for %s healthy..." "${label}"
    until docker ps --filter "name=${name}" --filter "health=healthy" -q | grep -q .; do
        printf "."
        sleep 3
    done
    printf " ✓\n"
}

echo "═══════════════════════════════════════════════════════════════"
echo "  [1/4] L1 chain — 6 geth ships + wire-mesh"
echo "═══════════════════════════════════════════════════════════════"
docker compose -f docker-compose.l1.yml up -d 2>&1 | tail -3
wait_healthy "convoy-ship-a" "ship-a"

echo
echo "═══════════════════════════════════════════════════════════════"
echo "  [2/4] L1 contracts — Stub, Registry, Verifier, CommandLog"
echo "═══════════════════════════════════════════════════════════════"

# If contracts at the addresses expected by local.env already have code,
# skip the deploy. Otherwise a re-run with old chain state would deploy
# fresh contracts at SHIFTED addresses (deployer nonce drift), and every
# downstream script reading local.env would point at the wrong contracts.
. deployments/local.env
already_deployed=true
for var in STARKNET_CORE_STUB_ADDR REGISTRY_ADDR CONVOY_VERIFIER_ADDR COMMAND_LOG_ADDR; do
    addr="${!var}"
    code=$(curl -s -X POST "${URL}" -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"${addr}\",\"latest\"],\"id\":1}" \
        | grep -oE '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4)
    if [ "${#code}" -le 4 ]; then
        already_deployed=false
        break
    fi
done

if ${already_deployed}; then
    echo "  L1 contracts already deployed at the local.env addresses — skipping."
    echo "    StarknetCoreStub: ${STARKNET_CORE_STUB_ADDR}"
    echo "    Registry:         ${REGISTRY_ADDR}"
    echo "    Verifier:         ${CONVOY_VERIFIER_ADDR}"
    echo "    CommandLog:       ${COMMAND_LOG_ADDR}"
else
    docker compose -f docker-compose.l1.yml --profile deploy run --rm deploy-l1 2>&1 \
        | grep -E "deployed at|deploy-l1\]" | head -10
fi

echo
echo "═══════════════════════════════════════════════════════════════"
echo "  [3/4] L2 stack — 10 Madara + 2 pathfinder leaders + prover APIs"
echo "═══════════════════════════════════════════════════════════════"
docker compose -f docker-compose.l1.yml -f docker-compose.l2.yml --profile l2 up -d 2>&1 | tail -3
wait_healthy "convoy-madara-alpha"     "madara-alpha (sequencer)"
wait_healthy "convoy-madara-bravo"     "madara-bravo (sequencer)"
wait_healthy "convoy-pathfinder-alpha-1" "pathfinder-alpha-1 (leader archive)"
wait_healthy "convoy-pathfinder-bravo-1" "pathfinder-bravo-1 (leader archive)"

if ! ${NO_DEBUGGER}; then
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "  [4/4] Dozzle log viewer"
    echo "═══════════════════════════════════════════════════════════════"
    docker compose -f debugger/docker-compose.yml up -d 2>&1 | tail -3
    echo "  → http://localhost:8888  (sidebar grouped by drone hardware)"
fi

echo
echo "═══════════════════════════════════════════════════════════════"
echo "  Stack is up. Suggested next steps:"
echo "═══════════════════════════════════════════════════════════════"
echo "    ./scripts/deploy-l2.sh"
echo "    ./scripts/generate-drone-accounts.sh --swarm both"
echo "    ./scripts/register-missions.sh"
echo "    ./scripts/open-missions.sh"
echo "    python3 scripts/generate-mission.py --scenario both-safe --output-dir .tmp-l2/missions/"
echo "    for swarm in alpha bravo; do"
echo "        for did in 1 2 3 4 5; do"
echo "            f=.tmp-l2/missions/both-safe/\${swarm}_\${did}.json"
echo "            [ -f \"\$f\" ] && ./scripts/submit-telemetry.sh \$swarm \$did \"\$f\""
echo "        done"
echo "    done"

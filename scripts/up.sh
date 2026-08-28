#!/usr/bin/env bash
# =============================================================================
# up.sh — bring the full convoy stack online in one command.
#
# Composes the four bring-up phases that every demo / dev session needs:
#
#   [1/4] L1 chain          6 Hyperledger Besu ships (PoA) + wire-mesh
#   [2/4] L1 contracts      Registry, Verifier, CommandLog
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

# Helper that waits for a docker container to reach the healthy state. Polls every 3s.
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

# Wait for the Besu L1 RPC (ship-a) to answer. Besu has no docker healthcheck,
# so we poll the JSON-RPC directly instead of docker health status.
wait_besu() {
    printf "  waiting for Besu ship-a RPC (localhost:8545)..."
    until curl -fs -X POST -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 >/dev/null 2>&1; do
        printf "."
        sleep 3
    done
    printf " ✓\n"
}

echo "  [1/4] L1 chain — 6 Besu QBFT validators (ships A–F)"
echo "═══════════════════════════════════════════════════════════════"
docker compose -f docker-compose.l1.yml up -d 2>&1 | tail -3
wait_besu

echo
echo "═══════════════════════════════════════════════════════════════"
echo "  [2/4] L1 contracts — Registry, Verifier, CommandLog"
echo "═══════════════════════════════════════════════════════════════"

# If contracts at the addresses expected by local.env already have code,
# skip the deploy. Otherwise a re-run with old chain state would deploy
# fresh contracts at SHIFTED addresses (deployer nonce drift), and every
# downstream script reading local.env would point at the wrong contracts.
. deployments/local.env
core_has_code() {
    local a="${1:-}"; [ -z "$a" ] && return 1
    local code
    code=$(curl -s -X POST "${URL}" -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"${a}\",\"latest\"],\"id\":1}" \
        | grep -oE '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4)
    [ "${#code}" -gt 4 ]
}
CORE_ADDR=""
bootstrap_core() {   # $1=swarm  $2=config file  $3=deployer key
    local swarm="$1" cfg="$2" key="$3"
    local out="${REPO_ROOT}/bootstrap/output/addresses-${swarm}.json"
    CORE_ADDR=""
    [ -f "${out}" ] && CORE_ADDR=$(grep -oE '"coreContract"[^"]*"0x[0-9a-fA-F]+"' "${out}" | head -1 | grep -oE '0x[0-9a-fA-F]+')
    if core_has_code "${CORE_ADDR}"; then echo "  reusing ${swarm} core ${CORE_ADDR}"; return 0; fi
    echo "  deploying ${swarm} Starknet core (bootstrapper-v2 setup-base)..."
    mkdir -p "${REPO_ROOT}/bootstrap/output"; printf '{}' > "${out}"
    MSYS_NO_PATHCONV=1 docker run --rm -w /app/build-artifacts \
        -e BASE_LAYER_PRIVATE_KEY="${key}" \
        -v "${REPO_ROOT}/bootstrap:/bootstrap" \
        ghcr.io/madara-alliance/bootstrapper-v2:nightly-b185bb3 \
        setup-base --config-path "/bootstrap/${cfg}" \
        --addresses-output-path "/bootstrap/output/addresses-${swarm}.json" 2>&1 \
        | grep -E "Deployed|config hash|saved" | tail -14
    CORE_ADDR=$(grep -oE '"coreContract"[^"]*"0x[0-9a-fA-F]+"' "${out}" | head -1 | grep -oE '0x[0-9a-fA-F]+')
}
bootstrap_core alpha config.json       "${ALPHA_RELAY_PK}"; STARKNET_CORE_ADDR_ALPHA="${CORE_ADDR}"
bootstrap_core bravo config-bravo.json "${BRAVO_RELAY_PK}"; STARKNET_CORE_ADDR_BRAVO="${CORE_ADDR}"
[ -n "${STARKNET_CORE_ADDR_ALPHA}" ] && [ -n "${STARKNET_CORE_ADDR_BRAVO}" ] || { echo "[up] bootstrapper failed" >&2; exit 1; }
export STARKNET_CORE_ADDR_ALPHA STARKNET_CORE_ADDR_BRAVO
echo "  Alpha core: ${STARKNET_CORE_ADDR_ALPHA}"
echo "  Bravo core: ${STARKNET_CORE_ADDR_BRAVO}"
already_deployed=true
for var in REGISTRY_ADDR CONVOY_VERIFIER_ADDR COMMAND_LOG_ADDR; do
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
# ── [3a] Seed alpha's and bravo's genesis (--devnet) so the --sequencer runtime has the
#         10 predeployed accounts.
seed_sequencer() {   # $1 = alpha | bravo
    local s="$1"
    docker ps --format '{{.Names}}' | grep -q "^convoy-madara-${s}$" && return 0
    echo "  seeding ${s} genesis (--devnet one-shot)..."
    docker compose -f docker-compose.l1.yml -f docker-compose.l2.yml --profile seed up -d "madara-${s}-seed"
    local tries=0
    until docker logs "convoy-madara-${s}-seed" 2>&1 | grep -q "computed for #0"; do
        tries=$((tries+1)); [ "$tries" -gt 60 ] && { echo "  ${s} seed TIMEOUT"; docker logs "convoy-madara-${s}-seed" 2>&1 | tail -5; break; }
        sleep 1
    done
    sleep 4
    docker compose -f docker-compose.l1.yml -f docker-compose.l2.yml --profile seed rm -sf "madara-${s}-seed"
    echo "  ${s} genesis seeded ✓"
}
seed_sequencer alpha
seed_sequencer bravo
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
echo "    ./scripts/deploy-l2.sh --swarm both"
echo "    ./scripts/generate-drone-accounts.sh --swarm both"
echo "    ./scripts/register-missions.sh --swarm both"
echo "    python3 scripts/generate-mission.py --scenario both-safe --output-dir .tmp-l2/missions/"
echo "    for swarm in alpha bravo; do"
echo "        for did in 1 2 3 4 5; do"
echo "            f=.tmp-l2/missions/both-safe/\${swarm}_\${did}.json"
echo "            [ -f \"\$f\" ] && ./scripts/submit-telemetry.sh \$swarm \$did \"\$f\""
echo "        done"
echo "    done"
echo "    ./scripts/relay-l2-messages.sh "
echo "    

docker run --rm --network convoy-l1 ghcr.io/foundry-rs/foundry:latest \
  -c "cast call 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 'advanceCount()(uint256)' --rpc-url http://ship-a:8545"   
  
"
echo "    

docker run --rm --network convoy-l1 ghcr.io/foundry-rs/foundry:latest -c "\
  cast send 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 \
    'advance(uint256,uint256,uint256)' 1 2 100 \
    --rpc-url http://ship-a:8545 \
    --private-key 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356 \
    --legacy"  
    
"

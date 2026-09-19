#!/usr/bin/env bash
# =============================================================================
# up.sh — bring the full convoy stack online in one command.
#
# Composes the four bring-up phases that every demo / dev session needs:
#
#   [1/4] L1 chain          6 Hyperledger Besu ships (PoA) + wire-mesh
#   [2/4] L1 contracts      Registry, Verifier, CommandLog
#                           (deterministic anvil-style addresses on a fresh
#                            chain — match LAYER1/deployments/local.env)
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
#   ./SIMULATOR/demo/scripts/script1_up.sh                  # bring up everything including Dozzle
#   ./SIMULATOR/demo/scripts/script1_up.sh --no-debugger    # skip Dozzle (saves a container)
#
# After this exits the next step is:
#   ./SIMULATOR/demo/scripts/script2_deploy-l2.sh
#   ./SIMULATOR/demo/scripts/script3_generate-drone-accounts.sh --swarm both
#   ./SIMULATOR/demo/scripts/script4_register-missions.sh
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
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
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

# ── Besu node-identity keys → per-ship volumes (QBFT validators) ──────────────
# Each ship reads /nodekey/key.priv at boot, so seed the volumes BEFORE the L1
# stack starts. Values piped via stdin (never on the host CLI / never in ps);
# idempotent. These addresses are fixed in genesis.json — the values must match
# EXACTLY or QBFT won't form consensus.
NODE_IMG="ghcr.io/foundry-rs/foundry:latest"
ensure_node_key() {   # $1 = volume   $2 = node private key (0x + 64 hex, no newline)
    MSYS_NO_PATHCONV=1 docker run --rm -v "$1:/nodekey" --entrypoint sh "${NODE_IMG}" -c 'test -s /nodekey/key.priv' 2>/dev/null && return 0
    printf "%s" "$2" | MSYS_NO_PATHCONV=1 docker run --rm -i --user 0:0 -v "$1:/nodekey" --entrypoint sh "${NODE_IMG}" -c 'cat > /nodekey/key.priv'
    echo "  seeded node key -> $1"
}
ensure_node_key convoy-ship-a-node "0xa7ee3c7df230a53396aac1c057c06a0adf53369f4eb76f7c5f7126abd066f1b1"
ensure_node_key convoy-ship-b-node "0x1cd7f0bbae7bd4acbd8df70d1927f30a3fceca1ad5c48ac72cbb215604b80002"
ensure_node_key convoy-ship-c-node "0xd3446ccdd6a4327dc4641e3447afa5d2237d342a7a7a9f6b3df2103b2e48b672"
ensure_node_key convoy-ship-d-node "0x3a18aac2f7ad9bb1d800331fcfa164ae152732dd26885226de635fcf480fd5db"
ensure_node_key convoy-ship-e-node "0xf422d1787a6821de53a5d26e697dbd1b823a82a61e97646feedaf70d504bc536"
ensure_node_key convoy-ship-f-node "0x2ba0265b8f32b99779b2a54b594bc18dc2d8891f59ebecf43c5e2728e5cb34b0"

echo "  [1/4] L1 chain — 6 Besu QBFT validators (ships A–F)"
echo "═══════════════════════════════════════════════════════════════"
docker compose --project-directory . -f LAYER1/docker-compose.l1.yml up -d 2>&1 | tail -3
wait_besu

echo
echo "═══════════════════════════════════════════════════════════════"
echo "  [2/4] L1 contracts — Registry, Verifier, CommandLog"
echo "═══════════════════════════════════════════════════════════════"

# If contracts at the addresses expected by local.env already have code,
# skip the deploy. Otherwise a re-run with old chain state would deploy
# fresh contracts at SHIFTED addresses (deployer nonce drift), and every
# downstream script reading local.env would point at the wrong contracts.
. LAYER1/deployments/local.env

# ── Owner key custody: import anvil[0] into ship A's volume (L1 command node) ──
# The owner/deployer key deploys + owns the L1 contracts. It lives ONLY in ship
# A's volume; deploy-l1, deploy-stark-verifier and the cast calls below all read
# it from there — it's never passed as --private-key on the host command line.
FOUNDRY_IMG="ghcr.io/foundry-rs/foundry:latest"
OWNER_KEYVOL="convoy-ship-a-key"
ensure_ship_key() {   # $1 = key volume   $2 = raw private key
    MSYS_NO_PATHCONV=1 docker run --rm -v "$1:/key" --entrypoint sh "${FOUNDRY_IMG}" -c 'test -s /key/pk' 2>/dev/null && return 0
    echo "  importing owner key into ship volume $1 (host never keeps it)"
    printf "%s" "$2" | MSYS_NO_PATHCONV=1 docker run --rm -i --user 0:0 -v "$1:/key" --entrypoint sh "${FOUNDRY_IMG}" -c 'cat > /key/pk'
}
ensure_ship_key "${OWNER_KEYVOL}" "${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

# Relay signer keys (L1 Stage-A proof submission) live in per-swarm volumes
# mounted into each prover-api — kept SEPARATE from the owner/deployer volumes
# so the forward prover never sees the higher-authority keys.
ensure_ship_key "convoy-relay-alpha-key" "${ALPHA_RELAY_PK:-0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba}"
ensure_ship_key "convoy-relay-bravo-key" "${BRAVO_RELAY_PK:-0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d}"
# Commander key (ship D) — signs mission orders in script4. Seeded here so
# script4 stays key-free and just reads it from ship D's volume.
ensure_ship_key "convoy-ship-d-key" "${COMMANDER_PK:-0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356}"


core_has_code() {
    local a="${1:-}"; [ -z "$a" ] && return 1
    local code
    code=$(curl -s -X POST "${URL}" -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"${a}\",\"latest\"],\"id\":1}" \
        | grep -oE '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4)
    [ "${#code}" -gt 4 ]
}
CORE_ADDR=""

bootstrap_core() {   # $1=swarm  $2=config file   (signer read from the relay volume)
    local swarm="$1" cfg="$2"
    local keyvol="convoy-relay-${swarm}-key"
    local out="${REPO_ROOT}/LAYER1/bootstrap/output/addresses-${swarm}.json"
    CORE_ADDR=""
    [ -f "${out}" ] && CORE_ADDR=$(grep -oE '"coreContract"[^"]*"0x[0-9a-fA-F]+"' "${out}" | head -1 | grep -oE '0x[0-9a-fA-F]+')
    if core_has_code "${CORE_ADDR}"; then echo "  reusing ${swarm} core ${CORE_ADDR}"; return 0; fi
    echo "  deploying ${swarm} Starknet core (bootstrapper-v2 setup-base)..."
    mkdir -p "${REPO_ROOT}/LAYER1/bootstrap/output"; printf '{}' > "${out}"
    # BASE_LAYER_PRIVATE_KEY read from the relay volume IN-CONTAINER (never on the
    # host CLI / never in ps); then re-exec the image's real entrypoint (tini).
    MSYS_NO_PATHCONV=1 docker run --rm -w /app/build-artifacts \
        -v "${keyvol}:/key" \
        -v "${REPO_ROOT}/LAYER1/bootstrap:/bootstrap" \
        --entrypoint sh \
        ghcr.io/madara-alliance/bootstrapper-v2:nightly-b185bb3 \
        -c 'export BASE_LAYER_PRIVATE_KEY=$(cat /key/pk); exec tini -- bootstrapper-v2 "$@"' sh \
        setup-base --config-path "/bootstrap/${cfg}" \
        --addresses-output-path "/bootstrap/output/addresses-${swarm}.json" 2>&1 \
        | grep -E "Deployed|config hash|saved" | tail -14
    CORE_ADDR=$(grep -oE '"coreContract"[^"]*"0x[0-9a-fA-F]+"' "${out}" | head -1 | grep -oE '0x[0-9a-fA-F]+')
}
bootstrap_core alpha config.json       ; STARKNET_CORE_ADDR_ALPHA="${CORE_ADDR}"
bootstrap_core bravo config-bravo.json ; STARKNET_CORE_ADDR_BRAVO="${CORE_ADDR}"

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
    docker compose --project-directory . -f LAYER1/docker-compose.l1.yml --profile deploy run --rm deploy-l1 2>&1 \
        | grep -E "deployed at|deploy-l1\]" | head -10
fi

# ── [2b] StarkWare 2023_9 GPS verifier suite + wire the convoy Verifier to it ──
echo "  [2b] StarkWare 2023_9 GPS verifier suite (byte-identical mainnet bytecode)"
STARK_ENV="${REPO_ROOT}/SIMULATOR/demo/.tmp-l1/stark-verifier.env"
GPS_ADDR=""
[ -f "${STARK_ENV}" ] && GPS_ADDR=$(grep '^GPS_STATEMENT_VERIFIER_ADDR=' "${STARK_ENV}" | cut -d= -f2)
if core_has_code "${GPS_ADDR}"; then
    echo "  reusing STARK verifier suite (GPS ${GPS_ADDR})"
else
    "${REPO_ROOT}/SIMULATOR/demo/scripts/deploy-stark-verifier.sh"
    GPS_ADDR=$(grep '^GPS_STATEMENT_VERIFIER_ADDR=' "${STARK_ENV}" | cut -d= -f2)
fi
echo "  wiring convoy Verifier ${CONVOY_VERIFIER_ADDR} -> GPS ${GPS_ADDR}"
MSYS_NO_PATHCONV=1 docker run --rm --network convoy-l1 -v "${OWNER_KEYVOL}:/key" --entrypoint sh "${FOUNDRY_IMG}" \
    -c 'PK=$(cat /key/pk); exec cast "$@" --private-key "$PK"' sh \
    send "${CONVOY_VERIFIER_ADDR}" "setStarkVerifier(address)" "${GPS_ADDR}" \
    --rpc-url http://ship-a:8545 \
    --legacy --gas-price 0 >/dev/null 2>&1 && echo "  ✓ starkVerifier wired"

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
    docker compose --project-directory . -f LAYER1/docker-compose.l1.yml -f LAYER2/docker-compose.l2.yml --profile seed up -d "madara-${s}-seed"
    local tries=0
    until docker logs "convoy-madara-${s}-seed" 2>&1 | grep -q "computed for #0"; do
        tries=$((tries+1)); [ "$tries" -gt 60 ] && { echo "  ${s} seed TIMEOUT"; docker logs "convoy-madara-${s}-seed" 2>&1 | tail -5; break; }
        sleep 1
    done
    sleep 4
    docker compose --project-directory . -f LAYER1/docker-compose.l1.yml -f LAYER2/docker-compose.l2.yml --profile seed rm -sf "madara-${s}-seed"
    echo "  ${s} genesis seeded ✓"
}
seed_sequencer alpha
seed_sequencer bravo
docker compose --project-directory . -f LAYER1/docker-compose.l1.yml -f LAYER2/docker-compose.l2.yml --profile l2 up -d 2>&1 | tail -3
wait_healthy "convoy-madara-alpha"     "madara-alpha (sequencer)"
wait_healthy "convoy-madara-bravo"     "madara-bravo (sequencer)"
wait_healthy "convoy-pathfinder-alpha-1" "pathfinder-alpha-1 (leader archive)"
wait_healthy "convoy-pathfinder-bravo-1" "pathfinder-bravo-1 (leader archive)"

if ! ${NO_DEBUGGER}; then
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "  [4/4] Dozzle log viewer"
    echo "═══════════════════════════════════════════════════════════════"
    docker compose -f SIMULATOR/debugger/docker-compose.yml up -d 2>&1 | tail -3
    echo "  → http://localhost:8888  (sidebar grouped by drone hardware)"
fi

echo
echo "═══════════════════════════════════════════════════════════════"
echo "  Stack is up. Suggested next steps:"
echo "═══════════════════════════════════════════════════════════════"
echo "    ./SIMULATOR/demo/scripts/script2_deploy-l2.sh --swarm both"
echo "    ./SIMULATOR/demo/scripts/script3_generate-drone-accounts.sh --swarm both"
echo "    ./SIMULATOR/demo/scripts/script4_register-missions.sh --swarm both"
echo "    python3 SIMULATOR/demo/scripts/script5_generate-mission.py --scenario both-safe"
echo "    for swarm in alpha bravo; do"
echo "        for did in 1 2 3 4 5; do"
echo "            f=SIMULATOR/demo/scenarios/both-safe/\${swarm}_\${did}.json"
echo "            [ -f \"\$f\" ] && ./SIMULATOR/demo/scripts/script6_submit-telemetry.sh \$swarm \$did \"\$f\""
echo "        done"
echo "    done"
echo "    

docker run --rm --network convoy-l1 ghcr.io/foundry-rs/foundry:latest \
  -c "cast call 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 'advanceCount()(uint256)' --rpc-url http://ship-a:8545"   
  
"
echo "    

docker run --rm --network convoy-l1 -v convoy-ship-d-key:/key --entrypoint sh ghcr.io/foundry-rs/foundry:latest -c "\
  cast send 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 \
    'advance(uint256,uint256,uint256)' 1 2 100 \
    --rpc-url http://ship-a:8545 \
    --private-key '$(cat /key/pk)' \
    --legacy"  
    
"

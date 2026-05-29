#!/usr/bin/env bash
# =============================================================================
# run-scenario.sh — drive an end-to-end scenario through the full real-verifier
# pipeline and ASSERT the expected outcome (convoy ADVANCES vs HOLDS).
#
# Walks the four-stack flow on L1:
#
#   1. Mission data simulator           : scripts/generate-mission.py
#   2. Prover container                  : docker exec convoy-prover-api ALL_*
#         a. cairo-compile + cairo-run + cpu_air_prover  (Cairo execution + Stone)
#         b. stark_evm_adapter           (proof → EVM shape)
#         c. path-a-runner               (STAGE A — phases 1-4 against
#                                          StarkWare contracts)
#         d. submit_proof_l1.py          (STAGE B — convoy Verifier)
#   3. Assertions                        : query Registry / CommandLog state
#      after the per-drone runs and verify the protocol state matches the
#      scenario's expected outcome.
#
# Scenarios (mirror scripts/generate-mission.py --scenario):
#
#   both-safe                — all 10 drones SAFE, convoy MUST advance
#   both-unsafe              — α[3]+β[3] unsafe, convoy MUST hold
#   mixed                    — only α completes, convoy MUST hold
#   alpha-dropout-vanish     — α[3] vanishes, convoy MUST hold
#   alpha-dropout-midflight  — α[3] verdict=0, convoy MUST hold
#   dual-dropout             — α[3] gone + β[4] partial, convoy MUST hold
#
# Required env (sourced from deployments/local.env or set by docker-compose):
#
#   GETH_RPC_URL                   L1 RPC (default http://localhost:8545)
#   REGISTRY_ADDR                  Registry.sol deployed address
#   COMMANDLOG_ADDR                CommandLog.sol deployed address
#   COMMANDER_PK                   D's commander key (advance signer)
#
# Usage:
#   scripts/run-scenario.sh both-safe
#   scripts/run-scenario.sh alpha-dropout-vanish
# =============================================================================
set -euo pipefail

SCENARIO="${1:-}"
if [ -z "${SCENARIO}" ]; then
    echo "usage: $0 <scenario>"
    echo "  scenarios: both-safe both-unsafe mixed alpha-dropout-vanish alpha-dropout-midflight dual-dropout"
    exit 2
fi

# Map scenario to expected outcome
case "${SCENARIO}" in
    both-safe)
        EXPECT_ALPHA_SAFE=1; EXPECT_BRAVO_SAFE=1; EXPECT_ADVANCE=1 ;;
    both-unsafe)
        EXPECT_ALPHA_SAFE=0; EXPECT_BRAVO_SAFE=0; EXPECT_ADVANCE=0 ;;
    mixed)
        EXPECT_ALPHA_SAFE=1; EXPECT_BRAVO_SAFE=0; EXPECT_ADVANCE=0 ;;
    alpha-dropout-vanish)
        EXPECT_ALPHA_SAFE=0; EXPECT_BRAVO_SAFE=1; EXPECT_ADVANCE=0 ;;
    alpha-dropout-midflight)
        EXPECT_ALPHA_SAFE=0; EXPECT_BRAVO_SAFE=1; EXPECT_ADVANCE=0 ;;
    dual-dropout)
        EXPECT_ALPHA_SAFE=0; EXPECT_BRAVO_SAFE=0; EXPECT_ADVANCE=0 ;;
    *)
        echo "[ERR] unknown scenario: ${SCENARIO}"
        exit 2 ;;
esac

# Resolve required env
: "${GETH_RPC_URL:=http://localhost:8545}"
: "${REGISTRY_ADDR:?REGISTRY_ADDR env var required}"
: "${COMMANDLOG_ADDR:?COMMANDLOG_ADDR env var required}"
: "${COMMANDER_PK:?COMMANDER_PK env var required}"

# Mission id constants — match Registry.sol
ALPHA_MID=1
BRAVO_MID=2

REPO_ROOT="$(cd "$(dirname "${0}")/.." && pwd)"
PROOFS_DIR="${REPO_ROOT}/proofs"
MISSIONS_DIR="${PROOFS_DIR}/missions/${SCENARIO}"

echo "==============================================================="
echo "  Scenario: ${SCENARIO}"
echo "  Expected: alpha-safe=${EXPECT_ALPHA_SAFE}  bravo-safe=${EXPECT_BRAVO_SAFE}  advance=${EXPECT_ADVANCE}"
echo "==============================================================="

# Step 1: generate the per-drone inputs (vanished drones get no JSON)
echo "[1/3] Generating mission data for ${SCENARIO}"
python3 "${REPO_ROOT}/scripts/generate-mission.py" \
    --scenario "${SCENARIO}" \
    --output-dir "${MISSIONS_DIR}"

# Step 2: trigger the prover container to iterate through all drones
echo
echo "[2/3] Triggering prover-api ALL_${SCENARIO} run"
SCEN_UPPER=$(echo "${SCENARIO}" | tr 'a-z-' 'A-Z_')
docker exec convoy-prover-api sh -c "echo ALL_${SCEN_UPPER} > /proofs/prove_trigger"

# Wait for prove_result to appear
echo "      waiting for prove_result..."
TIMEOUT=1800   # 30 min — 10 drones x up to 3 min each
ELAPSED=0
while [ ${ELAPSED} -lt ${TIMEOUT} ]; do
    if docker exec convoy-prover-api test -f /proofs/prove_result; then
        echo "      prover finished after ${ELAPSED}s"
        docker exec convoy-prover-api rm -f /proofs/prove_result
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done
if [ ${ELAPSED} -ge ${TIMEOUT} ]; then
    echo "[ERR] prover-api timed out after ${TIMEOUT}s"
    exit 1
fi

# Step 3: query L1 state and assert
echo
echo "[3/3] Asserting on-chain state"

# Registry.isMissionSafe(uint256) -> bool
ALPHA_SAFE_RAW=$(cast call --rpc-url "${GETH_RPC_URL}" "${REGISTRY_ADDR}" \
    "isMissionSafe(uint256)(bool)" ${ALPHA_MID})
BRAVO_SAFE_RAW=$(cast call --rpc-url "${GETH_RPC_URL}" "${REGISTRY_ADDR}" \
    "isMissionSafe(uint256)(bool)" ${BRAVO_MID})
ALPHA_SAFE=$([ "${ALPHA_SAFE_RAW}" = "true" ] && echo 1 || echo 0)
BRAVO_SAFE=$([ "${BRAVO_SAFE_RAW}" = "true" ] && echo 1 || echo 0)

# Registry.safeCount(uint256) -> uint8
ALPHA_COUNT=$(cast call --rpc-url "${GETH_RPC_URL}" "${REGISTRY_ADDR}" \
    "safeCount(uint256)(uint8)" ${ALPHA_MID} | awk '{print $1}')
BRAVO_COUNT=$(cast call --rpc-url "${GETH_RPC_URL}" "${REGISTRY_ADDR}" \
    "safeCount(uint256)(uint8)" ${BRAVO_MID} | awk '{print $1}')

echo "  Registry.safeCount[alpha]   = ${ALPHA_COUNT}  (expect 5 if alpha-safe=1)"
echo "  Registry.safeCount[bravo]   = ${BRAVO_COUNT}  (expect 5 if bravo-safe=1)"
echo "  Registry.isMissionSafe[α]   = ${ALPHA_SAFE}  (expect ${EXPECT_ALPHA_SAFE})"
echo "  Registry.isMissionSafe[β]   = ${BRAVO_SAFE}  (expect ${EXPECT_BRAVO_SAFE})"

PASS=1
[ "${ALPHA_SAFE}" = "${EXPECT_ALPHA_SAFE}" ] || { echo "  [FAIL] alpha missionSafe mismatch"; PASS=0; }
[ "${BRAVO_SAFE}" = "${EXPECT_BRAVO_SAFE}" ] || { echo "  [FAIL] bravo missionSafe mismatch"; PASS=0; }

# Attempt CommandLog.advance and check the outcome matches expectation
ADVANCE_OUT=$(cast send --rpc-url "${GETH_RPC_URL}" --private-key "${COMMANDER_PK}" \
    "${COMMANDLOG_ADDR}" "advance(uint256,uint256,uint256)" \
    ${ALPHA_MID} ${BRAVO_MID} 100 --json 2>&1 || true)

if echo "${ADVANCE_OUT}" | grep -q "transactionHash"; then
    ADVANCE_RESULT=1
    echo "  CommandLog.advance succeeded (tx mined)"
else
    ADVANCE_RESULT=0
    echo "  CommandLog.advance reverted (expected when missions not dual-safe)"
fi
[ "${ADVANCE_RESULT}" = "${EXPECT_ADVANCE}" ] \
    || { echo "  [FAIL] CommandLog.advance outcome mismatch (got=${ADVANCE_RESULT} expected=${EXPECT_ADVANCE})"; PASS=0; }

echo
if [ "${PASS}" = "1" ]; then
    echo "==============================================================="
    echo "  [PASS] scenario ${SCENARIO} — all on-chain state matches expectation"
    echo "==============================================================="
    exit 0
else
    echo "==============================================================="
    echo "  [FAIL] scenario ${SCENARIO} — see mismatches above"
    echo "==============================================================="
    exit 1
fi

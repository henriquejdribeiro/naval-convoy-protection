#!/usr/bin/env bash
# =============================================================================
# deploy-l2.sh — declare + deploy convoy_protocol.cairo to BOTH Madara
#                sequencers (alpha + bravo) for the dual-swarm topology.
#
# Prereqs:
#   - convoy-madara-alpha AND convoy-madara-bravo are up
#       docker compose -f docker-compose.l1.yml -f docker-compose.l2.yml \
#           --profile l2 up -d madara-alpha madara-bravo
#   - convoy-cairo-builder image is built (docker build infrastructure/cairo-builder/)
#   - cairo/convoy_protocol/target/dev/ has Sierra+CASM (run `scarb build`)
#
# What it does, per swarm (alpha + bravo):
#   1. Drops a starkli account file describing Madara's predeployed account #1
#   2. Drops a raw-key signer (Madara's pre-funded private key)
#   3. starkli declare → returns class_hash
#   4. starkli deploy  → returns contract_address  (no constructor args
#                        post-rewrite — see cairo/convoy_protocol/src/lib.cairo)
#   5. Smoke test: read safe_count(0) which returns 0 (proof the contract
#      is live; submit_telemetry would revert "mission not deployed"
#      because open_mission must be invoked via L1→L2 message first)
#   6. Writes /tmp/convoy_l2_{swarm}.env with CONVOY_PROTOCOL_ADDR + CLASS_HASH
#
# Pass --swarm alpha or --swarm bravo to deploy to just one; default = both.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Madara devnet account #1 — pre-funded, OZ-style. Same account exists on
# BOTH madara instances because both ran `--devnet` (deterministic genesis).
ACCOUNT_ADDR="0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d"
ACCOUNT_PK="0x077e56c6dc32d40a67f6f7e6625c8dc5e570abe49c0a24e9202e4ae906abcc07"
ACCOUNT_CLASS="0xe2eb8f5672af4e6a4e8a8f1b44989685e668489b0a25437733756c5a34a1d6"

# Madara serves /rpc/v0.7.1/, v0.8.1/ and v0.9.0/. Starkli 0.4.0 targets
# 0.8.0, so v0.8.1 is the closest match.
RPC_VERSION="0.8.1"

SIERRA="/work/cairo/convoy_protocol/target/dev/convoy_protocol_ConvoyProtocol.contract_class.json"
CASM="/work/cairo/convoy_protocol/target/dev/convoy_protocol_ConvoyProtocol.compiled_contract_class.json"

# Run starkli inside cairo-builder, mounted at /work so it can see artefacts.
SCARB_RUN() {
    local rpc_url="$1"; shift
    MSYS_NO_PATHCONV=1 docker run --rm -i \
        --network convoy-l1 \
        -v "${REPO_ROOT}:/work" \
        -e STARKNET_RPC="${rpc_url}" \
        -e STARKNET_ACCOUNT="/work/.tmp-l2/account.json" \
        -e STARKNET_KEYSTORE="/work/.tmp-l2/keystore.json" \
        -e STARKNET_KEYSTORE_PASSWORD="convoy" \
        -w /work \
        convoy-cairo-builder:latest \
        "$@"
}

# ── Per-swarm deployment routine ────────────────────────────────────────────
deploy_to() {
    local swarm="$1"           # "alpha" or "bravo"
    local madara_host="convoy-madara-${swarm}"
    local rpc_url="http://${madara_host}:9944/rpc/v${RPC_VERSION}"
    local env_file="${REPO_ROOT}/.tmp-l2/convoy_l2_${swarm}.env"

    echo
    echo "======================================================================"
    echo "  Deploying convoy_protocol to ${madara_host}  (swarm=${swarm})"
    echo "  RPC: ${rpc_url}"
    echo "======================================================================"

    # 3. Declare — returns class hash (idempotent if already declared)
    echo "[deploy-l2/${swarm}] declaring convoy_protocol..."
    local declare_out
    declare_out=$(SCARB_RUN "${rpc_url}" starkli declare \
        "${SIERRA}" \
        --casm-file "${CASM}" \
        --rpc "${rpc_url}" \
        --watch \
        2>&1) || { echo "${declare_out}"; return 1; }
    echo "${declare_out}" | tail -5
    local class_hash
    class_hash=$(echo "${declare_out}" | grep -Eo '0x[0-9a-fA-F]{40,}' | tail -n1)
    if [ -z "${class_hash}" ]; then
        echo "[deploy-l2/${swarm}] failed to extract class hash"; return 1
    fi
    echo "[deploy-l2/${swarm}] class_hash: ${class_hash}"

    # 4. Deploy via UDC. Constructor takes (l1_commander_addr, l1_verifier_addr)
    #    as felt252. Use anvil[7] (D's commander key, used in DeployL1.s.sol)
    #    cast to felt and L1 Verifier address. Both are passed verbatim — the
    #    bridge layer narrows them to the L1 sender field before delivery.
    local l1_commander="0x14dc79964da2c08b23698b3d3cc7ca32193d9955"
    local l1_verifier="0x3aa5ebb10dc797cac828524e59a333d0a371443c"

    echo "[deploy-l2/${swarm}] deploying contract..."
    echo "  constructor: l1_commander=${l1_commander}, l1_verifier=${l1_verifier}"
    local deploy_out
    deploy_out=$(SCARB_RUN "${rpc_url}" starkli deploy \
        "${class_hash}" \
        "${l1_commander}" \
        "${l1_verifier}" \
        --rpc "${rpc_url}" \
        --watch \
        2>&1)
    echo "${deploy_out}" | tail -5
    local contract_addr
    contract_addr=$(echo "${deploy_out}" | grep -E "deployed at address" | grep -Eo '0x[0-9a-fA-F]{40,}' | head -n1)
    if [ -z "${contract_addr}" ]; then
        echo "[deploy-l2/${swarm}] failed to extract contract address"; return 1
    fi
    echo "[deploy-l2/${swarm}] contract_addr: ${contract_addr}"

    # 5. Smoke test — safe_count for a non-existent mission returns 0
    #    (Cairo 1 Map default). Confirms the contract responds to calls.
    echo "[deploy-l2/${swarm}] smoke test: safe_count(0) (should return 0)..."
    SCARB_RUN "${rpc_url}" starkli call \
        "${contract_addr}" safe_count 0 \
        --rpc "${rpc_url}" 2>&1 | tail -3

    # 6. Persist swarm-specific env
    cat > "${env_file}" <<EOF
# Generated by deploy-l2.sh — do not commit
# Swarm: ${swarm}
# Madara: ${madara_host}
CONVOY_PROTOCOL_CLASS_HASH_${swarm^^}=${class_hash}
CONVOY_PROTOCOL_ADDR_${swarm^^}=${contract_addr}
ACCOUNT_ADDR=${ACCOUNT_ADDR}
EOF
    echo "[deploy-l2/${swarm}] OK — wrote .tmp-l2/convoy_l2_${swarm}.env"
    cat "${env_file}"
}

# ── Shared one-time setup (account file + keystore) ─────────────────────────

mkdir -p "${REPO_ROOT}/.tmp-l2"

# Account file
cat > "${REPO_ROOT}/.tmp-l2/account.json" <<EOF
{
  "version": 1,
  "variant": {
    "type": "open_zeppelin",
    "version": 1,
    "public_key": "0x0",
    "legacy": false
  },
  "deployment": {
    "status": "deployed",
    "class_hash": "${ACCOUNT_CLASS}",
    "address": "${ACCOUNT_ADDR}"
  }
}
EOF

# Encrypted keystore from raw key.
printf "%s" "${ACCOUNT_PK}" > "${REPO_ROOT}/.tmp-l2/_pk.txt"
MSYS_NO_PATHCONV=1 docker run --rm \
    --network convoy-l1 \
    -v "${REPO_ROOT}:/work" \
    -w /work \
    convoy-cairo-builder:latest \
    bash -c 'starkli signer keystore from-key /work/.tmp-l2/keystore.json --private-key-stdin --password convoy --force < /work/.tmp-l2/_pk.txt >/dev/null'
rm -f "${REPO_ROOT}/.tmp-l2/_pk.txt"

# Derive public key and inject into account file.
PUBLIC_KEY=$(MSYS_NO_PATHCONV=1 docker run --rm \
    -v "${REPO_ROOT}:/work" \
    -e STARKNET_KEYSTORE_PASSWORD=convoy \
    convoy-cairo-builder:latest \
    starkli signer keystore inspect /work/.tmp-l2/keystore.json --raw --password convoy 2>/dev/null | tail -n1)
if [ -n "${PUBLIC_KEY}" ]; then
    MSYS_NO_PATHCONV=1 docker run --rm \
        -v "${REPO_ROOT}:/work" \
        -e PUBLIC_KEY="${PUBLIC_KEY}" \
        convoy-cairo-builder:latest \
        python3 -c "
import json, os
p = '/work/.tmp-l2/account.json'
d = json.load(open(p))
d['variant']['public_key'] = os.environ['PUBLIC_KEY']
json.dump(d, open(p, 'w'), indent=2)
"
fi

echo "[deploy-l2] account: ${ACCOUNT_ADDR}"

# ── Arg parsing ─────────────────────────────────────────────────────────────
SWARM_FILTER="both"
while [ $# -gt 0 ]; do
    case "$1" in
        --swarm) SWARM_FILTER="$2"; shift 2 ;;
        --swarm=*) SWARM_FILTER="${1#--swarm=}"; shift ;;
        *) echo "[deploy-l2] unknown arg: $1"; exit 2 ;;
    esac
done

case "${SWARM_FILTER}" in
    alpha) deploy_to alpha ;;
    bravo) deploy_to bravo ;;
    both)
        deploy_to alpha
        deploy_to bravo
        # Combined env file with both addresses for downstream tooling.
        {
            grep -h '^CONVOY_PROTOCOL_' "${REPO_ROOT}/.tmp-l2/convoy_l2_alpha.env"
            grep -h '^CONVOY_PROTOCOL_' "${REPO_ROOT}/.tmp-l2/convoy_l2_bravo.env"
            echo "ACCOUNT_ADDR=${ACCOUNT_ADDR}"
        } > "${REPO_ROOT}/.tmp-l2/convoy_l2.env"
        echo
        echo "[deploy-l2] combined .tmp-l2/convoy_l2.env:"
        cat "${REPO_ROOT}/.tmp-l2/convoy_l2.env"
        ;;
    *) echo "[deploy-l2] --swarm must be alpha | bravo | both"; exit 2 ;;
esac

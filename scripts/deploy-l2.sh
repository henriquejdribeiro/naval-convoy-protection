#!/usr/bin/env bash
# =============================================================================
# deploy-l2.sh — declare + deploy convoy_protocol.cairo to the local Madara
#
# Prereqs:
#   - convoy-madara is up (docker compose ... up -d madara)
#   - convoy-cairo-builder image is built (docker build infra/cairo-builder/)
#   - cairo/convoy_protocol/target/dev/ has Sierra+CASM (run `scarb build`)
#
# What it does:
#   1. Drops a starkli account file describing Madara's predeployed account #1
#   2. Drops a raw-key signer (Madara's private key for that account)
#   3. starkli declare → returns class_hash
#   4. starkli deploy  → returns contract_address
#   5. Smoke test: invoke submit_telemetry once and read it back
#   6. Writes /tmp/convoy_l2.env with CONVOY_PROTOCOL_ADDR + CLASS_HASH
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Madara devnet account #1 — pre-funded, OZ-style
ACCOUNT_ADDR="0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d"
ACCOUNT_PK="0x077e56c6dc32d40a67f6f7e6625c8dc5e570abe49c0a24e9202e4ae906abcc07"
ACCOUNT_CLASS="0xe2eb8f5672af4e6a4e8a8f1b44989685e668489b0a25437733756c5a34a1d6"

# Madara JSON-RPC endpoint inside the convoy-l1 docker network.
# Madara serves /rpc/v0.7.1/, v0.8.1/ and v0.9.0/. Starkli 0.4.0 targets
# 0.8.0, so v0.8.1 is the closest match and the one starkli accepts
# without "spec mismatch" warnings.
RPC_URL="http://convoy-madara:9944/rpc/v0.8.1"
RPC_VERSION="0.8.1"

SIERRA="/work/cairo/convoy_protocol/target/dev/convoy_protocol_ConvoyProtocol.contract_class.json"
CASM="/work/cairo/convoy_protocol/target/dev/convoy_protocol_ConvoyProtocol.compiled_contract_class.json"

# Run starkli inside the cairo-builder container, mounted at /work
# so it can see the compiled artefacts.
SCARB_RUN() {
    MSYS_NO_PATHCONV=1 docker run --rm -i \
        --network convoy-l1 \
        -v "${REPO_ROOT}:/work" \
        -e STARKNET_RPC="${RPC_URL}" \
        -e STARKNET_ACCOUNT="/work/.tmp-l2/account.json" \
        -e STARKNET_KEYSTORE="/work/.tmp-l2/keystore.json" \
        -e STARKNET_KEYSTORE_PASSWORD="convoy" \
        -w /work \
        convoy-cairo-builder:latest \
        "$@"
}

mkdir -p "${REPO_ROOT}/.tmp-l2"

# 1. Account file — describes the OZ account so starkli can sign
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

# 2. Encrypted keystore from raw key. Pipe pk into stdin of a wrapper that
#    invokes starkli with --password (avoids the interactive password prompt
#    and works in non-TTY docker exec).
printf "%s" "${ACCOUNT_PK}" > "${REPO_ROOT}/.tmp-l2/_pk.txt"
MSYS_NO_PATHCONV=1 docker run --rm \
    --network convoy-l1 \
    -v "${REPO_ROOT}:/work" \
    -w /work \
    convoy-cairo-builder:latest \
    bash -c 'starkli signer keystore from-key /work/.tmp-l2/keystore.json --private-key-stdin --password convoy --force < /work/.tmp-l2/_pk.txt >/dev/null'
rm -f "${REPO_ROOT}/.tmp-l2/_pk.txt"

# Need the public key in the account file — derive from the private key.
# `inspect --raw` requires the keystore password; pass it explicitly.
PUBLIC_KEY=$(SCARB_RUN starkli signer keystore inspect /work/.tmp-l2/keystore.json --raw --password convoy 2>/dev/null | tail -n1)
if [ -n "${PUBLIC_KEY}" ]; then
    # Patch in-place via the docker container's python (avoids Git-Bash
    # path translation gotchas with native Windows Python).
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

# 3. Declare convoy_protocol — returns class hash (idempotent: starkli skips
#    if the class is already declared and prints the existing hash)
echo "[deploy-l2] declaring convoy_protocol..."
DECLARE_OUT=$(SCARB_RUN starkli declare \
    "${SIERRA}" \
    --casm-file "${CASM}" \
    --rpc "${RPC_URL}" \
    --watch \
    2>&1) || { echo "${DECLARE_OUT}"; exit 1; }

echo "${DECLARE_OUT}" | tail -10
CLASS_HASH=$(echo "${DECLARE_OUT}" | grep -Eo '0x[0-9a-fA-F]{40,}' | tail -n1)
if [ -z "${CLASS_HASH}" ]; then
    echo "[deploy-l2] failed to extract class hash"
    exit 1
fi
echo "[deploy-l2] class_hash: ${CLASS_HASH}"

# 4. Deploy via UDC — no constructor args
echo "[deploy-l2] deploying contract..."
DEPLOY_OUT=$(SCARB_RUN starkli deploy \
    "${CLASS_HASH}" \
    --rpc "${RPC_URL}" \
    --watch \
    2>&1)

echo "${DEPLOY_OUT}" | tail -10
# starkli prints "The contract will be deployed at address <ADDR>" before
# the tx; extract that line specifically (more reliable than "tail of all
# 0x... matches" which catches the tx hash too).
CONTRACT_ADDR=$(echo "${DEPLOY_OUT}" | grep -E "deployed at address" | grep -Eo '0x[0-9a-fA-F]{40,}' | head -n1)
if [ -z "${CONTRACT_ADDR}" ]; then
    echo "[deploy-l2] failed to extract contract address"
    exit 1
fi
echo "[deploy-l2] contract_addr: ${CONTRACT_ADDR}"

# 5. Smoke test — submit one telemetry cell and read it back. starkli
# 0.4.0 takes plain decimal/hex values; type prefixes (u128:/felt:/...)
# are not supported in this version.
echo "[deploy-l2] smoke test: submit_telemetry(2, 2, 4, 3, 4500, 1700000340)"
SCARB_RUN starkli invoke \
    "${CONTRACT_ADDR}" submit_telemetry \
        2 2 4 3 4500 1700000340 \
    --rpc "${RPC_URL}" \
    --watch 2>&1 | tail -5

echo "[deploy-l2] reading back get_cell_count(2, 2)..."
SCARB_RUN starkli call \
    "${CONTRACT_ADDR}" get_cell_count \
        2 2 \
    --rpc "${RPC_URL}" 2>&1 | tail -3

# 6. Persist the addresses for downstream tooling (orchestrator, snos, etc.)
cat > "${REPO_ROOT}/.tmp-l2/convoy_l2.env" <<EOF
# Generated by deploy-l2.sh — do not commit
CONVOY_PROTOCOL_CLASS_HASH=${CLASS_HASH}
CONVOY_PROTOCOL_ADDR=${CONTRACT_ADDR}
ACCOUNT_ADDR=${ACCOUNT_ADDR}
EOF
echo
echo "[deploy-l2] OK — wrote .tmp-l2/convoy_l2.env"
cat "${REPO_ROOT}/.tmp-l2/convoy_l2.env"

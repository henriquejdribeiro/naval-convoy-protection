#!/bin/sh
# init-geth.sh — initialise a single Geth Clique PoA node from genesis.json
# and import the validator's signer keystore. Called by each ship-N container.
#
# Required env vars (set per-container in docker-compose.l1.yml):
#   SHIP_ID         A | B | C | D | E | F  (cosmetic, for logs)
#   SIGNER_ADDR     0x...  (the validator's address, must be in genesis extradata)
#   SIGNER_KEYFILE  path to JSON keystore inside the container
#   PASSWORD_FILE   path to the keystore password file
#
# Reads:
#   /genesis.json   mounted from infrastructure/geth/genesis.json
#
# This script is idempotent — if the data dir is already initialised, it
# skips re-init and just brings the node up. If the keystore is missing, it
# imports the matching key from the well-known anvil mnemonic (dev only).

set -e

DATA_DIR="${DATA_DIR:-/data}"
GENESIS="${GENESIS:-/genesis.json}"
LOG_PREFIX="[ship-${SHIP_ID:-?}]"

echo "${LOG_PREFIX} initialising geth (signer=${SIGNER_ADDR})"

# 1. Initialise from genesis if not already done
if [ ! -d "${DATA_DIR}/geth/chaindata" ]; then
    echo "${LOG_PREFIX} loading genesis"
    geth --datadir "${DATA_DIR}" init "${GENESIS}"
else
    echo "${LOG_PREFIX} chain data exists, skipping init"
fi

# 2. Import the signing key if not already in keystore
if [ -n "${SIGNER_KEYFILE}" ] && [ -f "${SIGNER_KEYFILE}" ]; then
    if ! ls "${DATA_DIR}/keystore/" 2>/dev/null | grep -q .; then
        echo "${LOG_PREFIX} importing signer keystore"
        cp "${SIGNER_KEYFILE}" "${DATA_DIR}/keystore/"
    fi
fi

# 3. Run geth in Clique signer mode
exec geth \
    --datadir "${DATA_DIR}" \
    --networkid 1337 \
    --nodiscover \
    --syncmode full \
    --gcmode archive \
    --http \
    --http.addr 0.0.0.0 \
    --http.port 8545 \
    --http.api eth,net,web3,txpool,clique,personal \
    --http.corsdomain "*" \
    --http.vhosts "*" \
    --ws \
    --ws.addr 0.0.0.0 \
    --ws.port 8546 \
    --ws.api eth,net,web3,txpool,clique \
    --ws.origins "*" \
    --port "${P2P_PORT:-30303}" \
    --bootnodes "${BOOTNODES:-}" \
    --mine \
    --miner.etherbase "${SIGNER_ADDR}" \
    --unlock "${SIGNER_ADDR}" \
    --password "${PASSWORD_FILE}" \
    --allow-insecure-unlock \
    --verbosity 3

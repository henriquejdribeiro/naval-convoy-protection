#!/usr/bin/env bash
# Deploys the real StarkWare 2023_9 (7-builtin "starknet") GPS verifier suite
# on the local Besu chain, from the byte-identical mainnet bytecode + solc-0.6.12
# creation code vendored under contracts/starkware-verifier/.
# Writes the resulting addresses to .tmp-l1/stark-verifier.env (no fork needed).
set -euo pipefail

BESU=${L1_RPC:-http://ship-a:8545}
PK=${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
NET=${DOCKER_NET:-convoy-l1}
DIR=contracts/starkware-verifier
OUT=.tmp-l1/stark-verifier.env
FOUNDRY=ghcr.io/foundry-rs/foundry:latest
INIT_PREFIX=0x600b5981380380925939f3   # minimal "return the trailing runtime" deployer

mkdir -p .tmp-l1

encode() { MSYS_NO_PATHCONV=1 docker run --rm --entrypoint cast "$FOUNDRY" abi-encode "$@" 2>/dev/null; }

# Deploy raw initcode (hex) via a mounted file (avoids the Windows arg-length limit).
deploy_initcode() {  # $1 = initcode (0x...)
  printf '%s' "$1" > .tmp-l1/_init.hex
  MSYS_NO_PATHCONV=1 docker run --rm --network "$NET" -v "$(pwd)/.tmp-l1:/w" --entrypoint sh "$FOUNDRY" \
    -c "cast send --rpc-url $BESU --private-key $PK --legacy --gas-price 0 --create \"\$(cat /w/_init.hex)\"" 2>/dev/null \
    | grep -i '^contractAddress' | awk '{print $2}'
}

# Deploy a stateless contract: wrap its runtime bytecode and deploy.
deploy_stateless() {  # $1 = bytecode file
  local rt; rt=$(tr -d '\n' < "$1"); rt=${rt#0x}
  deploy_initcode "${INIT_PREFIX}${rt}"
}

echo "[deploy-stark] deploying 15 stateless contracts (byte-identical to mainnet 2023_9)..."
MERKLE=$(deploy_stateless $DIR/bytecode/Merkle.hex)
FRI=$(deploy_stateless $DIR/bytecode/Fri.hex)
MEMPAGE=$(deploy_stateless $DIR/bytecode/MemoryPage.hex)
CONSTRAINT=$(deploy_stateless $DIR/bytecode/CpuConstraintPoly.hex)
OODS=$(deploy_stateless $DIR/bytecode/CpuOods.hex)
BOOTLOADER=$(deploy_stateless $DIR/bytecode/Bootloader.hex)
PEDX=$(deploy_stateless $DIR/bytecode/PedersenX.hex)
PEDY=$(deploy_stateless $DIR/bytecode/PedersenY.hex)
ECDX=$(deploy_stateless $DIR/bytecode/EcdsaX.hex)
ECDY=$(deploy_stateless $DIR/bytecode/EcdsaY.hex)
PFR0=$(deploy_stateless $DIR/bytecode/PoseidonFR0.hex)
PFR1=$(deploy_stateless $DIR/bytecode/PoseidonFR1.hex)
PFR2=$(deploy_stateless $DIR/bytecode/PoseidonFR2.hex)
PPR0=$(deploy_stateless $DIR/bytecode/PoseidonPR0.hex)
PPR1=$(deploy_stateless $DIR/bytecode/PoseidonPR1.hex)

source $DIR/hashes.env

echo "[deploy-stark] deploying CpuFrilessVerifier (7-builtin starknet)..."
AUX="[$CONSTRAINT,$PEDX,$PEDY,$ECDX,$ECDY,$PFR0,$PFR1,$PFR2,$PPR0,$PPR1]"
CFV_ARGS=$(encode "f(address[],address,address,address,address,uint256,uint256)" "$AUX" "$OODS" "$MEMPAGE" "$MERKLE" "$FRI" 40 30)
CFV=$(deploy_initcode "$(tr -d '\n' < $DIR/cfv_creation.hex)${CFV_ARGS#0x}")

echo "[deploy-stark] deploying GpsStatementVerifier (2023_9, N_BUILTINS=9)..."
Z=0x0000000000000000000000000000000000000000
CVERIFIERS="[$Z,$Z,$Z,$Z,$Z,$Z,$CFV,$Z]"
GPS_ARGS=$(encode "f(address,address,address[],uint256,uint256,address,uint256)" "$BOOTLOADER" "$MEMPAGE" "$CVERIFIERS" "$HASHED_CAIRO_VERIFIERS" "$SIMPLE_BOOTLOADER_HASH" "$Z" 0)
GPS=$(deploy_initcode "$(tr -d '\n' < $DIR/gps_creation.hex)${GPS_ARGS#0x}")

cat > "$OUT" <<EOF
# StarkWare 2023_9 (7-builtin starknet) verifier suite on Besu - deploy-stark-verifier.sh
GPS_STATEMENT_VERIFIER_ADDR=$GPS
CPU_FRILESS_VERIFIER_ADDR=$CFV
MERKLE_STATEMENT_CONTRACT_ADDR=$MERKLE
FRI_STATEMENT_CONTRACT_ADDR=$FRI
MEMORY_PAGE_FACT_REGISTRY_ADDR=$MEMPAGE
CPU_CONSTRAINT_POLY_ADDR=$CONSTRAINT
CPU_OODS_ADDR=$OODS
CAIRO_BOOTLOADER_PROGRAM_ADDR=$BOOTLOADER
EOF

echo "[deploy-stark] done - addresses written to $OUT:"
cat "$OUT"

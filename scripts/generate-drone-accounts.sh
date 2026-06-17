#!/usr/bin/env bash
# =============================================================================
# generate-drone-accounts.sh — create 5 fresh OZ accounts per swarm and
#                              deploy them on each Madara devnet.
#
# Output:
#   .tmp-l2/drones-alpha.env — DRONE_{1..5}_{ADDR,KEYSTORE,PUBKEY}
#   .tmp-l2/drones-bravo.env — same for the bravo swarm
#   .tmp-l2/drones/{swarm}/{i}/keystore.json  — encrypted keystore per drone
#
# Each drone gets its OWN keypair so submit_telemetry's
#   assert(get_caller_address() == drone_addr[(mid, did)])
# check in convoy_protocol enforces real per-drone authentication.
#
# Why no funding step?
#   Madara is launched with --no-transaction-validation (see docker-compose.l2.yml).
#   Fee deduction is bypassed at the sequencer level, so a brand-new account
#   with 0 balance can still send transactions. Predeployed account #1 only
#   pays for the *deployment bytecode write* (zero-cost in our devnet), it
#   does not transfer any STRK / ETH to the drones.
#
# Prereqs:
#   - convoy-madara-alpha + convoy-madara-bravo are UP and HEALTHY
#       docker compose -f docker-compose.l1.yml -f docker-compose.l2.yml \
#           --profile l2 up -d madara-alpha madara-bravo
#   - convoy-cairo-builder image built (used to run starkli)
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Predeployed Madara devnet account #1 — pre-funded (irrelevant on
# --no-transaction-validation), used here only to broadcast the
# UDC deployment txs for the drone accounts.
DEPLOYER_ADDR="0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d"
DEPLOYER_PK="0x077e56c6dc32d40a67f6f7e6625c8dc5e570abe49c0a24e9202e4ae906abcc07"
DEPLOYER_CLASS="0xe2eb8f5672af4e6a4e8a8f1b44989685e668489b0a25437733756c5a34a1d6"

# OZ account class hash. Madara devnet pre-declares the OZ class at
# genesis, so we don't need to declare it ourselves.
OZ_CLASS_HASH="0x061dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f"

RPC_VERSION="0.8.1"
N_DRONES=5

# Run starkli inside cairo-builder, mounted at /work.
SCARB_RUN() {
    local rpc_url="$1"; shift
    MSYS_NO_PATHCONV=1 docker run --rm \
        --network convoy-l1 \
        -v "${REPO_ROOT}:/work" \
        -e STARKNET_RPC="${rpc_url}" \
        -e STARKNET_KEYSTORE_PASSWORD="convoy" \
        -w /work \
        convoy-cairo-builder:latest \
        "$@"
}

# Deploy a fresh OZ account on the given madara. Inputs:
#   $1 = swarm (alpha/bravo)
#   $2 = drone_id (1..5)
# Side effects: writes keystore.json + .signer files; echoes the new
# account's ContractAddress.
mint_drone_account() {
    local swarm="$1"
    local did="$2"
    local madara_host="convoy-madara-${swarm}"
    local rpc_url="http://${madara_host}:9944/rpc/v${RPC_VERSION}"
    local out_dir="${REPO_ROOT}/.tmp-l2/drones/${swarm}/${did}"

    mkdir -p "${out_dir}"
    local ks="${out_dir}/keystore.json"
    local pk_txt="${out_dir}/_pk.txt"
    local acc_file="${out_dir}/account.json"

    # 1. Generate a fresh raw private key (32 bytes)
    MSYS_NO_PATHCONV=1 docker run --rm \
        -v "${REPO_ROOT}:/work" -w /work \
        convoy-cairo-builder:latest \
        bash -c "starkli signer keystore from-key /work/.tmp-l2/drones/${swarm}/${did}/keystore.json --password convoy --force < <(starkli signer gen-keypair | awk '/Private/ {print \$NF}') >/dev/null"

    # Derive the public key from the keystore
    local pubkey
    pubkey=$(MSYS_NO_PATHCONV=1 docker run --rm \
        -v "${REPO_ROOT}:/work" -w /work \
        -e STARKNET_KEYSTORE_PASSWORD=convoy \
        convoy-cairo-builder:latest \
        starkli signer keystore inspect "${ks#${REPO_ROOT}/}" --raw --password convoy 2>/dev/null | tail -n1)

    # 2. Compute the counterfactual OZ account address from
    #    (class_hash, salt, constructor_calldata = [pubkey])
    #    starkli account oz init writes an account.json with the address.
    MSYS_NO_PATHCONV=1 docker run --rm \
        -v "${REPO_ROOT}:/work" -w /work \
        -e STARKNET_KEYSTORE_PASSWORD=convoy \
        convoy-cairo-builder:latest \
        starkli account oz init "${acc_file#${REPO_ROOT}/}" --keystore "${ks#${REPO_ROOT}/}" --password convoy --force >/dev/null

    # Extract the predicted address from account.json
    local addr
    addr=$(MSYS_NO_PATHCONV=1 docker run --rm \
        -v "${REPO_ROOT}:/work" -w /work \
        convoy-cairo-builder:latest \
        python3 -c "
import json
d = json.load(open('${acc_file#${REPO_ROOT}/}'))
print(d['deployment']['address'])
")

    # 3. Deploy the account by sending a DEPLOY_ACCOUNT tx. starkli does this
    #    via `account deploy`. No funding needed in our --no-transaction-validation
    #    devnet — the fee field is set to 0 and the sequencer accepts it.
    SCARB_RUN "${rpc_url}" \
        starkli account deploy "${acc_file#${REPO_ROOT}/}" \
            --keystore "${ks#${REPO_ROOT}/}" \
            --password convoy \
            --rpc "${rpc_url}" \
            --watch >/dev/null 2>&1 || {
                echo "[mint/${swarm}/${did}] DEPLOY_ACCOUNT failed — falling back to UDC dispatch"
                # Fallback: use deployer account to deploy via UDC
                _udc_deploy_via_account_1 "${swarm}" "${pubkey}" "${addr}" || return 1
            }

    echo "${addr}|${pubkey}|${ks}"
}

# Fallback path: deployer account uses the UDC to spawn the new OZ account.
_udc_deploy_via_account_1() {
    local swarm="$1"
    local pubkey="$2"
    local expected_addr="$3"
    local madara_host="convoy-madara-${swarm}"
    local rpc_url="http://${madara_host}:9944/rpc/v${RPC_VERSION}"
    local salt="0x0"

    # Write deployer keystore + account file (once per swarm; idempotent)
    local dep_dir="${REPO_ROOT}/.tmp-l2/drones/${swarm}/_deployer"
    mkdir -p "${dep_dir}"
    if [ ! -f "${dep_dir}/keystore.json" ]; then
        printf "%s" "${DEPLOYER_PK}" > "${dep_dir}/_pk.txt"
        MSYS_NO_PATHCONV=1 docker run --rm -v "${REPO_ROOT}:/work" -w /work \
            convoy-cairo-builder:latest \
            bash -c "starkli signer keystore from-key /work/.tmp-l2/drones/${swarm}/_deployer/keystore.json --private-key-stdin --password convoy --force < /work/.tmp-l2/drones/${swarm}/_deployer/_pk.txt >/dev/null"
        rm -f "${dep_dir}/_pk.txt"
        cat > "${dep_dir}/account.json" <<EOF
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
    "class_hash": "${DEPLOYER_CLASS}",
    "address": "${DEPLOYER_ADDR}"
  }
}
EOF
    fi

    # starkli deploy <class_hash> <constructor_args> --salt 0x0
    # OZ constructor takes one felt: the public key.
    MSYS_NO_PATHCONV=1 docker run --rm \
        --network convoy-l1 \
        -v "${REPO_ROOT}:/work" -w /work \
        -e STARKNET_RPC="${rpc_url}" \
        -e STARKNET_ACCOUNT="/work/.tmp-l2/drones/${swarm}/_deployer/account.json" \
        -e STARKNET_KEYSTORE="/work/.tmp-l2/drones/${swarm}/_deployer/keystore.json" \
        -e STARKNET_KEYSTORE_PASSWORD="convoy" \
        convoy-cairo-builder:latest \
        starkli deploy \
            "${OZ_CLASS_HASH}" "${pubkey}" \
            --salt "${salt}" \
            --rpc "${rpc_url}" \
            --watch >/dev/null
}

# ── Generate accounts for one swarm ────────────────────────────────────────
generate_for_swarm() {
    local swarm="$1"
    local madara_host="convoy-madara-${swarm}"
    local env_file="${REPO_ROOT}/.tmp-l2/drones-${swarm}.env"

    echo
    echo "======================================================================"
    echo "  Minting ${N_DRONES} drone accounts on ${madara_host}  (swarm=${swarm})"
    echo "======================================================================"

    : > "${env_file}"
    echo "# Generated by generate-drone-accounts.sh — do not commit" >> "${env_file}"
    echo "# Swarm: ${swarm}    Madara: ${madara_host}" >> "${env_file}"
    echo "" >> "${env_file}"

    for did in $(seq 1 ${N_DRONES}); do
        echo "[mint/${swarm}/${did}] generating keypair + deploying account..."
        local result
        result=$(mint_drone_account "${swarm}" "${did}")
        local addr=$(echo "${result}" | cut -d'|' -f1)
        local pub=$(echo "${result}" | cut -d'|' -f2)
        local ks=$(echo "${result}" | cut -d'|' -f3)

        local id_upper="${swarm^^}_DRONE_${did}"
        echo "${id_upper}_ADDR=${addr}"          >> "${env_file}"
        echo "${id_upper}_PUBKEY=${pub}"         >> "${env_file}"
        echo "${id_upper}_KEYSTORE=${ks#${REPO_ROOT}/}" >> "${env_file}"
        echo "" >> "${env_file}"

        echo "[mint/${swarm}/${did}] OK  addr=${addr}"
    done

    echo
    echo "[mint/${swarm}] wrote ${env_file#${REPO_ROOT}/}"
    cat "${env_file}"
}

# ── Argparse ───────────────────────────────────────────────────────────────
SWARM_FILTER="both"
while [ $# -gt 0 ]; do
    case "$1" in
        --swarm) SWARM_FILTER="$2"; shift 2 ;;
        --swarm=*) SWARM_FILTER="${1#--swarm=}"; shift ;;
        *) echo "[mint] unknown arg: $1"; exit 2 ;;
    esac
done

mkdir -p "${REPO_ROOT}/.tmp-l2/drones"

case "${SWARM_FILTER}" in
    alpha) generate_for_swarm alpha ;;
    bravo) generate_for_swarm bravo ;;
    both)
        generate_for_swarm alpha
        generate_for_swarm bravo
        ;;
    *) echo "[mint] --swarm must be alpha | bravo | both"; exit 2 ;;
esac

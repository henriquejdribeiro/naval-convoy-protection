#!/usr/bin/env bash
# =============================================================================
# generate-drone-accounts.sh — create 5 OZ accounts per swarm and deploy
#                              them on each Madara devnet.
#
# Output:
#   .tmp-l2/drones-alpha.env — ALPHA_DRONE_{1..5}_{ADDR,PUBKEY,KEYSTORE}
#   .tmp-l2/drones-bravo.env — BRAVO_DRONE_{1..5}_{ADDR,PUBKEY,KEYSTORE}
#   .tmp-l2/drones/{swarm}/{i}/keystore.json — encrypted keystore per drone
#
# How (and why this differs from DEPLOY_ACCOUNT):
#   We use account #1 (pre-funded by Madara devnet's genesis) to call the
#   Universal Deployer Contract (UDC), which deploys an OZ account with the
#   drone's public key as constructor calldata. The OZ class is the one
#   Madara devnet pre-declares at genesis (class hash $OZ_ACCOUNT_CLASS_HASH).
#
#   Why not `starkli account deploy` (i.e. self-deploy via DEPLOY_ACCOUNT)?
#   The starkli fee-estimation path queries the not-yet-deployed account
#   for its nonce + max_fee, fails, and the tx never reaches the mempool —
#   even under Madara's --no-transaction-validation. Going through account
#   #1 + UDC sidesteps that because account #1 already exists.
#
# Prereqs:
#   - convoy-madara-{alpha,bravo} up and healthy
#   - convoy-cairo-builder image built
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RPC_VERSION="0.8.1"
N_DRONES=5
KEYSTORE_PWD="convoy"

# Madara devnet pre-declared OZ account class. Same on both alpha and bravo
# because both ran with `--devnet` (deterministic genesis state).
OZ_ACCOUNT_CLASS_HASH="0xe2eb8f5672af4e6a4e8a8f1b44989685e668489b0a25437733756c5a34a1d6"

# Pre-funded account #1 (used as the UDC caller — it pays the deployment
# of each drone's OZ account contract).
DEPLOYER_ADDR="0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d"
DEPLOYER_PK="0x077e56c6dc32d40a67f6f7e6625c8dc5e570abe49c0a24e9202e4ae906abcc07"
DEPLOYER_CLASS="${OZ_ACCOUNT_CLASS_HASH}"

# Run starkli inside cairo-builder.
SK() {
    local rpc="$1"; shift
    local rpc_env=""
    [ -n "${rpc}" ] && rpc_env="-e STARKNET_RPC=${rpc}"
    MSYS_NO_PATHCONV=1 docker run --rm \
        --network convoy-l1 \
        -v "${REPO_ROOT}:/work" -w /work \
        -e STARKNET_KEYSTORE_PASSWORD="${KEYSTORE_PWD}" \
        ${rpc_env} \
        convoy-cairo-builder starkli "$@"
}

# Set up a starkli account file + keystore for the deployer (account #1).
# Idempotent: only writes the files once per swarm directory.
prep_deployer_account() {
    local swarm="$1"
    local dep_dir="${REPO_ROOT}/.tmp-l2/drones/${swarm}/_deployer"
    mkdir -p "${dep_dir}"

    if [ ! -f "${dep_dir}/keystore.json" ]; then
        printf "%s" "${DEPLOYER_PK}" > "${dep_dir}/_pk.txt"
        MSYS_NO_PATHCONV=1 docker run --rm \
            -v "${REPO_ROOT}:/work" -w /work \
            convoy-cairo-builder \
            bash -c "starkli signer keystore from-key /work/.tmp-l2/drones/${swarm}/_deployer/keystore.json --private-key-stdin --password ${KEYSTORE_PWD} --force < /work/.tmp-l2/drones/${swarm}/_deployer/_pk.txt >/dev/null"
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
}

mint_drone_account() {
    local swarm="$1"
    local did="$2"
    local rpc_url="http://convoy-madara-${swarm}:9944/rpc/v${RPC_VERSION}"
    local d_rel=".tmp-l2/drones/${swarm}/${did}"
    local out_dir="${REPO_ROOT}/${d_rel}"
    mkdir -p "${out_dir}"
    local ks_rel="${d_rel}/keystore.json"

    # 1. Generate a fresh encrypted keystore (random keypair)
    SK "" signer keystore new --password "${KEYSTORE_PWD}" --force "${ks_rel}" >/dev/null

    # 2. Read the public key out of the keystore (must pass --password
    #    explicitly; `starkli signer keystore inspect` does NOT read
    #    STARKNET_KEYSTORE_PASSWORD even though most other subcommands do).
    local pubkey
    pubkey=$(SK "" signer keystore inspect --raw --password "${KEYSTORE_PWD}" "${ks_rel}" 2>/dev/null | tail -n1 | tr -d '[:space:]')
    [ -z "${pubkey}" ] && { echo "[mint/${swarm}/${did}] could not derive pubkey" >&2; return 1; }

    # 3. Deploy the OZ account via UDC, signed by account #1. Use the
    #    drone_id as the salt so the address is deterministic per (swarm, did).
    local salt
    salt=$(printf "0x%064x" "${did}")
    local deploy_out
    deploy_out=$(MSYS_NO_PATHCONV=1 docker run --rm \
        --network convoy-l1 \
        -v "${REPO_ROOT}:/work" -w /work \
        -e STARKNET_RPC="${rpc_url}" \
        -e STARKNET_ACCOUNT="/work/.tmp-l2/drones/${swarm}/_deployer/account.json" \
        -e STARKNET_KEYSTORE="/work/.tmp-l2/drones/${swarm}/_deployer/keystore.json" \
        -e STARKNET_KEYSTORE_PASSWORD="${KEYSTORE_PWD}" \
        convoy-cairo-builder \
        starkli deploy \
            "${OZ_ACCOUNT_CLASS_HASH}" "${pubkey}" \
            --salt "${salt}" \
            --rpc "${rpc_url}" \
            --watch 2>&1)

    local addr
    addr=$(echo "${deploy_out}" | grep -E "will be deployed at address" | grep -Eo '0x[0-9a-fA-F]+' | head -n1)
    if [ -z "${addr}" ]; then
        {
            echo
            echo "[mint/${swarm}/${did}] failed to extract address. Raw deploy output:"
            echo "${deploy_out}"
        } >&2
        return 1
    fi

    # 4. Verify the contract actually has code on chain. starkli's --watch
    #    sometimes returns "OK" before the deploy tx is fully sealed (or
    #    after a silent timeout), so we explicitly poll class-hash-at the
    #    predicted address until it returns the expected OZ class hash.
    local poll_attempts=20
    local poll_ok=0
    while [ ${poll_attempts} -gt 0 ]; do
        local on_chain
        on_chain=$(MSYS_NO_PATHCONV=1 docker run --rm \
            --network convoy-l1 \
            -e STARKNET_RPC="${rpc_url}" \
            convoy-cairo-builder \
            starkli class-hash-at "${addr}" 2>&1 | tail -n1 | tr -d '[:space:]')
        if [ "${on_chain}" = "${OZ_ACCOUNT_CLASS_HASH}" ] || [ "${on_chain}" = "0x00${OZ_ACCOUNT_CLASS_HASH#0x}" ]; then
            poll_ok=1
            break
        fi
        poll_attempts=$((poll_attempts - 1))
        sleep 3
    done
    if [ ${poll_ok} -eq 0 ]; then
        echo "[mint/${swarm}/${did}] deploy never sealed at ${addr}" >&2
        return 1
    fi

    echo "${addr}|${pubkey}|${ks_rel}"
}

generate_for_swarm() {
    local swarm="$1"
    local env_file="${REPO_ROOT}/.tmp-l2/drones-${swarm}.env"

    echo
    echo "======================================================================"
    echo "  Minting ${N_DRONES} drone accounts on convoy-madara-${swarm}"
    echo "  (deployer: account #1 at ${DEPLOYER_ADDR})"
    echo "======================================================================"

    prep_deployer_account "${swarm}"

    {
        echo "# Generated by generate-drone-accounts.sh — do not commit"
        echo "# Swarm: ${swarm}    Madara: convoy-madara-${swarm}"
        echo ""
    } > "${env_file}"

    for did in $(seq 1 ${N_DRONES}); do
        printf "[mint/%s/%s] deploying drone account..." "${swarm}" "${did}"
        local result
        result=$(mint_drone_account "${swarm}" "${did}") || { echo " FAIL"; continue; }
        local addr pub ks
        addr=$(echo "${result}" | cut -d'|' -f1)
        pub=$(echo "${result}" | cut -d'|' -f2)
        ks=$(echo "${result}" | cut -d'|' -f3)

        local prefix="${swarm^^}_DRONE_${did}"
        {
            echo "${prefix}_ADDR=${addr}"
            echo "${prefix}_PUBKEY=${pub}"
            echo "${prefix}_KEYSTORE=${ks}"
            echo ""
        } >> "${env_file}"

        printf " OK  addr=%s\n" "${addr}"
    done

    echo
    echo "[mint/${swarm}] wrote ${env_file#${REPO_ROOT}/}"
    cat "${env_file}"
}

# ── Arg parsing ─────────────────────────────────────────────────────────────
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

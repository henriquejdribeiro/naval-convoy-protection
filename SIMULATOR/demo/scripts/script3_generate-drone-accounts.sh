#!/usr/bin/env bash
# =============================================================================
# generate-drone-accounts.sh — create 5 OZ accounts per swarm, deploy them
#                              on each Madara devnet, and bootstrap them
#                              with the artefacts + balance needed to send
#                              transactions immediately afterwards.
#
# Output per drone:
#   SIMULATOR/demo/.tmp-l2/drones/{swarm}/{i}/keystore.json — encrypted keystore
#   SIMULATOR/demo/.tmp-l2/drones/{swarm}/{i}/account.json  — starkli account descriptor
#                                              (required by `starkli invoke`)
#   on-chain balance: FUND_AMOUNT_WEI of both ETH and STRK on Madara devnet
#                     (Madara charges tx fees in STRK; without it a tx sits
#                      in RECEIVED forever)
#
# Output per swarm:
#   SIMULATOR/demo/.tmp-l2/drones-{swarm}.env — ALPHA_DRONE_{1..5}_{ADDR,PUBKEY,KEYSTORE}
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
# Why fund the drones inside this script (instead of leaving it to ops)?
#   With zero STRK balance, every signed tx from the drone hangs in the
#   sequencer's mempool indefinitely (Madara silently drops it during
#   block inclusion). Funding right after deploy makes the drone usable
#   in a single command — no manual top-up step before scripts/submit-
#   telemetry.sh.
#
# Prereqs:
#   - convoy-madara-{alpha,bravo} up and healthy
#   - convoy-cairo-builder image built
# =============================================================================


# -e about on first error
# -u about unset variables
# -o pipefail about any command in a pipeline failing
set -euo pipefail

# absolute path to the repo root (parent of this script)
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# Starknet RPC version to use for starkli calls. Madara's RPC is pinned to 0.8.1, so starkli must match.
RPC_VERSION="0.8.1"

# Number of drone accounts to create per swarm. Each account is deployed
N_DRONES=5

# Password for starkli keystore encryption. This is a constant because the
KEYSTORE_PWD="convoy"

# Madara devnet pre-declared OZ account class. Same on both alpha and bravo
# because both ran with `--devnet` (deterministic genesis state).
OZ_ACCOUNT_CLASS_HASH="0xe2eb8f5672af4e6a4e8a8f1b44989685e668489b0a25437733756c5a34a1d6"

# Pre-funded account #1 (used as the UDC caller — it pays the deployment
# of each drone's OZ account contract).
DEPLOYER_ADDR="0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d"
DEPLOYER_PK="0x077e56c6dc32d40a67f6f7e6625c8dc5e570abe49c0a24e9202e4ae906abcc07"
DEPLOYER_CLASS="${OZ_ACCOUNT_CLASS_HASH}"

# Madara devnet pre-deploys two ERC-20 fee tokens at deterministic addresses:
#   ETH  — legacy fee token (still used by some flows)
#   STRK — modern v3 invoke fee token (what Madara actually deducts from
#          for tx fees in this stack — without STRK, every drone tx hangs)
# Both have a `transfer(recipient, low: u128, high: u128)` selector and
# accept the standard ERC-20 amount split.
ETH_TOKEN_ADDR="0x049D36570D4e46f48e99674bd3fcc84644DdD6b96F7C741B1562B82f9e004dC7"
STRK_TOKEN_ADDR="0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"
# 1 ETH + 1 STRK per drone — generous (each submit_telemetry costs ~10^-7 STRK)
FUND_AMOUNT_WEI="1000000000000000000"

# Run starkli inside cairo-builder.
# Wrapper for calls of the form `starkli <subcommand> <args>...` (e.g. `starkli signer keystore new ...`).
# Two modes: local crypto ops(empty RPC) or on-chain ops (Madara RPC). The starkli container is already built and tagged as convoy-cairo-builder.
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

# The deployer account (#1) is held in the swarm's RELAY SHIP volume — ship F
# relays alpha, ship B relays bravo. Ships stay with the convoy (never
# forward-deployed like drones), so this key never rides a capturable asset and
# never touches the host filesystem.
relay_key_vol() {
    case "$1" in
        alpha) echo "convoy-ship-f-key" ;;    # ship F = alpha relay
        bravo) echo "convoy-ship-b-key" ;;    # ship B = bravo relay
        *) echo "convoy-provisioner-key" ;;
    esac
}

# Import account #1 into the relay ship's volume if absent. PK is piped via stdin
# (never a host file); keystore lands only inside the volume. Idempotent.
ensure_relay_deployer() {
    local keyvol="$1"
    if MSYS_NO_PATHCONV=1 docker run --rm -v "${keyvol}:/key" \
            convoy-cairo-builder test -f /key/keystore.json 2>/dev/null; then
        return 0
    fi
    echo "[mint] importing deployer key into relay-ship volume ${keyvol} (host never keeps it)" >&2
    printf "%s" "${DEPLOYER_PK}" | MSYS_NO_PATHCONV=1 docker run --rm -i \
        -v "${keyvol}:/key" convoy-cairo-builder \
        bash -c "starkli signer keystore from-key /key/keystore.json --private-key-stdin --password ${KEYSTORE_PWD} --force >/dev/null"
    MSYS_NO_PATHCONV=1 docker run --rm -i -v "${keyvol}:/key" \
        convoy-cairo-builder sh -c 'cat > /key/account.json' <<EOF
{
  "version": 1,
  "variant": { "type": "open_zeppelin", "version": 1, "public_key": "0x0", "legacy": false },
  "deployment": { "status": "deployed", "class_hash": "${DEPLOYER_CLASS}", "address": "${DEPLOYER_ADDR}" }
}
EOF
}

mint_drone_account() {
    local swarm="$1"
    local did="$2"
    local rpc_url="http://convoy-madara-${swarm}:9944/rpc/v${RPC_VERSION}"
    local d_rel="SIMULATOR/demo/.tmp-l2/drones/${swarm}/${did}"
    local out_dir="${REPO_ROOT}/${d_rel}"
    mkdir -p "${out_dir}"
    local ks_rel="${d_rel}/keystore.json"

    # Does this drone have its own signer machine? If so, mint the key INSIDE
    # it — born in the machine's volume, host never sees the private key.
    # Otherwise fall back to the legacy host-side mint.
    local MACHINE="convoy-machine-${swarm}-${did}"
    local in_machine=0
    docker ps --format '{{.Names}}' | grep -qx "${MACHINE}" && in_machine=1

    local pubkey
    if [ "${in_machine}" -eq 1 ]; then
        echo "[mint/${swarm}/${did}] minting key INSIDE ${MACHINE} (host never sees it)" >&2
        ks_rel="${MACHINE}:/key/keystore.json"   # key lives in the machine's volume, NOT on host
        MSYS_NO_PATHCONV=1 docker exec "${MACHINE}" \
            starkli signer keystore new --password "${KEYSTORE_PWD}" --force /key/keystore.json >/dev/null
        pubkey=$(MSYS_NO_PATHCONV=1 docker exec "${MACHINE}" \
            starkli signer keystore inspect --raw --password "${KEYSTORE_PWD}" /key/keystore.json 2>/dev/null | tail -n1 | tr -d '[:space:]')
    else
        SK "" signer keystore new --password "${KEYSTORE_PWD}" --force "${ks_rel}" >/dev/null
        pubkey=$(SK "" signer keystore inspect --raw --password "${KEYSTORE_PWD}" "${ks_rel}" 2>/dev/null | tail -n1 | tr -d '[:space:]')
    fi
    [ -z "${pubkey}" ] && { echo "[mint/${swarm}/${did}] could not derive pubkey" >&2; return 1; }

    # 3. Deploy the OZ account via UDC, signed by account #1. Use the
    #    drone_id as the salt so the address is deterministic per (swarm, did).
    local salt
    salt=$(printf "0x%064x" "${did}")
    local deploy_out
    deploy_out=$(MSYS_NO_PATHCONV=1 docker run --rm \
        --network convoy-l1 \
        -v "${KEYVOL}:/key" \
        -e STARKNET_RPC="${rpc_url}" \
        -e STARKNET_ACCOUNT="/key/account.json" \
        -e STARKNET_KEYSTORE="/key/keystore.json" \
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

    # 5. Write account.json where the drone can reach it (its own volume when
    #    it has a machine; else the host dir as before).
    if [ "${in_machine}" -eq 1 ]; then
        MSYS_NO_PATHCONV=1 docker exec -i "${MACHINE}" sh -c 'cat > /key/account.json' <<EOF
{
  "version": 1,
  "variant": { "type": "open_zeppelin", "version": 1, "public_key": "${pubkey}", "legacy": false },
  "deployment": { "status": "deployed", "class_hash": "${OZ_ACCOUNT_CLASS_HASH}", "address": "${addr}" }
}
EOF
    else
        cat > "${out_dir}/account.json" <<EOF
{
  "version": 1,
  "variant": { "type": "open_zeppelin", "version": 1, "public_key": "${pubkey}", "legacy": false },
  "deployment": { "status": "deployed", "class_hash": "${OZ_ACCOUNT_CLASS_HASH}", "address": "${addr}" }
}
EOF
    fi

    # Funding happens in a separate pass (fund_all_drones) AFTER every drone
    # has been deployed. Doing it inline here causes deployer-nonce races
    # because each fund call uses 2 nonces and starkli's chain-nonce fetch
    # briefly returns stale values between back-to-back txs.

    echo "${addr}|${pubkey}|${ks_rel}"
}

# Bootstrap a freshly-deployed drone with ETH + STRK so its first signed
# tx isn't silently dropped by the sequencer's mempool.
#
# Two single-call `starkli invoke --watch` txs signed by the deployer.
# starkli 0.4.1 does NOT support multi-call positional syntax (no `/`
# separator), so we settle for two sequential confirmations. Each
# returns when ACCEPTED_ON_L2, so when this function returns the drone
# has spendable balance on chain.
fund_drone() {
    local swarm="$1"
    local drone_addr="$2"
    local rpc_url="http://convoy-madara-${swarm}:9944/rpc/v${RPC_VERSION}"

    local token label out rc nonce attempts
    for token in "${STRK_TOKEN_ADDR}" "${ETH_TOKEN_ADDR}"; do
        [ "${token}" = "${STRK_TOKEN_ADDR}" ] && label=STRK || label=ETH

        # Poll the on-chain nonce until it ADVANCES past the value we last
        # used. Madara's "latest" block can briefly trail its mempool
        # immediately after a --watch returns, which is exactly when
        # starkli's auto-nonce fetch races. Explicit polling + passing
        # --nonce eliminates the race.
        attempts=20
        while [ ${attempts} -gt 0 ]; do
            nonce=$(deployer_nonce_hex "${rpc_url}")
            if [ -n "${nonce}" ] && [ "${nonce}" != "${LAST_USED_NONCE_HEX:-}" ]; then
                break
            fi
            attempts=$((attempts - 1))
            sleep 1
        done
        [ -z "${nonce}" ] && {
            echo "[fund/${swarm}] could not fetch deployer nonce" >&2
            return 1
        }

        out=$(MSYS_NO_PATHCONV=1 docker run --rm \
            --network convoy-l1 \
            -v "${KEYVOL}:/key" \
            -e STARKNET_RPC="${rpc_url}" \
            -e STARKNET_ACCOUNT="/key/account.json" \
            -e STARKNET_KEYSTORE="/key/keystore.json" \
            -e STARKNET_KEYSTORE_PASSWORD="${KEYSTORE_PWD}" \
            convoy-cairo-builder \
            starkli invoke "${token}" transfer "${drone_addr}" "${FUND_AMOUNT_WEI}" 0 \
                --rpc "${rpc_url}" --nonce "${nonce}" --watch 2>&1)
        rc=$?
        if [ ${rc} -ne 0 ]; then
            echo "[fund/${swarm}] ${label} transfer FAILED (rc=${rc}):" >&2
            echo "${out}" | tail -6 >&2
            return 1
        fi
        LAST_USED_NONCE_HEX="${nonce}"
    done
    return 0
}

# Fetch the deployer's current nonce as a hex string ("0x...")
deployer_nonce_hex() {
    local rpc_url="$1"
    # Use Madara's JSON-RPC directly — starkli's `signer keystore-nonce`
    # would also work but adds another container invocation per call.
    MSYS_NO_PATHCONV=1 docker run --rm --network convoy-l1 \
        curlimages/curl:latest \
        -s -X POST "${rpc_url}" \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"starknet_getNonce\",\"params\":[\"latest\",\"${DEPLOYER_ADDR}\"],\"id\":1}" 2>/dev/null \
        | grep -oE '"result":"0x[0-9a-fA-F]+"' | cut -d'"' -f4
}

generate_for_swarm() {
    local swarm="$1"
    local env_file="${REPO_ROOT}/SIMULATOR/demo/.tmp-l2/drones-${swarm}.env"
    local KEYVOL; KEYVOL=$(relay_key_vol "${swarm}")   # deploy/fund read this

    echo
    echo "======================================================================"
    echo "  Minting ${N_DRONES} drone accounts on convoy-madara-${swarm}"
    echo "  (deployer: account #1 at ${DEPLOYER_ADDR})"
    echo "======================================================================"

    ensure_relay_deployer "${KEYVOL}"

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

    # Second pass: fund every successfully-deployed drone with STRK + ETH.
    # Failures here are NON-FATAL: the account exists on chain and the env
    # file is already written, so the user can re-run `fund_drone` manually
    # or top up via any other route. We just print a clear warning.
    fund_all_drones "${swarm}"
}

# Iterate the swarm's env file and fund each drone the deployer issued.
# Sequential STRK-then-ETH per drone, with --watch on every tx to make
# sure starkli's next nonce fetch sees the previous tx as mined.
fund_all_drones() {
    local swarm="$1"
    local env_file="${REPO_ROOT}/SIMULATOR/demo/.tmp-l2/drones-${swarm}.env"
    local addrs
    addrs=$(grep -E "^[A-Z]+_DRONE_[0-9]+_ADDR=" "${env_file}" | cut -d= -f2)
    [ -z "${addrs}" ] && return 0

    echo
    echo "[fund/${swarm}] funding ${N_DRONES} drones with ${FUND_AMOUNT_WEI} wei STRK + ETH each..."
    local i=0
    for addr in ${addrs}; do
        i=$((i + 1))
        printf "  [%s/%d] %s... " "${i}" "${N_DRONES}" "${addr}"
        if fund_drone "${swarm}" "${addr}"; then
            printf "OK\n"
        else
            printf "FAIL (drone still deployed; fund manually before submit-telemetry)\n"
        fi
    done
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

mkdir -p "${REPO_ROOT}/SIMULATOR/demo/.tmp-l2/drones"

case "${SWARM_FILTER}" in
    alpha) generate_for_swarm alpha ;;
    bravo) generate_for_swarm bravo ;;
    both)
        generate_for_swarm alpha
        generate_for_swarm bravo
        ;;
    *) echo "[mint] --swarm must be alpha | bravo | both"; exit 2 ;;
esac

#!/bin/bash
# =============================================================================
# entrypoint.sh — naval-convoy Phase 3 prover-api
#
# Adapted from verifiable_grid/infrastructure/prover-api/entrypoint.sh.
# Pipeline:
#   1. Compile safe_area_verify.cairo (proof_mode)         once at boot
#   2. Run cairo-run with program_input → trace + memory + public_input
#   3. cpu_air_prover                  → STARK proof (~500 KB – 1 MB)
#   4. cpu_air_verifier                → off-chain verification (gate!)
#   5. stone-cli serialize-proof       → Ethereum-shaped proof JSON
#      (== stark_evm_adapter gen-annotated-proof, byte-identical)
#   6. path-a-runner                   → 4-phase StarkWare submission
#      (uses stark-evm-adapter Rust library for split_fri_merkle_statements)
#   7. submit_proof_l1.py              → Verifier.registerSafeProof on L1
#
# Triggers:
#   - On boot, runs the canonical SAFE input from sample_input.json
#   - Watches /proofs/prove_trigger for re-runs (write a tag, touch the file)
#
# Output volume layout (/proofs):
#   safe_area_verify.json    compiled Cairo program (program_hash source)
#   trace.bin / memory.bin   raw execution artefacts
#   public_input.json        StarkWare public inputs
#   private_input.json       StarkWare private inputs
#   proof.json               Stone STARK proof
#   evm_proof.json           EVM-adapted proof (consumed by submit_proof_l1)
#   proof_meta.json          summary (proofSize, nSteps, timestamps)
#   submit_log.json          tx hash + factHash from L1 submission
# =============================================================================
set -e

OUTPUT_DIR="${STONE_OUTPUT_DIR:-/proofs}"
# Cairo VM layout: `starknet`. 7 builtins (output, pedersen, range_check,
# ecdsa, bitwise, ec_op, poseidon -- no keccak). This is the canonical
# StarkNet layout that mainnet GpsStatementVerifier's cairoVerifierId=6
# slot was built for, and what stark-evm-adapter's annotated_proof.json
# fixture targets. Our bootloader is keccak-stripped (via
# scripts/strip-keccak-from-bootloader.py) to match.
LAYOUT="starknet"
CAIRO_LAYOUT="starknet"
INPUT_FILE_DEFAULT="${OUTPUT_DIR}/program_input.json"

mkdir -p "${OUTPUT_DIR}"

echo "============================================"
echo "  naval-convoy Phase 3 Stone prover"
echo "  cairo-compile + cairo-run + stone-cli prove-bootloader"
echo "  + stone-cli serialize-proof + path-a-runner L1 submission"
echo "============================================"

# ── Tool sanity ────────────────────────────────────────────────────────
echo "[*] Checking tools..."
cpu_air_prover    --help > /dev/null 2>&1 && echo "    cpu_air_prover    : OK"
cpu_air_verifier  --help > /dev/null 2>&1 && echo "    cpu_air_verifier  : OK"
stone-cli --help          > /dev/null 2>&1 && echo "    stone-cli         : OK"
path-a-runner --help      > /dev/null 2>&1 && echo "    path-a-runner     : OK" || true
cast --version            > /dev/null 2>&1 && echo "    cast              : OK"
python3 -c "import starkware; print('    cairo-lang        : ' + __import__('importlib.metadata', fromlist=['version']).version('cairo-lang'))"
echo ""

# ── Step 1: compile safe_area_verify.cairo (once) ──────────────────────
echo "[*] Step 1/6: compile safe_area_verify.cairo (proof mode)"
cairo-compile /app/safe_area_verify.cairo \
    --output "${OUTPUT_DIR}/safe_area_verify.json" \
    --proof_mode
python3 -c "
import json
p = json.load(open('${OUTPUT_DIR}/safe_area_verify.json'))
print('    builtins:', p.get('builtins', []))
print('    code size:', len(p.get('data', [])), 'felts')
"
echo ""

# Default input — copy sample if no program_input.json yet
if [ ! -f "${INPUT_FILE_DEFAULT}" ]; then
    echo "[*] No program_input.json — using sample_input.json"
    cp /app/sample_input.json "${INPUT_FILE_DEFAULT}"
fi

# ── prove() — generate + verify + adapt + submit a single proof ────────
prove_one() {
    local INPUT_PATH="$1"
    local TAG="${2:-default}"

    echo ""
    echo "============================================"
    echo "  Proving — tag=${TAG}"
    echo "  input: ${INPUT_PATH}"
    echo "============================================"

    # 2a. cairo-run → PIE with program_input baked in. stone-cli accepts
    #     either Cairo programs OR pre-computed PIEs; only the PIE flow
    #     carries per-run program_input through the bootloader interface.
    echo "[*] Step 2a/6: cairo-run --cairo_pie_output (input baked in)"
    cairo-run \
        --program="${OUTPUT_DIR}/safe_area_verify.json" \
        --layout="${CAIRO_LAYOUT}" \
        --program_input="${INPUT_PATH}" \
        --print_output \
        --cairo_pie_output="${OUTPUT_DIR}/safe_area_verify.pie"

    # 2b. stone-cli prove-bootloader — zksecurity's canonical user-facing CLI.
    #     Internally wraps the PIE in the canonical simple bootloader (no
    #     custom hash to track — stone-cli ships with the bootloader whose
    #     hash matches what mainnet GpsStatementVerifier was deployed with),
    #     then runs cpu_air_prover + cpu_air_verifier internally.
    #     Outputs: proof.json + fact_topologies.json
    echo "[*] Step 2b/6: stone-cli prove-bootloader"
    cat > "${OUTPUT_DIR}/prover_config.json" << 'EOCFG'
{
    "constraint_polynomial_task_size": 256,
    "n_out_of_memory_merkle_layers": 1,
    "table_prover_n_tasks_per_segment": 32,
    "cached_lde_config": {"store_full_lde": false, "use_fft_for_eval": false}
}
EOCFG
    # ── Canonical bootloader cpu_air_params.json + explicit MSB commitment.
    #
    # The canonical file at stone-cli/tests/configs/bootloader_cpu_air_params.json
    # has NO commitment_hash field, which lets cpu_air_prover fall back to its
    # built-in default of `keccak256_masked160_msb` (per
    # starkware-libs/stone-prover prover_main_helper_impl.cc).
    #
    # stone-cli's CLI flag struct has a HARDCODED default of
    #   #[clap(long="commitment_hash", default_value="keccak256-masked160-lsb")]
    # — so even passing NO --commitment_hash flag means the CLI hands the
    # prover `_lsb`, overriding the binary's MSB default. The only way to
    # restore canonical MSB output (which is what mainnet GpsStatementVerifier
    # was deployed to verify) is via --parameter_file: that path bypasses
    # stone-cli's CLI defaults entirely and passes the JSON straight to the
    # prover binary, where the absence of commitment_hash → MSB default.
    #
    # Stone-cli ships with `commitment_hash: keccak256_masked160_lsb` as the
    # canonical default. We match that here so the contract-side LSB patch
    # (contracts/lib/starkware-mainnet/PATCH.md) lines up with the prover
    # output without further configuration.
    cat > "${OUTPUT_DIR}/params.json" << 'EOPRM'
{
    "field": "PrimeField0",
    "channel_hash": "keccak256",
    "commitment_hash": "keccak256_masked160_lsb",
    "pow_hash": "keccak256",
    "page_hash": "pedersen",
    "verifier_friendly_channel_updates": false,
    "verifier_friendly_commitment_hash": "keccak256_masked160_lsb",
    "n_verifier_friendly_commitment_layers": 0,
    "stark": {
        "fri": {
            "fri_step_list": [0, 2, 2, 2, 2, 2, 2, 2, 2],
            "last_layer_degree_bound": 32,
            "n_queries": 18,
            "proof_of_work_bits": 30
        },
        "log_n_cosets": 4
    },
    "use_extension_field": false
}
EOPRM

    cd "${OUTPUT_DIR}" && stone-cli prove-bootloader \
        --cairo_pies safe_area_verify.pie \
        --layout "${CAIRO_LAYOUT}" \
        --prover_config_file prover_config.json \
        --parameter_file params.json \
        --output proof.json \
        --fact_topologies_output fact_topologies.json
    cd /

    PROOF_SIZE=$(stat -c%s "${OUTPUT_DIR}/proof.json" 2>/dev/null || echo 0)
    echo "    proof bytes: ${PROOF_SIZE}"

    # 4. stone-cli verify — produces annotation_file + extra_output_file
    #    needed by stark_evm_adapter / stone-cli serialize-proof. This is
    #    Stone's own off-chain verifier; failure here means the proof is
    #    bad and we should abort before submitting on-chain.
    echo "[*] Step 4/6: stone-cli verify (off-chain gate + annotation extraction)"
    # --stone_version v5: stone-cli's prove command uses v5 internally;
    # verify defaults to v6. Mismatch fails with "Out of domain sampling
    # verification failed" because v5/v6 use different OOD logic.
    cd "${OUTPUT_DIR}" && stone-cli verify \
        --proof proof.json \
        --annotation_file annotation.txt \
        --extra_output_file extra_annotation.txt \
        --stone_version v5 \
        && echo "    verification: PASSED" \
        || { echo "    verification: FAILED"; cd /; return 1; }
    cd /

    # 5. stone-cli serialize-proof --network ethereum → Ethereum-shaped proof.
    #    Per stone-cli's architecture diagram, the "Proof serializer for
    #    Ethereum" lives INSIDE stone-cli itself. Empirically byte-identical
    #    to stark_evm_adapter gen-annotated-proof (same SHA-256), so we use
    #    stone-cli's own serializer — one binary, one source of truth.
    #    path-a-runner still consumes evm_proof.json downstream; the
    #    split-into-4-phases logic lives in the stark-evm-adapter Rust
    #    library (linked into path-a-runner), not the CLI.
    echo "[*] Step 5/7: stone-cli serialize-proof --network ethereum"
    cd "${OUTPUT_DIR}" && stone-cli serialize-proof \
        --proof proof.json \
        --network ethereum \
        --annotation_file annotation.txt \
        --extra_output_file extra_annotation.txt \
        --output evm_proof.json \
        && echo "    Ethereum-serialized proof written: evm_proof.json" \
        || { echo "    Ethereum serialization FAILED"; cd /; return 1; }
    cd /

    # 5b. STAGE A — path-a-runner submits the four StarkWare pre-registration
    #     phases + the main GPS proof to the deployed StarkWare contracts
    #     on our local Geth. On success, GpsStatementVerifier.isValid(factHash)
    #     returns true, which the convoy Verifier reads in Stage B.
    #
    #     Contract addresses come from env vars (set by docker-compose from
    #     the DeployStarkVerifier.s.sol deployment summary). Skipping is
    #     opt-in via SKIP_STAGE_A=1 (useful only for legacy mock-mode tests;
    #     production / thesis-defence runs must NEVER skip Stage A).
    if [ "${SKIP_STAGE_A:-0}" = "1" ]; then
        echo "[!] Step 5b/7: STAGE A SKIPPED (SKIP_STAGE_A=1). Verifier.sol will revert."
    else
        echo "[*] Step 5b/7: STAGE A — path-a-runner against StarkWare contracts"
        : "${URL:?URL env var required (L1 RPC, e.g. http://ship-a:8545)}"
        : "${PRIVATE_KEY:?PRIVATE_KEY env var required (relay-ship key)}"
        : "${MERKLE_STATEMENT_CONTRACT_ADDR:?MERKLE_STATEMENT_CONTRACT_ADDR env var required}"
        : "${FRI_STATEMENT_CONTRACT_ADDR:?FRI_STATEMENT_CONTRACT_ADDR env var required}"
        : "${MEMORY_PAGE_FACT_REGISTRY_ADDR:?MEMORY_PAGE_FACT_REGISTRY_ADDR env var required}"
        : "${GPS_STATEMENT_VERIFIER_ADDR:?GPS_STATEMENT_VERIFIER_ADDR env var required}"

        ANNOTATED_PROOF="${OUTPUT_DIR}/evm_proof.json" \
        FACT_TOPOLOGIES="${OUTPUT_DIR}/fact_topologies.json" \
        URL="${URL}" \
        PRIVATE_KEY="${PRIVATE_KEY}" \
        MERKLE_STATEMENT_CONTRACT_ADDR="${MERKLE_STATEMENT_CONTRACT_ADDR}" \
        FRI_STATEMENT_CONTRACT_ADDR="${FRI_STATEMENT_CONTRACT_ADDR}" \
        MEMORY_PAGE_FACT_REGISTRY_ADDR="${MEMORY_PAGE_FACT_REGISTRY_ADDR}" \
        GPS_STATEMENT_VERIFIER_ADDR="${GPS_STATEMENT_VERIFIER_ADDR}" \
            path-a-runner 2>&1 | tee "${OUTPUT_DIR}/path_a_log.txt"

        if grep -q "DONE: proof verified on L1" "${OUTPUT_DIR}/path_a_log.txt"; then
            echo "    STAGE A: fact registered on GpsStatementVerifier"
        else
            echo "    STAGE A FAILED — submit_proof_l1.py will revert on isValid check"
            return 1
        fi
    fi

    # Summary metadata
    python3 -c "
import json, os
pub = json.load(open('${OUTPUT_DIR}/public_input.json'))
meta = {
    'proofSize':  os.path.getsize('${OUTPUT_DIR}/proof.json'),
    'nSteps':     pub['n_steps'],
    'tag':        '${TAG}',
    'inputFile':  '${INPUT_PATH}',
    'timestamp':  __import__('datetime').datetime.now().isoformat(),
}
json.dump(meta, open('${OUTPUT_DIR}/proof_meta.json', 'w'), indent=2)
print('[+] proof_meta.json written')
"

    # 6. STAGE B — application-level bookkeeping on the convoy Verifier.
    #    Tiny tx, no proof bytes. Sends only the 11-field SafeProofInputs.
    #    Verifier.sol asserts starkVerifier.isValid(factHash) == true
    #    (which is the case iff Stage A ran successfully above), then
    #    runs the strip-bounds check + Registry update + aggregation.
    echo "[*] Step 6/7: STAGE B — submit registerSafeProof to convoy Verifier"
    python3 /app/submit_proof_l1.py "${OUTPUT_DIR}" "${INPUT_PATH}" \
        2>&1 | tee "${OUTPUT_DIR}/submit_log.txt"

    echo ""
    echo "================================================"
    echo "  PIPELINE COMPLETE"
    echo "  proof:     ${OUTPUT_DIR}/proof.json"
    echo "  evm_proof: ${OUTPUT_DIR}/evm_proof.json"
    echo "  meta:      ${OUTPUT_DIR}/proof_meta.json"
    echo "  submit:    ${OUTPUT_DIR}/submit_log.txt"
    echo "================================================"
}

# Boot run
prove_one "${INPUT_FILE_DEFAULT}" "boot-bravo-safe" || \
    echo "[!] boot prove failed — container stays alive for debugging"

echo ""
echo "[*] Container alive. Re-prove with:"
echo "      docker exec convoy-prover-api sh -c 'echo TAG > /proofs/prove_trigger'"
echo ""

# ── Watch loop for on-demand proving ───────────────────────────────────
#
# prove_trigger can carry either:
#   - a plain tag (e.g. "manual")              → re-proves INPUT_FILE_DEFAULT
#   - a path-bearing line like                  → uses that input
#         input=/proofs/missions/both-safe/alpha3_input.json tag=alpha3
#     so the operator can drive the 10-drone aggregation by writing one
#     trigger per drone.
#   - the literal "ALL" or one of the scenario shortcuts below — each
#     iterates the matching scenario directory under /proofs/missions/.
#     Directory names mirror generate-mission.py's --scenario verbatim
#     so you can `python3 scripts/generate-mission.py --scenario foo
#     --output-dir /proofs/missions/foo/` and then trigger ALL_FOO.
#
#       ALL or ALL_SAFE        →  missions/both-safe/          (10/10 SAFE)
#       ALL_UNSAFE             →  missions/both-unsafe/        (alpha3+bravo3 fail)
#       ALL_MIXED              →  missions/mixed/              (single-flank fail)
#       ALL_VANISH             →  missions/alpha-dropout-vanish/
#                                   alpha3 has NO input file - "missing"
#                                   logged, no proof submitted; alpha
#                                   safeCount caps at 4, convoy HOLDS
#       ALL_MIDFLIGHT          →  missions/alpha-dropout-midflight/
#                                   alpha3 sweeps ~40% then vanishes -
#                                   partial-coverage proof lands with
#                                   verdict=0; safeCount unchanged
#       ALL_DUAL_DROPOUT       →  missions/dual-dropout/
#                                   alpha3 vanishes + bravo4 midflight -
#                                   the worst-case scenario, both swarms
#                                   stay in pending state
#
# A vanish_manifest.json in the scenario directory (emitted by
# generate-mission.py) is announced at the top of the run so the
# operator sees the sector blackouts before any proving starts.
while true; do
    if [ -f "${OUTPUT_DIR}/prove_trigger" ]; then
        TRIGGER=$(cat "${OUTPUT_DIR}/prove_trigger" 2>/dev/null || echo "manual")
        rm -f "${OUTPUT_DIR}/prove_trigger"

        # Parse "input=... tag=..." form, else fall back to scenario / tag
        INPUT_OVERRIDE=""
        SCENARIO_DIR=""
        TAG="manual"
        case "${TRIGGER}" in
            input=*)
                INPUT_OVERRIDE=$(echo "${TRIGGER}" | sed -nE 's/.*input=([^ ]+).*/\1/p')
                TAG=$(echo "${TRIGGER}" | sed -nE 's/.*tag=([^ ]+).*/\1/p')
                [ -z "${TAG}" ] && TAG=$(basename "${INPUT_OVERRIDE}" _input.json)
                ;;
            ALL|ALL_SAFE)         SCENARIO_DIR="${OUTPUT_DIR}/missions/both-safe" ;;
            ALL_UNSAFE)           SCENARIO_DIR="${OUTPUT_DIR}/missions/both-unsafe" ;;
            ALL_MIXED)            SCENARIO_DIR="${OUTPUT_DIR}/missions/mixed" ;;
            ALL_VANISH|ALL_DROPOUT_VANISH)
                                  SCENARIO_DIR="${OUTPUT_DIR}/missions/alpha-dropout-vanish" ;;
            ALL_MIDFLIGHT|ALL_DROPOUT_MIDFLIGHT)
                                  SCENARIO_DIR="${OUTPUT_DIR}/missions/alpha-dropout-midflight" ;;
            ALL_DUAL_DROPOUT|ALL_DROPOUT)
                                  SCENARIO_DIR="${OUTPUT_DIR}/missions/dual-dropout" ;;
            *)                    TAG="${TRIGGER}" ;;
        esac

        if [ -n "${SCENARIO_DIR}" ]; then
            echo "[*] ALL-scenarios run from ${SCENARIO_DIR}"

            # Announce the vanish manifest up front (operator awareness)
            MANIFEST="${SCENARIO_DIR}/vanish_manifest.json"
            if [ -f "${MANIFEST}" ]; then
                N_VANISHED=$(python3 -c "
import json, sys
try:
    m = json.load(open('${MANIFEST}'))
    print(len(m.get('vanished', [])))
except Exception:
    print(0)
")
                if [ "${N_VANISHED}" != "0" ]; then
                    echo "[!] vanish manifest: ${N_VANISHED} drone(s) reported missing - sectors will stay blind"
                    python3 -c "
import json
m = json.load(open('${MANIFEST}'))
for v in m.get('vanished', []):
    print(f\"      WANTED: {v['swarm']}{v['drone_id']} - sector \"
          f\"x=[{v['strip_x_start']},{v['strip_x_end']}) \"
          f\"y=[{v['strip_y_start']},{v['strip_y_end']}) blind\")
"
                fi
            fi

            for SWARM in alpha bravo; do
                for IDX in 1 2 3 4 5; do
                    F="${SCENARIO_DIR}/${SWARM}${IDX}_input.json"
                    if [ -f "${F}" ]; then
                        prove_one "${F}" "${SWARM}${IDX}" \
                            || echo "[!] prove failed for ${SWARM}${IDX}"
                    else
                        echo "[!] no telemetry for ${SWARM}${IDX} (expected at ${F}) - skipping"
                    fi
                done
            done
            SCENARIO_DIR=""
        elif [ -n "${INPUT_OVERRIDE}" ] && [ -f "${INPUT_OVERRIDE}" ]; then
            prove_one "${INPUT_OVERRIDE}" "${TAG}" || echo "[!] prove failed"
        else
            prove_one "${INPUT_FILE_DEFAULT}" "${TAG}" || echo "[!] prove failed"
        fi

        echo "DONE" > "${OUTPUT_DIR}/prove_result"
    fi
    sleep 1
done

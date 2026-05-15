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
#   5. stark_evm_adapter               → EVM-compatible "fact" tuple
#   6. submit_proof_l1.py              → Verifier.registerSafeProof on L1
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
# Cairo layout — matches StarkWare's pre-generated on-chain verifier
# at lib/starkex-contracts/evm-verifier/.../cpu/layout6 ("starknet"
# layout, LAYOUT_CODE = 8319381555716711796 = ASCII "starknet"). Our
# safe_area_verify.cairo only uses {output, range_check, poseidon},
# all three of which are in layout6; the keccak builtin (previously
# enabled via `starknet_with_keccak`) was never used by our program.
LAYOUT="starknet"
CAIRO_LAYOUT="starknet"
INPUT_FILE_DEFAULT="${OUTPUT_DIR}/program_input.json"

mkdir -p "${OUTPUT_DIR}"

echo "============================================"
echo "  naval-convoy Phase 3 Stone prover"
echo "  cairo-compile + cairo-run + cpu_air_prover"
echo "  + stark_evm_adapter + L1 fact submission"
echo "============================================"

# ── Tool sanity ────────────────────────────────────────────────────────
echo "[*] Checking tools..."
cpu_air_prover    --help > /dev/null 2>&1 && echo "    cpu_air_prover    : OK"
cpu_air_verifier  --help > /dev/null 2>&1 && echo "    cpu_air_verifier  : OK"
stark_evm_adapter --help > /dev/null 2>&1 && echo "    stark_evm_adapter : OK" || true
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

    # 2a. cairo-run → produce a PIE (Position-Independent Executable) of
    #     safe_area_verify with program_input baked in. The bootloader
    #     consumes this PIE rather than a raw program JSON, because raw
    #     programs cannot carry per-run program_input through the
    #     bootloader interface.
    echo "[*] Step 2a/6: cairo-run → PIE for the bootloader"
    cairo-run \
        --program="${OUTPUT_DIR}/safe_area_verify.json" \
        --layout="${CAIRO_LAYOUT}" \
        --program_input="${INPUT_PATH}" \
        --print_output \
        --cairo_pie_output="${OUTPUT_DIR}/safe_area_verify.pie"

    # 2b. convoy-bootloader-cli → wrap the task PIE in the simple bootloader.
    #     The bootloader's public output starts with the SIMPLE_BOOTLOADER_HASH
    #     and HASHED_CAIRO_VERIFIERS constants that GpsStatementVerifier was
    #     deployed with — without this wrap, the on-chain verifier rejects
    #     the proof at registerPublicMemoryMainPage. Also emits
    #     fact_topologies.json for the Rust submitter.
    echo "[*] Step 2b/6: convoy-bootloader-cli (bootloader wraps the PIE)"
    convoy-bootloader-cli \
        --task-pie    "${OUTPUT_DIR}/safe_area_verify.pie" \
        --output-dir  "${OUTPUT_DIR}" \
        --layout      "${CAIRO_LAYOUT}" \
        --bootloader-hash 0xd875840ac697dbeedb3d4c8f2a61889bc1d5f1af91e67a7cc7360e8faf35bf

    # 2c. Normalise public_input.json for Stone — cairo-vm's Rust serialiser
    #     emits public_memory values as bare hex strings (e.g. "40780017fff7fff")
    #     but Stone's cpu_air_prover requires the 0x prefix
    #     (rejects with "String does not start with '0x'"). Add the prefix
    #     to every public_memory value.
    echo "[*] Step 2c/6: normalise public_input for Stone (0x prefix)"
    python3 -c "
import json, pathlib
p = pathlib.Path('${OUTPUT_DIR}/public_input.json')
pi = json.loads(p.read_text())
fixed = 0
for entry in pi.get('public_memory', []):
    v = entry.get('value')
    if isinstance(v, str) and not v.startswith('0x'):
        entry['value'] = '0x' + v
        fixed += 1
p.write_text(json.dumps(pi, indent=2))
print(f'    fixed {fixed} memory values')
"

    N_STEPS=$(python3 -c "import json; print(json.load(open('${OUTPUT_DIR}/public_input.json'))['n_steps'])")
    echo "    n_steps: ${N_STEPS}"

    # FRI step list — calculated from n_steps just like verifiable_grid
    FRI_STEPS=$(python3 -c "
import math
n_steps = ${N_STEPS}
degree = n_steps * 16
log_degree = int(math.log2(degree))
target = log_degree - 6
steps = [0]
remaining = target
while remaining > 0:
    s = min(4, remaining)
    steps.append(s)
    remaining -= s
import json; print(json.dumps(steps))
")
    echo "    FRI step list: ${FRI_STEPS}"

    cat > "${OUTPUT_DIR}/prover_config.json" << 'EOCFG'
{
    "constraint_polynomial_task_size": 256,
    "n_out_of_memory_merkle_layers": 1,
    "table_prover_n_tasks_per_segment": 32,
    "cached_lde_config": {"store_full_lde": false, "use_fft_for_eval": false}
}
EOCFG

    python3 -c "
import json
fri_steps = ${FRI_STEPS}
params = {
    'field': 'PrimeField0',
    'stark': {
        'fri': {
            'fri_step_list': fri_steps,
            'last_layer_degree_bound': 64,
            'n_queries': 16,
            'proof_of_work_bits': 30
        },
        'log_n_cosets': 2
    },
    'use_extension_field': False
}
json.dump(params, open('${OUTPUT_DIR}/params.json', 'w'), indent=2)
"

    # 3. cpu_air_prover → STARK proof
    echo "[*] Step 3/6: cpu_air_prover (this takes 1–3 minutes)"
    cpu_air_prover \
        --out_file="${OUTPUT_DIR}/proof.json" \
        --public_input_file="${OUTPUT_DIR}/public_input.json" \
        --private_input_file="${OUTPUT_DIR}/private_input.json" \
        --prover_config_file="${OUTPUT_DIR}/prover_config.json" \
        --parameter_file="${OUTPUT_DIR}/params.json" \
        --generate_annotations
    PROOF_SIZE=$(stat -c%s "${OUTPUT_DIR}/proof.json")
    echo "    proof bytes: ${PROOF_SIZE}"

    # 4. cpu_air_verifier — the cryptographic gate
    echo "[*] Step 4/6: cpu_air_verifier (cryptographic gate)"
    cpu_air_verifier \
        --in_file="${OUTPUT_DIR}/proof.json" \
        --annotation_file="${OUTPUT_DIR}/annotation.txt" \
        --extra_output_file="${OUTPUT_DIR}/extra_annotation.txt" \
        2>&1 && echo "    verification: PASSED" \
        || { echo "    verification: FAILED"; return 1; }

    # 5. stark_evm_adapter → EVM-compatible fact tuple
    echo "[*] Step 5/6: stark_evm_adapter"
    stark_evm_adapter gen-annotated-proof \
        --stone-proof-file       "${OUTPUT_DIR}/proof.json" \
        --stone-annotation-file  "${OUTPUT_DIR}/annotation.txt" \
        --stone-extra-annotation-file "${OUTPUT_DIR}/extra_annotation.txt" \
        --output                 "${OUTPUT_DIR}/evm_proof.json" \
        2>&1 && echo "    EVM proof generated" \
        || echo "    EVM adaptation failed (non-critical)"

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

    # 6. Submit fact to L1 (Verifier.registerSafeProof)
    echo "[*] Step 6/6: submit registerSafeProof to L1"
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

# Watch loop for on-demand proving
while true; do
    if [ -f "${OUTPUT_DIR}/prove_trigger" ]; then
        TAG=$(cat "${OUTPUT_DIR}/prove_trigger" 2>/dev/null || echo "manual")
        rm -f "${OUTPUT_DIR}/prove_trigger"
        prove_one "${INPUT_FILE_DEFAULT}" "${TAG}" || echo "[!] prove failed"
        echo "DONE" > "${OUTPUT_DIR}/prove_result"
    fi
    sleep 1
done

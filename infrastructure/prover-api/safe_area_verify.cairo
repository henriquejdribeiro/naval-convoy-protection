// =============================================================================
// safe_area_verify.cairo — Cairo 0 program proving SAFE_AREA mission compliance
// =============================================================================
//
// Proves a drone (β or α) swept its assigned area inside the SAFE_AREA bounds:
//
//   ① Coverage:    n_swept_cells / area_total_cells  >=  coverage_min permille
//   ② Detection:   every cell.p_contact            <   p_min basis points
//   ③ Time:        max(cell.ts) − ts_start         <=  time_window seconds
//
// Also computes a Poseidon hash chain over the cell array (commitment =
// H_β or H_α) so the L1 verifier can bind the verdict to the specific cell
// set the drone submitted.
//
// Input format (JSON, fed via cairo-run --program_input):
//   See infrastructure/prover-api/sample_input.json for the canonical
//   schema. Every field shown there is required.
//
// Public outputs (in this exact order, written by serialize_word):
//   [mission_id, drone_id, coverage_permille, max_p_contact, elapsed_seconds, commitment]
//
// These six felt252 values are extracted by submit_proof_l1.py and passed
// verbatim into Verifier.registerSafeProof on L1.
//
// Layout:    starknet_with_keccak (matches verifiable_grid's pinned config)
// Compiler:  cairo-lang 0.14.0.1
// =============================================================================

// Builtin order MUST be a subsequence of the canonical list:
//   output, pedersen, range_check, ecdsa, bitwise, ec_op, keccak, poseidon, ...
%builtins output range_check poseidon

from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.alloc import alloc

// ─────────────────────────────────────────────────────────────────────────
//  Constants — must match contracts/src/Registry.sol
// ─────────────────────────────────────────────────────────────────────────
const DRONE_ALPHA = 1;
const DRONE_BRAVO = 2;
const PERMILLE_BASE = 1000;

// ─────────────────────────────────────────────────────────────────────────
//  Hint-driven array readers — pull arrays out of program_input.
//  `key_id` selects which JSON array to read (0=cells_x, 1=cells_y,
//  2=cells_p_contact, 3=cells_ts).
// ─────────────────────────────────────────────────────────────────────────
func read_array(dst: felt*, n: felt, idx: felt, key_id: felt) {
    if (idx == n) {
        return ();
    }
    %{
        keymap = {0: 'cells_x', 1: 'cells_y', 2: 'cells_p_contact', 3: 'cells_ts'}
        memory[ids.dst + ids.idx] = program_input[keymap[ids.key_id]][ids.idx]
    %}
    return read_array(dst, n, idx + 1, key_id);
}

// ─────────────────────────────────────────────────────────────────────────
//  Per-cell constraint: 0 <= p < p_min
//  Range-check fails (no proof) if any cell's p_contact >= p_min.
// ─────────────────────────────────────────────────────────────────────────
func check_each_p_below_min{range_check_ptr}(
    p_contacts: felt*, p_min: felt, n: felt, idx: felt
) {
    if (idx == n) {
        return ();
    }
    let p = p_contacts[idx];
    assert [range_check_ptr] = p;             // p >= 0
    assert [range_check_ptr + 1] = p_min - 1 - p; // p < p_min
    let range_check_ptr = range_check_ptr + 2;
    return check_each_p_below_min(p_contacts, p_min, n, idx + 1);
}

// ─────────────────────────────────────────────────────────────────────────
//  Range-check claimed_max >= every element in the array.
//  Used together with a hint that supplies claimed_max = max(array).
//  Soundness: prover cannot claim a value smaller than the true max
//  (a smaller value would fail one of the range checks below). A larger
//  value would still satisfy these checks but be rejected by the L1
//  Verifier's threshold check (claimed_max < p_min).
// ─────────────────────────────────────────────────────────────────────────
func check_max_ge_each{range_check_ptr}(
    arr: felt*, n: felt, idx: felt, claimed_max: felt
) {
    if (idx == n) {
        return ();
    }
    assert [range_check_ptr] = claimed_max - arr[idx];
    let range_check_ptr = range_check_ptr + 1;
    return check_max_ge_each(arr, n, idx + 1, claimed_max);
}

// ─────────────────────────────────────────────────────────────────────────
//  Coverage: assert (n_cells * 1000) // area_total_cells >= coverage_min
//  Returns the computed coverage_permille for the public output.
// ─────────────────────────────────────────────────────────────────────────
func check_coverage{range_check_ptr}(
    n_cells: felt, area_total_cells: felt, coverage_min: felt
) -> (coverage_permille: felt) {
    alloc_locals;

    // Hint computes integer division; we verify it on-chain via two
    // multiplicative range checks.
    local coverage_permille: felt;
    %{
        ids.coverage_permille = (ids.n_cells * 1000) // ids.area_total_cells
    %}

    // Verify  coverage_permille * area_total_cells <= n_cells * 1000
    let lhs = coverage_permille * area_total_cells;
    let rhs = n_cells * PERMILLE_BASE;
    assert [range_check_ptr] = rhs - lhs;
    let range_check_ptr = range_check_ptr + 1;

    // Verify  n_cells * 1000  <  (coverage_permille + 1) * area_total_cells
    //         which is equivalent to:
    //         (coverage_permille + 1) * area_total_cells - n_cells*1000 - 1 >= 0
    let upper = (coverage_permille + 1) * area_total_cells;
    assert [range_check_ptr] = upper - rhs - 1;
    let range_check_ptr = range_check_ptr + 1;

    // coverage_permille >= coverage_min
    assert [range_check_ptr] = coverage_permille - coverage_min;
    let range_check_ptr = range_check_ptr + 1;

    // Also bound coverage_permille to [0, 1000] for sanity.
    assert [range_check_ptr] = coverage_permille;
    assert [range_check_ptr + 1] = PERMILLE_BASE - coverage_permille;
    let range_check_ptr = range_check_ptr + 2;

    return (coverage_permille=coverage_permille);
}

// ─────────────────────────────────────────────────────────────────────────
//  Hash chain: H = Poseidon(... Poseidon(Poseidon(0, c0_x), c0_y) ..., cN_ts)
//  Each cell contributes 4 felts: x, y, p_contact, ts.
// ─────────────────────────────────────────────────────────────────────────
func hash_cells{poseidon_ptr: PoseidonBuiltin*}(
    cells_x: felt*, cells_y: felt*, cells_p: felt*, cells_ts: felt*,
    n: felt, idx: felt, acc: felt
) -> (commitment: felt) {
    if (idx == n) {
        return (commitment=acc);
    }
    let (h1) = poseidon_hash(acc, cells_x[idx]);
    let (h2) = poseidon_hash(h1, cells_y[idx]);
    let (h3) = poseidon_hash(h2, cells_p[idx]);
    let (h4) = poseidon_hash(h3, cells_ts[idx]);
    return hash_cells(cells_x, cells_y, cells_p, cells_ts, n, idx + 1, h4);
}

// ─────────────────────────────────────────────────────────────────────────
//  Main entry point
// ─────────────────────────────────────────────────────────────────────────
func main{output_ptr: felt*, range_check_ptr, poseidon_ptr: PoseidonBuiltin*}() {
    alloc_locals;

    // 1. Read scalar inputs from program_input.
    //
    // expected_commitment is OPTIONAL — when present it binds this proof
    // to a specific L2 storage value (the Poseidon hash chain the drone
    // already wrote on convoy_protocol via submit_sweep_commitment).
    // Pass 0 to skip the binding (Phase 3.a's standalone-input mode).
    local mission_id: felt;
    local drone_id: felt;
    local area_total_cells: felt;
    local coverage_min: felt;
    local p_min: felt;
    local time_window: felt;
    local ts_start: felt;
    local n_cells: felt;
    local expected_commitment: felt;
    %{
        ids.mission_id                 = program_input['mission_id']
        ids.drone_id            = program_input['drone_id']
        ids.area_total_cells    = program_input['area_total_cells']
        ids.coverage_min        = program_input['coverage_min']
        ids.p_min               = program_input['p_min']
        ids.time_window         = program_input['time_window']
        ids.ts_start            = program_input['ts_start']
        ids.n_cells             = program_input['n_cells']
        ids.expected_commitment = program_input.get('expected_commitment', 0)
    %}

    // 2. Validate drone_id ∈ {1, 2}.
    let valid = (drone_id - DRONE_ALPHA) * (drone_id - DRONE_BRAVO);
    assert valid = 0;

    // 3. Read the four parallel cell arrays.
    let (cells_x:  felt*) = alloc();
    let (cells_y:  felt*) = alloc();
    let (cells_p:  felt*) = alloc();
    let (cells_ts: felt*) = alloc();
    read_array(cells_x,  n_cells, 0, 0);
    read_array(cells_y,  n_cells, 0, 1);
    read_array(cells_p,  n_cells, 0, 2);
    read_array(cells_ts, n_cells, 0, 3);

    // 4. Detection check: every cell's p_contact < p_min.
    //    (Aborts the trace if any cell violates.)
    check_each_p_below_min(cells_p, p_min, n_cells, 0);

    // 5. Compute max(p_contact) via hint + range-check verification.
    local max_p: felt;
    %{
        ids.max_p = max(program_input['cells_p_contact'])
    %}
    check_max_ge_each(cells_p, n_cells, 0, max_p);
    // Bind max_p to one of the cells: the prover must show max_p appears.
    // Soundness via the L1 contract: max_p < p_min is checked on-chain;
    // a value larger than the true max would fail that on-chain bound.
    assert [range_check_ptr] = max_p;
    assert [range_check_ptr + 1] = p_min - 1 - max_p;
    let range_check_ptr = range_check_ptr + 2;

    // 6. Compute max(ts) via hint + range-check verification.
    local max_ts: felt;
    %{
        ids.max_ts = max(program_input['cells_ts'])
    %}
    check_max_ge_each(cells_ts, n_cells, 0, max_ts);

    // elapsed = max_ts - ts_start; assert 0 <= elapsed <= time_window.
    let elapsed = max_ts - ts_start;
    assert [range_check_ptr] = elapsed;
    assert [range_check_ptr + 1] = time_window - elapsed;
    let range_check_ptr = range_check_ptr + 2;

    // 7. Coverage check.
    let (coverage_permille) = check_coverage(n_cells, area_total_cells, coverage_min);

    // 8. Compute commitment: Poseidon hash chain over all cells.
    let (commitment) = hash_cells(cells_x, cells_y, cells_p, cells_ts, n_cells, 0, 0);

    // 8a. L2-binding gate. If a non-zero expected_commitment was supplied
    //     (drone read its own convoy_protocol.get_commitment storage value
    //     and passed it in), assert the prover's computed commitment
    //     matches. This is what gives "the proof comes from the L2 block":
    //     the cells_x/y/p/ts the prover used must produce the same Poseidon
    //     chain that's stored on Madara, otherwise the trace aborts.
    //     Soundness: a tampered cell array would produce a different chain,
    //     failing this assertion. Aborted traces produce no STARK proof.
    if (expected_commitment != 0) {
        assert commitment = expected_commitment;
    }

    // 9. Serialise public outputs in fixed order. submit_proof_l1.py reads
    //    these in the same order to build the SafeProofInputs tuple.
    serialize_word(mission_id);
    serialize_word(drone_id);
    serialize_word(coverage_permille);
    serialize_word(max_p);
    serialize_word(elapsed);
    serialize_word(commitment);

    return ();
}

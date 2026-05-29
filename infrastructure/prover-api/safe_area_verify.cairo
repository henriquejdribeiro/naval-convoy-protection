// =============================================================================
// safe_area_verify.cairo — Cairo 0 program proving SAFE_AREA per drone strip
// =============================================================================
//
// 5-drone-per-swarm rev (2026-05). Each drone proves it swept its assigned
// vertical strip of the swarm's frontal area, against four constraints:
//
//   ① Strip bounds: every cell falls within [x_start, x_end) × [y_start, y_end)
//   ② Detection:    every cell.p_contact  <  p_min
//   ③ Time:         max(cell.ts) − ts_start  ≤  time_window
//   ④ Coverage:     n_cells * 1000 / strip_total_cells  ≥  coverage_min permille
//
// The four predicates collapse into a single `verdict_bool` ∈ {0, 1}.
// Unlike the previous rev, this program **always produces a valid proof**
// — even when the mission failed. The verdict_bool tells the truth about
// whether constraints were met. This lets the on-chain ConvoyProtocol
// record UNSAFE outcomes explicitly (failed mission ≠ "no proof at all").
//
// Hiding commitment:
//   H = Pedersen-chain over (cells_x ‖ cells_y ‖ cells_p_contact ‖ cells_ts ‖ cells_nonce)
// The 252-bit `cells_nonce` (random per proving run, in [hints]) makes H
// information-theoretically hiding under the discrete-log assumption
// (Pedersen 1991). Without the nonce, H would only be binding, not hiding —
// an attacker who knew the cells could brute-force verify a hash match.
//
// Public outputs (in this exact order, written via serialize_word):
//   [mission_id, drone_id, strip_x_start, strip_x_end,
//    strip_y_start, strip_y_end, verdict_bool, commitment_H]
//
// These eight felts are the EXACT public-input vector that
// ConvoyProtocol.submit_commitment builds and passes to the Cairo Verifier.
// Any divergence between this serialisation and the contract's expectation
// causes verifier rejection.
//
// Layout:    starknet (Cairo VM layout 6)
// Compiler:  cairo-lang 0.14.0.1
// Builtins:  output, pedersen, range_check (3 of the 7 in layout 6)
// =============================================================================

%builtins output pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le

// ─────────────────────────────────────────────────────────────────────────
//  Constants
// ─────────────────────────────────────────────────────────────────────────
const PERMILLE_BASE = 1000;

// ─────────────────────────────────────────────────────────────────────────
//  Read four parallel cell arrays from program_input via hints.
//  key_id ∈ {0=cells_x, 1=cells_y, 2=cells_p_contact, 3=cells_ts}.
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
//  in_range_bool(v, low, high) → 1 if low ≤ v < high, 0 otherwise
//  Uses is_le from math_cmp (which costs 1 range-check slot per call).
// ─────────────────────────────────────────────────────────────────────────
func in_range_bool{range_check_ptr}(value: felt, low: felt, high: felt) -> (
    result: felt
) {
    // 1 iff low ≤ value
    let ge_low = is_le(low, value);
    // 1 iff value ≤ high − 1   (i.e., value < high)
    let lt_high = is_le(value + 1, high);
    // Multiplicative AND: 1 only when both booleans are 1
    return (result=ge_low * lt_high);
}

// ─────────────────────────────────────────────────────────────────────────
//  Verify every cell lies within the assigned strip rectangle.
//  Accumulator `acc` starts at 1 and gets multiplied by each cell's
//  (x_in × y_in). Returns 1 iff every cell passed both bounds.
// ─────────────────────────────────────────────────────────────────────────
func check_all_in_strip{range_check_ptr}(
    cells_x: felt*, cells_y: felt*,
    strip_x_start: felt, strip_x_end: felt,
    strip_y_start: felt, strip_y_end: felt,
    n: felt, idx: felt, acc: felt,
) -> (result: felt) {
    if (idx == n) {
        return (result=acc);
    }
    let (x_in) = in_range_bool(cells_x[idx], strip_x_start, strip_x_end);
    let (y_in) = in_range_bool(cells_y[idx], strip_y_start, strip_y_end);
    return check_all_in_strip(
        cells_x, cells_y,
        strip_x_start, strip_x_end, strip_y_start, strip_y_end,
        n, idx + 1, acc * x_in * y_in,
    );
}

// ─────────────────────────────────────────────────────────────────────────
//  Verify every cell's p_contact < p_min.
//  Returns 1 iff all cells passed; 0 if any cell violated.
// ─────────────────────────────────────────────────────────────────────────
func check_all_p_below_min{range_check_ptr}(
    p_contacts: felt*, p_min: felt, n: felt, idx: felt, acc: felt,
) -> (result: felt) {
    if (idx == n) {
        return (result=acc);
    }
    let p_ok = is_le(p_contacts[idx] + 1, p_min);  // 1 iff p < p_min
    return check_all_p_below_min(p_contacts, p_min, n, idx + 1, acc * p_ok);
}

// ─────────────────────────────────────────────────────────────────────────
//  Range-check that `claimed_max ≥ arr[i]` for every i.
//  This binds a hint-provided claimed_max to a true upper bound on the array.
//  (Used to ensure the prover's max_ts hint is at least the actual max.)
// ─────────────────────────────────────────────────────────────────────────
func check_max_ge_each{range_check_ptr}(
    arr: felt*, n: felt, idx: felt, claimed_max: felt,
) {
    if (idx == n) {
        return ();
    }
    // Hard assert: claimed_max ≥ arr[idx]. If the prover lies (claimed_max
    // < arr[idx]), the range-check fails and the proof aborts — which is
    // fine, because lying about max_ts would let the prover claim a shorter
    // elapsed time than is true. We catch that here.
    assert [range_check_ptr] = claimed_max - arr[idx];
    let range_check_ptr = range_check_ptr + 1;
    return check_max_ge_each(arr, n, idx + 1, claimed_max);
}

// ─────────────────────────────────────────────────────────────────────────
//  Pedersen-chain commitment.
//
//    acc₀  =  0
//    acc_k = Pedersen(acc_{k-1}, cell_field_k)   for k = 1 .. 4·n
//    acc_final = Pedersen(acc_{4n}, cells_nonce)        ← hiding step
//
//  Each cell contributes 4 felts (x, y, p_contact, ts). Including the
//  nonce as the final input makes the commitment hiding: same cells with
//  a different nonce → different H, computationally indistinguishable
//  from random under DL hardness.
// ─────────────────────────────────────────────────────────────────────────
func hash_cells_with_nonce{pedersen_ptr: HashBuiltin*}(
    cells_x: felt*, cells_y: felt*, cells_p: felt*, cells_ts: felt*,
    n: felt, idx: felt, acc: felt, cells_nonce: felt,
) -> (commitment: felt) {
    if (idx == n) {
        // Final step: chain the nonce. This is what makes H hiding.
        let (final) = hash2{hash_ptr=pedersen_ptr}(acc, cells_nonce);
        return (commitment=final);
    }
    let (h1) = hash2{hash_ptr=pedersen_ptr}(acc, cells_x[idx]);
    let (h2) = hash2{hash_ptr=pedersen_ptr}(h1, cells_y[idx]);
    let (h3) = hash2{hash_ptr=pedersen_ptr}(h2, cells_p[idx]);
    let (h4) = hash2{hash_ptr=pedersen_ptr}(h3, cells_ts[idx]);
    return hash_cells_with_nonce(
        cells_x, cells_y, cells_p, cells_ts, n, idx + 1, h4, cells_nonce,
    );
}

// ─────────────────────────────────────────────────────────────────────────
//  Compute coverage_permille = n_cells * 1000 / strip_total_cells.
//  Verified via two range-check inequalities bracketing integer division.
//  Returns (coverage_permille, coverage_ok) where coverage_ok ∈ {0, 1}.
// ─────────────────────────────────────────────────────────────────────────
func compute_coverage{range_check_ptr}(
    n_cells: felt, strip_total_cells: felt, coverage_min: felt,
) -> (coverage_permille: felt, coverage_ok: felt) {
    alloc_locals;

    // Hint computes the floor-division; we verify it with two assertions
    // bracketing the exact integer-division value:
    //   q * strip_total_cells ≤ n_cells * 1000
    //   (q + 1) * strip_total_cells  >  n_cells * 1000
    local coverage_permille: felt;
    %{ ids.coverage_permille = (ids.n_cells * 1000) // ids.strip_total_cells %}

    let lhs = coverage_permille * strip_total_cells;
    let rhs = n_cells * PERMILLE_BASE;
    assert [range_check_ptr] = rhs - lhs;                          // lhs ≤ rhs
    assert [range_check_ptr + 1] = (coverage_permille + 1) * strip_total_cells - rhs - 1;
    let range_check_ptr = range_check_ptr + 2;

    // Sanity bound coverage_permille ∈ [0, 1000]
    assert [range_check_ptr] = coverage_permille;
    assert [range_check_ptr + 1] = PERMILLE_BASE - coverage_permille;
    let range_check_ptr = range_check_ptr + 2;

    // coverage_ok = 1 iff coverage_permille ≥ coverage_min
    let coverage_ok = is_le(coverage_min, coverage_permille);

    return (coverage_permille=coverage_permille, coverage_ok=coverage_ok);
}

// ─────────────────────────────────────────────────────────────────────────
//  Main entry point
// ─────────────────────────────────────────────────────────────────────────
func main{output_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;

    // ── 1. Read public inputs from program_input ───────────────────────
    local mission_id: felt;
    local drone_id: felt;
    local strip_x_start: felt;
    local strip_x_end: felt;
    local strip_y_start: felt;
    local strip_y_end: felt;
    local strip_total_cells: felt;
    local coverage_min: felt;
    local p_min: felt;
    local time_window: felt;
    local ts_start: felt;
    local n_cells: felt;
    %{
        ids.mission_id        = program_input['mission_id']
        ids.drone_id          = program_input['drone_id']
        ids.strip_x_start     = program_input['strip_x_start']
        ids.strip_x_end       = program_input['strip_x_end']
        ids.strip_y_start     = program_input['strip_y_start']
        ids.strip_y_end       = program_input['strip_y_end']
        ids.strip_total_cells = program_input['strip_total_cells']
        ids.coverage_min      = program_input['coverage_min']
        ids.p_min             = program_input['p_min']
        ids.time_window       = program_input['time_window']
        ids.ts_start          = program_input['ts_start']
        ids.n_cells           = program_input['n_cells']
    %}

    // ── 2. Read private hints ──────────────────────────────────────────
    let (cells_x: felt*)  = alloc();
    let (cells_y: felt*)  = alloc();
    let (cells_p: felt*)  = alloc();
    let (cells_ts: felt*) = alloc();
    read_array(cells_x,  n_cells, 0, 0);
    read_array(cells_y,  n_cells, 0, 1);
    read_array(cells_p,  n_cells, 0, 2);
    read_array(cells_ts, n_cells, 0, 3);

    // ── 3. Hiding-commitment nonce — fresh 252-bit randomness per proof ─
    local cells_nonce: felt;
    %{
        import secrets
        # Stark prime - 1 is the largest valid felt252; randbelow(p) gives
        # us a uniformly-random element of the prime field.
        STARK_PRIME = 2**251 + 17 * 2**192 + 1
        ids.cells_nonce = secrets.randbelow(STARK_PRIME)
    %}

    // ── 4. Per-predicate boolean computations ──────────────────────────

    // 4a. Strip-bounds predicate (= 1 iff every cell ∈ assigned strip)
    let (strip_ok) = check_all_in_strip(
        cells_x, cells_y,
        strip_x_start, strip_x_end, strip_y_start, strip_y_end,
        n_cells, 0, 1,
    );

    // 4b. Contact predicate (= 1 iff every p_contact < p_min)
    let (contact_ok) = check_all_p_below_min(cells_p, p_min, n_cells, 0, 1);

    // 4c. Time predicate (= 1 iff max(ts) − ts_start ≤ time_window)
    local max_ts: felt;
    %{ ids.max_ts = max(program_input['cells_ts']) %}
    check_max_ge_each(cells_ts, n_cells, 0, max_ts);   // hard-assert hint is an upper bound
    let elapsed = max_ts - ts_start;
    // 1 iff elapsed ≥ 0 (guard against malformed ts_start vs cells)
    let elapsed_nonneg = is_le(0, elapsed);
    // 1 iff elapsed ≤ time_window
    let elapsed_within = is_le(elapsed, time_window);
    let time_ok = elapsed_nonneg * elapsed_within;

    // 4d. Coverage predicate (= 1 iff coverage_permille ≥ coverage_min)
    let (_, coverage_ok) = compute_coverage(n_cells, strip_total_cells, coverage_min);

    // ── 5. Combine: verdict_bool = strip_ok ∧ contact_ok ∧ time_ok ∧ coverage_ok
    //     All booleans are 0 or 1, so multiplication = logical AND.
    let verdict_bool = strip_ok * contact_ok * time_ok * coverage_ok;

    // Sanity: verdict_bool ∈ {0, 1} (should be guaranteed by inputs;
    // this protects against malformed booleans creeping in).
    assert verdict_bool * (verdict_bool - 1) = 0;

    // ── 6. Hiding Pedersen-chain commitment ────────────────────────────
    let (commitment_H) = hash_cells_with_nonce(
        cells_x, cells_y, cells_p, cells_ts, n_cells, 0, 0, cells_nonce,
    );

    // ── 7. Serialise public outputs in the EXACT order ConvoyProtocol's
    //      submit_commitment builds them as public_inputs to the verifier.
    //      Any divergence breaks proof acceptance on L2.
    serialize_word(mission_id);
    serialize_word(drone_id);
    serialize_word(strip_x_start);
    serialize_word(strip_x_end);
    serialize_word(strip_y_start);
    serialize_word(strip_y_end);
    serialize_word(verdict_bool);
    serialize_word(commitment_H);

    return ();
}

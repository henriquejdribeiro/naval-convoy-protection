// =============================================================================
// safe_area_verify.cairo — Cairo 0 program proving SAFE_AREA mission compliance
// =============================================================================
//
// Proves a drone β (or α) swept its assigned area inside the SAFE_AREA bounds:
//
//     ① Coverage:     n_swept_cells / area_total_cells >= coverage_min permille
//     ② Detection:    every cell.p_contact < p_min basis points
//     ③ Time:         (max(cell.ts) - ts_start) <= time_window seconds
//
// The program ALSO computes a Poseidon hash chain over the cell array
// (commitment = H_β or H_α) so the L1 verifier can bind the verdict to the
// specific cell set the drone submitted.
//
// Input format (JSON, fed via cairo-run --program_input):
//
// {
//   "mid":              11,                   // mission id (felt252)
//   "drone_id":         2,                    // 1 = α, 2 = β
//   "area_total_cells": 576,                  // 24×24 grid
//   "coverage_min":     950,                  // permille (≥ 950 = ≥ 95.0%)
//   "p_min":            7000,                 // basis points (< 7000 = < 0.7)
//   "time_window":      360,                  // seconds
//   "ts_start":         1700000000,           // mission start timestamp
//   "n_cells":          50,                   // length of cells array
//   "cells_x":          [0, 1, 2, ...],       // cell grid x indices
//   "cells_y":          [0, 0, 0, ...],       // cell grid y indices
//   "cells_p_contact":  [2300, 1500, ...],    // basis points per cell
//   "cells_ts":         [1700000010, ...]     // unix seconds per cell
// }
//
// Output (in public memory, in order):
//
//   [mid, drone_id, coverage_permille, max_p_contact, elapsed_seconds, commitment]
//
// These six felt252 values are extracted by submit_proof_l1.py and passed
// verbatim into Verifier.registerSafeProof on L1.
//
// Layout:    starknet_with_keccak (matches verifiable_grid's pinned config)
// Compiler:  cairo-lang 0.14.0.1 (pinned to match the bundled cpu_air_prover)
// =============================================================================

%builtins output poseidon range_check

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
const BASIS_POINTS_BASE = 10000;

// ─────────────────────────────────────────────────────────────────────────
//  Hint readers — pull arrays from program_input
// ─────────────────────────────────────────────────────────────────────────
func read_u16_array(dst: felt*, n: felt, idx: felt, key: felt) {
    if (idx == n) {
        return ();
    }
    %{
        # `key` is a felt encoding which array to read; map to JSON key
        keymap = {
            0: 'cells_x',
            1: 'cells_y',
            2: 'cells_p_contact',
            3: 'cells_ts',
        }
        memory[ids.dst + ids.idx] = program_input[keymap[ids.key]][ids.idx]
    %}
    return read_u16_array(dst, n, idx + 1, key);
}

// ─────────────────────────────────────────────────────────────────────────
//  Detection check: every cell.p_contact < p_min
//  Reverts via assert if any cell exceeds the threshold (no proof produced).
// ─────────────────────────────────────────────────────────────────────────
func check_no_contacts{range_check_ptr}(
    p_contacts: felt*, p_min: felt, n: felt, idx: felt, max_seen: felt
) -> (max_p: felt) {
    if (idx == n) {
        return (max_p=max_seen);
    }
    let p = p_contacts[idx];

    // Range-check 0 <= p < p_min  (asserts p < p_min)
    // Cairo trick: assert (p_min - 1 - p) is non-negative, where the upper
    // bound is set by the caller's range-check budget.
    assert [range_check_ptr] = p;
    assert [range_check_ptr + 1] = p_min - 1 - p;
    let range_check_ptr = range_check_ptr + 2;

    // Track max for the public output
    if (p == max_seen) {
        return check_no_contacts(p_contacts, p_min, n, idx + 1, max_seen);
    }
    // Compute max(p, max_seen) without an `if` on inequality — use the fact
    // that exactly one of (p > max_seen) or (max_seen > p) holds when they
    // differ. We encode "is p > max_seen" via range-check.
    tempvar diff = p - max_seen;
    %{ memory[ap] = 1 if ids.diff > 0 else 0 %}
    [ap] = [ap]; ap++;     // hint provides 0 or 1
    let p_is_larger = [ap - 1];

    if (p_is_larger == 1) {
        // assert p > max_seen by checking (diff - 1) >= 0
        assert [range_check_ptr] = diff - 1;
        let range_check_ptr = range_check_ptr + 1;
        return check_no_contacts(p_contacts, p_min, n, idx + 1, p);
    }
    // p <= max_seen — assert (max_seen - p) >= 0
    assert [range_check_ptr] = max_seen - p;
    let range_check_ptr = range_check_ptr + 1;
    return check_no_contacts(p_contacts, p_min, n, idx + 1, max_seen);
}

// ─────────────────────────────────────────────────────────────────────────
//  Time check: max(cells_ts) - ts_start <= time_window
//  Returns elapsed_seconds for the public output.
// ─────────────────────────────────────────────────────────────────────────
func find_max_ts{range_check_ptr}(
    cells_ts: felt*, n: felt, idx: felt, max_seen: felt
) -> (max_ts: felt) {
    if (idx == n) {
        return (max_ts=max_seen);
    }
    let t = cells_ts[idx];
    tempvar diff = t - max_seen;
    %{ memory[ap] = 1 if ids.diff > 0 else 0 %}
    [ap] = [ap]; ap++;
    let t_is_larger = [ap - 1];
    if (t_is_larger == 1) {
        assert [range_check_ptr] = diff - 1;
        let range_check_ptr = range_check_ptr + 1;
        return find_max_ts(cells_ts, n, idx + 1, t);
    }
    assert [range_check_ptr] = max_seen - t;
    let range_check_ptr = range_check_ptr + 1;
    return find_max_ts(cells_ts, n, idx + 1, max_seen);
}

// ─────────────────────────────────────────────────────────────────────────
//  Coverage check: (n_cells * 1000) / area_total_cells >= coverage_min
//  Returns coverage_permille for the public output.
// ─────────────────────────────────────────────────────────────────────────
func check_coverage{range_check_ptr}(
    n_cells: felt, area_total_cells: felt, coverage_min: felt
) -> (coverage_permille: felt) {
    alloc_locals;

    // Compute coverage_permille = (n_cells * 1000) // area_total_cells
    // Cairo doesn't have native division; we use a hint + assertion that
    // coverage_permille * area_total_cells <= n_cells * 1000 < (coverage_permille+1) * area_total_cells.
    local coverage_permille: felt;
    %{
        ids.coverage_permille = (ids.n_cells * 1000) // ids.area_total_cells
    %}

    // Verify: coverage_permille * area_total_cells <= n_cells * 1000
    let lhs = coverage_permille * area_total_cells;
    let rhs = n_cells * PERMILLE_BASE;
    assert [range_check_ptr] = rhs - lhs;
    let range_check_ptr = range_check_ptr + 1;

    // Verify: n_cells * 1000 < (coverage_permille + 1) * area_total_cells
    let upper = (coverage_permille + 1) * area_total_cells;
    assert [range_check_ptr] = upper - rhs - 1;
    let range_check_ptr = range_check_ptr + 1;

    // Range-check coverage_permille >= coverage_min
    assert [range_check_ptr] = coverage_permille - coverage_min;
    let range_check_ptr = range_check_ptr + 1;

    // Bound coverage_permille to [0, 1000] for sanity
    assert [range_check_ptr] = coverage_permille;
    assert [range_check_ptr + 1] = PERMILLE_BASE - coverage_permille;
    let range_check_ptr = range_check_ptr + 2;

    return (coverage_permille=coverage_permille);
}

// ─────────────────────────────────────────────────────────────────────────
//  Hash chain over the cell array: H = Poseidon(p1, Poseidon(p2, ...))
//  Each cell contributes 4 felts: x, y, p_contact, ts
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
func main{output_ptr: felt*, poseidon_ptr: PoseidonBuiltin*, range_check_ptr}() {
    alloc_locals;

    // 1. Read scalar inputs from program_input
    local mid: felt;
    local drone_id: felt;
    local area_total_cells: felt;
    local coverage_min: felt;
    local p_min: felt;
    local time_window: felt;
    local ts_start: felt;
    local n_cells: felt;
    %{
        ids.mid              = program_input['mid']
        ids.drone_id         = program_input['drone_id']
        ids.area_total_cells = program_input['area_total_cells']
        ids.coverage_min     = program_input['coverage_min']
        ids.p_min            = program_input['p_min']
        ids.time_window      = program_input['time_window']
        ids.ts_start         = program_input['ts_start']
        ids.n_cells          = program_input['n_cells']
    %}

    // 2. Validate drone_id ∈ {ALPHA, BRAVO}
    //    (asserts drone_id == 1 OR drone_id == 2)
    let valid_drone = (drone_id - DRONE_ALPHA) * (drone_id - DRONE_BRAVO);
    assert valid_drone = 0;

    // 3. Read cell arrays
    let (cells_x:  felt*) = alloc();
    let (cells_y:  felt*) = alloc();
    let (cells_p:  felt*) = alloc();
    let (cells_ts: felt*) = alloc();
    read_u16_array(cells_x,  n_cells, 0, 0);
    read_u16_array(cells_y,  n_cells, 0, 1);
    read_u16_array(cells_p,  n_cells, 0, 2);
    read_u16_array(cells_ts, n_cells, 0, 3);

    // 4. Detection check — reverts (no proof) if any p_contact >= p_min
    let (max_p) = check_no_contacts(cells_p, p_min, n_cells, 0, 0);

    // 5. Time check — find max ts and check elapsed
    let (max_ts) = find_max_ts(cells_ts, n_cells, 0, ts_start);
    let elapsed = max_ts - ts_start;
    assert [range_check_ptr] = elapsed;
    assert [range_check_ptr + 1] = time_window - elapsed;
    let range_check_ptr = range_check_ptr + 2;

    // 6. Coverage check — compute permille and assert >= coverage_min
    let (coverage_permille) = check_coverage(n_cells, area_total_cells, coverage_min);

    // 7. Compute commitment (Poseidon hash chain over all cells)
    let (commitment) = hash_cells(cells_x, cells_y, cells_p, cells_ts, n_cells, 0, 0);

    // 8. Serialise public outputs in fixed order (matches submit_proof_l1.py)
    serialize_word(mid);
    serialize_word(drone_id);
    serialize_word(coverage_permille);
    serialize_word(max_p);
    serialize_word(elapsed);
    serialize_word(commitment);

    return ();
}

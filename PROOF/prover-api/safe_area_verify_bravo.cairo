// =============================================================================
// safe_area_verify_bravo.cairo — per-SWARM coverage proof, BRAVO (purple zone)
// =============================================================================
// ONE STARK proof for the whole 5-drone bravo swarm. The swarm leader (b1) runs
// this over all 5 drones' L2-signed telemetry and produces a single proof, which
// the bravo relay ship (ship-b) submits to the L1 Verifier.
//
// BRAVO sensor class — BAKED INTO THIS PROGRAM'S HASH (the whole point of having
// two programs): the bravo sensors are 2× better — each reading is a 0.2° square
// footprint (SENSOR_HALF = 0.1°), clearing 2×2 = 4 of the zone's 0.1° blocks.
// Purple zone = 1°×2° = 200 blocks (doubled to the side, 13–15°W); each of the 5
// drones owns a 0.4°-wide strip = 40 blocks (double the alpha share).
//
// Per drone d ∈ 1..5, four SAFE_AREA predicates (all in E7 units):
//   ① Strip bounds: every reading's SQUARE FOOTPRINT ⊆ drone d's strip
//   ② Detection:    every cell.p_contact < p_min
//   ③ Time:         max(cell.ts) − ts_start ≤ time_window
//   ④ Coverage:     covered_blocks·1000 / strip_blocks ≥ coverage_min permille
//                   where covered_blocks = n_cells · SENSOR_FOOTPRINT
//
// Two-level 13-hash tree:
//   drone hash H_d = Pedersen-chain(cells_d ‖ nonce_d)      (5 computed here)
//   swarm hash     = Pedersen-chain(H_1 ‖ H_2 ‖ … ‖ H_5)    (this proof's output)
//   principal hash = keccak(swarm_alpha, swarm_bravo)       (computed on L1)
// Each drone also ECDSA-signs its H_d (Route-B identity binding); this proof
// verifies all 5 signatures in-circuit, binding the swarm verdict to 5 named
// drone identities (their pubkeys are public outputs, checked on L1).
//
// Like the per-drone rev, this ALWAYS produces a valid proof — swarm_verdict
// tells the truth (0/1). The only aborts are cheating inputs: an invalid drone
// signature, or a lie about a drone's max(ts).
//
// Public outputs (exact order, via serialize_word) — 13 felts:
//   [mission_id, swarm_id, zone_x, zone_y, zone_w, zone_h,
//    swarm_verdict, swarm_hash, pk_1, pk_2, pk_3, pk_4, pk_5]
//
// Layout:   starknet (Cairo VM layout 6)
// Compiler: cairo-lang 0.14.0.1
// Builtins: output, pedersen, range_check, ecdsa
// =============================================================================

%builtins output pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le

// ── BRAVO swarm constants — the sensor class is part of the program hash ──────
const SWARM_ID           = 2;
const N_DRONES           = 5;
const BLOCK_SIZE         = 1000000;    // E7 per 0.1° coverage block
const ZONE_W             = 20000000;   // 2°  (purple is 2° wide, 13–15°W)
const ZONE_H             = 10000000;   // 1°  (37–38°N)
const STRIP_WIDTH        = 4000000;    // 0.4° = ZONE_W / N_DRONES
const SENSOR_HALF        = 1000000;    // 0.1° half-edge → 0.2° square footprint
const SENSOR_FOOTPRINT   = 4;          // ((2·SENSOR_HALF)/BLOCK_SIZE)² = 4 blocks
const STRIP_TOTAL_BLOCKS = 40;         // (STRIP_WIDTH/BLOCK)·(ZONE_H/BLOCK) = 4·10
const PERMILLE_BASE      = 1000;

// ─────────────────────────────────────────────────────────────────────────
//  Read one drone's cell array from program_input['drones'][drone][field].
//  key_id ∈ {0=cells_x, 1=cells_y, 2=cells_p_contact, 3=cells_ts}.
// ─────────────────────────────────────────────────────────────────────────
func read_array(dst: felt*, n: felt, idx: felt, drone: felt, key_id: felt) {
    if (idx == n) {
        return ();
    }
    %{
        keymap = {0: 'cells_x', 1: 'cells_y', 2: 'cells_p_contact', 3: 'cells_ts'}
        memory[ids.dst + ids.idx] = program_input['drones'][ids.drone][keymap[ids.key_id]][ids.idx]
    %}
    return read_array(dst, n, idx + 1, drone, key_id);
}

// ─────────────────────────────────────────────────────────────────────────
//  ① Strip bounds — every reading's SQUARE FOOTPRINT (side 2·SENSOR_HALF,
//  centred on the reading) must lie fully inside the strip:
//     x_start + HALF ≤ x  and  x + HALF ≤ x_end   (same for y)
//  acc starts at 1, ×= each cell's containment bool. Returns 1 iff all pass.
// ─────────────────────────────────────────────────────────────────────────
func check_all_in_strip{range_check_ptr}(
    cells_x: felt*, cells_y: felt*,
    x_start: felt, x_end: felt, y_start: felt, y_end: felt,
    n: felt, idx: felt, acc: felt,
) -> (result: felt) {
    if (idx == n) {
        return (result=acc);
    }
    let x_lo_ok = is_le(x_start + SENSOR_HALF, cells_x[idx]);
    let x_hi_ok = is_le(cells_x[idx] + SENSOR_HALF, x_end);
    let y_lo_ok = is_le(y_start + SENSOR_HALF, cells_y[idx]);
    let y_hi_ok = is_le(cells_y[idx] + SENSOR_HALF, y_end);
    let cell_ok = x_lo_ok * x_hi_ok * y_lo_ok * y_hi_ok;
    return check_all_in_strip(
        cells_x, cells_y, x_start, x_end, y_start, y_end,
        n, idx + 1, acc * cell_ok,
    );
}

// ─────────────────────────────────────────────────────────────────────────
//  ② Detection — every cell.p_contact < p_min. Returns 1 iff all pass.
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
//  ③ Time helper — hard-assert the hinted claimed_max is ≥ every ts, so the
//  prover cannot understate elapsed time. Aborts the proof if it lies.
// ─────────────────────────────────────────────────────────────────────────
func check_max_ge_each{range_check_ptr}(
    arr: felt*, n: felt, idx: felt, claimed_max: felt,
) {
    if (idx == n) {
        return ();
    }
    assert [range_check_ptr] = claimed_max - arr[idx];
    let range_check_ptr = range_check_ptr + 1;
    return check_max_ge_each(arr, n, idx + 1, claimed_max);
}

// ─────────────────────────────────────────────────────────────────────────
//  Drone hash H_d — Pedersen-chain over (x‖y‖p‖ts) for every cell, finally
//  folding in the drone's hiding nonce. Identical to the per-drone rev.
// ─────────────────────────────────────────────────────────────────────────
func hash_cells_with_nonce{pedersen_ptr: HashBuiltin*}(
    cells_x: felt*, cells_y: felt*, cells_p: felt*, cells_ts: felt*,
    n: felt, idx: felt, acc: felt, cells_nonce: felt,
) -> (commitment: felt) {
    if (idx == n) {
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
//  Aggregate the swarm: for each drone d ∈ 0..N_DRONES-1 evaluate the four
//  predicates against its DERIVED strip (deriving the strip in-circuit is what
//  forces the 5 strips to tile the zone), verify its ECDSA signature over its
//  hash H_d, record its pubkey, AND the verdicts, and Pedersen-chain the hashes
//  into the swarm hash.
// ─────────────────────────────────────────────────────────────────────────
func process_drones{pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*}(
    zone_x: felt, zone_y: felt,
    coverage_min: felt, p_min: felt, time_window: felt, ts_start: felt,
    pubkeys: felt*, d: felt, verdict_acc: felt, hash_acc: felt,
) -> (swarm_verdict: felt, swarm_hash: felt) {
    alloc_locals;
    if (d == N_DRONES) {
        return (swarm_verdict=verdict_acc, swarm_hash=hash_acc);
    }

    // ── this drone's cell count + four parallel arrays ──
    local n_cells: felt;
    %{ ids.n_cells = program_input['drones'][ids.d]['n_cells'] %}

    let (cells_x: felt*)  = alloc();
    let (cells_y: felt*)  = alloc();
    let (cells_p: felt*)  = alloc();
    let (cells_ts: felt*) = alloc();
    read_array(cells_x,  n_cells, 0, d, 0);
    read_array(cells_y,  n_cells, 0, d, 1);
    read_array(cells_p,  n_cells, 0, d, 2);
    read_array(cells_ts, n_cells, 0, d, 3);

    // ── this drone's hiding nonce + pubkey + signature over H_d ──
    local cells_nonce: felt;
    local drone_pubkey: felt;
    local sig_r: felt;
    local sig_s: felt;
    %{
        ids.cells_nonce  = program_input['drones'][ids.d]['cells_nonce']
        ids.drone_pubkey = program_input['drones'][ids.d]['drone_pubkey']
        ids.sig_r        = program_input['drones'][ids.d]['sig_r']
        ids.sig_s        = program_input['drones'][ids.d]['sig_s']
    %}

    // ── derive drone d's strip (0-based d; drone_id = d+1) ──
    let x_start = zone_x + d * STRIP_WIDTH;
    let x_end   = x_start + STRIP_WIDTH;
    let y_start = zone_y;
    let y_end   = zone_y + ZONE_H;

    // ① strip-bounds (footprint ⊆ strip)
    let (strip_ok) = check_all_in_strip(
        cells_x, cells_y, x_start, x_end, y_start, y_end, n_cells, 0, 1,
    );
    // ② detection
    let (contact_ok) = check_all_p_below_min(cells_p, p_min, n_cells, 0, 1);
    // ③ time: max(ts) − ts_start ∈ [0, time_window]
    local max_ts: felt;
    %{ ids.max_ts = max(program_input['drones'][ids.d]['cells_ts']) %}
    check_max_ge_each(cells_ts, n_cells, 0, max_ts);
    let elapsed = max_ts - ts_start;
    let elapsed_nonneg = is_le(0, elapsed);
    let elapsed_within = is_le(elapsed, time_window);
    let time_ok = elapsed_nonneg * elapsed_within;
    // ④ coverage: covered_blocks·1000 ≥ coverage_min·strip_blocks
    let covered = n_cells * SENSOR_FOOTPRINT;
    let coverage_ok = is_le(coverage_min * STRIP_TOTAL_BLOCKS, covered * PERMILLE_BASE);

    let drone_verdict = strip_ok * contact_ok * time_ok * coverage_ok;
    assert drone_verdict * (drone_verdict - 1) = 0;

    // ── drone hash H_d + in-circuit ECDSA identity binding ──
    let (commitment_H) = hash_cells_with_nonce(
        cells_x, cells_y, cells_p, cells_ts, n_cells, 0, 0, cells_nonce,
    );
    verify_ecdsa_signature{ecdsa_ptr=ecdsa_ptr}(
        message=commitment_H, public_key=drone_pubkey,
        signature_r=sig_r, signature_s=sig_s,
    );

    // record pubkey for the public output; fold H_d into the swarm hash
    assert pubkeys[d] = drone_pubkey;
    let (new_hash) = hash2{hash_ptr=pedersen_ptr}(hash_acc, commitment_H);

    return process_drones(
        zone_x, zone_y,
        coverage_min, p_min, time_window, ts_start,
        pubkeys, d + 1, verdict_acc * drone_verdict, new_hash,
    );
}

// ─────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────
func main{output_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*}() {
    alloc_locals;

    // ── mission inputs (echoed as outputs → checked against the registered
    //    spec on L1: zone_x/zone_y locate the swarm's zone) ──
    local mission_id: felt;
    local zone_x: felt;
    local zone_y: felt;
    local coverage_min: felt;
    local p_min: felt;
    local time_window: felt;
    local ts_start: felt;
    %{
        ids.mission_id   = program_input['mission_id']
        ids.zone_x       = program_input['zone_x']
        ids.zone_y       = program_input['zone_y']
        ids.coverage_min = program_input['coverage_min']
        ids.p_min        = program_input['p_min']
        ids.time_window  = program_input['time_window']
        ids.ts_start     = program_input['ts_start']
    %}

    // Collect the 5 drone pubkeys for the public-output vector.
    let (pubkeys: felt*) = alloc();

    // Aggregate the 5 drones: AND the verdicts, Pedersen-chain the hashes.
    let (swarm_verdict, swarm_hash) = process_drones(
        zone_x, zone_y,
        coverage_min, p_min, time_window, ts_start,
        pubkeys, 0, 1, 0,
    );

    assert swarm_verdict * (swarm_verdict - 1) = 0;

    // ── public outputs (exact order the L1 Verifier expects) ──
    serialize_word(mission_id);
    serialize_word(SWARM_ID);
    serialize_word(zone_x);
    serialize_word(zone_y);
    serialize_word(ZONE_W);
    serialize_word(ZONE_H);
    serialize_word(swarm_verdict);
    serialize_word(swarm_hash);
    serialize_word(pubkeys[0]);
    serialize_word(pubkeys[1]);
    serialize_word(pubkeys[2]);
    serialize_word(pubkeys[3]);
    serialize_word(pubkeys[4]);

    return ();
}

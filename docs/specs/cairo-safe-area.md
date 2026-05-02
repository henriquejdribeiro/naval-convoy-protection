# Cairo 0 program — `safe_area_verify.cairo` (pseudocode)

> Same Cairo 0 / proof-mode dialect as `verifiable_grid/infrastructure/prover-api/drone_verify.cairo`.
> Compiles with `cairo-lang==0.14.0.1`, executes with `cairo_run --proof_mode`,
> proven by `cpu_air_prover` (Stone). Produces the PIE that SNOS replays
> and the STARK that lands on L1.

This is **pseudocode**, not a final implementation. The point is to
confront the edge cases of the SAFE_AREA criterion *before* committing
to a constraint shape. When this is finalised, it goes in
`cairo/safe_area_verify.cairo`.

---

## 1. Inputs

```
%builtins output poseidon range_check

# Public inputs come from the `output` segment — they're emitted as
# program output and end up on-chain as outputHash. Same convention as
# verifiable_grid/drone_verify.cairo.

# Private inputs are read via cairo_run hints:
#   %{ memory[ids.dst + ids.idx] = program_input['cells'][ids.idx]['x'] %}
#
# The `program_input` JSON file is built by the orchestrator from the
# Pathfinder block-with-state response.
```

```
PUBLIC INPUTS (emitted to output segment, become outputHash on L1):
    mission_id                    : felt   # EX-010 or EX-011
    area_polygon_hash             : felt   # Poseidon over polygon corners
    coverage_threshold_permille   : felt   # e.g. 950 (= 95.0%)
    contact_threshold_bps         : felt   # e.g. 7000 (= p < 0.7)
    time_window_seconds           : felt   # e.g. 360
    telemetry_commitment          : felt   # Poseidon over private cell array
    n_cells                       : felt   # length of private array
    # — outputs of the verification —
    coverage_permille             : felt   # actual achieved coverage
    max_contact_bps               : felt   # actual max contact prob
    elapsed_seconds               : felt   # actual time span
    safe                          : felt   # 0 or 1

PRIVATE WITNESS (via hints, never reaches L1):
    cells[]                       : TelemetryCell, len = n_cells
    total_cells_in_area           : felt   # for coverage %
    area_polygon[]                : Point,  # corners; their Poseidon hash
                                   # must equal area_polygon_hash

TelemetryCell layout (one per swept cell):
    cell_id, x, y, t, p_contact, bearing, signal, resweep
```

---

## 2. The five assertions

Each assertion is a separate Cairo function. The pattern of stacked
`range_check` assertions and recursive iteration mirrors
`verifiable_grid/.../drone_verify.cairo` (functions `assert_in_grid`,
`assert_valid_move`, `verify_path`).

### A. Witness binding

```
# Re-compute the Poseidon chain over the witness, assert it equals the
# commitment that the public input claims. Without this, the prover could
# silently swap in a different telemetry array.

func bind_witness{poseidon_ptr}(cells, n, claimed_commitment):
    let computed = poseidon_chain_over_cells(cells, n)
    assert computed == claimed_commitment
```

### B. Polygon binding

```
# Same idea, for the area definition.
func bind_polygon{poseidon_ptr}(corners, claimed_hash):
    let computed = poseidon_chain_over_corners(corners)
    assert computed == claimed_hash
```

### C. Coverage check

```
# Walk every cell in the witness; count how many lie inside the area
# polygon (using the standard ray-casting test). Coverage permille is
# (covered_unique * 1000) / total_cells_in_area.
func check_coverage{range_check_ptr}(cells, n, polygon, total_in_area):
    covered = 0
    seen = empty_set        # implemented as sorted-array uniqueness check
    for i in 0..n:
        cell = cells[i]
        # Range checks: x, y inside the convex hull of the polygon.
        # 0 ≤ x, y ≤ MAX_GRID_DIM (see range_check pattern in drone_verify.cairo)
        in_polygon = ray_cast_test(cell.x, cell.y, polygon)
        if in_polygon and not seen[cell.cell_id]:
            covered += 1
            seen.insert(cell.cell_id)
    coverage_permille = (covered * 1000) / total_in_area
    return coverage_permille
```

**Edge cases to flag here:**
1. **Drone leaves the area mid-sweep** → cells outside the polygon are silently dropped from the count. They don't fail the proof; they just don't count toward coverage.
2. **Sensor overlap** → two drones swept the same cell. The `seen` set deduplicates by `cell_id` so we don't double-count.
3. **A cell is claimed inside but is actually outside** → caught by the `ray_cast_test` failing; the cell doesn't contribute to coverage, which lowers the achieved %, which fails the threshold.
4. **A cell with the same `cell_id` is reported twice with different telemetry** → hidden weakness. We need an additional assertion: `cells[i].cell_id < cells[i+1].cell_id` after sorting, OR `seen` set rejects duplicates and the second occurrence is ignored. **Decision needed:** which mitigation we adopt; doc this when the program is implemented.

### D. Time window check

```
func check_time{range_check_ptr}(cells, n, window):
    earliest = MAX_FELT
    latest   = 0
    for i in 0..n:
        if cells[i].t < earliest: earliest = cells[i].t
        if cells[i].t > latest:   latest   = cells[i].t
    elapsed = latest - earliest
    # Range check: elapsed >= 0 (subtraction in felt; need explicit check)
    assert_le(elapsed, window)     # provided by starkware.cairo.common.math
    return elapsed
```

**Edge case:** clock skew between drones. The spec says "elapsed seconds across the whole sweep". If drone clocks differ by Δ, `elapsed` is inflated by up to Δ. **Mitigation:** the L2 sequencer rewrites all telemetry timestamps to the *L2 block timestamp* before storing — that's authoritative. Drones contribute the readings; the L2 contract assigns the time. This is enforced by `convoy_protocol.cairo`'s `submit_telemetry` only accepting `t` as the block timestamp at the moment of the tx (see [`interfaces.md`](./interfaces.md)).

### E. Contact threshold check

```
func check_contacts{range_check_ptr}(cells, n, threshold_bps):
    max_contact = 0
    for i in 0..n:
        if cells[i].p_contact > max_contact:
            max_contact = cells[i].p_contact
    assert_lt(max_contact, threshold_bps)
    return max_contact
```

**Edge case:** what about `p_contact == threshold_bps` exactly? The spec says "no contact ABOVE p ≥ 0.7", which is ambiguous. **Decision:** strict less-than (`assert_lt`, not `assert_le`). A reading of exactly 0.7 fails — operationally safer to err on the side of "abort the mission" than admit a borderline detection.

---

## 3. Main entry point

```
func main{output_ptr, poseidon_ptr, range_check_ptr}():
    # Read public inputs (already on output segment) and private witness (hints).
    # Cairo 0 idiom — see drone_verify.cairo lines 88–100 for read_drone_x etc.

    let pub  = read_public_inputs()
    let cells, polygon, total_in_area = read_witness()

    # Step 1 — bind the witness to its commitment
    bind_witness(cells, pub.n_cells, pub.telemetry_commitment)

    # Step 2 — bind the polygon to its hash
    bind_polygon(polygon, pub.area_polygon_hash)

    # Step 3 — coverage
    let coverage = check_coverage(cells, pub.n_cells, polygon, total_in_area)
    let coverage_ok = is_le(pub.coverage_threshold_permille, coverage)   # threshold ≤ achieved

    # Step 4 — time window
    let elapsed = check_time(cells, pub.n_cells, pub.time_window_seconds)
    # check_time already asserts elapsed ≤ window; if it doesn't, the proof aborts
    let time_ok = 1

    # Step 5 — contact threshold
    let max_contact = check_contacts(cells, pub.n_cells, pub.contact_threshold_bps)
    # check_contacts asserts max < threshold; if it doesn't, the proof aborts
    let contact_ok = 1

    # Compose verdict — ALL three must hold.
    let safe = coverage_ok * time_ok * contact_ok       # AND in {0,1}

    # Emit outputs to the output segment (these end up on L1).
    serialize_word(pub.mission_id)
    serialize_word(pub.area_polygon_hash)
    serialize_word(pub.coverage_threshold_permille)
    serialize_word(pub.contact_threshold_bps)
    serialize_word(pub.time_window_seconds)
    serialize_word(pub.telemetry_commitment)
    serialize_word(pub.n_cells)
    serialize_word(coverage)
    serialize_word(max_contact)
    serialize_word(elapsed)
    serialize_word(safe)

    return ()
```

The output segment is exactly what `keccak256(abi.encodePacked(...))` is taken over to produce `outputHash` on L1, matching the StarkWare GPS verifier convention used in `DroneProofVerifier.sol`.

---

## 4. What this program does NOT prove

These are intentional limits — written down so they don't get assumed away.

1. **Drone honesty.** The program proves that *the cells the drones reported* meet the criterion. It does not prove the cells are real. A compromised drone reporting "I swept (3, 4) at t=120s, p=0.05" — when in reality it was nowhere near (3, 4) — produces a STARK that verifies but is operationally a lie. *Future work:* require k-of-n drone signatures on each cell, verified inside this program.
2. **L2 sequencer honesty.** Same — the program trusts the witness as delivered. If Madara α and the drones collude to fabricate telemetry, this program signs off. *Mitigation:* the L2 sequencer's commitment must include the L2 block timestamp, which the L1 verifier compares against the mission deadline. A sequencer can't backdate.
3. **Polygon correctness.** The program checks the polygon's Poseidon hash matches the public input — but the *public input* itself comes from the registry, which was set by D (commander). A commander who deploys with a malformed polygon (e.g., self-intersecting) will get an artefact that ray-casting on still passes. *Mitigation:* `ConvoyMissionRegistry.deploy` should reject non-convex or self-intersecting polygons at submission time.
4. **Bit-level overflow.** All arithmetic is in the 252-bit field. Coverage is computed as `covered * 1000 / total`; for `covered = 10⁵` and `total = 10⁵`, that's still well within the field, but if the grid grows beyond ≈ 10²⁵ cells we'd need to revisit. Practical for naval grids (< 10⁴ cells per mission).

---

## 5. Why Cairo 0 and not Cairo 1 for this program

This question came up in `verifiable_grid` development too. Short answer: **the Stone prover only consumes Cairo 0 PIE traces.** Stwo and the newer Cairo 1 toolchain are still maturing — for a thesis where the verification path needs to be reproducible end-to-end *today*, Cairo 0 + Stone is the only path that lands on L1 via `stark_evm_adapter`.

The Cairo 1 contract (`convoy_protocol.cairo`) handles state and storage on L2; the Cairo 0 program (`safe_area_verify.cairo`) handles the proof. Two languages, two roles, two compilers — same pattern as the parent project.

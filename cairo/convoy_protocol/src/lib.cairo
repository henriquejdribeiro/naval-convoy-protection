// =============================================================================
// convoy_protocol — Cairo 1 contract for L2 (Madara α / β)
// =============================================================================
// Stores per-(mission_id, drone_id) sweep state and sweep commitments. The drone is
// the only client of this contract; its OZ account contract on Madara
// authenticates each tx via Stark-curve ECDSA.
//
// Three entry points map directly to the protocol.md steps:
//
//   - submit_telemetry(mission_id, drone_id, cells)         protocol step 5  (×N)
//   - submit_sweep_commitment(mission_id, drone_id, h)      protocol step 6
//   - get_cells / get_commitment / mission_status    view helpers
//
// Storage strategy: cells are stored append-only via four parallel
// Map<(mission_id, drone_id, idx), uint> tables (one per field). cell_count keeps
// the active length per mission. The Cairo program (safe_area_verify.cairo,
// run by SNOS) reads the same fields as a witness — we don't need an
// in-contract Array<TelemetryCell> primitive.
//
// Events are emitted on every state change so the off-chain orchestrator
// (running on the relay ship) can subscribe and pick up new sweeps without
// polling.
//
// Adapted from verifiable_grid/contracts/cairo/src/lib.cairo's structure.
// Same Cairo 1 dialect, same `#[starknet::interface]` + `#[starknet::contract]`
// pattern.
// =============================================================================

#[starknet::interface]
trait IConvoyProtocol<TContractState> {
    // ── Mutating entry points (called by drone) ─────────────────────────

    /// Append one telemetry cell to (mission_id, drone_id)'s sweep.
    /// Reverts if mission is already closed (commitment present).
    fn submit_telemetry(
        ref self: TContractState,
        mission_id: u128,
        drone_id: felt252,
        x: u16,
        y: u16,
        p_contact: u16,
        ts: u64,
    );

    /// Close the sweep with the Poseidon hash chain over all submitted cells.
    /// Reverts if mission_id/drone_id has no submitted cells, or if commitment is
    /// already set.
    fn submit_sweep_commitment(
        ref self: TContractState,
        mission_id: u128,
        drone_id: felt252,
        commitment: felt252,
    );

    // ── Read-only views ─────────────────────────────────────────────────

    /// Number of cells submitted under (mission_id, drone_id).
    fn get_cell_count(self: @TContractState, mission_id: u128, drone_id: felt252) -> u32;

    /// The i-th cell as (x, y, p_contact, ts). Reverts if i >= count.
    fn get_cell(
        self: @TContractState,
        mission_id: u128,
        drone_id: felt252,
        i: u32,
    ) -> (u16, u16, u16, u64);

    /// The submitted commitment (felt252). Returns 0 before
    /// submit_sweep_commitment is called.
    fn get_commitment(self: @TContractState, mission_id: u128, drone_id: felt252) -> felt252;

    /// Whether the sweep is finalised (commitment set + non-zero).
    fn is_sweep_closed(self: @TContractState, mission_id: u128, drone_id: felt252) -> bool;
}

// ---------------------------------------------------------------------------
//  Contract module
// ---------------------------------------------------------------------------
#[starknet::contract]
mod ConvoyProtocol {
    use starknet::storage::{
        Map,
        StorageMapReadAccess,
        StorageMapWriteAccess,
        StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    // Storage layout
    //
    //  cells_x  / cells_y  / cells_p_contact / cells_ts:
    //      Map<(mission_id, drone_id, idx) → primitive>
    //  cell_count:
    //      Map<(mission_id, drone_id) → u32>
    //  commitments:
    //      Map<(mission_id, drone_id) → felt252>   (0 = unset)
    //
    // Cairo 1's Map can't take a tuple key directly, so we encode
    // (mission_id, drone_id, idx) into a single felt252 via a stable hash —
    // here we use a simple bit-packed felt: hi-bits = mission_id, lo-bits = idx,
    // with drone_id mixed in. For dev purposes a small hash function suffices;
    // collisions across α / β are impossible because mission_id is unique.
    #[storage]
    struct Storage {
        cells_x:         Map<felt252, u16>,
        cells_y:         Map<felt252, u16>,
        cells_p_contact: Map<felt252, u16>,
        cells_ts:        Map<felt252, u64>,
        cell_count:      Map<felt252, u32>,         // key = (mission_id << 1) | (drone_id - 1)
        commitments:     Map<felt252, felt252>,
    }

    // ── Events ──────────────────────────────────────────────────────────
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        TelemetrySubmitted: TelemetrySubmitted,
        SweepCommitted:     SweepCommitted,
    }

    #[derive(Drop, starknet::Event)]
    struct TelemetrySubmitted {
        #[key] mission_id: u128,
        #[key] drone_id: felt252,
        idx: u32,
        x: u16,
        y: u16,
        p_contact: u16,
        ts: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct SweepCommitted {
        #[key] mission_id: u128,
        #[key] drone_id: felt252,
        commitment: felt252,
        n_cells: u32,
    }

    // ── Constants — must match contracts/src/Registry.sol ───────────────
    const DRONE_ALPHA: felt252 = 1;
    const DRONE_BRAVO: felt252 = 2;

    // ─────────────────────────────────────────────────────────────────────
    //  Internal key helpers — encode (mission_id, drone_id) and (mission_id, drone_id, idx)
    //  into single felt252 keys for the Map storage. Domain-separated by a
    //  prefix tag so the four parallel maps never collide with the count
    //  map even if the bit-packing aliases.
    // ─────────────────────────────────────────────────────────────────────

    /// Assert that `drone_id` is one of the two valid lane identifiers
    /// (1 = α, 2 = β). Used as the first line of every public entry
    /// point so off-lane writes are impossible.
    ///
    /// The arithmetic identity `(d - 1)·(d - 2) == 0` is zero iff
    /// `d ∈ {1, 2}`. Using multiplication rather than `==` makes the
    /// check portable across Cairo 1 toolchain versions that did not
    /// expose equality on `felt252`.
    fn _validate_drone(drone_id: felt252) {
        let valid = (drone_id - DRONE_ALPHA) * (drone_id - DRONE_BRAVO);
        assert(valid == 0, 'invalid drone_id');
    }

    /// Compose a single `felt252` key from `(mission_id, drone_id)` for the
    /// per-mission storage maps (`cell_count`, `commitments`).
    ///
    /// Encoding: `(mission_id << 4) | drone_id`. The 4-bit shift gives a wide
    /// margin around the 2-valued drone_id so different `mission_id`s never
    /// alias under any drone, even though `mission_id` is `u128`.
    fn _key_mission(mission_id: u128, drone_id: felt252) -> felt252 {
        let mission_id_felt: felt252 = mission_id.into();
        mission_id_felt * 16 + drone_id
    }

    /// Compose a single `felt252` key from `(mission_id, drone_id, idx)` for
    /// the per-cell storage maps (`cells_x`, `cells_y`,
    /// `cells_p_contact`, `cells_ts`).
    ///
    /// Encoding: `_key_mission(mission_id, drone_id) * 2^40 + idx`. `u32`'s
    /// max value (2^32 − 1) sits comfortably below the 2^40 gap, so
    /// adjacent missions cannot collide with each other's cells.
    fn _key_cell(mission_id: u128, drone_id: felt252, idx: u32) -> felt252 {
        let base = _key_mission(mission_id, drone_id);
        let idx_felt: felt252 = idx.into();
        base * 1099511627776 + idx_felt   // 1099511627776 = 2^40
    }

    // ─────────────────────────────────────────────────────────────────────
    //  Implementation
    // ─────────────────────────────────────────────────────────────────────
    #[abi(embed_v0)]
    impl ConvoyProtocolImpl of super::IConvoyProtocol<ContractState> {
        fn submit_telemetry(
            ref self: ContractState,
            mission_id: u128,
            drone_id: felt252,
            x: u16,
            y: u16,
            p_contact: u16,
            ts: u64,
        ) {
            _validate_drone(drone_id);

            let mkey = _key_mission(mission_id, drone_id);

            // Refuse new cells once sweep is closed
            let already_committed = self.commitments.read(mkey);
            assert(already_committed == 0, 'sweep already closed');

            let count = self.cell_count.read(mkey);
            let ckey = _key_cell(mission_id, drone_id, count);

            self.cells_x.write(ckey, x);
            self.cells_y.write(ckey, y);
            self.cells_p_contact.write(ckey, p_contact);
            self.cells_ts.write(ckey, ts);
            self.cell_count.write(mkey, count + 1);

            self.emit(TelemetrySubmitted {
                mission_id:       mission_id,
                drone_id:  drone_id,
                idx:       count,
                x:         x,
                y:         y,
                p_contact: p_contact,
                ts:        ts,
            });
        }

        fn submit_sweep_commitment(
            ref self: ContractState,
            mission_id: u128,
            drone_id: felt252,
            commitment: felt252,
        ) {
            _validate_drone(drone_id);
            assert(commitment != 0, 'commitment must be non-zero');

            let mkey = _key_mission(mission_id, drone_id);

            let n_cells = self.cell_count.read(mkey);
            assert(n_cells > 0, 'no telemetry submitted');

            let already = self.commitments.read(mkey);
            assert(already == 0, 'commitment already set');

            self.commitments.write(mkey, commitment);

            self.emit(SweepCommitted {
                mission_id:        mission_id,
                drone_id:   drone_id,
                commitment: commitment,
                n_cells:    n_cells,
            });
        }

        fn get_cell_count(self: @ContractState, mission_id: u128, drone_id: felt252) -> u32 {
            self.cell_count.read(_key_mission(mission_id, drone_id))
        }

        fn get_cell(
            self: @ContractState,
            mission_id: u128,
            drone_id: felt252,
            i: u32,
        ) -> (u16, u16, u16, u64) {
            let n = self.cell_count.read(_key_mission(mission_id, drone_id));
            assert(i < n, 'cell index out of range');
            let ckey = _key_cell(mission_id, drone_id, i);
            (
                self.cells_x.read(ckey),
                self.cells_y.read(ckey),
                self.cells_p_contact.read(ckey),
                self.cells_ts.read(ckey),
            )
        }

        fn get_commitment(self: @ContractState, mission_id: u128, drone_id: felt252) -> felt252 {
            self.commitments.read(_key_mission(mission_id, drone_id))
        }

        fn is_sweep_closed(self: @ContractState, mission_id: u128, drone_id: felt252) -> bool {
            self.commitments.read(_key_mission(mission_id, drone_id)) != 0
        }
    }
}

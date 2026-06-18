// =============================================================================
// convoy_protocol — Cairo 1 starknet contract for L2 (Madara)
// =============================================================================
// 5-drone-per-swarm architecture (rev 2026-06, raw-telemetry-on-L2).
//
// Each mission = a swarm of N drones (typically 5). Each drone covers a
// vertical strip of the swarm's frontal area. The contract:
//
//   1. Receives mission spec from L1 via #[l1_handler] open_mission
//   2. Records the N drone account addresses (one per drone_id 1..N)
//   3. Accepts a drone's RAW telemetry (per-cell measurements) via
//      submit_telemetry and checks the four SAFE_AREA predicates DIRECTLY
//      ON-CHAIN — no per-drone STARK proof, no off-chain prover
//   4. Aggregates verdicts; emits L1 message when all N drones SAFE
//
// SAFE_AREA predicates (evaluated in submit_telemetry):
//
//   ① Strip bounds: every cell in [strip.x_start, strip.x_end)
//                                 × [strip.y_start, strip.y_end)
//   ② Detection:    every cell.p_contact < spec.p_min      (basis points)
//   ③ Time:         max(cell.ts) − ts_start ≤ spec.time_window
//   ④ Coverage:     n_cells * 1000 / strip_total_cells ≥ spec.coverage_min
//                                                       (permille)
//
// If all four predicates hold → verdict = SAFE. Otherwise → UNSAFE,
// with the failing predicate logged in the CommitmentSubmitted event.
//
// Strip derivation (deterministic, computed in-contract):
//
//   strip_width      = spec.zone_w / spec.n_drones        (enforced exact)
//   strip[i].x_start = spec.zone_x + (i-1) * strip_width  (drone_id i ∈ 1..N)
//   strip[i].x_end   = strip[i].x_start + strip_width
//   strip[i].y_start = spec.zone_y
//   strip[i].y_end   = spec.zone_y + spec.zone_h
//
// ── Design note (architecture reversal from rev 2026-05) ─────────────────
//
// The previous design kept cells in drone-local Cairo hints and submitted
// a per-drone STARK proof to L2 via a Stone-cairo verifier contract. This
// rev reverses that decision: cells are submitted as L2 invoke calldata
// and the contract evaluates the four predicates directly.
//
// Implications:
//   - Telemetry is PUBLIC on L2 — anyone reading Madara history sees
//     each cell's (x, y, p_contact, ts). The Pedersen-hiding commitment H
//     is no longer required (kept only as an audit trail).
//   - No per-drone STARK proof. The cryptographic proof L1 verifies is
//     the Madara-block STARK proof produced by SNOS + Stone (which
//     attests that THIS contract correctly evaluated the predicates on
//     the public telemetry — i.e. zk-rollup execution proof, not a
//     drone-side privacy proof).
//   - The cairo_verifier construction argument is removed — there is
//     no per-drone proof for the contract to verify.
// =============================================================================

use core::starknet::ContractAddress;

// ── Public types (visible to dispatchers, ABI, off-chain callers) ──────────

/// All parameters defining one mission. Stored verbatim on chain.
/// Field order matters — it's how the L1 bridge serialises the payload.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct MissionSpec {
    pub mission_id:   felt252,
    pub swarm_id:     felt252,    // 1 = Alpha, 2 = Bravo
    pub zone_x:       u32,        // grid origin
    pub zone_y:       u32,
    pub zone_w:       u32,        // cells wide  (15 for Alpha, 20 for Bravo)
    pub zone_h:       u32,        // cells tall  (8 for both)
    pub n_drones:     u8,         // 5
    pub strip_width:  u32,        // = zone_w / n_drones (must be exact)
    pub coverage_min: u16,        // permille; e.g. 950 = 95%
    pub p_min:        u16,        // basis points; e.g. 7000 = 70%
    pub time_window:  u64,        // seconds
    pub ts_start:     u64,        // mission-start timestamp
}

/// One drone's assigned sub-area (derived deterministically from MissionSpec).
#[derive(Drop, Copy, Serde)]
pub struct StripBounds {
    pub x_start: u32,
    pub x_end:   u32,
    pub y_start: u32,
    pub y_end:   u32,
}

// Verdict codes used by the verdicts storage map and emitted in events.
pub const VERDICT_PENDING: u8 = 0;
pub const VERDICT_SAFE:    u8 = 1;
pub const VERDICT_UNSAFE:  u8 = 2;

// Failure codes — which predicate rejected the telemetry.
pub const FAIL_NONE:       u8 = 0;
pub const FAIL_STRIP:      u8 = 1;   // ① cell outside assigned strip
pub const FAIL_DETECTION:  u8 = 2;   // ② p_contact ≥ p_min
pub const FAIL_TIME:       u8 = 3;   // ③ ts beyond time_window
pub const FAIL_COVERAGE:   u8 = 4;   // ④ coverage permille below threshold

// ── Interface ──────────────────────────────────────────────────────────────

#[starknet::interface]
pub trait IConvoyProtocol<TContractState> {
    // ── Mutating entry points ───────────────────────────────────────
    //
    // open_mission lives in the contract module (it's #[l1_handler]); the
    // dev-mode companion `open_mission_local` IS part of this trait so
    // it can be invoked from a normal L2 account.

    /// Dev-mode mission deployment — same effect as the L1→L2-bridged
    /// `open_mission`, but callable as a regular invoke without needing
    /// an L1 message. Skips the L1-sender authorisation check; rely on
    /// the (mission_id) idempotency to prevent re-deployment.
    ///
    /// Use this until `--l1-sync-disabled` is dropped on the Madara
    /// services and the production L1→L2 bridge is fully wired.
    fn open_mission_local(
        ref self: TContractState,
        spec:            MissionSpec,
        drone_addresses: Array<ContractAddress>,
    );

    /// Drone → L2 submission of raw per-cell telemetry. The contract
    /// runs the four SAFE_AREA predicates on the cells against the
    /// drone's assigned strip and records SAFE or UNSAFE.
    ///
    /// All four parallel arrays must have the same length = n_cells.
    /// Reverts if:
    ///   - mission_id not deployed
    ///   - drone_id out of range or already submitted
    ///   - caller is not the registered drone account
    ///   - array lengths disagree or n_cells == 0
    fn submit_telemetry(
        ref self: TContractState,
        mission_id:       felt252,
        drone_id:         u8,
        cells_x:          Array<u32>,
        cells_y:          Array<u32>,
        cells_p_contact:  Array<u16>,
        cells_ts:         Array<u64>,
    );

    // ── Read-only views ─────────────────────────────────────────────

    /// Full mission spec. Reverts if not deployed.
    fn get_mission(self: @TContractState, mission_id: felt252) -> MissionSpec;

    /// Account address authorised to submit for (mission_id, drone_id).
    fn get_drone_addr(self: @TContractState, mission_id: felt252, drone_id: u8)
        -> ContractAddress;

    /// Sub-area assigned to (mission_id, drone_id), derived in-contract.
    fn get_strip(self: @TContractState, mission_id: felt252, drone_id: u8)
        -> StripBounds;

    /// Verdict code (0=PENDING, 1=SAFE, 2=UNSAFE) for one drone.
    fn verdict(self: @TContractState, mission_id: felt252, drone_id: u8) -> u8;

    /// If verdict is UNSAFE, which predicate failed (FAIL_* constant).
    fn fail_reason(self: @TContractState, mission_id: felt252, drone_id: u8) -> u8;

    /// True iff every drone in the mission has submitted SAFE.
    fn mission_safe(self: @TContractState, mission_id: felt252) -> bool;

    /// Number of drones currently in SAFE state for the mission.
    fn safe_count(self: @TContractState, mission_id: felt252) -> u8;

    /// Number of cells the drone reported (0 if no submission yet).
    fn get_n_cells(self: @TContractState, mission_id: felt252, drone_id: u8) -> u32;
}

// ── Contract module ────────────────────────────────────────────────────────

#[starknet::contract]
mod ConvoyProtocol {
    use core::starknet::{
        ContractAddress, get_caller_address,
    };
    use core::starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess,
    };
    use core::starknet::syscalls::send_message_to_l1_syscall;

    use super::{
        MissionSpec, StripBounds,
        VERDICT_PENDING, VERDICT_SAFE, VERDICT_UNSAFE,
        FAIL_NONE, FAIL_STRIP, FAIL_DETECTION, FAIL_TIME, FAIL_COVERAGE,
    };

    // ── Storage ────────────────────────────────────────────────────────────
    //
    // Storage keys for the per-(mission, drone) maps are computed via
    // `encode_drone_key(mid, did)` so the parallel maps share the
    // same slot space without colliding.
    #[storage]
    struct Storage {
        // Per-mission specs
        missions:       Map<felt252, MissionSpec>,
        mission_exists: Map<felt252, bool>,

        // Per-drone state — keyed by encode_drone_key(mid, did)
        drone_addr:    Map<felt252, ContractAddress>,
        verdicts:      Map<felt252, u8>,
        fail_reasons:  Map<felt252, u8>,
        n_cells_map:   Map<felt252, u32>,

        // Per-mission aggregates
        safe_count: Map<felt252, u8>,
        l1_emitted: Map<felt252, bool>,

        // Configuration (set at constructor, immutable thereafter)
        l1_commander_addr: felt252,    // L1 address authorised to call open_mission
        l1_verifier_addr:  felt252,    // L1 destination for the all-SAFE message
    }

    // ── Events ─────────────────────────────────────────────────────────────
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MissionDeployed:    MissionDeployed,
        TelemetrySubmitted: TelemetrySubmitted,
        MissionSafe:        MissionSafeEvent,
        MissionUnsafe:      MissionUnsafeEvent,
    }

    #[derive(Drop, starknet::Event)]
    struct MissionDeployed {
        #[key] mission_id: felt252,
        swarm_id: felt252,
        n_drones: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct TelemetrySubmitted {
        #[key] mission_id: felt252,
        #[key] drone_id:   u8,
        verdict:     u8,
        fail_reason: u8,
        n_cells:     u32,
    }

    #[derive(Drop, starknet::Event)]
    struct MissionSafeEvent {
        #[key] mission_id: felt252,
        n_drones: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct MissionUnsafeEvent {
        #[key] mission_id: felt252,
        failing_drone: u8,
        fail_reason:   u8,
    }

    // ── Mission deployment — two entry points share one implementation ─────
    //
    // PRODUCTION PATH: #[l1_handler] open_mission
    //   Triggered when the L1 Commander bridge calls L1's
    //   StarknetCore.sendMessageToL2(this_contract, selector, payload).
    //   Madara's block builder routes the message to this handler with
    //   `from_address` auto-filled to the L1 sender.
    //
    // DEV PATH: #[external_v0] open_mission_local (via IConvoyProtocol)
    //   Same body, no L1 round-trip — directly callable as a normal L2
    //   invoke. Needed because our Madaras run with --l1-sync-disabled,
    //   so the canonical L1→L2 message bridge isn't active in this
    //   deployment topology. Once we wire SNOS + orchestrator and drop
    //   --l1-sync-disabled, the L1 path becomes the only authorised one
    //   and open_mission_local can be removed.
    //
    // Shared helper _do_open_mission contains the spec-sanity checks
    // and storage writes so both entry points stay in lockstep.
    #[l1_handler]
    fn open_mission(
        ref self: ContractState,
        from_address: felt252,
        spec:            MissionSpec,
        drone_addresses: Array<ContractAddress>,
    ) {
        assert(
            from_address == self.l1_commander_addr.read(),
            'unauthorised L1 sender',
        );
        _do_open_mission(ref self, spec, drone_addresses);
    }

    fn _do_open_mission(
        ref self: ContractState,
        spec:            MissionSpec,
        drone_addresses: Array<ContractAddress>,
    ) {
        // 1. Idempotency
        assert(
            !self.mission_exists.read(spec.mission_id),
            'mission already deployed',
        );

        // 2. Spec sanity
        assert(spec.n_drones > 0_u8, 'n_drones must be > 0');
        let n_drones_u32: u32 = spec.n_drones.into();
        assert(spec.zone_w == spec.strip_width * n_drones_u32, 'zone_w not divisible');
        assert(spec.zone_h > 0_u32, 'zone_h must be > 0');
        assert(spec.strip_width > 0_u32, 'strip_width must be > 0');
        assert(drone_addresses.len() == n_drones_u32, 'drone addr count mismatch');

        // 3. Persist spec
        self.missions.write(spec.mission_id, spec);
        self.mission_exists.write(spec.mission_id, true);

        // 4. Register each drone's account address against (mid, did)
        let mut i: u32 = 0;
        loop {
            if i >= n_drones_u32 { break; }
            let drone_id_u8: u8 = (i + 1_u32).try_into().unwrap();
            let key = encode_drone_key(spec.mission_id, drone_id_u8);
            self.drone_addr.write(key, *drone_addresses.at(i));
            i += 1_u32;
        };

        self.emit(MissionDeployed {
            mission_id: spec.mission_id,
            swarm_id:   spec.swarm_id,
            n_drones:   spec.n_drones,
        });
    }

    // ── External entry points ──────────────────────────────────────────────
    #[abi(embed_v0)]
    impl ConvoyProtocolImpl of super::IConvoyProtocol<ContractState> {

        fn open_mission_local(
            ref self: ContractState,
            spec:            MissionSpec,
            drone_addresses: Array<ContractAddress>,
        ) {
            _do_open_mission(ref self, spec, drone_addresses);
        }

        fn submit_telemetry(
            ref self: ContractState,
            mission_id:       felt252,
            drone_id:         u8,
            cells_x:          Array<u32>,
            cells_y:          Array<u32>,
            cells_p_contact:  Array<u16>,
            cells_ts:         Array<u64>,
        ) {
            // 1. Mission must exist
            assert(self.mission_exists.read(mission_id), 'mission not deployed');
            let spec = self.missions.read(mission_id);

            // 2. drone_id ∈ [1, n_drones]
            assert(drone_id >= 1_u8,          'drone_id < 1');
            assert(drone_id <= spec.n_drones, 'drone_id > n_drones');

            // 3. Caller must be the registered drone account
            let dkey = encode_drone_key(mission_id, drone_id);
            let expected_caller = self.drone_addr.read(dkey);
            assert(get_caller_address() == expected_caller, 'wrong drone caller');

            // 4. Not yet submitted
            let prior = self.verdicts.read(dkey);
            assert(prior == VERDICT_PENDING, 'already submitted');

            // 5. Array lengths agree and non-zero
            let n_cells = cells_x.len();
            assert(n_cells > 0_u32,                       'n_cells must be > 0');
            assert(cells_y.len() == n_cells,              'cells_y length mismatch');
            assert(cells_p_contact.len() == n_cells,      'p_contact length mismatch');
            assert(cells_ts.len() == n_cells,             'cells_ts length mismatch');

            // 6. Derive this drone's strip bounds
            let strip = derive_strip(spec, drone_id);

            // 7. Evaluate the four SAFE_AREA predicates against the cells.
            //    First failing predicate wins — verdict becomes UNSAFE
            //    and fail_reason records which check rejected.
            let fail = evaluate_predicates(
                strip,
                spec.p_min,
                spec.time_window,
                spec.ts_start,
                spec.coverage_min,
                spec.strip_width,
                spec.zone_h,
                @cells_x,
                @cells_y,
                @cells_p_contact,
                @cells_ts,
            );

            // 8. Record outcome
            let new_verdict = if fail == FAIL_NONE { VERDICT_SAFE }
                              else                 { VERDICT_UNSAFE };
            self.verdicts.write(dkey, new_verdict);
            self.fail_reasons.write(dkey, fail);
            self.n_cells_map.write(dkey, n_cells);

            self.emit(TelemetrySubmitted {
                mission_id, drone_id,
                verdict:     new_verdict,
                fail_reason: fail,
                n_cells:     n_cells,
            });

            // 9. Aggregate updates
            if new_verdict == VERDICT_SAFE {
                let new_count = self.safe_count.read(mission_id) + 1_u8;
                self.safe_count.write(mission_id, new_count);

                if new_count == spec.n_drones && !self.l1_emitted.read(mission_id) {
                    // All drones SAFE — emit the L1 message exactly once.
                    self.l1_emitted.write(mission_id, true);

                    let n_drones_felt: felt252 = spec.n_drones.into();
                    let payload = array![mission_id, n_drones_felt].span();
                    let _ = send_message_to_l1_syscall(
                        self.l1_verifier_addr.read(),
                        payload,
                    );

                    self.emit(MissionSafeEvent {
                        mission_id,
                        n_drones: spec.n_drones,
                    });
                }
            } else {
                self.emit(MissionUnsafeEvent {
                    mission_id,
                    failing_drone: drone_id,
                    fail_reason:   fail,
                });
            }
        }

        // ── Views ──────────────────────────────────────────────────────────

        fn get_mission(self: @ContractState, mission_id: felt252) -> MissionSpec {
            assert(self.mission_exists.read(mission_id), 'mission not deployed');
            self.missions.read(mission_id)
        }

        fn get_drone_addr(
            self: @ContractState, mission_id: felt252, drone_id: u8,
        ) -> ContractAddress {
            self.drone_addr.read(encode_drone_key(mission_id, drone_id))
        }

        fn get_strip(
            self: @ContractState, mission_id: felt252, drone_id: u8,
        ) -> StripBounds {
            let spec = self.missions.read(mission_id);
            derive_strip(spec, drone_id)
        }

        fn verdict(self: @ContractState, mission_id: felt252, drone_id: u8) -> u8 {
            self.verdicts.read(encode_drone_key(mission_id, drone_id))
        }

        fn fail_reason(self: @ContractState, mission_id: felt252, drone_id: u8) -> u8 {
            self.fail_reasons.read(encode_drone_key(mission_id, drone_id))
        }

        fn mission_safe(self: @ContractState, mission_id: felt252) -> bool {
            if !self.mission_exists.read(mission_id) { return false; }
            let spec = self.missions.read(mission_id);
            self.safe_count.read(mission_id) == spec.n_drones
        }

        fn safe_count(self: @ContractState, mission_id: felt252) -> u8 {
            self.safe_count.read(mission_id)
        }

        fn get_n_cells(
            self: @ContractState, mission_id: felt252, drone_id: u8,
        ) -> u32 {
            self.n_cells_map.read(encode_drone_key(mission_id, drone_id))
        }
    }

    // ── Pure helpers ───────────────────────────────────────────────────────

    /// Encode `(mission_id, drone_id)` into a single felt252 storage key.
    fn encode_drone_key(mission_id: felt252, drone_id: u8) -> felt252 {
        let drone_felt: felt252 = drone_id.into();
        mission_id * 256 + drone_felt
    }

    /// Derive the sub-area assigned to `drone_id ∈ [1, n_drones]`.
    fn derive_strip(spec: MissionSpec, drone_id: u8) -> StripBounds {
        let i_u32: u32 = (drone_id - 1_u8).into();
        let x_start = spec.zone_x + i_u32 * spec.strip_width;
        StripBounds {
            x_start: x_start,
            x_end:   x_start + spec.strip_width,
            y_start: spec.zone_y,
            y_end:   spec.zone_y + spec.zone_h,
        }
    }

    /// Run the four SAFE_AREA predicates against the cell arrays.
    /// Returns FAIL_NONE iff all four pass, otherwise the first failure code.
    ///
    /// Note on duplicates: this version counts cells_x.len() as the coverage
    /// numerator. Drones must not duplicate cell entries (caller-side
    /// invariant); duplicates would inflate coverage. A more defensive rev
    /// could sort-and-dedupe in-contract, but at 5×~120 cells the gas cost
    /// of an O(n log n) sort is non-trivial for what is supposed to be a
    /// cheap L2 invocation.
    fn evaluate_predicates(
        strip:        StripBounds,
        p_min:        u16,
        time_window:  u64,
        ts_start:     u64,
        coverage_min: u16,
        strip_width:  u32,
        zone_h:       u32,
        cells_x:          @Array<u32>,
        cells_y:          @Array<u32>,
        cells_p_contact:  @Array<u16>,
        cells_ts:         @Array<u64>,
    ) -> u8 {
        let n = cells_x.len();
        let mut i: u32 = 0;

        // Cairo 1 disallows early `return` inside `loop`. We use `break expr`
        // to emit the per-cell verdict, then short-circuit if any failed.
        let per_cell_fail: u8 = loop {
            if i >= n { break FAIL_NONE; }

            let x = *cells_x.at(i);
            let y = *cells_y.at(i);
            let p = *cells_p_contact.at(i);
            let ts = *cells_ts.at(i);

            // ① Strip bounds
            if x < strip.x_start || x >= strip.x_end {
                break FAIL_STRIP;
            }
            if y < strip.y_start || y >= strip.y_end {
                break FAIL_STRIP;
            }

            // ② Detection: p_contact must be strictly below threshold
            if p >= p_min {
                break FAIL_DETECTION;
            }

            // ③ Time window: ts - ts_start ≤ time_window
            //    (and ts must be ≥ ts_start, otherwise drone clock-skewed)
            if ts < ts_start {
                break FAIL_TIME;
            }
            let elapsed = ts - ts_start;
            if elapsed > time_window {
                break FAIL_TIME;
            }

            i += 1_u32;
        };

        if per_cell_fail != FAIL_NONE {
            return per_cell_fail;
        }

        // ④ Coverage: n_cells * 1000 / strip_total_cells ≥ coverage_min
        //    where strip_total_cells = strip_width * zone_h.
        //    Rearranged to avoid division: n * 1000 ≥ coverage_min * total
        let total_cells: u32 = strip_width * zone_h;
        let coverage_min_u32: u32 = coverage_min.into();
        let lhs: u64 = (n.into()) * 1000_u64;
        let rhs: u64 = (coverage_min_u32.into()) * (total_cells.into());
        if lhs < rhs {
            return FAIL_COVERAGE;
        }

        FAIL_NONE
    }

    // ── Constructor ────────────────────────────────────────────────────────
    //
    // Note: the cairo_verifier_addr argument is REMOVED from this rev.
    // The contract no longer delegates to a per-drone STARK verifier;
    // the predicate check is now in-contract.
    #[constructor]
    fn constructor(
        ref self: ContractState,
        l1_commander_addr: felt252,
        l1_verifier_addr:  felt252,
    ) {
        self.l1_commander_addr.write(l1_commander_addr);
        self.l1_verifier_addr.write(l1_verifier_addr);
    }
}

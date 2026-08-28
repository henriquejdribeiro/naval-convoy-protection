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
//      ON-CHAIN
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
// ── Design note  ─────────────────
//
// Cells are submitted as L2 invoke calldata
// and the contract evaluates the four predicates directly.
//
// Implications:
//   - Telemetry is PUBLIC on L2 — anyone reading Madara history sees
//     each cell's (x, y, p_contact, ts). The Pedersen-hiding commitment H
//     is no longer required (kept only as an audit trail).
//   - The cryptographic proof L1 verifies is
//     the Madara-block STARK proof produced by SNOS + Stone (which
//     attests that THIS contract correctly evaluated the predicates on
//     the public telemetry — i.e. zk-rollup execution proof, not a
//     drone-side privacy proof).
// =============================================================================

// Starknet's native address type (a felt252-backed contract/account address).
// Imported at module top so the public types + the IConvoyProtocol trait below
// can refer to it — e.g. the drone account addresses in open_mission's
// `Array<ContractAddress>` and the `get_drone_addr` view's return type.
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

/// One drone's assigned sub-area: the rectangle [x_start, x_end) × [y_start, y_end).
/// Bounds are HALF-OPEN (x_end / y_end exclusive) so adjacent strips tile the
/// zone without overlap — drone i's x_end == drone i+1's x_start.
///
/// NOT #[starknet::Store] on purpose: a strip is never persisted. It's derived
/// on demand from the stored MissionSpec via derive_strip(spec, drone_id), so
/// storing it would be redundant. We keep:
///   Drop  — discardable
///   Copy  — passed by value into the predicate checks
///   Serde — get_strip() RETURNS this across the ABI (output must serialize to
///           felts). Note: needed for crossing the ABI, NOT for storage.
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


// #[starknet::contract] = the deployable contract (gets a class hash + address).
// (Compare: #[starknet::interface] above = the ABI trait; #[..contract(account)]
//  in drone_account = an account contract.) Storage, events, constructor, and
// the external impl all live inside this module.
//
// NOTE: a Cairo module is its OWN scope — it does NOT inherit the file's
// top-level imports, so we re-`use` everything the contract body needs below
// (that's why ContractAddress appears here again).
#[starknet::contract]
mod ConvoyProtocol {

    // Caller identity + address type.
    //   get_caller_address() → who invoked this fn. submit_telemetry uses it to
    //   assert the caller IS the registered drone account (account-abstraction
    //   enforcement — the whole "telemetry is unforgeable per drone" guarantee).
    use core::starknet::{
        ContractAddress, get_caller_address,
    };

    // Storage access.
    //   Map                     the key→value storage type used in `struct Storage`.
    //   StoragePointer*Access   enable .read()/.write() on PLAIN storage vars.
    //   StorageMap*Access       enable .read(key)/.write(key,val) on Maps.
    //   ⚠ In Cairo, .read()/.write() are TRAIT methods — the trait must be in
    //     scope or the call won't compile. Importing `Map` alone is not enough;
    //     you also need these *Access traits. (Common first-time gotcha.)
    use core::starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess,
    };

    // The L2→L1 message hook. Fired by submit_telemetry when the 5th drone lands
    // SAFE; the relay then hand-credits it on L1. (This is the syscall that needs
    // L1 gas — the reason only the 5th drone's tx hit the gas issue.)
    use core::starknet::syscalls::send_message_to_l1_syscall;

    // Shared types + codes defined at FILE scope (outside this module) so BOTH
    // the interface trait and this contract can use them. `super::` = the parent
    // (file) module; we reach up to pull them into the contract's scope.
    use super::{
        MissionSpec, StripBounds,
        VERDICT_PENDING, VERDICT_SAFE, VERDICT_UNSAFE,
        FAIL_NONE, FAIL_STRIP, FAIL_DETECTION, FAIL_TIME, FAIL_COVERAGE,
    };

    // ── Storage ────────────────────────────────────────────────────────────
    //
    // THE contract's permanent, PUBLIC, on-chain state — the only data that
    // survives between transactions. Exactly one #[storage] struct per contract.
    //
    // Most fields are Map<K,V>: a family of storage slots addressed by a key
    // (slot ≈ hash(field, key)), i.e. a key→value mapping — NOT a single value.
    //
    // IMPORTANT — what is NOT here: the raw cells (x/y/p_contact/ts). Those
    // arrive as calldata, get checked, and are thrown away — only the DECISION
    // is stored. The raw telemetry lives in the L2 block history (the tx
    // calldata), which IS the audit trail. Contract stores the verdict; the
    // chain stores the evidence.
    //
    // The per-drone maps below are "parallel maps": four separate maps that all
    // use the SAME key = encode_drone_key(mid, did) (= mid*256 + did). Compute
    // the key once, read/write all four at it. The packing guarantees distinct
    // (mission, drone) pairs never collide within a map.
    #[storage]
    struct Storage {
        // ── Per-mission spec (the mission's "constitution") ─────────────────
        missions:       Map<felt252, MissionSpec>, // mission_id → full spec, stored verbatim
        mission_exists: Map<felt252, bool>,        // mission_id → "was this deployed?"
        // ↑ needed because reading a never-set mission returns a ZEROED spec,
        //   indistinguishable from a real all-zero one. You can't tell "unset"
        //   from "zero" without a flag — so every entry point checks this bool.

        // Per-drone state — keyed by encode_drone_key(mid, did)
        drone_addr:    Map<felt252, ContractAddress>,   // → the L2 account allowed to submit
        verdicts:      Map<felt252, u8>,                // → PENDING(0)/SAFE(1)/UNSAFE(2)  (0 = default = not yet submitted)
        fail_reasons:  Map<felt252, u8>,                // → which predicate rejected it (FAIL_* code)
        n_cells_map:   Map<felt252, u32>,               // → how many cells the drone reported

        // Per-mission aggregates
        safe_count: Map<felt252, u8>,                   // mission_id → # of SAFE drones so far. THE counter relay-l2-messages reads.
        l1_emitted: Map<felt252, bool>,                 // mission_id → has the all-SAFE L1 message been sent?
        // ↑ idempotency latch: guarantees the L2→L1 MissionSafe message fires
        //   EXACTLY ONCE, even if the 5th submission is somehow re-run.

        // ── Configuration — written once in constructor, immutable after ────
        // Note: felt252, NOT ContractAddress. These are L1 (Ethereum) addresses;
        // ContractAddress is an L2 type. An L1 address (160 bits) crosses the
        // bridge as a plain felt252. Type = which chain the address belongs to.
        l1_commander_addr: felt252,    // L1 address authorised to call open_mission (#[l1_handler] sender check)
        l1_verifier_addr:  felt252,    // L1 destination of the all-SAFE send_message_to_l1
    }

    // ── Events ─────────────────────────────────────────────────────────────
    //
    // Events are the contract's BROADCAST LOG — written into the block, NOT
    // into storage. The contract can't read them back; they exist for off-chain
    // consumers (the webapp, the relay, indexers) to WATCH what happened.
    // Cheap (no storage slot). Storage = "what's true now" (pull); events =
    // "tell me the moment it happens" (push). submit_telemetry does BOTH.
    //
    // Every contract has ONE #[event] enum listing all emittable events. Each
    // variant maps a NAME → a data struct. The VARIANT name is the on-chain
    // event name: its selector = starknet_keccak(variant) — e.g. "MissionSafe"
    // hashes to 0x027a07… which is exactly relay-l2-messages' MISSION_SAFE_SELECTOR.
    // (starknet::Event = the derive that makes a type emittable.)
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MissionDeployed:    MissionDeployed,        // fired when a mission is opened
        TelemetrySubmitted: TelemetrySubmitted,     // fired on EVERY drone submission (safe or unsafe)
        MissionSafe:        MissionSafeEvent,       // fired when the last drone lands SAFE (L1 msg just sent)
        MissionUnsafe:      MissionUnsafeEvent,     // fired when a drone submits UNSAFE

        // ^ variant name = MissionSafe (clean on-chain name); struct is
        //   MissionSafeEvent only to avoid a type-name clash — logs say "MissionSafe".
    }

    // #[key] = an INDEXED field (like Solidity's `indexed`). Keys go into the
    // event's `keys` array (filterable/searchable off-chain); the rest go into
    // `data`. So #[key] mission_id lets a consumer fetch "all events for mission 1".

    // Emitted by _do_open_mission after a mission is registered on L2.
    #[derive(Drop, starknet::Event)]
    struct MissionDeployed {
        #[key] mission_id: felt252,    // filter by mission
        swarm_id: felt252,             // 1 = Alpha, 2 = Bravo
        n_drones: u8,
    }

    // Emitted by submit_telemetry on EVERY submission — the per-drone outcome.
    // Two keys → consumers can filter by mission AND by individual drone.
    #[derive(Drop, starknet::Event)]
    struct TelemetrySubmitted {
        #[key] mission_id: felt252,
        #[key] drone_id:   u8,
        verdict:     u8,                // VERDICT_SAFE / VERDICT_UNSAFE
        fail_reason: u8,                // FAIL_* code (FAIL_NONE if SAFE)
        n_cells:     u32,               // how many cells the drone reported
    }

    // Emitted by submit_telemetry when safe_count reaches n_drones — the whole
    // swarm cleared. This is the L2 half of the L2→L1 MissionSafe signal.
    #[derive(Drop, starknet::Event)]
    struct MissionSafeEvent {
        #[key] mission_id: felt252,
        n_drones: u8,
    }

    // Emitted by submit_telemetry when a drone fails a predicate — names the
    // culprit drone and which of the four checks rejected it (for diagnostics).
    #[derive(Drop, starknet::Event)]
    struct MissionUnsafeEvent {
        #[key] mission_id: felt252,
        failing_drone: u8,
        fail_reason:   u8,              // FAIL_STRIP / FAIL_DETECTION / FAIL_TIME / FAIL_COVERAGE
    }

    // ── Mission deployment — two entry points share one implementation ─────
    //
    // PRODUCTION PATH: #[l1_handler] open_mission
    //   Triggered when the L1 Commander bridge calls L1's
    //   StarknetCore.sendMessageToL2(this_contract, selector, payload).
    //   Madara's block builder routes the message to this handler with
    //   `from_address` auto-filled to the L1 sender (unforgeable), which the
    //   handler checks against l1_commander_addr for authorisation.
    //
    // Shared helper _do_open_mission contains the spec-sanity checks
    // and storage writes for the l1_handler.
    #[l1_handler]
    // #[l1_handler] = this fn is callable ONLY via an L1→L2 message, never as a
    // normal L2 invoke. When the L1 StarknetCore emits sendMessageToL2 targeting
    // this contract + the open_mission selector, Madara's sequencer injects a
    // transaction that calls this handler. (Active on the convoy stack: each
    // swarm's Madara runs --sequencer with L1 sync against its real Starknet core.)
    fn open_mission(
        ref self: ContractState,
        // ⚠ SPECIAL: an l1_handler's FIRST arg is always the L1 sender address,
        //   AUTO-FILLED by the protocol — the caller cannot supply or spoof it.
        //   This is the trust anchor that makes the check below meaningful.
        from_address: felt252,
        spec:            MissionSpec,
        drone_addresses: Array<ContractAddress>,
    ) {
        // AUTHORISATION: only the registered L1 commander may open a mission.
        // Because from_address is protocol-injected (not forgeable), this is a
        // real authority check: only the registered L1 commander can open a
        // mission, via the unforgeable protocol-injected sender.
        // ('unauthorised L1 sender' is a Cairo short-string error: a felt252-
        //  encoded literal, max 31 chars.)
        assert(
            from_address == self.l1_commander_addr.read(),
            'unauthorised L1 sender',
        );

        // Hand off to the shared body — same storage writes + validation as the
        // dev path, so the two entry points can never drift apart.
        _do_open_mission(ref self, spec, drone_addresses);
    }

    // Shared deployment body. NO authorisation check here — that's the caller's
    // job (open_mission asserts the unforgeable L1 sender). Kept separate so the
    // handler stays focused on auth.
    fn _do_open_mission(
        ref self: ContractState,

        // The full mission definition (geometry + thresholds). Passed by value —
        // MissionSpec is Copy, so `spec` is a cheap local copy we read fields off.
        spec:            MissionSpec,

        // The N drone account addresses, IN ORDER: index i ↔ drone_id (i+1).
        // Array is passed by value (consumed here); it's read positionally in
        // step 4 to register each drone under encode_drone_key(mission_id, i+1).
        drone_addresses: Array<ContractAddress>,
    ) {
        // 1. Idempotency — a mission_id can be opened ONCE. Re-deploy attempts
        //    revert here.
        assert(
            !self.mission_exists.read(spec.mission_id),
            'mission already deployed',
        );

        // 2. Spec sanity — reject a malformed mission before persisting anything.
        assert(spec.n_drones > 0_u8, 'n_drones must be > 0');
        // u8 → u32 widening (.into() is infallible) so we can compare against
        // the u32 geometry fields below.
        let n_drones_u32: u32 = spec.n_drones.into();
        // THE tiling invariant: strips must cover the zone EXACTLY — no gaps,
        // no overlap. strip_width * n_drones must equal zone_w.
        assert(spec.zone_w == spec.strip_width * n_drones_u32, 'zone_w not divisible');
        assert(spec.zone_h > 0_u32, 'zone_h must be > 0');
        assert(spec.strip_width > 0_u32, 'strip_width must be > 0');
        // Exactly one account address per drone.
        assert(drone_addresses.len() == n_drones_u32, 'drone addr count mismatch');

        // 3. Persist the spec. Writing mission_exists=true is what makes step 1's
        //    idempotency guard trip on any future call for this mission_id.
        self.missions.write(spec.mission_id, spec);
        self.mission_exists.write(spec.mission_id, true);

        // 4. Register each drone's account address under encode_drone_key(mid,did).
        //    Cairo has no C-style `for` — the idiom is `loop { if done break; }`.
        //    Note the index dance: i is 0-based, but drone_id is 1-based
        //    (drone_id = i + 1), matching the [1, n_drones] convention everywhere.
        let mut i: u32 = 0;
        loop {
            if i >= n_drones_u32 { break; }
            // u32 → u8 narrowing: try_into() can fail (value > 255), unwrap()
            // panics if so — safe here since n_drones is a u8 (≤ 255).
            let drone_id_u8: u8 = (i + 1_u32).try_into().unwrap();
            let key = encode_drone_key(spec.mission_id, drone_id_u8);
            // *drone_addresses.at(i): .at(i) returns a snapshot (read-only ref)
            // into the array; the * dereferences it to copy the ContractAddress out.
            self.drone_addr.write(key, *drone_addresses.at(i));
            i += 1_u32;
        };

        // Broadcast that the mission is live (off-chain consumers pick this up).
        self.emit(MissionDeployed {
            mission_id: spec.mission_id,
            swarm_id:   spec.swarm_id,
            n_drones:   spec.n_drones,
        });
    }

    // ── External entry points ──────────────────────────────────────────────
    //
    // #[abi(embed_v0)] on this impl is what MAKES these functions external —
    // it binds the IConvoyProtocol trait to real code and exposes each fn in
    // the ABI. (This embed is why there's no per-fn #[external_v0] attribute.)
    #[abi(embed_v0)]
    impl ConvoyProtocolImpl of super::IConvoyProtocol<ContractState> {

        // THE core function. A drone submits its raw sweep; the contract checks
        // it, records SAFE/UNSAFE, and — on the final SAFE drone — messages L1.
        // Structure: 5 guard checks → derive+evaluate → record → aggregate.
        fn submit_telemetry(
            ref self: ContractState,
            mission_id:       felt252,
            drone_id:         u8,
            // Four PARALLEL arrays: cell i = (x[i], y[i], p_contact[i], ts[i]).
            // Split into separate arrays (not an array of structs) because that's
            // how they arrive as calldata — and it's what the `-i` stdin bug
            // truncated (empty calldata → these mismatch at step 5).
            cells_x:          Array<u32>,
            cells_y:          Array<u32>,
            cells_p_contact:  Array<u16>,
            cells_ts:         Array<u64>,
        ) {

            // ── GUARDS (steps 1–5): reject bad input before doing real work ──

            // 1. Mission must be deployed (mission_exists distinguishes "unset"
            //    from a zeroed spec). Then load the spec for this mission's geometry.
            assert(self.mission_exists.read(mission_id), 'mission not deployed');
            let spec = self.missions.read(mission_id);

            // 2. drone_id ∈ [1, n_drones]
            assert(drone_id >= 1_u8,          'drone_id < 1');
            assert(drone_id <= spec.n_drones, 'drone_id > n_drones');

            // 3. THE identity check: caller must BE the account registered for this
            //    (mission, drone). get_caller_address() is protocol-supplied and
            //    unforgeable, so only the drone holding the matching key can submit
            //    as itself. This is what makes telemetry attributable per-drone.
            let dkey = encode_drone_key(mission_id, drone_id);
            let expected_caller = self.drone_addr.read(dkey);
            assert(get_caller_address() == expected_caller, 'wrong drone caller');

            // 4. One shot: verdict must still be PENDING (default 0). Prevents a
            //    drone re-submitting to overwrite or double-count its verdict.
            let prior = self.verdicts.read(dkey);
            assert(prior == VERDICT_PENDING, 'already submitted');

            // 5. The four arrays must be equal-length and non-empty (they're read
            //    in lockstep by index in evaluate_predicates).
            let n_cells = cells_x.len();
            assert(n_cells > 0_u32,                       'n_cells must be > 0');
            assert(cells_y.len() == n_cells,              'cells_y length mismatch');
            assert(cells_p_contact.len() == n_cells,      'p_contact length mismatch');
            assert(cells_ts.len() == n_cells,             'cells_ts length mismatch');

            // ── VERDICT (steps 6–8) ─────────────────────────────────────────

            // 6. Compute THIS drone's assigned strip from the stored geometry.
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

            // 8. Map fail-code → verdict, persist verdict + reason + cell count,
            //    and broadcast the per-drone outcome.
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

            // ── AGGREGATE + L1 MESSAGE (step 9) ─────────────────────────────

            if new_verdict == VERDICT_SAFE {
                // Bump the SAFE tally for this mission (the counter relay reads).
                let new_count = self.safe_count.read(mission_id) + 1_u8;
                self.safe_count.write(mission_id, new_count);

                // If THIS was the last drone to clear (and we haven't already
                // fired), send the L2→L1 "all SAFE" message — exactly once.
                // NOTE: only this branch runs send_message_to_l1_syscall, which
                // needs L1 gas — that's why only the 5th drone's tx hit the
                // "Insufficient max L1Gas" issue. l1_emitted is the once-only latch.
                if new_count == spec.n_drones && !self.l1_emitted.read(mission_id) {
                    // All drones SAFE — emit the L1 message exactly once.
                    self.l1_emitted.write(mission_id, true);

                    // Payload = [mission_id, n_drones]. The L1 Verifier is the
                    // destination (l1_verifier_addr, an L1 addr stored as felt252).
                    // .span() gives the syscall a read-only view of the array.
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
                // UNSAFE → no tally bump; emit a diagnostic naming the culprit
                // drone and which predicate rejected it.
                self.emit(MissionUnsafeEvent {
                    mission_id,
                    failing_drone: drone_id,
                    fail_reason:   fail,
                });
            }
        }

        // ── Views: read-only (self: @ContractState), no state change, no gas ──
        // Each is a thin storage read (or a derive). They exist for tooling /
        // the webapp / debugging — only safe_count is used by the core flow (relay).

        // Full spec; reverts if the mission was never deployed.
        fn get_mission(self: @ContractState, mission_id: felt252) -> MissionSpec {
            assert(self.mission_exists.read(mission_id), 'mission not deployed');
            self.missions.read(mission_id)
        }

        // The account authorised to submit for (mission, drone).
        fn get_drone_addr(
            self: @ContractState, mission_id: felt252, drone_id: u8,
        ) -> ContractAddress {
            self.drone_addr.read(encode_drone_key(mission_id, drone_id))
        }

        // Recompute the drone's strip from the mission geometry.
        fn get_strip(
            self: @ContractState, mission_id: felt252, drone_id: u8,
        ) -> StripBounds {
            let spec = self.missions.read(mission_id);
            derive_strip(spec, drone_id)
        }

        // Per-drone verdict code (0=PENDING / 1=SAFE / 2=UNSAFE).
        fn verdict(self: @ContractState, mission_id: felt252, drone_id: u8) -> u8 {
            self.verdicts.read(encode_drone_key(mission_id, drone_id))
        }

        // If UNSAFE, which predicate failed (FAIL_* code).
        fn fail_reason(self: @ContractState, mission_id: felt252, drone_id: u8) -> u8 {
            self.fail_reasons.read(encode_drone_key(mission_id, drone_id))
        }

        // True iff every drone in the mission is SAFE. Convenience over safe_count;
        // returns false for an undeployed mission instead of reverting.
        fn mission_safe(self: @ContractState, mission_id: felt252) -> bool {
            if !self.mission_exists.read(mission_id) { return false; }
            let spec = self.missions.read(mission_id);
            self.safe_count.read(mission_id) == spec.n_drones
        }

        // # of SAFE drones so far — THE value relay-l2-messages.sh polls.
        fn safe_count(self: @ContractState, mission_id: felt252) -> u8 {
            self.safe_count.read(mission_id)
        }

        // How many cells the drone reported (0 if no submission yet).
        fn get_n_cells(
            self: @ContractState, mission_id: felt252, drone_id: u8,
        ) -> u32 {
            self.n_cells_map.read(encode_drone_key(mission_id, drone_id))
        }
    }

    // ── Pure helpers ───────────────────────────────────────────────────────
    // Module-level (outside the impl) = PRIVATE. Internal utilities, not in the
    // ABI. Both are pure/stateless: they compute from inputs, never touch storage.

    /// Pack (mission_id, drone_id) into one felt252 so the per-drone Maps can be
    /// keyed by the pair. `mission_id * 256 + drone_id` is a bit-shift: mission_id
    /// occupies the high bits, drone_id the low 8. Since drone_id is u8 (<256) it
    /// can't collide into the mission portion → distinct pairs give distinct keys.
    fn encode_drone_key(mission_id: felt252, drone_id: u8) -> felt252 {
        let drone_felt: felt252 = drone_id.into();     // u8 → felt252 (infallible widening)
        mission_id * 256 + drone_felt
    }

    /// Turn the stored geometry into drone_id's actual rectangle. Pure (no storage)
    /// — that's why StripBounds isn't #[Store]; it's recomputed on demand here and
    /// in the get_strip view. Assumes 1-based drone_id (caller guards drone_id>=1;
    /// drone_id==0 would underflow at `drone_id - 1`).
    fn derive_strip(spec: MissionSpec, drone_id: u8) -> StripBounds {
        let i_u32: u32 = (drone_id - 1_u8).into();                   // 1-based id → 0-based index 
        let x_start = spec.zone_x + i_u32 * spec.strip_width;        // walk i strips right of origin
        StripBounds {
            x_start: x_start,
            x_end:   x_start + spec.strip_width,                     // one strip wide (exclusive)
            y_start: spec.zone_y,
            y_end:   spec.zone_y + spec.zone_h,                      // full zone height for every drone
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

            // ① Strip bounds: the cell must lie inside this drone's assigned rectangle
            if x < strip.x_start || x >= strip.x_end {
                break FAIL_STRIP;
            }
            if y < strip.y_start || y >= strip.y_end {
                break FAIL_STRIP;
            }

            // ② Detection: every cell must show contact probability below threshold
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
                break FAIL_TIME; // too late
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
    // Information known at deployment time (L1 commander/verifier addresses) is written once and never changed.
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

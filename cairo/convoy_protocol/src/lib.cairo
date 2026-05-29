// =============================================================================
// convoy_protocol — Cairo 1 starknet contract for L2 (Madara)
// =============================================================================
// 5-drone-per-swarm architecture (rev 2026-05).
//
// Each mission = a swarm of N drones (typically 5). Each drone covers a
// vertical strip of the swarm's frontal area. The contract:
//
//   1. Receives mission spec from L1 via #[l1_handler] open_mission
//   2. Records the N drone account addresses (one per drone_id 1..N)
//   3. Accepts a STARK proof per drone via submit_commitment, delegating
//      the cryptographic check to a STARK verifier contract whose address
//      is stored at construction time (Stwo-cairo or Stone-cairo)
//   4. Aggregates verdicts; emits L1 message when all N drones SAFE
//
// Strip derivation (deterministic, computed in-contract):
//
//   strip_width      = spec.zone_w / spec.n_drones        (enforced exact)
//   strip[i].x_start = spec.zone_x + (i-1) * strip_width  (drone_id i ∈ 1..N)
//   strip[i].x_end   = strip[i].x_start + strip_width
//   strip[i].y_start = spec.zone_y
//   strip[i].y_end   = spec.zone_y + spec.zone_h
//
// The Cairo program (safe_area_verify.cairo) MUST write the strip bounds
// to [output_ptr] in the same order this contract builds them as proof
// public inputs. Any mismatch (e.g. drone sweeps its neighbour's strip)
// causes the verifier call to revert.
//
// Privacy: the public output schema is intentionally minimal — only
//   (mission_id, drone_id, strip bounds, verdict_bool, H)
// crosses the L3→L2 boundary. Cell-level telemetry stays in the drone's
// volatile memory as Cairo hints. With Stwo enabled (strict ZK at the
// prover) plus a hiding Pedersen commitment H (cells_nonce added in
// safe_area_verify), the proof reveals nothing about the cells beyond
// the swarm-level verdict.
//
// Replaces the previous submit_telemetry/submit_sweep_commitment model
// (rev pre-2026-05) which stored cell data on-chain. That model leaked
// telemetry through chain history; this one keeps it hint-private.
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

// ── Interfaces ─────────────────────────────────────────────────────────────

/// Abstract STARK verifier contract. The address is supplied at
/// construction; this can be:
///   - The Stwo-cairo verifier  (strict ZK at L3→L2, recommended)
///   - The Stone-cairo verifier (soundness only, legacy)
///
/// `public_inputs` is the EXACT felt252 sequence the proof's [output_ptr]
/// committed to. The contract builds it from (mission_id, drone_id, strip
/// bounds, verdict_bool, commitment_H). Any divergence triggers a revert.
#[starknet::interface]
pub trait ICairoVerifier<TContractState> {
    fn verify_stark_proof(
        self: @TContractState,
        proof:         Span<felt252>,
        public_inputs: Span<felt252>,
    );
}

#[starknet::interface]
pub trait IConvoyProtocol<TContractState> {
    // ── Mutating entry points ───────────────────────────────────────
    //
    // open_mission is invoked via #[l1_handler]; it is NOT part of the
    // public interface but lives in the contract module.

    /// L3→L2 submission of a single drone's commitment + ZK proof.
    /// Reverts if:
    ///   - mission_id not deployed
    ///   - drone_id out of range or already submitted
    ///   - caller is not the registered drone account
    ///   - verify_stark_proof rejects the proof
    fn submit_commitment(
        ref self: TContractState,
        mission_id:    felt252,
        drone_id:      u8,
        commitment_H:  felt252,
        verdict_bool:  u8,
        proof:         Span<felt252>,
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

    /// True iff every drone in the mission has submitted SAFE.
    fn mission_safe(self: @TContractState, mission_id: felt252) -> bool;

    /// Number of drones currently in SAFE state for the mission.
    fn safe_count(self: @TContractState, mission_id: felt252) -> u8;

    /// The hiding-Pedersen commitment H this drone submitted (0 if pending).
    fn get_commitment(self: @TContractState, mission_id: felt252, drone_id: u8)
        -> felt252;

    /// The address of the configured STARK verifier (for off-chain reference).
    fn get_cairo_verifier(self: @TContractState) -> ContractAddress;
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
    use core::pedersen::pedersen;

    use super::{
        MissionSpec, StripBounds,
        ICairoVerifierDispatcher, ICairoVerifierDispatcherTrait,
        VERDICT_PENDING, VERDICT_SAFE, VERDICT_UNSAFE,
    };

    // ── Storage ────────────────────────────────────────────────────────────
    //
    // Storage keys for the per-(mission, drone) maps are computed via
    // `encode_drone_key(mid, did)` so the four parallel maps share the
    // same slot space without colliding.
    #[storage]
    struct Storage {
        // Per-mission specs
        missions:       Map<felt252, MissionSpec>,
        mission_exists: Map<felt252, bool>,

        // Per-drone state — keyed by encode_drone_key(mid, did)
        drone_addr:  Map<felt252, ContractAddress>,
        commitments: Map<felt252, felt252>,
        verdicts:    Map<felt252, u8>,

        // Per-mission aggregates
        safe_count: Map<felt252, u8>,
        l1_emitted: Map<felt252, bool>,

        // Configuration (set at constructor, immutable thereafter)
        cairo_verifier:    ContractAddress,
        l1_commander_addr: felt252,    // L1 address authorised to call open_mission
        l1_verifier_addr:  felt252,    // L1 destination for the all-SAFE message
    }

    // ── Events ─────────────────────────────────────────────────────────────
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MissionDeployed:     MissionDeployed,
        CommitmentSubmitted: CommitmentSubmitted,
        MissionSafe:         MissionSafeEvent,
        MissionUnsafe:       MissionUnsafeEvent,
    }

    #[derive(Drop, starknet::Event)]
    struct MissionDeployed {
        #[key] mission_id: felt252,
        swarm_id: felt252,
        n_drones: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct CommitmentSubmitted {
        #[key] mission_id: felt252,
        #[key] drone_id:   u8,
        verdict:    u8,
        commitment: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct MissionSafeEvent {
        #[key] mission_id: felt252,
        aggregate_commitment: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct MissionUnsafeEvent {
        #[key] mission_id: felt252,
        failing_drone: u8,
    }

    // ── L1 → L2 handler — mission deployment ───────────────────────────────
    //
    // Triggered when the L1 Commander bridge calls L1's
    // `StarknetCore.sendMessageToL2(this_contract, selector, payload)`. The
    // Madara block builder routes the message to this function. `from_address`
    // is the L1 sender, which we lock to the configured Commander bridge.
    //
    // For Cairo 1 #[l1_handler], complex struct/array payloads are decoded
    // automatically by the Serde derive on MissionSpec and Array<...>.
    #[l1_handler]
    fn open_mission(
        ref self: ContractState,
        from_address: felt252,
        spec:            MissionSpec,
        drone_addresses: Array<ContractAddress>,
    ) {
        // 1. Authorisation
        assert(
            from_address == self.l1_commander_addr.read(),
            'unauthorised L1 sender',
        );

        // 2. Idempotency
        assert(
            !self.mission_exists.read(spec.mission_id),
            'mission already deployed',
        );

        // 3. Spec sanity
        assert(spec.n_drones > 0_u8, 'n_drones must be > 0');
        let n_drones_u32: u32 = spec.n_drones.into();
        assert(spec.zone_w == spec.strip_width * n_drones_u32, 'zone_w not divisible');
        assert(spec.zone_h > 0_u32, 'zone_h must be > 0');
        assert(spec.strip_width > 0_u32, 'strip_width must be > 0');
        assert(drone_addresses.len() == n_drones_u32, 'drone addr count mismatch');

        // 4. Persist spec
        self.missions.write(spec.mission_id, spec);
        self.mission_exists.write(spec.mission_id, true);

        // 5. Register each drone's account address against (mid, did)
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

        fn submit_commitment(
            ref self: ContractState,
            mission_id:   felt252,
            drone_id:     u8,
            commitment_H: felt252,
            verdict_bool: u8,
            proof:        Span<felt252>,
        ) {
            // 1. Mission must exist
            assert(self.mission_exists.read(mission_id), 'mission not deployed');
            let spec = self.missions.read(mission_id);

            // 2. drone_id ∈ [1, n_drones]
            assert(drone_id >= 1_u8,            'drone_id < 1');
            assert(drone_id <= spec.n_drones,   'drone_id > n_drones');

            // 3. Caller must be the registered drone account
            let dkey = encode_drone_key(mission_id, drone_id);
            let expected_caller = self.drone_addr.read(dkey);
            assert(get_caller_address() == expected_caller, 'wrong drone caller');

            // 4. Not yet submitted
            let prior = self.verdicts.read(dkey);
            assert(prior == VERDICT_PENDING, 'already submitted');

            // 5. verdict_bool must be 0 or 1
            assert(verdict_bool == 0_u8 || verdict_bool == 1_u8, 'verdict_bool not 0/1');

            // 6. Derive this drone's strip bounds from the spec
            let strip = derive_strip(spec, drone_id);

            // 7. Compose the proof's expected public-input vector.
            //    safe_area_verify.cairo writes EXACTLY these felts to
            //    [output_ptr]; the verifier confirms the proof attests to
            //    a Cairo run whose serialised outputs match.
            let public_inputs = array![
                mission_id,
                drone_id.into(),
                strip.x_start.into(),
                strip.x_end.into(),
                strip.y_start.into(),
                strip.y_end.into(),
                verdict_bool.into(),
                commitment_H,
            ];

            // 8. Delegate cryptographic verification to the configured
            //    Cairo verifier contract (Stwo-cairo or Stone-cairo).
            let verifier = ICairoVerifierDispatcher {
                contract_address: self.cairo_verifier.read(),
            };
            verifier.verify_stark_proof(proof, public_inputs.span());

            // 9. Record commitment + verdict
            self.commitments.write(dkey, commitment_H);
            let new_verdict = if verdict_bool == 1_u8 { VERDICT_SAFE }
                              else                    { VERDICT_UNSAFE };
            self.verdicts.write(dkey, new_verdict);

            self.emit(CommitmentSubmitted {
                mission_id, drone_id,
                verdict:    new_verdict,
                commitment: commitment_H,
            });

            // 10. Aggregate updates
            if new_verdict == VERDICT_SAFE {
                let new_count = self.safe_count.read(mission_id) + 1_u8;
                self.safe_count.write(mission_id, new_count);

                if new_count == spec.n_drones && !self.l1_emitted.read(mission_id) {
                    // All drones SAFE — emit the L1 message exactly once.
                    self.l1_emitted.write(mission_id, true);
                    let agg = self.aggregate_commitment(mission_id, spec.n_drones);

                    let payload = array![mission_id, agg].span();
                    let _ = send_message_to_l1_syscall(
                        self.l1_verifier_addr.read(),
                        payload,
                    );

                    self.emit(MissionSafeEvent {
                        mission_id,
                        aggregate_commitment: agg,
                    });
                }
            } else {
                self.emit(MissionUnsafeEvent {
                    mission_id,
                    failing_drone: drone_id,
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

        fn mission_safe(self: @ContractState, mission_id: felt252) -> bool {
            if !self.mission_exists.read(mission_id) { return false; }
            let spec = self.missions.read(mission_id);
            self.safe_count.read(mission_id) == spec.n_drones
        }

        fn safe_count(self: @ContractState, mission_id: felt252) -> u8 {
            self.safe_count.read(mission_id)
        }

        fn get_commitment(
            self: @ContractState, mission_id: felt252, drone_id: u8,
        ) -> felt252 {
            self.commitments.read(encode_drone_key(mission_id, drone_id))
        }

        fn get_cairo_verifier(self: @ContractState) -> ContractAddress {
            self.cairo_verifier.read()
        }
    }

    // ── Internal helpers (instance methods, can read storage) ──────────────

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        /// Pedersen-chain the per-drone commitments into a single felt
        /// that L1 receives in the all-SAFE message.
        ///
        ///   agg = pedersen(...pedersen(pedersen(0, H_1), H_2)..., H_N)
        fn aggregate_commitment(
            self: @ContractState,
            mission_id: felt252,
            n_drones:   u8,
        ) -> felt252 {
            let mut acc: felt252 = 0;
            let mut i: u8 = 1_u8;
            loop {
                if i > n_drones { break; }
                let c = self.commitments.read(encode_drone_key(mission_id, i));
                acc = pedersen(acc, c);
                i += 1_u8;
            };
            acc
        }
    }

    // ── Pure helpers ───────────────────────────────────────────────────────

    /// Encode `(mission_id, drone_id)` into a single felt252 storage key.
    /// 8-bit slot for drone_id (well above any practical n_drones; we use 5).
    /// Collisions between missions impossible because mission_ids are unique.
    fn encode_drone_key(mission_id: felt252, drone_id: u8) -> felt252 {
        let drone_felt: felt252 = drone_id.into();
        mission_id * 256 + drone_felt
    }

    /// Derive the sub-area assigned to `drone_id ∈ [1, n_drones]`.
    /// strip_width was validated equal to zone_w / n_drones at open_mission,
    /// so this division is exact.
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

    // ── Constructor ────────────────────────────────────────────────────────
    #[constructor]
    fn constructor(
        ref self: ContractState,
        cairo_verifier_addr: ContractAddress,
        l1_commander_addr:   felt252,
        l1_verifier_addr:    felt252,
    ) {
        self.cairo_verifier.write(cairo_verifier_addr);
        self.l1_commander_addr.write(l1_commander_addr);
        self.l1_verifier_addr.write(l1_verifier_addr);
    }
}

// =============================================================================
// drone_account — OpenZeppelin Cairo Contracts v3 basic Account.
//
// Generated from the OZ wizard:
//   https://docs.openzeppelin.com/contracts-cairo/3.x/wizard
//
// One account contract per drone — the address derived from the drone's
// public key + this class hash is what gets registered in
// convoy_protocol.open_mission's drone_addresses array. submit_telemetry
// then asserts get_caller_address() == drone_addr[(mid, did)], enforcing
// real per-drone signing.
//
// STATUS: drones currently deploy against Madara's genesis-predeclared OZ class
// (0xe2eb8f…), so this source may not be separately declared. Verify with
// `scarb build && starkli class-hash …` — if it equals 0xe2eb8f… this is the
// canonical source; if not, it's a pivot leftover (retire or wire up a declare).
// =============================================================================

// On Starknet there are NO EOAs — every account is a contract. This IS what a
// drone "is" on L2: its on-chain identity. (account) marks it as an account
// contract, which lets it expose the protocol entrypoints __validate__ /
// __execute__ / __validate_declare__ / __validate_deploy__ and act as a tx sender.
#[starknet::contract(account)]
mod DroneAccount {

    // Compose ready-made OZ logic via COMPONENTS (Cairo's reuse model — no
    // inheritance). AccountComponent = signature-validate + execute; SRC5 =
    // interface introspection (the "are you an IAccount?" standard, ~ERC-165).
    use openzeppelin_account::AccountComponent;
    use openzeppelin_introspection::src5::SRC5Component;

    // Wire each component's storage + events into this host contract under the
    // names account/src5 (storage) and AccountEvent/SRC5Event (events).
    component!(path: AccountComponent, storage: account, event: AccountEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // PUBLIC face: #[abi(embed_v0)] embeds the component's external entrypoints
    // into this contract's ABI. The Mixin bundles them all: __validate__,
    // __execute__, __validate_declare__, is_valid_signature, get_public_key,
    // set_public_key + SRC5's supports_interface. This line is what makes the
    // contract usable as an account.
    #[abi(embed_v0)]
    impl AccountMixinImpl = AccountComponent::AccountMixinImpl<ContractState>;
    // PRIVATE toolbox: internal helpers (e.g. initializer), callable only from
    // inside this contract — NOT exposed externally (no #[abi]).
    impl AccountInternalImpl = AccountComponent::InternalImpl<ContractState>;

    // Storage. Each component owns its own slice via #[substorage(v0)] — the
    // host just hands over a namespace. The drone's public_key lives inside
    // `account`; SRC5's registered interfaces live inside `src5`.
    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: AccountComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    // Events. The host must aggregate each component's events; #[flat] surfaces
    // them directly (e.g. OwnerAdded) instead of nesting under a wrapper.
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: AccountComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    // Runs ONCE at deployment. Binds this account to the drone's key by storing
    // its public_key. From here on, only a signature from the matching PRIVATE
    // key passes __validate__ — which is exactly what makes telemetry
    // attributable to one drone (submit_telemetry checks caller == this address).
    // The address itself = hash(class_hash, [public_key], salt, deployer), so
    // key → address is deterministic and is what open_mission registers.
    #[constructor]
    fn constructor(ref self: ContractState, public_key: felt252) {
        self.account.initializer(public_key);
    }
}

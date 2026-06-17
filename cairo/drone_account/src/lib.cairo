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
// =============================================================================

#[starknet::contract(account)]
mod DroneAccount {
    use openzeppelin_account::AccountComponent;
    use openzeppelin_introspection::src5::SRC5Component;

    component!(path: AccountComponent, storage: account, event: AccountEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // Account Mixin (external entry-point bundle: __validate__, __execute__,
    // __validate_declare__, is_valid_signature, get_public_key, ...).
    #[abi(embed_v0)]
    impl AccountMixinImpl = AccountComponent::AccountMixinImpl<ContractState>;
    impl AccountInternalImpl = AccountComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        account: AccountComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: AccountComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, public_key: felt252) {
        self.account.initializer(public_key);
    }
}

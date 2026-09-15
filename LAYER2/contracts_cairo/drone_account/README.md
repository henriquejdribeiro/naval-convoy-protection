# Drone account (L2 identity) — verifiable

Every drone on L2 is an account contract — its on-chain identity. Each drone
deploys Madara devnet's genesis-predeclared account class:

    0xe2eb8f5672af4e6a4e8a8f1b44989685e668489b0a25437733756c5a34a1d6

which is **OpenZeppelin cairo-contracts v0.13.0 `AccountUpgradeable`, Cairo 2.6.3**.
This package reproduces it exactly.

## Reproduce + verify (source → deployed class hash)

    docker build -t scarb-2.6.3 - < LAYER2/contracts_cairo/drone_account/Dockerfile.scarb-2.6.3
    docker run --rm -v "$(pwd):/work" -w /work/LAYER2/contracts_cairo/drone_account scarb-2.6.3 scarb build
    docker run --rm -v "$(pwd):/work" -w /work convoy-cairo-builder \
      starkli class-hash LAYER2/contracts_cairo/drone_account/target/dev/drone_account_AccountUpgradeable.contract_class.json
    # → 0x00e2eb8f...cade9  (== the class hash above)

`generate-drone-accounts.sh` deploys one instance per drone; address =
hash(class_hash, [public_key], salt, deployer) — what open_mission registers and
submit_telemetry's get_caller_address() enforces.

Upstream source (Apache-2.0): https://github.com/OpenZeppelin/cairo-contracts/tree/v0.13.0
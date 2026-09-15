# Vendored: OpenZeppelin Contracts for Cairo v0.13.0 (MIT)

Readable copies of the account contract each drone deploys (class hash 0xe2eb8f…):
  - AccountUpgradeable.cairo — the account preset (composition + constructor)
  - AccountComponent.cairo    — the account logic (__validate__ STARK-curve
                                signature check, __execute__, get/set_public_key)

Source: github.com/OpenZeppelin/cairo-contracts @ v0.13.0 (MIT — see LICENSE here).
Reference copies for reading only — the verifiable build compiles the identical
files from the pinned `openzeppelin` v0.13.0 dependency (../Scarb.toml); the rest
of the component tree resolves from that dependency.
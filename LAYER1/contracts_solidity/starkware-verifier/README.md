# StarkWare `2023_9` GPS verifier suite (vendored bytecode)

Byte-identical Ethereum-mainnet bytecode of StarkWare's
`StarkWare_GpsStatementVerifier_2023_9` — the 7-builtin `starknet` verifier at
`cairoVerifierId = 6` — plus solc-0.6.12 creation bytecode for the two
constructor contracts, so the local Besu chain can host the *real* StarkWare
STARK verifier with no mainnet fork.

`scripts/deploy-stark-verifier.sh` deploys the suite and writes the resulting
addresses to `.tmp-l1/stark-verifier.env`.

## Provenance (Ethereum mainnet)

`bytecode/*.hex` = `eth_getCode` of the mainnet contracts:

| File | Mainnet address |
|---|---|
| Merkle | 0x634dcf4f1421fc4d95a968a559a450ad0245804c |
| Fri | 0xdef8a3b280a54ee7ed4f72e1c7d6098ad8df44fb |
| MemoryPage | 0x40864568f679c10ac9e72211500096a5130770fa |
| CpuConstraintPoly | 0xDd4cBe8CC7f420A9576F93E1D1CcC501495B5253 |
| CpuOods | 0x367B337Aa4A056CB78Fd74F94E283A73B27DfBB6 |
| Bootloader | 0xb4c61d092eCf1b69F1965F9D8DE639148ea26a40 |
| PedersenX / PedersenY | 0x3d571a45D2B14FF423D2DC4A0e7a46e07D9682bB / 0xFD12A123ecf4326E70A4D8b2bC260ec730BBE7Fd |
| EcdsaX / EcdsaY | 0xcB799CbBd4f5F0a3b6bbd9b55F59E8b301A0286B / 0x9e4FdD8ff1b11e8f788Af77caA4b0037c137EcC1 |
| Poseidon FR0/FR1/FR2 | 0xe7B835… / 0xC2969a… / 0xB5A575… (idx6) |
| Poseidon PR0/PR1 | 0x1Db84E… / 0x62960C… (idx6) |

Constructor contracts (recompiled from Sourcify-verified source, solc 0.6.12,
istanbul, optimizer runs 1000000):
- `gps_creation.hex` — GpsStatementVerifier `2023_9` (mainnet 0xd51A3D50d4D2f99a345a66971E650EEA064DD8dF)
- `cfv_creation.hex` — CpuFrilessVerifier idx6 (mainnet 0xaA2c9CDD4ceAebe9A35873B77F57FB47c3Ef11b9)

`hashes.env` — the GPS constructor's `simpleBootloaderProgramHash` and
`hashedSupportedCairoVerifiers`, read from the live mainnet GPS `getBootloaderConfig()`.

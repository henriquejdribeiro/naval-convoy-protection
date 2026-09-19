# StarkWare GPS STARK verifier — verifiable on-chain source

The L1 proof check is performed by StarkWare's on-chain GPS verifier suite
(`StarkWare_GpsStatementVerifier_2023_9`, `cairoVerifierId = 6`, layout6 /
"starknet"). We deploy the **byte-identical Ethereum-mainnet bytecode**
(`bytecode/*.hex` + `cfv_creation.hex` / `gps_creation.hex`) onto the local
Besu chain, so no mainnet fork is needed. This directory additionally vendors
the **verified Solidity source that recompiles to that bytecode**, so the
verification logic is readable and auditable — the L1 companion to the
verifiable Cairo drone account in `LAYER2/contracts_cairo/drone_account/`.

**License / attribution.** Apache-2.0, © 2019-2023 StarkWare Industries Ltd.
(`SPDX-License-Identifier: Apache-2.0`, `pragma solidity ^0.6.12`). The source
under `src/` is StarkWare's, vendored **unmodified** from the Sourcify
verified-source bundles of the deployed Ethereum-mainnet contracts.

## Layout

| Path | What |
|---|---|
| `bytecode/*.hex` | deployed **runtime** bytecode (`eth_getCode`) of the 15 stateless contracts |
| `cfv_creation.hex`, `gps_creation.hex` | **creation** bytecode of the two constructor contracts (CFV, GPS) |
| `hashes.env` | GPS `getBootloaderConfig()` — `simpleBootloaderProgramHash`, `hashedSupportedCairoVerifiers` |
| `src/<name>/` | verified Solidity source, one self-contained tree per deployed contract + its Sourcify `metadata.json`; `<name>` == the `bytecode/<name>.hex` basename (CFV/GPS map to the two `*_creation.hex`) |
| `extract-sources.py` | regenerates `src/` from `LAYER1/tmp-etherscan/sources/*.json` (address-driven) |
| `verify-bytecode.py` | recompiles each `src/<name>/` with solc 0.6.12 and diffs vs the deployed bytecode |

`SIMULATOR/demo/scripts/deploy-stark-verifier.sh` deploys the 15 stateless contracts,
then CFV, then GPS with `cairoVerifierContracts[6] = CFV`.

## Reproduce & verify

```bash
python3 extract-sources.py     # unpack Sourcify bundles -> src/
python3 verify-bytecode.py     # solc 0.6.12 recompile -> diff vs deployed bytecode
```

Compiler is pinned by each `metadata.json`: **solc 0.6.12+commit.27d51765, EVM
istanbul, optimizer enabled, runs = 1000000**.

## Verification result (2026-09-15)

**17 / 17 CODE-identical, 0 DIFF.** Every contract recompiles to the exact
deployed byte length and is byte-identical after removing the trailing CBOR
**metadata-hash digest**. The verdict is `CODE` (not `FULL`) because the
Sourcify bundles are `status: partial`: the metadata digest is a hash over the
original source paths/comments and differs on re-published source, while the
executable logic is identical. Identical byte length + identical stripped code
confine the only difference to that ~34-byte digest.

| Deployed contract | Mainnet address | `src/` dir | kind | bytes | verdict |
|---|---|---|---|--:|:--:|
| MerkleStatementContract | 0x634DCf4f1421Fc4D95A968A559a450ad0245804c | `Merkle/` | runtime | 1714 | CODE |
| FriStatementContract | 0xDEf8A3b280A54eE7Ed4f72E1c7d6098ad8df44fb | `Fri/` | runtime | 6656 | CODE |
| MemoryPageFactRegistry | 0x40864568f679c10aC9e72211500096a5130770fA | `MemoryPage/` | runtime | 2213 | CODE |
| CpuConstraintPoly | 0xDd4cBe8CC7f420A9576F93E1D1CcC501495B5253 | `CpuConstraintPoly/` | runtime | 14678 | CODE |
| CpuOods | 0x367B337Aa4A056CB78Fd74F94E283A73B27DfBB6 | `CpuOods/` | runtime | 18752 | CODE |
| CairoBootloaderProgram | 0xb4c61d092eCf1b69F1965F9D8DE639148ea26a40 | `Bootloader/` | runtime | 10907 | CODE |
| PedersenHashPointsXColumn | 0x3d571a45D2B14FF423D2DC4A0e7a46e07D9682bB | `PedersenX/` | runtime | 19293 | CODE |
| PedersenHashPointsYColumn | 0xFD12A123ecf4326E70A4D8b2bC260ec730BBE7Fd | `PedersenY/` | runtime | 19299 | CODE |
| EcdsaPointsXColumn | 0xcB799CbBd4f5F0a3b6bbd9b55F59E8b301A0286B | `EcdsaX/` | runtime | 9740 | CODE |
| EcdsaPointsYColumn | 0x9e4FdD8ff1b11e8f788Af77caA4b0037c137EcC1 | `EcdsaY/` | runtime | 9750 | CODE |
| PoseidonPoseidonFullRoundKey0Column | 0xe7B835eA7e348B25aF2480272C4ca28429573293 | `PoseidonFR0/` | runtime | 503 | CODE |
| PoseidonPoseidonFullRoundKey1Column | 0xC2969a099F22430e20bcE237F469ac6F3101Ac5f | `PoseidonFR1/` | runtime | 502 | CODE |
| PoseidonPoseidonFullRoundKey2Column | 0xB5A5759Dd063899F213eB9699906B445f855660D | `PoseidonFR2/` | runtime | 503 | CODE |
| PoseidonPoseidonPartialRoundKey0Column | 0x1Db84E79E8daEC762d6aDaa5bf358A4Ba001E975 | `PoseidonPR0/` | runtime | 2590 | CODE |
| PoseidonPoseidonPartialRoundKey1Column | 0x62960C874379653D7BBe3644Ac653736Da2eda12 | `PoseidonPR1/` | runtime | 1399 | CODE |
| CpuFrilessVerifier | 0xaA2c9CDD4ceAebe9A35873B77F57FB47c3Ef11b9 | `CpuFrilessVerifier/` | creation | 20808 | CODE |
| GpsStatementVerifier | 0xd51A3D50d4D2f99a345a66971E650EEA064DD8dF | `GpsStatementVerifier/` | creation | 9392 | CODE |

## Verification source inventory

The on-chain verification is composed of **17 deployed contracts = 48 unique
StarkWare `.sol` files** (physically ~97 copies on disk: each deployed
contract's `src/<name>/` tree carries its own copy of shared dependencies so it
compiles standalone), **plus 3 of our own `.sol` for the L1 identity gate** — 51
files total, of which we author 3. All vendored paths are under
`starkware-verifier/src/<ContractDir>/…`.

### What `convoy-submitter` calls (the 5 on-chain entry points)

| Phase | Deployed contract | Entry `.sol` |
|---|---|---|
| 1 | MerkleStatementContract | `Merkle/…/verifier/MerkleStatementContract.sol` |
| 2 | FriStatementContract | `Fri/…/verifier/FriStatementContract.sol` |
| 3 | MemoryPageFactRegistry | `MemoryPage/…/verifier/cpu/MemoryPageFactRegistry.sol` |
| 4a | GpsStatementVerifier | `GpsStatementVerifier/…/verifier/gps/GpsStatementVerifier.sol` |
| 4a → | CpuFrilessVerifier (`cairoVerifierId=6`) | `CpuFrilessVerifier/…/cpu/layout6/CpuFrilessVerifier.sol` |

### The 17 deployed contracts → main `.sol` (+ files in its tree)

| `src/` dir | Main contract file | # `.sol` |
|---|---|--:|
| `GpsStatementVerifier/` | `…/verifier/gps/GpsStatementVerifier.sol` | 14 |
| `CpuFrilessVerifier/` | `…/cpu/layout6/CpuFrilessVerifier.sol` | 32 |
| `Fri/` | `…/verifier/FriStatementContract.sol` | 9 |
| `Merkle/` | `…/verifier/MerkleStatementContract.sol` | 6 |
| `MemoryPage/` | `…/verifier/cpu/MemoryPageFactRegistry.sol` | 4 |
| `CpuOods/` | `…/cpu/layout6/CpuOods.sol` | 4 |
| `CpuConstraintPoly/` | `…/cpu/layout6/CpuConstraintPoly.sol` | 1 |
| `Bootloader/` | `…/verifier/cpu/CairoBootloaderProgram.sol` | 1 |
| `PedersenX/`, `PedersenY/` | `…/periodic_columns/PedersenHashPoints{X,Y}Column.sol` | 1 each |
| `EcdsaX/`, `EcdsaY/` | `…/periodic_columns/EcdsaPoints{X,Y}Column.sol` | 1 each |
| `PoseidonFR0/1/2/` | `…/cpu/layout6/PoseidonPoseidonFullRoundKey{0,1,2}Column.sol` | 1 each |
| `PoseidonPR0/1/` | `…/cpu/layout6/PoseidonPoseidonPartialRoundKey{0,1}Column.sol` | 1 each |

The 11 single-file contracts (`CpuConstraintPoly`, `Bootloader`, and the 9
periodic-column / round-key tables) are **precomputed constants** — CFV /
`StarkVerifier` take their addresses as constructor args and read from them;
they are not logic you would read.

### The 48 unique `.sol` files, by directory

**`starkware/solidity/components/`** — fact-registration base
`FactRegistry.sol`, `ReferableFactRegistry.sol`

**`starkware/solidity/interfaces/`**
`IFactRegistry.sol`, `IQueryableFactRegistry.sol`, `IPeriodicColumn.sol`, `IStarkVerifier.sol`, `Identity.sol`

**`starkware/solidity/libraries/`**
`Addresses.sol`

**`starkware/solidity/verifier/`** — core FRI + Merkle engine
`FriLayer.sol`, `FriStatementContract.sol`, `FriTransform.sol`, `HornerEvaluator.sol`, `IMerkleVerifier.sol`, `MerkleStatementContract.sol`, `MerkleStatementVerifier.sol`, `MerkleVerifier.sol`, `PrimeFieldElement0.sol`, `Prng.sol`, `VerifierChannel.sol`

**`starkware/solidity/verifier/cpu/`** — Cairo public-input / memory
`CairoBootloaderProgram.sol`, `CairoVerifierContract.sol`, `CpuPublicInputOffsetsBase.sol`, `MemoryPageFactRegistry.sol`, `PageInfo.sol`, `PublicMemoryOffsets.sol`

**`starkware/solidity/verifier/cpu/layout6/`** — the layout-6 STARK verifier itself
`StarkVerifier.sol`, `CpuVerifier.sol`, `CpuFrilessVerifier.sol`, `CpuConstraintPoly.sol`, `CpuOods.sol`, `Fri.sol`, `FriStatementVerifier.sol`, `LayoutSpecific.sol`, `MemoryAccessUtils.sol`, `MemoryMap.sol`, `CpuPublicInputOffsets.sol`, `StarkParameters.sol`, `PoseidonPoseidonFullRoundKey0Column.sol`, `PoseidonPoseidonFullRoundKey1Column.sol`, `PoseidonPoseidonFullRoundKey2Column.sol`, `PoseidonPoseidonPartialRoundKey0Column.sol`, `PoseidonPoseidonPartialRoundKey1Column.sol`

**`starkware/solidity/verifier/cpu/periodic_columns/`**
`EcdsaPointsXColumn.sol`, `EcdsaPointsYColumn.sol`, `PedersenHashPointsXColumn.sol`, `PedersenHashPointsYColumn.sol`

**`starkware/solidity/verifier/gps/`** — the GPS front door
`GpsStatementVerifier.sol`, `GpsOutputParser.sol`

### Our own contracts — the L1 identity gate (not vendored; in `contracts_solidity/src/`)

After the StarkWare suite proves the STARK valid, `convoy-submitter` calls **our**
gate, which is the entire trust surface we author:

- `src/Verifier.sol` — `registerSafeProof`; calls `starkVerifier.isValid(factHash)` on the deployed GPS, then the per-drone identity + strip-bounds gates
- `src/IStarkVerifier.sol` — the interface it calls the GPS through
- `src/Registry.sol` — supplies the `MissionSpec` the gate checks against

`CommandLog.sol` is **not** in the verification path (it is the advance-command log).

## Call flow — how the submitter's data becomes an accepted proof

`convoy-submitter` (`PROOF/submitter`) drives StarkWare's four phases against
this suite, then our identity gate:

1. **Trace Merkle commits** → `MerkleStatementContract.verifyMerkle()` — `src/Merkle/…`
2. **FRI layer commits** → `FriStatementContract.verifyFRI()` — `src/Fri/…`
3. **Public memory pages** → `MemoryPageFactRegistry.registerContinuousMemoryPage()` — `src/MemoryPage/…`
4. **GPS proof** → `GpsStatementVerifier.verifyProofAndRegister(proofParams, proof, taskMetadata, cairoAuxInput, cairoVerifierId = 6)` — `src/GpsStatementVerifier/…`
   - selects `cairoVerifierContractAddresses[6]` = `CpuFrilessVerifier`
   - `cairoVerifier.verifyProofExternal(...)` → `CpuFrilessVerifier` → `StarkVerifier`: consumes the Merkle + FRI + memory-page facts from phases 1-3, checks OODS (`CpuOods`), the AIR constraints (`CpuConstraintPoly` + the Pedersen / ECDSA / Poseidon periodic columns) and FRI folding (`Fri`) against the bootloader program (`CairoBootloaderProgram`)
   - `registerGpsFacts(...)` records the `(programHash, output)` fact

After phase 4, `convoy-submitter` calls **our** identity-gated
`Verifier.registerSafeProof` (`LAYER1/contracts_solidity/src/Verifier.sol` — not
part of this vendored suite), which requires the registered GPS fact and enforces
the per-drone identity gate before accepting the `safe_area` verdict. See
`CALLFLOW.md` (in this directory) for the full end-to-end path.

The `safe_area` predicate itself is compiled and proved **off-chain**
(`PROOF/prover-api`); this suite is only the on-chain checker that the STARK
proof of that predicate is valid.

## Relation to the rest of the repo

`src/` is the canonical readable source for the deployed verifier. 
Deploy uses the pre-built `bytecode/*.hex` via `deploy-stark-verifier.sh`, and this byte-verified `src/` is the sole readable source.
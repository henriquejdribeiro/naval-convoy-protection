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

`SIMULATOR/scripts/deploy-stark-verifier.sh` deploys the 15 stateless contracts,
then CFV, then GPS with `cairoVerifierContracts[6] = CFV`.

## Reproduce & verify

```bash
python3 extract-sources.py     # unpack Sourcify bundles -> src/
python3 verify-bytecode.py     # solc 0.6.12 recompile -> diff vs deployed bytecode
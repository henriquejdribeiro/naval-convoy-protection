# Pinned tool versions

> All versions below are taken from the **working `verifiable_grid` stack**
> (henriquejdribeiro/verifiable_grid, the parent thesis project). Every pin
> here has been validated end-to-end with Geth → Madara → Pathfinder →
> SNOS → Stone → on-chain `registerDroneProof`. Use these as the floor; do
> not bump until you have a reason and a test.

## Layer 1 — Settlement (Ethereum)

| Component | Version | Source |
|---|---|---|
| `ethereum/client-go` (Geth) | `v1.10.17` | `verifiable_grid/docker-compose.yml` |
| Solidity (foundry profile) | `0.8.33` | `verifiable_grid/contracts/solidity/madara-l1/foundry.toml` |
| EVM target | `paris` | same |
| Foundry image | `ghcr.io/foundry-rs/foundry:latest` | `verifiable_grid/infrastructure/deploy-l1/Dockerfile` |
| `solc` (legacy, for FactRegistry) | `0.6.12` | same |
| OpenZeppelin contracts | from npm via foundry remappings | `remappings.txt` |
| StarkWare verifier components | `starkex-contracts/evm-verifier` (FactRegistry, MemoryPageFactRegistry) | imported in `DroneProofVerifier.sol` |

Clique PoA configuration is per **EIP-225**. Six validator addresses (the six
ship keys) are baked into `genesis.json`.

## Layer 2 — Execution (Madara / Starknet)

| Component | Version | Source |
|---|---|---|
| Madara sequencer | `ghcr.io/madara-alliance/madara:nightly` | `verifiable_grid/docker-compose.yml` |
| Pathfinder (full node + JSON-RPC) | `eqlabs/pathfinder:v0.21.3` | same |
| Starknet protocol | `v0.14.1` | matches Pathfinder pin above |
| Cairo 1 (for L2 contracts) | `starknet >= 2.9.2`, edition `2024_07` | `verifiable_grid/contracts/cairo/Scarb.toml` |
| Scarb (Cairo package manager) | `2.9.2` (matches starknet dep) | `Scarb.lock` |
| Sierra | `1.6.0` (compiled output) | `verifiable_grid/contracts/cairo/src/lib.cairo` header |

> Note: Madara is pinned to `:nightly` rather than a numbered tag because
> the Madara alliance has not yet cut a stable release that supports the
> Starknet 0.14.1 protocol. This is a **known fragility**; pin to a specific
> digest (`docker pull ... && docker inspect`) once Phase 3 is stable.

## Proving — Cairo 0 / SNOS / Stone

| Component | Version / commit | Source |
|---|---|---|
| `keep-starknet-strange/snos` | `v0.14.1-alpha.0` (matches Starknet protocol) | `verifiable_grid/infrastructure/snos/Dockerfile`, line 32 |
| `cairo-lang` (Python pip, used by SNOS) | `0.14.1a0` | `verifiable_grid/infrastructure/snos/Dockerfile` |
| `cairo-lang` (Python pip, used by prover) | `0.14.0.1` | `verifiable_grid/infrastructure/prover-api/Dockerfile`, line 50 |
| `starkware-libs/stone-prover` | `main` (cloned `--depth 1`) | `prover-api/Dockerfile`, line 16 |
| Bazel (for stone build) | `5.4.1` | `prover-api/Dockerfile`, line 14 (`USE_BAZEL_VERSION`) |
| `Moonsong-Labs/stone-prover-cli` | `main` (cloned `--depth 1`) | `prover-api/Dockerfile`, line 27 |
| `stark-evm-adapter` | unmodified, `main` | `prover-api/Dockerfile` |
| Cairo bootloader (Rust crate) | bundled with stone-prover-cli | same |
| Madara orchestrator (Rust) | based on `madara-alliance/madara` orchestrator | `verifiable_grid/infrastructure/orchestrator/Dockerfile` |

## Build toolchains

| Component | Version |
|---|---|
| Rust (orchestrator + adapter) | `rust:1.89-bookworm` |
| Rust (stone-prover-cli) | `rust:1.81-bookworm` |
| Python (SNOS runtime) | `python3` on `ubuntu:22.04` |
| Python (Stone build) | `ciimage/python:3.9` |
| Runtime base for stone | `debian:bookworm-slim` |

## Supporting services

| Component | Version |
|---|---|
| MongoDB (orchestrator job state) | `mongo:7` |
| LocalStack (S3-compatible blob store for proofs) | `localstack/localstack:3` (Python 3.11) |
| Docker Compose | `2.24+` |
| WSL 2 (on Windows hosts) | Ubuntu 22.04 |

## Hardware / Phase 4

| Component | Version |
|---|---|
| ArduPilot SITL | `stable-4.5` (planned — not yet pinned in verifiable_grid) |
| Linux network emulation | `tc` / `netem` from kernel ≥ 5.15 |

## Why these exact pins

1. **Geth `v1.10.17`** — predates the Geth 1.11 PoS migration, keeps Clique PoA as a first-class consensus engine without `pos-merge` quirks.
2. **Pathfinder `v0.21.3` ↔ SNOS `v0.14.1-alpha.0` ↔ `cairo-lang 0.14.1a0`** — all aligned on **Starknet protocol v0.14.1**. Mismatching protocol versions across these three components is the single most common source of "block fails to sync" errors.
3. **`cairo-lang 0.14.0.1`** in the prover (vs. `0.14.1a0` in SNOS) — yes, deliberately different, because `cairo_run --proof_mode` in the prover image pins to the official 0.14.0.1 tag whereas SNOS needs the 0.14.1-alpha matching its protocol target.
4. **Bazel `5.4.1`** is the version stone-prover's `WORKSPACE` was tested against — newer Bazel breaks rule_python.
5. **Solidity `0.8.33`, EVM target `paris`** — the highest stable solc that compiles StarkWare's FactRegistry without modification, on an EVM rev that Geth 1.10 supports.

## Update policy

When something here gets bumped:
1. Run the `verifiable_grid` end-to-end smoke test against the new pin first.
2. Bump in lockstep with any aligned components (e.g. SNOS + Pathfinder + cairo-lang together when Starknet protocol moves).
3. Record the change in this file with a one-line rationale.

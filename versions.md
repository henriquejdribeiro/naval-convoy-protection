# Pinned tool versions

> Working baseline of the toolchain. These are the versions Phase 2 and
> Phase 3 will be built against. Each pin is **validated as the stack
> matures** — when something here gets bumped, the rationale and the
> validation result land below.

## Layer 1 — Settlement (Ethereum)

| Component | Version |
|---|---|
| `ethereum/client-go` (Geth) | `v1.10.17` |
| Solidity (foundry profile) | `0.8.33` |
| EVM target | `paris` |
| Foundry image | `ghcr.io/foundry-rs/foundry:latest` |
| `solc` (legacy, for FactRegistry) | `0.6.12` |
| OpenZeppelin Contracts | latest stable (via npm + foundry remappings) |
| StarkWare verifier components | [`starkware-libs/starkex-contracts`](https://github.com/starkware-libs/starkex-contracts) — `evm-verifier/FactRegistry`, `MemoryPageFactRegistry` |

Clique PoA configuration is per **EIP-225**. Six validator addresses (the six
ship keys) are baked into `genesis.json`.

## Layer 2 — Execution (Madara / Starknet)

| Component | Version |
|---|---|
| Madara sequencer | `ghcr.io/madara-alliance/madara:nightly` |
| Pathfinder (full node + JSON-RPC) | `eqlabs/pathfinder:v0.21.3` |
| Starknet protocol | `v0.14.1` (matches the Pathfinder pin) |
| Cairo 1 (for L2 contracts) | `starknet >= 2.9.2`, edition `2024_07` |
| Scarb (Cairo package manager) | `2.9.2` (matches the `starknet` dep) |
| Sierra (compiled output) | `1.6.0` |

> **Madara `:nightly` is a known fragility.** The Madara alliance has not yet
> cut a stable release that supports the Starknet 0.14.1 protocol. We pin to
> a specific image digest (`docker inspect`) once Phase 3 is reproducibly
> green; until then, every fresh build pulls whatever `:nightly` is current.

## Proving — Cairo 0 / SNOS / Stone

| Component | Version / commit |
|---|---|
| `keep-starknet-strange/snos` | `v0.14.1-alpha.0` (matches Starknet protocol) |
| `cairo-lang` (Python pip, used by SNOS) | `0.14.1a0` |
| `cairo-lang` (Python pip, used by prover) | `0.14.0.1` |
| `starkware-libs/stone-prover` | `main` (cloned `--depth 1`) |
| Bazel (used by stone-prover's `WORKSPACE`) | `5.4.1` |
| `Moonsong-Labs/stone-prover-cli` | `main` (cloned `--depth 1`) |
| `stark-evm-adapter` (StarkWare) | unmodified, `main` |
| Cairo bootloader (Rust crate) | bundled with `stone-prover-cli` |
| Madara orchestrator (Rust) | derived from `madara-alliance/madara` orchestrator |

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
| ArduPilot SITL | `stable-4.5` (planned — not yet pinned) |
| Linux network emulation | `tc` / `netem` from kernel ≥ 5.15 |

## Why these exact pins

1. **Geth `v1.10.17`** — predates the Geth 1.11 PoS migration, keeps Clique PoA as a first-class consensus engine without `pos-merge` quirks.
2. **Pathfinder `v0.21.3` ↔ SNOS `v0.14.1-alpha.0` ↔ `cairo-lang 0.14.1a0`** — all aligned on **Starknet protocol v0.14.1**. Mismatching protocol versions across these three components is the single most common source of "block fails to sync" errors.
3. **`cairo-lang 0.14.0.1` in the prover (vs. `0.14.1a0` in SNOS)** — deliberately different. `cairo_run --proof_mode` is on the official 0.14.0.1 release; SNOS needs the 0.14.1-alpha to match its protocol target.
4. **Bazel `5.4.1`** is the version `stone-prover`'s `WORKSPACE` was tested against — newer Bazel breaks `rule_python`.
5. **Solidity `0.8.33`, EVM target `paris`** — the highest stable solc that compiles StarkWare's `FactRegistry` without modification, on an EVM revision that Geth 1.10 supports.

## Update policy

When something here gets bumped:
1. Run the Phase 3 smoke test (`mission-replay.json`-producing run) against the new pin first.
2. Bump in lockstep with any aligned components (e.g. SNOS + Pathfinder + `cairo-lang` together when the Starknet protocol moves).
3. Record the change in this file with a one-line rationale and the date.

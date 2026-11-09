# stone-cli — vendored proving-CLI source

This directory vendors the complete, unmodified source of zksecurity's stone-cli,
the Rust command-line tool that orchestrates proving in our pipeline
(PROOF/prover-api/entrypoint.sh): it wraps the Cairo PIE in the simple bootloader,
runs the Stone prover, verifies off-chain, and serialize-proof into evm_proof.json
for Layer-1 submission.

- Built in: PROOF/prover-api/Dockerfile (stage stone-cli-builder; cargo install --locked --git ... --tag v0.2.0)
- Source:   https://github.com/zksecurity/stone-cli
- Tag:      v0.2.0
- Commit:   0fdfeb6c363e31dc88904d874a267f2952851414
- Language: Rust
- License:  see stone-cli-src/LICENSE

stone-cli does NOT bundle StarkWare's Stone prover C++ source. Its build.rs
downloads prebuilt, SHA-256-pinned cpu_air_prover / cpu_air_verifier binaries from
dipdup-io/stone-packaging at build time. The readable Stone math source is vendored
separately at PROOF/stone; this CLI is the orchestration and Ethereum
proof-serialization layer on top of it. The upstream tree is unchanged.

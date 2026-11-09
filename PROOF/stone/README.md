# Stone prover — vendored proving-layer source

This directory vendors the **complete, unmodified** source of the STARK prover
our proving layer runs: StarkWare's Stone (`cpu_air_prover` / `cpu_air_verifier`).

- Built in: `PROOF/prover-api/Dockerfile` (stage `stone-builder`, Bazel)
- Source:   https://github.com/starkware-libs/stone-prover
- Commit:   1414a545e4fb38a85391289abe91dd4467d268e1
- Language: C++ (Bazel build)
- License:  Apache-2.0 (see `stone-src/LICENSE`)

The Dockerfile builds `cpu_air_prover` and `cpu_air_verifier` from this exact
commit; only those two binaries are copied into the runtime image. This source is
included verbatim so the C++ behind the proofs can be read and the work
reproduced independently of upstream. The upstream tree is unchanged. Stone's own
dependencies are fetched by Bazel at build time (`http_archive` in `WORKSPACE`),
not vendored here.

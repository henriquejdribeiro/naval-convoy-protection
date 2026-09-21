# =============================================================================
# Phase 3 prover-api — bootloader-wrapped Stone STARK proof for
# safe_area_verify.cairo, end-to-end through StarkWare's GpsStatementVerifier.
#
# Self-contained build — NO external prebuilt base:
#   Stage 0 (stone-builder): cpu_air_prover/verifier from starkware-libs/stone-prover (Bazel)
#   stone-cli-builder:        zksecurity/stone-cli v0.2.0
#   convoy-submitter-builder: this repo's submitter (+ vendored zksecurity/stark-evm-adapter)
#   final (ubuntu:22.04):     cairo-lang 0.14.0.1 (pip) + the above binaries + convoy app/scripts
#
# Build context MUST be the repo root (COPY reads PROOF/…). Compose sets context: .
# =============================================================================

# ─── Stage 0: Stone prover binaries from StarkWare source (unmodified) ────────
# cpu_air_prover / cpu_air_verifier, built from starkware-libs/stone-prover in
# StarkWare's CI image. Only the compiled binaries are copied into the runtime —
# this stage does not ship. Replaces the prebuilt vg-prover-api base so the whole
# image builds from auditable upstream sources.
FROM ciimage/python:3.9 AS stone-builder
RUN apt-get update && apt-get install -y git wget && rm -rf /var/lib/apt/lists/*
RUN wget -q https://github.com/bazelbuild/bazelisk/releases/download/v1.19.0/bazelisk-linux-amd64 \
        -O /usr/local/bin/bazel && chmod +x /usr/local/bin/bazel
ENV USE_BAZEL_VERSION=5.4.1
WORKDIR /app
RUN git clone https://github.com/starkware-libs/stone-prover.git .
RUN bash install_deps.sh
RUN bazel build //...

# ─── Stage 1c: build zksecurity's stone-cli (canonical user-facing CLI) ─────
# Replaces our custom convoy-bootloader-cli with zksecurity's official
# `stone-cli prove-bootloader` command — the canonical zksecurity tool
# that internally wraps a task Cairo program with the simple bootloader
# and runs cpu_air_prover. No custom wrapping code, just StarkWare's
# documented user-facing CLI.
FROM rust:1.88-bookworm AS stone-cli-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
        pkg-config libssl-dev git ca-certificates && \
    rm -rf /var/lib/apt/lists/*
RUN cargo install --locked --git https://github.com/zksecurity/stone-cli --tag v0.2.0 stone-cli && \
    mv /usr/local/cargo/bin/stone-cli /usr/local/bin/stone-cli && \
    stone-cli --help > /dev/null

# ─── Stage 1b: build convoy-submitter (phases 1-4a + registerSafeProof) ──────
# Single Rust tool that runs the four StarkWare phases AND the identity-gated
# Verifier.registerSafeProof (replaces the the earlier submitters.
# Uses stark_evm_adapter (vendored). Addresses come from env at runtime.
FROM rust:1.88-bookworm AS convoy-submitter-builder

WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends \
        pkg-config libssl-dev && \
    rm -rf /var/lib/apt/lists/*

COPY PROOF/vendor/stark-evm-adapter/  /build/PROOF/vendor/stark-evm-adapter/
COPY PROOF/submitter/  /build/PROOF/submitter/

WORKDIR /build/PROOF/submitter
RUN cargo build --release
RUN cp target/release/convoy-submitter /usr/local/bin/convoy-submitter
RUN ls -la /usr/local/bin/convoy-submitter

# ─── Stage 2: the prover-api runtime image (self-built, no external base) ──────
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Runtime deps + official cairo-lang 0.14.0.1: provides cairo-compile, cairo-run,
# and the Python crypto (pedersen_hash, sign, private_to_stark_key) that
# sign_telemetry.py and the Cairo verify stdlib rely on.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-dev \
        libgmp-dev libgmp10 libdw1 \
        curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install --no-cache-dir cairo-lang==0.14.0.1 fastecdsa sympy

# Stone binaries (unmodified C++) + the libs they link against.
COPY --from=stone-builder /app/build/bazelbin/src/starkware/main/cpu/cpu_air_prover   /usr/local/bin/
COPY --from=stone-builder /app/build/bazelbin/src/starkware/main/cpu/cpu_air_verifier /usr/local/bin/
COPY --from=stone-builder /usr/lib/x86_64-linux-gnu/libdw*  /usr/lib/x86_64-linux-gnu/
COPY --from=stone-builder /usr/lib/x86_64-linux-gnu/libelf* /usr/lib/x86_64-linux-gnu/
COPY --from=stone-builder /usr/lib/x86_64-linux-gnu/libgmp* /usr/lib/x86_64-linux-gnu/
# Non-fatal sanity check: confirm the binaries load and their shared libs
# resolve. These StarkWare CLIs exit non-zero on --help (gflags), so we do NOT
# gate the build on exit code — real verification is the proving pipeline.
RUN echo "=== ldd cpu_air_prover ===";   ldd /usr/local/bin/cpu_air_prover   || true; \
    echo "=== ldd cpu_air_verifier ==="; ldd /usr/local/bin/cpu_air_verifier || true; \
    echo "=== cpu_air_prover --help ==="; cpu_air_prover --help 2>&1 | head -5 || true; \
    echo "=== cpu_air_verifier --help ==="; cpu_air_verifier --help 2>&1 | head -5 || true

# Foundry's `cast` — L1 convenience CLI. The proof-submission path goes through
# convoy-submitter (Rust); cast is not on the critical path.
RUN curl -L https://foundry.paradigm.xyz | bash || true
ENV PATH="/root/.foundry/bin:${PATH}"
RUN /root/.foundry/bin/foundryup -i stable && \
    /root/.foundry/bin/cast --version

# eth-utils for keccak256 in the submit script (sha3 fallback)
RUN pip3 install --no-cache-dir eth-utils

# Pull stone-cli (zksecurity's canonical user-facing CLI) in from its
# build stage. Used in entrypoint.sh's Step 2 to take our task Cairo
# program + program_input and produce a Stone-prover proof wrapped in
# the simple bootloader — exactly what GpsStatementVerifier expects.
COPY --from=stone-cli-builder /usr/local/bin/stone-cli /usr/local/bin/stone-cli

# Pull convoy-submitter (phases 1-4b in one tool) from its build stage.
COPY --from=convoy-submitter-builder /usr/local/bin/convoy-submitter /usr/local/bin/convoy-submitter

# Install the naval-convoy program + scripts + entrypoint
WORKDIR /app
COPY PROOF/prover-api/safe_area_verify_alpha.cairo /app/safe_area_verify_alpha.cairo
COPY PROOF/prover-api/safe_area_verify_bravo.cairo /app/safe_area_verify_bravo.cairo
COPY PROOF/prover-api/fetch_l2_swarm.py      /app/fetch_l2_swarm.py
COPY PROOF/prover-api/entrypoint.sh          /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Starkli — used by fetch_l2_cells.py to query convoy_protocol via Pathfinder.
RUN curl https://get.starkli.sh | sh || true
ENV PATH="/root/.starkli/bin:${PATH}"
RUN /bin/bash -c "source /root/.starkli/env 2>/dev/null && starkliup -v 0.4.0" || \
    echo "[warn] starkliup install failed (non-fatal — used only by fetch_l2_cells.py)"

RUN mkdir -p /proofs

ENTRYPOINT ["/app/entrypoint.sh"]

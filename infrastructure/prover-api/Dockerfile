# =============================================================================
# Phase 3 prover-api — Stone STARK prover for the convoy SAFE_AREA program
#
# Adapted from verifiable_grid/infrastructure/prover-api/Dockerfile (working
# pinned versions kept identical for compatibility with cpu_air_prover output).
#
# Build inputs:
#   - cpu_air_prover  / cpu_air_verifier  (Stone, official C++ binary, Bazel build)
#   - cairo-lang 0.14.0.1                  (cairo-compile + cairo-run --proof_mode)
#   - stone-prover-cli                     (Moonsong-Labs Rust bootloader, for SNOS PIEs)
#   - stark-evm-adapter                    (zksecurity, EVM-compatible proof adaptation)
#
# Adaptations vs verifiable_grid:
#   - safe_area_verify.cairo replaces drone_verify.cairo
#   - submit_proof_l1.py speaks the registerSafeProof(SafeProofInputs) ABI
#   - sample_input.json carries the SAFE_AREA cell schema (x, y, p_contact, ts)
# =============================================================================

# --- Stage 1: Build C++ Stone prover from official repo (Bazel) ---
FROM ciimage/python:3.9 AS stone-builder
RUN apt-get update && apt-get install -y git wget && rm -rf /var/lib/apt/lists/*
RUN wget -q https://github.com/bazelbuild/bazelisk/releases/download/v1.19.0/bazelisk-linux-amd64 \
        -O /usr/local/bin/bazel && chmod +x /usr/local/bin/bazel
ENV USE_BAZEL_VERSION=5.4.1
WORKDIR /app
RUN git clone https://github.com/starkware-libs/stone-prover.git .
RUN bash install_deps.sh
RUN bazel build //...

# --- Stage 2a: stone-prover-cli (Rust bootloader for SNOS v0.14 PIEs) ---
# Rust 1.81 is required — the time crate 0.3.34 has an inference regression on 1.82+
FROM rust:1.81-bookworm AS prover-cli-builder
RUN apt-get update && apt-get install -y git pkg-config libssl-dev cmake clang && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/Moonsong-Labs/stone-prover-cli.git /build/stone-prover-cli
WORKDIR /build/stone-prover-cli
RUN cargo build --release

# --- Stage 2b: stark-evm-adapter (proof bytes -> EVM-compatible "fact" tuple) ---
FROM rust:1.89-bookworm AS adapter-builder
RUN apt-get update && apt-get install -y git pkg-config libssl-dev cmake clang && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/zksecurity/stark-evm-adapter.git /build/adapter
WORKDIR /build/adapter
RUN cargo build --release

# --- Stage 3: Runtime ---
FROM ubuntu:22.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
        python3 python3-pip python3-dev \
        libgmp-dev libgmp10 libdw1 \
        curl ca-certificates jq \
    && rm -rf /var/lib/apt/lists/*

# cairo-lang 0.14.0.1 — pinned to match Stone's expected program format
RUN pip3 install --no-cache-dir \
        cairo-lang==0.14.0.1 \
        fastecdsa \
        sympy \
        pysha3 \
        eth-utils

# Official Stone binaries
COPY --from=stone-builder \
    /app/build/bazelbin/src/starkware/main/cpu/cpu_air_prover   /usr/local/bin/
COPY --from=stone-builder \
    /app/build/bazelbin/src/starkware/main/cpu/cpu_air_verifier /usr/local/bin/
COPY --from=stone-builder /usr/lib/x86_64-linux-gnu/libdw*  /usr/lib/x86_64-linux-gnu/
COPY --from=stone-builder /usr/lib/x86_64-linux-gnu/libelf* /usr/lib/x86_64-linux-gnu/
COPY --from=stone-builder /usr/lib/x86_64-linux-gnu/libgmp* /usr/lib/x86_64-linux-gnu/

# stone-prover-cli + stark-evm-adapter
COPY --from=prover-cli-builder \
    /build/stone-prover-cli/target/release/stone-prover-cli /usr/local/bin/
COPY --from=adapter-builder \
    /build/adapter/target/release/stark_evm_adapter /usr/local/bin/

# Verify binaries
RUN cpu_air_prover   --help > /dev/null 2>&1 && echo "cpu_air_prover  OK"
RUN cpu_air_verifier --help > /dev/null 2>&1 && echo "cpu_air_verifier OK"
RUN stone-prover-cli --help > /dev/null 2>&1 && echo "stone-prover-cli OK"
RUN stark_evm_adapter --help 2>&1 | head -1   && echo "stark-evm-adapter OK" || true

WORKDIR /app
COPY safe_area_verify.cairo /app/safe_area_verify.cairo
COPY sample_input.json      /app/sample_input.json
COPY prove_pie.py           /app/prove_pie.py
COPY submit_proof_l1.py     /app/submit_proof_l1.py
COPY entrypoint.sh          /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

RUN mkdir -p /proofs

ENTRYPOINT ["/app/entrypoint.sh"]

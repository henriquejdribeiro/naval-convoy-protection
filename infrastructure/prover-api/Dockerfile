# =============================================================================
# Phase 3.a prover-api — Stone STARK prover for safe_area_verify.cairo
#
# Adapted from verifiable_grid/infrastructure/prover-api with stone-prover-cli
# DROPPED (it pinned Rust 1.81 which hits a `time` crate ICE on current
# nightly registry resolutions). stone-prover-cli is only needed for SNOS-
# emitted PIEs (Phase 3.b); the direct cairo-run path used here lets
# cpu_air_prover consume the trace + memory + public_input files directly.
#
# Build stages:
#   1. stone-builder    cpu_air_prover / cpu_air_verifier (Bazel + ciimage/python)
#   2. adapter-builder  stark_evm_adapter (Rust 1.89, works without patches)
#   3. runtime          Ubuntu 22.04 + cairo-lang 0.14.0.1 (pip) + the binaries
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

# --- Stage 2: stark-evm-adapter (proof bytes -> EVM-compatible "fact" tuple) ---
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

# Foundry's cast — used by submit_proof_l1.py to send the L1 tx
RUN curl -L https://foundry.paradigm.xyz | bash || true
ENV PATH="/root/.foundry/bin:${PATH}"
RUN /root/.foundry/bin/foundryup -i stable && \
    /root/.foundry/bin/cast --version

# Official Stone binaries
COPY --from=stone-builder \
    /app/build/bazelbin/src/starkware/main/cpu/cpu_air_prover   /usr/local/bin/
COPY --from=stone-builder \
    /app/build/bazelbin/src/starkware/main/cpu/cpu_air_verifier /usr/local/bin/
COPY --from=stone-builder /usr/lib/x86_64-linux-gnu/libdw*  /usr/lib/x86_64-linux-gnu/
COPY --from=stone-builder /usr/lib/x86_64-linux-gnu/libelf* /usr/lib/x86_64-linux-gnu/
COPY --from=stone-builder /usr/lib/x86_64-linux-gnu/libgmp* /usr/lib/x86_64-linux-gnu/

# stark-evm-adapter
COPY --from=adapter-builder \
    /build/adapter/target/release/stark_evm_adapter /usr/local/bin/

# Verify binaries
RUN cpu_air_prover    --help > /dev/null 2>&1 && echo "cpu_air_prover    OK"
RUN cpu_air_verifier  --help > /dev/null 2>&1 && echo "cpu_air_verifier  OK"
RUN stark_evm_adapter --help 2>&1 | head -1   && echo "stark_evm_adapter OK" || true
RUN cast --version > /dev/null 2>&1 && echo "cast              OK"

WORKDIR /app
COPY safe_area_verify.cairo /app/safe_area_verify.cairo
COPY sample_input.json      /app/sample_input.json
COPY prove_pie.py           /app/prove_pie.py
COPY submit_proof_l1.py     /app/submit_proof_l1.py
COPY entrypoint.sh          /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

RUN mkdir -p /proofs

ENTRYPOINT ["/app/entrypoint.sh"]

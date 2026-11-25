# =============================================================================
# Phase 3 prover-api — bootloader-wrapped Stone STARK proof for
# safe_area_verify.cairo, end-to-end through StarkWare's GpsStatementVerifier.
#
# Self-contained build — NO external prebuilt base:
#   stone-cli-builder:        zksecurity/stone-cli v0.2.0
#   convoy-submitter-builder: this repo's submitter (+ vendored zksecurity/stark-evm-adapter)
#   final (ubuntu:22.04):     cairo-lang 0.14.0.1 (pip) + the above binaries + convoy app/scripts
#
# Build context MUST be the repo root (COPY reads PROOF/…). Compose sets context: .
# =============================================================================

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
RUN cargo build --release --offline
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
        libgmp-dev libgmp10 libdw1 libelf1\
        curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install --no-cache-dir cairo-lang==0.14.0.1 fastecdsa sympy

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
COPY PROOF/prover-api/compute_area_hash.py   /app/compute_area_hash.py
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

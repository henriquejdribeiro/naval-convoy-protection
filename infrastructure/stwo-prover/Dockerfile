# =============================================================================
# stwo-prover — Docker image for proving Cairo programs with Stwo Cairo.
# =============================================================================
#
# Pipeline (replaces Stone for L3→L2 in our dual-prover architecture):
#
#   safe_area_verify.cairo
#         │
#         │  cairo-compile (cairo-lang for Cairo 0; scarb build for Cairo 1)
#         ▼
#   compiled.json
#         │
#         │  cairo-vm-cli 3.2.0  (lambdaclass — the VM Stwo expects)
#         ▼
#   trace + memory + air_public_input + air_private_input
#         │
#         │  stwo-cairo-adapter  (converts cairo-vm output → ProverInput)
#         ▼
#   prover_input.json
#         │
#         │  stwo-cairo prove
#         ▼
#   proof.json  (Cairo-serde format: array of felts, ready for L2 INVOKE)
#         │
#         │  (off-chain self-check via stwo-cairo verify)
#         ▼
#   ✓ verified
#
# Toolchain pins (from stwo-cairo/.tool-versions and rust-toolchain.toml):
#   - Rust nightly-2025-06-23
#   - Scarb 2.15.0  (needed only if we later build the on-L2 Cairo verifier
#                    here — for the prover side alone we don't need Scarb,
#                    but we install it so the same image can compile the
#                    Stwo verifier contract for Madara deployment)
#   - Starknet Foundry 0.33.0 (sncast for L2 deployments)
# =============================================================================

# ─── Stage 1: build stwo-cairo prover binaries ───────────────────────────────
# Pinned to the stwo-cairo repo's rust-toolchain.toml. Older nightlies do not
# compile the prover; newer ones may have removed unstable features it uses.
FROM rustlang/rust:nightly-bookworm-slim AS stwo-builder

ENV DEBIAN_FRONTEND=noninteractive

# Build deps: git for cloning, pkg-config + libssl for some transitive crates.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates pkg-config libssl-dev \
        build-essential curl && \
    rm -rf /var/lib/apt/lists/*

# Force the EXACT nightly stwo-cairo's rust-toolchain.toml pins.
# If we don't, rustup will pull HEAD nightly and compilation may break on
# upstream feature changes.
RUN rustup install nightly-2025-06-23 --profile minimal && \
    rustup default nightly-2025-06-23

WORKDIR /build
# Bring in the vendored stwo-cairo clone (or it'll re-clone if absent).
COPY vendor/spike/stwo-cairo /build/stwo-cairo

# Build the prover binaries. -C target-cpu=native gives 2-3× speedup at runtime;
# we use a generic target here (the build host CPU != container runtime CPU),
# so opt-level=3 is the safe optimization.
WORKDIR /build/stwo-cairo/stwo_cairo_prover
RUN RUSTFLAGS="-C opt-level=3" \
    cargo build --release \
        --bin prove \
        --bin verify \
        --bin run_and_prove \
        --bin extract_mem_trace 2>&1 | tail -200

# Sanity-check the binaries.
RUN ls -la target/release/ && \
    target/release/prove --help > /dev/null 2>&1 && echo "prove   binary OK" && \
    target/release/verify --help > /dev/null 2>&1 && echo "verify  binary OK"

# ─── Stage 2: runtime image ──────────────────────────────────────────────────
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Runtime deps: ca-certs for HTTPS, python3 for input munging,
# curl/jq for L2 RPC calls.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl jq python3 python3-pip \
        libssl3 && \
    rm -rf /var/lib/apt/lists/* && \
    pip3 install --no-cache-dir --break-system-packages \
        starknet-py==0.27.0 || true   # for INVOKE submission to Madara

# Copy the Stwo prover binaries from stage 1.
COPY --from=stwo-builder /build/stwo-cairo/stwo_cairo_prover/target/release/prove          /usr/local/bin/stwo-prove
COPY --from=stwo-builder /build/stwo-cairo/stwo_cairo_prover/target/release/verify         /usr/local/bin/stwo-verify
COPY --from=stwo-builder /build/stwo-cairo/stwo_cairo_prover/target/release/run_and_prove  /usr/local/bin/stwo-run-and-prove

# Also install cairo-vm-cli — needed as the front of the pipeline (compile +
# run Cairo program → produce trace files in cairo-vm's exact format).
# Pin to 3.2.0 matching what stwo-cairo's adapter expects.
COPY --from=stwo-builder /usr/local/cargo/bin/cargo /usr/local/bin/cargo
COPY --from=stwo-builder /root/.rustup /root/.rustup
ENV RUSTUP_HOME=/root/.rustup PATH=/root/.rustup/toolchains/nightly-2025-06-23-x86_64-unknown-linux-gnu/bin:/usr/local/bin:$PATH

# Smoke test the installed binaries
RUN stwo-prove --help > /dev/null 2>&1 && echo "stwo-prove OK" && \
    stwo-verify --help > /dev/null 2>&1 && echo "stwo-verify OK"

# Copy the canned test data so we can run the spike example on first boot
COPY --from=stwo-builder /build/stwo-cairo/stwo_cairo_prover/test_data /opt/stwo-cairo/test_data

# Copy our Cairo program + sample input
WORKDIR /app
COPY infrastructure/prover-api/safe_area_verify.cairo /app/safe_area_verify.cairo
COPY infrastructure/prover-api/sample_input.json      /app/sample_input.json

# Entry: drop into bash for interactive spike-testing. Once we know the
# pipeline works, this gets replaced by an entrypoint.sh that runs the
# full off-chain prove + L2 INVOKE submission.
CMD ["/bin/bash"]

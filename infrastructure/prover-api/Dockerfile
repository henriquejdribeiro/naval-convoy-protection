# =============================================================================
# Phase 3 prover-api — bootloader-wrapped Stone STARK proof for
# safe_area_verify.cairo, end-to-end through StarkWare's GpsStatementVerifier.
#
# Multi-stage build:
#
#   Stage 1 (rust-builder): compiles convoy-bootloader-cli, which wraps
#       Moonsong-Labs/cairo-bootloader as a CLI that produces Stone-compatible
#       trace + memory + public_input + private_input + fact_topologies for a
#       given Cairo task. This replaces the raw `cairo-run` step in
#       entrypoint.sh so the produced proof has the bootloader envelope
#       GpsStatementVerifier expects.
#
#   Stage 2 (final): based on vg-prover-api-patched (which already has
#       cpu_air_prover, cpu_air_verifier, stark_evm_adapter, cairo-lang
#       0.14.0.1). Adds:
#         - convoy-bootloader-cli  (from Stage 1)
#         - foundry's `cast` (for legacy submit_proof_l1.py path)
#         - the convoy program + scripts + entrypoint
#
# Build context MUST be the repo root so Stage 1 can reach
# infrastructure/bootloader-cli/ and vendor/cairo-bootloader/. The compose
# file (docker-compose.l2.yml) sets `context: .` accordingly.
# =============================================================================

# ─── Stage 1: build the bootloader CLI ───────────────────────────────────────
# Rust 1.86 is the sweet spot:
#   - Has the `edition2024` Cargo feature (added in 1.85), required by
#     base64ct via the starknet-crypto dependency chain.
#   - Does NOT yet have the inherent `is_multiple_of` method (added in 1.87),
#     whose signature conflict breaks cairo-vm @ rev 05352b1c at compile time.
# The latest `time` and `base64ct` are too new for 1.86's MSRV, so we
# force-downgrade them via `cargo update --precise` before `cargo build`.
FROM rust:1.86-bookworm AS rust-builder

WORKDIR /build

# Bring in everything the bootloader-cli needs to compile. cairo-bootloader
# is a path dependency under vendor/, and cairo-vm is fetched by Cargo from
# git at build time (no network required at runtime).
COPY vendor/cairo-bootloader/          /build/vendor/cairo-bootloader/
COPY infrastructure/bootloader-cli/    /build/infrastructure/bootloader-cli/

WORKDIR /build/infrastructure/bootloader-cli
# First a `cargo generate-lockfile` (via `cargo update`) so we have a
# Cargo.lock to constrain. Then force-downgrade the two problematic crates
# whose latest versions require Rust >= 1.88. The pinned versions are
# known-compatible with Rust 1.86 and with the rest of the dependency tree.
RUN cargo generate-lockfile && \
    cargo update -p time      --precise 0.3.36 && \
    cargo update -p base64ct  --precise 1.6.0
RUN cargo build --release --locked && \
    cp target/release/convoy-bootloader-cli /usr/local/bin/convoy-bootloader-cli && \
    /usr/local/bin/convoy-bootloader-cli --help > /dev/null

# ─── Stage 2: the prover-api runtime image ───────────────────────────────────
FROM vg-prover-api-patched:latest

ENV DEBIAN_FRONTEND=noninteractive

# Foundry's `cast` — used by the legacy submit_proof_l1.py path against the
# mock verifier. The real-verifier path goes through convoy-submitter (Rust)
# and is built separately.
RUN curl -L https://foundry.paradigm.xyz | bash || true
ENV PATH="/root/.foundry/bin:${PATH}"
RUN /root/.foundry/bin/foundryup -i stable && \
    /root/.foundry/bin/cast --version

# eth-utils for keccak256 in the submit script (sha3 fallback)
RUN pip3 install --no-cache-dir eth-utils

# Pull the bootloader CLI in from the rust-builder stage.
COPY --from=rust-builder /usr/local/bin/convoy-bootloader-cli /usr/local/bin/convoy-bootloader-cli

# Replace the verifiable_grid program/entrypoint with our naval-convoy ones
WORKDIR /app
COPY infrastructure/prover-api/safe_area_verify.cairo /app/safe_area_verify.cairo
COPY infrastructure/prover-api/sample_input.json      /app/sample_input.json
COPY infrastructure/prover-api/prove_pie.py           /app/prove_pie.py
COPY infrastructure/prover-api/submit_proof_l1.py     /app/submit_proof_l1.py
COPY infrastructure/prover-api/fetch_l2_cells.py      /app/fetch_l2_cells.py
COPY infrastructure/prover-api/entrypoint.sh          /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Starkli — used by fetch_l2_cells.py to query convoy_protocol via Pathfinder.
RUN curl https://get.starkli.sh | sh
ENV PATH="/root/.starkli/bin:${PATH}"
RUN /bin/bash -c "source /root/.starkli/env && starkliup -v 0.4.0"

RUN mkdir -p /proofs

ENTRYPOINT ["/app/entrypoint.sh"]

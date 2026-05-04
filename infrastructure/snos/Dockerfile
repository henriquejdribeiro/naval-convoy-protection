# =============================================================================
# infrastructure/snos/Dockerfile — StarkNet OS for replaying L2 blocks
#
# Adapted from verifiable_grid/infrastructure/snos/Dockerfile. Phase 3.b
# wires this in once Madara + Pathfinder are running. Until then the
# image isn't built (the docker-compose.l2.yml service is gated by the
# `proving` profile).
#
# Pinned to v0.14.1-alpha.0 to match Madara 0.14.1 protocol target.
# patch_snos_txhash.py skips an over-strict tx-hash assertion that fails
# on Madara devnet's tweaked block headers — verifiable_grid hit and
# fixed this; we keep their patch verbatim.
# =============================================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
        curl git build-essential pkg-config \
        libssl-dev libgmp-dev \
        python3 python3-venv python3-pip python3-dev \
        ca-certificates wget rclone \
    && rm -rf /var/lib/apt/lists/*

# Rust toolchain (>=1.76)
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

# Clone SNOS at v0.14.1-alpha.0 — matches Madara 0.14.1 protocol
RUN git clone https://github.com/keep-starknet-strange/snos.git --recursive
WORKDIR /app/snos
RUN git checkout v0.14.1-alpha.0

# Patch over-strict tx-hash assertions for Madara devnet compatibility
COPY patch_snos_txhash.py /tmp/patch_snos_txhash.py
RUN cargo fetch 2>/dev/null || true && \
    python3 /tmp/patch_snos_txhash.py && \
    echo "[+] SNOS tx-hash patch applied"

# Cairo dependencies
RUN python3 -m venv .venv && \
    . .venv/bin/activate && \
    chmod +x setup-scripts/setup-cairo.sh && \
    ./setup-scripts/setup-cairo.sh && \
    pip install --upgrade pip

# Pre-build SNOS to amortise the slow first run
ENV CARGO_BUILD_JOBS=2
ENV VIRTUAL_ENV=/app/snos/.venv
ENV PATH="/app/snos/venv/bin:/app/snos/.venv/bin:${PATH}"

RUN . .venv/bin/activate && cargo build --release -p rpc-replay 2>&1 || \
    echo "[WARN] SNOS build failed at image-time — will compile on first run"

WORKDIR /app
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]

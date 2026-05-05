# =============================================================================
# infrastructure/snos/Dockerfile — StarkNet OS for replaying L2 blocks
#
# Phase 3.c. SNOS replays a sealed Madara block in the Cairo VM and
# emits a Cairo PIE the Stone prover consumes. The proof's public
# outputs include the new state root, so the on-chain Verifier can bind
# the convoy_protocol commitment storage value to a STARK-verified L2
# block execution.
#
# Builds FROM vg-snos:latest (the working image from verifiable_grid
# that already has SNOS v0.14.1-alpha.0 fully compiled — Karnot fork
# with the tx-hash patches, Cairo VM, rpc-replay binary, and the
# Python deps).
#
# WHY base from there: the upstream SNOS build is a 30+ minute Rust
# build + Cairo dependency setup that flakes out on slow apt mirrors.
# Reusing the cached image cuts our build to ~10 seconds.
#
# What we add:
#   - entrypoint.sh — replays Pathfinder blocks into PIEs in /output
# =============================================================================

FROM vg-snos:latest

ENV DEBIAN_FRONTEND=noninteractive

# Make sure curl is present so the entrypoint can poll Pathfinder.
RUN command -v curl >/dev/null 2>&1 || apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]

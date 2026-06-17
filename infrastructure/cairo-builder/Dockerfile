# =============================================================================
# cairo-builder — one-shot image with Scarb 2.9.2 + Starkli for declaring +
# deploying convoy_protocol.cairo to our Madara devnet.
#
# Stays minimal: Ubuntu 22.04 + curl + scarb + starkli. The compiled
# Sierra+CASM artefacts land in /work/cairo/convoy_protocol/target/.
# =============================================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git python3 jq build-essential pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install rustup + a recent stable rustc so we can `cargo install` the
# exact cairo-lang version Madara v0.10.0 expects.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

# Build the starknet-sierra-compile binary at cairo-lang 2.12.3, the
# version Madara v0.10.0 uses internally. starkli will be pointed at this
# via --compiler-path so the CASM hash we send matches what madara
# recomputes. Without this, scarb 2.11.4's bundled 2.11.4 sierra-compile
# produces CASM whose hash madara rejects (CompiledClassHashMismatch).
RUN cargo install --git https://github.com/starkware-libs/cairo --tag v2.12.3 starknet-sierra-compile --locked || \
    cargo install --git https://github.com/starkware-libs/cairo --tag v2.12.3 starknet-sierra-compile
RUN ln -s /root/.cargo/bin/starknet-sierra-compile /usr/local/bin/starknet-sierra-compile && \
    starknet-sierra-compile --version || echo "(version flag may be unsupported)"

# Build our own compute-casm-hash binary that uses cairo-lang-starknet-classes
# 2.12.3 (Madara v0.10.0's exact version). starkli's bundled version is 2.11.4,
# which hashes the same CASM bytes differently, so we override with --casm-hash
# at declare time. Source: infrastructure/cairo-builder/compute-casm-hash/.
COPY compute-casm-hash /tmp/compute-casm-hash
RUN cd /tmp/compute-casm-hash && cargo install --path . --locked
RUN ln -s /root/.cargo/bin/compute-casm-hash /usr/local/bin/compute-casm-hash

# Install Scarb 2.11.4 — closest available scarb to madara v0.10.0's
# cairo-lang-sierra-to-casm 2.12.3. Scarb skipped from 2.11 to 2.16 so no
# exact 2.12.x exists; 2.11.4 is the closest below. CASM output across
# 2.11.x ↔ 2.12.x should be compatible because the Sierra 1.7.0 → CASM
# format wasn't changed in patch releases.
#
# Madara v0.10.1+ migrated to the rebranded cairo-lang 1.0.0-alpha,
# which is incompatible with scarb 2.x's CASM output entirely. So we
# pin Madara to v0.10.0 (see docker-compose.l2.yml).
RUN curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh \
    | bash -s -- -v 2.11.4
ENV PATH="/root/.local/bin:${PATH}"

# Install Starkli — used to declare & deploy contracts via Starknet RPC.
# 0.4.1+ has a bundled sierra-to-casm matching cairo 2.11+; 0.4.2 is
# the latest, picked because v0.10.0 of madara serves spec 0.8.1 which
# both 0.4.1 and 0.4.2 target.
RUN curl https://get.starkli.sh | sh
ENV PATH="/root/.starkli/bin:${PATH}"
RUN /bin/bash -c "source /root/.starkli/env && starkliup -v 0.4.2"

WORKDIR /work

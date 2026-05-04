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
        curl ca-certificates git python3 jq \
    && rm -rf /var/lib/apt/lists/*

# Install Scarb 2.9.2 (matches Scarb.toml `starknet >= 2.9.2`)
RUN curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh \
    | bash -s -- -v 2.9.2
ENV PATH="/root/.local/bin:${PATH}"

# Install Starkli — used to declare & deploy contracts via Starknet RPC
RUN curl https://get.starkli.sh | sh
ENV PATH="/root/.starkli/bin:${PATH}"
RUN /bin/bash -c "source /root/.starkli/env && starkliup -v 0.4.0"

WORKDIR /work

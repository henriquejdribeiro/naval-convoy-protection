# =============================================================================
# Phase 3.a prover-api — Stone STARK prover for safe_area_verify.cairo
#
# Builds FROM vg-prover-api-patched:latest (the working image from
# verifiable_grid that already has cpu_air_prover, cpu_air_verifier,
# stark_evm_adapter, cairo-lang 0.14.0.1 — verified by inspection).
#
# WHY base from there: the upstream Stone Bazel build is 10+ minutes and
# Ubuntu mirrors flake out repeatedly. Using the cached image cuts our
# build to ~30 seconds and removes the network-dependence entirely.
#
# What we add:
#   - cast (foundry) — for L1 tx submission via submit_proof_l1.py
#   - safe_area_verify.cairo / sample_input.json / scripts / entrypoint
# =============================================================================

FROM vg-prover-api-patched:latest

ENV DEBIAN_FRONTEND=noninteractive

# Foundry's `cast` is what submit_proof_l1.py uses to send the L1 tx.
# foundryup downloads pre-built static binaries — no Rust toolchain needed.
RUN curl -L https://foundry.paradigm.xyz | bash || true
ENV PATH="/root/.foundry/bin:${PATH}"
RUN /root/.foundry/bin/foundryup -i stable && \
    /root/.foundry/bin/cast --version

# eth-utils for keccak256 in the submit script (sha3 fallback)
RUN pip3 install --no-cache-dir eth-utils

# Replace the verifiable_grid program/entrypoint with our naval-convoy ones
WORKDIR /app
COPY safe_area_verify.cairo /app/safe_area_verify.cairo
COPY sample_input.json      /app/sample_input.json
COPY prove_pie.py           /app/prove_pie.py
COPY submit_proof_l1.py     /app/submit_proof_l1.py
COPY fetch_l2_cells.py      /app/fetch_l2_cells.py
COPY entrypoint.sh          /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Starkli — used by fetch_l2_cells.py to query convoy_protocol via Pathfinder.
RUN curl https://get.starkli.sh | sh
ENV PATH="/root/.starkli/bin:${PATH}"
RUN /bin/bash -c "source /root/.starkli/env && starkliup -v 0.4.0"

RUN mkdir -p /proofs

ENTRYPOINT ["/app/entrypoint.sh"]

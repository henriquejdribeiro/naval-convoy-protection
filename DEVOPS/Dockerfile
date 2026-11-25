# =============================================================================
# convoy-devops — the FACTORY / operator node.
#
# The host runs exactly ONE script (SIMULATOR/demo/scripts/script0_devops.sh),
# which builds + starts THIS container. Everything else is the factory's job:
#
#   • runs the whole PoC pipeline (DEVOPS/orchestrate_poc1.sh → pipeline/script1..7) as bash
#   • drives the HOST Docker engine through the mounted /var/run/docker.sock to
#     CREATE / exec / compose every other container — the L1 Besu ships, the L2
#     Madara sequencers + follower mesh, the drone signer machines, the provers,
#     the ship-side submitters, and the stunnel TLS sidecars
#   • acts as the mTLS CERTIFICATE AUTHORITY (openssl): mints the CA + per-node
#     certs and seals each node's bundle into its volume            [Stage 2]
#   • reaches the live mesh over TLS through its own convoy-tls-devops sidecar
#
# Design: this is a CLIENT of the host engine (docker-out-of-docker), never its
# own daemon. ALL heavy toolchain — cairo / scarb / starkli / cast / forge / the
# prover — runs in SIBLING containers the factory launches, so none is installed
# here. The factory only orchestrates.
#
# Base: ubuntu:22.04 — a real registry image (any builder can pull it, so no
# "local base image not found"), and nothing we don't use.
# =============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ── What the pipeline actually runs INSIDE the factory ───────────────────────
#   bash                   orchestrate_poc1.sh + script1..7 are bash
#   coreutils grep sed gawk text wrangling in every script (cut/tr/seq/awk/…)
#   python3                script5_generate-mission.py (standard library only)
#   curl                   script1 L1 health polling + eth_getCode probes
#   ca-certificates        TLS roots for the https downloads below + curl calls
#   openssl                the factory's CA — gen-certs.sh mints + signs certs
# Heavy toolchain is deliberately absent: it lives in the sibling containers.
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash coreutils grep sed gawk python3 curl ca-certificates openssl \
    && rm -rf /var/lib/apt/lists/*

# ── Control plane to the host engine: docker CLI + compose plugin ────────────
# Pinned static binaries. We install ONLY the `docker` client (not dockerd/
# containerd/runc) — the factory talks to the host daemon via the mounted sock.
ARG DOCKER_VERSION=27.3.1
ARG COMPOSE_VERSION=2.29.7
RUN set -eux; \
    curl -fsSL --proto '=https' --tlsv1.2 \
        "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" -o /tmp/docker.tgz; \
    tar -xzf /tmp/docker.tgz -C /tmp; \
    install -m0755 /tmp/docker/docker /usr/local/bin/docker; \
    rm -rf /tmp/docker /tmp/docker.tgz; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL --proto '=https' --tlsv1.2 \
        "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose; \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose; \
    docker --version; \
    docker compose version

# Runs as root: must read the mounted docker.sock and write the repo + key/cert
# volumes. Inherent to docker-out-of-docker — the factory is host-root-equivalent;
# note that in the thesis trust model.
USER root

# working_dir, command (bash DEVOPS/orchestrate_poc1.sh) and all mounts come from
# DEVOPS/docker-compose.devops.yml, so no ENTRYPOINT/CMD is baked here.
# =============================================================================
# convoy-devops operator image.
#
# = convoy-cairo-builder (python3 + the mission scripts' deps)
#   + the Docker CLI and Compose plugin (static binaries), so the operator can
#     drive the HOST Docker daemon through the mounted /var/run/docker.sock.
#
# Static binaries → no apt/distro assumptions; downloaded once at build time.
# =============================================================================
FROM convoy-cairo-builder:latest
USER root

ARG DOCKER_VERSION=27.3.1
ARG COMPOSE_VERSION=2.29.7

RUN set -eux; \
    curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" -o /tmp/docker.tgz; \
    tar -xzf /tmp/docker.tgz -C /tmp; \
    install -m0755 /tmp/docker/docker /usr/local/bin/docker; \
    rm -rf /tmp/docker /tmp/docker.tgz; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose; \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose; \
    docker --version; \
    docker compose version

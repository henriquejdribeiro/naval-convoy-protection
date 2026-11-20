#!/usr/bin/env bash
# =============================================================================
# script0_devops.sh — the ONLY script you run on the host.
#
# Starts the convoy-devops OPERATOR node, which then runs the entire PoC
# (script1 … script7) from inside itself via DEVOPS/orchestrate_poc1.sh.
# Everything after this happens inside convoy-devops.
#
# Usage:
#   bash SIMULATOR/demo/scripts/script0_devops.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "${REPO_ROOT}"
export HOST_REPO_ROOT="${REPO_ROOT}"   # real host path → sibling bind-mounts resolve on the host daemon

# The operator image (convoy-devops) builds FROM cairo-builder, adding the
# Docker CLI + Compose plugin. cairo-builder must already exist.
docker image inspect convoy-cairo-builder:latest >/dev/null 2>&1 \
  || { echo "[devops] base image convoy-cairo-builder:latest is missing — build it first" >&2; exit 1; }

echo "[devops] building + starting convoy-devops  (HOST_REPO_ROOT=${HOST_REPO_ROOT})"
echo "[devops] first build downloads the static Docker CLI (~70 MB); later runs use the cache."
docker compose --project-directory . -f DEVOPS/docker-compose.devops.yml up -d --build --remove-orphans

echo "[devops] following the run — Ctrl+C only stops watching; the run keeps going inside the container:"
echo
docker logs -f convoy-devops

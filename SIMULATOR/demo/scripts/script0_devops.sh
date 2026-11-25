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
# devops talks to the HOST engine via docker.sock, so every repo path the inner
# scripts hand the engine must be a HOST path. On Docker Desktop the engine (a
# Linux VM) sees the Windows drives at /run/desktop/mnt/host/<drive> — colon-free,
# so it's valid as this container's mount target too. Translate the Git Bash
# /c/... form to it; on a native-Linux engine, pass through unchanged.
#
# CRITICAL: do NOT export this. Git Bash/MSYS mangles an *exported* POSIX path it
# doesn't recognise (/run/...) into "C:/Program Files/Git/run/..." when the native
# docker-compose.exe reads it. Writing it to a .env FILE makes compose substitute
# the value verbatim — the shell→exe conversion never happens.
case "${REPO_ROOT}" in
  /[a-z]/*) HOST_REPO_ROOT="/run/desktop/mnt/host${REPO_ROOT}" ;;  # /c/Users/... → /run/desktop/mnt/host/c/Users/...
  *)        HOST_REPO_ROOT="${REPO_ROOT}" ;;
esac
printf 'HOST_REPO_ROOT=%s\n' "${HOST_REPO_ROOT}" > DEVOPS/.env

# The pipeline (run inside convoy-devops) launches sibling containers from the
# convoy-cairo-builder image (starkli/scarb) — it must already be built on the host.
docker image inspect convoy-cairo-builder:latest >/dev/null 2>&1 \
  || { echo "[devops] sibling image convoy-cairo-builder:latest is missing — build it first" >&2; exit 1; }

echo "[devops] building + starting convoy-devops  (HOST_REPO_ROOT=${HOST_REPO_ROOT})"
echo "[devops] first build downloads the static Docker CLI (~70 MB); later runs use the cache."
docker compose --env-file DEVOPS/.env --project-directory . -f DEVOPS/docker-compose.devops.yml up -d --build --remove-orphans

echo "[devops] following the run — Ctrl+C only stops watching; the run keeps going inside the container:"
echo
docker logs -f convoy-devops

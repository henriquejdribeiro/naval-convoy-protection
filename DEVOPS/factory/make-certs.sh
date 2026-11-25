#!/usr/bin/env bash
# convoy mTLS cert FACTORY — the devops operator is the CA.
#   mint : one internal CA + a cert per node, into the PRIVATE vault volume (ca.key never leaves)
#   seal : copy ONLY <node>.pem + ca.crt into each node's own volume (least privilege)
# Self-locating; runnable on the host (Git Bash) OR inside convoy-devops — it only issues
# docker commands + reads gen-certs.sh locally (piped via stdin, so no bind-mount path games).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CA_VOL=convoy-tls-ca
NODES="node1 node2 node3 node4 node5 node1b node2b node3b node4b node5b shipa shipf shipb devops"

echo "[factory] minting CA + certs into private vault '${CA_VOL}' (idempotent)…"
docker run -i --rm -v "${CA_VOL}:/tls" alpine:3.20 \
  sh -c 'apk add --no-cache openssl >/dev/null 2>&1 && exec sh -s' < "${SCRIPT_DIR}/gen-certs.sh"

echo "[factory] sealing one cert per node into its own volume…"
for N in ${NODES}; do
  docker run --rm -v "${CA_VOL}:/src:ro" -v "convoy-tls-${N}:/dst" alpine:3.20 \
    sh -c "cp /src/${N}.pem /src/ca.crt /dst/ && chmod 600 /dst/${N}.pem"
  echo "    ✓ convoy-tls-${N}  (holds only ${N}.pem + ca.crt)"
done
echo "[factory] done — ca.key stayed in '${CA_VOL}'; no node volume holds another node's key."
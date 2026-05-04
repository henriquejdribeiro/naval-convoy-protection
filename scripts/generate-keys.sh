#!/bin/bash
# generate-keys.sh — produce the 7 Geth keystore JSONs for the convoy stack.
#
# Imports anvil's deterministic test keys [0..6] using the password in
# infrastructure/geth/password.txt. Output: infrastructure/geth/keys/X.json
# for X ∈ {A, B, C, D, E, F, D-commander}.
#
# Idempotent — re-running overwrites the existing keystore files.
# Requires Docker (uses ethereum/client-go:v1.10.17 image).
#
# Usage (from the repo root):
#     ./scripts/generate-keys.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYS_DIR="${REPO_ROOT}/infrastructure/geth/keys"
PASSWORD_FILE="${REPO_ROOT}/infrastructure/geth/password.txt"
GETH_IMAGE="ethereum/client-go:v1.10.17"

# Anvil's deterministic test keys (Foundry mnemonic).
# Order matches keys/README.md: 0..5 are ship validators A..F; 6 is D's commander.
declare -a ANVIL_KEYS=(
    "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"   # [0] A
    "59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"   # [1] B
    "5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"   # [2] C
    "7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"   # [3] D
    "47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"   # [4] E
    "8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba"   # [5] F
    "92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e"   # [6] D-commander
)
declare -a SHIP_LABELS=(A B C D E F D-commander)

mkdir -p "${KEYS_DIR}"

# Wipe previous keystore files (we re-import every time)
echo "[gen-keys] cleaning old keystores in ${KEYS_DIR}"
find "${KEYS_DIR}" -maxdepth 1 -name '*.json' -type f -delete 2>/dev/null || true

# Pull the geth image once
echo "[gen-keys] pulling ${GETH_IMAGE}"
docker pull "${GETH_IMAGE}" >/dev/null

for i in "${!ANVIL_KEYS[@]}"; do
    label="${SHIP_LABELS[$i]}"
    pk="${ANVIL_KEYS[$i]}"
    echo "[gen-keys] importing key for ship ${label}"

    # Per-key working directory inside the repo (Docker Desktop on Windows
    # only mounts paths under the project root by default).
    workdir="${REPO_ROOT}/.tmp-keys/${label}"
    rm -rf "${workdir}" && mkdir -p "${workdir}"
    echo -n "${pk}" > "${workdir}/key.txt"

    # Run geth in the docker image to import the raw private key — this
    # produces a UTC-named keystore JSON encrypted with the password.
    # MSYS_NO_PATHCONV stops Git Bash from rewriting /work to C:/Program Files/Git/work
    MSYS_NO_PATHCONV=1 docker run --rm \
        -v "${workdir}:/work" \
        -v "${PASSWORD_FILE}:/password.txt:ro" \
        --entrypoint geth \
        "${GETH_IMAGE}" \
        account import \
        --datadir /work/data \
        --password /password.txt \
        /work/key.txt > "${workdir}/import.log" 2>&1 || {
            echo "[gen-keys] geth import failed for ${label}; log:"
            cat "${workdir}/import.log"
            rm -rf "${workdir}"
            exit 1
        }

    # Move the produced keystore file to keys/<label>.json (predictable name)
    src=$(find "${workdir}/data/keystore" -type f -name 'UTC--*' | head -n1)
    if [[ -z "${src}" ]]; then
        echo "[gen-keys] keystore not produced for ${label}"
        rm -rf "${workdir}"
        exit 1
    fi
    cp "${src}" "${KEYS_DIR}/${label}.json"
done

# Clean up the temp directory tree
rm -rf "${REPO_ROOT}/.tmp-keys"

echo ""
echo "[gen-keys] done — produced:"
ls -1 "${KEYS_DIR}"/*.json | sed 's/^/    /'

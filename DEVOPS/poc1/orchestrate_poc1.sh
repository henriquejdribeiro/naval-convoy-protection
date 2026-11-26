#!/usr/bin/env bash
# =============================================================================
# orchestrate_poc1.sh — runs INSIDE convoy-devops (started by script0_devops.sh).
#
# Executes the full PoC in order — the exact README sequence — calling the
# existing mission scripts in DEVOPS/poc1/scripts/ . You never run this
# directly on the host; the devops container runs it automatically on boot.
#
# Watch it with:  docker logs -f convoy-devops
# =============================================================================
set -euo pipefail
cd "${HOST_REPO_ROOT:?orchestrate_poc1.sh must run inside convoy-devops (HOST_REPO_ROOT unset)}"
S="DEVOPS/poc1/scripts"

echo "════════════ [1/7] L1 + L2 bring-up ════════════"
bash "$S/script1_up.sh" --no-debugger

echo "════════════ [2/7] declare + deploy convoy_protocol on both Madaras ════════════"
bash "$S/script2_deploy-l2.sh" --swarm both

echo "════════════ [3/7] 10 drone accounts + per-drone signer machines (auto-funded) ════════════"
bash "$S/script3_generate-drone-accounts.sh" --swarm both

# Stamp the mission ORDER time once, in real PC unix seconds, and share it with
# the register step (Registry.deploy ts_start) AND the telemetry generator, so the
# proof's time window is anchored to the real moment the order is issued.
export TS_START="$(date +%s)"
echo "════════════ [4/7] register missions (order ts_start=${TS_START}) ════════════"
bash "$S/script4_register-missions.sh" --swarm both

echo "════════════ [5/7] generate both-safe scenario ════════════"
python3 "$S/script5_generate-mission.py" --scenario both-safe --output-dir SIMULATOR/poc1/demo/scenarios/

echo "════════════ [6/7] submit telemetry — 2 swarms × 5 drones ════════════"
for sw in alpha bravo; do
  for d in 1 2 3 4 5; do
    bash "$S/script6_submit-telemetry.sh" "$sw" "$d" "SIMULATOR/poc1/demo/scenarios/both-safe/${sw}_${d}.json"
  done
done

echo "════════════ [7/7] prove both swarms ════════════"
bash "$S/script7_prove-swarm.sh" alpha
bash "$S/script7_prove-swarm.sh" bravo

echo
echo "════════════ PoC launched ════════════"
echo "Proving + L1 submission run ASYNC inside the prover-api containers (a few minutes)."
echo "Follow them:"
echo "    docker logs -f convoy-prover-api-alpha"
echo "    docker logs -f convoy-prover-api-bravo"
echo "Dual-safe verdict lands when advanceCount() increments on the CommandLog."

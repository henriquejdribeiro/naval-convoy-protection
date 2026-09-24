# Naval Convoy Protection

A verifiable naval drone mission-compliance system on a modular blockchain stack.
Two five-drone swarms sweep an assigned zone; the swarm's leader compresses all
five drones' signed telemetry into **one aggregate STARK proof** that the assigned
area was covered, no contact exceeded the detection threshold, and every reading
was signed by a registered drone. Both proofs are verified natively on a
permissioned settlement L1; only when **both** flanks are certified does the
commander's `advance` command succeed and the convoy transit.

## Provenance

This project's architecture derives from the author's Master's thesis at Instituto
Superior Técnico (2026):

> **Modular blockchain architectures applied to drone swarms with low computational resources**
> *Execution of smart contracts and analysis of consensus time*

The repository is a standalone mission archetype, with its own contracts, container
topology, and visualisation.

## What this is

Rather than every node re-executing the mission logic, each swarm's reconnaissance
is reduced to a single ~1 MB proof that the six ships verify in well under a second.
Consensus over what a swarm did is thereby shifted from a cost repeatedly borne by
every constrained participant to a **one-time cost borne only by the prover**.

- **L1 — Hyperledger Besu QBFT.** 6 validators (ships A–F), Byzantine-fault-tolerant
  finality (quorum 4, tolerates 1 Byzantine ship). The settlement layer.
- **Real StarkWare Starknet cores.** One genuine `Starknet.sol` messaging core **per
  swarm**, deployed on L1 at bring-up by the
  [madara-bootstrapper](https://github.com/madara-alliance/madara) (`bootstrapper-v2`).
  Not a stub — the real proxied core, initialised with a per-chain config hash.
- **L2 — two Madara Starknet appchains** (`convoy_alpha`, `convoy_bravo`), v0.9.1.
  Each is a `--sequencer` with L1 sync enabled, watching **its own** core, plus 4
  `--full` follower nodes (one per drone) that re-execute its blocks.
- **`convoy_protocol` (Cairo).** Per-drone `submit_telemetry` + the `safe_area`
  compliance predicate. The raw per-cell telemetry stays in L2 storage; only the
  Pedersen commitment and the verdict are meant to leave L2.
- **Aggregate coverage proof (`safe_area_verify_{alpha,bravo}.cairo`).** One STARK
  proof per swarm over all 5 drones, compiled in proof mode against four builtins:
  `output` (public interface), `range_check` (coverage / detection / time / strip
  predicates), `pedersen` (folds the sweep into one collision-resistant commitment),
  and `ecdsa` (verifies each drone's signature **in-circuit**). A valid proof attests
  not that *some* readings pass, but that the *specific registered drones* produced them.
- **The L1→L2 bridge (trustless).** A commander opens a mission on L1 via
  `Registry.deploy`, which sends a real `LogMessageToL2` through that swarm's core.
  Each Madara **auto-consumes** it and runs `#[l1_handler] open_mission` on L2 — the
  mission only opens if the message really crossed the bridge, authorised by the L1
  commander. Because Besu under QBFT finalises blocks but does not serve the
  `finalized`/`safe` block tags, the sequencer reaches L1 through a thin RPC shim
  (`l1-shim`) that rewrites those tags to `latest`.
- **The L2→L1 verdict (trustless).** Each swarm's proof is verified on L1 by the
  **genuine StarkWare GPS verifier** (2023_9 suite, byte-identical to Ethereum
  mainnet); the convoy `Verifier.registerSwarmProof` then records the flank only if
  the fact is registered, the wrapped program hash matches the pinned safe-area
  program, and the 5 drone pubkeys match the mission. When both flanks are SAFE, the
  two swarm hashes fold into a single **principal hash** and the `advance` gate opens.

`Registry` holds both cores and dispatches each mission to the right one
(`_coreFor(mission_id)`), so alpha's sequencer only ever sees alpha's messages and
bravo's only bravo's — clean, no cross-chain handlers.

## Trust model at a glance

| Zone | Trust | Anchored in |
|---|---|---|
| Off-chain prover | none required | STARK soundness (configurable error) |
| L2 (per swarm) | operational | integrity of the navy-operated sequencer; followers re-execute |
| L1 (six ships) | cryptographic | Besu QBFT BFT consensus + native STARK verification |

## Project status

In-progress thesis project. The full pipeline runs end-to-end on a single
workstation: both swarm proofs are verified on L1 and recorded via
`registerSwarmProof`, the principal hash is certified, `isDualSafe(1,2)` reads true,
and the commander's `advance` succeeds. The negative scenarios (`both-unsafe`,
`mixed`, drop-out) correctly leave at least one flank uncertified and cause `advance`
to revert.

| Component | Status |
|---|---|
| L1 — Hyperledger Besu QBFT, 6 validators | ✅ Working |
| Real StarkWare Starknet cores (1 per swarm, via madara-bootstrapper) | ✅ Deployed on L1 at bring-up |
| L1 convoy contracts (`Registry`, `Verifier`, `CommandLog`) | ✅ Deploy + wired |
| L2 — Madara α + β (v0.9.1), 1 sequencer + 4 followers each | ✅ Both healthy |
| `convoy_protocol` on each L2 | ✅ Declared + deployed |
| 5 drone accounts + per-drone signer machines per swarm | ✅ All 10, keys born in-container |
| **L1→L2 `open_mission` auto-consume (both swarms)** | ✅ **Trustless via the real cores + `l1-shim`** |
| Per-drone `submit_telemetry` | ✅ Signed by each drone's own STARK-curve key |
| Real StarkWare STARK verifier on L1 (`GpsStatementVerifier` 2023_9) | ✅ **Deployed on Besu, byte-identical to mainnet** |
| Off-chain prover pipeline (Cairo → Stone → EVM proof) | ✅ Working |
| **Per-swarm aggregate proof — verified trustlessly on L1** | ✅ **`Verifier.registerSwarmProof`, gated on `isValid(factHash)` + program + drone pubkeys** |
| Dual-safe principal hash + gated `advance` | ✅ `CommandLog.advance`, reverts unless both flanks SAFE |
| Interactive 3D simulator + offline performance view | ✅ three.js walkthrough (Steps 0–7) + captured-run replay |

## Getting started

End-to-end from a fresh clone to both flanks certified and the convoy advancing.

**Prerequisites** — Docker + Docker Compose v2, git, Python 3.10+, **≈24 GB free RAM**
(the two Stone provers can run concurrently; each peaks ≈5.6 GiB), and internet on
first run (the bootstrapper and Madara images pull from ghcr). Host ports that must
be free: `8545`/`8546` (Besu L1 RPC/WS), `19944`–`19948` (Madara alpha + 4 followers),
`29944`–`29948` (Madara bravo + 4 followers), `9545`/`9645` (leader pathfinders),
`8888` (Dozzle), `8000` (web visualiser).

### 1. Clone

```bash
git clone --recurse-submodules https://github.com/henriquejdribeiro/naval-convoy-protection.git
cd naval-convoy-protection
```

### 2. Build the cairo-builder image (first time only)

Bundles scarb, starkli, and the `starknet-sierra-compile` / `compute-casm-hash`
helpers — all Cairo/Starknet tooling runs inside it, so nothing Cairo-related is
installed on the host.

```bash
docker build -t convoy-cairo-builder LAYER2/cairo-builder/
```

### 3. Bring up the stack + deploy L2 + drone accounts

```bash
./SIMULATOR/demo/scripts/script1_up.sh                                      # add --no-debugger to skip Dozzle
./SIMULATOR/demo/scripts/script2_deploy-l2.sh --swarm both                  # declare + deploy convoy_protocol on both Madaras
./SIMULATOR/demo/scripts/script3_generate-drone-accounts.sh --swarm both    # 10 drone accounts + per-drone signer machines, auto-funded
```

`script1_up.sh` is one idempotent command. It: (1) starts the **6-validator Besu
QBFT** L1; (2) runs the **madara-bootstrapper twice** — one real Starknet core per
swarm; (3) deploys the L1 convoy contracts (`Registry` bound to both cores,
`Verifier`, `CommandLog`) and the StarkWare 2023_9 verifier suite; (4) **seeds** each
sequencer's genesis (`--devnet` one-shot) then brings the L2 up as **`--sequencer`
with L1 sync**; (5) starts the 4 `--full` follower drones per swarm + the leader
pathfinders + Dozzle. The three L1 contract addresses are deterministic on a fresh
chain and printed in the deploy summary:

| Contract | Address | Role |
|---|---|---|
| `Registry` | `0x5FbDB2315678afecb367f032d93F642f64180aa3` | mission specs + verdicts, `isDualSafe` |
| `Verifier` | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` | `registerSwarmProof`, `principalHash` |
| `CommandLog` | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` | gated `advance` |

### 4. Open both missions across the real L1→L2 bridge

```bash
./SIMULATOR/demo/scripts/script4_register-missions.sh --swarm both
```

`Registry.deploy(mission_id, …)` sends a real `LogMessageToL2` through that swarm's
core, and each sequencer's L1 sync **auto-consumes** it (after a 10-block finality
wait) and runs `open_mission` on L2. No dev fallback — the mission opens *only*
because the L1 message crossed the bridge. Wait for both to land:

```bash
sleep 90   # 10-block finality + processing
docker logs convoy-madara-alpha 2>&1 | grep -iE "Processing L1→L2|nonce=" | tail -3
docker logs convoy-madara-bravo 2>&1 | grep -iE "Processing L1→L2|nonce=" | tail -3
```

Both should show `Processing L1→L2 message: … nonce=0`.

### 5. Generate telemetry and submit all 10 drones

Each drone **signs and submits from inside its own signer machine**
(`convoy-machine-<swarm>-<N>`): the STARK-curve key is born in the machine's Docker
volume via `starkli signer keystore new` and never touches the host.
`script6_submit-telemetry.sh` `docker exec`s into the machine to sign
`H = Pedersen(cells, nonce)` and invoke `submit_telemetry`; the contract's identity
gate accepts the tx only because the machine's account is the one registered for
`(mission, drone)`.

```bash
python3 SIMULATOR/demo/scripts/script5_generate-mission.py --scenario both-safe --output-dir SIMULATOR/demo/scenarios/

for sw in alpha bravo; do
  for d in 1 2 3 4 5; do
    ./SIMULATOR/demo/scripts/script6_submit-telemetry.sh "$sw" "$d" "SIMULATOR/demo/scenarios/both-safe/${sw}_${d}.json"
  done
done
```

Scenarios: `both-safe`, `both-unsafe`, `mixed`, `alpha-dropout-vanish`,
`alpha-dropout-midflight`, `dual-dropout`. Each drone's JSON stores the full flight
(home → sweep → home); only the in-zone readings are fed to the proof.

### 6. Prove each swarm and verify on L1

`script7_prove-swarm.sh <swarm>` has the swarm leader fetch its 5 drones' signed
telemetry from L2 (`fetch_l2_swarm.py`), produce **one** STARK proof over the swarm
with `safe_area_verify_<swarm>.cairo`, and the swarm's relay ship (alpha → ship F,
bravo → ship B) submit it via `convoy-submitter` → the real `GpsStatementVerifier` →
`Verifier.registerSwarmProof`.

```bash
./SIMULATOR/demo/scripts/script7_prove-swarm.sh alpha
./SIMULATOR/demo/scripts/script7_prove-swarm.sh bravo

docker logs -f convoy-prover-api-alpha    # the Stone prove takes a few minutes
docker logs -f convoy-prover-api-bravo
```

Verifying a proof on L1 is a **three-phase protocol** (Merkle → FRI → memory pages),
then `GpsStatementVerifier.verifyProofAndRegister` writes the canonical fact hash,
then `registerSwarmProof` records the flank. This settles in a **fixed, area-
independent 14 transactions per swarm** — a flank cleared with 50 readings and one
cleared with 50 000 settle through the same 14. **Prove takes minutes; on-chain
verification is sub-second** — the defining asymmetry of the validity-proof model.

### 7. Advance the convoy (gated on both flanks)

Once both swarm proofs are recorded, `Registry.isDualSafe(1,2)` reads true and the
commander (ship D) can advance. `CommandLog.advance` reverts unless the dual-safe
condition holds.

```bash
# check the gate
docker run --rm --network convoy-l1 --entrypoint sh ghcr.io/foundry-rs/foundry:latest -c "\
  echo -n 'principalHash='; cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 'principalHash()(bytes32)' --rpc-url http://ship-a:8545; \
  echo -n 'isDualSafe=';    cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 'isDualSafe(uint256,uint256)(bool)' 1 2 --rpc-url http://ship-a:8545"

# advance — signed by ship D's commander key
MSYS_NO_PATHCONV=1 docker run --rm --network convoy-l1 -v convoy-ship-d-key:/key --entrypoint sh ghcr.io/foundry-rs/foundry:latest -c "\
  cast send 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 'advance(uint256,uint256,uint256)' 1 2 100 \
    --rpc-url http://ship-a:8545 --private-key \"\$(cat /key/pk)\" --legacy"
```

### 8. Teardown

```bash
docker compose --project-directory . -f LAYER1/docker-compose.l1.yml -f LAYER2/docker-compose.l2.yml down -v --remove-orphans 2>/dev/null
docker ps -aq --filter name=convoy- | xargs -r docker rm -f
docker volume ls -q --filter name=naval-convoy-protection | xargs -r docker volume rm
docker volume ls -q --filter name=convoy- | xargs -r docker volume rm
docker network prune -f
```

> **Always tear down before a fresh run.** Madara persists its L1-sync cursor in a
> named volume; a stale volume makes the sequencer skip the next mission's messages.
> The block above removes the containers **and** the volumes.

## Interactive 3D simulator

The web visualiser is a three.js ocean world with the convoy, the six ships, and the
two swarms. It runs a guided **8-step walkthrough (Steps 0–7)** mirroring the mission
flow above — setup, open mission, sweep, prove, relay, verify, advance — and reads
real captured performance data from the last pipeline run.

```bash
python3 SIMULATOR/webapp/serve.py       # then open http://localhost:8000
```

- **Click any ship or drone** → a box lists the containers that make it up, with
  their Docker image sizes.
- **Click a ship / madara node** → a draggable window shows that node's captured
  chain logs (transactions + L1↔L2 messages).
- **Live-performance window** → replays each container's RAM over the mission,
  phase-banded (Setup · Deploy · Submit · Prove · Advance) and synced to the 7 steps.

This performance view is **offline**: it reads the newest
`SIMULATOR/demo/runs/metrics-*/` folder committed in the repo, so it works on a fresh
clone without re-running the stack.

### Capturing a new performance run (the way we run the whole mission)

This is the exact end-to-end sequence we run in **Git Bash** to drive the full
mission *and* record everything the 3D demo replays. It wraps the pipeline of §3–§7
in a `docker stats` sampler, writes phase-boundary markers (`setup` · `deploy` ·
`submit` · `prove` · `advance` · `end`), and captures every node's + prover's full
logs into a fresh `SIMULATOR/demo/runs/metrics-<timestamp>/` folder — which
`serve.py` auto-selects as the newest run. Run the blocks in order in **one terminal
session** (the `$RUN`, `$LOG`, `$STATS_PID` variables carry across blocks).

**1. Hardened teardown — start from a truly clean state** (containers **and**
volumes, so Madara's L1-sync cursor is fresh):

```bash
docker compose --project-directory . -f LAYER1/docker-compose.l1.yml -f LAYER2/docker-compose.l2.yml down -v --remove-orphans 2>/dev/null; docker ps -aq --filter name=convoy- | xargs -r docker rm -f; docker volume ls -q --filter name=naval-convoy-protection | xargs -r docker volume rm; docker volume ls -q --filter name=convoy- | xargs -r docker volume rm; docker network prune -f; echo "down done"
```

**2. Start the sampler + `setup` marker, then bring up + deploy L2 + drone accounts**
(scripts 1–3):

```bash
RUN=SIMULATOR/demo/runs/metrics-$(date +%Y%m%d-%H%M%S); mkdir -p "$RUN"; LOG="$RUN/pipeline.log"; echo "RUN=$RUN"
( while true; do printf '%s ' "$(date +%s)"; docker stats --no-stream --format '{{.Name}}={{.CPUPerc}}/{{.MemUsage}}' | tr '\n' ' '; echo; sleep 5; done ) > "$RUN/stats.log" 2>&1 & echo "STATS_PID=$!"
echo "setup $(date +%s)" >> "$RUN/phases.txt"
docker images --format '{{.Repository}}:{{.Tag}}	{{.Size}}' > "$RUN/docker-images.txt"
{ echo "=== script1 $(date +%T) ==="; ./SIMULATOR/demo/scripts/script1_up.sh; echo "=== script2 $(date +%T) ==="; ./SIMULATOR/demo/scripts/script2_deploy-l2.sh --swarm both; echo "=== script3 $(date +%T) ==="; ./SIMULATOR/demo/scripts/script3_generate-drone-accounts.sh --swarm both; } 2>&1 | tee -a "$LOG"; echo "infra ready"
```

**3. `deploy` marker → open both missions (script4) → wait for the L1→L2 bridge →
`submit` marker → submit all 10 drones** (`both-safe`). The gate polls `get_mission`
on both L2s until each mission's spec has landed (the `8f0d180` / `7bfa480` fragments
are the expected `both-safe` mission-spec hashes for alpha / bravo):

```bash
echo "deploy $(date +%s)" >> "$RUN/phases.txt"
{ echo "=== script4 $(date +%T) ==="; ./SIMULATOR/demo/scripts/script4_register-missions.sh --swarm both; } 2>&1 | tee -a "$LOG"
source SIMULATOR/demo/.tmp-l2/convoy_l2.env; ok=no; for i in $(seq 1 40); do a=$(MSYS_NO_PATHCONV=1 docker exec convoy-prover-api-alpha starkli call "$CONVOY_PROTOCOL_ADDR_ALPHA" get_mission 1 --rpc http://convoy-madara-alpha:9944/rpc/v0.8.1 2>&1); b=$(MSYS_NO_PATHCONV=1 docker exec convoy-prover-api-bravo starkli call "$CONVOY_PROTOCOL_ADDR_BRAVO" get_mission 2 --rpc http://convoy-madara-bravo:9944/rpc/v0.8.1 2>&1); ao=no; bo=no; echo "$a"|grep -qi 8f0d180 && ao=yes; echo "$b"|grep -qi 7bfa480 && bo=yes; echo "  try $i: alpha=$ao bravo=$bo"; [ "$ao" = yes ]&&[ "$bo" = yes ]&&{ ok=yes; break; }; sleep 10; done
if [ "$ok" = yes ]; then echo "submit $(date +%s)" >> "$RUN/phases.txt"; { for sw in alpha bravo; do for d in 1 2 3 4 5; do f=SIMULATOR/demo/scenarios/both-safe/${sw}_${d}.json; [ -f "$f" ] && ./SIMULATOR/demo/scripts/script6_submit-telemetry.sh "$sw" "$d" "$f"; done; done; } 2>&1 | tee -a "$LOG"; echo "submits done"; else echo ">>> GATE TIMEOUT — kill \$STATS_PID + ping me" | tee -a "$LOG"; fi
```

**4. `prove` marker → prove both swarms (script7), then watch until each registers:**

```bash
echo "prove $(date +%s)" >> "$RUN/phases.txt"; { echo "=== prove alpha $(date +%T) ==="; ./SIMULATOR/demo/scripts/script7_prove-swarm.sh alpha; echo "=== prove bravo $(date +%T) ==="; ./SIMULATOR/demo/scripts/script7_prove-swarm.sh bravo; } 2>&1 | tee -a "$LOG"
```

```bash
docker logs -f convoy-prover-api-alpha
```

```bash
docker logs -f convoy-prover-api-bravo
```

**5. `advance` marker → check the gate + advance → +10 s settle → capture ALL logs →
stop the sampler.** This writes `prover-{alpha,bravo}.log` and `logs/<node>.log`
(full node logs), and closes `phases.txt` with `end`:

```bash
echo "advance $(date +%s)" >> "$RUN/phases.txt"; { echo "=== L1 state $(date +%T) ==="; docker run --rm --network convoy-l1 --entrypoint sh ghcr.io/foundry-rs/foundry:latest -c "echo -n 'principalHash='; cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 'principalHash()(bytes32)' --rpc-url http://ship-a:8545; echo -n 'isDualSafe='; cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 'isDualSafe(uint256,uint256)(bool)' 1 2 --rpc-url http://ship-a:8545"; echo "=== advance $(date +%T) ==="; MSYS_NO_PATHCONV=1 docker run --rm --network convoy-l1 -v convoy-ship-d-key:/key --entrypoint sh ghcr.io/foundry-rs/foundry:latest -c "cast send 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 'advance(uint256,uint256,uint256)' 1 2 100 --rpc-url http://ship-a:8545 --private-key \"\$(cat /key/pk)\" --legacy"; } 2>&1 | tee -a "$LOG"
sleep 10
echo "end $(date +%s)" >> "$RUN/phases.txt"; kill "$STATS_PID" 2>/dev/null
docker logs convoy-prover-api-alpha > "$RUN/prover-alpha.log" 2>&1; docker logs convoy-prover-api-bravo > "$RUN/prover-bravo.log" 2>&1
mkdir -p "$RUN/logs"; for c in $(docker ps --format '{{.Names}}' | grep -E '^convoy-(ship-[a-f]|madara-(alpha|bravo)(-[2-5])?)$'); do docker logs "$c" > "$RUN/logs/$c.log" 2>&1; done
echo "ALL DONE — $RUN"
```

The result is one `metrics-<timestamp>/` folder containing `stats.log` (the whole
run's per-container RAM/CPU), `phases.txt` (the phase bands), `docker-images.txt`
(image sizes for the container inspector), `pipeline.log`, `prover-{alpha,bravo}.log`,
and `logs/<node>.log` (each ship's + madara node's chain logs — transactions and
L1↔L2 messages). Serve the webapp and the demo reads this newest run automatically.

## Hand-writing UNSAFE telemetry

Each per-drone JSON carries four in-zone arrays (`cells_x`, `cells_y`,
`cells_p_contact`, `cells_ts`). Copy a `both-safe` drone file and break one predicate:

- Drop coverage below 95% → `FAIL_COVERAGE`
- Push one `p_contact` to ≥ 7000 → `FAIL_DETECTION`
- Push one `ts` beyond `ts_start + 360` → `FAIL_TIME`
- Move one `(x, y)` outside the drone's strip → `FAIL_STRIP`

Any failing drone leaves its swarm's proof unable to certify SAFE, so that flank is
never recorded and `advance` reverts.

## Contract surface

| Suite | Layer | Origin | Purpose |
|---|---|---|---|
| Verifier Stack (`GpsStatementVerifier` + Merkle/FRI/MemoryPage + `CpuFrilessVerifier`) | L1 | Inherited (StarkWare 2023_9) | native STARK verification, `starknet` 7-builtin layout |
| `StarknetCore` (per swarm) | L1 | Inherited (Starknet) | L1↔L2 message bridge, L2 state custody |
| `Registry`, `Verifier`, `CommandLog` | L1 | Custom | mission specs, per-swarm proof gate + principal, gated advance |
| `convoy_protocol` | L2 | Custom | `open_mission` (l1_handler), `submit_telemetry`, `safe_area` predicate |

The two inherited suites are deployed **unmodified**, isolating the convoy
contribution to the application boundary.

## Repository layout

```
LAYER1/   Besu QBFT L1, Solidity contracts (convoy + StarkWare verifier), bootstrapper, l1-shim lives in LAYER2/
LAYER2/   Madara L2 config, convoy_protocol Cairo, cairo-builder image, l1-shim
PROOF/    safe_area Cairo programs, Stone prover-api, convoy-submitter
SIMULATOR/
  demo/scripts/   script1..7 + deploy-stark-verifier
  demo/scenarios/ per-drone telemetry per scenario
  demo/runs/      captured metrics-* runs (feed the 3D perf view)
  webapp/         three.js simulator + serve.py
```

## Ports

| URL | What |
|---|---|
| <http://localhost:8000> | Interactive 3D simulator (`SIMULATOR/webapp/serve.py`) |
| <http://localhost:8888> | Dozzle log viewer (grouped by drone) |

## License

Apache-2.0 — see `LICENSE`.

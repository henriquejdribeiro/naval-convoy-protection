# Naval Convoy Protection

## Provenance

This project's architecture derives from the author's Master's thesis at Instituto Superior Técnico (2026):

> **Modular blockchain architectures applied to drone swarms with low computational resources**
> *Execution of smart contracts and analysis of consensus time*

The repository is a standalone mission archetype, with its own contracts, container topology, and visualisation.

## What this is

A verifiable naval-drone mission-compliance system on a modular blockchain stack. Two 5-drone swarms (alpha, bravo) sweep an assigned zone; each drone proves it stayed inside its strip and met coverage/detection/time thresholds. The verdict is anchored on a settlement L1.

- **L1 — Hyperledger Besu QBFT.** 6 validators (ships A–F), BFT finality. The settlement layer.
- **Real StarkWare Starknet cores.** One genuine `Starknet.sol` messaging core **per swarm**, deployed on L1 at bring-up by the [madara-bootstrapper](https://github.com/madara-alliance/madara) (`bootstrapper-v2`). Not a stub — the real proxied core, initialized with a per-chain config hash.
- **L2 — two Madara Starknet appchains** (`convoy_alpha`, `convoy_bravo`), v0.9.1. Each is a `--sequencer` with L1 sync enabled, watching **its own** core, plus 4 `--full` follower nodes (one per drone).
- **`convoy_protocol` (Cairo).** Per-drone `submit_telemetry` + the `safe_area` compliance predicate. When a swarm's 5 drones all pass, it emits `MissionSafe`.
- **The L1→L2 bridge (trustless, working).** A commander opens a mission on L1 via `Registry.deploy`, which sends a real `LogMessageToL2` through that swarm's core. Each Madara **auto-consumes** it and runs the `#[l1_handler] open_mission` on L2. No dev fallback — the mission only opens if the message really crossed the bridge, authorised by the L1 commander.

`Registry` holds both cores and dispatches each mission to the right one (`_coreFor(mission_id)`), so alpha's sequencer only ever sees alpha's messages and bravo's only bravo's — clean, no cross-chain handlers.

## Project status

In-progress thesis project. The L1→L2 direction is fully wired and trustless for both swarms, and the L2→L1 verdict is settled trustlessly — each drone's `safe_area` compliance proof is verified on L1 by the **genuine StarkWare STARK verifier** before the convoy `Verifier` records the verdict.

| Component | Status |
|---|---|
| L1 — Hyperledger Besu QBFT, 6 validators | ✅ Working |
| Real StarkWare Starknet cores (1 per swarm, via madara-bootstrapper) | ✅ Deployed on L1 at bring-up |
| L1 convoy contracts (Registry, Verifier, CommandLog) | ✅ Deploy + wired |
| L2 — Madara α + β (v0.9.1), 1 sequencer + 4 followers each | ✅ Both healthy |
| `convoy_protocol` on each L2 | ✅ Declared + deployed |
| 5 drone accounts per swarm | ✅ Deployed + auto-funded |
| **L1→L2 `open_mission` auto-consume (both swarms)** | ✅ **Trustless via the real cores** |
| Per-drone `submit_telemetry` | ✅ Signed by each drone's own key |
| Real StarkWare STARK verifier on L1 (`GpsStatementVerifier_2023_9`) | ✅ **Deployed on Besu, byte-identical to mainnet** |
| Off-chain prover pipeline (Cairo → Stone → EVM proof) | ✅ Working |
| **L2→L1 verdict — `safe_area` proof verified trustlessly on L1** | ✅ **`Verifier.registerSafeProof`, gated on `isValid(factHash)`** |
| Web visualizer | ✅ Static animation |

## Getting started

End-to-end from a fresh clone to both missions live on L2 via the real bridge, in one terminal session.

**Prerequisites** — Docker + Docker Compose v2, git, Python 3.10+, ~16 GB free RAM, and internet on first run (the bootstrapper and Madara images pull from ghcr). Host ports that must be free: `8545`/`8546` (Besu L1 RPC/WS), `19944`–`19948` (Madara alpha + 4 followers), `29944`–`29948` (Madara bravo + 4 followers), `9545`/`9645` (leader pathfinders), `8888` (Dozzle).

### 1. Clone

```bash
git clone --recurse-submodules https://github.com/henriquejdribeiro/naval-convoy-protection.git
cd naval-convoy-protection
```

### 2. Build the cairo-builder image (first time only)

Bundles scarb, starkli, and the `starknet-sierra-compile` / `compute-casm-hash` helpers — all Cairo/Starknet tooling runs inside it, so nothing Cairo-related is installed on the host.

```bash
docker build -t convoy-cairo-builder LAYER2/cairo-builder/
```

### 3. Bring up the stack

```bash
./SIMULATOR/scripts/script1_up.sh            # add --no-debugger to skip the Dozzle log viewer
```

One idempotent command. It:

1. starts the **6-validator Besu QBFT** L1,
2. runs the **madara-bootstrapper twice** — one real Starknet core per swarm (alpha via `ALPHA_RELAY`, bravo via `BRAVO_RELAY`; configs `bootstrap/config.json` + `bootstrap/config-bravo.json`),
3. deploys the L1 convoy contracts (`Registry` bound to both cores, `Verifier`, `CommandLog`),
4. **seeds** each sequencer's genesis (`--devnet` one-shot) then brings the L2 up as **`--sequencer` with L1 sync** — this two-phase boot is required, because `--devnet` creates the predeployed accounts but disables L1 sync, while `--sequencer` runs the L1→L2 messaging worker,
5. starts the 4 `--full` follower drones per swarm + the leader pathfinders + Dozzle (<http://localhost:8888>).

### 4. Compile + deploy the L2 protocol

```bash
# recompile only if you've changed the Cairo source; artifacts are committed
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd)/LAYER2/contracts_cairo/convoy_protocol:/work" -w /work convoy-cairo-builder scarb build

./SIMULATOR/scripts/script2_deploy-l2.sh --swarm both                 # declare + deploy convoy_protocol on both Madaras
./SIMULATOR/scripts/script3_generate-drone-accounts.sh --swarm both   # 10 drone accounts, auto-funded STRK + ETH
./SIMULATOR/scripts/script4_register-missions.sh --swarm both          # commander opens both missions → real L1→L2 bridge
```

`script4_register-missions.sh` is the whole point: `Registry.deploy(mission_id, …)` sends a real `LogMessageToL2` through that swarm's core, and each sequencer's L1 sync **auto-consumes** it (after a 10-block finality wait) and runs `open_mission` on L2. No `open-missions.sh` — the mission opens *only* because the L1 message crossed the bridge.

Confirm it landed:

```bash
sleep 90   # 10-block finality + processing
docker logs convoy-madara-alpha 2>&1 | grep -iE "Processing L1→L2|nonce=" | tail -3
docker logs convoy-madara-bravo 2>&1 | grep -iE "Processing L1→L2|nonce=" | tail -3
```

Both should show `Processing L1→L2 message: … nonce=0`. To read the anchored spec on L2 (returns the 12-felt `MissionSpec`, reverts if not deployed):

```bash
CONV=$(grep CONVOY_PROTOCOL_ADDR_ALPHA .tmp-l2/convoy_l2.env | cut -d= -f2)
MSYS_NO_PATHCONV=1 docker run --rm -i --network convoy-l1 \
  convoy-cairo-builder:latest \
  starkli call "$CONV" get_mission 1 --rpc http://convoy-madara-alpha:9944/rpc/v0.8.1
```

### 5. Run a mission

Generate per-drone telemetry — the "world" producing ground-truth sweeps — then have a drone submit its sweep to L2. Each drone **signs and submits from inside its own signer machine** (`convoy-machine-<swarm>-<N>`): the STARK-curve key is born in the machine's Docker volume via `starkli signer keystore new` and never touches the host.

```bash
python3 SIMULATOR/scripts/script5_generate-mission.py --scenario both-safe --output-dir .tmp-l2/missions/

# submit one drone's sweep — signs H = Pedersen(cells, nonce) in the machine, then invokes submit_telemetry
./SIMULATOR/scripts/script6_submit-telemetry.sh bravo 3 .tmp-l2/missions/both-safe/bravo_3.json
```

`script6_submit-telemetry.sh` is a keyless orchestrator: it `docker exec`s into `convoy-machine-bravo-3` to (a) sign the telemetry commitment and (b) `starkli invoke submit_telemetry`. The contract's identity gate accepts the tx only because the machine's account is the one registered for `(mission 2, drone 3)` — see §4.

Scenarios (see [`SIMULATOR/scripts/script5_generate-mission.py`](SIMULATOR/scripts/script5_generate-mission.py)): `both-safe`, `both-unsafe`, `mixed`, `alpha-dropout-vanish`, `alpha-dropout-midflight`, `dual-dropout`.

> **Per-drone machines** are currently provisioned for the spike drone `bravo-3`; templating to all 10 is in progress. When all five drones in a swarm land SAFE, `convoy_protocol` emits `MissionSafe` and fires `send_message_to_l1_syscall` with `[mission_id, n_drones]`.

### 6. Prove the telemetry and verify on L1

The proof is generated **from the telemetry the drone actually submitted to L2** — not a fixture. `fetch_l2_cells.py` reads the signed cells + nonce + public key + signature back out of `convoy_protocol`; the prover re-derives `H = Pedersen(cells, nonce)`, verifies the drone's ECDSA signature **in-circuit**, and produces a Stone STARK proof. `convoy-submitter` then verifies that proof on the **genuine StarkWare `GpsStatementVerifier`** (deployed on Besu by `script1_up.sh`, byte-identical to Ethereum mainnet) and records the verdict via `registerSafeProof`.

```bash
CONV=$(grep CONVOY_PROTOCOL_ADDR_BRAVO .tmp-l2/convoy_l2.env | cut -d= -f2)

# 1. fetch the drone's SIGNED telemetry from L2 into the prover's input
MSYS_NO_PATHCONV=1 docker exec convoy-prover-api-bravo \
  python3 /app/fetch_l2_cells.py \
    --rpc http://convoy-madara-bravo:9944/rpc/v0.8.1 \
    --contract "$CONV" --mission_id 2 --drone-id 3 \
    --output /proofs/l2_input.json

# 2. trigger the prover on that input
MSYS_NO_PATHCONV=1 docker exec convoy-prover-api-bravo \
  sh -c 'echo "input=/proofs/l2_input.json tag=bravo3" > /proofs/prove_trigger'

# 3. watch the pipeline (the Stone prove takes a few minutes)
docker logs -f convoy-prover-api-bravo
```

Expected output — cairo execution, the Stone prove, and `convoy-submitter`'s four StarkWare phases, ending in the convoy verdict:

```
Step 2b: stone-cli prove-bootloader   Created proof at proof.json   proof bytes: ~980K
Step 4:  stone-cli verify             Verification successful! PASSED
Phase 1: trace Merkle commits         ✓ Trace 0/1/2
Phase 2: FRI commits                  ✓ FRI 0..7
Phase 3: memory pages                 ✓ memory page 0
Phase 4a: verifyProofAndRegister      ✓   ← STARK proof verified on L1 by the real StarkWare verifier
Phase 4b: registerSafeProof           ✓   ← mission 2, drone 3 → verdict SAFE
PIPELINE COMPLETE
```

**Phase 4a** is the trustless verification: the real StarkWare `GpsStatementVerifier` re-checks every Merkle/FRI/OODS constraint and registers the proof's fact on-chain. **Phase 4b** gates the convoy verdict on that fact **and** the drone's registered public key — a SAFE result is unforgeable, because no relay can register it without (a) a STARK proof the verifier accepts and (b) the in-proof ECDSA binding it to the drone whose key signed the telemetry on L2.

The proof, its Ethereum-serialized form, and metadata are written under the prover's `/proofs` volume (`proof.json`, `evm_proof.json`, `proof_meta.json`).

### 7. Teardown

```bash
docker compose --project-directory . -f LAYER1/docker-compose.l1.yml -f LAYER2/docker-compose.l2.yml \
    --profile l2 --profile seed --profile proving --profile proving-direct --profile deploy \
    down -v --remove-orphans
docker compose -f SIMULATOR/debugger/docker-compose.yml down -v --remove-orphans
```

## Drone telemetry — what `script6_submit-telemetry.sh` does

Takes a swarm, a drone id (1..5), and a JSON file with the four per-cell arrays (`cells_x`, `cells_y`, `cells_p_contact`, `cells_ts`). It loads the matching drone keystore, serialises the arrays into starkli calldata, and fires `submit_telemetry` **signed by the drone's own key** — so `get_caller_address()` inside the contract resolves to the drone's registered account, satisfying the per-drone authentication check.

For hand-written UNSAFE scenarios, copy [`docs/examples/alpha_drone_3_cells.json`](docs/examples/alpha_drone_3_cells.json) and modify the arrays:

- Drop coverage below 95% → `FAIL_COVERAGE`
- Push one `p_contact` to ≥ 7000 → `FAIL_DETECTION`
- Push one `ts` beyond `ts_start + 360` → `FAIL_TIME`
- Move one `(x, y)` outside the drone's strip → `FAIL_STRIP`

## Ports

| URL | What |
|---|---|
| <http://localhost:8888> | Dozzle log viewer (grouped by drone) |
| <http://localhost:8000> | Web visualiser (`python -m http.server` in `SIMULATOR/webapp/`) |

## License

Apache-2.0 — see `LICENSE`.

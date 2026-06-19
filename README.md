# Naval Convoy Protection

## Where each layer's contracts live

### L1 (shared by both swarms)

| Contract | Source | What it does |
|---|---|---|
| `StarknetCoreStub` | [contracts/src/StarknetCoreStub.sol](contracts/src/StarknetCoreStub.sol) | Minimal L1↔L2 message bridge — same interface as StarkWare's real `StarknetCore`, gutted of cryptographic checks for dev use |
| `Registry` | [contracts/src/Registry.sol](contracts/src/Registry.sol) | Stores per-mission specs (zone geometry, thresholds), per-drone verdicts, per-mission `missionSafe` aggregate |
| `Verifier` | [contracts/src/Verifier.sol](contracts/src/Verifier.sol) | Application-layer STARK-proof checker + Registry bookkeeping orchestrator |
| `CommandLog` | [contracts/src/CommandLog.sol](contracts/src/CommandLog.sol) | Append-only log of convoy-advance orders; reverts unless both missions are SAFE and caller is commander |
| StarkWare verifier stack | [contracts/lib/starkware-mainnet/](contracts/lib/starkware-mainnet/) | 17 vendored mainnet-source contracts: `GpsStatementVerifier`, `CpuFrilessVerifier`, `MerkleStatementContract`, `FriStatementContract`, `MemoryPageFactRegistry`, `CpuOods`, `CairoBootloaderProgram`, + 10 periodic-column constant contracts |

### L2 (one deployment per swarm, on different Madara chains)

| Contract | Source | Per-swarm |
|---|---|---|
| `convoy_protocol` (Cairo 1) | [cairo/convoy_protocol/src/lib.cairo](cairo/convoy_protocol/src/lib.cairo) | Same source, declared and deployed independently on each Madara — different storage state, different address |
| 5× drone OZ accounts | Madara devnet's pre-declared OZ class | One ContractAddress per drone, registered in `convoy_protocol.open_mission(spec, drone_addresses)` |
| Predeclared on Madara | UDC, ETH/STRK ERC20, OZ Account class, 10 pre-funded accounts | Standard Madara devnet genesis |

### Off-chain (out of the proof-of-record path)

| Tool | Source | What it does |
|---|---|---|
| `convoy-cairo-builder` Docker image | [infrastructure/cairo-builder/](infrastructure/cairo-builder/) | scarb 2.11.4, starkli 0.4.1, `starknet-sierra-compile` v2.12.3, `compute-casm-hash` (custom) — together bridge the version gap between scarb's CASM emit and Madara's CASM hash function |
| `scripts/deploy-l2.sh` | [scripts/deploy-l2.sh](scripts/deploy-l2.sh) | Declares + deploys `convoy_protocol` to both Madaras |
| `scripts/generate-drone-accounts.sh` | [scripts/generate-drone-accounts.sh](scripts/generate-drone-accounts.sh) | Generates 5 fresh keypairs per swarm, deploys OZ account contracts on each Madara via UDC signed by account #1 |

## Project status

This is an in-progress thesis project. The architecture diagram above shows the **target state**; not every box is wired end-to-end yet.

| Component | Status |
|---|---|
| L1 chain (6 ships, Clique PoA, mesh) | ✅ Working |
| L1 contracts (StarknetCoreStub, Registry, Verifier, CommandLog) | ✅ Compile + deploy |
| StarkWare verifier stack on L1 | ✅ Deploys (note: deploy-script address-prediction quirk under audit) |
| L2 chains (Madara α + β, v0.9.1) | ✅ Both come up healthy |
| `convoy_protocol` contract on each L2 | ✅ Declared + deployed |
| 5 fresh OZ drone accounts per swarm | ✅ Deployed via UDC signed by account #1 |
| Mission-open on L2 (`open_mission_local`) | ✅ Direct-invoke entry point + `scripts/open-missions.sh` wrapper |
| Per-drone `submit_telemetry` invokes | ✅ `scripts/submit-telemetry.sh <swarm> <drone_id> <cells.json>` signs with the drone's keystore |
| L1 `Verifier.sol` rewrite for L2 messages | ⏳ Pending |
| `generate-mission.py` rewrite (full scenarios) | ⏳ Pending — hand-written cells.json works today (see `docs/examples/`) |
| Off-chain prover pipeline (SNOS → Stone → L1) | ⏳ Phase 3.a shortcut deprecated; per-block L2 proof flow needs implementing |
| Web visualizer | ✅ Static animation (not a live dashboard) |

## Getting started

End-to-end from a fresh clone to a finalised `MissionSafe` on L1, in one terminal session.

**Prerequisites** — Docker + Docker Compose v2, git, Python 3.10+, ~16 GB free RAM, and these host ports unused: `8888` (Dozzle), `18545` (L1 RPC), `18546` (L1 WS), `19944`–`19948` (Madara alpha + 4 followers), `29944`–`29948` (Madara bravo + 4 followers), `9545` (pathfinder alpha-1), `9645` (pathfinder bravo-1).

### 1. Clone

```bash
git clone https://github.com/henriquejdribeiro/naval-convoy-protection.git
cd naval-convoy-protection
```

No submodules. The StarkWare evm-verifier ([`contracts/lib/starkware-mainnet/`](contracts/lib/starkware-mainnet/), patched per [`PATCH.md`](contracts/lib/starkware-mainnet/PATCH.md)) and the zksecurity stark-evm-adapter ([`vendor/stark-evm-adapter/`](vendor/stark-evm-adapter/)) are vendored in-tree so the cryptographic stack stays bit-reproducible without third-party hosting.

### 2. Build the cairo-builder image (first time only)

This image bundles scarb 2.11.4, starkli 0.4.1, a custom `starknet-sierra-compile` 2.12.3, and the `compute-casm-hash` helper. All Cairo/Starknet tooling runs inside it, so you don't install anything Cairo-related on the host.

```bash
docker build -t convoy-cairo-builder infrastructure/cairo-builder/
```

### 3. Bring up the stack

```bash
./scripts/up.sh
```

One command, idempotent. Brings up: 6 L1 geth ships → L1 contracts (skipped if already deployed) → 10 Madara nodes (5 per swarm: 1 sequencer + 4 `--full` follower drones) → 2 leader pathfinder archives → Dozzle log viewer at <http://localhost:8888>.

Healthcheck-gated. Pass `--no-debugger` to skip Dozzle.

### 4. Compile + deploy the L2 protocol

```bash
docker run --rm -v "$(pwd)/cairo/convoy_protocol:/work" -w /work convoy-cairo-builder scarb build
./scripts/deploy-l2.sh                              # declares + deploys convoy_protocol on both Madaras
./scripts/generate-drone-accounts.sh --swarm both   # 10 OZ accounts + account.json + auto-fund STRK/ETH
./scripts/register-missions.sh                      # anchors both missions on L1 + fires LogMessageToL2
./scripts/open-missions.sh                          # opens both missions on L2 (dev fallback for the bridge)
```

`generate-drone-accounts.sh` handles three previously-manual steps in one pass: writes `account.json` next to each drone's `keystore.json`, funds STRK + ETH from the deployer, and uses explicit on-chain nonce polling so the funding txs never race.

### 5. Run a mission

Pick a scenario, generate per-drone telemetry, fire all 10 submissions:

```bash
python3 scripts/generate-mission.py --scenario both-safe --output-dir .tmp-l2/missions/

for swarm in alpha bravo; do
    for did in 1 2 3 4 5; do
        f=.tmp-l2/missions/both-safe/${swarm}_${did}.json
        [ -f "$f" ] && ./scripts/submit-telemetry.sh "$swarm" "$did" "$f"
    done
done
```

Available scenarios (see [`scripts/generate-mission.py`](scripts/generate-mission.py)): `both-safe`, `both-unsafe`, `mixed`, `alpha-dropout-vanish`, `alpha-dropout-midflight`, `dual-dropout`. Dropout scenarios intentionally OMIT the affected drone's cells.json — the loop above silently skips missing files so absent telemetry is just absent (modelling real loss-of-comms).

When the 5th SAFE submission lands in a swarm, the L2 contract emits `MissionSafe` and fires `send_message_to_l1_syscall` with payload `[mission_id, n_drones]`. The message is visible in the tx's `messages_sent` field. To deliver it to L1 (dev fallback for settlement):

```bash
./scripts/relay-l2-messages.sh
```

After that, on L1: `Registry.missionSafe(mission_id) == true` for each completed swarm.

### 6. Teardown

```bash
docker compose -f docker-compose.l1.yml -f docker-compose.l2.yml \
    --profile l2 --profile proving --profile proving-direct --profile deploy \
    down -v --remove-orphans
docker compose -f debugger/docker-compose.yml down -v --remove-orphans
docker network rm convoy-l1 2>/dev/null || true
```

> ℹ️ **L1→L2 bridge status** — `register-missions.sh` correctly emits the `LogMessageToL2` event on L1 (verified end-to-end: the message hash is queued in `StarknetCoreStub.l1ToL2Messages`, the payload is the canonical Cairo Serde for `open_mission(spec, drone_addresses)`). Madara v0.9.1 however does NOT consume that message in our setup — the L1-polling code path stays inactive against the barebones stub (0 RPC requests observed; 0 L1-related log lines). Until we identify the stub-compatibility tripwire (or replace the stub with real `Starknet.sol`), `open-missions.sh` is the runtime delivery path.

Each step writes outputs into `deployments/` (L1) or `.tmp-l2/` (L2). The deploy log files name every deployed address.

### Drone telemetry — what `submit-telemetry.sh` does

The script takes a swarm, a drone id (1..5), and a JSON file with the four per-cell arrays (`cells_x`, `cells_y`, `cells_p_contact`, `cells_ts`). It loads the matching drone keystore from `.tmp-l2/drones/<swarm>/<drone_id>/`, serialises the arrays into starkli calldata, and fires `submit_telemetry` **signed by the drone's own key** — so `get_caller_address()` inside the contract resolves to the drone's registered account, satisfying the per-drone authentication check.

For hand-written UNSAFE scenarios beyond what `generate-mission.py` ships, copy [`docs/examples/alpha_drone_3_cells.json`](docs/examples/alpha_drone_3_cells.json) and modify the arrays:

- Drop coverage below 95% → `FAIL_COVERAGE`
- Push one `p_contact` to ≥ 7000 → `FAIL_DETECTION`
- Push one `ts` beyond `ts_start + 360` → `FAIL_TIME`
- Move one `(x, y)` outside the drone's strip → `FAIL_STRIP`

## Ports

| URL | What |
|---|---|
| <http://localhost:8000> | Web visualiser (`python -m http.server` in `webapp/`) |

## Technology stack

| Layer | Component | Pinned version |
|---|---|---|
| L1 chain | Geth (Clique PoA, 6 validators) | `ethereum/client-go:v1.10.17` |
| L1 contracts | Solidity + Foundry | `^0.8.20` (convoy), `^0.6.12` (vendored StarkWare) |
| L2 sequencer | Madara | `v0.9.1` (cairo-lang-sierra-to-casm 2.12.3) |
| L2 indexer | Pathfinder | `v0.21.3` |
| Cairo contract | Cairo 1 (Sierra 1.7.0) | scarb 2.11.4 |
| L2 tooling | starkli + custom `starknet-sierra-compile` + `compute-casm-hash` | 0.4.1 + cairo-lang 2.12.3 |
| Off-chain prover (when wired) | Stone (Atlantic mock) | via `ghcr.io/madara-alliance/orchestrator:nightly` |
| Visualisation | Vanilla JS + SVG (no framework) | — |

## License

Apache-2.0 — see `LICENSE`.

## Provenance

This project's architecture derives from the author's Master's thesis at Instituto Superior Técnico (2026):

> **Modular blockchain architectures applied to drone swarms with low computational resources**
> *Execution of smart contracts and analysis of consensus time*

The repository is a standalone mission archetype, with its own contracts, container topology, and visualisation.

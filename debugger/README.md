# debugger/ — browser log viewer for the 24 convoy nodes

```bash
docker compose -f debugger/docker-compose.yml up -d
# open http://localhost:8888
```

The sidebar lists the 24 nodes that make up the fleet:

| Layer | Nodes |
|---|---|
| L1 (geth, 6)               | `ship-a` `ship-b` `ship-c` `ship-d` `ship-e` `ship-f` |
| Drone 1 alpha (leader)     | `madara-alpha` (sequencer) + `pathfinder-alpha-1` (archive for SNOS) + `snos-alpha` + `orchestrator-alpha` + `prover-api-alpha` |
| Drones 2..5 alpha          | `madara-alpha-2` `…-3` `…-4` `…-5` (Madara `--full` mode) |
| Drone 1 bravo (leader)     | `madara-bravo` + `pathfinder-bravo-1` + `snos-bravo` + `orchestrator-bravo` + `prover-api-bravo` |
| Drones 2..5 bravo          | `madara-bravo-2` `…-3` `…-4` `…-5` (Madara `--full` mode) |

Each drone in a swarm runs its own onboard L2 node. The leader (drone 1)
hosts the sequencer + archive pathfinder + proving pipeline; followers
run Madara in `--full` mode, syncing from the leader sequencer and
relaying tx submissions back to it. Followers run with
`--l1-sync-disabled` since only the leader settles state to L1.

Click one for a live tail, Ctrl/Cmd-click several for a merged stream.
Search across the whole stack from the search box at the top.

Stop the viewer:

```bash
docker compose -f debugger/docker-compose.yml down
```

Bring the convoy stack up first with the standard
`docker compose -f docker-compose.l1.yml -f docker-compose.l2.yml ...`
commands from the top-level README — Dozzle only shows containers
that are already running.

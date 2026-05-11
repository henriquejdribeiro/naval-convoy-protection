// ============================================================================
// Transaction flow diagram — animated overlay on the same architecture
// layout as "Architecture at a glance". 24 messages walk through one full
// mission cycle (both lanes shown in parallel). Click play / next / prev.
// Each step highlights the active container(s) and draws an arrow between
// them; the right-hand side panel shows the contract endpoint, payload,
// authentication, and trust-boundary detail for the current step.
// ============================================================================

const SVG_NS  = 'http://www.w3.org/2000/svg';
const XLINK_NS = 'http://www.w3.org/1999/xlink';

// ── Architecture layout (mirrors architecture-diagram.js) ──────────────────
// VB_W slightly wider than the architecture diagram's 2580 — L2 banners are
// pushed outward to give 170px gaps to the inner ships, leaving room for
// step labels on the radio-dispatch arrows (steps 4 and 24).
const VB_W = 2600;
const VB_H = 760;

const SHIP_W = 200, SHIP_H = 90;
const CMDR_W = 200, CMDR_H = 90;
const L2_W   = 720, L2_H   = 175;
const DRONE_W = 90, DRONE_H = 50;

const HEADER_H = 30;
const CARD_PAD = 8;
const H_CARD_W = 110, H_CARD_H = 100, H_CARD_GAP = 14;
const H_ICON   = 26;
const V_CARD_H = 38, V_ICON = 20, V_CARD_GAP = 4;

const CONTAINERS = [
  { id: 'A',   kind: 'ship',      name: 'Ship A — Forward',         x: 1200, y: 40,  w: SHIP_W, h: SHIP_H },
  { id: 'L2A', kind: 'l2-alpha',  name: 'L2-Alpha — Madara α drone', x: 30,   y: 158, w: L2_W,   h: L2_H   },
  { id: 'F',   kind: 'ship',      name: 'Ship F — Forward-left',    x: 920,  y: 200, w: SHIP_W, h: SHIP_H },
  { id: 'B',   kind: 'ship',      name: 'Ship B — Forward-right',   x: 1480, y: 200, w: SHIP_W, h: SHIP_H },
  { id: 'L2B', kind: 'l2-bravo',  name: 'L2-Bravo — Madara β drone', x: 1850, y: 158, w: L2_W,   h: L2_H   },
  { id: 'E',   kind: 'ship',      name: 'Ship E — Mid-left',        x: 920,  y: 440, w: SHIP_W, h: SHIP_H },
  { id: 'C',   kind: 'ship',      name: 'Ship C — Mid-right',       x: 1480, y: 440, w: SHIP_W, h: SHIP_H },
  { id: 'D',   kind: 'ship-cmdr', name: 'Ship D — Commander',       x: 1200, y: 600, w: CMDR_W, h: CMDR_H }
];

const HVU_W = 200, HVU_H = 90;
const HVUS = [
  { id: 'HVU-1', x: 1200, y: 200 },
  { id: 'HVU-2', x: 1200, y: 320 },
  { id: 'HVU-3', x: 1200, y: 440 }
];

const SERVICES = {
  'ship': [
    { icon: 'images/ethereum.png', name: 'Geth (Clique PoA)', sub: 'L1 validator node' }
  ],
  'ship-cmdr': [
    { icon: 'images/ethereum.png', name: 'Geth (Clique PoA)', sub: 'L1 validator node' }
  ],
  'l2-alpha': [
    { icon: 'images/madara.png',       name: 'Madara α',     sub: 'Execution Layer',  stage: 'exec'  },
    { icon: 'images/pathfinder.png',   name: 'Starknet Node', sub: 'Pathfinder',      stage: 'exec'  },
    { icon: 'images/madara.png',       name: 'Orchestrator', sub: 'Settlement orch.', stage: 'exec'  },
    { icon: 'images/snos.jpg',         name: 'SNOS',         sub: 'StarkNet OS',      stage: 'prove' },
    { icon: 'images/stone-prover.svg', name: 'Stone Prover', sub: 'STARK Prover',     stage: 'prove' }
  ],
  'l2-bravo': [
    { icon: 'images/madara.png',       name: 'Madara β',     sub: 'Execution Layer',  stage: 'exec'  },
    { icon: 'images/pathfinder.png',   name: 'Starknet Node', sub: 'Pathfinder',      stage: 'exec'  },
    { icon: 'images/madara.png',       name: 'Orchestrator', sub: 'Settlement orch.', stage: 'exec'  },
    { icon: 'images/snos.jpg',         name: 'SNOS',         sub: 'StarkNet OS',      stage: 'prove' },
    { icon: 'images/stone-prover.svg', name: 'Stone Prover', sub: 'STARK Prover',     stage: 'prove' }
  ]
};

// ── Lifeline → architecture target ─────────────────────────────────────────
// L1 contracts (Registry, Verifier, CommandLog) live in EVERY ship's Geth
// node — the PoA chain is the collective. We anchor them visually on the
// L1 cluster (all 6 ships pulse). Ship B is the bravo lane's primary relay,
// so it gets its own lifeline. Ship D is the commander.
function targetOf(id) {
  switch (id) {
    case 'D':          return { kind: 'container', id: 'D' };       // commander
    case 'ShipB':      return { kind: 'container', id: 'B' };       // bravo relay
    case 'ShipF':      return { kind: 'container', id: 'F' };       // alpha relay
    case 'L1Cluster':  return { kind: 'l1-cluster', anchor: 'A' };  // all 6 ships
    case 'L2Banner':   return { kind: 'container', id: 'L2B' };     // whole L2-B
    case 'L2BannerA':  return { kind: 'container', id: 'L2A' };     // whole L2-A
    case 'Drone':      return { kind: 'drone-anchor', l2: 'L2B' };  // off-chain (β)
    case 'DroneA':     return { kind: 'drone-anchor', l2: 'L2A' };  // off-chain (α)
    case 'Madara':     return { kind: 'l2-svc', l2: 'L2B', i: 0 };
    case 'MadaraA':    return { kind: 'l2-svc', l2: 'L2A', i: 0 };
    case 'Pathfinder': return { kind: 'l2-svc', l2: 'L2B', i: 1 };
    case 'PathfinderA':return { kind: 'l2-svc', l2: 'L2A', i: 1 };
    case 'Orch':       return { kind: 'l2-svc', l2: 'L2B', i: 2 };
    case 'OrchA':      return { kind: 'l2-svc', l2: 'L2A', i: 2 };
    case 'SNOS':       return { kind: 'l2-svc', l2: 'L2B', i: 3 };
    case 'SNOSA':      return { kind: 'l2-svc', l2: 'L2A', i: 3 };
    case 'Stone':      return { kind: 'l2-svc', l2: 'L2B', i: 4 };
    case 'StoneA':     return { kind: 'l2-svc', l2: 'L2A', i: 4 };
    case 'HVUs':       return { kind: 'hvu-cluster' };
    default: return null;
  }
}

// Resolve a target to an SVG bounding box { x, y, w, h, cx, cy }
function targetBox(t) {
  if (t.kind === 'container') {
    const c = CONTAINERS.find(x => x.id === t.id);
    return { x: c.x, y: c.y, w: c.w, h: c.h, cx: c.x + c.w / 2, cy: c.y + c.h / 2, _container: c };
  }
  if (t.kind === 'l1-cluster') {
    // Highlight all six ships as the L1 cluster, but the arrow anchor uses
    // a single ship (the master) so arrows don't get tangled.
    const a = CONTAINERS.find(x => x.id === t.anchor);
    return { x: a.x, y: a.y, w: a.w, h: a.h, cx: a.x + a.w / 2, cy: a.y + a.h / 2, _cluster: true, _label: t.label };
  }
  if (t.kind === 'l2-svc') {
    const c = CONTAINERS.find(x => x.id === t.l2);
    const innerY = HEADER_H + 8;
    const totalW = 5 * H_CARD_W + 4 * H_CARD_GAP;
    const xStart = (c.w - totalW) / 2;
    const tileX = c.x + xStart + t.i * (H_CARD_W + H_CARD_GAP);
    const tileY = c.y + innerY;
    return { x: tileX, y: tileY, w: H_CARD_W, h: H_CARD_H, cx: tileX + H_CARD_W / 2, cy: tileY + H_CARD_H / 2, _container: c };
  }
  if (t.kind === 'drone-anchor') {
    // Virtual point ABOVE the L2 banner, slightly to the right of the
    // Madara service tile. The drone is off-chain so it lives "above"
    // the on-chain L2 stack; the arrow hooks down into Madara from here.
    // The L2 banner itself gets the active highlight (since L2 = drone).
    const c = CONTAINERS.find(x => x.id === t.l2);
    const innerY = HEADER_H + 8;
    const totalW = 5 * H_CARD_W + 4 * H_CARD_GAP;
    const xStart = (c.w - totalW) / 2;
    const madaraCx = c.x + xStart + H_CARD_W / 2;
    const x = madaraCx + 80;     // 80px right of Madara (hook curves left)
    const y = c.y - 48;          // 48px above banner top
    return { x: x - 6, y: y - 6, w: 12, h: 12, cx: x, cy: y };
  }
  if (t.kind === 'hvu-cluster') {
    // Centroid of the three HVU tiles in the convoy interior
    const cx = 1200 + HVU_W / 2;
    const cy = HVUS[1].y + HVU_H / 2;
    return { x: 1200, y: HVUS[0].y, w: HVU_W, h: (HVUS[2].y + HVU_H) - HVUS[0].y, cx, cy };
  }
  return null;
}

// ── Messages — full mission cycle for the L2-Bravo lane ────────────────────
// Mirrors the 8-phase sequence in the convoy simulation. L2-Alpha follows
// the same shape with ship F as the relay instead of ship B.
//
// Phase 1 (1-4):   Mission deploy + L1 PoA propagation + radio dispatch to L2
// Phase 2 (5-7):   Drone sweep + commitment + block sealing
// Phase 3 (8):     Pathfinder indexes the block
// Phase 4 (9-18):  Proof-generation pipeline (Orch → SNOS → Stone)
// Phase 5 (19-21): Relay back to L1 + on-chain FRI verification + verdict
// Phase 6 (22-23): Commander D activates advance + PoA fan-out + ConvoyAdvance event
// Phase 7 (24):    Radio bridge — advance command to both L2 drones
const MESSAGES = [
  // ───────── Phase 1 — Mission deploy & L2 dispatch ─────────
  {
    step: 1, kind: 'self', on: 'D',
    label: 'write deploy(EX-011) tx',
    sig: 'Registry.deploy(MissionSpec spec) external onlyCommander returns (uint256 missionId)',
    payload: [
      { f: 'spec.area_hash',    t: 'bytes32 — Poseidon hash of polygon vertices' },
      { f: 'spec.coverage_min', t: 'uint16 — permille (950 = ≥ 95% cells)' },
      { f: 'spec.p_min',        t: 'uint16 — basis points (7000 = p_contact ≥ 0.7)' },
      { f: 'spec.time_window',  t: 'uint64 — seconds (360 = 6 min)' }
    ],
    auth: 'secp256k1 ECDSA. D signs the L1 tx with the commander key (separate keystore entry from the regular ship key). The onlyCommander modifier on Registry.deploy checks msg.sender against the stored commander address.',
    boundary: 'commander → L1',
    crosses: false,
    desc: 'Phase 1.a — Ship D writes the deploy tx onto its own Geth node. The tx names mission EX-011 (Bravo lane) and includes the full MissionSpec.'
  },
  {
    step: 2, kind: 'msg', from: 'D', to: 'L1Cluster',
    label: 'PoA fan-out → Registry stores + emits MissionDeployed',
    sig: '(Clique PoA peer broadcast) → Registry.sol state write → emit MissionDeployed(missionId, drone_id, spec)',
    payload: [
      { f: 'block N',  t: 'sealed PoA block including the deploy tx' },
      { f: 'signer',   t: 'rotating among the 6 ship validators (EIP-225)' },
      { f: 'state Δ',  t: 'Registry storage updated with (missionId → MissionSpec)' },
      { f: 'event',    t: 'MissionDeployed(uint256 indexed missionId, uint256 indexed drone_id, MissionSpec spec)' },
      { f: 'indexed',  t: 'drone_id is indexed so off-chain subscribers (relay ships) can filter on it' }
    ],
    auth: 'secp256k1 — block sealer signs the block header. Other validators verify the signature against the pre-baked validator list in genesis.json. The deploy tx executing on every node is what causes the Registry state write + event emission, atomically with block inclusion.',
    boundary: 'L1 internal',
    crosses: false,
    desc: 'Phase 1.b — The deploy tx propagates to all 6 ships via Clique PoA peer fan-out. As the same block executes on every Geth node, Registry.sol stores the spec and emits MissionDeployed. After this block, A, B, C, D, E, F all see the same Registry state and the same event log.'
  },
  {
    step: 3, kind: 'self', on: 'ShipB',
    also: ['F'],     // ship F also acts in parallel on the alpha lane
    label: 'event filter dispatches mission to relay (B for β, F for α)',
    sig: 'web3.eth.subscribe("logs", { address: Registry, topics: [MissionDeployed, missionId, drone_id] })',
    payload: [
      { f: 'B\'s subscription', t: 'topic[0]=MissionDeployed, topic[2]=β  →  B\'s onMission(spec) handler runs' },
      { f: 'F\'s subscription', t: 'topic[0]=MissionDeployed, topic[2]=α  →  F\'s onMission(spec) handler runs' },
      { f: 'A, C, D, E',        t: 'no relay subscription — observe only' },
      { f: 'extracted',         t: 'missionId + drone_id + MissionSpec passed to the matching handler' }
    ],
    auth: 'No cryptographic auth on the read path — Geth\'s event log is local to each node. The relay assignment is enforced by which drone_id each ship\'s orchestrator subscribes to (configured in orchestrator.toml at deployment, not on-chain).',
    boundary: 'L1 internal',
    crosses: false,
    desc: 'Phase 1.c — The smart contract\'s emit in step 2 fires every event subscription that matches. B is configured to listen for drone_id == β and F for drone_id == α; their orchestrator handlers run automatically. This is how the contract "tells" the relay ships they have a job to do — without any direct on-chain call to a specific ship. A, C, D, E have the same Registry state but no relay subscription, so nothing fires.'
  },
  {
    step: 4, kind: 'msg', from: 'ShipB', to: 'L2Banner',
    parallel: [{ from: 'ShipF', to: 'L2BannerA' }],
    label: 'B→L2-B / F→L2-A radio dispatch',
    sig: 'POST /l2-{bravo|alpha}/admin/deploy_mission  body: { spec, missionId }  (over convoy radio link)',
    payload: [
      { f: 'spec',     t: 'MissionSpec — relayed verbatim' },
      { f: 'missionId',      t: 'uint256 — same mission id as on L1 (EX-010 for α, EX-011 for β)' },
      { f: 'lane (β)', t: 'B → L2-B with missionId = EX-011' },
      { f: 'lane (α)', t: 'F → L2-A with missionId = EX-010' }
    ],
    auth: 'TLS + relay-to-L2 mutual auth (Phase 3 detail). Ship B\'s relay key is whitelisted on Madara β; ship F\'s on Madara α. Each is the only off-chain dispatcher for its lane.',
    boundary: 'L1 → L2 (radio handoff)',
    crosses: true,
    desc: 'Phase 1.c — Both relay ships dispatch in parallel: B forwards EX-011 to L2-B over the convoy radio link, F forwards EX-010 to L2-A. Drones α and β now have their respective mission specs.'
  },

  // ───────── Phase 2 — Drone sweep + commitment ─────────
  {
    step: 5, kind: 'self', on: 'Madara',
    parallel: [{ on: 'MadaraA' }],
    label: 'submit_telemetry(...)  ×N  [drone-signed]',
    sig: 'fn submit_telemetry(mission_id: u128, cells: Array<TelemetryCell>) external',
    payload: [
      { f: 'mission_id',           t: 'u128 — same missionId the dispatch carried' },
      { f: 'cells: Array<...>',    t: 'one tx per cell, dozens per sweep' },
      { f: '  cell.x, cell.y',     t: 'u16 — cell index in the area grid' },
      { f: '  cell.p_contact',     t: 'u16 — basis points (max-prob hit, 0–10000)' },
      { f: '  cell.ts',            t: 'u64 — unix seconds' }
    ],
    auth: 'Stark-curve ECDSA. Drone β signs each L2 tx hash with its private key (keystore/bravo.json). The OZ account contract on Madara recovers the public key and verifies it before letting the tx execute.',
    boundary: 'drone → L2',
    crosses: true,
    desc: 'Phase 2 — As drone β sweeps the right corridor, it sends one submit_telemetry tx per cell. Signature proves it\'s the drone speaking; the data\'s correctness is enforced inside the proof program (step 14).'
  },
  {
    step: 6, kind: 'self', on: 'Madara',
    parallel: [{ on: 'MadaraA' }],
    label: 'submit_sweep_commitment(missionId, H_β | H_α)  [drone-signed]',
    sig: 'fn submit_sweep_commitment(mission_id: u128, h: felt252) external',
    payload: [
      { f: 'mission_id', t: 'u128' },
      { f: 'h',          t: 'felt252 — H_β = Poseidon hash chain over all cells submitted in step 5' }
    ],
    auth: 'Stark-curve ECDSA — same signing path as submit_telemetry. The Cairo contract recomputes Poseidon over the witness cells and reverts if h ≠ Poseidon(cells).',
    boundary: 'drone → L2',
    crosses: true,
    desc: 'Phase 3 — Drone β closes the sweep. H_β is the public commitment that lands on L1 as part of the proof\'s public inputs.'
  },
  {
    step: 7, kind: 'self', on: 'Madara',
    parallel: [{ on: 'MadaraA' }],
    label: 'seal block N',
    sig: '(internal) Madara sequencer block production',
    payload: [
      { f: 'block N',    t: 'sealed Starknet block' },
      { f: 'state diff', t: 'includes the H_β storage write' }
    ],
    auth: 'Sequencer signs the block with its own Madara identity key. No STARK yet — that\'s generated by the orchestrator pipeline below.',
    boundary: 'L2 internal',
    crosses: false,
    desc: 'Phase 3 — Madara β bundles the telemetry + commitment txs into block N, executes them, computes the state diff, seals.'
  },

  // ───────── Phase 3 — Indexing ─────────
  {
    step: 8, kind: 'msg', from: 'Madara', to: 'Pathfinder',
    parallel: [{ from: 'MadaraA', to: 'PathfinderA' }],
    label: 'feeder gateway sync',
    sig: 'GET /feeder_gateway/get_block?blockNumber=N',
    payload: [
      { f: 'block',      t: 'sealed Starknet block N' },
      { f: 'state_diff', t: 'storage updates' }
    ],
    auth: 'No cryptographic auth — internal HTTP between L2 services on the same Docker network.',
    boundary: 'L2 internal',
    crosses: false,
    desc: 'Pathfinder pulls block N from Madara, indexes it, exposes via JSON-RPC.'
  },

  // ───────── Phase 4 — Proof generation pipeline ─────────
  {
    step: 9, kind: 'msg', from: 'Orch', to: 'Pathfinder',
    parallel: [{ from: 'OrchA', to: 'PathfinderA' }],
    label: 'starknet_getBlockWithTxs(N)',
    sig: 'JSON-RPC: starknet_getBlockWithTxs({"block_number": N})',
    payload: [{ f: 'block_number', t: 'u64' }],
    auth: 'No auth — internal JSON-RPC.',
    boundary: 'L2 internal',
    crosses: false,
    desc: 'Phase 4 — Orchestrator notices a block with a sweep commitment and pulls it from Pathfinder.'
  },
  {
    step: 10, kind: 'msg', from: 'Pathfinder', to: 'Orch',
    parallel: [{ from: 'PathfinderA', to: 'OrchA' }],
    label: 'block + state_diff',
    sig: '(JSON-RPC response)',
    payload: [
      { f: 'block',        t: 'header + tx list' },
      { f: 'state_diff',   t: 'storage updates' },
      { f: 'class hashes', t: 'contracts touched (for SNOS replay)' }
    ],
    auth: 'No signature.', boundary: 'L2 internal', crosses: false,
    desc: 'Pathfinder returns everything SNOS needs to replay the block.'
  },
  {
    step: 11, kind: 'msg', from: 'Orch', to: 'SNOS',
    parallel: [{ from: 'OrchA', to: 'SNOSA' }],
    label: 'request proof input(block N)',
    sig: 'snos.generate_pie(block, state_diff, class_hashes)',
    payload: [
      { f: 'block',      t: 'block N' },
      { f: 'state_diff', t: 'storage updates' },
      { f: 'os_input',   t: 'StarkNet OS input — bootloader config' }
    ],
    auth: 'No external signature — local IPC/RPC.',
    boundary: 'L2 internal', crosses: false,
    desc: 'Orchestrator hands the block to SNOS and asks for a Cairo program input (PIE).'
  },
  {
    step: 12, kind: 'msg', from: 'SNOS', to: 'Pathfinder',
    parallel: [{ from: 'SNOSA', to: 'PathfinderA' }],
    label: 'state + receipts queries',
    sig: 'JSON-RPC: starknet_getStateUpdate, starknet_getTransactionReceipt, starknet_call',
    payload: [{ f: '(multiple calls)', t: 'fetches receipts, storage proofs, class definitions' }],
    auth: 'No auth.', boundary: 'L2 internal', crosses: false,
    desc: 'SNOS needs more than the block — it queries Pathfinder for full state context.'
  },
  {
    step: 13, kind: 'msg', from: 'Pathfinder', to: 'SNOS',
    parallel: [{ from: 'PathfinderA', to: 'SNOSA' }],
    label: 'state + receipts',
    sig: '(JSON-RPC responses)',
    payload: [
      { f: 'state_update', t: 'storage proof at block N-1' },
      { f: 'receipts',     t: 'tx receipts for replay validation' },
      { f: 'class defs',   t: 'Sierra/CASM' }
    ],
    auth: 'No signature.', boundary: 'L2 internal', crosses: false,
    desc: 'Pathfinder returns the state context.'
  },
  {
    step: 14, kind: 'self', on: 'SNOS',
    parallel: [{ on: 'SNOSA' }],
    label: 'replay (Cairo VM) — assert SAFE_AREA',
    sig: 'cairo_run(starknet_os.cairo, input=block + state)',
    payload: [
      { f: 'execution trace',   t: 'every Cairo opcode executed' },
      { f: 'memory access log', t: 'reads/writes for FRI proof generation' },
      { f: 'PIE',               t: 'Program-Independent Executable' }
    ],
    auth: 'Cryptographic gate is the Cairo VM constraint system: if any constraint fails (e.g. SAFE_AREA), the replay aborts and no PIE is produced.',
    boundary: 'L2 internal', crosses: false,
    desc: 'SNOS replays block N inside lambdaclass cairo-vm. The SAFE_AREA assertion in safe_area_verify.cairo runs here — if {coverage ≥ 95%, time ≤ 360s, all p_contact < 7000} doesn\'t hold, the replay aborts. No proof can be generated for invalid telemetry.'
  },
  {
    step: 15, kind: 'msg', from: 'SNOS', to: 'Orch',
    parallel: [{ from: 'SNOSA', to: 'OrchA' }],
    label: 'PIE',
    sig: '(returns PIE struct)',
    payload: [
      { f: 'pie',          t: 'Program-Independent Executable' },
      { f: 'public_input', t: 'mission_id, H_β, area_hash, thresholds' }
    ],
    auth: 'No signature.', boundary: 'L2 internal', crosses: false,
    desc: 'SNOS hands the PIE back to the Orchestrator.'
  },
  {
    step: 16, kind: 'msg', from: 'Orch', to: 'Stone',
    parallel: [{ from: 'OrchA', to: 'StoneA' }],
    label: 'send PIE + config',
    sig: 'stone-prover-cli prove --pie <pie.zip> --config <prover.json>',
    payload: [
      { f: 'pie',    t: 'from step 15' },
      { f: 'config', t: 'prover params: field, blowup, FRI queries, security level' }
    ],
    auth: 'No signature — local exec / RPC.',
    boundary: 'L2 internal', crosses: false,
    desc: 'Orchestrator dispatches the PIE to Stone with the prover configuration.'
  },
  {
    step: 17, kind: 'self', on: 'Stone',
    parallel: [{ on: 'StoneA' }],
    label: 'run FRI → π_β | π_α',
    sig: '(internal Stone prover)',
    payload: [
      { f: 'AIR encoding',     t: 'Algebraic Intermediate Representation of Cairo VM trace' },
      { f: 'FRI commit phase', t: 'Reed-Solomon commitments to the trace polynomial' },
      { f: 'FRI query phase',  t: 'random sampling, Merkle decommitments — yields π_β' }
    ],
    auth: 'No signature — the cryptographic gate IS the proof. STARK soundness rests on collision-resistance of the hash and the FRI argument; no trusted setup.',
    boundary: 'L2 internal', crosses: false,
    desc: 'Stone runs the STARK prover over the PIE. Output is π_β — the proof bytes plus public inputs.'
  },
  {
    step: 18, kind: 'msg', from: 'Stone', to: 'Orch',
    parallel: [{ from: 'StoneA', to: 'OrchA' }],
    label: 'π_β | π_α + public inputs',
    sig: '(returns proof bundle)',
    payload: [
      { f: 'π_β',          t: 'proof bytes (~100–500 KB)' },
      { f: 'public_input', t: 'missionId, H_β, area_hash, thresholds, drone_id=β' }
    ],
    auth: 'No signature — the proof itself is the credential.',
    boundary: 'L2 internal', crosses: false,
    desc: 'Stone hands the finished proof back to the Orchestrator.'
  },

  // ───────── Phase 5 — Relay back to L1 + on-chain verification ─────────
  {
    step: 19, kind: 'msg', from: 'Orch', to: 'ShipB',
    parallel: [{ from: 'OrchA', to: 'ShipF' }],
    label: 'hand off π_β to B / π_α to F (radio)',
    sig: 'POST /relay/submit  body: { proof: π_β, public_input, missionId, drone_id=β }',
    payload: [
      { f: 'proof',        t: 'π_β bytes' },
      { f: 'public_input', t: 'from step 18' },
      { f: 'missionId',          t: 'mission id' },
      { f: 'drone_id',     t: 'felt252 — β' }
    ],
    auth: 'Off-chain RPC over the convoy radio link. The relay ship trusts the Orchestrator only insofar as it forwards whatever proof it receives — soundness rests on the on-chain re-check (step 22), not on the relay\'s honesty.',
    boundary: 'L2 → L1 (relay handoff)',
    crosses: true,
    desc: 'Phase 5 — Orchestrator hands the proof bundle to ship B. The proof leaves the L2 perimeter. (L2-Alpha mirrors with ship F.)'
  },
  {
    step: 20, kind: 'self', on: 'ShipB',
    parallel: [{ on: 'ShipF' }],
    label: 'submitProof tx — B for π_β, F for π_α',
    sig: 'Verifier.submitProof(bytes proof, bytes32[] public_inputs, uint256 missionId, uint256 drone_id) external',
    payload: [
      { f: 'proof (β)',     t: 'bytes — π_β  (signed by B)' },
      { f: 'proof (α)',     t: 'bytes — π_α  (signed by F)' },
      { f: 'public_inputs', t: 'bytes32[] — recomputed from each proof\'s public input array' },
      { f: 'missionId',           t: 'uint256 — EX-011 for β, EX-010 for α' },
      { f: 'drone_id',      t: 'uint256 — β or α' }
    ],
    auth: 'secp256k1 ECDSA — each relay signs its own L1 tx envelope. B signs π_β\'s tx, F signs π_α\'s tx. The signature only authenticates "this ship submitted this tx" — proof correctness is checked by the contract logic, not the signature. Relay ships are deliberately not trusted to vouch for proof validity.',
    boundary: 'L1 internal',
    crosses: false,
    desc: 'Phase 5 — In parallel, ship B writes its submitProof tx for π_β onto its Geth node, and ship F writes its submitProof tx for π_α onto its Geth node. Both call Verifier.sol.'
  },
  {
    step: 21, kind: 'msg', from: 'ShipB', to: 'L1Cluster',
    parallel: [{ from: 'ShipF', to: 'L1Cluster' }],
    label: 'PoA fan-out — both proof txs propagate',
    sig: '(Clique PoA peer broadcast)',
    payload: [
      { f: 'block N+k',   t: 'sealed PoA block including B\'s submitProof tx' },
      { f: 'block N+k+1', t: 'sealed PoA block including F\'s submitProof tx (may be same block if same signer slot)' }
    ],
    auth: 'secp256k1 — block sealer signs the header. Same PoA fan-out as step 2.',
    boundary: 'L1 internal',
    crosses: false,
    desc: 'Both submitProof txs propagate to all 6 ships via Clique PoA. As each block executes on every Geth in lockstep, Verifier.submitProof internally runs FRI re-verification (the cryptographic gate — invalid proofs revert here) and writes the SAFE verdict to Registry under (missionId, drone_id). After this step, Registry holds verdict[α] = SAFE and verdict[β] = SAFE on every node.'
  },

  // ───────── Phase 6 — Commander activates advance ─────────
  {
    step: 22, kind: 'self', on: 'D',
    label: 'D sees dual-SAFE → advance(MAX_SPEED) tx',
    sig: 'CommandLog.advance(uint256 speed) external onlyCommander',
    payload: [
      { f: 'verdict_α', t: 'uint8 — SAFE (read from Registry by D\'s orchestrator)' },
      { f: 'verdict_β', t: 'uint8 — SAFE (read from Registry by D\'s orchestrator)' },
      { f: 'speed',     t: 'uint256 — MAX_SPEED constant' }
    ],
    auth: 'secp256k1 ECDSA — D signs the L1 tx with the commander key (separate keystore from the regular ship key). The onlyCommander modifier on CommandLog.advance checks msg.sender against the stored commander address. CommandLog also re-checks Registry to ensure dual-SAFE before accepting the call.',
    boundary: 'L1 internal',
    crosses: false,
    desc: 'Phase 7 — Ship D\'s orchestrator polls Registry. Once it sees both α and β verdicts SAFE for the same mission, D signs an advance(MAX_SPEED) tx with the commander key and writes it to its Geth node. This is the explicit go-ahead from the commander; CommandLog will refuse the call if either verdict is missing.'
  },
  {
    step: 23, kind: 'msg', from: 'D', to: 'L1Cluster',
    label: 'PoA fan-out → CommandLog stores + emits ConvoyAdvance',
    sig: '(Clique PoA peer broadcast) → CommandLog.advance executes → emit ConvoyAdvance(block_number, speed, commander)',
    payload: [
      { f: 'block N+m',    t: 'sealed PoA block including D\'s advance tx' },
      { f: 'state Δ',      t: 'CommandLog stores (block_number, speed, commander) record' },
      { f: 'event',        t: 'ConvoyAdvance(uint256 indexed block_number, uint256 speed, address commander)' }
    ],
    auth: 'secp256k1 — block sealer signs the header. The advance tx itself was signed by D with the commander key. CommandLog.advance re-checks the onlyCommander modifier + dual-SAFE precondition before accepting.',
    boundary: 'L1 internal',
    crosses: false,
    desc: 'D\'s advance tx propagates to all 6 ships. As each Geth executes the tx, CommandLog stores the advance record and emits ConvoyAdvance. After this block, every ship\'s Geth has the same event log. Relays B, F (and D for HVUs) will pick it up via their event subscriptions and bridge it off-chain in the next steps.'
  },

  // ───────── Phase 7 — Radio bridge to drones + HVUs ─────────
  {
    step: 24, kind: 'msg', from: 'ShipB', to: 'L2Banner',
    parallel: [{ from: 'ShipF', to: 'L2BannerA' }],
    label: 'B→L2-B / F→L2-A radio advance',
    sig: 'POST /l2-{bravo|alpha}/admin/advance  body: { event: "ConvoyAdvance", block_number, speed }',
    payload: [
      { f: 'event',        t: 'ConvoyAdvance' },
      { f: 'block_number', t: 'uint256 — L1 block where the advance was recorded' },
      { f: 'speed',        t: 'uint256 — MAX_SPEED' }
    ],
    auth: 'TLS + relay-to-L2 mutual auth (same channel as step 4, opposite direction). No decision-making on B or F — they are pure event-bridges (L1 event → radio frame). The decision was already made by D in step 22 and recorded on L1 in step 24.',
    boundary: 'L1 → L2 (radio)',
    crosses: true,
    desc: 'Phase 8 — Final messages of the cycle. Both relays bridge the L1 advance event over radio to their L2 drones: B → L2-B (drone β), F → L2-A (drone α). A, C, D, E observe the same event in their L1 event log but take no message-level action.'
  }
];

// ───────────────────────────────────────────────────────────────────
// SVG construction
// ───────────────────────────────────────────────────────────────────

function el(name, attrs = {}) {
  const node = document.createElementNS(SVG_NS, name);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, String(v));
  return node;
}

function image(href, x, y, w, h) {
  const img = el('image', { x, y, width: w, height: h, href });
  img.setAttributeNS(XLINK_NS, 'xlink:href', href);
  return img;
}

let overlayLayer = null;  // refreshed every step

function buildSvg() {
  const stage = document.getElementById('tflow-stage');
  if (!stage) return null;

  const svg = el('svg', {
    viewBox: `0 0 ${VB_W} ${VB_H}`,
    class: 'tflow-svg',
    preserveAspectRatio: 'xMidYMid meet'
  });

  const defs = el('defs');

  const pattern = el('pattern', {
    id: 'tflow-grid', width: 30, height: 30, patternUnits: 'userSpaceOnUse'
  });
  pattern.appendChild(el('path', {
    d: 'M 30 0 L 0 0 0 30', fill: 'none',
    stroke: '#1a2436', 'stroke-width': 1
  }));
  defs.appendChild(pattern);

  // Arrowhead — neutral
  const arrow = el('marker', {
    id: 'tflow-arrow-head', viewBox: '0 -5 10 10', refX: 9, refY: 0,
    markerWidth: 8, markerHeight: 8, orient: 'auto'
  });
  arrow.appendChild(el('path', { d: 'M 0 -4 L 9 0 L 0 4 z', fill: '#ffd600' }));
  defs.appendChild(arrow);

  // Arrowhead — trust crossing (orange)
  const arrowCross = el('marker', {
    id: 'tflow-arrow-head-cross', viewBox: '0 -5 10 10', refX: 9, refY: 0,
    markerWidth: 8, markerHeight: 8, orient: 'auto'
  });
  arrowCross.appendChild(el('path', { d: 'M 0 -4 L 9 0 L 0 4 z', fill: '#f97316' }));
  defs.appendChild(arrowCross);

  svg.appendChild(defs);

  const root = el('g', { class: 'tflow-root' });
  svg.appendChild(root);

  // Background grid
  root.appendChild(el('rect', {
    x: 0, y: 0, width: VB_W, height: VB_H, fill: 'url(#tflow-grid)'
  }));

  // L1 PoA ring (faded polygon through ship centres)
  const ships = CONTAINERS.filter(c => c.kind === 'ship' || c.kind === 'ship-cmdr');
  const ringPts = ['A', 'B', 'C', 'D', 'E', 'F']
    .map(id => ships.find(s => s.id === id))
    .map(c => `${c.x + c.w / 2},${c.y + c.h / 2}`).join(' ');
  root.appendChild(el('polygon', {
    points: ringPts,
    fill: 'rgba(79,195,247,0.03)',
    stroke: 'rgba(79,195,247,0.30)',
    'stroke-width': 1.4,
    'stroke-dasharray': '6 5'
  }));

  // HVUs
  for (const h of HVUS) {
    const hg = el('g', { class: 'tflow-hvu', 'data-id': h.id, transform: `translate(${h.x} ${h.y})` });
    hg.appendChild(el('rect', {
      x: 0, y: 0, width: HVU_W, height: HVU_H,
      rx: 6, ry: 6, class: 'tflow-hvu-body'
    }));
    const lbl = el('text', {
      x: HVU_W / 2, y: HVU_H / 2 - 1,
      'text-anchor': 'middle', class: 'tflow-hvu-label'
    });
    lbl.textContent = h.id;
    hg.appendChild(lbl);
    const sub = el('text', {
      x: HVU_W / 2, y: HVU_H / 2 + 16,
      'text-anchor': 'middle', class: 'tflow-hvu-sub'
    });
    sub.textContent = 'off-network';
    hg.appendChild(sub);
    root.appendChild(hg);
  }

  // Containers
  for (const c of CONTAINERS) {
    root.appendChild(buildContainer(c));
  }

  // Overlay layer (cleared and rebuilt on every step change)
  overlayLayer = el('g', { class: 'tflow-overlay' });
  root.appendChild(overlayLayer);

  stage.appendChild(svg);
  return { svg, root };
}

function buildContainer(c) {
  const g = el('g', {
    class: `tflow-container kind-${c.kind}`,
    'data-id': c.id,
    transform: `translate(${c.x} ${c.y})`
  });

  g.appendChild(el('rect', {
    x: 0, y: 0, width: c.w, height: c.h, rx: 8, ry: 8, class: 'tflow-body'
  }));
  g.appendChild(el('rect', {
    x: 0, y: 0, width: c.w, height: HEADER_H, rx: 8, ry: 8, class: 'tflow-header'
  }));
  g.appendChild(el('rect', {
    x: 0, y: HEADER_H - 8, width: c.w, height: 8, class: 'tflow-header'
  }));

  const nameText = el('text', { x: 12, y: 20, class: 'tflow-name' });
  nameText.textContent = c.id.startsWith('L2') ? c.id.replace('L2', 'L2-') : `Ship ${c.id}`;
  g.appendChild(nameText);

  const dockerLogo = image('images/docker.png', c.w - 70, 8, 14, 14);
  dockerLogo.setAttribute('opacity', '0.7');
  g.appendChild(dockerLogo);

  const dockerText = el('text', {
    x: c.w - 12, y: 20, class: 'tflow-docker', 'text-anchor': 'end'
  });
  dockerText.textContent = 'DOCKER';
  g.appendChild(dockerText);

  const services = SERVICES[c.kind] || [];
  const isL2 = c.kind.startsWith('l2-');

  if (isL2) renderHorizontalServices(g, c, services);
  else      renderVerticalServices(g, c, services);

  return g;
}

function renderHorizontalServices(g, c, services) {
  const innerY = HEADER_H + 8;
  const totalW = services.length * H_CARD_W + (services.length - 1) * H_CARD_GAP;
  const xStart = (c.w - totalW) / 2;
  let xOff = xStart;

  for (let i = 0; i < services.length; i++) {
    const s = services[i];

    g.appendChild(el('rect', {
      x: xOff, y: innerY,
      width: H_CARD_W, height: H_CARD_H,
      rx: 5, ry: 5,
      class: `tflow-svc-card stage-${s.stage || 'plain'}`,
      'data-l2': c.id, 'data-svc-i': i
    }));

    g.appendChild(image(
      s.icon,
      xOff + (H_CARD_W - H_ICON) / 2,
      innerY + 14,
      H_ICON, H_ICON
    ));

    const nm = el('text', {
      x: xOff + H_CARD_W / 2, y: innerY + 60,
      'text-anchor': 'middle', class: 'tflow-svc-name'
    });
    nm.textContent = s.name;
    g.appendChild(nm);

    const sb = el('text', {
      x: xOff + H_CARD_W / 2, y: innerY + 76,
      'text-anchor': 'middle', class: 'tflow-svc-sub'
    });
    sb.textContent = s.sub;
    g.appendChild(sb);

    xOff += H_CARD_W + H_CARD_GAP;
  }
}

function renderVerticalServices(g, c, services) {
  let yOff = HEADER_H + 6;
  for (let i = 0; i < services.length; i++) {
    const s = services[i];

    g.appendChild(el('rect', {
      x: CARD_PAD, y: yOff,
      width: c.w - 2 * CARD_PAD, height: V_CARD_H,
      rx: 4, ry: 4, class: 'tflow-svc-card'
    }));

    g.appendChild(image(
      s.icon,
      CARD_PAD + 8,
      yOff + (V_CARD_H - V_ICON) / 2,
      V_ICON, V_ICON
    ));

    const textX = CARD_PAD + 8 + V_ICON + 8;
    const nm = el('text', { x: textX, y: yOff + 15, class: 'tflow-svc-name' });
    nm.textContent = s.name;
    g.appendChild(nm);

    const sb = el('text', { x: textX, y: yOff + 28, class: 'tflow-svc-sub' });
    sb.textContent = s.sub;
    g.appendChild(sb);

    yOff += V_CARD_H + V_CARD_GAP;
  }
}

// ───────────────────────────────────────────────────────────────────
// Step rendering — clears the overlay and draws the current step
// ───────────────────────────────────────────────────────────────────

function clearOverlay() {
  if (!overlayLayer) return;
  while (overlayLayer.firstChild) overlayLayer.removeChild(overlayLayer.firstChild);
  document.querySelectorAll('.tflow-container.active, .tflow-svc-card.active, .tflow-container.cluster-active, .tflow-hvu.active')
    .forEach(n => {
      n.classList.remove('active');
      n.classList.remove('cluster-active');
    });
}

function highlightTarget(t) {
  if (t.kind === 'container') {
    document.querySelector(`.tflow-container[data-id="${t.id}"]`)?.classList.add('active');
  } else if (t.kind === 'l1-cluster') {
    // Light up all six ship containers
    document.querySelectorAll('.tflow-container.kind-ship, .tflow-container.kind-ship-cmdr')
      .forEach(n => n.classList.add('cluster-active'));
    document.querySelector(`.tflow-container[data-id="${t.anchor}"]`)?.classList.add('active');
  } else if (t.kind === 'l2-svc') {
    document.querySelector(`.tflow-svc-card[data-l2="${t.l2}"][data-svc-i="${t.i}"]`)?.classList.add('active');
  } else if (t.kind === 'drone-anchor') {
    // Drone = the L2 banner itself (drone is the only client of this L2).
    // Highlight the whole banner so the viewer sees where the call originates.
    document.querySelector(`.tflow-container[data-id="${t.l2}"]`)?.classList.add('active');
  } else if (t.kind === 'hvu-cluster') {
    document.querySelectorAll('.tflow-hvu').forEach(n => n.classList.add('active'));
  }
}

// Compute a sensible "edge anchor" point on a target's bounding box, given
// the direction from `box` toward `other`. Used so arrows touch the
// nearest edge instead of the centre.
function edgeAnchor(box, other) {
  const dx = other.cx - box.cx;
  const dy = other.cy - box.cy;
  const adx = Math.abs(dx), ady = Math.abs(dy);
  if (adx * box.h > ady * box.w) {
    // crosses the left/right edge first
    const x = dx > 0 ? box.x + box.w : box.x;
    const t = (x - box.cx) / dx;
    return { x, y: box.cy + t * dy };
  } else {
    const y = dy > 0 ? box.y + box.h : box.y;
    const t = (y - box.cy) / dy;
    return { x: box.cx + t * dx, y };
  }
}

function drawStep(stepIdx) {
  clearOverlay();
  if (stepIdx < 0 || stepIdx >= MESSAGES.length) {
    updatePanel(null);
    updateCounter(0);
    return;
  }

  const m = MESSAGES[stepIdx];
  const stepCls = m.crosses ? 'crosses' : 'normal';

  // Helper — draw a self-loop. For L2 service tiles (which sit inside a
  // larger banner), draw a compact loop in the message lane just inside
  // the banner's bottom edge, with the label *below* the banner so it
  // never overlaps with tile content. For top-level containers (ships,
  // L1 cluster anchor), draw above the box as before.
  const drawSelfLoop = (box, label) => {
    const insideContainer = box._container && box.w < box._container.w;

    if (insideContainer) {
      const c = box._container;
      const laneY  = c.y + c.h - 16;    // badge line inside the banner
      const labelY = c.y + c.h + 16;    // label sits OUTSIDE the banner, below
      // No loop arrow — the active tile highlight + step badge + label
      // convey "this service is doing something internal at this step".
      // (A U-loop would be hidden behind the badge at this scale anyway.)
      drawStepBadge(overlayLayer, box.cx, laneY, m, stepCls);
      if (label) drawStepLabel(overlayLayer, box.cx, labelY, label, 'middle');
    } else {
      const loopX = box.cx;
      const loopY = box.y - 22;
      overlayLayer.appendChild(el('path', {
        d: `M ${loopX - 20} ${loopY + 6} q -10 -22 20 -22 q 30 0 20 22`,
        class: `tflow-flow-arrow ${stepCls}`,
        fill: 'none',
        'marker-end': m.crosses ? 'url(#tflow-arrow-head-cross)' : 'url(#tflow-arrow-head)'
      }));
      drawStepBadge(overlayLayer, loopX - 28, loopY - 6, m, stepCls);
      if (label) drawStepLabel(overlayLayer, loopX, loopY - 18, label, 'middle');
    }
  };

  // Optional `also` list — extra ship containers to highlight alongside the
  // primary actor (e.g. ship F lighting up when ship B is the active bravo
  // relay, since F does the same job on the alpha lane in parallel).
  const highlightAlso = (m) => {
    if (!Array.isArray(m.also)) return;
    for (const id of m.also) {
      document.querySelector(`.tflow-container[data-id="${id}"]`)?.classList.add('active');
    }
  };

  if (m.kind === 'self') {
    const t = targetOf(m.on);
    const box = targetBox(t);
    highlightTarget(t);
    highlightAlso(m);
    drawSelfLoop(box, m.label);

    // Parallel self-loops (e.g. Madara α seals a block in parallel with Madara β)
    if (Array.isArray(m.parallel)) {
      for (const p of m.parallel) {
        if (!p.on) continue;
        const pt = targetOf(p.on);
        if (!pt) continue;
        const pbox = targetBox(pt);
        highlightTarget(pt);
        // No label on the mirror loop — same step, same action
        drawSelfLoop(pbox, '');
      }
    }
  } else {
    const tFrom = targetOf(m.from);
    const tTo   = targetOf(m.to);
    const bFrom = targetBox(tFrom);
    const bTo   = targetBox(tTo);

    highlightTarget(tFrom);
    highlightTarget(tTo);
    highlightAlso(m);

    // ── Fan-out: source ship → L1 cluster (PoA peer broadcast).
    // Draw a straight dashed line from the source to EACH of the other 5
    // ships so the viewer sees the broadcast reach every validator. Matches
    // the simulation's L1 propagation visual.
    if (tTo.kind === 'l1-cluster' && tFrom.kind === 'container') {
      const SHIP_IDS = ['A', 'B', 'C', 'D', 'E', 'F'];
      const drawFanOut = (srcContainer) => {
        const bSrc = { x: srcContainer.x, y: srcContainer.y, w: srcContainer.w, h: srcContainer.h, cx: srcContainer.x + srcContainer.w / 2, cy: srcContainer.y + srcContainer.h / 2 };
        for (const sid of SHIP_IDS) {
          if (sid === srcContainer.id) continue;
          const s = CONTAINERS.find(x => x.id === sid);
          const bShip = { x: s.x, y: s.y, w: s.w, h: s.h, cx: s.x + s.w / 2, cy: s.y + s.h / 2 };
          const a1 = edgeAnchor(bSrc, bShip);
          const a2 = edgeAnchor(bShip, bSrc);
          overlayLayer.appendChild(el('line', {
            x1: a1.x, y1: a1.y, x2: a2.x, y2: a2.y,
            class: `tflow-flow-arrow cross-container ${stepCls}`,
            'marker-end': m.crosses ? 'url(#tflow-arrow-head-cross)' : 'url(#tflow-arrow-head)'
          }));
        }
        drawStepBadge(overlayLayer, bSrc.cx, bSrc.y - 14, m, stepCls);
      };
      drawFanOut(CONTAINERS.find(c => c.id === tFrom.id));
      drawStepLabel(overlayLayer, bFrom.cx, bFrom.y - 28, m.label, 'middle');

      // Parallel fan-outs (e.g. F → L1 cluster alongside B → L1 cluster
      // when both relays submit their proof txs in parallel).
      if (Array.isArray(m.parallel)) {
        for (const p of m.parallel) {
          if (!p.from) continue;
          const pFrom = targetOf(p.from);
          if (!pFrom || pFrom.kind !== 'container') continue;
          const pSrc = CONTAINERS.find(c => c.id === pFrom.id);
          if (!pSrc) continue;
          highlightTarget(pFrom);
          drawFanOut(pSrc);
        }
      }
    }
    // ── L1-internal calls (both endpoints map to the same box) — self-loop
    else if (bFrom.cx === bTo.cx && bFrom.cy === bTo.cy) {
      drawSelfLoop(bFrom, m.label);
    }
    // ── Standard one-to-one arrow
    else {
      const a1 = edgeAnchor(bFrom, bTo);
      const a2 = edgeAnchor(bTo, bFrom);

      // Detect cross-container arrow: arrows that leave or enter a Docker
      // container (ship → L2, L2-svc → ship, drone → L2, ship → HVU). These
      // get straight dashed lines like the simulation. Service-to-service
      // arrows inside the same L2 banner stay as curved beziers.
      const sameContainer = bFrom._container && bTo._container
        && bFrom._container.id === bTo._container.id;

      if (sameContainer) {
        // Within-container service-to-service — straight horizontal arrow
        // in a "message lane" inside the banner, label rendered BELOW the
        // banner (outside it) so it never overlaps with tile content.
        const drawLaneArrow = (b1, b2, withLabel) => {
          const c = b1._container;
          const laneY  = c.y + c.h - 16;    // arrow line just inside banner bottom
          const labelY = c.y + c.h + 16;    // label outside banner, below
          const sx = b1.cx;
          const tx = b2.cx;
          const dir = tx > sx ? 1 : -1;
          overlayLayer.appendChild(el('line', {
            x1: sx + dir * 16, y1: laneY,    // start past the badge (badge r=14)
            x2: tx,            y2: laneY,
            class: `tflow-flow-arrow ${stepCls}`,
            'marker-end': m.crosses ? 'url(#tflow-arrow-head-cross)' : 'url(#tflow-arrow-head)'
          }));
          drawStepBadge(overlayLayer, sx, laneY, m, stepCls);
          if (withLabel) drawStepLabel(overlayLayer, (sx + tx) / 2, labelY, m.label, 'middle');
        };
        drawLaneArrow(bFrom, bTo, true);

        // Parallel same-container arrows (alpha-lane mirror inside L2-A)
        if (Array.isArray(m.parallel)) {
          for (const p of m.parallel) {
            if (!p.from || !p.to) continue;
            const pFrom = targetOf(p.from);
            const pTo   = targetOf(p.to);
            if (!pFrom || !pTo) continue;
            const pbFrom = targetBox(pFrom);
            const pbTo   = targetBox(pTo);
            highlightTarget(pFrom);
            highlightTarget(pTo);
            drawLaneArrow(pbFrom, pbTo, false);
          }
        }
      } else if (tFrom.kind === 'l2-svc' && tTo.kind === 'container'
                 && bFrom._container.id !== bTo._container.id) {
        // Special: L2 service → outside ship (e.g. Orch → ship B).
        // Route the arrow DOWN from the source tile, out under the L2
        // banner, then UP into the target ship's bottom — avoids cutting
        // straight across the other service tiles inside the banner.
        const drawL2OutToShip = (b1, b2, withLabel) => {
          const lc = b1._container;            // source's L2 banner
          const sx = b1.cx;
          const sy = b1.y + b1.h;              // source tile bottom
          const tx = b2.cx;
          const ty = b2.y + b2.h;              // target ship bottom
          const dipY = lc.y + lc.h + 36;       // 36px below the L2 banner
          // Cubic bezier: down out of banner, swing across, up into target
          overlayLayer.appendChild(el('path', {
            d: `M ${sx} ${sy} C ${sx} ${dipY}, ${tx} ${dipY}, ${tx} ${ty}`,
            class: `tflow-flow-arrow cross-container ${stepCls}`,
            fill: 'none',
            'marker-end': m.crosses ? 'url(#tflow-arrow-head-cross)' : 'url(#tflow-arrow-head)'
          }));
          drawStepBadge(overlayLayer, sx, sy + 12, m, stepCls);
          if (withLabel) drawStepLabel(overlayLayer, (sx + tx) / 2, dipY + 14, m.label, 'middle');
        };
        drawL2OutToShip(bFrom, bTo, true);

        if (Array.isArray(m.parallel)) {
          for (const p of m.parallel) {
            if (!p.from || !p.to) continue;
            const pFrom = targetOf(p.from);
            const pTo   = targetOf(p.to);
            if (!pFrom || !pTo) continue;
            const pbFrom = targetBox(pFrom);
            const pbTo   = targetBox(pTo);
            highlightTarget(pFrom);
            highlightTarget(pTo);
            drawL2OutToShip(pbFrom, pbTo, false);
          }
        }
      } else if (tFrom.kind === 'drone-anchor') {
        // Special: drone is off-chain, reaches DOWN into the L2 stack to
        // call Madara. Render as a curved hook from above-right of the
        // banner, curving left and down into Madara's top edge.
        const drawDroneHook = (b1, b2, withLabel) => {
          const sx = b1.cx, sy = b1.cy;
          const tx = b2.cx, ty = b2.y;     // Madara tile top edge
          // Cubic bezier: down → left-and-down → down into target top
          const c1x = sx,  c1y = sy + 28;
          const c2x = tx,  c2y = sy + 28;
          overlayLayer.appendChild(el('path', {
            d: `M ${sx} ${sy} C ${c1x} ${c1y}, ${c2x} ${c2y}, ${tx} ${ty}`,
            class: `tflow-flow-arrow cross-container ${stepCls}`,
            fill: 'none',
            'marker-end': m.crosses ? 'url(#tflow-arrow-head-cross)' : 'url(#tflow-arrow-head)'
          }));
          drawStepBadge(overlayLayer, sx, sy, m, stepCls);
          if (withLabel) drawStepLabel(overlayLayer, sx, sy - 22, m.label, 'middle');
        };
        drawDroneHook(bFrom, bTo, true);

        if (Array.isArray(m.parallel)) {
          for (const p of m.parallel) {
            if (!p.from || !p.to) continue;
            const pFrom = targetOf(p.from);
            const pTo   = targetOf(p.to);
            if (!pFrom || !pTo) continue;
            const pbFrom = targetBox(pFrom);
            const pbTo   = targetBox(pTo);
            highlightTarget(pFrom);
            highlightTarget(pTo);
            drawDroneHook(pbFrom, pbTo, false);
          }
        }
      } else {
        // Cross-container — straight dashed line (mirrors the simulation)
        const mx = (a1.x + a2.x) / 2;
        const my = (a1.y + a2.y) / 2;
        overlayLayer.appendChild(el('line', {
          x1: a1.x, y1: a1.y, x2: a2.x, y2: a2.y,
          class: `tflow-flow-arrow cross-container ${stepCls}`,
          'marker-end': m.crosses ? 'url(#tflow-arrow-head-cross)' : 'url(#tflow-arrow-head)'
        }));
        drawStepBadge(overlayLayer, a1.x, a1.y, m, stepCls);
        drawStepLabel(overlayLayer, mx, my - 10, m.label, 'middle');

        // Parallel arrows — same step number, drawn alongside the main arrow.
        // Used when two lanes act simultaneously (e.g. B→L2-B & F→L2-A).
        if (Array.isArray(m.parallel)) {
          for (const p of m.parallel) {
            const pFrom = targetOf(p.from);
            const pTo   = targetOf(p.to);
            if (!pFrom || !pTo) continue;
            const pbFrom = targetBox(pFrom);
            const pbTo   = targetBox(pTo);
            highlightTarget(pFrom);
            highlightTarget(pTo);
            const pa1 = edgeAnchor(pbFrom, pbTo);
            const pa2 = edgeAnchor(pbTo, pbFrom);
            overlayLayer.appendChild(el('line', {
              x1: pa1.x, y1: pa1.y, x2: pa2.x, y2: pa2.y,
              class: `tflow-flow-arrow cross-container ${stepCls}`,
              'marker-end': m.crosses ? 'url(#tflow-arrow-head-cross)' : 'url(#tflow-arrow-head)'
            }));
            // Same step badge on the parallel source so both arrows are
            // clearly part of the same step.
            drawStepBadge(overlayLayer, pa1.x, pa1.y, m, stepCls);
          }
        }
      }
    }
  }

  updatePanel(m);
  updateCounter(stepIdx + 1);
}

function drawStepBadge(layer, x, y, m, stepCls) {
  layer.appendChild(el('circle', {
    cx: x, cy: y, r: 14,
    class: `tflow-step-badge ${stepCls}`
  }));
  const t = el('text', {
    x: x, y: y + 5, 'text-anchor': 'middle',
    class: 'tflow-step-num'
  });
  t.textContent = String(m.step);
  layer.appendChild(t);
}

function drawStepLabel(layer, x, y, text, anchor) {
  // Background pill behind the label so it stays readable on busy areas
  const tEl = el('text', {
    x: x, y: y, 'text-anchor': anchor || 'middle',
    class: 'tflow-flow-label'
  });
  tEl.textContent = text;
  layer.appendChild(tEl);
}

// ───────────────────────────────────────────────────────────────────
// Pan / zoom
// ───────────────────────────────────────────────────────────────────

let svgRef = null, rootRef = null;
let scale = 1, tx = 0, ty = 0;
let dragging = false, dragMoved = false, lastX = 0, lastY = 0;
const MIN_S = 0.5, MAX_S = 3;

function applyTransform() {
  if (rootRef) rootRef.setAttribute('transform', `translate(${tx} ${ty}) scale(${scale})`);
}

function reset() {
  scale = 1; tx = 0; ty = 0;
  applyTransform();
}

function clientToVB(clientX, clientY) {
  const r = svgRef.getBoundingClientRect();
  return {
    x: (clientX - r.left) * (VB_W / r.width),
    y: (clientY - r.top) * (VB_H / r.height)
  };
}

function zoomAt(clientX, clientY, factor) {
  const next = Math.max(MIN_S, Math.min(MAX_S, scale * factor));
  if (next === scale) return;
  const { x: mx, y: my } = clientToVB(clientX, clientY);
  const px = (mx - tx) / scale;
  const py = (my - ty) / scale;
  scale = next;
  tx = mx - px * scale;
  ty = my - py * scale;
  applyTransform();
}

function zoomCenter(factor) {
  const r = svgRef.getBoundingClientRect();
  zoomAt(r.left + r.width / 2, r.top + r.height / 2, factor);
}

function bindInteractions() {
  svgRef.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    dragging = true;
    dragMoved = false;
    lastX = e.clientX;
    lastY = e.clientY;
  });
  window.addEventListener('mousemove', (e) => {
    if (!dragging) return;
    const dx = e.clientX - lastX;
    const dy = e.clientY - lastY;
    if (Math.abs(dx) + Math.abs(dy) > 3) dragMoved = true;
    lastX = e.clientX;
    lastY = e.clientY;
    if (dragMoved) {
      const r = svgRef.getBoundingClientRect();
      tx += dx * (VB_W / r.width);
      ty += dy * (VB_H / r.height);
      applyTransform();
    }
  });
  window.addEventListener('mouseup', () => {
    dragging = false;
    setTimeout(() => { dragMoved = false; }, 0);
  });
  svgRef.addEventListener('wheel', (e) => {
    e.preventDefault();
    const factor = e.deltaY < 0 ? 1.12 : 1 / 1.12;
    zoomAt(e.clientX, e.clientY, factor);
  }, { passive: false });

  // Buttons (scoped to the tflow controls)
  const ctrl = document.querySelector('.tflow-controls');
  ctrl?.querySelector('[data-act="zoom-in"]')?.addEventListener('click', () => zoomCenter(1.25));
  ctrl?.querySelector('[data-act="zoom-out"]')?.addEventListener('click', () => zoomCenter(1 / 1.25));
  ctrl?.querySelector('[data-act="reset"]')?.addEventListener('click', reset);
}

// ───────────────────────────────────────────────────────────────────
// Playback controls
// ───────────────────────────────────────────────────────────────────

let curStep = -1;            // -1 = nothing rendered yet
let playTimer = null;
const PLAY_INTERVAL_MS = 1800;

function step(delta) {
  stopPlay();
  // Allow going back to -1 (initial empty state) so prev keeps working
  // even when the user is at step 1.
  const next = Math.max(-1, Math.min(MESSAGES.length - 1, curStep + delta));
  if (next === curStep) return;
  curStep = next;
  if (curStep < 0) {
    clearOverlay();
    updatePanel(null);
    updateCounter(0);
  } else {
    drawStep(curStep);
  }
}

function gotoStep(i) {
  stopPlay();
  curStep = Math.max(0, Math.min(MESSAGES.length - 1, i));
  drawStep(curStep);
}

function play() {
  if (playTimer) { stopPlay(); return; }
  if (curStep < 0) curStep = 0;
  drawStep(curStep);
  setPlayBtnState(true);
  playTimer = setInterval(() => {
    if (curStep >= MESSAGES.length - 1) {
      stopPlay();
      return;
    }
    curStep++;
    drawStep(curStep);
  }, PLAY_INTERVAL_MS);
}

function stopPlay() {
  if (playTimer) { clearInterval(playTimer); playTimer = null; }
  setPlayBtnState(false);
}

function setPlayBtnState(playing) {
  const btn = document.querySelector('.tflow-playbtn[data-act="play"]');
  if (!btn) return;
  btn.textContent = playing ? '❚❚' : '▶';
  btn.title = playing ? 'Pause' : 'Play';
  btn.classList.toggle('playing', playing);
}

function bindPlayback() {
  const bar = document.querySelector('.tflow-playbar');
  if (!bar) return;
  bar.querySelector('[data-act="reset-step"]')?.addEventListener('click', () => { stopPlay(); curStep = -1; clearOverlay(); updatePanel(null); updateCounter(0); });
  bar.querySelector('[data-act="prev"]')?.addEventListener('click', () => step(-1));
  bar.querySelector('[data-act="play"]')?.addEventListener('click', () => play());
  bar.querySelector('[data-act="next"]')?.addEventListener('click', () => step(+1));

  // Keyboard
  window.addEventListener('keydown', (e) => {
    const inFlow = document.querySelector('.tflow-stage-wrap')?.matches(':hover');
    if (!inFlow) return;
    if (e.key === 'ArrowRight') { step(+1); e.preventDefault(); }
    else if (e.key === 'ArrowLeft') { step(-1); e.preventDefault(); }
    else if (e.key === ' ') { play(); e.preventDefault(); }
  });
}

function updateCounter(cur) {
  const elCur = document.getElementById('tflow-cur');
  const elTotal = document.getElementById('tflow-total');
  if (elCur) elCur.textContent = String(cur);
  if (elTotal) elTotal.textContent = String(MESSAGES.length);
}

// ───────────────────────────────────────────────────────────────────
// Side panel
// ───────────────────────────────────────────────────────────────────

const ACTOR_LABEL = {
  D: 'ship D', ShipB: 'ship B', ShipF: 'ship F', L1Cluster: 'L1 (all 6 ships)',
  L2Banner: 'L2-B (drone\'s stack)', L2BannerA: 'L2-A (drone\'s stack)',
  Drone: 'drone β',
  Madara: 'Madara β', Pathfinder: 'Pathfinder', Orch: 'Orchestrator',
  SNOS: 'SNOS', Stone: 'Stone', HVUs: '3 HVUs (off-network)'
};

function escapeHTML(s) {
  return String(s).replace(/[&<>"']/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

function updatePanel(m) {
  const panel = document.getElementById('tflow-panel');
  if (!panel) return;

  if (!m) {
    panel.innerHTML = `
      <div class="tflow-panel-empty">
        <h4>Step detail</h4>
        <p>Click <strong>▶ Play</strong> to walk through one full mission cycle, or use <strong>▶▶ Next</strong> / <strong>◀ Prev</strong> to step manually. Each step shows the contract endpoint, payload schema, authentication, and trust-boundary detail of one call between containers.</p>
      </div>`;
    return;
  }

  const fromName = m.from ? (ACTOR_LABEL[m.from] || m.from) : '';
  const toName   = m.to   ? (ACTOR_LABEL[m.to]   || m.to)   : '';
  const onName   = m.on   ? (ACTOR_LABEL[m.on]   || m.on)   : '';

  panel.innerHTML = `
    <div class="tflow-detail-head">
      <span class="tflow-detail-step ${m.crosses ? 'crosses' : ''}">Step ${m.step} / ${MESSAGES.length}</span>
      ${m.crosses ? '<span class="tflow-detail-cross">trust crossing</span>' : ''}
    </div>
    <h4 class="tflow-detail-route">
      ${m.kind === 'self'
        ? `<span>${escapeHTML(onName)}</span><span class="tflow-arrow-glyph">↻</span><span>self</span>`
        : `<span>${escapeHTML(fromName)}</span><span class="tflow-arrow-glyph">→</span><span>${escapeHTML(toName)}</span>`}
    </h4>
    <p class="tflow-detail-label">${escapeHTML(m.label)}</p>

    <p class="tflow-detail-section-h">Endpoint signature</p>
    <pre class="tflow-detail-sig"><code>${escapeHTML(m.sig)}</code></pre>

    <p class="tflow-detail-section-h">Payload</p>
    <ul class="tflow-detail-payload">
      ${m.payload.map(p => `
        <li><code class="f">${escapeHTML(p.f)}</code>${p.t ? ` <span class="t">${escapeHTML(p.t)}</span>` : ''}</li>
      `).join('')}
    </ul>

    <p class="tflow-detail-section-h">Authentication</p>
    <p class="tflow-detail-auth">${escapeHTML(m.auth)}</p>

    <p class="tflow-detail-section-h">Trust boundary</p>
    <p class="tflow-detail-boundary ${m.crosses ? 'crosses' : ''}">
      <strong>${escapeHTML(m.boundary)}</strong>
      ${m.crosses ? ' &mdash; this call crosses a trust domain' : ' &mdash; no crossing'}
    </p>

    <p class="tflow-detail-section-h">What happens</p>
    <p class="tflow-detail-desc">${escapeHTML(m.desc)}</p>
  `;
}

// ───────────────────────────────────────────────────────────────────
// Init
// ───────────────────────────────────────────────────────────────────

function init() {
  if (!document.getElementById('tflow-stage')) return;
  const built = buildSvg();
  if (!built) return;
  svgRef = built.svg;
  rootRef = built.root;
  applyTransform();
  bindInteractions();
  bindPlayback();
  updateCounter(0);
  updatePanel(null);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

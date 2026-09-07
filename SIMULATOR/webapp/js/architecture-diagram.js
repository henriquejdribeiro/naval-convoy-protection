// ============================================================================
// Architecture diagram — the "how": every Docker container, services inside,
// click-to-see files. Pannable / zoomable SVG.
// ============================================================================

const REPO = 'https://github.com/henriquejdribeiro/naval-convoy-protection';
const SVG_NS = 'http://www.w3.org/2000/svg';
const XLINK_NS = 'http://www.w3.org/1999/xlink';

const VB_W = 2580;
const VB_H = 760;

// ---------------------------------------------------------------------------
// Layout — L2-Alpha sits on the LEFT flank at the same y as ship F, and
// L2-Bravo sits on the RIGHT flank at the same y as ship B, so the proof
// flows directly sideways from each L2 pipeline into its primary relay ship.
// The six-ship convoy keeps a hexagonal formation in the middle.
// ---------------------------------------------------------------------------

const SHIP_W = 200, SHIP_H = 90;
const CMDR_W = 200, CMDR_H = 90;       // same as SHIP_H — D no longer runs a
                                        // watcher daemon, only the Geth node
const L2_W   = 720, L2_H   = 175;   // header + 5 service tiles (no inner
                                     // sequence diagram — flow detail moves
                                     // to the Transaction flow diagram)

const CONTAINERS = [
  // Top of the convoy. Layout: 100 left margin, 720 L2A, 80 corridor, 200 F,
  // 80 ship-HVU gap, 200 HVU, 80 ship-HVU gap, 200 B, 80 corridor, 720 L2B,
  // 100 right margin = VB_W 2580. The 80 ship-HVU gap is the visible
  // breathing room around each HVU at the rendered scale.
  { id: 'A',   kind: 'ship',      name: 'Ship A — Forward',           x: 1200, y: 40,  w: SHIP_W, h: SHIP_H },
  // L2 banners — vertical centre aligns with F / B vertical centre (245)
  { id: 'L2A', kind: 'l2-alpha',  name: 'L2-Alpha — Madara α drone',   x: 120,  y: 158, w: L2_W,   h: L2_H   },
  { id: 'F',   kind: 'ship',      name: 'Ship F — Forward-left',      x: 920,  y: 200, w: SHIP_W, h: SHIP_H },
  { id: 'B',   kind: 'ship',      name: 'Ship B — Forward-right',     x: 1480, y: 200, w: SHIP_W, h: SHIP_H },
  { id: 'L2B', kind: 'l2-bravo',  name: 'L2-Bravo — Madara β drone',   x: 1760, y: 158, w: L2_W,   h: L2_H   },
  // Lower row of the convoy
  { id: 'E',   kind: 'ship',      name: 'Ship E — Mid-left',          x: 920,  y: 440, w: SHIP_W, h: SHIP_H },
  { id: 'C',   kind: 'ship',      name: 'Ship C — Mid-right',         x: 1480, y: 440, w: SHIP_W, h: SHIP_H },
  // Commander at the bottom
  { id: 'D',   kind: 'ship-cmdr', name: 'Ship D — Commander',         x: 1200, y: 600, w: CMDR_W, h: CMDR_H }
];

// HVUs — High-Value Units. NOT part of the network: no L1 validator key,
// no L2 sequencer, no Docker container. Same physical size as escort
// ships (200×90) so they read as comparable assets in the formation,
// but a dashed border + "off-network" sub-label flags that they sit
// outside the cryptographic perimeter. Centre column, between F and B
// (HVU-1), formation centre (HVU-2), between E and C (HVU-3).
const HVU_W = 200, HVU_H = 90;
const HVUS = [
  { id: 'HVU-1', x: 1200, y: 200 },   // same row as F & B, dead-centre between
  { id: 'HVU-2', x: 1200, y: 320 },   // formation centre, between F/B and E/C rows
  { id: 'HVU-3', x: 1200, y: 440 }    // same row as E & C, dead-centre between
];

// Proof-generation flow inside an L2 stack — the Madara → Pathfinder →
// Orchestrator → SNOS → Stone pipeline, expressed as a sequence diagram.
// `from` and `to` are indices into the L2 service array:
//   0 = Madara, 1 = Pathfinder, 2 = Orchestrator, 3 = SNOS, 4 = Stone Prover
// `kind: 'self'` draws a small loop on the actor's own lifeline.
const L2_FLOW = [
  { step: 9,  kind: 'msg',  from: 0, to: 1, label: 'Feeder Gateway sync' },
  { step: 10, kind: 'msg',  from: 2, to: 0, label: 'getBlockWithTxs' },
  { step: 11, kind: 'msg',  from: 0, to: 2, label: 'block + state diff' },
  { step: 12, kind: 'msg',  from: 2, to: 3, label: 'request proof input' },
  { step: 13, kind: 'msg',  from: 3, to: 1, label: 'query block data' },
  { step: 14, kind: 'msg',  from: 1, to: 3, label: 'state + receipts' },
  { step: 15, kind: 'self', from: 3, to: 3, label: 'replay (Cairo VM)' },
  { step: 16, kind: 'msg',  from: 3, to: 2, label: 'PIE trace' },
  { step: 17, kind: 'msg',  from: 2, to: 4, label: 'send PIE + config' },
  { step: 18, kind: 'self', from: 4, to: 4, label: 'run FRI → π' }
];

// L2 services are ordered by *proof generation flow*:
// Madara executes → Pathfinder indexes → Orchestrator coordinates →
// SNOS replays trace → Stone produces the STARK.
const SERVICES = {
  'ship': [
    { icon: 'images/ethereum.png', name: 'Geth (Clique PoA)', sub: 'L1 validator node', version: 'v1.10.17' }
  ],
  'ship-cmdr': [
    { icon: 'images/ethereum.png', name: 'Geth (Clique PoA)', sub: 'L1 validator node', version: 'v1.10.17' }
  ],
  'l2-alpha': [
    { icon: 'images/madara.png',       name: 'Madara α',     sub: 'Execution Layer',  version: ':nightly',         stage: 'exec'  },
    { icon: 'images/pathfinder.png',   name: 'Starknet Node', sub: 'Pathfinder',      version: 'v0.21.3',          stage: 'exec'  },
    { icon: 'images/madara.png',       name: 'Orchestrator', sub: 'Settlement orch.', version: 'in-house',         stage: 'exec'  },
    { icon: 'images/snos.jpg',         name: 'SNOS',         sub: 'StarkNet OS',      version: 'v0.14.1-α',         stage: 'prove' },
    { icon: 'images/stone-prover.svg', name: 'Stone Prover', sub: 'STARK Prover',     version: 'main',             stage: 'prove' }
  ],
  'l2-bravo': [
    { icon: 'images/madara.png',       name: 'Madara β',     sub: 'Execution Layer',  version: ':nightly',         stage: 'exec'  },
    { icon: 'images/pathfinder.png',   name: 'Starknet Node', sub: 'Pathfinder',      version: 'v0.21.3',          stage: 'exec'  },
    { icon: 'images/madara.png',       name: 'Orchestrator', sub: 'Settlement orch.', version: 'in-house',         stage: 'exec'  },
    { icon: 'images/snos.jpg',         name: 'SNOS',         sub: 'StarkNet OS',      version: 'v0.14.1-α',         stage: 'prove' },
    { icon: 'images/stone-prover.svg', name: 'Stone Prover', sub: 'STARK Prover',     version: 'main',             stage: 'prove' }
  ]
};

const KIND_LABEL = {
  'ship':      'L1 VALIDATOR',
  'ship-cmdr': 'COMMANDER · L1 VALIDATOR',
  'l2-alpha':  'L2-ALPHA',
  'l2-bravo':  'L2-BRAVO'
};

// Each L2 IS a single drone — its own Madara sequencer, its own Pathfinder,
// its own SNOS+Stone proving stack. The drone is the only client of its L2:
// it holds one OpenZeppelin account contract on Madara, signs every
// `submit_telemetry` call with its Stark-curve key, and closes the sweep
// with `submit_sweep_commitment`. Inside `convoy_protocol.cairo` it's
// addressed by its `drone_id` (felt252).
const DRONES = {
  'l2-alpha': { id: 'α', account: '0x__α__', key: 'keystore/alpha.json' },
  'l2-bravo': { id: 'β', account: '0x__β__', key: 'keystore/bravo.json' }
};

// Per-kind specification — what the container is, which cryptographic
// primitives it uses, and what it can / cannot do (the trust boundary).
const WHAT_IS = {
  'ship':      'One of six L1 validators on the Geth Clique PoA chain. Also acts as a best-signal proof relay between an L2 and L1.',
  'ship-cmdr': 'Regular L1 validator <em>plus</em> holder of the commander key. The only ship authorised to deploy mission specs and to fire a manual advance override.',
  'l2-alpha':  'A single drone running its own self-contained L2 stack (Madara α + Pathfinder + SNOS + Stone). The drone is the only client of this L2.',
  'l2-bravo':  'A single drone running its own self-contained L2 stack (Madara β + Pathfinder + SNOS + Stone). The drone is the only client of this L2.'
};

const CRYPTO_IN_PLAY = {
  'ship': [
    { p: 'secp256k1 ECDSA',  d: 'Clique PoA block sealing + L1 transaction signing (mission deploy, proof relay)' }
  ],
  'ship-cmdr': [
    { p: 'secp256k1 ECDSA',  d: 'same as a regular ship — block sealing + tx signing' },
    { p: 'Commander key',     d: 'separate keystore entry; required by Registry.deploy() and the CommandLog manual-override path' }
  ],
  'l2-alpha': [
    { p: 'Stark-curve ECDSA', d: 'drone signs every <code>submit_telemetry</code> tx; verified by its OZ account contract on Madara' },
    { p: 'Poseidon',          d: 'telemetry commitment <code>H_α</code> over the per-cell array; Cairo-native hash, cheap to verify inside the proof' },
    { p: 'STARK / FRI',       d: 'Stone produces <code>π_α</code> over <code>safe_area_verify.cairo</code>; lambdaclass <code>cairo-vm</code> executes the program' }
  ],
  'l2-bravo': [
    { p: 'Stark-curve ECDSA', d: 'drone signs every <code>submit_telemetry</code> tx; verified by its OZ account contract on Madara' },
    { p: 'Poseidon',          d: 'telemetry commitment <code>H_β</code> over the per-cell array; Cairo-native hash, cheap to verify inside the proof' },
    { p: 'STARK / FRI',       d: 'Stone produces <code>π_β</code> over <code>safe_area_verify.cairo</code>; lambdaclass <code>cairo-vm</code> executes the program' }
  ]
};

// Per-package metadata. Stack inventory in the architecture-at-a-glance side
// panel is rendered from this. The architecture view answers "what's running"
// — version, source, license, role. Flow / endpoints / hashes / signatures
// are answered by the upcoming Transaction flow diagram.
const PACKAGE_SPEC = {
  'ship': [
    { name: 'Geth (ethereum/client-go)', version: 'v1.10.17', license: 'LGPL-3.0',
      source: 'https://github.com/ethereum/go-ethereum',
      role: 'L1 Clique PoA validator (EIP-225); secp256k1 block sealing',
      note: 'EVM target paris — predates 1.11 PoS migration; keeps Clique as a first-class consensus engine' },
    { name: 'Solidity (Foundry profile)', version: '0.8.33', license: 'MIT / Apache-2.0',
      source: 'https://github.com/foundry-rs/foundry',
      role: 'L1 contract compile target (Verifier, Registry, CommandLog, StarknetCoreStub)',
      note: 'Highest stable solc that compiles StarkWare FactRegistry without modification' },
    { name: 'StarkWare verifier components', version: 'main', license: 'Apache-2.0',
      source: 'https://github.com/starkware-libs/starkex-contracts',
      role: 'evm-verifier base (FactRegistry, MemoryPageFactRegistry)',
      note: 'Used as the production base for Verifier.sol' }
  ],
  'ship-cmdr': [
    { name: 'Geth (ethereum/client-go)', version: 'v1.10.17', license: 'LGPL-3.0',
      source: 'https://github.com/ethereum/go-ethereum',
      role: 'L1 Clique PoA validator + commander key holder',
      note: 'Same Geth build as a regular ship; commander role is a separate keystore entry, not a different binary' },
    { name: 'Solidity (Foundry profile)', version: '0.8.33', license: 'MIT / Apache-2.0',
      source: 'https://github.com/foundry-rs/foundry',
      role: 'L1 contract compile target',
      note: 'Same as a regular ship' },
    { name: 'StarkWare verifier components', version: 'main', license: 'Apache-2.0',
      source: 'https://github.com/starkware-libs/starkex-contracts',
      role: 'evm-verifier base for Verifier.sol',
      note: 'Same as a regular ship' }
  ],
  'l2-alpha': [
    { name: 'Madara α', version: ':nightly', license: 'Apache-2.0',
      source: 'https://github.com/madara-alliance/madara',
      role: 'Starknet sequencer — execution layer for L2-Alpha',
      note: 'Pinned to nightly digest until the Madara Alliance cuts a stable Starknet 0.14.1-aligned release' },
    { name: 'Pathfinder', version: 'v0.21.3', license: 'MIT / Apache-2.0',
      source: 'https://github.com/eqlabs/pathfinder',
      role: 'Starknet full node + JSON-RPC',
      note: 'Aligned with Starknet protocol v0.14.1' },
    { name: 'Orchestrator', version: 'in-house', license: 'Apache-2.0',
      source: 'https://github.com/madara-alliance/madara',
      role: 'Settlement orchestrator — coordinates SNOS + Stone, hands proof to relay ship',
      note: 'Rust adaptation derived from the madara orchestrator; Phase 3 deliverable' },
    { name: 'SNOS', version: 'v0.14.1-alpha.0', license: 'MIT / Apache-2.0',
      source: 'https://github.com/keep-starknet-strange/snos',
      role: 'StarkNet OS — generates PIE traces from sealed L2 blocks',
      note: 'Uses cairo-lang 0.14.1a0 + lambdaclass cairo-vm internally' },
    { name: 'Stone Prover', version: 'main', license: 'Apache-2.0',
      source: 'https://github.com/starkware-libs/stone-prover',
      role: 'STARK prover — runs FRI over the PIE',
      note: 'Built with Bazel 5.4.1 + cairo-lang 0.14.0.1 (deliberately different cairo-lang from SNOS)' }
  ],
  'l2-bravo': [
    { name: 'Madara β', version: ':nightly', license: 'Apache-2.0',
      source: 'https://github.com/madara-alliance/madara',
      role: 'Starknet sequencer — execution layer for L2-Bravo',
      note: 'Pinned to nightly digest until the Madara Alliance cuts a stable Starknet 0.14.1-aligned release' },
    { name: 'Pathfinder', version: 'v0.21.3', license: 'MIT / Apache-2.0',
      source: 'https://github.com/eqlabs/pathfinder',
      role: 'Starknet full node + JSON-RPC',
      note: 'Aligned with Starknet protocol v0.14.1' },
    { name: 'Orchestrator', version: 'in-house', license: 'Apache-2.0',
      source: 'https://github.com/madara-alliance/madara',
      role: 'Settlement orchestrator — coordinates SNOS + Stone, hands proof to relay ship',
      note: 'Rust adaptation derived from the madara orchestrator; Phase 3 deliverable' },
    { name: 'SNOS', version: 'v0.14.1-alpha.0', license: 'MIT / Apache-2.0',
      source: 'https://github.com/keep-starknet-strange/snos',
      role: 'StarkNet OS — generates PIE traces from sealed L2 blocks',
      note: 'Uses cairo-lang 0.14.1a0 + lambdaclass cairo-vm internally' },
    { name: 'Stone Prover', version: 'main', license: 'Apache-2.0',
      source: 'https://github.com/starkware-libs/stone-prover',
      role: 'STARK prover — runs FRI over the PIE',
      note: 'Built with Bazel 5.4.1 + cairo-lang 0.14.0.1 (deliberately different cairo-lang from SNOS)' }
  ]
};

// ---------------------------------------------------------------------------
// PARKED FOR THE TRANSACTION FLOW DIAGRAM (next section).
// CONTRACT_API, LIFECYCLE, L1_ANCHOR describe how data MOVES — they do not
// belong in the architecture-at-a-glance ("what's running") view. They are
// kept here because the Transaction flow diagram will render them; the
// selectContainer() panel below no longer references them.
// ---------------------------------------------------------------------------

// Cairo contract entry points + struct shapes — the API engineers will code
// against in Phase 3. Per-L2 because the symbols (α / β, H_α / H_β) differ.
const CONTRACT_API = {
  'l2-alpha': {
    entryPoints: [
      { sig: 'fn deploy_mission(spec: MissionSpec) -> u128',                       caller: 'L1→L2 bridge', desc: 'consumes the mission spec relayed from L1 Registry' },
      { sig: 'fn submit_telemetry(mission_id: u128, cells: Array<TelemetryCell>)', caller: 'drone α',       desc: 'per-cell readings; signed with the drone\'s Stark-curve key' },
      { sig: 'fn submit_sweep_commitment(mission_id: u128, h: felt252)',           caller: 'drone α',       desc: 'closes the sweep; commits H_α = Poseidon(cells)' }
    ],
    structs: [
      { name: 'MissionSpec',   fields: [
        { f: 'area_hash: felt252',  c: 'Poseidon hash of polygon vertices' },
        { f: 'coverage_min: u16',   c: 'permille (950 = ≥ 95% cells)' },
        { f: 'p_min: u16',          c: 'basis points (7000 = p_contact ≥ 0.7)' },
        { f: 'time_window: u64',    c: 'seconds (360 = 6 min)' }
      ]},
      { name: 'TelemetryCell', fields: [
        { f: 'x: u16, y: u16',      c: 'cell index in the area grid' },
        { f: 'p_contact: u16',      c: 'basis points (max-prob hit in cell)' },
        { f: 'ts: u64',             c: 'unix timestamp seconds' }
      ]}
    ]
  },
  'l2-bravo': {
    entryPoints: [
      { sig: 'fn deploy_mission(spec: MissionSpec) -> u128',                       caller: 'L1→L2 bridge', desc: 'consumes the mission spec relayed from L1 Registry' },
      { sig: 'fn submit_telemetry(mission_id: u128, cells: Array<TelemetryCell>)', caller: 'drone β',       desc: 'per-cell readings; signed with the drone\'s Stark-curve key' },
      { sig: 'fn submit_sweep_commitment(mission_id: u128, h: felt252)',           caller: 'drone β',       desc: 'closes the sweep; commits H_β = Poseidon(cells)' }
    ],
    structs: [
      { name: 'MissionSpec',   fields: [
        { f: 'area_hash: felt252',  c: 'Poseidon hash of polygon vertices' },
        { f: 'coverage_min: u16',   c: 'permille (950 = ≥ 95% cells)' },
        { f: 'p_min: u16',          c: 'basis points (7000 = p_contact ≥ 0.7)' },
        { f: 'time_window: u64',    c: 'seconds (360 = 6 min)' }
      ]},
      { name: 'TelemetryCell', fields: [
        { f: 'x: u16, y: u16',      c: 'cell index in the area grid' },
        { f: 'p_contact: u16',      c: 'basis points (max-prob hit in cell)' },
        { f: 'ts: u64',             c: 'unix timestamp seconds' }
      ]}
    ]
  }
};

// End-to-end mission lifecycle from the L2's perspective — chronological,
// from "spec arrives on L1" to "verdict lands on L1". Each step has a `who`
// label naming the actor (L1, drone, Madara, SNOS, Stone, L1 again).
const LIFECYCLE = {
  'l2-alpha': [
    { who: 'L1',      t: 'Registry emits <code>MissionDeployed(EX-0xx)</code>; bridge relays spec to L2' },
    { who: 'drone α', t: 'Sweeps cells; signs and submits each <code>submit_telemetry(...)</code> tx' },
    { who: 'drone α', t: 'Closes with <code>submit_sweep_commitment(H_α)</code>' },
    { who: 'Madara',  t: 'Seals block; Pathfinder indexes it' },
    { who: 'SNOS',    t: 'Replays block in Cairo VM; asserts SAFE_AREA on the witness' },
    { who: 'Stone',   t: 'Produces <code>π_α</code>; orchestrator hands it to relay ship F → A' },
    { who: 'L1',      t: 'Verifier re-runs FRI; on dual SAFE, <code>CommandLog.advance()</code> fires' }
  ],
  'l2-bravo': [
    { who: 'L1',      t: 'Registry emits <code>MissionDeployed(EX-0xx)</code>; bridge relays spec to L2' },
    { who: 'drone β', t: 'Sweeps cells; signs and submits each <code>submit_telemetry(...)</code> tx' },
    { who: 'drone β', t: 'Closes with <code>submit_sweep_commitment(H_β)</code>' },
    { who: 'Madara',  t: 'Seals block; Pathfinder indexes it' },
    { who: 'SNOS',    t: 'Replays block in Cairo VM; asserts SAFE_AREA on the witness' },
    { who: 'Stone',   t: 'Produces <code>π_β</code>; orchestrator hands it to relay ship B → A' },
    { who: 'L1',      t: 'Verifier re-runs FRI; on dual SAFE, <code>CommandLog.advance()</code> fires' }
  ]
};

// L1 settlement anchor — the contract this Madara writes its state diffs and
// proof commits into. The 4th L1 contract (alongside Verifier, Registry,
// CommandLog), required by Madara's settlement loop.
const L1_ANCHOR = {
  'l2-alpha': {
    contract: 'StarknetCoreStub.sol',
    address:  '0x__core_α__',
    desc:     'Madara α settles state diffs + proof commits here',
    msgs: [
      { dir: 'L1 → L2', t: 'mission spec relay (Registry → bridge → <code>deploy_mission</code>)' },
      { dir: 'L2 → L1', t: 'state diff + proof root committed by the orchestrator' }
    ]
  },
  'l2-bravo': {
    contract: 'StarknetCoreStub.sol',
    address:  '0x__core_β__',
    desc:     'Madara β settles state diffs + proof commits here',
    msgs: [
      { dir: 'L1 → L2', t: 'mission spec relay (Registry → bridge → <code>deploy_mission</code>)' },
      { dir: 'L2 → L1', t: 'state diff + proof root committed by the orchestrator' }
    ]
  }
};

const TRUST_SPEC = {
  'ship': [
    { mark: 'ok',   t: 'Sign blocks (1 of 6 PoA validators; ≥ 4 of 6 needed for finality)' },
    { mark: 'ok',   t: 'Submit proof-relay transactions to L1 (envelope only)' },
    { mark: 'no',   t: 'Cannot forge a STARK proof — the Verifier re-runs FRI on every submission' },
    { mark: 'no',   t: 'Cannot bypass the dual-SAFE auto-fire — chain enforces it inside the Verifier' }
  ],
  'ship-cmdr': [
    { mark: 'ok',   t: 'Same as a regular ship' },
    { mark: 'ok',   t: 'Deploy mission specs on the Registry (<code>onlyCommander</code>)' },
    { mark: 'ok',   t: 'Manual advance override via <code>CommandLog.advance()</code> (failsafe path)' },
    { mark: 'no',   t: 'Cannot manufacture a SAFE verdict — Verifier remains the only gate' },
    { mark: 'no',   t: 'Cannot bypass dual-SAFE for the auto-fire path' }
  ],
  'l2-alpha': [
    { mark: 'ok',   t: 'Sequences telemetry into L2 blocks' },
    { mark: 'ok',   t: 'Cairo program enforces SAFE_AREA on the witness (Coverage / Time / Contacts)' },
    { mark: 'ok',   t: 'Stone refuses to prove constraint-violating telemetry → no <code>π_α</code>, nothing reaches L1' },
    { mark: 'no',   t: 'Cannot bypass the L1 Verifier — FRI re-runs on chain regardless of who submitted' },
    { mark: 'warn', t: 'A compromised drone reporting fake-low <code>p_contact</code> still produces a valid proof — drones must be honest sensors (current trust assumption; future: k-of-n drone signatures)' }
  ],
  'l2-bravo': [
    { mark: 'ok',   t: 'Sequences telemetry into L2 blocks' },
    { mark: 'ok',   t: 'Cairo program enforces SAFE_AREA on the witness (Coverage / Time / Contacts)' },
    { mark: 'ok',   t: 'Stone refuses to prove constraint-violating telemetry → no <code>π_β</code>, nothing reaches L1' },
    { mark: 'no',   t: 'Cannot bypass the L1 Verifier — FRI re-runs on chain regardless of who submitted' },
    { mark: 'warn', t: 'A compromised drone reporting fake-low <code>p_contact</code> still produces a valid proof — drones must be honest sensors (current trust assumption; future: k-of-n drone signatures)' }
  ]
};

// Per-container file inventory — placeholders until each phase is built.
const FILES = {
  'ship': [
    { p: 'docker/ship/docker-compose.yml', d: 'Geth validator service definition',           phase: 2 },
    { p: 'docker/ship/geth/genesis.json',  d: 'Clique PoA genesis (6 validators)',           phase: 2 },
    { p: 'docker/ship/geth/config.toml',   d: 'sealing key, peer list, RPC ports',           phase: 2 }
  ],
  'ship-cmdr': [
    { p: 'docker/ship/docker-compose.yml',     d: 'Geth validator service definition',                 phase: 2 },
    { p: 'docker/ship/geth/genesis.json',      d: 'Clique PoA genesis (6 validators)',                 phase: 2 },
    { p: 'docker/ship/geth/config.toml',       d: 'sealing key, peer list, RPC ports',                 phase: 2 },
    { p: 'docker/ship/commander.key',          d: 'D holds this key; lets D send a manual advance()',  phase: 2 }
  ],
  'l2-alpha': [
    { p: 'docker/l2-alpha/docker-compose.yml',     d: 'Madara α + Pathfinder + SNOS + Stone + orchestrator', phase: 3 },
    { p: 'docker/l2-alpha/madara/config.toml',     d: 'sequencer params, settlement contract on L1',         phase: 3 },
    { p: 'docker/l2-alpha/pathfinder/config.toml', d: 'indexer + JSON-RPC for the Alpha drone',             phase: 3 },
    { p: 'docker/l2-alpha/orchestrator.toml',      d: 'L1 RPC, relay-ship priority (F → A)',                 phase: 3 },
    { p: 'cairo/alpha_verify.cairo',               d: 'SAFE_AREA verification program (Alpha)',              phase: 3 }
  ],
  'l2-bravo': [
    { p: 'docker/l2-bravo/docker-compose.yml',     d: 'Madara β + Pathfinder + SNOS + Stone + orchestrator', phase: 3 },
    { p: 'docker/l2-bravo/madara/config.toml',     d: 'sequencer params, settlement contract on L1',         phase: 3 },
    { p: 'docker/l2-bravo/pathfinder/config.toml', d: 'indexer + JSON-RPC for the Bravo drone',             phase: 3 },
    { p: 'docker/l2-bravo/orchestrator.toml',      d: 'L1 RPC, relay-ship priority (B → A)',                 phase: 3 },
    { p: 'cairo/bravo_verify.cairo',               d: 'SAFE_AREA verification program (Bravo)',              phase: 3 }
  ]
};

const SHARED_L1_CONTRACTS = [
  { p: 'contracts/Verifier.sol',    d: 're-runs FRI on submitted STARK proofs; on dual SAFE auto-calls CommandLog.advance()', phase: 2 },
  { p: 'contracts/Registry.sol',    d: 'mission spec + verdict per EX-0xx',      phase: 2 },
  { p: 'contracts/CommandLog.sol',  d: 'records the advance event; only the Verifier (or D for manual override) may call', phase: 2 }
];

// ---------------------------------------------------------------------------
// SVG construction
// ---------------------------------------------------------------------------

function el(name, attrs = {}) {
  const node = document.createElementNS(SVG_NS, name);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, String(v));
  return node;
}

function image(href, x, y, w, h) {
  const img = el('image', { x, y, width: w, height: h, href });
  img.setAttributeNS(XLINK_NS, 'xlink:href', href); // legacy Safari
  return img;
}

const HEADER_H   = 30;
const CARD_PAD   = 8;
// Vertical (ship) layout
const V_CARD_H   = 38, V_CARD_GAP = 4, V_ICON = 20;
// Horizontal (L2) layout — sequence-diagram-style column headers
// (one card per actor in the proof-generation pipeline).
const H_CARD_W   = 110, H_CARD_H = 100, H_CARD_GAP = 14;
const H_ICON     = 26;
const STEP_R     = 8;

function buildContainer(c) {
  const g = el('g', {
    class: `arch-container kind-${c.kind}`,
    'data-id': c.id,
    transform: `translate(${c.x} ${c.y})`
  });
  g.style.cursor = 'pointer';

  // Body
  g.appendChild(el('rect', {
    x: 0, y: 0, width: c.w, height: c.h, rx: 8, ry: 8, class: 'arch-body'
  }));

  // Header strip (rounded top, square bottom via overlay rect)
  g.appendChild(el('rect', {
    x: 0, y: 0, width: c.w, height: HEADER_H, rx: 8, ry: 8, class: 'arch-header'
  }));
  g.appendChild(el('rect', {
    x: 0, y: HEADER_H - 8, width: c.w, height: 8, class: 'arch-header'
  }));

  // Header — name + docker badge
  const nameText = el('text', { x: 12, y: 20, class: 'arch-name' });
  nameText.textContent = c.id.startsWith('L2') ? c.id.replace('L2', 'L2-') : `Ship ${c.id}`;
  g.appendChild(nameText);

  const dockerLogo = image('images/docker.png', c.w - 70, 8, 14, 14);
  dockerLogo.setAttribute('opacity', '0.7');
  g.appendChild(dockerLogo);

  const dockerText = el('text', {
    x: c.w - 12, y: 20, class: 'arch-docker', 'text-anchor': 'end'
  });
  dockerText.textContent = 'DOCKER';
  g.appendChild(dockerText);

  const services = SERVICES[c.kind] || [];
  const isL2 = c.kind.startsWith('l2-');

  if (isL2) renderHorizontalServices(g, c, services);
  else      renderVerticalServices(g, c, services);

  return g;
}

// Horizontal pipeline: 5 service tiles in a row showing icon + package name +
// short role label. The architecture view answers "what's running"; flow
// detail (sequence arrows, step numbers) lives in the Transaction flow
// diagram, not here.
function renderHorizontalServices(g, c, services) {
  const innerY = HEADER_H + 8;
  const totalW = services.length * H_CARD_W + (services.length - 1) * H_CARD_GAP;
  const xStart = (c.w - totalW) / 2;
  let xOff = xStart;

  for (let i = 0; i < services.length; i++) {
    const s = services[i];

    // Card body
    g.appendChild(el('rect', {
      x: xOff, y: innerY,
      width: H_CARD_W, height: H_CARD_H,
      rx: 5, ry: 5,
      class: `svc-card stage-${s.stage || 'plain'}`
    }));

    // Logo centred horizontally near the top
    g.appendChild(image(
      s.icon,
      xOff + (H_CARD_W - H_ICON) / 2,
      innerY + 14,
      H_ICON, H_ICON
    ));

    // Name (centred, bold)
    const nm = el('text', {
      x: xOff + H_CARD_W / 2, y: innerY + 56,
      'text-anchor': 'middle', class: 'svc-name'
    });
    nm.textContent = s.name;
    g.appendChild(nm);

    // Sub (centred, muted)
    const sb = el('text', {
      x: xOff + H_CARD_W / 2, y: innerY + 70,
      'text-anchor': 'middle', class: 'svc-sub'
    });
    sb.textContent = s.sub;
    g.appendChild(sb);

    // Version chip (small, centred under sub)
    if (s.version) {
      const vc = el('text', {
        x: xOff + H_CARD_W / 2, y: innerY + 86,
        'text-anchor': 'middle', class: 'svc-version'
      });
      vc.textContent = s.version;
      g.appendChild(vc);
    }

    xOff += H_CARD_W + H_CARD_GAP;
  }
}

// Vertical layout: single (or two) cards stacked — used by ship containers.
function renderVerticalServices(g, c, services) {
  let yOff = HEADER_H + 6;
  for (let i = 0; i < services.length; i++) {
    const s = services[i];

    g.appendChild(el('rect', {
      x: CARD_PAD, y: yOff,
      width: c.w - 2 * CARD_PAD, height: V_CARD_H,
      rx: 4, ry: 4,
      class: `svc-card stage-${s.stage || 'plain'}`
    }));

    g.appendChild(image(
      s.icon,
      CARD_PAD + 8,
      yOff + (V_CARD_H - V_ICON) / 2,
      V_ICON, V_ICON
    ));

    const textX = CARD_PAD + 8 + V_ICON + 8;
    const nm = el('text', { x: textX, y: yOff + 15, class: 'svc-name' });
    nm.textContent = s.name;
    g.appendChild(nm);

    const sb = el('text', { x: textX, y: yOff + 28, class: 'svc-sub' });
    sb.textContent = s.sub;
    g.appendChild(sb);

    yOff += V_CARD_H + V_CARD_GAP;
  }
}

function buildSvg() {
  const stage = document.getElementById('arch-stage');
  if (!stage) return null;

  const svg = el('svg', {
    viewBox: `0 0 ${VB_W} ${VB_H}`,
    class: 'arch-svg',
    preserveAspectRatio: 'xMidYMid meet'
  });

  // Defs: grid pattern + arrow marker
  const defs = el('defs');

  const pattern = el('pattern', {
    id: 'arch-grid', width: 30, height: 30, patternUnits: 'userSpaceOnUse'
  });
  pattern.appendChild(el('path', {
    d: 'M 30 0 L 0 0 0 30', fill: 'none',
    stroke: '#1a2436', 'stroke-width': 1
  }));
  defs.appendChild(pattern);

  const marker = el('marker', {
    id: 'arch-arrow', viewBox: '0 -5 10 10', refX: 8, refY: 0,
    markerWidth: 6, markerHeight: 6, orient: 'auto'
  });
  marker.appendChild(el('path', { d: 'M 0 -4 L 8 0 L 0 4 z', fill: '#94a3b8' }));
  defs.appendChild(marker);

  // Smaller arrowhead for the in-banner sequence-diagram step messages
  const flowMarker = el('marker', {
    id: 'arch-flow-arrow', viewBox: '0 -4 8 8', refX: 7, refY: 0,
    markerWidth: 5, markerHeight: 5, orient: 'auto'
  });
  flowMarker.appendChild(el('path', { d: 'M 0 -3 L 7 0 L 0 3 z', fill: '#cbd5e1' }));
  defs.appendChild(flowMarker);

  svg.appendChild(defs);

  // Pan/zoom group
  const root = el('g', { class: 'arch-root' });
  svg.appendChild(root);

  // Background grid
  root.appendChild(el('rect', {
    x: 0, y: 0, width: VB_W, height: VB_H, fill: 'url(#arch-grid)'
  }));

  // Faint L1 PoA ring through ship centres (A → B → C → D → E → F → A)
  const ships = CONTAINERS.filter(c => c.kind === 'ship' || c.kind === 'ship-cmdr');
  const ring = ['A', 'B', 'C', 'D', 'E', 'F']
    .map(id => ships.find(s => s.id === id))
    .map(c => `${c.x + c.w / 2},${c.y + c.h / 2}`).join(' ');
  root.appendChild(el('polygon', {
    points: ring,
    fill: 'rgba(79,195,247,0.03)',
    stroke: 'rgba(79,195,247,0.30)',
    'stroke-width': 1.4,
    'stroke-dasharray': '6 5',
    class: 'arch-ring'
  }));

  // (π_α / π_β relay arrows used to render here — moved to the Transaction
  // flow diagram, which is the proper home for cross-layer message arrows.)

  // HVUs — protected, off-network. Dashed border to signal "outside the
  // cryptographic perimeter". They receive D's tactical-radio command
  // (rendered in the simulation), not L1 transactions.
  for (const h of HVUS) {
    const hg = el('g', {
      class: 'arch-hvu',
      transform: `translate(${h.x} ${h.y})`
    });
    hg.appendChild(el('rect', {
      x: 0, y: 0, width: HVU_W, height: HVU_H,
      rx: 6, ry: 6, class: 'arch-hvu-body'
    }));
    const lbl = el('text', {
      x: HVU_W / 2, y: HVU_H / 2 - 1,
      'text-anchor': 'middle', class: 'arch-hvu-label'
    });
    lbl.textContent = h.id;
    hg.appendChild(lbl);
    const sub = el('text', {
      x: HVU_W / 2, y: HVU_H / 2 + 16,
      'text-anchor': 'middle', class: 'arch-hvu-sub'
    });
    sub.textContent = 'off-network';
    hg.appendChild(sub);
    root.appendChild(hg);
  }

  // Containers
  for (const c of CONTAINERS) {
    const g = buildContainer(c);
    g.addEventListener('click', () => {
      if (dragMoved) return;       // suppress click that came from a drag
      selectContainer(c.id);
    });
    root.appendChild(g);
  }

  stage.appendChild(svg);
  return { svg, root };
}

// ---------------------------------------------------------------------------
// Pan / zoom
// ---------------------------------------------------------------------------

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
    y: (clientY - r.top)  * (VB_H / r.height)
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
  // Zoom around the visible centre of the SVG
  const r = svgRef.getBoundingClientRect();
  zoomAt(r.left + r.width / 2, r.top + r.height / 2, factor);
}

function bindInteractions() {
  // Drag-to-pan
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
    // dragMoved is reset by the next mousedown — leaving it set here lets the
    // upcoming click handler skip selection if a drag just ended.
    setTimeout(() => { dragMoved = false; }, 0);
  });

  // Wheel zoom around cursor
  svgRef.addEventListener('wheel', (e) => {
    e.preventDefault();
    const factor = e.deltaY < 0 ? 1.12 : 1 / 1.12;
    zoomAt(e.clientX, e.clientY, factor);
  }, { passive: false });

  // Touch — single-finger pan, pinch zoom
  let touchMode = null, touchStart = null;
  svgRef.addEventListener('touchstart', (e) => {
    if (e.touches.length === 1) {
      touchMode = 'pan';
      touchStart = { x: e.touches[0].clientX, y: e.touches[0].clientY };
    } else if (e.touches.length === 2) {
      touchMode = 'pinch';
      const [t1, t2] = e.touches;
      touchStart = {
        d: Math.hypot(t1.clientX - t2.clientX, t1.clientY - t2.clientY),
        cx: (t1.clientX + t2.clientX) / 2,
        cy: (t1.clientY + t2.clientY) / 2
      };
    }
  }, { passive: true });
  svgRef.addEventListener('touchmove', (e) => {
    if (touchMode === 'pan' && e.touches.length === 1) {
      const t = e.touches[0];
      const dx = t.clientX - touchStart.x;
      const dy = t.clientY - touchStart.y;
      touchStart.x = t.clientX; touchStart.y = t.clientY;
      const r = svgRef.getBoundingClientRect();
      tx += dx * (VB_W / r.width);
      ty += dy * (VB_H / r.height);
      applyTransform();
      e.preventDefault();
    } else if (touchMode === 'pinch' && e.touches.length === 2) {
      const [t1, t2] = e.touches;
      const d = Math.hypot(t1.clientX - t2.clientX, t1.clientY - t2.clientY);
      zoomAt(touchStart.cx, touchStart.cy, d / touchStart.d);
      touchStart.d = d;
      e.preventDefault();
    }
  }, { passive: false });
  svgRef.addEventListener('touchend', () => { touchMode = null; }, { passive: true });

  // Buttons
  document.querySelector('[data-act="zoom-in"]') ?.addEventListener('click', () => zoomCenter(1.25));
  document.querySelector('[data-act="zoom-out"]')?.addEventListener('click', () => zoomCenter(1 / 1.25));
  document.querySelector('[data-act="reset"]')   ?.addEventListener('click', reset);

  // Keyboard: +, -, 0
  window.addEventListener('keydown', (e) => {
    if (!svgRef.matches(':hover') && document.activeElement?.tagName !== 'BODY') return;
    if (e.key === '+' || e.key === '=') { zoomCenter(1.2); e.preventDefault(); }
    else if (e.key === '-' || e.key === '_') { zoomCenter(1 / 1.2); e.preventDefault(); }
    else if (e.key === '0') { reset(); e.preventDefault(); }
  });
}

// ---------------------------------------------------------------------------
// Side panel
// ---------------------------------------------------------------------------

function escape(s) {
  return String(s).replace(/[&<>"']/g, m => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]
  ));
}

function fileRow(f) {
  return `
    <li class="arch-panel-file">
      <a href="${REPO}" target="_blank" rel="noopener" class="arch-file-path">${escape(f.p)}</a>
      <span class="arch-file-phase phase-${f.phase}">Phase ${f.phase}</span>
      <span class="arch-file-desc">${escape(f.d)}</span>
    </li>`;
}

function selectContainer(id) {
  const c = CONTAINERS.find(x => x.id === id);
  if (!c) return;

  document.querySelectorAll('.arch-container.selected')
          .forEach(n => n.classList.remove('selected'));
  document.querySelector(`.arch-container[data-id="${id}"]`)
          ?.classList.add('selected');

  const panel = document.getElementById('arch-panel');
  if (!panel) return;

  const files = FILES[c.kind] || [];
  const isShip = c.kind === 'ship' || c.kind === 'ship-cmdr';
  const isL2 = c.kind.startsWith('l2-');
  const drone = DRONES[c.kind] || null;
  const packages = PACKAGE_SPEC[c.kind] || [];

  // Helper — short github org/repo from full URL for display
  const ghShort = (url) => {
    const m = url.match(/github\.com\/([^\/]+)\/([^\/?#]+)/);
    return m ? `${m[1]}/${m[2]}` : url;
  };

  panel.innerHTML = `
    <div class="arch-panel-header">
      <span class="arch-panel-kind kind-${c.kind}">${KIND_LABEL[c.kind] || ''}</span>
      <h4>${escape(c.name)}</h4>
    </div>

    ${WHAT_IS[c.kind] ? `
      <p class="arch-panel-section-h">What this is</p>
      <p class="arch-panel-prose">${WHAT_IS[c.kind]}</p>
    ` : ''}

    ${isL2 && drone ? `
      <p class="arch-panel-section-h">Drone &mdash; the only client of this L2</p>
      <ul class="arch-panel-drones">
        <li class="drone-row-h">
          <span>drone_id</span>
          <span>account on Madara</span>
          <span>signing keystore</span>
        </li>
        <li class="drone-row drone-solo">
          <span class="drone-id" title="felt252 literal hard-coded in convoy_protocol.cairo">${escape(drone.id)}</span>
          <span class="drone-acct" title="OZ account contract address on Madara — placeholder until Phase 3">${escape(drone.account)}</span>
          <span class="drone-key"  title="JSON keystore holding the Stark-curve private key — placeholder until Phase 3">${escape(drone.key)}</span>
        </li>
      </ul>
      <ul class="drone-caption">
        <li><code>${escape(drone.id)}</code> &mdash; the <code>drone_id</code> felt252 used inside <code>convoy_protocol.cairo</code></li>
        <li><code>${escape(drone.account)}</code> &mdash; placeholder for the OpenZeppelin account contract address on Madara (real address lands at Phase 3 deploy)</li>
        <li><code>${escape(drone.key)}</code> &mdash; placeholder for the JSON keystore holding the Stark-curve private key the drone signs <code>submit_telemetry</code> with</li>
      </ul>
    ` : ''}

    ${packages.length ? `
      <p class="arch-panel-section-h">${isL2 ? 'Stack inventory' : 'Packages running'}</p>
      <ul class="arch-pkg-list">
        ${packages.map(p => `
          <li class="arch-pkg-card">
            <div class="arch-pkg-head">
              <span class="arch-pkg-name">${escape(p.name)}</span>
              <span class="arch-pkg-ver">${escape(p.version)}</span>
              <span class="arch-pkg-license">${escape(p.license)}</span>
            </div>
            <div class="arch-pkg-role">${escape(p.role)}</div>
            <a class="arch-pkg-source" href="${escape(p.source)}" target="_blank" rel="noopener">${escape(ghShort(p.source))}</a>
            ${p.note ? `<div class="arch-pkg-note">${escape(p.note)}</div>` : ''}
          </li>
        `).join('')}
      </ul>
    ` : ''}

    ${(CRYPTO_IN_PLAY[c.kind] || []).length ? `
      <p class="arch-panel-section-h">Crypto provided</p>
      <ul class="arch-panel-crypto">
        ${CRYPTO_IN_PLAY[c.kind].map(x => `
          <li><strong>${escape(x.p)}</strong> &mdash; ${x.d}</li>
        `).join('')}
      </ul>
    ` : ''}

    ${(TRUST_SPEC[c.kind] || []).length ? `
      <p class="arch-panel-section-h">Specification &mdash; trust boundary</p>
      <ul class="arch-panel-trust">
        ${TRUST_SPEC[c.kind].map(x => `
          <li class="mark-${x.mark}"><span class="mark-icon"></span><span>${x.t}</span></li>
        `).join('')}
      </ul>
    ` : ''}

    <p class="arch-panel-section-h">Files</p>
    <ul class="arch-panel-files">
      ${files.map(fileRow).join('')}
      ${isShip ? `
        <li class="arch-panel-section">Shared L1 contracts &mdash; deployed once, every Geth node holds the same state</li>
        ${SHARED_L1_CONTRACTS.map(fileRow).join('')}
      ` : ''}
    </ul>
    <p class="arch-panel-foot">All file paths and account placeholders are stubs. Real values land when Phase ${isShip ? 2 : 3} ships. Contract endpoints, mission lifecycle, and L1 settlement bridge live in the Transaction flow diagram (next section).</p>
  `;
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

function init() {
  if (!document.getElementById('arch-stage')) return;
  const built = buildSvg();
  if (!built) return;
  svgRef = built.svg;
  rootRef = built.root;
  applyTransform();
  bindInteractions();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

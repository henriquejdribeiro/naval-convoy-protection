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
const L2_W   = 720, L2_H   = 380;   // tall — actor row at top + lifelines
                                     // with 10 step-arrows below (steps 9-18
                                     // of the proof generation flow)

const CONTAINERS = [
  // Top of the convoy. Layout: 100 left margin, 720 L2A, 80 corridor, 200 F,
  // 80 ship-HVU gap, 200 HVU, 80 ship-HVU gap, 200 B, 80 corridor, 720 L2B,
  // 100 right margin = VB_W 2580. The 80 ship-HVU gap is the visible
  // breathing room around each HVU at the rendered scale.
  { id: 'A',   kind: 'ship',      name: 'Ship A — Forward',           x: 1200, y: 40,  w: SHIP_W, h: SHIP_H },
  // L2 banners — vertical centre aligns with F / B vertical centre
  { id: 'L2A', kind: 'l2-alpha',  name: 'L2-Alpha — Madara α swarm',   x: 120,  y: 55,  w: L2_W,   h: L2_H   },
  { id: 'F',   kind: 'ship',      name: 'Ship F — Forward-left',      x: 920,  y: 200, w: SHIP_W, h: SHIP_H },
  { id: 'B',   kind: 'ship',      name: 'Ship B — Forward-right',     x: 1480, y: 200, w: SHIP_W, h: SHIP_H },
  { id: 'L2B', kind: 'l2-bravo',  name: 'L2-Bravo — Madara β swarm',   x: 1760, y: 55,  w: L2_W,   h: L2_H   },
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

// Proof-generation flow inside an L2 swarm — mirrors steps 9–18 of the
// sequence diagram in verifiable_grid/architecture/layers.html.
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

const KIND_LABEL = {
  'ship':      'L1 VALIDATOR',
  'ship-cmdr': 'COMMANDER · L1 VALIDATOR',
  'l2-alpha':  'L2-ALPHA',
  'l2-bravo':  'L2-BRAVO'
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
    { p: 'docker/l2-alpha/pathfinder/config.toml', d: 'indexer + JSON-RPC for Alpha drones',                 phase: 3 },
    { p: 'docker/l2-alpha/orchestrator.toml',      d: 'L1 RPC, relay-ship priority (F → A)',                 phase: 3 },
    { p: 'cairo/alpha_verify.cairo',               d: 'SAFE_AREA verification program (Alpha)',              phase: 3 }
  ],
  'l2-bravo': [
    { p: 'docker/l2-bravo/docker-compose.yml',     d: 'Madara β + Pathfinder + SNOS + Stone + orchestrator', phase: 3 },
    { p: 'docker/l2-bravo/madara/config.toml',     d: 'sequencer params, settlement contract on L1',         phase: 3 },
    { p: 'docker/l2-bravo/pathfinder/config.toml', d: 'indexer + JSON-RPC for Bravo drones',                 phase: 3 },
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
// Horizontal (L2) layout — sequence-diagram-style column headers,
// matching the actor row from the verifiable_grid layers.html.
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

// Horizontal pipeline: 5 column-header cards in a row, then a mini
// sequence diagram (lifelines + step-arrows) below — mirrors layers.html
// in the verifiable_grid project.
function renderHorizontalServices(g, c, services) {
  const innerY = HEADER_H + 8;
  const totalW = services.length * H_CARD_W + (services.length - 1) * H_CARD_GAP;
  const xStart = (c.w - totalW) / 2;
  let xOff = xStart;

  // Collect each actor's lifeline x-position so we can draw arrows after.
  const lifelineX = [];

  for (let i = 0; i < services.length; i++) {
    const s = services[i];

    // Card body
    g.appendChild(el('rect', {
      x: xOff, y: innerY,
      width: H_CARD_W, height: H_CARD_H,
      rx: 5, ry: 5,
      class: `svc-card stage-${s.stage || 'plain'}`
    }));

    // Step-number badge top-left
    g.appendChild(el('circle', {
      cx: xOff + STEP_R + 4, cy: innerY + STEP_R + 4,
      r: STEP_R, class: `svc-step stage-${s.stage || 'plain'}`
    }));
    const num = el('text', {
      x: xOff + STEP_R + 4, y: innerY + STEP_R + 7.5,
      'text-anchor': 'middle', class: 'svc-step-num'
    });
    num.textContent = String(i + 1);
    g.appendChild(num);

    // Logo centred horizontally near the top
    g.appendChild(image(
      s.icon,
      xOff + (H_CARD_W - H_ICON) / 2,
      innerY + 22,
      H_ICON, H_ICON
    ));

    // Name (centred, bold)
    const nm = el('text', {
      x: xOff + H_CARD_W / 2, y: innerY + 64,
      'text-anchor': 'middle', class: 'svc-name'
    });
    nm.textContent = s.name;
    g.appendChild(nm);

    // Sub (centred, muted)
    const sb = el('text', {
      x: xOff + H_CARD_W / 2, y: innerY + 78,
      'text-anchor': 'middle', class: 'svc-sub'
    });
    sb.textContent = s.sub;
    g.appendChild(sb);

    lifelineX.push(xOff + H_CARD_W / 2);
    xOff += H_CARD_W + H_CARD_GAP;
  }

  // ── Mini sequence diagram below the actor row ─────────────
  const cardsBottom = innerY + H_CARD_H;
  const flowTop     = cardsBottom + 14;
  const flowBottom  = c.h - 12;
  const stepRows    = L2_FLOW.length;
  const rowGap      = (flowBottom - flowTop) / (stepRows + 0.5);

  // Vertical lifelines descending from each actor card
  for (const x of lifelineX) {
    g.appendChild(el('line', {
      x1: x, y1: cardsBottom + 2,
      x2: x, y2: flowBottom,
      class: 'arch-lifeline'
    }));
  }

  // Step arrows
  for (let i = 0; i < L2_FLOW.length; i++) {
    const ev = L2_FLOW[i];
    const rowY = flowTop + (i + 0.5) * rowGap;
    const fromX = lifelineX[ev.from];
    const toX   = lifelineX[ev.to];

    if (ev.kind === 'self') {
      // Self-loop on the actor's own lifeline. Default to drawing it on the
      // RIGHT side, but flip LEFT when the actor sits near the banner's
      // right edge and there isn't room — keeps the loop + label inside the
      // green / purple container.
      const loopW = 26, loopH = Math.min(10, rowGap * 0.7);
      const labelEstW  = (ev.label || '').length * 5.6;
      const rightSpace = (c.w - CARD_PAD) - fromX;
      const goLeft = rightSpace < (loopW + 10 + labelEstW);
      const dir = goLeft ? -1 : 1;

      g.appendChild(el('path', {
        d: `M ${fromX} ${rowY} L ${fromX + dir * loopW} ${rowY} ` +
           `L ${fromX + dir * loopW} ${rowY + loopH} ` +
           `L ${fromX + dir * 4} ${rowY + loopH}`,
        class: 'arch-flow-line',
        'marker-end': 'url(#arch-flow-arrow)'
      }));
      drawStepBadge(g, fromX, rowY, ev.step);
      const lbl = el('text', {
        x: fromX + dir * (loopW + 6), y: rowY + loopH / 2 + 3,
        'text-anchor': goLeft ? 'end' : 'start',
        class: 'arch-flow-label'
      });
      lbl.textContent = ev.label;
      g.appendChild(lbl);
    } else {
      // Horizontal message arrow between two lifelines
      const dir = toX > fromX ? 1 : -1;
      const x1 = fromX + dir * 4;   // small offset off the source lifeline
      const x2 = toX   - dir * 2;   // arrow tip just before target lifeline
      g.appendChild(el('line', {
        x1, y1: rowY, x2, y2: rowY,
        class: 'arch-flow-line',
        'marker-end': 'url(#arch-flow-arrow)'
      }));
      drawStepBadge(g, fromX, rowY, ev.step);
      const lbl = el('text', {
        x: (fromX + toX) / 2, y: rowY - 4,
        'text-anchor': 'middle', class: 'arch-flow-label'
      });
      lbl.textContent = ev.label;
      g.appendChild(lbl);
    }
  }
}

// Small numbered circle (white text on dark fill) anchored at (x, y).
function drawStepBadge(g, x, y, n) {
  g.appendChild(el('circle', {
    cx: x, cy: y, r: 7, class: 'arch-flow-step'
  }));
  const t = el('text', {
    x: x, y: y + 2.5, 'text-anchor': 'middle',
    class: 'arch-flow-step-num'
  });
  t.textContent = String(n);
  g.appendChild(t);
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

  // Relay arrows: L2-Alpha hands π_α sideways into F;
  //               L2-Bravo hands π_β sideways into B.
  // Picks the closest edges based on relative container position so the
  // arrow stays clean whether L2 sits on a flank or above the convoy.
  function relay(fromId, toId, color, label) {
    const a = CONTAINERS.find(c => c.id === fromId);
    const b = CONTAINERS.find(c => c.id === toId);
    const aCx = a.x + a.w / 2, aCy = a.y + a.h / 2;
    const bCx = b.x + b.w / 2, bCy = b.y + b.h / 2;

    let x1, y1, x2, y2, labelDy;
    if (Math.abs(aCx - bCx) > Math.abs(aCy - bCy)) {
      // Horizontal flow — connect the facing left/right edges
      y1 = aCy; y2 = bCy;
      if (aCx < bCx) { x1 = a.x + a.w; x2 = b.x; }
      else            { x1 = a.x;       x2 = b.x + b.w; }
      labelDy = -10;
    } else {
      // Vertical flow — connect the facing top/bottom edges
      x1 = aCx; x2 = bCx;
      if (aCy < bCy) { y1 = a.y + a.h; y2 = b.y; }
      else            { y1 = a.y;       y2 = b.y + b.h; }
      labelDy = 0;
    }

    root.appendChild(el('line', {
      x1, y1, x2, y2,
      stroke: color, 'stroke-width': 2.5, 'stroke-dasharray': '7 5',
      'marker-end': 'url(#arch-arrow)', opacity: 0.85
    }));
    const lbl = el('text', {
      x: (x1 + x2) / 2, y: (y1 + y2) / 2 + labelDy,
      'text-anchor': 'middle',
      class: 'arch-edge-label', fill: color
    });
    lbl.textContent = label;
    root.appendChild(lbl);
  }
  relay('L2A', 'F', '#22c55e', 'π_α  relay');
  relay('L2B', 'B', '#8b5cf6', 'π_β  relay');

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
  const services = SERVICES[c.kind] || [];

  panel.innerHTML = `
    <div class="arch-panel-header">
      <span class="arch-panel-kind kind-${c.kind}">${KIND_LABEL[c.kind] || ''}</span>
      <h4>${escape(c.name)}</h4>
      ${isL2 ? '<p class="arch-panel-flow">Proof generation flow ↓</p>' : ''}
      <ul class="arch-panel-services">
        ${services.map((s, i) => `
          <li class="stage-${s.stage || 'plain'}">
            ${isL2 ? `<span class="svc-step-pill stage-${s.stage || 'plain'}">${i + 1}</span>` : ''}
            <img src="${escape(s.icon)}" alt="" class="svc-icon"/>
            <span><strong>${escape(s.name)}</strong> &mdash; ${escape(s.sub)}</span>
          </li>
        `).join('')}
      </ul>
    </div>
    <ul class="arch-panel-files">
      ${files.map(fileRow).join('')}
      ${isShip ? `
        <li class="arch-panel-section">Shared L1 contracts &mdash; deployed once, every Geth node holds the same state</li>
        ${SHARED_L1_CONTRACTS.map(fileRow).join('')}
      ` : ''}
    </ul>
    <p class="arch-panel-foot">All file paths are placeholders. The actual layout will be finalised when Phase ${isShip ? 2 : 3} ships.</p>
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

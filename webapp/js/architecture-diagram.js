// ============================================================================
// Architecture diagram — the "how": every Docker container, services inside,
// click-to-see files. Pannable / zoomable SVG.
// ============================================================================

const REPO = 'https://github.com/henriquejdribeiro/naval-convoy-protection';
const SVG_NS = 'http://www.w3.org/2000/svg';
const XLINK_NS = 'http://www.w3.org/1999/xlink';

const VB_W = 1240;
const VB_H = 640;

// ---------------------------------------------------------------------------
// Layout — mirrors the convoy formation: A top, D commander bottom,
// L2 swarms on the flanks, validator ring connects all six ships.
// ---------------------------------------------------------------------------

const SHIP_W = 170, SHIP_H = 90;
const CMDR_W = 170, CMDR_H = 130;
const L2_W   = 230, L2_H   = 295;

const CONTAINERS = [
  { id: 'A',   kind: 'ship',      name: 'Ship A — Forward',          x: 535, y: 20,  w: SHIP_W, h: SHIP_H },
  { id: 'L2A', kind: 'l2-alpha',  name: 'L2-Alpha — Madara α swarm',  x: 10,  y: 175, w: L2_W,   h: L2_H   },
  { id: 'F',   kind: 'ship',      name: 'Ship F — Rear-left',        x: 290, y: 200, w: SHIP_W, h: SHIP_H },
  { id: 'B',   kind: 'ship',      name: 'Ship B — Forward-right',    x: 780, y: 200, w: SHIP_W, h: SHIP_H },
  { id: 'L2B', kind: 'l2-bravo',  name: 'L2-Bravo — Madara β swarm',  x: 1000, y: 175, w: L2_W,   h: L2_H   },
  { id: 'E',   kind: 'ship',      name: 'Ship E — Mid-left',         x: 290, y: 340, w: SHIP_W, h: SHIP_H },
  { id: 'C',   kind: 'ship',      name: 'Ship C — Mid-right',        x: 780, y: 340, w: SHIP_W, h: SHIP_H },
  { id: 'D',   kind: 'ship-cmdr', name: 'Ship D — Commander',        x: 535, y: 480, w: CMDR_W, h: CMDR_H }
];

// L2 services are ordered by *proof generation flow*:
// Madara executes → Pathfinder indexes → Orchestrator coordinates →
// SNOS replays trace → Stone produces the STARK.
const SERVICES = {
  'ship': [
    { icon: 'images/ethereum.png', name: 'Geth (Clique PoA)', sub: 'L1 Ethereum node — validator key' }
  ],
  'ship-cmdr': [
    { icon: 'images/ethereum.png', name: 'Geth (Clique PoA)', sub: 'L1 Ethereum node — validator key' },
    { icon: 'images/nodejs.png',   name: 'Commander watcher', sub: 'fires advance() on dual SAFE'    }
  ],
  'l2-alpha': [
    { icon: 'images/madara.png',       name: 'Madara α',     sub: 'Execution layer (Cairo VM)',    stage: 'exec'  },
    { icon: 'images/pathfinder.png',   name: 'Pathfinder',   sub: 'Indexer · Starknet RPC',        stage: 'exec'  },
    { icon: 'images/madara.png',       name: 'Orchestrator', sub: 'Coordinates proving → L1',      stage: 'exec'  },
    { icon: 'images/snos.jpg',         name: 'SNOS',         sub: 'Replays trace · prover input',  stage: 'prove' },
    { icon: 'images/stone-prover.svg', name: 'Stone prover', sub: 'Generates STARK proof π_α',     stage: 'prove' }
  ],
  'l2-bravo': [
    { icon: 'images/madara.png',       name: 'Madara β',     sub: 'Execution layer (Cairo VM)',    stage: 'exec'  },
    { icon: 'images/pathfinder.png',   name: 'Pathfinder',   sub: 'Indexer · Starknet RPC',        stage: 'exec'  },
    { icon: 'images/madara.png',       name: 'Orchestrator', sub: 'Coordinates proving → L1',      stage: 'exec'  },
    { icon: 'images/snos.jpg',         name: 'SNOS',         sub: 'Replays trace · prover input',  stage: 'prove' },
    { icon: 'images/stone-prover.svg', name: 'Stone prover', sub: 'Generates STARK proof π_β',     stage: 'prove' }
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
    { p: 'docker/commander/watch.js',          d: 'watches L1 for both SAFE events, fires advance tx', phase: 2 }
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
  { p: 'contracts/Verifier.sol',    d: 're-runs FRI on submitted STARK proofs',  phase: 2 },
  { p: 'contracts/Registry.sol',    d: 'mission spec + verdict per EX-0xx',      phase: 2 },
  { p: 'contracts/CommandLog.sol',  d: 'commander advance events',               phase: 2 }
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

const CARD_PAD = 8;          // horizontal padding from container edge
const HEADER_H = 30;
const CARD_H   = 38;         // each service card height
const CARD_GAP = 4;          // gap between cards (no flow arrow)
const FLOW_GAP = 14;         // gap between cards when a flow arrow goes between
const ICON_SIZE = 20;
const STEP_R   = 8;          // step-number badge radius

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

  // Header — name + docker badge (logo + text)
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

  // Service cards stacked vertically — for L2s, the order is the proof flow
  const services = SERVICES[c.kind] || [];
  const isL2 = c.kind.startsWith('l2-');
  let yOff = HEADER_H + 6;

  for (let i = 0; i < services.length; i++) {
    const s = services[i];
    const isLast = i === services.length - 1;

    // Card rect — tinted by stage (exec = warm, prove = cool)
    g.appendChild(el('rect', {
      x: CARD_PAD, y: yOff,
      width: c.w - 2 * CARD_PAD, height: CARD_H,
      rx: 4, ry: 4,
      class: `svc-card stage-${s.stage || 'plain'}`
    }));

    // Step-number badge on the left (L2 only — ships have just 1 service)
    let textX;
    if (isL2) {
      g.appendChild(el('circle', {
        cx: CARD_PAD + STEP_R + 4, cy: yOff + CARD_H / 2,
        r: STEP_R, class: `svc-step stage-${s.stage || 'plain'}`
      }));
      const num = el('text', {
        x: CARD_PAD + STEP_R + 4, y: yOff + CARD_H / 2 + 3.5,
        'text-anchor': 'middle', class: 'svc-step-num'
      });
      num.textContent = String(i + 1);
      g.appendChild(num);

      // Icon shifted right of the badge
      g.appendChild(image(
        s.icon,
        CARD_PAD + STEP_R * 2 + 12,
        yOff + (CARD_H - ICON_SIZE) / 2,
        ICON_SIZE, ICON_SIZE
      ));
      textX = CARD_PAD + STEP_R * 2 + 12 + ICON_SIZE + 8;
    } else {
      g.appendChild(image(
        s.icon,
        CARD_PAD + 8,
        yOff + (CARD_H - ICON_SIZE) / 2,
        ICON_SIZE, ICON_SIZE
      ));
      textX = CARD_PAD + 8 + ICON_SIZE + 8;
    }

    // Name + subtitle
    const nm = el('text', { x: textX, y: yOff + 15, class: 'svc-name' });
    nm.textContent = s.name;
    g.appendChild(nm);

    const sb = el('text', { x: textX, y: yOff + 28, class: 'svc-sub' });
    sb.textContent = s.sub;
    g.appendChild(sb);

    yOff += CARD_H;

    // Flow arrow between consecutive L2 cards
    if (isL2 && !isLast) {
      const ax = c.w / 2;
      const ay = yOff + 4;
      const path = el('path', {
        d: `M ${ax - 5} ${ay} L ${ax + 5} ${ay} L ${ax} ${ay + 6} Z`,
        class: 'svc-flow-arrow'
      });
      g.appendChild(path);
      yOff += FLOW_GAP;
    } else {
      yOff += CARD_GAP;
    }
  }

  return g;
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

  // Relay arrows: L2-Alpha → F (π_α), L2-Bravo → B (π_β)
  function relay(fromId, toId, color, label) {
    const a = CONTAINERS.find(c => c.id === fromId);
    const b = CONTAINERS.find(c => c.id === toId);
    const x1 = a.x + a.w, y1 = a.y + a.h / 2;
    const x2 = b.x,        y2 = b.y + b.h / 2;
    root.appendChild(el('line', {
      x1, y1, x2: x2 - 2, y2,
      stroke: color, 'stroke-width': 2.5, 'stroke-dasharray': '7 5',
      'marker-end': 'url(#arch-arrow)', opacity: 0.75
    }));
    const lbl = el('text', {
      x: (x1 + x2) / 2, y: (y1 + y2) / 2 - 8,
      'text-anchor': 'middle', class: 'arch-edge-label', fill: color
    });
    lbl.textContent = label;
    root.appendChild(lbl);
  }
  relay('L2A', 'F', '#22c55e', 'π_α  relay');
  relay('L2B', 'B', '#8b5cf6', 'π_β  relay');

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

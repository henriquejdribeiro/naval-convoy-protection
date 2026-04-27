// ============================================================================
// convoy-sim.js — Naval Convoy Protection: end-to-end mission simulation
// ============================================================================
// Single-page interactive widget that visualises the eight phases of the
// convoy mission, from L1 mission deployment through L2 sweeps, STARK proof
// generation, best-signal proof relay, on-chain verification, and finally
// the commander's convoy advance command.
//
// Design pattern mirrors the thesis Mission 1 widget: a fixed-size frame,
// a frame-timeline model so Prev/Next/Pause are exact and reversible, and
// a single ▶ Play button that auto-walks the whole sequence.
// ============================================================================

import { poseidonHashChain, toHex, toHexShort } from './poseidon-core.js';

// ── Convoy world geometry ────────────────────────────────────────────────
// SVG coordinate space: 0..1000 horizontal, 0..600 vertical.
// Convoy heading is "up" (decreasing y).
//
//   y=0   ┌───────── frontal areas ─────────┐
//         │   left  (zigzag)  │  right (corridor) │
//   y=200 ├───────────────────┴───────────────────┤
//         │   convoy formation (ships)            │
//   y=600 └───────────────────────────────────────┘

const SHIPS = {
    A: { x: 500, y: 320, role: 'forward',         relays: ['alpha', 'bravo'] },
    B: { x: 600, y: 380, role: 'forward-right',   relays: ['bravo']          },
    C: { x: 600, y: 460, role: 'mid-right',       relays: ['bravo']          },
    D: { x: 500, y: 540, role: 'commander',       relays: []                 },
    E: { x: 400, y: 460, role: 'mid-left',        relays: ['alpha']          },
    F: { x: 400, y: 380, role: 'rear-left',       relays: ['alpha']          },
};

const PROTECTED_SHIPS = [
    { x: 500, y: 400 },   // VIP-1
    { x: 500, y: 440 },   // VIP-2
    { x: 500, y: 480 },   // VIP-3
];

// Frontal sweep areas
const ALPHA_AREA = { x: 100, y: 30,  w: 380, h: 180 };  // left zigzag
const BRAVO_AREA = { x: 520, y: 30,  w: 380, h: 180 };  // right corridor

// Alpha drones — zigzag pattern in the left area
const ALPHA_DRONES = generateAlphaSweep();
function generateAlphaSweep() {
    const drones = [];
    // 5 drones, each starts at left edge, sweeps in horizontal bands
    const bands = 5;
    for (let i = 0; i < bands; i++) {
        const baseY = ALPHA_AREA.y + 20 + i * (ALPHA_AREA.h - 40) / (bands - 1);
        // each drone produces a list of waypoints (zigzag right then left)
        const waypoints = [];
        const cells = 8;
        for (let c = 0; c <= cells; c++) {
            const x = ALPHA_AREA.x + 20 + (c / cells) * (ALPHA_AREA.w - 40);
            const yOff = (c % 2 === 0) ? 0 : 18;  // small zigzag amplitude
            waypoints.push({ x, y: baseY + yOff });
        }
        drones.push({ id: `alpha-${i+1}`, waypoints, color: '#22c55e' });
    }
    return drones;
}

// Bravo drones — corridor sweep (length-wise back and forth)
const BRAVO_DRONES = generateBravoSweep();
function generateBravoSweep() {
    const drones = [];
    const lanes = 5;
    for (let i = 0; i < lanes; i++) {
        const x = BRAVO_AREA.x + 20 + i * (BRAVO_AREA.w - 40) / (lanes - 1);
        const waypoints = [];
        const segments = 6;
        for (let s = 0; s <= segments; s++) {
            const y = BRAVO_AREA.y + 20 + (s / segments) * (BRAVO_AREA.h - 40);
            waypoints.push({ x, y });
        }
        drones.push({ id: `bravo-${i+1}`, waypoints, color: '#8b5cf6' });
    }
    return drones;
}

// L1 node (rendered as a central box at the bottom corner)
const L1_NODE = { x: 870, y: 540 };

// ── Compute commitments from drone sweep data ────────────────────────────
// Each sweep cell coordinate is folded into a Poseidon hash chain.
function computeCommitments() {
    // Alpha: collect all waypoints across all drones into one stream
    const alphaFelts = [];
    for (const d of ALPHA_DRONES) {
        for (const wp of d.waypoints) {
            alphaFelts.push(BigInt(Math.round(wp.x)));
            alphaFelts.push(BigInt(Math.round(wp.y)));
        }
    }
    const bravoFelts = [];
    for (const d of BRAVO_DRONES) {
        for (const wp of d.waypoints) {
            bravoFelts.push(BigInt(Math.round(wp.x)));
            bravoFelts.push(BigInt(Math.round(wp.y)));
        }
    }
    return {
        H_alpha: poseidonHashChain(alphaFelts),
        H_bravo: poseidonHashChain(bravoFelts),
        nAlphaFelts: alphaFelts.length,
        nBravoFelts: bravoFelts.length,
    };
}

const COMMITMENTS = computeCommitments();

// ── SVG rendering helpers ─────────────────────────────────────────────────

function renderBaseScene() {
    return `
      <svg viewBox="0 0 1000 600" xmlns="http://www.w3.org/2000/svg">
        <!-- background gradient: deep maritime blue -->
        <defs>
          <radialGradient id="seaGrad" cx="50%" cy="80%" r="80%">
            <stop offset="0%"  stop-color="#0d1a2f"/>
            <stop offset="100%" stop-color="#050810"/>
          </radialGradient>
          <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
            <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#1e293b" stroke-width="0.5"/>
          </pattern>
          <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0,0 L10,5 L0,10 Z" fill="#4fc3f7"/>
          </marker>
          <marker id="arrow-yellow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0,0 L10,5 L0,10 Z" fill="#ffd600"/>
          </marker>
          <marker id="arrow-green" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0,0 L10,5 L0,10 Z" fill="#22c55e"/>
          </marker>
        </defs>
        <rect width="1000" height="600" fill="url(#seaGrad)"/>
        <rect width="1000" height="600" fill="url(#grid)"/>

        <!-- compass / heading indicator -->
        <g transform="translate(50,60)">
          <circle r="22" fill="#0a0e17" stroke="#1e293b"/>
          <path d="M0,-14 L0,12" stroke="#4fc3f7" stroke-width="2" marker-end="url(#arrow)"/>
          <text y="-22" text-anchor="middle" font-family="Consolas,monospace" font-size="9" fill="#4fc3f7">CONVOY HEADING</text>
        </g>
      </svg>
    `;
}

function renderConvoy() {
    let s = '';
    // protected ships in the centre (purple HVU markers)
    for (const p of PROTECTED_SHIPS) {
        s += `<g><circle cx="${p.x}" cy="${p.y}" r="14" fill="#3b1d6b" stroke="#8b5cf6" stroke-width="2"/>
                <text x="${p.x}" y="${p.y+4}" text-anchor="middle" font-size="11" font-family="Consolas,monospace" fill="#c4b5fd">HVU</text></g>`;
    }
    // 6 convoy ships
    for (const [id, sh] of Object.entries(SHIPS)) {
        const isCmd = id === 'D';
        const stroke = isCmd ? '#ffd600' : '#4fc3f7';
        const fill   = isCmd ? '#2a2400' : '#0a1828';
        const glow   = isCmd ? 'filter="url(#cmdGlow)"' : '';
        s += `<g class="ship-g ship-${id}">
                <circle cx="${sh.x}" cy="${sh.y}" r="22" fill="${fill}" stroke="${stroke}" stroke-width="2"/>
                <text x="${sh.x}" y="${sh.y+5}" text-anchor="middle" font-family="Consolas,monospace" font-size="16" font-weight="700" fill="${stroke}">${id}</text>
              </g>`;
    }
    return s;
}

function renderAreas(highlightAlpha = false, highlightBravo = false) {
    const aStroke = highlightAlpha ? '#22c55e' : '#1e3a2e';
    const aFill   = highlightAlpha ? 'rgba(34,197,94,0.08)' : 'rgba(34,197,94,0.03)';
    const bStroke = highlightBravo ? '#8b5cf6' : '#2e1e3a';
    const bFill   = highlightBravo ? 'rgba(139,92,246,0.08)' : 'rgba(139,92,246,0.03)';
    return `
      <rect x="${ALPHA_AREA.x}" y="${ALPHA_AREA.y}" width="${ALPHA_AREA.w}" height="${ALPHA_AREA.h}"
            fill="${aFill}" stroke="${aStroke}" stroke-width="1.5" stroke-dasharray="4,3" rx="6"/>
      <text x="${ALPHA_AREA.x + 8}" y="${ALPHA_AREA.y + 18}" font-family="Consolas,monospace" font-size="11" fill="${aStroke}">EX-010 · LEFT FRONTAL · ALPHA</text>

      <rect x="${BRAVO_AREA.x}" y="${BRAVO_AREA.y}" width="${BRAVO_AREA.w}" height="${BRAVO_AREA.h}"
            fill="${bFill}" stroke="${bStroke}" stroke-width="1.5" stroke-dasharray="4,3" rx="6"/>
      <text x="${BRAVO_AREA.x + 8}" y="${BRAVO_AREA.y + 18}" font-family="Consolas,monospace" font-size="11" fill="${bStroke}">EX-011 · RIGHT FRONTAL · BRAVO</text>
    `;
}

function renderL1Node(highlight = false) {
    const stroke = highlight ? '#ffd600' : '#4fc3f7';
    return `
      <g transform="translate(${L1_NODE.x}, ${L1_NODE.y})">
        <rect x="-50" y="-30" width="100" height="60" rx="6"
              fill="#0a1828" stroke="${stroke}" stroke-width="1.5"/>
        <text y="-14" text-anchor="middle" font-family="Consolas,monospace" font-size="9.5" fill="${stroke}">L1 PoA</text>
        <text y="3"   text-anchor="middle" font-family="Consolas,monospace" font-size="11" font-weight="700" fill="${stroke}">VERIFIER</text>
        <text y="20"  text-anchor="middle" font-family="Consolas,monospace" font-size="8.5" fill="#94a3b8">6 validators</text>
      </g>
    `;
}

// Render drones at a given progress (0..1) along their sweep path
function renderDrones(swarm, progress) {
    if (progress <= 0) return '';
    let s = '';
    for (const d of swarm) {
        const wp = d.waypoints;
        // total path length to interpolate along
        const segCount = wp.length - 1;
        const t = progress * segCount;
        const segIdx = Math.min(Math.floor(t), segCount - 1);
        const segT = t - segIdx;
        const p0 = wp[segIdx];
        const p1 = wp[segIdx + 1];
        const x = p0.x + segT * (p1.x - p0.x);
        const y = p0.y + segT * (p1.y - p0.y);

        // trail (visited waypoints up to current progress)
        let trail = `M ${wp[0].x},${wp[0].y}`;
        for (let i = 1; i <= segIdx; i++) trail += ` L ${wp[i].x},${wp[i].y}`;
        trail += ` L ${x},${y}`;

        s += `<path d="${trail}" stroke="${d.color}" stroke-width="1.2" fill="none" opacity="0.7"/>`;
        s += `<circle cx="${x}" cy="${y}" r="3.5" fill="${d.color}"/>`;
        s += `<circle cx="${x}" cy="${y}" r="7"   fill="${d.color}" opacity="0.25"/>`;
    }
    return s;
}

// Coverage cell heatmap during sweep
function renderCoverageCells(swarm, progress, colorWith) {
    if (progress <= 0) return '';
    let s = '';
    const totalCells = swarm.length * (swarm[0].waypoints.length - 1);
    const visitedCells = Math.floor(progress * totalCells);
    let cellCount = 0;
    for (const d of swarm) {
        for (let i = 0; i < d.waypoints.length - 1; i++) {
            if (cellCount >= visitedCells) break;
            const p0 = d.waypoints[i], p1 = d.waypoints[i+1];
            const cx = (p0.x + p1.x) / 2, cy = (p0.y + p1.y) / 2;
            s += `<rect x="${cx-7}" y="${cy-7}" width="14" height="14" fill="${colorWith}" opacity="0.18" rx="2"/>`;
            cellCount++;
        }
    }
    return s;
}

// Animated proof packet line from L2 to a ship to L1
function renderProofRelay(fromX, fromY, toShip, color, progress) {
    if (progress <= 0) return '';
    const ship = SHIPS[toShip];
    const midX = (fromX + ship.x) / 2;
    const midY = (fromY + ship.y) / 2;

    // Stage A: from L2 (above the area) to the ship — progress 0..0.5
    // Stage B: from ship to L1 — progress 0.5..1
    let s = '';
    if (progress < 0.5) {
        const t = progress / 0.5;
        const px = fromX + t * (ship.x - fromX);
        const py = fromY + t * (ship.y - fromY);
        s += `<line x1="${fromX}" y1="${fromY}" x2="${px}" y2="${py}"
                    stroke="${color}" stroke-width="2" stroke-dasharray="6,4"
                    opacity="0.7"/>`;
        s += `<circle cx="${px}" cy="${py}" r="6" fill="${color}"/>`;
        s += `<circle cx="${px}" cy="${py}" r="11" fill="${color}" opacity="0.3"/>`;
    } else {
        const t = (progress - 0.5) / 0.5;
        // full line L2 -> ship
        s += `<line x1="${fromX}" y1="${fromY}" x2="${ship.x}" y2="${ship.y}"
                    stroke="${color}" stroke-width="2" stroke-dasharray="6,4" opacity="0.5"/>`;
        // line ship -> L1 with packet
        const px = ship.x + t * (L1_NODE.x - ship.x);
        const py = ship.y + t * (L1_NODE.y - ship.y);
        s += `<line x1="${ship.x}" y1="${ship.y}" x2="${px}" y2="${py}"
                    stroke="${color}" stroke-width="2.5" opacity="0.85"
                    marker-end="url(#arrow${color === '#22c55e' ? '-green' : color === '#8b5cf6' ? '' : ''})"/>`;
        s += `<circle cx="${px}" cy="${py}" r="6" fill="${color}"/>`;
        s += `<circle cx="${px}" cy="${py}" r="11" fill="${color}" opacity="0.3"/>`;
    }
    return s;
}

// Mission deployment lines from L1 to L2-Alpha and L2-Bravo cluster centres
function renderMissionDeploy(progress) {
    if (progress <= 0) return '';
    const t = progress;
    const aTarget = { x: ALPHA_AREA.x + ALPHA_AREA.w/2, y: ALPHA_AREA.y + ALPHA_AREA.h/2 };
    const bTarget = { x: BRAVO_AREA.x + BRAVO_AREA.w/2, y: BRAVO_AREA.y + BRAVO_AREA.h/2 };
    const apx = L1_NODE.x + t * (aTarget.x - L1_NODE.x);
    const apy = L1_NODE.y + t * (aTarget.y - L1_NODE.y);
    const bpx = L1_NODE.x + t * (bTarget.x - L1_NODE.x);
    const bpy = L1_NODE.y + t * (bTarget.y - L1_NODE.y);
    return `
      <line x1="${L1_NODE.x}" y1="${L1_NODE.y}" x2="${apx}" y2="${apy}"
            stroke="#22c55e" stroke-width="1.5" stroke-dasharray="3,3" opacity="0.6"/>
      <circle cx="${apx}" cy="${apy}" r="5" fill="#22c55e"/>
      <text x="${apx + 12}" y="${apy + 4}" font-family="Consolas,monospace" font-size="10" fill="#22c55e">EX-010</text>

      <line x1="${L1_NODE.x}" y1="${L1_NODE.y}" x2="${bpx}" y2="${bpy}"
            stroke="#8b5cf6" stroke-width="1.5" stroke-dasharray="3,3" opacity="0.6"/>
      <circle cx="${bpx}" cy="${bpy}" r="5" fill="#8b5cf6"/>
      <text x="${bpx + 12}" y="${bpy + 4}" font-family="Consolas,monospace" font-size="10" fill="#c4b5fd">EX-011</text>
    `;
}

// Convoy advance — translate ships forward
function renderConvoyAdvanced(forwardOffset) {
    let s = '';
    for (const p of PROTECTED_SHIPS) {
        s += `<circle cx="${p.x}" cy="${p.y - forwardOffset}" r="14" fill="#3b1d6b" stroke="#8b5cf6" stroke-width="2"/>
              <text x="${p.x}" y="${p.y - forwardOffset + 4}" text-anchor="middle" font-size="11" font-family="Consolas,monospace" fill="#c4b5fd">HVU</text>`;
    }
    for (const [id, sh] of Object.entries(SHIPS)) {
        const isCmd = id === 'D';
        const stroke = isCmd ? '#ffd600' : '#4fc3f7';
        const fill   = isCmd ? '#2a2400' : '#0a1828';
        s += `<circle cx="${sh.x}" cy="${sh.y - forwardOffset}" r="22" fill="${fill}" stroke="${stroke}" stroke-width="2"/>
              <text x="${sh.x}" y="${sh.y - forwardOffset + 5}" text-anchor="middle" font-family="Consolas,monospace" font-size="16" font-weight="700" fill="${stroke}">${id}</text>`;
    }
    // forward speed wake
    s += `<g opacity="0.6">`;
    for (let i = 0; i < 5; i++) {
        s += `<line x1="500" y1="${600 - i*8}" x2="500" y2="${600 - i*8 + 6}" stroke="#4fc3f7" stroke-width="1"/>`;
    }
    s += `</g>`;
    return s;
}

// ── Compose a full scene given a frame's render config ───────────────────
function renderScene(cfg) {
    let s = renderBaseScene();
    // wrap content inside the SVG
    let inner = '';
    inner += renderAreas(cfg.highlightAlpha, cfg.highlightBravo);
    inner += renderMissionDeploy(cfg.deployProgress || 0);
    inner += renderCoverageCells(ALPHA_DRONES, cfg.alphaSweep || 0, '#22c55e');
    inner += renderCoverageCells(BRAVO_DRONES, cfg.bravoSweep || 0, '#8b5cf6');
    inner += renderDrones(ALPHA_DRONES, cfg.alphaSweep || 0);
    inner += renderDrones(BRAVO_DRONES, cfg.bravoSweep || 0);
    if (cfg.alphaProof) {
        const start = { x: ALPHA_AREA.x + ALPHA_AREA.w/2, y: ALPHA_AREA.y + ALPHA_AREA.h/2 };
        inner += renderProofRelay(start.x, start.y, cfg.alphaProof.viaShip, '#22c55e', cfg.alphaProof.progress);
    }
    if (cfg.bravoProof) {
        const start = { x: BRAVO_AREA.x + BRAVO_AREA.w/2, y: BRAVO_AREA.y + BRAVO_AREA.h/2 };
        inner += renderProofRelay(start.x, start.y, cfg.bravoProof.viaShip, '#8b5cf6', cfg.bravoProof.progress);
    }
    if (cfg.advancedOffset > 0) {
        inner += renderConvoyAdvanced(cfg.advancedOffset);
    } else {
        inner += renderConvoy();
    }
    inner += renderL1Node(cfg.l1Highlight);
    if (cfg.commanderActive) {
        // pulse on ship D
        inner += `<circle cx="${SHIPS.D.x}" cy="${SHIPS.D.y}" r="32" fill="none"
                          stroke="#ffd600" stroke-width="2" opacity="0.7">
                    <animate attributeName="r" values="22;38;22" dur="1.6s" repeatCount="indefinite"/>
                    <animate attributeName="opacity" values="0.9;0.1;0.9" dur="1.6s" repeatCount="indefinite"/>
                  </circle>`;
    }

    // inject inner into base scene (between </defs> and </svg>)
    return s.replace('</svg>', inner + '</svg>');
}

// ── Frame timeline ───────────────────────────────────────────────────────
// Each frame is a (config, status, registry, dwell) tuple.
function buildFrames() {
    const F = [];
    const reg = (ex010 = '—', ex011 = '—', commander = 'idle', advance = '—') => ({
        ex010, ex011, commander, advance,
    });

    // Phase 1 — Mission deployment
    F.push({
        phase: '1/8 — mission deployment',
        cfg: { deployProgress: 0, l1Highlight: true },
        badge: 'Deploy', badgeClass: 'deploy',
        text: `Ship D issues two parallel L1 transactions: <code>EX-010</code> &rarr; L2-Alpha and <code>EX-011</code> &rarr; L2-Bravo.`,
        registry: reg('PENDING', 'PENDING', 'idle'),
        dwell: 1500,
    });
    F.push({
        phase: '1/8 — mission deployment',
        cfg: { deployProgress: 1, l1Highlight: true },
        badge: 'Deploy', badgeClass: 'deploy',
        text: `Mission specs broadcast to both L2 chains. Each carries area, coverage threshold &ge; 95&thinsp;%, time window 6 min, detection threshold p &ge; 0.7.`,
        registry: reg('DISPATCHED', 'DISPATCHED', 'idle'),
        dwell: 2200,
    });

    // Phase 2 — Drone sweeps (Alpha + Bravo simultaneously)
    const sweepSteps = 18;
    for (let i = 1; i <= sweepSteps; i++) {
        const p = i / sweepSteps;
        F.push({
            phase: '2/8 — parallel area sweep',
            cfg: {
                deployProgress: 1,
                alphaSweep: p,
                bravoSweep: p,
                highlightAlpha: true, highlightBravo: true,
            },
            badge: 'Sweep', badgeClass: 'sweep',
            text: `Alpha drones zig-zag the left area, Bravo drones cover the right corridor. Coverage <strong>${Math.round(p*100)}&thinsp;%</strong>.`,
            registry: reg('SWEEPING', 'SWEEPING', 'idle'),
            dwell: 220,
        });
    }

    // Phase 3 — Per-cell commitments compile into the chain hash
    F.push({
        phase: '3/8 — Poseidon commitment',
        cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, highlightAlpha: true, highlightBravo: true },
        badge: 'Commit', badgeClass: 'commit',
        text: `Each L2 folds its sweep cells into a Poseidon hash chain: <code>H_α = ${toHexShort(COMMITMENTS.H_alpha, 8, 5)}</code>, <code>H_β = ${toHexShort(COMMITMENTS.H_bravo, 8, 5)}</code>.`,
        registry: reg('COMMITTED', 'COMMITTED', 'idle'),
        dwell: 3000,
    });

    // Phase 4 — STARK proof generation (both L2s working)
    F.push({
        phase: '4/8 — STARK proof generation',
        cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1 },
        badge: 'Prove',  badgeClass: 'prove',
        text: `Stone provers (one per L2) generate STARK proofs <code>π_α</code> and <code>π_β</code>. Inside the proof, the Cairo program asserts coverage &ge; 95&thinsp;%, no contacts above <em>p</em>, and time within window.`,
        registry: reg('PROVING', 'PROVING', 'idle'),
        dwell: 2800,
    });

    // Phase 5 — Best-signal proof relay (Alpha first via F, Bravo via B)
    const relaySteps = 8;
    for (let i = 1; i <= relaySteps; i++) {
        const p = i / relaySteps;
        F.push({
            phase: '5/8 — proof relay (best-signal)',
            cfg: {
                deployProgress: 1, alphaSweep: 1, bravoSweep: 1,
                alphaProof: { viaShip: 'F', progress: p },
                bravoProof: { viaShip: 'B', progress: p },
            },
            badge: 'Relay', badgeClass: 'relay',
            text: p < 0.55
              ? `<code>π_α</code> → ship F (rear-left, primary relay). <code>π_β</code> → ship B (forward-right, primary relay).`
              : `Ships F and B each submit an L1 transaction carrying the proof bytes for cryptographic verification.`,
            registry: reg(p < 0.55 ? 'RELAYING' : 'L1 PENDING',
                          p < 0.55 ? 'RELAYING' : 'L1 PENDING',
                          'idle'),
            dwell: 380,
        });
    }

    // Phase 6 — L1 contract verification
    F.push({
        phase: '6/8 — on-chain verification',
        cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, l1Highlight: true },
        badge: 'Verify', badgeClass: 'verify',
        text: `<code>ConvoyProofVerifier</code> contract checks <code>π_α</code> against <code>H_α</code>. Cryptographic ground truth is established by the L1 verifier, not by ships.`,
        registry: reg('SAFE ✓ (by F)', 'L1 PENDING', 'idle'),
        dwell: 2200,
    });
    F.push({
        phase: '6/8 — on-chain verification',
        cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, l1Highlight: true },
        badge: 'Verify', badgeClass: 'verify',
        text: `Both proofs verified. Registry now reads <code>EX-010 SAFE</code> (validated by F) and <code>EX-011 SAFE</code> (validated by B).`,
        registry: reg('SAFE ✓ (by F)', 'SAFE ✓ (by B)', 'idle'),
        dwell: 2600,
    });

    // Phase 7 — Commander gates
    F.push({
        phase: '7/8 — commander watches',
        cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, commanderActive: true },
        badge: 'Cmd',    badgeClass: 'cmd',
        text: `Ship D detects both SAFE events on L1. The two-of-two precondition is met. Commander preparing the convoy advance command…`,
        registry: reg('SAFE ✓ (by F)', 'SAFE ✓ (by B)', 'gate met'),
        dwell: 2400,
    });
    F.push({
        phase: '7/8 — convoy advance command',
        cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, commanderActive: true, l1Highlight: true },
        badge: 'Cmd',    badgeClass: 'cmd',
        text: `Ship D submits L1 transaction: <code>convoyAdvance(maxSpeed = true)</code>. Event broadcast to all six ships' validators.`,
        registry: reg('SAFE ✓ (by F)', 'SAFE ✓ (by B)', 'gate met', 'BROADCAST'),
        dwell: 2400,
    });

    // Phase 8 — Convoy advances
    const advSteps = 12;
    for (let i = 1; i <= advSteps; i++) {
        F.push({
            phase: '8/8 — convoy advance',
            cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, advancedOffset: i * 8 },
            badge: 'Advance', badgeClass: 'advance',
            text: `Convoy moves forward at maximum speed through the cleared frontal area. Mission cycle complete.`,
            registry: reg('SAFE ✓ (by F)', 'SAFE ✓ (by B)', 'advance issued', 'EXECUTING'),
            dwell: 200,
        });
    }
    F.push({
        phase: '8/8 — cycle complete',
        cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, advancedOffset: advSteps * 8 },
        badge: 'Advance', badgeClass: 'advance',
        text: `All eight phases complete. Both proofs cryptographically anchored on L1; convoy now advancing through verified-safe waters.`,
        registry: reg('SAFE ✓ (by F)', 'SAFE ✓ (by B)', 'advance issued', 'COMPLETE'),
        dwell: 0,
    });

    return F;
}

// ── Demo driver ──────────────────────────────────────────────────────────
class ConvoySim {
    constructor(root) {
        root.innerHTML = `
          <div class="cs-frame">
            <div class="cs-header">
              <div>
                <div class="cs-title">Convoy Mission — End-to-End Simulation</div>
                <div class="cs-subtitle">Two parallel L2 chains · 6-ship PoA · proof relay · two-of-two governance</div>
              </div>
              <div class="cs-phase-badge">— ready —</div>
            </div>
            <div class="cs-canvas">
              <div class="cs-canvas-inner"></div>
            </div>
            <div class="cs-status">
              <div class="cs-status-badge idle">idle</div>
              <div class="cs-status-text">Click ▶ Play to begin the eight-phase walkthrough.</div>
            </div>
            <div class="cs-side">
              <div class="cs-registry">
                <div class="cs-registry-title">L1 mission registry</div>
                <div class="cs-registry-row pending"><span class="k">EX-010 (left)</span><span class="v" id="reg-ex010">—</span></div>
                <div class="cs-registry-row pending"><span class="k">EX-011 (right)</span><span class="v" id="reg-ex011">—</span></div>
              </div>
              <div class="cs-registry">
                <div class="cs-registry-title">Commander &amp; convoy state</div>
                <div class="cs-registry-row pending"><span class="k">Ship D status</span><span class="v" id="reg-cmdr">idle</span></div>
                <div class="cs-registry-row pending"><span class="k">Advance command</span><span class="v" id="reg-adv">—</span></div>
              </div>
            </div>
            <div class="cs-controls">
              <button class="cs-btn cs-prev">◀ Prev</button>
              <button class="cs-btn primary cs-play">▶ Play Demonstration</button>
              <button class="cs-btn cs-next">Next ▶</button>
              <button class="cs-btn cs-reset">⏮ Reset</button>
              <div class="cs-progress"><div class="cs-progress-fill"></div></div>
              <div class="cs-progress-text">— / —</div>
            </div>
          </div>
        `;

        this.canvas      = root.querySelector('.cs-canvas-inner');
        this.phaseBadge  = root.querySelector('.cs-phase-badge');
        this.statusBadge = root.querySelector('.cs-status-badge');
        this.statusText  = root.querySelector('.cs-status-text');
        this.progressBar = root.querySelector('.cs-progress-fill');
        this.progressTxt = root.querySelector('.cs-progress-text');
        this.btnPlay     = root.querySelector('.cs-play');
        this.btnPrev     = root.querySelector('.cs-prev');
        this.btnNext     = root.querySelector('.cs-next');
        this.btnReset    = root.querySelector('.cs-reset');
        this.regEx010    = root.querySelector('#reg-ex010');
        this.regEx011    = root.querySelector('#reg-ex011');
        this.regCmdr     = root.querySelector('#reg-cmdr');
        this.regAdv      = root.querySelector('#reg-adv');

        this.frames = buildFrames();
        this.idx = -1;
        this.playing = false;
        this._timer = null;

        this.btnPlay .addEventListener('click', () => this._togglePlay());
        this.btnPrev .addEventListener('click', () => this._step(-1));
        this.btnNext .addEventListener('click', () => this._step(+1));
        this.btnReset.addEventListener('click', () => this.reset());

        this.reset();
    }

    _renderRegistry(reg) {
        const setRow = (el, val, isSafe = false, isAdvance = false) => {
            el.textContent = val;
            const row = el.closest('.cs-registry-row');
            row.classList.remove('safe', 'pending', 'advance');
            if (isAdvance)               row.classList.add('advance');
            else if (isSafe || (typeof val === 'string' && val.startsWith('SAFE'))) row.classList.add('safe');
            else if (val === '—' || val === 'idle') row.classList.add('pending');
        };
        setRow(this.regEx010, reg.ex010);
        setRow(this.regEx011, reg.ex011);
        setRow(this.regCmdr,  reg.commander, false, reg.commander === 'advance issued');
        setRow(this.regAdv,   reg.advance, false, reg.advance && reg.advance !== '—');
    }

    _renderCurrent() {
        if (this.idx < 0) {
            this.canvas.innerHTML = renderScene({});
            this.phaseBadge.textContent = '— ready —';
            this.statusBadge.className = 'cs-status-badge idle';
            this.statusBadge.textContent = 'idle';
            this.statusText.innerHTML = 'Click ▶ Play to begin the eight-phase walkthrough.';
            this.progressBar.style.width = '0%';
            this.progressTxt.textContent = `— / ${this.frames.length}`;
            this.btnPrev.disabled = true;
            this.btnNext.disabled = false;
            this._renderRegistry({ ex010: '—', ex011: '—', commander: 'idle', advance: '—' });
            return;
        }
        const f = this.frames[this.idx];
        this.canvas.innerHTML = renderScene(f.cfg);
        this.phaseBadge.textContent = f.phase;
        this.statusBadge.className = 'cs-status-badge ' + f.badgeClass;
        this.statusBadge.textContent = f.badge;
        this.statusText.innerHTML = f.text;
        const pct = 100 * (this.idx + 1) / this.frames.length;
        this.progressBar.style.width = pct + '%';
        this.progressTxt.textContent = `${this.idx + 1} / ${this.frames.length}`;
        this.btnPrev.disabled = this.idx <= 0;
        this.btnNext.disabled = this.idx >= this.frames.length - 1;
        this._renderRegistry(f.registry);
    }

    _togglePlay() {
        if (this.playing) this.pause();
        else              this.play();
    }
    play() {
        if (this.idx >= this.frames.length - 1) this.idx = -1;
        this.playing = true;
        this.btnPlay.textContent = '⏸ Pause';
        this.btnPlay.classList.remove('primary');
        this._tick();
    }
    pause() {
        this.playing = false;
        clearTimeout(this._timer); this._timer = null;
        this.btnPlay.textContent = this.idx >= this.frames.length - 1 ? '↻ Replay' : '▶ Play Demonstration';
        this.btnPlay.classList.add('primary');
    }
    _tick() {
        if (!this.playing) return;
        if (this.idx >= this.frames.length - 1) { this.pause(); return; }
        this.idx++;
        this._renderCurrent();
        const dwell = this.frames[this.idx].dwell || 1;
        this._timer = setTimeout(() => this._tick(), dwell);
    }
    _step(dir) {
        this.pause();
        const next = this.idx + dir;
        if (next < -1 || next >= this.frames.length) return;
        this.idx = next;
        this._renderCurrent();
    }
    reset() {
        this.pause();
        this.idx = -1;
        this.btnPlay.textContent = '▶ Play Demonstration';
        this.btnPlay.classList.add('primary');
        this._renderCurrent();
    }
}

// ── Bootstrap ────────────────────────────────────────────────────────────
function init() {
    document.querySelectorAll('.convoy-sim').forEach(root => new ConvoySim(root));
}
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
} else {
    init();
}
window.ConvoySim = { init };

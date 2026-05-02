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
// SVG coordinate space: 0..1000 × 0..600. The grid is 40-unit and EVERY
// node, area corner, and drone waypoint sits on a grid vertex (multiple
// of 40). Convoy heading is "up" (decreasing y).
//
//   y=0   ┌───────── frontal sweep areas ────────┐
//         │  ALPHA (zigzag)   │   BRAVO (corridor) │
//   y=280 ├───────────────────┴───────────────────┤
//         │   convoy formation (6 ships, 3 HVUs)  │
//   y=600 └───────────────────────────────────────┘
//
// L1 is the collective of all six ships' Clique-PoA validators — there is
// no separate L1 box; verification fans out peer-to-peer across the ring.

const GRID = 40;
const VIEW_W = 960;
const VIEW_H = 960;                    // bottom-y of the world
// Zone is at y=120–440 (320 px tall). The convoy starts south of it (y=520+).
// Original viewBox had only 120 px of visible canvas above the zone — not
// enough for the convoy to advance THROUGH the zone and finish in clean
// water on the far side. We extend the viewBox upward by SAFE_BAND so the
// post-zone "after" margin (520 px) equals the pre-zone "before" margin.
const SAFE_BAND = 400;
const VIEW_Y0 = -SAFE_BAND;            // viewBox top (negative = extended)
const VIEW_BOX_H = VIEW_H - VIEW_Y0;   // 1360 — total visible vertical span

// Ships and HVUs centred on x=440 (area-junction column, on grid).
// Horizontal margin = 3 grid squares (120) each side. A and D equidistant
// (120 units) from HVU-2.
const SHIPS = {
    A: { x: 440, y: 520, role: 'forward',         relays: ['alpha', 'bravo'] },
    B: { x: 560, y: 600, role: 'forward-right',   relays: ['bravo']          },
    C: { x: 560, y: 680, role: 'mid-right',       relays: ['bravo']          },
    D: { x: 440, y: 760, role: 'commander',       relays: []                 },
    E: { x: 320, y: 680, role: 'mid-left',        relays: ['alpha']          },
    F: { x: 320, y: 600, role: 'forward-left',    relays: ['alpha']          },
};

const PROTECTED_SHIPS = [
    { x: 440, y: 600 },   // HVU-1
    { x: 440, y: 640 },   // HVU-2 (centre)
    { x: 440, y: 680 },   // HVU-3
];

// L2 sequencer drones — they ARE the drones. Each has a home vertex and a
// sweep path that takes them from home, into the area, through the sweep,
// and back home. Position is interpolated along the path during Phase 2.
const L2_NODES = [
    { id: 'L2-A', home: { x: 200, y: 600 }, color: '#fb923c', sweepKey: 'alpha' },
    { id: 'L2-B', home: { x: 680, y: 600 }, color: '#fb923c', sweepKey: 'bravo' },
];

// Frontal sweep areas — corners on grid. Areas TOUCH at x=440.
// Vertical = 8 squares tall (320). Horizontal margin = 3 squares each side.
const ALPHA_AREA = { x: 120, y: 120, w: 320, h: 320 };   // 320 × 320
const BRAVO_AREA = { x: 440, y: 120, w: 400, h: 320 };   // 400 × 320 (1.25× Alpha)
const ALPHA_CENTER = { x: ALPHA_AREA.x + ALPHA_AREA.w/2, y: ALPHA_AREA.y + ALPHA_AREA.h/2 };
const BRAVO_CENTER = { x: BRAVO_AREA.x + BRAVO_AREA.w/2, y: BRAVO_AREA.y + BRAVO_AREA.h/2 };

// Bravo corridor — the inner band where drones do their actual sweep.
// Pattern matches the spec's a:2a:a layout (a = 2 squares = 80; corridor = 4 squares).
const BRAVO_CORRIDOR = { x: 440, y: 200, w: 400, h: 160 };

// L2-A drone — sensor reaches 2 grid squares (80 units). 4 vertical strokes
// (UP → right → DOWN → right → UP → right → DOWN). Drone enters at the
// area's BOTTOM-left so the first stroke goes UP, matching the spec drawing.
const ALPHA_DRONES = [{
    id: 'L2-A', color: '#ef4444',     // RED (matches the spec sketch)
    sensor: GRID,                      // radius = 1 square (3×3 footprint)
    area: ALPHA_AREA,
    waypoints: buildAlphaVerticalZigZag(),
}];
function buildAlphaVerticalZigZag() {
    // Explicit vertex list in user grid coords (bottom-left origin, y up).
    // Translate to internal pixels (x*40, (24-y)*40).
    const G = (x, y) => ({ x: x * GRID, y: (24 - y) * GRID });
    return [
        G(5, 9),     //  1. home
        G(5, 12),    //  2. 3 north
        G(10, 12),   //  3. 5 east
        G(10, 20),   //  4. 8 north
        G(8, 20),    //  5. 2 west
        G(8, 14),    //  6. 6 south
        G(6, 14),    //  7. 2 west
        G(6, 20),    //  8. 6 north
        G(4, 20),    //  9. 2 west
        G(4, 9),     // 10. 11 south
        G(5, 9),     // 11. 1 east — home
    ];
}

// L2-B drone — sensor reaches 2 grid squares (80 units = 2a). Only 2 horizontal
// sweeps are needed to fully cover the 4-row corridor: sweep at y=200 covers
// rows 1-2, sweep at y=280 covers rows 3-4. Exits at corridor bottom-left.
const BRAVO_DRONES = [{
    id: 'L2-B', color: '#3b82f6',     // BLUE (matches the spec sketch)
    sensor: GRID * 2,                  // radius = 2 squares (5×5 footprint)
    area: BRAVO_CORRIDOR,              // only the corridor counts as covered
    waypoints: buildBravoTwoSweepPath(),
}];
function buildBravoTwoSweepPath() {
    // Explicit vertex list in user grid coords (bottom-left origin, y up).
    const G = (x, y) => ({ x: x * GRID, y: (24 - y) * GRID });
    return [
        G(17, 9),    //  1. home
        G(17, 12),   //  2. 3 north
        G(13, 12),   //  3. 4 west
        G(13, 15),   //  4. 3 north
        G(19, 15),   //  5. 6 east
        G(19, 19),   //  6. 4 north
        G(13, 19),   //  7. 6 west
        G(13, 12),   //  8. 7 south
        G(17, 12),   //  9. 4 east
        G(17, 9),    // 10. 3 south — home
    ];
}

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
      <svg viewBox="0 ${VIEW_Y0} ${VIEW_W} ${VIEW_BOX_H}" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid meet">
        <defs>
          <radialGradient id="seaGrad" cx="50%" cy="80%" r="80%">
            <stop offset="0%"  stop-color="#0d1a2f"/>
            <stop offset="100%" stop-color="#050810"/>
          </radialGradient>
          <!-- 40-unit grid: stronger lines + vertex dots so positions are legible -->
          <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
            <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#243758" stroke-width="0.7"/>
            <circle cx="0" cy="0" r="1" fill="#3a5478"/>
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
          <marker id="arrow-purple" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0,0 L10,5 L0,10 Z" fill="#8b5cf6"/>
          </marker>
          <marker id="arrow-red" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0,0 L10,5 L0,10 Z" fill="#ef4444"/>
          </marker>
          <marker id="arrow-blue" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0,0 L10,5 L0,10 Z" fill="#3b82f6"/>
          </marker>
        </defs>
        <rect x="0" y="${VIEW_Y0}" width="${VIEW_W}" height="${VIEW_BOX_H}" fill="url(#seaGrad)"/>
        <rect x="0" y="${VIEW_Y0}" width="${VIEW_W}" height="${VIEW_BOX_H}" fill="url(#grid)"/>
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
    const aStroke = highlightAlpha ? '#ef4444' : '#3a1d1d';
    const aFill   = highlightAlpha ? 'rgba(239,68,68,0.08)' : 'rgba(239,68,68,0.03)';
    const bStroke = highlightBravo ? '#3b82f6' : '#1d2a3a';
    const bFill   = highlightBravo ? 'rgba(59,130,246,0.08)' : 'rgba(59,130,246,0.03)';
    return `
      <rect x="${ALPHA_AREA.x}" y="${ALPHA_AREA.y}" width="${ALPHA_AREA.w}" height="${ALPHA_AREA.h}"
            fill="${aFill}" stroke="${aStroke}" stroke-width="1.5" stroke-dasharray="4,3" rx="6"/>
      <text x="${ALPHA_AREA.x + 8}" y="${ALPHA_AREA.y + 18}" font-family="Consolas,monospace" font-size="11" fill="${aStroke}">EX-010 · LEFT FRONTAL · ALPHA</text>

      <rect x="${BRAVO_AREA.x}" y="${BRAVO_AREA.y}" width="${BRAVO_AREA.w}" height="${BRAVO_AREA.h}"
            fill="${bFill}" stroke="${bStroke}" stroke-width="1.5" stroke-dasharray="4,3" rx="6"/>
      <text x="${BRAVO_AREA.x + 8}" y="${BRAVO_AREA.y + 18}" font-family="Consolas,monospace" font-size="11" fill="${bStroke}">EX-011 · RIGHT FRONTAL · BRAVO</text>

      <!-- Bravo inner corridor (the 2a band where the actual sweep happens) -->
      <rect x="${BRAVO_CORRIDOR.x}" y="${BRAVO_CORRIDOR.y}" width="${BRAVO_CORRIDOR.w}" height="${BRAVO_CORRIDOR.h}"
            fill="rgba(59,130,246,0.05)" stroke="${bStroke}" stroke-width="1" stroke-dasharray="2,2" rx="3" opacity="0.7"/>
      <text x="${BRAVO_CORRIDOR.x + 8}" y="${BRAVO_CORRIDOR.y - 4}" font-family="Consolas,monospace" font-size="9" fill="${bStroke}" opacity="0.7">corridor 2a</text>
    `;
}

// L1 is the collective of all six ships' validators — there is no separate
// L1 node. When verification happens, every ship's outline pulses green
// (handled inline in renderScene), representing the proof landing on the
// shared chain.
function renderL1Node() { return ''; }

// Position along a waypoint path at progress p ∈ [0,1].
function positionAlongPath(wp, p) {
    if (p <= 0) return { ...wp[0] };
    if (p >= 1) return { ...wp[wp.length - 1] };
    const segCount = wp.length - 1;
    const t = p * segCount;
    const segIdx = Math.min(Math.floor(t), segCount - 1);
    const segT = t - segIdx;
    const a = wp[segIdx], b = wp[segIdx + 1];
    return { x: a.x + segT * (b.x - a.x), y: a.y + segT * (b.y - a.y) };
}

// L2 sequencer drones — orange labelled circles. Position is at home when
// idle; during sweep they travel along their path (entry → sweep → return).
// During convoy advance they translate forward with the rest of the formation
// but don't paint new coverage cells (they're not on a sweep mission anymore).
function renderL2Nodes(alphaProgress, bravoProgress, advanceOffset = 0) {
    let s = '';
    for (const n of L2_NODES) {
        const prog = (n.sweepKey === 'alpha') ? alphaProgress : bravoProgress;
        const path = (n.sweepKey === 'alpha') ? ALPHA_DRONES[0].waypoints : BRAVO_DRONES[0].waypoints;
        const base = (prog > 0) ? positionAlongPath(path, prog) : n.home;
        const cx = base.x;
        const cy = base.y - advanceOffset;     // travel forward with the convoy
        s += `<g class="l2-node">
                <circle cx="${cx}" cy="${cy}" r="20"
                        fill="#1a0e05" stroke="${n.color}" stroke-width="2"/>
                <text x="${cx}" y="${cy + 4}" text-anchor="middle"
                      font-family="Consolas,monospace" font-size="10"
                      font-weight="700" fill="${n.color}">${n.id}</text>
              </g>`;
    }
    return s;
}

// Render drones at a given progress (0..1) along their sweep path
// Trail of where the L2 drone has been so far. The drone itself is rendered
// as the orange L2 node in renderL2Nodes (it sits on top of this trail).
function renderDrones(swarm, progress) {
    if (progress <= 0) return '';
    let s = '';
    for (const d of swarm) {
        const wp = d.waypoints;
        const segCount = wp.length - 1;
        const t = progress * segCount;
        const segIdx = Math.min(Math.floor(t), segCount - 1);
        const segT = t - segIdx;
        const p0 = wp[segIdx];
        const p1 = wp[segIdx + 1];
        const x = p0.x + segT * (p1.x - p0.x);
        const y = p0.y + segT * (p1.y - p0.y);

        let trail = `M ${wp[0].x},${wp[0].y}`;
        for (let i = 1; i <= segIdx; i++) trail += ` L ${wp[i].x},${wp[i].y}`;
        trail += ` L ${x},${y}`;

        s += `<path d="${trail}" stroke="${d.color}" stroke-width="1.5" fill="none" opacity="0.7"/>`;
    }
    return s;
}

// Coverage cell heatmap during sweep — paints the 40×40 grid square the
// drone is sweeping as it traverses each segment. Makes "area cleared"
// visually unambiguous.
// Paints coverage cells as the drone passes through. Sensor reach is a
// RADIUS — at each grid step the drone visits, every cell within `radius`
// in any direction (square footprint of (2r+1)×(2r+1)) is marked covered.
// Cells are drawn EVERYWHERE the drone passes; the assigned `area` is what
// gets cryptographically validated, but the sensor shadow is drawn freely.
function renderCoverageCells(swarm, progress, colorWith) {
    if (progress <= 0) return '';
    let s = '';
    for (const d of swarm) {
        const sensor = d.sensor || GRID;          // sensor radius in pixels
        const radius = Math.round(sensor / GRID); // sensor radius in grid units
        const wp     = d.waypoints;
        const segCount = wp.length - 1;
        const t = progress * segCount;
        const upToSeg = Math.floor(t);
        const segT = t - upToSeg;

        // Set of `${gx},${gy}` grid cells covered so far.
        const visited = new Set();

        for (let i = 0; i <= Math.min(upToSeg, segCount - 1); i++) {
            const p0 = wp[i], p1 = wp[i+1];
            const segProg = (i < upToSeg) ? 1 : segT;
            const dx = p1.x - p0.x, dy = p1.y - p0.y;
            const segLen = Math.max(Math.abs(dx), Math.abs(dy));
            const steps = Math.max(1, Math.round(segLen / GRID));
            const visitedSteps = Math.max(1, Math.round(segProg * steps));

            for (let si = 0; si <= visitedSteps; si++) {
                const f  = si / steps;
                const px = p0.x + f * dx;
                const py = p0.y + f * dy;
                const gx = Math.round(px / GRID);
                const gy = Math.round(py / GRID);
                // Drone is at a vertex. Footprint is the cells *touching* the
                // vertex extended by `radius`: a (2*radius) × (2*radius) block
                // symmetric around the vertex.
                for (let cx = gx - radius; cx < gx + radius; cx++) {
                    for (let cy = gy - radius; cy < gy + radius; cy++) {
                        visited.add(`${cx},${cy}`);
                    }
                }
            }
        }

        // Render every covered cell. No area filter — the shadow follows
        // wherever the drone has been.
        for (const key of visited) {
            const [gx, gy] = key.split(',').map(Number);
            const cellX = gx * GRID;
            const cellY = gy * GRID;
            s += `<rect x="${cellX}" y="${cellY}" width="${GRID}" height="${GRID}"
                        fill="${colorWith}" opacity="0.22" stroke="${colorWith}"
                        stroke-width="0.5" stroke-opacity="0.4"/>`;
        }
    }
    return s;
}

// Animated proof packet: area → relay ship → peer fan-out to the other
// 5 ships. The fan-out represents the proof being recorded on L1, where
// every ship's validator independently checks it.
//
// Stage A (0..0.6): packet travels from area centre down to the relay ship.
// Stage B (0.6..1): packet replicates from relay ship out to all peers.
function renderProofRelay(fromX, fromY, toShip, color, progress) {
    if (progress <= 0) return '';
    const ship = SHIPS[toShip];
    const markerEnd = color === '#ef4444' ? 'url(#arrow-red)'
                    : color === '#3b82f6' ? 'url(#arrow-blue)'
                    : color === '#22c55e' ? 'url(#arrow-green)'
                    : color === '#8b5cf6' ? 'url(#arrow-purple)'
                    : 'url(#arrow)';
    let s = '';

    if (progress < 0.6) {
        const t = progress / 0.6;
        const px = fromX + t * (ship.x - fromX);
        const py = fromY + t * (ship.y - fromY);
        s += `<line x1="${fromX}" y1="${fromY}" x2="${px}" y2="${py}"
                    stroke="${color}" stroke-width="2" stroke-dasharray="6,4"
                    opacity="0.75" marker-end="${markerEnd}"/>`;
        s += `<circle cx="${px}" cy="${py}" r="6" fill="${color}"/>`;
        s += `<circle cx="${px}" cy="${py}" r="11" fill="${color}" opacity="0.3"/>`;
    } else {
        const t = (progress - 0.6) / 0.4;
        // full line area → relay ship (faded, established)
        s += `<line x1="${fromX}" y1="${fromY}" x2="${ship.x}" y2="${ship.y}"
                    stroke="${color}" stroke-width="2" stroke-dasharray="6,4"
                    opacity="0.45"/>`;
        // peer fan-out from relay ship to each other ship
        for (const [id, peer] of Object.entries(SHIPS)) {
            if (id === toShip) continue;
            const px = ship.x + t * (peer.x - ship.x);
            const py = ship.y + t * (peer.y - ship.y);
            s += `<line x1="${ship.x}" y1="${ship.y}" x2="${px}" y2="${py}"
                        stroke="${color}" stroke-width="1.5" opacity="0.8"/>`;
            // small packet head
            s += `<circle cx="${px}" cy="${py}" r="3.5" fill="${color}"/>`;
        }
    }
    return s;
}

// Mission deployment — commander D writes a tx on L1; because the L1 chain
// is the collective of all six ships, every other ship sees it (peer fan-out).
// Then the two relay ships pass the mission spec to their L2 sequencer.
//
// Stage A (0..0.55): D → A, B, C, E, F      (L1 propagation)
// Stage B (0.55..1):  F → L2-A (EX-010)
//                    B → L2-B (EX-011)      (relay-to-sequencer)
function renderMissionDeploy(progress) {
    if (progress <= 0) return '';
    const D    = SHIPS.D;
    const F    = SHIPS.F;
    const B    = SHIPS.B;
    const L2A  = L2_NODES[0].home;
    const L2B  = L2_NODES[1].home;
    const peers = ['A', 'B', 'C', 'E', 'F'];
    let s = '';

    if (progress < 0.55) {
        // Stage A — packets travel from D to each L1 peer simultaneously.
        const t = progress / 0.55;
        for (const id of peers) {
            const p = SHIPS[id];
            const px = D.x + t * (p.x - D.x);
            const py = D.y + t * (p.y - D.y);
            s += `<line x1="${D.x}" y1="${D.y}" x2="${px}" y2="${py}"
                        stroke="#4fc3f7" stroke-width="1.5" stroke-dasharray="4,3" opacity="0.75"/>`;
            s += `<circle cx="${px}" cy="${py}" r="4" fill="#4fc3f7"/>`;
        }
    } else {
        // Stage A complete — show faint static lines from D to all peers.
        for (const id of peers) {
            const p = SHIPS[id];
            s += `<line x1="${D.x}" y1="${D.y}" x2="${p.x}" y2="${p.y}"
                        stroke="#4fc3f7" stroke-width="1" stroke-dasharray="4,3" opacity="0.35"/>`;
        }
        // Stage B — F dispatches EX-010 to L2-A; B dispatches EX-011 to L2-B.
        const t = (progress - 0.55) / 0.45;
        const apx = F.x + t * (L2A.x - F.x);
        const apy = F.y + t * (L2A.y - F.y);
        const bpx = B.x + t * (L2B.x - B.x);
        const bpy = B.y + t * (L2B.y - B.y);

        s += `<line x1="${F.x}" y1="${F.y}" x2="${apx}" y2="${apy}"
                    stroke="#ef4444" stroke-width="2" stroke-dasharray="3,3" opacity="0.85"/>`;
        s += `<circle cx="${apx}" cy="${apy}" r="5" fill="#ef4444"/>`;
        s += `<text x="${apx}" y="${apy - 10}" text-anchor="middle"
                    font-family="Consolas,monospace" font-size="10"
                    font-weight="700" fill="#ef4444">EX-010</text>`;

        s += `<line x1="${B.x}" y1="${B.y}" x2="${bpx}" y2="${bpy}"
                    stroke="#3b82f6" stroke-width="2" stroke-dasharray="3,3" opacity="0.85"/>`;
        s += `<circle cx="${bpx}" cy="${bpy}" r="5" fill="#3b82f6"/>`;
        s += `<text x="${bpx}" y="${bpy - 10}" text-anchor="middle"
                    font-family="Consolas,monospace" font-size="10"
                    font-weight="700" fill="#3b82f6">EX-011</text>`;
    }
    return s;
}

// Convoy advance broadcast — two stages:
//   Stage 1 (0 → 0.55): D fans the convoyAdvance tx out on L1 to the five
//                        other validator ships (A, B, C, E, F). Yellow.
//   Stage 2 (0.55 → 1):  Radio relay layer.
//                        F → L2-Alpha (green), B → L2-Bravo (purple), and
//                        D → the three HVUs (yellow) since HVUs aren't L1
//                        validators and need a direct radio command.
function renderAdvanceBroadcast(progress) {
    if (progress <= 0) return '';
    const D = SHIPS.D;
    const F = SHIPS.F;
    const B = SHIPS.B;
    const STAGE1_END = 0.55;

    let s = '';

    // ── Stage 1: D → ships (L1 broadcast) ─────────────────
    const t1 = Math.min(1, progress / STAGE1_END);
    const shipTargets = [SHIPS.A, SHIPS.B, SHIPS.C, SHIPS.E, SHIPS.F];
    for (const tgt of shipTargets) {
        const px = D.x + t1 * (tgt.x - D.x);
        const py = D.y + t1 * (tgt.y - D.y);
        s += `<line x1="${D.x}" y1="${D.y}" x2="${px}" y2="${py}"
                    stroke="#ffd600" stroke-width="1.5" stroke-dasharray="4,3"
                    opacity="0.8"/>`;
        s += `<circle cx="${px}" cy="${py}" r="4" fill="#ffd600"/>`;
    }

    // ── Stage 2: radio relay layer ────────────────────────
    if (progress > STAGE1_END) {
        const t2 = (progress - STAGE1_END) / (1 - STAGE1_END);

        // F → L2-Alpha (green to match the α swarm)
        const tgtA = L2_NODES[0].home;
        const fpx = F.x + t2 * (tgtA.x - F.x);
        const fpy = F.y + t2 * (tgtA.y - F.y);
        s += `<line x1="${F.x}" y1="${F.y}" x2="${fpx}" y2="${fpy}"
                    stroke="#22c55e" stroke-width="1.5" stroke-dasharray="4,3"
                    opacity="0.85"/>`;
        s += `<circle cx="${fpx}" cy="${fpy}" r="4" fill="#22c55e"/>`;

        // B → L2-Bravo (purple to match the β swarm)
        const tgtB = L2_NODES[1].home;
        const bpx = B.x + t2 * (tgtB.x - B.x);
        const bpy = B.y + t2 * (tgtB.y - B.y);
        s += `<line x1="${B.x}" y1="${B.y}" x2="${bpx}" y2="${bpy}"
                    stroke="#8b5cf6" stroke-width="1.5" stroke-dasharray="4,3"
                    opacity="0.85"/>`;
        s += `<circle cx="${bpx}" cy="${bpy}" r="4" fill="#8b5cf6"/>`;

        // D → each HVU (tactical radio, same yellow as D's commander signal)
        for (const hvu of PROTECTED_SHIPS) {
            const hpx = D.x + t2 * (hvu.x - D.x);
            const hpy = D.y + t2 * (hvu.y - D.y);
            s += `<line x1="${D.x}" y1="${D.y}" x2="${hpx}" y2="${hpy}"
                        stroke="#ffd600" stroke-width="1.2" stroke-dasharray="2,3"
                        opacity="0.7"/>`;
            s += `<circle cx="${hpx}" cy="${hpy}" r="3" fill="#ffd600"/>`;
        }
    }

    return s;
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
    // forward speed wake from the commander's column
    s += `<g opacity="0.6">`;
    const wakeX = SHIPS.D.x;
    const wakeBottom = VIEW_H;
    for (let i = 0; i < 5; i++) {
        s += `<line x1="${wakeX}" y1="${wakeBottom - i*8}" x2="${wakeX}" y2="${wakeBottom - i*8 + 6}" stroke="#4fc3f7" stroke-width="1"/>`;
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
    // Deploy lines only render while the deploy phase is in progress; once we
    // move on to sweep/proof/etc. the canvas should be clean of those lines.
    if (cfg.showDeploy) inner += renderMissionDeploy(cfg.deployProgress || 0);
    inner += renderCoverageCells(ALPHA_DRONES, cfg.alphaSweep || 0, '#ef4444');
    inner += renderCoverageCells(BRAVO_DRONES, cfg.bravoSweep || 0, '#3b82f6');
    inner += renderDrones(ALPHA_DRONES, cfg.alphaSweep || 0);
    inner += renderDrones(BRAVO_DRONES, cfg.bravoSweep || 0);
    if (cfg.alphaProof) {
        // Proof originates from the L2-A sequencer node (drone's home position).
        inner += renderProofRelay(L2_NODES[0].home.x, L2_NODES[0].home.y, cfg.alphaProof.viaShip, '#ef4444', cfg.alphaProof.progress);
    }
    if (cfg.bravoProof) {
        inner += renderProofRelay(L2_NODES[1].home.x, L2_NODES[1].home.y, cfg.bravoProof.viaShip, '#3b82f6', cfg.bravoProof.progress);
    }
    if (cfg.advanceBroadcast) {
        inner += renderAdvanceBroadcast(cfg.advanceBroadcast);
    }
    if (cfg.advancedOffset > 0) {
        inner += renderConvoyAdvanced(cfg.advancedOffset);
    } else {
        inner += renderConvoy();
    }
    inner += renderL2Nodes(cfg.alphaSweep || 0, cfg.bravoSweep || 0, cfg.advancedOffset || 0);
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
    // 1.a Ship D writes the deploy tx on L1
    F.push({
        phase: '1/8 — mission deployment',
        cfg: { showDeploy: true, deployProgress: 0, commanderActive: true },
        badge: 'Deploy', badgeClass: 'deploy',
        text: `Commander D submits an L1 transaction: <code>deploy(EX-010, EX-011)</code> with area, coverage &ge; 95&thinsp;%, time &le; 6 min, detection p &ge; 0.7.`,
        registry: reg('PENDING', 'PENDING', 'issuing deploy'),
        dwell: 1700,
    });
    // 1.b L1 propagation — every ship sees the tx (Clique PoA shared chain)
    F.push({
        phase: '1/8 — L1 propagation',
        cfg: { showDeploy: true, deployProgress: 0.55 },
        badge: 'Deploy', badgeClass: 'deploy',
        text: `L1 is the collective of all six ships' validators &mdash; the deploy tx propagates to A, B, C, E, F via PoA peer fan-out.`,
        registry: reg('ON L1', 'ON L1', 'idle'),
        dwell: 1700,
    });
    // 1.c Relay ships dispatch the spec to their L2 sequencer
    F.push({
        phase: '1/8 — L2 dispatch',
        cfg: { showDeploy: true, deployProgress: 1 },
        badge: 'Deploy', badgeClass: 'deploy',
        text: `F forwards <code>EX-010</code> to <code>L2-A</code> (Alpha). B forwards <code>EX-011</code> to <code>L2-B</code> (Bravo). Drones now have their mission spec.`,
        registry: reg('DISPATCHED', 'DISPATCHED', 'idle'),
        dwell: 2000,
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
              ? `<code>π_α</code> → ship F (forward-left, primary relay). <code>π_β</code> → ship B (forward-right, primary relay).`
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

    // Phase 7 — On-chain advance trigger (Pattern A: no commander daemon).
    // The Verifier contract internally calls CommandLog.advance() the moment
    // the SECOND verifyProof tx clears FRI — atomic with verification, no
    // human or off-chain process involved.
    F.push({
        phase: '7/8 — verifier auto-fires advance',
        cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, commanderActive: true, l1Highlight: true },
        badge: 'Cmd',    badgeClass: 'cmd',
        text: `Inside the same transaction that verifies <code>π_β</code>, the Verifier contract sees <code>verdict[EX-010] = verdict[EX-011] = SAFE</code> and atomically calls <code>CommandLog.advance()</code>. No commander daemon, no off-chain trigger — the chain enforces the two-of-two rule.`,
        registry: reg('SAFE ✓ (by F)', 'SAFE ✓ (by B)', 'auto-triggered', 'EMITTED'),
        dwell: 2400,
    });
    // 7.b — Stage 1: ConvoyAdvance event gossips through the PoA validator
    // network. Every ship sees it within the same block.
    F.push({
        phase: '7/8 — broadcast advance',
        cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, commanderActive: true, advanceBroadcast: 0.55 },
        badge: 'Cmd',    badgeClass: 'cmd',
        text: `Stage 1 — the on-chain <code>ConvoyAdvance</code> event gossips through the PoA validator network. Every ship (A, B, C, D, E, F) sees it within the same block.`,
        registry: reg('SAFE ✓ (by F)', 'SAFE ✓ (by B)', 'event seen on L1', 'BROADCAST'),
        dwell: 1400,
    });
    // 7.c — Stage 2: F and B push the command over radio into their L2
    // swarms; D bridges the event to the HVUs over tactical radio.
    F.push({
        phase: '7/8 — broadcast advance',
        cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, commanderActive: true, advanceBroadcast: 1 },
        badge: 'Cmd',    badgeClass: 'cmd',
        text: `Stage 2 — radio relay layer. F → L2-Alpha (green); B → L2-Bravo (purple); D → the three HVUs (thin yellow). These are pure event-bridges (L1 event → radio frame), no decision-making — the decision was already enforced on-chain.`,
        registry: reg('SAFE ✓ (by F)', 'SAFE ✓ (by B)', 'relayed to swarms', 'BROADCAST'),
        dwell: 1600,
    });

    // Phase 8 — Convoy advances through and past the swept area.
    // Lead ship A starts at y=520 (80 px south of the zone's bottom edge).
    // To finish symmetrically — rear ship D ending 80 px NORTH of the zone's
    // top edge (y=120) — D must travel from y=760 to y=40, i.e. 720 px.
    const advSteps = 30;
    const advStepSize = 24;          // 30 × 24 = 720 px total travel
    for (let i = 1; i <= advSteps; i++) {
        F.push({
            phase: '8/8 — convoy advance',
            cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, advancedOffset: i * advStepSize },
            badge: 'Advance', badgeClass: 'advance',
            text: `Convoy moves forward at maximum speed through the cleared frontal area to the other side. Mission cycle complete.`,
            registry: reg('SAFE ✓ (by F)', 'SAFE ✓ (by B)', 'advance issued', 'EXECUTING'),
            dwell: 90,
        });
    }
    F.push({
        phase: '8/8 — cycle complete',
        cfg: { deployProgress: 1, alphaSweep: 1, bravoSweep: 1, advancedOffset: advSteps * advStepSize },
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
            <aside class="cs-status-panel">
              <div class="cs-status-header">
                <h3>Mission status</h3>
                <p>Per-node state and message log — 6 ships + 2 L2 sequencers.</p>
              </div>

              <div class="cs-nodes" id="cs-nodes">
                <div class="cs-node" data-node="A">
                  <div class="cs-node-head"><span class="cs-node-id node-A">A</span><span class="cs-node-role">forward · α+β relay</span><span class="cs-node-state">idle</span></div>
                  <ul class="cs-node-log"></ul>
                  <pre class="cs-node-terminal" data-source="geth-A · ship-A">$ geth-A     | clique PoA · validator key loaded
$ geth-A     | block height: 0 · pending tx: 0
$ ship-A     | orchestrator up · watching L1 events</pre>
                </div>
                <div class="cs-node" data-node="B">
                  <div class="cs-node-head"><span class="cs-node-id node-B">B</span><span class="cs-node-role">forward-right · β relay</span><span class="cs-node-state">idle</span></div>
                  <ul class="cs-node-log"></ul>
                  <pre class="cs-node-terminal" data-source="geth-B · ship-B">$ geth-B     | clique PoA · validator key loaded
$ ship-B     | orchestrator up · L2-B link nominal</pre>
                </div>
                <div class="cs-node" data-node="C">
                  <div class="cs-node-head"><span class="cs-node-id node-C">C</span><span class="cs-node-role">mid-right</span><span class="cs-node-state">idle</span></div>
                  <ul class="cs-node-log"></ul>
                  <pre class="cs-node-terminal" data-source="geth-C · ship-C">$ geth-C     | clique PoA · validator key loaded
$ ship-C     | orchestrator up · idle</pre>
                </div>
                <div class="cs-node" data-node="D">
                  <div class="cs-node-head"><span class="cs-node-id node-D">D</span><span class="cs-node-role">commander</span><span class="cs-node-state">idle</span></div>
                  <ul class="cs-node-log"></ul>
                  <pre class="cs-node-terminal" data-source="geth-D · ship-D">$ geth-D     | clique PoA · validator key loaded
$ ship-D     | commander mode · waiting for SAFE × 2
$ ship-D     | advance gate: armed</pre>
                </div>
                <div class="cs-node" data-node="E">
                  <div class="cs-node-head"><span class="cs-node-id node-E">E</span><span class="cs-node-role">mid-left</span><span class="cs-node-state">idle</span></div>
                  <ul class="cs-node-log"></ul>
                  <pre class="cs-node-terminal" data-source="geth-E · ship-E">$ geth-E     | clique PoA · validator key loaded
$ ship-E     | orchestrator up · idle</pre>
                </div>
                <div class="cs-node" data-node="F">
                  <div class="cs-node-head"><span class="cs-node-id node-F">F</span><span class="cs-node-role">forward-left · α relay</span><span class="cs-node-state">idle</span></div>
                  <ul class="cs-node-log"></ul>
                  <pre class="cs-node-terminal" data-source="geth-F · ship-F">$ geth-F     | clique PoA · validator key loaded
$ ship-F     | orchestrator up · L2-A link nominal</pre>
                </div>
                <div class="cs-node" data-node="L2-A">
                  <div class="cs-node-head"><span class="cs-node-id node-L2A">L2-A</span><span class="cs-node-role">Madara α sequencer</span><span class="cs-node-state">idle</span></div>
                  <ul class="cs-node-log"></ul>
                  <pre class="cs-node-terminal" data-source="madara-α · pathfinder-α · snos-α · stone-α">$ madara-α      | sequencer up · chain_id convoy_alpha_v1
$ pathfinder-α  | indexed block #0
$ snos-α        | awaiting L2 trace
$ stone-α       | prover idle · 0 jobs queued</pre>
                </div>
                <div class="cs-node" data-node="L2-B">
                  <div class="cs-node-head"><span class="cs-node-id node-L2B">L2-B</span><span class="cs-node-role">Madara β sequencer</span><span class="cs-node-state">idle</span></div>
                  <ul class="cs-node-log"></ul>
                  <pre class="cs-node-terminal" data-source="madara-β · pathfinder-β · snos-β · stone-β">$ madara-β      | sequencer up · chain_id convoy_bravo_v1
$ pathfinder-β  | indexed block #0
$ snos-β        | awaiting L2 trace
$ stone-β       | prover idle · 0 jobs queued</pre>
                </div>
              </div>
            </aside>

            <div class="cs-stage">
              <div class="cs-canvas">
                <div class="cs-zoom">
                  <button class="cs-zoom-btn cs-zoom-in"  title="Zoom in">+</button>
                  <button class="cs-zoom-btn cs-zoom-out" title="Zoom out">−</button>
                  <button class="cs-zoom-btn cs-zoom-fit" title="Reset view">⌂</button>
                </div>
                <div class="cs-canvas-inner"></div>
              </div>
              <div class="cs-status">
                <div class="cs-status-badge idle">idle</div>
                <div class="cs-status-text">Click ▶ Play to begin the eight-phase walkthrough.</div>
              </div>
              <div class="cs-controls">
                <button class="cs-btn cs-prev"  title="Previous step (← arrow key)">←</button>
                <button class="cs-btn primary cs-play" title="Play / Pause (Space)">▶ Play</button>
                <button class="cs-btn cs-next"  title="Next step (→ arrow key)">→</button>
                <button class="cs-btn cs-reset" title="Reset to start">⏮</button>
                <div class="cs-progress"><div class="cs-progress-fill"></div></div>
                <div class="cs-progress-text">— / —</div>
              </div>
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
        this.nodes       = {};   // map node-id → { stateEl, logEl, rowEl }
        for (const el of root.querySelectorAll('.cs-node')) {
            this.nodes[el.dataset.node] = {
                rowEl:   el,
                stateEl: el.querySelector('.cs-node-state'),
                logEl:   el.querySelector('.cs-node-log'),
            };
        }
        this._lastLoggedPhase = null;

        this.frames = buildFrames();
        this.idx = -1;
        this.playing = false;
        this._timer = null;

        this.btnPlay .addEventListener('click', () => this._togglePlay());
        this.btnPrev .addEventListener('click', () => this._step(-1));
        this.btnNext .addEventListener('click', () => this._step(+1));
        this.btnReset.addEventListener('click', () => this.reset());

        // Keyboard shortcuts — fire when the cursor is over the simulation
        // area so the rest of the page (scrolling, etc.) keeps its bindings.
        root.tabIndex = 0;
        const keyHandler = (e) => {
            if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
            if (e.key === 'ArrowRight') { this._step(+1); e.preventDefault(); }
            else if (e.key === 'ArrowLeft')  { this._step(-1); e.preventDefault(); }
            else if (e.key === ' ' || e.key === 'Spacebar') { this._togglePlay(); e.preventDefault(); }
        };
        root.addEventListener('keydown', keyHandler);
        root.addEventListener('mouseenter', () => {
            window.addEventListener('keydown', keyHandler);
        });
        root.addEventListener('mouseleave', () => {
            window.removeEventListener('keydown', keyHandler);
        });

        // ── Zoom & pan ────────────────────────────────────────
        this.zoom = 1;
        this.panX = 0;
        this.panY = 0;
        this.canvasFrame = root.querySelector('.cs-canvas');
        root.querySelector('.cs-zoom-in') .addEventListener('click', () => this._zoomBy(1.25));
        root.querySelector('.cs-zoom-out').addEventListener('click', () => this._zoomBy(1/1.25));
        root.querySelector('.cs-zoom-fit').addEventListener('click', () => this._zoomReset());
        // Wheel zoom centred on cursor
        this.canvasFrame.addEventListener('wheel', (e) => {
            if (!e.ctrlKey && Math.abs(e.deltaY) < 1) return;
            e.preventDefault();
            const rect = this.canvasFrame.getBoundingClientRect();
            const cx = e.clientX - rect.left;
            const cy = e.clientY - rect.top;
            const factor = e.deltaY < 0 ? 1.15 : 1/1.15;
            this._zoomBy(factor, cx, cy);
        }, { passive: false });
        // Drag to pan — works at any zoom level (use ⌂ to recentre).
        let drag = null;
        this.canvasFrame.addEventListener('mousedown', (e) => {
            // Ignore clicks on the zoom buttons themselves.
            if (e.target.closest('.cs-zoom')) return;
            drag = { x: e.clientX, y: e.clientY, panX: this.panX, panY: this.panY };
            this.canvasFrame.classList.add('dragging');
        });
        window.addEventListener('mousemove', (e) => {
            if (!drag) return;
            this.panX = drag.panX + (e.clientX - drag.x);
            this.panY = drag.panY + (e.clientY - drag.y);
            this._applyTransform();
        });
        window.addEventListener('mouseup', () => {
            drag = null;
            this.canvasFrame.classList.remove('dragging');
        });

        this.reset();

        // Lock the glossary's height to the simulation widget so they end at
        // the same vertical line. ResizeObserver tracks any layout change.
        const sim = root.closest('.convoy-sim') || root;
        requestAnimationFrame(() => this._syncGlossaryHeight());
        if (typeof ResizeObserver !== 'undefined') {
            const ro = new ResizeObserver(() => this._syncGlossaryHeight());
            ro.observe(sim);
        }
        window.addEventListener('resize', () => this._syncGlossaryHeight());
    }

    _applyTransform() {
        this.canvas.style.transform =
            `translate(${this.panX}px, ${this.panY}px) scale(${this.zoom})`;
    }
    _zoomBy(factor, cx, cy) {
        const newZoom = Math.max(0.6, Math.min(4, this.zoom * factor));
        if (cx === undefined) {
            // Zoom around viewport centre
            const rect = this.canvasFrame.getBoundingClientRect();
            cx = rect.width / 2;
            cy = rect.height / 2;
        }
        // Keep the cursor point stationary in canvas coords.
        const k = newZoom / this.zoom;
        this.panX = cx - k * (cx - this.panX);
        this.panY = cy - k * (cy - this.panY);
        this.zoom = newZoom;
        this._applyTransform();
    }
    _zoomReset() {
        this.zoom = 1; this.panX = 0; this.panY = 0;
        this._applyTransform();
    }

    _renderRegistry(/* reg */) { /* state per-node now lives in node sections */ }

    // Which nodes are active (and should log) for a given frame.
    // Uses phase string for finer-grained routing within a badgeClass.
    _nodesForFrame(f) {
        const phase = f.phase || '';
        if (phase.includes('L1 propagation')) return ['D', 'A', 'B', 'C', 'E', 'F'];
        if (phase.includes('L2 dispatch'))    return ['F', 'B', 'L2-A', 'L2-B'];
        switch (f.badgeClass) {
            case 'deploy':  return ['D'];
            case 'sweep':
            case 'commit':
            case 'proof':   return ['L2-A', 'L2-B'];
            case 'relay':   return ['F', 'B', 'A', 'C', 'D', 'E', 'L2-A', 'L2-B'];
            case 'verify':
            case 'safe':    return ['A', 'B', 'C', 'D', 'E', 'F'];
            case 'advance': return ['D', 'A', 'B', 'C', 'E', 'F'];
            default:        return Object.keys(this.nodes);
        }
    }

    _setNodeState(id, state, badgeClass) {
        const n = this.nodes[id];
        if (!n) return;
        n.stateEl.textContent = state;
        n.stateEl.className = 'cs-node-state ' + (badgeClass || '');
        n.rowEl.classList.toggle('active', state !== 'idle' && state !== '—');
    }
    _appendNodeLog(id, badge, badgeClass, text) {
        const n = this.nodes[id];
        if (!n) return;
        const li = document.createElement('li');
        li.className = 'cs-node-event ' + (badgeClass || '');
        li.innerHTML = `<span class="cs-node-event-tag">${badge}</span><span class="cs-node-event-text">${text}</span>`;
        n.logEl.appendChild(li);
        n.logEl.scrollTop = n.logEl.scrollHeight;
    }
    _resetNodes() {
        for (const id of Object.keys(this.nodes)) {
            this._setNodeState(id, 'idle', '');
            this.nodes[id].logEl.innerHTML = '';
        }
        this._lastLoggedPhase = null;
    }

    _renderCurrent() {
        if (this.idx < 0) {
            this.canvas.innerHTML = renderScene({});
            if (this.phaseBadge) this.phaseBadge.textContent = '— ready —';
            this.statusBadge.className = 'cs-status-badge idle';
            this.statusBadge.textContent = 'idle';
            this.statusText.innerHTML = 'Click ▶ Play to begin the eight-phase walkthrough.';
            this.progressBar.style.width = '0%';
            this.progressTxt.textContent = `— / ${this.frames.length}`;
            this.btnPrev.disabled = true;
            this.btnNext.disabled = false;
            this._resetNodes();
            return;
        }
        const f = this.frames[this.idx];
        this.canvas.innerHTML = renderScene(f.cfg);
        if (this.phaseBadge) this.phaseBadge.textContent = f.phase;
        this.statusBadge.className = 'cs-status-badge ' + f.badgeClass;
        this.statusBadge.textContent = f.badge;
        this.statusText.innerHTML = f.text;
        const pct = 100 * (this.idx + 1) / this.frames.length;
        this.progressBar.style.width = pct + '%';
        this.progressTxt.textContent = `${this.idx + 1} / ${this.frames.length}`;
        this.btnPrev.disabled = this.idx <= 0;
        this.btnNext.disabled = this.idx >= this.frames.length - 1;
        this._maybeLogEvent(f);
    }

    _maybeLogEvent(f) {
        if (f.phase === this._lastLoggedPhase) return;
        this._lastLoggedPhase = f.phase;
        const targets = this._nodesForFrame(f);
        const stripped = (f.text || '').replace(/<[^>]+>/g, '');  // drop HTML tags for log
        for (const id of targets) {
            this._setNodeState(id, f.badge, f.badgeClass);
            this._appendNodeLog(id, f.badge, f.badgeClass, stripped);
        }
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
    _syncGlossaryHeight() {
        const sim = document.querySelector('.convoy-sim');
        const glossary = document.querySelector('.sim-glossary');
        if (!sim || !glossary) return;
        glossary.style.maxHeight = sim.offsetHeight + 'px';
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

/* demo.js — Guided "tutorial" walkthrough of the certified convoy mission.
   -------------------------------------------------------------------------
   Runs when the landing menu picks DEMO (window.CONVOY_MODE === 'demo').
   Drives the 3D world through window.convoyWorld (exposed by world3d.js):
   an 8-step narrated mission — brief → deploy → sweep → sign+submit (L2) →
   prove → verify (L1) → certify → advance — overlaid with the REAL numbers
   captured from the live end-to-end run (both STARK proofs, dual-safe, advance).

   Self-contained: injects its own CSS + panel, no index.html markup needed
   beyond <script src="js/demo.js">.
*/
(function () {
  'use strict';

  // ── Real mission record (captured from the verified live run) ────────────
  const M = {
    green:  '37–38°N · 15–16°W · 1°×1° · 100 blocks',
    purple: '37–38°N · 13–15°W · 1°×2° · 200 blocks',
    alpha: { proofKB: 1048, program: '0x0778bbf9…c99a', swarm: '(per run)',
             relay: 'ship F', readings: 20, footprint: '0.1° (1 block)', proveSec: 174, verifySec: 101 },
    bravo: { proofKB: 954, program: '0x0198ddb5…357e', swarm: '(per run)',
             relay: 'ship B', readings: 10, footprint: '0.2° (4 blocks)', proveSec: 329, verifySec: 98 },
    principal: '(per run)',
    gpsTx: 13,            // per swarm: 3 trace-Merkle + 8 FRI + 1 memory page + 1 GPS verify
    advanceGas: 187178,
    // ── proof-circuit meta (stable — baked into safe_area_verify_{alpha,bravo}.cairo) ──
    proof: { felts: 509, builtins: 'output · pedersen · range_check · ecdsa', cairoVer: '0.14.0.1' },
  };
  const dsec = s => Math.floor(s / 60) + 'm ' + String(s % 60).padStart(2, '0') + 's';   // 174 → "2m 54s"

  // ── sweep path per drone — the footprint-centre lattice (same geometry
  //    script5 generates), computed in-browser so the demo is self-contained
  //    (no fetch, works after git clone). Serpentine: down col 0, up col 1.
  //    Green (alpha) -16..-15 · 0.2° strips · 0.1° cells · 10 rows.
  //    Purple (bravo) -15..-13 · 0.4° strips · 0.2° footprints · 5 rows.
  function stripPath(id) {
    const i = (+id[1]) - 1, alpha = id[0] === 'a';
    const x0 = alpha ? (-16 + i * 0.2) : (-15 + i * 0.4);
    const cw = alpha ? 0.1 : 0.2;
    const cols = [x0 + cw / 2, x0 + cw + cw / 2];
    const nrow = alpha ? 10 : 5;
    const latC = r => 37 + (r + 0.5) * cw;
    const pts = [];
    // enter at the SOUTH-WEST corner (closest to the convoy), sweep UP col 0,
    // over, then DOWN col 1 — so the drone flies a direct path in from the south.
    for (let r = 0; r < nrow; r++)     pts.push({ lon: cols[0], lat: latC(r) });
    for (let r = nrow - 1; r >= 0; r--) pts.push({ lon: cols[1], lat: latC(r) });
    return pts;
  }

  // ── the 8 tutorial steps ─────────────────────────────────────────────────
  // Each: { tag, title, body (HTML), data (HTML | null), enter(fn) }
  const STEPS = [
    {
      tag: 'Mission', title: 'The convoy & the mission',
      body: 'A convoy crosses the open Atlantic (35–40°N, 10–20°W). Two sea zones ' +
            'ahead — <b style="color:#86efac">green</b> and <b style="color:#c4b5fd">purple</b> — ' +
            'must be <b>proven</b> clear before it may pass.' +
            '<div class="fleet">' +
            '<div><span class="k">3</span> high-value units — the protected cargo &amp; civilians</div>' +
            '<div><span class="k">6</span> warships (A–F) — the escort, the <b>6 Besu QBFT validators</b> that are part of Layer 1</div>' +
            '<div><span class="k">2</span> drone swarms — Alpha &amp; Bravo (5 each), each its own <b>Madara Starknet chain</b> (Layer 2)</div>' +
            '</div>',
      data: '<b>The plan</b> <span style="color:#64748b">— the next 7 steps</span>' +
            '<div class="plan">' +
            '<div>① commander <b>D</b> opens the mission on L1</div>' +
            '<div>② relay ships <b>F</b> &amp; <b>B</b> carry it to L2</div>' +
            '<div>③ the swarms sweep their zones</div>' +
            '<div>④ each swarm leader produces one STARK proof</div>' +
            '<div>⑤ the proof returns to its relay ship</div>' +
            '<div>⑥ L1 verifies both on-chain</div>' +
            '<div>⑦ commander <b>D</b> gives <b>advance</b></div>' +
            '</div>',
      enter: () => { W.clearTracks(); resetDrones(); W.focus(-14.6, 36.7, 190); },
    },
    {
      tag: 'Layer 1', title: 'Commander D opens the mission',
      body: 'Commander ship <b>D</b> signs the open-mission transaction and broadcasts ' +
            'it to the <b>Besu Layer-1</b> chain. All <b>6 QBFT warships (A–F)</b> validate ' +
            'it and reach consensus — the order is now final on L1.',
      data: 'Registry.deploy tx → the 6 QBFT validators reach consensus → block final on L1',
      enter: () => { W.clearTracks(); resetDrones(); W.focus(-15.0, 36.0, 64); openL1(1600); },
    },
    {
      tag: 'L1 → L2', title: 'Relay ships carry it to Layer 2',
      body: 'The relay ships — <b>F</b> for Alpha, <b>B</b> for Bravo — hand the order to ' +
            'each swarm’s <b>leader</b> (a1 / b1), which runs that swarm’s ' +
            '<b>Madara sequencer</b> (the L2 block producer). The leader opens the mission, ' +
            'and its 4 followers sync it.',
      data: 'F → a1 &nbsp;·&nbsp; B → b1 (sequencers) → each leader tasks its 4 follower drones',
      enter: () => { W.clearTracks(); resetDrones(); W.focus(-15.0, 36.1, 74); toL2(2600); },
    },
    {
      tag: 'Sweep', title: 'The swarms sweep their zones',
      body: 'The 10 drones fly out from the convoy and sweep their strips, sensing for ' +
            'contacts and <b>signing every reading</b> (ECDSA). Alpha clears a 0.1° ' +
            'footprint per reading; Bravo’s sensors are 2× — 0.2° (4 blocks) — over a ' +
            'doubled zone. The green &amp; purple fill in as <b>covered-safe</b>; then the ' +
            'drones return to the fleet.',
      data: `Alpha ${M.alpha.readings} readings/drone · Bravo ${M.bravo.readings} · ` +
            'every reading ECDSA-signed · safe_count 5/5 per swarm',
      enter: () => {
        W.clearTracks(); resetTrails(); resetDrones();
        // Follow-through: glide from wherever step 2 left the camera (near the
        // convoy) UP and TILT overhead, zoomed out enough to keep the FULL green
        // + purple in frame, while the drones fly straight in from the convoy,
        // painting the footprint they clear (transit + sweep). Then they sweep the
        // zones and fly back to the convoy (camera follows back down).
        const from = W.getView ? W.getView() : { lon: -15.0, lat: 36.1, rad: 74, theta: -0.3, phi: 1.0 };
        const over = { lon: -14.5, lat: 37.5, rad: 220, theta: -0.15, phi: 0.5 };
        focusTween(from, over, 2600);
        flyToStripStarts(2600);
        setTimeout(() => sweepAll(7000, () => {
          focusTween(over, { lon: -15.0, lat: 36.3, rad: 120, theta: -0.3, phi: 0.9 }, 2600);
          returnHome(2600);
        }), 2700);
      },
    },
    {
      tag: 'Prove', title: 'Telemetry to L2 → one STARK proof',
      body: 'Back with the fleet, every drone <b>submits its signed telemetry to L2</b> — ' +
            'to its swarm’s leader / sequencer (a1 · b1). Each leader then fetches all 5 ' +
            'drones’ readings and runs the coverage circuit — every strip, every reading, ' +
            'all 5 signatures verified in-circuit — into a single <b>swarm STARK proof</b>.',
      data: `10 signed <code>submit_telemetry</code> txns → a1 · b1<br>` +
            `Circuit <b>${M.proof.felts} felts</b> · ${M.proof.builtins} · 5× in-circuit ECDSA (cairo ${M.proof.cairoVer})<br>` +
            `Alpha proof <b>${M.alpha.proofKB} KB</b> · Bravo <b>${M.bravo.proofKB} KB</b><br>` +
            `Stone prove time: a1 <b>${dsec(M.alpha.proveSec)}</b> · b1 <b>${dsec(M.bravo.proveSec)}</b> &nbsp;(verify off-chain &lt;1s)`,
      enter: () => { W.clearTracks(); resetDrones(); W.focus(-15.0, 35.98, 88); submitAndProve(2600); },
    },
    {
      tag: 'Relay', title: 'The proof returns to its relay ship',
      body: 'Each leader sends its swarm proof back to its relay ship — Alpha’s to ' +
            '<b>F</b>, Bravo’s to <b>B</b> — the only ships allowed to submit it on L1.',
      data: 'a1 → ship F &nbsp;·&nbsp; b1 → ship B',
      enter: () => { W.focus(-14.7, 36.9, 150); proofToRelay(1800); },
    },
    {
      tag: 'Verify', title: 'Layer 1 verifies both proofs',
      body: 'Each relay ship submits its proof to the <b>StarkWare GPS verifier</b> on L1, ' +
            'then <code>registerSwarmProof</code> records the verdict. Both SAFE → the two ' +
            'swarm hashes fold into one <b>principal hash</b>; <code>isDualSafe</code> is true.',
      data: `${M.gpsTx} verify txns/swarm → 2 swarm hashes → principal <b>${M.principal}</b><br>` +
            `L1 verify + submit time: ship F <b>${dsec(M.alpha.verifySec)}</b> · ship B <b>${dsec(M.bravo.verifySec)}</b>`,
      enter: () => { W.clearTracks(); W.focus(-15.0, 36.2, 76); },
    },
    {
      tag: 'Advance', title: 'Commander D gives advance',
      body: 'Gated on <code>isDualSafe</code>, commander <b>D</b> issues the advance ' +
            'command. The convoy moves north through water that two STARK proofs — not ' +
            'trust — certified clear.',
      data: `CommandLog.advance(1, 2, 100) · ${M.advanceGas.toLocaleString()} gas · status OK`,
      enter: () => {
        W.clearTracks();
        // Watch the whole fleet — ships, HVUs and drones — move north UP THROUGH
        // the green + purple zones and out the far side; camera follows overhead.
        const from = { lon: -14.5, lat: 36.6, rad: 210, theta: -0.12, phi: 0.6 };
        const to   = { lon: -14.5, lat: 38.0, rad: 210, theta: -0.12, phi: 0.6 };
        if (W.view) W.view(from); else W.focus(from.lon, from.lat, from.rad);
        focusTween(from, to, 6000);
        advanceConvoy(6000);
      },
    },
  ];

  // ── state ────────────────────────────────────────────────────────────────
  let W = null, idx = 0, raf = 0, camRaf = 0, homes = {}, unitHomes = [];
  const trailLast = {}, paintLast = {};                   // id → last trailed / painted pos (throttle)
  const col  = id => id[0] === 'a' ? 0x22c55e : 0xa855f7; // alpha green / bravo purple
  const HALF = id => id[0] === 'a' ? 0.05 : 0.10;         // sensor footprint half-edge (deg)

  // Smoothly move the camera from one view to another (its own rAF so it runs
  // alongside drone motion). from/to may carry {lon,lat,rad,theta,phi} — every
  // key present in BOTH is interpolated, so we can pan, zoom AND orbit/tilt.
  function focusTween(from, to, ms) {
    cancelAnimationFrame(camRaf);
    const keys = ['lon', 'lat', 'rad', 'theta', 'phi'], t0 = performance.now();
    (function step(now) {
      const k = Math.min(1, (now - t0) / ms), e = k < .5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      const v = {};
      keys.forEach(key => { if (from[key] != null && to[key] != null) v[key] = from[key] + (to[key] - from[key]) * e; });
      if (W.view) W.view(v); else W.focus(v.lon, v.lat, v.rad);
      if (k < 1) camRaf = requestAnimationFrame(step);
    })(t0);
  }

  // Grow each drone's breadcrumb trail (the line under it) — throttled so a point
  // is added only every ~0.01°. No-op if world3d.js has no trail API yet.
  function trailAll() {
    if (!W.trail) return;
    W.drones.forEach(id => {
      const p = W.posOf(id); if (!p) return;
      const l = trailLast[id];
      if (l && Math.hypot(p.lon - l.lon, p.lat - l.lat) < 0.01) return;
      trailLast[id] = p; W.trail(id, p.lon, p.lat, col(id));
    });
  }
  // paint a continuous footprint corridor under each drone wherever it flies (e.g.
  // the transit in from the convoy) — ~half-footprint spacing so squares overlap
  // into a band. The in-zone sweep paints the clean reading lattice separately.
  function coverAll() {
    if (!W.paintCell) return;
    W.drones.forEach(id => {
      const p = W.posOf(id); if (!p) return;
      const h = HALF(id), l = paintLast[id];
      if (l && Math.hypot(p.lon - l.lon, p.lat - l.lat) < h) return;
      paintLast[id] = p; W.paintCell(p.lon, p.lat, h, h, col(id));
    });
  }
  function resetTrails() { for (const k in trailLast) delete trailLast[k]; for (const k in paintLast) delete paintLast[k]; }

  function resetDrones() {
    W.drones.forEach(id => { const h = homes[id]; if (h) W.setPos(id, h.lon, h.lat); });
  }

  const stripStart = id => stripPath(id)[0];      // deploy target = first sweep waypoint

  function tween(items, ms, onDone, onStep) {   // items: [{id, from, to}]
    cancelAnimationFrame(raf);
    const t0 = performance.now();
    (function step(now) {
      const k = Math.min(1, (now - t0) / ms), e = k < .5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      items.forEach(it => W.setPos(it.id, it.from.lon + (it.to.lon - it.from.lon) * e,
                                          it.from.lat + (it.to.lat - it.from.lat) * e));
      if (onStep) onStep(k);
      if (k < 1) raf = requestAnimationFrame(step); else if (onDone) onDone();
    })(t0);
  }

  function flyToStripStarts(ms) {
    // trail + coverage follow them straight in from the convoy to their strip corner,
    // so the area they clear on the way is painted too (coherent with the sweep).
    tween(W.drones.map(id => ({ id, from: W.posOf(id), to: stripStart(id) })), ms,
          null, () => { trailAll(); coverAll(); });
  }

  // After the sweep, fly the drones back to their convoy positions. The painted
  // coverage + trails stay put (that's the evidence); no new coverage on the way back.
  function returnHome(ms, onDone) {
    tween(W.drones.map(id => ({ id, from: W.posOf(id), to: homes[id] })), ms, onDone);
  }

  // Tween EVERY unit by index key (ships + all 3 HVUs + 10 drones). items:[{key,from,to}]
  function tweenUnits(items, ms, onDone) {
    cancelAnimationFrame(raf);
    const t0 = performance.now();
    (function step(now) {
      const k = Math.min(1, (now - t0) / ms), e = k < .5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      items.forEach(it => W.setUnit(it.key, it.from.lon + (it.to.lon - it.from.lon) * e,
                                            it.from.lat + (it.to.lat - it.from.lat) * e));
      if (k < 1) raf = requestAnimationFrame(step); else if (onDone) onDone();
    })(t0);
  }
  // Snap the WHOLE formation back to its start positions (undo any advance).
  function resetAllUnits() {
    if (W.allUnits && W.setUnit) unitHomes.forEach(u => W.setUnit(u.key, u.lon, u.lat));
    else resetDrones();
  }

  // Fly each drone through its strip lattice, growing the trail under it and
  // painting the footprint square it clears as SAFE (green Alpha / purple Bravo).
  //   Does NOT clear existing tracks — the fly-in trail continues into the sweep
  //   so the path from the convoy stays unbroken.
  function sweepAll(ms, onDone) {
    const paths = W.drones.map(id => ({ id, pts: stripPath(id) }));
    cancelAnimationFrame(raf);
    const painted = {}, drawn = {};              // last footprint / fallback-track index per drone
    const t0 = performance.now();
    (function step(now) {
      const k = Math.min(1, (now - t0) / ms);
      paths.forEach(p => {
        const f = k * (p.pts.length - 1), i = Math.floor(f), frac = f - i;
        const a = p.pts[i], b = p.pts[Math.min(i + 1, p.pts.length - 1)];
        W.setPos(p.id, a.lon + (b.lon - a.lon) * frac, a.lat + (b.lat - a.lat) * frac);
        if (W.paintCell) {                        // paint every footprint cleared so far
          const h = HALF(p.id), c = col(p.id);
          if (painted[p.id] === undefined) painted[p.id] = -1;
          while (painted[p.id] < i) { painted[p.id]++; const q = p.pts[painted[p.id]]; W.paintCell(q.lon, q.lat, h, h, c); }
        } else if (drawn[p.id] !== i + 1) {        // fallback (pre-API world3d.js): strip track
          drawn[p.id] = i + 1; W.drawTrack(p.id, p.pts.slice(0, i + 1));
        }
      });
      trailAll();
      if (k < 1) raf = requestAnimationFrame(step); else if (onDone) onDone();
    })(t0);
  }

  // Advance EVERYONE — ships, all 3 HVUs and the 10 drones — north through the
  // green + purple zones and out the far side (the certified-safe passage).
  function advanceConvoy(ms) {
    const dLat = 2.3;   // convoy starts ~35.9–36.1°N; +2.3° carries it past 38°N (through both zones)
    if (W.allUnits && W.setUnit) {
      const items = W.allUnits().map(u => ({ key: u.key, from: { lon: u.lon, lat: u.lat }, to: { lon: u.lon, lat: u.lat + dLat } }));
      tweenUnits(items, ms);
    } else {            // fallback (pre-API world3d.js): ships only
      const items = ['A', 'B', 'C', 'D', 'E', 'F'].map(id => { const p = W.posOf(id); return p ? { id, from: p, to: { lon: p.lon, lat: p.lat + dLat } } : null; }).filter(Boolean);
      tween(items, ms);
    }
  }

  // Animate "beams" (a transaction/message propagating) from one unit to another.
  // pairs: [{from:id, to:id, color}] — each beam grows from `from` to `to` over ms.
  function beams(pairs, ms) {
    cancelAnimationFrame(raf);
    const t0 = performance.now();
    (function step(now) {
      const k = Math.min(1, (now - t0) / ms);
      W.clearTracks();
      pairs.forEach(pr => {
        const a = W.posOf(pr.from), b = W.posOf(pr.to);
        if (!a || !b) return;
        W.drawTrack('beam', [{ lon: a.lon, lat: a.lat },
          { lon: a.lon + (b.lon - a.lon) * k, lat: a.lat + (b.lat - a.lat) * k }], pr.color);
      });
      if (k < 1) raf = requestAnimationFrame(step);
    })(t0);
  }
  // commander D → the 6 QBFT ships (tx entering / finalising on L1)
  const openL1 = ms => beams(['A', 'B', 'C', 'E', 'F'].map(id => ({ from: 'D', to: id, color: 0x38bdf8 })), ms);
  // Run beam "phases" in sequence, keeping earlier phases' completed lines drawn.
  function beamPhases(phases, msEach) {
    cancelAnimationFrame(raf);
    const done = []; let pi = 0;
    (function runPhase() {
      if (pi >= phases.length) return;
      const cur = phases[pi], t0 = performance.now();
      (function step(now) {
        const k = Math.min(1, (now - t0) / msEach);
        W.clearTracks();
        done.forEach(pr => { const a = W.posOf(pr.from), b = W.posOf(pr.to);
          if (a && b) W.drawTrack('beam', [{ lon: a.lon, lat: a.lat }, { lon: b.lon, lat: b.lat }], pr.color); });
        cur.forEach(pr => { const a = W.posOf(pr.from), b = W.posOf(pr.to); if (!a || !b) return;
          W.drawTrack('beam', [{ lon: a.lon, lat: a.lat },
            { lon: a.lon + (b.lon - a.lon) * k, lat: a.lat + (b.lat - a.lat) * k }], pr.color); });
        if (k < 1) raf = requestAnimationFrame(step);
        else { cur.forEach(pr => done.push(pr)); pi++; runPhase(); }
      })(t0);
    })();
  }
  // L1→L2: relay ships → each swarm's LEADER (the Madara sequencer / block producer),
  //   then the leader → the rest of its swarm (follower full-nodes).
  const toL2 = ms => beamPhases([
    [{ from: 'F', to: 'a1', color: 0x22c55e }, { from: 'B', to: 'b1', color: 0xa855f7 }],
    [...['a2', 'a3', 'a4', 'a5'].map(id => ({ from: 'a1', to: id, color: 0x22c55e })),
     ...['b2', 'b3', 'b4', 'b5'].map(id => ({ from: 'b1', to: id, color: 0xa855f7 }))],
  ], ms / 2);
  // swarm leaders a1/b1 → their relay ships F/B (proof returning)
  const proofToRelay = ms => beams([
    { from: 'a1', to: 'F', color: 0x22c55e }, { from: 'b1', to: 'B', color: 0xa855f7 },
  ], ms);
  // Prove step: the 5 followers submit their signed telemetry to the swarm's leader
  // / sequencer (a1 · b1) on L2; the leader then runs the coverage circuit into one
  // swarm STARK proof. Beams converge on the leader = "all 5 → the proof".
  const submitAndProve = ms => beamPhases([
    [...['a2', 'a3', 'a4', 'a5'].map(id => ({ from: id, to: 'a1', color: 0x22c55e })),
     ...['b2', 'b3', 'b4', 'b5'].map(id => ({ from: id, to: 'b1', color: 0xa855f7 }))],
  ], ms);

  function pulse(kind) { document.getElementById('demo-panel').dataset.pulse = kind; }

  // ── "what's inside this unit" inspector ──────────────────────────────────
  // Click any ship/drone (demo mode) → a box lists the containers that make it
  // up. Leaders a1/b1 run their swarm's whole L2 stack; a2-5/b2-5 are follower
  // nodes; ships A-F are Besu L1 validators. Names match the live `docker ps`.
  // container → its docker image size (from the run's docker-images.txt; images are stable)
  function imageOf(n) {
    if (/^convoy-ship-/.test(n)) return '883 MB';
    if (/^convoy-madara-/.test(n)) return '490 MB';
    if (/^convoy-pathfinder-/.test(n)) return '494 MB';
    if (/^convoy-(prover-api|machine)-/.test(n)) return '1.27 GB';
    if (/^convoy-l1-shim/.test(n)) return '200 MB';
    return '';
  }
  const STACK = (() => {
    const s = {
      A: { title: 'Ship A — L1 validator · RPC anchor', tier: 'Besu L1', c: [
           ['convoy-ship-a', 'Besu QBFT validator · L1 RPC (owner/deployer)'],
           ['convoy-l1-shim', 'L1→L2 RPC shim (serves finalized→latest)'] ] },
      B: { title: 'Ship B — L1 validator · Bravo relay', tier: 'Besu L1', c: [
           ['convoy-ship-b', 'Besu QBFT validator · submits the Bravo proof to L1'] ] },
      C: { title: 'Ship C — L1 validator', tier: 'Besu L1', c: [
           ['convoy-ship-c', 'Besu QBFT validator'] ] },
      D: { title: 'Ship D — L1 validator · Commander', tier: 'Besu L1', c: [
           ['convoy-ship-d', 'Besu QBFT validator · opens the mission + gives advance'] ] },
      E: { title: 'Ship E — L1 validator', tier: 'Besu L1', c: [
           ['convoy-ship-e', 'Besu QBFT validator'] ] },
      F: { title: 'Ship F — L1 validator · Alpha relay', tier: 'Besu L1', c: [
           ['convoy-ship-f', 'Besu QBFT validator · submits the Alpha proof to L1'] ] },
      a1: { title: 'Drone a1 — Alpha leader', tier: 'Madara L2 · Alpha', c: [
            ['convoy-madara-alpha', 'Starknet sequencer (L2 block producer)'],
            ['convoy-pathfinder-alpha-1', 'archive full-node (L2 RPC)'],
            ['convoy-prover-api-alpha', 'Stone STARK prover + L1 submitter'],
            ['convoy-machine-alpha-1', 'drone signer (ECDSA key custody)'],
            ['convoy-madara-alpha-seed', 'genesis seeder (one-shot, then removed)'] ] },
      b1: { title: 'Drone b1 — Bravo leader', tier: 'Madara L2 · Bravo', c: [
            ['convoy-madara-bravo', 'Starknet sequencer (L2 block producer)'],
            ['convoy-pathfinder-bravo-1', 'archive full-node (L2 RPC)'],
            ['convoy-prover-api-bravo', 'Stone STARK prover + L1 submitter'],
            ['convoy-machine-bravo-1', 'drone signer (ECDSA key custody)'],
            ['convoy-madara-bravo-seed', 'genesis seeder (one-shot, then removed)'] ] },
      HVU: { title: 'High-value unit — protected asset', tier: 'escorted cargo', c: [] },
    };
    for (let i = 2; i <= 5; i++) {
      s['a' + i] = { title: `Drone a${i} — Alpha follower`, tier: 'Madara L2 · Alpha', c: [
        ['convoy-madara-alpha-' + i, 'follower full-node (syncs the sequencer)'],
        ['convoy-machine-alpha-' + i, 'drone signer (ECDSA key custody)'] ] };
      s['b' + i] = { title: `Drone b${i} — Bravo follower`, tier: 'Madara L2 · Bravo', c: [
        ['convoy-madara-bravo-' + i, 'follower full-node (syncs the sequencer)'],
        ['convoy-machine-bravo-' + i, 'drone signer (ECDSA key custody)'] ] };
    }
    return s;
  })();

  let stackBox = null;
  function hideStackBox() { if (stackBox) { stackBox.remove(); stackBox = null; } }
  function onDemoPick(id, x, y) {
    hideStackBox();
    const u = id && STACK[id];
    if (!u) return;                                   // clicked open sea
    const rows = u.c.length
      ? u.c.map(([n, r]) => { const sz = imageOf(n); const log = /^convoy-(ship-|madara-)/.test(n) && !/-seed$/.test(n);
          return `<div class="row${log ? ' clk' : ''}"${log ? ` data-log="${n}"` : ''}>` +
            `<span class="cn">${n}${sz ? `<span class="sz">${sz}</span>` : ''}${log ? '<span class="lgh">▤ logs</span>' : ''}</span>` +
            `<span class="cr">${r}</span></div>`;
        }).join('')
      : '<div class="empty">no on-chain software — the asset being protected</div>';
    const b = document.createElement('div');
    b.className = 'demo-stack';
    b.innerHTML = `<div class="hd"><span class="ut">${u.title}</span><span class="tier">${u.tier}</span>` +
      '<button class="x" title="close">✕</button></div><div class="bd">' + rows + '</div>' +
      (u.c.length ? '<div class="ft"><button class="perfbtn">▟ live performance</button></div>' : '');
    document.body.appendChild(b);                      // append first so offsetHeight is real
    const bw = 300, bh = b.offsetHeight || 200;
    b.style.left = Math.min(x + 14, window.innerWidth - bw - 12) + 'px';
    b.style.top = Math.min(Math.max(12, y - 20), window.innerHeight - bh - 12) + 'px';
    b.querySelector('.x').addEventListener('click', hideStackBox);
    if (u.c.length) b.querySelector('.perfbtn').addEventListener('click', () => { hideStackBox(); openPerf(u); });
    b.querySelectorAll('.row.clk').forEach(row => row.addEventListener('click', () => openLog(row.dataset.log)));
    stackBox = b;
  }

  // ── live-performance window (piece 2) — replays the run's stats.log with a
  //    playhead: one draggable window per unit, a CPU+MEM sparkline per container.
  let STATS = null, statsFetch = null;
  const perfWins = [];
  function ensureStats(cb) {
    if (STATS) return cb(STATS);
    (statsFetch || (statsFetch = fetch('/api/run-stats').then(r => r.ok ? r.json() : null).catch(() => null)))
      .then(d => { STATS = d; cb(d); });
  }
  const fmt = s => { s = Math.round(s); return String(s / 60 | 0).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0'); };
  const PLAY_MS = 24000;                              // sweep the whole captured window in ~24s
  function sparkPath(vals, W, H, pad) {
    const n = vals.length; if (n < 2) return `M0,${H / 2} L${W},${H / 2}`;
    const mx = Math.max(1, ...vals);
    return vals.map((v, i) => `${i ? 'L' : 'M'}${(i / (n - 1) * W).toFixed(1)},${(H - pad - (v / mx) * (H - 2 * pad)).toFixed(1)}`).join(' ');
  }
  function dragify(win, handle) {
    handle.addEventListener('mousedown', e => {
      if (e.target.tagName === 'BUTTON') return;
      e.preventDefault();
      const r = win.getBoundingClientRect(), ox = e.clientX - r.left, oy = e.clientY - r.top;
      const mv = ev => { win.style.left = Math.max(0, Math.min(window.innerWidth - 60, ev.clientX - ox)) + 'px';
                         win.style.top = Math.max(0, Math.min(window.innerHeight - 28, ev.clientY - oy)) + 'px'; };
      const up = () => { window.removeEventListener('mousemove', mv); window.removeEventListener('mouseup', up); };
      window.addEventListener('mousemove', mv); window.addEventListener('mouseup', up);
    });
  }
  const PHASE_COL = { setup: '#64748b', deploy: '#38bdf8', submit: '#22c55e', prove: '#f59e0b', verify: '#a855f7', advance: '#f43f5e' };
  const PHASE_LBL = { setup: 'Setup', deploy: 'Deploy', submit: 'Submit', prove: 'Prove', verify: 'Verify', advance: 'Advance' };
  //   tutorial step (0..7) → mission phase the perf window plays when you reach it
  const STEP_PHASE = ['setup', 'deploy', 'deploy', 'submit', 'prove', 'prove', 'prove', 'advance'];
  function openPerf(unit) {
    ensureStats(stats => {
      const W = 320, H = 34, PAD = 3;
      const have = stats && stats.t && stats.t.length > 1, dur = have ? stats.dur : 0;
      const phases = (have && stats.phases && stats.phases.length) ? stats.phases : null;
      const panels = unit.c.map(([n]) => {
        const s = have && stats.containers[n];
        if (!s) return `<div class="pp" data-c="${n}"><div class="pn">${n}<span class="pv">— no samples</span></div></div>`;
        const peak = Math.round(Math.max(0, ...s.mem));
        return `<div class="pp" data-c="${n}"><div class="pn">${n}<span class="pv"><b class="mem">·</b> <span class="pk">peak ${peak} MiB</span></span></div>` +
          `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" class="spark">` +
          `<path class="pmem" d="${sparkPath(s.mem, W, H, PAD)}"/>` +
          `<line class="ph" x1="0" y1="0" x2="0" y2="${H}"/></svg></div>`;
      }).join('');
      const strip = phases ? '<div class="pstrip">' + phases.map(p =>
        `<span class="pseg" data-p="${p.name}" style="left:${(p.t0 / dur * 100).toFixed(2)}%;width:${((p.t1 - p.t0) / dur * 100).toFixed(2)}%;background:${PHASE_COL[p.name] || '#475569'}">${PHASE_LBL[p.name] || p.name}</span>`
      ).join('') + '<span class="phh"></span></div>' : '';
      const win = document.createElement('div'); win.className = 'demo-perf';
      win.innerHTML =
        `<div class="ph-hd"><span class="pt">${unit.title} · live performance</span>` +
        `<button class="pl">▶</button><button class="xx" title="close">✕</button></div>` +
        `<div class="pb">${have ? panels : '<div class="pnone">no stats captured for this run — re-run with the sampler from the start</div>'}</div>` +
        (have ? `<div class="pf">${strip}<div class="pfrow"><span class="cur">—</span>` +
          `<input class="scrub" type="range" min="0" max="${dur}" value="0" step="1"><span class="tl">00:00 / ${fmt(dur)}</span></div></div>` : '');
      document.body.appendChild(win);
      win.style.left = Math.max(20, window.innerWidth - 430 - perfWins.length * 24) + 'px';
      win.style.top = (90 + perfWins.length * 24) + 'px';
      perfWins.push(win);
      const close = () => { win.remove(); const i = perfWins.indexOf(win); if (i >= 0) perfWins.splice(i, 1); };
      win.querySelector('.xx').addEventListener('click', close);
      dragify(win, win.querySelector('.ph-hd'));
      if (!have) return;
      let playT = 0, raf = 0, playing = false;
      const scrub = win.querySelector('.scrub'), tl = win.querySelector('.tl'), pl = win.querySelector('.pl'),
            cur = win.querySelector('.cur'), phh = win.querySelector('.phh');
      const nearest = t => { const arr = stats.t; let i = 0; while (i < arr.length - 1 && arr[i + 1] <= t) i++; return i; };
      const phaseAt = t => phases ? (phases.find(p => t >= p.t0 && t < p.t1) || phases[phases.length - 1]) : null;
      function render() {
        const i = nearest(playT), frac = dur ? playT / dur : 0;
        win.querySelectorAll('.pp').forEach(pp => {
          const s = stats.containers[pp.dataset.c]; if (!s) return;
          const ln = pp.querySelector('.ph'); if (ln) ln.setAttribute('transform', `translate(${(frac * W).toFixed(1)},0)`);
          const m = pp.querySelector('.pv .mem');
          if (m) m.textContent = Math.round(s.mem[i] || 0) + ' MiB';
        });
        scrub.value = playT; tl.textContent = fmt(playT) + ' / ' + fmt(dur);
        if (phh) phh.style.left = (frac * 100).toFixed(2) + '%';
        if (cur) { const ph = phaseAt(playT); cur.textContent = ph ? (PHASE_LBL[ph.name] || ph.name) : '—'; cur.style.color = ph ? (PHASE_COL[ph.name] || '#cbd5e1') : '#94a3b8'; }
      }
      const stop = () => { playing = false; cancelAnimationFrame(raf); pl.textContent = '▶'; };
      function playFrom(t, end, ms) {                   // play the [t,end] window over ms (default: proportional)
        stop(); end = (end != null ? end : dur);
        ms = ms || (dur ? Math.abs(end - t) / dur * PLAY_MS : 1);
        playing = true; pl.textContent = '⏸'; playT = t;
        const t0 = performance.now();
        (function step(now) {
          if (!playing) return;
          const k = Math.min(1, (now - t0) / ms); playT = t + (end - t) * k; render();
          if (k < 1) raf = requestAnimationFrame(step); else stop();
        })(t0);
      }
      pl.addEventListener('click', () => { if (playing) return stop(); playFrom(playT >= dur ? 0 : playT, dur); });
      scrub.addEventListener('input', () => { stop(); playT = +scrub.value; render(); });
      win.querySelectorAll('.pseg').forEach(seg => seg.addEventListener('click', () => {
        const p = phases.find(x => x.name === seg.dataset.p); if (p) playFrom(p.t0, p.t1, 6000);
      }));
      // sync to tutorial step: play through that step's mission phase (~6s)
      win._sync = phaseName => { if (!phaseName || !phases) return; const p = phases.find(x => x.name === phaseName); if (p) playFrom(p.t0, p.t1, 6000); };
      render();
    });
  }
  function perfSyncStep(i) { const ph = STEP_PHASE[i]; perfWins.forEach(w => { if (w._sync) w._sync(ph); }); }

  // ── node log viewer — click a ship/madara container → its captured chain log
  //    (transactions + L1↔L2 messages + blocks). Served by serve.py /api/node-log.
  const logWins = [];
  const LOG_HI = /message|l1|l2|mission|open_mission|submit|telemetry|block|import|produced|seal|nonce|confirm|finali|deploy|declare| tx /i;
  function openLog(name) {
    const win = document.createElement('div'); win.className = 'demo-log';
    win.innerHTML =
      `<div class="lg-hd"><span class="lt">${name} · node log</span>` +
      `<input class="lq" placeholder="filter…"><button class="lmode">highlights</button><button class="lxx" title="close">✕</button></div>` +
      `<pre class="lb">loading…</pre>`;
    document.body.appendChild(win);
    win.style.left = Math.max(20, (window.innerWidth - 660) / 2 + logWins.length * 22) + 'px';
    win.style.top = (70 + logWins.length * 22) + 'px';
    logWins.push(win);
    const close = () => { win.remove(); const i = logWins.indexOf(win); if (i >= 0) logWins.splice(i, 1); };
    win.querySelector('.lxx').addEventListener('click', close);
    dragify(win, win.querySelector('.lg-hd'));
    const pre = win.querySelector('.lb'), q = win.querySelector('.lq'), mb = win.querySelector('.lmode');
    let lines = [], mode = 'hi';
    function render() {
      const s = q.value.trim().toLowerCase();
      let ls = lines;
      if (mode === 'hi') ls = ls.filter(l => LOG_HI.test(l));
      if (s) ls = ls.filter(l => l.toLowerCase().includes(s));
      pre.textContent = ls.slice(-1500).join('\n') || '(no matching lines)';
      pre.scrollTop = pre.scrollHeight;
    }
    q.addEventListener('input', render);
    mb.addEventListener('click', () => { mode = mode === 'hi' ? 'all' : 'hi'; mb.textContent = mode === 'hi' ? 'highlights' : 'all lines'; render(); });
    fetch('/api/node-log?name=' + encodeURIComponent(name))
      .then(r => r.ok ? r.text() : Promise.reject(r.status))
      .then(t => { lines = t.split('\n'); render(); })
      .catch(() => { pre.textContent = '(could not load log — update serve.py with the /api/node-log route and capture node logs into the run)'; });
  }

  // ── panel UI ─────────────────────────────────────────────────────────────
  function css() {
    const s = document.createElement('style');
    s.textContent = `
      body.demo-mode .hud-play, body.demo-mode .hud-units, body.demo-mode #sel{display:none}
      #demo-tr{position:fixed;right:18px;top:18px;z-index:30;display:flex;flex-direction:column;
        align-items:flex-end;gap:10px;max-height:calc(100vh - 36px)}
      #demo-panel{width:400px;display:flex;flex-direction:column;
        background:rgba(6,12,22,.9);border:1px solid #1e3a5f;
        border-radius:12px;padding:16px 18px 14px;color:#cbd5e1;backdrop-filter:blur(6px);
        box-shadow:0 14px 44px rgba(2,8,20,.6);font-size:13px;line-height:1.55}
      #demo-panel .top{display:flex;align-items:center;gap:10px;margin-bottom:8px}
      #demo-panel .tag{font-size:10.5px;letter-spacing:1.5px;text-transform:uppercase;
        color:#0b1220;background:#38bdf8;font-weight:700;border-radius:5px;padding:2px 8px}
      #demo-panel .count{margin-left:auto;font-size:11px;color:#64748b}
      #demo-panel h3{margin:0 0 6px;font-size:16px;color:#f1f5f9;font-weight:600}
      #demo-panel p{margin:0}
      #demo-panel .fleet{margin-top:11px;display:flex;flex-direction:column;gap:7px;font-size:12.5px}
      #demo-panel .fleet div{padding-left:27px;position:relative;color:#cbd5e1}
      #demo-panel .fleet .k{position:absolute;left:0;top:0;width:19px;text-align:center;color:#0b1220;
        background:#7dd3fc;border-radius:5px;font-weight:700;font-size:11px;line-height:18px}
      #demo-panel .fleet em{font-style:normal;color:#7dd3fc}
      #demo-panel .data{margin-top:11px;padding:9px 11px;border-left:2px solid #38bdf8;
        background:rgba(56,189,248,.07);border-radius:0 8px 8px 0;font-size:12px;color:#93c5fd}
      #demo-panel .data code{color:#7dd3fc}
      #demo-panel .data b{color:#e0f2fe;font-weight:600}
      #demo-panel .plan{margin-top:7px;display:flex;flex-direction:column;gap:4px}
      #demo-panel .foot{display:flex;align-items:center;gap:10px;margin-top:14px}
      #demo-panel .dots{display:flex;gap:6px}
      #demo-panel .dot{width:8px;height:8px;border-radius:50%;background:#1e3a5f;cursor:pointer;transition:all .2s}
      #demo-panel .dot.on{background:#38bdf8;box-shadow:0 0 8px rgba(56,189,248,.7)}
      #demo-panel .nav{margin-left:auto;display:flex;gap:8px}
      #demo-panel button{font:inherit;font-size:12px;color:#cbd5e1;background:rgba(30,58,95,.6);
        border:1px solid #1e3a5f;border-radius:7px;padding:6px 13px;cursor:pointer;transition:all .15s}
      #demo-panel button:hover{border-color:#38bdf8;color:#e2e8f0}
      #demo-panel button.primary{background:#0ea5e9;border-color:#0ea5e9;color:#04121f;font-weight:600}
      #demo-panel button:disabled{opacity:.4;cursor:default}
      #demo-restart{font-size:11px;color:#64748b;
        background:rgba(6,12,22,.7);border:1px solid #1e3a5f;border-radius:7px;padding:6px 10px;cursor:pointer}
      #demo-restart:hover{color:#7dd3fc;border-color:#38bdf8}
      .demo-stack{position:fixed;z-index:40;width:300px;background:rgba(6,12,22,.95);
        border:1px solid #1e3a5f;border-radius:11px;box-shadow:0 16px 48px rgba(2,8,20,.7);
        color:#cbd5e1;font-size:12px;overflow:hidden;backdrop-filter:blur(6px)}
      .demo-stack .hd{display:flex;align-items:center;gap:8px;padding:10px 12px;
        border-bottom:1px solid #17304d;background:rgba(30,58,95,.25)}
      .demo-stack .ut{font-weight:600;color:#f1f5f9;font-size:12.5px;flex:1;line-height:1.3}
      .demo-stack .tier{font-size:9.5px;letter-spacing:.5px;text-transform:uppercase;color:#7dd3fc;
        background:rgba(56,189,248,.12);border-radius:4px;padding:2px 6px;white-space:nowrap}
      .demo-stack .x{background:none;border:none;color:#64748b;cursor:pointer;font-size:13px;padding:0 2px}
      .demo-stack .x:hover{color:#e2e8f0}
      .demo-stack .bd{padding:6px 0;max-height:300px;overflow:auto}
      .demo-stack .row{display:flex;flex-direction:column;gap:1px;padding:6px 12px}
      .demo-stack .row:hover{background:rgba(56,189,248,.06)}
      .demo-stack .cn{color:#93c5fd;font-family:ui-monospace,Menlo,monospace;font-size:11px}
      .demo-stack .sz{margin-left:8px;font-size:9.5px;color:#64748b;font-family:system-ui;
        background:rgba(30,58,95,.4);border-radius:3px;padding:1px 5px}
      .demo-stack .cr{color:#94a3b8;font-size:11px;line-height:1.35}
      .demo-stack .row.clk{cursor:pointer}
      .demo-stack .row.clk:hover{background:rgba(56,189,248,.12)}
      .demo-stack .lgh{margin-left:8px;font-size:9.5px;color:#38bdf8}
      .demo-stack .empty{padding:12px;color:#94a3b8;font-style:italic}
      .demo-stack .ft{padding:8px 12px;border-top:1px solid #17304d}
      .demo-stack .perfbtn{width:100%;font:inherit;font-size:11.5px;color:#04121f;font-weight:600;
        background:#0ea5e9;border:none;border-radius:7px;padding:7px;cursor:pointer}
      .demo-stack .perfbtn:hover{background:#38bdf8}
      .demo-perf{position:fixed;z-index:45;width:390px;background:rgba(6,12,22,.96);border:1px solid #1e3a5f;
        border-radius:11px;box-shadow:0 18px 54px rgba(2,8,20,.75);color:#cbd5e1;font-size:11.5px;
        overflow:hidden;backdrop-filter:blur(7px)}
      .demo-perf .ph-hd{display:flex;align-items:center;gap:8px;padding:9px 11px;cursor:move;
        border-bottom:1px solid #17304d;background:rgba(30,58,95,.3)}
      .demo-perf .pt{flex:1;font-weight:600;color:#f1f5f9;font-size:12px}
      .demo-perf .ph-hd button{background:rgba(30,58,95,.6);border:1px solid #1e3a5f;color:#cbd5e1;
        border-radius:6px;cursor:pointer;font-size:11px;padding:2px 9px}
      .demo-perf .ph-hd button:hover{border-color:#38bdf8;color:#e2e8f0}
      .demo-perf .pb{padding:4px 10px;max-height:58vh;overflow:auto}
      .demo-perf .pp{padding:5px 0;border-bottom:1px solid rgba(23,48,77,.5)}
      .demo-perf .pp:last-child{border-bottom:none}
      .demo-perf .pn{display:flex;justify-content:space-between;gap:8px;font-family:ui-monospace,Menlo,monospace;
        font-size:10.5px;color:#93c5fd;margin-bottom:2px}
      .demo-perf .pv{color:#64748b;font-family:system-ui}
      .demo-perf .pv .mem{color:#fbbf24;font-weight:600}
      .demo-perf .pv .pk{color:#64748b}
      .demo-perf .spark{width:100%;height:34px;display:block}
      .demo-perf .spark .pmem{fill:none;stroke:#fbbf24;stroke-width:1.5;vector-effect:non-scaling-stroke}
      .demo-perf .spark .ph{stroke:#e2e8f0;stroke-width:1;opacity:.55;vector-effect:non-scaling-stroke}
      .demo-perf .pf{padding:8px 11px;border-top:1px solid #17304d}
      .demo-perf .pstrip{position:relative;height:16px;border-radius:4px;overflow:hidden;
        background:rgba(30,58,95,.35);margin-bottom:7px}
      .demo-perf .pseg{position:absolute;top:0;bottom:0;display:flex;align-items:center;justify-content:center;
        font-size:8.5px;letter-spacing:.3px;text-transform:uppercase;color:#04121f;font-weight:700;
        opacity:.72;cursor:pointer;overflow:hidden;white-space:nowrap;border-right:1px solid rgba(6,12,22,.5)}
      .demo-perf .pseg:hover{opacity:.95}
      .demo-perf .phh{position:absolute;top:0;bottom:0;width:2px;background:#e2e8f0;
        box-shadow:0 0 6px rgba(226,232,240,.8);pointer-events:none}
      .demo-perf .pfrow{display:flex;align-items:center;gap:9px}
      .demo-perf .cur{font-size:10px;font-weight:700;letter-spacing:.3px;text-transform:uppercase;min-width:52px}
      .demo-perf .scrub{flex:1;accent-color:#38bdf8}
      .demo-perf .tl{font-family:ui-monospace,Menlo,monospace;font-size:10.5px;color:#94a3b8;white-space:nowrap}
      .demo-perf .pnone{padding:16px;color:#94a3b8;font-style:italic}
      .demo-log{position:fixed;z-index:46;width:660px;max-width:calc(100vw - 40px);background:rgba(6,12,22,.97);
        border:1px solid #1e3a5f;border-radius:11px;box-shadow:0 18px 54px rgba(2,8,20,.8);color:#cbd5e1;
        overflow:hidden;backdrop-filter:blur(7px)}
      .demo-log .lg-hd{display:flex;align-items:center;gap:8px;padding:9px 11px;cursor:move;
        border-bottom:1px solid #17304d;background:rgba(30,58,95,.3)}
      .demo-log .lt{flex:1;font-weight:600;color:#f1f5f9;font-size:12px;font-family:ui-monospace,Menlo,monospace}
      .demo-log .lq{width:150px;font:inherit;font-size:11px;color:#e2e8f0;background:rgba(6,12,22,.7);
        border:1px solid #1e3a5f;border-radius:6px;padding:3px 8px}
      .demo-log .lg-hd button{background:rgba(30,58,95,.6);border:1px solid #1e3a5f;color:#cbd5e1;
        border-radius:6px;cursor:pointer;font-size:11px;padding:3px 9px}
      .demo-log .lg-hd button:hover{border-color:#38bdf8;color:#e2e8f0}
      .demo-log .lb{margin:0;padding:10px 12px;height:46vh;overflow:auto;font-family:ui-monospace,Menlo,monospace;
        font-size:10.5px;line-height:1.5;color:#a8c5e0;white-space:pre-wrap;word-break:break-word}`;
    document.head.appendChild(s);
  }

  function build() {
    css();
    const p = document.createElement('div');
    p.id = 'demo-panel';
    p.innerHTML =
      '<div class="top"><span class="tag" id="d-tag"></span><span class="count" id="d-count"></span></div>' +
      '<h3 id="d-title"></h3>' +
      '<p id="d-body"></p><div class="data" id="d-data"></div>' +
      '<div class="foot"><div class="dots" id="d-dots"></div>' +
      '<div class="nav"><button id="d-prev">‹ Back</button>' +
      '<button id="d-next" class="primary">Next ›</button></div></div>';
    const r = document.createElement('div'); r.id = 'demo-restart'; r.textContent = '↺ restart tutorial';
    const wrap = document.createElement('div'); wrap.id = 'demo-tr';   // top-right: panel + restart below it
    wrap.appendChild(p); wrap.appendChild(r); document.body.appendChild(wrap);

    const dots = document.getElementById('d-dots');
    STEPS.forEach((_, i) => {
      const d = document.createElement('div'); d.className = 'dot'; d.title = STEPS[i].tag;
      d.addEventListener('click', () => go(i)); dots.appendChild(d);   // left→right order
    });
    document.getElementById('d-prev').addEventListener('click', () => go(idx - 1));
    document.getElementById('d-next').addEventListener('click', () => go(idx + 1));
    r.addEventListener('click', () => go(0));
    window.addEventListener('keydown', e => {
      if (window.CONVOY_MODE !== 'demo') return;
      if (e.key === 'ArrowRight' && !hasSelection()) go(idx + 1);
      if (e.key === 'ArrowLeft' && !hasSelection()) go(idx - 1);
    });
  }
  const hasSelection = () => false;  // demo owns arrows (no unit selected in demo mode)

  function go(i) {
    i = Math.max(0, Math.min(STEPS.length - 1, i));
    hideStackBox();                              // close any open unit inspector on step change
    idx = i; const s = STEPS[i];
    document.getElementById('d-tag').textContent = s.tag;
    document.getElementById('d-title').textContent = s.title;
    document.getElementById('d-body').innerHTML = s.body;
    const dd = document.getElementById('d-data');
    dd.innerHTML = s.data || ''; dd.style.display = s.data ? '' : 'none';
    document.getElementById('d-count').textContent = i + ' / ' + (STEPS.length - 1);
    document.getElementById('d-prev').disabled = i === 0;
    const nx = document.getElementById('d-next');
    nx.textContent = i === STEPS.length - 1 ? 'Done' : 'Next ›';
    [...document.querySelectorAll('#demo-panel .dot')].forEach((d, k) => d.classList.toggle('on', k <= i));
    if (W.view) W.view({ theta: -0.3, phi: 1.0 });   // reset orbit to default; each step's enter() overrides it
    resetAllUnits();                                  // clean formation baseline (undo any advance) before the step animates
    try { s.enter(); } catch (err) { console.warn('[demo] step', i, err); }
    perfSyncStep(i);                                  // any open perf window plays this step's mission phase
  }

  function start() {
    W = window.convoyWorld;
    if (!W) { console.warn('[demo] convoyWorld API not found — is world3d.js the API build?'); return; }
    W.drones.forEach(id => { const p = W.posOf(id); if (p) homes[id] = p; });
    if (W.allUnits) unitHomes = W.allUnits();    // home position of EVERY unit (for advance + reset)
    document.body.classList.add('demo-mode');   // strip play-mode HUD lines + selection bar
    W.onDemoPick = onDemoPick;                   // click a unit → show its container stack
    build();
    go(0);
  }

  // launch when the menu selects demo (or immediately if already set)
  if (window.CONVOY_MODE === 'demo') start();
  else window.addEventListener('convoy:mode', e => { if (e.detail === 'demo') start(); });
})();

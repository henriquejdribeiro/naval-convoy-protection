/* world3d.js — Naval Convoy Protection · 3D ocean world + zoom-adaptive WGS84 grid
   ---------------------------------------------------------------------------
   three.js Ocean (Water + Sky + sun). Level-of-detail coordinate grid over the
   whole simulator sea (35–40°N × 10–20°W): step swaps 1°→0.1°→0.01°→0.001°→
   0.0001° as you zoom, drawn only in a bounded window. Convoy in defensive
   formation (ships + 3 HVUs + commander + alpha/bravo drone wings). Hover a
   unit to read its live WGS84 coordinates.

   Vendored: three.min.js · Water.js · Sky.js · waternormals.jpg  (all r128)
   Interaction: drag = orbit · shift-drag = pan · scroll = zoom · hover = coords.
*/
(function () {
  'use strict';
  if (!window.THREE) { console.error('[world3d] three.js not loaded'); return; }
  const T = window.THREE;
  const host = document.getElementById('world');

  const WORLD = { latMin: 35, latMax: 40, lonMin: -20, lonMax: -10 };
  const SCALE = 80;
  const lonC = (WORLD.lonMin + WORLD.lonMax) / 2, latC = (WORLD.latMin + WORLD.latMax) / 2;
  const lonToX = lon => (lon - lonC) * SCALE;
  const latToZ = lat => -(lat - latC) * SCALE;
  const xToLon = x => x / SCALE + lonC;
  const zToLat = z => -z / SCALE + latC;
  const COV = { latMin: 37, latMax: 38, lonMin: -16, lonMax: -14 };
  const CDIV_LON = (COV.lonMin + COV.lonMax) / 2;

  const renderer = new T.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.toneMapping = T.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 0.5;
  host.appendChild(renderer.domElement);

  const scene = new T.Scene();
  const camera = new T.PerspectiveCamera(55, 1, 0.05, 80000);
  scene.add(new T.AmbientLight(0xb8c6d8, 0.55));
  const dir = new T.DirectionalLight(0xffffff, 0.9); scene.add(dir);

  // ── ocean + sky ─────────────────────────────────────────────────────────
  const sun = new T.Vector3();
  let water = null;
  if (T.Water) {
    water = new T.Water(new T.PlaneGeometry(60000, 60000), {
      textureWidth: 512, textureHeight: 512,
      waterNormals: new T.TextureLoader().load('js/vendor/waternormals.jpg', tex => { tex.wrapS = tex.wrapT = T.RepeatWrapping; }),
      sunDirection: new T.Vector3(), sunColor: 0xffffff, waterColor: 0x0a3550, distortionScale: 3.7, fog: false
    });
    water.rotation.x = -Math.PI / 2; scene.add(water);
  } else {
    const flat = new T.Mesh(new T.PlaneGeometry(60000, 60000), new T.MeshStandardMaterial({ color: 0x0a2036 }));
    flat.rotation.x = -Math.PI / 2; scene.add(flat);
  }
  if (T.Sky) {
    const sky = new T.Sky(); sky.scale.setScalar(60000); scene.add(sky);
    const su = sky.material.uniforms;
    su['turbidity'].value = 10; su['rayleigh'].value = 2; su['mieCoefficient'].value = 0.005; su['mieDirectionalG'].value = 0.8;
    const pmrem = new T.PMREMGenerator(renderer);
    sun.setFromSphericalCoords(1, T.MathUtils.degToRad(90 - 22), T.MathUtils.degToRad(165));
    sky.material.uniforms['sunPosition'].value.copy(sun);
    if (water) water.material.uniforms['sunDirection'].value.copy(sun).normalize();
    dir.position.copy(sun).multiplyScalar(1000);
    try { scene.environment = pmrem.fromScene(sky).texture; } catch (e) { console.warn('PMREM skipped', e); }
  } else {
    scene.background = new T.Color(0x88a6c4);
    sun.set(0.4, 0.7, 0.3); dir.position.copy(sun).multiplyScalar(1000);
  }

  // ── constant-screen-size registries ─────────────────────────────────────
  const sprites = [], bodies = [], pickables = [];
  function labelSprite(list, text, color, sizeFactor) {
    const font = 44, pad = 10;
    let cv = document.createElement('canvas'); let cx = cv.getContext('2d');
    cx.font = `bold ${font}px system-ui, Arial, sans-serif`;
    cv.width = Math.ceil(cx.measureText(text).width) + pad * 2; cv.height = font + pad * 2;
    cx = cv.getContext('2d'); cx.font = `bold ${font}px system-ui, Arial, sans-serif`;
    cx.textAlign = 'center'; cx.textBaseline = 'middle'; cx.fillStyle = color || '#f8fafc';
    cx.fillText(text, cv.width / 2, cv.height / 2);
    const tex = new T.CanvasTexture(cv); tex.minFilter = T.LinearFilter;
    const sp = new T.Sprite(new T.SpriteMaterial({ map: tex, transparent: true, depthTest: false, depthWrite: false }));
    sp.userData.aspect = cv.width / cv.height; sp.userData.size = sizeFactor || 0.028;
    (list || sprites).push(sp);
    return sp;
  }

  // ── world boundary + coverage tints (fixed reference) ───────────────────
  const bpts = [];
  const corners = [[WORLD.latMin, WORLD.lonMin], [WORLD.latMin, WORLD.lonMax], [WORLD.latMax, WORLD.lonMax], [WORLD.latMax, WORLD.lonMin]];
  for (let i = 0; i < 4; i++) { const a = corners[i], b = corners[(i + 1) % 4]; bpts.push(new T.Vector3(lonToX(a[1]), 0, latToZ(a[0])), new T.Vector3(lonToX(b[1]), 0, latToZ(b[0]))); }
  const border = new T.LineSegments(new T.BufferGeometry().setFromPoints(bpts), new T.LineBasicMaterial({ color: 0x9fc0e0, transparent: true, opacity: 0.5, depthWrite: false }));
  border.position.y = 0.3; scene.add(border);
  [[WORLD.latMax, WORLD.lonMin], [WORLD.latMax, WORLD.lonMax], [WORLD.latMin, WORLD.lonMin], [WORLD.latMin, WORLD.lonMax]].forEach(c =>
    labelSprite(sprites, `${c[0].toFixed(4)}°N ${Math.abs(c[1]).toFixed(4)}°W`, '#dbeafe', 0.03).position.set(lonToX(c[1]), 2, latToZ(c[0])));

  function covZone(lonA, lonB, color) {
    const xA = lonToX(lonA), xB = lonToX(lonB), zN = latToZ(COV.latMax), zS = latToZ(COV.latMin);
    const m = new T.Mesh(new T.PlaneGeometry(Math.abs(xB - xA), Math.abs(zS - zN)),
      new T.MeshBasicMaterial({ color, transparent: true, opacity: 0.18, side: T.DoubleSide, depthWrite: false }));
    m.rotation.x = -Math.PI / 2; m.position.set((xA + xB) / 2, 0.5, (zN + zS) / 2); scene.add(m);
  }
  covZone(COV.lonMin, CDIV_LON, 0x22c55e);
  covZone(CDIV_LON, COV.lonMax, 0xa855f7);
  labelSprite(sprites, 'EX-010 · ALPHA', '#bbf7d0', 0.032).position.set(lonToX((COV.lonMin + CDIV_LON) / 2), 3, latToZ(COV.latMax));
  labelSprite(sprites, 'EX-011 · BRAVO', '#e9d5ff', 0.032).position.set(lonToX((CDIV_LON + COV.lonMax) / 2), 3, latToZ(COV.latMax));

  // ── ship/drone body (constant screen size) + hover data ─────────────────
  function body(id, lon, lat, color, opts) {
    opts = opts || {};
    const g = new T.Group();
    g.position.set(lonToX(lon), 0.6, latToZ(lat));
    const mesh = new T.Mesh(new T.SphereGeometry(1, 24, 18),
      new T.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: 0.4, roughness: 0.3, metalness: 0.25 }));
    mesh.userData = { group: g };
    pickables.push(mesh);
    g.add(mesh);
    const lbl = labelSprite(null, id, opts.textColor || '#0b1220', 0.024);
    lbl.position.set(0, 2.5, 0); g.add(lbl); sprites.pop();
    g.userData.label = lbl; g.userData.size = opts.size || 0.02;
    g.userData.id = id; g.userData.lon = lon; g.userData.lat = lat; g.userData.sphere = mesh;
    bodies.push(g); scene.add(g);
    return g;
  }

  // ── swap a body's sphere for a glTF/GLB 3D model (async, falls back) ──────
  function attachModel(group, url, opts) {
    opts = opts || {};
    if (!T.GLTFLoader) { console.warn('[world3d] GLTFLoader not loaded — ' + group.userData.id + ' stays a sphere'); return; }
    new T.GLTFLoader().load(url, gltf => {
      const m = gltf.scene;
      const box = new T.Box3().setFromObject(m), sz = new T.Vector3(), ctr = new T.Vector3();
      box.getSize(sz); box.getCenter(ctr);
      const s = (opts.fit || 2.4) / (Math.max(sz.x, sz.y, sz.z) || 1);
      m.scale.setScalar(s);
      m.position.set(-ctr.x * s, -ctr.y * s + (opts.lift || 0), -ctr.z * s);
      if (opts.rotY != null) m.rotation.y = opts.rotY;
      const sph = group.userData.sphere;
      if (sph) { sph.visible = false; const i = pickables.indexOf(sph); if (i >= 0) pickables.splice(i, 1); }
      m.traverse(o => { if (o.isMesh) { o.userData = { group: group }; pickables.push(o); } });
      group.add(m); group.userData.model = m;
      console.log('[world3d] model loaded for ' + group.userData.id + ': ' + url);
    }, undefined, err => console.error('[world3d] model load failed (' + url + ') — ' + group.userData.id + ' stays a sphere', err));
  }

  // ── convoy formation — staged ~100 km SOUTH of the coverage zone ─────────
  //    (drones will sweep the green/bravo boxes to prove the area is clear,
  //     then the convoy advances through it). A = north point, D = south rear.
  //    Zone south edge = 37.0°N; 1° lat ≈ 111.3 km, so 100 km ≈ 0.90°.
  //    Leading unit A = cLat + 3·SY = 36.10°N → ~100 km from the zone.
  const cLon = -15.0, cLat = 36.01, SX = 0.025, SY = 0.03;
  const P = (col, row) => [cLon + col * SX, cLat + row * SY];
  const SHIP = 0x60a5fa, CMDR = 0xfacc15, HVU = 0xa855f7, DRONE = 0xf59e0b;
  // ships (blue), commander D (yellow, rear centre)
  const aShip = body('A', ...P(0, 3), SHIP, { size: 0.05, textColor: '#0b1220' });
  // A = aircraft carrier / flagship (Oswald Boelcke).
  attachModel(aShip, 'js/vendor/models/german_super_aircraft_carrier_-_oswald_boelcke.glb', { fit: 3.6, rotY: Math.PI, lift: 0.2 });
  const bShip = body('B', ...P(3, 1), SHIP, { size: 0.04 });
  // B = the Black Pearl (drop the_black_pearl.glb into js/vendor/models/).
  attachModel(bShip, 'js/vendor/models/the_black_pearl.glb', { fit: 3.0, rotY: 0, lift: 0.2 });
  const fShip = body('F', ...P(-3, 1), SHIP, { size: 0.04 });
  // F = Arleigh Burke destroyer (left-swarm relay).
  attachModel(fShip, 'js/vendor/models/arleigh_burke_flight_iv_u.s.s._thomas_g._kelley.glb', { fit: 3.0, rotY: -Math.PI / 2, lift: 0.2 });
  const eShip = body('E', ...P(-3, -1), SHIP, { size: 0.032 });
  // E = submarine (drop submarine.glb into js/vendor/models/). rotY aims the bow.
  attachModel(eShip, 'js/vendor/models/submarine.glb', { fit: 2.8, rotY: 0, lift: 0 });
  const cShip = body('C', ...P(3, -3), SHIP, { size: 0.05 });
  // C = Imperial-class Star Destroyer (drop star-destroyer.glb into js/vendor/models/).
  // rotY aims the nose: try 0, ±Math.PI/2, Math.PI if it faces the wrong way.
  attachModel(cShip, 'js/vendor/models/star_wars_imperial-class_star_destroyer/scene.gltf', { fit: 3.4, rotY: Math.PI, lift: 0.3 });
  const dShip = body('D', ...P(0, -3), CMDR, { size: 0.05 });
  // D = Mon Calamari cruiser (commander flagship).
  attachModel(dShip, 'js/vendor/models/mon_calamari.glb', { fit: 3.4, rotY: Math.PI, lift: 0.2 });
  // HVUs (purple, centre column)
  const hvuFore = body('HVU', ...P(0, 1), HVU, { size: 0.042, textColor: '#f8fafc' });
  // fore HVU = container ship (the protected cargo).
  attachModel(hvuFore, 'js/vendor/models/container_ship.glb', { fit: 3.0, rotY: Math.PI / 2, lift: 0.2 });
  const hvuMid = body('HVU', ...P(0, 0), HVU, { size: 0.026, textColor: '#f8fafc' });
  const hvuAft = body('HVU', ...P(0, -1), HVU, { size: 0.042, textColor: '#f8fafc' });
  // aft HVU = cruise ship (protected civilians).
  attachModel(hvuAft, 'js/vendor/models/cruise_ship_07.glb', { fit: 3.0, rotY: -Math.PI / 2, lift: 0.2 });
  // middle HVU = Dassault Falcon 50.
  attachModel(hvuMid, 'js/vendor/models/dassault_falcon_50.glb', { fit: 2.4, rotY: Math.PI, lift: 0.3 });
  // alpha drones (amber) — left wing, 2-2-1
  const a1Drone = body('a1', ...P(-6, 2), DRONE, { size: 0.02 });
  const a2Drone = body('a2', ...P(-5, 2), DRONE, { size: 0.02 });
  // a1 = Fairey IIID seaplane, a2 = F-35 Lightning II (left swarm).
  attachModel(a1Drone, 'js/vendor/models/fairey_iii_d.glb', { fit: 2.0, rotY: Math.PI, lift: 0.3 });
  attachModel(a2Drone, 'js/vendor/models/f-35_lightning_ii_-_fighter_jet_-_free.glb', { fit: 2.0, rotY: Math.PI / 2, lift: 0.3 });
  const a3Drone = body('a3', ...P(-6, 1), DRONE, { size: 0.02 });
  const a4Drone = body('a4', ...P(-5, 1), DRONE, { size: 0.02 });
  // a3 = F-22 Raptor, a4 = F-16 Fighting Falcon (left swarm).
  attachModel(a3Drone, 'js/vendor/models/f-22_raptor_-_fighter_jet_-_free.glb', { fit: 2.0, rotY: Math.PI / 2, lift: 0.3 });
  attachModel(a4Drone, 'js/vendor/models/f-16_fighting_falcon_-_fighter_jet_-_free.glb', { fit: 2.0, rotY: Math.PI / 2, lift: 0.3 });
  const a5Drone = body('a5', ...P(-6, 0), DRONE, { size: 0.024 });
  // a5 = Boeing E-3 Sentry AWACS (left swarm).
  attachModel(a5Drone, 'js/vendor/models/boeing_e-3_sentry.glb', { fit: 2.4, rotY: -2 * Math.PI / 3, lift: 0.3 });
  // bravo drones (amber) — right wing, 2-2-1
  const b1Drone = body('b1', ...P(6, 2), DRONE, { size: 0.022 });
  const b2Drone = body('b2', ...P(5, 2), DRONE, { size: 0.02 });
  // b1 = Toothless, b2 = phoenix (right swarm).
  attachModel(b1Drone, 'js/vendor/models/toothless_-_how_to_train_your_dragon.glb', { fit: 2.2, rotY: Math.PI, lift: 0.3 });
  attachModel(b2Drone, 'js/vendor/models/phoenix.glb', { fit: 2.2, rotY: Math.PI, lift: 0.3 });
  const b3Drone = body('b3', ...P(6, 1), DRONE, { size: 0.02 });
  const b4Drone = body('b4', ...P(5, 1), DRONE, { size: 0.02 });
  // b3 = red bird, b4 = pterosaur (drop the .glb files into js/vendor/models/).
  // rotY aims heading; fit/lift tune size + height above the water.
  attachModel(b3Drone, 'js/vendor/models/red_bird.glb', { fit: 2.0, rotY: Math.PI, lift: 0.3 });
  attachModel(b4Drone, 'js/vendor/models/pterosaur_quetzalcoatlus_2.glb', { fit: 2.2, rotY: Math.PI, lift: 0.3 });
  const b5Drone = body('b5', ...P(6, 0), DRONE, { size: 0.022 });
  // b5 = Celestara the crowned sky steed (right swarm).
  attachModel(b5Drone, 'js/vendor/models/celestara_the_crowned_sky_steed.glb', { fit: 2.2, rotY: Math.PI, lift: 0.3 });

  // ── level-of-detail grid ────────────────────────────────────────────────
  const target = new T.Vector3(lonToX(cLon), 0, latToZ(cLat));
  let radius = 60, theta = -0.3, phi = 1.0;
  let gridLines = null; const gridLabels = [];
  let lastStep = null, lastCLon = null, lastCLat = null;
  function chooseStep() {
    const span = radius / SCALE;
    if (span > 6) return 1;
    if (span > 0.6) return 0.1;
    if (span > 0.06) return 0.01;
    if (span > 0.006) return 0.001;
    return 0.0001;
  }
  function buildGrid() {
    const step = chooseStep(), half = 24;
    const tLon = xToLon(target.x), tLat = zToLat(target.z);
    const cLo = Math.round(tLon / step) * step, cLa = Math.round(tLat / step) * step;
    if (step === lastStep && Math.abs(cLo - lastCLon) < step / 2 && Math.abs(cLa - lastCLat) < step / 2) return;
    lastStep = step; lastCLon = cLo; lastCLat = cLa;
    if (gridLines) { scene.remove(gridLines); gridLines.geometry.dispose(); }
    gridLabels.forEach(l => { scene.remove(l); const i = sprites.indexOf(l); if (i >= 0) sprites.splice(i, 1); });
    gridLabels.length = 0;
    const lonA = Math.max(WORLD.lonMin, cLo - half * step), lonB = Math.min(WORLD.lonMax, cLo + half * step);
    const latA = Math.max(WORLD.latMin, cLa - half * step), latB = Math.min(WORLD.latMax, cLa + half * step);
    const start = v => Math.ceil((v - 1e-9) / step) * step, pts = [];
    for (let lon = start(lonA); lon <= lonB + 1e-9; lon += step) pts.push(new T.Vector3(lonToX(lon), 0, latToZ(latA)), new T.Vector3(lonToX(lon), 0, latToZ(latB)));
    for (let lat = start(latA); lat <= latB + 1e-9; lat += step) pts.push(new T.Vector3(lonToX(lonA), 0, latToZ(lat)), new T.Vector3(lonToX(lonB), 0, latToZ(lat)));
    gridLines = new T.LineSegments(new T.BufferGeometry().setFromPoints(pts), new T.LineBasicMaterial({ color: 0xbfe3ff, transparent: true, opacity: step >= 1 ? 0.4 : 0.65, depthWrite: false }));
    gridLines.position.y = 0.35; scene.add(gridLines);
    const every = 6 * step;
    for (let lon = start(lonA); lon <= lonB + 1e-9; lon += step) { if (Math.abs(Math.round(lon / every) * every - lon) > step / 2) continue; labelSprite(gridLabels, `${Math.abs(lon).toFixed(4)}°W`, '#cfe3f7', 0.022).position.set(lonToX(lon), 1.6, latToZ(latA)); }
    for (let lat = start(latA); lat <= latB + 1e-9; lat += step) { if (Math.abs(Math.round(lat / every) * every - lat) > step / 2) continue; labelSprite(gridLabels, `${lat.toFixed(4)}°N`, '#cfe3f7', 0.022).position.set(lonToX(lonA), 1.6, latToZ(lat)); }
  }

  // ── camera + hover ──────────────────────────────────────────────────────
  function place() {
    const s = Math.sin(phi), c = Math.cos(phi);
    camera.position.set(target.x + radius * s * Math.sin(theta), target.y + radius * c, target.z + radius * s * Math.cos(theta));
    camera.lookAt(target);
  }
  const raycaster = new T.Raycaster(), ndc = new T.Vector2(), tip = document.getElementById('tip');
  function hover(e) {
    const w = host.clientWidth, h = host.clientHeight;
    ndc.set((e.clientX / w) * 2 - 1, -(e.clientY / h) * 2 + 1);
    raycaster.setFromCamera(ndc, camera);
    const hits = raycaster.intersectObjects(pickables, false);
    const g = hits.length ? hits[0].object.userData.group : null;
    if (g) {
      if (tip) { tip.innerHTML = `<b>${g.userData.id}</b> &nbsp; ${g.userData.lat.toFixed(4)}°N &nbsp; ${Math.abs(g.userData.lon).toFixed(4)}°W`; tip.style.left = (e.clientX + 14) + 'px'; tip.style.top = (e.clientY + 14) + 'px'; tip.hidden = false; }
      el.style.cursor = 'pointer';
    } else { if (tip) tip.hidden = true; el.style.cursor = ''; }
  }
  // ── selection · arrow-key flight · telemetry capture ────────────────────
  const selRing = new T.Mesh(new T.RingGeometry(1.5, 1.9, 40),
    new T.MeshBasicMaterial({ color: 0x38f5c8, transparent: true, opacity: 0.9, side: T.DoubleSide, depthWrite: false }));
  selRing.rotation.x = -Math.PI / 2; selRing.visible = false; scene.add(selRing);

  let selected = null;
  const keys = Object.create(null);
  const telem = Object.create(null);
  const selBox = document.getElementById('sel');
  const SAMPLE_STEP = 0.002;                                   // deg moved between telemetry samples (~220 m)
  const swarmOf = id => id[0] === 'a' ? 'alpha' : id[0] === 'b' ? 'bravo' : 'convoy';
  const zoneOf = id => id[0] === 'a' ? 'EX-010' : id[0] === 'b' ? 'EX-011' : null;
  const swarmColor = id => id[0] === 'a' ? 0x22c55e : id[0] === 'b' ? 0xa855f7 : 0x38bdf8;

  function telemetryFor(id) {
    return telem[id] || (telem[id] = { samples: [], lastLat: null, lastLon: null, pathPts: [], pathLine: null, saveTimer: 0 });
  }
  function pushSample(g) {
    const tl = telemetryFor(g.userData.id), lat = g.userData.lat, lon = g.userData.lon;
    tl.samples.push({ seq: tl.samples.length, t: Date.now(), lat: +lat.toFixed(6), lon: +lon.toFixed(6), lat_e7: Math.round(lat * 1e7), lon_e7: Math.round(lon * 1e7) });
    tl.lastLat = lat; tl.lastLon = lon;
    tl.pathPts.push(new T.Vector3(lonToX(lon), 0.5, latToZ(lat)));
    if (tl.pathLine) { scene.remove(tl.pathLine); tl.pathLine.geometry.dispose(); }
    tl.pathLine = new T.Line(new T.BufferGeometry().setFromPoints(tl.pathPts), new T.LineBasicMaterial({ color: swarmColor(g.userData.id), transparent: true, opacity: 0.95, depthWrite: false }));
    scene.add(tl.pathLine);
    scheduleSave(g.userData.id);
  }
  function recordSample(g) {
    const tl = telemetryFor(g.userData.id);
    if (tl.lastLat === null) { pushSample(g); return; }
    if (Math.hypot(g.userData.lat - tl.lastLat, g.userData.lon - tl.lastLon) >= SAMPLE_STEP) pushSample(g);
  }
  function moveSelected(dLon, dLat) {
    const g = selected;
    const lon = Math.max(WORLD.lonMin, Math.min(WORLD.lonMax, g.userData.lon + dLon));
    const lat = Math.max(WORLD.latMin, Math.min(WORLD.latMax, g.userData.lat + dLat));
    g.userData.lon = lon; g.userData.lat = lat;
    g.position.x = lonToX(lon); g.position.z = latToZ(lat);
    recordSample(g); updateSelHud();
  }
  function select(g) {
    selected = g; selRing.visible = !!g;
    if (g) { const tl = telemetryFor(g.userData.id); if (!tl.samples.length) pushSample(g); }
    updateSelHud();
  }
  function selectAt(e) {
    const w = host.clientWidth, h = host.clientHeight;
    ndc.set((e.clientX / w) * 2 - 1, -(e.clientY / h) * 2 + 1);
    raycaster.setFromCamera(ndc, camera);
    const hits = raycaster.intersectObjects(pickables, false);
    select(hits.length ? hits[0].object.userData.group : null);
  }
  function scheduleSave(id) {
    const tl = telemetryFor(id);
    clearTimeout(tl.saveTimer);
    tl.saveTimer = setTimeout(() => saveTelemetry(id), 700);
  }
  function saveTelemetry(id) {
    const tl = telemetryFor(id);
    if (!tl.samples.length) return;
    const payload = { drone: id, swarm: swarmOf(id), zone: zoneOf(id), generated_at: new Date().toISOString(), count: tl.samples.length, samples: tl.samples };
    setStatus('saving ' + tl.samples.length + ' pts…');
    fetch('/api/telemetry/' + id, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) })
      .then(r => r.ok ? r.json() : Promise.reject('HTTP ' + r.status))
      .then(res => setStatus('saved ' + res.count + ' pts → ' + res.path))
      .catch(err => setStatus('save failed (' + err + ') — start serve.py', true));
  }
  function setStatus(msg, err) {
    const s = document.getElementById('svstat');
    if (s) { s.textContent = msg; s.style.color = err ? '#fca5a5' : '#86efac'; }
  }
  function updateSelHud() {
    if (!selBox) return;
    if (!selected) { selBox.innerHTML = '<span class="dim">no unit selected — click a unit, then fly it with the arrow keys</span>'; return; }
    const g = selected, tl = telemetryFor(g.userData.id);
    selBox.innerHTML = '<b style="color:#7dd3fc">' + g.userData.id + '</b> selected &nbsp; ' +
      g.userData.lat.toFixed(4) + '°N&nbsp; ' + Math.abs(g.userData.lon).toFixed(4) + '°W' +
      ' &nbsp;·&nbsp; <span class="dim">' + tl.samples.length + ' telemetry pts</span> &nbsp; <span id="svstat"></span>';
  }
  updateSelHud();

  window.addEventListener('keydown', e => {
    if (e.key === 'ArrowUp' || e.key === 'ArrowDown' || e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
      if (selected) { keys[e.key] = true; e.preventDefault(); }
    } else if (e.key === 'Enter') { if (selected) saveTelemetry(selected.userData.id); }
    else if ((e.key === 'c' || e.key === 'C') && selected) {
      const tl = telemetryFor(selected.userData.id);
      tl.samples = []; tl.lastLat = tl.lastLon = null; tl.pathPts = [];
      if (tl.pathLine) { scene.remove(tl.pathLine); tl.pathLine.geometry.dispose(); tl.pathLine = null; }
      pushSample(selected); updateSelHud();
    }
  });
  window.addEventListener('keyup', e => { if (keys[e.key] !== undefined) keys[e.key] = false; });

  // ── camera input (orbit / pan / click-select) ───────────────────────────
  let mode = null, lx = 0, ly = 0, downX = 0, downY = 0, downBtn = 0;
  const el = renderer.domElement;
  el.addEventListener('mousedown', e => { mode = (e.shiftKey || e.button === 2) ? 'pan' : 'orbit'; lx = e.clientX; ly = e.clientY; downX = e.clientX; downY = e.clientY; downBtn = e.button; if (tip) tip.hidden = true; e.preventDefault(); });
  el.addEventListener('contextmenu', e => e.preventDefault());
  window.addEventListener('mouseup', e => { const wasClick = downBtn === 0 && Math.abs(e.clientX - downX) < 5 && Math.abs(e.clientY - downY) < 5; mode = null; if (wasClick) selectAt(e); });
  window.addEventListener('mousemove', e => {
    if (!mode) { hover(e); return; }
    const dx = e.clientX - lx, dy = e.clientY - ly; lx = e.clientX; ly = e.clientY;
    if (mode === 'orbit') { theta -= dx * 0.005; phi = Math.max(0.10, Math.min(1.50, phi - dy * 0.005)); place(); }
    else { const fwd = new T.Vector3(); camera.getWorldDirection(fwd); fwd.y = 0; fwd.normalize(); const rgt = new T.Vector3(-fwd.z, 0, fwd.x); const k = (2 * radius * Math.tan(camera.fov * Math.PI / 360)) / host.clientHeight; target.addScaledVector(rgt, -dx * k); target.addScaledVector(fwd, dy * k); place(); buildGrid(); }
  });
  el.addEventListener('wheel', e => { e.preventDefault(); radius = Math.max(0.25, Math.min(1800, radius * (1 + e.deltaY * 0.0012))); place(); buildGrid(); }, { passive: false });

  function resize() { const w = host.clientWidth, h = host.clientHeight; renderer.setSize(w, h); camera.aspect = w / h; camera.updateProjectionMatrix(); }
  window.addEventListener('resize', resize);
  resize(); place(); buildGrid();

  const clock = new T.Clock(), cpos = new T.Vector3(), wp = new T.Vector3();
  (function loop() {
    requestAnimationFrame(loop);
    const dt = clock.getDelta();
    if (water) water.material.uniforms['time'].value += dt;
    if (selected && (keys.ArrowUp || keys.ArrowDown || keys.ArrowLeft || keys.ArrowRight)) {
      const speed = Math.min(0.5, Math.max(0.003, (radius / SCALE) * 0.12));   // deg/sec, faster when zoomed out
      let dLat = (keys.ArrowUp ? 1 : 0) - (keys.ArrowDown ? 1 : 0);
      let dLon = (keys.ArrowRight ? 1 : 0) - (keys.ArrowLeft ? 1 : 0);
      const mag = Math.hypot(dLat, dLon) || 1;
      moveSelected(dLon / mag * speed * dt, dLat / mag * speed * dt);
    }
    cpos.copy(camera.position);
    for (const sp of sprites) { const d = cpos.distanceTo(sp.getWorldPosition(wp)); const s = d * sp.userData.size; sp.scale.set(s * sp.userData.aspect, s, 1); }
    for (const g of bodies) { const d = cpos.distanceTo(g.position); g.scale.setScalar(Math.max(0.02, d * g.userData.size)); g.userData.label.scale.set(g.userData.label.userData.aspect, 1, 1); }
    if (selected) { const d = cpos.distanceTo(selected.position); selRing.position.set(selected.position.x, 0.42, selected.position.z); selRing.scale.setScalar(Math.max(0.02, d * selected.userData.size) * 1.8); }
    renderer.render(scene, camera);
  })();
})();

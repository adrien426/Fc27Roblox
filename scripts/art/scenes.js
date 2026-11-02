// The pictures (see shoot.mjs): each scene lays out a background, the 3D render and its titles in #stage
const wait = () => new Promise(r => { const t = () => window.FC ? r() : setTimeout(t, 50); t(); });
await wait();
const { THREE, C, TEAMS, player, ball, pitch, goal, stadium, makeRenderer, lights } = window.FC;
const { RoomEnvironment } = await import('three/addons/environments/RoomEnvironment.js');

const style = document.createElement('style');
style.textContent = `@font-face{font-family:Lilita;src:url(fonts/lilita.woff2) format('woff2')}
.t{position:absolute;font-family:Lilita,sans-serif;color:#fff;text-align:center;line-height:1;white-space:nowrap;
  -webkit-text-stroke:0;paint-order:stroke fill}
.conf{position:absolute;border-radius:2px}`;
document.head.appendChild(style);
await document.fonts.load('40px Lilita');

const stage = document.getElementById('stage');
function reset(w, h, bg) {
  stage.innerHTML = '';
  stage.style.width = w + 'px'; stage.style.height = h + 'px';
  stage.style.background = bg || 'transparent';
}
let renderer = null;
function gl(w, h, scene, cam) {
  if (renderer) renderer.dispose();
  renderer = makeRenderer(w, h);
  renderer.render(scene, cam);
  const img = new Image();
  img.src = renderer.domElement.toDataURL('image/png');
  img.style.cssText = 'position:absolute;left:0;top:0';
  stage.appendChild(img);
  return img;
}
function el(tag, css, html) {
  const e = document.createElement(tag);
  e.style.cssText = css;
  if (html != null) e.innerHTML = html;
  stage.appendChild(e);
  return e;
}
// Big title: white with a thick dark outline and a drop shadow
function title(text, css, { size = 80, color = '#fff', stroke = '#14241a', sw = 0.16 } = {}) {
  const e = el('div', `font-size:${size}px;color:${color};-webkit-text-stroke:${size * sw}px ${stroke};` +
    `filter:drop-shadow(0 ${size * 0.06}px 0 rgba(0,0,0,.35));` + css, text);
  e.className = 't';
  return e;
}
let seed = 7;
const rnd = () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
function confetti(n, w, h, colors, { y0 = 0, y1 = 1, size = 1 } = {}) {
  for (let i = 0; i < n; i++) {
    const c = el('div', `left:${rnd() * w}px;top:${(y0 + rnd() * (y1 - y0)) * h}px;width:${(8 + rnd() * 10) * size}px;height:${(4 + rnd() * 6) * size}px;` +
      `background:${colors[i % colors.length]};transform:rotate(${rnd() * 360}deg);opacity:${0.75 + rnd() * 0.25}`);
    c.className = 'conf';
  }
}
function sparkles(n, w, h, color = '#fff', size = 1) {
  for (let i = 0; i < n; i++) {
    const s = (10 + rnd() * 18) * size;
    el('div', `position:absolute;left:${rnd() * w}px;top:${rnd() * h}px;width:${s}px;height:${s}px;background:${color};` +
      `clip-path:polygon(50% 0,61% 39%,100% 50%,61% 61%,50% 100%,39% 61%,0 50%,39% 39%);opacity:${0.5 + rnd() * 0.5}`);
  }
}
function scene3d({ env = 0, sun, power } = {}) {
  const s = new THREE.Scene();
  lights(s, { sun, power });
  if (env) {
    const r = makeRenderer(16, 16);
    const pm = new THREE.PMREMGenerator(r);
    s.environment = pm.fromScene(new RoomEnvironment(), 0.04).texture;
    s.environmentIntensity = env;
  }
  return s;
}
function cam(w, h, fov, pos, look) {
  const c = new THREE.PerspectiveCamera(fov, w / h, 0.05, 1000);
  c.position.set(...pos); c.lookAt(...look);
  return c;
}
// A soft round shadow on transparent ground
function blob(r = 0.6, o = 0.35) {
  const cv = document.createElement('canvas'); cv.width = cv.height = 128;
  const k = cv.getContext('2d');
  const g = k.createRadialGradient(64, 64, 0, 64, 64, 64);
  g.addColorStop(0, `rgba(0,0,0,${o})`); g.addColorStop(1, 'rgba(0,0,0,0)');
  k.fillStyle = g; k.fillRect(0, 0, 128, 128);
  const m = new THREE.Mesh(new THREE.PlaneGeometry(r * 2, r * 2), new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(cv), transparent: true, depthWrite: false }));
  m.rotation.x = -Math.PI / 2; m.position.y = 0.005;
  return m;
}
const RED = TEAMS[0], BLUE = TEAMS[1];
const GOLD = C(230, 180, 40), BLACK = C(20, 20, 22), PINK = C(235, 60, 140), CYAN = C(40, 200, 230), WHITE = C(240, 240, 240);
const mix = (a, b, k) => a.clone().lerp(b, k);
const kit = (team, extra = {}) => ({ shirt: team.color, shorts: team.shorts, boots: BLACK, ...extra });

// A gold coin, face up by default, with a star stamped on it
function coin(r = 0.5) {
  const cv = document.createElement('canvas'); cv.width = cv.height = 256;
  const k = cv.getContext('2d');
  const g = k.createRadialGradient(110, 100, 10, 128, 128, 128);
  g.addColorStop(0, '#ffe58a'); g.addColorStop(0.7, '#f2c230'); g.addColorStop(1, '#c98f12');
  k.fillStyle = g; k.fillRect(0, 0, 256, 256);
  k.strokeStyle = '#b7800c'; k.lineWidth = 14; k.beginPath(); k.arc(128, 128, 104, 0, Math.PI * 2); k.stroke();
  k.fillStyle = '#d99a14';
  k.beginPath();
  for (let i = 0; i < 10; i++) {
    const a = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 ? 30 : 70;
    k.lineTo(128 + Math.cos(a) * rr, 128 + Math.sin(a) * rr);
  }
  k.fill();
  const face = new THREE.CanvasTexture(cv); face.colorSpace = THREE.SRGBColorSpace;
  const side = new THREE.MeshStandardMaterial({ color: C(222, 165, 30), metalness: 0.85, roughness: 0.3 });
  const top = new THREE.MeshStandardMaterial({ map: face, metalness: 0.6, roughness: 0.35 });
  return new THREE.Mesh(new THREE.CylinderGeometry(r, r, r * 0.16, 48), [side, top, top]);
}
function coinPile(n, spread, r) {
  const g = new THREE.Group();
  // stacks
  const stacks = [];
  for (let i = 0; i < n.stacks; i++) {
    const a = (i / Math.max(1, n.stacks)) * Math.PI * 2 + 0.4;
    const d = n.stacks === 1 ? 0 : spread * (0.55 + 0.45 * ((i * 37) % 7) / 7);
    stacks.push([Math.cos(a) * d, Math.sin(a) * d, n.height - (i % 3) * 2]);
  }
  for (const [x, z, h] of stacks) {
    for (let j = 0; j < h; j++) {
      const c = coin(r);
      c.position.set(x + (rnd() - 0.5) * 0.04, r * 0.08 + j * r * 0.165, z + (rnd() - 0.5) * 0.04);
      c.rotation.y = rnd() * 6;
      g.add(c);
    }
  }
  // loose coins around, some leaning
  for (let i = 0; i < n.loose; i++) {
    const c = coin(r);
    const a = rnd() * Math.PI * 2, d = spread * (0.3 + rnd() * 1.1);
    c.position.set(Math.cos(a) * d, r * 0.1, Math.sin(a) * d * 0.8);
    c.rotation.set((rnd() - 0.5) * 0.5, rnd() * 6, (rnd() - 0.5) * 0.5);
    g.add(c);
  }
  return g;
}

// Ball in flight with a fire / stars / ice trail drawn behind it (2D, under the 3D ball)
function trail(w, h, from, to, kind, width = 70) {
  const cv = el('canvas', 'position:absolute;left:0;top:0');
  cv.width = w; cv.height = h;
  const k = cv.getContext('2d');
  const cols = {
    fire: ['rgba(255,250,200,1)', 'rgba(255,190,40,0.95)', 'rgba(255,90,20,0.8)', 'rgba(200,30,10,0)'],
    ice: ['rgba(240,255,255,1)', 'rgba(150,230,255,0.9)', 'rgba(70,160,255,0.6)', 'rgba(40,80,255,0)'],
    stars: ['rgba(255,255,230,1)', 'rgba(255,235,140,0.9)', 'rgba(255,210,80,0.5)', 'rgba(255,180,40,0)'],
  }[kind];
  const [x0, y0] = from, [x1, y1] = to; // from = tail, to = ball
  const ang = Math.atan2(y1 - y0, x1 - x0), len = Math.hypot(x1 - x0, y1 - y0);
  for (const [blur, wk, a] of [[18, 1.5, 0.7], [6, 1, 1], [0, 0.5, 1]]) {
    k.save();
    k.translate(x1, y1); k.rotate(ang);
    k.filter = `blur(${blur}px)`;
    k.globalAlpha = a;
    const g = k.createLinearGradient(0, 0, -len, 0);
    g.addColorStop(0, cols[0]); g.addColorStop(0.25, cols[1]); g.addColorStop(0.6, cols[2]); g.addColorStop(1, cols[3]);
    k.fillStyle = g;
    k.beginPath();
    const W2 = width * wk / 2;
    k.moveTo(8, -W2);
    // flame tongues along the edges
    const N = 9;
    for (let i = 1; i <= N; i++) { const t = i / N; k.lineTo(-len * t, -W2 * (1 - t) * (i % 2 ? 1.25 : 0.8)); }
    for (let i = N; i >= 1; i--) { const t = i / N; k.lineTo(-len * t, W2 * (1 - t) * (i % 2 ? 0.8 : 1.25)); }
    k.lineTo(8, W2);
    k.arc(8, 0, W2, Math.PI / 2, -Math.PI / 2, true);
    k.fill();
    k.restore();
  }
  if (kind === 'stars') {
    for (let i = 0; i < 14; i++) {
      const t = rnd(), s = 10 + rnd() * 16 * (1 - t);
      const x = x1 + (x0 - x1) * t + (rnd() - 0.5) * width, y = y1 + (y0 - y1) * t + (rnd() - 0.5) * width;
      el('div', `position:absolute;left:${x - s / 2}px;top:${y - s / 2}px;width:${s}px;height:${s}px;background:#fff6c0;clip-path:polygon(50% 0,61% 39%,100% 50%,61% 61%,50% 100%,39% 61%,0 50%,39% 39%)`);
    }
  }
}

// Ball scene: just the ball, at a given screen spot (renders a 3D ball and returns nothing)
function ballLayer(w, h, kind, at, px) {
  const s = scene3d({ env: 1, sun: [3, 6, 5] });
  const b = ball(kind, 1); b.rotation.set(0.4, 0.8, 0.2); s.add(b);
  // orthographic camera: 1 unit = px pixels, ball centred at screen point `at`
  const c = new THREE.OrthographicCamera(-w / 2 / px, w / 2 / px, h / 2 / px, -h / 2 / px, 0.1, 100);
  c.position.set(-(at[0] - w / 2) / px, (at[1] - h / 2) / px, 10); c.lookAt(c.position.x, c.position.y, 0);
  gl(w, h, s, c);
}

const BG = {
  purple: 'radial-gradient(circle at 50% 40%, #9b5cff 0%, #5a2bd6 55%, #2a1170 100%)',
  teal: 'radial-gradient(circle at 50% 40%, #3fe0c8 0%, #12a08f 55%, #0b4f5a 100%)',
  gold: 'radial-gradient(circle at 50% 38%, #fff1a8 0%, #f2c230 45%, #b8740c 100%)',
  night: 'radial-gradient(circle at 60% 45%, #3a4fd6 0%, #1a2470 55%, #0a0e30 100%)',
  green: 'radial-gradient(circle at 50% 40%, #6be36b 0%, #2f9e3f 55%, #135a22 100%)',
  sky: 'linear-gradient(#4aa8ff, #9fd4ff)',
};

window.SCENES = {
  // ---------- Shop items (512 x 512, subject inside the central circle: Roblox shows them round) ----------
  celebrations: { run() {
    const W = 512, H = 512; reset(W, H, BG.purple);
    confetti(70, W, H, ['#ffd23f', '#ff5c8a', '#3fe0ff', '#7dff6b', '#ffffff']);
    const s = scene3d();
    const p = player(kit(RED, { boots: GOLD, pose: ['victory', 0.8] }));
    p.rotation.y = 0.25; s.add(p, blob(0.7));
    const b = ball(); b.position.set(0.55, 0.11, 0.35); s.add(b);
    gl(W, H, s, cam(W, H, 30, [0, 0.6, 5.6], [0, 1.08, 0]));
    return [W, H];
  } },
  style: { run() {
    const W = 512, H = 512; reset(W, H, BG.teal);
    sparkles(16, W, H);
    const s = scene3d({ env: 0.5 });
    const a = player(kit(RED, { shirt: mix(RED.color, GOLD, 0.55), boots: GOLD, pose: ['idle', 0.3] }));
    a.position.x = -0.5; a.rotation.y = 0.35;
    const b = player(kit(BLUE, { shirt: mix(BLUE.color, BLACK, 0.55), boots: PINK, pose: ['idle', 1.1] }));
    b.position.x = 0.5; b.rotation.y = -0.35;
    s.add(a, b, blob(1.2));
    gl(W, H, s, cam(W, H, 30, [0, 0.45, 5.2], [0, 0.98, 0]));
    // Boots close-up badges
    for (const [x, c] of [[70, '#e6b428'], [442, '#eb3c8c']]) {
      el('div', `position:absolute;left:${x - 26}px;top:400px;width:52px;height:52px;border-radius:50%;background:${c};border:5px solid #fff;box-shadow:0 4px 0 rgba(0,0,0,.3)`);
    }
    return [W, H];
  } },
  vip: { run() {
    const W = 512, H = 512; reset(W, H, BG.gold);
    // light rays
    el('div', 'position:absolute;inset:0;background:repeating-conic-gradient(from 0deg at 50% 45%, rgba(255,255,255,.22) 0 10deg, rgba(255,255,255,0) 10deg 20deg)');
    sparkles(14, W, H, '#fffbe0');
    const s = scene3d({ env: 0.4 });
    const p = player(kit(BLUE, { boots: GOLD, pose: ['idle', 0.6] }));
    p.rotation.y = 0.2; s.add(p, blob(0.7));
    gl(W, H, s, cam(W, H, 30, [0, 0.9, 5.3], [0, 0.98, 0]));
    // Gold name over the head, as in the game
    title('★ VIP', 'left:0;right:0;top:44px', { size: 70, color: '#ffd84a', stroke: '#5a3a00' });
    return [W, H];
  } },
  trail: { run() {
    const W = 512, H = 512; reset(W, H, BG.night);
    sparkles(18, W, H, '#ffffff', 0.6);
    trail(W, H, [40, 440], [330, 190], 'fire', 120);
    ballLayer(W, H, 'classique', [330, 190], 120);
    // two little ones: ice and stars
    trail(W, H, [250, 470], [420, 360], 'ice', 48);
    ballLayer2(W, H, [[420, 360, 48]]);
    trail(W, H, [40, 260], [150, 110], 'stars', 48);
    ballLayer2(W, H, [[150, 110, 48]]);
    return [W, H];
  } },
  coins500: { run() { return coinsScene(500, { stacks: 1, height: 6, loose: 2 }, 0.95, 0.5); } },
  coins1500: { run() { return coinsScene(1500, { stacks: 3, height: 8, loose: 5 }, 0.95, 0.75); } },
  coins5000: { run() { return coinsScene(5000, { stacks: 7, height: 12, loose: 14 }, 0.95, 0.95); } },

  // ---------- The game's icon (512 x 512) ----------
  icon: { run() {
    const W = 512, H = 512; reset(W, H, BG.green);
    el('div', 'position:absolute;inset:0;background:repeating-linear-gradient(90deg, rgba(255,255,255,.07) 0 64px, rgba(0,0,0,0) 64px 128px)');
    el('div', 'position:absolute;inset:0;background:repeating-conic-gradient(from 0deg at 50% 70%, rgba(255,255,255,.12) 0 8deg, rgba(255,255,255,0) 8deg 16deg)');
    const s = scene3d();
    const p = player(kit(RED, { boots: GOLD, pose: ['kick', 0.5] }));
    p.rotation.y = 0.9; s.add(p, blob(0.7));
    const b = ball(); b.position.set(0.75, 0.45, 0.45); s.add(b);
    gl(W, H, s, cam(W, H, 30, [0.2, 0.8, 5.4], [0.15, 1.12, 0]));
    title('FC27', 'left:0;right:0;top:16px', { size: 104, color: '#ffd23f' });
    return [W, H];
  } },

  // ---------- Thumbnails (1920 x 1080) ----------
  thumb1: { run() {
    const W = 1920, H = 1080; reset(W, H, BG.sky);
    const s = scene3d({ sun: [30, 60, 20], power: 2.2 });
    s.add(pitch(), goal(-52.5), goal(52.5));
    try { s.add(stadium()); } catch (e) { console.log('stadium', e.message); }
    const F = [[3, 34, 'GK', 1], [18, 9], [15, 26], [15, 42], [18, 59], [32, 11], [29, 28], [29, 40], [32, 57], [46, 28], [46, 40]];
    for (const t of [0, 1]) {
      F.forEach(([x, y, r], i) => {
        const team = TEAMS[t];
        const gk = r === 'GK';
        const px = (t === 0 ? x : 105 - x) - 52.5, pz = y - 34;
        const m = player(kit(team, { shirt: gk ? team.gk : team.color, shorts: gk ? C(25, 25, 25) : team.shorts, boots: [BLACK, WHITE, GOLD, CYAN][i % 4], pose: [gk ? 'gkIdle' : 'run', (i * 0.17) % 0.7] }));
        m.position.set(px * 0.8 + (t === 0 ? 4 : -4), 0, pz * 0.8);
        m.rotation.y = (t === 0 ? 1 : -1) * Math.PI / 2;
        s.add(m);
      });
    }
    const b = ball('classique', 0.4); b.position.set(-0.5, 0.2, 2); s.add(b);
    gl(W, H, s, cam(W, H, 40, [-6, 9, 26], [1, 0, -2]));
    el('div', 'position:absolute;left:0;top:0;width:1100px;height:360px;background:radial-gradient(ellipse at 0% 0%, rgba(10,20,40,.85) 0%, rgba(10,20,40,.55) 45%, rgba(10,20,40,0) 75%)');
    title('FC27', 'left:60px;top:50px', { size: 170, color: '#ffd23f' });
    title('Foot à 11 contre 11 !', 'left:66px;top:235px', { size: 64 });
    return [W, H];
  } },
  thumb2: { run() {
    const W = 1920, H = 1080; reset(W, H, BG.sky);
    const s = scene3d({ sun: [10, 20, 14] });
    s.add(pitch(), goal(52.5));
    try { s.add(stadium()); } catch (e) { console.log('stadium', e.message); }
    const sh = player(kit(RED, { boots: GOLD, pose: ['kick', 0.5] }));
    sh.position.set(41, 0, 3); sh.rotation.y = Math.PI / 2 - 0.25; s.add(sh);
    const gk = player(kit(BLUE, { shirt: BLUE.gk, shorts: C(25, 25, 25), boots: WHITE, pose: ['diveL', 0.45] }));
    gk.position.set(51.2, 0, -0.5); gk.rotation.y = -Math.PI / 2; s.add(gk);
    const df = player(kit(BLUE, { boots: BLACK, pose: ['tackle', 0.4] }));
    df.position.set(43.5, 0, 5.2); df.rotation.y = -Math.PI / 2 - 0.6; s.add(df);
    const c = cam(W, H, 38, [36, 2.6, 13], [46.5, 1.2, 0]);
    s.add(sh, gk);
    const img = gl(W, H, s, c);
    // the ball flying to the top corner, with its fire trail
    const p0 = new THREE.Vector3(42.3, 0.5, 2.6).project(c), p1 = new THREE.Vector3(51.8, 1.55, -2.6).project(c);
    const sp = v => [(v.x + 1) / 2 * W, (1 - v.y) / 2 * H];
    trail(W, H, sp(p0), sp(p1), 'fire', 70);
    ballLayer2(W, H, [[...sp(p1), 62]]);
    title('BUUUT !', 'right:70px;top:60px', { size: 150, color: '#ffd23f' });
    return [W, H];
  } },
  thumb3: { run() {
    const W = 1920, H = 1080; reset(W, H, BG.purple);
    el('div', 'position:absolute;inset:0;background:repeating-conic-gradient(from 0deg at 50% 60%, rgba(255,255,255,.10) 0 8deg, rgba(255,255,255,0) 8deg 16deg)');
    confetti(160, W, H, ['#ffd23f', '#ff5c8a', '#3fe0ff', '#7dff6b', '#ffffff'], { size: 1.6 });
    const s = scene3d({ env: 0.3 });
    const kits = [
      [RED, mix(RED.color, GOLD, 0.55), GOLD, ['victory', 0.8], -1.6, 0.4],
      [BLUE, mix(BLUE.color, BLACK, 0.55), PINK, ['dance', 1.0], 0, 0],
      [RED, RED.color, CYAN, ['victory', 2.4], 1.6, -0.4],
    ];
    for (const [team, shirt, boots, pose, x, ry] of kits) {
      const p = player(kit(team, { shirt, boots, pose }));
      p.position.x = x; p.rotation.y = ry; const bl = blob(0.8); bl.position.x = x; s.add(p, bl);
    }
    gl(W, H, s, cam(W, H, 30, [0, 0.9, 8.6], [0, 1.0, 0]));
    title('Célèbre tes buts !', 'left:0;right:0;top:40px', { size: 110, color: '#ffd23f' });
    title('Crampons, maillots, effets de tir', 'left:0;right:0;bottom:50px', { size: 60 });
    return [W, H];
  } },
};

// Several balls at screen points [x, y, diameter px]
function ballLayer2(w, h, list) {
  for (const [x, y, d] of list) ballLayer(w, h, 'classique', [x, y], d);
}
function coinsScene(n, pile, zoom, spread) {
  const W = 512, H = 512; reset(W, H, BG.gold);
  el('div', 'position:absolute;inset:0;background:repeating-conic-gradient(from 0deg at 50% 45%, rgba(255,255,255,.22) 0 10deg, rgba(255,255,255,0) 10deg 20deg)');
  sparkles(10, W, H, '#fffbe0');
  const s = scene3d({ env: 2.2, sun: [3, 8, 5], power: 3.2 });
  s.add(coinPile(pile, spread, 0.4));
  gl(W, H, s, cam(W, H, 30, [0, 3.2 * zoom, 5.2 * zoom], [0, 0.35, 0]));
  title(n.toLocaleString('fr-FR'), 'left:0;right:0;bottom:34px', { size: 96, color: '#ffffff', stroke: '#6a3d00' });
  return [W, H];
}

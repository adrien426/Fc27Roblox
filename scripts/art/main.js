// Loads the game's footballer, balls and stadium (three.js) and makes footballers in any kit and pose (the web
// game's animation clips), balls, a pitch, goals and the stadium for the pictures in scenes.js.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import * as SkeletonUtils from 'three/addons/utils/SkeletonUtils.js';

const loader = new GLTFLoader();
const load = (u) => new Promise((ok, ko) => loader.load(u, ok, undefined, ko));
const json = (u) => fetch(u).then(r => r.json());

const [playerG, ballsG, stadiumG, base, clips, siuu] = await Promise.all([
  load('m/player.glb'), load('m/balls.glb'), load('m/stadium.glb'),
  json('m/base.json'), json('m/clips.json'), json('m/siuu.json'),
]);
const ALL = { ...base, ...clips, siuu };

function clip(name) {
  const src = ALL[name];
  const tracks = [];
  for (const t of src.tracks) {
    const m = t.name.match(/^mixamorig\d*:?(\w+)\.(quaternion|position)$/);
    if (!m) continue;
    const bone = 'mixamorig5' + m[1];
    if (m[2] === 'quaternion') tracks.push(new THREE.QuaternionKeyframeTrack(bone + '.quaternion', t.times, t.values));
    else if (m[1] === 'Hips') {
      const v = t.values.slice();
      const big = Math.abs(v[1]) > 5;
      for (let i = 0; i < v.length; i++) v[i] = i % 3 === 1 ? (big ? v[i] / 100 : v[i]) : 0;
      tracks.push(new THREE.VectorKeyframeTrack(bone + '.position', t.times, v));
    }
  }
  return new THREE.AnimationClip(name, src.duration, tracks);
}

const C = (r, g, b) => new THREE.Color().setRGB(r / 255, g / 255, b / 255, THREE.SRGBColorSpace);
export const TEAMS = [
  { color: C(215, 38, 61), shorts: C(244, 244, 244), gk: C(34, 179, 107) },
  { color: C(43, 111, 214), shorts: C(15, 31, 69), gk: C(242, 194, 48) },
];

// A footballer: kit colours, pose = [clip, time]
export function player({ shirt, shorts, socks, boots, hair = C(40, 28, 20), pose = ['idle', 0.3], skin }) {
  const root = SkeletonUtils.clone(playerG.scene);
  root.traverse(o => {
    if (!o.isMesh) return;
    o.frustumCulled = false;
    o.castShadow = true;
    o.material = o.material.clone();
    const n = o.name;
    if (/Shirt/.test(n)) o.material.color = shirt.clone();
    else if (/Shorts/.test(n)) o.material.color = shorts.clone();
    else if (/Socks/.test(n)) o.material.color = (socks || shirt).clone();
    else if (/Shoes/.test(n)) { o.material.map = null; o.material.color = boots.clone(); o.material.roughness = 0.3; o.material.metalness = boots.getHSL({}).s > 0.5 && boots.getHSL({}).l > 0.35 ? 0.35 : 0.05; }
    else if (/Hair/.test(n)) o.material.color = hair.clone();
    else if (/Body/.test(n) && skin) o.material.color = skin.clone();
  });
  const mixer = new THREE.AnimationMixer(root);
  const a = mixer.clipAction(clip(pose[0]));
  a.play();
  mixer.setTime(pose[1]);
  root.updateMatrixWorld(true);
  return root;
}

export function ball(kind = 'classique', size = 0.22) {
  const src = ballsG.scene.getObjectByName(kind) || ballsG.scene.getObjectByName('Classic');
  const b = src.clone(true);
  b.position.set(0, 0, 0);
  b.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(b);
  const s = size / Math.max(...box.getSize(new THREE.Vector3()).toArray());
  const g = new THREE.Group();
  b.scale.multiplyScalar(s);
  b.updateMatrixWorld(true);
  const c = new THREE.Box3().setFromObject(b).getCenter(new THREE.Vector3());
  b.position.sub(c);
  b.traverse(o => { if (o.isMesh) o.castShadow = true; });
  g.add(b);
  return g;
}

// Pitch: stripes and lines, 105 x 68, centre at origin, x along the length
export function pitch() {
  const cv = document.createElement('canvas');
  cv.width = 2100; cv.height = 1360;
  const k = cv.getContext('2d');
  for (let i = 0; i < 14; i++) {
    k.fillStyle = i % 2 ? '#3f8f3a' : '#4a9c43';
    k.fillRect(i * 150, 0, 150, 1360);
  }
  k.strokeStyle = 'rgba(255,255,255,0.92)'; k.lineWidth = 3;
  const m = 20; // px per metre
  k.strokeRect(0 + 2, 2, 2096, 1356);
  k.beginPath(); k.moveTo(1050, 0); k.lineTo(1050, 1360); k.stroke();
  k.beginPath(); k.arc(1050, 680, 9.15 * m, 0, Math.PI * 2); k.stroke();
  for (const side of [0, 1]) {
    const x0 = side ? 2100 : 0, d = side ? -1 : 1;
    k.strokeRect(Math.min(x0, x0 + d * 16.5 * m), 680 - 20.16 * m, 16.5 * m, 40.32 * m);
    k.strokeRect(Math.min(x0, x0 + d * 5.5 * m), 680 - 9.16 * m, 5.5 * m, 18.32 * m);
    k.beginPath(); k.arc(x0 + d * 11 * m, 680, 3, 0, Math.PI * 2); k.fill();
  }
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 8;
  const surround = new THREE.Mesh(new THREE.PlaneGeometry(160, 110), new THREE.MeshStandardMaterial({ color: C(60, 128, 55), roughness: 1 }));
  surround.rotation.x = -Math.PI / 2; surround.position.y = -0.01; surround.receiveShadow = true;
  const p = new THREE.Mesh(new THREE.PlaneGeometry(105, 68), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.95 }));
  p.rotation.x = -Math.PI / 2; p.receiveShadow = true;
  const g = new THREE.Group(); g.add(surround, p);
  return g;
}

export function goal(x) {
  const g = new THREE.Group();
  const mat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.4 });
  const post = (h) => new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, h, 12), mat);
  for (const z of [-3.66, 3.66]) { const p = post(2.44); p.position.set(0, 1.22, z); g.add(p); }
  const bar = post(7.32); bar.rotation.x = Math.PI / 2; bar.position.set(0, 2.44, 0); g.add(bar);
  const net = new THREE.Mesh(new THREE.BoxGeometry(2, 2.44, 7.32), new THREE.MeshStandardMaterial({ color: 0xffffff, wireframe: true, transparent: true, opacity: 0.35 }));
  net.position.set(Math.sign(x) * 1, 1.22, 0); g.add(net);
  g.position.x = x;
  return g;
}

export function stadium() {
  const s = stadiumG.scene.clone(true);
  const S = 68 / 137;
  s.scale.setScalar(S);
  s.updateMatrixWorld(true);
  let box = new THREE.Box3().setFromObject(s);
  const size = box.getSize(new THREE.Vector3());
  if (size.z > size.x) { s.rotation.y = Math.PI / 2; s.updateMatrixWorld(true); box = new THREE.Box3().setFromObject(s); }
  const c = box.getCenter(new THREE.Vector3());
  s.position.x -= c.x; s.position.z -= c.z;
  s.position.y -= box.min.y + (3 - 1.5455) * S + 0.06;
  return s;
}

export function makeRenderer(w, h, alpha = true) {
  const r = new THREE.WebGLRenderer({ antialias: true, alpha, preserveDrawingBuffer: true });
  r.setPixelRatio(1);
  r.setSize(w, h);
  r.outputColorSpace = THREE.SRGBColorSpace;
  r.toneMapping = THREE.ACESFilmicToneMapping;
  r.toneMappingExposure = 1.15;
  r.shadowMap.enabled = true;
  r.shadowMap.type = THREE.PCFSoftShadowMap;
  return r;
}

export function lights(scene, { sun = [6, 12, 8], power = 2.6 } = {}) {
  scene.add(new THREE.HemisphereLight(0xdfeeff, 0x3a5a30, 1.4));
  const d = new THREE.DirectionalLight(0xfff4e0, power);
  d.position.set(...sun);
  d.castShadow = true;
  d.shadow.mapSize.set(2048, 2048);
  const cam = d.shadow.camera; cam.left = -15; cam.right = 15; cam.top = 15; cam.bottom = -15; cam.far = 80;
  d.shadow.bias = -0.0005;
  scene.add(d);
  const rim = new THREE.DirectionalLight(0xbfd8ff, 1.2);
  rim.position.set(-6, 5, -8);
  scene.add(rim);
  return d;
}

export { THREE, C };
window.FC = { THREE, C, TEAMS, player, ball, pitch, goal, stadium, makeRenderer, lights, clipNames: Object.keys(ALL), ALL };
window.ready = true;

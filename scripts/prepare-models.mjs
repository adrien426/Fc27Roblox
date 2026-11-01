// Turns the web game's models (assets/source/*.glb) into files Roblox can import (assets/build/*.glb):
// - Draco compression removed (Roblox cannot read it)
// - every mesh kept under Roblox's 20,000 triangles per MeshPart: heavy meshes are simplified, then cut in pieces
// - stadium: its goal frames removed (the game builds its own goals, like the web version)
// - balls: one node per ball, lightened (a 22 cm ball does not need 20,000 triangles)
// Usage: node prepare-models.mjs
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune, dedup, weld } from '@gltf-transform/functions';
import draco3d from 'draco3dgltf';
import { MeshoptSimplifier } from 'meshoptimizer';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', 'assets');
const SRC = join(ROOT, 'source'), OUT = join(ROOT, 'build');
const MAX_TRIS = 19000;

const io = new NodeIO()
  .registerExtensions(ALL_EXTENSIONS)
  .registerDependencies({ 'draco3d.decoder': await draco3d.createDecoderModule() });
await MeshoptSimplifier.ready;

const tris = prim => (prim.getIndices() ? prim.getIndices().getCount() : prim.getAttribute('POSITION').getCount()) / 3;

// Drops the Draco extension so the file is written uncompressed
function decompress(doc) {
  for (const ext of doc.getRoot().listExtensionsUsed()) if (ext.extensionName === 'KHR_draco_mesh_compression') ext.dispose();
}

// Simplifies one primitive to about `ratio` of its triangles (meshoptimizer), allowing more error if needed
async function simplifyPrimitive(prim, ratio, error) {
  const before = tris(prim);
  const idx = prim.getIndices().getArray();
  const pos = prim.getAttribute('POSITION').getArray();
  const target = Math.floor(idx.length * ratio / 3) * 3;
  const [out] = MeshoptSimplifier.simplify(new Uint32Array(idx), pos, 3, target, error, ['LockBorder']);
  let res = out;
  // Not enough with the error bound: allow more error, step by step
  let e = error;
  while (res.length > Math.max(target * 1.15, 3) && e < 0.05) {
    e *= 2;
    res = MeshoptSimplifier.simplify(new Uint32Array(idx), pos, 3, target, e, ['LockBorder'])[0];
  }
  prim.getIndices().setArray(pos.length / 3 > 65535 ? new Uint32Array(res) : new Uint16Array(res));
  console.log(`  simplified ${prim.getMaterial()?.getName() || '?'}: ${before} -> ${tris(prim)} triangles`);
}

// Cuts every primitive above MAX_TRIS into pieces, each in its own mesh and node (one Roblox MeshPart each)
function split(doc) {
  const scene = doc.getRoot().getDefaultScene() || doc.getRoot().listScenes()[0];
  for (const node of doc.getRoot().listNodes()) {
    const mesh = node.getMesh();
    if (!mesh || node.getSkin()) continue;
    for (const prim of mesh.listPrimitives()) {
      const n = tris(prim);
      if (n <= MAX_TRIS) continue;
      const idx = prim.getIndices().getArray();
      const names = prim.listSemantics();
      const pieces = Math.ceil(n / MAX_TRIS);
      for (let k = 0; k < pieces; k++) {
        const a = k * MAX_TRIS * 3, b = Math.min(idx.length, a + MAX_TRIS * 3);
        const remap = new Map(), newIdx = new Uint32Array(b - a);
        for (let i = a; i < b; i++) {
          let v = remap.get(idx[i]);
          if (v === undefined) { v = remap.size; remap.set(idx[i], v); }
          newIdx[i - a] = v;
        }
        const p = doc.createPrimitive().setMaterial(prim.getMaterial()).setMode(prim.getMode());
        for (const sem of names) {
          const src = prim.getAttribute(sem), size = src.getElementSize(), arr = src.getArray();
          const dst = new arr.constructor(remap.size * size);
          for (const [o, nv] of remap) for (let c = 0; c < size; c++) dst[nv * size + c] = arr[o * size + c];
          p.setAttribute(sem, doc.createAccessor().setType(src.getType()).setArray(dst).setNormalized(src.getNormalized()));
        }
        p.setIndices(doc.createAccessor().setType('SCALAR').setArray(remap.size > 65535 ? newIdx : new Uint16Array(newIdx)));
        const m = doc.createMesh(`${mesh.getName()}_${k + 1}`).addPrimitive(p);
        const child = doc.createNode(`${node.getName()}_${k + 1}`).setMesh(m);
        (node.getParentNode() || scene).addChild(child);
        child.setTranslation(node.getTranslation()).setRotation(node.getRotation()).setScale(node.getScale());
      }
      mesh.removePrimitive(prim);
      prim.dispose();
    }
    if (!mesh.listPrimitives().length) { node.setMesh(null); mesh.dispose(); }
  }
}

function report(name, doc) {
  const meshes = doc.getRoot().listMeshes();
  const all = meshes.flatMap(m => m.listPrimitives().map(tris));
  console.log(`${name}: ${meshes.length} meshes, ${all.reduce((a, b) => a + b, 0)} triangles, largest ${Math.max(...all)}`);
}

mkdirSync(OUT, { recursive: true });

// One skin with the whole skeleton for every piece of the player. In player.glb each piece (shoes, hair, shirt...)
// has its own skin with only the bones it uses: Roblox then gives that piece a skeleton cut at that point (the
// shoes' starts at the shin, the hair's at the upper back), so the shoes stay on the ground and the hair stays
// behind when the body moves. The pieces' joint indices are renumbered into the shared skin.
function unifySkins(doc) {
  const root = doc.getRoot();
  const skins = root.listSkins();
  if (skins.length < 2) return;
  const ibm = new Map();
  for (const s of skins) {
    const m = s.getInverseBindMatrices().getArray();
    s.listJoints().forEach((j, i) => { if (!ibm.has(j)) ibm.set(j, m.slice(i * 16, i * 16 + 16)); });
  }
  const hips = skins[0].listJoints().find(j => /Hips$/.test(j.getName())) || skins[0].listJoints()[0];
  const joints = [];
  (function walk(n) { if (ibm.has(n)) joints.push(n); n.listChildren().forEach(walk); })(hips);
  if (joints.length !== ibm.size) throw new Error(`player: ${ibm.size - joints.length} joints outside the skeleton`);
  const index = new Map(joints.map((j, i) => [j, i]));
  const mats = new Float32Array(joints.length * 16);
  joints.forEach((j, i) => mats.set(ibm.get(j), i * 16));
  const skin = doc.createSkin('Skeleton').setSkeleton(hips)
    .setInverseBindMatrices(doc.createAccessor('InverseBindMatrices').setType('MAT4').setArray(mats).setBuffer(root.listBuffers()[0]));
  joints.forEach(j => skin.addJoint(j));
  for (const node of root.listNodes()) {
    const old = node.getSkin();
    if (!old || old === skin) continue;
    const map = old.listJoints().map(j => index.get(j));
    for (const prim of node.getMesh().listPrimitives()) {
      for (const sem of prim.listSemantics().filter(n => n.startsWith('JOINTS_'))) {
        const acc = prim.getAttribute(sem);
        const src = acc.getArray();
        const out = new Uint16Array(src.length);
        for (let i = 0; i < src.length; i++) out[i] = map[src[i]];
        prim.setAttribute(sem, doc.createAccessor(sem).setType('VEC4').setArray(out).setBuffer(acc.getBuffer()));
      }
    }
    node.setSkin(skin);
  }
  for (const s of skins) s.dispose();
}

// Player: decompressed, its pieces share one whole skeleton (bones and skinning otherwise kept as they are)
{
  const doc = await io.read(join(SRC, 'player.glb'));
  decompress(doc);
  unifySkins(doc);
  await doc.transform(prune(), dedup());
  report('player', doc);
  await io.write(join(OUT, 'player.glb'), doc);
}

// Stadium: goal frames removed, seats and stands simplified, then cut in pieces
{
  const doc = await io.read(join(SRC, 'stadium.glb'));
  decompress(doc);
  for (const node of doc.getRoot().listNodes()) if (/Goal_Post/.test(node.getName())) node.dispose();
  await doc.transform(prune(), dedup(), weld());
  for (const mesh of doc.getRoot().listMeshes()) {
    for (const prim of mesh.listPrimitives()) {
      const n = tris(prim);
      // Seats and stand structure carry most of the triangles: keep about 40 % of them
      if (n > 40000) await simplifyPrimitive(prim, 0.4, 0.0005);
    }
  }
  split(doc);
  await doc.transform(prune());
  report('stadium', doc);
  await io.write(join(OUT, 'stadium.glb'), doc);
}

// Balls: each primitive lowered to 4,000 triangles at most; normal map dropped (invisible at this size)
{
  const doc = await io.read(join(SRC, 'balls.glb'));
  decompress(doc);
  for (const mat of doc.getRoot().listMaterials()) mat.setNormalTexture(null);
  await doc.transform(prune(), dedup(), weld());
  for (const mesh of doc.getRoot().listMeshes()) {
    for (const prim of mesh.listPrimitives()) if (tris(prim) > 4000) await simplifyPrimitive(prim, 4000 / tris(prim), 0.001);
  }
  await doc.transform(prune());
  report('balls', doc);
  await io.write(join(OUT, 'balls.glb'), doc);
}

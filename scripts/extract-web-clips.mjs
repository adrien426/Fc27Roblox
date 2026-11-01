// One-time: pulls the Mixamo clips embedded in the web game's index.html into a clips.json-like file
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import draco3d from 'draco3dgltf';
import { readFileSync, writeFileSync } from 'node:fs';
const html = readFileSync(process.argv[2], 'utf8');
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ 'draco3d.decoder': await draco3d.createDecoderModule() });
const out = {};
for (const m of html.matchAll(/<script type="text\/plain" id="mdl-([a-zA-Z0-9]+)">([\s\S]*?)<\/script>/g)) {
  const key = m[1]; if (key === 'xbot' || key === 'splash') continue;
  const doc = await io.readBinary(Buffer.from(m[2].trim(), 'base64'));
  const anim = doc.getRoot().listAnimations()[0];
  const tracks = []; let dur = 0;
  for (const ch of anim.listChannels()) {
    const path = ch.getTargetPath(); if (path === 'scale') continue;
    const s = ch.getSampler(), t = Array.from(s.getInput().getArray()), v = Array.from(s.getOutput().getArray());
    dur = Math.max(dur, t[t.length - 1]);
    tracks.push({ name: ch.getTargetNode().getName() + '.' + (path === 'rotation' ? 'quaternion' : 'position'), times: t.map(x => +x.toFixed(4)), values: v.map(x => +x.toFixed(5)) });
  }
  out[key] = { name: key, duration: dur, tracks };
  console.log(key, dur.toFixed(2), tracks.length);
}
writeFileSync(process.argv[3], JSON.stringify(out));

// Uploads the game's models and sounds to Roblox with an Open Cloud API key, then writes their ids into
// src/shared/AssetIds.luau so the game loads them.
// - models: assets/build/player.glb, stadium.glb, balls.glb (made by prepare-models.mjs)
// - sounds: assets/source/sounds/*.mp3
// A file already uploaded is not sent again unless it changed (then a new version of the same asset is uploaded,
// so its id stays the same). What was sent is remembered in assets/uploaded.json.
//
// Environment:
//   ROBLOX_API_KEY            Open Cloud key with the "assets" read and write permissions
//   ROBLOX_CREATOR_USER_ID    the Roblox user who owns the assets (must own the experience too), or
//   ROBLOX_CREATOR_GROUP_ID   the group, for an experience owned by a group
// Usage: node upload-assets.mjs [--only player,stadium,...] [--dry-run]
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join, basename } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const MANIFEST = join(ROOT, 'assets', 'uploaded.json');
const IDS = join(ROOT, 'src', 'shared', 'AssetIds.luau');
const API = 'https://apis.roblox.com/assets/v1';

const ITEMS = [
  { key: 'player', file: 'assets/build/player.glb', type: 'Model', mime: 'model/gltf-binary', name: 'FC27 Player' },
  { key: 'stadium', file: 'assets/build/stadium.glb', type: 'Model', mime: 'model/gltf-binary', name: 'FC27 Stadium' },
  { key: 'balls', file: 'assets/build/balls.glb', type: 'Model', mime: 'model/gltf-binary', name: 'FC27 Balls' },
  { key: 'sounds.whistle', file: 'assets/source/sounds/whistle.mp3', type: 'Audio', mime: 'audio/mpeg', name: 'FC27 Whistle' },
  { key: 'sounds.bed', file: 'assets/source/sounds/bed.mp3', type: 'Audio', mime: 'audio/mpeg', name: 'FC27 Crowd' },
  { key: 'sounds.chant', file: 'assets/source/sounds/chant.mp3', type: 'Audio', mime: 'audio/mpeg', name: 'FC27 Chant' },
  { key: 'sounds.roar', file: 'assets/source/sounds/roar.mp3', type: 'Audio', mime: 'audio/mpeg', name: 'FC27 Roar' },
];

const args = process.argv.slice(2);
const dry = args.includes('--dry-run');
const onlyArg = args.indexOf('--only');
const only = onlyArg >= 0 ? new Set(args[onlyArg + 1].split(',')) : null;

const key = process.env.ROBLOX_API_KEY;
const userId = process.env.ROBLOX_CREATOR_USER_ID, groupId = process.env.ROBLOX_CREATOR_GROUP_ID;
if (!dry && (!key || !(userId || groupId))) {
  console.error('ROBLOX_API_KEY and ROBLOX_CREATOR_USER_ID (or ROBLOX_CREATOR_GROUP_ID) must be set.');
  process.exit(1);
}
const creator = groupId ? { groupId: String(groupId) } : { userId: String(userId) };

const manifest = existsSync(MANIFEST) ? JSON.parse(readFileSync(MANIFEST, 'utf8')) : {};
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function call(method, url, body) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, { method, headers: { 'x-api-key': key }, body });
    if ((res.status === 429 || res.status >= 500) && attempt < 5) { await sleep(2000 * 2 ** attempt); continue; }
    const text = await res.text();
    if (!res.ok) throw new Error(`${method} ${url} -> ${res.status} ${text}`);
    return text ? JSON.parse(text) : {};
  }
}

// Uploads become operations: wait until Roblox has processed the file and gives the asset id
async function finish(op) {
  let o = op;
  for (let i = 0; !o.done; i++) {
    if (i > 120) throw new Error(`Upload still processing after 4 minutes: ${o.path}`);
    await sleep(2000);
    o = await call('GET', `${API}/${o.path}`);
  }
  if (o.error) throw new Error(`Upload failed: ${JSON.stringify(o.error)}`);
  return o.response;
}

async function upload(item, data, existing) {
  const form = new FormData();
  const request = existing
    ? { assetId: String(existing) }
    : { assetType: item.type, displayName: item.name, description: 'FC27 (Roblox version of the web game)', creationContext: { creator } };
  form.append('request', JSON.stringify(request));
  form.append('fileContent', new Blob([data], { type: item.mime }), basename(item.file));
  const op = existing ? await call('PATCH', `${API}/assets/${existing}`, form) : await call('POST', `${API}/assets`, form);
  const res = await finish(op);
  return Number(res.assetId || existing);
}

function writeIds() {
  const id = k => manifest[k]?.id || 0;
  const src = `-- Roblox ids of the web game's models and sounds, written by scripts/upload-assets.mjs after it uploads
-- assets/build/*.glb and assets/source/sounds/*.mp3 with the Open Cloud key. 0 = not uploaded yet: the game then
-- uses its built-in stand-ins (stadium built from code, standard avatars, plain ball, no recorded sounds).
return {
\tplayer = ${id('player')},
\tstadium = ${id('stadium')},
\tballs = ${id('balls')},
\tsounds = {
\t\twhistle = ${id('sounds.whistle')},
\t\tbed = ${id('sounds.bed')},
\t\tchant = ${id('sounds.chant')},
\t\troar = ${id('sounds.roar')},
\t},
}
`;
  writeFileSync(IDS, src);
}

let failed = 0;
for (const item of ITEMS) {
  if (only && !only.has(item.key) && !only.has(item.key.split('.')[0])) continue;
  const path = join(ROOT, item.file);
  if (!existsSync(path)) { console.error(`${item.key}: ${item.file} is missing (run prepare-models.mjs)`); failed++; continue; }
  const data = readFileSync(path);
  const hash = createHash('sha256').update(data).digest('hex');
  const prev = manifest[item.key];
  if (prev && prev.sha256 === hash) { console.log(`${item.key}: unchanged (asset ${prev.id})`); continue; }
  const mb = (data.length / 1048576).toFixed(1);
  if (dry) { console.log(`${item.key}: would ${prev ? 'update asset ' + prev.id : 'create a new ' + item.type} (${mb} MB)`); continue; }
  try {
    console.log(`${item.key}: ${prev ? 'updating asset ' + prev.id : 'uploading'} (${mb} MB)...`);
    const id = await upload(item, data, prev?.id);
    manifest[item.key] = { id, sha256: hash, file: item.file, type: item.type };
    writeFileSync(MANIFEST, JSON.stringify(manifest, null, 2) + '\n');
    console.log(`${item.key}: asset ${id}`);
  } catch (e) {
    console.error(`${item.key}: ${e.message}`);
    failed++;
  }
}
if (!dry) writeIds();
process.exit(failed ? 1 : 0);

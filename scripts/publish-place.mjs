// Publishes a place file to a Roblox experience with an Open Cloud API key (a test experience, for instance).
// The place file is the Fc27.rbxlx that GitHub builds for each branch (release "preview-<branch>", or "latest"
// for main); a local file can be given instead.
//
// Environment:
//   ROBLOX_API_KEY       Open Cloud key with the "universe-places" write permission on that experience
//   ROBLOX_UNIVERSE_ID   the experience's id (Creator Hub > the experience > ... > Copy Universe ID)
//   ROBLOX_PLACE_ID      its start place's id
// Usage:
//   node publish-place.mjs --release preview-claude-my-branch   download that release's Fc27.rbxlx and publish it
//   node publish-place.mjs --file Fc27.rbxlx                     publish a local file
//   add --saved to save it as a version without making it live
import { readFileSync } from 'node:fs';

const args = process.argv.slice(2);
const opt = n => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const key = process.env.ROBLOX_API_KEY;
const universe = process.env.ROBLOX_UNIVERSE_ID, place = process.env.ROBLOX_PLACE_ID;
const repo = process.env.GITHUB_REPO || 'adrien426/Fc27Roblox';
if (!key || !universe || !place) {
  console.error('ROBLOX_API_KEY, ROBLOX_UNIVERSE_ID and ROBLOX_PLACE_ID must be set.');
  process.exit(1);
}

let data;
if (opt('--file')) {
  data = readFileSync(opt('--file'));
} else if (opt('--release')) {
  const url = `https://github.com/${repo}/releases/download/${opt('--release')}/Fc27.rbxlx`;
  const res = await fetch(url);
  if (!res.ok) { console.error(`Could not download ${url}: ${res.status}`); process.exit(1); }
  data = Buffer.from(await res.arrayBuffer());
} else {
  console.error('Give --release <tag> or --file <path>.');
  process.exit(1);
}

const type = args.includes('--saved') ? 'Saved' : 'Published';
const isXml = data.subarray(0, 64).toString('utf8').includes('<roblox');
const res = await fetch(`https://apis.roblox.com/universes/v1/${universe}/places/${place}/versions?versionType=${type}`, {
  method: 'POST',
  headers: { 'x-api-key': key, 'Content-Type': isXml ? 'application/xml' : 'application/octet-stream' },
  body: data,
});
const text = await res.text();
if (!res.ok) { console.error(`Publish failed: ${res.status} ${text}`); process.exit(1); }
console.log(`${type}: place ${place}, version ${JSON.parse(text).versionNumber} (${(data.length / 1048576).toFixed(1)} MB)`);
console.log(`Play it: https://www.roblox.com/games/${place}`);

// The game's page on Roblox: its description, its icon and its thumbnails (assets/art/icon.png, thumb1..3.png, drawn
// by scripts/art). What was sent is remembered in assets/game-page.json, so that only what changed is sent again.
//
// - description: Open Cloud universe update (permission universe:write, already needed to restart the servers)
// - thumbnails: homepage thumbnails (permission universe.thumbnail:write)
// - the other languages (permission legacy-universe:manage): turned on for the game, with the description, icon and
//   thumbnails (titles translated: assets/art/thumbN.<lang>.png) in each; Roblox only takes them for the languages
//   other than the game's source language (French), whose icon and thumbnails are set once by hand in the Creator Hub.
// Texts: scripts/store-text.mjs.
// Each part that fails is reported and the others still go.
//
// Environment: ROBLOX_API_KEY, ROBLOX_UNIVERSE_ID
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { LANGS as ALL_LANGS, GAME_DESCRIPTION } from './store-text.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const MANIFEST = join(ROOT, 'assets', 'game-page.json');
const key = process.env.ROBLOX_API_KEY, universe = process.env.ROBLOX_UNIVERSE_ID;
if (!key || !universe) { console.error('ROBLOX_API_KEY and ROBLOX_UNIVERSE_ID must be set.'); process.exit(1); }

const DESCRIPTION = GAME_DESCRIPTION.fr;

const ICON = join(ROOT, 'assets', 'art', 'icon.png');
const thumbsOf = lang => ['thumb1', 'thumb2', 'thumb3'].map(n => join(ROOT, 'assets', 'art', lang === 'fr' ? `${n}.png` : `${n}.${lang}.png`)).filter(existsSync);
const THUMBS = thumbsOf('fr');
const LANGS = ALL_LANGS;

const sent = existsSync(MANIFEST) ? JSON.parse(readFileSync(MANIFEST, 'utf8')) : {};
const save = () => writeFileSync(MANIFEST, JSON.stringify(sent, null, 2) + '\n');
const hash = (...parts) => { const h = createHash('sha256'); for (const p of parts) h.update(p); return h.digest('hex'); };
const png = (path) => new Blob([readFileSync(path)], { type: 'image/png' });

async function call(method, url, body, json) {
  const headers = { 'x-api-key': key };
  if (json) headers['content-type'] = 'application/json';
  const res = await fetch(url, { method, headers, body: json ? JSON.stringify(json) : body });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${url.replace(/\?.*/, '')} -> ${res.status} ${text.slice(0, 300)}`);
  try { return text ? JSON.parse(text) : {}; } catch { return { text }; }
}

let failed = 0;
async function step(name, h, fn) {
  if (sent[name] === h) { console.log(`${name}: unchanged`); return; }
  try {
    await fn();
    sent[name] = h; save();
    console.log(`${name}: sent`);
  } catch (e) { console.error(`${name}: ${e.message}`); failed++; }
}

// 1. Description
await step('description', hash(DESCRIPTION), () =>
  call('PATCH', `https://apis.roblox.com/cloud/v2/universes/${universe}?updateMask=description`, null, { description: DESCRIPTION }));

// 2. Homepage thumbnails
const thumbsHash = hash(...THUMBS.map(p => readFileSync(p)));
await step('thumbnails', thumbsHash, async () => {
  const f = new FormData();
  for (const p of THUMBS) f.append('files', png(p), p.split('/').pop());
  const r = await call('POST', `https://apis.roblox.com/thumbnail-personalization-api/v1/universes/${universe}/thumbnails/uploads`, f);
  console.log('thumbnails:', JSON.stringify(r).slice(0, 300));
});

// 3. The other languages: turned on for the game, then its description, icon and thumbnails in each of them (Roblox
//    takes them for every language but the source one, French)
const source = 'fr';
let displayName = 'FC27';
try {
  const r = await call('GET', `https://apis.roblox.com/cloud/v2/universes/${universe}`);
  displayName = r.displayName || displayName;
} catch (e) { console.error(`universe: ${e.message}`); }
const others = LANGS.filter(l => l !== source);
await step('languages', hash(others.join(',')), () =>
  call('PATCH', `https://apis.roblox.com/legacy-game-internationalization/v1/supported-languages/games/${universe}`, null,
    others.map(l => ({ languageCodeType: 'Language', languageCode: l, delete: false }))));
await step('descriptions', hash(displayName, ...others.map(l => GAME_DESCRIPTION[l])), async () => {
  const r = await call('PATCH', `https://apis.roblox.com/legacy-game-internationalization/v1/name-description/games/${universe}`, null,
    { data: others.map(l => ({ name: displayName, description: GAME_DESCRIPTION[l], languageCode: l })) });
  if (r.failedOperations && r.failedOperations.length) throw new Error(JSON.stringify(r.failedOperations).slice(0, 300));
});
const iconHash = existsSync(ICON) ? hash(readFileSync(ICON)) : null;
for (const lang of others) {
  if (iconHash) {
    await step(`icon.${lang}`, iconHash, () => {
      const f = new FormData(); f.append('request.files', png(ICON), 'icon.png'); f.append('files', png(ICON), 'icon.png');
      return call('POST', `https://apis.roblox.com/legacy-game-internationalization/v1/game-icon/games/${universe}/language-codes/${lang}`, f);
    });
  }
  const files = thumbsOf(lang);
  await step(`thumbnails.${lang}`, hash(...files.map(p => readFileSync(p))), async () => {
    for (const p of files) {
      const f = new FormData(); f.append('Files', png(p), p.split('/').pop());
      await call('POST', `https://apis.roblox.com/legacy-game-internationalization/v1/game-thumbnails/games/${universe}/language-codes/${lang}/image`, f);
    }
  });
}
save();
process.exit(failed ? 1 : 0);

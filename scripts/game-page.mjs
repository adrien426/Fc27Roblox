// The game's page on Roblox: its description, its icon and its thumbnails (assets/art/icon.png, thumb1..3.png, drawn
// by scripts/art). What was sent is remembered in assets/game-page.json, so that only what changed is sent again.
//
// - description: Open Cloud universe update (permission universe:write, already needed to restart the servers)
// - thumbnails: homepage thumbnails (permission universe.thumbnail:write)
// - icon and thumbnails per language (permission legacy-universe:manage): Roblox only takes them for the languages
//   other than the game's source language; for the source language they are set once by hand in the Creator Hub.
// Each part that fails is reported and the others still go.
//
// Environment: ROBLOX_API_KEY, ROBLOX_UNIVERSE_ID
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const MANIFEST = join(ROOT, 'assets', 'game-page.json');
const key = process.env.ROBLOX_API_KEY, universe = process.env.ROBLOX_UNIVERSE_ID;
if (!key || !universe) { console.error('ROBLOX_API_KEY and ROBLOX_UNIVERSE_ID must be set.'); process.exit(1); }

const DESCRIPTION = `⚽ FC27 : le foot à 11 contre 11 !

Joue avec tes amis dans un vrai stade. Choisis ton équipe (Rouges ou Bleus) et ton poste dans le vestiaire : attaquant, milieu, défenseur ou gardien. Les places libres sont prises par des robots, donc tu peux jouer même tout seul.

🎮 Comment jouer
• Cours avec le joystick
• Passe, Lob et Tir pour jouer le ballon
• Tacle pour récupérer le ballon
• Dribble pour faire des gestes techniques
• Gardien : Plonger pour arrêter les tirs

🏆 Dans le jeu
• Hors-jeu, fautes, cartons, penaltys, corners et touches
• Ralenti après chaque but
• Statistiques à la fin du match et classement des meilleurs buteurs
• Un commentateur qui parle ta langue

🪙 Gagne des pièces en jouant (buts, passes, tacles, victoires) et débloque des célébrations, des crampons de couleur, des maillots spéciaux et des effets de tir. Tout est pour le style : rien ne rend ton joueur plus fort.`;

const ICON = join(ROOT, 'assets', 'art', 'icon.png');
const THUMBS = ['thumb1', 'thumb2', 'thumb3'].map(n => join(ROOT, 'assets', 'art', `${n}.png`)).filter(existsSync);
const LANGS = ['fr', 'en', 'es', 'de', 'it', 'pt'];

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

// 3. Icon and thumbnails in each language Roblox accepts (all but the source language)
let source = null;
try {
  const r = await call('GET', `https://apis.roblox.com/legacy-game-internationalization/v1/source-language/games/${universe}`);
  source = r.languageCode || r.name || null;
  console.log(`source language: ${source}`);
} catch (e) { console.error(`source language: ${e.message}`); }
const iconHash = existsSync(ICON) ? hash(readFileSync(ICON)) : null;
for (const lang of LANGS) {
  if (lang === source) continue;
  if (iconHash) {
    await step(`icon.${lang}`, iconHash, () => {
      const f = new FormData(); f.append('request.files', png(ICON), 'icon.png'); f.append('files', png(ICON), 'icon.png');
      return call('POST', `https://apis.roblox.com/legacy-game-internationalization/v1/game-icon/games/${universe}/language-codes/${lang}`, f);
    });
  }
  await step(`thumbnails.${lang}`, thumbsHash, async () => {
    for (const p of THUMBS) {
      const f = new FormData(); f.append('Files', png(p), p.split('/').pop());
      await call('POST', `https://apis.roblox.com/legacy-game-internationalization/v1/game-thumbnails/games/${universe}/language-codes/${lang}/image`, f);
    }
  });
}
save();
process.exit(failed ? 1 : 0);

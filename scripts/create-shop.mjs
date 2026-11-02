// Creates the shop's game passes and coin packs (developer products) on Roblox with Open Cloud, if they do not exist
// yet, and writes their ids into src/shared/ShopIds.luau (read by server/Economy for real purchases).
// Names, descriptions and prices come from src/shared/Shop.luau's values below (keep them in step).
//
// Environment: ROBLOX_API_KEY (permissions game-pass read/write and developer-product read/write on the experience),
//              ROBLOX_UNIVERSE_ID
// Names, descriptions and pictures (assets/art) are sent again when they change (assets/shop-art.json).
// Usage: node create-shop.mjs
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { LANGS, passText, packText } from './store-text.mjs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const IDS = join(ROOT, 'src', 'shared', 'ShopIds.luau');
const key = process.env.ROBLOX_API_KEY, key_ = key, universe = process.env.ROBLOX_UNIVERSE_ID;
if (!key || !universe) { console.error('ROBLOX_API_KEY and ROBLOX_UNIVERSE_ID must be set.'); process.exit(1); }

// Names and descriptions in every language (scripts/store-text.mjs): French is the item's own text, the others are
// sent as its translations
const PASSES = [
  { id: 'celebrations', price: 99 }, { id: 'style', price: 149 }, { id: 'vip', price: 299 }, { id: 'trail', price: 149 },
].map(p => ({ ...p, ...passText(p.id, 'fr'), text: lang => passText(p.id, lang) }));
const PACKS = [
  { id: 'coins500', coins: 500, price: 49 }, { id: 'coins1500', coins: 1500, price: 129 }, { id: 'coins5000', coins: 5000, price: 399 },
].map(p => ({ ...p, ...packText(p.coins, 'fr'), text: lang => packText(p.coins, lang) }));
// Each item's picture: assets/art/<id>.png (drawn by scripts/art). What was last sent (name, description, picture)
// is remembered in assets/shop-art.json, so that an item is only updated when one of them changed.
const ART = join(ROOT, 'assets', 'shop-art.json');
const sent = existsSync(ART) ? JSON.parse(readFileSync(ART, 'utf8')) : {};
const picture = id => join(ROOT, 'assets', 'art', `${id}.png`);
const stamp = p => createHash('sha256').update(p.name + '\n' + p.description + '\n')
  .update(existsSync(picture(p.id)) ? readFileSync(picture(p.id)) : Buffer.alloc(0)).digest('hex');

async function call(method, url, form) {
  const res = await fetch(url, { method, headers: { 'x-api-key': key }, body: form });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${url} -> ${res.status} ${text}`);
  return text ? JSON.parse(text) : {};
}
function form(fields, id) {
  const f = new FormData();
  for (const [k, v] of Object.entries(fields)) f.append(k, String(v));
  if (id && existsSync(picture(id))) f.append('imageFile', new Blob([readFileSync(picture(id))], { type: 'image/png' }), `${id}.png`);
  return f;
}
// Name, description and picture of an item that already exists, when they changed
async function refresh(kind, url, p) {
  const key = `${kind}.${p.id}`, h = stamp(p);
  if (sent[key] === h) return;
  await call('PATCH', url, form({ name: p.name, description: p.description }, p.id));
  sent[key] = h;
  writeFileSync(ART, JSON.stringify(sent, null, 2) + '\n');
  console.log(`${key}: name, description and picture updated`);
}
// Its name and description in the other languages (the game must support them: game-page.mjs turns them on)
async function translate(kind, id, p) {
  for (const lang of LANGS.slice(1)) {
    const t = p.text(lang), key = `${kind}.${p.id}.${lang}`;
    const h = createHash('sha256').update(t.name + '\n' + t.description).digest('hex');
    if (sent[key] === h) continue;
    const path = kind === 'pass' ? `game-passes/${id}` : `developer-products/${id}`;
    // Roblox sometimes answers 500 for a moment: try again a few times
    let res;
    for (let attempt = 0; attempt < 4; attempt++) {
      res = await fetch(`https://apis.roblox.com/legacy-game-internationalization/v1/${path}/name-description/language-codes/${lang}`, {
        method: 'PATCH', headers: { 'x-api-key': key_, 'content-type': 'application/json' }, body: JSON.stringify(t),
      });
      if (res.status < 500 && res.status !== 429) break;
      await new Promise(r => setTimeout(r, 2000 * 2 ** attempt));
    }
    if (!res.ok) { console.error(`${key}: ${res.status} ${(await res.text()).slice(0, 200)}`); failed++; continue; }
    sent[key] = h;
    writeFileSync(ART, JSON.stringify(sent, null, 2) + '\n');
    console.log(`${key}: translated`);
  }
}

const ids = { passes: {}, products: {} };
// Ids already written (keep them)
const cur = readFileSync(IDS, 'utf8');
for (const m of cur.matchAll(/(\w+) = (\d+)/g)) {
  if (PASSES.some(p => p.id === m[1])) ids.passes[m[1]] = Number(m[2]);
  if (PACKS.some(p => p.id === m[1])) ids.products[m[1]] = Number(m[2]);
}

let failed = 0;
// Game passes: find by name, create the missing ones
try {
  const existing = (await call('GET', `https://apis.roblox.com/game-passes/v1/universes/${universe}/game-passes/creator?pageSize=100`)).gamePasses || [];
  for (const p of PASSES) {
    if (ids.passes[p.id] > 0) continue;
    const found = existing.find(g => g.name === p.name);
    if (found) { ids.passes[p.id] = found.gamePassId; console.log(`pass ${p.id}: exists (${found.gamePassId})`); continue; }
    const made = await call('POST', `https://apis.roblox.com/game-passes/v1/universes/${universe}/game-passes`,
      form({ name: p.name, description: p.description, price: p.price, isForSale: true }, p.id));
    ids.passes[p.id] = made.gamePassId;
    sent[`pass.${p.id}`] = stamp(p);
    console.log(`pass ${p.id}: created (${made.gamePassId}) at ${p.price} R$`);
  }
  for (const p of PASSES) {
    if (!(ids.passes[p.id] > 0)) continue;
    try { await refresh('pass', `https://apis.roblox.com/game-passes/v1/universes/${universe}/game-passes/${ids.passes[p.id]}`, p); }
    catch (e) { console.error(`pass ${p.id}: ${e.message}`); failed++; }
    await translate('pass', ids.passes[p.id], p);
  }
} catch (e) { console.error(`Game passes: ${e.message}`); failed++; }

// Developer products (coin packs)
try {
  const base = `https://apis.roblox.com/developer-products/v2/universes/${universe}/developer-products`;
  const existing = (await call('GET', `${base}/creator?pageSize=100`)).developerProducts || [];
  for (const p of PACKS) {
    if (ids.products[p.id] > 0) continue;
    const found = existing.find(g => g.name === p.name);
    if (found) { ids.products[p.id] = found.productId; console.log(`product ${p.id}: exists (${found.productId})`); continue; }
    const made = await call('POST', base, form({ name: p.name, description: p.description, price: p.price, isForSale: true }, p.id));
    ids.products[p.id] = made.productId;
    sent[`product.${p.id}`] = stamp(p);
    console.log(`product ${p.id}: created (${made.productId}) at ${p.price} R$`);
  }
  for (const p of PACKS) {
    if (!(ids.products[p.id] > 0)) continue;
    try { await refresh('product', `${base}/${ids.products[p.id]}`, p); }
    catch (e) { console.error(`product ${p.id}: ${e.message}`); failed++; }
    await translate('product', ids.products[p.id], p);
  }
} catch (e) { console.error(`Developer products: ${e.message}`); failed++; }

writeFileSync(ART, JSON.stringify(sent, null, 2) + '\n');
const n = (o, k) => o[k] || 0;
writeFileSync(IDS, `-- Roblox ids of the shop's game passes and Robux coin packs (developer products), written by
-- scripts/create-shop.mjs at each deploy. 0 = not created yet: buying it with Robux is not offered (coins still work;
-- the game's creators get everything free anyway).
return {
\tpasses = { celebrations = ${n(ids.passes, 'celebrations')}, style = ${n(ids.passes, 'style')}, vip = ${n(ids.passes, 'vip')}, trail = ${n(ids.passes, 'trail')} },
\tproducts = { coins500 = ${n(ids.products, 'coins500')}, coins1500 = ${n(ids.products, 'coins1500')}, coins5000 = ${n(ids.products, 'coins5000')} },
}
`);
process.exit(failed ? 1 : 0);

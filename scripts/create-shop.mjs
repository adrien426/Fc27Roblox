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
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const IDS = join(ROOT, 'src', 'shared', 'ShopIds.luau');
const key = process.env.ROBLOX_API_KEY, universe = process.env.ROBLOX_UNIVERSE_ID;
if (!key || !universe) { console.error('ROBLOX_API_KEY and ROBLOX_UNIVERSE_ID must be set.'); process.exit(1); }

const COSMETIC = 'Pour le style seulement : ça ne rend pas ton joueur plus fort.';
const PASSES = [
  { id: 'celebrations', name: 'FC27 Célébrations', price: 99,
    description: `Après chaque but, ton joueur fait sa fête : Siuu, danse, victoire ou bravo. Tout le stade la voit ! Tu choisis ta célébration dans la boutique du vestiaire. ${COSMETIC}` },
  { id: 'style', name: 'FC27 Crampons et maillots', price: 149,
    description: `Des crampons de couleur (dorés, noirs, blancs, roses ou cyan) et un maillot édition or ou noire. Ta couleur d’équipe reste, pour qu’on te reconnaisse. ${COSMETIC}` },
  { id: 'vip', name: 'FC27 Pass VIP', price: 299,
    description: `Ton nom s’écrit en doré avec une étoile ★ au-dessus de ton joueur, et tu entres dans le coin VIP du vestiaire. ${COSMETIC}` },
  { id: 'trail', name: 'FC27 Effet de tir', price: 149,
    description: `Quand tu tires, le ballon laisse une traînée derrière lui : feu, étoiles ou glace. Tu choisis ton effet dans la boutique du vestiaire. ${COSMETIC}` },
];
const PACKS = [
  { id: 'coins500', name: 'FC27 500 pièces', price: 49,
    description: '500 pièces FC27 pour acheter des articles de la boutique du vestiaire. Tu gagnes aussi des pièces en jouant : buts, passes, tacles et victoires.' },
  { id: 'coins1500', name: 'FC27 1500 pièces', price: 129,
    description: '1500 pièces FC27 pour acheter des articles de la boutique du vestiaire. Tu gagnes aussi des pièces en jouant : buts, passes, tacles et victoires.' },
  { id: 'coins5000', name: 'FC27 5000 pièces', price: 399,
    description: '5000 pièces FC27 pour acheter des articles de la boutique du vestiaire. Tu gagnes aussi des pièces en jouant : buts, passes, tacles et victoires.' },
];
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

// Creates the shop's game passes and coin packs (developer products) on Roblox with Open Cloud, if they do not exist
// yet, and writes their ids into src/shared/ShopIds.luau (read by server/Economy for real purchases).
// Names, descriptions and prices come from src/shared/Shop.luau's values below (keep them in step).
//
// Environment: ROBLOX_API_KEY (permissions game-pass read/write and developer-product read/write on the experience),
//              ROBLOX_UNIVERSE_ID
// Usage: node create-shop.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const IDS = join(ROOT, 'src', 'shared', 'ShopIds.luau');
const key = process.env.ROBLOX_API_KEY, universe = process.env.ROBLOX_UNIVERSE_ID;
if (!key || !universe) { console.error('ROBLOX_API_KEY and ROBLOX_UNIVERSE_ID must be set.'); process.exit(1); }

const PASSES = [
  { id: 'celebrations', name: 'FC27 Célébrations', description: 'Ta célébration après chaque but : Siuu, danse, victoire…', price: 99 },
  { id: 'style', name: 'FC27 Crampons et maillots', description: 'Crampons de couleur et maillots en édition spéciale.', price: 149 },
  { id: 'vip', name: 'FC27 Pass VIP', description: 'Nom en doré et accès au coin VIP du vestiaire.', price: 299 },
  { id: 'trail', name: 'FC27 Effet de tir', description: 'Une traînée de feu, d’étoiles ou de glace derrière le ballon sur tes frappes.', price: 149 },
];
const PACKS = [
  { id: 'coins500', name: 'FC27 500 pièces', description: '500 pièces FC27', price: 49 },
  { id: 'coins1500', name: 'FC27 1500 pièces', description: '1500 pièces FC27', price: 129 },
  { id: 'coins5000', name: 'FC27 5000 pièces', description: '5000 pièces FC27', price: 399 },
];

async function call(method, url, form) {
  const res = await fetch(url, { method, headers: { 'x-api-key': key }, body: form });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${url} -> ${res.status} ${text}`);
  return text ? JSON.parse(text) : {};
}
function form(fields) {
  const f = new FormData();
  for (const [k, v] of Object.entries(fields)) f.append(k, String(v));
  return f;
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
      form({ name: p.name, description: p.description, price: p.price, isForSale: true }));
    ids.passes[p.id] = made.gamePassId;
    console.log(`pass ${p.id}: created (${made.gamePassId}) at ${p.price} R$`);
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
    const made = await call('POST', base, form({ name: p.name, description: p.description, price: p.price, isForSale: true }));
    ids.products[p.id] = made.productId;
    console.log(`product ${p.id}: created (${made.productId}) at ${p.price} R$`);
  }
} catch (e) { console.error(`Developer products: ${e.message}`); failed++; }

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

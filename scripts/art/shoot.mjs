// Draws the shop's pictures, the game's icon and its thumbnails (assets/art/*.png) from the game's own 3D models
// (assets/build/*.glb, assets/source/anims/*.json), rendered with three.js in a headless Chromium (scenes.js).
// Usage: cd scripts/art && npm install && npm run build -- prepare-models first (assets/build) -- then
//        node shoot.mjs [outDir] [scene1,scene2]
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
const ROOT = new URL('.', import.meta.url).pathname;
const REPO = join(ROOT, '..', '..');
// /m/<file>: the game's models, animations and ball textures
const M = { 'player.glb': 'assets/build/player.glb', 'balls.glb': 'assets/build/balls.glb', 'stadium.glb': 'assets/build/stadium.glb',
  'base.json': 'assets/source/anims/base.json', 'clips.json': 'assets/source/anims/clips.json', 'siuu.json': 'assets/source/anims/siuu.json' };
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.glb': 'model/gltf-binary', '.png': 'image/png' };
const srv = http.createServer(async (q, s) => {
  try { const u = decodeURIComponent(q.url.split('?')[0]); const p = u.startsWith('/m/') ? join(REPO, M[u.slice(3)]) : join(ROOT, u); s.writeHead(200, { 'content-type': TYPES[extname(p)] || 'application/octet-stream' }); s.end(await readFile(p)); }
  catch { s.writeHead(404); s.end(); }
}).listen(8765);
const out = process.argv[2] || join(REPO, 'assets', 'art');
const only = process.argv[3] ? process.argv[3].split(',') : null;
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage();
page.on('console', m => console.log('[page]', m.text()));
page.on('pageerror', e => console.log('[err]', e.message));
await page.goto('http://localhost:8765/page.html');
await page.waitForFunction(() => window.ready && window.SCENES, null, { timeout: 120000 });
const list = await page.evaluate(() => Object.keys(window.SCENES));
for (const name of list) {
  if (only && !only.includes(name)) continue;
  const [w, h] = await page.evaluate(async n => await window.SCENES[n].run(), name);
  await page.setViewportSize({ width: w, height: h });
  await page.waitForTimeout(400);
  await page.locator('#stage').screenshot({ path: `${out}/${name}.png`, omitBackground: true });
  console.log('shot', name, w, h);
}
await browser.close(); srv.close();

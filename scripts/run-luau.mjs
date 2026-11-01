// Runs a Luau script on a Roblox server of the experience (Open Cloud Luau Execution) and prints what it prints
// and returns: a way to look inside the live game (imported models, bones...) without opening Studio.
// The place's own scripts run too, so the script can require the game's modules.
//
// Environment: ROBLOX_API_KEY (permission luau-execution-sessions write), ROBLOX_UNIVERSE_ID, ROBLOX_PLACE_ID
// Usage: node run-luau.mjs <script.luau>
import { readFileSync } from 'node:fs';

const key = process.env.ROBLOX_API_KEY, universe = process.env.ROBLOX_UNIVERSE_ID, place = process.env.ROBLOX_PLACE_ID;
if (!key || !universe || !place) { console.error('ROBLOX_API_KEY, ROBLOX_UNIVERSE_ID and ROBLOX_PLACE_ID must be set.'); process.exit(1); }
const script = readFileSync(process.argv[2], 'utf8');
const API = 'https://apis.roblox.com/cloud/v2';
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function call(method, url, body) {
  const res = await fetch(url, { method, headers: { 'x-api-key': key, 'Content-Type': 'application/json' }, body: body && JSON.stringify(body) });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${url} -> ${res.status} ${text}`);
  return text ? JSON.parse(text) : {};
}

let task = await call('POST', `${API}/universes/${universe}/places/${place}/luau-execution-session-tasks`, { script, timeout: '120s' });
for (let i = 0; !['COMPLETE', 'FAILED', 'CANCELLED'].includes(task.state); i++) {
  if (i > 90) throw new Error('Still running after 3 minutes');
  await sleep(2000);
  task = await call('GET', `${API}/${task.path}`);
}
try {
  const logs = await call('GET', `${API}/${task.path}/logs?view=STRUCTURED`);
  for (const l of logs.luauExecutionSessionTaskLogs || []) {
    for (const m of l.structuredMessages || []) console.log(`[${m.messageType}] ${m.message}`);
    for (const m of l.messages || []) console.log(m);
  }
} catch (e) { console.log(`(no logs: ${e.message})`); }
console.log(`State: ${task.state}`);
if (task.output) console.log('Returned:', JSON.stringify(task.output.results, null, 1));
if (task.error) { console.log('Error:', JSON.stringify(task.error)); process.exit(1); }

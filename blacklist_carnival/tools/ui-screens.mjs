// Renders the built NUI (web/dist) in headless Chromium with a fake game
// bridge and saves a screenshot of every screen. For reviewing the look
// without a FiveM server:
//   node tools/ui-screens.mjs <outDir> [scene ...]
// Needs Playwright (and Chromium). Run `npm run build` in web/ first.
import { execSync } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { extname, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// Playwright from the project, or from the global npm install.
let pw;
try { pw = await import('playwright'); } catch {
  pw = await import(join(execSync('npm root -g').toString().trim(), 'playwright', 'index.mjs'));
}
const { chromium } = pw;

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'web');
const dist = join(root, 'dist');
const fixture = JSON.parse(await readFile(join(root, 'src/__tests__/fixture.json'), 'utf8'));
const outDir = process.argv[2] || 'ui-screens';
const only = process.argv.slice(3);
await mkdir(outDir, { recursive: true });

const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.ogg': 'audio/ogg', '.json': 'application/json', '.svg': 'image/svg+xml' };
const server = createServer(async (req, res) => {
  const path = decodeURIComponent(req.url.split('?')[0]);
  try {
    // ox_inventory item images (nui://ox_inventory/web/images/...) are served from images/inventory
    const file = path.startsWith('/inv/') ? join(root, '..', 'images', 'inventory', path.slice(5)) : join(dist, path === '/' ? 'index.html' : path);
    const body = await readFile(file);
    res.writeHead(200, { 'Content-Type': types[extname(file)] || 'application/octet-stream' });
    res.end(body);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise((r) => server.listen(0, r));
const base = `http://127.0.0.1:${server.address().port}/`;

const now = () => Math.floor(Date.now() / 1000);
const settings = { ...fixture.defaults, groups: { colours: fixture.defaults.groups.colours } };
const names = ['Ada Lovelace', 'Marlo Vance', 'Juno Reyes', 'Silas Crow', 'Ivy Thorn', 'Otto Graves', 'Mina Holt', 'Rex Calloway', 'Nell Ashby', 'Cass Morrow'];
const colours = ['red', 'blue', 'green', 'yellow', 'purple', 'orange'];
const board = { entries: names.map((n, i) => ({ rank: i + 1, participantId: i + 1, name: n, colour: colours[i % 6], total: 180 - i * 14, completed: 6 - Math.floor(i / 2) })), updatedAt: now() };
const participant = { registered: true, id: 1, name: 'Ada Lovelace', colour: 'red', status: 'active', total: 128, rank: 2, walkup: true,
  ticket: { serial: 'CTD-7K2QF-M9XRA', status: 'active' }, sequence: ['shooting', 'wheel', 'fortune', 'puppets', 'deception', 'horror'],
  completed: ['shooting', 'wheel'], current: { attraction: 'fortune', status: 'active' }, next: 'puppets',
  breakdown: { shooting: 64, wheel: 25, fortune: 0, puppets: 0, deception: 0, horror: 0 } };
const event = { active: true, id: 3, name: 'Carnival of the Damned', state: 'running', stateLabel: 'Running', mode: 'walkup', round: 0, totalRounds: 6, participantCount: 37, maxParticipants: 120, registrationOpen: true };

// the configured rounds as the server would send them (deterministic layout)
const sh = settings.attractions.shooting;
const sgRounds = []; const plan = [];
{
  let offset = 0, id = 0;
  sh.rounds.forEach((rc, i) => {
    const duration = rc.durationSeconds * 1000;
    for (let k = 0; k < rc.targetCount; k++) {
      id++;
      const kind = k % 9 === 4 ? 'special' : k % 5 === 3 && rc.decoyChance > 10 ? 'decoy' : 'normal';
      plan.push({ id, round: i + 1, t: offset + Math.floor(k * (duration - rc.targetLifetimeMs) / rc.targetCount), life: rc.targetLifetimeMs, kind, lane: 1 + (k % rc.lanes), dir: k % 2 ? 1 : -1 });
    }
    sgRounds.push({ number: i + 1, label: rc.label, startMs: offset, endMs: offset + duration, lanes: rc.lanes, size: rc.targetSize, motion: rc.motion, pointsPercent: rc.pointsPercent, life: rc.targetLifetimeMs, decoyChance: rc.decoyChance, targets: rc.targetCount });
    offset += duration + (i < sh.rounds.length - 1 ? sh.roundBreakSeconds * 1000 : 0);
  });
}
const sgDuration = sgRounds[sgRounds.length - 1].endMs;
const mystery = settings.attractions.deception.mysteries[0];
const deceptionState = { active: true, roundId: 4, status: 'questioning', endsAt: now() + 412, serverTime: now(), submissionsUsed: 0, maxSubmissions: 2,
  mystery: { id: mystery.id, title: mystery.title, description: mystery.description, rules: mystery.rules, liarCount: mystery.liarCount,
    performers: mystery.performers.map((p) => ({ id: p.id, name: p.name, profile: p.profile, statements: p.statements })) },
  clues: [{ id: 'c1', text: 'Sawdust was found on the Ringmaster\'s boots.' }] };
const fortuneVisit = { visitId: 1, greeting: settings.attractions.fortune.greeting, fortune: 'A stranger in a red coat will cost you dearly.',
  question: { id: 'q1', kind: 'choice', prompt: 'What walks on four legs at dawn, two at noon and three at dusk?', choices: ['A man', 'A ghost', 'A clockwork horse', 'The moon'], index: 1, total: 3, timeout: 30 } };
const attractionsOverview = ['shooting', 'wheel', 'fortune', 'puppets', 'deception', 'horror'].map((id, i) => ({
  id, label: settings.attractions[id].label, readiness: { available: i !== 4, status: i === 4 ? 'unavailable' : 'ready', reason: i === 4 ? 'Repairing the stage lights' : null },
  summary: [{ playing: 2 }, { spins: 41 }, { activeVisits: 1 }, { performance: 'running', title: 'The Lion Tamer\'s Last Bow' }, null, { status: 'running', inside: 3, remaining: 140 }][i],
}));
const walkupSessions = [
  { sessionId: 31, attraction: 'shooting', busy: true, startedAt: now() - 60, players: [{ id: 1, name: 'Ada Lovelace', colour: 'red', online: true }, { id: 7, name: 'Mina Holt', colour: 'red', online: true }] },
  { sessionId: 32, attraction: 'horror', busy: true, startedAt: now() - 90, players: [{ id: 6, name: 'Otto Graves', colour: 'orange', online: true }, { id: 3, name: 'Juno Reyes', colour: 'green', online: true }, { id: 9, name: 'Nell Ashby', colour: 'green', online: false }] },
];
const dashboard = {
  serverTime: now(), event: { ...event }, participants: { total: 37, online: 22, unassigned: 0 }, outstandingRewards: 1,
  rotation: { walkup: true, round: 0, totalRounds: 6, walkupSessions },
  attractions: attractionsOverview,
  leaderboard: board.entries.slice(0, 10).map((e) => ({ id: e.participantId, rank: e.rank, name: e.name, colour: e.colour, total: e.total })),
  health: { ready: true, uptime: 7400, schemaVersion: 4, resourceVersion: '1.0.0', inventoryRunning: true, targetRunning: true, qbxRunning: true, discordEnabled: false,
    database: { healthy: true }, counters: { warning: 3, error: 0 }, config: { source: 'global', global: { version: 7 } } },
  recentTransactions: names.slice(0, 8).map((n, i) => ({ id: 100 - i, display_name: n, attraction_id: ['shooting', 'wheel', 'fortune', 'horror', 'puppets', 'deception'][i % 6], delta: [25, 15, -10, 40, 30, 12, 5, 20][i], created_at: now() - i * 95 })),
  recentStaffActions: [], recentProblems: [],
};
const responses = {
  'leaderboard.public': { ok: true, data: board },
  'wheel.spin': { ok: true, data: { index: 3, outcome: { id: 'treat', label: 'Sweet Treat', type: 'points' }, points: 15, spinsUsed: 1, maxSpins: 2, animationMs: 4000 } },
  'fortune.begin': { ok: true, data: fortuneVisit },
  'deception.public': { ok: true, data: deceptionState },
  'admin.dashboard': { ok: true, data: dashboard },
  'rotation.state': { ok: true, data: { walkup: true, round: 0, totalRounds: 6, walkupSessions } },
  'system.health': { ok: true, data: dashboard.health },
  'items.validate': { ok: true, data: { ok: true, inventoryRunning: true, missing: [], checked: [{ item: 'carnival_ticket_red', registered: true }, { item: 'carnival_prize_box', registered: true }] } },
  'config.get': { ok: true, data: { data: fixture.defaults, schema: fixture.schema, versions: { source: 'global', global: { version: 7 } }, scope: 'global', hasEventOverride: false, activeEventId: 3, canEdit: true, canSeeSecrets: true, liveLocked: false, sounds: fixture.sounds } },
  'props.list': { ok: true, data: { max: 1000, models: ['carnival_gate', 'carnival_lamp'], props: [
    { id: 1, model: 'carnival_gate', label: 'Main gate', x: -1630.52, y: -1050.25, z: 13.1, rx: 0, ry: 0, rz: 230, collision: true, createdBy: 'Owner', createdAt: now() - 3600 },
    { id: 2, model: 'carnival_lamp', label: 'Lamp by the booth', x: -1636.1, y: -1055.8, z: 13.15, rx: 0, ry: 0, rz: 45, collision: true, createdBy: 'Owner', createdAt: now() - 1800 },
    { id: 3, model: 'carnivalcoingold', label: null, x: -1604.0, y: -1115.5, z: 14.1, rx: 0, ry: 0, rz: 0, collision: false, createdBy: 'Admin', createdAt: now() - 120 },
  ] } },
  'prizebox.simulate': { ok: true, data: { boxes: 2000, avgItems: 2.13, rows: fixture.defaults.prizeBox.contents.map((c) => ({ item: c.item, label: c.item.replace('carnival_', '').replace(/_/g, ' '), inBoxes: Math.round(c.chance * 1.9 * 10) / 10, avgCount: Math.round(c.chance * 2.2) / 100 })) } },
  'shop.wallet': { ok: true, data: { balance: 85, earned: 140, spent: 55, currency: 'Prize Tickets' } },
  'shop.overview': { ok: true, data: { currency: 'Prize Tickets', totals: { wallets: 31, outstanding: 2140, earned: 5260, spent: 3120, purchasesToday: 18, spentToday: 410 },
    popular: [['carnival_finger_dog', 22, 550], ['carnival_blood_slushie', 19, 285], ['carnival_bloodfloss', 15, 225], ['carnival_prize_box', 3, 750]].map(([item, sold, points]) => ({ item, sold, points })),
    recent: names.slice(0, 7).map((n, i) => ({ id: 90 - i, citizenid: 'CID' + i, display_name: n, kind: i === 3 ? 'adjust' : 'purchase', delta: i === 3 ? 50 : -[25, 15, 30, 0, 250, 10, 15][i], balance_after: 40 + i * 7,
      item: i === 3 ? null : ['carnival_finger_dog', 'carnival_witch_brew', 'carnival_web_cake', null, 'carnival_prize_box', 'carnival_eyeball_pop', 'carnival_grave_popcorn'][i], item_count: 1, staff_name: i === 3 ? 'Owner' : null, reason: i === 3 ? 'Points lost in a crash' : null, created_at: now() - i * 400 })),
    wallets: board.entries.map((e, i) => ({ citizenid: 'CID' + i, display_name: e.name, balance: 320 - i * 27, earned_total: 520 - i * 30, spent_total: 200 - i * 3, updated_at: now() - i * 600 })) } },
  'participants.search': { ok: true, data: { page: 1, pageSize: 25, total: 10, rows: board.entries.map((e) => ({ id: e.participantId, display_name: e.name, colour: e.colour, status: 'active', total_score: e.total, online: e.rank % 3 !== 0, last_seen_at: now() - e.rank * 60 })) } },
};
const perms = ['panel.admin', 'config.view', 'config.edit', 'events.manage', 'events.operate', 'events.history', 'participants.view', 'participants.manage', 'scores.view', 'scores.adjust', 'rewards.manage', 'monitoring.view', 'audit.view', 'staff.manage', 'leaderboard.staff', 'deception.secrets', 'export.history', 'props.manage', 'shop.manage'];

const shopItems = { carnival_bloodfloss: 'Bloodspun Candy Floss', carnival_eyeball_pop: 'Eyeball Cake Pop', carnival_grave_popcorn: 'Graveyard Popcorn', carnival_poison_apple: 'Poisoned Toffee Apple',
  carnival_bone_pretzel: 'Bone-Knot Pretzel', carnival_finger_dog: 'Severed Finger Corn Dog', carnival_web_cake: 'Cobweb Funnel Cake', carnival_witch_brew: "Witch's Brew Lemonade",
  carnival_blood_slushie: 'Blood Moon Slushie', carnival_grave_shake: 'Grave Dirt Shake', carnival_prize_box: 'Carnival Prize Box' };
const shopData = { label: settings.shop.label, currency: settings.shop.currency, wallet: { balance: 85, earned: 140, spent: 55 },
  earning: ['shooting', 'wheel', 'fortune', 'puppets', 'deception', 'horror'].map((id, i) => ({ attraction: id, label: settings.attractions[id].label, ...settings.shop.earning[id], wonTonight: [42, 40, 12, 0, 0, 0][i] })),
  items: settings.shop.items.filter((it) => shopItems[it.item]).map((it, i) => ({ item: it.item, label: shopItems[it.item], price: it.price, category: it.category, dailyLimit: it.dailyLimit,
    remainingToday: it.dailyLimit > 0 ? it.dailyLimit - (i % 2) : undefined, description: ['Spun from sugar and something darker. It leaves your lips red.', 'A cake pop that watches you eat it. Raspberry glaze.', 'Buttered and charcoal-black kernels in a coffin-striped box.', 'Black toffee over a green apple. The skull on the stick is only a joke. Probably.'][i % 4] })) };

const scenes = {
  hud: [['hud', { visible: true }]],
  hub: [['open', { view: 'player', data: {} }]],
  ticket: [['open', { view: 'ticket', data: { serial: 'CTD-7K2QF-M9XRA', colour: 'red', holder: 'Ada Lovelace', status: 'valid', eventName: 'Carnival of the Damned' } }]],
  leaderboard: [['open', { view: 'leaderboard', data: board }]],
  wheel: [['open', { view: 'wheel', data: { outcomes: settings.attractions.wheel.outcomes, spinsUsed: 0, maxSpins: 2, cooldownRemaining: 0, animationMs: 4000, label: settings.attractions.wheel.label } }]],
  fortune: [['open', { view: 'fortune', data: fortuneVisit }]],
  shooting: [['open', { view: 'shootingGame', data: { gameId: 1, duration: sgDuration, rounds: sgRounds, countdownMs: 3000, elapsedMs: sgRounds[2].startMs + 5200, plan, total: 95, hits: 19, shots: 24, hitIds: [], label: 'The Shooting Gallery' } }]],
  shootingbreak: [['open', { view: 'shootingGame', data: { gameId: 2, duration: sgDuration, rounds: sgRounds, countdownMs: 3000, elapsedMs: sgRounds[1].endMs + 1200, plan, total: 70, hits: 14, shots: 17, hitIds: [], label: 'The Shooting Gallery' } }]],
  shootingresult: [['open', { view: 'shootingGame', data: { gameId: 3, duration: sgDuration, rounds: sgRounds, countdownMs: 3000, elapsedMs: sgDuration - 300, plan, total: 186, hits: 41, shots: 49, hitIds: [], label: 'The Shooting Gallery' } }],
    ['push', { channel: 'shooting', data: { action: 'result', result: { gameId: 3, points: 202, targetPoints: 186, hits: 41, shots: 49, bullseyes: 9, specials: 5, decoys: 1, accuracy: 83, accuracyBonus: 16,
      rounds: sgRounds.map((r, i) => ({ number: r.number, label: r.label, points: [62, 72, 52][i], hits: [12, 15, 14][i], targets: r.targets, pointsPercent: r.pointsPercent })) } } }]],
  deception: [['open', { view: 'deception', data: deceptionState }]],
  vote: [['open', { view: 'theatreVote', data: { performanceId: 2, title: 'The Lion Tamer\'s Last Bow', endsAt: now() + 20, serverTime: now(), self: 1, candidates: [{ participantId: 2, name: 'Marlo Vance', role: 'Lion Tamer' }, { participantId: 3, name: 'Juno Reyes', role: 'Unionised Lion' }] } }]],
  theatre: [['open', { view: 'theatre', data: { scenario: { title: 'The Lion Tamer\'s Last Bow', difficulty: 'absurd', description: 'The lion has unionised and refuses to perform until its demands are met.' }, role: 'Unionised Lion', performer: true, status: 'running', endsAt: now() + 120, serverTime: now(), performers: [{ name: 'Marlo Vance', role: 'Lion Tamer' }, { name: 'Ada Lovelace', role: 'Unionised Lion' }] } }]],
  horror: [['horror', { active: true, status: 'running', endsAt: now() + 148, serverTime: now(), collected: 3, points: 40, runnerStatus: 'inside' }]],
  admin: [['open', { view: 'admin', data: {} }]],
  settings: [['open', { view: 'admin', data: {} }], ['click', '.nav-item:nth-child(4)']],
  horrorsettings: [['open', { view: 'admin', data: {} }], ['click', '.nav-item:nth-child(4)'], ['click', '.tab:nth-child(2)'], ['click', '.chip:nth-child(6)']],
  props: [['open', { view: 'admin', data: {} }], ['click', '.nav-item:nth-child(4)'], ['click', '.tab:nth-child(4)']],
  players: [['open', { view: 'admin', data: {} }], ['click', '.nav-item:nth-child(2)']],
  shop: [['open', { view: 'shop', data: shopData }]],
  prizebox: [['open', { view: 'admin', data: {} }], ['click', '.nav-item:nth-child(4)'], ['click', '.tab:nth-child(3)'], ['click', '.chip:nth-child(4)']],
  prizeboxodds: [['open', { view: 'admin', data: {} }], ['click', '.nav-item:nth-child(4)'], ['click', '.tab:nth-child(3)'], ['click', '.chip:nth-child(4)'], ['scroll', '.shell-main']],
  reveal: [['open', { view: 'prizeReveal', data: { contents: [{ item: 'carnival_eyeball_pop', count: 2, label: 'Eyeball Cake Pop' }, { item: 'carnival_finger_dog', count: 1, label: 'Severed Finger Corn Dog' }, { item: 'carnival_token_gold', count: 1, label: 'Gold Horror Token' }], images: [] } }]],
  shopprizes: [['open', { view: 'shop', data: shopData }], ['click', '.chips .chip:nth-child(4)'], ['click', '.booth-item:nth-child(3)']],
  shopadmin: [['open', { view: 'admin', data: {} }], ['click', '.nav-item:nth-child(2)'], ['click', '.tab:nth-child(5)']],
};

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined });
for (const [name, msgs] of Object.entries(scenes)) {
  if (only.length && !only.includes(name)) continue;
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  page.on('pageerror', (err) => console.warn(`${name}: page error: ${err.message}`));
  await page.addInitScript(() => { window.GetParentResourceName = () => 'blacklist_carnival'; });
  await page.route('https://blacklist_carnival/**', async (route) => {
    const body = route.request().postDataJSON() || {};
    let data = { ok: true };
    if (route.request().url().endsWith('/api')) data = responses[body.endpoint] ?? { ok: false, error: 'not_mocked', message: 'No preview data for ' + body.endpoint };
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(data) });
  });
  // stand-in for the nui:// scheme: point ox_inventory item images at the local copies
  await page.addInitScript(() => {
    new MutationObserver(() => document.querySelectorAll('img[src^="nui://ox_inventory/web/images/"]').forEach((img) => {
      img.src = '/inv/' + img.getAttribute('src').split('/').pop();
    })).observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ['src'] });
  });
  await page.goto(base);
  // a dim street scene stands in for the game world behind the UI
  await page.addStyleTag({ content: 'html,body{background:radial-gradient(circle at 30% 40%,#2c3440,#0d1015 70%) !important}' });
  const post = (action, data) => page.evaluate(([a, d]) => window.dispatchEvent(new MessageEvent('message', { data: { action: a, data: d } })), [action, data]);
  await post('push', { channel: 'bootstrap', data: { serverTime: now(), settings, event, participant, permissions: perms, role: 'owner' } });
  for (const [a, d] of msgs) {
    if (a === 'scroll') {
      await page.waitForTimeout(600);
      await page.evaluate((sel) => { const el = document.querySelector(sel); if (el) el.scrollTop = el.scrollHeight; }, d);
    } else if (a === 'click') {
      await page.waitForTimeout(300);
      try { await page.click(d, { timeout: 3000 }); } catch { console.warn(`${name}: nothing matched ${d}`); }
    } else await post(a, d);
  }
  await page.waitForTimeout(600);
  await page.screenshot({ path: join(outDir, `${name}.png`) });
  await page.close();
}
await browser.close();
server.close();
console.log('saved to', outDir);

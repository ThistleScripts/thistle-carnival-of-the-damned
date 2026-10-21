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
    const file = join(dist, path === '/' ? 'index.html' : path);
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

const plan = Array.from({ length: 40 }, (_, i) => ({ id: i + 1, t: i * 900, life: 2800, kind: i % 9 === 4 ? 'special' : i % 7 === 3 ? 'decoy' : 'normal', lane: i % 3, dir: i % 2 ? 1 : -1 }));
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
  'participants.search': { ok: true, data: { page: 1, pageSize: 25, total: 10, rows: board.entries.map((e) => ({ id: e.participantId, display_name: e.name, colour: e.colour, status: 'active', total_score: e.total, online: e.rank % 3 !== 0, last_seen_at: now() - e.rank * 60 })) } },
};
const perms = ['panel.admin', 'config.view', 'config.edit', 'events.manage', 'events.operate', 'events.history', 'participants.view', 'participants.manage', 'scores.view', 'scores.adjust', 'rewards.manage', 'monitoring.view', 'audit.view', 'staff.manage', 'leaderboard.staff', 'deception.secrets', 'export.history'];

const scenes = {
  hud: [['hud', { visible: true }]],
  hub: [['open', { view: 'player', data: {} }]],
  ticket: [['open', { view: 'ticket', data: { serial: 'CTD-7K2QF-M9XRA', colour: 'red', holder: 'Ada Lovelace', status: 'valid', eventName: 'Carnival of the Damned' } }]],
  leaderboard: [['open', { view: 'leaderboard', data: board }]],
  wheel: [['open', { view: 'wheel', data: { outcomes: settings.attractions.wheel.outcomes, spinsUsed: 0, maxSpins: 2, cooldownRemaining: 0, animationMs: 4000, label: settings.attractions.wheel.label } }]],
  fortune: [['open', { view: 'fortune', data: fortuneVisit }]],
  shooting: [['open', { view: 'shootingGame', data: { gameId: 1, duration: 45000, lanes: 3, countdownMs: 3000, elapsedMs: 9000, plan, total: 35, hits: 6, shots: 8, hitIds: [], label: 'The Shooting Gallery' } }]],
  deception: [['open', { view: 'deception', data: deceptionState }]],
  vote: [['open', { view: 'theatreVote', data: { performanceId: 2, title: 'The Lion Tamer\'s Last Bow', endsAt: now() + 20, serverTime: now(), self: 1, candidates: [{ participantId: 2, name: 'Marlo Vance', role: 'Lion Tamer' }, { participantId: 3, name: 'Juno Reyes', role: 'Unionised Lion' }] } }]],
  theatre: [['open', { view: 'theatre', data: { scenario: { title: 'The Lion Tamer\'s Last Bow', difficulty: 'absurd', description: 'The lion has unionised and refuses to perform until its demands are met.' }, role: 'Unionised Lion', performer: true, status: 'running', endsAt: now() + 120, serverTime: now(), performers: [{ name: 'Marlo Vance', role: 'Lion Tamer' }, { name: 'Ada Lovelace', role: 'Unionised Lion' }] } }]],
  horror: [['horror', { active: true, status: 'running', endsAt: now() + 148, serverTime: now(), collected: 3, points: 40, runnerStatus: 'inside' }]],
  admin: [['open', { view: 'admin', data: {} }]],
  settings: [['open', { view: 'admin', data: {} }], ['click', '.nav-item:nth-child(4)']],
  horrorsettings: [['open', { view: 'admin', data: {} }], ['click', '.nav-item:nth-child(4)'], ['click', '.tab:nth-child(2)'], ['click', '.chip:nth-child(6)']],
  players: [['open', { view: 'admin', data: {} }], ['click', '.nav-item:nth-child(2)']],
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
  await page.goto(base);
  // a dim street scene stands in for the game world behind the UI
  await page.addStyleTag({ content: 'html,body{background:radial-gradient(circle at 30% 40%,#2c3440,#0d1015 70%) !important}' });
  const post = (action, data) => page.evaluate(([a, d]) => window.dispatchEvent(new MessageEvent('message', { data: { action: a, data: d } })), [action, data]);
  await post('push', { channel: 'bootstrap', data: { serverTime: now(), settings, event, participant, permissions: perms, role: 'owner' } });
  for (const [a, d] of msgs) {
    if (a === 'click') {
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

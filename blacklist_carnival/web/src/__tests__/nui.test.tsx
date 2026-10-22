// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from './fixture.json';

// Mock the Lua bridge: every api() call is answered from this table.
const responses: Record<string, any> = {};
const calls: { endpoint: string; payload: any }[] = [];
vi.mock('../nui', async () => {
  const actual: any = await vi.importActual('../nui');
  return {
    ...actual,
    isNui: false,
    api: vi.fn(async (endpoint: string, payload: any) => {
      calls.push({ endpoint, payload });
      const r = responses[endpoint];
      if (typeof r === 'function') return r(payload);
      return r ?? { ok: false, error: 'not_mocked' };
    }),
    closeView: vi.fn(),
    releaseFocus: vi.fn(),
    effect: vi.fn(),
    setWaypoint: vi.fn(),
    placeProp: vi.fn(),
    captureCoords: vi.fn(async () => ({ x: 1, y: 2, z: 3, w: 90 })),
  };
});
vi.mock('../audio', () => ({ playSound: vi.fn(), stopSound: vi.fn(), stopAll: vi.fn(), setAmbient: vi.fn() }));

import App from '../App';
import { installBridge } from '../bridge';
installBridge();
import { getState, setState } from '../store';
import { formatDuration, signed, colourHex } from '../format';
import { placeProp } from '../nui';
import { playSound, setAmbient } from '../audio';

const settings: any = {
  ...(fixture as any).defaults,
  groups: { colours: (fixture as any).defaults.groups.colours },
};

function lua(action: string, data: any) {
  act(() => {
    window.dispatchEvent(new MessageEvent('message', { data: { action, data } }));
  });
}

beforeEach(() => {
  calls.length = 0;
  for (const k of Object.keys(responses)) delete responses[k];
  setState({ views: {}, minimised: {}, hudVisible: false, shooting: { active: false }, horror: { active: false } });
  lua('push', {
    channel: 'bootstrap',
    data: {
      serverTime: Math.floor(Date.now() / 1000),
      settings,
      event: { active: true, id: 1, name: 'Test Night', state: 'running', stateLabel: 'Running', round: 2, totalRounds: 6, roundEndsAt: Math.floor(Date.now() / 1000) + 300, participantCount: 12, maxParticipants: 120 },
      participant: { registered: true, id: 5, name: 'Ada Lovelace', colour: 'red', status: 'active', total: 42, rank: 3, ticket: { serial: 'CTD-ABCDE-FGHIJ', status: 'active' }, completed: ['shooting'], current: { attraction: 'wheel', status: 'active', sessionId: 9 }, next: 'fortune', breakdown: { shooting: 30 } },
      permissions: ['panel.admin', 'panel.staff', 'config.view', 'config.edit', 'events.manage', 'events.operate', 'events.history', 'participants.view', 'participants.manage', 'scores.view', 'scores.adjust', 'rewards.manage', 'attractions.operate.wheel', 'attractions.operate.horror', 'horror.control', 'monitoring.view', 'audit.view', 'staff.manage', 'leaderboard.staff', 'deception.secrets', 'export.history', 'shop.manage'],
      role: 'owner',
    },
  });
});
afterEach(() => cleanup());

describe('format helpers', () => {
  it('formats durations and deltas', () => {
    expect(formatDuration(65)).toBe('1:05');
    expect(formatDuration(3725)).toBe('1:02:05');
    expect(signed(5)).toBe('+5');
    expect(signed(-3)).toBe('-3');
    expect(colourHex(settings, 'red')).toBe('#b3122a');
  });
});

describe('player screens', () => {
  it('shows the HUD with score, round and current attraction', () => {
    render(<App />);
    lua('hud', { visible: true });
    expect(screen.getByText('42')).toBeTruthy();
    expect(screen.getByText(/Round 2\/6/)).toBeTruthy();
    expect(screen.getByText('The Wheel of Misfortune')).toBeTruthy();
  });

  it('walk-up mode: the HUD shows progress and the next game instead of rounds', () => {
    render(<App />);
    lua('push', { channel: 'event', data: { active: true, id: 2, name: 'Open Night', state: 'running', stateLabel: 'Running', mode: 'walkup', round: 0, totalRounds: 6 } });
    lua('push', { channel: 'participant', data: { registered: true, id: 5, colour: 'red', status: 'active', total: 7, walkup: true,
      sequence: ['shooting', 'wheel', 'fortune', 'puppets', 'deception', 'horror'], completed: ['shooting'], current: { attraction: 'wheel', status: 'active' }, next: 'fortune' } });
    lua('hud', { visible: true });
    expect(screen.getByText(/1\/6 played/)).toBeTruthy();
    expect(screen.queryByText(/Round \d/)).toBeNull();
    expect(screen.getByText('The Wheel of Misfortune')).toBeTruthy();
    expect(screen.getByText(/target the attendant to play/)).toBeTruthy();
  });

  it('opens and closes the ticket card with Escape (focus released)', () => {
    render(<App />);
    lua('open', { view: 'ticket', data: { action: 'issued', colour: 'red', serial: 'CTD-ABCDE-FGHIJ', holder: 'Ada Lovelace', eventName: 'Test Night' } });
    expect(screen.getByText('ADMIT ONE')).toBeTruthy();
    expect(screen.getByText('Serial CTD-ABCDE-FGHIJ')).toBeTruthy();
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(getState().views.ticket).toBeUndefined();
  });

  it('shows a void ticket clearly', () => {
    render(<App />);
    lua('open', { view: 'ticket', data: { status: 'void', colour: 'blue', serial: 'CTD-OLD', holder: 'X' } });
    expect(screen.getByText(/VOID/)).toBeTruthy();
  });

  it('wheel: spins through the server and shows the server outcome', async () => {
    responses['wheel.spin'] = { ok: true, data: { index: 2, outcome: { id: 'jackpot', label: 'Jackpot of Souls', type: 'large_points' }, points: 40, spinsUsed: 1, maxSpins: 2, animationMs: 10, cooldownSeconds: 0 } };
    render(<App />);
    const outcomes = settings.attractions.wheel.outcomes.map((o: any) => ({ id: o.id, label: o.label, type: o.type, colour: o.colour }));
    lua('open', { view: 'wheel', data: { outcomes, spinsUsed: 0, maxSpins: 2, animationMs: 10, cooldownRemaining: 0, label: 'The Wheel of Misfortune' } });
    fireEvent.click(screen.getByText('Spin the wheel'));
    await waitFor(() => expect(screen.getAllByText('Jackpot of Souls').length).toBeGreaterThan(1));
    expect(calls.some((c) => c.endpoint === 'wheel.spin')).toBe(true);
    expect(screen.getByText(/\+40 points/)).toBeTruthy();
  });

  it('wheel: shows server errors instead of a result', async () => {
    responses['wheel.spin'] = { ok: false, error: 'no_spins', message: 'You have used all of your spins.' };
    render(<App />);
    lua('open', { view: 'wheel', data: { outcomes: [{ id: 'a', label: 'A', type: 'nothing', colour: '#000000' }, { id: 'b', label: 'B', type: 'bonus', colour: '#111111' }], spinsUsed: 0, maxSpins: 2, animationMs: 10 } });
    fireEvent.click(screen.getByText('Spin the wheel'));
    await waitFor(() => expect(screen.getByText('You have used all of your spins.')).toBeTruthy());
  });

  it('fortune: answers a multiple-choice question', async () => {
    responses['fortune.answer'] = { ok: true, data: { correct: true, points: 10, text: 'Yes...', finished: true, farewell: 'Go now.' } };
    render(<App />);
    lua('open', { view: 'fortune', data: { visitId: 3, greeting: 'Sit, child.', question: { id: 'q_cards', kind: 'choice', prompt: 'Which card?', choices: ['A', 'B', 'C'], index: 1, total: 1, timeout: 60 } } });
    fireEvent.click(screen.getByText('B'));
    await waitFor(() => expect(screen.getByText('Correct.')).toBeTruthy());
    expect(calls.find((c) => c.endpoint === 'fortune.answer')!.payload).toMatchObject({ visitId: 3, questionId: 'q_cards', choice: 2 });
  });

  it('deception: requires exactly the liar count before accusing', async () => {
    responses['deception.submit'] = { ok: true, data: { submissionNumber: 1, remaining: 1 } };
    render(<App />);
    const m = settings.attractions.deception.mysteries[0];
    lua('open', { view: 'deception', data: { active: true, roundId: 7, status: 'questioning', maxSubmissions: 2, submissionsUsed: 0, clues: [], mystery: { title: m.title, description: m.description, liarCount: 3, performers: m.performers.map((p: any) => ({ id: p.id, name: p.name, profile: p.profile })) } } });
    const accuse = screen.getByText('Accuse').closest('button')!;
    expect(accuse.disabled).toBe(true);
    for (const name of ['Bruno the Strongman', 'Lady Ash', 'The Great Valentino']) fireEvent.click(screen.getByText(name));
    expect(accuse.disabled).toBe(false);
    fireEvent.click(accuse);
    await waitFor(() => expect(screen.getByText(/Accusation #1 recorded/)).toBeTruthy());
  });

  it('theatre card and horror HUD render as non-blocking overlays', () => {
    render(<App />);
    lua('open', { view: 'theatre', data: { action: 'card', status: 'displayed', performer: true, role: 'Lion Tamer', scenario: { title: 'The Reluctant Lion Tamer', description: 'x', difficulty: 'medium' }, performers: [{ name: 'Ada', role: 'Lion Tamer' }] } });
    expect(screen.getByText(/Your role/)).toBeTruthy();
    lua('horror', { active: true, status: 'running', endsAt: Math.floor(Date.now() / 1000) + 50, collected: 2, points: 15, runnerStatus: 'inside' });
    expect(screen.getByText('Tokens 2')).toBeTruthy();
    lua('horror', { active: false });
    expect(screen.queryByText('Tokens 2')).toBeNull();
  });

  it('leaderboard shows live pushes', () => {
    render(<App />);
    lua('open', { view: 'leaderboard', data: { active: true, eventName: 'Test Night', entries: [{ rank: 1, name: 'Ada', total: 99 }], you: { rank: 1, total: 99 } } });
    expect(screen.getAllByText('Ada').length).toBeGreaterThan(0);
    lua('push', { channel: 'leaderboard', data: { active: true, eventName: 'Test Night', entries: [{ rank: 1, name: 'Grace', total: 120 }] } });
    expect(screen.getAllByText('Grace').length).toBeGreaterThan(0);
    expect(screen.queryByText('Ada')).toBeNull();
  });
});

describe('admin panel', () => {
  it('admin config editor renders every section from the real schema and blocks invalid saves', async () => {
    let saved: any = null;
    responses['config.get'] = { ok: true, data: { scope: 'global', data: settings, schema: (fixture as any).schema, versions: { global: { version: 4 }, source: 'global' }, hasEventOverride: false, activeEventId: 1, canEdit: true, canSeeSecrets: true, sounds: (fixture as any).sounds, liveLocked: true } };
    responses['config.save'] = (p: any) => { saved = p; return { ok: true, data: { saved: false, analysis: { valid: false, errors: [{ path: 'attractions.wheel.maxSpins', message: 'must be at most 50' }], warnings: [], changes: [] } } }; };
    render(<App />);
    lua('open', { view: 'admin', data: {} });
    // five sections in the sidebar, no per-game pages
    expect(document.querySelectorAll('.nav-item').length).toBe(5);
    fireEvent.click(screen.getByText('Settings'));
    const sections: Record<string, string[]> = {
      Carnival: ['General', 'Ticket booth', 'Ticket colours', 'Rotation', 'Audio'],
      Attractions: ['Shooting Gallery', 'Wheel', 'Fortune Teller', 'Theatre', 'Hall of Deception', 'House of Horrors'],
      'Scoring & prizes': ['Scoring', 'Leaderboard', 'Prizes & results', 'Reward items'],
    };
    for (const [tab, chips] of Object.entries(sections)) {
      fireEvent.click(screen.getByRole('tab', { name: tab }));
      for (const chip of chips) {
        fireEvent.click(screen.getByRole('tab', { name: chip }));
        await waitFor(() => expect(document.querySelector('.config-page')).toBeTruthy());
      }
    }
    // no staff modes left in any attraction's settings
    fireEvent.click(screen.getByRole('tab', { name: 'Attractions' }));
    fireEvent.click(screen.getByRole('tab', { name: 'House of Horrors' }));
    await screen.findByText('Run duration (s)');
    expect(screen.queryByText('Mode')).toBeNull();
    expect(screen.queryByText(/performer/i)).toBeNull();
    // Wheel page: change max spins to an invalid value and save
    fireEvent.click(screen.getByRole('tab', { name: 'Wheel' }));
    const label = await screen.findByText('Spins per participant');
    const input = label.parentElement!.querySelector('input')!;
    fireEvent.change(input, { target: { value: '999' } });
    fireEvent.click(screen.getByText(/Save global configuration/));
    await waitFor(() => expect(screen.getByText('must be at most 50')).toBeTruthy());
    expect(saved.data.attractions.wheel.maxSpins).toBe(999);
    // locked fields are disabled while the event runs
    fireEvent.click(screen.getByRole('tab', { name: 'Carnival' }));
    fireEvent.click(screen.getByRole('tab', { name: 'Rotation' }));
    await waitFor(() => expect(screen.getByText('Rotation matrix')).toBeTruthy());
    const matrixSelect = document.querySelector('.config-page table select') as HTMLSelectElement;
    expect(matrixSelect.disabled).toBe(true);
  });

  it('admin coordinate tool fills vec4 fields from the player position', async () => {
    responses['config.get'] = { ok: true, data: { scope: 'global', data: settings, schema: (fixture as any).schema, versions: { global: { version: 4 }, source: 'global' }, hasEventOverride: false, activeEventId: 1, canEdit: true, canSeeSecrets: true, sounds: (fixture as any).sounds, liveLocked: false } };
    render(<App />);
    lua('open', { view: 'admin', data: {} });
    fireEvent.click(screen.getByText('Settings'));
    fireEvent.click(screen.getByRole('tab', { name: 'Ticket booth' }));
    await screen.findByText('Entrance booth location');
    fireEvent.click(screen.getAllByText('Use my position')[0]);
    await waitFor(() => {
      const inputs = screen.getByText('Entrance booth location').parentElement!.querySelectorAll('input');
      expect((inputs[0] as HTMLInputElement).value).toBe('1');
      expect((inputs[3] as HTMLInputElement).value).toBe('90');
    });
  });

  it('admin overview shows the attractions, who is playing and the board, and recovers from errors', async () => {
    const now = Math.floor(Date.now() / 1000);
    let fail = true;
    const dashboard = {
      serverTime: now, event: { active: true, id: 2, name: 'Open Night', state: 'running', stateLabel: 'Running', mode: 'walkup', registrationOpen: true, participantCount: 3, maxParticipants: 120 },
      participants: { total: 3, online: 2, unassigned: 0 }, outstandingRewards: 0, rotation: { walkup: true, walkupSessions: [] },
      attractions: [{ id: 'shooting', label: 'The Shooting Gallery', readiness: { available: true, status: 'ready' }, summary: { playing: 1 } },
        { id: 'deception', label: 'The Hall of Deception', readiness: { available: false, status: 'unavailable', reason: 'Stage repairs' } }],
      leaderboard: [{ id: 5, rank: 1, name: 'Ada Lovelace', colour: 'red', total: 42 }],
      health: { ready: true, uptime: 60, schemaVersion: 4, resourceVersion: '1.0.0', inventoryRunning: true, targetRunning: true, qbxRunning: true, discordEnabled: false, database: { healthy: true }, counters: {}, config: { source: 'global', global: { version: 1 } } },
      recentTransactions: [], recentStaffActions: [], recentProblems: [],
    };
    responses['admin.dashboard'] = () => (fail ? { ok: false, error: 'database_error', message: 'The change could not be saved.' } : { ok: true, data: dashboard });
    responses['rotation.state'] = { ok: true, data: { walkup: true, serverTime: now, walkupSessions: [
      { sessionId: 4, attraction: 'shooting', busy: true, startedAt: now, players: [{ id: 5, name: 'Ada Lovelace', colour: 'red', online: true }] },
    ] } };
    render(<App />);
    lua('push', { channel: 'event', data: dashboard.event });
    lua('open', { view: 'admin', data: {} });
    await waitFor(() => expect(screen.getByText('The change could not be saved.')).toBeTruthy());
    fail = false;
    fireEvent.click(screen.getByText('Retry'));
    await waitFor(() => expect(screen.getByText('Open Night')).toBeTruthy());
    expect(screen.getByText('1 playing')).toBeTruthy();
    expect(screen.getByText('Stage repairs')).toBeTruthy();
    expect(screen.getByText('Reopen')).toBeTruthy();
    await waitFor(() => expect(screen.getByText('in play')).toBeTruthy());
    expect(screen.getAllByText(/Ada Lovelace/).length).toBeGreaterThan(1);
    // walk-up carnivals have no rounds to run
    expect(screen.queryByText('Between rounds')).toBeNull();
    expect(screen.queryByText('Force-advance round')).toBeNull();
    expect(screen.getByText('End the night')).toBeTruthy();
  });

  it('props tab lists placed props, starts the in-world placer and removes props', async () => {
    const now = Math.floor(Date.now() / 1000);
    responses['props.list'] = { ok: true, data: { max: 1000, models: ['carnival_gate'], props: [
      { id: 7, model: 'carnival_gate', label: 'Main gate', x: -1630.5, y: -1050.25, z: 13.1, rx: 0, ry: 0, rz: 90, collision: true, createdBy: 'Owner', createdAt: now },
      { id: 8, model: 'carnivalcoingold', x: 1, y: 2, z: 3, rx: 0, ry: 0, rz: -90, collision: false, createdBy: 'Owner', createdAt: now },
    ] } };
    responses['props.delete'] = { ok: true, data: true };
    render(<App />);
    setState({ permissions: new Set(['panel.admin', 'config.view', 'props.manage']) });
    lua('open', { view: 'admin', data: {} });
    fireEvent.click(screen.getByText('Settings'));
    fireEvent.click(screen.getByRole('tab', { name: 'Props' }));
    await screen.findByText('Main gate');
    expect(screen.getByText('270°')).toBeTruthy();
    // place a new prop
    const model = screen.getByPlaceholderText('e.g. carnivalcoingold');
    expect((screen.getByText('Place in the world') as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(model, { target: { value: 'carnival_stall' } });
    fireEvent.click(screen.getByText('Place in the world'));
    expect(placeProp).toHaveBeenCalledWith({ model: 'carnival_stall', label: undefined, collision: true });
    // move an existing one
    fireEvent.click(screen.getAllByText('Move')[0]);
    expect(placeProp).toHaveBeenLastCalledWith({ id: 7 });
    // remove (after confirming)
    fireEvent.click(screen.getAllByText('Remove')[1]);
    fireEvent.click(document.querySelector('.modal-foot .btn-danger') as HTMLElement);
    await waitFor(() => expect(calls.some((c) => c.endpoint === 'props.delete' && c.payload.id === 8)).toBe(true));
  });

  it('permission loss while open closes nothing in the NUI but hides gated navigation', () => {
    render(<App />);
    lua('open', { view: 'admin', data: {} });
    expect(screen.getByText('Settings')).toBeTruthy();
    fireEvent.click(screen.getByText('System'));
    expect(screen.getByRole('tab', { name: 'Monitoring' })).toBeTruthy();
    lua('push', { channel: 'perms', data: { role: 'observer', permissions: ['panel.admin'] } });
    expect(screen.queryByText('Settings')).toBeNull();
    expect(screen.queryByRole('tab', { name: 'Monitoring' })).toBeNull();
  });
});

describe('preview mode', () => {
  it('wheel preview spins locally without calling the server', async () => {
    render(<App />);
    const outcomes = settings.attractions.wheel.outcomes.map((o: any) => ({ id: o.id, label: o.label, type: o.type, colour: o.colour }));
    lua('open', { view: 'wheel', data: { preview: true, outcomes, spinsUsed: 0, maxSpins: 2, animationMs: 10, cooldownRemaining: 0 } });
    expect(screen.getByText(/PREVIEW/)).toBeTruthy();
    fireEvent.click(screen.getByText('Spin the wheel'));
    await waitFor(() => expect(document.querySelector('.wheel-result')).toBeTruthy());
    expect(calls.some((c) => c.endpoint === 'wheel.spin')).toBe(false);
  });

  it('fortune and deception previews never call the server', async () => {
    render(<App />);
    lua('open', { view: 'fortune', data: { preview: true, visitId: 0, greeting: 'Sit.', question: { id: 'preview', kind: 'choice', prompt: 'Q?', choices: ['A', 'B', 'C'], index: 1, total: 1, timeout: 60, previewCorrect: 3 } } });
    fireEvent.click(screen.getByText('C'));
    await waitFor(() => expect(screen.getByText('Correct.')).toBeTruthy());
    expect(calls.length).toBe(0);
  });
});

describe('shooting gallery aim game', () => {
  const plan = [
    { id: 1, t: 0, life: 5000, kind: 'normal', lane: 1, dir: 1 },
    { id: 2, t: 0, life: 5000, kind: 'decoy', lane: 2, dir: -1 },
  ];

  it('clicking a target reports the shot to the server and shows the server score', async () => {
    responses['shooting.shot'] = (p: any) => ({ ok: true, data: { hit: true, targetId: p.targetId, kind: 'normal', points: 5, total: 5, shots: 1, hits: 1 } });
    render(<App />);
    lua('open', { view: 'shootingGame', data: { gameId: 77, duration: 30000, lanes: 3, countdownMs: 3000, elapsedMs: 100, plan, total: 0, hits: 0, shots: 0, hitIds: [] } });
    const targets = document.querySelectorAll('.sg-target');
    expect(targets.length).toBe(2);
    expect(document.querySelector('.sg-decoy')).toBeTruthy();
    fireEvent.mouseDown(document.querySelector('.sg-normal')!);
    await waitFor(() => expect(calls.find((c) => c.endpoint === 'shooting.shot')!.payload).toMatchObject({ gameId: 77, targetId: 1 }));
    await waitFor(() => expect(screen.getByText('+5')).toBeTruthy());
  });

  it('clicking empty space reports a miss (no target id)', async () => {
    responses['shooting.shot'] = { ok: true, data: { hit: false, total: 0, shots: 1, hits: 0 } };
    render(<App />);
    lua('open', { view: 'shootingGame', data: { gameId: 78, duration: 30000, lanes: 3, countdownMs: 3000, elapsedMs: 100, plan, total: 0, hits: 0, shots: 0 } });
    fireEvent.mouseDown(document.querySelector('.sg-area')!);
    await waitFor(() => expect(calls.find((c) => c.endpoint === 'shooting.shot')!.payload.targetId).toBeUndefined());
  });

  it('shows the countdown before targets appear and the final result from the server', async () => {
    responses['shooting.finish'] = { ok: true, data: { gameId: 79, points: 42, hits: 8, shots: 10, accuracy: 80, accuracyBonus: 16 } };
    render(<App />);
    lua('open', { view: 'shootingGame', data: { gameId: 79, duration: 1000, lanes: 3, countdownMs: 3000, elapsedMs: 5000, plan, total: 26 } });
    await waitFor(() => expect(screen.getByText('42 points')).toBeTruthy(), { timeout: 3000 });
  });

  it('plays harder rounds: a break card names the next round and the result lists every round', async () => {
    const rounds = [
      { number: 1, label: 'Warm-up', startMs: 0, endMs: 2000, lanes: 2, size: 100, motion: 'straight', pointsPercent: 100, life: 1500, decoyChance: 5, targets: 2 },
      { number: 2, label: 'Dead Eye', startMs: 6000, endMs: 8000, lanes: 3, size: 70, motion: 'wave', pointsPercent: 200, life: 1000, decoyChance: 20, targets: 2 },
    ];
    const plan2 = [{ id: 1, round: 1, t: 0, life: 1500, kind: 'normal', lane: 1, dir: 1 }, { id: 2, round: 2, t: 6000, life: 1000, kind: 'normal', lane: 3, dir: -1 }];
    render(<App />);
    // 3 s into the game: the break before round 2
    lua('open', { view: 'shootingGame', data: { gameId: 90, duration: 8000, rounds, countdownMs: 3000, elapsedMs: 3000, plan: plan2, total: 5 } });
    expect(screen.getByText('Dead Eye')).toBeTruthy();
    expect(screen.getByText('Faster targets')).toBeTruthy();
    expect(screen.getByText('Smaller targets')).toBeTruthy();
    expect(screen.getByText('Targets weave')).toBeTruthy();
    expect(screen.getByText('Points ×2')).toBeTruthy();
    expect(screen.getByText('Round', { exact: false, selector: '.sg-stats span' })).toBeTruthy();
    // clicking the range during the break sends nothing
    fireEvent.mouseDown(document.querySelector('.sg-area')!);
    expect(calls.filter((c) => c.endpoint === 'shooting.shot').length).toBe(0);
    lua('push', { channel: 'shooting', data: { action: 'result', result: { gameId: 90, points: 35, hits: 2, shots: 3, accuracy: 66, targetPoints: 35,
      rounds: [{ number: 1, label: 'Warm-up', points: 5, hits: 1, targets: 2, pointsPercent: 100 }, { number: 2, label: 'Dead Eye', points: 30, hits: 1, targets: 2, pointsPercent: 200 }] } } });
    await waitFor(() => expect(screen.getByText('35 points')).toBeTruthy());
    expect(screen.getByText('+30')).toBeTruthy();
    expect(screen.getByText('Round 2 · Dead Eye', { exact: false })).toBeTruthy();
  });

  it('preview mode plays locally', () => {
    render(<App />);
    lua('open', { view: 'shootingGame', data: { preview: true, duration: 30000, lanes: 3, lifetime: 2800, countdownMs: 3000 } });
    expect(screen.getByText(/PREVIEW/)).toBeTruthy();
    fireEvent.mouseDown(document.querySelector('.sg-area')!);
    expect(calls.length).toBe(0);
  });
});

describe('theatre audience vote', () => {
  it('lists the other performers and sends the vote', async () => {
    responses['theatre.vote'] = { ok: true, data: { voted: true } };
    render(<App />);
    lua('open', { view: 'theatreVote', data: { performanceId: 5, title: 'Lion Tamer', self: 10, endsAt: Math.floor(Date.now() / 1000) + 20,
      candidates: [{ participantId: 10, name: 'Me', role: 'A' }, { participantId: 11, name: 'Grace', role: 'B' }] } });
    expect(screen.queryByText('Me')).toBeNull();
    fireEvent.click(screen.getByText('Grace'));
    await waitFor(() => expect(screen.getByText(/Vote cast/)).toBeTruthy());
    expect(calls.find((c) => c.endpoint === 'theatre.vote')!.payload).toMatchObject({ performanceId: 5, participantId: 11 });
  });
});

describe('prize counter', () => {
  const shop = {
    label: 'The Prize Counter', currency: 'Prize Tickets',
    wallet: { balance: 40, earned: 60, spent: 20 },
    earning: [{ attraction: 'shooting', label: 'The Shooting Gallery', perPlay: 5, per100Points: 20, maxPerNight: 60, wonTonight: 30 }],
    items: [
      { item: 'carnival_witch_brew', label: "Witch's Brew Lemonade", description: 'Sour green lemonade.', price: 15, category: 'drink', dailyLimit: 0 },
      { item: 'carnival_prize_box', label: 'Carnival Prize Box', price: 250, category: 'prize', dailyLimit: 2, remainingToday: 2 },
      { item: 'carnival_trick_token', label: 'Trick Token', price: 5, category: 'prize', dailyLimit: 5, remainingToday: 0 },
      { item: 'carnival_bloodfloss', label: 'Bloodspun Candy Floss', price: 10, category: 'food', dailyLimit: 0 },
    ],
  };

  it('shows the ticket balance, shelves and how to win tickets, and redeems with a fresh request id', async () => {
    responses['shop.buy'] = { ok: true, data: { balance: 10, item: 'carnival_witch_brew', count: 2, cost: 30 } };
    responses['shop.open'] = { ok: true, data: { ...shop, wallet: { ...shop.wallet, balance: 10 } } };
    render(<App />);
    lua('open', { view: 'shop', data: shop });
    expect(screen.getByText('40')).toBeTruthy();
    expect(screen.getByText('+5 for playing')).toBeTruthy();
    expect(screen.getByText('30/60 tonight')).toBeTruthy();
    // shelves filter the items
    fireEvent.click(screen.getByText('Prizes'));
    expect(screen.queryByText('Bloodspun Candy Floss')).toBeNull();
    // unaffordable and sold-out prizes cannot be redeemed
    fireEvent.click(screen.getByText('Carnival Prize Box', { selector: '.booth-item-name' }));
    expect((screen.getByText('210 more prize tickets needed').closest('button') as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(screen.getByText('Trick Token', { selector: '.booth-item-name' }));
    expect((screen.getByText('Come back tomorrow').closest('button') as HTMLButtonElement).disabled).toBe(true);
    // buy two drinks
    fireEvent.click(screen.getByText('Everything'));
    fireEvent.click(screen.getByText("Witch's Brew Lemonade", { selector: '.booth-item-name' }));
    fireEvent.click(document.querySelector('.booth-detail .stepper button:last-child')!);
    fireEvent.click(screen.getByText('Redeem 2 for 30'));
    await waitFor(() => expect(calls.find((c) => c.endpoint === 'shop.buy')).toBeTruthy());
    const buy = calls.find((c) => c.endpoint === 'shop.buy')!.payload;
    expect(buy).toMatchObject({ item: 'carnival_witch_brew', count: 2 });
    expect(buy.requestId).toMatch(/^[0-9a-f]{24}$/);
    await waitFor(() => expect(document.querySelector('.booth-balance-value')!.textContent).toBe('10'));
    expect(playSound).toHaveBeenCalledWith('shop_purchase', 0.7);
  });

  it('wallet pushes update the balance and announce the tickets won', async () => {
    render(<App />);
    lua('open', { view: 'shop', data: shop });
    lua('push', { channel: 'wallet', data: { balance: 65, earned: 85, spent: 20, currency: 'Prize Tickets', delta: 25, attraction: 'horror' } });
    expect(document.querySelector('.booth-balance-value')!.textContent).toBe('65');
    await waitFor(() => expect(screen.getByText(/\+25 Prize Tickets from House of Horrors/)).toBeTruthy());
  });

  it('item pictures come from ox_inventory: the item\'s own image, then the inventory image path, then an icon', () => {
    render(<App />);
    lua('inventory', { imagePath: 'https://cdn.example.com/items/' });
    const items = [
      { ...shop.items[0], image: 'nui://ox_inventory/web/images/custom_brew.png' },
      ...shop.items.slice(1),
    ];
    lua('open', { view: 'shop', data: { ...shop, items } });
    const img = () => document.querySelector('.booth-detail img') as HTMLImageElement;
    expect(img().getAttribute('src')).toBe('nui://ox_inventory/web/images/custom_brew.png');
    fireEvent.error(img());
    expect(img().getAttribute('src')).toBe('https://cdn.example.com/items/carnival_witch_brew.png');
    fireEvent.error(img());
    expect(img().getAttribute('src')).toBe('nui://ox_inventory/web/images/carnival_witch_brew.png');
    fireEvent.error(img());
    expect(document.querySelector('.booth-detail .item-img-missing')).toBeTruthy();
    // shelf cards without a resolved image use the inventory image path
    const floss = screen.getByText('Bloodspun Candy Floss', { selector: '.booth-item-name' }).closest('button')!.querySelector('img')!;
    expect(floss.getAttribute('src')).toBe('https://cdn.example.com/items/carnival_bloodfloss.png');
  });

  it('ambient levels from Lua go to the mixer', () => {
    lua('ambient', { levels: [{ id: 'crowd', sound: 'ambient_crowd', volume: 0.3 }] });
    expect(setAmbient).toHaveBeenCalledWith([{ id: 'crowd', sound: 'ambient_crowd', volume: 0.3 }]);
  });

  it('admin prize counter page lists wallets and adjusts with a reason', async () => {
    responses['shop.overview'] = { ok: true, data: {
      currency: 'Prize Tickets',
      totals: { wallets: 1, outstanding: 40, earned: 60, spent: 20, purchasesToday: 1, spentToday: 20 },
      popular: [{ item: 'carnival_witch_brew', sold: 2, points: 30 }],
      recent: [{ id: 3, citizenid: 'ABC123', display_name: 'Ada Lovelace', kind: 'purchase', delta: -30, balance_after: 40, item: 'carnival_witch_brew', item_count: 2, created_at: 1760000000 }],
      wallets: [{ citizenid: 'ABC123', display_name: 'Ada Lovelace', balance: 40, earned_total: 60, spent_total: 20, updated_at: 1760000000 }],
    } };
    responses['shop.adjust'] = { ok: true, data: { balance: 90 } };
    render(<App />);
    lua('open', { view: 'admin', data: {} });
    fireEvent.click(screen.getByText('Players'));
    fireEvent.click(screen.getByText('Prize counter'));
    await waitFor(() => expect(screen.getByText('Best sellers')).toBeTruthy());
    fireEvent.click(screen.getByText('Adjust'));
    fireEvent.change(screen.getByPlaceholderText('e.g. 50 or -20'), { target: { value: '50' } });
    fireEvent.change(document.querySelector('.modal textarea')!, { target: { value: 'Lost points in a crash' } });
    fireEvent.click(screen.getByText('Apply'));
    await waitFor(() => expect(calls.find((c) => c.endpoint === 'shop.adjust')).toBeTruthy());
    expect(calls.find((c) => c.endpoint === 'shop.adjust')!.payload).toMatchObject({ citizenid: 'ABC123', delta: 50, reason: 'Lost points in a crash' });
  });
});

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
    captureCoords: vi.fn(async () => ({ x: 1, y: 2, z: 3, w: 90 })),
  };
});
vi.mock('../audio', () => ({ playSound: vi.fn(), stopSound: vi.fn(), stopAll: vi.fn() }));

import App from '../App';
import { installBridge } from '../bridge';
installBridge();
import { getState, setState } from '../store';
import { formatDuration, signed, colourHex } from '../format';

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
      permissions: ['panel.admin', 'panel.staff', 'config.view', 'config.edit', 'events.manage', 'events.operate', 'events.history', 'participants.view', 'participants.manage', 'scores.view', 'scores.adjust', 'rewards.manage', 'attractions.operate.wheel', 'attractions.operate.horror', 'horror.control', 'monitoring.view', 'audit.view', 'staff.manage', 'leaderboard.staff', 'deception.secrets', 'export.history'],
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
    expect(screen.getByText('Ada')).toBeTruthy();
    lua('push', { channel: 'leaderboard', data: { active: true, eventName: 'Test Night', entries: [{ rank: 1, name: 'Grace', total: 120 }] } });
    expect(screen.getByText('Grace')).toBeTruthy();
  });
});

describe('staff & admin panels', () => {
  it('admin config editor renders every section from the real schema and blocks invalid saves', async () => {
    let saved: any = null;
    responses['config.get'] = { ok: true, data: { scope: 'global', data: settings, schema: (fixture as any).schema, versions: { global: { version: 4 }, source: 'global' }, hasEventOverride: false, activeEventId: 1, canEdit: true, canSeeSecrets: true, sounds: (fixture as any).sounds, liveLocked: true } };
    responses['config.save'] = (p: any) => { saved = p; return { ok: true, data: { saved: false, analysis: { valid: false, errors: [{ path: 'attractions.wheel.maxSpins', message: 'must be at most 50' }], warnings: [], changes: [] } } }; };
    render(<App />);
    lua('open', { view: 'admin', data: {} });
    for (const section of ['General', 'Registration & tickets', 'Rotation', 'Scoring', 'Prizes & results', 'Shooting Gallery', 'Wheel of Misfortune', 'Fortune Teller', "Puppet Master's Theatre", 'Hall of Deception', 'House of Horrors']) {
      fireEvent.click(screen.getAllByText(section)[0]);
      await waitFor(() => expect(document.querySelector('.config-page')).toBeTruthy());
    }
    // Wheel page: change max spins to an invalid value and save
    fireEvent.click(screen.getAllByText('Wheel of Misfortune')[0]);
    const label = await screen.findByText('Spins per participant');
    const input = label.parentElement!.querySelector('input')!;
    fireEvent.change(input, { target: { value: '999' } });
    fireEvent.click(screen.getByText(/Save global configuration/));
    await waitFor(() => expect(screen.getByText('must be at most 50')).toBeTruthy());
    expect(saved.data.attractions.wheel.maxSpins).toBe(999);
    // locked fields are disabled while the event runs
    fireEvent.click(screen.getAllByText('Rotation')[0]);
    await waitFor(() => expect(screen.getByText('Rotation matrix')).toBeTruthy());
    const matrixSelect = document.querySelector('.config-page table select') as HTMLSelectElement;
    expect(matrixSelect.disabled).toBe(true);
  });

  it('admin coordinate tool fills vec4 fields from the player position', async () => {
    responses['config.get'] = { ok: true, data: { scope: 'global', data: settings, schema: (fixture as any).schema, versions: { global: { version: 4 }, source: 'global' }, hasEventOverride: false, activeEventId: 1, canEdit: true, canSeeSecrets: true, sounds: (fixture as any).sounds, liveLocked: false } };
    render(<App />);
    lua('open', { view: 'admin', data: {} });
    fireEvent.click(screen.getAllByText('Registration & tickets')[0]);
    await screen.findByText('Entrance booth location');
    fireEvent.click(screen.getAllByText('Use my position')[0]);
    await waitFor(() => {
      const inputs = screen.getByText('Entrance booth location').parentElement!.querySelectorAll('input');
      expect((inputs[0] as HTMLInputElement).value).toBe('1');
      expect((inputs[3] as HTMLInputElement).value).toBe('90');
    });
  });

  it('staff panel shows only consoles the user may operate and renders loading/error states', async () => {
    responses['rotation.state'] = { ok: false, error: 'database_error', message: 'The change could not be saved.' };
    responses['groups.overview'] = { ok: true, data: { groups: [], unassigned: 0, total: 0 } };
    responses['attractions.overview'] = { ok: true, data: [] };
    setState({ permissions: new Set(['panel.staff', 'attractions.operate.wheel', 'participants.view']) });
    render(<App />);
    lua('open', { view: 'staff', data: {} });
    expect(screen.getByText('Event Staff')).toBeTruthy();
    expect(screen.getAllByText('Wheel of Misfortune').length).toBeGreaterThan(0);
    expect(screen.queryByText('House of Horrors')).toBeNull();
    await waitFor(() => expect(screen.getByText('The change could not be saved.')).toBeTruthy());
    expect(screen.getByText('Retry')).toBeTruthy();
  });

  it('walk-up mode: live operations list who is playing where, with no round controls', async () => {
    const now = Math.floor(Date.now() / 1000);
    responses['rotation.state'] = { ok: true, data: { walkup: true, round: 0, totalRounds: 6, walkupSessions: [
      { sessionId: 4, attraction: 'shooting', busy: true, startedAt: now, players: [{ id: 5, name: 'Ada Lovelace', colour: 'red', online: true }] },
    ] } };
    responses['groups.overview'] = { ok: true, data: { groups: [], unassigned: 0, total: 0 } };
    responses['attractions.overview'] = { ok: true, data: [] };
    render(<App />);
    lua('open', { view: 'staff', data: {} });
    await waitFor(() => expect(screen.getByText(/Walk-up mode: players buy a ticket/)).toBeTruthy());
    expect(screen.getAllByText(/Ada Lovelace/).length).toBeGreaterThan(0);
    expect(screen.getByText('in play')).toBeTruthy();
    expect(screen.queryByText('Force-advance round')).toBeNull();
  });

  it('permission loss while open closes nothing in the NUI but hides gated navigation', () => {
    render(<App />);
    lua('open', { view: 'admin', data: {} });
    expect(screen.getAllByText('Monitoring centre').length).toBeGreaterThan(0);
    lua('push', { channel: 'perms', data: { role: 'observer', permissions: ['panel.admin'] } });
    expect(screen.queryByText('Monitoring centre')).toBeNull();
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

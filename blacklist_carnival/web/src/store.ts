import { useSyncExternalStore } from 'react';

// Global NUI state. Updated from Lua messages (see main.tsx).

export interface Settings {
  general: { eventName: string; blipLabel: string; hudEnabled: boolean };
  registration: any;
  groups: { colours: Record<string, { enabled: boolean; label: string; hex: string }> };
  rotation: { matrix: string[][]; roundDurationSeconds: number; transitionSeconds: number };
  leaderboard: any;
  audio: { masterVolume: number; notificationSound: string; roundSound: string };
  rewards: any;
  attractions: Record<string, any>;
}

export interface EventState {
  active: boolean;
  id?: number;
  name?: string;
  description?: string;
  state?: string;
  mode?: 'walkup' | 'scheduled';
  stateLabel?: string;
  serverTime?: number;
  round?: number;
  totalRounds?: number;
  roundState?: string;
  roundEndsAt?: number;
  roundRemaining?: number;
  nextRoundAt?: number;
  overtime?: boolean;
  registrationOpen?: boolean;
  participantCount?: number;
  maxParticipants?: number;
}

export interface State {
  settings: Settings | null;
  event: EventState | null;
  participant: any;
  permissions: Set<string>;
  role: string | null;
  serverOffset: number; // serverTime - Date.now()/1000
  views: Record<string, any>; // open views and their data
  minimised: Record<string, boolean>;
  hudVisible: boolean;
  hudHidden: boolean;
  shooting: any;
  horror: any;
  leaderboard: any;
  lastScore: any;
  invalidations: Record<string, number>;
}

let state: State = {
  settings: null,
  event: null,
  participant: null,
  permissions: new Set(),
  role: null,
  serverOffset: 0,
  views: {},
  minimised: {},
  hudVisible: false,
  hudHidden: false,
  shooting: { active: false },
  horror: { active: false },
  leaderboard: null,
  lastScore: null,
  invalidations: {},
};

const listeners = new Set<() => void>();

export function getState() {
  return state;
}

export function setState(patch: Partial<State> | ((s: State) => Partial<State>)) {
  const p = typeof patch === 'function' ? patch(state) : patch;
  state = { ...state, ...p };
  listeners.forEach((l) => l());
}

export function subscribe(l: () => void) {
  listeners.add(l);
  return () => listeners.delete(l);
}

export function useStore<T>(selector: (s: State) => T): T {
  return useSyncExternalStore(subscribe, () => selector(state));
}

export function serverNow(): number {
  return Math.floor(Date.now() / 1000) + state.serverOffset;
}

export function syncServerTime(serverTime?: number) {
  if (typeof serverTime === 'number') {
    setState({ serverOffset: serverTime - Math.floor(Date.now() / 1000) });
  }
}

export function has(perm: string) {
  return state.permissions.has(perm);
}

export function usePermission(perm: string) {
  return useStore((s) => s.permissions.has(perm));
}

export function openView(view: string, data: any) {
  setState((s) => ({ views: { ...s.views, [view]: data ?? {} }, minimised: { ...s.minimised, [view]: false } }));
}

export function closeViewState(view: string) {
  setState((s) => {
    const views = { ...s.views };
    delete views[view];
    return { views };
  });
}

export function invalidate(topics: string[]) {
  setState((s) => {
    const inv = { ...s.invalidations };
    for (const t of topics) inv[t] = (inv[t] ?? 0) + 1;
    return { invalidations: inv };
  });
}

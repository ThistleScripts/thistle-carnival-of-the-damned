// Formatting helpers. Server timestamps are UTC epoch seconds; they are shown in
// the viewer's local time zone.

export function formatDuration(seconds: number | null | undefined): string {
  const s = Math.max(0, Math.floor(seconds ?? 0));
  const m = Math.floor(s / 60);
  const r = s % 60;
  if (m >= 60) {
    const h = Math.floor(m / 60);
    return `${h}:${String(m % 60).padStart(2, '0')}:${String(r).padStart(2, '0')}`;
  }
  return `${m}:${String(r).padStart(2, '0')}`;
}

export function formatTime(epoch?: number | null): string {
  if (!epoch) return '—';
  return new Date(epoch * 1000).toLocaleString(undefined, {
    year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
}

export function formatClock(epoch?: number | null): string {
  if (!epoch) return '—';
  return new Date(epoch * 1000).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

export function signed(n: number): string {
  return n > 0 ? `+${n}` : `${n}`;
}

export const ATTRACTION_IDS = ['shooting', 'wheel', 'fortune', 'puppets', 'deception', 'horror'] as const;
export const COLOURS = ['red', 'blue', 'green', 'yellow', 'purple', 'orange'] as const;

export const ATTRACTION_SHORT: Record<string, string> = {
  shooting: 'Shooting Gallery',
  wheel: 'Wheel of Misfortune',
  fortune: 'Fortune Teller',
  puppets: 'Puppet Theatre',
  deception: 'Hall of Deception',
  horror: 'House of Horrors',
  general: 'General',
};

export const DEFAULT_COLOUR_HEX: Record<string, string> = {
  red: '#b3122a', blue: '#1f4fbf', green: '#1f8a3c', yellow: '#d8b21c', purple: '#6a2a9c', orange: '#d4621a',
};

export const STATE_LABELS: Record<string, string> = {
  inactive: 'Inactive',
  configuring: 'Configuring',
  registration_open: 'Registration open',
  registration_closed: 'Registration closed',
  ready: 'Ready to start',
  running: 'Running',
  paused: 'Paused',
  between_rounds: 'Between rounds',
  final_results: 'Final results',
  completed: 'Completed',
  cancelled: 'Cancelled',
};

// Allowed transitions (mirrors shared/constants.lua; the server re-validates).
export const TRANSITIONS: Record<string, string[]> = {
  inactive: ['configuring', 'cancelled'],
  configuring: ['inactive', 'registration_open', 'cancelled'],
  registration_open: ['registration_closed', 'cancelled'],
  registration_closed: ['registration_open', 'ready', 'cancelled'],
  ready: ['registration_closed', 'running', 'cancelled'],
  running: ['paused', 'between_rounds', 'final_results', 'cancelled'],
  paused: ['running', 'between_rounds', 'final_results', 'cancelled'],
  between_rounds: ['running', 'paused', 'final_results', 'cancelled'],
  final_results: ['completed'],
  completed: [],
  cancelled: [],
};

export function colourHex(settings: any, colour?: string | null): string {
  if (!colour) return '#555';
  return settings?.groups?.colours?.[colour]?.hex ?? DEFAULT_COLOUR_HEX[colour] ?? '#555';
}

export function colourLabel(settings: any, colour?: string | null): string {
  if (!colour) return 'Unassigned';
  return settings?.groups?.colours?.[colour]?.label ?? colour;
}

export function attractionLabel(settings: any, id?: string | null): string {
  if (!id) return '—';
  return settings?.attractions?.[id]?.label ?? ATTRACTION_SHORT[id] ?? id;
}

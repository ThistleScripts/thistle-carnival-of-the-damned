// Bridge between the NUI and the client Lua.
// All server data goes through the client's generic `api` callback, which
// forwards to the server router where permissions are enforced.

export const RESOURCE = 'blacklist_carnival';

// True when running inside FiveM's CEF.
export const isNui = typeof (window as any).GetParentResourceName === 'function';

export interface ApiResult<T = any> {
  ok: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export async function fetchNui<T = any>(name: string, data: unknown = {}): Promise<T> {
  if (!isNui) {
    throw new Error('not_in_game');
  }
  const res = await fetch(`https://${RESOURCE}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data ?? {}),
  });
  return (await res.json()) as T;
}

export async function api<T = any>(endpoint: string, payload: Record<string, unknown> = {}): Promise<ApiResult<T>> {
  try {
    return await fetchNui<ApiResult<T>>('api', { endpoint, payload });
  } catch (e) {
    return { ok: false, error: 'network', message: isNui ? 'Could not reach the game client.' : 'Open this interface in game.' };
  }
}

export function closeView(view?: string) {
  if (!isNui) return;
  fetchNui('close', view ? { view } : {}).catch(() => undefined);
}

export function releaseFocus(view: string) {
  if (!isNui) return;
  fetchNui('releaseFocus', { view }).catch(() => undefined);
}

export function effect(kind: string, extra: Record<string, unknown> = {}) {
  if (!isNui) return;
  fetchNui('effect', { kind, ...extra }).catch(() => undefined);
}

export function setWaypoint(x: number, y: number) {
  if (!isNui) return;
  fetchNui('setWaypoint', { x, y }).catch(() => undefined);
}

export async function captureCoords(): Promise<{ x: number; y: number; z: number; w: number } | null> {
  try {
    const r = await fetchNui<ApiResult<{ x: number; y: number; z: number; w: number }>>('captureCoords');
    return r.ok && r.data ? r.data : null;
  } catch {
    return null;
  }
}

// Hand over to the in-world prop placer: the admin panel minimises so the
// player can move and aim (reopen it with /carnivaladmin).
export function placeProp(opts: { id?: number; model?: string; label?: string; collision?: boolean }) {
  if (!isNui) return;
  releaseFocus('admin');
  fetchNui('propPlace', opts).catch(() => undefined);
}

// Unique id for idempotent admin actions (retries reuse the same id).
export function requestId(): string {
  const a = new Uint8Array(12);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, '0')).join('');
}

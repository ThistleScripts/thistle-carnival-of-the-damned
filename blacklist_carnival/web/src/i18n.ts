import type { ApiResult } from './nui';

// Error / message strings come from locales/en.json (served by the resource).
// The server usually supplies a specific message; these are fallbacks per code.

let strings: Record<string, string> = {};

export async function loadLocale() {
  try {
    const res = await fetch('../../locales/en.json');
    if (res.ok) strings = await res.json();
  } catch {
    strings = {};
  }
}

export function t(key: string, fallback?: string): string {
  return strings[key] ?? fallback ?? key;
}

export function errorText(r: ApiResult<any>): string {
  if (r.message && typeof r.message === 'string') return r.message;
  if (r.message && typeof r.message === 'object') {
    const m: any = r.message;
    if (Array.isArray(m.errors) && m.errors[0]) return `${m.errors[0].path}: ${m.errors[0].message}`;
  }
  return t(`error.${r.error}`, r.error ? r.error.replace(/_/g, ' ') : 'Unknown error');
}

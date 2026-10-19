import React, { useCallback, useEffect, useRef, useState } from 'react';
import { api, ApiResult } from '../nui';
import { serverNow, useStore } from '../store';
import { colourHex, colourLabel, formatDuration, STATE_LABELS } from '../format';
import { errorText } from '../i18n';

// ---------------------------------------------------------------------------
// Toasts
// ---------------------------------------------------------------------------
type ToastKind = 'success' | 'error' | 'info' | 'warning';
interface ToastItem { id: number; text: string; kind: ToastKind }
let toastId = 0;
let toastListener: ((t: ToastItem[]) => void) | null = null;
let toasts: ToastItem[] = [];

export function toast(text: string, kind: ToastKind = 'info') {
  const t = { id: ++toastId, text, kind };
  toasts = [...toasts, t].slice(-5);
  toastListener?.(toasts);
  setTimeout(() => {
    toasts = toasts.filter((x) => x.id !== t.id);
    toastListener?.(toasts);
  }, kind === 'error' ? 6000 : 3500);
}

export function ToastHost() {
  const [items, setItems] = useState<ToastItem[]>([]);
  useEffect(() => {
    toastListener = setItems;
    return () => { toastListener = null; };
  }, []);
  return (
    <div className="toasts" role="status" aria-live="polite">
      {items.map((t) => <div key={t.id} className={`toast toast-${t.kind}`}>{t.text}</div>)}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Data hooks
// ---------------------------------------------------------------------------
export interface ApiState<T> { data: T | null; error: string | null; loading: boolean; reload: () => void }

// Fetches an endpoint; refetches when deps change or when the server
// invalidates one of `topics`.
export function useApi<T = any>(endpoint: string | null, payload: Record<string, unknown> = {}, deps: unknown[] = [], topics: string[] = []): ApiState<T> {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(!!endpoint);
  const [tick, setTick] = useState(0);
  const inv = useStore((s) => topics.map((t) => s.invalidations[t] ?? 0).join(','));
  const payloadRef = useRef(payload);
  payloadRef.current = payload;

  useEffect(() => {
    if (!endpoint) return;
    let alive = true;
    setLoading(true);
    api<T>(endpoint, payloadRef.current).then((r) => {
      if (!alive) return;
      if (r.ok) {
        setData((r.data ?? null) as T | null);
        setError(null);
      } else {
        setError(errorText(r));
      }
      setLoading(false);
    });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [endpoint, tick, inv, ...deps]);

  const reload = useCallback(() => setTick((t) => t + 1), []);
  return { data, error, loading, reload };
}

// Runs a mutating endpoint with busy state and toasts.
export function useAction() {
  const [busy, setBusy] = useState(false);
  const run = useCallback(async <T = any,>(endpoint: string, payload: Record<string, unknown> = {}, success?: string): Promise<ApiResult<T>> => {
    setBusy(true);
    const r = await api<T>(endpoint, payload);
    setBusy(false);
    if (r.ok) {
      if (success) toast(success, 'success');
    } else {
      toast(errorText(r), 'error');
    }
    return r;
  }, []);
  return { busy, run };
}

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------
type BtnVariant = 'primary' | 'danger' | 'ghost' | 'gold' | 'default';
export function Button(props: React.ButtonHTMLAttributes<HTMLButtonElement> & { variant?: BtnVariant; small?: boolean; busy?: boolean }) {
  const { variant = 'default', small, busy, className, children, disabled, ...rest } = props;
  return (
    <button {...rest} disabled={disabled || busy} className={`btn btn-${variant}${small ? ' btn-sm' : ''} ${className ?? ''}`}>
      {busy ? <span className="spinner spinner-inline" /> : null}
      {children}
    </button>
  );
}

export function Card({ title, actions, children, className }: { title?: React.ReactNode; actions?: React.ReactNode; children: React.ReactNode; className?: string }) {
  return (
    <section className={`card ${className ?? ''}`}>
      {(title || actions) && (
        <header className="card-head">
          {title ? <h3>{title}</h3> : <span />}
          {actions ? <div className="card-actions">{actions}</div> : null}
        </header>
      )}
      <div className="card-body">{children}</div>
    </section>
  );
}

export function Stat({ label, value, tone }: { label: string; value: React.ReactNode; tone?: 'gold' | 'blood' | 'ok' | 'warn' }) {
  return (
    <div className={`stat ${tone ? 'stat-' + tone : ''}`}>
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
    </div>
  );
}

const STATUS_TONE: Record<string, string> = {
  running: 'ok', active: 'ok', ready: 'ok', delivered: 'ok', completed: 'ok', valid: 'ok', available: 'ok', escaped: 'ok', committed: 'ok', questioning: 'ok',
  paused: 'warn', pending: 'warn', between_rounds: 'warn', registration_open: 'ok', registration_closed: 'warn', awaiting_approval: 'warn', approved: 'warn',
  held: 'warn', no_performer: 'warn', configuring: 'muted', inactive: 'muted', scheduled: 'muted', setup: 'muted', draft: 'muted', closed: 'warn', revealed: 'gold',
  failed: 'bad', cancelled: 'bad', unknown: 'bad', unavailable: 'bad', disabled: 'muted', removed: 'bad', skipped: 'muted', interrupted: 'bad',
  final_results: 'gold', trapped: 'bad', inside: 'warn', error: 'bad', critical: 'bad', warning: 'warn', info: 'muted', debug: 'muted',
};

export function StatusPill({ status, label }: { status?: string | null; label?: string }) {
  if (!status) return <span className="pill pill-muted">—</span>;
  const tone = STATUS_TONE[status] ?? 'muted';
  return <span className={`pill pill-${tone}`}>{label ?? STATE_LABELS[status] ?? status.replace(/_/g, ' ')}</span>;
}

export function ColourChip({ colour, withLabel = true }: { colour?: string | null; withLabel?: boolean }) {
  const settings = useStore((s) => s.settings);
  return (
    <span className="colour-chip" title={colourLabel(settings, colour)}>
      <span className="colour-dot" style={{ background: colourHex(settings, colour) }} />
      {withLabel ? colourLabel(settings, colour) : null}
    </span>
  );
}

export function Spinner() {
  return <div className="spinner" aria-label="Loading" />;
}

export function Loading({ text = 'Summoning data…' }: { text?: string }) {
  return <div className="state-box"><Spinner /><span>{text}</span></div>;
}

export function Empty({ text }: { text: string }) {
  return <div className="state-box state-empty">{text}</div>;
}

export function ErrorBox({ text, onRetry }: { text: string; onRetry?: () => void }) {
  return (
    <div className="state-box state-error">
      <span>{text}</span>
      {onRetry ? <Button small onClick={onRetry}>Retry</Button> : null}
    </div>
  );
}

// Render loading / error / empty states consistently around api data.
export function Async<T>({ state, empty, children }: { state: ApiState<T>; empty?: (d: T) => string | null; children: (d: T) => React.ReactNode }) {
  if (state.loading && state.data == null) return <Loading />;
  if (state.error && state.data == null) return <ErrorBox text={state.error} onRetry={state.reload} />;
  if (state.data == null) return <Empty text="Nothing here yet." />;
  const e = empty?.(state.data);
  if (e) return <Empty text={e} />;
  return <>{children(state.data)}</>;
}

export function Tabs<T extends string>({ tabs, active, onChange }: { tabs: { id: T; label: React.ReactNode }[]; active: T; onChange: (id: T) => void }) {
  return (
    <div className="tabs" role="tablist">
      {tabs.map((t) => (
        <button key={t.id} role="tab" aria-selected={t.id === active} className={`tab ${t.id === active ? 'tab-active' : ''}`} onClick={() => onChange(t.id)}>
          {t.label}
        </button>
      ))}
    </div>
  );
}

export function Pagination({ page, total, pageSize, onPage }: { page: number; total: number; pageSize: number; onPage: (p: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  return (
    <div className="pagination">
      <Button small disabled={page <= 1} onClick={() => onPage(page - 1)}>‹ Prev</Button>
      <span>Page {page} of {pages} · {total} records</span>
      <Button small disabled={page >= pages} onClick={() => onPage(page + 1)}>Next ›</Button>
    </div>
  );
}

export function Field({ label, hint, error, children }: { label: string; hint?: string; error?: string | null; children: React.ReactNode }) {
  return (
    <label className={`field ${error ? 'field-error' : ''}`}>
      <span className="field-label">{label}{hint ? <span className="field-hint" title={hint}> ⓘ</span> : null}</span>
      {children}
      {error ? <span className="field-msg">{error}</span> : null}
    </label>
  );
}

export function Countdown({ endsAt, remaining, className }: { endsAt?: number | null; remaining?: number | null; className?: string }) {
  const [, setTick] = useState(0);
  useEffect(() => {
    if (!endsAt) return;
    const t = setInterval(() => setTick((x) => x + 1), 500);
    return () => clearInterval(t);
  }, [endsAt]);
  const secs = endsAt ? Math.max(0, endsAt - serverNow()) : remaining ?? 0;
  return <span className={`countdown ${secs <= 10 && endsAt ? 'countdown-urgent' : ''} ${className ?? ''}`}>{formatDuration(secs)}</span>;
}

export function Modal({ title, onClose, children, footer, wide }: { title: string; onClose: () => void; children: React.ReactNode; footer?: React.ReactNode; wide?: boolean }) {
  useEffect(() => {
    const h = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); onClose(); } };
    window.addEventListener('keydown', h, true);
    return () => window.removeEventListener('keydown', h, true);
  }, [onClose]);
  return (
    <div className="modal-backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className={`modal ${wide ? 'modal-wide' : ''}`} role="dialog" aria-modal="true" aria-label={title}>
        <header className="modal-head"><h3>{title}</h3><button className="icon-btn" onClick={onClose} aria-label="Close">✕</button></header>
        <div className="modal-body">{children}</div>
        {footer ? <footer className="modal-foot">{footer}</footer> : null}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Confirmation with optional mandatory reason
// ---------------------------------------------------------------------------
interface ConfirmOpts { title: string; message?: React.ReactNode; confirmLabel?: string; danger?: boolean; reason?: 'required' | 'optional'; extra?: React.ReactNode }
interface ConfirmReq extends ConfirmOpts { resolve: (r: { reason: string } | null) => void }
let confirmListener: ((r: ConfirmReq | null) => void) | null = null;

export function confirmAction(opts: ConfirmOpts): Promise<{ reason: string } | null> {
  return new Promise((resolve) => {
    if (!confirmListener) return resolve(null);
    confirmListener({ ...opts, resolve });
  });
}

export function ConfirmHost() {
  const [req, setReq] = useState<ConfirmReq | null>(null);
  const [reason, setReason] = useState('');
  useEffect(() => {
    confirmListener = (r) => { setReason(''); setReq(r); };
    return () => { confirmListener = null; };
  }, []);
  if (!req) return null;
  const close = (ok: boolean) => {
    req.resolve(ok ? { reason: reason.trim() } : null);
    setReq(null);
  };
  const needs = req.reason === 'required';
  const valid = !needs || reason.trim().length >= 3;
  return (
    <Modal title={req.title} onClose={() => close(false)} footer={
      <>
        <Button variant="ghost" onClick={() => close(false)}>Cancel</Button>
        <Button variant={req.danger ? 'danger' : 'primary'} disabled={!valid} onClick={() => close(true)}>{req.confirmLabel ?? 'Confirm'}</Button>
      </>
    }>
      {req.message ? <div className="confirm-msg">{req.message}</div> : null}
      {req.extra}
      {req.reason ? (
        <Field label={needs ? 'Reason (required, recorded in the audit log)' : 'Note (optional)'}>
          <textarea autoFocus value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} rows={3} />
        </Field>
      ) : null}
    </Modal>
  );
}

export function Table({ head, children, compact }: { head: React.ReactNode[]; children: React.ReactNode; compact?: boolean }) {
  return (
    <div className="table-wrap">
      <table className={`table ${compact ? 'table-compact' : ''}`}>
        <thead><tr>{head.map((h, i) => <th key={i}>{h}</th>)}</tr></thead>
        <tbody>{children}</tbody>
      </table>
    </div>
  );
}

export function Delta({ value }: { value: number }) {
  return <span className={value > 0 ? 'delta-pos' : value < 0 ? 'delta-neg' : 'delta-zero'}>{value > 0 ? `+${value}` : value}</span>;
}

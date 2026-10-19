import { useEffect, useMemo, useState } from 'react';
import { api, captureCoords } from '../nui';
import { Async, Button, Card, Empty, Field, Modal, Pagination, StatusPill, Table, confirmAction, toast, useAction, useApi } from '../components/ui';
import { errorText } from '../i18n';
import { COLOURS, formatTime } from '../format';
import { playSound } from '../audio';

// Schema-driven editor for every gameplay setting. The schema comes from the
// server (shared/schema.lua) so the editor always matches what the server validates.

interface Node {
  key?: string; type: string; label?: string; fields?: Node[]; keys?: string[]; item?: Node; options?: string[];
  min?: number; max?: number; step?: number; secret?: boolean; restart?: boolean; locked?: boolean; help?: string; itemLabel?: string; allowEmpty?: boolean;
}

interface Ctx { sounds: string[]; liveLocked: boolean; canEdit: boolean; errors: Record<string, string> }

function defaultFor(node: Node): any {
  switch (node.type) {
    case 'group': { const o: any = {}; for (const f of node.fields ?? []) o[f.key!] = defaultFor(f); return o; }
    case 'map': { const o: any = {}; for (const k of node.keys ?? []) o[k] = defaultFor(node.item!); return o; }
    case 'list': case 'multiselect': return [];
    case 'bool': return false;
    case 'int': case 'number': return node.min != null && node.min > 0 ? node.min : 0;
    case 'select': return node.options?.[0] ?? '';
    case 'vec3': return { x: 0, y: 0, z: 0 };
    case 'vec4': return { x: 0, y: 0, z: 0, w: 0 };
    case 'color': return '#888888';
    case 'sound': return 'carnival_chime';
    case 'matrix': return [];
    default: return '';
  }
}

function setIn(obj: any, path: (string | number)[], value: any): any {
  if (path.length === 0) return value;
  const [h, ...rest] = path;
  const copy = Array.isArray(obj) ? [...obj] : { ...(obj ?? {}) };
  (copy as any)[h] = setIn(obj?.[h as any], rest, value);
  return copy;
}

function pathKey(path: (string | number)[]) {
  return path.map((p) => (typeof p === 'number' ? p + 1 : p)).join('.');
}

function CoordsInput({ value, onChange, withHeading, disabled }: { value: any; onChange: (v: any) => void; withHeading: boolean; disabled: boolean }) {
  const v = value ?? {};
  const axes = withHeading ? ['x', 'y', 'z', 'w'] : ['x', 'y', 'z'];
  return (
    <div className="coords">
      {axes.map((a) => (
        <input key={a} type="number" step="0.01" disabled={disabled} value={v[a] ?? 0} title={a === 'w' ? 'heading' : a}
          onChange={(e) => onChange({ ...v, [a]: Number(e.target.value) })} />
      ))}
      <Button small disabled={disabled} onClick={async () => {
        const c = await captureCoords();
        if (!c) return toast('Could not read your position.', 'error');
        onChange(withHeading ? c : { x: c.x, y: c.y, z: c.z });
        toast('Captured your current position.', 'success');
      }}>Use my position</Button>
    </div>
  );
}

function MatrixEditor({ value, onChange, disabled, attractions }: { value: string[][]; onChange: (v: string[][]) => void; disabled: boolean; attractions: string[] }) {
  const rows = Array.isArray(value) ? value : [];
  return (
    <div className="table-wrap">
      <table className="table table-compact">
        <thead><tr><th>Round</th>{COLOURS.map((c) => <th key={c}>{c}</th>)}</tr></thead>
        <tbody>
          {rows.map((row, r) => (
            <tr key={r}>
              <td>{r + 1}</td>
              {COLOURS.map((_, i) => (
                <td key={i}>
                  <select disabled={disabled} value={row[i]} onChange={(e) => onChange(rows.map((rr, ri) => (ri === r ? rr.map((x, xi) => (xi === i ? e.target.value : x)) : rr)))}>
                    {attractions.map((a) => <option key={a} value={a}>{a}</option>)}
                  </select>
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      <div className="small muted">Each round needs six different attractions, and each colour must visit every attraction once.</div>
    </div>
  );
}

function ScalarEditor({ node, value, onChange, path, ctx }: { node: Node; value: any; onChange: (v: any) => void; path: (string | number)[]; ctx: Ctx }) {
  const disabled = !ctx.canEdit || (node.locked === true && ctx.liveLocked);
  const hidden = node.secret && value === undefined;
  if (hidden) return <input disabled value="(hidden — requires additional permission)" />;
  switch (node.type) {
    case 'bool':
      return <label className="toggle"><input type="checkbox" disabled={disabled} checked={!!value} onChange={(e) => onChange(e.target.checked)} /><span /></label>;
    case 'int': case 'number':
      return <input type="number" disabled={disabled} min={node.min} max={node.max} step={node.step ?? (node.type === 'int' ? 1 : 0.1)} value={value ?? ''}
        onChange={(e) => onChange(e.target.value === '' ? null : Number(e.target.value))} />;
    case 'text':
      return <textarea disabled={disabled} rows={3} maxLength={node.max} value={value ?? ''} onChange={(e) => onChange(e.target.value)} />;
    case 'select':
      return <select disabled={disabled} value={value ?? ''} onChange={(e) => onChange(e.target.value)}>{node.options?.map((o) => <option key={o} value={o}>{o.replace(/_/g, ' ')}</option>)}</select>;
    case 'multiselect': {
      const list: string[] = Array.isArray(value) ? value : [];
      const remaining = (node.options ?? []).filter((o) => !list.includes(o));
      return (
        <div className="multi">
          {list.map((o, i) => (
            <span key={o} className="multi-item">{i + 1}. {o.replace(/_/g, ' ')}
              <button disabled={disabled || i === 0} onClick={() => { const n = [...list]; [n[i - 1], n[i]] = [n[i], n[i - 1]]; onChange(n); }}>↑</button>
              <button disabled={disabled} onClick={() => onChange(list.filter((x) => x !== o))}>✕</button>
            </span>
          ))}
          {remaining.length ? <select disabled={disabled} value="" onChange={(e) => e.target.value && onChange([...list, e.target.value])}><option value="">Add…</option>{remaining.map((o) => <option key={o} value={o}>{o.replace(/_/g, ' ')}</option>)}</select> : null}
        </div>
      );
    }
    case 'vec3': return <CoordsInput value={value} onChange={onChange} withHeading={false} disabled={disabled} />;
    case 'vec4': return <CoordsInput value={value} onChange={onChange} withHeading disabled={disabled} />;
    case 'color':
      return <div className="inline-form"><input type="color" disabled={disabled} value={value ?? '#888888'} onChange={(e) => onChange(e.target.value)} /><input disabled={disabled} value={value ?? ''} onChange={(e) => onChange(e.target.value)} /></div>;
    case 'sound':
      return (
        <div className="inline-form">
          <select disabled={disabled} value={value ?? ''} onChange={(e) => onChange(e.target.value)}>{ctx.sounds.map((s) => <option key={s} value={s}>{s}</option>)}</select>
          <Button small onClick={() => playSound(value, 0.7)}>▶</Button>
        </div>
      );
    case 'matrix':
      return <MatrixEditor value={value} onChange={onChange} disabled={disabled} attractions={['shooting', 'wheel', 'fortune', 'puppets', 'deception', 'horror']} />;
    default:
      return <input disabled={disabled} maxLength={node.max ?? 255} value={value ?? ''} onChange={(e) => onChange(e.target.value)}
        placeholder={node.type === 'item' ? 'ox_inventory item name' : node.type === 'model' ? 'GTA model name' : ''} />;
  }
}

function NodeEditor({ node, value, onChange, path, ctx, depth = 0 }: { node: Node; value: any; onChange: (v: any) => void; path: (string | number)[]; ctx: Ctx; depth?: number }) {
  const err = ctx.errors[pathKey(path)];
  if (node.type === 'group') {
    return (
      <div className={`cfg-group depth-${depth}`}>
        {(node.fields ?? []).map((f) => (
          <NodeEditor key={f.key} node={f} value={value?.[f.key!]} path={[...path, f.key!]} ctx={ctx} depth={depth + 1}
            onChange={(v) => onChange({ ...(value ?? {}), [f.key!]: v })} />
        ))}
      </div>
    );
  }
  const title = node.label ?? node.key ?? '';
  const flags = <>{node.restart ? <span className="pill pill-warn" title="Takes full effect after a reset / next session">reset</span> : null}
    {node.locked ? <span className="pill pill-muted" title="Locked while the event is in progress">locked live</span> : null}
    {node.secret ? <span className="pill pill-bad">secret</span> : null}</>;
  if (node.type === 'map') {
    return (
      <details className="cfg-block" open={depth < 2}>
        <summary>{title} {flags}</summary>
        {(node.keys ?? []).map((k) => (
          <div key={k} className="cfg-map-item">
            <h5>{k}</h5>
            <NodeEditor node={node.item!} value={value?.[k]} path={[...path, k]} ctx={ctx} depth={depth + 1} onChange={(v) => onChange({ ...(value ?? {}), [k]: v })} />
          </div>
        ))}
      </details>
    );
  }
  if (node.type === 'list') {
    const list: any[] = Array.isArray(value) ? value : [];
    const scalar = node.item!.type !== 'group';
    const disabled = !ctx.canEdit || (node.locked === true && ctx.liveLocked);
    if (node.secret && value === undefined) return <Field label={title}><input disabled value="(hidden — requires additional permission)" /></Field>;
    return (
      <details className={`cfg-block ${err ? 'field-error' : ''}`} open={depth < 2 || list.length <= 3}>
        <summary>{title} <span className="muted small">({list.length}{node.max ? `/${node.max}` : ''})</span> {flags}</summary>
        {err ? <div className="field-msg">{err}</div> : null}
        {list.map((item, i) => (
          <div key={i} className={`cfg-list-item ${scalar ? 'cfg-list-scalar' : ''}`}>
            {scalar ? (
              <ScalarEditor node={node.item!} value={item} path={[...path, i]} ctx={ctx} onChange={(v) => onChange(list.map((x, xi) => (xi === i ? v : x)))} />
            ) : (
              <details open={false}>
                <summary>{i + 1}. {String(item?.[node.itemLabel ?? 'id'] ?? item?.id ?? '').slice(0, 80) || '(new)'} {ctx.errors && Object.keys(ctx.errors).some((k) => k.startsWith(pathKey([...path, i]) + '.')) ? <span className="pill pill-bad">error</span> : null}</summary>
                <NodeEditor node={node.item!} value={item} path={[...path, i]} ctx={ctx} depth={depth + 1} onChange={(v) => onChange(list.map((x, xi) => (xi === i ? v : x)))} />
              </details>
            )}
            <div className="cfg-list-actions">
              <button disabled={disabled || i === 0} onClick={() => { const n = [...list]; [n[i - 1], n[i]] = [n[i], n[i - 1]]; onChange(n); }} title="Move up">↑</button>
              <button disabled={disabled} onClick={() => onChange([...list.slice(0, i + 1), JSON.parse(JSON.stringify(item)), ...list.slice(i + 1)].map((x, xi) => (xi === i + 1 && x && typeof x === 'object' && 'id' in x ? { ...x, id: `${x.id}_copy` } : x)))} title="Duplicate">⧉</button>
              <button disabled={disabled} onClick={() => onChange(list.filter((_, xi) => xi !== i))} title="Remove">✕</button>
            </div>
          </div>
        ))}
        <Button small disabled={disabled || (node.max != null && list.length >= node.max)} onClick={() => {
          const d = defaultFor(node.item!);
          if (d && typeof d === 'object' && 'id' in d) d.id = `item_${list.length + 1}`;
          onChange([...list, d]);
        }}>+ Add</Button>
      </details>
    );
  }
  return (
    <Field label={title} hint={node.help} error={err}>
      <div className="field-row"><ScalarEditor node={node} value={value} onChange={onChange} path={path} ctx={ctx} />{flags}</div>
    </Field>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------
export function ConfigEditor({ section }: { section: string }) {
  const [scope, setScope] = useState<'global' | 'event'>('global');
  const st = useApi<any>('config.get', { scope }, [scope], ['config']);
  const [doc, setDoc] = useState<any>(null);
  const [dirty, setDirty] = useState(false);
  const [analysis, setAnalysis] = useState<any>(null);
  const [note, setNote] = useState('');
  const [showVersions, setShowVersions] = useState(false);
  const { busy, run } = useAction();

  useEffect(() => {
    if (st.data && !dirty) setDoc(st.data.data);
  }, [st.data]);

  const errors = useMemo(() => {
    const m: Record<string, string> = {};
    for (const e of analysis?.errors ?? []) m[e.path] = e.message;
    return m;
  }, [analysis]);

  if (st.loading && !st.data) return <Card title="Configuration"><Async state={st}>{() => null}</Async></Card>;
  if (!st.data) return <Card title="Configuration"><Async state={st}>{() => null}</Async></Card>;
  const d = st.data;
  const root: Node = d.schema;
  const [top, sub] = section.split('.');
  let node = root.fields!.find((f: Node) => f.key === top)!;
  let path: (string | number)[] = [top];
  if (sub && node?.fields) {
    node = node.fields.find((f: Node) => f.key === sub)!;
    path = [top, sub];
  }
  if (!node || !doc) return <Empty text="Unknown section." />;
  const value = path.reduce((v: any, k) => v?.[k as any], doc);
  const ctx: Ctx = { sounds: d.sounds, liveLocked: d.liveLocked, canEdit: d.canEdit, errors };

  const preview = async () => {
    const r = await api('config.preview', { scope, data: doc });
    if (r.ok) setAnalysis(r.data);
    else toast(errorText(r), 'error');
    return r.ok ? r.data : null;
  };

  const save = async (confirm = false) => {
    const r = await run<any>('config.save', { scope, data: doc, note, confirm });
    if (!r.ok) return;
    const res = r.data;
    if (res.saved) {
      toast(`Saved as version ${res.version}`, 'success');
      setDirty(false);
      setAnalysis(null);
      setNote('');
      st.reload();
    } else if (res.needsConfirm) {
      setAnalysis({ valid: true, errors: [], warnings: res.warnings, changes: res.changes });
      const ok = await confirmAction({
        title: 'Apply these changes?',
        message: <><p>{res.changes.length} setting(s) change.</p>{res.warnings.map((w: string, i: number) => <div key={i} className="pill pill-warn">{w}</div>)}</>,
        confirmLabel: 'Apply',
      });
      if (ok) save(true);
    } else if (res.analysis) {
      setAnalysis(res.analysis);
      toast(`${res.analysis.errors.length} validation error(s) — fix the highlighted fields.`, 'error');
    }
  };

  return (
    <div className="config-page">
      <div className="config-toolbar">
        <div className="inline-form">
          <label>Scope</label>
          <select value={scope} onChange={(e) => { if (dirty && !window.confirm('Discard unsaved changes?')) return; setDirty(false); setAnalysis(null); setScope(e.target.value as any); }}>
            <option value="global">Global defaults</option>
            <option value="event" disabled={!d.activeEventId}>This event only{d.activeEventId ? ` (#${d.activeEventId})` : ''}</option>
          </select>
          <span className="small muted">
            Active: {d.versions.source === 'event' ? `event v${d.versions.event?.version}` : `global v${d.versions.global?.version}`}
            {scope === 'event' && !d.hasEventOverride ? ' · saving creates an event-specific copy' : ''}
          </span>
          {d.liveLocked ? <span className="pill pill-warn">Event in progress — some fields are locked</span> : null}
          {!d.canEdit ? <span className="pill pill-muted">read-only</span> : null}
        </div>
        <div className="btn-row">
          <Button small onClick={() => setShowVersions(true)}>Versions</Button>
          {scope === 'event' && d.hasEventOverride && d.canEdit ? <Button small variant="danger" onClick={async () => {
            const r = await confirmAction({ title: 'Remove event-specific settings?', message: 'The event will follow the global settings again.', reason: 'required', danger: true });
            if (r) { await run('config.clearEventOverride', { reason: r.reason }, 'Event settings removed'); st.reload(); }
          }}>Use global settings</Button> : null}
          <Button small disabled={!dirty} onClick={() => { setDoc(d.data); setDirty(false); setAnalysis(null); }}>Discard</Button>
          <Button small disabled={!dirty} onClick={preview}>Preview changes</Button>
        </div>
      </div>

      <Card title={node.label ?? top}>
        <NodeEditor node={node} value={value} path={path} ctx={ctx} onChange={(v) => { setDoc(setIn(doc, path, v)); setDirty(true); }} />
      </Card>

      {analysis ? (
        <Card title={analysis.valid ? `Preview — ${analysis.changes.length} change(s)` : `${analysis.errors.length} validation error(s)`}>
          {analysis.errors.map((e: any, i: number) => <div key={i} className="state-error small">{e.path}: {e.message}</div>)}
          {(analysis.warnings ?? []).map((w: string, i: number) => <div key={i} className="pill pill-warn">{w}</div>)}
          {analysis.changes?.length ? (
            <Table compact head={['Setting', 'Before', 'After', '']}>
              {analysis.changes.map((c: any) => (
                <tr key={c.path}><td className="mono small">{c.path}</td><td className="small">{JSON.stringify(c.before)?.slice(0, 80)}</td><td className="small">{JSON.stringify(c.after)?.slice(0, 80)}</td>
                  <td>{c.restart ? <span className="pill pill-warn">reset</span> : null}{c.locked ? <span className="pill pill-muted">locked</span> : null}</td></tr>
              ))}
            </Table>
          ) : null}
        </Card>
      ) : null}

      {d.canEdit ? (
        <div className="save-bar">
          <input placeholder="Change note (recorded with the version)" maxLength={300} value={note} onChange={(e) => setNote(e.target.value)} />
          <Button variant="primary" busy={busy} disabled={!dirty} onClick={() => save(false)}>Save {scope === 'event' ? 'event' : 'global'} configuration</Button>
        </div>
      ) : null}
      {showVersions ? <VersionsModal scope={scope} onClose={() => setShowVersions(false)} onRolledBack={() => { setDirty(false); st.reload(); }} /> : null}
    </div>
  );
}

function VersionsModal({ scope, onClose, onRolledBack }: { scope: string; onClose: () => void; onRolledBack: () => void }) {
  const [page, setPage] = useState(1);
  const st = useApi<any>('config.versions', { scope, page }, [scope, page], ['config']);
  const { busy, run } = useAction();
  return (
    <Modal title={`${scope === 'event' ? 'Event' : 'Global'} configuration versions`} onClose={onClose} wide>
      <Async state={st} empty={(d) => (d.rows.length === 0 ? 'No versions yet.' : null)}>
        {(d) => (
          <>
            <Table head={['Version', 'Saved', 'By', 'Note', 'Status', '']}>
              {d.rows.map((v: any) => (
                <tr key={v.id}>
                  <td>v{v.version}{v.rollback_of ? <span className="small muted"> (rollback)</span> : null}</td>
                  <td className="small">{formatTime(v.created_at)}</td>
                  <td>{v.created_by_name ?? '—'}</td>
                  <td className="small">{v.note}</td>
                  <td>{v.is_active ? <StatusPill status="active" /> : null}</td>
                  <td>{!v.is_active ? <Button small busy={busy} onClick={async () => {
                    const r = await confirmAction({ title: `Roll back to v${v.version}?`, message: 'A new version is created with the old settings; nothing is deleted.', reason: 'optional', confirmLabel: 'Roll back' });
                    if (!r) return;
                    let res = await run<any>('config.rollback', { versionId: v.id, note: r.reason });
                    if (res.ok && res.data?.needsConfirm) {
                      if (await confirmAction({ title: 'This rollback changes settings that need a reset', message: <>{res.data.warnings.map((w: string, i: number) => <div key={i} className="pill pill-warn">{w}</div>)}</> })) {
                        res = await run<any>('config.rollback', { versionId: v.id, note: r.reason, confirm: true });
                      } else return;
                    }
                    if (res.ok && res.data?.saved) { toast(`Rolled back (new version v${res.data.version})`, 'success'); onRolledBack(); st.reload(); }
                    else if (res.ok && res.data?.analysis) toast(`Cannot roll back: ${res.data.analysis.errors[0]?.message}`, 'error');
                  }}>Roll back</Button> : null}</td>
                </tr>
              ))}
            </Table>
            <Pagination page={d.page} total={d.total} pageSize={d.pageSize} onPage={setPage} />
          </>
        )}
      </Async>
    </Modal>
  );
}

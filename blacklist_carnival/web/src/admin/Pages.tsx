import { useState } from 'react';
import { useStore } from '../store';
import {
  ATTRACTION_IDS, ATTRACTION_SHORT, STATE_LABELS, attractionLabel, formatClock, formatTime,
} from '../format';
import {
  Async, Button, Card, ColourChip, Countdown, Delta, Empty, Field, Modal, Pagination, Stat, StatusPill, Table, confirmAction, toast, useAction, useApi,
} from '../components/ui';
import { EventControls, ParticipantDetail, TransactionTable } from '../shared/Operations';
import { Icon } from '../components/Art';

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------
export function Dashboard() {
  const settings = useStore((s) => s.settings);
  const st = useApi<any>('admin.dashboard', {}, [], ['dashboard', 'rotation', 'scores', 'participants', 'rewards', 'config', 'events']);
  return (
    <Async state={st}>
      {(d) => {
        const e = d.event;
        const h = d.health;
        return (
          <div className="stack">
            <div className="stats">
              <Stat label="Event" value={e.active ? `#${e.id}` : 'none'} />
              <Stat label="State" value={e.active ? <StatusPill status={e.state} /> : '—'} />
              <Stat label="Registration" value={e.registrationOpen ? 'Open' : 'Closed'} tone={e.registrationOpen ? 'ok' : undefined} />
              <Stat label="Participants" value={d.participants ? `${d.participants.total}` : '0'} />
              <Stat label="Online" value={d.participants ? d.participants.online : 0} tone="ok" />
              <Stat label="Round" value={e.round ? `${e.round}/${e.totalRounds}` : '—'} />
              <Stat label="Round timer" value={e.roundEndsAt ? <Countdown endsAt={e.roundEndsAt} /> : e.roundRemaining != null ? <Countdown remaining={e.roundRemaining} /> : '—'} />
              <Stat label="Outstanding rewards" value={d.outstandingRewards} tone={d.outstandingRewards > 0 ? 'warn' : undefined} />
              <Stat label="Database" value={h.database.healthy ? 'Healthy' : 'ERROR'} tone={h.database.healthy ? 'ok' : 'blood'} />
              <Stat label="Config" value={h.config.source === 'event' ? `event v${h.config.event?.version}` : `global v${h.config.global?.version}`} />
              <Stat label="Resource" value={`v${h.resourceVersion}`} />
              <Stat label="Warnings / errors" value={`${h.counters.warning ?? 0} / ${(h.counters.error ?? 0) + (h.counters.critical ?? 0)}`} tone={(h.counters.error ?? 0) > 0 ? 'blood' : undefined} />
            </div>
            {e.active ? <Card title={e.name}><EventControls /></Card> : <Card title="No active event"><p>Create an event on the Events page.</p></Card>}
            <div className="grid-2">
              <Card title="Groups">
                {d.groups ? (
                  <Table compact head={['Group', 'Members', 'Online', 'Now', 'Done']}>
                    {d.groups.groups.filter((g: any) => g.enabled).map((g: any) => (
                      <tr key={g.colour}><td><ColourChip colour={g.colour} /></td><td>{g.members}/{g.capacity}</td><td>{g.online}</td>
                        <td>{g.current ? <>{attractionLabel(settings, g.current.attraction)} <StatusPill status={g.current.status} /></> : '—'}</td>
                        <td>{g.completed.filter((c: any) => c.status === 'completed').length}/6</td></tr>
                    ))}
                  </Table>
                ) : <Empty text="No event." />}
              </Card>
              <Card title="Attraction readiness">
                {d.attractions ? (
                  <Table compact head={['Attraction', 'Readiness', 'Group', 'Live']}>
                    {d.attractions.map((a: any) => (
                      <tr key={a.id}><td><Icon name={a.id} size={14} /> {a.label}</td><td><StatusPill status={a.readiness.status} /></td>
                        <td>{a.session ? <><ColourChip colour={a.session.colour} withLabel={false} /> <StatusPill status={a.session.status} /></> : '—'}</td>
                        <td className="small">{a.summary ? Object.entries(a.summary).map(([k, v]) => `${k}: ${v}`).join(' · ') : ''}</td></tr>
                    ))}
                  </Table>
                ) : <Empty text="No event." />}
              </Card>
              <Card title="Top 10">
                {d.leaderboard?.length ? (
                  <Table compact head={['#', 'Name', 'Group', 'Points']}>
                    {d.leaderboard.map((x: any) => <tr key={x.id}><td>{x.rank}</td><td>{x.name}</td><td><ColourChip colour={x.colour} withLabel={false} /></td><td className="num">{x.total}</td></tr>)}
                  </Table>
                ) : <Empty text="No scores yet." />}
              </Card>
              <Card title="Recent score transactions">
                {d.recentTransactions.length ? (
                  <Table compact head={['When', 'Who', 'Where', 'Δ', 'Source']}>
                    {d.recentTransactions.map((t: any) => <tr key={t.id}><td className="small">{formatClock(t.created_at)}</td><td>{t.display_name}</td><td>{ATTRACTION_SHORT[t.attraction_id] ?? 'General'}</td><td><Delta value={t.delta} /></td><td className="small">{t.source}</td></tr>)}
                  </Table>
                ) : <Empty text="None yet." />}
              </Card>
              <Card title="Recent staff actions">
                {d.recentStaffActions.length ? (
                  <ul className="feed">{d.recentStaffActions.map((a: any) => <li key={a.id}><span className="small muted">{formatClock(a.created_at)}</span> <strong>{a.actor_name ?? 'system'}</strong> {a.action.replace(/_/g, ' ')} {a.target_type ? <span className="small muted">{a.target_type} {a.target_id}</span> : null}</li>)}</ul>
                ) : <Empty text="None yet." />}
              </Card>
              <Card title="Recent warnings & errors">
                {d.recentProblems.length ? (
                  <ul className="feed">{d.recentProblems.map((p: any, i: number) => <li key={i}><span className="small muted">{formatClock(p.created_at)}</span> <StatusPill status={p.severity} /> {p.category}/{p.action} <span className="small muted">{p.details?.slice(0, 120)}</span></li>)}</ul>
                ) : <Empty text="All quiet." />}
              </Card>
            </div>
            <Card title="Resource health">
              <div className="health">
                <span>Ready: {h.ready ? 'yes' : 'no'}</span>
                <span>Uptime: {Math.floor(h.uptime / 60)} min</span>
                <span>Schema: v{h.schemaVersion}</span>
                <span>ox_inventory: {h.inventoryRunning ? 'running' : 'NOT RUNNING'}</span>
                <span>ox_target: {h.targetRunning ? 'running' : 'NOT RUNNING'}</span>
                <span>qbx_core: {h.qbxRunning ? 'running' : 'NOT RUNNING'}</span>
                <span>Discord: {h.discordEnabled ? 'enabled' : 'off'}</span>
                <span>DB last error: {h.database.lastError ? `${h.database.lastError.slice(0, 80)} (${formatTime(h.database.lastErrorAt)})` : 'none'}</span>
                <span>Players online: {h.onlinePlayers}</span>
              </div>
            </Card>
          </div>
        );
      }}
    </Async>
  );
}

// ---------------------------------------------------------------------------
// Events & history
// ---------------------------------------------------------------------------
function toEpoch(v: string): number | false { return v ? Math.floor(new Date(v).getTime() / 1000) : false; }
function fromEpoch(e?: number | null) {
  if (!e) return '';
  const d = new Date(e * 1000);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function EventForm({ initial, onSubmit, busy, submitLabel }: { initial?: any; onSubmit: (f: any) => void; busy: boolean; submitLabel: string }) {
  const [f, setF] = useState({
    name: initial?.name ?? '', description: initial?.description ?? '',
    registrationOpensAt: fromEpoch(initial?.registration_opens_at), registrationClosesAt: fromEpoch(initial?.registration_closes_at),
    scheduledStart: fromEpoch(initial?.scheduled_start), scheduledEnd: fromEpoch(initial?.scheduled_end),
  });
  return (
    <div className="form-grid">
      <Field label="Event name"><input maxLength={96} value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} /></Field>
      <Field label="Description"><textarea rows={3} maxLength={1000} value={f.description} onChange={(e) => setF({ ...f, description: e.target.value })} /></Field>
      <Field label="Registration opens (information)"><input type="datetime-local" value={f.registrationOpensAt} onChange={(e) => setF({ ...f, registrationOpensAt: e.target.value })} /></Field>
      <Field label="Registration closes (information)"><input type="datetime-local" value={f.registrationClosesAt} onChange={(e) => setF({ ...f, registrationClosesAt: e.target.value })} /></Field>
      <Field label="Scheduled start"><input type="datetime-local" value={f.scheduledStart} onChange={(e) => setF({ ...f, scheduledStart: e.target.value })} /></Field>
      <Field label="Scheduled end"><input type="datetime-local" value={f.scheduledEnd} onChange={(e) => setF({ ...f, scheduledEnd: e.target.value })} /></Field>
      <Button variant="primary" busy={busy} disabled={!f.name.trim()} onClick={() => onSubmit({
        name: f.name, description: f.description,
        registrationOpensAt: toEpoch(f.registrationOpensAt), registrationClosesAt: toEpoch(f.registrationClosesAt),
        scheduledStart: toEpoch(f.scheduledStart), scheduledEnd: toEpoch(f.scheduledEnd),
      })}>{submitLabel}</Button>
    </div>
  );
}

export function EventsPage() {
  const perms = useStore((s) => s.permissions);
  const event = useStore((s) => s.event);
  const [page, setPage] = useState(1);
  const [state, setStateFilter] = useState('');
  const [search, setSearch] = useState('');
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<any>(null);
  const [detail, setDetail] = useState<number | null>(null);
  const list = useApi<any>('events.list', { page, state: state || undefined, search: search || undefined }, [page, state, search], ['events']);
  const { busy, run } = useAction();

  return (
    <div className="stack">
      {event?.active ? (
        <Card title={`Active: ${event.name}`} actions={perms.has('events.manage') ? <Button small onClick={() => setEditing({ id: event.id })}>Edit details</Button> : null}>
          <EventControls />
          {perms.has('events.manage') ? (
            <div className="btn-row">
              <span className="small muted">Recovery tools:</span>
              {[['reload', 'Reload state from database'], ['force_pause', 'Force pause'], ['recheck_rewards', 'Flag interrupted reward deliveries']].map(([a, l]) => (
                <Button key={a} small busy={busy} onClick={async () => { const r = await confirmAction({ title: l, reason: 'required' }); if (r) run('events.recover', { action: a, reason: r.reason }, 'Recovery action done'); }}>{l}</Button>
              ))}
            </div>
          ) : null}
        </Card>
      ) : perms.has('events.manage') ? (
        <Card title="No active event" actions={<Button variant="gold" onClick={() => setCreating(true)}>Create event</Button>}>
          <p className="muted">Creating a new event never modifies earlier events.</p>
        </Card>
      ) : null}

      <Card title="Event history">
        <div className="filters">
          <input placeholder="Search name" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} />
          <select value={state} onChange={(e) => { setStateFilter(e.target.value); setPage(1); }}>
            <option value="">Any state</option>{Object.entries(STATE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </div>
        <Async state={list} empty={(d) => (d.rows.length === 0 ? 'No events yet.' : null)}>
          {(d) => (
            <>
              <Table head={['#', 'Name', 'State', 'Participants', 'Created', 'Started', 'Ended', '']}>
                {d.rows.map((e: any) => (
                  <tr key={e.id}>
                    <td>{e.id}</td><td>{e.name}</td><td><StatusPill status={e.state} /></td><td>{e.participant_count}</td>
                    <td className="small">{formatTime(e.created_at)}</td><td className="small">{formatTime(e.started_at)}</td><td className="small">{formatTime(e.ended_at)}</td>
                    <td className="btn-row">
                      <Button small onClick={() => setDetail(e.id)}>Open</Button>
                      {perms.has('events.manage') && !event?.active ? <Button small onClick={async () => {
                        const r = await confirmAction({ title: `Create a new event from #${e.id}?`, message: 'Copies the name, description and event-specific settings. The original event is untouched.' });
                        if (r) run('events.duplicate', { id: e.id }, 'Event created from template');
                      }}>Use as template</Button> : null}
                    </td>
                  </tr>
                ))}
              </Table>
              <Pagination page={d.page} total={d.total} pageSize={d.pageSize} onPage={setPage} />
            </>
          )}
        </Async>
      </Card>

      {creating ? (
        <Modal title="Create event" onClose={() => setCreating(false)}>
          <EventForm busy={busy} submitLabel="Create" onSubmit={async (f) => {
            const r = await run('events.create', f, 'Event created');
            if (r.ok) setCreating(false);
          }} />
        </Modal>
      ) : null}
      {editing ? <EditEvent id={editing.id} onClose={() => setEditing(null)} /> : null}
      {detail != null ? <EventDetail id={detail} onClose={() => setDetail(null)} /> : null}
    </div>
  );
}

function EditEvent({ id, onClose }: { id: number; onClose: () => void }) {
  const st = useApi<any>('events.get', { id }, [id]);
  const { busy, run } = useAction();
  return (
    <Modal title={`Edit event #${id}`} onClose={onClose}>
      <Async state={st}>
        {(d) => <EventForm initial={d.event} busy={busy} submitLabel="Save" onSubmit={async (f) => { const r = await run('events.update', { id, ...f }, 'Event updated'); if (r.ok) onClose(); }} />}
      </Async>
    </Modal>
  );
}

function EventDetail({ id, onClose }: { id: number; onClose: () => void }) {
  const perms = useStore((s) => s.permissions);
  const st = useApi<any>('events.get', { id }, [id], ['events', 'results']);
  const [version, setVersion] = useState<number | undefined>(undefined);
  const results = useApi<any>('results.get', { eventId: id, version }, [id, version], ['results']);
  const [exported, setExported] = useState<any>(null);
  const { busy, run } = useAction();
  const [participant, setParticipant] = useState<number | null>(null);
  return (
    <Modal title={`Event #${id}`} onClose={onClose} wide>
      <Async state={st}>
        {(d) => (
          <div className="stack">
            <div className="detail-head">
              <div><h3>{d.event.name}</h3><p className="small">{d.event.description}</p></div>
              <div><StatusPill status={d.event.state} /> <span className="small muted">{d.stats.participants} participants · {d.stats.transactions} score transactions · {d.stats.rewards} rewards</span></div>
            </div>
            {d.event.end_reason ? <div className="small">End reason: {d.event.end_reason}</div> : null}
            <Card title="Final results" actions={
              <div className="btn-row">
                {d.results.length > 1 ? <select value={version ?? ''} onChange={(e) => setVersion(e.target.value ? Number(e.target.value) : undefined)}>
                  <option value="">Latest version</option>{d.results.map((r: any) => <option key={r.id} value={r.version}>v{r.version} — {formatTime(r.frozen_at)}</option>)}
                </select> : null}
                {perms.has('export.history') && d.results.length ? <Button small busy={busy} onClick={async () => { const r = await run('results.export', { eventId: id }, 'Export ready'); if (r.ok) setExported(r.data); }}>Export</Button> : null}
              </div>
            }>
              {results.data?.results ? (
                <Table compact head={['#', 'Name', 'Group', 'Done', 'Points', 'Prize', '']}>
                  {results.data.results.entries.map((x: any) => (
                    <tr key={x.participantId}><td>{x.rank}{x.tied ? '=' : ''}</td><td>{x.name}</td><td><ColourChip colour={x.colour} withLabel={false} /></td><td>{x.completed}</td><td className="num">{x.total}</td><td>{x.prize ?? ''}</td>
                      <td><Button small onClick={() => setParticipant(x.participantId)}>Open</Button></td></tr>
                  ))}
                </Table>
              ) : <Empty text="No frozen results for this event." />}
              {results.data?.results ? <div className="small muted">Tie-break: {(results.data.results.tieBreak ?? []).join(' → ')} · frozen {formatTime(results.data.results.frozenAt)}</div> : null}
            </Card>
            {exported ? (
              <Card title={`Export (results v${exported.version})`}>
                <textarea className="mono" rows={8} readOnly value={exported.csv} onFocus={(e) => e.target.select()} />
                <div className="small muted">Select and copy (Ctrl+C). The export is recorded in the audit log.</div>
              </Card>
            ) : null}
            <Card title="State history">
              <Table compact head={['When', 'From', 'To', 'By', 'Reason']}>
                {d.transitions.map((t: any) => <tr key={t.id}><td className="small">{formatTime(t.created_at)}</td><td>{STATE_LABELS[t.from_state] ?? t.from_state}</td><td>{STATE_LABELS[t.to_state] ?? t.to_state}</td><td>{t.actor_name ?? t.actor}</td><td className="small">{t.reason}</td></tr>)}
              </Table>
            </Card>
            <Card title="Settings snapshots">
              {d.settingsSnapshots.length ? (
                <Table compact head={['When', 'Reason', 'Global version', 'Event version']}>
                  {d.settingsSnapshots.map((s: any) => <tr key={s.id}><td className="small">{formatTime(s.created_at)}</td><td>{s.reason}</td><td>{s.global_version ?? '—'}</td><td>{s.event_version ?? '—'}</td></tr>)}
                </Table>
              ) : <Empty text="No snapshots yet (taken at start, completion and cancellation)." />}
            </Card>
          </div>
        )}
      </Async>
      {participant != null ? <ParticipantDetail id={participant} onClose={() => setParticipant(null)} /> : null}
    </Modal>
  );
}

// ---------------------------------------------------------------------------
// Scores ledger
// ---------------------------------------------------------------------------
export function LedgerPage() {
  const perms = useStore((s) => s.permissions);
  const [page, setPage] = useState(1);
  const [attraction, setAttraction] = useState('');
  const [txType, setTxType] = useState('');
  const [participant, setParticipant] = useState('');
  const list = useApi<any>('scores.transactions', { page, attractionId: attraction || undefined, txType: txType || undefined, participantId: participant ? Number(participant) : undefined }, [page, attraction, txType, participant], ['scores']);
  const { busy, run } = useAction();
  const [report, setReport] = useState<any>(null);
  return (
    <div className="stack">
      <Card title="Score ledger" actions={perms.has('scores.adjust') ? <Button small busy={busy} onClick={async () => { const r = await run('scores.verify', {}); if (r.ok) { setReport(r.data); toast(r.data.ok ? 'Ledger verified — consistent' : 'Ledger mismatch found', r.data.ok ? 'success' : 'error'); } }}>Verify ledger</Button> : null}>
        {report ? (
          <div className={report.ok ? 'state-ok' : 'state-error'}>
            {report.ok ? `Consistent: ${report.transactions} transactions, totals and summaries match the ledger.` :
              `Mismatches — totals: ${report.totals.length}, summaries: ${report.summaries.length}, chain breaks: ${report.chains.length}. See the monitoring log (category score).`}
          </div>
        ) : null}
        <div className="filters">
          <input placeholder="Participant #id" value={participant} onChange={(e) => { setParticipant(e.target.value.replace(/\D/g, '')); setPage(1); }} />
          <select value={attraction} onChange={(e) => { setAttraction(e.target.value); setPage(1); }}><option value="">All attractions</option>{ATTRACTION_IDS.map((a) => <option key={a} value={a}>{ATTRACTION_SHORT[a]}</option>)}</select>
          <select value={txType} onChange={(e) => { setTxType(e.target.value); setPage(1); }}><option value="">All types</option>{['award', 'penalty', 'participation', 'bonus', 'adjustment', 'correction'].map((t) => <option key={t}>{t}</option>)}</select>
        </div>
        <Async state={list} empty={(d) => (d.rows.length === 0 ? 'No transactions.' : null)}>
          {(d) => (
            <>
              <TransactionTable rows={d.rows} canReverse={perms.has('scores.adjust')} onChanged={list.reload} />
              <Pagination page={d.page} total={d.total} pageSize={d.pageSize} onPage={setPage} />
            </>
          )}
        </Async>
      </Card>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Rewards reconciliation
// ---------------------------------------------------------------------------
export function RewardsPage() {
  const [page, setPage] = useState(1);
  const [status, setStatus] = useState('');
  const [outstanding, setOutstanding] = useState(true);
  const list = useApi<any>('rewards.list', { page, status: status || undefined, outstanding }, [page, status, outstanding], ['rewards']);
  const { busy, run } = useAction();
  const act = async (endpoint: string, id: number, title: string, reason: 'required' | 'optional' | undefined, ok: string) => {
    const r = await confirmAction({ title, reason });
    if (!r) return;
    await run(endpoint, { id, reason: r.reason }, ok);
    list.reload();
  };
  return (
    <Card title="Rewards & delivery reconciliation">
      <div className="filters">
        <label className="check"><input type="checkbox" checked={outstanding} onChange={(e) => { setOutstanding(e.target.checked); setPage(1); }} /> Outstanding only</label>
        <select value={status} onChange={(e) => { setStatus(e.target.value); setPage(1); }}>
          <option value="">Any status</option>{['pending', 'failed', 'unknown', 'awaiting_approval', 'approved', 'delivering', 'delivered', 'cancelled'].map((s) => <option key={s}>{s}</option>)}
        </select>
      </div>
      <p className="small muted">"unknown" means the server restarted mid-delivery: check the player's inventory, then mark delivered or reset to pending. Deliveries are never replayed automatically.</p>
      <Async state={list} empty={(d) => (d.rows.length === 0 ? 'Nothing to reconcile.' : null)}>
        {(d) => (
          <>
            <Table head={['#', 'Player', 'Item', 'Qty', 'Source', 'Status', 'Attempts', 'Last error', 'Updated', 'Actions']}>
              {d.rows.map((r: any) => (
                <tr key={r.id}>
                  <td>{r.id}</td><td>{r.display_name}</td><td>{r.item}</td><td>{r.count}</td><td className="small">{r.source}</td><td><StatusPill status={r.status} /></td>
                  <td>{r.attempts}</td><td className="small">{r.last_error ?? ''}</td><td className="small">{formatTime(r.updated_at)}</td>
                  <td className="btn-row">
                    {r.status === 'awaiting_approval' ? <Button small variant="gold" busy={busy} onClick={() => act('rewards.approve', r.id, 'Approve and deliver?', 'optional', 'Approved')}>Approve</Button> : null}
                    {['pending', 'failed', 'approved'].includes(r.status) ? <Button small busy={busy} onClick={() => act('rewards.retry', r.id, 'Retry delivery now?', undefined, 'Retry attempted')}>Retry</Button> : null}
                    {['unknown', 'failed'].includes(r.status) ? <Button small busy={busy} onClick={() => act('rewards.resetPending', r.id, 'Reset to pending?', 'required', 'Reset to pending')}>Reset</Button> : null}
                    {['pending', 'failed', 'unknown', 'approved'].includes(r.status) ? <Button small busy={busy} onClick={() => act('rewards.markDelivered', r.id, 'Mark as delivered manually?', 'required', 'Marked delivered')}>Mark delivered</Button> : null}
                    {!['delivered', 'cancelled', 'delivering'].includes(r.status) ? <Button small variant="danger" busy={busy} onClick={() => act('rewards.cancel', r.id, 'Cancel this reward?', 'required', 'Cancelled')}>Cancel</Button> : null}
                  </td>
                </tr>
              ))}
            </Table>
            <Pagination page={d.page} total={d.total} pageSize={d.pageSize} onPage={setPage} />
          </>
        )}
      </Async>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Monitoring centre & audit
// ---------------------------------------------------------------------------
function dateToEpoch(v: string) { return v ? Math.floor(new Date(v).getTime() / 1000) : undefined; }

export function MonitoringPage() {
  const [f, setF] = useState({ from: '', to: '', eventId: '', participantId: '', actor: '', attractionId: '', category: '', severity: '', minSeverity: '', search: '' });
  const [page, setPage] = useState(1);
  const [open, setOpen] = useState<any>(null);
  const payload = {
    page, pageSize: 50, from: dateToEpoch(f.from), to: dateToEpoch(f.to), eventId: f.eventId ? Number(f.eventId) : undefined,
    participantId: f.participantId ? Number(f.participantId) : undefined, actor: f.actor || undefined, attractionId: f.attractionId || undefined,
    category: f.category || undefined, severity: f.severity || undefined, minSeverity: f.minSeverity || undefined, search: f.search || undefined,
  };
  const st = useApi<any>('monitoring.query', payload, [JSON.stringify(payload)]);
  const set = (k: string, v: string) => { setF({ ...f, [k]: v }); setPage(1); };
  return (
    <Card title="Monitoring centre" actions={<Button small onClick={st.reload}>Refresh</Button>}>
      <div className="filters">
        <input type="datetime-local" value={f.from} onChange={(e) => set('from', e.target.value)} title="From" />
        <input type="datetime-local" value={f.to} onChange={(e) => set('to', e.target.value)} title="To" />
        <input placeholder="Event #" value={f.eventId} onChange={(e) => set('eventId', e.target.value.replace(/\D/g, ''))} />
        <input placeholder="Participant #" value={f.participantId} onChange={(e) => set('participantId', e.target.value.replace(/\D/g, ''))} />
        <input placeholder="Staff / actor" value={f.actor} onChange={(e) => set('actor', e.target.value)} />
        <select value={f.attractionId} onChange={(e) => set('attractionId', e.target.value)}><option value="">Any attraction</option>{ATTRACTION_IDS.map((a) => <option key={a} value={a}>{ATTRACTION_SHORT[a]}</option>)}</select>
        <select value={f.category} onChange={(e) => set('category', e.target.value)}><option value="">Any category</option>{(st.data?.categories ?? []).map((c: string) => <option key={c}>{c}</option>)}</select>
        <select value={f.minSeverity} onChange={(e) => set('minSeverity', e.target.value)}><option value="">Any severity</option>{['info', 'warning', 'error', 'critical'].map((s) => <option key={s} value={s}>{s}+</option>)}</select>
        <input placeholder="Search action/details" value={f.search} onChange={(e) => set('search', e.target.value)} />
      </div>
      <Async state={st} empty={(d) => (d.rows.length === 0 ? 'No records match.' : null)}>
        {(d) => (
          <>
            <Table compact head={['When', 'Severity', 'Category', 'Event', 'Attraction', 'Participant', 'Actor', 'Action', 'Result', '']}>
              {d.rows.map((r: any) => (
                <tr key={r.id}>
                  <td className="small">{formatTime(r.created_at)}</td><td><StatusPill status={r.severity} /></td><td>{r.category}</td><td>{r.event_id ?? ''}</td>
                  <td>{r.attraction_id ? ATTRACTION_SHORT[r.attraction_id] : ''}</td><td>{r.participant_id ?? ''}</td><td className="small">{r.actor_name ?? r.actor ?? ''}</td>
                  <td>{r.action}</td><td>{r.result ?? ''}</td><td>{r.details ? <Button small onClick={() => setOpen(r)}>Details</Button> : null}</td>
                </tr>
              ))}
            </Table>
            <Pagination page={d.page} total={d.total} pageSize={d.pageSize} onPage={setPage} />
          </>
        )}
      </Async>
      {open ? <Modal title={`${open.category}/${open.action}`} onClose={() => setOpen(null)}><pre className="mono pre">{(() => { try { return JSON.stringify(JSON.parse(open.details), null, 2); } catch { return open.details; } })()}</pre></Modal> : null}
    </Card>
  );
}

export function AuditPage() {
  const [f, setF] = useState({ from: '', to: '', eventId: '', actor: '', action: '', targetType: '', targetId: '' });
  const [page, setPage] = useState(1);
  const [open, setOpen] = useState<any>(null);
  const payload = { page, from: dateToEpoch(f.from), to: dateToEpoch(f.to), eventId: f.eventId ? Number(f.eventId) : undefined, actor: f.actor || undefined, action: f.action || undefined, targetType: f.targetType || undefined, targetId: f.targetId || undefined };
  const st = useApi<any>('audit.query', payload, [JSON.stringify(payload)]);
  const set = (k: string, v: string) => { setF({ ...f, [k]: v }); setPage(1); };
  return (
    <Card title="Administrative audit trail (append-only)">
      <div className="filters">
        <input type="datetime-local" value={f.from} onChange={(e) => set('from', e.target.value)} />
        <input type="datetime-local" value={f.to} onChange={(e) => set('to', e.target.value)} />
        <input placeholder="Event #" value={f.eventId} onChange={(e) => set('eventId', e.target.value.replace(/\D/g, ''))} />
        <input placeholder="Staff name / license" value={f.actor} onChange={(e) => set('actor', e.target.value)} />
        <input placeholder="Action contains" value={f.action} onChange={(e) => set('action', e.target.value)} />
        <input placeholder="Target type" value={f.targetType} onChange={(e) => set('targetType', e.target.value)} />
        <input placeholder="Target id" value={f.targetId} onChange={(e) => set('targetId', e.target.value)} />
      </div>
      <Async state={st} empty={(d) => (d.rows.length === 0 ? 'No audit records match.' : null)}>
        {(d) => (
          <>
            <Table compact head={['When', 'Staff', 'Action', 'Target', 'Event', 'Reason', '']}>
              {d.rows.map((r: any) => (
                <tr key={r.id}>
                  <td className="small">{formatTime(r.created_at)}</td><td>{r.actor_name ?? r.actor_license}</td><td>{r.action}</td>
                  <td className="small">{r.target_type ? `${r.target_type} ${r.target_id ?? ''}` : ''}</td><td>{r.event_id ?? ''}</td><td className="small">{r.reason ?? ''}</td>
                  <td>{r.details ? <Button small onClick={() => setOpen(r)}>Details</Button> : null}</td>
                </tr>
              ))}
            </Table>
            <Pagination page={d.page} total={d.total} pageSize={d.pageSize} onPage={setPage} />
          </>
        )}
      </Async>
      {open ? <Modal title={open.action} onClose={() => setOpen(null)}><pre className="mono pre">{(() => { try { return JSON.stringify(JSON.parse(open.details), null, 2); } catch { return open.details; } })()}</pre></Modal> : null}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Staff & roles
// ---------------------------------------------------------------------------
export function StaffPage() {
  const st = useApi<any>('staff.list', {}, [], ['staff']);
  const { busy, run } = useAction();
  const [grant, setGrant] = useState({ source: '', license: '', role: '', attractionId: '', eventScoped: false });
  return (
    <Async state={st}>
      {(d) => (
        <div className="stack">
          <Card title="Grant a role">
            {!d.allowGrants ? <p className="muted">In-game grants are disabled in config.lua (Config.Security.AllowDatabaseGrants).</p> : (
              <div className="form-grid">
                <Field label="Online player">
                  <select value={grant.source} onChange={(e) => setGrant({ ...grant, source: e.target.value, license: '' })}>
                    <option value="">— or enter a license below —</option>
                    {d.online.map((p: any) => <option key={p.source} value={p.source}>{p.name} (id {p.source}){p.role ? ` · ${p.role}` : ''}</option>)}
                  </select>
                </Field>
                <Field label="License identifier"><input placeholder="license:…" value={grant.license} disabled={!!grant.source} onChange={(e) => setGrant({ ...grant, license: e.target.value.trim() })} /></Field>
                <Field label="Role">
                  <select value={grant.role} onChange={(e) => setGrant({ ...grant, role: e.target.value })}>
                    <option value="">Choose…</option>{d.grantable.map((r: any) => <option key={r.id} value={r.id}>{r.label}</option>)}
                  </select>
                </Field>
                <Field label="Attraction assignment (operators / performers)">
                  <select value={grant.attractionId} onChange={(e) => setGrant({ ...grant, attractionId: e.target.value })}>
                    <option value="">None</option>{d.attractions.map((a: string) => <option key={a} value={a}>{ATTRACTION_SHORT[a]}</option>)}
                  </select>
                </Field>
                <label className="check"><input type="checkbox" checked={grant.eventScoped} onChange={(e) => setGrant({ ...grant, eventScoped: e.target.checked })} /> Only for the current event</label>
                <Button variant="primary" busy={busy} disabled={!grant.role || (!grant.source && !grant.license)} onClick={async () => {
                  const r = await confirmAction({ title: 'Grant this role?', reason: 'required' });
                  if (!r) return;
                  const res = await run('staff.grant', { source: grant.source ? Number(grant.source) : undefined, license: grant.source ? undefined : grant.license, role: grant.role, attractionId: grant.attractionId || undefined, eventScoped: grant.eventScoped, reason: r.reason }, 'Role granted');
                  if (res.ok) { setGrant({ source: '', license: '', role: '', attractionId: '', eventScoped: false }); st.reload(); }
                }}>Grant</Button>
                <p className="small muted">Owner and Administrator come only from config.lua or ACE and cannot be granted here. You can only grant roles below your own.</p>
              </div>
            )}
          </Card>
          <Card title="Assignments">
            {d.assignments.length === 0 ? <Empty text="No in-game assignments." /> : (
              <Table head={['#', 'Name', 'License', 'Role', 'Attraction', 'Event', 'Granted', 'Status', '']}>
                {d.assignments.map((a: any) => (
                  <tr key={a.id} className={a.revoked_at ? 'muted' : ''}>
                    <td>{a.id}</td><td>{a.display_name ?? '—'}</td><td className="mono small">{a.license}</td><td>{a.role}</td><td>{a.attraction_id ? ATTRACTION_SHORT[a.attraction_id] : '—'}</td>
                    <td>{a.event_id ?? 'all'}</td><td className="small">{formatTime(a.created_at)}</td>
                    <td>{a.revoked_at ? `revoked ${formatTime(a.revoked_at)}` : <StatusPill status="active" />}</td>
                    <td>{!a.revoked_at ? <Button small variant="danger" busy={busy} onClick={async () => {
                      const r = await confirmAction({ title: 'Revoke this role?', reason: 'required', danger: true });
                      if (r) { await run('staff.revoke', { id: a.id, reason: r.reason }, 'Role revoked'); st.reload(); }
                    }}>Revoke</Button> : null}</td>
                  </tr>
                ))}
              </Table>
            )}
          </Card>
          <Card title="Roles (from config.lua)">
            <ul className="plain">{d.roles.map((r: any) => <li key={r.id}><strong>{r.label}</strong> <span className="muted small">({r.id}, rank {r.rank})</span></li>)}</ul>
          </Card>
        </div>
      )}
    </Async>
  );
}

// ---------------------------------------------------------------------------
// System
// ---------------------------------------------------------------------------
export function SystemPage() {
  const items = useApi<any>('items.validate', {});
  return (
    <Card title="Inventory item check" actions={<Button small onClick={items.reload}>Re-check</Button>}>
      <Async state={items}>
        {(d) => (
          <>
            {!d.inventoryRunning ? <div className="state-error">ox_inventory is not running.</div> :
              d.ok ? <div className="state-ok">Every carnival and configured reward item is registered.</div> :
                <div className="state-error">Missing: {d.missing.join(', ')} — see docs/INSTALLATION.md.</div>}
            <Table compact head={['Item', 'Registered', 'Referenced by']}>
              {(d.checked ?? []).map((c: any, i: number) => <tr key={i}><td className="mono">{c.item}</td><td>{c.registered ? '✔' : '✘'}</td><td className="small">{c.path ?? 'resource item'}</td></tr>)}
            </Table>
          </>
        )}
      </Async>
    </Card>
  );
}

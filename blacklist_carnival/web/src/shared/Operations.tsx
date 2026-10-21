import { useState } from 'react';
import { useStore } from '../store';
import {
  ATTRACTION_IDS, ATTRACTION_SHORT, COLOURS, STATE_LABELS, TRANSITIONS, attractionLabel, colourHex, colourLabel, formatAgo, formatClock, formatTime,
} from '../format';
import {
  Async, Button, Card, ColourChip, Countdown, Delta, Empty, Field, Modal, Pagination, StatusPill, Table, confirmAction, toast, useAction, useApi,
} from '../components/ui';
import { Icon } from '../components/Art';
import { requestId } from '../nui';

// ---------------------------------------------------------------------------
// Event state & controls
// ---------------------------------------------------------------------------
const ACTION_LABELS: Record<string, string> = {
  paused: 'Pause', final_results: 'End the night', completed: 'Close the books', cancelled: 'Cancel', between_rounds: 'Between rounds',
};

const MANAGE_ONLY = new Set(['configuring', 'inactive', 'registration_open', 'registration_closed', 'ready', 'final_results', 'completed', 'cancelled']);

export function EventControls() {
  const e = useStore((s) => s.event);
  const perms = useStore((s) => s.permissions);
  const { busy, run } = useAction();
  if (!e?.active) return <Empty text="There is no active event." />;

  const go = async (to: string) => {
    const danger = to === 'cancelled';
    const res = await confirmAction({
      title: `${ACTION_LABELS[to] ?? STATE_LABELS[to]}?`, danger,
      message: to === 'final_results' ? (e.mode === 'walkup'
        ? 'Freezes tonight\'s leaderboard as the final results (prize tiers are delivered if enabled). Once you close the books, a fresh carnival opens and players buy new tickets.'
        : 'Ends the rotation and freezes the leaderboard as final results (prize tiers are delivered if enabled).') :
        to === 'cancelled' ? 'Cancelling stops every attraction. History is kept, but the event cannot be resumed.' :
          `Move the event from ${STATE_LABELS[e.state!]} to ${STATE_LABELS[to]}.`,
      reason: danger ? 'required' : 'optional',
      confirmLabel: ACTION_LABELS[to] ?? STATE_LABELS[to],
    });
    if (!res) return;
    await run('events.transition', { to, reason: res.reason }, `Event: ${STATE_LABELS[to]}`);
  };

  const options = (TRANSITIONS[e.state ?? ''] ?? []).filter((to) => {
    if (e.state === 'paused' && (to === 'running' || to === 'between_rounds')) return false; // use Resume
    if (e.mode === 'walkup' && to === 'between_rounds') return false; // walk-up carnivals have no rounds
    if (MANAGE_ONLY.has(to) || (to === 'running' && e.state === 'ready')) return perms.has('events.manage');
    return perms.has('events.operate') || perms.has('events.manage');
  });

  return (
    <div className="event-controls">
      <div className="event-state">
        <StatusPill status={e.state} />
        {e.round ? <span>Round {e.round}/{e.totalRounds}</span> : null}
        {e.roundEndsAt ? <span>Round ends in <Countdown endsAt={e.roundEndsAt} /></span> : null}
        {e.roundRemaining != null ? <span>Frozen at <Countdown remaining={e.roundRemaining} /></span> : null}
        {e.nextRoundAt ? <span>Next round in <Countdown endsAt={e.nextRoundAt} /></span> : null}
        {e.overtime ? <span className="pill pill-warn">overtime — waiting for a show or run to finish</span> : null}
        <span className="muted">{e.participantCount}/{e.maxParticipants} registered</span>
      </div>
      <div className="btn-row">
        {e.state === 'paused' && (perms.has('events.operate')) ? (
          <Button variant="primary" busy={busy} onClick={async () => {
            const r = await confirmAction({ title: 'Resume the event?', reason: 'optional', confirmLabel: 'Resume' });
            if (r) run('events.resume', { reason: r.reason }, 'Event resumed');
          }}>Resume</Button>
        ) : null}
        {options.map((to) => (
          <Button key={to} variant={to === 'cancelled' ? 'danger' : to === 'paused' ? 'default' : 'gold'} busy={busy} onClick={() => go(to)}>
            {ACTION_LABELS[to] ?? STATE_LABELS[to]}
          </Button>
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Rotation grid + per-group controls
// ---------------------------------------------------------------------------
export function RotationPanel() {
  const settings = useStore((s) => s.settings);
  const perms = useStore((s) => s.permissions);
  const state = useApi<any>('rotation.state', {}, [], ['rotation']);
  const { busy, run } = useAction();
  const canOperate = perms.has('events.operate');

  const groupAction = async (endpoint: string, colour: string, title: string, opts: { seconds?: boolean; reason?: 'required' | 'optional' } = {}) => {
    let seconds = 120;
    const res = await confirmAction({
      title, reason: opts.reason ?? 'required',
      extra: opts.seconds ? (
        <Field label="Seconds"><input type="number" min={10} max={3600} defaultValue={120} onChange={(e) => { seconds = Number(e.target.value); }} /></Field>
      ) : undefined,
    });
    if (!res) return;
    await run(endpoint, { colour, reason: res.reason, seconds }, 'Done');
    state.reload();
  };

  return (
    <Async state={state}>
      {(d) => d.walkup ? (
        <div className="rotation">
          {(d.walkupSessions ?? []).length === 0 ? <Empty text="Nobody is playing right now." /> : (
            <Table head={['Attraction', 'Players', 'Status', 'Started', '']}>
              {d.walkupSessions.map((w: any) => {
                const canComplete = canOperate;
                return (
                  <tr key={w.sessionId}>
                    <td><span className="cell-attraction"><Icon name={w.attraction} size={16} /> {ATTRACTION_SHORT[w.attraction] ?? attractionLabel(settings, w.attraction)}</span></td>
                    <td>{w.players.length === 0 ? '—' : w.players.map((p: any) => <span key={p.id} className="walkup-player"><ColourChip colour={p.colour} withLabel={false} /> {p.name}{p.online ? '' : <span className="muted"> (offline)</span>}</span>)}</td>
                    <td>{w.busy ? <span className="pill pill-gold">in play</span> : <span className="pill pill-muted">gathering</span>}</td>
                    <td className="muted">{formatAgo(w.startedAt, d.serverTime)}</td>
                    <td className="btn-row">
                      {canComplete ? <Button small busy={busy} onClick={async () => {
                        const r = await confirmAction({ title: 'Complete this visit for every player in it?', reason: 'optional' });
                        if (r) { await run('rotation.completeSession', { sessionId: w.sessionId, reason: r.reason }, 'Visit completed'); state.reload(); }
                      }}>Complete</Button> : null}
                    </td>
                  </tr>
                );
              })}
            </Table>
          )}
        </div>
      ) : (
        <div className="rotation">
          <div className="btn-row">
            {canOperate && d.roundState === 'active' ? (
              <>
                <Button busy={busy} onClick={async () => {
                  let seconds = 120;
                  const r = await confirmAction({ title: 'Extend the round', reason: 'required', extra: <Field label="Extra seconds"><input type="number" min={10} max={3600} defaultValue={120} onChange={(e) => { seconds = Number(e.target.value); }} /></Field> });
                  if (r) { await run('rotation.extend', { seconds, reason: r.reason }, 'Round extended'); state.reload(); }
                }}>Extend round</Button>
                <Button variant="danger" busy={busy} onClick={async () => {
                  const r = await confirmAction({ title: 'Force-advance the round?', danger: true, reason: 'required', message: 'Every unfinished group is marked complete now. Staff-judged attractions should be judged first.' });
                  if (r) { await run('rotation.advance', { reason: r.reason }, 'Round advanced'); state.reload(); }
                }}>Force-advance round</Button>
              </>
            ) : null}
            {canOperate && d.roundState === 'completed' && !d.allRoundsDone ? (
              <Button variant="gold" busy={busy} onClick={async () => {
                const r = await confirmAction({ title: 'Start the next round now?', reason: 'optional' });
                if (r) { await run('rotation.advance', { reason: r.reason || 'Started manually' }, 'Next round started'); state.reload(); }
              }}>Start next round now</Button>
            ) : null}
            {d.allRoundsDone ? <span className="pill pill-gold">All rounds complete — move the event to Final results</span> : null}
          </div>

          <div className="table-wrap">
            <table className="table rotation-grid">
              <thead>
                <tr><th>Round</th>{COLOURS.map((c) => <th key={c}><ColourChip colour={c} /></th>)}</tr>
              </thead>
              <tbody>
                {(d.grid ?? []).map((row: any, i: number) => (
                  <tr key={i} className={d.round === i + 1 ? 'row-current' : ''}>
                    <td>{i + 1}</td>
                    {COLOURS.map((c) => {
                      const cell = row[c];
                      const enabled = (d.enabledColours ?? []).includes(c);
                      return (
                        <td key={c} className={!enabled ? 'muted' : ''}>
                          <div className="cell-attraction"><Icon name={cell.attraction} size={14} /> {ATTRACTION_SHORT[cell.attraction]}</div>
                          {enabled ? <StatusPill status={cell.status} /> : <span className="small">disabled</span>}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <h4>Current round</h4>
          {(d.current ?? []).length === 0 ? <Empty text="No round in progress." /> : (
            <Table head={['Group', 'Attraction', 'Status', 'Players', 'Readiness', 'Actions']}>
              {d.current.map((g: any) => {
                const canComplete = canOperate;
                return (
                  <tr key={g.colour}>
                    <td><ColourChip colour={g.colour} /></td>
                    <td>{attractionLabel(settings, g.attraction)}</td>
                    <td><StatusPill status={g.status} />{g.delayedUntil ? <span className="small"> until {formatClock(g.delayedUntil)}</span> : null}</td>
                    <td>{g.online}/{g.members} online</td>
                    <td><StatusPill status={g.readiness?.status} /></td>
                    <td className="btn-row">
                      {g.status === 'pending' && canOperate ? <Button small variant="gold" onClick={() => groupAction('rotation.activate', g.colour, `Open ${ATTRACTION_SHORT[g.attraction]} for ${g.colour}`, { reason: 'optional' })}>Open</Button> : null}
                      {(g.status === 'active' || g.status === 'pending') && canComplete ? <Button small onClick={() => groupAction('rotation.completeSession', g.colour, 'Mark this group complete?', { reason: 'optional' })}>Complete</Button> : null}
                      {(g.status === 'active' || g.status === 'pending') && canOperate ? <Button small onClick={() => groupAction('rotation.delay', g.colour, 'Delay this group', { seconds: true })}>Delay</Button> : null}
                      {(g.status === 'active' || g.status === 'pending') && canOperate ? <Button small variant="danger" onClick={() => groupAction('rotation.skip', g.colour, 'Skip this attraction for the group?')}>Skip</Button> : null}
                    </td>
                  </tr>
                );
              })}
            </Table>
          )}
        </div>
      )}
    </Async>
  );
}

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------
export function GroupsPanel() {
  const settings = useStore((s) => s.settings);
  const st = useApi<any>('groups.overview', {}, [], ['participants', 'rotation']);
  return (
    <Async state={st}>
      {(d) => (
        <div className="groups">
          {d.groups.map((g: any) => (
            <div key={g.colour} className={`group-tile ${g.enabled ? '' : 'muted'}`} style={{ borderColor: g.hex }}>
              <div className="group-name" style={{ color: g.hex }}>{g.label}</div>
              <div className="group-count">{g.members}<span>/{g.capacity}</span></div>
              <div className="small">{g.online} online</div>
              <div className="small">Now: {g.current ? `${attractionLabel(settings, g.current.attraction)} (${g.current.status})` : '—'}</div>
              <div className="small">Next: {g.next ? attractionLabel(settings, g.next) : '—'}</div>
              <div className="small">Done: {g.completed.filter((c: any) => c.status === 'completed').length}/6</div>
            </div>
          ))}
          {d.unassigned > 0 ? <div className="pill pill-warn">{d.unassigned} participant(s) without a group</div> : null}
        </div>
      )}
    </Async>
  );
}

// ---------------------------------------------------------------------------
// Participants
// ---------------------------------------------------------------------------
export function ParticipantsPanel({ eventId }: { eventId?: number }) {
  const perms = useStore((s) => s.permissions);
  const [query, setQuery] = useState('');
  const [colour, setColour] = useState('');
  const [status, setStatus] = useState('');
  const [sort, setSort] = useState('id');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<number | null>(null);
  const [registering, setRegistering] = useState(false);
  const list = useApi<any>('participants.search', { query, colour: colour || undefined, status: status || undefined, page, sort, eventId }, [query, colour, status, page, sort, eventId], ['participants', 'scores']);

  return (
    <div>
      <div className="filters">
        <input placeholder="Search name, citizen id or #id" value={query} onChange={(e) => { setQuery(e.target.value); setPage(1); }} />
        <select value={colour} onChange={(e) => { setColour(e.target.value); setPage(1); }}>
          <option value="">All colours</option>{COLOURS.map((c) => <option key={c} value={c}>{c}</option>)}
        </select>
        <select value={status} onChange={(e) => { setStatus(e.target.value); setPage(1); }}>
          <option value="">Any status</option><option value="active">Active</option><option value="removed">Removed</option>
        </select>
        <select value={sort} onChange={(e) => setSort(e.target.value)}><option value="id">Registration order</option><option value="score">Score</option></select>
        {perms.has('participants.manage') && !eventId ? <Button onClick={() => setRegistering(true)}>Register a player</Button> : null}
      </div>
      <Async state={list} empty={(d) => (d.rows.length === 0 ? 'No participants match.' : null)}>
        {(d) => (
          <>
            <Table head={['#', 'Name', 'Group', 'Status', 'Points', 'Online', 'Last seen', '']}>
              {d.rows.map((p: any) => (
                <tr key={p.id}>
                  <td>{p.id}</td>
                  <td>{p.display_name}</td>
                  <td><ColourChip colour={p.colour} /></td>
                  <td><StatusPill status={p.status} /></td>
                  <td className="num">{p.total_score}</td>
                  <td>{p.online ? '●' : '○'}</td>
                  <td className="small">{formatTime(p.last_seen_at)}</td>
                  <td><Button small onClick={() => setSelected(p.id)}>Open</Button></td>
                </tr>
              ))}
            </Table>
            <Pagination page={d.page} total={d.total} pageSize={d.pageSize} onPage={setPage} />
          </>
        )}
      </Async>
      {selected != null ? <ParticipantDetail id={selected} onClose={() => { setSelected(null); list.reload(); }} /> : null}
      {registering ? <RegisterPlayer onClose={() => { setRegistering(false); list.reload(); }} /> : null}
    </div>
  );
}

function RegisterPlayer({ onClose }: { onClose: () => void }) {
  const online = useApi<any[]>('participants.unregisteredOnline', {});
  const [source, setSource] = useState('');
  const [colour, setColour] = useState('');
  const { busy, run } = useAction();
  return (
    <Modal title="Register an online player" onClose={onClose} footer={
      <Button variant="primary" busy={busy} disabled={!source} onClick={async () => {
        const r = await run('participants.registerPlayer', { source: Number(source), colour: colour || undefined }, 'Player registered');
        if (r.ok) onClose();
      }}>Register</Button>
    }>
      <Async state={online} empty={(d) => (d.length === 0 ? 'Every online player is already registered.' : null)}>
        {(list) => (
          <>
            <Field label="Player">
              <select value={source} onChange={(e) => setSource(e.target.value)}>
                <option value="">Choose…</option>
                {list.map((p) => <option key={p.source} value={p.source}>{p.name} (id {p.source})</option>)}
              </select>
            </Field>
            <Field label="Group (blank = automatic allocation)">
              <select value={colour} onChange={(e) => setColour(e.target.value)}>
                <option value="">Automatic</option>{COLOURS.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
            </Field>
          </>
        )}
      </Async>
    </Modal>
  );
}

export function ParticipantDetail({ id, onClose }: { id: number; onClose: () => void }) {
  const perms = useStore((s) => s.permissions);
  const st = useApi<any>('participants.get', { id }, [id], ['participants', 'scores', 'rewards']);
  const { busy, run } = useAction();
  const [colour, setColour] = useState('');
  const [delta, setDelta] = useState('');
  const [attraction, setAttraction] = useState('');

  return (
    <Modal title={`Participant #${id}`} onClose={onClose} wide>
      <Async state={st}>
        {(d) => {
          const p = d.participant;
          return (
            <div className="detail">
              <div className="detail-head">
                <div>
                  <h3>{p.display_name}</h3>
                  <div className="small muted">citizen {p.citizenid}{p.license ? ` · ${p.license}` : ''} · registered {formatTime(p.registered_at)}</div>
                </div>
                <div className="btn-row">
                  <ColourChip colour={p.colour} /><StatusPill status={p.status} /><span className="pill pill-gold">{p.total_score} pts</span>
                  <span className="pill">{d.online ? 'online' : 'offline'}</span>
                </div>
              </div>

              {perms.has('participants.manage') ? (
                <div className="detail-actions">
                  <div className="inline-form">
                    <select value={colour} onChange={(e) => setColour(e.target.value)}>
                      <option value="">Move to group…</option>{COLOURS.filter((c) => c !== p.colour).map((c) => <option key={c} value={c}>{c}</option>)}
                    </select>
                    <Button small busy={busy} disabled={!colour} onClick={async () => {
                      const r = await confirmAction({ title: `Move to ${colour}?`, message: 'A new ticket in the new colour is issued and the old one voided.', reason: 'required' });
                      if (r) { await run('participants.reassign', { id, colour, reason: r.reason }, 'Group changed'); st.reload(); }
                    }}>Transfer</Button>
                  </div>
                  <Button small busy={busy} onClick={async () => {
                    const r = await confirmAction({ title: 'Replace this ticket?', message: 'The current serial is voided and removed from their inventory if present.', reason: 'required' });
                    if (r) { await run('tickets.replace', { participantId: id, reason: r.reason }, 'Ticket replaced'); st.reload(); }
                  }}>Replace ticket</Button>
                  <Button small busy={busy} onClick={async () => { await run('tickets.deliver', { participantId: id }, 'Delivery attempted'); st.reload(); }}>Retry ticket delivery</Button>
                  {p.status === 'active' ? (
                    <Button small variant="danger" busy={busy} onClick={async () => {
                      const r = await confirmAction({ title: 'Remove from the event?', danger: true, reason: 'required' });
                      if (r) { await run('participants.remove', { id, reason: r.reason }, 'Participant removed'); st.reload(); }
                    }}>Remove</Button>
                  ) : (
                    <Button small variant="gold" busy={busy} onClick={async () => {
                      const r = await confirmAction({ title: 'Reinstate this participant?', reason: 'required' });
                      if (r) { await run('participants.reinstate', { id, reason: r.reason }, 'Participant reinstated'); st.reload(); }
                    }}>Reinstate</Button>
                  )}
                </div>
              ) : null}

              {perms.has('scores.adjust') ? (
                <div className="inline-form">
                  <input type="number" placeholder="± points" value={delta} onChange={(e) => setDelta(e.target.value)} />
                  <select value={attraction} onChange={(e) => setAttraction(e.target.value)}>
                    <option value="">General</option>{ATTRACTION_IDS.map((a) => <option key={a} value={a}>{ATTRACTION_SHORT[a]}</option>)}
                  </select>
                  <Button small busy={busy} disabled={!delta || Number(delta) === 0} onClick={async () => {
                    const r = await confirmAction({ title: `Adjust score by ${delta}?`, reason: 'required' });
                    if (r) {
                      const res = await run('scores.adjust', { participantId: id, delta: Number(delta), reason: r.reason, requestId: requestId(), attractionId: attraction || undefined }, 'Score adjusted');
                      if (res.ok) { setDelta(''); st.reload(); }
                    }
                  }}>Adjust score</Button>
                </div>
              ) : null}

              <div className="detail-grid">
                <Card title="Points by attraction">
                  {d.breakdown.length === 0 ? <Empty text="No points yet." /> : (
                    <Table compact head={['Attraction', 'Points', '+', '−', 'Tx']}>
                      {d.breakdown.map((b: any) => <tr key={b.attraction_id}><td>{ATTRACTION_SHORT[b.attraction_id] ?? b.attraction_id}</td><td className="num">{b.points}</td><td className="num">{b.positive}</td><td className="num">{b.negative}</td><td className="num">{b.tx_count}</td></tr>)}
                    </Table>
                  )}
                </Card>
                <Card title="Attractions completed">
                  {d.participation.length === 0 ? <Empty text="None yet." /> : (
                    <ul className="plain">{d.participation.map((x: any) => <li key={x.id}><Icon name={x.attraction_id} size={14} /> {ATTRACTION_SHORT[x.attraction_id]} — <StatusPill status={x.status} /> {formatClock(x.completed_at)}</li>)}</ul>
                  )}
                </Card>
                <Card title="Tickets">
                  <Table compact head={['Serial', 'Colour', 'Status', 'Issued', 'Note']}>
                    {d.tickets.map((t: any) => <tr key={t.id}><td className="mono">{t.serial}</td><td><ColourChip colour={t.colour} withLabel={false} /></td><td><StatusPill status={t.status} /></td><td className="small">{formatTime(t.issued_at)}</td><td className="small">{t.invalidated_reason ?? t.delivery_error ?? t.issue_reason ?? ''}</td></tr>)}
                  </Table>
                </Card>
                <Card title="Group history">
                  <Table compact head={['When', 'From', 'To', 'How', 'Reason']}>
                    {d.groups.map((g: any) => <tr key={g.id}><td className="small">{formatTime(g.created_at)}</td><td>{g.from_colour ?? '—'}</td><td>{g.to_colour ?? '—'}</td><td>{g.method}</td><td className="small">{g.reason}</td></tr>)}
                  </Table>
                </Card>
                <Card title="Rewards">
                  {d.rewards.length === 0 ? <Empty text="No rewards." /> : (
                    <Table compact head={['Item', 'Qty', 'Source', 'Status', 'Error']}>
                      {d.rewards.map((r: any) => <tr key={r.id}><td>{r.item}</td><td>{r.count}</td><td>{r.source}</td><td><StatusPill status={r.status} /></td><td className="small">{r.last_error ?? ''}</td></tr>)}
                    </Table>
                  )}
                </Card>
              </div>
              {d.transactions.length > 0 ? (
                <Card title="Score ledger">
                  <TransactionTable rows={d.transactions} canReverse={perms.has('scores.adjust')} onChanged={st.reload} />
                </Card>
              ) : null}
            </div>
          );
        }}
      </Async>
    </Modal>
  );
}

export function TransactionTable({ rows, canReverse, onChanged }: { rows: any[]; canReverse?: boolean; onChanged?: () => void }) {
  const { run } = useAction();
  return (
    <Table compact head={['#', 'When', 'Who', 'Attraction', 'Δ', 'Total', 'Type', 'Source / reason', 'Staff', '']}>
      {rows.map((t) => (
        <tr key={t.id}>
          <td>{t.id}</td>
          <td className="small">{formatClock(t.created_at)}</td>
          <td>{t.display_name ?? `#${t.participant_id}`}</td>
          <td>{t.attraction_id ? ATTRACTION_SHORT[t.attraction_id] : 'General'}</td>
          <td className="num"><Delta value={t.delta} />{t.requested_delta != null && t.requested_delta !== t.delta ? <span className="small muted"> (req {t.requested_delta})</span> : null}</td>
          <td className="num">{t.resulting_total}</td>
          <td>{t.tx_type}{t.reverses_tx ? ` ↺#${t.reverses_tx}` : ''}</td>
          <td className="small">{t.source}{t.reason ? ` — ${t.reason}` : ''}</td>
          <td className="small">{t.staff_name ?? ''}</td>
          <td>{canReverse && !t.reverses_tx && t.delta !== 0 ? <Button small onClick={async () => {
            const r = await confirmAction({ title: `Reverse transaction #${t.id}?`, message: 'A correction entry is added; the original stays in the ledger.', reason: 'required' });
            if (r) { const res = await run('scores.reverse', { txId: t.id, reason: r.reason }, 'Correction recorded'); if (res.ok) onChanged?.(); }
          }}>Reverse</Button> : null}</td>
        </tr>
      ))}
    </Table>
  );
}

// ---------------------------------------------------------------------------
// Leaderboard (admin view)
// ---------------------------------------------------------------------------
export function StaffLeaderboard() {
  const st = useApi<any>('leaderboard.staff', {}, [], ['scores', 'participants']);
  const [detail, setDetail] = useState<number | null>(null);
  return (
    <Async state={st} empty={(d) => (d.entries.length === 0 ? 'No participants yet.' : null)}>
      {(d) => (
        <>
          <div className="small muted">Tie-break order: total → {d.tieBreak.join(' → ')} → id</div>
          <Table head={['#', 'Name', 'Group', ...ATTRACTION_IDS.map((a) => ATTRACTION_SHORT[a]), 'Done', 'Deductions', 'Gold', 'Total', '']}>
            {d.entries.map((e: any) => (
              <tr key={e.id}>
                <td>{e.rank}{e.tied ? '=' : ''}</td>
                <td>{e.name} {e.online ? '●' : ''}</td>
                <td><ColourChip colour={e.colour} withLabel={false} /></td>
                {ATTRACTION_IDS.map((a) => <td key={a} className="num muted">{e.breakdown?.[a] ?? 0}</td>)}
                <td>{e.completed}</td><td>{e.deductions}</td><td>{e.goldTokens}</td>
                <td className="num strong">{e.total}</td>
                <td><Button small onClick={() => setDetail(e.id)}>Open</Button></td>
              </tr>
            ))}
          </Table>
          {detail != null ? <ParticipantDetail id={detail} onClose={() => setDetail(null)} /> : null}
        </>
      )}
    </Async>
  );
}

export function useColourStyle(colour?: string | null) {
  const settings = useStore((s) => s.settings);
  return { color: colourHex(settings, colour), label: colourLabel(settings, colour) };
}

export { toast };

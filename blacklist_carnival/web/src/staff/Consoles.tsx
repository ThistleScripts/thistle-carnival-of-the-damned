import React, { useEffect, useState } from 'react';
import { useStore } from '../store';
import { ATTRACTION_SHORT, formatClock, signed } from '../format';
import {
  Async, Button, Card, ColourChip, Countdown, Empty, Field, Modal, StatusPill, Table, confirmAction, toast, useAction, useApi,
} from '../components/ui';
import { api, requestId } from '../nui';
import { errorText } from '../i18n';

function SessionLine({ session }: { session: any }) {
  if (!session) return <div className="pill pill-muted">No group scheduled here this round</div>;
  return <div className="session-line">Group <ColourChip colour={session.colour} /> · round {session.round_number} · <StatusPill status={session.status} /></div>;
}

// ---------------------------------------------------------------------------
// Shooting Gallery
// ---------------------------------------------------------------------------
export function ShootingConsole() {
  const st = useApi<any>('shooting.staff.state', {}, [], ['shooting', 'rotation']);
  const { busy, run } = useAction();
  return (
    <Async state={st}>
      {(d) => (
        <div className="console">
          <SessionLine session={d.session} />
          <div className="small muted">Self-service: players target the gallery ped and play the aim game themselves. This page is for monitoring.</div>
          <div className="console-grid">
            <Card title={`Playing now (${d.live.length})`}>
              {d.live.length === 0 ? <Empty text="Nobody is shooting right now." /> : (
                <Table compact head={['Player', 'Score', 'Hits/Shots', 'Rejected', 'Time left']}>
                  {d.live.map((g: any) => <tr key={g.id}><td>{g.name}</td><td className="num">{g.points}</td><td>{g.hits}/{g.shots}</td><td>{g.rejected}</td><td>{g.remaining}s</td></tr>)}
                </Table>
              )}
            </Card>
            <Card title="Group">
              {d.members.length === 0 ? <Empty text="No group here." /> : (
                <Table compact head={['Name', 'Played', 'Points', '']}>
                  {d.members.map((m: any) => (
                    <tr key={m.id}><td>{m.name}{m.online ? '' : ' (offline)'}</td><td>{m.played}/{d.playsPerVisit}</td><td className="num">{m.points}</td>
                      <td>{m.played > 0 ? <Button small busy={busy} onClick={async () => {
                        const r = await confirmAction({ title: `Give ${m.name} another go?`, message: 'Their earlier score stays; they may play again this visit.', reason: 'required' });
                        if (r) { await run('shooting.allowReplay', { participantId: m.id, reason: r.reason }, 'Replay allowed'); st.reload(); }
                      }}>Allow replay</Button> : null}</td></tr>
                  ))}
                </Table>
              )}
            </Card>
            <Card title="Recent results" className="span-2">
              {d.recent.length === 0 ? <Empty text="No results yet." /> : (
                <Table compact head={['Name', 'Hits/Shots', 'Bull', 'Golden', 'Acc+', 'Rejected', 'Points']}>
                  {d.recent.map((r: any) => <tr key={r.id}><td>{r.display_name}</td><td>{r.hits}/{r.shots}</td><td>{r.bullseyes}</td><td>{r.specials}</td><td>{r.accuracy_bonus}</td><td>{r.rejected_hits}</td><td className="num">{r.points}</td></tr>)}
                </Table>
              )}
            </Card>
          </div>
        </div>
      )}
    </Async>
  );
}

// ---------------------------------------------------------------------------
// Wheel of Misfortune
// ---------------------------------------------------------------------------
export function WheelConsole() {
  const st = useApi<any>('wheel.staff.state', {}, [], ['wheel', 'rewards', 'rotation']);
  const { busy, run } = useAction();
  return (
    <Async state={st}>
      {(d) => (
        <div className="console">
          <SessionLine session={d.session} />
          <div className="console-grid">
            <Card title={`Awaiting approval (${d.approvals.length})`}>
              {d.approvals.length === 0 ? <Empty text="No special prizes waiting." /> : (
                <Table compact head={['Player', 'Prize', 'When', '']}>
                  {d.approvals.map((a: any) => (
                    <tr key={a.id}>
                      <td>{a.display_name}</td><td>{a.count}x {a.item}</td><td className="small">{formatClock(a.created_at)}</td>
                      <td className="btn-row">
                        <Button small variant="gold" busy={busy} onClick={() => run('wheel.staff.approve', { rewardId: a.id }, 'Approved and delivered').then(st.reload)}>Approve</Button>
                        <Button small variant="danger" busy={busy} onClick={async () => { const r = await confirmAction({ title: 'Reject this prize?', reason: 'required', danger: true }); if (r) { await run('wheel.staff.approve', { rewardId: a.id, reject: true, reason: r.reason }, 'Rejected'); st.reload(); } }}>Reject</Button>
                      </td>
                    </tr>
                  ))}
                </Table>
              )}
            </Card>
            <Card title="Group spins">
              {d.members.length === 0 ? <Empty text="No group here." /> : (
                <Table compact head={['Name', 'Spins']}>
                  {d.members.map((m: any) => <tr key={m.id}><td>{m.name}{m.online ? '' : ' (offline)'}</td><td>{m.spins}/{d.maxSpins}</td></tr>)}
                </Table>
              )}
            </Card>
            <Card title="Recent spins" className="span-2">
              {d.spins.length === 0 ? <Empty text="No spins yet." /> : (
                <Table compact head={['When', 'Player', '#', 'Outcome', 'Points', 'Reward']}>
                  {d.spins.map((s: any) => (
                    <tr key={s.id}><td className="small">{formatClock(s.created_at)}</td><td>{s.display_name}</td><td>{s.spin_number}</td><td>{s.outcome_label}</td><td className="num">{signed(s.points)}</td>
                      <td>{s.item ? <>{s.item_count}x {s.item} <StatusPill status={s.reward_status} /></> : '—'}</td></tr>
                  ))}
                </Table>
              )}
            </Card>
          </div>
        </div>
      )}
    </Async>
  );
}

// ---------------------------------------------------------------------------
// Fortune Teller
// ---------------------------------------------------------------------------
export function FortuneConsole() {
  const st = useApi<any>('fortune.staff.state', {}, [], ['fortune', 'rotation']);
  const { busy, run } = useAction();
  const [target, setTarget] = useState('');
  const [question, setQuestion] = useState('');
  const [fortune, setFortune] = useState('');
  const [custom, setCustom] = useState('');
  const [points, setPoints] = useState('');
  const [reason, setReason] = useState('');
  return (
    <Async state={st}>
      {(d) => (
        <div className="console">
          <SessionLine session={d.session} />
          <div className="small muted">Mode: {d.mode}. Automated visits happen when players talk to the fortune teller; you can also lead a reading.</div>
          <div className="console-grid">
            <Card title="Group">
              {d.members.length === 0 ? <Empty text="No group here." /> : (
                <Table compact head={['', 'Name', 'Answered', 'Correct', 'Points', '']}>
                  {d.members.map((m: any) => (
                    <tr key={m.id}><td><input type="radio" name="fortune-target" checked={target === String(m.id)} onChange={() => setTarget(String(m.id))} disabled={!m.online} /></td>
                      <td>{m.name}{m.inVisit ? ' (reading)' : ''}{m.online ? '' : ' (offline)'}</td><td>{m.answered}</td><td>{m.correct}</td><td className="num">{m.points}</td>
                      <td>{d.session?.kind === 'walkup' ? <Button small busy={busy} onClick={() => run('fortune.staff.finish', { participantId: m.id }, 'Reading finished').then(st.reload)}>Finish reading</Button> : null}</td></tr>
                  ))}
                </Table>
              )}
            </Card>
            <Card title="Present a question">
              <Field label="Question (answer shown for staff only)">
                <select value={question} onChange={(e) => setQuestion(e.target.value)}>
                  <option value="">Choose…</option>
                  {d.questions.map((q: any) => <option key={q.id} value={q.id}>[{q.category}] {q.prompt.slice(0, 70)}</option>)}
                </select>
              </Field>
              {question ? <div className="small gold">Answer: {d.questions.find((q: any) => q.id === question)?.answer}</div> : null}
              <Button busy={busy} disabled={!target || !question} onClick={() => run('fortune.staff.present', { participantId: Number(target), questionId: question }, 'Question presented').then(st.reload)}>Present to selected player</Button>
            </Card>
            <Card title="Reveal a fortune">
              <Field label="Fortune">
                <select value={fortune} onChange={(e) => setFortune(e.target.value)}>
                  <option value="">Custom text…</option>
                  {d.fortunes.map((f: string, i: number) => <option key={i} value={String(i + 1)}>{f.slice(0, 80)}</option>)}
                </select>
              </Field>
              {!fortune ? <Field label="Custom fortune"><textarea rows={2} maxLength={300} value={custom} onChange={(e) => setCustom(e.target.value)} /></Field> : null}
              <div className="btn-row">
                <Button busy={busy} disabled={!target || (!fortune && !custom.trim())} onClick={() => run('fortune.staff.reveal', { participantIds: [Number(target)], fortuneIndex: fortune ? Number(fortune) : undefined, text: fortune ? undefined : custom }, 'Fortune revealed')}>To selected</Button>
                <Button busy={busy} disabled={d.members.length === 0 || (!fortune && !custom.trim())} onClick={() => run('fortune.staff.reveal', { participantIds: d.members.filter((m: any) => m.online).map((m: any) => m.id), fortuneIndex: fortune ? Number(fortune) : undefined, text: fortune ? undefined : custom }, 'Fortune revealed to the group')}>To whole group</Button>
              </div>
            </Card>
            <Card title="Roleplay challenge award">
              <div className="inline-form">
                <input type="number" min={1} max={d.roleplayMaxPoints} placeholder={`1-${d.roleplayMaxPoints}`} value={points} onChange={(e) => setPoints(e.target.value)} />
                <input placeholder="Reason" value={reason} maxLength={200} onChange={(e) => setReason(e.target.value)} />
                <Button busy={busy} disabled={!target || !points || reason.trim().length < 3} onClick={async () => {
                  const r = await run('fortune.staff.award', { participantId: Number(target), points: Number(points), reason, requestId: requestId() }, 'Points awarded');
                  if (r.ok) { setPoints(''); setReason(''); st.reload(); }
                }}>Award</Button>
              </div>
            </Card>
            <Card title="Recent answers" className="span-2">
              {d.recent.length === 0 ? <Empty text="No answers yet." /> : (
                <Table compact head={['When', 'Player', 'Question', 'Answer', 'Result', 'Points']}>
                  {d.recent.map((a: any) => <tr key={a.id}><td className="small">{formatClock(a.created_at)}</td><td>{a.display_name}</td><td>{a.question_id}</td><td>{a.answer ?? '—'}</td><td>{a.timed_out ? 'timeout' : a.correct ? '✔' : '✘'}</td><td className="num">{signed(a.points)}</td></tr>)}
                </Table>
              )}
            </Card>
          </div>
        </div>
      )}
    </Async>
  );
}

// ---------------------------------------------------------------------------
// Puppet Master's Theatre
// ---------------------------------------------------------------------------
export function TheatreConsole() {
  const perms = useStore((s) => s.permissions);
  const st = useApi<any>('theatre.state', {}, [], ['theatre', 'rotation']);
  const { busy, run } = useAction();
  const [scenarioId, setScenarioId] = useState('');
  const [cast, setCast] = useState<Record<number, string>>({});
  const [duration, setDuration] = useState('');
  const [filters, setFilters] = useState({ category: '', difficulty: '' });
  const [customOpen, setCustomOpen] = useState(false);
  const [custom, setCustom] = useState({ title: '', description: '', difficulty: 'medium', maxPoints: '' });
  const [awards, setAwards] = useState<Record<number, { points: string; winner: boolean }>>({});
  const [bonus, setBonus] = useState(true);
  const [note, setNote] = useState('');
  const [preview, setPreview] = useState<any>(null);

  useEffect(() => { setPreview(null); }, [st.data?.current?.id, st.data?.current?.status]);

  return (
    <Async state={st}>
      {(d) => {
        const scenario = d.scenarios.find((s: any) => s.id === scenarioId);
        const cur = d.current;
        const categories = Array.from(new Set(d.scenarios.map((s: any) => s.category))) as string[];
        const awardPayload = () => ({
          performanceId: cur?.id, participationBonus: bonus, note,
          awards: Object.entries(awards).map(([pid, a]) => ({ participantId: Number(pid), points: Number(a.points || 0), winner: a.winner })),
        });
        return (
          <div className="console">
            <SessionLine session={d.session} />
            {!cur ? (
              <div className="console-grid">
                <Card title="1 · Choose a scenario">
                  <div className="inline-form">
                    <select value={filters.category} onChange={(e) => setFilters({ ...filters, category: e.target.value })}><option value="">Any category</option>{categories.map((c) => <option key={c}>{c}</option>)}</select>
                    <select value={filters.difficulty} onChange={(e) => setFilters({ ...filters, difficulty: e.target.value })}><option value="">Any difficulty</option>{['easy', 'medium', 'hard', 'absurd'].map((c) => <option key={c}>{c}</option>)}</select>
                    <Button small onClick={async () => {
                      const r = await api('theatre.random', { ...filters, players: Object.keys(cast).length || undefined });
                      if (r.ok && r.data) setScenarioId(r.data.id); else toast(errorText(r), 'error');
                    }}>Random</Button>
                  </div>
                  <select className="block" value={scenarioId} onChange={(e) => setScenarioId(e.target.value)}>
                    <option value="">Choose from the library…</option>
                    {d.scenarios.filter((s: any) => (!filters.category || s.category === filters.category) && (!filters.difficulty || s.difficulty === filters.difficulty))
                      .map((s: any) => <option key={s.id} value={s.id}>{s.title} ({s.minPlayers}-{s.maxPlayers}p, {s.difficulty})</option>)}
                  </select>
                  {scenario ? <div className="scenario-preview"><strong>{scenario.title}</strong><p>{scenario.description}</p><div className="small muted">{scenario.minPlayers}-{scenario.maxPlayers} performers · {scenario.timeLimit}s · {scenario.minPoints}-{scenario.maxPoints} pts · roles: {scenario.roles.join(', ')}</div></div> : null}
                  {perms.has('theatre.custom') ? <Button small onClick={() => setCustomOpen(true)}>Create a custom scenario…</Button> : null}
                </Card>
                <Card title="2 · Cast performers">
                  {d.eligible.length === 0 ? <Empty text="No group at the theatre." /> : (
                    <Table compact head={['', 'Name', 'Role']}>
                      {d.eligible.map((p: any, i: number) => (
                        <tr key={p.id}>
                          <td><input type="checkbox" checked={cast[p.id] !== undefined} onChange={(e) => setCast((c) => { const n = { ...c }; if (e.target.checked) n[p.id] = scenario?.roles?.[Object.keys(c).length] ?? ''; else delete n[p.id]; return n; })} /></td>
                          <td>{p.name}{p.online ? '' : ' (offline)'}</td>
                          <td>{cast[p.id] !== undefined ? <input value={cast[p.id]} maxLength={64} onChange={(e) => setCast((c) => ({ ...c, [p.id]: e.target.value }))} placeholder={scenario?.roles?.[i] ?? 'Role'} /> : null}</td>
                        </tr>
                      ))}
                    </Table>
                  )}
                  <Field label={`Duration (s) — default ${scenario?.timeLimit ?? d.defaultDuration}`}><input type="number" min={15} max={1800} value={duration} onChange={(e) => setDuration(e.target.value)} /></Field>
                  <Button variant="primary" busy={busy} disabled={!scenarioId || Object.keys(cast).length === 0} onClick={async () => {
                    const r = await run('theatre.create', { scenarioId, duration: duration ? Number(duration) : undefined, performers: Object.entries(cast).map(([pid, role]) => ({ participantId: Number(pid), role })) }, 'Performance prepared');
                    if (r.ok) { setCast({}); setAwards({}); st.reload(); }
                  }}>Prepare performance</Button>
                </Card>
              </div>
            ) : (
              <div className="console-grid">
                <Card title={cur.scenario.title} actions={<StatusPill status={cur.status} />}>
                  <p>{cur.scenario.description}</p>
                  <ul className="plain">{cur.performers.map((p: any) => <li key={p.participantId}>{p.name}{p.role ? ` — ${p.role}` : ''}{p.online ? '' : ' (offline)'}</li>)}</ul>
                  <div className="big-timer">{cur.status === 'running' ? <Countdown endsAt={cur.endsAt} /> : cur.status === 'paused' ? <Countdown remaining={cur.remaining} /> : `${cur.duration}s`}</div>
                  <div className="btn-row">
                    {(cur.status === 'draft' || cur.status === 'displayed') ? <Button busy={busy} onClick={() => run('theatre.display', {}, 'Cards shown').then(st.reload)}>Show cards</Button> : null}
                    {(cur.status === 'draft' || cur.status === 'displayed') ? <Button variant="primary" busy={busy} onClick={() => run('theatre.start', {}, 'Performance started').then(st.reload)}>Start</Button> : null}
                    {cur.status === 'running' ? <Button busy={busy} onClick={() => run('theatre.pause', {}, 'Paused').then(st.reload)}>Pause</Button> : null}
                    {cur.status === 'paused' ? <Button busy={busy} onClick={() => run('theatre.resume', {}, 'Resumed').then(st.reload)}>Resume</Button> : null}
                    {['running', 'paused', 'displayed'].includes(cur.status) ? <Button variant="gold" busy={busy} onClick={() => run('theatre.end', {}, 'Curtain down').then(st.reload)}>End performance</Button> : null}
                    <Button variant="danger" busy={busy} onClick={async () => { const r = await confirmAction({ title: 'Cancel this performance? No points are awarded.', reason: 'required', danger: true }); if (r) { await run('theatre.cancel', { reason: r.reason }, 'Cancelled'); st.reload(); } }}>Cancel</Button>
                  </div>
                </Card>
                {cur.status === 'ended' ? (
                  <Card title="Judging">
                    <Table compact head={['Performer', 'Winner', `Points (max ${Math.min(cur.scenario.maxPoints ?? d.maxPointsPerAward, d.maxPointsPerAward)})`]}>
                      {cur.performers.map((p: any) => {
                        const a = awards[p.participantId] ?? { points: '', winner: false };
                        return (
                          <tr key={p.participantId}>
                            <td>{p.name}</td>
                            <td><input type="checkbox" checked={a.winner} onChange={(e) => setAwards((x) => ({ ...x, [p.participantId]: { ...a, winner: e.target.checked } }))} /></td>
                            <td><input type="number" min={0} value={a.points} onChange={(e) => setAwards((x) => ({ ...x, [p.participantId]: { ...a, points: e.target.value } }))} /></td>
                          </tr>
                        );
                      })}
                    </Table>
                    <label className="check"><input type="checkbox" checked={bonus} onChange={(e) => setBonus(e.target.checked)} /> Participation bonus ({d.participationBonus}) for every performer</label>
                    <Field label="Judging note"><textarea rows={2} maxLength={1000} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
                    <div className="btn-row">
                      <Button busy={busy} onClick={async () => { const r = await run('theatre.preview', awardPayload()); if (r.ok) setPreview(r.data); }}>Preview</Button>
                      <Button variant="primary" busy={busy} disabled={!preview} onClick={async () => {
                        if (!(await confirmAction({ title: 'Commit these results?', message: 'Points are written to the ledger. This cannot be repeated for this performance.' }))) return;
                        const r = await run('theatre.commit', awardPayload(), 'Results committed');
                        if (r.ok) { setAwards({}); setNote(''); setPreview(null); st.reload(); }
                      }}>Commit results</Button>
                    </div>
                    {preview ? (
                      <div className="preview">
                        <Table compact head={['Performer', 'Winner', 'Points', 'Bonus', 'Note']}>
                          {preview.lines.map((l: any) => <tr key={l.participantId}><td>{l.name}</td><td>{l.winner ? '★' : ''}</td><td>{l.points}</td><td>{l.bonus}</td><td className="small">{l.capNote ?? ''}</td></tr>)}
                        </Table>
                        {preview.warnings.map((w: string, i: number) => <div key={i} className="pill pill-warn">{w}</div>)}
                      </div>
                    ) : null}
                  </Card>
                ) : null}
              </div>
            )}
            <Card title="Previous performances">
              {d.history.length === 0 ? <Empty text="None yet." /> : (
                <Table compact head={['#', 'Scenario', 'Status', 'Operator', 'Results', 'Note']}>
                  {d.history.map((h: any) => (
                    <tr key={h.id}><td>{h.id}</td><td>{h.scenario}</td><td><StatusPill status={h.status} /></td><td>{h.operator}</td>
                      <td className="small">{h.performers.map((p: any) => `${p.display_name}${p.is_winner ? '★' : ''} ${p.points + p.participation_bonus}`).join(', ')}</td><td className="small">{h.note}</td></tr>
                  ))}
                </Table>
              )}
            </Card>
            {customOpen ? (
              <Modal title="Custom scenario" onClose={() => setCustomOpen(false)} footer={
                <Button variant="primary" busy={busy} disabled={!custom.title.trim() || !custom.description.trim() || Object.keys(cast).length === 0} onClick={async () => {
                  const r = await run('theatre.create', {
                    custom: { title: custom.title, description: custom.description, difficulty: custom.difficulty, maxPoints: custom.maxPoints ? Number(custom.maxPoints) : undefined },
                    duration: duration ? Number(duration) : undefined,
                    performers: Object.entries(cast).map(([pid, role]) => ({ participantId: Number(pid), role })),
                  }, 'Custom performance prepared');
                  if (r.ok) { setCustomOpen(false); setCast({}); st.reload(); }
                }}>Prepare with selected cast</Button>
              }>
                <p className="small muted">Cast performers in step 2 first. Custom scenarios must follow server rules.</p>
                <Field label="Title"><input maxLength={96} value={custom.title} onChange={(e) => setCustom({ ...custom, title: e.target.value })} /></Field>
                <Field label="Scenario"><textarea rows={4} maxLength={1000} value={custom.description} onChange={(e) => setCustom({ ...custom, description: e.target.value })} /></Field>
                <Field label="Difficulty"><select value={custom.difficulty} onChange={(e) => setCustom({ ...custom, difficulty: e.target.value })}>{['easy', 'medium', 'hard', 'absurd'].map((x) => <option key={x}>{x}</option>)}</select></Field>
                <Field label={`Maximum award (≤ ${d.maxPointsPerAward})`}><input type="number" value={custom.maxPoints} onChange={(e) => setCustom({ ...custom, maxPoints: e.target.value })} /></Field>
              </Modal>
            ) : null}
          </div>
        );
      }}
    </Async>
  );
}

// ---------------------------------------------------------------------------
// Hall of Deception
// ---------------------------------------------------------------------------
export function DeceptionConsole() {
  const st = useApi<any>('deception.staff.state', {}, [], ['deception', 'rotation']);
  const brief = useApi<any>('deception.myBrief', {}, [], ['deception']);
  const { busy, run } = useAction();
  const [mystery, setMystery] = useState('');
  const [adjust, setAdjust] = useState<Record<number, { judgePoints: string; note: string }>>({});
  const [note, setNote] = useState('');
  const [preview, setPreview] = useState<any>(null);
  const [recordFor, setRecordFor] = useState<any>(null);

  const adjustments = () => Object.entries(adjust).map(([pid, a]) => ({ participantId: Number(pid), judgePoints: Number(a.judgePoints || 0), note: a.note }));

  return (
    <div className="console">
      {brief.data?.assigned?.length ? (
        <Card title="Your performer brief" className="brief-card">
          {brief.data.assigned.map((b: any) => (
            <div key={b.id} className="brief">
              <h4>{b.name} {b.isLiar ? <span className="pill pill-bad">YOU ARE LYING</span> : <span className="pill pill-ok">YOU TELL THE TRUTH</span>}</h4>
              <p className="small">{b.profile}</p>
              <p>{b.brief}</p>
              <div className="small muted">Keep these statements consistent:</div>
              <ul>{(b.statements ?? []).map((s: string, i: number) => <li key={i}>{s}</li>)}</ul>
            </div>
          ))}
          {brief.data.mystery?.rules ? <p className="small muted">Rules: {brief.data.mystery.rules}</p> : null}
        </Card>
      ) : null}
      <Async state={st}>
        {(d) => {
          const r = d.round;
          return (
            <>
              <SessionLine session={d.session} />
              {!r || r.status === 'committed' ? (
                <Card title="Set up a mystery">
                  <div className="inline-form">
                    <select value={mystery} onChange={(e) => setMystery(e.target.value)}>
                      <option value="">Default ({d.defaultMystery})</option>
                      {d.mysteries.map((m: any) => <option key={m.id} value={m.id}>{m.title} ({m.liarCount} liars / {m.performers})</option>)}
                    </select>
                    <Button variant="primary" busy={busy} disabled={!d.session} onClick={() => run('deception.setup', { mysteryId: mystery || d.defaultMystery }, 'Mystery prepared').then(st.reload)}>Prepare for this group</Button>
                  </div>
                  <p className="small muted">New mysteries are created in the admin configurator (Hall of Deception page) so they are versioned with the rest of the configuration.</p>
                </Card>
              ) : (
                <div className="console-grid">
                  <Card title={r.mystery.title} actions={<><StatusPill status={r.status} />{r.status === 'questioning' ? <Countdown endsAt={r.endsAt} /> : null}</>}>
                    <p className="small">{r.mystery.description}</p>
                    <div className="btn-row">
                      {r.status === 'setup' ? <Button variant="primary" busy={busy} onClick={() => run('deception.start', {}, 'Questioning started').then(st.reload)}>Start questioning</Button> : null}
                      {r.status === 'questioning' ? <Button busy={busy} onClick={() => run('deception.end', {}, 'Questioning ended').then(st.reload)}>End questioning</Button> : null}
                      {(r.status === 'closed' || r.status === 'questioning') ? <Button variant="gold" busy={busy} onClick={async () => { if (await confirmAction({ title: 'Reveal the liars to the group?' })) { await run('deception.reveal', {}, 'Solution revealed'); st.reload(); } }}>Reveal solution</Button> : null}
                    </div>
                    {d.canSeeSecrets ? <div className="secret">Answer key: <strong>{r.answerKey.map((x: any) => x.name).join(', ')}</strong></div> : <div className="small muted">The answer key is hidden for your role.</div>}
                  </Card>
                  <Card title="Performers">
                    <Table compact head={['Profile', d.canSeeSecrets ? 'Liar?' : '', 'Played by']}>
                      {r.mystery.performers.map((p: any) => {
                        const full = d.canSeeSecrets ? r.performers.find((x: any) => x.id === p.id) : null;
                        const a = r.assignments?.[p.id];
                        return (
                          <tr key={p.id}>
                            <td>{p.name}</td>
                            <td>{full ? (full.isLiar ? <span className="pill pill-bad">liar</span> : <span className="pill pill-ok">truth</span>) : ''}</td>
                            <td>
                              <select value={''} onChange={async (e) => { await run('deception.assign', { profileId: p.id, source: e.target.value === 'none' ? false : Number(e.target.value) }, 'Assignment updated'); st.reload(); }}>
                                <option value="">{a ? a.name : 'Unassigned'}</option>
                                <option value="none">— clear —</option>
                                {d.staff.map((s: any) => <option key={s.source} value={s.source}>{s.name}</option>)}
                              </select>
                            </td>
                          </tr>
                        );
                      })}
                    </Table>
                  </Card>
                  <Card title="Clues">
                    <ul className="plain">
                      {r.clues.map((c: any) => (
                        <li key={c.id} className="clue-row">
                          <span>{c.text}</span>
                          {r.released.includes(c.id) ? <span className="pill pill-ok">released</span>
                            : <Button small busy={busy} onClick={() => run('deception.clue', { clueId: c.id }, 'Clue released').then(st.reload)}>Release</Button>}
                        </li>
                      ))}
                    </ul>
                  </Card>
                  <Card title={`Submissions (${r.submissions.length})`} className="span-2">
                    <Table compact head={['Player', '#', 'Accused', d.canSeeSecrets ? 'Correct' : '', 'Reasoning', 'Judge +', 'Note']}>
                      {r.submissions.map((s: any) => (
                        <tr key={s.id}>
                          <td>{s.name}{s.recordedBy ? ' (recorded)' : ''}</td><td>{s.number}</td>
                          <td className="small">{s.selections.map((id: string) => r.mystery.performers.find((p: any) => p.id === id)?.name ?? id).join(', ')}</td>
                          <td>{d.canSeeSecrets ? `${s.correct}/${r.mystery.liarCount}${s.incorrect ? ` (−${s.incorrect})` : ''}` : ''}</td>
                          <td className="small">{s.explanation ?? ''}</td>
                          <td><input type="number" min={0} className="narrow" value={adjust[s.participantId]?.judgePoints ?? ''} onChange={(e) => setAdjust((x) => ({ ...x, [s.participantId]: { note: x[s.participantId]?.note ?? '', judgePoints: e.target.value } }))} /></td>
                          <td><input className="narrow" value={adjust[s.participantId]?.note ?? ''} maxLength={200} onChange={(e) => setAdjust((x) => ({ ...x, [s.participantId]: { judgePoints: x[s.participantId]?.judgePoints ?? '', note: e.target.value } }))} /></td>
                        </tr>
                      ))}
                    </Table>
                    <div className="btn-row">
                      {(r.status === 'questioning' || r.status === 'closed') ? <Button small onClick={() => setRecordFor({ participantId: '', selections: [] as string[], explanation: '' })}>Record an answer for a player</Button> : null}
                    </div>
                    {d.canSeeSecrets && (r.status === 'closed' || r.status === 'revealed') ? (
                      <>
                        <Field label="Judging note"><textarea rows={2} maxLength={1000} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
                        <div className="btn-row">
                          <Button busy={busy} onClick={async () => { const res = await run('deception.preview', { adjustments: adjustments() }); if (res.ok) setPreview(res.data); }}>Preview scores</Button>
                          <Button variant="primary" busy={busy} disabled={!preview} onClick={async () => {
                            if (!(await confirmAction({ title: 'Commit scores for this mystery?', message: 'Points are written to the ledger once; committing again has no effect.' }))) return;
                            const res = await run('deception.commit', { roundId: r.id, adjustments: adjustments(), note }, 'Scores committed');
                            if (res.ok) { setPreview(null); setAdjust({}); setNote(''); st.reload(); }
                          }}>Commit scores</Button>
                        </div>
                        {preview ? (
                          <Table compact head={['Player', 'Correct', 'Wrong', 'Auto', 'Tie-break', 'Judge', 'Total']}>
                            {preview.lines.map((l: any) => <tr key={l.participantId}><td>{l.name}</td><td>{l.correct}</td><td>{l.incorrect}</td><td>{l.auto - l.tieBreak}</td><td>{l.tieBreak}</td><td>{l.judge}</td><td className="num strong">{l.total}</td></tr>)}
                          </Table>
                        ) : null}
                      </>
                    ) : null}
                  </Card>
                  {recordFor ? (
                    <Modal title="Record an answer" onClose={() => setRecordFor(null)} footer={
                      <Button variant="primary" busy={busy} disabled={!recordFor.participantId || recordFor.selections.length !== r.mystery.liarCount} onClick={async () => {
                        const res = await run('deception.record', { participantId: Number(recordFor.participantId), selections: recordFor.selections, explanation: recordFor.explanation }, 'Answer recorded');
                        if (res.ok) { setRecordFor(null); st.reload(); }
                      }}>Record</Button>
                    }>
                      <Field label="Player">
                        <select value={recordFor.participantId} onChange={(e) => setRecordFor({ ...recordFor, participantId: e.target.value })}>
                          <option value="">Choose…</option>
                          {(r.members ?? []).map((m: any) => <option key={m.id} value={m.id}>{m.name} ({m.used} used)</option>)}
                        </select>
                      </Field>
                      <div className="checks">
                        {r.mystery.performers.map((p: any) => (
                          <label key={p.id} className="check"><input type="checkbox" checked={recordFor.selections.includes(p.id)} onChange={(e) => setRecordFor({ ...recordFor, selections: e.target.checked ? [...recordFor.selections, p.id] : recordFor.selections.filter((x: string) => x !== p.id) })} /> {p.name}</label>
                        ))}
                      </div>
                      <Field label="Reasoning (optional)"><textarea rows={2} value={recordFor.explanation} onChange={(e) => setRecordFor({ ...recordFor, explanation: e.target.value })} /></Field>
                    </Modal>
                  ) : null}
                </div>
              )}
            </>
          );
        }}
      </Async>
    </div>
  );
}

// ---------------------------------------------------------------------------
// House of Horrors
// ---------------------------------------------------------------------------
export function HorrorConsole() {
  const st = useApi<any>('horror.staff.state', {}, [], ['horror', 'rotation']);
  const { busy, run } = useAction();
  const [msg, setMsg] = useState('');
  useEffect(() => {
    if (!st.data?.run || st.data.run.status !== 'running') return;
    const t = setInterval(st.reload, 4000);
    return () => clearInterval(t);
  }, [st.data?.run?.status]);
  return (
    <Async state={st}>
      {(d) => {
        const r = d.run;
        const live = r && (r.status === 'running' || r.status === 'paused');
        return (
          <div className="console">
            <SessionLine session={d.session} />
            {!d.canControl ? <div className="pill pill-warn">You can trigger scares; run controls need the horror controller allowlist.</div> : null}
            <div className="console-grid">
              <Card title={r ? `Run #${r.id}` : 'No run'} actions={r ? <StatusPill status={r.status} /> : null}>
                {live ? <div className="big-timer">{r.status === 'paused' ? <Countdown remaining={r.remaining} /> : <Countdown endsAt={r.endsAt} />}</div> : null}
                {live ? <div className="small muted">Warnings at {r.warnings.join(', ')}s</div> : null}
                {d.canControl ? (
                  <div className="btn-row">
                    {!live ? <Button variant="primary" busy={busy} disabled={!d.session || d.session.status !== 'active'} onClick={async () => { if (await confirmAction({ title: 'Open the House of Horrors and start the countdown?' })) { await run('horror.start', {}, 'Run started'); st.reload(); } }}>Start run</Button> : null}
                    {r?.status === 'running' ? <Button busy={busy} onClick={() => run('horror.pause', {}, 'Paused').then(st.reload)}>Pause</Button> : null}
                    {r?.status === 'paused' ? <Button busy={busy} onClick={() => run('horror.resume', {}, 'Resumed').then(st.reload)}>Resume</Button> : null}
                    {live ? <Button variant="gold" busy={busy} onClick={async () => { if (await confirmAction({ title: 'Stop the run now? Escapes so far keep their bonus.' })) { await run('horror.stop', {}, 'Run stopped'); st.reload(); } }}>Stop</Button> : null}
                    {r ? <Button variant="danger" busy={busy} onClick={async () => {
                      let revert = false;
                      const res = await confirmAction({ title: 'Reset this run?', danger: true, reason: 'required', message: 'The run is abandoned. Optionally reverse every point it awarded (requires score adjustment permission).',
                        extra: <label className="check"><input type="checkbox" onChange={(e) => { revert = e.target.checked; }} /> Reverse points from this run</label> });
                      if (res) { await run('horror.reset', { reason: res.reason, revertScores: revert }, 'Run reset'); st.reload(); }
                    }}>Reset</Button> : null}
                  </div>
                ) : null}
                {live && d.canControl ? (
                  <div className="inline-form">
                    <input placeholder="Optional warning text" maxLength={120} value={msg} onChange={(e) => setMsg(e.target.value)} />
                    <Button small busy={busy} onClick={() => run('horror.warn', { message: msg }, 'Warning sent')}>Send warning</Button>
                  </div>
                ) : null}
              </Card>
              <Card title="Scares">
                {d.scares.length === 0 ? <Empty text="No scare points configured." /> : (
                  <div className="btn-row">{d.scares.map((s: any) => <Button key={s.id} small disabled={r?.status !== 'running'} onClick={async () => { const res = await api('horror.scare', { scareId: s.id }); toast(res.ok ? `Scare hit ${res.data.targets} runner(s)` : errorText(res), res.ok ? 'success' : 'error'); }}>{s.label}</Button>)}</div>
                )}
              </Card>
              {r ? (
                <Card title="Runners" className="span-2">
                  <Table compact head={['Name', 'Status', 'Tokens', 'Points', 'In maze', 'Online']}>
                    {r.runners.map((x: any) => <tr key={x.id}><td>{x.name}</td><td><StatusPill status={x.status} /></td><td>{x.collected}</td><td className="num">{x.points}</td><td>{x.insideBoundary ? '✔' : '✘'}</td><td>{x.online ? '●' : '○'}</td></tr>)}
                  </Table>
                </Card>
              ) : null}
              {r ? (
                <Card title="Tokens" className="span-2">
                  <div className="token-grid">
                    {r.tokens.map((t: any) => <span key={t.id} className={`token token-${t.type} ${t.collections > 0 ? 'token-taken' : ''}`} title={`${t.key}: ${t.collections} collection(s)`}>{t.key}{t.collections ? ` ×${t.collections}` : ''}{t.respawning ? ' ⟳' : ''}</span>)}
                  </div>
                </Card>
              ) : null}
            </div>
          </div>
        );
      }}
    </Async>
  );
}

export const CONSOLES: Record<string, { label: string; component: React.FC }> = {
  shooting: { label: ATTRACTION_SHORT.shooting, component: ShootingConsole },
  wheel: { label: ATTRACTION_SHORT.wheel, component: WheelConsole },
  fortune: { label: ATTRACTION_SHORT.fortune, component: FortuneConsole },
  puppets: { label: ATTRACTION_SHORT.puppets, component: TheatreConsole },
  deception: { label: ATTRACTION_SHORT.deception, component: DeceptionConsole },
  horror: { label: ATTRACTION_SHORT.horror, component: HorrorConsole },
};

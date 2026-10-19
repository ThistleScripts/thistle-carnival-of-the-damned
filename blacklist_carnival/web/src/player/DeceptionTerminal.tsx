import { useEffect, useState } from 'react';
import { api } from '../nui';
import { Backdrop, Icon } from '../components/Art';
import { Button, Countdown, StatusPill } from '../components/ui';
import { errorText } from '../i18n';
import { formatClock } from '../format';
import { syncServerTime } from '../store';

export function DeceptionTerminal({ data, onClose }: { data: any; onClose: () => void }) {
  const m = data.mystery ?? {};
  const [selected, setSelected] = useState<string[]>([]);
  const [explanation, setExplanation] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const [used, setUsed] = useState<number>(data.submissionsUsed ?? 0);
  useEffect(() => { if (data.serverTime) syncServerTime(data.serverTime); }, [data.serverTime]);
  const toggle = (id: string) => {
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : s.length < (m.liarCount ?? 3) ? [...s, id] : s));
  };
  const remaining = (data.maxSubmissions ?? 1) - used;
  const open = data.status === 'questioning';

  const submit = async () => {
    setBusy(true);
    const r = data.preview
      ? { ok: true, data: { submissionNumber: used + 1, remaining: (data.maxSubmissions ?? 1) - used - 1 } } as any
      : await api('deception.submit', { roundId: data.roundId, selections: selected, explanation });
    setBusy(false);
    if (r.ok && r.data) {
      setUsed(r.data.submissionNumber);
      setMessage({ ok: true, text: `Accusation #${r.data.submissionNumber} recorded. ${r.data.remaining > 0 ? `You may change your mind ${r.data.remaining} more time(s); your latest accusation counts.` : 'That was your final accusation.'}` });
    } else {
      setMessage({ ok: false, text: errorText(r) });
    }
  };

  const liars = new Set((data.solution ?? []).map((s: any) => s.id));
  return (
    <div className="overlay-center">
      <Backdrop name="deception" className="panel-frame deception-frame">
        {data.preview ? <div className="preview-banner">PREVIEW — demo data, nothing is sent to the server</div> : null}
        <header className="frame-head">
          <div>
            <h2>{m.title ?? 'The Hall of Deception'}</h2>
            <span className="muted"><StatusPill status={data.status} /> {open && data.endsAt ? <>closes in <Countdown endsAt={data.endsAt} /></> : null}</span>
          </div>
          <Button variant="ghost" onClick={onClose}>Close</Button>
        </header>
        <p className="deception-desc">{m.description}</p>
        {m.rules ? <p className="muted small"><strong>Rules:</strong> {m.rules}</p> : null}
        <div className="suspects">
          {(m.performers ?? []).map((p: any) => (
            <button key={p.id} type="button" disabled={!open} onClick={() => toggle(p.id)}
              className={`suspect ${selected.includes(p.id) ? 'suspect-picked' : ''} ${liars.has(p.id) ? 'suspect-liar' : ''}`}>
              <Icon name="deception" size={22} />
              <strong>{p.name}</strong>
              <span>{p.profile}</span>
              {liars.has(p.id) ? <span className="pill pill-bad">LIAR</span> : null}
            </button>
          ))}
        </div>
        {(data.clues ?? []).length > 0 ? (
          <div className="clues">
            <h4>Clues</h4>
            <ul>{data.clues.map((c: any) => <li key={c.id}><span className="muted small">{formatClock(c.releasedAt)}</span> {c.text}</li>)}</ul>
          </div>
        ) : null}
        {open ? (
          <div className="accuse">
            <textarea placeholder="Explain your reasoning (optional — judges may award bonus points)" maxLength={1000} rows={3} value={explanation} onChange={(e) => setExplanation(e.target.value)} />
            <div className="accuse-row">
              <span className="muted">Choose exactly {m.liarCount} · selected {selected.length} · accusations left {remaining}</span>
              <Button variant="primary" busy={busy} disabled={selected.length !== m.liarCount || remaining <= 0} onClick={submit}>Accuse</Button>
            </div>
          </div>
        ) : data.solution ? <div className="muted">The liars have been unmasked.</div> : <div className="muted">Accusations are not being accepted right now.</div>}
        {message ? <div className={message.ok ? 'state-ok' : 'state-error'}>{message.text}</div> : null}
      </Backdrop>
    </div>
  );
}

export function DeceptionReveal({ data }: { data: any }) {
  return (
    <div className="side-card reveal-card">
      <Icon name="deception" size={22} />
      <div>
        <div className="muted small">{data.mystery?.title} — the liars were</div>
        <strong>{(data.solution ?? []).map((s: any) => s.name).join(', ')}</strong>
      </div>
    </div>
  );
}

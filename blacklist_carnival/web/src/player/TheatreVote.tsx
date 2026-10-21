import { useState } from 'react';
import { api } from '../nui';
import { Backdrop, Icon } from '../components/Art';
import { Button, Countdown } from '../components/ui';
import { errorText } from '../i18n';

// Audience vote after a self-service theatre show.
export function TheatreVote({ data, onClose }: { data: any; onClose: () => void }) {
  const [voted, setVoted] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const candidates: any[] = (data.candidates ?? []).filter((c: any) => c.participantId !== data.self);

  const vote = async (pid: number) => {
    setBusy(true);
    setError(null);
    const r = data.preview ? { ok: true } as any : await api('theatre.vote', { performanceId: data.performanceId, participantId: pid });
    setBusy(false);
    if (r.ok) setVoted(pid);
    else setError(errorText(r));
  };

  return (
    <div className="overlay-center">
      <Backdrop name="theatre" className="panel-frame vote-frame">
        <header className="frame-head">
          <div className="fortune-title"><Icon name="puppets" size={26} /><h2>Who stole the show?</h2></div>
          <div className="btn-row">{data.endsAt ? <span className="muted">Voting closes in <Countdown endsAt={data.endsAt} /></span> : null}<Button variant="ghost" onClick={onClose}>Close</Button></div>
        </header>
        <p className="muted">{data.title}</p>
        <div className="suspects">
          {candidates.map((c) => (
            <button key={c.participantId} type="button" disabled={busy || voted !== null} onClick={() => vote(c.participantId)}
              className={`suspect ${voted === c.participantId ? 'suspect-picked' : ''}`}>
              <Icon name="puppets" size={22} />
              <strong>{c.name}</strong>
              <span>{c.role}</span>
            </button>
          ))}
        </div>
        {candidates.length === 0 ? <p className="muted">You were the only performer - the audience decides.</p> : null}
        {voted !== null ? <div className="state-ok">Vote cast. The results are announced when voting closes.</div> : null}
        {error ? <div className="state-error">{error}</div> : null}
      </Backdrop>
    </div>
  );
}

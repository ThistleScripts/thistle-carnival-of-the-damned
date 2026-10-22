import { useStore } from '../store';
import { attractionLabel, colourHex, colourLabel } from '../format';
import { Countdown } from '../components/ui';
import { Icon } from '../components/Art';

const OVER = new Set(['final_results', 'completed', 'cancelled']);

// Small always-on participant HUD (no focus): one compact card on the right.
export function Hud() {
  const visible = useStore((s) => s.hudVisible && !s.hudHidden);
  const p = useStore((s) => s.participant);
  const e = useStore((s) => s.event);
  const settings = useStore((s) => s.settings);
  const horrorActive = useStore((s) => s.horror.active);
  if (!visible || !p?.registered || !e?.active || OVER.has(e.state ?? '')) return null;

  const hex = colourHex(settings, p.colour);
  const current = p.current;
  const walkup = e.mode === 'walkup';
  const sequence: string[] = p.sequence ?? [];
  const done = new Set<string>(p.completed ?? []);
  return (
    <div className={`hud ${horrorActive ? 'hud-dim' : ''}`} style={{ ['--ticket' as any]: hex }}>
      <div className="hud-top">
        <span className="hud-ticket"><Icon name="ticket" size={14} />{colourLabel(settings, p.colour)} ticket</span>
        {p.rank ? <span className="hud-rank">#{p.rank}</span> : null}
      </div>
      <div className="hud-score">
        <span className="hud-points">{p.total ?? 0}</span>
        <span className="hud-label">points</span>
        {e.state === 'paused' ? <span className="hud-flag">Paused</span> : null}
        {p.status !== 'active' ? <span className="hud-flag">Removed</span> : null}
        {p.ticket?.status === 'pending_delivery' ? <span className="hud-flag">Collect ticket</span> : null}
      </div>
      {sequence.length ? (
        <div className="hud-route" aria-label={`${done.size} of ${sequence.length} played`}>
          {sequence.map((a) => (
            <span key={a} className={`hud-step ${done.has(a) ? 'hud-step-done' : current?.attraction === a ? 'hud-step-now' : ''}`} title={attractionLabel(settings, a)}>
              <Icon name={a} size={13} />
            </span>
          ))}
          <span className="hud-count">{done.size}/{sequence.length}</span>
        </div>
      ) : null}
      {!walkup && (e.round || e.roundEndsAt) ? (
        <div className="hud-round">
          {e.round ? <span>Round {e.round}/{e.totalRounds}</span> : null}
          {e.roundEndsAt ? <Countdown endsAt={e.roundEndsAt} /> : e.roundRemaining != null ? <Countdown remaining={e.roundRemaining} /> : null}
          {e.nextRoundAt ? <span>Next round <Countdown endsAt={e.nextRoundAt} /></span> : null}
        </div>
      ) : null}
      {current ? (
        <div className="hud-next">
          <Icon name={current.attraction} size={18} />
          <div>
            <div className="hud-now">{attractionLabel(settings, current.attraction)}</div>
            <div className="hud-sub">
              {walkup ? 'Next game · talk to the attendant'
                : current.status === 'active' ? 'Open now' : current.status === 'pending' ? 'Opening shortly' : current.status}
            </div>
          </div>
        </div>
      ) : walkup && p.finished ? (
        <div className="hud-next"><Icon name="crown" size={18} /><div className="hud-sub">Every game played. Check the leaderboard!</div></div>
      ) : null}
    </div>
  );
}

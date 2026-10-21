import { useStore } from '../store';
import { attractionLabel, colourHex, colourLabel } from '../format';
import { Countdown } from '../components/ui';
import { Icon } from '../components/Art';

// Small always-on participant HUD (no focus).
export function Hud() {
  const visible = useStore((s) => s.hudVisible && !s.hudHidden);
  const p = useStore((s) => s.participant);
  const e = useStore((s) => s.event);
  const settings = useStore((s) => s.settings);
  const horrorActive = useStore((s) => s.horror.active);
  if (!visible || !p?.registered || !e?.active) return null;

  const current = p.current;
  const walkup = e.mode === 'walkup';
  return (
    <div className={`hud ${horrorActive ? 'hud-dim' : ''}`}>
      <div className="hud-ticket" style={{ borderColor: colourHex(settings, p.colour) }}>
        <Icon name="ticket" size={16} />
        <span style={{ color: colourHex(settings, p.colour) }}>{colourLabel(settings, p.colour)}</span>
        {p.status !== 'active' ? <span className="hud-warn">removed</span> : null}
        {p.ticket?.status === 'pending_delivery' ? <span className="hud-warn">collect ticket</span> : null}
      </div>
      <div className="hud-score">
        <span className="hud-points">{p.total ?? 0}</span>
        <span className="hud-label">points{p.rank ? ` · #${p.rank}` : ''}</span>
      </div>
      <div className="hud-round">
        {e.state === 'paused' ? <span className="hud-paused">Paused</span> : null}
        {walkup ? <span>{e.state === 'running' ? 'Open' : e.stateLabel} · {p.completed?.length ?? 0}/{p.sequence?.length ?? 6} played</span>
          : e.round ? <span>Round {e.round}/{e.totalRounds}</span> : <span>{e.stateLabel}</span>}
        {e.roundEndsAt ? <Countdown endsAt={e.roundEndsAt} /> : e.roundRemaining != null ? <Countdown remaining={e.roundRemaining} /> : null}
        {e.nextRoundAt ? <span className="hud-next">Next round <Countdown endsAt={e.nextRoundAt} /></span> : null}
      </div>
      {current ? (
        <div className="hud-attraction">
          <Icon name={current.attraction} size={18} />
          <div>
            <div className="hud-now">{attractionLabel(settings, current.attraction)}</div>
            <div className="hud-sub">
              {walkup ? 'Your next game · target the attendant to play'
                : current.status === 'active' ? 'Open now' : current.status === 'pending' ? 'Opening shortly' : current.status}
              {p.next ? ` · next: ${attractionLabel(settings, p.next)}` : ''}
            </div>
          </div>
        </div>
      ) : walkup && p.finished ? (
        <div className="hud-attraction"><div className="hud-sub">Every attraction played — check the leaderboard!</div></div>
      ) : p.next ? (
        <div className="hud-attraction"><div className="hud-sub">Next: {attractionLabel(settings, p.next)}</div></div>
      ) : null}
    </div>
  );
}

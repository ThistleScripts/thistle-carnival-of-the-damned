import { useEffect, useState } from 'react';
import { serverNow, useStore } from '../store';
import { Countdown } from '../components/ui';
import { Icon } from '../components/Art';

export function HorrorHud() {
  const h = useStore((s) => s.horror);
  const [flash, setFlash] = useState<string | null>(null);
  useEffect(() => {
    if (h.warning == null) return;
    setFlash(h.warningText ?? `${h.warning}s remaining`);
    const t = setTimeout(() => setFlash(null), 2500);
    return () => clearTimeout(t);
  }, [h.warning, h.warningText]);
  const [, setTick] = useState(0);
  useEffect(() => {
    if (!h.active || !h.endsAt) return;
    const t = setInterval(() => setTick((x) => x + 1), 1000);
    return () => clearInterval(t);
  }, [h.active, h.endsAt]);
  if (!h.active) return null;
  return (
    <div className={`horror-hud ${h.runnerStatus === 'escaped' || h.runnerStatus === 'bailed' ? 'horror-escaped' : ''}`}>
      <div className="horror-title"><Icon name="horror" size={18} /> House of Horrors</div>
      <div className="horror-timer">
        {h.status === 'paused' ? <span>Paused <Countdown remaining={h.remaining} /></span> : <Countdown endsAt={h.endsAt} />}
      </div>
      <div className="horror-stats"><span>Tokens {h.collected ?? 0}</span><span>{h.points ?? 0} pts</span></div>
      {h.runnerStatus === 'escaped' ? <div className="horror-note">You escaped!</div>
        : h.runnerStatus === 'bailed' ? <div className="horror-note">You bailed out</div>
        : h.status !== 'paused' && h.endsAt && h.endsAt <= serverNow() ? <div className="horror-note">Time's up!</div>
        : <div className="horror-note">Step into the green EXIT circle before time runs out</div>}
      {flash ? <div className="horror-flash">{flash}</div> : null}
    </div>
  );
}

export function HorrorResult({ data }: { data: any }) {
  return (
    <div className="side-card">
      <Icon name="horror" size={22} />
      <div>
        <strong>{data.status === 'escaped' ? 'You survived the House of Horrors' : data.status === 'bailed' ? 'You took the escape hatch' : 'The house kept you…'}</strong>
        <div className="muted">Tokens: {data.collected} · Points: {data.points}</div>
      </div>
    </div>
  );
}

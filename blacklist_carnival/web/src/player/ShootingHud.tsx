import { useEffect, useState } from 'react';
import { useStore } from '../store';
import { Countdown } from '../components/ui';
import { Icon } from '../components/Art';

export function ShootingHud() {
  const s = useStore((st) => st.shooting);
  const [pop, setPop] = useState<any>(null);
  useEffect(() => {
    if (!s.hit) return;
    setPop(s.hit);
    const t = setTimeout(() => setPop(null), 900);
    return () => clearTimeout(t);
  }, [s.hit]);
  if (!s.active) return null;
  return (
    <div className="shooting-hud">
      <div className="horror-title"><Icon name="shooting" size={18} /> Shooting Gallery</div>
      <div className="horror-timer">{s.paused ? <span>Paused</span> : <Countdown endsAt={s.endsAt} />}</div>
      <div className="horror-stats"><span>Hits {s.hits ?? 0}</span><span>Shots {s.shots ?? 0}</span><span>{s.total ?? 0} pts</span></div>
      {s.special ? <div className="shooting-special">SPECIAL TARGET UP!</div> : null}
      {pop ? <div className={`shooting-pop ${pop.bullseye ? 'bullseye' : ''}`}>+{pop.points}{pop.bullseye ? ' BULLSEYE' : ''}{pop.special ? ' SPECIAL' : ''}</div> : null}
    </div>
  );
}

export function ShootingResult({ data }: { data: any }) {
  return (
    <div className="side-card">
      <Icon name="shooting" size={22} />
      <div>
        <strong>Heat over: {data.points} points</strong>
        <div className="muted">{data.hits} hits / {data.shots} shots ({data.accuracy}%) · {data.bullseyes} bullseyes · {data.specials} specials
          {data.accuracyBonus ? ` · accuracy +${data.accuracyBonus}` : ''}{data.penalty ? ` · misses −${data.penalty}` : ''}</div>
      </div>
    </div>
  );
}

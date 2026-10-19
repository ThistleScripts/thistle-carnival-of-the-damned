import { useEffect } from 'react';
import { Icon } from '../components/Art';
import { Countdown } from '../components/ui';
import { syncServerTime } from '../store';

// Non-blocking scenario card: performers see their role, the audience sees the scene.
export function TheatreCard({ data }: { data: any }) {
  useEffect(() => { if (data.serverTime) syncServerTime(data.serverTime); }, [data.serverTime]);
  const sc = data.scenario ?? {};
  return (
    <div className={`side-card theatre-card ${data.performer ? 'theatre-performer' : ''}`}>
      <div className="theatre-head">
        <Icon name="puppets" size={24} />
        <div>
          <div className="muted small">{data.performer ? 'You are on stage!' : 'Now performing'} · {sc.difficulty}</div>
          <strong>{sc.title}</strong>
        </div>
        <div className="theatre-timer">
          {data.status === 'running' ? <Countdown endsAt={data.endsAt} /> : data.status === 'paused' ? <span>Paused</span> : <span>Get ready</span>}
        </div>
      </div>
      <p>{sc.description}</p>
      {data.role ? <div className="theatre-role">Your role: <strong>{data.role}</strong></div> : null}
      <ul className="theatre-cast">
        {(data.performers ?? []).map((p: any, i: number) => <li key={i}>{p.name}{p.role ? ` — ${p.role}` : ''}</li>)}
      </ul>
    </div>
  );
}

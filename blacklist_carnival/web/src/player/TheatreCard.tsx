import { useEffect } from 'react';
import { Icon } from '../components/Art';
import { Countdown } from '../components/ui';
import { syncServerTime } from '../store';

interface OrderEntry { name: string; done: boolean; now: boolean; skipped: boolean; you: boolean }

// Non-blocking show card (players keep acting). Each performer has the stage
// alone in turn; everyone sees who is on, their prompt and the running order.
export function TheatreCard({ data }: { data: any }) {
  useEffect(() => { if (data.serverTime) syncServerTime(data.serverTime); }, [data.serverTime]);
  if (data.mode !== 'turns') return <LegacyCard data={data} />;
  const on = data.onStage;
  const next = data.upNext;
  const paused = data.status === 'paused';
  return (
    <div className={`side-card theatre-card ${data.isYou ? 'theatre-performer' : ''}`}>
      <div className="theatre-head">
        <Icon name="puppets" size={24} />
        <div>
          <div className="muted small">Solo Showcase · turn {Math.min(data.turn, data.total)} of {data.total}</div>
          <strong>{data.isYou ? "You're on stage!" : on ? `Now on stage: ${on.name}` : next ? (next.isYou ? "You're up next!" : `Up next: ${next.name}`) : 'Get ready'}</strong>
        </div>
        <div className="theatre-timer">
          {paused ? <span>Paused</span> : on ? <Countdown endsAt={data.endsAt} /> : data.startsAt ? <Countdown endsAt={data.startsAt} /> : null}
        </div>
      </div>
      {on ? (
        <div className="theatre-prompt">
          <div className="theatre-prompt-title">{on.title} <span className="pill">{on.difficulty}</span></div>
          <p>{on.description}</p>
        </div>
      ) : next?.isYou ? (
        <div className="theatre-prompt"><div className="theatre-prompt-title">{next.title}</div><p>Get into position. Your turn starts when the timer runs out.</p></div>
      ) : null}
      <ol className="theatre-order">
        {(data.order ?? []).map((o: OrderEntry, i: number) => (
          <li key={i} className={`${o.done ? 'order-done' : ''} ${o.now ? 'order-now' : ''} ${o.skipped ? 'order-skipped' : ''} ${o.you ? 'order-you' : ''}`}>
            <span className="order-mark">{o.skipped ? '–' : o.done ? '✓' : o.now ? '▶' : i + 1}</span>
            {o.name}{o.you ? ' (you)' : ''}
          </li>
        ))}
      </ol>
      <div className="muted small">When everyone has performed, vote for the best performance.</div>
    </div>
  );
}

// Card format from before solo turns (kept for a show started by an older server).
function LegacyCard({ data }: { data: any }) {
  const sc = data.scenario ?? {};
  return (
    <div className={`side-card theatre-card ${data.performer ? 'theatre-performer' : ''}`}>
      <div className="theatre-head">
        <Icon name="puppets" size={24} />
        <div><div className="muted small">{data.performer ? 'You are on stage!' : 'Now performing'}</div><strong>{sc.title}</strong></div>
        <div className="theatre-timer">{data.status === 'running' ? <Countdown endsAt={data.endsAt} /> : <span>Get ready</span>}</div>
      </div>
      <p>{sc.description}</p>
    </div>
  );
}

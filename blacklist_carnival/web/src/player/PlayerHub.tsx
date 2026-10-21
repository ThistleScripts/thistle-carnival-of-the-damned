import { useStore } from '../store';
import { ATTRACTION_IDS, attractionLabel, colourHex, colourLabel } from '../format';
import { Backdrop, Icon } from '../components/Art';
import { Button, Countdown, StatusPill, useApi } from '../components/ui';
import { LeaderboardTable } from './LeaderboardView';
import { setWaypoint } from '../nui';

// /carnival for players: their ticket, schedule, score breakdown and the board.
export function PlayerHub({ onClose }: { onClose: () => void }) {
  const p = useStore((s) => s.participant);
  const e = useStore((s) => s.event);
  const settings = useStore((s) => s.settings);
  const board = useApi('leaderboard.public', {}, [], ['scores']);

  const myColourIdx = p?.colour ? ['red', 'blue', 'green', 'yellow', 'purple', 'orange'].indexOf(p.colour) : -1;
  const schedule: string[] = myColourIdx >= 0 && settings ? settings.rotation.matrix.map((row) => row[myColourIdx]) : [];
  const completed = new Set<string>(p?.completed ?? []);
  const walkup = e?.mode === 'walkup';

  return (
    <div className="overlay-center">
      <Backdrop name="hub" className="panel-frame hub-frame">
        <header className="frame-head">
          <div>
            <h2>{e?.name ?? settings?.general.eventName ?? 'Carnival of the Damned'}</h2>
            <span className="muted">{e?.active ? (walkup && e.state === 'running' ? 'Open — play at your own pace' : e.stateLabel) : 'No event tonight'}{e?.round ? ` · Round ${e.round}/${e.totalRounds}` : ''}
              {e?.roundEndsAt ? <> · <Countdown endsAt={e.roundEndsAt} /></> : null}</span>
          </div>
          <Button variant="ghost" onClick={onClose}>Close</Button>
        </header>
        {!p?.registered ? (
          <div className="hub-empty">
            <p>{!p?.canRegister ? 'You are not registered for this event.'
              : walkup ? 'The carnival is open. Buy a ticket at the booth by the entrance; its colour sets the order of your games.'
              : 'Registration is open. Visit the ticket booth at the carnival entrance to take your ticket.'}</p>
            {settings ? <Button variant="gold" onClick={() => setWaypoint(settings.registration.entrance.x, settings.registration.entrance.y)}>Mark the ticket booth</Button> : null}
          </div>
        ) : (
          <div className="hub-grid">
            <div className="hub-col">
              <div className="hub-ticket" style={{ borderColor: colourHex(settings, p.colour) }}>
                <div className="hub-points">{p.total ?? 0}<span> points</span></div>
                <div>Rank <strong>{p.rank ? `#${p.rank}` : '—'}</strong> · <span style={{ color: colourHex(settings, p.colour) }}>{colourLabel(settings, p.colour)} group</span></div>
                <div className="muted small">Ticket {p.ticket?.serial ?? '—'} · <StatusPill status={p.ticket?.status ?? 'none'} /></div>
              </div>
              <h4>Your route</h4>
              <ol className="route">
                {schedule.map((a, i) => {
                  const isCurrent = p.current?.attraction === a;
                  return (
                    <li key={a} className={`${completed.has(a) ? 'route-done' : ''} ${isCurrent ? 'route-now' : ''}`}>
                      <Icon name={a} size={16} />
                      <span>{walkup ? `${i + 1}.` : `Round ${i + 1}:`} {attractionLabel(settings, a)}</span>
                      {completed.has(a) ? <span className="pill pill-ok">done</span> : isCurrent ? <span className="pill pill-gold">{walkup ? 'next' : 'now'}</span> : null}
                      {isCurrent && settings ? <Button small onClick={() => setWaypoint(settings.attractions[a].location.x, settings.attractions[a].location.y)}>Waypoint</Button> : null}
                    </li>
                  );
                })}
              </ol>
              <h4>Points by attraction</h4>
              <div className="breakdown">
                {ATTRACTION_IDS.map((a) => (
                  <div key={a} className="breakdown-row"><Icon name={a} size={14} /><span>{attractionLabel(settings, a)}</span><strong>{p.breakdown?.[a] ?? 0}</strong></div>
                ))}
              </div>
            </div>
            <div className="hub-col">
              <h4>Leaderboard</h4>
              {board.data ? <LeaderboardTable data={board.data} /> : null}
            </div>
          </div>
        )}
      </Backdrop>
    </div>
  );
}

import { useStore } from '../store';
import { Countdown } from '../components/ui';
import { Icon } from '../components/Art';

// Hall of Deception: a small timer card while a player is inside the maze of doors.
export function MazeHud() {
  const m = useStore((s) => s.maze);
  if (!m.active) return null;
  return (
    <div className="horror-hud maze-hud">
      <div className="horror-title"><Icon name="deception" size={18} /> Hall of Deception</div>
      <div className="horror-timer">{m.paused ? <span>Paused</span> : <Countdown endsAt={m.endsAt} />}</div>
      <div className="horror-stats"><span>Doors {m.doorsUsed ?? 0}</span><span>Back to start {m.resets ?? 0}</span></div>
      <div className="horror-note">Pick your doors. Find the golden circle.</div>
    </div>
  );
}

export function MazeResult({ data }: { data: any }) {
  const won = data.reason === 'finished';
  const mins = Math.floor((data.seconds ?? 0) / 60);
  const secs = (data.seconds ?? 0) % 60;
  return (
    <div className="side-card">
      <Icon name="deception" size={22} />
      <div>
        <strong>{won ? 'You found the way out!' : 'The hall kept you guessing…'}</strong>
        <div className="muted">
          {won ? `+${data.points ?? 0} points · ` : ''}{data.doors ?? 0} doors · {data.resets ?? 0} back to the start · {mins}:{String(secs).padStart(2, '0')}
        </div>
      </div>
    </div>
  );
}

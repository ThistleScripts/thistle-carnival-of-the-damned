import { useEffect } from 'react';
import { setState, useStore } from '../store';
import { ATTRACTION_IDS, ATTRACTION_SHORT } from '../format';
import { Backdrop, Icon } from '../components/Art';
import { Button, ColourChip, Empty } from '../components/ui';
import { formatTime } from '../format';

export function LeaderboardTable({ data }: { data: any }) {
  const entries: any[] = data?.entries ?? [];
  if (entries.length === 0) return <Empty text="No scores yet. The night is young." />;
  const showBreakdown = entries.some((e) => e.breakdown);
  return (
    <div className="table-wrap">
      <table className="table board">
        <thead>
          <tr>
            <th>#</th><th>Name</th>
            {entries.some((e) => e.colour) ? <th>Ticket</th> : null}
            {entries.some((e) => e.completed != null) ? <th>Done</th> : null}
            {showBreakdown ? ATTRACTION_IDS.map((a) => <th key={a} title={ATTRACTION_SHORT[a]}><Icon name={a} size={14} /></th>) : null}
            {entries.some((e) => e.prize) ? <th>Prize</th> : null}
            <th className="num">Points</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((e, i) => (
            <tr key={i} className={e.rank <= 3 ? `board-top board-top-${e.rank}` : ''}>
              <td>{e.rank}{e.tied ? '=' : ''}</td>
              <td>{e.name}</td>
              {entries.some((x) => x.colour) ? <td><ColourChip colour={e.colour} withLabel={false} /></td> : null}
              {entries.some((x) => x.completed != null) ? <td>{e.completed ?? '—'}/6</td> : null}
              {showBreakdown ? ATTRACTION_IDS.map((a) => <td key={a} className="num muted">{e.breakdown?.[a] ?? '·'}</td>) : null}
              {entries.some((x) => x.prize) ? <td className="gold">{e.prize ?? ''}</td> : null}
              <td className="num strong">{e.total}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function LeaderboardView({ initial, onClose }: { initial: any; onClose: () => void }) {
  const live = useStore((s) => s.leaderboard);
  useEffect(() => {
    if (initial && Object.keys(initial).length) setState({ leaderboard: initial });
  }, [initial]);
  const data = live ?? initial;
  return (
    <div className="overlay-center">
      <Backdrop name="leaderboard" className="panel-frame board-frame">
        <header className="frame-head">
          <div>
            <h2>{data?.eventName ?? 'Leaderboard'}</h2>
            <span className="muted">
              {data?.active === false && data?.frozen ? `Final results · ${formatTime(data.frozenAt)}` : data?.frozen ? 'Final results (frozen)' : 'Live standings'}
              {data?.count ? ` · ${data.count} contestants` : ''}
            </span>
          </div>
          <Button variant="ghost" onClick={onClose}>Close</Button>
        </header>
        {data?.you?.rank ? <div className="board-you">You are <strong>#{data.you.rank}</strong> with <strong>{data.you.total}</strong> points</div> : null}
        <LeaderboardTable data={data} />
      </Backdrop>
    </div>
  );
}

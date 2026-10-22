import { useEffect } from 'react';
import { Backdrop, Icon } from '../components/Art';
import { ColourChip } from '../components/ui';

export const RESULTS_SECONDS = 30;

// Shown to everyone when the final results are frozen. It has no mouse focus
// (players keep moving), so it closes by itself after RESULTS_SECONDS.
export function ResultsBanner({ data, onClose }: { data: any; onClose: () => void }) {
  const top: any[] = data?.top ?? [];
  useEffect(() => {
    const t = setTimeout(onClose, RESULTS_SECONDS * 1000);
    return () => clearTimeout(t);
  }, [data]);
  return (
    <div className="results-banner">
      <Backdrop name="results" className="results-inner">
        <Icon name="crown" size={36} className="gold" />
        <h2>The final bell has rung</h2>
        <ol className="results-list">
          {top.slice(0, 5).map((t, i) => (
            <li key={i} className={`results-${t.rank}`}>
              <span className="results-rank">{t.rank}</span>
              <span className="results-name">{t.name ?? 'Contestant'}</span>
              {t.colour ? <ColourChip colour={t.colour} withLabel={false} /> : null}
              <span className="results-points">{t.total}</span>
              {t.prize ? <span className="pill pill-gold">{t.prize}</span> : null}
            </li>
          ))}
        </ol>
        <div className="results-timer" style={{ animationDuration: `${RESULTS_SECONDS}s` }} />
      </Backdrop>
    </div>
  );
}

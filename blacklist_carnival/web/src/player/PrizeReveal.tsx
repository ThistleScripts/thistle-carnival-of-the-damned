import { useEffect } from 'react';
import { Icon } from '../components/Art';
import { ItemImage } from '../components/ItemImage';

export const REVEAL_SECONDS = 7;

// Shown when a prize box is opened. No mouse focus, so it closes by itself.
export function PrizeReveal({ data, onClose }: { data: any; onClose: () => void }) {
  const contents: { item: string; count: number; label?: string }[] = data?.contents ?? [];
  const images: (string | undefined)[] = data?.images ?? [];
  useEffect(() => {
    const t = setTimeout(onClose, REVEAL_SECONDS * 1000);
    return () => clearTimeout(t);
  }, [data]);
  return (
    <div className="prize-reveal">
      <div className="prize-reveal-head"><Icon name="gift" size={20} /> Your prize box held</div>
      <div className="prize-reveal-items">
        {contents.map((c, i) => (
          <div key={c.item} className="prize-reveal-item" style={{ animationDelay: `${0.15 + i * 0.18}s` }}>
            <ItemImage item={c.item} src={images[i]} className="prize-reveal-img" size={28} />
            <span className="prize-reveal-count">{c.count}×</span>
            <span className="prize-reveal-name">{c.label ?? c.item}</span>
          </div>
        ))}
      </div>
      <div className="results-timer" style={{ animationDuration: `${REVEAL_SECONDS}s` }} />
    </div>
  );
}

import { useEffect, useState } from 'react';
import { useStore } from '../store';
import { Icon } from './Art';

export const DEFAULT_IMAGE_PATH = 'nui://ox_inventory/web/images';

// Picture of an ox_inventory item. `src` is the image the client resolved from
// ox_inventory (the item's own client.image); if it fails we fall back to
// <inventory image path>/<item>.png and finally to an icon.
export function ItemImage({ item, src, className, size = 40 }: { item: string; src?: string; className?: string; size?: number }) {
  const base = useStore((s) => s.inventoryImagePath) || DEFAULT_IMAGE_PATH;
  const candidates = [src, `${base}/${item}.png`, `${DEFAULT_IMAGE_PATH}/${item}.png`].filter((u, i, a): u is string => !!u && a.indexOf(u) === i);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => setAttempt(0), [item, src, base]);
  if (attempt >= candidates.length) {
    return <div className={`item-img item-img-missing ${className ?? ''}`}><Icon name="gift" size={size} /></div>;
  }
  return <img className={`item-img ${className ?? ''}`} src={candidates[attempt]} alt="" draggable={false} onError={() => setAttempt((n) => n + 1)} />;
}

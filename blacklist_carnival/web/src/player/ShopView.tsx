import { useState } from 'react';
import { useStore } from '../store';
import { api, requestId } from '../nui';
import { playSound } from '../audio';
import { Backdrop, Icon } from '../components/Art';
import { Button, toast } from '../components/ui';

export interface ShopItem { item: string; label: string; description?: string; price: number; dailyLimit: number; remainingToday?: number }
export interface ShopData { label: string; currency: string; earnPercent: number; wallet: { balance: number; earned: number; spent: number }; items: ShopItem[] }

// Item artwork comes from ox_inventory's image folder (the same PNGs players see
// in their inventory); a missing image falls back to an icon.
function ItemImage({ item }: { item: string }) {
  const [failed, setFailed] = useState(false);
  if (failed) return <div className="shop-img shop-img-missing"><Icon name="gift" size={44} /></div>;
  return <img className="shop-img" src={`nui://ox_inventory/web/images/${item}.png`} alt="" onError={() => setFailed(true)} draggable={false} />;
}

function ShopCard({ it, balance, currency, onBought }: { it: ShopItem; balance: number; currency: string; onBought: (balance: number) => void }) {
  const [count, setCount] = useState(1);
  const [busy, setBusy] = useState(false);
  const limit = it.remainingToday ?? 20;
  const affordable = Math.floor(balance / it.price);
  const max = Math.max(0, Math.min(20, limit, affordable));
  const qty = Math.min(count, Math.max(1, max));
  const soldOut = it.remainingToday === 0;
  const buy = async () => {
    setBusy(true);
    const r = await api<{ balance: number; count: number }>('shop.buy', { item: it.item, count: qty, requestId: requestId() });
    setBusy(false);
    if (r.ok && r.data) {
      playSound('shop_purchase', 0.7);
      toast(`${qty} × ${it.label} — enjoy.`, 'success');
      setCount(1);
      onBought(r.data.balance);
    } else {
      toast(r.message ?? r.error ?? 'Purchase failed', 'error');
      onBought(-1);
    }
  };
  return (
    <div className={`shop-card ${max === 0 ? 'shop-card-dim' : ''}`}>
      <ItemImage item={it.item} />
      <div className="shop-card-body">
        <strong className="shop-name">{it.label}</strong>
        {it.description ? <p className="shop-desc">{it.description}</p> : null}
        <div className="shop-meta">
          <span className="shop-price"><Icon name="coin" size={14} />{it.price}</span>
          {it.dailyLimit > 0 ? <span className="pill">{soldOut ? 'Limit reached today' : `${it.remainingToday ?? it.dailyLimit} left today`}</span> : null}
        </div>
      </div>
      <div className="shop-buy">
        <div className="stepper" aria-label="Quantity">
          <button onClick={() => setCount(Math.max(1, qty - 1))} disabled={qty <= 1 || busy}>−</button>
          <span>{qty}</span>
          <button onClick={() => setCount(Math.min(max, qty + 1))} disabled={qty >= max || busy}>+</button>
        </div>
        <Button variant="gold" busy={busy} disabled={max === 0} onClick={buy} title={max === 0 && !soldOut ? `Not enough ${currency}` : undefined}>
          {soldOut ? 'Sold out' : `Buy · ${it.price * qty}`}
        </Button>
      </div>
    </div>
  );
}

export function ShopView({ data, onClose }: { data: ShopData; onClose: () => void }) {
  const [shop, setShop] = useState<ShopData>(data);
  const pushed = useStore((s) => s.wallet);
  const balance = pushed?.balance ?? shop.wallet.balance;
  const refresh = async () => {
    const r = await api<ShopData>('shop.open');
    if (r.ok && r.data) setShop(r.data);
  };
  return (
    <div className="overlay-center">
      <Backdrop name="shop" className="panel-frame shop-frame">
        <header className="frame-head">
          <div>
            <span className="kicker">Redeem your winnings</span>
            <h2>{shop.label}</h2>
            <span className="muted">Every point you score in the games earns {shop.currency.toLowerCase()} to spend here. They keep between nights.</span>
          </div>
          <div className="shop-wallet">
            <span className="shop-wallet-label">{shop.currency}</span>
            <span className="shop-wallet-value">{balance}</span>
            <Button variant="ghost" small onClick={onClose}>Close</Button>
          </div>
        </header>
        {shop.items.length === 0 ? <p className="muted">The counter is bare tonight. Come back later.</p> : (
          <div className="shop-grid">
            {shop.items.map((it) => (
              <ShopCard key={it.item} it={it} balance={balance} currency={shop.currency}
                onBought={(b) => { if (b >= 0) setShop((s) => ({ ...s, wallet: { ...s.wallet, balance: b } })); refresh(); }} />
            ))}
          </div>
        )}
      </Backdrop>
    </div>
  );
}

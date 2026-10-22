import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { useStore } from '../store';
import { api, requestId } from '../nui';
import { playSound } from '../audio';
import { Backdrop, Icon } from '../components/Art';
import { ItemImage } from '../components/ItemImage';
import { Button, toast } from '../components/ui';

export interface ShopItem { item: string; image?: string; label: string; description?: string; price: number; category?: string; dailyLimit: number; remainingToday?: number }
export interface EarningRule { attraction: string; label: string; perPlay: number; per100Points: number; maxPerNight: number; wonTonight: number }
export interface ShopData { label: string; currency: string; earning?: EarningRule[]; wallet: { balance: number; earned: number; spent: number }; items: ShopItem[] }

const SHELVES: { id: string; label: string }[] = [
  { id: 'all', label: 'Everything' },
  { id: 'food', label: 'Treats' },
  { id: 'drink', label: 'Drinks' },
  { id: 'prize', label: 'Prizes' },
  { id: 'other', label: 'Curiosities' },
];

// A ticket stub with the price / balance on it.
function Stub({ value, small, dim }: { value: ReactNode; small?: boolean; dim?: boolean }) {
  return <span className={`stub ${small ? 'stub-sm' : ''} ${dim ? 'stub-dim' : ''}`}><Icon name="ticket" size={small ? 13 : 18} />{value}</span>;
}

function maxQty(it: ShopItem, balance: number) {
  return Math.max(0, Math.min(20, it.remainingToday ?? 20, Math.floor(balance / it.price)));
}

function Detail({ it, balance, currency, onBought }: { it: ShopItem; balance: number; currency: string; onBought: (balance: number | null) => void }) {
  const [count, setCount] = useState(1);
  const [busy, setBusy] = useState(false);
  useEffect(() => setCount(1), [it.item]);
  const max = maxQty(it, balance);
  const qty = Math.min(count, Math.max(1, max));
  const cost = it.price * qty;
  const soldOut = it.remainingToday === 0;
  const short = it.price - balance;
  const redeem = async () => {
    setBusy(true);
    const r = await api<{ balance: number }>('shop.buy', { item: it.item, count: qty, requestId: requestId() });
    setBusy(false);
    if (r.ok && r.data) {
      playSound('shop_purchase', 0.7);
      toast(`${qty} × ${it.label} — enjoy.`, 'success');
      setCount(1);
      onBought(r.data.balance);
    } else {
      toast(r.message ?? r.error ?? 'Could not redeem that', 'error');
      onBought(null);
    }
  };
  return (
    <aside className="booth-detail">
      <div className="booth-spot"><ItemImage item={it.item} src={it.image} className="booth-img booth-img-lg" size={56} /></div>
      <h3 className="booth-detail-name">{it.label}</h3>
      {it.description ? <p className="booth-detail-desc">{it.description}</p> : null}
      <div className="booth-detail-meta">
        <Stub value={`${it.price} each`} small />
        {it.dailyLimit > 0 ? <span className="pill">{soldOut ? 'Limit reached today' : `${it.remainingToday ?? it.dailyLimit} of ${it.dailyLimit} left today`}</span> : null}
      </div>
      <div className="booth-qty">
        <span className="muted small">How many</span>
        <div className="stepper" aria-label="Quantity">
          <button onClick={() => setCount(Math.max(1, qty - 1))} disabled={qty <= 1 || busy}>−</button>
          <span>{qty}</span>
          <button onClick={() => setCount(Math.min(max, qty + 1))} disabled={qty >= max || busy}>+</button>
        </div>
      </div>
      <div className="booth-sum">
        <div><span className="muted small">Costs</span><strong>{cost}</strong></div>
        <div><span className="muted small">Left after</span><strong className={balance - cost < 0 ? 'booth-neg' : ''}>{balance - cost < 0 ? '—' : balance - cost}</strong></div>
      </div>
      <Button variant="gold" className="booth-redeem" busy={busy} disabled={max === 0} onClick={redeem}>
        {soldOut ? 'Come back tomorrow' : max === 0 ? `${short} more ${currency.toLowerCase()} needed` : `Redeem ${qty > 1 ? `${qty} for ` : 'for '}${cost}`}
      </Button>
    </aside>
  );
}

function HowToWin({ rules }: { rules: EarningRule[] }) {
  if (!rules.length) return null;
  return (
    <section className="booth-earn">
      <h4>Win tickets at the games</h4>
      <div className="booth-earn-row">
        {rules.map((r) => {
          const pct = r.maxPerNight > 0 ? Math.min(100, Math.round((r.wonTonight / r.maxPerNight) * 100)) : 0;
          return (
            <div key={r.attraction} className="booth-earn-card" title={r.label}>
              <div className="booth-earn-head"><Icon name={r.attraction} size={16} /><span>{r.label}</span></div>
              <div className="booth-earn-rates">
                {r.perPlay > 0 ? <span>+{r.perPlay} for playing</span> : null}
                {r.per100Points > 0 ? <span>+{r.per100Points} per 100 pts</span> : null}
              </div>
              {r.maxPerNight > 0 ? (
                <div className="booth-earn-bar" aria-label={`${r.wonTonight} of ${r.maxPerNight} won tonight`}>
                  <span style={{ width: `${pct}%` }} />
                  <em>{r.wonTonight}/{r.maxPerNight} tonight</em>
                </div>
              ) : <div className="booth-earn-bar"><em>{r.wonTonight} won tonight</em></div>}
            </div>
          );
        })}
      </div>
    </section>
  );
}

export function ShopView({ data, onClose }: { data: ShopData; onClose: () => void }) {
  const [shop, setShop] = useState<ShopData>(data);
  const [shelf, setShelf] = useState('all');
  const [picked, setPicked] = useState<string | null>(data.items[0]?.item ?? null);
  const [flash, setFlash] = useState(0);
  const pushed = useStore((s) => s.wallet);
  const balance = pushed?.balance ?? shop.wallet.balance;

  const shelves = useMemo(() => SHELVES.filter((s) => s.id === 'all' || shop.items.some((i) => (i.category ?? 'other') === s.id)), [shop.items]);
  const items = shop.items.filter((i) => shelf === 'all' || (i.category ?? 'other') === shelf);
  const current = shop.items.find((i) => i.item === picked) ?? items[0];

  const refresh = async () => {
    const r = await api<ShopData>('shop.open');
    if (r.ok && r.data) setShop(r.data);
  };
  useEffect(() => { setFlash((f) => f + 1); }, [balance]);

  return (
    <div className="overlay-center">
      <Backdrop name="shop" className="panel-frame booth-frame">
        <div className="booth-bulbs" aria-hidden="true" />
        <header className="booth-head">
          <div>
            <span className="kicker">Step right up</span>
            <h2 className="booth-title">{shop.label}</h2>
            <span className="muted">Trade the tickets you win at the games for treats and prizes. Your tickets keep between nights.</span>
          </div>
          <div className="booth-wallet">
            <div key={flash} className="booth-balance">
              <span className="booth-balance-label">Your {shop.currency.toLowerCase()}</span>
              <span className="booth-balance-value">{balance}</span>
            </div>
            <Button variant="ghost" small onClick={onClose}>Close</Button>
          </div>
        </header>

        {shop.items.length === 0 ? <p className="muted">The counter is bare tonight. Come back later.</p> : (
          <div className="booth-body">
            <div className="booth-main">
              {shelves.length > 2 ? (
                <div className="chips" role="tablist">
                  {shelves.map((s) => (
                    <button key={s.id} role="tab" aria-selected={s.id === shelf} className={`chip ${s.id === shelf ? 'chip-active' : ''}`} onClick={() => setShelf(s.id)}>{s.label}</button>
                  ))}
                </div>
              ) : null}
              <div className="booth-shelf">
                {items.map((it) => {
                  const can = maxQty(it, balance) > 0;
                  return (
                    <button key={it.item} className={`booth-item ${current?.item === it.item ? 'booth-item-on' : ''} ${can ? '' : 'booth-item-dim'}`}
                      onClick={() => setPicked(it.item)} aria-pressed={current?.item === it.item}>
                      <ItemImage item={it.item} src={it.image} className="booth-img" />
                      <span className="booth-item-name">{it.label}</span>
                      <Stub value={it.price} small dim={!can} />
                    </button>
                  );
                })}
              </div>
            </div>
            {current ? <Detail it={current} balance={balance} currency={shop.currency}
              onBought={(b) => { if (b !== null) setShop((s) => ({ ...s, wallet: { ...s.wallet, balance: b } })); refresh(); }} /> : null}
          </div>
        )}
        <HowToWin rules={shop.earning ?? []} />
      </Backdrop>
    </div>
  );
}

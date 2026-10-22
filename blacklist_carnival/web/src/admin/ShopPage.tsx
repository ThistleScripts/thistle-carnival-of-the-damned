import { useState } from 'react';
import { Async, Button, Card, Delta, Field, Modal, Stat, Table, useAction, useApi } from '../components/ui';
import { formatTime } from '../format';
import { requestId } from '../nui';
import { ItemImage } from '../components/ItemImage';

const KIND_LABELS: Record<string, string> = { purchase: 'Bought', refund: 'Refund', adjust: 'Adjusted', earned: 'Earned' };

function AdjustModal({ wallet, currency, onClose, onDone }: { wallet: any; currency: string; onClose: () => void; onDone: () => void }) {
  const [delta, setDelta] = useState('');
  const [reason, setReason] = useState('');
  const [rid] = useState(requestId);
  const { busy, run } = useAction();
  const n = Number(delta);
  const valid = Number.isInteger(n) && n !== 0 && reason.trim().length >= 3;
  const submit = async () => {
    const r = await run('shop.adjust', { citizenid: wallet.citizenid, delta: n, reason: reason.trim(), requestId: rid }, 'Wallet adjusted');
    if (r.ok) { onDone(); onClose(); }
  };
  return (
    <Modal title={`Adjust ${wallet.display_name ?? wallet.citizenid}`} onClose={onClose} footer={
      <>
        <Button variant="ghost" onClick={onClose}>Cancel</Button>
        <Button variant="primary" busy={busy} disabled={!valid} onClick={submit}>Apply</Button>
      </>
    }>
      <p className="muted small">Current balance: <strong className="gold">{wallet.balance}</strong> {currency}. Use a negative number to take points away.</p>
      <Field label={`Change (${currency})`}><input type="number" value={delta} onChange={(e) => setDelta(e.target.value)} placeholder="e.g. 50 or -20" autoFocus /></Field>
      <Field label="Reason (recorded in the audit log)"><textarea rows={3} maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
    </Modal>
  );
}

// Players → Prize counter: what is being bought, who holds points, and manual corrections.
export function ShopPage() {
  const ov = useApi<any>('shop.overview', {}, [], ['shop']);
  const [query, setQuery] = useState('');
  const [submitted, setSubmitted] = useState('');
  const search = useApi<any>(submitted ? 'shop.search' : null, { query: submitted }, [submitted], ['shop']);
  const [adjusting, setAdjusting] = useState<any>(null);
  const reload = () => { ov.reload(); search.reload(); };

  return (
    <div className="stack">
      <Async state={ov}>
        {(d) => {
          const wallets = submitted && search.data ? search.data.wallets : d.wallets;
          return (
            <>
              <div className="stats">
                <Stat label={`${d.currency} held`} value={d.totals.outstanding} tone="gold" />
                <Stat label="Earned all time" value={d.totals.earned} />
                <Stat label="Spent all time" value={d.totals.spent} />
                <Stat label="Purchases (24 h)" value={d.totals.purchasesToday} tone="ok" />
                <Stat label="Players with points" value={d.totals.wallets} />
              </div>
              <div className="grid-2">
                <Card title="Best sellers">
                  {d.popular.length === 0 ? <p className="muted">Nothing sold yet.</p> : (
                    <Table compact head={['Item', 'Sold', d.currency]}>
                      {d.popular.map((p: any) => <tr key={p.item}><td><span className="item-cell"><ItemImage item={p.item} className="item-thumb" size={14} />{p.item}</span></td><td>{p.sold}</td><td>{p.points}</td></tr>)}
                    </Table>
                  )}
                </Card>
                <Card title="Recent purchases & changes">
                  {d.recent.length === 0 ? <p className="muted">No activity yet.</p> : (
                    <Table compact head={['When', 'Player', 'What', 'Change']}>
                      {d.recent.map((r: any) => (
                        <tr key={r.id}>
                          <td className="small">{formatTime(r.created_at)}</td>
                          <td>{r.display_name ?? r.citizenid}</td>
                          <td className="small"><span className="item-cell">{r.item ? <ItemImage item={r.item} className="item-thumb" size={14} /> : null}<span>{KIND_LABELS[r.kind] ?? r.kind}{r.item ? ` · ${r.item_count} × ${r.item}` : ''}{r.kind === 'adjust' ? ` · ${r.staff_name ?? ''}: ${r.reason ?? ''}` : ''}</span></span></td>
                          <td><Delta value={r.delta} /></td>
                        </tr>
                      ))}
                    </Table>
                  )}
                </Card>
              </div>
              <Card title="Wallets" actions={
                <form className="btn-row" onSubmit={(e) => { e.preventDefault(); setSubmitted(query.trim()); }}>
                  <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Name or citizen ID" />
                  <Button small type="submit">Search</Button>
                  {submitted ? <Button small variant="ghost" type="button" onClick={() => { setQuery(''); setSubmitted(''); }}>Clear</Button> : null}
                </form>
              }>
                {wallets.length === 0 ? <p className="muted">{submitted ? 'No wallets match.' : 'Nobody has earned any points yet.'}</p> : (
                  <Table head={['Player', 'Balance', 'Earned', 'Spent', 'Last change', '']}>
                    {wallets.map((w: any) => (
                      <tr key={w.citizenid}>
                        <td>{w.display_name ?? '—'} <span className="muted small">{w.citizenid}</span></td>
                        <td className="gold">{w.balance}</td><td>{w.earned_total}</td><td>{w.spent_total}</td>
                        <td className="small">{formatTime(w.updated_at)}</td>
                        <td><Button small onClick={() => setAdjusting(w)}>Adjust</Button></td>
                      </tr>
                    ))}
                  </Table>
                )}
              </Card>
              {adjusting ? <AdjustModal wallet={adjusting} currency={d.currency} onClose={() => setAdjusting(null)} onDone={reload} /> : null}
            </>
          );
        }}
      </Async>
    </div>
  );
}

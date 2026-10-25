import { Async, Button, Card, Table, useApi } from '../components/ui';
import { ItemImage } from '../components/ItemImage';

// Opens a few thousand boxes on the server with the saved prize box settings,
// so the owner can see what players will actually get.
export function PrizeBoxOdds() {
  const sim = useApi<any>('prizebox.simulate', { boxes: 2000 }, [], ['config']);
  return (
    <Card title="What players will get" actions={<Button small onClick={sim.reload}>Open another 2,000</Button>}>
      <p className="muted small">Based on the saved settings: save your changes first, then this updates.</p>
      <Async state={sim}>
        {(d) => (
          <>
            <p>On average a box holds <strong className="gold">{d.avgItems}</strong> item{d.avgItems === 1 ? '' : 's'} ({d.boxes.toLocaleString()} boxes opened).</p>
            <Table compact head={['Prize', 'Found in', 'Average per box']}>
              {d.rows.map((r: any) => (
                <tr key={r.item}>
                  <td><span className="item-cell"><ItemImage item={r.item} className="item-thumb" size={14} />{r.label ?? r.item}</span></td>
                  <td>
                    <span className="odds-bar"><span style={{ width: `${Math.min(100, r.inBoxes)}%` }} /></span>
                    {r.inBoxes}% of boxes
                  </td>
                  <td>{r.avgCount}</td>
                </tr>
              ))}
            </Table>
          </>
        )}
      </Async>
    </Card>
  );
}

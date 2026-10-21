import { useState } from 'react';
import { placeProp, setWaypoint } from '../nui';
import { formatAgo } from '../format';
import { Async, Button, Card, Empty, Field, Table, confirmAction, useAction, useApi } from '../components/ui';

// Models that always ship with the resource (stream/props/).
const BUNDLED = ['carnivalcoinbronze', 'carnivalcoinsilver', 'carnivalcoingold'];

function round(n: number, d = 2) {
  return Number(n).toFixed(d);
}

// World props: place, move and remove props that every player sees.
export function PropsPage() {
  const st = useApi<any>('props.list', {}, [], ['props']);
  const { busy, run } = useAction();
  const [model, setModel] = useState('');
  const [label, setLabel] = useState('');
  const [collision, setCollision] = useState(true);
  const [filter, setFilter] = useState('');

  return (
    <div className="stack">
      <Card title="Place a prop">
        <div className="form-grid">
          <Field label="Model" hint="The prop's model name: its file name in stream/props without the extension.">
            <input list="carnival-prop-models" placeholder="e.g. carnivalcoingold" value={model} onChange={(e) => setModel(e.target.value.trim())} />
            <datalist id="carnival-prop-models">
              {Array.from(new Set([...BUNDLED, ...(st.data?.models ?? [])])).map((m) => <option key={m} value={m} />)}
            </datalist>
          </Field>
          <Field label="Name (optional)"><input placeholder="e.g. Gold coin by the gate" maxLength={64} value={label} onChange={(e) => setLabel(e.target.value)} /></Field>
          <label className="check"><input type="checkbox" checked={collision} onChange={(e) => setCollision(e.target.checked)} /> Solid (players bump into it)</label>
          <div><Button variant="gold" disabled={!/^[A-Za-z0-9_]+$/.test(model)} onClick={() => placeProp({ model, label: label || undefined, collision })}>Place in the world</Button></div>
        </div>
        <p className="small muted">The panel minimises while you place: look where the prop should go, scroll to rotate, arrow keys to raise, lower and tilt, G to drop it onto the ground, Enter to place. Reopen the panel with /carnivaladmin. Admins can also target any placed prop to move or remove it.</p>
      </Card>

      <Card title="Placed props" actions={<input className="filter-input" placeholder="Filter by name or model" value={filter} onChange={(e) => setFilter(e.target.value)} />}>
        <Async state={st}>
          {(d) => {
            const f = filter.toLowerCase();
            const rows = (d.props as any[]).filter((p) => !f || p.model.toLowerCase().includes(f) || (p.label ?? '').toLowerCase().includes(f));
            return rows.length === 0 ? <Empty text={d.props.length ? 'No props match.' : 'No props placed yet.'} /> : (
              <>
                <div className="small muted">{d.props.length} of {d.max} props placed · every player sees them and they survive restarts</div>
                <Table head={['#', 'Prop', 'Position', 'Heading', 'Solid', 'Placed', '']}>
                  {rows.map((p: any) => (
                    <tr key={p.id}>
                      <td>{p.id}</td>
                      <td><strong>{p.label ?? p.model}</strong>{p.label ? <div className="small muted mono">{p.model}</div> : null}</td>
                      <td className="mono small">{round(p.x)}, {round(p.y)}, {round(p.z)}</td>
                      <td className="num">{Math.round(((p.rz % 360) + 360) % 360)}°</td>
                      <td>{p.collision ? 'Yes' : 'No'}</td>
                      <td className="small muted">{p.createdBy ?? '—'} · {formatAgo(p.updatedAt ?? p.createdAt)}</td>
                      <td><div className="btn-row row-actions">
                        <Button small onClick={() => placeProp({ id: p.id })}>Move</Button>
                        <Button small variant="ghost" onClick={() => setWaypoint(p.x, p.y)}>Waypoint</Button>
                        <Button small variant="danger" busy={busy} onClick={async () => {
                          const r = await confirmAction({ title: `Remove ${p.label ?? p.model}?`, message: 'It disappears for every player. The record is kept in the audit trail.', danger: true, confirmLabel: 'Remove' });
                          if (r) { await run('props.delete', { id: p.id }, 'Prop removed'); st.reload(); }
                        }}>Remove</Button>
                      </div></td>
                    </tr>
                  ))}
                </Table>
              </>
            );
          }}
        </Async>
      </Card>
    </div>
  );
}

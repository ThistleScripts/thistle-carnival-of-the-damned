import { useStore } from '../store';
import { colourHex, colourLabel } from '../format';
import { Backdrop, Icon } from '../components/Art';
import { Button } from '../components/ui';

const STATUS_TEXT: Record<string, string> = {
  valid: 'Valid ticket',
  void: 'VOID — this ticket has been replaced',
  expired: 'Expired — this ticket is from another event',
  invalid: 'Not recognised by the ticket booth',
  pending_delivery: 'Waiting at the ticket booth',
  none: 'No ticket issued',
};

export function TicketCard({ data, onClose }: { data: any; onClose: () => void }) {
  const settings = useStore((s) => s.settings);
  const colour = data.colour as string | undefined;
  const hex = colourHex(settings, colour);
  const status = data.action === 'issued' ? 'valid' : (data.status ?? 'valid');
  return (
    <div className="overlay-center">
      <Backdrop name="ticket" className="ticket-stage">
        <div className={`ticket ${status !== 'valid' ? 'ticket-void' : ''}`} style={{ ['--ticket' as any]: hex }}>
          <div className="ticket-stub">
            <Icon name="ticket" size={34} />
            <span className="ticket-admit">ADMIT ONE</span>
          </div>
          <div className="ticket-main">
            <div className="ticket-event">{data.eventName ?? settings?.general.eventName ?? 'Carnival of the Damned'}</div>
            <div className="ticket-colour" style={{ color: hex }}>{colourLabel(settings, colour)} group</div>
            <div className="ticket-holder">{data.holder ?? '—'}</div>
            <div className="ticket-serial">{data.virtual ? 'Virtual ticket' : `Serial ${data.serial ?? '—'}`}</div>
            <div className={`ticket-status ticket-status-${status}`}>{STATUS_TEXT[status] ?? status}</div>
          </div>
        </div>
        {data.action === 'issued' ? <p className="ticket-hint">Keep this ticket on you. You must present it at every attraction.</p> : null}
        <Button variant="gold" onClick={onClose}>Close</Button>
      </Backdrop>
    </div>
  );
}

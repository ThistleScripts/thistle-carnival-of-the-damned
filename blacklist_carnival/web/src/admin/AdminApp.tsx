import React, { useState } from 'react';
import { useStore } from '../store';
import { Backdrop, Icon } from '../components/Art';
import { Button, Card } from '../components/ui';
import { releaseFocus } from '../nui';
import { ConfigEditor } from './ConfigEditor';
import { AuditPage, Dashboard, EventsPage, LedgerPage, MonitoringPage, RewardsPage, StaffPage, SystemPage } from './Pages';
import { AttractionReadiness, GroupsPanel, ParticipantsPanel, RotationPanel } from '../shared/Operations';

interface NavItem { id: string; label: string; perm?: string; icon?: string; group: string }

const NAV: NavItem[] = [
  { id: 'dashboard', label: 'Dashboard', group: 'Overview' },
  { id: 'events', label: 'Events & history', group: 'Overview', perm: 'events.history' },
  { id: 'live', label: 'Live operations', group: 'Overview' },
  { id: 'cfg:general', label: 'General', group: 'Configuration', perm: 'config.view' },
  { id: 'cfg:registration', label: 'Registration & tickets', group: 'Configuration', perm: 'config.view' },
  { id: 'cfg:groups', label: 'Colours & groups', group: 'Configuration', perm: 'config.view' },
  { id: 'cfg:rotation', label: 'Rotation', group: 'Configuration', perm: 'config.view' },
  { id: 'cfg:scoring', label: 'Scoring', group: 'Configuration', perm: 'config.view' },
  { id: 'cfg:leaderboard', label: 'Leaderboard', group: 'Configuration', perm: 'config.view' },
  { id: 'cfg:prizes', label: 'Prizes & results', group: 'Configuration', perm: 'config.view' },
  { id: 'cfg:rewards', label: 'Reward items', group: 'Configuration', perm: 'config.view' },
  { id: 'cfg:audio', label: 'Audio', group: 'Configuration', perm: 'config.view' },
  { id: 'cfg:attractions.shooting', label: 'Shooting Gallery', icon: 'shooting', group: 'Attractions', perm: 'config.view' },
  { id: 'cfg:attractions.wheel', label: 'Wheel of Misfortune', icon: 'wheel', group: 'Attractions', perm: 'config.view' },
  { id: 'cfg:attractions.fortune', label: 'Fortune Teller', icon: 'fortune', group: 'Attractions', perm: 'config.view' },
  { id: 'cfg:attractions.puppets', label: "Puppet Master's Theatre", icon: 'puppets', group: 'Attractions', perm: 'config.view' },
  { id: 'cfg:attractions.deception', label: 'Hall of Deception', icon: 'deception', group: 'Attractions', perm: 'config.view' },
  { id: 'cfg:attractions.horror', label: 'House of Horrors', icon: 'horror', group: 'Attractions', perm: 'config.view' },
  { id: 'participants', label: 'Participants', group: 'People', perm: 'participants.view' },
  { id: 'ledger', label: 'Score ledger', group: 'People', perm: 'scores.view' },
  { id: 'rewards', label: 'Rewards', group: 'People', perm: 'rewards.manage' },
  { id: 'staff', label: 'Staff & roles', group: 'People', perm: 'staff.manage' },
  { id: 'monitoring', label: 'Monitoring centre', group: 'System', perm: 'monitoring.view' },
  { id: 'audit', label: 'Audit trail', group: 'System', perm: 'audit.view' },
  { id: 'system', label: 'Items & health', group: 'System' },
];

// Owner / administrator configurator. Navigation hides pages the user cannot
// use; every request is still permission-checked by the server.
export default function AdminApp({ onClose }: { onClose: () => void }) {
  const perms = useStore((s) => s.permissions);
  const role = useStore((s) => s.role);
  const event = useStore((s) => s.event);
  const [page, setPage] = useState('dashboard');
  const items = NAV.filter((n) => !n.perm || perms.has(n.perm));
  const groups = Array.from(new Set(items.map((i) => i.group)));

  let content: React.ReactNode = null;
  if (page.startsWith('cfg:')) content = <ConfigEditor key={page} section={page.slice(4)} />;
  else if (page === 'dashboard') content = <Dashboard />;
  else if (page === 'events') content = <EventsPage />;
  else if (page === 'live') content = (
    <div className="stack">
      <Card title="Rotation"><RotationPanel /></Card>
      <Card title="Groups"><GroupsPanel /></Card>
      <Card title="Attractions"><AttractionReadiness /></Card>
    </div>
  );
  else if (page === 'participants') content = <Card title="Participants"><ParticipantsPanel /></Card>;
  else if (page === 'ledger') content = <LedgerPage />;
  else if (page === 'rewards') content = <RewardsPage />;
  else if (page === 'staff') content = <StaffPage />;
  else if (page === 'monitoring') content = <MonitoringPage />;
  else if (page === 'audit') content = <AuditPage />;
  else if (page === 'system') content = <SystemPage />;

  return (
    <div className="overlay-full">
      <Backdrop name="admin" className="app-shell admin-shell">
        <aside className="sidebar">
          <div className="brand"><Icon name="horror" size={26} /><div><strong>Carnival of the Damned</strong><span>Configurator</span></div></div>
          {groups.map((g) => (
            <div key={g} className="nav-group">
              <div className="nav-title">{g}</div>
              {items.filter((i) => i.group === g).map((i) => (
                <button key={i.id} className={`nav-item ${page === i.id ? 'nav-active' : ''}`} onClick={() => setPage(i.id)}>
                  {i.icon ? <Icon name={i.icon} size={14} /> : null}{i.label}
                </button>
              ))}
            </div>
          ))}
        </aside>
        <div className="shell-body">
          <header className="shell-head">
            <div className="shell-title">
              <h1>{items.find((i) => i.id === page)?.label ?? ''}</h1>
              <span className="muted">{event?.active ? `${event.name} · ${event.stateLabel}` : 'No active event'} · role: {role ?? 'none'}</span>
            </div>
            <div className="btn-row">
              <Button small onClick={() => releaseFocus('admin')} title="Hide the panel so you can move (e.g. to capture coordinates); reopen with /carnivaladmin">Minimise</Button>
              <Button small variant="ghost" onClick={onClose}>Close</Button>
            </div>
          </header>
          <main className="shell-main">{content}</main>
        </div>
      </Backdrop>
    </div>
  );
}

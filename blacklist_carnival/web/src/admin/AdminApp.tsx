import React, { useState } from 'react';
import { useStore } from '../store';
import { Backdrop, Icon } from '../components/Art';
import { Button, StatusPill, Tabs } from '../components/ui';
import { releaseFocus } from '../nui';
import { ConfigEditor } from './ConfigEditor';
import { AuditPage, EventsPage, HealthPage, LedgerPage, MonitoringPage, Overview, RewardsPage, StaffPage } from './Pages';
import { ParticipantsPanel, StaffLeaderboard } from '../shared/Operations';
import { PropsPage } from './PropsPage';
import { ShopPage } from './ShopPage';

type PageId = 'overview' | 'players' | 'nights' | 'settings' | 'system';
interface Tab { id: string; label: string; perm?: string }
interface Page { id: PageId; label: string; icon: string; blurb: string; tabs?: Tab[]; perm?: string }

const PAGES: Page[] = [
  { id: 'overview', label: 'Overview', icon: 'home', blurb: 'How the carnival is doing right now' },
  {
    id: 'players', label: 'Players', icon: 'people', blurb: 'Tickets, scores, prizes and the prize counter',
    tabs: [
      { id: 'participants', label: 'Participants', perm: 'participants.view' },
      { id: 'leaderboard', label: 'Leaderboard', perm: 'leaderboard.staff' },
      { id: 'ledger', label: 'Score ledger', perm: 'scores.view' },
      { id: 'rewards', label: 'Prize deliveries', perm: 'rewards.manage' },
      { id: 'shop', label: 'Prize counter', perm: 'shop.manage' },
    ],
  },
  { id: 'nights', label: 'Nights & results', icon: 'crown', blurb: 'Every carnival night, its results and exports', perm: 'events.history' },
  {
    id: 'settings', label: 'Settings', icon: 'gear', blurb: 'Locations, rules, content and props',
    tabs: [
      { id: 'carnival', label: 'Carnival', perm: 'config.view' },
      { id: 'attractions', label: 'Attractions', perm: 'config.view' },
      { id: 'scoring', label: 'Scoring & prizes', perm: 'config.view' },
      { id: 'props', label: 'Props', perm: 'props.manage' },
    ],
  },
  {
    id: 'system', label: 'System', icon: 'shield', blurb: 'Health, roles and logs',
    tabs: [
      { id: 'health', label: 'Health & items' },
      { id: 'roles', label: 'Roles', perm: 'staff.manage' },
      { id: 'monitoring', label: 'Monitoring', perm: 'monitoring.view' },
      { id: 'audit', label: 'Audit trail', perm: 'audit.view' },
    ],
  },
];

// Settings sections shown as a second row of chips inside each settings tab.
const SETTING_SECTIONS: Record<string, { id: string; label: string; icon?: string }[]> = {
  carnival: [
    { id: 'general', label: 'General' },
    { id: 'registration', label: 'Ticket booth' },
    { id: 'groups', label: 'Ticket colours' },
    { id: 'rotation', label: 'Rotation' },
    { id: 'audio', label: 'Audio' },
    { id: 'ambience', label: 'Ambient sound' },
  ],
  attractions: [
    { id: 'attractions.shooting', label: 'Shooting Gallery', icon: 'shooting' },
    { id: 'attractions.wheel', label: 'Wheel', icon: 'wheel' },
    { id: 'attractions.fortune', label: 'Fortune Teller', icon: 'fortune' },
    { id: 'attractions.puppets', label: 'Theatre', icon: 'puppets' },
    { id: 'attractions.deception', label: 'Hall of Deception', icon: 'deception' },
    { id: 'attractions.horror', label: 'House of Horrors', icon: 'horror' },
  ],
  scoring: [
    { id: 'scoring', label: 'Scoring' },
    { id: 'leaderboard', label: 'Leaderboard' },
    { id: 'prizes', label: 'Prizes & results' },
    { id: 'rewards', label: 'Reward items' },
    { id: 'shop', label: 'Prize counter' },
  ],
};

function SettingsPage({ tab }: { tab: string }) {
  const sections = SETTING_SECTIONS[tab] ?? [];
  const [picked, setPicked] = useState<Record<string, string>>({});
  const section = picked[tab] ?? sections[0]?.id;
  return (
    <div className="stack">
      <div className="chips" role="tablist">
        {sections.map((s) => (
          <button key={s.id} role="tab" aria-selected={s.id === section} className={`chip ${s.id === section ? 'chip-active' : ''}`}
            onClick={() => setPicked({ ...picked, [tab]: s.id })}>
            {s.icon ? <Icon name={s.icon} size={15} /> : null}{s.label}
          </button>
        ))}
      </div>
      {section ? <ConfigEditor key={section} section={section} /> : null}
    </div>
  );
}

// Owner / administrator panel. Navigation hides what the user cannot use; every
// request is still permission-checked by the server.
export default function AdminApp({ onClose }: { onClose: () => void }) {
  const perms = useStore((s) => s.permissions);
  const role = useStore((s) => s.role);
  const event = useStore((s) => s.event);
  const [pageId, setPageId] = useState<PageId>('overview');
  const [tabs, setTabs] = useState<Record<string, string>>({});

  const allowedTabs = (p: Page) => (p.tabs ?? []).filter((t) => !t.perm || perms.has(t.perm));
  const pages = PAGES.filter((p) => (p.perm ? perms.has(p.perm) : true) && (!p.tabs || allowedTabs(p).length > 0));
  const page = pages.find((p) => p.id === pageId) ?? pages[0];
  const pageTabs = allowedTabs(page);
  const tab = tabs[page.id] && pageTabs.some((t) => t.id === tabs[page.id]) ? tabs[page.id] : pageTabs[0]?.id;

  let content: React.ReactNode = null;
  if (page.id === 'overview') content = <Overview onNavigate={(p) => setPageId(p as PageId)} />;
  else if (page.id === 'nights') content = <EventsPage />;
  else if (page.id === 'settings') content = tab === 'props' ? <PropsPage /> : <SettingsPage key={tab} tab={tab} />;
  else if (page.id === 'players') {
    if (tab === 'participants') content = <ParticipantsPanel />;
    else if (tab === 'leaderboard') content = <StaffLeaderboard />;
    else if (tab === 'ledger') content = <LedgerPage />;
    else if (tab === 'rewards') content = <RewardsPage />;
    else if (tab === 'shop') content = <ShopPage />;
  } else if (page.id === 'system') {
    if (tab === 'health') content = <HealthPage />;
    else if (tab === 'roles') content = <StaffPage />;
    else if (tab === 'monitoring') content = <MonitoringPage />;
    else if (tab === 'audit') content = <AuditPage />;
  }

  const open = event?.active && (event.state === 'running' || event.state === 'between_rounds');
  return (
    <div className="overlay-full">
      <Backdrop name="admin" className="app-shell">
        <aside className="sidebar">
          <div className="brand">
            <div className="brand-mark"><Icon name="horror" size={22} /></div>
            <div><strong>Carnival of the Damned</strong><span>Ringmaster's office</span></div>
          </div>
          <nav className="nav">
            {pages.map((p) => (
              <button key={p.id} className={`nav-item ${page.id === p.id ? 'nav-active' : ''}`} onClick={() => setPageId(p.id)}>
                <Icon name={p.icon} size={18} />
                <span>{p.label}</span>
              </button>
            ))}
          </nav>
          <div className="sidebar-foot">
            <span className={`status-dot ${open ? 'status-dot-on' : ''}`} />
            <div>
              <strong>{event?.active ? (open ? 'Carnival open' : event.stateLabel) : 'Carnival closed'}</strong>
              <span>{event?.mode === 'walkup' ? 'Walk-up' : event?.active ? 'Timed rounds' : '—'} · {role ?? 'no role'}</span>
            </div>
          </div>
        </aside>
        <div className="shell-body">
          <header className="shell-head">
            <div className="shell-title">
              <h1>{page.label}</h1>
              <span className="muted">{page.blurb}</span>
            </div>
            <div className="btn-row">
              {event?.active ? <StatusPill status={event.state} /> : null}
              <Button small variant="ghost" onClick={() => releaseFocus('admin')} title="Hide the panel so you can move (e.g. to capture coordinates); reopen with /carnivaladmin">Minimise</Button>
              <Button small variant="ghost" onClick={onClose}>Close</Button>
            </div>
          </header>
          {pageTabs.length > 1 ? (
            <div className="shell-tabs">
              <Tabs tabs={pageTabs.map((t) => ({ id: t.id, label: t.label }))} active={tab} onChange={(id) => setTabs({ ...tabs, [page.id]: id })} />
            </div>
          ) : null}
          <main className="shell-main">{content}</main>
        </div>
      </Backdrop>
    </div>
  );
}

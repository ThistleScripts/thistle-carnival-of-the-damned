import React, { useState } from 'react';
import { useStore } from '../store';
import { Backdrop, Icon } from '../components/Art';
import { Button, Card } from '../components/ui';
import { releaseFocus } from '../nui';
import { ActivityFeed, AttractionReadiness, EventControls, GroupsPanel, ParticipantsPanel, ReportProblem, RotationPanel, StaffLeaderboard } from '../shared/Operations';
import { CONSOLES } from './Consoles';
import { ATTRACTION_IDS } from '../format';

type Tab = 'overview' | 'participants' | 'leaderboard' | 'activity' | string;

// Event staff panel: built for speed during a live event. Shows only the tools
// the staff member's permissions allow; the server enforces the same rules.
export default function StaffApp({ onClose }: { onClose: () => void }) {
  const perms = useStore((s) => s.permissions);
  const role = useStore((s) => s.role);
  const event = useStore((s) => s.event);
  const [tab, setTab] = useState<Tab>('overview');
  const [reporting, setReporting] = useState(false);

  const consoles = ATTRACTION_IDS.filter((a) => perms.has(`attractions.operate.${a}`));
  const tabs: { id: Tab; label: React.ReactNode }[] = [
    { id: 'overview', label: 'Overview' },
    ...(perms.has('participants.view') ? [{ id: 'participants', label: 'Participants' }] : []),
    ...consoles.map((a) => ({ id: a, label: <><Icon name={a} size={14} /> {CONSOLES[a].label}</> })),
    ...(perms.has('leaderboard.staff') ? [{ id: 'leaderboard', label: 'Leaderboard' }] : []),
    { id: 'activity', label: 'Activity' },
  ];
  const Console = CONSOLES[tab]?.component;

  return (
    <div className="overlay-full">
      <Backdrop name="staff" className="app-shell">
        <header className="shell-head">
          <div className="shell-title">
            <h1>Event Staff</h1>
            <span className="muted">{event?.active ? `${event.name} · ${event.stateLabel}` : 'No active event'} · role: {role ?? 'none'}</span>
          </div>
          <div className="btn-row">
            <Button small onClick={() => setReporting(true)}>Report problem</Button>
            <Button small onClick={() => releaseFocus('staff')} title="Hide the panel so you can move; reopen with /carnivalstaff">Minimise</Button>
            <Button small variant="ghost" onClick={onClose}>Close</Button>
          </div>
        </header>
        <nav className="shell-tabs">
          {tabs.map((t) => (
            <button key={t.id} className={`tab ${tab === t.id ? 'tab-active' : ''}`} onClick={() => setTab(t.id)}>{t.label}</button>
          ))}
        </nav>
        <main className="shell-main">
          {tab === 'overview' ? (
            <div className="stack">
              <Card title="Event"><EventControls /></Card>
              <Card title="Rotation"><RotationPanel /></Card>
              <Card title="Groups"><GroupsPanel /></Card>
              <Card title="Attractions"><AttractionReadiness /></Card>
            </div>
          ) : tab === 'participants' ? (
            <Card title="Participants"><ParticipantsPanel /></Card>
          ) : tab === 'leaderboard' ? (
            <Card title="Live leaderboard"><StaffLeaderboard /></Card>
          ) : tab === 'activity' ? (
            <Card title="Recent activity (this event)"><ActivityFeed /></Card>
          ) : Console ? <Console /> : null}
        </main>
        {reporting ? <ReportProblem onClose={() => setReporting(false)} /> : null}
      </Backdrop>
    </div>
  );
}

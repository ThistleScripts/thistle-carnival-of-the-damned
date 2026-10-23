import { useEffect } from 'react';
import { closeViewState, getState, useStore } from './store';
import { closeView, isNui } from './nui';
import { ConfirmHost, ToastHost } from './components/ui';
import AdminApp from './admin/AdminApp';
import { Hud } from './player/Hud';
import { TicketCard } from './player/TicketCard';
import { LeaderboardView } from './player/LeaderboardView';
import { WheelGame } from './player/WheelGame';
import { FortuneGame, FortuneCard } from './player/FortuneGame';
import { DeceptionTerminal, DeceptionReveal } from './player/DeceptionTerminal';
import { TheatreCard } from './player/TheatreCard';
import { HorrorHud, HorrorResult } from './player/HorrorHud';
import { ShootingGame } from './player/ShootingGame';
import { TheatreVote } from './player/TheatreVote';
import { ResultsBanner } from './player/ResultsBanner';
import { PlayerHub } from './player/PlayerHub';
import { ErrorBoundary } from './components/ErrorBoundary';
import { ShopView } from './player/ShopView';
import { PrizeReveal } from './player/PrizeReveal';

// Views that hold NUI focus; Escape closes the top-most one.
const FOCUS_ORDER = ['shop', 'ticket', 'wheel', 'fortune', 'deception', 'shootingGame', 'theatreVote', 'leaderboard', 'player', 'admin'];

export function close(view: string) {
  closeViewState(view);
  closeView(view);
}

export default function App() {
  const views = useStore((s) => s.views);
  const minimised = useStore((s) => s.minimised);

  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      if (document.querySelector('.modal-backdrop')) return; // modals handle their own Escape
      const open = getState().views;
      for (const v of FOCUS_ORDER) {
        if (open[v] && !getState().minimised[v]) {
          close(v);
          return;
        }
      }
    };
    window.addEventListener('keydown', h);
    return () => window.removeEventListener('keydown', h);
  }, []);

  const show = (v: string) => views[v] !== undefined && !minimised[v];

  return (
    <ErrorBoundary onReset={() => { for (const v of Object.keys(getState().views)) close(v); }}>
    <div className={`app ${isNui ? '' : 'app-browser'}`}>
      <Hud />
      <HorrorHud />
      {show('theatre') && <TheatreCard data={views.theatre} />}
      {show('fortuneCard') && <FortuneCard data={views.fortuneCard} />}
      {show('deceptionReveal') && <DeceptionReveal data={views.deceptionReveal} />}
      {show('horrorResult') && <HorrorResult data={views.horrorResult} />}
      {show('prizeReveal') && <PrizeReveal data={views.prizeReveal} onClose={() => close('prizeReveal')} />}
      {show('results') && <ResultsBanner data={views.results} onClose={() => close('results')} />}

      {show('player') && <PlayerHub onClose={() => close('player')} />}
      {show('shop') && <ShopView data={views.shop} onClose={() => close('shop')} />}
      {show('ticket') && <TicketCard data={views.ticket} onClose={() => close('ticket')} />}
      {show('leaderboard') && <LeaderboardView initial={views.leaderboard} onClose={() => close('leaderboard')} />}
      {show('wheel') && <WheelGame data={views.wheel} onClose={() => close('wheel')} />}
      {show('fortune') && <FortuneGame data={views.fortune} onClose={() => close('fortune')} />}
      {show('deception') && <DeceptionTerminal data={views.deception} onClose={() => close('deception')} />}
      {show('shootingGame') && <ShootingGame data={views.shootingGame} onClose={() => close('shootingGame')} />}
      {show('theatreVote') && <TheatreVote data={views.theatreVote} onClose={() => close('theatreVote')} />}
      {show('admin') && <AdminApp onClose={() => close('admin')} />}

      {!isNui && Object.keys(views).length === 0 && (
        <div className="browser-note">
          <h1>Carnival of the Damned</h1>
          <p>This interface runs inside FiveM. Open it in game with <code>/carnival</code> or <code>/carnivaladmin</code>.</p>
        </div>
      )}
      <ConfirmHost />
      <ToastHost />
    </div>
    </ErrorBoundary>
  );
}

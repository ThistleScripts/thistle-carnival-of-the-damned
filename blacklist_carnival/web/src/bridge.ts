import { closeViewState, invalidate, openView, setState, syncServerTime } from './store';
import { playSound, setAmbient, stopAll, stopSound } from './audio';
import { toast } from './components/ui';
import { ATTRACTION_SHORT, signed } from './format';

// Messages from client Lua: { action, data }
function handlePush(channel: string, data: any) {
  switch (channel) {
    case 'bootstrap':
      syncServerTime(data.serverTime);
      setState({
        settings: data.settings ?? null,
        event: data.event ?? null,
        participant: data.participant ?? null,
        permissions: new Set<string>(data.permissions ?? []),
        role: data.role ?? null,
      });
      break;
    case 'event':
      syncServerTime(data.serverTime);
      setState({ event: data });
      break;
    case 'participant':
      setState({ participant: data });
      break;
    case 'perms':
      setState({ permissions: new Set<string>(data.permissions ?? []), role: data.role ?? null });
      break;
    case 'settings':
      setState({ settings: data });
      break;
    case 'leaderboard':
      setState({ leaderboard: data });
      break;
    case 'rank':
      setState((s) => ({ participant: s.participant ? { ...s.participant, rank: data.rank, total: data.total } : s.participant }));
      break;
    case 'score': {
      setState((s) => ({ lastScore: { ...data, at: Date.now() }, participant: s.participant ? { ...s.participant, total: data.total } : s.participant }));
      if (data.delta !== 0) {
        const where = data.attraction ? ATTRACTION_SHORT[data.attraction] ?? data.attraction : 'Carnival';
        toast(`${signed(data.delta)} points · ${data.reason ?? where}`, data.delta > 0 ? 'success' : 'warning');
      }
      break;
    }
    case 'shooting':
      setState({ shooting: { ...data, receivedAt: Date.now() } });
      break;
    case 'wallet':
      setState({ wallet: { balance: data.balance ?? 0, earned: data.earned ?? 0, spent: data.spent ?? 0, currency: data.currency ?? 'Prize Tickets' } });
      if (data.delta > 0) toast(`+${data.delta} ${data.currency ?? 'prize tickets'}${data.attraction ? ` from ${ATTRACTION_SHORT[data.attraction] ?? data.attraction}` : ''}`, 'success');
      break;
    case 'invalidate':
      if (Array.isArray(data)) invalidate(data);
      break;
    default:
      break;
  }
}

export function onLuaMessage(ev: MessageEvent) {
  const msg = ev.data;
  if (!msg || typeof msg !== 'object' || typeof msg.action !== 'string') return;
  const data = msg.data ?? {};
  switch (msg.action) {
    case 'open':
      openView(data.view, data.data);
      break;
    case 'close':
      closeViewState(data.view);
      break;
    case 'closeAll':
      setState({ views: {}, minimised: {} });
      break;
    case 'minimised':
      setState((s) => ({ minimised: { ...s.minimised, [data.view]: true } }));
      break;
    case 'push':
      handlePush(data.channel, data.data ?? {});
      break;
    case 'hud':
      if (data.toggle) setState((s) => ({ hudHidden: !s.hudHidden }));
      else setState({ hudVisible: !!data.visible });
      break;
    case 'audio':
      if (data.action === 'play') playSound(data.sound, data.volume ?? 1, !!data.loop);
      else if (data.action === 'stop') stopSound(data.sound);
      else if (data.action === 'stopAll') stopAll();
      break;
    case 'inventory':
      if (typeof data.imagePath === 'string' && data.imagePath) setState({ inventoryImagePath: data.imagePath.replace(/\/+$/, '') });
      break;
    case 'ambient':
      setAmbient(Array.isArray(data.levels) ? data.levels : []);
      break;
    case 'shooting':
      if (data.serverTime) syncServerTime(data.serverTime);
      setState((s) => ({ shooting: data.active === false ? { active: false } : { ...s.shooting, ...data } }));
      break;
    case 'maze':
      if (data.serverTime) syncServerTime(data.serverTime);
      setState((s) => ({ maze: data.active === false ? { active: false } : { ...s.maze, ...data } }));
      break;
    case 'horror':
      if (data.serverTime) syncServerTime(data.serverTime);
      setState((s) => ({ horror: data.active === false ? { active: false } : { ...s.horror, ...data } }));
      break;
    default:
      break;
  }
}

let installed = false;
export function installBridge() {
  if (installed) return;
  installed = true;
  window.addEventListener('message', onLuaMessage);
}

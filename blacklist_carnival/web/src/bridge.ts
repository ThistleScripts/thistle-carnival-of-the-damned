import { closeViewState, getState, invalidate, openView, setState, syncServerTime } from './store';
import { playSound, stopAll, stopSound } from './audio';
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
    case 'invalidate':
      if (Array.isArray(data)) invalidate(data);
      break;
    case 'deception': {
      // keep the open terminal in sync with server pushes
      const v = getState().views.deception;
      if (v && data && data.roundId) openView('deception', { ...v, ...data });
      break;
    }
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
    case 'shooting':
      if (data.serverTime) syncServerTime(data.serverTime);
      setState((s) => ({ shooting: data.active === false ? { active: false } : { ...s.shooting, ...data } }));
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

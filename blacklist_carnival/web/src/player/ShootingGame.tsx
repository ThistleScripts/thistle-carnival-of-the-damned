import { useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../nui';
import { useStore } from '../store';
import { Backdrop } from '../components/Art';
import { Button } from '../components/ui';
import { playSound } from '../audio';
import { errorText } from '../i18n';
import { signed } from '../format';

// The Shooting Gallery mini-game. Targets slide across lanes; aim with the mouse
// and click to shoot. The schedule comes from the server, every click is sent to
// the server, and the server decides whether it hit and how many points it is
// worth. In preview mode everything is local and nothing is sent.

interface PlanTarget { id: number; t: number; life: number; kind: 'normal' | 'special' | 'decoy'; lane: number; dir: number }
interface Popup { id: number; x: number; y: number; text: string; good: boolean }

function previewPlan(duration: number, lanes: number, life: number): PlanTarget[] {
  const out: PlanTarget[] = [];
  const count = 40;
  for (let i = 0; i < count; i++) {
    const r = Math.random();
    const kind = r < 0.1 ? 'special' : r < 0.22 ? 'decoy' : 'normal';
    const l = kind === 'special' ? life * 0.65 : life;
    out.push({ id: i + 1, t: Math.min((i * (duration - life)) / count + Math.random() * 400, duration - l), life: l, kind, lane: 1 + Math.floor(Math.random() * lanes), dir: Math.random() < 0.5 ? 1 : -1 });
  }
  return out;
}

const PREVIEW_POINTS = { normal: 5, bull: 3, special: 15, decoy: -10 };

function TargetArt({ kind }: { kind: string }) {
  if (kind === 'decoy') {
    return (
      <svg viewBox="0 0 100 100" className="sg-art">
        <rect x="38" y="8" width="24" height="10" rx="3" fill="#6e6a5c" />
        <path d="M30 22 h40 l-6 62 h-28 z" fill="rgba(220,235,255,0.25)" stroke="#cfd9e6" strokeWidth="4" />
        <path d="M50 40 c10 12 6 26 0 30 c-6 -4 -10 -18 0 -30 z" fill="#9fd4ff" />
        <rect x="32" y="84" width="36" height="8" rx="3" fill="#6e6a5c" />
      </svg>
    );
  }
  const gold = kind === 'special';
  return (
    <svg viewBox="0 0 100 100" className="sg-art">
      <circle cx="50" cy="50" r="47" fill={gold ? '#e6be46' : '#f2e8d8'} stroke={gold ? '#fff2b0' : '#b8964d'} strokeWidth="4" />
      <circle cx="50" cy="50" r="34" fill={gold ? '#b8862a' : '#9e1b26'} />
      <circle cx="50" cy="50" r="22" fill={gold ? '#e6be46' : '#f2e8d8'} />
      <circle cx="50" cy="50" r="12" fill={gold ? '#fff2b0' : '#c42a37'} />
    </svg>
  );
}

export function ShootingGame({ data, onClose }: { data: any; onClose: () => void }) {
  const preview = !!data.preview;
  const duration: number = data.duration ?? 45000;
  const lanes: number = data.lanes ?? 3;
  const plan: PlanTarget[] = useMemo(() => data.plan ?? previewPlan(duration, lanes, data.lifetime ?? 2800), [data.gameId, preview]);
  const countdown: number = data.countdownMs ?? 3000;
  const startRef = useRef(performance.now() - (data.elapsedMs ?? -countdown) - countdown);
  const hitRef = useRef<Set<number>>(new Set((data.hitIds ?? []).map(Number)));
  const areaRef = useRef<HTMLDivElement>(null);
  const [, setFrame] = useState(0);
  const [total, setTotal] = useState<number>(data.total ?? 0);
  const [hits, setHits] = useState<number>(data.hits ?? 0);
  const [shots, setShots] = useState<number>(data.shots ?? 0);
  const [popups, setPopups] = useState<Popup[]>([]);
  const [mouse, setMouse] = useState<{ x: number; y: number } | null>(null);
  const [result, setResult] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const finishing = useRef(false);
  const push = useStore((s) => s.shooting);

  // animation loop
  useEffect(() => {
    let raf = 0;
    const loop = () => { setFrame((f) => (f + 1) % 1000000); raf = requestAnimationFrame(loop); };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, []);

  // server pushes: pause re-sync and the final result
  useEffect(() => {
    if (!push || preview) return;
    if (push.action === 'sync' && typeof push.elapsedMs === 'number') startRef.current = performance.now() - push.elapsedMs - countdown;
    if (push.action === 'result' && push.result && push.result.gameId === data.gameId) setResult(push.result);
  }, [push]);

  const gt = performance.now() - startRef.current - countdown; // game time in ms
  const over = gt > duration;

  useEffect(() => {
    if (!over || finishing.current || result) return;
    finishing.current = true;
    if (preview) {
      setResult({ points: total, hits, shots, accuracy: shots ? Math.round((hits / shots) * 100) : 0, accuracyBonus: 0, penalty: 0, preview: true });
      return;
    }
    let tries = 0;
    const attempt = async () => {
      const r = await api('shooting.finish', { gameId: data.gameId });
      if (r.ok) { setResult(r.data); return; }
      if ((r.error === 'too_early' || r.error === 'network') && tries++ < 10) { setTimeout(attempt, 600); return; }
      if (r.error !== 'stale') setError(errorText(r));
    };
    setTimeout(attempt, 300);
  }, [over]);

  const addPopup = (x: number, y: number, text: string, good: boolean) => {
    const id = Math.random();
    setPopups((p) => [...p, { id, x, y, text, good }]);
    setTimeout(() => setPopups((p) => p.filter((q) => q.id !== id)), 900);
  };

  const shoot = async (target: PlanTarget | null, ring: 'inner' | 'outer', x: number, y: number) => {
    if (gt < 0 || over || result) return;
    if (target) hitRef.current.add(target.id);
    if (preview) {
      setShots((s) => s + 1);
      if (!target) return;
      const pts = target.kind === 'decoy' ? PREVIEW_POINTS.decoy : target.kind === 'special' ? PREVIEW_POINTS.special : PREVIEW_POINTS.normal + (ring === 'inner' ? PREVIEW_POINTS.bull : 0);
      if (target.kind !== 'decoy') setHits((h) => h + 1);
      setTotal((t) => t + pts);
      addPopup(x, y, signed(pts), pts > 0);
      playSound(pts > 0 ? (ring === 'inner' ? 'shooting_bullseye' : 'shooting_hit') : 'wheel_lose', 0.6);
      return;
    }
    const r = await api('shooting.shot', { gameId: data.gameId, targetId: target?.id, ring });
    if (r.ok && r.data) {
      setTotal(r.data.total);
      setHits(r.data.hits);
      setShots(r.data.shots);
      if (r.data.hit) {
        addPopup(x, y, signed(r.data.points), r.data.points > 0);
        playSound(r.data.points > 0 ? (ring === 'inner' && r.data.kind === 'normal' ? 'shooting_bullseye' : 'shooting_hit') : 'wheel_lose', 0.6);
      }
    } else if (target && r.error !== 'too_fast') {
      // the server refused the hit; let the target be drawn again if still on screen
      hitRef.current.delete(target.id);
    }
  };

  const onAreaDown = (e: React.MouseEvent) => {
    const rect = areaRef.current!.getBoundingClientRect();
    playSound('wheel_tick', 0.25);
    shoot(null, 'outer', e.clientX - rect.left, e.clientY - rect.top);
  };

  const rect = areaRef.current?.getBoundingClientRect();
  const W = rect?.width ?? 1000;
  const H = rect?.height ?? 500;
  const size = Math.max(40, Math.min(110, (H / lanes) * 0.7));
  const visible = gt >= 0 && !over ? plan.filter((t) => !hitRef.current.has(t.id) && gt >= t.t && gt < t.t + t.life) : [];

  return (
    <div className="overlay-center">
      <Backdrop name="shooting" className="panel-frame shooting-frame">
        {preview ? <div className="preview-banner">PREVIEW — demo data, nothing is sent to the server</div> : null}
        <header className="frame-head">
          <div>
            <h2>{data.label ?? 'The Shooting Gallery'}</h2>
            <span className="muted">Hit the targets · golden targets are worth more · <strong>never shoot the spirit lanterns</strong></span>
          </div>
          <div className="sg-stats">
            <span>Time <strong>{Math.max(0, Math.ceil((duration - Math.max(0, gt)) / 1000))}s</strong></span>
            <span>Hits <strong>{hits}</strong>/{shots}</span>
            <span className="gold">Score <strong>{total}</strong></span>
            <Button variant="ghost" onClick={onClose}>{result ? 'Close' : 'Leave'}</Button>
          </div>
        </header>
        <div ref={areaRef} className="sg-area" onMouseDown={onAreaDown}
          onMouseMove={(e) => { const r = areaRef.current!.getBoundingClientRect(); setMouse({ x: e.clientX - r.left, y: e.clientY - r.top }); }}
          onMouseLeave={() => setMouse(null)}>
          {Array.from({ length: lanes }, (_, i) => <div key={i} className="sg-lane" style={{ top: `${(i / lanes) * 100}%`, height: `${100 / lanes}%` }} />)}
          {visible.map((t) => {
            const p = (gt - t.t) / t.life;
            const xr = t.dir > 0 ? p : 1 - p;
            const x = -size + xr * (W + size);
            const y = ((t.lane - 0.5) / lanes) * H - size / 2;
            return (
              <div key={t.id} className={`sg-target sg-${t.kind}`} style={{ left: x, top: y, width: size, height: size }}
                onMouseDown={(e) => {
                  e.stopPropagation();
                  const r = (e.currentTarget as HTMLDivElement).getBoundingClientRect();
                  const dx = e.clientX - (r.left + r.width / 2);
                  const dy = e.clientY - (r.top + r.height / 2);
                  const ring = Math.sqrt(dx * dx + dy * dy) < r.width * 0.15 ? 'inner' : 'outer';
                  const ar = areaRef.current!.getBoundingClientRect();
                  shoot(t, ring, e.clientX - ar.left, e.clientY - ar.top);
                }}>
                <TargetArt kind={t.kind} />
              </div>
            );
          })}
          {popups.map((p) => <div key={p.id} className={`sg-popup ${p.good ? 'good' : 'bad'}`} style={{ left: p.x, top: p.y }}>{p.text}</div>)}
          {mouse && !result ? <div className="sg-crosshair" style={{ left: mouse.x, top: mouse.y }} /> : null}
          {gt < 0 ? <div className="sg-countdown">{Math.ceil(-gt / 1000)}</div> : null}
          {over && !result && !error ? <div className="sg-countdown small">Tallying…</div> : null}
          {result ? (
            <div className="sg-result">
              <h3>{result.preview ? 'Preview over' : 'Time!'}</h3>
              <div className="sg-result-points">{result.points} points</div>
              <div className="muted">{result.hits} hits from {result.shots} shots ({result.accuracy}%)
                {result.bullseyes ? ` · ${result.bullseyes} bullseyes` : ''}{result.specials ? ` · ${result.specials} golden` : ''}
                {result.decoys ? ` · ${result.decoys} lanterns shot` : ''}{result.accuracyBonus ? ` · accuracy +${result.accuracyBonus}` : ''}</div>
              <Button variant="gold" onClick={onClose}>Close</Button>
            </div>
          ) : null}
          {error ? <div className="sg-result"><div className="state-error">{error}</div><Button onClick={onClose}>Close</Button></div> : null}
        </div>
      </Backdrop>
    </div>
  );
}

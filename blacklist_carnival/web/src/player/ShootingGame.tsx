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

interface PlanTarget { id: number; t: number; life: number; kind: 'normal' | 'special' | 'decoy'; lane: number; dir: number; round?: number }
interface Round { number: number; label: string; startMs: number; endMs: number; lanes: number; size: number; motion: string; pointsPercent: number; life: number; decoyChance: number; targets: number }
interface Popup { id: number; x: number; y: number; text: string; good: boolean }

// Round settings as configured (attractions.shooting.rounds) -> local timeline + plan for preview mode.
export function previewGame(cfgRounds: any[] | undefined, breakSeconds: number, fallback: { duration: number; lanes: number; life: number }) {
  const list = cfgRounds?.length ? cfgRounds : [{ label: 'Round', durationSeconds: fallback.duration / 1000, targetCount: 40, lanes: fallback.lanes, targetLifetimeMs: fallback.life, targetSize: 100, specialChance: 10, decoyChance: 12, motion: 'straight', pointsPercent: 100 }];
  const rounds: Round[] = [];
  const plan: PlanTarget[] = [];
  let offset = 0;
  let id = 0;
  list.forEach((rc, i) => {
    const duration = rc.durationSeconds * 1000;
    const span = Math.max(1, duration - rc.targetLifetimeMs);
    for (let k = 0; k < rc.targetCount; k++) {
      const roll = Math.random() * 100;
      const kind = roll < rc.specialChance ? 'special' : roll < rc.specialChance + rc.decoyChance ? 'decoy' : 'normal';
      const life = kind === 'special' ? rc.targetLifetimeMs * 0.65 : rc.targetLifetimeMs;
      const local = Math.min((k * span) / rc.targetCount + Math.random() * (span / rc.targetCount), duration - life);
      plan.push({ id: ++id, round: i + 1, t: offset + Math.max(0, local), life, kind, lane: 1 + Math.floor(Math.random() * rc.lanes), dir: Math.random() < 0.5 ? 1 : -1 });
    }
    rounds.push({ number: i + 1, label: rc.label, startMs: offset, endMs: offset + duration, lanes: rc.lanes, size: rc.targetSize, motion: rc.motion,
      pointsPercent: rc.pointsPercent, life: rc.targetLifetimeMs, decoyChance: rc.decoyChance, targets: rc.targetCount });
    offset += duration + (i < list.length - 1 ? breakSeconds * 1000 : 0);
  });
  return { rounds, plan, duration: rounds[rounds.length - 1].endMs };
}

// What makes a round harder than the one before, for the break card.
function changes(r: Round, prev?: Round): string[] {
  if (!prev) return [];
  const out: string[] = [];
  if (r.life < prev.life) out.push('Faster targets');
  if (r.size < prev.size) out.push('Smaller targets');
  if (r.lanes > prev.lanes) out.push('More lanes');
  if (r.decoyChance > prev.decoyChance) out.push('More spirit lanterns');
  if (r.motion === 'wave' && prev.motion !== 'wave') out.push('Targets weave');
  return out;
}

const multiplier = (pct: number) => `×${(pct / 100).toFixed(pct % 100 === 0 ? 0 : pct % 10 === 0 ? 1 : 2)}`;

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
  const game = useMemo(() => {
    if (data.plan && data.rounds) return { plan: data.plan as PlanTarget[], rounds: data.rounds as Round[], duration: data.duration as number };
    if (data.plan) {
      // single-round game from an older server
      const d = data.duration ?? 45000;
      return { plan: data.plan as PlanTarget[], duration: d, rounds: [{ number: 1, label: '', startMs: 0, endMs: d, lanes: data.lanes ?? 3, size: 100, motion: 'straight', pointsPercent: 100, life: 2800, decoyChance: 0, targets: data.plan.length }] };
    }
    return previewGame(data.rounds, data.roundBreakSeconds ?? 4, { duration: data.duration ?? 45000, lanes: data.lanes ?? 3, life: data.lifetime ?? 2800 });
  }, [data.gameId, preview]);
  const { plan, rounds, duration } = game;
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
  const roundIdx = rounds.findIndex((r) => Math.max(0, gt) < r.endMs);
  const round = rounds[roundIdx === -1 ? rounds.length - 1 : roundIdx];
  const between = gt >= 0 && gt < round.startMs; // break before this round
  const lanes = round.lanes;

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
    if (gt < 0 || over || result || (!target && between)) return;
    if (target) hitRef.current.add(target.id);
    if (preview) {
      setShots((s) => s + 1);
      if (!target) return;
      const pct = rounds[(target.round ?? 1) - 1]?.pointsPercent ?? 100;
      const base = target.kind === 'decoy' ? PREVIEW_POINTS.decoy : target.kind === 'special' ? PREVIEW_POINTS.special : PREVIEW_POINTS.normal + (ring === 'inner' ? PREVIEW_POINTS.bull : 0);
      const pts = Math.round((base * pct) / 100);
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
            {rounds.length > 1 ? <span>Round <strong>{round.number}</strong>/{rounds.length}</span> : null}
            <span>Time <strong>{between ? '—' : `${Math.max(0, Math.ceil((round.endMs - Math.max(round.startMs, gt)) / 1000))}s`}</strong></span>
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
            const tr = rounds[(t.round ?? 1) - 1] ?? round;
            const laneH = H / tr.lanes;
            const size = Math.max(30, Math.min(120, laneH * 0.7 * (tr.size / 100)));
            const p = (gt - t.t) / t.life;
            const xr = t.dir > 0 ? p : 1 - p;
            const x = -size + xr * (W + size);
            const wave = tr.motion === 'wave' ? Math.sin(p * Math.PI * 3 + t.id) * laneH * 0.22 : 0;
            const y = ((t.lane - 0.5) / tr.lanes) * H - size / 2 + wave;
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
          {gt < 0 ? (
            <div className="sg-countdown sg-roundcard">
              {rounds.length > 1 ? <div className="sg-round-kicker">Round 1 of {rounds.length}{round.label ? ` · ${round.label}` : ''}</div> : null}
              <div>{Math.ceil(-gt / 1000)}</div>
            </div>
          ) : null}
          {between && !over ? (
            <div className="sg-countdown sg-roundcard sg-break">
              <div className="sg-round-kicker">Round {round.number} of {rounds.length}</div>
              <div className="sg-round-name">{round.label}</div>
              <div className="sg-round-changes">
                {changes(round, rounds[round.number - 2]).map((c) => <span key={c} className="pill">{c}</span>)}
                {round.pointsPercent !== 100 ? <span className="pill pill-gold">Points {multiplier(round.pointsPercent)}</span> : null}
              </div>
              <div className="sg-round-count">{Math.ceil((round.startMs - gt) / 1000)}</div>
            </div>
          ) : null}
          {over && !result && !error ? <div className="sg-countdown small">Tallying…</div> : null}
          {result ? (
            <div className="sg-result">
              <h3>{result.preview ? 'Preview over' : 'Time!'}</h3>
              <div className="sg-result-points">{result.points} points</div>
              <div className="muted">{result.hits} hits from {result.shots} shots ({result.accuracy}%)
                {result.bullseyes ? ` · ${result.bullseyes} bullseyes` : ''}{result.specials ? ` · ${result.specials} golden` : ''}
                {result.decoys ? ` · ${result.decoys} lanterns shot` : ''}{result.accuracyBonus ? ` · accuracy +${result.accuracyBonus}` : ''}</div>
              {result.capped ? (
                <div className="sg-capped">Your run was worth {result.total} - the gallery pays out at most {result.maxScore} points.</div>
              ) : null}
              {result.rounds && result.rounds.length > 1 ? (
                <div className="sg-rounds">
                  {result.rounds.map((r: any) => (
                    <div key={r.number} className="sg-round-row">
                      <span>Round {r.number}{r.label ? ` · ${r.label}` : ''}{r.pointsPercent !== 100 ? <em> {multiplier(r.pointsPercent)}</em> : null}</span>
                      <span className="muted">{r.hits}/{r.targets} hit</span>
                      <strong>{signed(r.points)}</strong>
                    </div>
                  ))}
                </div>
              ) : null}
              <Button variant="gold" onClick={onClose}>Close</Button>
            </div>
          ) : null}
          {error ? <div className="sg-result"><div className="state-error">{error}</div><Button onClick={onClose}>Close</Button></div> : null}
        </div>
      </Backdrop>
    </div>
  );
}

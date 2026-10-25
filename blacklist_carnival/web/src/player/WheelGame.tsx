import { useEffect, useRef, useState } from 'react';
import { api, effect } from '../nui';
import { Backdrop } from '../components/Art';
import { Button } from '../components/ui';
import { playSound } from '../audio';
import { errorText } from '../i18n';
import { signed } from '../format';

interface Outcome { id: string; label: string; type: string; colour: string }

const GOOD = new Set(['small_points', 'large_points', 'bonus', 'treat', 'common_prize', 'rare_prize', 'special_prize']);

function segmentPath(i: number, n: number, r: number) {
  const a0 = (i / n) * Math.PI * 2 - Math.PI / 2;
  const a1 = ((i + 1) / n) * Math.PI * 2 - Math.PI / 2;
  const x0 = Math.cos(a0) * r, y0 = Math.sin(a0) * r;
  const x1 = Math.cos(a1) * r, y1 = Math.sin(a1) * r;
  const large = 1 / n > 0.5 ? 1 : 0;
  return `M0 0 L${x0} ${y0} A${r} ${r} 0 ${large} 1 ${x1} ${y1} Z`;
}

export function WheelGame({ data, onClose }: { data: any; onClose: () => void }) {
  const outcomes: Outcome[] = data.outcomes ?? [];
  const n = Math.max(outcomes.length, 1);
  const [rotation, setRotation] = useState(0);
  const [spinning, setSpinning] = useState(false);
  const [result, setResult] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);
  const [used, setUsed] = useState<number>(data.spinsUsed ?? 0);
  const [cooldown, setCooldown] = useState<number>(data.cooldownRemaining ?? 0);
  const tickTimer = useRef<number | null>(null);
  const duration = data.animationMs ?? 6000;

  useEffect(() => {
    if (cooldown <= 0) return;
    const t = setInterval(() => setCooldown((c) => Math.max(0, c - 1)), 1000);
    return () => clearInterval(t);
  }, [cooldown > 0]);

  useEffect(() => () => { if (tickTimer.current) clearInterval(tickTimer.current); }, []);

  const spin = async () => {
    setError(null);
    setResult(null);
    setSpinning(true);
    const r = data.preview
      ? (() => {
        const index = Math.floor(Math.random() * n) + 1;
        const o = outcomes[index - 1];
        return { ok: true, data: { index, outcome: { id: o.id, label: o.label, type: o.type }, points: 0, spinsUsed: used + 1, maxSpins: data.maxSpins, cooldownSeconds: 0 } } as any;
      })()
      : await api('wheel.spin', {});
    if (!r.ok || !r.data) {
      setSpinning(false);
      setError(errorText(r));
      return;
    }
    const res = r.data;
    // Land the pointer (top) in the middle of the winning segment.
    const seg = 360 / n;
    const target = 360 - ((res.index - 1) * seg + seg / 2);
    const jitter = (Math.random() - 0.5) * seg * 0.6;
    const base = rotation - (rotation % 360);
    setRotation(base + 360 * 6 + target + jitter);
    let interval = 60;
    const start = Date.now();
    const tick = () => {
      playSound('wheel_tick', 0.35);
      const elapsed = Date.now() - start;
      interval = 60 + (elapsed / duration) * 260;
      if (elapsed < duration - 200) tickTimer.current = window.setTimeout(tick, interval);
    };
    tick();
    window.setTimeout(() => {
      setSpinning(false);
      setResult(res);
      setUsed(res.spinsUsed);
      setCooldown(res.cooldownSeconds ?? 0);
      playSound(GOOD.has(res.outcome.type) ? 'wheel_win' : 'wheel_lose', 0.8);
      if (res.outcome.type === 'trick') effect('trick');
      if (res.outcome.type === 'treat') effect('treat');
    }, duration);
  };

  const remaining = (data.maxSpins ?? 0) - used;
  return (
    <div className="overlay-center">
      <Backdrop name="wheel" className="panel-frame wheel-frame">
        {data.preview ? <div className="preview-banner">PREVIEW — demo data, nothing is sent to the server</div> : null}
        <header className="frame-head">
          <div><div className="kicker">Step right up</div><h2>{data.label ?? 'The Wheel of Misfortune'}</h2><span className="muted">Spins left: {remaining} of {data.maxSpins}</span></div>
          <Button variant="ghost" onClick={onClose} disabled={spinning}>Leave</Button>
        </header>
        <div className={`wheel-stage ${spinning ? 'wheel-spinning' : ''}`}>
          <svg className="wheel-pointer" viewBox="0 0 44 54" aria-hidden="true">
            <defs>
              <linearGradient id="wheel-pointer-foil" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stopColor="#fff1c4" /><stop offset="0.5" stopColor="#d6ae60" /><stop offset="1" stopColor="#8a6629" />
              </linearGradient>
            </defs>
            <path d="M22 52 L4 14 A18 18 0 1 1 40 14 Z" fill="url(#wheel-pointer-foil)" stroke="#3a2410" strokeWidth="1.5" />
            <circle cx="22" cy="16" r="6" fill="#8e1626" stroke="#3a2410" strokeWidth="1.2" />
          </svg>
          <svg className="wheel" viewBox="-120 -120 240 240" style={{ transform: `rotate(${rotation}deg)`, transitionDuration: `${duration}ms` }}>
            <defs>
              <radialGradient id="wheel-sheen" cx="0" cy="0" r="100" gradientUnits="userSpaceOnUse">
                <stop offset="0.25" stopColor="#000" stopOpacity="0.35" />
                <stop offset="0.75" stopColor="#fff" stopOpacity="0.06" />
                <stop offset="1" stopColor="#000" stopOpacity="0.4" />
              </radialGradient>
              <linearGradient id="wheel-rim" x1="0" y1="-1" x2="0" y2="1">
                <stop offset="0" stopColor="#f6dfa2" /><stop offset="0.5" stopColor="#a5792f" /><stop offset="1" stopColor="#5d3f16" />
              </linearGradient>
              <radialGradient id="wheel-hub" cx="0.35" cy="0.3" r="0.8">
                <stop offset="0" stopColor="#fff1c4" /><stop offset="0.55" stopColor="#c99a48" /><stop offset="1" stopColor="#5d3f16" />
              </radialGradient>
            </defs>
            <circle r="118" fill="#1a0b10" />
            <circle r="114" fill="none" stroke="url(#wheel-rim)" strokeWidth="10" />
            {Array.from({ length: 24 }, (_, i) => {
              const a = (i / 24) * Math.PI * 2;
              return <circle key={i} className={`wheel-bulb ${i % 2 ? 'wheel-bulb-alt' : ''}`} cx={Math.cos(a) * 114} cy={Math.sin(a) * 114} r="3" />;
            })}
            {outcomes.map((o, i) => {
              const mid = ((i + 0.5) / n) * 360;
              return (
                <g key={o.id}>
                  <path d={segmentPath(i, n, 104)} fill={o.colour || (i % 2 ? '#2a0d12' : '#151015')} stroke="#d6ae60" strokeWidth="0.9" />
                  <text transform={`rotate(${mid}) translate(0 -66) rotate(90)`} className="wheel-label" textAnchor="middle" dominantBaseline="middle">
                    {o.label.length > 16 ? o.label.slice(0, 15) + '…' : o.label}
                  </text>
                </g>
              );
            })}
            <circle r="104" fill="url(#wheel-sheen)" pointerEvents="none" />
            <circle r="20" fill="url(#wheel-hub)" stroke="#3a2410" strokeWidth="1.5" />
            <circle r="7" fill="#8e1626" stroke="#3a2410" strokeWidth="1" />
          </svg>
        </div>
        <div className="wheel-foot">
          {result ? (
            <div className={`wheel-result ${GOOD.has(result.outcome.type) ? 'good' : 'bad'}`}>
              <div className="wheel-result-title">{result.outcome.label}</div>
              <div>
                {result.points ? `${signed(result.points)} points` : 'No points'}
                {result.reward ? ` · ${result.reward.count}x ${result.reward.label ?? result.reward.item} (${result.reward.status === 'pending' || result.reward.status === 'delivered' ? 'in your pockets' : result.reward.status === 'awaiting_approval' ? 'waiting on approval' : 'held at the ticket booth'})` : ''}
              </div>
            </div>
          ) : error ? <div className="state-error">{error}</div> : <div className="muted">The wheel remembers every hand that spins it…</div>}
          <Button variant="primary" busy={spinning} disabled={spinning || remaining <= 0 || cooldown > 0} onClick={spin}>
            {remaining <= 0 ? 'No spins left' : cooldown > 0 ? `Settling… ${cooldown}s` : 'Spin the wheel'}
          </Button>
        </div>
      </Backdrop>
    </div>
  );
}

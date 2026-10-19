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
    const r = await api('wheel.spin', {});
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
        <header className="frame-head">
          <div><h2>{data.label ?? 'The Wheel of Misfortune'}</h2><span className="muted">Spins left: {remaining} of {data.maxSpins}</span></div>
          <Button variant="ghost" onClick={onClose} disabled={spinning}>Leave</Button>
        </header>
        <div className="wheel-stage">
          <div className="wheel-pointer" aria-hidden="true">▼</div>
          <svg className="wheel" viewBox="-110 -110 220 220" style={{ transform: `rotate(${rotation}deg)`, transitionDuration: `${duration}ms` }}>
            <circle r="108" fill="#0c0a0b" stroke="#b8964d" strokeWidth="3" />
            {outcomes.map((o, i) => {
              const mid = ((i + 0.5) / n) * 360;
              return (
                <g key={o.id}>
                  <path d={segmentPath(i, n, 100)} fill={o.colour || (i % 2 ? '#2a0d12' : '#151015')} stroke="#b8964d" strokeWidth="0.8" />
                  <text transform={`rotate(${mid}) translate(0 -62) rotate(90)`} className="wheel-label" textAnchor="middle" dominantBaseline="middle">
                    {o.label.length > 16 ? o.label.slice(0, 15) + '…' : o.label}
                  </text>
                </g>
              );
            })}
            <circle r="16" fill="#151015" stroke="#b8964d" strokeWidth="2" />
            <circle r="5" fill="#b8964d" />
          </svg>
        </div>
        <div className="wheel-foot">
          {result ? (
            <div className={`wheel-result ${GOOD.has(result.outcome.type) ? 'good' : 'bad'}`}>
              <div className="wheel-result-title">{result.outcome.label}</div>
              <div>
                {result.points ? `${signed(result.points)} points` : 'No points'}
                {result.reward ? ` · ${result.reward.count}x ${result.reward.label ?? result.reward.item} (${result.reward.status === 'delivered' ? 'in your pockets' : result.reward.status === 'awaiting_approval' ? 'awaiting staff approval' : 'held at the booth'})` : ''}
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

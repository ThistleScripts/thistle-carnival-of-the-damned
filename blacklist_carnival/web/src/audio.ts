// Plays the bundled local sound files (web/public/sounds/*.ogg).

const playing = new Map<string, HTMLAudioElement[]>();

function url(name: string) {
  return `sounds/${name}.ogg`;
}

export function playSound(name: string, volume = 1, loop = false) {
  if (!/^[a-z0-9_]+$/.test(name)) return;
  if (loop) stopSound(name);
  const audio = new Audio(url(name));
  audio.volume = Math.max(0, Math.min(1, volume));
  audio.loop = loop;
  const list = playing.get(name) ?? [];
  list.push(audio);
  playing.set(name, list);
  audio.addEventListener('ended', () => {
    const l = playing.get(name);
    if (l) playing.set(name, l.filter((a) => a !== audio));
  });
  audio.play().catch(() => undefined);
}

export function stopSound(name: string) {
  for (const a of playing.get(name) ?? []) {
    a.pause();
    a.currentTime = 0;
  }
  playing.delete(name);
}

export function stopAll() {
  for (const name of Array.from(playing.keys())) stopSound(name);
  for (const ch of ambient.values()) ch.audio.pause();
  ambient.clear();
}

// ---------------------------------------------------------------------------
// Ambient zones: one looping channel per zone, faded towards the target volume
// sent by the client (which already accounts for distance and settings).
// ---------------------------------------------------------------------------
interface Channel { audio: HTMLAudioElement; sound: string; target: number }
const ambient = new Map<string, Channel>();
let fadeTimer: ReturnType<typeof setInterval> | null = null;
const FADE_STEP = 0.04; // per 50 ms ≈ 1.25 s from silent to full

function fadeTick() {
  let active = false;
  for (const [id, ch] of ambient) {
    const v = ch.audio.volume;
    const next = v < ch.target ? Math.min(ch.target, v + FADE_STEP) : Math.max(ch.target, v - FADE_STEP);
    ch.audio.volume = Math.max(0, Math.min(1, next));
    if (ch.target === 0 && ch.audio.volume === 0) {
      ch.audio.pause();
      ambient.delete(id);
    } else if (ch.audio.volume !== ch.target) {
      active = true;
    }
  }
  if (!active && fadeTimer) {
    clearInterval(fadeTimer);
    fadeTimer = null;
  }
}

export function setAmbient(levels: { id: string; sound: string; volume: number }[]) {
  const wanted = new Set<string>();
  for (const l of levels) {
    if (!l || typeof l.id !== 'string' || !/^[a-z0-9_]+$/.test(l.sound)) continue;
    wanted.add(l.id);
    let ch = ambient.get(l.id);
    if (ch && ch.sound !== l.sound) {
      ch.audio.pause();
      ch = undefined;
    }
    if (!ch) {
      const audio = new Audio(url(l.sound));
      audio.loop = true;
      audio.volume = 0;
      audio.play().catch(() => undefined);
      ch = { audio, sound: l.sound, target: 0 };
      ambient.set(l.id, ch);
    }
    ch.target = Math.max(0, Math.min(1, Number(l.volume) || 0));
  }
  for (const [id, ch] of ambient) if (!wanted.has(id)) ch.target = 0;
  if (!fadeTimer) fadeTimer = setInterval(fadeTick, 50);
}

export function ambientChannels() {
  return Array.from(ambient.entries()).map(([id, ch]) => ({ id, sound: ch.sound, target: ch.target }));
}

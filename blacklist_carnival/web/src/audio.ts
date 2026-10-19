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
}

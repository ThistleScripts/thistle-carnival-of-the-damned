#!/usr/bin/env python3
"""Generate the original sound effects bundled with Carnival of the Damned.

Every sound is synthesised from scratch (sine/noise/envelopes) so the resource
ships no third-party audio. Output: web/public/sounds/<name>.ogg (Vorbis, mono).

Usage:  python3 tools/generate_audio.py
Requires numpy and ffmpeg on PATH.
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'web', 'public', 'sounds')
rng = np.random.default_rng(1666)


def t(seconds):
    return np.linspace(0, seconds, int(SR * seconds), endpoint=False)


def env(n, attack=0.01, release=0.2, total=None):
    total = total or n / SR
    e = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def tone(freq, seconds, shape='sine'):
    x = t(seconds)
    ph = 2 * np.pi * freq * x
    if shape == 'sine':
        return np.sin(ph)
    if shape == 'saw':
        return 2 * ((freq * x) % 1) - 1
    if shape == 'square':
        return np.sign(np.sin(ph))
    if shape == 'tri':
        return 2 * np.abs(2 * ((freq * x) % 1) - 1) - 1
    raise ValueError(shape)


def bell(freq, seconds, decay=3.0):
    x = t(seconds)
    partials = [(1, 1.0), (2.0, 0.6), (2.76, 0.4), (5.4, 0.25), (8.9, 0.12)]
    s = sum(a * np.sin(2 * np.pi * freq * p * x) * np.exp(-decay * p * 0.5 * x) for p, a in partials)
    return s * env(len(x), 0.002, 0.05)


def lowpass(sig, cutoff):
    # simple one-pole low-pass
    a = np.exp(-2 * np.pi * cutoff / SR)
    out = np.zeros_like(sig)
    acc = 0.0
    for i, v in enumerate(sig):
        acc = (1 - a) * v + a * acc
        out[i] = acc
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def concat(*parts):
    return np.concatenate(parts)


def silence(seconds):
    return np.zeros(int(SR * seconds))


def normalise(sig, peak=0.85):
    m = np.max(np.abs(sig)) or 1
    return sig / m * peak


def write(name, sig):
    sig = normalise(sig)
    pcm = (sig * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, name + '.wav')
        with wave.open(wav, 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        dst = os.path.join(OUT, name + '.ogg')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', '3', dst], check=True)
    print('wrote', name)


def main():
    # Ambient drone loop (8 s, seamless): detuned low saws through a low-pass with slow beating + wind noise.
    x = t(8.0)
    drone = sum(np.sin(2 * np.pi * f * x) for f in (55.0, 55.5, 82.4, 110.25)) / 4
    wind = lowpass(rng.normal(0, 1, len(x)), 400) * (0.5 + 0.5 * np.sin(2 * np.pi * x / 8.0))
    creak = np.sin(2 * np.pi * (300 + 40 * np.sin(2 * np.pi * x * 0.25)) * x) * np.exp(-((x - 5.2) ** 2) * 40) * 0.3
    write('horror_ambient', drone * 0.7 + wind * 0.6 + creak)

    # Warning: two low dissonant bell strikes.
    write('horror_warning', mix(bell(196, 1.6), concat(silence(0.35), bell(207.6, 1.25))))

    # Final warning (<=10 s): fast heartbeat thumps with a rising whine.
    beat = lowpass(np.sin(2 * np.pi * 60 * t(0.12)) * env(int(SR * 0.12), 0.005, 0.1), 300)
    hb = concat(beat, silence(0.08), beat * 0.7, silence(0.35))
    whine = tone(880, 0.75) * np.linspace(0, 0.15, int(SR * 0.75))
    write('horror_final', mix(hb, whine))

    # End of run: deep gong + descending sweep.
    sweep_t = t(2.5)
    sweep = np.sin(2 * np.pi * (400 * np.exp(-sweep_t * 1.2)) * sweep_t) * np.exp(-sweep_t * 1.5) * 0.4
    write('horror_end', mix(bell(98, 3.5, decay=1.2), sweep))

    # Scare stinger: noise burst + screeching dissonant cluster.
    n = t(1.2)
    burst = rng.normal(0, 1, len(n)) * np.exp(-n * 6)
    cluster = sum(tone(f, 1.2, 'saw') for f in (740, 784, 830, 1108)) / 4 * np.exp(-n * 2.5)
    write('horror_scare', burst * 0.6 + cluster)

    # Wheel tick: short click.
    c = t(0.03)
    write('wheel_tick', rng.normal(0, 1, len(c)) * np.exp(-c * 250) + np.sin(2 * np.pi * 2400 * c) * np.exp(-c * 200))

    # Win: rising arpeggio in a minor key (still eerie).
    notes = [440, 523.25, 659.25, 880]
    win = concat(*[tone(f, 0.14, 'tri') * env(int(SR * 0.14), 0.005, 0.05) for f in notes], bell(880, 1.0))
    write('wheel_win', win)

    # Lose: descending tritone wah.
    lose_t = t(1.0)
    lose = np.sin(2 * np.pi * (330 - 120 * lose_t) * lose_t) * env(len(lose_t), 0.01, 0.4)
    write('wheel_lose', mix(lose, concat(silence(0.3), tone(233, 0.7, 'tri') * env(int(SR * 0.7), 0.01, 0.5) * 0.6)))

    # Notification chime: two bell tones.
    write('carnival_chime', mix(bell(659.25, 1.2, 4), concat(silence(0.15), bell(987.8, 1.05, 4) * 0.7)))

    # Round bell: three strikes.
    write('round_bell', concat(bell(523.25, 0.6, 2.5), bell(523.25, 0.6, 2.5), bell(392, 1.6, 1.8)))

    # Shooting hit / bullseye.
    h = t(0.18)
    write('shooting_hit', np.sin(2 * np.pi * 1200 * h) * np.exp(-h * 30) + rng.normal(0, 0.3, len(h)) * np.exp(-h * 60))
    write('shooting_bullseye', concat(bell(1318.5, 0.25, 8), bell(1760, 0.6, 6)))

    # Trick: wobbling, comic low "laugh" made of pitch-bent pulses (no voices).
    pulses = []
    for i in range(5):
        pt = t(0.16)
        f = 220 - i * 18
        pulses.append(np.sin(2 * np.pi * (f + 30 * np.sin(2 * np.pi * 18 * pt)) * pt) * env(len(pt), 0.01, 0.08))
        pulses.append(silence(0.05))
    write('trick_laugh', concat(*pulses))

    # Treat: sparkling high glissando.
    st_ = t(1.0)
    sparkle = sum(np.sin(2 * np.pi * (1500 + 1500 * st_ + k * 210) * st_) * np.exp(-st_ * (3 + k)) for k in range(4))
    write('treat_sparkle', sparkle)

    # ---- Ambient zone loops (seamless: every component completes whole cycles) ----
    # Midway organ (16 s): a slow, slightly detuned minor waltz on a reedy organ.
    bpm_beat = 16.0 / 48  # 48 beats (16 bars of 3/4)
    def organ(freq, seconds):
        x = t(seconds)
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * x)
        sig = sum(a * np.sin(2 * np.pi * freq * h * vib * x) for h, a in ((1, 1.0), (2, 0.5), (3, 0.3), (4, 0.15), (6, 0.08)))
        return sig * env(len(x), 0.02, min(0.15, seconds * 0.4))
    A, C5, D, E, F, G = 220.0, 261.63, 293.66, 329.63, 349.23, 392.0
    melody = [E * 2, D * 2, C5 * 2, A * 2, None, E * 2, F * 2, E * 2, D * 2, C5 * 2, None, None,
              D * 2, C5 * 2, A * 2, G, None, A * 2, C5 * 2, A * 2, G, E, None, None,
              E * 2, D * 2, C5 * 2, A * 2, None, E * 2, F * 2, A * 2, G * 2, F * 2, E * 2, None,
              D * 2, E * 2, C5 * 2, A * 2, None, G, A * 2, None, None, A, None, None]
    bass = [A / 2, A / 2, F / 2, F / 2, D / 2, D / 2, E / 2, E / 2, A / 2, A / 2, F / 2, F / 2, D / 2, E / 2, A / 2, A / 2]
    mel = concat(*[(organ(f, bpm_beat) if f else silence(bpm_beat)) for f in melody])
    oom = []
    for b in bass:
        oom += [organ(b, bpm_beat) * 0.9, organ(b * 3, bpm_beat) * 0.35, organ(b * 3, bpm_beat) * 0.35]
    pah = concat(*oom)
    n = min(len(mel), len(pah))
    organ_loop = mel[:n] * 0.55 + pah[:n] * 0.45
    organ_loop = lowpass(organ_loop, 2600)
    write('ambient_organ', organ_loop)

    # Crowd murmur (12 s): band-limited noise with slow, overlapping swells of "voices".
    x = t(12.0)
    murmur = lowpass(rng.normal(0, 1, len(x)), 900) - lowpass(rng.normal(0, 1, len(x)), 180) * 0.6
    swell = 0.6 + 0.25 * np.sin(2 * np.pi * x / 12.0) + 0.15 * np.sin(2 * np.pi * x * 3 / 12.0 + 1.0)
    voices = np.zeros(len(x))
    for k in range(18):
        start = rng.uniform(0, 11.0)
        dur = rng.uniform(0.25, 0.7)
        seg = t(dur)
        f0 = rng.uniform(110, 240)
        v = np.sin(2 * np.pi * (f0 + 25 * np.sin(2 * np.pi * 4 * seg)) * seg) * np.sin(np.pi * seg / dur) ** 2
        i = int(start * SR)
        voices[i:i + len(v)] += lowpass(v, 700)[:len(voices) - i] * 0.25
    fade = np.minimum(1, np.minimum(x, 12.0 - x) / 0.5)  # soften the loop seam
    write('ambient_crowd', (murmur * swell + voices) * (0.7 + 0.3 * fade))

    # Fortune chimes (12 s): sparse glassy bells over a soft pad.
    x = t(12.0)
    pad = sum(np.sin(2 * np.pi * f * x) for f in (220.0, 261.63, 329.63)) / 3 * (0.5 + 0.5 * np.sin(2 * np.pi * x / 12.0 - np.pi / 2)) * 0.3
    chimes = np.zeros(len(x))
    for start, f in ((0.4, 1318.5), (1.9, 1567.98), (3.1, 1174.66), (5.2, 1760.0), (6.0, 1318.5), (8.3, 1975.5), (9.7, 1567.98)):
        b = bell(f, 2.2, decay=2.2) * 0.35
        i = int(start * SR)
        chimes[i:i + len(b)] += b[:len(chimes) - i]
    write('ambient_chimes', pad + chimes)

    # Wind (16 s): howling filtered noise with moaning resonant gusts.
    x = t(16.0)
    base = lowpass(rng.normal(0, 1, len(x)), 500)
    gust = 0.45 + 0.35 * np.sin(2 * np.pi * x / 16.0) + 0.2 * np.sin(2 * np.pi * x * 2 / 16.0 + 0.7)
    howl = np.sin(2 * np.pi * (180 + 60 * np.sin(2 * np.pi * x / 8.0)) * x) * (0.5 + 0.5 * np.sin(2 * np.pi * x / 16.0 + 2.0)) * 0.25
    write('ambient_wind', base * gust + howl)

    # Prize counter purchase: coin clink + little bell.
    c = t(0.08)
    clink = np.sin(2 * np.pi * 3200 * c) * np.exp(-c * 60) + np.sin(2 * np.pi * 4700 * c) * np.exp(-c * 80) * 0.6
    write('shop_purchase', mix(concat(clink, silence(0.05), clink * 0.7), concat(silence(0.12), bell(1046.5, 0.9, 5) * 0.6)))


if __name__ == '__main__':
    main()

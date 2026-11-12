#!/usr/bin/env python3
"""Synthesizes the built-in soundtrack: full-length, arranged radio tracks and the
victory / defeat stings. Everything is generated from oscillators and noise in
this file and gen_audio.py; there are no samples and no third-party audio.

Usage: python3 tools/gen_music.py      (writes audio/music/*.ogg and audio/sting_*.wav)

To use recorded or licensed music instead, drop an .ogg into audio/music/ and add
an entry to scripts/core/soundtrack.gd; the radio, states and UI follow."""
import os, subprocess
import numpy as np
from scipy import signal
import gen_audio as g
from gen_audio import SR, midi, place, kick, snare, clap, hat, bass808, pad, pluck, bell, saw, lp, hp, simple_reverb, sidechain, finish

OUT = os.path.join(g.OUT, "music")
os.makedirs(OUT, exist_ok=True)
MINOR = [0, 3, 7, 10, 14, 15, 19]
SCALE = [0, 2, 3, 5, 7, 8, 10, 12, 14, 15]


def glide_lead(notes, beat, bright=2600.0):
    """Portamento sine/triangle lead (the whistling synth of West Coast hip hop).
    notes: [(start_beat, length_beats, midi_note)]"""
    end = max(s + l for s, l, _ in notes) * beat + 0.3
    n = int(end * SR)
    f = np.zeros(n)
    amp = np.zeros(n)
    last = midi(notes[0][2])
    for s, l, nt in notes:
        i0 = int(s * beat * SR)
        i1 = min(int((s + l) * beat * SR), n)
        tgt = midi(nt)
        gl = min(int(0.07 * SR), i1 - i0)
        f[i0:i0 + gl] = np.linspace(last, tgt, gl)
        f[i0 + gl:i1] = tgt
        a = np.ones(i1 - i0)
        ed = min(int(0.02 * SR), len(a) // 2)
        a[:ed] = np.linspace(0, 1, ed)
        a[-ed:] = np.linspace(1, 0, ed)
        amp[i0:i1] = a
        last = tgt
    f[f == 0] = last
    vib = 1.0 + 0.006 * np.sin(2 * np.pi * 5.5 * np.arange(n) / SR)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    x = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.12 * signal.sawtooth(ph)
    return lp(x * amp, bright) * 0.6


def synth_bass(freq, dur, fc=700.0):
    t = np.arange(int(SR * dur)) / SR
    x = signal.sawtooth(2 * np.pi * freq * t) * 0.6 + signal.square(2 * np.pi * freq * 0.5 * t) * 0.5
    env = np.minimum(t / 0.005, 1.0) * np.exp(-t / (dur * 0.7))
    cut = fc * (0.5 + 1.8 * np.exp(-t / 0.08))
    y = np.zeros_like(x)
    z = 0.0
    for i in range(len(x)):          # one-pole filter with a decaying cutoff: the "wow" of a funk bass
        a = min(cut[i] * 2 * np.pi / SR, 0.99)
        z += a * (x[i] - z)
        y[i] = z
    return y * env


def stab(freqs, dur, fc=3200.0):
    out = np.zeros(int(SR * dur))
    for f in freqs:
        out += saw(f, dur)[:len(out)]
    t = np.arange(len(out)) / SR
    return lp(out, fc) * np.exp(-t / (dur * 0.35)) * 0.35


def riser(dur):
    n = int(SR * dur)
    nz = np.random.default_rng(5).standard_normal(n)
    t = np.arange(n) / SR
    out = np.zeros(n)
    steps = 24
    for k in range(steps):           # band of noise sweeping upward
        i0, i1 = k * n // steps, (k + 1) * n // steps
        fc = 300 * (40 ** (k / (steps - 1)))
        seg = g.bp(nz[max(i0 - 2000, 0):i1], fc * 0.7, min(fc * 1.4, SR * 0.45))
        out[i0:i1] = seg[-(i1 - i0):]
    return out * (t / dur) ** 2 * 0.5


def song(name, bpm, key, prog, style, sections, seed=1):
    """sections: [(bars, "layers")], layers a string of letters:
       d drums, h hats only, b bass, p pad, l lead, s stabs/arp, r riser into the next section."""
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar = beat * 4
    bars = sum(s[0] for s in sections)
    N = int(bar * bars * SR) + int(SR * 2.0)
    drums = np.zeros((2, N))
    music = np.zeros((2, N))
    bassb = np.zeros((2, N))
    kicks = []
    b = 0
    for nbars, layers in sections:
        for k in range(nbars):
            t0 = b * bar
            root = key + prog[b % len(prog)]
            fill = (k % 4 == 3)
            last = k == nbars - 1
            chord = [midi(root + MINOR[i]) for i in range(4)]
            # ---------------- drums
            if "d" in layers:
                if style == "gfunk":
                    kp = [0, 0.75, 2, 2.5] if b % 2 == 0 else [0, 1.5, 2.75]
                    sp = [1, 3]
                elif style == "breaks":
                    kp = [0, 1.75, 2.5] if b % 2 == 0 else [0, 0.75, 2.25, 3.5]
                    sp = [1, 3] if not fill else [1, 2.75, 3]
                elif style == "boombap":
                    kp = [0, 1.5, 2.25] if b % 2 == 0 else [0, 0.75, 2.5]
                    sp = [1, 3]
                elif style == "trap":
                    kp = [0, 0.75, 2.5, 3.5] if b % 2 == 0 else [0, 1.5, 2.75]
                    sp = [2]
                else:           # four on the floor
                    kp = [0, 1, 2, 3] if not fill else [0, 1, 2, 2.5, 3.25]
                    sp = [1, 3]
                for kk in kp:
                    place(drums, kick(), t0 + kk * beat, 1.0)
                    kicks.append(t0 + kk * beat)
                for s in sp:
                    place(drums, snare(), t0 + s * beat, 0.8)
                    place(drums, clap(), t0 + s * beat, 0.55, 0.1)
                if fill and last:
                    for r in range(6):
                        place(drums, snare(0.14), t0 + (3.25 + r * 0.125) * beat, 0.3 + r * 0.09, -0.3 + r * 0.12)
            if "d" in layers or "h" in layers:
                steps = 8 if style == "trap" else 16
                sw = 0.09 if style in ("boombap", "gfunk") else 0.0
                for h in range(steps):
                    pos = h * 4.0 / steps + (sw if h % 2 else 0.0)
                    if style == "trap" and fill and h >= 6:
                        for r in range(3):
                            place(drums, hat(), t0 + (pos + r * 0.166) * beat, 0.38, 0.3)
                    else:
                        place(drums, hat(open_=(h == steps - 2 and b % 2 == 1)), t0 + pos * beat,
                              (0.5 if h % 2 == 0 else 0.3) * float(rng.uniform(0.85, 1.1)), 0.3 if h % 2 else -0.2)
            # ---------------- bass
            if "b" in layers:
                lo = root - 24 if root - 24 >= 28 else root - 12
                if style == "gfunk":
                    pat = [(0, 0.9, 0), (1.5, 0.4, 0), (2, 0.45, 7), (2.5, 0.9, 0), (3.5, 0.4, 10 if b % 2 else 12)]
                    for pos, ln, off in pat:
                        place(bassb, synth_bass(midi(lo + 12 + off) / 2, ln * beat), t0 + pos * beat, 0.9)
                elif style == "breaks":
                    for i in range(8):
                        off = [0, 0, 12, 0, 3, 0, 10, 7][i]
                        if i in (1, 5) and b % 2 == 0:
                            continue
                        place(bassb, synth_bass(midi(lo + off), beat * 0.45, 500 + 500 * (i % 3)), t0 + i * 0.5 * beat, 0.85)
                elif style == "drive":
                    for i in range(8):
                        o = 12 if i in (3, 6) else 0
                        place(bassb, bass808(midi(lo + o), beat * 0.48), t0 + i * 0.5 * beat, 0.8)
                else:
                    bf = midi(lo)
                    place(bassb, bass808(bf, beat * 1.4), t0, 0.95)
                    place(bassb, bass808(bf, beat * 0.7), t0 + (1.5 if style == "boombap" else 0.75) * beat, 0.8)
                    place(bassb, bass808(bf, beat * 1.3, slide_to=bf * 0.94 if fill else None), t0 + 2.5 * beat, 0.9)
            # ---------------- harmony
            if "p" in layers:
                place(music, pad(chord, bar * 1.02, 900 if style in ("boombap", "gfunk") else 1500), t0, 0.28, -0.15)
            if "s" in layers:
                if style == "gfunk":
                    for pos in (0.5, 1.5, 3.0):
                        place(music, stab([c * 2 for c in chord[:3]], 0.3 * beat + 0.12, 2600), t0 + pos * beat, 0.5, 0.3)
                elif style == "breaks":
                    for pos in (0, 0.75, 1.5, 2.5, 3.25):
                        place(music, stab([chord[0] * 2, chord[2] * 2, chord[3] * 2], 0.22, 4200), t0 + pos * beat, 0.55, -0.3)
                elif style == "boombap":
                    pat = [(0, 4), (0.75, 2), (1.5, 3), (2.5, 1), (3.25, 2)] if b % 2 == 0 else [(0, 3), (1, 4), (1.75, 2), (3, 0)]
                    for pos, deg in pat:
                        place(music, bell(midi(root + 12 + MINOR[deg]), 0.9), t0 + pos * beat, 0.3, 0.35)
                elif style == "trap":
                    for pos in (0, 1.5, 3):
                        for c in chord[:3]:
                            place(music, pluck(c * 2, 0.6, 4500), t0 + pos * beat, 0.2, -0.3)
                else:
                    arp = [0, 2, 1, 2, 3, 2, 1, 2, 0, 2, 1, 2, 4, 3, 2, 1]
                    for i in range(16):
                        place(music, pluck(midi(root + 12 + MINOR[arp[i]]), 0.22, 5200), t0 + i * 0.25 * beat, 0.22, 0.5 * np.sin(i))
            # ---------------- lead: a two-bar hook that answers itself
            if "l" in layers and b % 2 == 0:
                r12 = key + 12 + (12 if style in ("gfunk", "trap") else 0)
                hooks = {
                    "gfunk": [(0, 1.5, 7), (1.5, 0.5, 10), (2, 1, 12), (3, 1, 10), (4, 1.5, 7), (5.5, 0.5, 5), (6, 2, 3 if (b // 2) % 2 else 7)],
                    "breaks": [(0, 0.5, 0), (0.75, 0.5, 3), (1.5, 0.5, 7), (2.5, 1, 10), (4, 0.5, 12), (4.75, 0.5, 10), (5.5, 0.5, 7), (6.5, 1, 3)],
                    "boombap": [(0, 1, 7), (1.5, 1, 5), (3, 1, 3), (4, 2, 0), (6.5, 1, 3)],
                    "trap": [(0, 0.5, 12), (1, 0.5, 10), (2, 1, 7), (4, 0.5, 8), (5, 0.5, 7), (6, 1.5, 3)],
                    "drive": [(0, 1, 0), (1, 1, 7), (2, 0.5, 10), (2.5, 1.5, 12), (4, 1, 15), (5, 1, 12), (6, 2, 7)],
                }[style]
                notes = [(s, l, r12 + prog[b % len(prog)] + n) for s, l, n in hooks]
                place(music, glide_lead(notes, beat, 3000 if style != "boombap" else 1800), t0, 0.34, 0.2)
            if "r" in layers and last:
                place(music, riser(bar), t0, 0.5)
            b += 1
    music[0] = simple_reverb(music[0], 0.24, 1)
    music[1] = simple_reverb(music[1], 0.24, 2)
    music = sidechain(music, kicks, 0.4)
    mix = drums * 0.9 + bassb * 0.85 + music * 1.0
    out = finish(mix)
    # fade the tail so tracks can follow each other on the radio
    tail = int(SR * 1.8)
    out[-tail:] *= np.linspace(1, 0, tail)[:, None]
    path = os.path.join(OUT, name + ".wav")
    from scipy.io import wavfile
    wavfile.write(path, SR, (np.clip(out, -1, 1) * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", "4",
                    os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(path)
    print("wrote music/%s  %.0f s" % (name, len(out) / SR))


def sting(name, notes, bpm, brass=True, down=False):
    beat = 60.0 / bpm
    total = max(s + l for s, l, _ in notes) * beat + 1.6
    buf = np.zeros((2, int(total * SR)))
    for s, l, chord in notes:
        fr = [midi(n) for n in chord]
        x = np.zeros(int((l * beat + 0.5) * SR))
        for f in fr:
            x += saw(f, l * beat + 0.5, 0.008, 5)[:len(x)]
        t = np.arange(len(x)) / SR
        env = np.minimum(t / 0.02, 1.0) * np.exp(-np.maximum(t - l * beat, 0) / 0.25)
        x = lp(x * env, 3800 if brass else 1500) * 0.3
        place(buf, x, s * beat, 0.9, -0.1)
        place(buf, kick(0.5, 90, 38), s * beat, 0.7)
        if not down:
            place(buf, clap(), s * beat, 0.35, 0.2)
    buf[0] = simple_reverb(buf[0], 0.3, 1)
    buf[1] = simple_reverb(buf[1], 0.3, 2)
    g.save(name, finish(buf, 0.85, 1.2))


if __name__ == "__main__":
    A, B, C = "dbps", "dbpsl", "dbpl"
    # West Coast flavoured main theme: the hook is the whistling lead
    song("main_theme", 94, 57, [0, 0, -4, -2, 0, 0, 5, 3], "gfunk",
         [(2, "pr"), (4, "hbps"), (8, B), (4, A), (8, B), (2, "pl"), (4, B), (2, "pl")], 1)
    song("night_shift", 90, 55, [0, 0, -4, -2, 0, 0, -4, -5], "boombap",
         [(2, "hp"), (8, A), (8, B), (4, "hbp"), (8, B), (4, A), (2, "ps")], 2)
    song("redline", 128, 52, [0, 0, 3, -2, 0, 0, -4, -5], "drive",
         [(4, "hpr"), (8, "dbs"), (8, B), (4, "psr"), (16, B), (8, "dbs"), (4, "ps")], 3)
    song("halcyon", 140, 54, [0, 0, 3, -2, 0, 0, -4, -2], "trap",
         [(4, "ps"), (8, "dbps"), (8, B), (4, "hpsr"), (16, B), (4, "ps")], 4)
    song("overpass", 132, 50, [0, 0, -2, -2, 3, 3, -4, -5], "breaks",
         [(4, "hpr"), (8, "dbs"), (8, B), (4, "hblr"), (16, B), (8, "dbs"), (2, "p")], 5)
    song("chrome_heart", 98, 53, [0, 0, 3, 3, -2, -2, -4, -5], "gfunk",
         [(2, "p"), (8, "dbps"), (8, B), (4, "hbl"), (8, B), (4, A), (2, "pl")], 6)
    sting("sting_win", [(0, 0.75, [57, 60, 64]), (0.75, 0.75, [59, 62, 67]), (1.5, 0.5, [60, 64, 69]), (2.0, 2.5, [62, 66, 69, 74])], 110)
    sting("sting_lose", [(0, 1.0, [57, 60, 64]), (1.0, 1.0, [55, 58, 62]), (2.0, 2.5, [50, 53, 57])], 84, brass=False, down=True)

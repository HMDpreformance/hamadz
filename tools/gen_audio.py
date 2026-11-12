#!/usr/bin/env python3
"""Synthesizes every sound in the game from scratch (no samples, no third-party audio).
Usage: python3 tools/gen_audio.py   (writes into audio/, needs numpy + scipy + ffmpeg)"""
import os, subprocess, sys
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def t_(dur):
    return np.arange(int(SR * dur)) / SR


def env_exp(dur, tau):
    return np.exp(-t_(dur) / tau)


def lp(x, fc, order=2):
    b, a = signal.butter(order, min(fc, SR * 0.45) / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bp(x, f1, f2, order=2):
    b, a = signal.butter(order, [f1 / (SR / 2), f2 / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x if m < 1e-9 else x * (peak / m)


def sat(x, drive=1.0):
    return np.tanh(x * drive)


def save(name, x, sr=SR, ogg=False, q=4):
    x = np.clip(x, -1, 1)
    path = os.path.join(OUT, name + ".wav")
    wavfile.write(path, sr, (x * 32767).astype(np.int16))
    if ogg:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis",
                        "-q:a", str(q), os.path.join(OUT, name + ".ogg")], check=True)
        os.remove(path)
    print("wrote", name)


# ---------------------------------------------------------------- drums / instruments
def kick(dur=0.45, f0=120, f1=42, punch=1.0):
    t = t_(dur)
    f = f1 + (f0 - f1) * np.exp(-t / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) * np.exp(-t / 0.16)
    click = hp(rng.standard_normal(len(t)), 2000) * np.exp(-t / 0.004) * 0.35 * punch
    return sat(x * 1.6 + click, 1.2)


def bass808(freq, dur, slide_to=None):
    t = t_(dur)
    f = np.full(len(t), freq, dtype=float)
    if slide_to:
        f = freq + (slide_to - freq) * np.clip((t - dur * 0.5) / (dur * 0.4), 0, 1)
    f = f * (1 + 1.5 * np.exp(-t / 0.02))
    ph = 2 * np.pi * np.cumsum(f) / SR
    e = np.minimum(1, t / 0.004) * np.exp(-t / (dur * 0.9)) * np.clip((dur - t) / 0.02, 0, 1)
    return sat(np.sin(ph) * e * 1.8, 1.4)


def snare(dur=0.3):
    t = t_(dur)
    n = bp(rng.standard_normal(len(t)), 900, 7500) * np.exp(-t / 0.085)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05) * 0.6
    return sat((n * 0.9 + tone) * 1.4)


def clap(dur=0.3):
    t = t_(dur)
    n = bp(rng.standard_normal(len(t)), 1000, 5000)
    e = np.zeros(len(t))
    for d in (0.0, 0.011, 0.023):
        tt = np.clip(t - d, 0, None)
        e += (t >= d) * np.exp(-tt / 0.012)
    e += (t >= 0.03) * np.exp(-np.clip(t - 0.03, 0, None) / 0.09)
    return n * e * 0.6


def hat(dur=0.07, open_=False):
    d = 0.3 if open_ else dur
    t = t_(d)
    n = hp(rng.standard_normal(len(t)), 7000, 3)
    return n * np.exp(-t / (0.09 if open_ else 0.018)) * 0.35


def saw(freq, dur, detune=0.006, voices=3):
    t = t_(dur)
    x = np.zeros(len(t))
    for v in range(voices):
        f = freq * (1 + detune * (v - (voices - 1) / 2))
        x += signal.sawtooth(2 * np.pi * f * t + rng.uniform(0, 6.28))
    return x / voices


def pluck(freq, dur, bright=3000):
    t = t_(dur)
    x = saw(freq, dur) + 0.5 * signal.square(2 * np.pi * freq * 0.5 * t)
    # falling filter imitation: blend of bright and dull versions
    e = np.exp(-t / 0.12)
    y = lp(x, bright) * e + lp(x, 500) * (1 - e)
    return y * np.minimum(1, t / 0.003) * np.exp(-t / (dur * 0.45))


def pad(freqs, dur, fc=1400):
    t = t_(dur)
    x = np.zeros(len(t))
    for f in freqs:
        x += saw(f, dur, 0.009, 5)
    x = lp(x / len(freqs), fc, 3)
    e = np.minimum(1, t / 0.4) * np.clip((dur - t) / 0.5, 0, 1)
    return x * e


def bell(freq, dur):
    t = t_(dur)
    mod = np.sin(2 * np.pi * freq * 3.01 * t) * np.exp(-t / 0.3) * 2.2
    return np.sin(2 * np.pi * freq * t + mod) * np.exp(-t / (dur * 0.35))


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def place(buf, x, at, gain=1.0, pan=0.0):
    i = int(at * SR)
    if i >= buf.shape[1]:
        return
    n = min(len(x), buf.shape[1] - i)
    l = gain * np.sqrt(0.5 * (1 - pan))
    r = gain * np.sqrt(0.5 * (1 + pan))
    buf[0, i:i + n] += x[:n] * l * 1.414
    buf[1, i:i + n] += x[:n] * r * 1.414
    # wrap the tail around so loops are seamless
    if n < len(x):
        rest = x[n:]
        m = min(len(rest), buf.shape[1])
        buf[0, :m] += rest[:m] * l * 1.414
        buf[1, :m] += rest[:m] * r * 1.414


def sidechain(buf, kick_times, depth=0.45, rel=0.18):
    g = np.ones(buf.shape[1])
    for kt in kick_times:
        i = int(kt * SR)
        n = min(int(rel * 3 * SR), buf.shape[1] - i)
        if n > 0:
            g[i:i + n] = np.minimum(g[i:i + n], 1 - depth * np.exp(-np.arange(n) / (rel * SR)))
    return buf * g


def simple_reverb(x, mix=0.2, seed=3):
    r = np.random.default_rng(seed)
    n = int(SR * 1.3)
    ir = r.standard_normal(n) * np.exp(-np.arange(n) / (SR * 0.35))
    ir = lp(ir, 5000)
    ir /= np.sqrt(np.sum(ir ** 2))
    wet = signal.fftconvolve(x, ir)[:len(x)]
    # fold the reverb tail back to the start for looping material
    return x * (1 - mix) + wet * mix


def finish(buf, peak=0.92, drive=1.3):
    buf = buf / (np.max(np.abs(buf)) + 1e-9)
    buf = np.tanh(buf * drive) / np.tanh(drive)
    return (buf * peak).T


def beat_track(name, bpm, bars, key, prog, style):
    """prog: list (len=bars) of chord root offsets (semitones from key, minor)."""
    beat = 60.0 / bpm
    bar = beat * 4
    total = bar * bars
    N = int(total * SR)
    drums = np.zeros((2, N))
    music = np.zeros((2, N))
    bassb = np.zeros((2, N))
    kicks = []
    minor = [0, 3, 7, 10, 14]
    for b in range(bars):
        t0 = b * bar
        root = key + prog[b % len(prog)]
        fill = (b % 4 == 3)
        # --- drums
        if style == "menu":   # laid-back boom bap, swung hats
            kp = [0, 1.5, 2.25] if b % 2 == 0 else [0, 0.75, 2.5]
            sp = [1, 3]
            sw = 0.09
        elif style == "intro":  # half-time, heavy
            kp = [0, 0.75, 2.5, 3.5] if b % 2 == 0 else [0, 1.5, 2.75]
            sp = [2]
            sw = 0.0
        else:  # drive: uptempo four-ish with breaks
            kp = [0, 1, 2, 3] if not fill else [0, 1, 2, 2.5, 3.25]
            sp = [1, 3]
            sw = 0.0
        for k in kp:
            place(drums, kick(), t0 + k * beat, 1.0)
            kicks.append(t0 + k * beat)
        for s in sp:
            place(drums, snare(), t0 + s * beat, 0.8)
            place(drums, clap(), t0 + s * beat, 0.6, 0.1)
        steps = 16 if style != "intro" else 8
        for h in range(steps):
            pos = h * 4.0 / steps
            if h % 2 == 1:
                pos += sw
            vel = 0.55 if h % 2 == 0 else 0.32
            if style == "intro" and fill and h >= 6:
                for r in range(3):
                    place(drums, hat(), t0 + (pos + r * 0.166) * beat, 0.4, 0.3)
            else:
                place(drums, hat(open_=(h == steps - 2 and b % 2 == 1)), t0 + pos * beat, vel, 0.3 if h % 2 else -0.2)
        if fill and style != "intro":
            for r in range(4):
                place(drums, snare(0.15), t0 + (3.5 + r * 0.125) * beat, 0.35 + r * 0.1)
        # --- bass
        bf = midi(root - 24 if root - 24 >= 26 else root - 12)
        if style == "drive":
            for i in range(8):
                o = 12 if i in (3, 6) else 0
                place(bassb, bass808(midi(root - 24 + o) if root - 24 >= 26 else midi(root - 12 + o), beat * 0.48), t0 + i * 0.5 * beat, 0.8)
        else:
            place(bassb, bass808(bf, beat * 1.4), t0, 0.95)
            place(bassb, bass808(bf, beat * 0.7), t0 + (1.5 if style == "menu" else 0.75) * beat, 0.8)
            place(bassb, bass808(bf * 2 ** (minor[2] / 12) / 2 if b % 2 else bf, beat * 1.3, slide_to=bf * 0.94 if fill else None), t0 + 2.5 * beat, 0.9)
        # --- harmony
        chord = [midi(root + minor[0]), midi(root + minor[1]), midi(root + minor[2]), midi(root + minor[3])]
        place(music, pad(chord, bar * 1.02, 900 if style == "menu" else 1500), t0, 0.28, -0.15)
        # --- lead / stabs
        if style == "menu":
            pat = [(0, 4), (0.75, 2), (1.5, 3), (2.5, 1), (3.25, 2)] if b % 2 == 0 else [(0, 3), (1, 4), (1.75, 2), (3, 0)]
            for pos, deg in pat:
                place(music, bell(midi(root + 12 + minor[deg]), 0.9), t0 + pos * beat, 0.3, 0.35)
            if b % 2 == 1:
                place(music, pluck(midi(root + minor[2]), 0.5, 2000), t0 + 3.5 * beat, 0.3, -0.4)
        elif style == "intro":
            for pos in (0, 1.5, 3):
                for c in chord[:3]:
                    place(music, pluck(c * 2, 0.6, 4500), t0 + pos * beat, 0.2, -0.3)
            mel = [4, 3, 2, 3, 4, 2, 1, 0]
            for i in range(8):
                if (b % 4 >= 2) or i % 2 == 0:
                    place(music, bell(midi(root + 24 + minor[mel[(i + b) % 8] % 5]), 0.5), t0 + i * 0.5 * beat, 0.16, 0.4)
        else:
            arp = [0, 2, 1, 2, 3, 2, 1, 2, 0, 2, 1, 2, 4, 3, 2, 1]
            for i in range(16):
                place(music, pluck(midi(root + 12 + minor[arp[i]]), 0.22, 5200), t0 + i * 0.25 * beat, 0.22, 0.5 * np.sin(i))
            for pos in (0, 2.5):
                for c in chord[:3]:
                    place(music, pluck(c, 0.8, 2600), t0 + pos * beat, 0.24, -0.35)
    # vinyl crackle / air
    if style == "menu":
        cr = (rng.random(N) > 0.9993) * rng.uniform(0.2, 1, N)
        cr = hp(signal.lfilter([1], [1, -0.6], cr), 1500) * 0.5
        music += np.vstack([cr, np.roll(cr, 300)]) * 0.5
    music[0] = simple_reverb(music[0], 0.25, 1)
    music[1] = simple_reverb(music[1], 0.25, 2)
    music = sidechain(music, kicks, 0.4)
    mix = drums * 0.9 + bassb * 0.85 + music * 1.0
    save(name, finish(mix), ogg=True, q=5)


# ---------------------------------------------------------------- engines
def engine_loop(name, cyl, base_rpm, character, bright):
    """Loopable engine tone at base_rpm. Pitch-shifted in game."""
    rev = base_rpm / 60.0
    fire = rev * cyl / 2.0
    cycles = 24  # crank cycles (2 revs each) so the loop is exactly periodic
    dur = cycles * 2 / rev
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    x = np.zeros(n)
    r = np.random.default_rng(cyl * 100 + int(bright * 10))
    cyc_f = rev / 2.0  # one 4-stroke cycle
    if character == "v8":
        # cross-plane burble: strong half-order content
        orders = [(1, 0.5), (2, 0.8), (3, 0.45), (4, 1.0), (5, 0.3), (6, 0.5), (8, 0.7), (12, 0.35), (16, 0.25), (24, 0.12)]
    elif character == "i4":
        orders = [(4, 1.0), (8, 0.75), (12, 0.5), (16, 0.4), (20, 0.25), (24, 0.2), (2, 0.25), (6, 0.2), (32, 0.12)]
    else:  # six: smooth howl
        orders = [(6, 1.0), (12, 0.8), (18, 0.55), (24, 0.3), (3, 0.3), (9, 0.3), (30, 0.2), (36, 0.12)]
    for o, a in orders:
        f = cyc_f * o
        k = max(1, round(f * dur))  # integer periods in the loop
        hi = 1.0 if f < 400 else bright
        x += a * hi * np.sin(2 * np.pi * k * t / dur + r.uniform(0, 6.28))
    # pulse train for exhaust crackle, exactly periodic
    pulses = np.zeros(n)
    per = n / (cycles * cyl)
    for i in range(cycles * cyl):
        amp = 1.0 + (0.35 * ((i % cyl) in (0, 3)) if character == "v8" else 0.08 * r.standard_normal())
        idx = int(i * per)
        pulses[idx % n] += amp
    pul = signal.lfilter([1], [1, -0.985], pulses)
    pul = bp(np.tile(pul, 3), 60, 900 + 2500 * bright)[n:2 * n]
    x = x / np.max(np.abs(x)) + 0.9 * pul / np.max(np.abs(pul))
    # mechanical noise (periodic by tiling a filtered noise buffer w/ crossfade)
    nz = bp(r.standard_normal(n * 2), 1500, 6000)
    w = np.linspace(0, 1, n)
    nz = nz[:n] * w + nz[n:] * (1 - w)
    x += nz * 0.06 * bright
    x = sat(x * (1.2 + bright), 1.0)
    save(name, norm(x, 0.8))


def turbo_whine():
    dur = 2.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f, a in ((3000, 1.0), (6000, 0.4), (4500, 0.25)):
        k = round(f * dur)
        x += a * np.sin(2 * np.pi * k * t / dur + 0.3 * np.sin(2 * np.pi * 6 * t))
    nz = bp(rng.standard_normal(2 * n), 2500, 9000)
    w = np.linspace(0, 1, n)
    x = x * 0.5 + (nz[:n] * w + nz[n:] * (1 - w)) * 0.5
    save("turbo_whine", norm(x, 0.5))


def blowoff():
    t = t_(0.7)
    nz = rng.standard_normal(len(t))
    f = 5000 * np.exp(-t / 0.25) + 900
    # time-varying band via two filtered mixes
    a = bp(nz, 2500, 9000) * np.exp(-t / 0.1)
    b = bp(nz, 700, 2800) * np.exp(-t / 0.28) * np.minimum(1, t / 0.03)
    flutter = 1 + 0.5 * signal.square(2 * np.pi * 26 * t) * (t > 0.15) * np.exp(-(t - 0.15) / 0.2)
    save("blowoff", norm((a + b * flutter) * np.minimum(1, t / 0.004), 0.8))


def tire_loop():
    dur = 1.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f, a in ((880, 1), (1010, 0.8), (1320, 0.6), (1850, 0.4), (2400, 0.3)):
        k = round(f * dur)
        vib = 0.6 * np.sin(2 * np.pi * round(7 * dur) * t / dur + f)
        x += a * np.sin(2 * np.pi * k * t / dur + vib)
    nz = bp(rng.standard_normal(2 * n), 600, 4000)
    w = np.linspace(0, 1, n)
    x = sat(x * 0.5, 1.5) * 0.6 + (nz[:n] * w + nz[n:] * (1 - w)) * 0.7
    save("tire_screech", norm(x, 0.7))


def nitro():
    t = t_(1.2)
    nz = rng.standard_normal(len(t))
    whoosh = bp(nz, 300, 3000) * np.minimum(1, t / 0.02) * np.exp(-t / 0.5)
    hiss = hp(nz, 4000) * np.exp(-t / 0.7) * 0.6
    f = 80 + 300 * np.minimum(1, t / 0.4)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.4) * 0.5
    save("nitro_start", norm(whoosh + hiss + tone, 0.85))
    dur = 1.0
    n = int(dur * SR)
    nz = rng.standard_normal(2 * n)
    y = bp(nz, 500, 5000) + hp(nz, 5000) * 0.6
    w = np.linspace(0, 1, n)
    save("nitro_loop", norm(y[:n] * w + y[n:] * (1 - w), 0.6))


def road_loop():
    dur = 2.0
    n = int(dur * SR)
    nz = rng.standard_normal(2 * n)
    y = lp(nz, 420, 3) * 2 + bp(nz, 800, 2500) * 0.25
    w = np.linspace(0, 1, n)
    save("road_wind", norm(y[:n] * w + y[n:] * (1 - w), 0.6))


# ---------------------------------------------------------------- UI / misc sfx
def ui_sounds():
    t = t_(0.07)
    x = np.sin(2 * np.pi * 1400 * t) * np.exp(-t / 0.012) + 0.4 * hp(rng.standard_normal(len(t)), 5000) * np.exp(-t / 0.004)
    save("ui_move", norm(x, 0.5))

    t = t_(0.28)
    x = (np.sin(2 * np.pi * 660 * t) * np.exp(-t / 0.04)
         + (t > 0.06) * np.sin(2 * np.pi * 990 * t) * np.exp(-np.clip(t - 0.06, 0, None) / 0.07))
    x += 0.5 * kick(0.28, 200, 60)
    save("ui_select", norm(x, 0.7))

    t = t_(0.22)
    f = 700 * np.exp(-t / 0.12) + 200
    save("ui_back", norm(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.07), 0.55))

    t = t_(0.3)
    x = signal.square(2 * np.pi * 140 * t) * ((t < 0.1) | ((t > 0.15) & (t < 0.27)))
    save("ui_deny", norm(lp(x, 1200), 0.45))

    # purchase: coin shimmer + register bell
    t = t_(0.9)
    x = np.zeros(len(t))
    for i, f in enumerate((1568, 2093, 2637, 3136)):
        d = i * 0.05
        tt = np.clip(t - d, 0, None)
        x += (t >= d) * np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.22)
    x += 0.4 * hp(rng.standard_normal(len(t)), 6000) * np.exp(-t / 0.05)
    save("purchase", norm(x, 0.7))

    # install: impact wrench burst
    t = t_(0.75)
    rate = 34
    gate = (signal.square(2 * np.pi * rate * t, 0.35) > 0) * 1.0
    body = bp(rng.standard_normal(len(t)), 500, 5000) * gate
    whir = signal.sawtooth(2 * np.pi * (300 + 500 * np.minimum(1, t / 0.2)) * t) * 0.25
    e = np.minimum(1, t / 0.02) * np.clip((0.75 - t) / 0.1, 0, 1)
    save("install", norm((body + whir) * e, 0.7))

    # whoosh for transitions
    t = t_(0.6)
    nz = rng.standard_normal(len(t))
    e = np.sin(np.pi * t / 0.6) ** 2
    x = bp(nz, 300, 1800) * e * (0.5 + 0.5 * t / 0.6) + bp(nz, 1800, 7000) * e ** 3 * 0.6
    save("whoosh", norm(x, 0.6))

    # checkpoint
    t = t_(0.5)
    x = np.sin(2 * np.pi * 1175 * t) * np.exp(-t / 0.08) + (t > 0.09) * np.sin(2 * np.pi * 1760 * t) * np.exp(-np.clip(t - 0.09, 0, None) / 0.16)
    save("checkpoint", norm(x, 0.7))

    for nm, f, d in (("beep_lo", 660, 0.18), ("beep_hi", 1320, 0.5)):
        t = t_(d)
        x = signal.square(2 * np.pi * f * t) * np.minimum(1, t / 0.003) * np.clip((d - t) / 0.03, 0, 1)
        save(nm, norm(lp(x, 4000), 0.45))

    # crash
    t = t_(0.5)
    x = kick(0.5, 180, 40) + bp(rng.standard_normal(len(t)), 300, 4000) * np.exp(-t / 0.06) * 0.9
    save("crash", norm(sat(x, 2), 0.85))

    # finish fanfare
    t = t_(1.6)
    x = np.zeros(len(t))
    for i, nn in enumerate((60, 64, 67, 72, 76)):
        d = i * 0.09
        tt = np.clip(t - d, 0, None)
        x += (t >= d) * (bell(midi(nn + 12), 1.6)[:len(t)] * 0 + np.sin(2 * np.pi * midi(nn + 12) * tt) * np.exp(-tt / 0.5))
    save("finish", norm(x, 0.7))

    # logo sting: reverse swell + impact + shimmer
    t = t_(3.2)
    swell = bp(rng.standard_normal(len(t)), 200, 3000) * np.clip(t / 1.4, 0, 1) ** 3 * (t < 1.4)
    hit_t = np.clip(t - 1.4, 0, None)
    f = 38 + 90 * np.exp(-hit_t / 0.05)
    hit = (t >= 1.4) * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-hit_t / 0.6)
    shim = np.zeros(len(t))
    for fr in (523, 784, 1046, 1568):
        shim += (t >= 1.4) * np.sin(2 * np.pi * fr * hit_t + 2 * np.sin(2 * np.pi * 5 * hit_t)) * np.exp(-hit_t / 0.9)
    crashn = (t >= 1.4) * hp(rng.standard_normal(len(t)), 3000) * np.exp(-hit_t / 0.5) * 0.4
    x = swell * 0.5 + sat(hit * 2) + shim * 0.12 + crashn
    save("logo_sting", norm(simple_reverb(x, 0.25), 0.9))

    # title slam
    t = t_(2.0)
    f = 34 + 120 * np.exp(-t / 0.04)
    x = sat(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.7) * 2.5)
    x += bp(rng.standard_normal(len(t)), 400, 6000) * np.exp(-t / 0.12) * 0.7
    x += 0.2 * signal.sawtooth(2 * np.pi * 55 * t) * np.exp(-t / 0.5)
    save("title_slam", norm(simple_reverb(x, 0.2), 0.9))

    # engine start crank
    t = t_(1.1)
    crank = signal.square(2 * np.pi * 11 * t, 0.3) * bp(rng.standard_normal(len(t)), 200, 1500) * (t < 0.6)
    f = 40 + 90 * np.clip((t - 0.55) / 0.25, 0, 1) - 30 * np.clip((t - 0.8) / 0.3, 0, 1)
    roar = (t > 0.55) * sat(signal.sawtooth(2 * np.pi * np.cumsum(f) / SR) * 1.5) * np.clip((1.1 - t) / 0.2, 0, 1)
    save("engine_start", norm(crank * 0.7 + lp(roar, 1800), 0.75))


def garage_amb():
    dur = 16.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    L = np.zeros(n)
    R = np.zeros(n)
    hum = 0.25 * np.sin(2 * np.pi * 60 * t) + 0.12 * np.sin(2 * np.pi * 120 * t) + 0.05 * np.sin(2 * np.pi * 180 * t)
    nz = rng.standard_normal(2 * n)
    w = np.linspace(0, 1, n)
    air = lp(nz, 600, 2)
    air = (air[:n] * w + air[n:] * (1 - w)) * 0.5
    buzz = 0.03 * signal.sawtooth(2 * np.pi * 100 * t) * (1 + 0.3 * np.sin(2 * np.pi * 0.25 * t))  # neon tube
    L += hum + air + buzz
    R += hum * 0.9 + np.roll(air, 5000) + buzz * 0.5
    # distant metallic clinks and a ratchet
    for at, f, pan in ((2.3, 2300, -0.6), (6.8, 3100, 0.5), (11.2, 1800, 0.2), (13.9, 2700, -0.3)):
        tt = t_(0.8)
        c = (np.sin(2 * np.pi * f * tt) + 0.6 * np.sin(2 * np.pi * f * 1.52 * tt)) * np.exp(-tt / 0.12) * 0.12
        c = simple_reverb(c, 0.5, int(f))
        i = int(at * SR)
        L[i:i + len(c)] += c * (1 - pan) / 2
        R[i:i + len(c)] += c * (1 + pan) / 2
    tt = t_(0.9)
    rat = bp(rng.standard_normal(len(tt)), 2000, 6000) * (signal.square(2 * np.pi * 18 * tt, 0.2) > 0) * 0.08
    rat = simple_reverb(rat, 0.4, 9)
    i = int(9.0 * SR)
    L[i:i + len(rat)] += rat * 0.3
    R[i:i + len(rat)] += rat
    x = np.vstack([L, R])
    x = x / np.max(np.abs(x)) * 0.6
    save("amb_garage", x.T, ogg=True, q=4)


def city_amb():
    dur = 12.0
    n = int(dur * SR)
    nz = rng.standard_normal((2, 2 * n))
    w = np.linspace(0, 1, n)
    out = []
    for c in range(2):
        a = lp(nz[c], 300, 2) * 1.5 + bp(nz[c], 500, 1500) * 0.15
        out.append(a[:n] * w + a[n:] * (1 - w))
    x = np.vstack(out)
    save("amb_city", (x / np.max(np.abs(x)) * 0.5).T, ogg=True, q=3)


if __name__ == "__main__":
    A = -3  # semitone offset helpers: key roots as midi
    engine_loop("eng_tuner_on", 4, 4200, "i4", 1.0)
    engine_loop("eng_tuner_off", 4, 4200, "i4", 0.35)
    engine_loop("eng_muscle_on", 8, 3000, "v8", 0.9)
    engine_loop("eng_muscle_off", 8, 3000, "v8", 0.3)
    engine_loop("eng_euro_on", 6, 4000, "six", 1.0)
    engine_loop("eng_euro_off", 6, 4000, "six", 0.35)
    turbo_whine(); blowoff(); tire_loop(); nitro(); road_loop()
    ui_sounds(); garage_amb(); city_amb()

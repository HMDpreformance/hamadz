#!/usr/bin/env python3
"""Synthesizes the vehicle audio sample sets (original, no recordings).

Every engine profile gets a set of seamless loops at several RPM points, each
in an on-load and an off-load (overrun) version, plus an intake loop.  The game
crossfades between neighbouring RPM layers and between load states, so no single
sample is ever pitched far from where it was made.

The model is a physical-ish source/filter: each cylinder firing is an impulse,
grouped per exhaust bank in the engine's real firing order, shaped by a pulse
spectrum and sent through a pipe resonator (comb), body formants and saturation.
All filtering is done circularly in the frequency domain, so loops are exact.

Replacing these with real recordings: drop WAV loops in audio/engines/ with the
same names (<profile>_<rpm>_on.wav / _off.wav) and edit the rpm list for that
profile in scripts/audio/engine_profiles.gd.  Nothing else changes.

Usage: python3 tools/gen_engines.py   (needs numpy, scipy)
"""
import os
import zlib
import numpy as np
from scipy.io import wavfile

SR = 32000
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
ENG = os.path.join(ROOT, "engines")
CAR = os.path.join(ROOT, "car")
os.makedirs(ENG, exist_ok=True)
os.makedirs(CAR, exist_ok=True)


def write(path, x, peak=None):
    if peak is not None:
        m = np.max(np.abs(x))
        if m > 1e-9:
            x = x * (peak / m)
    x = np.clip(x, -1, 1)
    wavfile.write(path, SR, (x * 32767).astype(np.int16))


# ------------------------------------------------------------------ engine model
# fire: crank angles (deg, 0..720) of each firing; bank: exhaust bank index per firing
PROFILES = {
    # even-firing four: hard second-order bark, raspy top end
    "i4": dict(fire=[0, 180, 360, 540], bank=[0, 0, 0, 0], rpms=[900, 2000, 3400, 5000, 7000],
               pipe=[0.0105], comb=0.42, formants=[(260, 2.0, 5), (720, 1.6, 4), (1650, 1.3, 3), (3100, 0.8, 3)],
               bright=1.0, cyl_var=0.10, lope=0.05, rasp=0.55, sub=0.25, width=0.9),
    # straight six: smooth, harmonic, turbine-like howl
    "i6": dict(fire=[0, 120, 240, 360, 480, 600], bank=[0, 0, 0, 0, 0, 0], rpms=[800, 1900, 3300, 5000, 7000],
               pipe=[0.0135], comb=0.5, formants=[(210, 1.8, 4), (560, 2.2, 5), (1250, 1.5, 4), (2500, 0.7, 3)],
               bright=0.8, cyl_var=0.05, lope=0.03, rasp=0.3, sub=0.2, width=1.25),
    # V6: two banks of three, throaty mid-range trumpet
    "v6": dict(fire=[0, 120, 240, 360, 480, 600], bank=[0, 1, 0, 1, 0, 1], rpms=[800, 1900, 3300, 4900, 6800],
               pipe=[0.0125, 0.0147], comb=0.5, formants=[(300, 1.6, 4), (840, 2.6, 6), (1500, 1.2, 4), (2800, 0.6, 3)],
               bright=0.85, cyl_var=0.16, lope=0.06, rasp=0.4, sub=0.3, width=1.1),
    # cross-plane V8: uneven pulses per bank give the burble; lumpy cam at idle
    "v8": dict(fire=[0, 90, 180, 270, 360, 450, 540, 630], bank=[0, 1, 1, 0, 1, 0, 0, 1], rpms=[750, 1700, 2900, 4400, 6200],
               pipe=[0.0188, 0.0216], comb=0.6, formants=[(140, 2.6, 4), (370, 2.0, 4), (900, 1.3, 3), (2100, 0.7, 3)],
               bright=0.7, cyl_var=0.22, lope=0.42, rasp=0.5, sub=0.75, width=1.5),
    # supercharged V8: same bottom end, harder and brighter under the blower
    "v8sc": dict(fire=[0, 90, 180, 270, 360, 450, 540, 630], bank=[0, 1, 1, 0, 1, 0, 0, 1], rpms=[800, 1800, 3000, 4600, 6500],
                 pipe=[0.0172, 0.0196], comb=0.55, formants=[(160, 2.4, 4), (440, 2.2, 4), (1150, 1.7, 4), (2600, 1.0, 3)],
                 bright=0.95, cyl_var=0.18, lope=0.3, rasp=0.7, sub=0.7, width=1.3),
    # twin-turbo V8: turbines smooth and muffle the pulses into a deep hum
    "v8tt": dict(fire=[0, 90, 180, 270, 360, 450, 540, 630], bank=[0, 1, 1, 0, 1, 0, 0, 1], rpms=[750, 1800, 3100, 4800, 6800],
                 pipe=[0.0150, 0.0156], comb=0.4, formants=[(150, 2.2, 3), (400, 1.6, 3), (800, 1.0, 3)],
                 bright=0.45, cyl_var=0.08, lope=0.1, rasp=0.25, sub=0.6, width=2.0),
    # twin-rotor: two fat pulses per shaft turn, buzzing and choppy at idle
    "rotary": dict(fire=[0, 180, 360, 540], bank=[0, 0, 0, 0], rpms=[1000, 2400, 4200, 6400, 8600],
                   pipe=[0.0085], comb=0.62, formants=[(330, 1.5, 3), (1100, 2.4, 5), (2300, 2.0, 4), (4200, 1.0, 3)],
                   bright=1.35, cyl_var=0.06, lope=0.5, rasp=0.85, sub=0.15, width=0.55),
    # flat-plane V12-style exotic: very high firing frequency, clean scream
    "exotic": dict(fire=[i * 60 for i in range(12)], bank=[i % 2 for i in range(12)], rpms=[1000, 2500, 4300, 6300, 8400],
                   pipe=[0.0098, 0.0104], comb=0.38, formants=[(420, 1.4, 3), (1150, 2.2, 5), (2500, 2.0, 5), (4300, 1.0, 3)],
                   bright=1.2, cyl_var=0.07, lope=0.04, rasp=0.35, sub=0.12, width=0.8),
}


def circ_filter(x, H):
    return np.fft.irfft(np.fft.rfft(x) * H, len(x))


def render(p, rpm, load, seed):
    """One seamless loop for profile p at rpm; load 1 = full throttle, 0 = overrun."""
    r = np.random.default_rng(seed)
    rev_s = rpm / 60.0
    cyc_t = 2.0 / rev_s      # one 720 degree cycle
    cycles = max(6, int(round(1.15 / cyc_t)))
    n = int(round(cycles * cyc_t * SR))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    nb = len(p["pipe"])
    trains = [np.zeros(n) for _ in range(nb)]
    intake = np.zeros(n)
    burst = np.zeros(n)
    idle_k = np.clip((1600 - rpm) / 900.0, 0.0, 1.0)          # 1 at idle, 0 above ~1600 rpm
    # slow lope: a lumpy cam misfires weakly at idle (one strong, one soft cycle pattern)
    lope_pat = 1.0 + p["lope"] * idle_k * r.uniform(-1, 1, cycles)
    cyl_gain = 1.0 + p["cyl_var"] * r.uniform(-1, 1, len(p["fire"]))
    for c in range(cycles):
        for k, ang in enumerate(p["fire"]):
            jit = r.normal(0, 0.004 + 0.012 * idle_k * p["lope"])
            t = (c + ang / 720.0 + jit) * cyc_t
            a = cyl_gain[k] * lope_pat[c] * (1.0 + 0.06 * r.normal())
            if load < 0.5:
                # overrun: uneven burn, some cycles barely fire
                a *= r.choice([1.0, 0.75, 0.45], p=[0.55, 0.3, 0.15])
            pos = (t * SR) % n
            i0 = int(pos)
            fr = pos - i0
            b = p["bank"][k]
            trains[b][i0 % n] += a * (1 - fr)
            trains[b][(i0 + 1) % n] += a * fr
            ip = (pos + 0.35 * cyc_t / len(p["fire"]) * SR) % n
            intake[int(ip) % n] += a
            burst[i0 % n] += a
    # pulse spectrum: wide soft pulse at low load, sharp at high load / high rpm
    rp = np.clip(rpm / p["rpms"][-1], 0, 1)
    fc = (180 + 900 * rp) * (0.55 + 0.9 * load) * p["bright"] / p["width"]
    pulse = 1.0 / (1.0 + (f / fc) ** 2) ** (0.9 if load > 0.5 else 1.25)
    pulse = pulse * (f / (f + 18.0))                     # no DC
    out = np.zeros(n)
    for b in range(nb):
        tau = p["pipe"][b]
        g = p["comb"] * (1.0 if load > 0.5 else 1.12)
        g = min(g, 0.8)
        comb = 1.0 / (1.0 - g * np.exp(-2j * np.pi * f * tau) * np.exp(-f / 5200.0))
        out += circ_filter(trains[b], pulse * comb)
    # body / tailpipe formants
    H = np.ones(len(f), dtype=complex) * 0.55
    for fc_f, gain, q in p["formants"]:
        H += gain * (1.0 / (1.0 + 1j * q * (f / fc_f - fc_f / np.maximum(f, 1e-3)))) * (0.6 + 0.4 * load if fc_f > 800 else 1.0)
    out = circ_filter(out, H)
    out /= np.max(np.abs(out)) + 1e-9
    # sub-harmonic thump (felt more than heard), follows the firing rhythm
    sub = circ_filter(sum(trains), 1.0 / (1.0 + (f / 85.0) ** 4) * (f ** 2 / (f ** 2 + 45.0 ** 2)))
    sub /= np.max(np.abs(sub)) + 1e-9
    out += p["sub"] * sub * (0.6 + 0.4 * load)
    # combustion rasp: noise gated by each firing
    nz = r.standard_normal(n)
    gate = circ_filter(burst, 1.0 / (1.0 + (f / (40.0 + 60.0 * rev_s / 20.0)) ** 2))
    gate = np.maximum(gate, 0)
    gate /= np.max(gate) + 1e-9
    band = np.exp(-((np.log2(np.maximum(f, 1) / (1400.0 * p["bright"]))) ** 2) / 1.6)
    rasp = circ_filter(nz, band) * gate
    rasp /= np.max(np.abs(rasp)) + 1e-9
    out += p["rasp"] * rasp * (0.25 + 0.75 * load) * (0.5 + 0.5 * rp)
    # valvetrain / mechanical hash
    mech = circ_filter(r.standard_normal(n), np.exp(-((np.log2(np.maximum(f, 1) / 3800.0)) ** 2) / 0.8))
    mech /= np.max(np.abs(mech)) + 1e-9
    out += 0.05 * mech * (0.4 + 0.6 * gate)
    out = circ_filter(out, f ** 2 / (f ** 2 + 38.0 ** 2))       # nothing useful below ~40 Hz
    out /= np.max(np.abs(out)) + 1e-9
    drive = 1.1 + 1.6 * load + 0.6 * rp
    out = np.tanh(out * drive) / np.tanh(drive)
    out *= (0.26 if load > 0.5 else 0.2) / (out.std() + 1e-9)   # equal loudness across layers
    out = np.tanh(out * 1.3) / 1.3
    # intake roar (separate file, on-load only)
    ih = np.exp(-((np.log2(np.maximum(f, 1) / (300.0 + 500.0 * rp))) ** 2) / 2.2) / (1.0 - 0.5 * np.exp(-2j * np.pi * f * 0.0034))
    ink = circ_filter(intake, ih) + 0.5 * circ_filter(nz, np.exp(-((np.log2(np.maximum(f, 1) / 900.0)) ** 2) / 1.5)) * (0.4 + 0.6 * gate)
    return out, ink


def engines():
    for name, p in PROFILES.items():
        for i, rpm in enumerate(p["rpms"]):
            on, ink = render(p, rpm, 1.0, zlib.crc32(("%s%d" % (name, rpm)).encode()) % 100000)
            off, _ = render(p, rpm, 0.0, zlib.crc32(("%s%doff" % (name, rpm)).encode()) % 100000)
            write(os.path.join(ENG, "%s_%d_on.wav" % (name, rpm)), on)
            write(os.path.join(ENG, "%s_%d_off.wav" % (name, rpm)), off)
            if i == 2:
                write(os.path.join(ENG, "%s_intake.wav" % name), ink, 0.6)
        # startup: starter motor, then the idle layer catching with a short flare
        idle, _ = render(p, p["rpms"][0], 0.7, 4242)
        flare, _ = render(p, p["rpms"][1], 1.0, 4243)
        n = int(SR * 1.9)
        t = np.arange(n) / SR
        rr = np.random.default_rng(5)
        crank_f = 9.0 + 3.0 * np.minimum(t / 0.5, 1)
        starter = np.sin(2 * np.pi * np.cumsum(180 + 60 * np.sin(2 * np.pi * np.cumsum(crank_f) / SR)) / SR) * 0.35
        starter += 0.25 * rr.standard_normal(n) * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(crank_f) / SR))
        starter *= (t < 0.62) * np.minimum(t / 0.03, 1) * np.minimum((0.62 - t).clip(0) / 0.05, 1)
        a = np.resize(flare, n) * np.clip((t - 0.5) / 0.08, 0, 1) * np.exp(-np.clip(t - 0.6, 0, None) / 0.35)
        b = np.resize(idle, n) * np.clip((t - 0.85) / 0.5, 0, 1) * np.clip((1.9 - t) / 0.25, 0, 1)
        write(os.path.join(ENG, "%s_start.wav" % name), starter + a * 0.9 + b * 0.75, 0.85)
        print("engine", name)


# ------------------------------------------------------------------ helpers for the rest
def noise_loop(n, shape, seed):
    r = np.random.default_rng(seed)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    x = circ_filter(r.standard_normal(n), shape(f))
    return x / (np.max(np.abs(x)) + 1e-9)


def band(fc, width):
    return lambda f: np.exp(-((np.log2(np.maximum(f, 1) / fc)) ** 2) / width)


def tone_loop(n, partials, vib_hz=0.0, vib=0.0):
    t = np.arange(n) / SR
    dur = n / SR
    x = np.zeros(n)
    for fr, a in partials:
        k = round(fr * dur)
        ph = 2 * np.pi * k * t / dur
        if vib_hz:
            ph += vib * np.sin(2 * np.pi * round(vib_hz * dur) * t / dur + fr)
        x += a * np.sin(ph)
    return x / (np.max(np.abs(x)) + 1e-9)


def one_shot_noise(dur, fc, width, tau, seed, attack=0.002):
    n = int(SR * dur)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    x = np.fft.irfft(np.fft.rfft(r.standard_normal(n)) * band(fc, width)(f), n)
    x /= np.max(np.abs(x)) + 1e-9
    return x * np.exp(-t / tau) * np.minimum(t / attack, 1)


def car_sounds():
    n2 = SR * 2
    # turbo: compressor whistle (blade-pass tones) riding on rushing air
    whistle = tone_loop(n2, [(2600, 1.0), (2615, 0.7), (5200, 0.35), (7800, 0.15)], 5.0, 0.25)
    air = noise_loop(n2, band(3600, 1.2), 11)
    write(os.path.join(CAR, "turbo_spool.wav"), whistle * 0.5 + air * 0.6, 0.5)
    # big-frame turbo: lower, breathier
    whistle = tone_loop(n2, [(1500, 1.0), (1512, 0.8), (3000, 0.4), (4500, 0.2)], 4.0, 0.3)
    air = noise_loop(n2, band(2200, 1.6), 12)
    write(os.path.join(CAR, "turbo_spool_big.wav"), whistle * 0.45 + air * 0.75, 0.5)
    # blow-off valves: sharp vent (small) and long whoosh (big)
    t = np.arange(int(SR * 0.55)) / SR
    x = one_shot_noise(0.55, 4200, 1.4, 0.07, 21) + 0.7 * one_shot_noise(0.55, 1600, 1.2, 0.16, 22, 0.02)
    write(os.path.join(CAR, "bov_small.wav"), x, 0.8)
    x = one_shot_noise(0.9, 3000, 1.8, 0.12, 23) + 0.9 * one_shot_noise(0.9, 1100, 1.4, 0.3, 24, 0.03)
    write(os.path.join(CAR, "bov_big.wav"), x, 0.85)
    # compressor surge flutter: "stu-tu-tu-tu", pulses slowing and fading
    for i, (rate0, cnt) in enumerate(((34.0, 9), (26.0, 7))):
        n = int(SR * 0.8)
        y = np.zeros(n)
        tt = 0.0
        for k in range(cnt):
            b = one_shot_noise(0.07, 1500 - 60 * k, 1.5, 0.014, 30 + i * 20 + k, 0.001)
            j = int(tt * SR)
            m = min(len(b), n - j)
            y[j:j + m] += b[:m] * (0.92 ** k)
            tt += 1.0 / (rate0 * (0.9 ** k))
        write(os.path.join(CAR, "flutter_%d.wav" % (i + 1)), y, 0.8)
    # wastegate: harsh pulsing hiss while boost is held at the limit
    wg = noise_loop(SR, band(5200, 0.9), 41)
    t1 = np.arange(SR) / SR
    wg *= 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * 31 * t1))
    write(os.path.join(CAR, "wastegate.wav"), wg, 0.5)
    # supercharger: rotor-lobe whine with sidebands and belt hash
    sc = tone_loop(n2, [(1250, 1.0), (1262, 0.6), (2500, 0.7), (3750, 0.45), (5000, 0.25), (625, 0.3)], 7.0, 0.12)
    sc = sc * 0.8 + noise_loop(n2, band(2400, 0.7), 51) * 0.25
    write(os.path.join(CAR, "sc_whine.wav"), sc, 0.5)
    # gearbox: straight-cut style gear mesh whine
    tr = tone_loop(n2, [(880, 1.0), (891, 0.5), (1760, 0.5), (2640, 0.22)], 3.0, 0.1)
    write(os.path.join(CAR, "trans_whine.wav"), tr * 0.8 + noise_loop(n2, band(1200, 0.5), 52) * 0.2, 0.4)
    # exhaust pops / crackles and backfires
    for i in range(5):
        r = np.random.default_rng(60 + i)
        dur = 0.16 + 0.05 * r.random()
        fcp = 900 + 900 * r.random()
        x = one_shot_noise(dur, fcp, 2.2, 0.018 + 0.012 * r.random(), 70 + i, 0.0006)
        t = np.arange(len(x)) / SR
        thump = np.sin(2 * np.pi * (140 - 200 * t).clip(40) * t) * np.exp(-t / 0.03)
        write(os.path.join(CAR, "pop_%d.wav" % (i + 1)), np.tanh((x + 0.7 * thump) * 2.2), 0.85)
    for i in range(2):
        x = one_shot_noise(0.5, 500 + 250 * i, 2.6, 0.06, 80 + i, 0.0008)
        t = np.arange(len(x)) / SR
        thump = np.sin(2 * np.pi * 70 * t * np.exp(-t * 5)) * np.exp(-t / 0.09)
        tail = one_shot_noise(0.5, 1800, 2.0, 0.14, 85 + i, 0.02) * 0.3
        write(os.path.join(CAR, "backfire_%d.wav" % (i + 1)), np.tanh((x + thump + tail) * 2.5), 0.95)
    # tyres: high squeal, low scrubbing drift, and a brake squeal
    sq = tone_loop(n2, [(940, 1), (1075, 0.8), (1410, 0.6), (1930, 0.4), (2520, 0.3)], 7.0, 0.6)
    write(os.path.join(CAR, "tire_squeal.wav"), np.tanh(sq * 1.2) * 0.55 + noise_loop(n2, band(1500, 1.2), 91) * 0.6, 0.7)
    sc2 = noise_loop(n2, band(520, 1.6), 92) * (0.75 + 0.25 * tone_loop(n2, [(23, 1), (37, 0.6)]))
    write(os.path.join(CAR, "tire_scrub.wav"), sc2 + 0.3 * tone_loop(n2, [(410, 1), (455, 0.7), (610, 0.5)], 5.0, 0.8), 0.7)
    bq = tone_loop(n2, [(2950, 1), (2962, 0.6), (5900, 0.25)], 9.0, 0.2) * 0.6 + noise_loop(n2, band(900, 1.5), 93) * 0.5
    write(os.path.join(CAR, "brake_squeal.wav"), bq, 0.45)
    # road roar and wind, separate so each follows its own curve
    write(os.path.join(CAR, "road.wav"), noise_loop(n2, lambda f: 1.0 / (1.0 + (f / 260.0) ** 3) + 0.12 * band(1100, 0.8)(f), 94), 0.6)
    write(os.path.join(CAR, "wind.wav"), noise_loop(n2, lambda f: band(700, 3.0)(f) * (f / (f + 150.0)), 95) * (0.8 + 0.2 * tone_loop(n2, [(0.5, 1), (1.5, 0.5)])), 0.6)
    # rev limiter cut "thud"
    x = one_shot_noise(0.09, 300, 2.0, 0.02, 96, 0.0005)
    write(os.path.join(CAR, "limiter.wav"), x, 0.7)
    print("car sounds")


if __name__ == "__main__":
    engines()
    car_sounds()

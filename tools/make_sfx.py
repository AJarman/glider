#!/usr/bin/env python3
"""Synthesises the game's sound effects into assets/sfx. Standard library only."""
import math
import os
import random
import struct
import wave

RATE = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
random.seed(7)


def silence(dur):
    return [0.0] * int(dur * RATE)


def mix(*parts):
    """Each part is (samples, start seconds, gain)."""
    end = max(int(t * RATE) + len(s) for s, t, _ in parts)
    out = [0.0] * end
    for s, t, g in parts:
        o = int(t * RATE)
        for i, v in enumerate(s):
            out[o + i] += v * g
    return out


def sweep(f0, f1, dur, decay=4.0, shape=math.sin, curve=1.0):
    n = int(dur * RATE)
    phase = 0.0
    out = []
    for i in range(n):
        t = i / n
        phase += 2 * math.pi * (f0 + (f1 - f0) * t ** curve) / RATE
        out.append(shape(phase) * math.exp(-decay * t))
    return out


def saw(p):
    return ((p / (2 * math.pi)) % 1.0) * 2.0 - 1.0


def noise(dur, cut0, cut1, decay=4.0, attack=0.0):
    n = int(dur * RATE)
    y = 0.0
    out = []
    for i in range(n):
        t = i / n
        a = min((cut0 + (cut1 - cut0) * t) * 2 * math.pi / RATE, 1.0)
        y += a * (random.uniform(-1, 1) - y)
        env = math.exp(-decay * t) * (min(t / attack, 1.0) if attack else 1.0)
        out.append(y * env * 2.2)
    return out


def pluck(freq, dur, bright=0.5):
    """Karplus-Strong string: koto and shamisen."""
    size = int(RATE / freq)
    line = [random.uniform(-1, 1) for _ in range(size)]
    last = 0.0
    for i in range(1, size):
        line[i] = line[i] * bright + line[i - 1] * (1 - bright)
    out = []
    for i in range(int(dur * RATE)):
        v = line[i % size]
        line[i % size] = (v + last) * 0.4985
        last = v
        out.append(v)
    return out


def bell(freqs, dur, decay=5.0):
    return mix(*[(sweep(f, f, dur, decay * (1 + k * 0.4)), 0, 1.0 / (k + 1)) for k, f in enumerate(freqs)])


def taiko(pitch=1.0, dur=0.9):
    body = sweep(150 * pitch, 58 * pitch, dur, 6.0, curve=0.35)
    skin = noise(0.05, 2600, 500, 5.0)
    return mix((body, 0, 1.0), (skin, 0, 0.35))


def voice(f0, f1, dur, formants, vibrato=7.0):
    """A sawtooth through vowel resonators: kabuki-style shouts."""
    n = int(dur * RATE)
    phase = 0.0
    src = []
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t * t
        f *= 1 + 0.03 * t * math.sin(2 * math.pi * vibrato * i / RATE)
        phase += 2 * math.pi * f / RATE
        src.append(saw(phase) * min(t * 18, 1) * min((1 - t) * 6, 1))
    out = [0.0] * n
    for fc, bw, g in formants:
        r = math.exp(-math.pi * bw / RATE)
        c = 2 * r * math.cos(2 * math.pi * fc / RATE)
        y1 = y2 = 0.0
        for i in range(n):
            y = src[i] * (1 - r) + c * y1 - r * r * y2
            y2, y1 = y1, y
            out[i] += y * g
    return out


VOWEL_O = [(450, 90, 1.0), (800, 110, 0.5), (2600, 170, 0.1)]
VOWEL_I = [(300, 70, 1.0), (2300, 120, 0.3), (3000, 170, 0.1)]
VOWEL_A = [(750, 110, 1.0), (1200, 120, 0.6), (2600, 170, 0.15)]


def crush(s, step):
    out = []
    held = 0.0
    for i, v in enumerate(s):
        if i % step == 0:
            held = round(v * 10) / 10
        out.append(held)
    return out


def echo(s, delay=0.13, fb=0.4, tail=0.6):
    d = int(delay * RATE)
    out = s + [0.0] * int(tail * RATE)
    for i in range(d, len(out)):
        out[i] += out[i - d] * fb
    return out


def seamless(s, fade):
    """Equal-power crossfade of the tail into the head, so a noise loop has no seam."""
    n = int(fade * RATE)
    body = s[:-n]
    for i in range(n):
        t = i / n * math.pi / 2
        body[i] = body[i] * math.sin(t) + s[len(body) + i] * math.cos(t)
    return body


def blown(dur, fc, damp, level):
    """Noise through a resonant band-pass, with centre and level as functions of
    time in 0..1. Moving those slowly is what makes noise sound like air, not hiss."""
    n = int(dur * RATE)
    low = band = 0.0
    out = []
    for i in range(n):
        t = i / n
        f = 2 * math.sin(math.pi * fc(t) / RATE)
        high = random.uniform(-1, 1) - low - damp * band
        band += f * high
        low += f * band
        out.append(band * level(t) * damp)
    return out


def muffle(s, cut, passes=3):
    """Stacked low-pass filters, to take the hiss off filtered noise."""
    a = min(cut * 2 * math.pi / RATE, 1.0)
    for _ in range(passes):
        y = 0.0
        out = []
        for v in s:
            y += a * (v - y)
            out.append(y)
        s = out
    return s


def drift(*waves):
    """Slow wobble: (cycles per loop, depth, phase) sine waves added together."""
    def wobble(t):
        return 1.0 + sum(d * math.sin(2 * math.pi * c * t + p) for c, d, p in waves)
    return wobble


def write(name, s, gain=0.85):
    peak = max(abs(v) for v in s) or 1.0
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(math.tanh(v / peak * 1.3) * gain * 32000)) for v in s))


# In scale, the sound of the koto.
D, EB, G, A, BB = 293.66, 311.13, 392.0, 440.0, 466.16
SCALE = [D, EB, G, A, BB, D * 2, EB * 2, G * 2, A * 2, BB * 2, D * 4]


def koto_run(notes, gap, tail=0.9):
    return mix(*[(pluck(SCALE[n], tail, 0.6), i * gap, 1.0) for i, n in enumerate(notes)])


def sparkle(count=14, dur=0.9):
    return mix(*[(sweep(f, f, 0.3, 7.0), i * dur / count, 0.5)
                 for i, f in enumerate(random.uniform(2400, 6200) for _ in range(count))])


write("tick", mix((sweep(1500, 1100, 0.035, 5.0), 0, 1), (noise(0.012, 5000, 2000, 3), 0, 0.5)), 0.55)
write("step", mix((sweep(120, 70, 0.07, 7), 0, 1), (noise(0.03, 500, 200, 7), 0, 0.3)), 0.4)
write("taiko", echo(taiko(), 0.11, 0.25, 0.3))
write("ready", mix((taiko(1.3, 0.3), 0, 0.5), (taiko(1.3, 0.3), 0.12, 0.6), (taiko(1.3, 0.3), 0.24, 0.8), (taiko(0.9), 0.36, 1.0)))
write("yoo", echo(mix((voice(190, 150, 0.2, VOWEL_I), 0, 0.5), (voice(240, 520, 0.75, VOWEL_O), 0.14, 1.0),
                      (noise(0.03, 5000, 3000, 2), 0.93, 1.5), (noise(0.03, 5000, 3000, 2), 1.0, 1.0)), 0.16, 0.3, 0.5))
write("go", mix((taiko(0.8), 0, 1.0), (koto_run([0, 2, 3, 5, 7, 8, 10], 0.05), 0.02, 0.55),
                (voice(320, 640, 0.42, VOWEL_A, 11), 0.05, 0.55)))
write("launch", mix((sweep(180, 2400, 0.8, 1.5, curve=2.2), 0, 0.5), (noise(0.9, 400, 6000, 2.5, 0.4), 0, 0.8)))
write("wings", echo(mix((noise(0.18, 8000, 1500, 4), 0, 0.7), (bell([1760, 2640, 3960, 5280], 0.7, 6), 0.04, 0.6),
                        (sweep(900, 3600, 0.16, 1.0), 0, 0.25))))
write("skim", mix((sweep(300, 1500, 0.18, 1.2, curve=0.6), 0, 0.9), (sweep(700, 2000, 0.12, 2.5), 0.12, 0.5),
                  (noise(0.3, 3000, 900, 4), 0, 0.5)))
write("splash", mix((noise(0.9, 3500, 400, 4), 0, 1.0), (sweep(120, 420, 0.14, 2), 0.05, 0.7), (sweep(180, 620, 0.1, 2), 0.2, 0.5),
                    (sweep(260, 800, 0.08, 2), 0.32, 0.4)))
write("crash", crush(mix((taiko(0.55, 0.7), 0, 1.2), (noise(0.45, 5200, 500, 4), 0, 1.0), (sweep(70, 34, 0.7, 3), 0, 1.0)), 3))
shrapnel = mix(*[(bell([random.uniform(1800, 5200), random.uniform(3000, 7000)], 0.09, 7), 0.25 + random.uniform(0, 1.1), 0.5)
                 for _ in range(26)])
write("boom", echo(crush(mix((shrapnel, 0, 0.8), (noise(1.5, 2500, 90, 3.2), 0, 1.3), (sweep(95, 26, 1.5, 3), 0, 1.3),
                             (bell([610, 1183, 1771], 1.3, 5), 0.02, 0.3)), 2), 0.2, 0.3, 0.6))
write("beep", sweep(1760, 1760, 0.075, 1.0, lambda p: 1.0 if math.sin(p) > 0 else -1.0), 0.5)
write("score", echo(mix((koto_run([0, 2, 3, 4, 5, 7], 0.075), 0, 1.0), (sparkle(), 0.3, 0.5))))
write("perfect", echo(mix((koto_run([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.055, 1.3), 0, 1.0), (bell([98, 196, 293, 391, 587], 2.2, 3), 0.55, 0.75),
                          (sparkle(26, 1.6), 0.5, 0.6), (voice(260, 560, 0.5, VOWEL_A), 0.55, 0.45))))
write("miss", mix((pluck(BB, 0.7, 0.45), 0, 1), (pluck(A, 0.7, 0.45), 0.2, 1), (pluck(EB, 0.8, 0.45), 0.4, 1),
                  (sweep(420, 90, 0.9, 1.6, saw, 1.4), 0.55, 0.22)))
write("modifier", echo(mix((taiko(0.7), 0, 1.0), (taiko(0.7), 0.16, 1.0), (bell([146, 311, 466, 622, 932], 1.5, 3), 0.16, 0.8),
                           (sweep(116, 110, 0.9, 1.6, saw), 0.16, 0.3), (sweep(123, 117, 0.9, 1.6, saw), 0.16, 0.3))))
write("kira", mix((sparkle(), 0, 1.0), (bell([1568, 2349], 0.6, 5), 0, 0.5)))


def rush():
    """Airflow past the body: a soft low roar with a gentle moving breath on top."""
    size = 9.0
    roar_f, roar_l = drift((2, 0.1, 0.0), (5, 0.05, 1.0)), drift((3, 0.18, 0.4), (7, 0.08, 2.0))
    air_f, air_l = drift((3, 0.22, 2.0), (7, 0.1, 0.5)), drift((2, 0.35, 1.0), (5, 0.2, 2.5))
    return mix((blown(size, lambda t: 210 * roar_f(t), 0.9, roar_l), 0, 1.0),
               (blown(size, lambda t: 520 * air_f(t), 0.7, air_l), 0, 0.45))


def gale():
    """A storm: deep buffeting with long gusts and a low moan rising through them."""
    size = 14.0
    gust = drift((2, 0.45, 0.0), (5, 0.22, 1.3), (9, 0.1, 2.2))
    moan_f = drift((2, 0.3, 0.3), (5, 0.12, 1.0))
    return mix((blown(size, lambda t: 130 * (0.8 + 0.2 * gust(t)), 1.0, gust), 0, 1.0),
               (blown(size, lambda t: 330 * moan_f(t), 0.35, lambda t: max(gust(t) - 0.6, 0.0)), 0, 0.5))


write("rush", seamless(muffle(rush(), 750), 1.5), 0.6)
write("storm", seamless(muffle(gale(), 480), 2.0), 0.6)

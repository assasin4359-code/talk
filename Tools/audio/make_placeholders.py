#!/usr/bin/env python3
"""Synthesizes the TEMPORARY sounds in assets/audio/placeholder/.

Stand-ins until real recordings arrive (see assets/audio/README.md). Deterministic:
re-running produces identical files. Loops carry a WAV 'smpl' chunk so Godot's
importer ("Detect from WAV") plays them seamlessly without editing .import files.

    python Tools/audio/make_placeholders.py
"""
from __future__ import annotations

import math
import random
import struct
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "placeholder"

# Rough vowel formants (F1, F2, F3) in Hz. Index order is the voice-sample order the
# game uses: a, e, i, o, u (game/audio/fake_voice.gd maps Hangul vowels onto these).
VOWELS = {
    "a": (800, 1200, 2500),
    "e": (500, 1900, 2500),
    "i": (300, 2300, 3000),
    "o": (500, 850, 2500),
    "u": (320, 800, 2300),
}


def write_wav(path: Path, samples: list[float], loop: bool = False) -> None:
    pcm = b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples)
    fmt = struct.pack("<HHIIHH", 1, 1, RATE, RATE * 2, 2, 16)
    chunks = [b"fmt " + struct.pack("<I", len(fmt)) + fmt, b"data" + struct.pack("<I", len(pcm)) + pcm]
    if loop:
        # smpl chunk: one forward loop over the whole sample
        smpl = struct.pack("<9I", 0, 0, int(1e9 / RATE), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(samples) - 1, 0, 0)
        chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    body = b"WAVE" + b"".join(chunks)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"RIFF" + struct.pack("<I", len(body)) + body)


def normalize(s: list[float], peak: float) -> list[float]:
    m = max(abs(x) for x in s) or 1.0
    return [x * peak / m for x in s]


def lowpass(s: list[float], cutoff: float) -> list[float]:
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    out, y = [], 0.0
    for x in s:
        y += a * (x - y)
        out.append(y)
    return out


def highpass(s: list[float], cutoff: float) -> list[float]:
    lp = lowpass(s, cutoff)
    return [x - y for x, y in zip(s, lp)]


def crossfade_loop(s: list[float], fade: int) -> list[float]:
    """Last `fade` samples blend into the first ones, so end -> start is seamless."""
    body, tail = s[: len(s) - fade], s[len(s) - fade:]
    for i in range(fade):
        t = i / fade
        body[i] = body[i] * t + tail[i] * (1 - t)
    return body


def voice_blip(formants: tuple[int, int, int], f0: float = 190.0, dur: float = 0.085) -> list[float]:
    n = int(dur * RATE)
    harmonics = []
    for k in range(1, int(3800 / f0)):
        f = k * f0
        amp = sum(math.exp(-(((f - F) / 110.0) ** 2)) * g for F, g in zip(formants, (1.0, 0.7, 0.35)))
        harmonics.append((f, amp + 0.02 / k))
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.006) * min(1.0, (dur - t) / 0.03)
        out.append(env * sum(a * math.sin(2 * math.pi * f * t) for f, a in harmonics))
    return normalize(out, 0.6)


def footstep(kind: str, seed: int) -> list[float]:
    rng = random.Random(seed)
    dur = 0.14 + rng.uniform(-0.02, 0.02)
    n = int(dur * RATE)
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    if kind == "dirt":  # soft, low, a little crunch
        body = lowpass(noise, 700 + rng.uniform(-100, 100))
        decay = 0.035
        crunch = [rng.uniform(-1, 1) if rng.random() < 0.02 else 0.0 for _ in range(n)]
        body = [b + 0.15 * c for b, c in zip(body, highpass(crunch, 2500))]
    elif kind == "stone":  # hard, bright, short
        body = highpass(lowpass(noise, 3200), 400)
        decay = 0.018
    else:  # wood: hollow knock
        f = 170 + rng.uniform(-20, 20)
        body = [0.8 * math.sin(2 * math.pi * f * i / RATE) + 0.4 * x for i, x in enumerate(lowpass(noise, 1400))]
        decay = 0.04
    out = []
    for i, x in enumerate(body):
        t = i / RATE
        out.append(x * min(1.0, t / 0.003) * math.exp(-t / decay))
    return normalize(out, 0.5)


def wind_loop(seconds: float = 8.0) -> list[float]:
    rng = random.Random(7)
    fade = RATE
    n = int(seconds * RATE) + fade
    noise = lowpass(lowpass([rng.uniform(-1, 1) for _ in range(n)], 400), 900)
    out = []
    for i, x in enumerate(noise):
        t = i / RATE
        swell = 0.55 + 0.25 * math.sin(2 * math.pi * 0.13 * t) + 0.2 * math.sin(2 * math.pi * 0.31 * t + 1.7)
        out.append(x * swell)
    return normalize(crossfade_loop(out, fade), 0.3)


def fire_loop(seconds: float = 4.0) -> list[float]:
    rng = random.Random(11)
    fade = RATE // 2
    n = int(seconds * RATE) + fade
    out = [x * 0.25 for x in lowpass([rng.uniform(-1, 1) for _ in range(n)], 250)]
    i = 0
    while i < n:  # crackles: short bright pops at random intervals
        i += int(rng.expovariate(14.0) * RATE) + 1
        amp = rng.uniform(0.2, 1.0)
        for j in range(min(220, n - i)):
            out[i + j] += amp * rng.uniform(-1, 1) * math.exp(-j / 40.0)
    return normalize(crossfade_loop(highpass(out, 60), fade), 0.35)


def main() -> None:
    for name, formants in VOWELS.items():
        write_wav(OUT / "voice" / f"blip_{name}.wav", voice_blip(formants))
    for kind in ("dirt", "stone", "wood"):
        for v in range(1, 5):
            write_wav(OUT / "footsteps" / f"{kind}_{v}.wav", footstep(kind, seed=v * 101 + len(kind)))
    write_wav(OUT / "ambience" / "wind_loop.wav", wind_loop(), loop=True)
    write_wav(OUT / "ambience" / "fire_loop.wav", fire_loop(), loop=True)
    for p in sorted(OUT.rglob("*.wav")):
        print(f"{p.relative_to(OUT.parent.parent.parent)}  {p.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()

"""Generates the game's placeholder sound effects as .wav files in audio/sfx/.

Everything is synthesized from sine, square and noise waves, so there are no licensing
questions. Run it again after tweaking a sound:  python tools/make_placeholder_sfx.py
Replace any file with a real sound later; the game only cares about the file name.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "sfx")
random.seed(7)


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def tone(freq_start, freq_end, seconds, shape="sine", volume=0.6, decay=4.0):
    """A pitch sweep with an exponential fade."""
    out = []
    phase = 0.0
    n = int(RATE * seconds)
    for i in range(n):
        t = i / n
        freq = freq_start + (freq_end - freq_start) * t
        phase += 2 * math.pi * freq / RATE
        if shape == "sine":
            v = math.sin(phase)
        elif shape == "square":
            v = 1.0 if math.sin(phase) >= 0 else -1.0
        else:  # saw
            v = (phase / math.pi) % 2 - 1
        out.append(v * volume * math.exp(-decay * t))
    return out


def noise(seconds, volume=0.6, decay=6.0, smooth=0.0):
    """White noise, optionally low-passed (smooth near 1 = darker)."""
    out = []
    last = 0.0
    n = int(RATE * seconds)
    for i in range(n):
        t = i / n
        v = random.uniform(-1, 1)
        last = last * smooth + v * (1 - smooth)
        out.append(last * volume * math.exp(-decay * t))
    return out


def mix(*layers):
    length = max(len(layer) for layer in layers)
    out = [0.0] * length
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    return out


def then(*parts):
    out = []
    for part in parts:
        out.extend(part)
    return out


def save(name, samples):
    os.makedirs(OUT, exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))


# Guns
save("rivet_shot", mix(noise(0.12, 0.7, 18), tone(180, 60, 0.12, "sine", 0.8, 10)))
save("shotgun_shot", mix(noise(0.4, 0.9, 7, 0.3), tone(110, 40, 0.35, "sine", 1.0, 6)))
save("bolt_shot", mix(tone(1800, 300, 0.25, "saw", 0.4, 6), noise(0.08, 0.5, 20), tone(90, 50, 0.2, "sine", 0.7, 8)))
save("reload", then(tone(900, 700, 0.04, "square", 0.4, 12), silence(0.25), tone(600, 1100, 0.05, "square", 0.4, 10)))
save("switch", tone(1400, 900, 0.04, "square", 0.3, 12))
save("empty", tone(2000, 1800, 0.03, "square", 0.25, 20))

# Hits and robots
save("hit", tone(2400, 2000, 0.04, "square", 0.25, 15))
save("kill", mix(tone(700, 120, 0.25, "square", 0.35, 6), noise(0.25, 0.5, 8, 0.2)))
save("robot_swing", noise(0.22, 0.6, 5, 0.85))
save("robot_death", mix(noise(0.35, 0.7, 6, 0.5), tone(300, 60, 0.35, "saw", 0.4, 5)))
save("bolt_fire", mix(tone(500, 1200, 0.18, "sine", 0.5, 4), noise(0.1, 0.2, 10)))
save("bolt_impact", mix(noise(0.15, 0.6, 12, 0.4), tone(800, 200, 0.12, "sine", 0.4, 10)))

# Player
save("player_hurt", mix(tone(160, 70, 0.2, "square", 0.4, 8), noise(0.15, 0.5, 12, 0.6)))
save("downed", mix(tone(600, 70, 0.9, "saw", 0.5, 2.5), noise(0.9, 0.25, 3, 0.3)))
save("revive", then(tone(200, 900, 0.35, "sine", 0.6, 1.5), tone(900, 1200, 0.15, "sine", 0.4, 5)))

# Hacking
save("hack_lock", tone(1300, 1500, 0.08, "square", 0.3, 8))
save("hack_miss", tone(150, 120, 0.18, "square", 0.4, 4))
save("hack_success", then(tone(600, 600, 0.08, "square", 0.3, 3), tone(800, 800, 0.08, "square", 0.3, 3), tone(1200, 1200, 0.2, "square", 0.3, 4)))
save("hack_fail", then(tone(500, 500, 0.12, "square", 0.3, 2), tone(300, 300, 0.12, "square", 0.3, 2), tone(150, 100, 0.35, "square", 0.3, 3)))

# Economy and world
save("scrap", then(tone(1000, 1000, 0.05, "sine", 0.4, 6), tone(1500, 1500, 0.09, "sine", 0.4, 6)))
save("buy", then(tone(700, 700, 0.07, "square", 0.25, 4), tone(950, 950, 0.07, "square", 0.25, 4), tone(1400, 1400, 0.16, "square", 0.25, 5)))
save("refuse", tone(110, 100, 0.22, "square", 0.35, 3))
save("gate_open", mix(noise(0.9, 0.8, 3, 0.92), tone(70, 40, 0.9, "saw", 0.4, 3)))
save("button", tone(500, 500, 0.12, "square", 0.3, 6))

# Rounds and the Warden
save("round_start", then(tone(220, 220, 0.35, "saw", 0.4, 1), tone(165, 165, 0.6, "saw", 0.4, 2)))
save("round_end", mix(tone(440, 440, 0.8, "sine", 0.3, 3), tone(554, 554, 0.8, "sine", 0.25, 3), tone(659, 659, 0.8, "sine", 0.25, 3)))
save("countdown_tick", tone(1000, 1000, 0.05, "sine", 0.3, 10))
save("warden_slam", mix(noise(0.7, 1.0, 4, 0.9), tone(60, 30, 0.7, "sine", 1.0, 3)))
save("warden_groan", mix(tone(55, 45, 1.2, "saw", 0.5, 1.5), tone(82, 70, 1.2, "sine", 0.4, 1.5)))

print("Wrote sounds to", os.path.abspath(OUT))

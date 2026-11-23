"""The ASKODOX tune played before every payment voice (owner 2026-11-23, branding).

Makes askodox_tune.wav here; encode it with
  ffmpeg -i askodox_tune.wav -c:a libvorbis -q:a 4 android/app/src/main/res/raw/askodox_tune.ogg
"""
import numpy as np, wave
sr = 44100
dur = 0.95
t = np.arange(int(sr * dur)) / sr
out = np.zeros_like(t)
# "AS-KO-DOX": three bright notes going up (G5, C6, E6), bell-like, the last one rings a little longer.
notes = [(0.00, 783.99, 0.42), (0.16, 1046.50, 0.42), (0.32, 1318.51, 0.62)]
for start, f, length in notes:
    n0 = int(start * sr)
    tt = t[n0:] - start
    env = np.minimum(tt / 0.008, 1.0) * np.exp(-tt / (length / 3.2))
    tone = (np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(2 * np.pi * 2 * f * tt) * np.exp(-tt / 0.08)
            + 0.12 * np.sin(2 * np.pi * 3.01 * f * tt) * np.exp(-tt / 0.05))
    out[n0:] += env * tone
fade = np.ones_like(t); k = int(0.06 * sr); fade[-k:] = np.linspace(1, 0, k)
out *= fade
out = out / np.max(np.abs(out)) * 0.7
pcm = (out * 32767).astype(np.int16)
with wave.open("askodox_tune.wav", "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm.tobytes())

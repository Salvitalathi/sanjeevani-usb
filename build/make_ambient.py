"""Calm ambient loop played while the Assistant works (assets/ambient.mp3).
Generated here (no third-party audio, no licence questions): slow pad chords from detuned sine partials,
a soft high shimmer and a little filtered air. The loop is seamless (the end crossfades into the start).
Needs numpy + ffmpeg."""
import numpy as np, subprocess, os, tempfile, wave

SR = 32000
DUR = 64.0
N = int(SR * DUR)
t = np.arange(N) / SR
rng = np.random.default_rng(7)

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)
# A minor-ish, calm: Am9, Fmaj7, Cmaj9, Gadd9 (MIDI notes)
chords = [[45, 57, 60, 64, 67, 71], [41, 53, 57, 60, 64, 69], [48, 55, 59, 62, 64, 67], [43, 55, 57, 59, 62, 66]]
seg = DUR / len(chords)
L = np.zeros(N); R = np.zeros(N)

def env_for(i):
    # raised-cosine window, 1.6 segments long, centred on the segment, wrapping around the loop
    c = (i + 0.5) * seg
    width = seg * 1.6
    d = (t - c + DUR / 2) % DUR - DUR / 2
    e = np.where(np.abs(d) < width / 2, 0.5 * (1 + np.cos(np.pi * d / (width / 2))), 0.0)
    return e

for i, ch in enumerate(chords):
    e = env_for(i)
    for k, m in enumerate(ch):
        f = hz(m)
        amp = 0.16 if k == 0 else 0.07
        for det, pan in ((-0.12, 0.25), (0.0, 0.5), (0.13, 0.75)):
            ph = rng.uniform(0, 2 * np.pi)
            # loop-exact frequency so the wave also wraps cleanly
            fr = round((f * 2 ** (det / 12)) * DUR) / DUR
            s = np.sin(2 * np.pi * fr * t + ph) + 0.18 * np.sin(2 * np.pi * 2 * fr * t + ph * 1.3)
            trem = 1 + 0.12 * np.sin(2 * np.pi * (round(0.11 * DUR) / DUR) * t + k)
            L += amp * e * s * trem * (1 - pan); R += amp * e * s * trem * pan

# shimmer: soft bell notes from the scale, slowly
scale = [76, 79, 81, 83, 84, 88]
for j in range(14):
    st = (j * DUR / 14 + rng.uniform(0, 1.5))
    f = hz(scale[rng.integers(len(scale))])
    d = (t - st) % DUR
    e = np.where(d < 6, np.exp(-d / 1.6) * (1 - np.exp(-d * 40)), 0)
    s = np.sin(2 * np.pi * f * t) * e * 0.035
    p = rng.uniform(0.2, 0.8)
    L += s * (1 - p); R += s * p

# air: low-passed noise, circular so it loops
def lp_noise():
    n = rng.standard_normal(N)
    F = np.fft.rfft(n); fr = np.fft.rfftfreq(N, 1 / SR)
    F *= 1 / (1 + (fr / 900) ** 2)
    return np.fft.irfft(F, N)
air = 0.012 / 0.05
L += lp_noise() * 0.004; R += lp_noise() * 0.004

mx = max(np.abs(L).max(), np.abs(R).max())
L = L / mx * 0.5; R = R / mx * 0.5
pcm = (np.stack([L, R], 1) * 32767).astype('<i2')
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(root, 'kit', 'Sanjeevani', 'PCDoctor', 'assets', 'ambient.mp3')
with tempfile.TemporaryDirectory() as d:
    w = os.path.join(d, 'a.wav')
    with wave.open(w, 'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(SR); f.writeframes(pcm.tobytes())
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', w, '-b:a', '80k', '-ar', '32000', out], check=True)
print('wrote', out, os.path.getsize(out) // 1024, 'KB')

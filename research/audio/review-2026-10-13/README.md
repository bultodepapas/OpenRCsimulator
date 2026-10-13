# Audio review probes (2026-10-13)

Evidence scripts for the [audio realism plan](../../../docs/plans/audio-realism.md). Run from the repository root.

- `wavscan.py <wav...>`: duration, level, DC, dominant frequency, centroid and envelope variation.
- `seam.py <wav...>`: loop-seam click score (second difference at the tiled seam versus the rest of the file).
- `clamp_probe/`: standalone Godot 4.7.2 project. One 1 kHz `AudioStreamPlayer3D` (unit_size 8, max_db 0, filter off) steps through distance/volume cases. Capture the real mixer output on a headless Linux host with Movie Maker:

```sh
G="$(app/get-godot.sh)"; P=research/audio/review-2026-10-13/clamp_probe; OUT=$(mktemp -d)
xvfb-run -a "$G" --path "$P" --import
xvfb-run -a "$G" --path "$P" --rendering-driver opengl3 --write-movie "$OUT/out.png" --fixed-fps 60
python3 research/audio/review-2026-10-13/measure_clamp.py "$OUT/out.wav"
```

Movie Maker writes `out.wav` (48 kHz, stereo, 32-bit) beside the PNG frames. Measured levels carry a constant -3.0 dB centre-pan offset.

- `loop_probe/`: standalone project that plays `motor_combustion.wav` as a forward loop without and with the AUD-07a guard tail (F14). Capture it like the clamp probe, then run `python3 research/audio/review-2026-10-13/measure_loop.py "$OUT/out.wav"` from the repository root.
- `limiter_probe/`: a −20 dBFS tone with a 40 ms burst at 2.0 s through a bus limiter (F15). Run with `FX=hard REL=0.12 BURST_DB=12` (or `FX=hardslow REL=<s>`, `FX=limiter`, `FX=compressor`) in the environment, capture like the clamp probe, then `python3 research/audio/review-2026-10-13/measure_limiter.py "$OUT/out.wav"`. Measured 2026-10-13 on Godot 4.7.2 with a +12 dB burst: `AudioEffectHardLimiter` stays −3.19 / −1.31 / −0.50 / −0.25 / −0.14 / −0.07 dB low for 18 s at release 0.05 / 0.12 / 0.3 / 0.6 / 1.0 / 2.0 s; `AudioEffectLimiter` returns to 0.00 dB and holds the −1.00 dBFS ceiling.

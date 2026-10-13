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

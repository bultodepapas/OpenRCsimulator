# Soundscape tools

2026-10-11 · **Status: implemented.** Scope and results: [AUDIO-PLAN](../../docs/AUDIO-PLAN.md), [AUD-04](../../docs/research/audio/AUD-04/README.md). Godot is pinned to the repository's 4.7.2 binary; Python generator/checker dependency is `numpy==2.4.6`.

Run from the repository root. Replace `godot` below with the pinned binary. Windows native output uses WASAPI. Do not use `--headless` when qualifying the native driver: that selects Dummy; use `--display-driver headless --audio-driver WASAPI` for audio without graphics.

```sh
python -m pip install -r tools/audio/requirements.txt
python tools/audio/generate.py --check
godot --headless --editor --path app --import
godot --headless --path app --script res://tests/test_soundscape.gd
godot --headless --path app --script /absolute/repo/tools/audio/check_parity.gd -- --soundscape=off --audio-seed=4102026 --report=/absolute/output/parity.json
godot --headless --path app --script /absolute/repo/tools/audio/check_parity.gd -- --soundscape=off --audio-seed=4102026 --electric-demo=4s --report=/absolute/output/parity-electric.json
godot --path app --audio-driver WASAPI --script /absolute/repo/tools/audio/gameplay_probe.gd -- --fps=60 --duration=35 --audio-seed=4102026 --out=/absolute/output/review
python tools/audio/check_captures.py /absolute/output/review --out=/absolute/output/checks.json
```

The probe flies the actual physics scene with keyboard-rate throttle commands, then pauses, resumes, switches camera and restarts. Standard aircraft, weather, time-of-day and scenery arguments pass through. It captures stereo mix output after the limiter, event timestamps, source/listener distances, dropped frames and adapter timing; rendered runs also save a PNG. Use `--fps=30/60/144` in separate runs. These requested frame caps are not measured render-frame guarantees.

`profile_native.py --help` describes the Windows thread-CPU probe. Named thread CPU deltas are average work, not a per-buffer deadline or hardware latency measurement. A missing thread name or zero/unavailable counter must remain unqualified. Avoid simultaneous native audio probes and isolate preferences for parallel full suites (`XDG_DATA_HOME` on Linux).

Export verification uses `godot --headless --editor --path app --export-pack Windows /absolute/output/audio.pck`, then runs `check_pack.gd` with that PCK as the sole user argument from an empty project. It checks all 14 imported WAVs, PCM format and sample count, manifest and MIT notice. This is resource-pack qualification, not a full installer/release smoke test.

Live gameplay defaults to audio on. Use `--soundscape=off` for silence, `--soundscape=legacy` for the retained G3b engine, and `--audio-seed=<integer>` for a reproducible ambience sequence. The new runtime requires no external audio middleware. Source WAVs, import settings, provenance and license are under `app/assets/audio/soundscape/`.

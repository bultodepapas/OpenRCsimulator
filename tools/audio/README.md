# Soundscape tools

2026-10-11 · **Status: implemented.** Scope and results: [AUDIO-PLAN](../../docs/AUDIO-PLAN.md), [AUD-04](../../docs/research/audio/AUD-04/README.md), [AUD-05 wildlife](../../docs/research/audio/AUD-05/README.md). Godot is pinned to the repository's 4.7.2 binary; Python generator/checker dependency is `numpy==2.4.6`.

Run from the repository root. Replace `godot` below with the pinned binary. Windows native output uses WASAPI. Bare `--headless` selects Dummy; explicitly request a native driver and verify the report's actual driver. The capture matrix uses `--display-driver headless --audio-driver WASAPI` for audio without graphics; the Windows profiler uses `--headless` followed by the explicit WASAPI override.

```sh
python -m pip install -r tools/audio/requirements.txt
python tools/audio/generate.py --check
python tools/audio/generate_wildlife.py --check
godot --headless --editor --path app --import
godot --headless --path app --script res://tests/test_soundscape.gd
godot --headless --path app --script res://tests/test_wildlife.gd
godot --headless --path app --script /absolute/repo/tools/audio/check_environment.gd -- --scenery=on --weather=gusty --time-of-day=23:00
godot --headless --path app --script /absolute/repo/tools/audio/check_parity.gd -- --soundscape=off --audio-seed=4102026 --report=/absolute/output/parity.json
godot --headless --path app --script /absolute/repo/tools/audio/check_parity.gd -- --soundscape=off --audio-seed=4102026 --electric-demo=4s --report=/absolute/output/parity-electric.json
godot --path app --audio-driver WASAPI --script /absolute/repo/tools/audio/gameplay_probe.gd -- --fps=60 --duration=35 --audio-seed=4102026 --out=/absolute/output/review
python tools/audio/check_captures.py /absolute/output/review --out=/absolute/output/checks.json
```

The probe flies the actual physics scene with keyboard-rate throttle commands, then pauses, resumes, switches camera and restarts. Standard aircraft, weather, time-of-day and scenery arguments pass through. It captures stereo mix output after the limiter, event timestamps, source/listener distances, dropped frames and adapter timing; rendered runs also save a PNG. Use `--fps=30/60/144` in separate runs. These requested frame caps are not measured render-frame guarantees.

`make_bus_layout.gd` generates `app/default_bus_layout.tres` (AUD-12): Master ends in one `AudioEffectHardLimiter`, ceiling −1 dBFS, release 2 s, after every per-scene bus. Edit its constants and regenerate (`godot --headless --path app --script /absolute/repo/tools/audio/make_bus_layout.gd`); `-- --check` fails on a stale or hand-edited layout and runs in `app/test.sh`.

`fleet_loudness.py <prefix>...` tabulates full-power and idle K level at 100 m per aircraft from source-level sweeps (`--engine-only --audio-delay=off --audio-absorption=off`), relative to the Stik, and marks stages with a crash or pause as invalid.

The Movie Maker bench (`bench.sh`, usage in its header) adds a `crash` scenario (full-power dive into the ground) and `--view=chase` for a listener near the aircraft. `bench_analyze.py` reports a 4× oversampled true peak (dBTP) and the count of full-scale samples, since the integer capture clips above 0 dBFS.

`check_parity.gd` pairs every fixed-wing catalog aircraft through `main.tscn` with audio off and on, and requires identical full checkpoints each tick. Its input tape drives the four primary controls and keeps any extra channels (gear, flaps, smoke) at their accepted start values. Each pair is judged by its own checks. Rotorcraft use another route and are listed under `skipped` in the report, not silently passed.

`check_environment.gd` inspects live wind/sun values and suppression of the old scenery bed. Repeat with `--scenery=on --soundscape=off`, then with `--soundscape=legacy`, to check routing compatibility.

`profile_native.py --help` describes the Windows thread-CPU probe. Named thread CPU deltas are average work, not a per-buffer deadline or hardware latency measurement. A missing thread name or zero/unavailable counter must remain unqualified. Avoid simultaneous native audio probes and isolate preferences for parallel full suites (`XDG_DATA_HOME` on Linux).

For longer wildlife listening, add `--wildlife-review --duration=130`; this holds neutral controls in the real trimmed flight and keeps the pilot camera. Add `--time-of-day=23:00` for owls/crickets. The optional harness-only `--resume-focus` explicitly resumes focus-loss pauses only when no fault, crash or session hold exists; it never changes production focus behavior. Reports record these resumes and final physics tick/paused state. The checker rejects a wildlife review that did not sustain the flight. No species is forced for a listening review.

Export verification uses `godot --headless --editor --path app --export-pack Windows /absolute/output/audio.pck`, then runs `check_pack.gd` with that PCK as the sole user argument from an empty project. It checks all 33 imported WAVs, PCM format and sample count, three manifests and MIT/CC0 notices. This is resource-pack qualification, not a full installer/release smoke test.

AUD-14 adds real wind/fabric recordings. Source downloads and hashes are in `research/audio/AUD-14/recordings/environment/`; exact pinned editing dependencies are separate from the synthetic generators. The importer decodes the retained MP3 previews, trims, crossfades, filters and normalizes them into long mono PCM loops. Versioned `.wav.import` files keep `compress/mode=0`; Godot's QOA default cannot use the PCM wrap guard. Reproduction and focused checks:

```sh
python -m pip install -r tools/audio/requirements-recordings.txt
python tools/audio/import_wind_recordings.py --check
godot --headless --path app --script res://tests/test_recorded_audio.gd
godot --display-driver headless --audio-driver WASAPI --path app --script /absolute/repo/tools/audio/wind_probe.gd -- --fps=60 --out=/absolute/output/wind
```

`wind_probe.gd` is a staged presentation bench for calm, light/strong wind, gusts and reversal, pause/resume, and listener distance. It captures Master plus an isolated fabric bus, reports the actual audio driver, source identities, peaks, capture-buffer discards, measured wall update rate and update times, and checks native pause/bus cleanup. Settled measurements exclude the first 0.5 s per stage; digital silence reports a finite -240 dBFS floor. Compare captured duration with wall time as well as the discard counter. It does not qualify acoustic realism or replace a flight test. See [AUD-14](../../docs/research/audio/AUD-14/README.md) for results and limitations.

Live gameplay defaults to audio on. Use `--soundscape=off` for silence, `--soundscape=legacy` for the retained G3b engine, `--audio-seed=<integer>` for a reproducible ambience sequence, `--audio-delay=off` to hear the aircraft without propagation delay, and `--audio-absorption=off` to remove air absorption for source-level calibration ([AUD-11](../../docs/research/audio/AUD-11/README.md)). The new runtime requires no external audio middleware. Source WAVs, import settings, provenance and license are under `app/assets/audio/soundscape/`.

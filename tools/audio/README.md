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

`check_parity.gd` pairs every fixed-wing catalog aircraft through `main.tscn` with audio off and on, and requires identical full checkpoints each tick. It updates the full production adapter, including engine and ground contacts. Its input tape drives the four primary controls and keeps any extra channels (gear, flaps, smoke) at their accepted start values. Each pair is judged by its own checks. Rotorcraft use another route and are listed under `skipped` in the report, not silently passed.

`check_environment.gd` inspects live wind/sun values and suppression of the old scenery bed. Repeat with `--scenery=on --soundscape=off`, then with `--soundscape=legacy`, to check routing compatibility.

`profile_native.py --help` describes the Windows thread-CPU probe. Named thread CPU deltas are average work, not a per-buffer deadline or hardware latency measurement. A missing thread name or zero/unavailable counter must remain unqualified. Avoid simultaneous native audio probes and isolate preferences for parallel full suites (`XDG_DATA_HOME` on Linux).

For longer wildlife listening, add `--wildlife-review --duration=130`; this holds neutral controls in the real trimmed flight and keeps the pilot camera. Add `--time-of-day=23:00` for owls/crickets. The optional harness-only `--resume-focus` explicitly resumes focus-loss pauses only when no fault, crash or session hold exists; it never changes production focus behavior. Reports record these resumes and final physics tick/paused state. The checker rejects a wildlife review that did not sustain the flight. No species is forced for a listening review.

Export verification uses `godot --headless --editor --path app --export-pack Windows /absolute/output/audio.pck`, then runs `check_pack.gd` with that PCK as the sole user argument from an empty project. It checks 33 original/ambience WAVs plus six powertrain loops and four landing-gear clips, PCM format and sample count, manifests, bank definitions and MIT/CC0 notices. This is resource-pack qualification, not a full installer/release smoke test.

AUD-14 adds real wind/fabric recordings. Source downloads and hashes are in `research/audio/AUD-14/recordings/environment/`; exact pinned editing dependencies are separate from the synthetic generators. The importer decodes the retained MP3 previews, trims, crossfades, filters and normalizes them into long mono PCM loops. Versioned `.wav.import` files keep `compress/mode=0`; Godot's QOA default cannot use the PCM wrap guard. Reproduction and focused checks:

```sh
python -m pip install -r tools/audio/requirements-recordings.txt
python tools/audio/import_wind_recordings.py --check
godot --headless --path app --script res://tests/test_recorded_audio.gd
godot --display-driver headless --audio-driver WASAPI --path app --script /absolute/repo/tools/audio/wind_probe.gd -- --fps=60 --out=/absolute/output/wind
```

`wind_probe.gd` is a staged presentation bench for calm, light/strong wind, gusts and reversal, pause/resume, and listener distance. It captures Master plus an isolated fabric bus, reports the actual audio driver, source identities, peaks, capture-buffer discards, measured wall update rate and update times, and checks native pause/bus cleanup. Settled measurements exclude the first 0.5 s per stage; digital silence reports a finite -240 dBFS floor. Compare captured duration with wall time as well as the discard counter. It does not qualify acoustic realism or replace a flight test. See [AUD-14](../../docs/research/audio/AUD-14/README.md) for results and limitations.

Live gameplay defaults to audio on. Use `--soundscape=off` for silence, `--soundscape=legacy` for the retained G3b engine, `--audio-seed=<integer>` for a reproducible ambience sequence, `--audio-delay=off` to hear the aircraft without propagation delay, and `--audio-absorption=off` to remove air absorption for source-level calibration ([AUD-11](../../docs/research/audio/AUD-11/README.md)). The new runtime requires no external audio middleware. Source WAVs, import settings, provenance and license are under `app/assets/audio/soundscape/`.

AUD-15 adds installed powertrain banks and landing-gear contacts. The current behavior and source-fit limits are in [AUDIO-PLAN](../../docs/AUDIO-PLAN.md), with [engine provenance](../../docs/research/audio/AUD-15/sources.md), [ground provenance](../../docs/research/audio/AUD-15/landing-gear.md) and [validation](../../docs/research/audio/AUD-15/validation.md). Both importers reproduce from retained licensed previews without network access:

```sh
python tools/audio/recorded_powertrains.py --check
python tools/audio/import_landing_gear.py --check
godot --headless --path app --script res://tests/test_powertrain_audio.gd
godot --headless --path app --script res://tests/test_ground_audio.gd
godot --display-driver headless --audio-driver WASAPI --max-fps 60 --path app --script res://tests/test_glow_audio_pump.gd
```

The glow-pump test deliberately blocks the main thread for 600 ms, then checks native PCM duration, source skips and pause/restart lifecycle. Its worker owns the procedural voice and a 50 ms queue. Dummy-driver checks cover lifecycle only; they do not qualify continuous native output. Run the native test separately from other Godot workloads.

`pump_stress_probe.gd` extends that check to 125 seconds with five near/far phases, levels down to −92 dB, and a 600 ms busy GDScript stall in each phase. It checks native driver identity, worker state, source skips, capture drops, and PCM duration within 120 ms of wall time. Its detached constant-RPM source isolates audio scheduling; it does not qualify a loaded flight scene or acoustic fidelity.

```sh
godot --display-driver headless --audio-driver WASAPI --max-fps 60 --path app --script /absolute/repo/tools/audio/pump_stress_probe.gd -- --out=/absolute/output/pump-stress.json
```

The worker uses the documented [AudioServer lock](https://docs.godotengine.org/en/4.7/classes/class_audioserver.html#class-audioserver-method-lock) for playback ring access. In the pinned engine, the [WASAPI mixer](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/wasapi/audio_driver_wasapi.cpp) holds that lock during mixing, while the [generator playback](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/effects/audio_stream_generator.cpp) has ordinary ring indices. Do not move synthesis inside the lock or access a live playback from the worker without it.

`fleet_sequence.gd -- --list` lists the supported fleet. Its capture report distinguishes accepted live physics from explicit approach resets and harness engine-latch stimuli. Stage names alone do not establish successful takeoff, landing or a continuous full flight; consult the recorded outcomes.

```sh
python tools/audio/check_fleet_sequence.py --out-dir tmp/audio-aud15/fleet
python tools/audio/check_fleet_sequence.py --out-dir tmp/audio-aud15/fleet --analyze-only
godot --display-driver headless --audio-driver WASAPI --max-fps 60 --path app --script /absolute/repo/tools/audio/contact_mix_probe.gd -- --out=/absolute/output/mix.json
```

Run native captures sequentially on a quiet host. The fleet wrapper accepts repeated `--aircraft=<catalog ID>` arguments for targeted reruns. Phase boundaries use accepted simulation ticks; PCM and event timestamps use elapsed wall time. Session epochs preserve the tick history across explicitly marked fixture resets. Compare sample duration, capture discards, accepted simulation ticks and observed contact events. `--wall-timeout=360 --timeout=420` bounds stalled sessions and the containing Godot process.

For a continuous fixed-wing lifecycle, use `--continuous-straight`. It reuses the research FT-card-v5 pilot laws for runway takeoff, climb, a straight approach, touchdown on terrain ahead, and rollout. It does not return to the departure runway. `--continuous-helicopter` uses the existing HELI-20 X-Cell spool/hover/land/coast/disarm law. Neither mode resets the session after capture begins. A completed phase schedule alone is insufficient: contact, route health, source identity, native PCM timing and signal gates remain separate.

```sh
python tools/audio/check_fleet_sequence.py --aircraft=turbo-lumber-evolution --continuous-straight --post-landing-soak=130 --out-dir tmp/audio-aud15/turbo-continuous
python tools/audio/check_fleet_sequence.py --aircraft=xcell-60-research --continuous-helicopter --out-dir tmp/audio-aud15/heli-continuous
```

The optional `--post-landing-soak` adds accepted simulation time after a settled rollout to test a longer session. The older `--continuous` option retains the experimental Stik circuit pilot; its current failed-route evidence does not qualify a full flight. Live capture stores whole PCM buffers and frame counters; concatenation, finite-sample checks and waveform measurements run after the capture interval. Reports retain the capture-clock lag series and glow worker status. Fixed-wing identity records both input and semantic data hashes; rotorcraft uses its existing exact-input, model-law, lifecycle-law, weather and pad contract.

`contact_mix_probe.gd` separately measures engine, ground and their sum at an 8 m listening distance. It stages off/idle/full-power rolling, 2 m/s taxiing, stationary contact, touchdown, airborne release and pause/resume for the six installed engine families. The helicopter uses skid impacts without wheel roll. For the closest-distance headroom check, append `--distance=3 --exhaust-angle=30 --full-rpm-ratio=1 --full-load=1`; the default full-power fixture uses 91% rated RPM and 88% load. Reports include the actual driver, capture durations/discards, pre-master peak and glow-generator underruns. These detached snapshots qualify presentation behavior only; source fidelity and successful live flights require separate evidence.

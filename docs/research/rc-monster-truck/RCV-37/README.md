# RCV-37 — MONSTER CAR 2 CPU optimization

2026-10-15. The visual adapter prepares track metadata, mesh bindings, engine-pivot inverse and per-instance interpolation scratch during `build()`. It retains the original interpolation order and float32 accumulation. The Nitro voice computes eligibility, fuel-flow fraction and clutch level once per audio block. Sample-wise smoothing, oscillators, noise and fades are unchanged. No geometry, textures, particle budgets, physics equations, source checks or simulation frequency were reduced.

## Measurements

Godot 4.7.2 official debug source runtime, Windows, Ryzen 9 5900X and RTX 3090. Component comparisons alternate baseline/candidate execution order after warmup. Native activity measurements use Compatibility at 1280×720, the production airfield, four accepted 240 Hz ticks per rendered frame and a fixed 0.5 throttle tape. Audio is measured separately to avoid device-buffer timing bias. Each native run contains 30 warmup and 240 measured frames. Startup, GPU work, frame scheduling and audio-device latency are outside these CPU measurements.

| Work measured | Baseline | Candidate | CPU time reduction |
| --- | ---: | ---: | ---: |
| Animation `draw()`, median of three paired rounds | 1.705 ms | 1.289 ms | 24.4% |
| Sound synthesis, 98,304 stereo frames; median of seven paired rounds | 386.281 ms | 323.520 ms | 16.2% |
| Activity presentation callback, median of three run means | 3.720 ms | 2.951 ms | 20.7% |
| Activity presentation callback, median of three run p95 values | 5.301 ms | 3.568 ms | 32.7% |

The native runs were sequential: three baselines followed by three candidates. A later baseline confirmation measured 3.556 ms mean presentation cost, consistent with an improvement but also showing machine/run variability. Other desktop processes were left running. These results are CPU-work measurements, not FPS or target-hardware guarantees. The [machine-readable summary](summary.json) pins all reports, logs and images; [visual](checks/visual.json) and [audio](checks/audio.json) reports retain paired comparison details.

## Preserved behavior

- All 173 visual poses match the retained baseline byte-for-byte for every mesh transform and visibility, root transform, out-of-art flag and input-state preservation. Cases cover each corner, all bump/droop boundary combinations, steering limits, out-of-art clamping, independent wheel/crank phases and 128 seeded interiors. The 8.60002 gear ratio exercises clutch-bell motion. Timing uses 18 representative poses.
- All 222,882 audio frames in 220 blocks match byte-for-byte, along with 22 internal state fields after every block. Cases include engine start/stop, empty fuel, pause/resume, disabled sound, both clutch-slip signs, contacting tire skid, RPM transients and bounded block sizes.
- Every native run accepts 1,080 ticks with the same trajectory digest and backend identity. All retain 1,086 3D draw calls, 944,460 primitives, 70 grime overlays, 96 dust particles, 32 exhaust particles and four active dust wheels. Physics and solver identity are unchanged (`solver_changed=false`).
- The independent [session profile](checks/session.json) completes 60 warmup plus 960 mixed throttle/steering/braking ticks. Accepted control tape, every replayed state, final state and JSON checkpoint restore match exactly; identity probing agrees with the checkpoint.
- [Scoped regressions](checks/verification.json) pass: Nitro audio 23, authored visual checks, Nitro activity 99, grime/exhaust effects 376, engine/fuel service 38 and Bisonte activity 24. `git diff --check` is clean. The full repository suite and a new release export were not run.

The [baseline vehicle capture](baseline-confirmation/activity.png) and [candidate capture](candidate-3/activity.png) were visually inspected. Later native captures omit HUD and track text with both the original and optimized adapters, so these captures qualify the 3D vehicle/effects only; they do not establish text-rendering correctness. HUD state and service routing remain covered by the activity regressions. The earlier [baseline capture](baseline-1/activity.png) includes the HUD. This presentation issue is independent of the adapter change and remains unqualified in this performance pass.

## Remaining performance limit

The final mixed-driving profile costs 5.818 ms mean and 7.994 ms p95 per physics callback, exceeding the 4.167 ms interval at 240 Hz on this source-runtime run. Identity generation alone costs about 1.225 ms mean. Full source/artifact verification remains active on every tick. A [read-path experiment](checks/identity.json) preserved hashes but saved only about 7–8% of file-hashing cost; it was not integrated. Further simulation work needs separate profiling and exact replay gates. No physical calibration is claimed here.

## Reproduction

The [vehicle guide](../../../../research/rc-monster-truck/monster-car-2/README.md) owns operation. Comparison sources and harnesses are in [`research/rc-monster-truck/monster-car-2/rcv37/`](../../../../research/rc-monster-truck/monster-car-2/rcv37/). `baseline_model.gd` and `baseline_voice.gd` are pinned pre-optimization oracles, used only by these source-runtime harnesses.

From the repository root, run `bench_visual.gd`, `bench_audio.gd` and `bench_session.gd` sequentially with:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script ../research/rc-monster-truck/monster-car-2/rcv37/bench_visual.gd -- --output=C:/path/to/visual.json
```

Replace the script/output name for each component. Run `bench_activity.gd` without `--headless`, using `--output=<existing absolute directory>`; append `--baseline` for the original adapter. Do not run benchmarks concurrently. Each native run saves `activity.json`, `activity.png` and requires a fresh process. The harness disables live driving input and resumes background focus holds solely for this fixed tape.

```powershell
python research/rc-monster-truck/monster-car-2/rcv37/verify_update.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe
python research/rc-monster-truck/monster-car-2/rcv37/summarize.py
```

The verifier runs the scoped regressions. `--reuse-passing-logs` instead checks their pinned sources/logs when only evidence metadata changed. The summarizer validates the retained native/component reports and rebuilds `summary.json`; it does not run benchmarks. The existing audio regression also rewrites its deterministic RCV-36 WAV preview; exact PCM preservation keeps those bytes unchanged.

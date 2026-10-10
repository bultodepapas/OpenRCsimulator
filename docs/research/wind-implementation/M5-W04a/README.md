# M5-W04a: seeded temporal turbulence

2026-10-09 · **Status: implemented; software verification below. Physical/pilot and target performance gates remain open.**

Home → Weather → Turbulence now controls independent NED RMS values, correlation time and a uint32 seed. The appended Turbulence practice preset uses 3 m/s from west, RMS `[0.6, 0.6, 0.4]` m/s, tau 2 s and seed 20261009. These are authored practice settings. Wind/gust presets and legacy preferences remain readable; untouched values retain source precision. The UI supports English/Spanish, draft Apply/Cancel, keyboard focus and exact integer seed entry.

## Physics and state

The [float64 kernel](kernel.md) starts in its stationary distribution, then advances exact-discrete OU once per 240 Hz tick. Raw PCG32 words produce open 53-bit uniforms and Box–Muller normals. Simulation time controls correlation even at zero airspeed. The wind window linearly interpolates between tick endpoints for RK4; render/HUD/trace queries consume no RNG words.

The seven-value interval follows engine/servo, gear-anchor and downwash auxiliary state. Its signed int64 RNG state follows the engine mode. Existing H8 rollback/checkpoint machinery owns both. Air-relative aerodynamics, shaft inflow, downwash and transported wake use the same stage wind; wheel forces remain ground-relative. Airborne reset adds the stationary initial wind to trimmed ground velocity. Runway solving uses the same initial wind. An existing tick-zero weather change pauses and requires reset before advancing or creating a checkpoint.

Exact weather continuation uses flight checkpoint v2; untrusted model/config/layout/clock/anchor/window inputs fail before altering the destination. A fresh calm destination can adopt a same-model turbulence checkpoint. All-zero RMS consumes no draws and preserves calm state/checkpoint bytes. Golden v1 now explicitly refuses non-calm recording/replay because it lacks weather identity and lossless RNG encoding.

## Verification

- [Kernel test](../../../../app/tests/test_wind_turbulence.gd): **29 checks**, including known answers, raw signed-state continuation, zero innovation, validation and three 20,000-step streams. The [measured statistics](statistics.json) use `dt=0.02`, `tau=0.5`, sigma 1; RMS, mean, AC1 and cross-axis covariance bands are documented in [kernel.md](kernel.md). RMS is measured without subtracting a fitted mean; AC1/covariance use declared sample centering.
- [Flight regression](../../../../app/tests/test_turbulence_flight.gd): **157 checks**, including all four aircraft, byte-exact reset/replay/body/aux/RNG/wake, disabled/calm parity, failed-step rollback, pause, interval midpoint, malformed checkpoint/trace refusals and a closed-form force integral through the real RK4 path.
- [UI regression](../../../../app/tests/test_ui_turbulence.gd): legacy preservation, v2 preferences, integer seed bounds, untouched precision, tabs/focus, future-file refusal and Home→Fly handoff; [rendered evidence](ui.md).
- [Independent trace oracle](../../../../app/tests/check_wind_trace.py) supports v4/v5. V5 adds six state/k1 turbulence columns, exact first-interval metadata and raw RNG as a signed string. The Python implementation reconstructs PCG initialization/recurrence, Box–Muller and OU independently of GDScript, then checks combined wind, clocks and airspeeds. [CLI regressions](../../../../app/tests/test_turbulence_cli.py) exercise nondefault tau/seed, restart, midflight recording, corrupted records and real-app FPS independence.

The real app with injected keyboard inputs reached the same complete flight SHA-256 at 30/60/144 FPS: `2b924c3462106172f4669b6fb1fd5b56c9c204bbaa7a4bdcbf1abbfeb86af36b` (480 ticks). This covers body, sampled state, continuous wake, RNG, inputs, loads and clock, rather than only visible airplane position.

`app/test.sh` completed successfully: 135 GDScript test programs, global import/parse/float64 guards, legacy goldens, geometry contracts, flown handling/ground checks, CLI negative controls and frame-rate checks. Final preference/schema tests and weather trace/CLI tests passed again after the final serialization guards; the extended turbulence CLI suite has **10 passing tests**, and the flight regression **157 passing checks**. Some existing UI/input tests emit an audio-playback ObjectDB shutdown warning, reproduced on the frozen baseline; no engine/script errors are accepted by the suite.

Three desktop exports pass `app/export.sh`: Linux trimmed flight, pack/data probes, Windows version metadata and macOS universal/ad-hoc signing checks. The [native comparison](native-flight.json) checks all four aircraft with 721 samples each; exported Linux/source numeric rows are byte-identical and satisfy the independent OU/velocity oracle. Windows/macOS execution still needs those operating systems. Reproduce with [native_compare.py](native_compare.py) after exporting.

A large-clock regression starts recording at tick 100,000,000 using a valid shifted checkpoint, without simulating days of flight. Default float-to-string formatting truncated the timestep and rejected this valid trace. V4/v5 now serialize `dt_s` with full precision; calm v3 remains unchanged. The independent reader accepts the extended nine-row fixture.

## Reproduction

```sh
"$(app/get-godot.sh)" --path app -- --weather=turbulent
"$(app/get-godot.sh)" --headless --path app -- --weather=turbulent --trace=/tmp/ou.csv --t=3
python3 app/tests/check_wind_trace.py /tmp/ou.csv --duration=3
app/test.sh
```

A complete `openrc-weather v2` JSON file supports custom conditions via `--weather-file=path.json`. V1 keys remain required; additional keys are `turbulence_rms_mps`, `turbulence_tau_s`, `turbulence_seed`. Bounds are in [WIND-PLAN](../../../WIND-PLAN.md#m5-w04a-turbulence-contract).

## Cost method and limitations

The same [benchmark harness](../../../../app/tests/bench_wind.gd) runs a frozen `fca70b2` source tree and this change with steady wind, then this change with turbulence. It preserves complete auxiliary/mode/wake fixtures and restores them before each batch, including RNG. This corrects the earlier harness's four-value auxiliary fixture, which omitted anchors/downwash; do not compare old fixture timings directly. Steady-air trim trajectories and complete snapshot hashes match the frozen source at ticks 0/240/480 for every aircraft.

Raw reports: [baseline steady](cost-baseline.json), [current steady](cost-steady.json), [current turbulence](cost-turbulent.json). Each case has seven 240-tick batches with 240-tick warmup. Percentiles describe batch means, not individual ticks. Shared-host noise and differing turbulent trajectories preclude precise attribution or target-device acceptance. Reports contain exact snapshot hashes; numeric JSON diagnostics are not replay files.

Batch medians (µs/tick), observational rather than an acceptance result:

| Aircraft | Regime | Frozen steady | Current steady | Current turbulence |
| --- | --- | ---: | ---: | ---: |
| jensen-das-ugly-stik-60 | trim | 371.5 | 348.8 | 443.7 |
| jensen-das-ugly-stik-60 | stall | 358.1 | 365.8 | 442.1 |
| jensen-das-ugly-stik-60 | ground | 408.4 | 418.7 | 460.0 |
| gp-extra-300s-60 | trim | 251.7 | 263.6 | 314.6 |
| gp-extra-300s-60 | stall | 277.6 | 283.3 | 302.3 |
| gp-extra-300s-60 | ground | 341.9 | 340.1 | 368.4 |
| p51d-mustang-120 | trim | 516.7 | 532.3 | 539.9 |
| p51d-mustang-120 | stall | 537.7 | 529.4 | 574.9 |
| p51d-mustang-120 | ground | 341.3 | 338.2 | 396.4 |
| sebart-avanti-s-a200-p100rx | trim | 301.1 | 302.3 | 348.6 |
| sebart-avanti-s-a200-p100rx | stall | 308.9 | 296.4 | 364.7 |
| sebart-avanti-s-a200-p100rx | ground | 265.8 | 271.8 | 325.8 |

The P-51 remains above 500 µs in airborne cases, including the frozen baseline. These measurements leave Gate P open.

This is spatially uniform temporal practice turbulence, with independent axes and a common wall-time tau. It has no Dryden/MIL atmospheric calibration, spatial gradients, rotational gusts, terrain wakes or measured site validation. Interpolated interior RMS differs slightly from tick-boundary RMS. Gaussian excursions can exceed RMS controls; no explicit wind-speed cap is applied to samples. Sigma/tau/configuration bounds are validated. The pinned Godot RNG and platform math functions do not promise cross-version/platform bit identity. `wind_at` represents the current interval, not historical/future random weather. Pilot handling, physical statistics, Windows/macOS execution and the 500 µs target gate remain open.


## Preference compatibility and provenance

V2 weather is saved with outer settings schema 2; v1 retains schema 1. Current code reads both. The actual frozen schema-1 reader refuses to overwrite the new file even when its language is changed: [older-reader.json](older-reader.json) records `ERR_FILE_NO_PERMISSION` and equal before/after file hashes. [schema_probe.gd](schema_probe.gd) reproduces the writer/older-reader experiment against their respective app trees. This guard protects the turbulence fields rather than allowing an older validator to replace them with calm defaults.

[Source manifest](source-manifest.json) records the application and test inputs for this development change. Generated binaries/captures remain local artifacts; this step does not publish a release or close physical/pilot acceptance.

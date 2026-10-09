# M5-W01a wind baseline and core performance evidence

**Status (2026-10-09):** Frozen calm baseline and current core snapshot measured. The core snapshot preserves exact calm checkpoints on all four catalog aircraft; weather and cost measurements are engineering evidence, not Gate W-A or feature acceptance.

## Method

The baseline was measured in a disposable no-hardlinks clone at `/tmp/openrc-wind-baseline-6973e42`. Its tracked source was clean at the pinned revision. The only untracked file in that clone was the copied measurement harness [`app/tests/bench_wind.gd`](../../../app/tests/bench_wind.gd), which is also in this working tree.

Godot 4.7.2 official (`ed1daf0bf`), Linux x86_64, Intel Core i5-10500 at 3.10 GHz. The final harness SHA-256 is `cd4f6bd54983974fd9339888199109dd2a41eed467f36f61523784f252d0080a`. Every cost sample restores the same fixture, runs 240 untimed warmup ticks, restores again, then times 240 calls to the complete `session.sim.step()`. There are five batches per fixture. The median and nearest-rank p95 are calculated across those five **batch means**; with five samples, p95 is the maximum sample. These are not individual-tick percentiles.

The three fixture types are trimmed start, 15° air-relative alpha at the same initial airspeed, and a 2 m/s ground fixture with gear compression. Costs include the complete simulation step and its deterministic auxiliary updates. Calm fingerprint checkpoints capture packed body state, auxiliary state, continuous state, modes, inputs, and start-of-tick loads at ticks 0, 240, and 480. The report stores each numeric snapshot, its SHA-256, and the cumulative trajectory SHA-256 through that tick.

Exact command:

```sh
/home/bulto/OpenRCsimulator/.tools/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path /tmp/openrc-wind-baseline-6973e42/app \
  --script res://tests/bench_wind.gd -- \
  --revision=6973e42159eaf21574c17f44f64e536b2e0304eb \
  --weather=calm --output=/tmp/wind-baseline-6973e42.json
```

## Whole-tick cost

All measurements completed without a simulation fault. Values are median / p95 of the five batch means, in µs per 240 Hz tick.

| Aircraft | Trim | Stall | Ground |
| --- | ---: | ---: | ---: |
| Jensen Das Ugly Stik 60 | 242.30 / 249.53 | 268.34 / 319.29 | 284.46 / 298.54 |
| Great Planes Extra 300S .60 | 241.20 / 251.57 | 257.90 / 270.39 | 387.31 / 418.36 |
| P-51D Mustang 1/4 | 493.90 / 521.56 | 509.86 / 533.24 | 337.55 / 395.18 |
| SebArt Avanti S | 299.42 / 312.89 | 289.38 / 313.44 | 271.09 / 300.52 |

The largest baseline median is the P-51 stall fixture at 509.86 µs/tick. This host is not the owner's slowest-machine target, so the observation does not decide its budget gate.

## Calm trajectory fingerprints

The exact arrays and hashes for every aircraft are in [`baseline.json`](baseline.json). Each checkpoint contains 13 rigid-body values, 4 auxiliary values, no continuous values, 0 discrete modes, 4 inputs, and 6 loads. These are same-build fingerprints for exact regression comparison, not cross-platform bit-exact guarantees.

## Core snapshot weather measurements

To isolate the stable physics/session change from ongoing menu work, the core snapshot is a detached worktree at the same base commit with only the listed files overlaid. Its source SHA manifest is [`core-source-manifest.json`](core-source-manifest.json), snapshot identity `810075d0893bd231803341bd886856061b5098c467499fd287243a18fd6b77b8`. All four aircraft data files and the benchmark harness are byte-identical to the frozen baseline. The raw reports are [`core-calm.json`](core-calm.json), [`core-steady.json`](core-steady.json), and [`core-gusty.json`](core-gusty.json); [`core-comparison.txt`](core-comparison.txt) and [`compare_core.py`](compare_core.py) reproduce the comparison.

The same 5 × 240-tick batches and 240-tick per-sample warmup were used in trim, stall, and ground fixtures. The table gives median whole-tick cost in µs. Steady is 3 m/s from 270°; gusty is the same mean with a 3 m/s horizontal and 1.5 m/s upward half-cosine pulse, 4 s duration, 12 s period, and the benchmark-only delay override set to 0 s. The configured preset delay is 2 s; the override makes active gust work occur in the timed batches. The core harness also records 480-tick trim trajectories for each weather case.

| Aircraft | Fixture | Baseline calm | Core calm | Steady | Gusty, delay 0 | Steady Δ vs core calm | Gust Δ vs core calm |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ugly Stik | Trim | 242.30 | 284.36 | 269.90 | 271.43 | −5.1% | −4.5% |
| Ugly Stik | Stall | 268.34 | 273.32 | 268.67 | 269.98 | −1.7% | −1.2% |
| Ugly Stik | Ground | 284.46 | 282.44 | 323.10 | 328.35 | +14.4% | +16.3% |
| Extra 300S | Trim | 241.20 | 241.35 | 237.70 | 277.86 | −1.5% | +15.1% |
| Extra 300S | Stall | 257.90 | 261.03 | 260.07 | 272.23 | −0.4% | +4.3% |
| Extra 300S | Ground | 387.31 | 370.98 | 355.94 | 332.98 | −4.1% | −10.2% |
| P-51D | Trim | 493.90 | 484.66 | 492.34 | 491.35 | +1.6% | +1.4% |
| P-51D | Stall | 509.86 | 491.51 | 504.59 | 530.08 | +2.7% | +7.8% |
| P-51D | Ground | 337.55 | 357.50 | 342.62 | 345.80 | −4.2% | −3.3% |
| Avanti S | Trim | 299.42 | 265.39 | 274.88 | 293.51 | +3.6% | +10.6% |
| Avanti S | Stall | 289.38 | 278.65 | 308.37 | 305.21 | +10.7% | +9.5% |
| Avanti S | Ground | 271.09 | 261.29 | 249.42 | 270.10 | −4.5% | +3.4% |

The calm overlay reproduces every baseline numeric state, auxiliary state, continuous state, mode, input, load, snapshot hash, and trajectory hash at ticks 0, 240, and 480 on all four aircraft. Steady samples are `(0, 3, 0) m/s` NED. With the gust delay set to zero, gusty samples reach `(0, 6, −1.5) m/s` NED at 2 s; all steady and gust flights complete 480 ticks without a numerical fault, and their trajectories separate after the gust begins.

The largest observed core median is the P-51 stall fixture in gusty conditions at 530.08 µs/tick (core calm 491.51, steady 504.59). It is a performance point to watch, not a demonstrated wind bottleneck: scenario deltas have mixed signs, the baseline P-51 stall median was already 509.86 µs/tick, and a long-running UI test shared the host during these runs. No component profiler or owner-target hardware measurement was made. The likely extra work is repeated `WindField.sample()` calls during RK stages, including new packed-vector values and a cosine evaluation while a gust is active; profile this path before considering an optimization.

## Golden replay baseline

In the same frozen checkout, `tests/test_golden.gd` passed all four existing maneuvers: `roll_15` (600 ticks), `pull_throttle` (720), `rudder_doublet` (720), and `glide_15` (1200). Auxiliary and discrete checkpoints matched. Maximum reported position error was `3.55e-15 m`, velocity error `1.78e-15 m/s`, attitude component error `5.55e-17`, and rate error `2.22e-16 rad/s`.

The full frozen-clone `bash app/test.sh` run also completed with exit code 0. It parsed every app script, replayed the goldens, ran all app checks and model contracts, checked the four real-app trimmed traces, and completed the input, frame-rate, and ground-contact regressions. The raw console output is preserved in [`app-test.log`](app-test.log).

## Limits

These numbers are observational and machine-specific. The benchmark ran in a shared development environment; no OS-level load trace was captured, so timing changes cannot be attributed to wind alone. Compare the identical harness, fixtures, engine, and machine, retain the raw samples, and interpret timing beside the calm trajectory hashes. The tested field is uniform and deterministic; no spatial gradients, turbulence, or independent aerodynamic/pilot validation are included here. Gates W-A and W-B remain open.

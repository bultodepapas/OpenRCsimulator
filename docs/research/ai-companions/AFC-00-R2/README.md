# AFC-00 R2 — Windows rendered population baseline

Measured 2026-10-20 local time (2026-10-21 UTC). The user selected this Windows
machine as the first target. Native Linux/macOS testing and independent RC pilot
review remain release gates. This is a baseline of the **original circuit pilot**,
SHA `1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c`,
before the reachable-turn controller promotion. It does not qualify that replacement.

## Result

| AI count | Frames | p50 ms | p95 ms | p99 ms | Simulation / wall time | Assessment |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 0 | 12,189 | 4.535 | 7.364 | 10.146 | 1.00009 | Active workload; render budget passes |
| 1 | 8,152 | 7.084 | 11.124 | 17.119 | 0.99994 | Active workload; render budget passes |
| 2 | 3,914 | 14.564 | 21.691 | 33.988 | 0.99975 | Active workload; render budget fails |
| 3 | 1,286 | 46.679 | 59.904 | 92.094 | 0.95817 | Clock and render budgets fail |

The proposed render gates are p95 ≤16.67 ms and p99 ≤25 ms. The reducer requires
simulation/wall time in [0.98, 1.02]; smooth frames from a stopped or slow simulation
cannot pass. Every player and companion remained active without a crash or fault at
the endpoint. Three companions nevertheless fell behind wall time. No higher count
or busy-skies preset is unlocked by this result. One passing case at count one is
not the complete model, regime, camera, endurance or callback-cost qualification.

## Workload and identity

Windows 11 Pro build 26100; Ryzen 9 5900X (12 cores / 24 threads); about 64 GiB RAM;
GeForce RTX 3090, NVIDIA 617.42. The Balanced power scheme was retained. Engine:
Godot `4.7.2.stable.official.ed1daf0bf`, Compatibility/OpenGL 3.3, 1280×720 window,
vsync disabled and no frame cap. Each count has 10 seconds of warmup followed by
60 measured wall seconds, with the production 240 Hz physics and normal rendering
and audio. No ORFL recorder or callback timer runs in this native matrix; the
existing frame sampler remains enabled.

The research fixture replaces only this process's player input adapter with
neutral controls at the accepted initial trim throttle. The player flies straight
away; companions fly their normal circuits. This is **not an all-visible workload**
or a radio/device qualification. The fixture requests focus once before launch;
later focus loss retains normal pause handling and invalidates the sample. It does
not change OS devices, preferences, physics frequency or focus-pause policy.

The four AFC workers held their simulator subprocesses during the sequential
native matrix. No Godot process was observed before launch. Ordinary OS background
activity was not disabled; other repository tracks were not globally controlled.

[verification.json](verification.json) retains hardware, endpoint summaries, hashes,
raw artifact locations and limitations. [frozen-source-manifest.json](frozen-source-manifest.json)
identifies 4,270 source, asset and imported-cache files from the frozen D: snapshot.
It was collected after the runs, not independently before every run. The imported
cache was copied, so this is not fresh-clone/import qualification. Small checked
runner reports/logs are retained in [checks](checks/). Each engine run exited zero
with no errors and one existing unsupported maple-material wind warning.

Large raw frame vectors and fixture/assessment JSON remain at
`D:/OpenRCsimulator-AFC-work/evidence/performance/windows-baseline-r3-20261020/`.
Their absolute paths, sizes and SHA-256 values are in the receipt. Preserve or
transfer those files with the receipt when reproducing this evidence elsewhere.

## Reproduce and reject invalid measurements

Use a fresh output directory and the frozen source identity in the receipt. For
each count 0–3, run the following through `tools/godot/run_checked.py`, requiring
`AFC native fixture complete; active endpoint=true` and `frame times:`. Replace
`<snapshot>`, `<output>` and `<count>` with explicit paths/counts:

```text
.tools/Godot_v4.7.2-stable_win64_console.exe --path <snapshot>/app --rendering-driver opengl3 --resolution 1280x720 --disable-vsync --max-fps 0 --script <snapshot>/research/ai-companions/native_performance_probe.gd -- --quick-flight --start=airborne --companions=<count> --companions-seed=20261020 --fixture-out=<output>/fixture.json --frametimes=<output>/frames.json --warmup=10 --t=60 --case=afc-neutral-trim-count-<count>
python research/ai-companions/native_performance_report.py --frames <output>/frames.json --fixture <output>/fixture.json --count <count> --out <output>/assessment.json
```

The current reducer checks complete Windows/backend/resolution metadata, warmup/sample
length, advancing common ticks, 240 Hz, expected population, active endpoints and
clock pacing before reporting a render pass. A follow-up also recomputes nearest-rank
percentiles from raw wall durations and cross-checks timestamps and sample endpoints.
Its ten unit cases cover frozen/slow/reset clocks, damaged/stopped/desynchronized
fleets, malformed/nonfinite input, insufficient warmup and forged timing summaries.
[Raw-sample reassessment](raw-sample-reassessment.json) preserves the original four
verdicts and exact percentile values. The original reducer is retained under
[sources](sources/native_performance_report.py); original assessments remain unchanged.

Earlier device-driven attempts crashed the player before sampling; the first
neutral-input smoke lost focus at tick 12 and paused. They are rejected, despite
plausible frame times. Their checked logs remain under the D: performance
`windows-baseline-20261020`, `windows-baseline-r2-20261020` and `fixture-checks`
directories. The repaired 12-second smoke is only a fixture check, not a budget pass.

## Separate callback diagnostic and remaining gates

A 2,400-tick headless diagnostic after 240 warmup ticks measured complete callback
p95 values of 1.487 / 2.968 / 4.483 / 5.957 ms at counts 0 / 1 / 2 / 3. It preserved
player fingerprints across counts. Short checks from other workers overlapped
that diagnostic; retain it as attribution evidence, not an isolated timing pass.
It also misses the proposed 2 ms p95 fleet budget at every enabled count. The
receipt identifies its raw report. Full aircraft solvers dominate the cost.

Next gates: measure the promoted controller, repeat isolated callback and rendered
runs, cover all-visible/offscreen/ground/mixed-aircraft regimes, retain CPU/GPU
attribution and long-duration pacing, and validate native packages on the other
platforms. Keep the existing experimental 1–3 menu range distinct from supported
performance claims. Source or physics changes require new qualification evidence.

# M5-W05d-R5 — active atmospheric workload admission

2026-10-26. Owner: M5-W. [Wind guide](../../../WIND-PLAN.md), [preceding stage optimization](../M5-W05d-R4/README.md), [benchmark commands and report contract](../../../tools/physics.md#spatial-wind-workload-verification-and-timing).

## Change and reason

The existing full-session benchmark covered steady mean wind and spatial turbulence, with no gust agenda or thermal cells. Simply selecting the existing presets would not exercise their important components: the first gust begins at 6 s, whereas each default batch restarts at zero and runs for 2 s; the thermal preset starts later and lies away from that trajectory. The provider-only benchmark's young thermal is a separate, weak early-lifecycle workload. Its historical workload remains unchanged.

`app/tests/bench_spatial_wind.gd` now offers explicit gust, thermal and combined cases, optional X8 selection, and `--battery` for accepted catalog pack data. The original default case/aircraft lists and all four original weather configurations remain unchanged. New cases require explicit filters. No production source, aircraft data, weather schema, preset, force, timestep or interactive default changes.

`--verify-only` executes the same full-session production workload without reading the batch timer or reporting timing arrays, ratios or budget fractions. It retains exact fixture reset checks, accepted-step counts, finite state/load checks and crash/fault refusal. Timing mode still measures production `Simulation.step`; statistics are batch means, not per-tick latency percentiles. Session report v2 distinguishes untimed workload counts from timed counts. Unknown flags, malformed integers, undersized full-session workloads and existing output paths are refused instead of silently changing the request or overwriting evidence.

After production batches, an equivalent counting provider repeats the full workload. Separate isolated component providers sample each actual stage/wash query without affecting its returned wind. Required gust/thermal components must reach at least 0.01 m/s somewhere in that trajectory; counts also identify samples above 1e-6 m/s. These are fixture-admission thresholds, not claims about atmospheric realism. Configuration/field identity and final state hashes must match production. The original provider and tick-zero fixture are restored on success or failure. X8's inactive horizontal-tail slot is excluded from the reported station-query count.

Actual solver, benchmark, preset factory and aircraft-file hashes accompany reports. Caller-supplied revision/manifest annotations are identified as annotations. The harness checks that solver and benchmark source identities remain stable during each full run. The independent read-only reviewer found no blocker; the suggested no-timing regression assertion was added to the focused test.

## Authored workloads

All new cases keep the previous benchmark's 3 m/s reference wind FROM 270 degrees, 24 finite turbulence modes, nominal 0.3 m/s turbulence input and seed/epoch identity. The nominal input is not measured local RMS.

| Explicit case | Added components and clock |
| --- | --- |
| `spatial-v5-gusts-24` | Complete 24-event subdued Realistic agenda, epoch offset 7 s; the first pulse runs during the default 0–2 s batch and peaks at 0.28 m/s. |
| `spatial-v5-thermals-24` | One 720 s cell, radius 60 m, top 200 m, peak parameter 1 m/s; epoch offset 360 s starts at mature half-life. Center at birth is [-72, 36] m and drift is [0.2, -0.1] m/s, placing its center at the origin at simulation time zero. |
| `spatial-v5-gusts-thermals-24` | Same mature cell and complete gust agenda; all gust starts shift by 353 s so the first pulse occupies the same relative flight window. |

These are explicitly authored benchmark configurations, not unmodified UI presets or inferred daytime meteorology. Full configuration values and field receipts are retained in the workload JSON. Aircraft start at their normal airborne fixture and follow open-loop neutral commands; the test does not move the field to follow the airplane.

## Verification

The [nine completed workloads](workloads/summary.json) each accept three 480-tick production batches, three 240-tick warmups and one separate 480-tick coverage replay: **23,760 accepted ticks total**, at 240 Hz. Each batch resets to the same fixture; this is repeated 2 s coverage, not a 99 s continuous flight. All nine fixture-reset checks per case pass and all repeated production final-state hashes agree. The instrumented final state also matches. Endpoint equality is not proof of arbitrary per-tick or physical equivalence.

| Aircraft / power | Case | First-tick wind queries | Full 480-tick coverage queries | Observed gust / thermal peak, m/s |
| --- | --- | ---: | ---: | ---: |
| Jensen / ideal | Legacy steady | 6 | 2,880 | 0 / 0 |
| Jensen / ideal | Spatial 24-mode control | 60 | 28,800 | 0 / 0 |
| Jensen / ideal | Gusts | 60 | 28,800 | 0.280 / 0 |
| Jensen / ideal | Thermals | 60 | 28,800 | 0 / 0.142196 |
| Jensen / ideal | Gusts + thermals | 60 | 28,800 | 0.280 / 0.142517 |
| Extra 300S / ideal | Gusts + thermals | 98 | 47,524 | 0.280 / 0.142829 |
| Turbo Lumber / ideal | Gusts + thermals | 60 | 28,800 | 0.280 / 0.142233 |
| X8 / ideal | Gusts + thermals | 36 | 17,280 | 0.280 / 0.143186 |
| X8 / pack | Gusts + thermals | 36 | 17,280 | 0.280 / 0.143184 |

Extra's total demonstrates why the initial tick's count is not a constant per-flight query demand. Reported peaks are sampled component **vector magnitudes** along these trajectories, not peak vertical lift, model-wide maxima or meteorological measurements.

`test_spatial_wind_benchmark.gd` passes **110 checks** in both the frozen snapshot and the final integrated tree. It covers the original four canonical configuration hashes, active/expired agendas, actual instrumentation wind bytes, detached configuration, probe failure, provider/fixture restoration after a manufactured state mismatch, X8 ideal/pack geometry, batch-statistic semantics and verification reports without timing claims. The CLI driver passes [eight contracts](cli-verification.json), including seven deliberate refusals and preservation of an existing output file. The seven negative checked-runner reports intentionally have nonzero exits; they are expected rejection evidence.

Draft receipts are retained. The first test parse used a nonexistent `WindField.from_config` method; it was corrected to the existing `build` API before integration. The initial focused test had 87 checks; the final version adds verification-report assertions. No runtime validation was weakened. The earlier combined Jensen draft run is not counted in the nine final workloads.

Concurrent work changed contact/session sources after the first shared-tree check. The final integrated test was repeated with [stable before](integrated-stable-before.json)/[after](integrated-stable-after.json) observations. [Comparison](integration-comparison.json) identifies the three unrelated sources that differ from the isolated workload snapshot, including a newly added ground-damage source. Those changes were preserved. No complete repository suite or current-tree nine-workload rerun is claimed.

## Reproduction and source identity

Pinned engine: `4.8.beta1.official.4d10419ca`, Windows. Base commit: `61e1dd9895f83b42a6427af26b22bddd4d156b08`.

| Identity | SHA-256 |
| --- | --- |
| Frozen solver, unchanged by R5 | `5a501c161343d39a3a7694b94030153d5f541677a0885455b0e5b754710b0612` |
| Final benchmark | `afc13da123d21f3d724bef525c04b96156d867972328fc95911a433bbff7d02e` |

[Reproduction manifest](reproduction-manifest.json) binds 1,569 source/config files. [Original snapshot manifest](original-source-manifest.json) is the caller annotation passed to the workload runner. Only the benchmark changes among those original files; the focused test is added. `source-overlays/` preserves both owned changes plus pre-existing working-tree/mixed-line-ending bytes needed to reconstruct the frozen snapshot. They are evidence, not instructions to overwrite the live shared tree.

Create a disposable checkout of the base commit, then run `restore_sources.py --repo <repository> --destination <checkout>` from this evidence directory. It restores and verifies all recorded source hashes and the solver identity. A source-only reconstruction was also verified; neither that check nor the evidence-only Git checkout checks qualify a complete application clone. Import the reconstructed app with the pinned engine before tests.

The retained `verify_workloads.py`, `verify_cli.py`, `baseline_configs.gd` and `bench-before.gd` record the original experiment. Their original layout is `tmp/wind-bench-r5/`, with the reconstructed app at `snapshot/app`, the original manifest named `source-manifest.json`, and the base commit in `base-revision.txt`. Copy the scripts there or adapt those path constants before reproduction; retained checked-runner reports record exact original commands. The baseline-config driver extends the saved original benchmark copied to `snapshot/app/tests/bench_spatial_original.gd`. Use fresh output directories. [Payload hashes](payload-manifest.json) and [evidence checkout verification](checkout-verification.json) protect the recorded bytes.

## Remaining gate

Other full suites were active throughout this work, so **no timing benchmark or speedup measurement was performed**. These workload and reporting checks prepare a controlled comparison of R4 on a quiet host, including active weather and separate receipt/wash cost attribution. The 500 microsecond physics target, real-time 240 Hz operation, per-tick latency and 1080p qualification remain open. Longer maneuvers, pilot acceptance, spectra, thermal heating, terrain/obstacle flow, live weather shifts and shared companion admission retain their existing gates. Spatial presets remain opt-in.

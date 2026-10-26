# M5-W05d-R2 — immutable wind-field preparation

2026-10-26. Owner: M5-W. This is a bounded optimization of the [R1 spatial implementation](../M5-W05d-R1/README.md), with its field laws, experimental status and acceptance limits preserved. [Wind guide](../../../WIND-PLAN.md).

## Change and ownership

Only `app/physics/wind_spatial_field.gd` changes runtime behavior. `_apply_config` now prepares typed float64 profile constants and ordered packed gust scalars from the validated, detached configuration. `_neutral_profile` and `_wall_join` reuse constant logarithms and direction trigonometry; `_profile_wind` reuses its join heights. `_gust_wind` skips transition work for an empty agenda, and reads active-event values from packed storage. `_turbulence_wind` accumulates into three scalar float64 locals before constructing its return array.

Arithmetic grouping, mode/event order, signed zeros, seeds, phase reduction, wavelengths, intensity, query locations and 240 Hz stepping are preserved. No mutable time or position cache is introduced. Every sample remains independently evaluable, including reversed-time queries. Returned arrays and configuration objects remain detached. All prepared values are replaced at construction; direct reflective mutation of private fields is unsupported. No aircraft data, geometry, force ownership, weather schema, default, preset or kernel interface changes. No new dependency or native evaluator is introduced.

The repeated profile/gust work was identified in the existing debug bridge's GDScript profiler. The field-only change avoids the mutable model-geometry and shared-session interfaces under concurrent development. Those wider optimizations require separate dependency/invalidation proofs. Source review found no arithmetic-order or ownership blocker.

## Identity and reproduction

The comparison starts from the retained R1 candidate, reconstructed from commit `ac6fb953508bad76b2f12f9690a03ea5b20c014a` plus R1's `candidate-source/` and `verification-generated/` overlays. Apply this directory's `candidate-source/` last for R2. The [comparison manifest](comparison-manifest.json) verifies that exactly one physics/simulation/failure source differs.

| Identity | SHA-256 |
| --- | --- |
| Baseline solver | `cba4552d2749e19ace9483de73a6114adb7beb15ce7e70922b05a2a02fe27904` |
| Candidate solver | `1e035f01e7332979c6c25187cfe99e5be91dea6346f0ec3fc7ca70800a1b1363` |
| Baseline field source | `218908e722fa89347ccdd20423bedac9f0358f970b47661a4ec42cfa1bcf3130` |
| Candidate field source | `39e19ee8beb710f3adeb38bc615a62235373275a36f4752df97472aa0b9553ba` |

Use the pinned Godot `4.8.beta1.official.4d10419ca`, import the reconstructed app, then use the repository's checked runner and `tests/bench_spatial_wind.gd`. Retained checked-runner reports contain exact commands. `run_pinned_comparison.py` records the ABBA order and launcher affinity, using the existing benchmark without changing its workload. Paths in capture receipts identify the original local workspaces; reconstruct those trees or substitute equivalent absolute paths when reproducing. The shared root received unrelated ground, aircraft and lighting work during this experiment; it is not the controlled baseline.

[Payload hashes](payload-manifest.json) cover the retained inputs, sources and receipts. [Fresh evidence-only checkout checks](checkout-verification.json) preserve all 125 payloads byte-for-byte with both `core.autocrlf=true` and `false`, without changing the shared Git index. This is evidence preservation, not full-application clone qualification.

## Correctness evidence

`test_spatial_wind_field.gd` passes its existing 154 checks, including 48 prior exact-byte samples across 8/24/64 modes and thermal composition. The new `test_spatial_wind_prepared.gd` passes 1543 checks against **760 samples recorded from the unmodified baseline**, including zero speed, cardinal/non-cardinal directions, nondefault roughness/displacement, wall/free-air/layer boundaries, tied/overlapping gust starts and endpoints, horizon limits, and 24/64 modes. It repeats the grid backwards while interleaving independent fields and mutating returned arrays. It also checks canonical configuration detachment, unchanged content hashes and byte-identical speed envelopes. The fixture generator is retained; this is a numerical regression oracle, not an independent meteorological model.

The first boundary-harness run compared canonical dictionaries directly with JSON numeric types and failed four configuration-equality assertions. All sample bytes already matched. The corrected test compares the untouched canonical snapshot before/after public-object mutation; it does not loosen sample or hash equality. Both runner receipts are retained.

The four completed full-session benchmark runs cover Jensen, Extra 300S and Turbo Lumber, each under legacy v4 and spatial v5/24-mode weather. Across all runs, the same case retains identical configuration, starting state, final-state hashes and query counts. Every batch passes all eight reset checks and accepts every requested tick without crash/fault. Total workload: **34,560 timed accepted ticks plus 17,280 warmup ticks**. This validates the exercised trajectories; final-state hashes alone do not establish per-tick equality for arbitrary inputs.

All **12 targeted test programs pass, totaling 2912 checks**; receipts are retained under `verification/`. The original R1 spatial `.orfl` is preserved at its existing home. Its exact replay completes with `solver_changed=false`; the R2 candidate replay completes with `solver_changed=true`. Every value in all 61 CSV rows and 62 columns matches, in addition to passing the existing flight-log comparator. Candidate-mode replay remains a candidate experiment, even when all exported values match.

Working-tree field checks also pass (1543 prepared-field and 154 existing checks). The newer working-tree fleet test reports **99 checks, two failures**, both X8 v5 airborne starts. A disposable copy of that solver with the original field reproduces precisely those two failures; [source comparison](root-before-comparison.json) confirms every other physics/simulation/failure source is identical. `WindAircraftFlow.geometry` still requires a horizontal tail, while the valid X8/elevon model deliberately has none. Spatial Aero continuation also assumes both tails. This pre-existing tailless integration gap is not concealed by altering aircraft data or relaxing field checks. Root and original-field runner reports are retained; this slice does not claim a green current-tree fleet gate or a complete repository suite run.

## Profiling and timing

The baseline Extra 300S debug session used the full Realistic v5 preset: 1.5 m/s FROM 075° at 10 m, 24 turbulence modes at nominal 0.08 m/s RMS and 24 gust events. The 20-second **wall-time** profiler window contained four engine samples and advanced tick 552→636, only 0.35 simulation seconds. Flight remained airborne without fault/crash and the session exited without leaked objects. The short, instrumented profile is useful for hotspot ranking, not a production frame budget.

Reported profiler self/total times include `_turbulence_wind` 33.865/46.946 ms over 5619 calls, `_gust_wind` 8.796/9.364 ms, and `sample_world` 2.792/64.502 ms. Audio was the largest overall script cost and remains separate work. Full sorted profiles and accepted weather/state receipts are retained in `profile/`.

Provider-only observations use the existing benchmark's mean wind, seeded modes and active thermal, with three batches of 480 ticks after 240 warmup ticks. At 32 sampling stations:

| Modes | Baseline µs/query | Final candidate µs/query | Observed reduction |
| --- | ---: | ---: | ---: |
| 8 | 18.1475 | 16.1874 | 10.8% |
| 24 | 32.2152 | 30.1650 | 6.4% |
| 64 | 68.5958 | 64.5226 | 5.9% |

These are sequential observations on a shared host, not an isolated causal speedup measurement. All provider checksums match. The scalar-only intermediate run is retained separately. The benchmark has no gust events, so it cannot quantify the active-gust packing gain.

Full-session ABBA runs inherit affinity mask `1048576` (logical processor 20), verified on both engine processes. Host: AMD Ryzen 9 5900X, 24 logical CPUs, Windows, pinned engine above. Other development jobs continued running; affinity does not isolate the CPU from those jobs or its SMT sibling. We did not control CPU frequency, thermals or OS load. Each cell below is the median of six **batch-average** tick costs, not per-tick latency/p95:

| Aircraft | Legacy baseline / candidate µs/tick | Spatial 24-mode baseline / candidate µs/tick | Spatial queries/tick |
| --- | ---: | ---: | ---: |
| Jensen | 602.0 / 732.4 | 4119.0 / 4843.4 | 60 |
| Extra 300S | 2225.3 / 2878.7 | 7821.5 / 9277.0 | 98 |
| Turbo Lumber | 1029.4 / 1081.0 | 4456.1 / 4305.7 | 60 |

**The full-session experiment is inconclusive about a causal speedup or regression.** Unchanged legacy controls are 5–29% slower in the candidate windows; Extra's candidate spatial batch means span 7265.7–23712.2 µs. All raw runs and ranges are retained, including unfavorable observations. An earlier unpinned pair had overlapping launch windows and is excluded from the timing comparison, while retained for transparency. No performance gate is closed. In particular, Extra still exceeds the whole 4166.67 µs tick interval, and none of these results qualifies the stricter physics budget or 1080p rendering performance.

## Acceptance and remaining work

This slice removes measured repeated field work while preserving the tested outputs and public contract. It does not claim a fully optimized simulator or physically validated weather. Before a default change or performance admission, repeat paired full-session measurements on a quiet controlled host, including active gust agendas, thermal weather and longer maneuvers. Continue with measured stage-receipt/geometry overhead only after defining immutable model dependencies and safe invalidation. Do not reduce modes, omit aerodynamic points, change weather by aircraft identity or lower physics frequency to hide cost. R1's spectral, pilot, terrain, heating, spatial-wake, companion and hardware gates remain open.

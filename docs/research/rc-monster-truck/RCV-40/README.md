# RCV-40 — Terrain and track sampling CPU optimization

2026-10-15. Ground sampling now avoids repeated edge calculations and temporary ramp arrays. MONSTER CAR 2's complete production session uses **13.0% less CPU time per tick** in the paired headless workload below. The 240 Hz update rate, float64 arithmetic, contact queries, solver settings and per-tick artifact identity checks remain intact.

## Change and measurement

`GroundTerrain._sample_microrelief_validated` evaluates each rectangle edge's value and slope together, replacing eight script calls per rectangle. `AirfieldTrack.sample` skips masks that cannot beat an existing coverage of one, preserving strict tie precedence. Ramp value and slope calculations use local scalars with the original arithmetic order instead of allocating a packed array per obstacle. There is no cross-query cache or coordinate quantization. The shared terrain optimization also applies to aircraft and helicopter contact sampling; the track remains specific to the RC airfield.

Godot 4.7.2 official Windows debug runtime, Ryzen 9 5900X, native ground-body backend, headless with audio disabled. [Paired whole-session measurements](paired.json) use three rounds of 60 warmup and 960 measured ticks each. Baseline and candidate receive identical inputs, alternating first execution every tick. Timing covers the production `Session.tick_once`; comparison snapshots are taken outside the timer. The baseline substitutes only the retained terrain/track samplers through an otherwise identical course bridge.

| CPU measurement | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Whole session, median of round means | 7.040 ms/tick | 6.122 ms/tick | 13.0% |
| Whole session, median of round p95s | 9.112 ms/tick | 7.926 ms/tick | 13.0% |
| Terrain microrelief | 8.402 µs/query | 4.891 µs/query | 41.8% |
| Track, loop centerline | 13.046 µs/query | 7.478 µs/query | 42.7% |
| Track, global mixed probes | 8.747 µs/query | 6.872 µs/query | 21.4% |

Whole-session reductions are 13.0%, 12.9% and 13.0% across the three rounds. Component values are medians of five alternating batches: 200 warmup calls per implementation, then 3,072 terrain queries or 3,000 track queries per batch. [Terrain](terrain.json) and [track](track.json) receipts retain source/input identities and raw timings; their harnesses regenerate the fixed seeded inputs.

The initial [instrumented profile](baseline.json) attributed 4.227 ms/tick, about 46% of tick time, to 70 road queries per tick. This is a nested cost inside integration/telemetry, not an additional independent bucket. The [candidate profile](candidate.json) uses the same instrumentation and validates replay. These separate processes are diagnostic; the interleaved, uninstrumented session comparison above is the performance result. Concurrent unrelated work on this shared host varied absolute times. These measurements do not establish FPS, GPU cost or target-hardware performance. The candidate still exceeds the 4.167 ms interval at 240 Hz; that gate and the track's stricter performance target remain open.

## Equivalence and compatibility

The [summary validator and evidence hashes](summary.json) require all receipts to be complete and match their sources. Verification covers:

- 18,256 terrain comparisons across rectangle seams, overlaps, small rectangles, custom/empty tables and lake contact. Finite accepted results use byte equality; invalid public inputs must retain NaN rejection.
- 45,596 byte-exact track dictionaries across a full grid, ramp and shoulder boundaries, seeded points, three valid geometry variants and the empty-track case. Height, gradients, coverage, feature IDs and signed zero are compared.
- 3,060 paired ticks with exact state and telemetry bytes, plus identical accepted control tapes, event tapes and checkpoints within each paired round.
- The independently recorded baseline and candidate each pass checkpoint restore, official replay and a second full-trajectory replay. Both versions and every paired round share trajectory SHA-256 `d2c255aee62148ea79908da716d1c1c6279b20b22e5b1a88bc9e261597908eb8`, covering all 1,020 warmup/measured states per trajectory.
- All 12 [focused regression suites](checks/verification.json) pass: 365 numbered checks plus the lake/course suites, which report aggregate success without a count. They cover terrain, ground surfaces/contact, lake contact, aircraft ground starts, helicopter ground starts/sessions, RC track/course, Nitro dynamics/session and the original ground-vehicle session. Retained engine logs contain no script/shader/engine errors. Full repository tests, rendering and release export are outside this phase.

An initial ramp draft replaced runtime negation of a zero slope with a literal negative zero; 89 boundary comparisons detected a changed zero sign. The accepted implementation retains runtime negation/division and passes the byte comparison. Keep the edge cases when changing this arithmetic.

`solver_changed=false`: body/Nitro code and native binary identities are unchanged. `course_changed=true`: course identity includes the modified sampler sources. Historical course-pinned RC checkpoints/recordings therefore remain incompatible with this source revision under the existing identity guard. No guard was relaxed. Numerical equivalence on the tested inputs does not establish physical calibration or permission to relabel historical recordings.

## Reproduce

The [vehicle guide](../../../../research/rc-monster-truck/monster-car-2/README.md) owns operation. [`rcv40/`](../../../../research/rc-monster-truck/monster-car-2/rcv40/) owns retained baseline samplers, the course bridge, paired/component harnesses, profile wrapper, regression runner and summary validator. Run Godot processes sequentially from the repository root, with an existing output directory:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/rc-monster-truck/monster-car-2/rcv40/bench_terrain.gd -- --output=C:/path/to/terrain.json
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/rc-monster-truck/monster-car-2/rcv40/bench_track.gd -- --output=C:/path/to/track.json
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/rc-monster-truck/monster-car-2/rcv40/bench_pair.gd -- --output=C:/path/to/paired.json
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/rc-monster-truck/monster-car-2/rcv40/bench_session.gd -- --output=C:/path/to/candidate.json
python research/rc-monster-truck/monster-car-2/rcv40/verify.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out C:/path/to/checks
python research/rc-monster-truck/monster-car-2/rcv40/summarize.py
```

The summary validator reads the canonical evidence directory. The retained baseline profile was captured before integration; reproduce it only in an isolated checkout with the two production samplers replaced by their retained baselines. Paired/component harnesses need no production file replacement.

Godot's [CPU optimization guidance](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html) recommends profiling bottlenecks, repeating manual timings and accounting for cache effects. Its [profiler documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/the_profiler.html) distinguishes frame and physics timing. Consulted 2026-10-15; the receipts identify the exact tested runtime.

# UI-34c / DT-11a: repeated contact preparation

2026-10-24. This continuation of [R3](../UI-34c-R3/README.md) reuses the immutable scenery collision inventory. The [execution plan](../../../MENU-REDESIGN-PLAN.md#12-home-to-flight-loading-ui-34c-and-dt-11a) owns remaining work. Physics equations, aircraft data, session validation and golden recordings are unchanged.

## Implementation and ownership

`CollisionWorld.build` keeps one process-local entry containing serialized input and world bytes, capped at **8 MiB combined**. Its exact key covers the complete field, scenery and light inputs plus the current parked-aircraft metadata. Each distinct aircraft/configuration file is read once per construction request; that same snapshot supplies both the key and the build. File changes therefore invalidate reuse even when catalog IDs stay the same. There is no disk cache or retained live world/session.

Only the main thread accesses the cache. Unsafe or oversized inputs and off-main calls use ordinary construction; failed builds never publish. Every hit decodes a new world, including independent proxy dictionaries and broadphase bins. The normal scenery/field loading and session collision validation still run. Source constants have process lifetime; this cache does not promise editor hot-reload invalidation.

Godot's ordinary [Variant serialization](https://docs.godotengine.org/en/stable/classes/class_@globalscope.html#class-globalscope-method-bytes-to-var) is used without object deserialization. The default entry retains **4,910,972 bytes**; the cap describes retained serialized data, not temporary allocation, caller-owned worlds or process RSS.

## Evidence and method

[Source identities](source-identities.json) freeze baseline `d064ccc3a` and candidate `9608f7200`. Both worktrees have identical hashes for the other measured integration files and all 399 tracked import metadata files. The engine is Godot 4.7.2 Compatibility on Ryzen 9 5900X / RTX 3090, NVIDIA 617.42. Initial seeded imports reported stale UIDs; the second checked import passed in both worktrees before measurement. OS/driver caches and other host activity are uncontrolled; no competing Godot process was detected when each timed run started.

The existing debug bridge's [headless script profile](attribution-profile.json) supported construction attribution. Its sampled, instrumented CPU values are not native loading timings. The existing loading probe then ran **five alternating fresh-process pairs**, each with a first and repeated Turbo Lumber flight, at actual fullscreen **1920×1080**. [Raw runs and frame distributions](native-summary.json) retain all samples, including slower candidate runs. All 20 paired transitions had active first draws, zero orphan nodes and clean checked exits.

| Median | Baseline | Candidate |
| --- | ---: | ---: |
| First Fly readiness | 8.401 s | 8.344 s |
| Repeated Fly readiness | 1.692 s | 1.592 s |
| First contact preparation | 229.6 ms | 268.0 ms |
| Repeated contact preparation | 227.9 ms | 121.0 ms |

Repeated contact preparation improved in all five pairs, with a **46.9% median reduction**. Total repeated readiness improved in three pairs and regressed in two; its median fell 5.9%, but this series does not establish a general end-to-end speedup beyond host variation. There is **no demonstrated first-load speedup**. Serialization adds roughly 38 ms to median first contact preparation; this is an explicit cost of retaining reusable data.

Candidate click-to-loading-draw feedback was 7.8–20.1 ms. Cold handoff p95 was 22.4–28.4 ms, but maximum frames were **1.65–2.41 s**. Warm p95 was 176–231 ms, with maximums 229–257 ms. Counts above 33/50/100 ms are retained per run. Cold scene preparation and scenery/sound/instrument work still violate the cadence and chunk targets; the many responsive trim-worker frames do not erase those stalls.

The separate [20-cycle Stik run](native-stik20.json) had 869 Home nodes on every cycle, zero orphan nodes, active first draws throughout and no remaining audio playbacks at shutdown. First readiness was 3.900 s; repeated median was 1.616 s. This verifies node lifecycle for that route, not RAM/VRAM stability, a 30-minute soak or minimum-hardware qualification.

## Correctness checks

The [checked differential test](cache-parity.log) compares the complete default world against the unmodified baseline source: **4,781,420 identical bytes**, SHA-256 `a0eeb61cd3f072b5f1e77564592841bcb6067c85de2667955bd8cb7f3e4300c4`. Cold and decoded-hit output match. The isolated diagnostic measured 213.9 ms for a miss and 49.1 ms for a hit; it is not a full-Fly estimate.

- Cache regression: 32 checks with the baseline reference, covering input/parked-geometry changes, mutation of both cold and hit results, eviction, failures, unsafe/recursive data, oversized input/output and off-main fallback.
- Existing landscape collisions: 52 checks; visibility/quality collision setup: 22; parked-aircraft geometry/contact behavior: 45.
- Loading transaction: 14 checks, including cancel, quit, duplicate activation and readiness. All four existing golden flights pass without re-recording.
- The optional compiler-warning audit is inconclusive: both [baseline](compiler-baseline.json) and [candidate](compiler-candidate.json) return `NO_DIAGNOSTICS` for the collision script. This is a language-server/tool limitation, not a clean-warning result. Checked import, execution and differential validation above pass.
- Final import passes. [Checked receipts](checked-runs.json) retain commands, diagnostics and engine-log hashes; direct exploratory runs are not substitutes for these receipts.

Integration into shared `main` at `9384a0c11` preserves the concurrent branding, camera and graphics changes. Import, the 32-check differential/cache test and the 14-check loading transaction test pass again. The [native integration check](integration.json) completed two electric launches at 1920×1080 with active first draws, zero orphans and clean teardown (8.349 / 1.540 s readiness). It is separate from the frozen A/B series.

## Remaining work

Keep the normal flight-scene loader while its threaded lifetime regression remains unresolved. Next isolate cold scene-script preparation, then split the measured scenery/sound/instrument chunks and the still-blocking contact miss. A same-lake hull-preparation duplication was identified in `FlightSession.set_lake_context`; it is only an audit finding, not an implemented change. Any repair there needs session/contact parity and the solver-source qualification workflow.

Selected numeric prefetch remains a later experiment with immediate-Fly and 2/5-second dwell comparisons, cancellation and total-startup gates. Fly ≤2 s, loading p95 ≤33 ms, no chunk above 100 ms, the full source suite, exported package, route matrix and DT-12 qualification remain open. No physical validation is claimed.

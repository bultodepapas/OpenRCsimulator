# 11 — Startup stages, resource reuse and Compatibility shader preparation

2026-10-07 · DT-00-R1 · **Source/code investigation; no startup or GPU timing claim.**

## Question and method

What can actually improve launch and Home → Fly without hiding cost, changing flight timing or adding unsafe threads? Read `app/app_root.gd`, `app/ui/home_scene.gd`, `app/main.gd`, `app/render/tree_assets.gd`, `app/sim/flight_session.gd` and the Godot 4.7 documentation below. Existing [VQ-01b](../../visual-quality-implementation/VQ-01b/README.md) supplies measurement infrastructure, not a current hardware baseline.

## Audited path

| Stage | Current code | Research implication |
| --- | --- | --- |
| Bootstrap | `app_root.gd` preloads menu classes; `show_home()` constructs `HomeScene` before Home controls | An empty/blocked window may precede the interactive menu; measure from OS process creation as well as GDScript startup |
| Home scene | `HomeScene._init()` loads field data and builds atmosphere, field and aircraft synchronously | Threading scene-file loading alone cannot eliminate procedural construction |
| Fly | `start_flight()` removes Home and calls `load(FLIGHT_SCENE).instantiate()` then adds it to the tree | Isolate resource loading from instantiation, `_ready`, validation and first draw |
| Flight readiness | Session `setup()` loads/validates aircraft and solves its trimmed state before committing it | Do not skip trim or reuse a mismatched result to meet a startup target |
| Repeated geometry | Home and flight call the shared field/aircraft builders independently | Possible reuse opportunity, but a shared builder does not prove repeated expensive work or a cache benefit |
| Tree resources | `TreeAssets.card_mesh()` reparses its catalog and constructs mesh/material per call; atlas uses `load()` | Resource cache and procedural construction are different costs; ownership comments deliberately permit caller mutation |

These are call-path findings, not a profiler result. Concurrent landscape and physics work can change the bottleneck; freeze source hashes and artifact identity before timing.

## Primary-source findings

[Background loading](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html) allows resource requests in worker threads, but fetching the result before completion still blocks. It does not move procedural `_init`/`_ready` work out of the main thread automatically. [ResourceLoader](https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html) documents resource caching and cache modes; use the effective mode and reference lifetime when explaining repeated-load results.

Godot warns that active SceneTree operations and rendering-object creation are not generally thread-safe. Sharing and mutating a resource from workers introduces a separate correctness problem. Keep scene activation on the main thread and add concurrency only around a measured, supported operation. [Thread-safe APIs](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html).

The engine's shader baker and modern pipeline precompilation do **not** apply to Compatibility. Its documented preparation route involves actually rendering the needed materials before use. Invisible or unrendered resources alone cannot be accepted as proof of warming this backend. Hardware/driver caches are separate from Godot's imported-resource cache. [Shader compilation guidance](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html).

## Proposed experiment

Add timestamps around process launch, bootstrap entry, Home construction, Home first draw and Home accepting input; then around Fly action, resource acquisition, procedural construction, trim/validation, scene activation and first controllable flight frame. Record failure paths too. A shell launch timestamp and a GDScript timestamp need a defined alignment, not subtraction of unrelated clocks. Use the protocol in [09](09-performance-statistics.md).

For each offered aircraft, compare first launch, second process launch, first Fly and repeated Fly. Name caches as warm/cold/unknown separately for imports, OS file cache and driver shaders. A new process is not evidence of a cold driver cache. Do not wipe a pilot's global driver cache for a benchmark.

Then run one bounded experiment at a time:

| Hypothesis | Smallest useful change | Reject if |
| --- | --- | --- |
| Disk/resource loading dominates | Begin one threaded resource request while Home is usable; consume only after loaded | Construction/trim still dominates and total latency does not improve |
| Procedural field rebuild dominates | Reuse immutable source data or a bounded cache with declared ownership | Callers mutate shared materials/meshes; memory climbs across sessions |
| First-use compilation dominates | Render the required material/mesh variants during a bounded readiness stage | Only load/instantiate timing improves while first visible flight still stalls |
| Startup itself is acceptable but UI seems frozen | Present responsive loading state before expensive activation | Cosmetic frame appears but keyboard/cancel never works or progress is invented |

Hold simulation and engine audio until the accepted readiness point. Releasing the hold requires valid aircraft state and intact input/arming rules; never start flight behind a loading panel and later hide the elapsed time. Cancellation/quit frees pending scenes and does not reactivate an abandoned flight.

## Plan changes and acceptance

**DT-10:** collect a stage breakdown before choosing DT-11a. Keep startup measurement outside the steady-state frame logger, which excludes its first callback and warm-up.

**DT-11a:** explicitly exclude shader-baker toggles for the current backend. If a cache is justified, cap its retained resources, identify invalidation (aircraft/field/version), and preserve the current ownership contracts. A renderer change needs separate evidence and approval through its existing owner.

**DT-12:** exercise rapid aircraft selection, repeated Fly/End, cancel/quit during preparation and missing/corrupt packaged resources. Require no doubled cameras, stale aircraft, live audio in Home, simulation advancement behind readiness UI or unbounded retained resources. Compare before/after on the same package protocol and hardware.

No resources, shaders or physics were modified. No benchmark was run: performance priority remains unknown until native profiling. All linked vendor pages were opened on 2026-10-07; the table's optimization choices are proposed experiments rather than measured wins.

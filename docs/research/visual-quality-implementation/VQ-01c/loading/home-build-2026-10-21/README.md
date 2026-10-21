# DT-11a / VQ-01c — release Home construction attribution

2026-10-21. **Bounded attribution completed; retain the production runtime.** Two collector-only controls and two diagnostic Windows release runs identify first-Home field/scenery and aircraft-preview costs. No specific small repair establishes a plausible >5% complete Home/Fly gain with unchanged output. This closes the next action from [package attribution](../package-attribution-2026-10-21/README.md), not loading, pacing or visual acceptance.

## Scope and method

Frozen source: `3f3892c7ee97340469975e12b99d5cd6c160e0f0`, initially clean. All 3,840 tracked `app/`, `assets/aircraft/` and `tools/` inputs remain unchanged. A private real-byte snapshot on D: holds copied import/native caches, two actual Windows release exports and diagnostic instrumentation. Export preset, source guards and native DLL receipt remain intact. No generated asset, physics input, golden or production launch configuration changed.

Reuse the preceding release collector: a custom MainLoop with an empty host scene invokes the real AppRoot, Home Fly callback, deferred readiness and post-draw path, then bounded cleanup. Scope is the default Ugly Stik and Club field. Each process completes two Fly/return cycles. Both executables report `editor_feature=false` and `debug_build=false`; they launch normally from an empty directory. These are collector-bearing release builds, not a new ordinary-package qualification.

The diagnostic adds a maximum of 512 in-memory spans, with 117 recorded per run. Wrappers retain the original function bodies and synchronous order. Field segment clocks surround ground, cues, lake resolution, scenery attachment, lake attachment, grass, landscape and finalization. `World.build` exposes its existing `field_build_ms` through diagnostic metadata. The existing Scenery `stats.timing_ms` is copied after build; no per-call logging or additional geometry traversal is added. Report writing happens after timed transitions.

**Timing semantics:** Home `_init`, World, Field, Scenery and preview spans are inclusive and nested. Do not add them. Scenery's `meshes` bucket includes `cell_meshes`, `shelter_material` and `shelter_meshes`. Its `build_ms` ends before final metadata assignment, so it is slightly shorter than the wrapper. Field `cues` includes treeline/cue construction and cue shadows; `grass` includes exclusions and attachment. World minus its field callback includes both surrounding world work and instrumentation; it is not a measured standalone optimization. Synchronous construction excludes subsequent first-draw work and is not a GPU timer.

Host: Ryzen 9 5900X, RTX 3090, NVIDIA 617.42, Godot 4.7.2 `ed1daf0bf`, Compatibility, 1280×720 viewport, VSync 1, cap 60, Dummy audio. Native timing was serialized, without overlapping export, bulk copy, tests or hashing. OS/import/shader caches and background host activity were uncontrolled. Fresh process does not mean cold cache. The virtual desktop still does not qualify the physical display or refresh/latency target.

## Complete-path observations

| Execution order | Home engine elapsed (s) | Home from load (s) | First Fly draw (s) | Warm Fly draw (s) | Home from load + first Fly (s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Collector 01 | 6.634 | 3.927 | 2.200 | 1.472 | 6.127 |
| Diagnostic 01 | 6.619 | 3.913 | 2.196 | 1.465 | 6.109 |
| Diagnostic 02 | 6.646 | 4.069 | 2.293 | 1.452 | 6.362 |
| Collector 02 | 6.441 | 3.881 | 2.140 | 1.433 | 6.021 |

Every first draw is active at tick 12. All reports show zero orphan nodes, released tracked audio and removed isolated settings. Flight node counts are 1,272; Home counts are 781 except one 779 observation. This is not exact scene parity, a growth test or leak-free certification. No ObjectDB exit warning appears in these four collector logs; the prior ordinary-release four-object shutdown warning remains unresolved.

The controls bracket diagnostics, but four samples cannot isolate observer overhead from host variation or establish a speedup. Home engine elapsed still exceeds 5 s and first Fly exceeds 2 s. The combined interval excludes pre-load startup and the user's time on Home; it is the retained screening denominator, not total launch-to-flight wall time. [Raw reports](runs/) and [derived metrics](metrics.json) preserve exact values.

## Construction findings and ROI

| First-Home inclusive stage | Diagnostic 01 (ms) | Diagnostic 02 (ms) |
| --- | ---: | ---: |
| Home `_init` | 2,348.966 | 2,453.091 |
| World build | 1,917.925 | 1,991.320 |
| Existing World field callback | 1,706.572 | 1,759.987 |
| Field build | 1,706.556 | 1,759.969 |
| Scenery attach | 1,110.590 | 1,116.107 |
| Scenery build | 1,081.188 | 1,082.047 |
| Aircraft preview (`show_aircraft`) | 410.873 | 440.616 |
| Aircraft builder within preview | 317.165 | 343.240 |

The existing callback confirms that the field owns most World construction. Surrounding World work is approximately 211–231 ms by subtraction; its separately observed pre-field interval is 72–78 ms. First field ground work is 134–141 ms, cues 174–190 ms, lake attachment 72–75 ms and field projected shadows 121–134 ms. Later complete World builds are 539–563 ms and Scenery builds 160–169 ms. Returning Home construction is 748–761 ms in the diagnostics; caches already eliminate much first-use work.

Within first Scenery construction, the largest reported buckets are vegetation **277–294 ms**, fleet **126–129 ms**, botanicals **115–116 ms**, instances **106–113 ms**, and population **76–78 ms**. Vegetation falls to approximately **1.2–1.5 ms** on subsequent builds. `ImportedVegetation.get_parts` already retains imported parts; adding another cache cannot remove its first acquisition. These inclusive durations do not distinguish disk/resource decoding, mesh/material preparation and driver work.

No candidate is adopted:

- Eliminating the entire measured first vegetation bucket would save only about 4.3–4.8% of the combined first path, before any replacement cost. Moving its work to startup or first flight would shift the delay. This is a screening bound for that bucket, not proof that all vegetation-related work is below 5%.
- Scenery's 1.08 s is distributed among assets and independent builders. Reusing a complete field would introduce scene, lighting, damage and resource ownership work; that is not a small repair established by these timings.
- Preview's 411–441 ms is worth recording, but contains required model construction and shadow binding. No safe way to eliminate most of it on the first launch was demonstrated. Repeated cue/shadow construction may merit a future owner-specific experiment, but these samples do not establish a qualifying complete-path mechanism.

The experiment solved the attribution question, not loading latency. Reusing existing timings and collector code kept engineering scope bounded; another general cache/preload system is not justified. No candidate means no five-pair adoption campaign or speculative production patch. This is a defer/retain decision with limited evidence, not a claim that loading cannot be improved.

## Verification, limits and next action

Two exports and four native runs pass the checked runner. Existing maple-wind and aircraft-inertia notices remain in the logs. [Verification](verification.json) checks retained hashes, log hashes, release identity, active completion, span nesting/callback consistency, source preservation and unchanged export preset. Both exported native DLLs match the pinned receipt. No full app suite, capture matrix, field parity suite, 20-cycle growth test, soak or other-platform export was run: production code did not change and no visual/runtime adoption is claimed.

**Next: DT-10a / H / VQ-01c native frame pacing, then VQ-01d / CAM motion visibility.** Close this half-day loading attribution scope. On a frozen ordinary release, collect three uninterrupted controls with 10 s warmup and 60 s sample; retain paused/incomplete runs as ineligible. Use existing `--frametimes` and reducers, followed by a separate `--frame-diagnostics` run only to attribute a reproduced tail. Keep VSync/cap experiments separate, and preserve focus-loss pause and explicit resume. The existing [native-frame workflow](../../../../../../research/performance/README.md#native-frame-evidence) owns commands and interpretation.

Bound the next pacing attribution to half an engineering day. Select one reproducible >50 ms hitch or complete-workload cost only when evidence identifies a mechanism; otherwise retain/defer and refresh the motion reference. Physical-display qualification requires a named physical monitor; available virtual-display diagnostics remain explicitly unqualified. A repair still requires the owning correctness gates and three alternating A/B pairs, with >5% affected-workload gain or removal of the reproduced named hitch. Refresh motion cases and obtain owner circuit/readability evidence before appearance changes. Loading goals, ordinary-release shutdown, long lifecycle and platform gates remain open.

## Reproduction

[Manifest](evidence-manifest.json) maps original/stored SHA-256 values; large artifacts use deterministic gzip. Exact profile sources, patches, frozen input hashes, build identities, native receipt, checked logs and recipes are retained in `provenance/`. Binary exports stay on D: with hashes recorded.

At the stated commit, copy the preparation/run recipes into `<repo>/tmp/`, preserving `graphics-phase2-2026-10-21/make_loading_profile.py` beneath it. Preparation requires the pinned engine/templates and refuses an existing D: snapshot. Run `home_prepare_graphics_export.py`, `home_prepare_export_collector.py`, then `home_run_graphics_export.py collector`. Collect `home_run_package_loading.py collector 01`; apply `prepare_home_profile.py` once, export `diagnostic`, collect diagnostics 01/02, then collector 02. The already exported collector executable is unchanged by later snapshot instrumentation. Use fresh output numbers and serialize native runs. The profile recipe is a one-off mutator, not a safe general snapshot builder: it does not preflight the complete manifest or enforce a reusable output boundary. Apply it only to the freshly prepared fixed-path snapshot. Post-run source verification establishes the inputs of these runs. `home-profile.patch` describes changed files; the separately retained `profile-sources/phase2_loading_profile.gd` and `home-profile-sha256.json` are also required. Spans use timestamp containment and chronological build order, not explicit cycle IDs. These are diagnostic recipes, not a new production harness.

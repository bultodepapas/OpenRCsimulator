# DT-11a: first-flight scene warmup — retain baseline

2026-10-21 · Source `210018c5367defe04677cdc937d45e869bafc4b9` · Godot 4.7.2 `ed1daf0bf` · Windows Compatibility, RTX 3090, 1280×720, VSync on, cap 60.

**Decision: reject this candidate.** Loading `main.tscn` in a background request before Home construction makes Fly faster but delays Home, fails the complete-path benefit gate and introduces a repeated shutdown warning. No runtime change is adopted. This completes one bounded DT-11a experiment; it does not qualify VQ-01c or a package.

## Hypothesis and implementation

[Attribution profile 05](../../attribution-2026-10-21/README.md) isolates first scene resource loading at 1,627.941 ms and instantiation at 0.068 ms; warm values are 0.763 and 0.092 ms. The earlier `_create_flight` span alone could not distinguish these operations. Repeated aircraft validation is about 16 ms, so a validation cache is not justified by this profile.

The [scratch patch](sources/warmup-trial.patch) starts one `ResourceLoader.load_threaded_request(main.tscn, "PackedScene", false)` after preferences identify a flyable fixed-wing and before initial Home construction. The matching Fly consumes the request once and instantiates on the main thread; direct/rotorcraft routes retain their existing path. Request failure falls back to normal loading. An unused request is drained on shell exit. No flight instance, validation result or simulation is prefabricated.

Godot documents background resource requests and warns that retrieval blocks while a request remains in progress. That makes Home cost, immediate Fly and pending-request teardown relevant gates. Both observed Fly retrievals report status `3` (loaded). The request being complete does not establish safe shared-resource concurrency or clean shutdown. [Godot 4.7 ResourceLoader](https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html), [background loading](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html).

## Native stop/go results

All four fresh processes complete two real Home → Fly → Home cycles through the unchanged loading probe. Every first draw is active at tick 12; node counts are 777 at Home and 1,268 in flight, with zero reported orphan nodes. The probe releases its tracked audio and removes its isolated settings. These counters do not rule out other retained objects.

| Pair / order | Variant | Home from load (s) | First Fly draw (s) | Combined (s) | Warm Fly draw (s) |
| --- | --- | ---: | ---: | ---: | ---: |
| 01: control → candidate | Control | 7.007 | 4.273 | 11.280 | 2.249 |
| | Candidate | 8.857 | 2.209 | 11.066 | 2.371 |
| 02: candidate → control | Control | 5.247 | 3.416 | 8.662 | 1.712 |
| | Candidate | 6.638 | 1.762 | 8.400 | 1.679 |

Combined is the per-run sum of Home first-draw-from-load and immediate first-Fly first-draw intervals, not a sum of percentiles or process launch time. Home regresses **26.4% / 26.5%**; combined gains are **1.90% / 3.02%**, below the >5% complete-workload gate. Engine-elapsed Home values remain in [comparison.json](comparison.json) and the raw reports. Even the narrower Home-from-load values miss the 5 s goal in every run.

Both candidates emit **“11 ObjectDB instances were leaked at exit”**; neither control does. The checked runner returns `ok: true` because warnings are not globally errors, but this new repeated warning independently fails candidate acceptance. It is an exit-retention signal, not a measured steady-state leak rate or an identified root cause. No warning is suppressed.

The second pair is diagnostic: copying/hashing approximately 975 KB of already completed evidence may overlap candidate startup. No native processes overlap. The first pair has no such packaging overlap. Host activity is otherwise unreserved, OS/import/shader caches are uncontrolled, and elapsed times differ substantially between pairs. Do not average these into a qualified speedup. Two failed screens justify stopping; they do not replace the five-pair adoption campaign.

## Tests, boundaries and return on effort

Candidate `app_root.gd` parses successfully. Native real-route checks establish two successful warm repeats per variant, normal readiness and the repeated exit warning. Separate existing simulation (11 checks), UI-pause and start-choice (36 checks) suites pass on the frozen control with the startup observer; their checked logs are retained under `checks/`. They establish those existing safety contracts, not candidate acceptance. No physics, aircraft data, generated assets or goldens change.

Because the candidate fails before adoption, pending-exit, route-switch, injected-request-failure, 20-cycle growth, full physics/capture and package campaigns are **not run for this candidate**. They are not marked passed. No attempt is made to repair its new lifetime/concurrency risk without a qualifying benefit. The useful outcome is a precise first-load target and avoidance of an extra asynchronous ownership path with poor observed return.

Measurements are source/editor runs; export presets use `script_export_mode=2`, and actual exported loading may differ. The virtual 1920×1080 desktop and GPU identity do not qualify the physical 4K/120 Hz display, minimum hardware, input latency or other platforms. No visual-quality change is claimed.

## Next bounded action

**DT-11a / DT, then UI:** measure the same first-Fly resource-load boundary in one current Windows export using the repository's existing isolated export workflow and pinned mode. Keep original source and package identities, first-draw/readiness semantics, fresh/warm distinction and clean teardown. First inspect available disk/template capacity; do not download another large toolchain or clear user caches merely to force a run.

If the exported first load is still material, inspect the dominant dependency group of `main.gd` before selecting one lazy-load or dependency reduction experiment. Require actual complete Home-to-Fly improvement >5%, no Home regression, unchanged validation, unused-feature first-use checks, repeated route/lifecycle checks and five alternating fresh/warm pairs before adoption. Do not defer a dependency onto the first crash, failure, smoke or controller event without measuring that new stall. If package loading is small, retain the scene-loading path and return to the measured field/scenery construction cost (~0.57/~0.20 s during flight), selecting only one attributable mechanism. No broad preload rewrite or renderer change follows from this result.

## Reproduction and integrity

[Manifest](evidence-manifest.json) retains raw/stored hashes and original locations; [source identities](sources/warmup-trial-identity.json) distinguish original bytes from LF-normalized patch text. [Source verification](source-verification.json) checks the frozen tracked inputs against production and both trial trees. Only candidate `app/app_root.gd` differs. Ignored import/native caches are reused and are outside that tracked-input assertion.

The scripts are retained experiment recipes, not a new production harness. Reconstruct the frozen control at the stated commit with its imported resources and sibling `assets/aircraft`/`tools` inputs; place the recipes in the original `tmp/graphics-phase2-2026-10-21` layout. `make_warmup_trial.py` creates new linked snapshots and detaches every edited file; it refuses existing output directories. Do not import/edit shared hardlinked resources in those snapshots. `run_warmup_trial.py control 01` and `run_warmup_trial.py warmup 01` invoke the canonical checked runner and loading probe. Exact commands, warnings, timestamps and exit statuses are retained in `runs/*/report.json` and `engine.log`. Keep timed runs serialized and retain unsuccessful runs.

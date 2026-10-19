# Cold scenery construction audit

Static source review against the detached baseline at HEAD 122889b8e846b501dc17ffd610e60bf340bd4786; the frozen source tree is in ../baseline/. The timing table uses the retained native attribution JSON from a prior WIP campaign ([raw result](../../godot-audit-r2-20261019/loading/attribution-native-v4.json)), not a measurement on this frozen baseline. The JSON does not pin source hashes and reports 30 vegetation instances, while this baseline's current default placement data has 27. Treat that as a workload-comparability limit; it is not evidence of a game defect. No new engine checks or timings were run here.

## Measured phase ranking

These are the complete `timing_ms` groups from the prior WIP run's cold `home_initial` scenery build (`build_ms` 1,047.639 ms), ranked by the raw values rather than by subtracting two selected fields:

Raw result SHA-256: `935b2f937d7e7a2b7179a5634e5644ba50390c7e36800e72538341e8416ae522`.

| Rank | Scenery group | Cold time | Share of 1,047.639 ms |
| --- | --- | ---: | ---: |
| 1 | Imported vegetation | 353.655 ms | 33.8% |
| 2 | Procedural instances | 198.005 ms | 18.9% |
| 3 | Botanicals | 131.613 ms | 12.6% |
| 4 | Population | 120.608 ms | 11.5% |
| 5 | Patch | 80.377 ms | 7.7% |
| 6 | Woodland edges | 76.134 ms | 7.3% |
| 7 | Meshes | 29.729 ms | 2.8% |
| 8 | Fence | 25.275 ms | 2.4% |
| 9 | Fleet | 15.146 ms | 1.4% |
| 10 | Hedge | 13.645 ms | 1.3% |
| 11 | Track | 1.112 ms | 0.1% |

The raw groups sum to 1,045.299 ms (99.78% of the reported build), leaving a 2.340 ms residual. These values are one native cold observation from a fresh process; the JSON says OS/import/shader cache state was uncontrolled and does not separate disk work from scene instantiation or mesh preparation. In its first two warm scenery phases (`fly_cycle_01`, `home_return_01`), procedural instances still cost 123.546 and 140.743 ms, and botanicals 48.338 and 84.766 ms. These remain the dominant warm construction groups to profile. By comparison, across the retained warm phases vegetation costs 2.64–4.58 ms and population 5.39–7.86 ms. The cold 30-versus-27 vegetation placement discrepancy prevents treating any of these timings as an exact measurement of the current default source.

## Candidate review

The most obvious exact reuse in the reviewed source is the second call to **VegetationPlacement.spec** in the instance loop of app/scenery/scenery.gd. The first call queues each imported plant; the later call recomputes its dimensions for a contact shadow. Current default data has 27 imported placements: 10 shade trees, 4 saplings, 6 bushes and 7 flower clumps. The catalog enables those shadows only for shade trees and saplings, so at most 14 repeated spec calls are removed. The placements are all inside the 300 m shadow range. Each repeated spec performs scalar sizing and deep-copies one already indexed asset record through **ImportedVegetation.get_asset**; it does not reload a model or parse the catalog. The likely saving is below 1 ms, far below 1% of a cold build, and the 30-placement WIP timing cannot quantify it for the 27-placement baseline. Rejected without a code draft.

Other safe-looking ideas do not clear the same bar from available evidence:

- Population.build calls Mesh.get_aabb for each source part and placement. The current default field has 24 population placements. Hoisting the part bounds is exact, but the prior WIP population group is 120.608 ms and has no sub-call timing showing that these repeated native queries cost 10 ms or more. Rejected as unproven below the 1% gate.
- Imported vegetation grows per-instance bounds and prepares one draw mesh per source part. Moving the small bounds expression is unlikely to matter at this placement count. Returning cached source meshes instead of duplicates could change resource sharing and mutation behavior, so it does not meet the exact mesh ownership constraint without new evidence.
- A prior strong PackedScene reference probe reduced warm load to 0.529–0.545 ms and instantiation to 0.055–0.063 ms. The previous audit rejected that cache; this remains below the end-to-end gate.

No candidate here has a justified saving above 1%. The next useful action is a fresh-process native profile on an exact current-source snapshot that first confirms the default 27 imported placements. Prioritize the persistent `instances` and `botanicals` groups, and split their expensive calls; then profile `ImportedVegetation._load_parts` and `Population._source` if cold imported assets remain an explicit target. Draft only against a sub-call that shows at least roughly 10 ms removable from the full cold build, and keep resource ownership unchanged.

For that follow-up, retain the untouched source snapshot and candidate source with SHA-256 hashes before running either. Use the same engine build, project settings, machine, and default field inputs; execute baseline and candidate serially in fresh processes, alternating order across at least seven paired runs. Record the full cold-build time and the profiled sub-call time per run, then compare paired medians and spread. Accept a performance claim only if the paired end-to-end median improves by at least 1% and the gain exceeds observed run-to-run noise. Before comparing timings, assert identical placement IDs/transforms, mesh vertex/index/surface data, material assignments and resource ownership; compare deterministic build summaries and rendered captures at fixed camera, lighting and frame state. Revert the candidate if any output differs or if the end-to-end gain misses the threshold.

## Static review of the windsock update cache

The baseline already contains the VQ-04a-F3 windsock optimization. It is a cue-local view cache in each windsock root's metadata, not a global PackedScene or asset cache. It stores that cue's Fabric, Basket and Support nodes, material, dimensions, and fixed hardware bounds. Field.build creates those children and keeps the same cue roots in its wind_cues list; frame updates and resets act on those field-owned roots. No current call site replaces the cached children, meshes or material.

Each build still creates its own meshes and ShaderMaterials. The cached node references live with the root and are released with that field; shader and texture resources are preloaded constants. Reset forces an upload even when it returns to a previously cached pose. Ordinary updates skip only when the exact centerline, yaw and clamped inflation match; the shared shader clock still advances GPU flutter. The concrete lifecycle limit is runtime replacement of a cached child or material after build, which the owning VQ-04a-F3 note explicitly excludes. No present production caller does that.

Existing evidence for this change is component-scoped: its retained paired probe reports 4.279 to 2.423 ms for one cue's active motion/update batch and 2.770 to 0.221 ms for paused repeated updates; the report also records pixel-exact captures and focused assertions. These measurements are not a full-flight FPS result and were not rerun for this audit.

## Source identity

SHA-256 values from the detached baseline:

These hashes identify the source reviewed for static candidate analysis; the prior WIP timing JSON does not provide matching source hashes.

| Source | SHA-256 |
| --- | --- |
| ../baseline/app/scenery/scenery.gd | d39ddfc864a9b594c94071369524052adf688ee8a2e05ac0e960bd8eef77440c |
| ../baseline/app/scenery/vegetation_placement.gd | d97a3db24d6fa9033109c7f23dabaf028b30e3732ce4dce6b7fc97850fd523b8 |
| ../baseline/app/scenery/imported_vegetation.gd | 57fbf931787e6acd086b39edc7cf9ef89bf21140891ad9076750bb287aed48aa |
| ../baseline/app/scenery/population.gd | 718488305af101b174fbc235a82033de5acf645ab834e65bd5ce753c445b49a8 |
| ../baseline/app/render/windsock.gd | 1665385442fd4a77ce265d2378f5c5cce2642c8c5dd2e96440dfef53dc7018a46 |

The cold-scene investigation changed no application or test source; its findings are retained in this scratch directory.

## Read-only suite runner review

The shell runner scripts were inspected but not executed by this review. The retained `integration.status` says `exit_code=126`; its log records `/usr/bin/sha256sum` and `/usr/bin/timeout` returning WSL Input/output errors before `app/test.sh` starts. This is neither a passing nor a failing application-test result. The scripts also contain two protocol hazards: `prepare_worktrees.sh` creates only shard0–3 while `run_suite.sh` asks for shard4–7, and `run_suite.sh` masks worker failures with `|| true`, ignores all unit-worker wait statuses and ends successfully even when integration fails. `run_partition.sh` writes a per-partition `exit_code`, but its `FINISHED` state and `SCRIPT ERROR` count alone do not imply a successful suite. No test execution or pass claim is made here; audit the replacement native harness's aggregation and coverage before accepting any result.

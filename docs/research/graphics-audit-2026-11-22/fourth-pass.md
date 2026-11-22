# Fourth graphics audit — deeper vehicle, rendering and menu paths

**The strongest new result is a source-bound MONSTER CAR 2 numeric experiment: its combined sampler candidate reduced median paired component time by 19.6–27.7% across two final processes and three workloads, with byte-identical tested outputs.** It is an isolated headless result, not an FPS improvement or a production optimization. The broader audit traces 13 additional items across cars, drones, helicopters, fixed-wing aircraft, Home and authored lighting. Existing optimization work and historical evidence are explicitly credited; U10 is a further trigger investigation for an already-known skyline cost.

All findings and component evidence are pinned to [simulator source `7940a4081e10994f34c858c4acac3d7a1a271464`](https://github.com/bultodepapas/OpenRCsimulator/tree/7940a4081e10994f34c858c4acac3d7a1a271464). During this pass, main advanced to [`c20a074ded808c650b56cb19495d1a42fd12d877`](https://github.com/bultodepapas/OpenRCsimulator/commit/c20a074ded808c650b56cb19495d1a42fd12d877), a website/download/README release update. `graphics-audit` integrates that new main too. Git confirms no changes to app, tools, workflows or native sources; the performance source and measurements therefore remain applicable at their stated scope. The preceding published audit is `b0f0bd17fdc2e2e2944d2cda6765c06bc31f6ac9`. This pass adds reports and an isolated research fixture; application, native implementation, CI configuration and graphics settings are unchanged. U01–U13 are local audit labels, not implementation-track IDs.

## Reports and evidence

| Deliverable | What it contains |
| --- | --- |
| [Ground vehicles and native boundaries](fourth-pass-ground.md) | Native corner geometry, Nitro rig interpolation, repeated state composition and clean grime overlays |
| [Drones and helicopters](fourth-pass-rotorcraft.md) | Impact-cache validation, near-lake grouping, race-wrapper stage projections and OSD refresh work |
| [Fixed-wing gear presentation](fourth-pass-fixed-wing.md) | Repeated retractable poses, F4U sample counts, P-51 actuators and compression/light ordering |
| [Rendering, aircraft lighting and Home](fourth-pass-rendering.md) | Glare Off processing, skyline restarts, lighting budget/release work and per-item inverses |
| [Rig sampler experiment](rig-sampler-experiment.md) | Four-arm design, byte parity, timings, noise, preliminary harness failure and production limits |
| [Raw component evidence](rig-sampler-evidence.json) | All three attempts, manifests, checked logs/verdicts, raw timing blocks and calculations |
| [Current CI receipt](fourth-pass-evidence.json) | Reviewed simulator-source completed run, 28 job states, latest-main website delta and its separate pending run |
| [Reproduction instructions](../../../research/performance/graphics-audit-2026-11-22/README.md) | Offline reducer witness and the isolated numeric experiment |

## Findings and their actual strength

“Source-confirmed” below means the work is reachable under the stated conditions. It does not mean its removal is safe or that it limits FPS. Detailed reports retain call sites, guards, counterexamples and specific validation suites.

| ID | Observed work or question | Smallest candidate / evidence limit |
| --- | --- | --- |
| U01 | An admitted native car body evaluation computes four-corner geometry before the road callback and again inside the kernel | Reuse within the same invocation only, preserving callback/failure/FP semantics. Source-confirmed; no native timing or assembly evidence here. |
| U02 | The Nitro visual sampler prepares 247 track-axis mappings although this manifest has five distinct mappings; its packed result crosses an `Array`-typed helper | Typed helper and shared-coordinate design tested separately and together. Numeric component result measured; full draw, mutable metadata, callbacks and real visual parity unqualified. Continues RCV-37. |
| U03 | Nitro service status reads a composed-state property six to ten times per process frame | Capture one same-call state after eligibility checks. Source-confirmed, narrow change, likely modest; no measured allocation or FPS value. |
| U04 | A clean Nitro vehicle still binds 70 grime overlays at exactly zero dirt/wetness | Controlled GPU comparison of exact-zero detach/restore. Bindings are confirmed; actual passes, zero-alpha shader cost and savings are hypotheses. Existing tests make bindings observable. |
| U05 | Helicopter impact detection validates 56 prepared probes before later empty-world/high-flight rejection | Profile validation separately; consider one native batch or a truly immutable representation. Current mutable-cache refusal behavior forbids simply validating once. |
| U06 | Near-lake helicopter checks regroup the 56 probes and recompute part bounds after the broad-phase gates | Prepare groups only with complete mutation/invalidation semantics. Conditional reference-stage path; ordinary high flight skips it. |
| U07 | The quad race wrapper slices 31 aux and eight mode values and creates a plant context for every RK stage, including IDLE on an installed track | Specialize the verified live built-in plant boundary; retain generic callback slicing, command masking and kernel mutation guards. No stage count or physics rate reduction. |
| U08 | Quad flight angles/heading are computed before the analog refresh return; Off also keeps internal projected state | Separate tracking position from display projection. Analog interframes are the clearest case; Off needs its internal consumer/diagnostic contract preserved. Default HD Freestyle consumes these values. |
| U09 | Zero-intensity glare still reaches source/cloud/skyline work | An explicit Off-path design must preserve or deliberately revise diagnostics, sky-disc occlusion, afterimage recovery and re-enable readiness. Source work confirmed; not a safe blanket early return. |
| U10 | Home preview camera changes can restart the previously documented skyline build when movement exceeds 2 m | Trace actual threshold crossings and preparation cost; investigate reusable immutable geometry or smaller start jobs. This is a continuation, not a newly measured Home stall. |
| U11 | Disabled authored show-effect pools repeatedly release already-empty buffers; unchanged valid owner submissions still reconcile the scene budget | Make release transitions idempotent first; any budget shortcut needs settled-generation and reentrancy proofs. Counts are per helper/apply call, not a universal per-frame cap. |
| U12 | Live or retained spark/trail state inverts the same world-root transform per item | Hoist a stable built-in inverse within the owner update. Two full trails can reach 126 inverses; 252 per-instance setter calls require granted buffers. Neither is a GPU-upload count. |
| U13 | Fixed-wing gear observers reapply unchanged accepted retraction poses: F4U has 17 sampled nodes; a complete P-51 has seven actuator assignments | Cache scene-owned base poses only with generation/invalidation proof; restore sampled oleo bases before light following, then preserve wheel/steer/compression work. Source-confirmed, unmeasured. |

## What is now measured

The isolated sampler fixture uses real pinned rig bytes, 209 tracks, 186 synthetic finite control sets and three candidate arms. Each final process compares **116,622 candidate outputs** against the unchanged sampler, checking both float32 accumulation bytes and serialized transforms. All comparisons passed in both final runs. Three workloads have 12 rotating-order paired rounds, with 18 full numeric batches per arm/block. Median paired reductions were:

- **Packed helper:** 4.7–6.5% of this component's elapsed time.
- **Shared coordinates:** 15.1–21.2%, including changed scratch writes and indexing.
- **Combined:** 19.6–27.7%.

These are ranges across six process/workload summaries, not confidence intervals. The common timing wrapper, scheduler noise, lack of thermal/clock control and headless execution limit extrapolation. The fixture excludes the actual GLB, body/wheel/bell transforms, node setters, scene notifications, renderer, physics and audio. All slow blocks and a preliminary version-format assertion failure remain in the evidence. The [experiment report](rig-sampler-experiment.md) gives raw-derived times and explains why byte parity here does not qualify the complete live draw.

## Native and engine implementation priorities

1. **Advance U02 with its smallest measured change.** A packed-typed helper keeps the current native engine representation/math and avoids a demonstrated conversion boundary. Validate the real visual path and measure it before adding a new extension. Shared coordinates have the larger measured component signal but also a broader ownership contract.
2. **Investigate U01 and U05 as native work with clear attribution.** U01 is already inside C++; avoid duplicate same-invocation geometry if callback and compiler evidence permit. U05 is a candidate for a bounded native validator rather than removal of fail-closed checks. The native car body route is Windows/Linux only here; no corresponding installed native car backend was exercised locally.
3. **Take bounded presentation reuse seriously.** U03's local state snapshot, U12's built-in inverse reuse and U13's scene-owned base poses have smaller change surfaces than rewriting whole vehicles. Measure complete callbacks to determine whether their absolute savings matter. U13 must retain invalid/unavailable actuator fallback as well as ordinary accepted states.
4. **Keep policy-sensitive rendering changes behind explicit equivalence tests.** U04, U09–U11 can change resource bindings, diagnostics, readiness, grants or reentrant behavior. Their source counts justify experiments, not an automatic patch. Resolve first-visible and cleanup costs as well as steady-state costs.
5. **Consider native batching only when the boundary wins.** A C++ rig sampler or contiguous MultiMesh submission must include marshalling, exact arithmetic/format, ownership and buffer fill costs. Preserve float64 physics, 240 Hz sampling and indivisible accepted-tick/checkpoint/rollback behavior. Existing engine calls are native already; moving a small call behind another extension boundary is not inherently faster.

## Cost models and practical decision rules

At 60 FPS the frame budget is 16.67 ms; at 120 FPS it is 8.33 ms. At 240 accepted ticks/s, U05's current 56-probe validator can execute 13,440 probe iterations/s, or 224 per nominal 60 Hz frame with four ticks. That arithmetic identifies a repeated workload; it does not assign a cost to a norm, dictionary lookup or native call.

For U07, one ordinary four-stage tick projects `4 × (31 × 8 + 8 × 8) = 1,248` logical bytes into slices and creates four wrapper dictionaries. At 240 ticks/s this is 299,520 logical payload bytes/s before implementation overhead. Contact substeps multiply the stage count, while refusals shorten it. These are logical payloads, not measured allocations or RSS.

For a measured saving `d` on a frame's limiting serial path, the conditional uncapped FPS relationship is `F_new = 1000 / (T_old - d)`. If the GPU, compositor, display cap or another thread limits the frame, component savings can improve headroom without increasing FPS. Do not add overlapping findings' timings or convert the sampler percentage into a whole-game percentage. Isolate one mechanism, retain a matched baseline, then test the whole callback and presented frame tails.

## Current main and CI

The core run for the audited simulator source `7940a408`, [workflow run 45026329656](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45026329656) is now **completed / success**, updated at **2026-11-22 16:18:32 UTC (11:18:32 Colombia)**. The independently fetched latest-attempt job inventory contains **23 successful jobs and five skipped jobs**. The final `CI required` job succeeded. This resolves the earlier [14:32 UTC snapshot](current-main-and-tests.md), when integration and visual capture lanes were still running; that historical receipt is preserved.

Successful lanes include eight unit shards, integration 0, visual captures, Windows/Linux RC native production checks, Linux/Windows native-kernel qualification, experimental macOS ARM64 source correctness, release builds and Windows package qualification. These are workflow/job observations. This pass did not redownload and independently adjudicate all artifacts, and green CI is not a Windows/Linux/macOS FPS certificate. The prior Windows queue receipt and phase/focus findings remain scoped as documented.

At the later **16:43:35 UTC (11:43:35 Colombia)** observation, latest repository main `c20a074de` had its own [CI run 45044228684](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45044228684) **in progress**, with no final conclusion. The website-only delta does not invalidate the unchanged simulator-source evidence, but the earlier green run is not a green status for this newer commit. The receipt retains both identities.

## Required platform evidence

| Target | Concrete next comparison | Evidence still needed |
| --- | --- | --- |
| Windows | Both cars; sampled and procedural retractable aircraft; quad race/OSD; helicopter high/near-lake; Home/Workshop | Matched actual backend, renderer/API and 1080p physical display; component CPU, allocations where relevant, presented frame p95/p99/max, GPU trace for overlays |
| Linux | Same workloads on physical integrated and discrete GPU hosts where available | Admitted graphical session and focus; native selection versus reference recorded; no transfer from shared compositor or headless component timings |
| Apple Silicon | Native Retina primary comparison plus explicitly separate 1080p diagnostic | Actual native/reference support per vehicle, drawable/internal/output pixels, renderer/API, thermal/power state and presented/GPU timing; experimental source CI does not qualify packaging or FPS |
| Lifecycle / menus | Cold and warm Home selections, field changes, pause/resume, Off→On, layout changes, repeated entry/exit | Time to first presentation, skyline restart count, retained resources, reallocation hitches, fresh diagnostics and no stale transforms |

Use the repository's admitted performance route and existing RCV-37, HELI, OSD, gear, sun and lighting fixtures identified in each report. An unavailable target is an open validation item, not an inferred pass. Previous [measurement-integrity findings](measurement-integrity.md) still require correct focus and phase ownership before phase-attributed FPS claims.

## Research, review and rejected broader claims

Three helpers followed `docs/SUBAGENTS.md` with requested `gpt-6.1-terra` / maximum reasoning in fresh contexts. Effective runtime settings beyond the request remain unverified. Helpers inspected source and drafted bounded evidence; none launched an engine or changed repository files. The lead independently traced critical paths, read primary documentation, owned all six checked fixture invocations, integrated drafts and retained raw evidence. Cross-review was assigned away from each draft's author.

Accepted corrections include mutable helicopter part labels that remain valid, the inner race callable's isolation, Off HUD state consumers, the helicopter CSV/checkpoint versus fixed-wing ORFL distinction, per-call lighting release counts and dead-owner reconciliation, and the F4U compression/light ordering. The proposed public-cache shortcuts were narrowed accordingly. The repeated native gear pose/copy is already D08; Stik linkage solving is already coalesced; cloud transmission has a cache with snapped direction; scene gaze and viewport/shadow paths have guards. Those were not repackaged as new defects.

Primary research used [Godot CPU optimization](https://docs.godotengine.org/en/latest/tutorials/performance/cpu_optimization.html), [Array conversion semantics](https://docs.godotengine.org/en/latest/classes/class_array.html), [material overlays](https://docs.godotengine.org/en/latest/classes/class_geometryinstance3d.html#class-geometryinstance3d-property-material-overlay) and [MultiMesh optimization](https://docs.godotengine.org/en/latest/tutorials/performance/using_multimesh.html), retrieved 22 November 2026. These moving official references support measurement, representation and API choices, not exact pinned-engine allocation counts, driver submissions or platform gains. The executed binary and repository source identities remain the authority for this experiment.

Final local verification checked 30 newly added local links/anchors against staged Git objects with the repository's documentation checker, parsed the new JSON/Python artifacts, verified final probe/reproducer/result identities and checked the staged diff for whitespace errors. The independent evidence reviewer recomputed all timing summaries and faster-pair counts, checked the sole preliminary version-format change, and confirmed zero checked engine diagnostics. No full application suite, rendered GPU comparison or production optimization was run as part of this report-only/research change.

Return to the [audit index](README.md) for the earlier T01–T11/M01–M02 findings and previous passes.

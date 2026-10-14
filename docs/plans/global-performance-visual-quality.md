# Global performance and visual-quality implementation plan

2026-10-14 · Revision 15 · Planning baseline: `70a84ee6` · Godot **4.7.2**, desktop Compatibility.

**Execution decision:** baseline → visibility reference → measured CPU/loading repairs → texture audit → ground and foliage comparisons → targeted aircraft/weather repairs → qualified quality profiles → native acceptance. Implementation has started with **VQ-01c / DT-01 / DT-10a** measurement tools and a read-only texture inventory. [First evidence and unresolved gates](../research/visual-quality-implementation/VQ-01c/README.md) now include an attributed **DT-11a lake geometry reuse repair** with exact buffer parity and faster Home/Fly transitions. Native flight, cold-loading and visual-change acceptance remain open. Current step status stays in the owning VQ plan.

**Scope decision:** six of the 24 brainstorm ideas are selected as bounded probes/refinements; five are conditional, eight deferred and five rejected from this delivery. The three ambitious rendering branches are also rejected from this delivery. A selected probe ends in either a qualified change or a documented **retain baseline** decision. It does not guarantee that its candidate ships.

**Latest DT-11a slice:** [horizon azimuth reuse and index preallocation](../research/visual-quality-implementation/VQ-01c/loading/horizon-build/README.md) reduce mesh construction from 68.721→55.027 ms in five native runs, preserving complete arrays in 40 paired comparisons. Profile validation and normal accumulation stay unchanged. The combined native horizon/atmosphere test reports texture shutdown errors on both reference and candidate; that issue remains open. [Earlier shadow blur](../research/visual-quality-implementation/VQ-01c/loading/shadow-blur/README.md), [shadow geometry](../research/visual-quality-implementation/VQ-01c/loading/shadow-geometry/README.md), [grass masks](../research/visual-quality-implementation/VQ-01c/loading/grass-masks/README.md) and [ground images](../research/visual-quality-implementation/VQ-01c/loading/ground-image/README.md) retain separate evidence. These are construction results, not summed startup or FPS gains. Next: attribute remaining Home/first-Fly costs on a consistent current snapshot and isolate the reproduced texture shutdown issue. Foreground loading, pacing and current-package/native acceptance remain open.

Earlier [grain precomputation and package repairs](../research/visual-quality-implementation/VQ-01c/loading/grain/README.md) retain their own source identity, measurements and export scope; do not pool campaigns.

Follow-up: [duplicate night-kit geometry extraction removed](../research/visual-quality-implementation/VQ-01c/loading/night-kit/README.md), with exact fleet output parity and 123 passing GPU checks. Export conflicts are reconciled with the incoming rotorcraft/grass checks. Exit warnings are narrowed to MP3 audio objects; no audio fix or full-loading acceptance is claimed.

The [audio teardown follow-up](../research/visual-quality-implementation/VQ-01c/loading/audio/README.md) reproduces asynchronous mixer retirement and adds bounded, verified cleanup to the loading probe. Three unchanged-package runs close without exit warnings, including 50 cycles with one paused first draw. Production shutdown, uninterrupted interactive-cycle acceptance and the soak remain open.

This is the authoritative sequence and disposition for the [dated research](../research/godot-global-review-2026-10-14.md). It replaces this document's earlier broad backlog and six-prototype recommendation. Implementation status stays in the owning plans: [VQ](../VISUAL-QUALITY-PLAN.md), [landscape](../LANDSCAPE-PLAN.md), [sky](sky-clouds-weather.md), [UI](../MENU-REDESIGN-PLAN.md), [DT](../DESKTOP-DELIVERY-PLAN.md), [camera](camera-views.md), and the [ownership registry](../README.md#tracks-plans-and-step-ids). New follow-up IDs below are registered in those homes; no new track namespace is introduced.

Latest VQ-02a slice: [embedded-image and runtime texture inventory](../research/visual-quality-implementation/VQ-02a/README.md) inspects 25 embedded PNG/JPEG images and 39 assigned texture resources across the default day world and five fixed-wing families on a frozen source. This is the permitted independent read-only audit; material/import corrections and full VQ-02a qualification remain open.

## 1. Decisions already made

Latest VQ-01d slice: [moving visibility references](../research/visual-quality-implementation/VQ-01d/README.md) add four lossless native clips with the existing pilot camera, matched poses and recorded projected sizes. Capture integrity is verified; background classification, the full matrix and owner orientation/response-time acceptance remain open. Material/camera adoption gates are unchanged.

| Topic | Decision for this delivery | Reason / reopening condition |
| --- | --- | --- |
| Engine and renderer | Keep 4.7.2 and Compatibility; no dependency upgrade | Preserve export, shader and numerical baselines. VQ-07 remains outside this delivery. |
| Performance target | Qualify a 60 Hz profile at 1280×720; compare 1920×1080 separately | DT-01 names actual hardware before any support claim. RTX 3090 evidence is a reference, not a minimum-GPU claim. |
| Ground blending | Try **one Laplacian blend** against current dual-sample detiling, using retained turf | Smaller preprocessing scope than histogram/LUT authoring. If it fails, retain current blending; a second algorithm needs a new finding. |
| Vegetation | Test the existing atlas and alpha-to-coverage first | No replacement library, octahedral addon or custom mip importer in the initial slice. |
| Aircraft | Preserve current materials/livery; repair demonstrated readability or sparkle problems | Film gloss, filtered markings, propeller blur and hinge-glint repairs already exist. |
| Wind and clouds | Compare static windsock against wind-driven foliage; reproduce high-wind cloud stepping | Reuse M5 read-only inputs and FW-81 history. No new weather physics. |
| Quality UI | Balanced retains the current qualified look; Performance ships only with measured benefit | Use VQ-06 and UI-24. No Ultra profile, renderer selector or second preferences system. |
| Assets | Reuse retained maps, trees, aircraft generators and licensed packs | Check free downloadable equivalents before authoring content. No asset-library replacement campaign. |
| Product breadth | No replay UI, ghosts, latency-training mode, photo-field or terrain replacement | These do not repair this delivery's performance/visual acceptance gaps. |

The strongest recorded signals are incomplete full-flight qualification, scenery queries above their 100 µs objective, a small-sample lake-on/off increment, and 4.694 s historical cold full-field construction. They justify attribution, not an assumed current regression. Their scopes remain in [research §3](../research/godot-global-review-2026-10-14.md#3-measurements-that-change-the-priority).

## 2. Contracts and scope boundaries

- Preserve float64 simulation state, 240 Hz timing, RK4 order, input sampling, validation, event identity and checkpoint/trace contracts. Render vectors remain at the presentation boundary. Never re-record goldens for a performance or visual change.
- Keep `airplane`, `propeller` and `*_hinge` names, scale and articulation. Generated geometry/data change through their source pipelines. Livery/LOD cannot change mass, collision or flight forces.
- Graphics profiles use the same collision world and physical weather. Audit existing scenery tiers before connecting them to global profiles. Collidable obstacles remain identifiable in the relevant flying range.
- Preserve physical weather, sky appearance and time-of-day ownership. Pause/reset/restore, failed setup, Workshop and Home/flight replacement retain transactional state boundaries.
- Run measurements alone. Separate checkouts may host independent development, but `main.gd`, `app_root.gd`, shared world state, preferences, imports and exports have one integrator at a time. Recheck Git status; preserve unrelated work, including the Savox plan.
- Research, software verification, native hardware qualification, human acceptance and physical validation are separate. An unavailable hardware/pilot gate cannot be closed by inference.

## 3. Order, dependencies and reviewable deliveries

Each row is a work package. Split instrumentation, implementation and evidence into separate commits where useful; one runtime mechanism per PR. Conditional rows are evaluated in order and explicitly marked **trigger absent / skipped** when appropriate. That is an outcome, not unfinished speculative work.

| Order | Owner step(s) | Deliverable | Depends on | Completion evidence |
| --- | --- | --- | --- | --- |
| 01 | **VQ-01c**, DT-01/10a/10, H | Current package/source manifest, full-session timing, loading phases and failure ledger | None | Comparable unmodified runs; metric semantics, hardware and gaps recorded |
| 02 | **VQ-01d**, L6c, CAM-22 | Aircraft visibility/motion reference | 01 source/camera freeze | Blinded clips, orientation results and pilot findings; no camera-law change |
| 03 | **LU-10-R1**, H | One scenery/lake query repair if 01 confirms the problem | 01 | Oracle/state parity plus full-workload gain; otherwise retain baseline |
| 04 | **DT-11a**, UI/session owners | One dominant loading/first-draw repair if 01 confirms a miss/hitch | 01; remeasure after 03 if shared construction changed | Phase timings, failure/cancel behavior and lifecycle proof |
| 05 | **VQ-02a**, L/model owners | Texture/import inventory and demonstrated import-error corrections | 01, 02; stable 03/04 baseline for timing | Channel/color/filter/provenance checks, memory/load deltas |
| 06 | **L9e-R1**, VQ-02 coordination | Current ground versus one Laplacian blend on retained maps | 02, 05 | Near/far moving day/night review; visual and whole-frame gates |
| 07 | **L6b-R1**, L6c/LU | Existing foliage coverage versus alpha-to-coverage if motion shows a defect | 02, 05 | Coverage/edge/shimmer/cost result on one atlas, including 2×/4× MSAA |
| 08 | **VQ-02b**, aircraft owner/CAM | Conditional marking/skin or metallic-highlight repair | 02, 05; 06/07 for final background comparison | Model/generator checks, orientation result and moving glint review |
| 09 | **L15a/c**, M5 interface owner | Windsock coherence probe; repair demonstrated mismatch | 01, 02 | Same gust, correct direction/calm/lag, bounded geometry, unchanged physics |
| 10 | **FW-81-R1**, FW/TOD | Smooth-cloud probe; repair reproduced stepping | 01, 02; merge after 09 if sharing world/atmosphere code | Continuous motion, bounded radiance, reset/restore/reflection coherence |
| 11 | **LU-22-R1**, L/SC/FW | Conditional one-region shore/material correction | 02, 05, 06; query baseline stable | Pilot/overview agreement and unchanged lake/contact boundary |
| 12 | **VQ-06a**, SC-24, DT-11c | Qualified Balanced/Performance data and apply boundary | 03–11 outcomes recorded | Fixed-preset comparison; same state/collision identity |
| 13 | **VQ-06b**, UI-24, DT-03…05 | Saved graphics settings for qualified controls | 12; **UI-22 and UI-23** precede UI-24 | EN/ES, focus, migration, persistence, Keep/Revert and recovery |
| 14 | **VQ-06c**, DT-02/10/12, L/FW/CAM | Integrated native/package/pilot acceptance | Selected/conditional outcomes; 13 if controls ship | Exact artifact identity, required suites, motion/night flight, lifecycle/platform ledger |

**Parallelism:** after 01, the offline visibility kit can proceed beside CPU/loading attribution. Import inventory can be read-only in parallel. Ground/tree/model development may use separate checkouts after 05; timing and integration stay serialized. UI-22/23 retain their existing parallel UI sequence; this plan does not assume them done. If no new profile/control qualifies at 12, skip graphics UI work at 13 and record that result; other UI obligations remain in their own plan.

**Milestones:** 01–04 establish a measured, numerically unchanged performance baseline; 05–11 produce qualified visual changes or explicit no-change decisions; 12–14 produce safe settings and a flyable package. Re-estimate effort after 01; the earlier speculative day ranges are not a schedule. No conditional branch may expand into a new subsystem without revising scope.

## 4. Measurement and acceptance contract

### Baseline protocol

Use the available native Windows workstation first for development comparisons; DT-01 records its actual CPU/GPU/driver. The M1-class 8 GB Mac and native Linux remain qualification targets when available, not assumed passes. Name supported hardware/output profiles before acceptance. Missing hardware permits independent development but leaves that platform unqualified.

Record commit/dirty-file hashes, engine/package hashes, aircraft/field identity, seed, physical/visual weather, camera/FOV/aid state, output/internal resolution, MSAA, VSync/cap, refresh rate, power mode and background load. Retain raw samples, failed runs and observer overhead. Measure instrumented attribution separately from release exports.

| Workload | Minimum coverage |
| --- | --- |
| Complete fixed-wing flight | Stik circuit/takeoff/contact, P-51 high-load flight, electric Timber route; basic route for other enabled catalog aircraft. Keep aircraft distributions separate. |
| Shared-family regressions | Helicopter/Bisonte initialization/reset/camera/world when shared files change; performance reported separately |
| Collision attribution | Empty/near car/tree/fence, bin edge, grazing/tied hit, fast rotating hull, shoreline crossing and airborne over lake |
| Rendering/readability | Pilot normal/zoom, trees/horizon/cloud crossings, close pass, supported chase/orbit; 720p/1080p |
| Conditions | Day/dusk, moonlit/moonless night, strongest qualified sky/storm, smoke and shadows; transient peaks separate |
| Startup/lifecycle | Process launch → Home usable → Fly request → first validated interactive frame; Workshop; pause/reset/failed setup/return Home |

Steady runs use **10 s warmup + 60 s sample**, at least **three alternating baseline/candidate pairs** on one idle host. Extend cases that miss periodic updates. Test intended VSync/cap and separate uncapped diagnosis; image readback stays outside timing. Existing short turf/scene probes remain attribution tools.

For loading, retain at least five fresh-process and five warm in-process repetitions, with distributions and phase boundaries. Distinguish process-cold, import-cold and driver-cache conditions; a fresh process does not establish a cold GPU cache. Do not erase global user caches.

Existing `bench_regimes.gd` batches `sim.step()` rather than the complete input/FlightSession/collision route. The lake bench has four warmup and twenty measured steps at one airborne point. The scripted frame logger is not a full-flight replay or an input-to-photon measurement. **VQ-01c adds only the missing bounded complete-session workload and per-tick data before extrapolating these tools.** Preserve historical outputs/semantics.

### Gates to freeze in VQ-01c

These are targets, not achieved measurements. Keep stricter owning-track limits; report misses without silently weakening them.

| Gate | Required result |
| --- | --- |
| Frame pacing | DT 60 Hz process-loop targets: p95 ≤18 ms, p99 ≤25 ms; simulation/wall ratio 0.99–1.01. Assess uncapped throughput separately against 16.67 ms. Attribute repeatable gameplay intervals >50 ms. |
| Physics/query cost | Preserve 500 µs/tick Gate P and its regime/statistic definition. Disclose complete-session overhead; nearby-query objective remains 100 µs. Neither is extra budget. |
| Optimization adoption | Gain exceeds paired-run variation and reaches 5% of the affected complete workload, or removes a named reproducible hitch/memory defect. Include worst cases; reject repeatable harmful tradeoffs. |
| Added visual cost | Allocate measured headroom before implementation. Initial ceiling for **all new visual work combined**: +0.5 ms frame-p95 on the qualified target, while the whole-profile gate passes. Not +0.5 ms per effect. |
| Loading | Home ≤5 s process-cold / ≤3 s warm; Fly ≤2 s. If staging is needed, aim for ≤100 ms main-thread slices. Never start flight before validation/readiness. |
| Correctness | Existing oracle/trace/checkpoint contracts pass on the pinned runtime; exact where already promised, established tolerance elsewhere. No new goldens or relaxed guards. |
| Visibility | No new repeatable loss of subject, orientation or landing cue in fixed clips and owner circuit. Compare orientation accuracy/response time; small samples are acceptance evidence, not population statistics. |
| Lifecycle | No unexplained growth after warmup in 20 Home/Fly/Workshop/reset cycles; caches bounded by bytes/count and invalidation. DT-12 separately requires **50 Home/flight cycles and a 30-minute soak**. |
| Resources | Retain LU's 650k source-geometry cap and provenance checks. Record visible primitives/textures/VRAM separately. No unsupported minimum VRAM claim. |

Visibility uses two existing aircraft with contrasting appearance, fixed flight/camera inputs, 20/50/100 m plus the existing farther acceptance range, sky/tree/cloud backgrounds and day/dusk/night coverage. Randomize A/B order and repeat uncertain comparisons. Log projected span/chord, FOV, zoom and assistance; detecting a dot and recognizing attitude are different. Extend L6c/CAM kits. Gate L/2/FW acceptance still needs an actual owner flight.

## 5. Work-package specifications

### VQ-01c / VQ-01d — reproducible decisions

**Files:** extend [frame samples](../../app/render/frame_samples.gd), [visual cases](../../app/tests/visual_quality_cases.py), relevant benchmarks and existing capture manifests. Instrument [FlightSession](../../app/sim/flight_session.gd) only where needed, without another simulation route. Offline reducers stay outside `app/`; GDScript added inside must parse first.

**Deliver:** workload/run manifests, per-tick versus batch definitions, loading phases, full-session coverage, failure ledger and paired clips. Add projected-size/aid metadata instead of another HUD or zoom algorithm. Future evidence belongs under `docs/research/visual-quality-implementation/VQ-01c/` and `VQ-01d/`; these are planned outputs. Link DT hardware evidence rather than copying it.

**Exit:** another developer can reproduce the baseline with documented existing tools plus the newly delivered harness; observer overhead is known. Attribute inherited failures by source identity and owner, never by rewriting expected results.

### LU-10-R1 — one query mechanism per patch

**Files:** [collision world](../../app/scenery/collision_world.gd), [session collision](../../app/sim/scenery_collision.gd), affected lake/contact code and oracle fixtures. Attribute bin lookup, candidates, rejection, sweeps, ties and post-step work. Broadphase reuse and vertical rejection already exist.

Try conservative rejection or per-tick immutable preparation first. No persistent motion cache, worker-owned simulation state or native flight kernel in this slice. Preserve earliest hits and stable-ID tolerance ties through rotation, grazing and shoreline cases.

**Exit:** same-world state/oracle parity, failed-step/restore/reset behavior and complete-workload gain. If the cause is elsewhere, retain this code and route a narrow attributed H repair; do not optimize the wrong function to satisfy a row.

Any Gate P miss outside scenery/lake queries becomes a separately registered H-owned corrective step with its own evidence and scope decision after VQ-01c attribution. It is not silently added to LU-10-R1. Independent visual work may continue, but VQ-06c performance acceptance stays open until the required Gate P cases pass; an inherited failure is still a failure.

### DT-11a — dominant startup phase only

**Files:** [AppRoot](../../app/app_root.gd), [field builder](../../app/render/field.gd), world/scenery builders and UI loading boundary. Current synchronous creation restores Home on failed setup; preserve it unless measured cost requires staging.

Choose one route: immutable resource reuse for repeated setup; threaded requests for measured I/O; detached pure-data preparation for measured construction; bounded visible warmup for reproduced OpenGL first-use stalls. Do not build all four. Staging requires generation-token cancellation, late-result disposal, isolated candidate state and main-thread scene attachment; those are new coverage requirements.

Implemented within the resource-reuse route: bounded CPU arrays for repeated setup,
then a generated default-lake resource for fresh processes. The [cold-loading follow-up](../research/visual-quality-implementation/VQ-01c/loading/cold/README.md)
records exact procedural parity, input/version fallback, paired timings and the limited
export check. Cold Home and first Fly still miss their targets; attribute the remaining
phases before selecting another repair. No asynchronous lifecycle was introduced.

**Exit:** cold/warm phase distributions, preserved direct/capture/trace start semantics, failed/cancelled setup, no sky/exposure leak and bounded retention. Use existing field-failure checks; add stale/cancel tests only when introducing those behaviors.

### VQ-02a / L9e-R1 — imports before ground blending

**Files:** import metadata, [ground shader](../../app/render/ground.gdshader), [grass sampling](../../app/render/grass_surface.gdshaderinc), [turf detail](../../app/render/turf_detail.gdshaderinc) and [ground tools](../../tools/ground/README.md). Inventory ordinary, embedded GLB, atlas and generated textures: dimensions, channels, color space, mips/filter, compression, resident estimate, consumers and provenance.

Fix demonstrated metadata errors individually. Albedo and linear slopes/roughness/masks have different policies. No blanket sRGB, lossy data compression or 4K upgrade. Keep packed turf lossless unless error is qualified; preserve scale and normal orientation.

Then compare current dual-sample blending with one Laplacian candidate using retained turf. Preserve `textureGrad` footprints, masks/discard order, macro variation, haze and runway cues. Sampling stays offset-only, so idea 06 adds no standalone task. Check contrast across mips and motion. If cost or blotches fail the gate, retain the current ground; do not automatically try a histogram/LUT pipeline.

### L6b-R1 — one atlas, not a vegetation rewrite

**Files:** [treeline shader](../../app/render/treeline.gdshader), its material setup and [tree tools](../../tools/trees/README.md). Imported LU vegetation is a separate family. Reproduce coverage/shimmer first, then compare alpha compensation with alpha-to-coverage, including scissor/antialiasing-edge interaction and MSAA Off/2×/4×.

Keep a valid baseline edge mode with MSAA off; profiles cannot select incompatible combinations. Inspect day/night, camera orbit, transitions and projected shadows. Correct historical documentation after the native probe. Custom mips are deferred: normal PNG imports regenerate them, so a separate preservation/import proof is required. No custom importer here.

**Exit:** motion benefit without density shifts, concealed obstacles, atlas bleed or cost regression; otherwise retain baseline. Chunk/LOD tuning requires an attributed bottleneck and a separate patch.

### VQ-02b — conditional aircraft repair

**Trigger:** VQ-01d attributes orientation errors to markings, or a moving P-51 clip shows sparkle after VQ-02a. Choose the matching intervention: at most two existing/licensed orientation schemes; smooth suppression of narrow markings preserving broad blocks; or one material's modest roughness-floor A/B. Separate PRs if multiple interventions are justified.

**Files:** only the selected model's shader/material/source generator and verification, following the [aircraft registry](../README.md#tracks-plans-and-step-ids). No skin-selection product, mesh scaling, generic clearcoat or fleet rewrite. Preserve articulation, Home preview, crash copy and stopped propeller.

**Exit:** targeted visual/flight benefit with no worse silhouette/orientation or plastic-looking metal. Keep the original default scheme unless evidence supports replacement. No qualifying symptom means explicitly skipped.

### L15a/c / FW-81-R1 — separate motion repairs

**Windsock:** [windsock](../../app/render/windsock.gd), field attachment and existing M5 presentation seam. Vegetation already shares wind. Compare cloth/foliage on one supported gust; add bounded render-only sock response only if needed. Check cardinal direction, calm and conservative bounds. Reuse visual time; no wind solver or fabric-calibration claim.

**Clouds:** [cloud transport](../../app/render/weather/cloud_transport.gd), [atmosphere](../../app/render/atmosphere.gd), [World](../../app/render/world/world.gd) and sky tests. Reproduce high-wind stepping, then test deterministic visual interpolation without changing physical weather/history. Do not simply update uniforms every frame: measure radiance, ground shadows and reflection coherence.

**Exit:** calm/zero-feature controls, cardinal movement, pause/resume, time jumps, scene replacement and restore pass; same-seed captures repeat on the same GPU path. If smoothing requires another renderer or exceeds budget, retain bounded transport and record its limitation.

### LU-22-R1 — conditional shore using existing data

**Trigger:** VQ-01d/L9 review confirms a specific discontinuity in both pilot-height motion and overview. An older screenshot preference alone is insufficient.

**Files:** [bank shader](../../app/render/lake/bank.gdshader), existing terrain/water inputs and source pipeline. Trial one dry/damp/shallow transition using current boundary/depth and retained maps. A local semantic mask is allowed only if existing field inputs cannot express the diagnosed region. No field-wide schema/editor or weather history.

**Exit:** aligned visual/contact shore, no artificial uniform ring, stable grazing-angle depth/transparency and accepted cost. No water physics, wet friction or fluid solver. Skip if current materials pass.

### VQ-06a/b — qualified presets, one settings path

Define pure validated profile data and a presentation-only apply boundary. A module such as `app/render/quality_profile.gd` is **proposed**, not implemented; placement follows the existing UI registry boundary. Reuse SC-24 tiers after checking obstacle visibility and collision identity.

| Setting | Balanced | Performance candidate | Rule |
| --- | --- | --- | --- |
| Renderer | Current Compatibility | Same | No migration selector |
| MSAA | Current 4× | Test 2× first; retain 4× if readability suffers | Valid alpha-edge pairing |
| Output/3D scale | Current qualified values | Preserve aircraft resolution first | Display resolution stays explicit, never adaptive |
| Distant detail/decoration | Current accepted values | Only measured cheaper variants | Same colliders, landmarks and obstacle silhouettes |
| Sky/shadow/water cadence | Current qualified behavior | Individually qualified reductions only | Same clocks/events and visible hazards |
| Textures | Current qualified imports | Same for this slice | No live reimport, streaming or duplicate resident sets |
| Physics | Unchanged | Unchanged | No profile-specific simulation controls |

Performance must pass timing/readability against Balanced on named hardware. Publish qualified controls only. UI-24 owns Settings/schema migration; preserve calibration, invalid/future/unwritable-file handling, direct automation behavior and preferences. UI-23/DT own display/DPI/Keep-Revert, including the 15 s wall-clock timeout and no automatic flight resume. No parallel config or duplicate controls.

### VQ-06c — integrated delivery

Run required checks once the integrated diff stabilizes, then export from an isolated checkout: the current script recreates `dist/`. DT-08/08a own future staging/provenance changes; do not mix packaging redesign into shader work. Retain/test exact package hashes rather than rebuilding tested bytes.

Fly the accepted ground/trees/clouds/settings together, including night/flash intervals and bright/dark aircraft. Roll back a failing change individually. Run 20-cycle resource checks; DT-12 claims additionally need its 50-cycle/30-minute protocol. Signing/installers/notarization remain separate desktop deliverables, not hidden requirements of this visual slice.

Close VQ-06c only after the required performance gates pass, including any H-owned Gate P correction identified by VQ-01c. Record partial visual acceptance separately if that dependency remains open.

## 6. Verification entrypoints

[TOOLS](../TOOLS.md) owns setup/commands. Existing tools below are runnable; missing full-session, cancellation and settings coverage must be delivered with its ticket. Native rendering needs a display. Check engine errors as well as exit codes.

```powershell
# Repository root; exact installed pinned native binary.
$GodotWindows = 'C:\Tools\Godot_v4.7.2-stable_win64_console.exe'
& $GodotWindows --headless --path app --editor --import
& $GodotWindows --headless --path app --audio-driver Dummy --script res://tests/test_simulation.gd
& $GodotWindows --headless --path app --script res://tests/benchmark_landscape_collision.gd
& $GodotWindows --headless --path app --script res://tests/bench_lake_session_airborne.gd
```

The last two are attribution probes, with the limits above. On WSL/Linux obtain the executable with `"$(app/get-godot.sh)"`; the downloader itself is not Godot. Bash suites run in an isolated Linux-filesystem checkout per TOOLS.

| Change | Existing focused checks / authoritative capture home |
| --- | --- |
| Timing/visibility | `test_frame_samples.gd`, `test_visual_quality_cases.py`, `test_camera_math.gd`, `test_camera_views.gd`, `test_camera_route.gd`; [VQ-01b protocol](../research/visual-quality-implementation/VQ-01b/README.md), [L6c kit](../research/visual-quality-implementation/L6c/README.md) |
| Queries | `test_landscape_collision_oracle.gd`, `test_landscape_collision_session.gd`, `test_landscape_collision_world.gd`, `test_lake_collision.gd`, `test_lake_session.gd`, `test_lake_ground_contact.gd`; [landscape tools](../../tools/landscape/README.md) |
| Loading | `test_field_failures.py`, Home/aircraft/pause/flight-capture tests, affected Workshop/sky routes; new stale/cancel coverage only if staging is introduced |
| Ground/imports | `test_ground_surfaces.gd`, `test_ground_terrain.gd`, `test_landscape_ground_lu18.gd`; [ground tools](../../tools/ground/README.md) |
| Foliage/wind | `test_treeline.gd`, `test_tree_assets.gd`, `test_tree_wind.gd`, `test_windsock.gd`, `test_landscape_tree_bounds.gd`; [tree tools](../../tools/trees/README.md), LU vegetation checks |
| Clouds | `test_cloud_transport.gd`, `test_sky_checkpoint.gd`, `test_sky_routes.gd`, `test_world_sky.gd`, `test_sky_render.gd`; [atmosphere](../../tools/atmosphere/README.md) and [world](../../tools/world/README.md) tools |
| Presets/UI | `test_scenery_build.gd`, existing UI input/pause/Home/language checks; new VQ-06/UI-23/24 migration, rollback, capability, state/collision parity and recovery coverage |
| Integration | `app/test.sh`, applicable `research/test-tools.sh`, schema/generator/CI checks, `app/capture.sh`, isolated `app/export.sh`; native packaged execution remains separate |

Capture stills/motion with the same pose/time/seed/resolution. Keep readback/recording overhead outside timing. Runtime integration gets affected checks plus required complete suites; broaden only for a relevant change, failure or unresolved concern.

## 7. Implementation control and rollback

Before each ticket: re-read owner status and Git state, freeze baseline, choose one mechanism, list owned/shared paths, declare the defect/budget and exact verification route. Draft scripts stay outside `app/` until they parse. Preserve source/asset/license hashes through regeneration.

Reports record baseline/candidate identity, trigger, mechanism, commands, raw outputs, variation, visual verdict, numerical contracts, limitations and **adopt / retain baseline / trigger absent**. Evidence lives in the owning step hierarchy; no second global benchmark archive. Missing optional branches do not block unrelated work.

Rollback restores code with its source/import/generated outputs as one change. Remove rejected experimental branches/switches. Accepted settings retain restore-default behavior. Do not keep duplicate unqualified shaders, a global scene cache or a silent physics fallback to avoid deciding.

| Risk | Required response |
| --- | --- |
| Instrumentation changes cost | Measure overhead; use release exports for user-facing results |
| Early/tied contact changes | Reject; fix against the oracle before timing again |
| Staged setup leaks state | Keep accepted scene until candidate validates; generation guard and late-result cleanup |
| Better still, worse flight | Motion/pilot result wins; revert |
| Alpha coverage depends on MSAA | Validate combination; keep baseline edge mode |
| Smooth sky refreshes radiance continuously | Measure and reject if the combined gate fails |
| UI dependency unfinished | Keep internal data separate; never ship a second settings system |
| Hardware/pilot unavailable | Continue independent work; external gate stays unqualified |

## 8. Completion and immediate next action

**Continue VQ-01c:** the complete-callback CPU probe, strict native reducer and first Windows source observations now exist. Resolve the [recorded gaps](../research/visual-quality-implementation/VQ-01c/README.md#remaining-acceptance-and-next-implementation-action): foreground native pacing, CPU variance/observer cost, cold Home/first Fly loading, flight coverage and package identity. The actual Home/Fly probe and first before/after samples now exist. VQ-01d follows on the qualified source/camera identity. DT-11a delivered the first narrow runtime repair: [bounded lake geometry reuse](../research/visual-quality-implementation/VQ-01c/loading/README.md). The measured construction bottleneck justified this independent loading repair while query/visibility qualification stays open; no LU-10-R1 query change was adopted. The read-only import inventory may proceed independently; no material candidate is accepted by inventory alone.

Complete means selected probes have outcomes, conditional triggers are resolved, adopted work passes combined correctness/performance/readability gates, qualified controls have safe persistence/recovery, and the native/pilot ledger names accepted platforms/profiles. Missing external acceptance stays open; documents/ZIPs cannot close it. Deferred/rejected ideas are not completion requirements. No implementation step is marked complete by this revision.

When fulfilled or superseded, consolidate accepted behavior/decisions into owner guides, retain dated research/evidence and remove this coordination plan under repository conventions.

## 9. Exploratory prototypes from the second research round

Binding disposition of the [24 research ideas](../research/godot-global-review-2026-10-14.md#9-second-research-round-creative-directions): **Selected** = bounded probe/refinement with gated adoption; **Conditional** = starts on stated evidence; **Deferred** = later scope, no implementation time here; **Rejected** = deliberately excluded, reopening needs a new scoped decision rather than an automatic fallback.

| Idea | Decision | Application / reopening condition |
| --- | --- | --- |
| 01 Visibility laboratory | **Selected** | VQ-01d first; extend L6c/CAM evidence, no camera algorithm |
| 02 Orientation liveries | **Conditional** | VQ-02b after marking-related errors; at most two existing/licensed/source-pipeline schemes |
| 03 Marking detail by projected size | **Conditional** | VQ-02b for demonstrated narrow-detail aliasing/disappearance; preserve broad scheme/geometry |
| 04 Calmer circuit background | **Deferred** | L6c/SC: repeated clutter-related failure after material work; fixed-world art treatment |
| 05 Ground contrast blend | **Selected** | L9e-R1: current versus one Laplacian candidate; histogram/LUT not an automatic second trial |
| 06 Rotated normal handling | **Rejected** | No rotation is selected, so no current defect. Correct transforms become a requirement only if a future design adds rotation |
| 07 Foliage coverage | **Selected** | L6b-R1: motion diagnosis then alpha-to-coverage if useful; custom mip import out of scope |
| 08 Metallic sparkle | **Conditional** | VQ-02b after persistent P-51 motion defect survives import/filter review; one material |
| 09 Additional clearcoat | **Rejected** | Existing gloss has no established missing lobe; extra glare/scope unjustified |
| 10 Damp/wet/puddle history | **Deferred** | FW/L: requested wet-ground scenario and explicit appearance contract, never implied tire physics |
| 11 Semantic masks | **Conditional** | LU-22-R1 for one diagnosed region current inputs cannot describe; no general editor/schema |
| 12 Shore material zones | **Conditional** | LU-22-R1 after pilot/overview confirms a defect; reuse boundary/depth |
| 13 Windsock coherence | **Selected** | L15a/c same-gust comparison; repair demonstrated mismatch, reuse foliage response |
| 14 Authored cloud map | **Deferred** | FW: nine current profiles first fail a named composition/readability requirement |
| 15 Smooth clouds | **Selected** | FW-81-R1 after stepping reproduction; deterministic history and bounded radiance |
| 16 Regional palettes | **Deferred** | L/FW: requested regional preset with references and existing assets |
| 17 Octahedral trees | **Deferred** | L/LU: residual tree bottleneck after current LOD/batch tuning; pinned addon/backend/export proof |
| 18 Elevation skyline | **Deferred** | L12/L13: real-field/horizon need, licensed crop/datum/seam; never runway/contact truth |
| 19 Photo-field hybrid | **Rejected** | Moving cameras/dynamic lighting conflict; only separate fixed-eye scenario can reopen |
| 20 Preserve aircraft resolution | **Selected** | VQ-06a compares a cheaper fixed background after timing; only qualified controls ship |
| 21 Orientation-loss debrief | **Deferred** | CAM/HUD: repeated actionable losses and offline video/trace value before product UI |
| 22 Previous-flight ghost | **Rejected** | Large replay/training dependency, outside graphics/performance repair |
| 23 Audio reacquisition | **Deferred** | AUD/CAM: named failure with current listener policies; existing audio acceptance first |
| 24 Deliberate latency exercise | **Rejected** | Different training feature confounding response diagnosis; retain physical latency measurement |

All three ambitious branches are **rejected from this delivery**: traversable volumetric clouds (needs explicit in-cloud requirement and separate VQ-07/FW study), split-resolution aircraft/background (depth/transparency/occlusion complexity), and a spotting contour (assistance semantics; no recovery of attitude information). Each needs a new decision based on an unresolved need before reopening.

First-draft topics also have dispositions: renderer migration and terrain addons are deferred to VQ-07/L12/L13; native flight kernels require a separate Gate P finding; SSAO/glow/native shadow maps wait for an existing contact/night gate to identify a gap; frame-history rings/HUD micro-optimization, broader caches, chunk retuning and reflection-cadence changes require attribution. They are not an unlimited backlog or prerequisites for this program.

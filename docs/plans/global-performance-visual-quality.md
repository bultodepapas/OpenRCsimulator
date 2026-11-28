# Performance and visual-quality acceptance

VQ-01c/d and DT own the measurement and moving-aircraft evidence used to qualify a graphics or performance change. Use the [roadmap](../../ROADMAP.md) for project priorities, the [optimization register](optimization-priorities.md) to select a discriminating experiment and the [dated implementation records](../research/visual-quality-implementation/) for results tied to a particular build.

## Scope and display target

Normally qualify 1920×1080 first, higher resolutions second and 1280×720 last. On Apple Silicon with a built-in or external Retina (2×) display, use native display pixels for fullscreen output and the 3D result after MetalFX where available. Record the actual output, drawable and internal 3D pixels, renderer and flight backend. [Apple campaign](apple-silicon-performance.md#campaign-protocol-and-acceptance-budgets)

Keep the fixed 240 Hz float64 simulation, input sampling, validation, accepted event order and replay contracts. Graphics profiles share physical weather, collision geometry and identifiable obstacles. Preserve generated aircraft node names, scale and articulation, licensed asset provenance, pause/reset/restore, failed setup and world replacement boundaries. [Runtime contracts](../STACK.md)

## 3. Order, dependencies and reviewable deliveries

The following dependencies apply within this visual-quality delivery. Project-wide scheduling belongs to the [roadmap](../../ROADMAP.md). Split instrumentation, implementation and evidence into separate commits where useful; one runtime mechanism per PR. Conditional rows are evaluated in order and explicitly marked **trigger absent / skipped** when appropriate. That is an outcome, not unfinished speculative work.

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

Read-only import inventory and visibility capture preparation can proceed alongside CPU/loading attribution. Run paired timings serially. Exclude conditional controls when their underlying change fails qualification.

## 4. Measurement and acceptance contract

### Baseline protocol

Use the available native Windows workstation first for development comparisons; DT-01 records its actual CPU/GPU/driver. The M1-class 8 GB Mac and native Linux remain qualification targets when available, not assumed passes. Name supported hardware/output profiles before acceptance. Missing hardware permits independent development but leaves that platform unqualified.

Record commit/dirty-file hashes, engine/package hashes, aircraft/field identity, seed, physical/visual weather, camera/FOV/aid state, actual output/drawable/internal resolution, effective flight backend, MSAA, VSync/cap, refresh rate, power mode and background load. Retain raw samples, failed runs and observer overhead. Measure instrumented attribution separately from release exports.

For intermittent stutters and FPS drops, reuse the existing [PT1h-R15 frame captures](../../tools/debug/README.md#frame-pacing-and-stutter-captures-pt1h-r15).
The [stutter-diagnostics subplan](stutter-diagnostics.md), informed by [24 investigations](../research/release-readiness/PT1h-R15/research-2026-11-19.md),
sequences provenance/freshness, bounded incident collection and comparable-run analysis.
The watch collects callback incidents and can split valid intervals into eight engine phases. Periodic
engine monitor maxima and last-read GPU values do not establish same-frame CPU/GPU
attribution or displayed pacing. This plan retains the product gates below.

| Workload | Minimum coverage |
| --- | --- |
| Complete fixed-wing flight | Stik circuit/takeoff/contact, P-51 high-load flight, electric Turbo Lumber Evolution route; basic route for other enabled catalog aircraft. Keep aircraft distributions separate. |
| Shared-family regressions | Helicopter/Bisonte initialization/reset/camera/world when shared files change; performance reported separately |
| Collision attribution | Empty/near car/tree/fence, bin edge, grazing/tied hit, fast rotating hull, shoreline crossing and airborne over lake |
| Rendering/readability | Pilot normal/zoom, trees/horizon/cloud crossings, close pass and supported chase/orbit at the applicable display target above |
| Conditions | Day/dusk, moonlit/moonless night, strongest qualified sky/storm, smoke and shadows; transient peaks separate |
| Startup/lifecycle | Process launch → Home usable → Fly request → first validated interactive frame; Workshop; pause/reset/failed setup/return Home |

Steady runs use **10 s warmup + 60 s sample**, at least **three alternating baseline/candidate pairs** on one idle host. Extend cases that miss periodic updates. Test intended VSync/cap and separate uncapped diagnosis; image readback stays outside timing. Existing short turf/scene probes remain attribution tools.

For loading, retain at least five fresh-process and five warm in-process repetitions, with distributions and phase boundaries. Distinguish process-cold, import-cold and driver-cache conditions; a fresh process does not establish a cold GPU cache. Do not erase global user caches.

Report the exact timer boundary. A `bench_regimes.gd` batch, a lake probe at one airborne point, a complete flight callback including observers, and a rendered frame answer different questions. The [Gate P record](../research/simulation-state/Gate-P/README.md) defines its regimes and 120-tick batch statistic. Retain individual tick tails separately.

### Gates to freeze in VQ-01c

These are targets, not achieved measurements. Keep stricter owning-track limits; report misses without silently weakening them.

| Gate | Required result |
| --- | --- |
| Frame pacing | DT 60 Hz process-loop targets: p95 ≤18 ms, p99 ≤25 ms; simulation/wall ratio 0.99–1.01. Assess uncapped throughput separately against 16.67 ms. Attribute repeatable gameplay intervals >50 ms. Physical scanout and input-to-photon latency require separately aligned display and input observations. |
| Physics/query cost | Preserve 500 µs/tick Gate P and its regime/statistic definition. Disclose complete-session overhead; nearby-query objective remains 100 µs. Neither is extra budget. |
| Optimization adoption | Gain exceeds paired-run variation and reaches 5% of the affected complete workload, or removes a named reproducible hitch/memory defect. Include worst cases; reject repeatable harmful tradeoffs. |
| Added visual cost | Allocate measured headroom before implementation. Initial ceiling for **all new visual work combined**: +0.5 ms frame-p95 on the qualified target, while the whole-profile gate passes. Not +0.5 ms per effect. |
| Loading | Home ≤5 s process-cold / ≤3 s warm; Fly ≤2 s. If staging is needed, aim for ≤100 ms main-thread slices. Never start flight before validation/readiness. |
| Correctness | Existing oracle/trace/checkpoint contracts pass on the pinned runtime; exact where already promised, established tolerance elsewhere. No new goldens or relaxed guards. |
| Visibility | No new repeatable loss of subject, orientation or landing cue in fixed clips and owner circuit. Compare orientation accuracy/response time; small samples are acceptance evidence, not population statistics. |
| Lifecycle | No unexplained growth after warmup in 20 Home/Fly/Workshop/reset cycles; caches bounded by bytes/count and invalidation. DT-12 separately requires **50 Home/flight cycles and a 30-minute soak**. |
| Resources | [LU-34](../research/landscape-upgrade/LU-34/README.md) replaces the pooled source-geometry cap: drawn primitives/draws per view class and subsystem, shadow casters, full-detail meshes and texture memory (`tools/scenery/budget.sh`), plus per-subsystem source allowances. Keep provenance checks. No unsupported minimum VRAM claim. |

Visibility uses two existing aircraft with contrasting appearance, fixed flight/camera inputs, 20/50/100 m plus the existing farther acceptance range, sky/tree/cloud backgrounds and day/dusk/night coverage. Randomize A/B order and repeat uncertain comparisons. Log projected span/chord, FOV, zoom and assistance; detecting a dot and recognizing attitude are different. Extend L6c/CAM kits. Gate L/2/FW acceptance still needs an actual owner flight.

## 5. Work-package specifications

The package table above defines the query, loading, texture, foliage and weather work. For CPU/query changes, compare earliest hit, stable tie ordering, failed tick/restore and whole-session cost on the same world. For loading, measure validated interactive readiness as well as phase time. Preserve cancellation and fail-closed startup. Compare ground/foliage candidates at matching texture footprints, light, camera and MSAA, including motion and MSAA off. Use the [collision checks](../../tools/landscape/README.md), [texture inventory](../research/visual-quality-implementation/VQ-02a/README.md) and [loading evidence](../research/visual-quality-implementation/VQ-01c/loading/README.md).

### VQ-02b — conditional aircraft repair

**Trigger:** VQ-01d attributes orientation errors to markings, or a moving P-51 clip shows sparkle after VQ-02a. Choose the matching intervention: at most two existing/licensed orientation schemes; smooth suppression of narrow markings preserving broad blocks; or one material's modest roughness-floor A/B. Separate PRs if multiple interventions are justified.

**Files:** only the selected model's shader/material/source generator and verification, following the [aircraft registry](../README.md#tracks-plans-and-step-ids). No skin-selection product, mesh scaling, generic clearcoat or fleet rewrite. Preserve articulation, Home preview, crash copy and stopped propeller.

Future per-build color/decal and show-effect controls belong to [AE-24](aircraft-editor.md#5-planned-player-facing-work), with AS model bindings and SM rendering. They are separate product work; this conditional VQ repair keeps its current scope and acceptance gates.

**Exit:** targeted visual/flight benefit with no worse silhouette/orientation or plastic-looking metal. Keep the original default scheme unless evidence supports replacement. No qualifying symptom means explicitly skipped.

### Weather and shore

Compare windsock and foliage under the same gust and calm controls. For cloud stepping, keep deterministic visual time and measure radiance, ground-shadow and reflection coherence through pause/reset/restore. Trial a shore transition only for a visible discontinuity confirmed in pilot-height motion and overview. Keep water contact and lake boundaries unchanged.

### Settings and integrated delivery

Use existing settings, persistence and recovery. Validate manual overrides, migration, invalid/unwritable preferences, language/focus, display Keep/Revert and distinct ground, vegetation, lighting, shadows, reflections and effects controls. A disabled feature should avoid unnecessary work and allocations. Check CPU, GPU, RAM and VRAM where measurable at every qualified tier, including maximum. The [Automatic graphics plan](automatic-graphics.md) owns initial recommendations and the [dynamic-resolution plan](dynamic-resolution.md) owns adaptation and restoration.

Fly the combined changes, including dusk/night, bright/dark aircraft, close passes and distant horizon crossings, on the exact package. Run lifecycle and moving-aircraft checks at the target display. Record per-platform results, exceptions, and pilot findings; VQ-06c closes only when all applicable performance gates, including any Gate P dependency, pass.

## Verification and rollback

Use the [tool index](../tools/README.md) for checked execution, the [performance guide](../../research/performance/README.md) for capture commands and the [hardware tour](../../tools/godtest/PERFORMANCE_TOUR.md) for product routes. Inspect [VQ-01c](../research/visual-quality-implementation/VQ-01c/README.md) for capture limits and [VQ-01d](../research/visual-quality-implementation/VQ-01d/README.md) for visibility references. Record each candidate, comparison, controls and adopt/retain/skip decision in the owning investigation. Roll back the failed mechanism and its generated outputs together.

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

First-draft topics also have dispositions: renderer migration and terrain addons are deferred to VQ-07/L12/L13; native physics selection and qualification follow the [native guide](../../research/native-kernel/README.md#normal-flight-backend-selection); SSAO/glow/native shadow maps wait for an existing contact/night gate to identify a gap; frame-history rings/HUD micro-optimization, broader caches, chunk retuning and reflection-cadence changes require attribution. They are not an unlimited backlog or prerequisites for this program.

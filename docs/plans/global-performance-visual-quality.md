# Global performance and visual-quality improvement plan

2026-10-14 · Proposed execution plan · Godot **4.7.2**, desktop Compatibility baseline.

**Recommendation:** qualify the complete current flight first, address measured CPU and loading costs, then improve materials and visual consistency through small comparisons. Keep Compatibility as the production baseline while VQ-07 evaluates other renderers separately. The highest-value graphics outcome is a convincing field with a continuously readable aircraft and stable frame pacing.

**Scope:** performance, loading, graphics, textures, shaders, scene organization, quality controls and delivery verification. This document plans work; it implements none. Research, source links, inspected images and measurement limitations live in the [dated review](../research/godot-global-review-2026-10-14.md). Documentation is English under the repository convention.

**Ownership:** cross-track coordination under VQ; physics/H, LU/L, FW/TOD, SC, UI/HUD/CAM, aircraft-model, AUD and DT owners retain their files and acceptance decisions. This plan owns sequencing and cross-track experiments only. It introduces no new step namespace and does not supersede [ROADMAP](../../ROADMAP.md), [VQ](../VISUAL-QUALITY-PLAN.md), [landscape](../LANDSCAPE-PLAN.md), [sky/weather](sky-clouds-weather.md) or the [ownership registry](../README.md#tracks-plans-and-step-ids). Follow-ups to delivered steps require an unused repair substep in their owning plan before implementation; parent IDs below are routing references, not newly delivered work.

## 1. Starting point and priorities

The simulator already has deterministic float64 flight at 240 Hz, interpolated presentation, manual batching, imported LOD, filtered ground shaders, downloaded plants and population, projected shadows, propeller blur, dynamic sky/weather, audio and a reflective lake. These systems should be improved and qualified, not rebuilt.

The [research ledger](../research/godot-global-review-2026-10-14.md#3-measurements-that-change-the-priority) identifies the strongest starting signals:

- Current-content qualification is incomplete. Earlier H15 GDScript work brought fixture medians within 500 µs/tick, but those four-aircraft fixtures do not qualify every current route and world.
- Nearby scenery queries still miss their 100 µs objective. A later LU-22 paired airborne test adds approximately 330 µs median wall time with the lake enabled; its small sample warrants investigation, not extrapolation.
- LU-22 recorded 4.694 s cold complete-field construction. Warm scenery-only times are much smaller and measure a different scope.
- RTX 3090 scene views are fast, but they do not establish complete-flight performance on minimum hardware. The two-slot reflection-atlas fix, LOD and asset reuse are already delivered.
- Material appearance, aircraft tracking against vegetation/clouds and flown night readability remain useful visual work. More postprocessing alone does not close those gates.

Priority meanings: **P0** establishes or restores product headroom; **P1** delivers visible quality and scalable settings; **P2** is conditional research after P0/P1. No speculative FPS uplift is promised.

## 2. Constraints that every delivery preserves

1. Keep float64 simulation state, RK4 order, 240 Hz timing, transactional failure behavior, input sampling and complete checkpoint identity. Do not use render vectors for flight state. Never weaken validation or re-record goldens to pass a performance change.
2. Keep `airplane`, `propeller` and `*_hinge` contracts. Modify generated geometry/physics through the owning source pipeline. Visual LOD must not change collision identity or flight forces.
3. A visual-quality setting changes presentation only. It must not remove collision obstacles, change wind/weather, reduce physics rate, alter a random event sequence or disable simulation validation.
4. Prefer existing/free downloadable assets and native engine facilities. Reuse the retained Grass001 trial, plant library and effect masks before creating equivalents. New dependencies need an exact version, license record, reproducible import and three-platform export proof.
5. Preserve the explicit separation of physical weather, visual sky and time of day. Pause, reset, checkpoint restore, scene replacement and failed candidate setup must restore all presentation state coherently.
6. Native GPU, pilot, radio-latency and physical-validation gates remain distinct. A still image or headless test cannot close them.

## 3. Ordered backlog

All rows are proposed. Detailed work and acceptance follow in sections 4–8; canonical implementation status stays in the owning track.

| Priority / owner IDs | Work | Minimum proof / exit | Indicative effort |
| --- | --- | --- | --- |
| P0 · VQ-01 follow-up, DT-01/10a, H/Gate P | Freeze a current-commit full-session benchmark and hardware matrix | Reproducible manifest, raw frame/tick samples, repeatability range, current failure ledger | 2–4 days |
| P0 · LU-10/LU-22 follow-up, H | Attribute scenery/lake cost and implement one bounded optimization | Same-world paired gain outside noise; exhaustive/differential contacts and replay preserved | 3–6 days after profiling |
| P0 · UI loading boundary, VQ-06, DT-11a | Separate cold loading/construction/first-draw stalls; improve the dominant phase | Cold/warm export timings, responsive loading/cancel, no stale scene or first-flight hitch | 2–4 days |
| P1 · VQ-06a, SC-24, LU/L | Inventory and qualify render-only quality knobs | Capability-aware preset data, CPU/GPU attribution, unchanged physics/world identity | 2–3 days |
| P1 · VQ-02, L9 follow-up, aircraft owners | Audit imports and compare one ground material and one aircraft finish | Map/VRAM inventory; matched still/motion review; correct color/normal interpretation | 3–5 days |
| P1 · L9, FW/TOD, LU-25 follow-up | Profile ground, cloud/radiance, projected-shadow and lake shader/update cost | Feature-isolated timings; bounded updates; no horizon, shore, color or temporal regressions | 3–5 days |
| P1 · L6c, SC-24, LU vegetation | Tune existing chunks, LOD and alpha coverage | Pilot/flyover/zoom motion clips; no culling pop, light loss or concealed collision objects | 2–4 days |
| P1 · VQ-02/04b, FW-30/36/75 | Improve local material/contact lighting and qualify night flight | Aircraft tracking in actual circuits; bounded light/shadow cost; controlled exposure | 2–4 days plus pilot review |
| P1 · VQ-06b, UI-22…24, DT-03…05 | Expose saved quality/display settings and reliable recovery | EN/ES, keyboard/radio focus, Keep/Revert, restart-required options, invalid-setting recovery | 2–4 days |
| P1 · DT-02/10/12/13, owning tracks | Qualify the delivered slice on exported desktop packages | Current regression results, native matrix, 20-cycle lifecycle checks, release evidence | 2–4 days plus hardware access |
| P2 · VQ-07 | Isolated Compatibility/Mobile/Forward+ comparison | Same content, color/depth fixes, full-flight cost, first-use pacing and export recovery | 3–5 days |
| P2 · L12/L13, GP | Compare an existing terrain addon only if editable physical terrain is needed | Shared scalar terrain oracle, near/far continuity, exact addon pin and packaged builds | 4–7 day spike; integration separate |

These are planning ranges for an experienced developer, not commitments. They overlap in discovery and verification; do not add them as a guaranteed schedule. Re-estimate after the baseline. CPU optimization and asset experiments may proceed independently once their interfaces are fixed, but timing runs must execute alone.

## 4. Measurement before optimization

### Hardware and scene matrix

DT-01 freezes a named minimum desktop GPU/CPU/driver and target resolution before claiming performance acceptance. Existing CPU evidence identifies an i5-10500 Linux KVM development host; that is not a minimum-GPU specification. Use the RTX 3090 workstation as a comparison host, native Windows/Linux for shipped x86 builds, and DT's M1-class 8 GB Mac candidate when available. Unsupported or unavailable hosts remain explicitly unqualified.

Use release exports for user-facing timing and an instrumented development build for attribution. Record commit/dirty diff, engine hash, package hash, aircraft/data identity, scenery/lake identity, seed, exact conditions, camera, output/internal resolution, renderer/driver, VSync/FPS cap, power mode and background load. Keep the first unmodified run.

| Scenario | Why it belongs |
| --- | --- |
| Cold launch → Home → selected aircraft → Fly; warm repeat; Workshop enter/exit | Import/resource/build cost, preview ownership, shader first-use, memory retention |
| Fixed-wing trim, powered high-angle flight, approach/contact/rollout | Full flight and controls, active aero/wake/gear; include P-51 and electric Timber |
| Experimental helicopter and Bisonte, separately labeled | Different runtime/evaluator paths; do not blend their results into a fixed-wing claim |
| Pilot north, aircraft crossing trees/horizon, close pass, chase/orbit/zoom | Readability, foliage overdraw, model LOD, camera behavior |
| Near car/tree/fence, bank/shore crossing, high-speed sweep | Scenery broadphase/narrowphase and contact ordering, lake cost |
| Day, dusk, moonless/moonlit night, clouds, electrical storm, smoke | Lighting/radiance updates, transparency, transient peaks and sound |
| Pause/focus loss, reset, failed setup, return Home, aircraft/sky change | Resource lifecycle, retained contexts, clocks, audio and first-use spikes |

For steady rendering, start with the existing sky protocol: 10 s warmup and 60 s sampling, at least three alternating baseline/candidate pairs on the same machine. Include a longer circuit when 60 s misses a periodic sky/reflection update. Record all runs and noise, including failures. Test VSync off to diagnose limits and the intended cap/VSync to assess presentation. Keep screenshot PNG readback outside measured frames.

Collect frame p50/p95/p99/max and counts above 16.67/33.33/50 ms; raw whole-session tick timings and simulation-time/wall-time ratio; physics-load/contact/observer costs; CPU render submission, GPU time where supported, draws, primitives, RAM/VRAM and object/resource counts. Do not sum independent percentile values or CPU/GPU times as if their work could not overlap. A high FPS counter can hide simulation slowdown under the 12-tick catch-up limit.

The current frame logger measures process-loop intervals, not displayed-frame presentation or input-to-photon delay. Keep those labels in reports. Use the existing radio-latency tools and an instrumented native display/radio test for end-to-end latency; a shorter `_process()` interval alone cannot prove better control response. DT-10b's proposed 30-minute Mac soak is separate from the short comparison runs.

Use Godot's standard and Visual Profilers for attribution; the latter excludes non-render CPU work and is unavailable on macOS Compatibility. Record unavailable counters as unavailable. Extend the existing harness instead of building a second benchmark framework. Sources and caveats: [review §5](../research/godot-global-review-2026-10-14.md#5-godot-47-source-findings).

### Working acceptance proposals

Existing DT proposals remain with [the desktop plan](../DESKTOP-DELIVERY-PLAN.md#acceptance-and-evidence). Additional targets below are **proposals to freeze with the owning track**, not achieved results. Label process-loop, render and presentation metrics separately.

| Quantity | Proposed rule |
| --- | --- |
| 60 Hz profile | Retain DT-10's proposed process-loop p95 ≤18 ms/p99 ≤25 ms and simulation/wall ratio 0.99–1.01. Separately assess uncapped throughput against the 16.67 ms frame budget; investigate repeatable >50 ms gameplay hitches. |
| Optional 120 Hz profile | p95 ≤8.33 ms and p99 ≤10 ms only on named qualified hardware; never an implicit baseline promise. |
| Simulation | Preserve the canonical 500 µs/tick Gate P and separately disclose session/input/collision/recording overhead. Keep the nearby-query 100 µs objective visible; it is not extra free budget. |
| Optimization claim | Repeated paired improvement larger than observed run variance; proposed useful floor 5% in the affected complete workload, unless a specific hitch/memory failure is removed. Report losing cases too. |
| Visual increment | Allocate a budget from measured headroom before each effect; initial small-pass proposal ≤0.5 ms frame-p95 increase on the target, with the whole-profile gate still passing. |
| Loading | Retain DT-10's candidate Home ≤5 s cold/≤3 s warm and Fly ≤2 s, with exact phase boundaries frozen after attribution. Additionally propose ≤100 ms main-thread loading slices for responsive progress/cancel. No flight starts before validation/readiness. |
| Memory/lifecycle | No unexplained growth after warmup across 20 Home/Fly/Workshop/reset cycles; retained caches have explicit count/byte caps and invalidation tests. |
| Readability | No lost subject, mistaken orientation or concealed landing cue in matched owner-reviewed circuits. Quantitative image measures support this review, not replace it. |

Keep existing per-track limits, including LU's current 650k complete source-geometry cap, separate from visible draw/primitive budgets. Any revision needs recorded justification in its owner report.

## 5. Performance work packages

### Physics and scenery

Use `bench_regimes.gd` and existing dynamics-cost tools to locate current cost, then instrument the **complete FlightSession tick** including pre/post-step collision work. Preserve batch timings for historical comparisons and add per-tick sampling without conflating the distributions. The earlier H4/H5 and later H15 results describe different optimization stages, not a contradiction.

Start with LU-22's lake-on/off increment and the near-obstacle workload. Split bin lookup, candidate count, vertical/bounds rejection, each exact sweep, event collection/sorting and state copies. Try one conservative rejection or immutable-data preparation improvement at a time. Broadphase reuse already exists; do not implement it again.

An ordered traversal is acceptable only if its lower bound cannot skip the earliest valid event, including the tolerance-based stable-ID tie rule. A cache requires world/model generation, start/end state, full hull rotation, terrain identity and invalidation semantics; prefer a per-tick immutable preparation over a broad persistent memoization layer. Never disable world collisions through a graphics preset.

Acceptance includes oracle equivalence for empty/near-contact paths, bin boundaries, high speed, large rotation, bank/shore, grazing/tied hits, failed steps, restore and reset. Compare full state/checkpoint/trace identity with the frozen reference; use intentional defect tests on disposable copies where the existing harness requires them. Re-profile if the whole workload does not improve.

Only if the quiet-target result still misses Gate P should another native kernel be considered. Reuse the existing GDExtension research/build pattern, transfer a coarse validated float64 payload, retain the GDScript oracle and pin the backend in replay. The truck's qualified native path is not automatic qualification for flight. Do not move the active SceneTree or shared mutable simulation state to workers as a generic speed fix.

### Loading, resource ownership and render-loop CPU

Time disk/resource loading, aircraft validation/derivation, procedural field construction, shader/material creation, GPU upload, first visible draw and first interactive tick separately. Preloading a script does not prove all its runtime-generated resources are ready.

For a measured I/O bottleneck, request resources through Godot's threaded loader and retrieve them only after completion. For CPU construction, move only detached pure-data preparation to workers, then perform bounded scene attachment on the main thread. Keep accepted world state until the candidate is valid. Cancellation or replacement increments a generation token and disposes late results; do not let a cancelled preview overwrite the active sky/exposure.

Consider bounded reuse of immutable imported meshes/materials and static field recipes keyed by normalized field/asset identity. Mutable environment, clocks, world presentation context and aircraft-specific state are scene-owned. Measure memory retention before keeping whole scenes alive.

For reproduced OpenGL first-use hitches, warm the required materials/effects in a bounded loading view. Verify that materials actually draw; hidden nodes alone are insufficient evidence. Test cold imported data separately from a warm driver cache; do not erase the user's global GPU caches. The Forward+/Mobile pipeline tutorial is not an OpenGL fix.

If script profiling shows it matters, replace the bounded `_frame_times.slice()` pattern with a ring buffer and refresh unchanged diagnostic text less often. Preserve full-rate flight controls, aircraft pose and meaningful warnings. Existing overlay throttling should be reused. This is lower priority than measured lake/contact/loading cost.

## 6. Graphics, textures and shader work packages

### Ground and material consistency

Use the latest LU-22 images and a new matched current-commit pilot view. Compare existing ground with the already-retained **Grass001** maps at their documented world scale. Keep the field's current detiling, macro modulation, runway masks, derivative filtering and flight cues as the control. Tune one layer at a time: base hue/value, near detail, normal amplitude, roughness and distant variation. Do not replace the complete ground shader with a generic material that loses weather, runway, lake or haze behavior.

For a selected aircraft, compare covering film/paint, bare metal, rubber and canopy as distinct materials. Begin with plausible roughness and restrained normal detail; use downloaded maps only where they add visible information. Plastic/paint is not made metallic because it looks shiny. Keep clear silhouettes and upper/lower color cues at 20/50/100 m and the existing farther readability distances. Preserve hinge articulation, model scale, crash duplication and stopped-propeller parity.

Test noon/dusk/night, shadow/lit sides, glancing angles, camera movement and zoom. Imported normal orientation and roughness channels must be verified on a known lit patch. Use per-object variation without mutating globally shared materials; compare source materials before introducing another custom shader family.

### Texture/import audit

Create a small inventory from source/import metadata: use, dimensions, channels, color space, mip/filter mode, compression, GPU estimate, on-disk size, consumers and license. Include embedded GLB textures, generated `ImageTexture`s and atlases; the latter two may bypass normal import decisions.

| Map type | Candidate policy to test |
| --- | --- |
| Albedo / painted color | Color-aware sampling, mipmaps and anisotropic filtering for oblique 3D surfaces; start 1K/2K by screen coverage |
| Normal / roughness / AO / masks / packed slopes | Linear data, verified channel meanings and normal orientation; no blanket sRGB conversion |
| Foliage/effect alpha | Border padding and mip coverage review; test compressed silhouettes against lossless controls |
| UI / diagnostic marks | Preserve crisp text and exact diagnostic values; no blanket 3D compression rule |
| HDR environment references | Keep reference size bounded; the procedural solar/weather sky remains authoritative |

Compare a few high-memory photographic maps using renderer-supported VRAM compression. Compatibility ignores Godot's high-quality BPTC/ASTC option, so do not promise BC7 as a production fix. Keep packed data lossless unless its numerical/image error has been accepted. Report VRAM and loading change separately from archive size. Import-time roughness filtering can be trialed when normal detail sparkles; verify that it does not flatten the aircraft finish.

### Shader cost and stability

Profile on-screen coverage before simplifying arithmetic. Candidate isolation switches belong in the benchmark, not necessarily the product menu. Compare ground detail, parcel variation, cloud shadows, rain/bank transparency, water screen/depth sampling and projected shadow passes independently.

Ground's rectangle/polygon loops and procedural noise are bounded but unmeasured candidates. Investigate their actual pixel cost with identical views/resolution changes; only then consider simpler distant material paths or precomputed data. Preserve field-format coverage and whole-field fallbacks. Maintain derivative evaluation before shoreline discard and keep distant runway coverage stable.

Audit sky-uniform/radiance refresh, lighting-driven projector refresh and lake reflection capture cadence. These systems already have bounded/event-driven behavior; measure its spikes before changing cadence. Preserve the visible sky/background, ground, aircraft and reflections as a coherent state during time progression. Reduce redundant writes only when equality/dirty checks actually save work and do not hide required updates.

Water already reconstructs OpenGL depth. A renderer experiment must test depth conventions, screen-read ordering, transparency, bank intersection, smoke/propeller overlap and a camera above/below/near the water. Compare shallow/deep transition and bank materials using the same scalar geometry; never disguise a visual/physical shoreline mismatch with foam.

### Vegetation, LOD and transparency

Tune existing imported vegetation and spatial batches before seeking another library. Sweep candidate cell sizes on the real field; compare submission cost against culling and overdraw. Include per-object light coverage at night because a MultiMesh shares that limit. Bounds must include all transforms and maximum shader sway, without becoming world-sized.

Keep geometric LOD, material simplification and visibility distance separate. Use hysteresis where supported or an explicit stable transition policy; test alpha-scissor/alpha-to-coverage on actual foliage and 2×/4× MSAA. Avoid treating transparent crossfades as free. Imported geometry needs normals/UVs/tangents/LOD checked at several distances.

Near the flying corridor, every collidable object remains visibly identifiable. Density reduction targets non-collidable decoration or changes visual detail while retaining obstacle silhouettes. Culling is visual only. Never lower a render preset by loading a different collision world.

### Lighting, shadows and perceptual quality

Keep VQ-04a projected shadows as the control. Measure all mask viewports, draw work and refreshes. Native shadow maps remain VQ-04b's optional comparison, with wheel/contact precision, thin-wing bias and low-sun behavior checked before acceptance.

Godot 4.7 Compatibility supports glow and SSAO, so prototype only a restrained effect with a visible purpose: small local contact cues or bounded light halos. Compare against existing contact shadows to avoid double-darkening. Reject effects that hide control-surface edges, wash out lamps or reduce aircraft/background separation. Do not add depth of field, camera motion blur or a dramatic color grade as default flight embellishment.

Night work uses actual circuits with light and dark airframes, lamps on/off where the scenario permits, cloud cover, moonlight and electrical flashes. Retain FW's calibrated color/exposure path and flash recovery. Review transition peaks and quiet intervals, not only attractive stills. For distant landscape, tune haze and tonal separation together with aircraft tracking; a more detailed horizon is not automatically a better training background.

## 7. Quality profiles and optional renderer/terrain experiments

VQ-06 defines data; UI-22…24 exposes it; DT owns display/platform recovery. Proposed profile names describe intended use and are not hardware certification:

| Control | Performance candidate | Balanced candidate | High candidate |
| --- | --- | --- | --- |
| Renderer | Compatibility | Compatibility | Compatibility; separate VQ-07 build for another backend |
| MSAA | Test Off/2× | Current 4× | 4×; 8× only after measured benefit |
| Texture detail | Resident assets sized for the target; avoid live reimport | Current qualified assets | Higher resolution only for visible improvement |
| Decoration / vegetation | Shorter nonessential range and simpler distant materials | Existing scene as baseline | Additional detail only within measured cost |
| Sky / water / shadows | Bounded lower presentation cost; preserve essential cues | Current qualified behavior | Higher precision/cadence only when justified |
| Physics / collisions / event identity | Identical | Identical | Identical |

Separate native output resolution, 3D scale, VSync/frame cap and UI scale. Reducing internal resolution can make a distant RC aircraft disappear; require the flight readability gate. Keep advanced controls available without presenting unsupported renderer features. Quality changes that compile resources or change backend may require a loading step/restart. Provide restore defaults, validated persistence and Keep/Revert for display changes without accidentally resuming flight.

VQ-07 compares **Compatibility, Mobile and Forward+** with the same content and engine pin. Mobile is a meaningful desktop control between the other two. Start with equivalent effects; only then cost optional advanced effects. Audit color/exposure, custom `FOG`, depth reconstruction, alpha, projected masks, terrain and imported materials. Measure cold/warm pacing, CPU/GPU, memory, OS exports and input latency. TAA/FSR2 are experiments for small fast aircraft, not assumed improvements. Renderer migration requires its own reviewed decision in DECISIONS after evidence; no automatic production switch is authorized by this plan.

For terrain, compare existing free **Terrain3D** and **HTerrain** capabilities before writing another editor. A spike must pin source/binaries and test 4.7.2/export support. GP must own a float64 height/normal/contact interface matching visual terrain, with flat-runway parity and deterministic samples. ProtonScatter may assist offline placement if it exports reproducible data; neither a runtime scatter dependency nor whole-field replacement is needed for the present materials work. Source/license caveats: [review §6](../research/godot-global-review-2026-10-14.md#6-repositories-and-free-resources).

## 8. Verification, rollback and delivery

Each implementation PR changes one bounded mechanism or asset family. State the observed problem, exact source revision, intended visual/numerical change, paired result and known limits. Record reusable decisions in the existing decision log only when adopted; store routine evidence beside the owning step. Do not create another benchmark archive or duplicate every track's status here.

| Change | Required checks |
| --- | --- |
| Documentation/inventory only | Relative links, source/version claims, diff scope; no unrelated runtime suite |
| Physics/query optimization | Focused oracle/differential tests, float64/transcendental guards, checkpoint/golden/trace checks and complete-workload timing |
| Material/shader/asset | Import/parse, owning model/landscape tests, matched native stills and motion, export/resource/license checks, physics parity |
| Loading/settings/cache | Failed/cancelled setup, repeated apply/reset, stale-generation rejection, restore/recovery, 20-cycle memory and resource audit |
| Renderer/new native dependency | Full relevant suite and native package matrix; first-run, fallback, driver errors, color/depth and input checks |

Use the canonical commands in [TOOLS](../TOOLS.md) and each owning tool README. Before delivery of runtime work, run the relevant integration checks and required `app/test.sh`/CI checks from a coherent snapshot. Check log errors as well as exit codes. Reproduce inherited failures against the unchanged baseline; report them with source identity rather than silently changing expected results.

Keep experiment switches outside the ordinary product flow. A rejected optimization is removed, not hidden behind a permanent flag. An accepted render profile retains the known-safe baseline through validated settings; it must not leave alternate physics paths. Restore prior import metadata/assets as a unit when rejecting a material trial. Never mutate generated outputs by hand or delete shared build directories during qualification.

The first reviewable milestone is a **current baseline plus one measured CPU or loading improvement**, with no visual or numerical regression. The second is **one coherent ground/aircraft material comparison plus qualified quality controls**. The third closes the affected native/pilot gates. Only then select the optional renderer or terrain experiment based on the remaining limitation.

Completion means those chosen slices meet their declared gates, failures are visible, and the owner can fly takeoff/circuit/landing comfortably at the chosen profile. It does not mean every P2 idea must become a feature. Once this coordination plan is fulfilled or superseded, consolidate accepted rationale into the owning guides, retain the dated research and remove the redundant plan under the repository's documentation rules.

## 9. Exploratory prototypes from the second research round

The [second research round](../research/godot-global-review-2026-10-14.md#9-second-research-round-creative-directions) adds 24 ideas and three ambitious branches, with sources, first experiments and failure conditions. It explores perception, contrast-preserving textures, foliage coverage, semantic materials, coherent weather, real-field references and debrief tools. These are candidates alongside the execution sequence, not additions to every owner's mandatory backlog. No prototype was implemented or benchmarked in this research.

Select one small experiment at a time. Use existing assets and generators; allocate a repair or new step in the owning plan only when selected. Small visual/tooling studies may proceed in isolation while whole-flight CPU/loading qualification continues; production integration still passes the relevant gates above.

| Prototype | Owning track / existing home | Bounded work | Decision evidence |
| --- | --- | --- | --- |
| Visibility lab and optional orientation skins (ideas 01/02) | CAM acceptance, VQ/L6c and aircraft authoring | One aircraft, two source-authored liveries, matched moving clips across sky/trees/dusk | Detection versus orientation errors, response times, projected size, resolution/FOV/aid state; retain the original skin |
| Ground contrast comparison (05) | VQ-02 / L9 material follow-up | Existing turf blend versus one histogram or Laplacian alternative | Matched near/far motion, color/contrast and GPU cost; no new tile collection |
| Foliage coverage comparison (07) | L/LU vegetation owner | One atlas: existing compensation versus alpha-to-coverage; custom mips only after proving an import route that retains them | Alpha-scissor interaction, coverage per mip, atlas bleeding, shimmer, night appearance and measured cost at current MSAA |
| Path-to-shore material study (11/12) | L/LU/SC with FW water owner | One region using semantic wear/maintenance masks and dry/damp/shallow-water zones | Pilot and overview captures, visible collision boundaries, material continuity, texture memory and overdraw |
| Consistent wind and smooth sky (13/15) | L15 / FW/TOD, read-only M5 interface | Compare static windsock with already wind-driven vegetation; separately test cloud clocks; use separate runtime PRs | Visual direction/lag, high-wind stepping, sky/radiance costs, pause/reset and deterministic capture behavior |
| Orientation-loss debrief (21) | CAM/HUD with simulation/trace owner | Offline video/trace synchronization and one marker before a replay product | Correct time/view/pose alignment and a pilot finding that can be acted on; retention/size estimate |

The first three are the recommended starting set for creative graphics work. The material-region and weather studies supply a more coherent field if the pilot finds the current appearance unconvincing. A full ghost/replay UI, octahedral forest replacement, photo-field, GIS terrain or second renderer requires a separate decision after its narrow probe. None requires changing the 240 Hz float64 simulation, enlarging the aircraft, lowering collision fidelity or purchasing content.

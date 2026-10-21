# Advanced graphics and visual-quality upgrade plan

2026-10-21 · Planning only · Owner: Visual quality (VQ), with L/LU/SC, FW/TOD/SUN, aircraft, SM/CR, UI and DT owners.

Make OpenRC look substantially more convincing while flying: recognizable aircraft materials, stable vegetation, coherent sunlight and atmosphere, convincing ground contact, and smooth motion. Use modern rendering where it improves those outcomes. “AAA quality” is an ambition, not an acceptance metric or a promise of a particular technology.

**Recommended order:** finish the current Compatibility improvements → qualify a representative scene → compare Forward+ on the same engine → select a few proven effects → consider an optional High desktop profile. RTX, neural rendering and frame generation remain independent experiments.

## 1. Scope and authority

This plan expands **VQ-07** into reviewable steps and proposes the later High-profile decision. The [global performance/visual plan](global-performance-visual-quality.md) still owns the active Compatibility delivery; its exclusions and budgets remain binding for that delivery. [VQ](../VISUAL-QUALITY-PLAN.md) owns parent-step status. Existing material, landscape, smoke, sky and settings tasks stay in their current homes; they are dependencies, not a second backlog here.

The [dated investigation](../research/advanced-graphics-2026-10-21/README.md) records independent source checks, current-code findings and corrections to the supplied October 20 brief. Its [second round of 25 investigations](../research/advanced-graphics-2026-10-21/round-2.md) adds GitHub, Reddit, Godot Forum, documentation and tool evidence; [section 9](#9-disposition-of-the-25-follow-up-investigations) maps each finding to existing work. This document owns proposed execution. No graphics change, benchmark, renderer adoption or completed implementation is claimed by creating the plan.

| Boundary | Owner and paths |
| --- | --- |
| VQ-07 experiments | VQ; proposed tools under `research/visual-quality/forward-plus/`, future evidence under `docs/research/visual-quality-implementation/VQ-07/`; this plan owns VQ-07a…h |
| Renderer adaptation | VQ with FW/LU; `app/render/`, particularly sky, atmosphere, world exposure, lake, shadows and transparent effects |
| Aircraft finish | Aircraft owners; source generators and materials identified in their guides; AS owns node/binding contracts |
| Vegetation/terrain/scenery | L/LU/SC; existing assets, generators, batching, field adapters and obstacle inventory |
| Sky, time, smoke and incidents | FW/TOD/SUN and SM/CR; consume existing resolved state and lifecycle contracts |
| Profiles, startup and delivery | VQ-06 with UI-23/24 and DT; existing preferences, launcher and export paths |

Read [ownership](../README.md#tracks-plans-and-step-ids) and Git status before each implementation slice. Shared integration files have one integrator at a time. Draft scripts remain outside `app/` until they parse.

## 2. Starting point and visible target

The inspected tree at `ef91916374cee18b8bc84e736f69b9623e681adf` pins Godot **4.7.2-stable**, Compatibility, a 1280×720 base viewport, 4× MSAA and fixed 240 Hz physics. This was a working-tree review with unrelated trailer/documentation edits, not a clean release qualification. Runtime and pins remain authoritative: [project configuration](../../app/project.godot), [engine downloader](../../app/get-godot.sh), [architecture](../STACK.md).

Already present: PBR/shader-based aircraft, projected silhouettes, RPM-driven propeller blur, terrain/grass/trees, lake reflections/refraction, selectable skies, night lighting, smoke and storm presentation. Improve their integration and qualify their open gates before replacing them. The current delivery is desktop; Compatibility's web capability does not mean OpenRC ships a web build.

Build one representative comparison using the existing **Club field**, **Extra 300S** and **P-51**, with Ugly Stik as the main flight reference. Cover the runway edge, trees, mountains, lake and existing buildings. Expand to Green paradise and all enabled vehicles before qualifying shared changes.

| Visible outcome | Review evidence |
| --- | --- |
| Aircraft surfaces look like paint, film, metal, rubber and canopy material | Matched close views plus 20/50/100 m motion; coherent highlights without sparkle, disappearing markings or unreadable attitude |
| Field looks grounded and consistent | Pilot-height takeoff/landing; stable grass/tree edges, plausible texture scale, shadows attached to wheels and objects, readable runway cues |
| Light and atmosphere belong to one world | Day, cross-sun, dusk, moonlit and moonless clips; continuous sky/horizon haze, matching cloud/light/reflection state, no clipped flashes or exposure pumping |
| Motion feels responsive | Native frame-time distributions, first-use hitch record and same-device input-to-photon comparison where available |
| Presentation scales across machines | Measured Compatibility baseline and, only if qualified, an optional High profile with reliable startup recovery |

Keep an ordinary pilot-camera circuit in every review. A close-up or trailer shot alone cannot establish flight quality.

## 3. First delivery: improve what already works

Execute through the [existing implementation sequence](global-performance-visual-quality.md#3-order-dependencies-and-reviewable-deliveries). The table below prioritizes outcomes; it does not change those steps' status or adoption gates.

| Existing owner steps | Next useful outcome | Constraint |
| --- | --- | --- |
| VQ-01c/d, DT-01/10a/11a | Current source/package baseline, moving visibility reference and attributed loading/frame stalls | Read-only source research can proceed immediately; acceptance needs native measurements and owner flight |
| VQ-02a/b, aircraft owners | Correct demonstrated import/channel/filter errors, then one aircraft material or marking repair; trial stock normal-aware roughness import only for a suitable texture pair and observed sparkle | Retain existing livery and generators; review perceived material in motion, not maximum gloss; no blanket metallic, clearcoat or 4K conversion |
| L9e-R1 and grass/tree plans | Stable ground detail and foliage in motion; inspect LOD silhouette, wind-expanded bounds and night illumination during existing batching trials | Reconcile later [grass](grass-quality.md) and [tree](tree-forest-quality.md) work before applying an older probe; preserve population/contacts and reuse accepted assets |
| VQ-04b, L/FW/TOD/SUN | Better contact/light coherence where the current comparison identifies a defect | Preserve projected shadows as the reference; existing sun/night controls keep their owners |
| L15a/c, FW-81-R1 | Coherent windsock/foliage movement and smooth clouds | Visual clock/transport changes cannot modify physical wind or weather |
| SM-16…25, CR | Finish and qualify the existing smoke/effect overhaul | Reuse [SM's plan](../../SMOKE_SYSTEM_MASTER_PLAN.md); do not start another smoke renderer |
| VQ-06a/b/c, UI/DT | Qualified Balanced/Performance settings and integrated delivery | Same physical world and aircraft; current Compatibility budget and recovery gates apply |

Download-first intake: inspect retained packs first, then suitable free materials/HDRIs/models from [Poly Haven](https://polyhaven.com/license) or [ambientCG](https://docs.ambientcg.com/license/), both publishing CC0 assets. Record the exact asset URL, author, download date, license, hash, resolution, scale, channel layout and import recipe. Adapt the smallest suitable download; author replacement content only when a documented need has no suitable free source. A photographic sky with a baked sun is useful as a reference, but must not silently replace dynamic time-of-day lighting.

## 4. VQ-07: isolated renderer comparison

Use separate checkouts/import caches and private preferences. Pin the same official engine and assets on both sides. Do not combine an engine upgrade, scenery replacement and renderer change in one comparison. An independent prototype can start once a reproducible snapshot is available; inherited baseline failures stay recorded and block the relevant release gate.

| ID | Work | Proof/status |
| --- | --- | --- |
| VQ-07a | Freeze the comparison manifest, target-host identities, scenes, motion tapes, camera states and baseline failures. Reuse VQ-01c/d tools; record actual renderer/backend and presentation settings. | **Pending.** Reproducible running-application captures, not editor-preview lighting; private experimental startup and actual fallback recorded. |
| VQ-07b | Establish Forward+ visual/functional parity with advanced effects off. Fix one demonstrated renderer assumption per patch in the isolated copy. | **Pending; after a.** Sky/ground/fog/light consistency, correct water depth, complete materials, shadows and alpha effects; no new shader/runtime errors; unchanged accepted simulation state. |
| VQ-07c | Measure bare renderer cost and first-use pipeline behavior. Attribute main/shadow passes, transparency, sky/radiance and loading before adding effects; reuse free profilers when needed. | **Pending; after b.** Paired native timing, loading, VRAM and pipeline events with declared cache conditions; decision whether this hardware has useful headroom. If not, retain Compatibility on it. |
| VQ-07d | Compare edge stability and reconstruction: native MSAA, native SMAA, native TAA, native FSR2, then reduced-resolution FSR2. | **Pending; after c.** Lossless moving comparisons, silhouette/attitude review, real frame cost and history-reset behavior. Keep native rendering if reconstruction harms the aircraft. |
| VQ-07e | Compare directional shadows and reflections, then a single indirect-light candidate only if a remaining defect justifies it. | **Pending; after c.** Separate outcomes for PCSS, probe/SSR and optional SSAO/SSIL/GI; no combined “all effects” comparison. |
| VQ-07f | Evaluate bounded atmosphere and effect improvements when FW/SM/CR identify a gap. FW-85 retains the cloud-backend decision. | **Conditional; after c.** Same authoritative inputs, readable pilot circuit, pause/reset/cut behavior, bounded particles/overdraw and cost. Volumetric clouds are not required. |
| VQ-07g | Integrate only accepted candidates; produce the project-level renderer/High-profile decision and a tested fallback package. | **Pending; after d/e and any selected f.** Combined native acceptance, platform ledger, reproducible export and documented adopt/retain/defer decision in DECISIONS. Passing isolated effects is insufficient. |
| VQ-07h | Review vendor technologies in disposable projects, only after the native path has a decision and a named unresolved need. | **Deferred, optional.** Pinned SDK/fork sample, license/build/API/hardware assessment, latency and image evidence. Not required to close VQ-07a…g. |

### VQ-07b: concrete migration hazards

The current source contains actual assumptions to test, not merely a generic shader checklist:

- `sky.gdshader` encodes output for the GLES3 sky colour conversion; `atmosphere.gd` and `world/exposure.gd` coordinate exposure, fog, ambient light and night presentation. Audit encoding and exposure as a complete chain. Do not stack engine auto-exposure on top of the existing adaptation.
- `lake/water.gdshader::view_depth_at()` reconstructs OpenGL NDC depth. Adapt and test the RenderingDevice depth convention, refraction and shore intersection. A successful compile is not proof of correct depth.
- Ground/bank shaders already branch on `OUTPUT_IS_SRGB`; inspect all relevant shader families before introducing new renderer branches. Include canopy, smoke, propeller disc, clouds, stars, sun/glare, rain, lightning and crash effects.
- Compare projected and engine shadows independently. Avoid double-darkening by explicitly choosing the receiver/caster path per comparison; keep current projected silhouettes available.
- Exercise Home, Workshop, direct-flight automation and fixed-wing/experimental vehicle routes. Shared world changes must survive scene replacement and restore.
- Keep the existing interpolated float64 pose as the aircraft/camera source. Check camera, shadow and smoke attachment at supported 30/60/120/144 Hz; distinguish pose phase from temporal-AA history before changing smoothing. Keep 240 Hz simulation and avoid double interpolation.
- Inspect screen-copy ordering with canopy, propeller disc, smoke and water/refraction. An effect reading the opaque screen copy may miss later transparent layers. Establish the required pass scope before considering a compositor or viewport addition.

Godot documents different shader colour/depth conventions and compositor availability across renderers. Use its [shader guidance](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html) and the [source audit](../research/advanced-graphics-2026-10-21/README.md#local-findings) before coding.

### VQ-07d: preserve a small moving aircraft

Start at 1080p, with 720p as the accessibility/regression case and 1440p as an optional higher-resolution case. Compare each AA method separately, with other effects and sharpening fixed. FSR2 supplies its own temporal AA; do not count a simultaneous TAA setting as another independent treatment. At scale 1.0 it is a quality experiment with extra cost. Test scales 0.85 and 0.75 before 0.67; each is a candidate, not a promised preset. Record actual internal dimensions. [Godot scaling documentation](https://docs.godotengine.org/en/4.7/tutorials/3d/resolution_scaling.html)

Inspect rolling/inverted aircraft, thin wings, distant liveries, propellers, transparent canopy/smoke, vegetation crossings and specular highlights. Test camera cuts, pause/resume, reset, teleport and visual-checkpoint restore so stale temporal history cannot leave trails. Evaluate attitude recognition separately from merely detecting a dot. SMAA is an additional spatial comparison from the [4.7 AA documentation](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html); it is not a cure for temporal/specular shimmer.

Label the observed defect before selecting a treatment: geometric edge breakup, specular sparkle, LOD silhouette loss, dither pattern, texture-animation trails or pose jitter. Where used, include animated UVs and dithered LOD transitions in the tape. Inspect transitions with the aircraft crossing the treeline, not just an empty landscape. Older upstream reports provide reproduction ideas, not proof of defects in 4.7.2; retain exact-version results, including non-reproduction. [R12, R16–R17, R21–R22](../research/advanced-graphics-2026-10-21/round-2.md)

### VQ-07e/f: spend headroom selectively

| Candidate | First experiment | Retain baseline if… |
| --- | --- | --- |
| Directional shadows, then optional PCSS | Tune distance/cascade allocation and bias separately at fixed resolution, starting from the current two-split setup; compare gear, fences and low-sun field against projected shadows | Contact cues, useful long shadows, flicker or total main/shadow-pass cost worsen |
| Reflections | Verify visible and probe-source environments across Home/Workshop/Fly and day/dusk; trial bounded refresh/masks; SSR only for a demonstrated water/aircraft gap | Off-screen loss, edge popping, missing alpha reflections, false inclusion/history lag or update stalls are worse |
| Indirect light | One nearby structure/aircraft scene; compare simple ambient/probe treatment, then one SSAO or SSIL candidate | Dark halos, hidden detail or negligible pilot-view improvement |
| SDFGI/VoxelGI/LightmapGI | Conditional building/hangar requirement, with the selected time-of-day contract | Open-field benefit is small, moving-object response is wrong, or baked sunlight contradicts dynamic time |
| Atmosphere | Existing haze first; if attribution warrants it, separately trial sky radiance work or a stock half-resolution cloud subpass; a bounded fog volume needs its own visible purpose | Aircraft disappears, bright edges/reflections degrade, lightning trails, restore diverges or horizon/fog is applied twice |
| Flight effects | Existing SM/CR sources first; one trail, contact-dust or exhaust-distortion candidate using available authoritative state | Overdraw dominates, effects lag inputs/reset, unsupported aircraft emit them, or fallback hides an active hazard |

Built-in GPU trails are renderer-dependent; they do not justify replacing the accepted smoke system. Dust requires suitable surface/contact state. Heat haze requires an installed propulsion source. Condensation and new water effects stay deferred until their owning tracks define credible triggers. No graphics setting invents humidity, tire friction, engine forces or damage.

SSR requires an exact-runtime transparency test: the 4.6 overhaul samples prior-frame color, so the older “transparent materials are never reflected” rule is insufficient. Compare alpha sources with/without an opaque depth surface, a moving occluder and camera cuts. [Upstream evidence, R11](../research/advanced-graphics-2026-10-21/round-2.md#r11--lake-reflections-and-the-changed-ssr-path)

For existing or candidate GPU particles, test first emission after instantiation/re-entry, relevant resource changes and reset, with renderer logs. One upstream initialization issue is partially fixed but remains open; a separate old TAA particle report is closed. Neither status substitutes for a 4.7.2 result. Keep this within SM/CR lifecycle coverage. [R13](../research/advanced-graphics-2026-10-21/round-2.md#r13--version-specific-first-particle-emission)

Sky work stays conditional on attributed cost or a visible defect. Preserve the CPU-supplied clock and deterministic restore; do not blindly replace the current QUALITY radiance mode. A stock lower-resolution cloud subpass keeps aircraft and sharp sky features at full resolution and does not authorize a split scene-viewport architecture. Check convergence, reflections, storms and, where the supported camera reaches them, cloud-layer crossings. Bruneton's available atmosphere reference is an optional diagnostic, not a replacement commitment. [R08, R18, R25](../research/advanced-graphics-2026-10-21/round-2.md)

## 5. Quality profiles and safe adoption

**Balanced** retains the current Compatibility appearance as its reference; the owning plan's remaining qualification gates stay open. **Performance** remains the existing measured cheaper candidate. **High** is proposed only after VQ-07g; **Ultra** has no commitment. Renderer choice and effect quality are separate concerns.

The initial trial uses explicit startup configuration. Before exposing High, VQ-06/UI/DT must extend the existing preferences and launch flow: validate capabilities, require restart when necessary, retain a known-good Compatibility launch, handle invalid/unwritable preferences, and recover from unsuccessful initialization without a restart loop. Record the renderer that actually launched; engine fallback is not High acceptance. Unsupported effects must have qualified baseline behavior. Do not add a second settings file or silently change controller calibration.

Keep pilot presentation free of compulsory motion blur, depth of field, grain or chromatic aberration. Stronger grading, glow, optional depth of field and offline supersampling belong to the [trailer/camera workflow](cinematic-trailer.md) and remain independently switchable. Higher internal precision is not a commitment to HDR-display output.

VQ-07g must explicitly resolve whether to maintain a second renderer. Evidence of visual benefit, maintenance cost and supported platform coverage goes into [DECISIONS](../DECISIONS.md) before production adoption; the old global delivery is not retroactively expanded.

## 6. Measurement and acceptance

Reuse the [global measurement contract](global-performance-visual-quality.md#4-measurement-and-acceptance-contract) and [performance tools](../../research/performance/README.md). All numbers below are gates/proposals, not measurements from this research.

| Dimension | Required evidence |
| --- | --- |
| Controlled comparison | Same aircraft/assets, world, inputs/ticks, camera/FOV/zoom, sky/time, resolution and host/driver. Keep visual capture overhead outside timed runs. |
| Sampling | Existing minimum: 10 s warmup + 60 s sample, three alternating A/B pairs. Extend for periodic effects; report each run and variation. Loading: five fresh-process and five warm repetitions, with cache conditions declared. |
| Frame pacing | Existing 60 Hz gate: process-loop p95 ≤18 ms, p99 ≤25 ms; simulation/wall ratio 0.99–1.01. Report uncapped throughput separately against 16.67 ms. Attribute recurring gameplay intervals >50 ms. |
| Visual cost | Active Compatibility delivery retains its combined +0.5 ms frame-p95 ceiling. Proposed High targets 1080p/60 on named hardware with the same pacing gate; freeze its total measured headroom in VQ-07c before selecting effects. It cannot borrow unused physics budget or justify a Compatibility regression. |
| CPU/GPU and memory | Separate complete-session CPU, render CPU, GPU timings where available, draw/primitive counts, peak/resident VRAM and process memory. Missing GPU timers remain missing, not estimates from FPS. |
| Loading and compilation | Preserve current Home ≤5 s process-cold/≤3 s warm and Fly ≤2 s goals; distinguish construction, import and first draw. Fresh process is not necessarily cold shader cache. Inspect first night/storm/smoke appearance and first profile application. Qualify actual exports, including separate empty-cache macOS runs when advertised; use isolated caches, not destructive global cache clearing. |
| Simulation preservation | Same accepted checkpoint/state/input results on the pinned runtime under existing exact/tolerance contracts. Keep 240 Hz, float64 kernel, collision world and aircraft definitions unchanged. Never re-record goldens for graphics. |
| Readability | Randomized matched clips and owner circuit with bright/dark aircraft at close range, 20/50/100 m and the existing farther acceptance range. No new repeatable loss of attitude, subject or landing cue. Record projected size and aids. |
| Responsiveness | Same input device, monitor/refresh, VSync/cap and scene; input-to-photon samples with a stated measurement method and uncertainty when available. Software frame time alone cannot close latency acceptance. |
| Presentation telemetry | On Windows, reuse PresentMon where useful: record process/swapchain and presentation mode; retain dropped frames. Separate rendered/displayed/generated counts only where supported instrumentation provides them. Missing metrics stay unavailable; keyboard/mouse latency fields cannot qualify an RC-radio path. |
| Lifecycle | Pause/reset/restore, camera changes, failed setup and field/aircraft switching. No unexplained growth after warmup over 20 cycles; DT qualification separately keeps 50 cycles and a 30-minute soak. |
| Platforms/packages | Actual exported Windows, Linux and macOS execution for each advertised renderer/profile. Missing hardware remains unqualified; one Windows GPU cannot establish a minimum spec or Mac/Linux support. |

Use existing Stik circuit/takeoff/contact, P-51 high-load flight and Timber electric routes; basic coverage for other enabled aircraft. Add both landscapes and shared-family initialization/reset/camera/world regressions when their render code changes. Include day/dusk, moonlit/moonless night, strongest qualified storm, maximum qualified smoke and a no-effect control. Report transient peaks separately from steady flight.

For flight-feel/control claims, follow [FL logging](../FLIGHT-LOGGING.md): retain a complete baseline `.orfl`, verify exact replay, then compare one candidate on the same input tape; preserve markers, identities, CSV/reports and `complete`/`solver_changed` fields. Candidate replay is not exact equivalence or physical validation. The fixed-wing recorder does not substitute for helicopter/truck recorders, and visual-history equality is a separate check.

Every accepted experiment retains a manifest, raw measurements, logs/errors, representative lossless motion/stills, source/license identities and an adopt/retain/defer outcome. Use existing free profilers and plotting tools. When attribution is unclear, retain an annotated RenderDoc frame separately from uncaptured timing; API/platform support must match the host. Extend warmup when a selected radiance/history path needs convergence and report that duration. No new general benchmarking product is required. [Tool findings, R06–R07](../research/advanced-graphics-2026-10-21/round-2.md)

## 7. Vendor research boundary

VQ-07h is optional and separate from delivery. Native FSR2 is the first reconstruction experiment. AFMF is a user-driver experiment, not an OpenRC integration. Newer FSR, DLSS/DLAA/Reflex and NVIDIA's Godot path-tracing fork require exact SDK/fork pins, compatible API/OS/GPU evidence, redistribution terms and a maintenance assessment before a simulator prototype.

The supplied brief has two corrected claims: Streamline's current DLSS-G documentation includes Vulkan support, with narrower D3D12-only restrictions for Dynamic MFG and VSync with FG; DLSS 5's initial announcement was March 16, 2026. AMD FSR SDK 2.3's Vulkan limitation also must be distinguished from the older FSR3.1 implementation. [Verified vendor findings and primary links](../research/advanced-graphics-2026-10-21/README.md#vendor-claims-and-corrections)

Run vendor samples before attempting engine integration. Report real rendered FPS, displayed/generated FPS, simulation rate and measured latency separately. Check fast rolls, small aircraft, transparent trails and UI. Neural rendering must preserve silhouette, markings and state cues; attractive invented detail cannot establish simulator fidelity. No vendor feature is a prerequisite for High, and frame generation cannot rescue a failed native-performance gate.

## 8. First work packages and stopping rules

1. **Baseline package:** reconcile current VQ/L/FW/SM evidence, freeze source and representative views, complete VQ-07a. Deliver the comparison inputs and failure ledger.
2. **Parity package:** VQ-07b plus VQ-07c, one renderer adaptation per patch. Deliver paired native clips/timing and a decision to continue or retain Compatibility.
3. **Quality package:** VQ-07d, then separately shadows/reflections under VQ-07e. Only investigate VQ-07f where its owner has a remaining gap. Deliver an individual result for each selected candidate.
4. **Adoption package:** VQ-07g and, only following its decision, the scoped VQ-06/UI/DT High extension. Deliver exact tested packages, recovery proof and the platform/pilot ledger.

Planning allowance for one developer: baseline refresh **2–4 engineering days**, parity/cost study **3–6**, selected AA/light trials **4–8**, and profile/recovery/package work **4–8 after a positive decision**. These are estimates, exclude unresolved baseline repairs and hardware/pilot availability, and must be revised after VQ-07c. Conditional atmosphere/vendor work has no committed delivery date.

Stop a candidate when benefit is not visible in its intended view, when cost consumes the declared budget, or when readability/state/recovery regresses. Retaining the baseline is a valid completed experiment. VQ-07a…g closes with documented outcomes and an explicit renderer decision; shipping High additionally requires its native/pilot/platform gates. Optional vendor work does not hold that decision open.

When this plan is completed or superseded, consolidate adopted behavior into VQ and the owning guides, retain dated evidence and decisions, then remove this coordination plan under the repository's documentation conventions.

## 9. Disposition of the 25 follow-up investigations

The [research ledger](../research/advanced-graphics-2026-10-21/round-2.md) retains questions, exact sources, dates, limitations and experiment gates. This table changes execution priorities without creating another track. “Selected” means a comparison/check, not feature adoption; conditional additions cannot displace the baseline/parity packages.

| Evidence IDs | Priority and concrete plan change | Owning work / disposition |
| --- | --- | --- |
| R01, R24 | Use runtime references and verify one interpolation phase before judging smoothness | VQ-07a/b, CAM; selected |
| R06, R07, R19 | Attribute GPU work, separate presentation metrics, declare cache conditions and retain first-use events | VQ-07a/c, DT; selected diagnostics |
| R15 | Test actual exported Mac startup with isolated cache when that profile is advertised | VQ-07c/DT; required for that platform claim |
| R02, R20 | If the baseline shows a material defect, compare stock roughness import or one finish adjustment | VQ-02a/b; conditional, source pipeline and livery preserved |
| R03, R22 | Add night-light reach, deformed bounds and silhouette transitions to existing vegetation evidence | L/LU/SC, VQ-07c; selected checks, changes only after evidence |
| R12, R16, R17, R21 | Separate aliasing/history failure types; include animated UV and dither cases only where present | VQ-07d; selected motion matrix, conditional case applicability |
| R04, R05, R11 | Fix environment/reflection semantics and shadow allocation before buying costlier effects | VQ-04b/VQ-07b/e; selected trials; FFT ocean deferred |
| R13, R23 | Check alpha pass ordering and exact-version first GPU-particle emission | VQ-07b/f, SM/CR; selected where applicable |
| R08, R18, R25 | Reuse a clear-sky reference and trial bounded sky work only for an identified gap; test cloud crossings where reachable | FW-85/VQ-07f; conditional; full atmosphere replacement deferred |
| R09 | Consider a licensed far-field impostor only after a measured scenery bottleneck | Existing tree plan; adoption deferred pending license, compatibility and circuit evidence |
| R10 | Reuse Material Maker offline only when retained/free materials cannot meet a named requirement | VQ-02b/aircraft; conditional; no custom replacement tool |
| R14 | Existing LUT addon is a possible trailer experiment if current tools lack the required capability | Cinematic workflow; conditional, outside pilot/High prerequisites |

First implementation choice remains the baseline package. The most promising low-scope visual experiments after that are one material correction, stable vegetation transitions and targeted shadow/probe tuning. Sky subpasses, impostors and LUT tooling require their stated triggers; no extra addon, engine fork or asset replacement is approved by a favorable README alone.

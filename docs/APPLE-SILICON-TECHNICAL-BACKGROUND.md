# Apple Silicon optimization — technical background

Audited 2026-11-02 against clean source **`46b004c7b469448c29ef96168da4f03cee2c6d23`**. Owner: DT/PT, with VQ/GDU for rendering/engine and SF/FL for simulation. This document and the [master implementation plan](plans/apple-silicon-performance.md) are the two authoritative Apple optimization documents. The background owns implementation facts, limitations and research; the plan owns work, status and acceptance. Dated investigations remain evidence, not competing instructions.

**Conclusion:** first close the native measurement gaps, then attribute the actual workload on the available M1's built-in display. The product's 1080p priority still needs a separate actual-output check. The repository already contains meaningful CPU/loading/rendering optimizations and most Mac experiment preparation. Native Metal is a strong experiment, not a proven faster default. NK-3 is a Linux x86_64 evaluator with architecture-specific exactness requirements, not a ready-made Apple Silicon acceleration path. iOS has no delivery implementation to optimize yet.

This audit used three independent Terra 6.1 Max specialists: Godot/Metal rendering research, Apple diagnostics/platform research, and NK-3/source/evidence review. The lead checked decisive code paths and primary references, challenged scope and reconciled the findings. No optimization, engine upgrade, native helper, hardware benchmark, package publication or performance qualification was performed. The current environment is Linux; the available M1 is a subsequent test host. The shared tree later advanced through unrelated documentation/asset-cleanup commits; audited runtime/tool source was rechecked against this baseline. The user confirms an M1; retained DT-MAC evidence identifies it as an Air with 8 GB, which native inventory must verify before using it as the fanless/low-memory floor.

**Later implementation update (2026-11-02):** DT-MAC-02c/d portable evidence repairs and DT-MAC-02h Mac reference bundle identity now have focused tests. Native preflight verified a MacBookAir10,1 M1/8 GB, and short Aqua/resource/frame screening ran on its built-in panel. This does not revise the historical audit claim above. Results and open gates are in the [dated DT-MAC-02 evidence](research/desktop-delivery-investigations/DT-MAC-02/README.md#first-m1-native-screening-2026-11-02).

Audit verification: the two deliverables and new routing links passed 79 local link/anchor checks using the repository's existing checker logic; all 47 named test scripts exist. Whitespace checks passed. Runtime/tool code was rechecked against the audited baseline after concurrent documentation commits. These are documentation/source checks; no app suite or target-device test was run.

## 1. Audit coverage and reconciliation

| Existing material | Retained value and current disposition |
| --- | --- |
| [Initial Apple review](research/apple-silicon-performance-2026-10-24.md) | Historical 4.7.2 snapshot; its missing-downloader/MetalFX statements no longer describe current source. |
| [DT-MAC-00-R1 investigations I01–I20](research/desktop-delivery-investigations/DT-MAC-00-R1/README.md) | Hardware/memory, renderers, MetalFX, textures, scheduling, power, profiling and package questions are incorporated below; historical product specifications are not qualification. |
| [DT-MAC-00-R2 audit](research/desktop-delivery-investigations/DT-MAC-00-R2/README.md) | Correct distinction between SDK features and exact engine implementation; superseded implementation gaps must be read with DT-MAC-02. |
| [DT-MAC-02 preparation](research/desktop-delivery-investigations/DT-MAC-02/README.md) | Current getter, streaming capture, isolated trials and guarded MetalFX were prepared on Windows/WSL. Its broad test campaign was **not** a full-suite pass; cold import failed initially, two unit partitions stopped on audio/reference failures and later tests were unrun. Those dated failures are neither silently waived nor assumed current. |
| [Desktop delivery](DESKTOP-DELIVERY-PLAN.md), [DT-00/R1/R2](research/desktop-delivery-investigations/DT-00-R2/README.md) | Preserve signing, downloaded-package, Retina/Spaces, controller/audio, native CI, numeric and thermal gates. Apple execution detail belongs in the master plan; parent DT release gates remain authoritative. |
| [Global performance sequence](plans/global-performance-visual-quality.md) and [VQ](VISUAL-QUALITY-PLAN.md) | Preserve whole-session measurement, visual/collision invariants and loading ownership. The global plan's old “keep 4.7.2” delivery constraint is superseded by actual 4.8-beta1 adoption, not an instruction to downgrade. |
| [GDU upgrade](plans/godot-4.8-upgrade.md), [universal-template evidence](research/engine-upgrade/GDU-03/macos/README.md) | Exact beta and template workaround matter; native Mac acceptance remains distinct from cross-export checks. |
| [NK-3 tools](../research/native-kernel/README.md), [NK-3 evidence](research/native-kernel/NK-3/README.md), [scoping decisions](research/native-kernel-scoping-2026-10-27.md) | Preserve evaluator contracts, Linux-only admission, exactness, toolchain and qualified source identity. Earlier Mac reference-only policy is the starting point. |
| [Performance tools](../research/performance/README.md), [debug tools](../tools/debug/README.md), [native diagnostic tools](../tools/godot/README.md) | Reuse their collectors, reducers and commands; this audit identifies remaining platform and schema gaps. |
| iOS/iPadOS | Searches of plans, desktop investigations, exports, workflows and native tooling found incidental API references but no iOS export preset, release workflow or dedicated optimization implementation. Treat this as a separate platform prerequisite branch. |

Historical evidence and raw source identities are preserved. New implementation receipts should use the existing DT-MAC evidence area, not another archive or independent performance plan. No existing evidence establishes an M1 speedup, a five-generation performance guarantee, or iOS readiness.

## 2. Actual runtime and package architecture

| Boundary | Current source and implication |
| --- | --- |
| Engine | [get-godot.sh](../app/get-godot.sh) pins official `4.8.beta1.official.4d10419ca`; editor SHA-512 varies by platform. Match templates and any engine patch separately. Mutable `stable` documentation cannot override this pin. |
| Default graphics | [project.godot](../app/project.godot): `gl_compatibility`, 1280×720 configured viewport, 4× MSAA, reflection atlas count 2. These defaults do not establish 1080p qualification. A comment claiming the app imports no textures is obsolete; runtime assets/imports exist. |
| Render selection | [high_graphics_profile.gd](../app/render/high_graphics_profile.gd) and [launcher](../tools/graphics/launch.py): Standard/High product modes; High changes effects as well as renderer. Bare Forward+ can select High. Research copies explicitly control effects, method and driver. |
| Native Metal | Compatibility uses OpenGL. Mobile/Forward+ can use native Metal; Vulkan on macOS is a distinct MoltenVK path. The pinned Metal factory constructs **MTL3**, regardless of newer OS capability labels. See primary source [G1](#g1). |
| Simulation | [Simulation](../app/sim/simulation.gd), [VehicleModel](../app/sim/vehicle_model.gd), [FlightSession](../app/sim/flight_session.gd): float64 scalar/packed state, fixed 240 Hz, RK4, atomic accepted-tick publication. Rendering converts detached state. The kernel must stay vehicle-independent. |
| Catch-up | Maximum 12 physics ticks/frame. Sustained rendering below roughly 20 FPS can slow simulation; acceptable-looking FPS alone is insufficient. Preserve the sim/wall-time check. |
| Flight backend | Main requests native; verified loader/adapters can admit NK-3, otherwise reference fallback. Low-level sessions retain reference defaults. Native Mac/Windows aircraft qualification is absent. Ground-vehicle native support is a separate implementation and does not qualify aircraft. |
| Observation | Input, collision, sessions, accepted-state observers, HUD, audio, recording and presentation extend beyond evaluator timing. `step_usec` does not include every observer or complete live callback. |
| Presentation | Camera interpolation and jitter-fix configuration already exist. Renderer trials must not change the camera law, physics rate, control sampling or replay semantics. |
| Launch paths | [AppRoot](../app/app_root.gd) Home loads preferences; technical user arguments route to direct flight. `--scripted` uses a non-physics scripted pose; scripted frame-time captures additionally disable input. It is a rendering fixture. A direct frame capture is not Home → Fly product acceptance. |
| Export | [presets](../app/export_presets.cfg): Linux x86_64, Windows x86_64, macOS universal. [export.sh](../app/export.sh) explicitly requires Linux and performs Linux/native checks. Darwin support in individual helpers does not make the complete export pipeline Mac-native. |
| macOS package | Ad-hoc universal package checks exist. Public signing/notarization, final downloaded/quarantined execution and actual ARM64 performance remain separate gates. No iOS preset exists. |

The beta1 universal exporter has a reproduced release/debug payload inversion. [macos_universal_template.py](../tools/godot/macos_universal_template.py) prepares a project-local corrected ZIP from exact official bytes. Keep it for this pin; do not apply it to an engine containing the upstream fix or to a single-architecture export. Verify actual Mach-O UUIDs and release payloads before performance claims. A debug export is not made release-equivalent by a launch flag.

### Reference-release identity is a mandatory Mac gap

[FlightLog._replay_identity](../app/sim/flight_log.gd) delegates release-template identity to [NativePackage.identity](../app/app_state/native_package.gd), which only accepts Linux x86_64 and its NK-3 manifest. Consequently a Mac release, including GDScript reference flight, yields `unavailable-export`; the replay CLI refuses exact replay. The release session benchmark also expects the Linux packaged-executable identity. This is a code-path finding, not a native execution result.

Repair this independently of the optional ARM64 solver port. Mac exports have a separate PCK: hashing only the Mach-O would not bind the solver scripts/data. A versioned bundle-aware identity must cover actual executable, pack and solver-relevant resources/sidecars, final signing order and artifact receipts. Update replay/benchmark validators while preserving old Linux identity semantics and refusing unknown/substituted contents. Source-editor replay can support initial investigation but does not establish final-package exact replay. The Python flight-log tool also needs explicit native `--godot`/`GODOT` selection because its non-Windows default points at Linux.

## 3. Existing optimization work to preserve

These are source observations, not new measurements on Apple hardware.

| Area | Implemented mechanism | Remaining question |
| --- | --- | --- |
| Vegetation submission | [treeline.gd](../app/render/treeline.gd) uses up to eight bounded sector MultiMeshes without per-frame processing or real-time shadows; [near_grass.gd](../app/render/near_grass.gd) uses up to four bounded chunks; [field_tree_detail.gd](../app/render/field_tree_detail.gd) uses 256 m cells with LOD/culling. | Is the actual cost submission, vertex work, transparency, pixel shading or bandwidth? “Add MultiMesh/culling” is duplicate advice. |
| Reflections | [lake_reflection.gd](../app/render/lake/lake_reflection.gd) coalesces updates into `UPDATE_ONCE`; the atlas is already small. [Planar reflection](../app/render/lake/lake_planar_reflection.gd) is optional and gated by High/view/water conditions. | Measure its second viewport, copies, attachment memory and lifetime when enabled. Do not demand a new once-only reflection cache. |
| Presentation writes | Propeller blur and several cloud/global updates skip unchanged values. | Optional planar reflection still repeats some parameter/mask assignments; source repetition does not establish significant cost. Rank it only after attribution. |
| Scene detail | [scene_detail.gd](../app/render/scene_detail.gd) already maps Low/Medium/High/Extreme to scenery tier, tree coverage and LOD threshold. Auto uses adapter strings: `apple m` → Medium, unknown → High. | The heuristic is neither a capability query nor a measured device recommendation. Keep explicit scene detail fixed in renderer experiments. |
| Loading | Existing performance evidence covers validated-data reuse, lake geometry/resource caching, ground/grass/stars/woodland construction and audio retirement. Home/launch preparation and trim-cache paths already exist. | Attribute current source before adding another cache or background loader. Cache-empty, new process, fresh import and driver-cache-cold are different states. |
| Simulation | Prepared native configuration, per-tick context, deflection reuse, combined stage responses and bounded per-tick facts exist. | Full session/observer cost can dominate after evaluator improvements. Cache invalidation and observer ownership remain correctness boundaries. |
| Collision | Spatial bins, cached/bounded queries and early rejection already exist. | Any new broadphase optimization must preserve stable hit identity, earliest hit and collision-world equivalence. |
| Texture preparation | ETC2/ASTC imports are enabled; VQ-02a inventories ordinary, embedded and runtime textures. | The setting alone does not prove resident GPU format, compression, memory saving or appropriate mip/color-space behavior on a particular Mac. |

The dominant unresolved opportunity is **selection based on a complete workload**, not a missing generic optimization checklist. CPU allocation, immutable preparation, resource reuse and optional presentation work are plausible targets, but no large new production win was proven by this source audit.

### Current bounded optimization candidates

The 2026-11-02 implementation retains chronological packed speed-window values
for statistics, independent byte snapshots for flight-log intervention guards,
and zero-contribution rejection in the ground shader. Accepted-tick cadence,
recording durability, float64 physics and visual settings are unchanged.
Frozen-reference checks and five native M1 Compatibility views passed;
the views are byte-identical. Native performance claims and renderer decisions
remain separate from this parity result. Exact source identities, checks and
native outcomes live in the [DT-MAC-02 evidence](research/desktop-delivery-investigations/DT-MAC-02/README.md#dt-mac-04b--06b-optimization-candidates-2026-11-02).

A second shader batch skips fully filtered grass noise, inactive pilot-anchor and
twilight terms, and redundant cloud lattice wrapping. Focused checks passed, and
twelve native Compatibility views have quantified, tiny static pixel differences.
Single render-only pairs measured p95 37.291 → 30.939 ms on Mobile/Metal and
47.959 → 34.243 ms on Compatibility at 2560×1600. Native offscreen motion and
bounded shader comparisons, a new development package, signature verification
and exact packaged replay passed. Repeated timing attempts lost window
drawability and were excluded; active-flight benefit and sustained qualification
remain open.
This does not promote Metal or change production quality settings. Exact identities and
limits are in the [second-batch evidence](research/desktop-delivery-investigations/DT-MAC-02/README.md#dt-mac-06b-shader-work-reduction-second-batch-2026-11-02).

## 4. Rendering research tied to OpenRC

### 4.1 Mobile, Forward+ and Apple GPU memory traffic

Apple GPUs use tile-based rendering; keeping attachments in tile storage can reduce memory traffic. Unified memory avoids some discrete-device transfers but still has bandwidth, residency, synchronization and total-memory limits. Godot owns render passes, resource lifetimes and queues; an application cannot safely substitute its own Metal submission around engine textures without an explicit integration contract. [Apple GPU guidance](https://developer.apple.com/videos/play/wwdc2021/10148/), [Apple Silicon optimization](https://developer.apple.com/videos/play/wwdc2020/10632/).

Mobile/Metal is a sensible first efficiency candidate, while Forward+/Metal offers different features and temporal reconstruction. Neither is assumed faster. There is a specific OpenRC caveat: [water](../app/render/lake/water.gdshader) reads screen and depth; sun glare/afterimage use depth/screen inputs. In the pinned Mobile renderer, visible screen/depth consumers can disable merged subpasses and cause copies/resolves. This is a source-proven conditional path, **not a measured bottleneck**. Inspect actual pass cost and retain water/visibility functions unless an accepted alternative preserves them. [Pinned Mobile source](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp#L916-L942).

First compare common effects, fixed scenery, Native reconstruction and identical output/internal pixels. Then test one cost at a time: MSAA 4× versus 2×, reflection size/update cadence, shadow maps/casters, transparent coverage, texture residency or bounded geometry. Screen-space effects, smoke and foliage need moving images; a faster static frame can hide loss of distant-aircraft attitude cues. Open terrain may not justify CPU occlusion culling. Preserve collision populations even when rendering less detail.

A default renderer change also needs platform-policy care: the Mac package is
universal, so a `.macos` setting applies to Intel Macs too. Pinned Godot registers
each dot-separated override tag independently and selects a matching tag;
`.macos.arm64` does not express an AND condition. Use the planned explicit
capability/recovery policy, not a presumed compound feature filter.
[ProjectSettings implementation](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/core/config/project_settings.cpp).

### 4.2 Pipeline and loading behavior

Mobile/Forward+ use pipeline preparation and ubershaders; Compatibility requires shaders/materials/particles to be actually drawn for at least one frame in the view frustum for first-use preparation. Preloading an object is not always enough. Pipeline counters distinguish mesh-load and first-instantiation Surface work from on-demand Draw work; instantiation can occur during gameplay. Native cold/warm evidence must separate shader front-end compilation, intermediate representation and device pipeline compilation. [Godot pipeline guide](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html).

Two concrete experiments merit investigation if first-use hitches occur:

- Optional planar reflection uses 2× MSAA while the main default is 4×. Mixed viewport sample counts can create pipeline variants. Correlate counters and first-use stalls before matching them; matching upward can increase GPU cost.
- Metal shader baking requires a macOS-hosted, non-headless Metal export workflow. It is unavailable through the current Linux cross-export alone and does not eliminate device-specific final pipeline compilation. Compare startup, package size and residual stutter before adopting a native build stage.

Do not ship machine-specific driver caches as universal data or delete global user caches for a benchmark. Use disposable project/import identities and label uncontrollable driver-cache state.

### 4.3 MetalFX: implemented policy versus engine execution

[metalfx_policy.gd](../app/render/metalfx_policy.gd), [reconstruction.gd](../app/render/reconstruction.gd) and existing Settings already implement opt-in Spatial/Temporal trials, runtime method/driver/RD checks, feature constants, scale bounds and provider-specific AA/sharpening. They report effective MetalFX execution as **unknown**. This is deliberate honesty, not a missing enum implementation.

| Effective renderer/driver | Existing policy eligibility |
| --- | --- |
| Compatibility/OpenGL | Neither provider; Native fallback. |
| Mobile/Metal | Spatial when trial/build/device checks pass; no Temporal. |
| Forward+/Metal | Spatial and Temporal subject to actual support and valid scale limits. |
| Vulkan/MoltenVK | No native MetalFX through this driver. |

Temporal bounds from Godot use a factor of **1,000,000** and are input/output scale, not Apple's inverse upscale ratio. Missing/invalid bounds fail closed. Preserve Native AA when leaving reconstruction; do not apply FSR sharpness to MetalFX. A 0.85 input scale is a proposed starting experiment, not a tuned preset or performance claim.

Three distinct unresolved gates prevent promotion:

1. **Effective execution:** viewport property readback can retain a request while the engine substitutes another scaler. A capture can establish one run, but continuous truthful failure/substitution reporting needs an engine-observed status seam or an explicit unavailable state.
2. **Temporal discontinuity:** current stock integration has no acknowledged reset seam. OpenRC falls back to Native after a notified history discontinuity rather than claiming reset success. Camera switches, teleport/reset, resize and world replacement need engine-consumed reset or safe context recreation.
3. **Creation failure:** Apple's scaler factory returns an optional result. The pinned MetalFX source stores creation results without an evident corresponding null guard before temporal setter calls. OpenRC's `guard_runtime_failure()` covers FSR2/FSR3/DLSS, not MetalFX creation/execution. This is an inspected failure-path risk, not a reproduced Mac crash; require focused upstream review/failure evidence before promising recovery. [Pinned MetalFX implementation](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/servers/rendering/renderer_rd/effects/metal_fx.cpp), [Apple temporal factory](https://developer.apple.com/documentation/metalfx/mtlfxtemporalscalerdescriptor/maketemporalscaler(device:)).

Spatial must earn its cost on the actual GPU. Temporal additionally needs propeller/hinge motion, distant thin markings, wind foliage, smoke, disocclusion, camera cuts and pause/resume review. Frame interpolation is a separate presentation project: generated frames neither advance physics nor satisfy the real-frame or input-latency gate.

### 4.4 New Apple features: opportunity boundary

| Feature | Relevant decision |
| --- | --- |
| Metal 4 command submission | Pinned engine uses MTL3. Evaluate an upstream implementation only for a measured limitation; exact source/build and MTL3 recovery are prerequisites. OS support is not execution proof. |
| Newer neural MetalFX inputs | Availability, engine exposure, actual device execution and measured benefit are four separate gates. Recheck the exact SDK/source when selected; do not hardcode support by marketing model name. |
| Ray tracing/denoised scaling/tensors | No current production consumer justifies adding a ray tracer or ML workload for optimization. Keep deferred until a specific renderer feature needs them. |
| Mesh/tile shaders, indirect work, memoryless attachments, async compute | Prefer existing engine controls first. These are engine-level proposals only after relevant pass/bandwidth/synchronization evidence. |
| ProMotion/VRR/HDR/Game Mode | Separate display/power experiments after 1080p/60 Hz. Fullscreen alone proves neither effective Game Mode nor low-latency presentation. |

The retained [Apple technology investigation](research/desktop-delivery-investigations/DT-MAC-00-R2/apple-technologies.md) preserves dated newer-API references. Apple publishes [feature tables](https://developer.apple.com/metal/capabilities/); use actual device queries and supported SDK availability checks over generation inference. A later or announced model is a coverage opportunity, not a release prerequisite or automatic High preset.

## 5. NK-3, CPU scheduling and numerical constraints

NK-3 replaces vehicle evaluators through existing `VehicleModel` callbacks. It does **not** replace the kernel's validation, discrete supervision, integration transaction, collision or observer publication. [Native adapters](../app/native/), [native guide](../research/native-kernel/README.md).

The current build/receipt/loader/install path is Linux x86_64. `nk::R` uses left-first SSE2 inline assembly to preserve malformed-input NaN behavior; transcendental behavior follows the Linux engine/glibc relationship. macOS ARM64 cannot compile and qualify this by changing a target flag. It needs a platform math strategy, same-host native/reference probes, compiler/SDK pins, dylib/dependency/signature handling and admission receipts. A successful finite-state test does not cover NaNs, signed zero, literals or libm behavior.

Clang's strictness must be checked in actual compile commands: `-fno-fast-math` alone does not guarantee disabled contraction. Preserve explicit `-ffp-contract=off` and inspect conflicting overrides. Even that is not parity proof. Never reduce float64, reassociate RK4 or use GPU flight physics as a graphics optimization. [Clang floating-point documentation](https://clang.llvm.org/docs/UsersManual.html#cmdoption-ffp-contract).

The native tools are substantial and reusable:

| Existing tool | Coverage and limit |
| --- | --- |
| `build.py`, `run.py`, component/stage/trajectory oracles | Receipts, malformed inputs, negative controls, exact states/trajectories and source identity. Installation demands current reports and actual native execution. |
| `devtools.py` UBSan/profile/ASan modes | Isolated builds, symbols/frame pointers/compilation database, positive detector controls and checked logs. Current GCC/Linux flow is not an Apple Clang flow. |
| ASan | Official Linux engine's `RTLD_DEEPBIND` blocks the supported ASan combination; compatible instrumented engine required. Do not generalize this Linux loader problem to macOS or bypass it with a shim. |
| Fleet campaign | Source-bound family/weather/start/refusal/terminal coverage. Current MoonRunner rows have explicit exclusions; historical X8 results cannot qualify changed X99 data. |
| Session baseline | Includes more production session work than the research-stage microbenchmark, but detached probes still omit live presentation callbacks. |

Historical 1.65–2.76× Linux reference/native mean-tick-cost ratios describe median paired **mean tick** ratios for specified detached-session cases. They are not per-tick tail guarantees, Mac speedups or FPS gains. The 1,238-case historical fleet result separates 1,202 completed flights, 28 startup refusals, six runtime refusals and two terminal collisions; retain its source/date scope instead of transferring it to today's catalog.

Before a native port, profile the M1 reference workload: evaluator stages, scenery queries, immutable guards, endpoint publication, signal callbacks, logging and audio. Reuse validated preparation and remove measured repeated work without weakening failure semantics. Work with the OS scheduler and appropriate QoS for independent work; do not pin P/E cores, busy-spin, disable App Nap globally, or move the active SceneTree/simulation transaction onto arbitrary workers. Apple CPU topology is not uniform across all generations. [Godot thread-safety constraints](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html).

## 6. Measurement tooling: what exists and what is missing

| Tool/source | Implemented | Remaining gap or interpretation limit |
| --- | --- | --- |
| [Native preflight](../tools/godot/macos_preflight.py) | Bounded host/GPU/display/tool inventory, serial filtering, engine identity; native M1 execution recorded. | Screen dimensions are not drawable pixels. |
| [Research preparation](../tools/graphics/prepare_research.py), [launcher](../tools/graphics/launch.py) | Hashed private app copies, isolated user/import identity, explicit method/driver pairs and controlled profile. | Linked sibling assets are not immutable; freeze/hash them. Source-copy success does not qualify exported release selection/recovery. |
| [frame_samples.gd](../app/render/frame_samples.gd) | v2 short arrays; v3 512-frame chunk stream, up to 3,600 s, bounded frame/file size, sequence/hash/completion and synchronous write-cost receipts. | Long-stream support already exists. Disk writes can cause hitches; measure overhead before deciding on buffering/worker changes. Interrupted/capped output cannot qualify a soak. |
| [frame_diagnostics.gd](../app/render/frame_diagnostics.gd) | Method/driver/architecture/VSync/cap, reconstruction receipts, viewport timing, engine memory counters and scope notes. | macOS Compatibility viewport timing is explicitly disabled. Viewport coordinates are not verified drawable/internal pixels; presentation is uncollected. Missing GPU channels cannot be treated as zero cost. |
| [native_summary.py](../research/performance/native_summary.py), [frame_diagnose.py](../research/performance/frame_diagnose.py) | v2/v3 validation, sample integrity, duration gates and per-interval render-progress eligibility from Main. Historical progress is unknown; stale GPU polls cannot establish rendering. | Render-server calls and window drawability are not presentation. Default 10/60 s minima are not the Mac 30/1,800 s soak protocol. Qualify completeness and each required channel separately. |
| [resource_samples.py](../tools/godot/resource_samples.py), [checked runner](../tools/godot/run_checked.py) | psutil process CPU/RSS, system memory/swap, availability, clock anchors and bounded output. DT-MAC-02c raises the 1 Hz default to 2,100 samples, probes unsupported process I/O once, and adds required-channel coverage while retaining v1 legacy coverage. A short native M1 reference run had complete required coverage. | Sustained frame-interval alignment and measurement overhead remain unverified. Unsupported optional Darwin I/O remains visible as null/status and can still make a legacy Perfetto trace partial. |
| [Incident bundle](../tools/godot/incident_bundle.py), [Perfetto export](../tools/godot/perfetto_export.py) | DT-MAC-02d preserves valid v3 manifest/sidecar pairs, old v2 input and explicit selected-window/track timeline scope; interrupted sidecars are labeled unverified. Focused Linux/Mac fixtures and long synthetic streams passed. | Hashes do not sanitize personal data; full native soak and consumer overhead remain open. |
| [Debug bridge](../tools/debug/debugctl.py) | Local authenticated control, state, smoke, lifecycle, hitches, scripts and diagnostics. DT-MAC-02c routes Aqua launches without Xvfb and samples Mac RSS through the existing optional psutil sampler. A short native Aqua Home launch passed. | Package behavior and sustained lifecycle checks remain open. |
| [Loading probe](../research/performance/loading_probe.gd) | Actual Home/Fly route, readiness/draw boundaries, private preferences and bounded transition cycles. | Paused first draw is not interactive readiness; observer screenshots stall and belong outside timing. |

The psutil Darwin counter limitation is confirmed in the pinned [7.2.2 platform implementation](https://github.com/giampaolo/psutil/blob/release-7.2.2/psutil/_psosx.py). Short native M1 checks confirmed unsupported process I/O and complete required CPU/RSS/system-memory coverage; this does not establish sustained coverage or diagnostic overhead.

### Native tools to reuse

Use Instruments Time Profiler for CPU stacks, Allocations/Leaks for suspicious lifetime growth, and Game Performance/Metal System Trace plus Xcode GPU capture/counters for Metal workloads. Inspect waits, submission and presentation as well as shader duration. When debug information is separate, dSYM and binary UUIDs must match; embedded debug information is also usable. Official engine symbols may be unavailable, in which case record unsymbolicated scope or use a separately pinned diagnostic engine. [Apple performance workflow](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app), [debugging symbols](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information).

Metal HUD and API/Shader Validation are diagnostic tools, not final benchmark settings. HUD does not profile OpenGL. Discover installed Xcode/xctrace templates and optional newer GPU CLI tools; do not assume a tool exists on the M1 OS or make full Xcode a player requirement. `powermetrics` is an optional developer workflow with host-specific permissions/counters, not a privileged automatic game logger. Energy Impact is relative, not watts; RSS plus engine GPU estimates is not additive unified-memory use. [Metal HUD](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance).

Timing layers remain separate: process callback interval, whole active-flight callback, tick/evaluator duration, viewport GPU timing, submitted/presented frame events, and physical input-to-photon latency. CPU/GPU overlap means adding their durations does not reconstruct frame time. Diagnostic debug runs are useful for attribution; acceptance uses the real optimized release with costly observers disabled and a paired observer-cost check.

## 7. Native diagnostics and voluntary community reports

**Recommended minimum:** extend existing capture/resource/bundle tools, with a small optional native macOS companion only for missing public OS channels. Do not build a profiler, uploader service or second render loop. Separate developer collection from the eventual packaged user flow.

| Channel | Proposed collection boundary | Required caveat |
| --- | --- | --- |
| Thermal state / low-power state | Foundation `ProcessInfo`, initial query before subscribing to change notifications, then bounded sampling. | Thermal state is categorical, not temperature or proof that this process caused throttling; missing APIs are unavailable. |
| AC/battery context | Public IOKit power-source snapshots on macOS; explicit availability/permission receipt. | A short battery percentage slope is not trustworthy energy consumption. Exclude identifying device details. |
| Memory pressure | Public Dispatch memory-pressure notifications plus existing process/system memory samples. | Event state before first notification is unknown. System pressure/swap is not attributable to OpenRC alone. |
| CPU/RSS and supported I/O | Existing resource sampler; stable optional-channel support metadata. | Do not count unsupported optional fields as corrupt required capture or replace them with zero. |
| App phase events | Existing monotonic capture ID/clock anchors; optional `os_signpost` for loading, transitions and sampled diagnostic ranges. | No per-stage/per-tick release signpost flood. Engine already has Metal pipeline-creation signposts; reuse those for that scope first. |
| GPU/presentation | Existing engine counters plus bounded developer trace/capture. | A helper-created MTLDevice's allocations are not the game's GPU allocations; the pinned engine does not expose the later documented `get_driver_resource` seam. No undocumented cross-process GPU scraping. |

Public API references: [thermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property), [isLowPowerModeEnabled](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled), [Dispatch memory pressure](https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:)), [IOKit power sources](https://developer.apple.com/documentation/iokit/iopowersources_h/1810316-iopsgetprovidingpowersourcetype), [signposts](https://developer.apple.com/documentation/os/recording-performance-data).

For developers, a bounded sidecar avoids making physics/native solver delivery a dependency of host telemetry. If user collection later needs in-process events, add only a narrow Apple bridge with non-Apple no-op behavior; select extension versus supported platform plugin based on packaging/availability evidence. The user flow must work without Python, Xcode, administrator rights, shell editing or the debug server. Signed helper identity, lifecycle and architecture must follow the app package; never download and execute code during collection.

Collection is off by default and local. The user chooses a bounded session, sees fields, can stop/delete, previews the sanitized bundle, and explicitly shares it using an existing support channel. Do not add automatic upload, unique hardware identifiers, usernames, serials, home paths, controller serials, environment dumps, screenshots, exact input tapes or full `.orfl` files by default. Error text, command lines and file paths need sanitization too. Keep optional richer traces separate with a clear preview; hashes of personal data are not anonymization.

The normal app-route owner must create one fresh capture ID and convey it to all its collectors/helpers: the current frame collector gets its ID only from the checked-runner environment, so independently generated helper IDs cannot be joined. Record schema/capture version, random per-report ID, source/package/engine/import/native identities, requested/effective settings, actual output/internal dimensions when observed, sample availability, monotonic origin and clock uncertainty, sequence/hash/size/count, drops and stop reason. Missing fields carry reason/status. Maintain existing numeric v2/v3 arrays; optional channels live in versioned sidecars rather than inserting null into legacy finite arrays.

Use bounded 1 Hz sampling and event notifications initially: 2,100 samples for the psutil runner and a separate proposed helper cap of 4,096 snapshots plus 1,024 events. Verify timestamp coverage of startup, 30 s warmup, 30-minute sample and shutdown; capacity alone does not prove it. Native build and runtime capability checks must distinguish unsupported, denied, failed, interrupted and complete. Helper crash, slow/full disk or cancellation must not block flight. Measure collector-off/on CPU, memory, frame tails and disk effects; proposed overhead gates are in the master plan.

MetricKit is a **later supplementary source**, not a replacement for session logs: aggregate metrics are typically daily, while diagnostic events may be delivered immediately where supported. As checked on 2026-11-02, Apple documents legacy `MXMetricManager` metrics on iOS 13+/macOS 26+ and immediate diagnostics on iOS 15+/macOS 12+; newer `MetricManager` begins on iOS/iPadOS/macOS 27+. Verify availability/deprecation against the SDK actually selected; delivery is not guaranteed during a short session. Keep optional and separate from the M1 baseline and from immediate frame claims. [MetricKit](https://developer.apple.com/documentation/metrickit), [MXMetricManager](https://developer.apple.com/documentation/metrickit/mxmetricmanager), [MetricManager](https://developer.apple.com/documentation/metrickit/metricmanager).

Community bundles are untrusted and selectively submitted. Validate sizes, schemas, hashes, finite values and path traversal before analysis; reject executable attachments and malformed completeness. Compare within hardware/OS/backend/workload groups, not pooled FPS across chips. Community reports extend coverage but do not establish absence of failures in unobserved configurations.

## 8. iOS and cross-platform boundary

Godot can export iOS applications, but OpenRC currently has no iOS package, touch workflow, device qualification or mobile native evaluator. An M-series iPad is not a Mac and a simulator run is not physical-device GPU evidence. The future iOS branch needs an exact engine/template/Xcode/SDK baseline, device versus simulator architecture, signing/provisioning, supported renderer, resource formats, lifecycle, memory-warning behavior, audio route/interruption and controller/control usability. [Godot iOS export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html).

Reuse the float64 kernel and reference backend initially. Native Metal/mobile policy may be shared only through capability interfaces; platform collection requires an iOS plugin/extension packaging path, public APIs and app lifecycle handling. A macOS command-line helper, IOKit host script, debug port or external resource sampler is not the iOS product solution. MetricKit/Organizer can supplement physical-device tests after delivery exists.

1080p remains the primary engineering target where the device/output allows it; record actual aspect ratio, pixels, safe areas and internal scale on each device. Then qualify higher resolutions; 720p remains a disclosed fallback. Do not lower simulation frequency or render UI into a low-resolution reconstruction surface to manufacture a mobile pass. A usable supported control path and sustainable physical flight must precede mobile performance claims.

## 9. Evidence standard and remaining opportunities

The [master plan](plans/apple-silicon-performance.md) turns these findings into bounded work. Its priority is: native-tool correctness and report semantics → reproducible M1 baseline → highest attributed CPU/loading/memory fix or common-feature Metal trial → measured GPU/pipeline changes → conditional MetalFX → safe product selection → sustained final-package and community qualification. NK-3 ARM64, iOS and engine-level Metal work are independent conditional branches with their own entry gates.

No percentage speedup, memory ceiling, thermal duration pass or preset recommendation is established by this audit. Freeze candidate acceptance targets before measurements; keep explicit failed and untested rows. Software parity does not establish physical realism. Rendered correctness, same-host exact replay, cross-platform numerical agreement, release trust and target-device performance are different claims.

<a id="g1"></a>
**G1 — decisive engine source:** the pinned [Metal factory](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/drivers/metal/rendering_context_driver_metal.cpp) creates MTL3. The published architecture page's broader Metal 4 language cannot establish this binary's backend. Recheck source and actual native receipts after any engine change.

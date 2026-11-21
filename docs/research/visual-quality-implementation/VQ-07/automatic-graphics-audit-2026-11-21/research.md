> Research snapshot from 2026-11-21. R01–R20 and their primary sources are retained; the original phase numbers below describe the earlier audit. The [canonical plan](../../../../plans/automatic-graphics.md) supersedes that execution order, reuses later GitHub evidence and tracks implementation.

# OpenRC Simulator: 20 Research Investigations for Better Automatic Graphics

**Research date:** 21 November 2026\
**Scope:** GPU detection, renderer selection, graphics recommendations, calibration, application, recovery and qualification.\
**Status:** external research completed; OpenRC adaptations and experiments proposed. No new OpenRC hardware performance result or implemented improvement is claimed.\
**Baseline:** the preceding [GPU audit and phased plan][audit], referencing OpenRC revision [`57abea025f62b20233ca281d58d2acbee4ab8b8e`][baseline] and Godot `4.8.beta2.official.cafc17a19`.\
**Ownership:** existing VQ-07h automatic graphics work, with UI, PT, DT and Apple owners. R01–R20 are local research labels, not a new repository workstream.

## Executive recommendation

The most useful lesson from other games is to treat automatic graphics as a sequence of decisions that must remain recoverable and explainable: identify the active device, establish what the renderer can actually do, recommend a workload, preserve the player's intent, apply it coherently, and validate the result under representative conditions.

This report selects **20 distinct investigations**, rather than twenty unrelated links. Each one identifies a source mechanism, an OpenRC-specific hypothesis, a bounded experiment, a decision gate and a transfer limit. The selection includes Warzone 2100, OpenMW, Luanti, SuperTuxKart, 0 A.D., Lyra, Forza Motorsport, Factorio, Fortnite, EA SPORTS FC 26 and Unity's Boat Attack sample, alongside Valve, Microsoft, Khronos, Intel, Apple and AMD documentation.

The immediate priorities are R01, R02, R05 and R11 for correctness, followed by R07–R10 and R12–R14 for trustworthy evidence. Runtime adaptation in R15–R20 should advance only after the identity, measurement and application contracts are reliable. A useful early energy experiment is a bounded Home-screen policy, separately qualified from live-flight behavior.

The preceding audit's F-numbers are used for traceability. Its six phases are: **0 baseline; 1 startup and user intent; 2 identity and resolved policy; 3 calibration; 4 hardware qualification; 5 release and explanations**. The canonical implementation status remains in the repository's [automatic graphics plan][autoPlan]. Recommendations below are additions or refinements to those owners, not evidence that existing related work is absent.

## Research method and limits

Three research helpers investigated open-source games, published game-engine cases, and platform APIs. The lead independently read the selected primary material, including exact code snapshots where available, and reconciled it with the earlier audit. Sources are original project repositories, developer publications, official support notes, standards and vendor API documentation. No third-party benchmark ranking is used as an OpenRC performance oracle.

The source paragraphs describe what another project documents. Everything under **OpenRC proposal**, **Experiment** and **Decision gate** is our engineering recommendation. Published screenshots, company measurements, product descriptions and inspected code have different evidential strength. A title's reported speedup, power saving or quality threshold does not transfer automatically to OpenRC.

The research preserves the project's [instructions][agents]: fixed 240 Hz simulation; exact/tolerance replay contracts; unchanged collision and physical scenario; preserved explicit settings; 1080p-first general qualification; and the native-output/reconstructed-result requirements of the Apple Retina work. Scalers may change presentation cost only within those boundaries.

## Investigation index

| ID | Primary inspiration | Question to investigate | Audit connection | Phase |
| --- | --- | --- | --- | --- |
| R01 | Warzone 2100 | Can a failed or alternating renderer transition always terminate safely? | F01/F02/F15 | 1 |
| R02 | OpenMW | Did the engine actually obtain the requested antialiasing configuration? | F06/F18 | 2–3 |
| R03 | Luanti | Is optional-feature eligibility checked against the active renderer? | F05/F18/F20 | 2 |
| R04 | SuperTuxKart restrictions | Can a driver workaround affect only its demonstrated scope? | F03/F08/F18 | 2 |
| R05 | 0 A.D. | Can automatic recommendations remain separate from player intent? | F13/F14/F18 | 1–2 |
| R06 | Valve Steamworks | Which settings and evidence belong to one device? | F03/F08/F14/F15 | 1–2 |
| R07 | D3D12/DXGI | Are capacity and budget observations attached to the rendering adapter? | F03/F06/F08 | 2/4 |
| R08 | Vulkan/DRM/GLX | Can Linux renderer changes be correlated without GPU-name guesses? | F01/F03/F04 | 2 |
| R09 | Unreal/Lyra | Can recommendations be computed and compared before application? | F05/F09/F18/F20 | 2–4 |
| R10 | SuperTuxKart benchmark | Does a repeatable route expose target misses better than average FPS? | F07/F09/F17/F20 | 3–4 |
| R11 | Forza Motorsport | Do reconfiguration and unusual refresh rates retain correct pacing? | F10/F11/F13/F18 | 1/3/4 |
| R12 | Intel PresentMon | Are measured frames submitted, rendered or actually displayed? | F12/F20 | 4 |
| R13 | Factorio | Can graphics cost be separated from simulation cadence and correctness? | F09/F12/F20 | 3–4 |
| R14 | Unreal/Fortnite and Godot | Can cold pipeline work be separated from steady calibration? | F07/F08/F10/F20 | 3–4 |
| R15 | EA SPORTS FC 26 | Should resolution adapt only when pixel-sensitive GPU work is limiting? | F08–F12 | 3–4 |
| R16 | Unity Adaptive Performance | Can a bounded controller avoid oscillation and wrong-resource changes? | F09/F10/F12 | 3–4 |
| R17 | Fortnite energy research | Can qualified GPU headroom and idle-Home behavior reduce power? | F10/F12/F20 | 4 |
| R18 | Boat Attack thermal case | Can presentation-only interventions remain useful after thermal soak? | F12/F17/F20 | 4 |
| R19 | Apple Game Mode and Metal HUD | Does the benchmark reproduce the player's actual app/display/scaler path? | F08/F12/F20 | 3–4 |
| R20 | AMD FSR2 integration | Does temporal reconstruction preserve distant aircraft and pilot cues? | F08/F10/F18/F20 | 4 |

## A. Recovery, capabilities and player intent

### R01 — Warzone 2100: persistent renderer initialization recovery

**Source evidence.** Warzone 2100's 4.6 release notes describe trying alternative graphics backends on first launch or initialization failure. The inspected source writes the backend being attempted; a later launch treats an unfinished attempt as a crash and removes failed candidates. Successful initialization clears its progress record. [Release, September 2025][S01] [Pinned recovery implementation][S02]

**OpenRC proposal.** Implement a versioned renderer-transition transaction around the existing planner and guard. Record the starting active facts, player intent, target, attempt count and fallback before launching the child. Verify that the record was saved. Distinguish a failed initialization from a successful launch whose new adapter description reverses the policy recommendation.

**Experiment.** Construct a small multi-process harness for the actual exported entry path. Inject failure before renderer initialization, before GDScript, after startup and before confirmation. Include corrupt state, unwritable storage, no previous working renderer, failed fallback and a new explicit retry. Separately replay the audit's alternating RX 6800M descriptions through successful process launches. Inspect persisted state after every boundary.

**Decision gate.** For a proposed initial budget of one automatic trial plus one fallback, every case must reach a confirmed usable renderer or a diagnosable stop without another automatic restart. User intent must survive; failed persistence must not be reported as armed recovery. A still-hung process requires supervision or termination/relaunch, which must be stated separately from next-launch recovery.

**Transfer limit.** Warzone's marker demonstrates crash recovery, not convergence after two successful but alternating recommendations. OpenRC needs the additional transition budget. Do not copy unchecked persistence behavior or assume a successful process launch establishes sustained graphics performance.

**Owner and output:** rendering/startup with DT; F01/F02/F15, Phase 1. Deliver a transition-state specification and exported failure-injection receipts.

### R02 — OpenMW: verify effective antialiasing and bound fallback

**Source evidence.** OpenMW's inspected window-creation code reduces requested MSAA when creation fails or the realized framebuffer reports fewer samples. It logs the fallback and retries at a lower sample count. The same code distinguishes SDL window size from drawable size. [Pinned implementation][S03]

**OpenRC proposal.** Give each relevant setting separate requested, supported, applied and verified fields. For AA, determine exactly which facts Godot beta2 exposes for each renderer and scaler combination. Keep the saved request when a session requires a temporary fallback. A viewport property should remain a configured value unless a stronger observation verifies effective behavior.

**Experiment.** Inject requested 8× with a 4× supported result; repeated creation failure down to disabled AA; an unrelated window-initialization failure; renderer restart; and a temporal scaler that changes the effective AA path. Check the production report, UI, cache key and later retry. On one qualified backend, use a native capture or trustworthy engine receipt to compare the effective result with the report.

**Decision gate.** Fallback must terminate, never claim a higher effective sample count than the available evidence, and preserve the request across restart. Calibration must reference the effective workload generation or explicitly say it is unverified. Missing readback must not become a success value.

**Transfer limit.** OpenMW's implementation changes its AA setting during fallback. Preserving separate saved intent is our adaptation. A window-creation failure does not prove AA was its cause; retain an unknown/initialization-failed reason unless stronger evidence exists. SDL/OpenGL framebuffer handling is not a portable Godot API; one native verification cannot qualify Vulkan, Metal, D3D12 and Compatibility together.

**Owner and output:** rendering and UI; F06/F18, Phases 2–3. Deliver a per-backend evidence table and a tested finite fallback contract.

### R03 — Luanti: gate an optional feature by actual prerequisites

**Source evidence.** Luanti's shadow renderer checks support on its active driver, chooses supported floating-point texture formats, and declines initialization when required formats are unavailable. The inspected code establishes feature eligibility independently of a GPU marketing name. [Pinned shadow renderer][S04]

**OpenRC proposal.** Take one expensive optional feature, such as a qualified shadow or reconstruction path, and trace it through four distinct states: eligible, resources created, configured in the scene, and observed running. Extend OpenRC's existing runtime capability checks rather than adding a second independent capability registry.

**Experiment.** Inject an absent mandatory capability, an unavailable preferred format with a valid fallback, total format failure, resource-creation failure and successful creation without a completed observation. Then qualify the actual scene path on a native backend. Verify that the feature's status and reason propagate to Settings, reports and workload invalidation.

**Decision gate.** Every failure must leave a usable supported configuration, retain the saved request and produce the same effective state in all consumers. The system may say eligible or configured before an execution receipt exists; it may not say verified merely because a capability query returned true.

**Transfer limit.** Luanti's formats and OpenGL version conditions belong to its renderer. Capability support does not establish acceptable frame time or prove output correctness. Automatic quality still needs performance evidence after eligibility is established.

**Owner and output:** rendering feature owner; F05/F18/F20, Phase 2. Deliver one complete feature-state trace before generalizing the pattern.

### R04 — SuperTuxKart: narrow, evidence-linked driver workarounds

**Source evidence.** SuperTuxKart maintains a graphics-restriction table that can combine adapter/vendor text, OS and driver-version comparisons with a named feature restriction. Its table includes both bounded and broad historical rules. [Pinned restriction table][S05]

**OpenRC proposal.** Keep workarounds separate from performance classification. A reproduced driver defect should disable or redirect its demonstrated feature, not automatically demote the entire GPU family. Each rule should carry an evidence link, affected engine/backend and driver scope, owner, review condition and fallback reason.

**Experiment.** Start with synthetic rules rather than inventing a real driver blacklist. Exercise below/at/above version boundaries, missing versions, different vendor numbering, two backends on the same adapter, an OS mismatch and a driver update. Verify that the same reason is visible in the resolved plan and that only materially affected calibration is invalidated.

**Decision gate.** All fixtures must match their independently specified expectation; unrelated features must remain unaffected. Unknown versions must be handled by a declared rule rather than an arbitrary numeric conversion. A production restriction needs an OpenRC reproduction or directly applicable engine defect with a verified affected range.

**Transfer limit.** Upstream historical restrictions are not current OpenRC evidence. String parsing can itself fail, so prefer structured driver information when available and retain uncertainty. Review and expiry conditions must prevent a temporary workaround becoming a permanent invisible quality penalty.

**Owner and output:** rendering/platform maintainers; F03/F08/F18, Phase 2. Deliver a minimal rule schema, boundary corpus and diagnostic reason format.

### R05 — 0 A.D.: separate hardware defaults from player preferences

**Source evidence.** The inspected 0 A.D. hardware detector writes into a separate `hwdetect` configuration namespace. Its comments give local preferences higher priority than detected defaults, and the inspected path limits its rules to GL/GLARB. [Pinned detector][S06]

**OpenRC proposal.** Formalize four layers: shipped defaults, automatic recommendations, saved player requests and temporary effective fallbacks. Re-detection should refresh recommendations. Returning a control to Automatic should remove only that control's override. Restore, re-detect and remeasure must be different operations with explicit transactional effects.

**Experiment.** Exercise Auto → Manual → Auto for renderer, Scene detail, AA and reconstruction. Combine these with guard failure, unsupported features, Restore → Revert → unrelated Keep, defaults-already-equal and failed calibration deletion after display-save commit. Read back both saved and in-memory values after restart and after cancellation.

**Decision gate.** Every explicit request survives an unrelated optimization or temporary capability fallback. An uncommitted reset produces no disk effect. A partially successful commit is reported and retryable. The UI and diagnostic report must identify which layer determined each effective setting.

**Transfer limit.** Do not copy 0 A.D.'s old hardware exceptions or treat its GL scope as coverage for modern backends. OpenRC's physical scenario settings, including the RC circuit, must remain outside graphics reset even if they currently share a preference file.

**Owner and output:** UI/persistence with rendering; F13/F14/F18 and F16 boundary protection, Phases 1–2. Deliver a precedence table and transaction tests that cover both values and side effects.

### R06 — Valve Steamworks: keep machine-specific graphics state local

**Source evidence.** Valve recommends storing graphics settings per device and excluding them from clouded saves. Its hardware guidance allows device-specific defaults while discouraging hiding settings solely because of the hardware identity. [Steamworks hardware recommendations][S07]

**OpenRC proposal.** Classify persistence by meaning before adding any sync, migration or configuration export. Player progress and portable preferences differ from display selection, renderer evidence, calibration, crash history and transient adapter identifiers. Treat a copied settings directory as a possible device migration, not proof that the same GPU remains present.

**Experiment.** Use two synthetic machine identities and two actual machines if available. Transfer only the proposed portable subset, then test an accidental whole-directory copy, restored backup, changed monitor and offline first launch. Verify that local device evidence is revalidated while portable choices survive. Test the ability to choose supported manual settings on a low-confidence or unrecognized GPU.

**Decision gate.** No measurement or failure record from device A may become device-specific proof on device B without corroborated identity and workload validity. Offline launch must work. Automatic defaults may be conservative, while real capability restrictions must be distinguished from a mere model-family preference.

**Transfer limit.** This is a persistence-design lesson; it does not establish that OpenRC currently uses Steam Cloud or needs a Steam integration. Nor does preserving manual choice require offering unsupported rendering features. Avoid uploading raw device identifiers as a side effect of implementing local optimization.

**Owner and output:** persistence/release with UI; F03/F08/F14/F15, Phases 1–2. Deliver a portable-versus-device-local state inventory and migration behavior.

## B. Active-device identity and recommendations

### R07 — D3D12 and DXGI: attach memory observations to the actual adapter

**Source evidence.** A D3D12 device exposes its adapter LUID, which DXGI can resolve to the corresponding adapter. The LUID's uniqueness is limited to the current system session. DXGI provides changing memory budgets and usage, with an optional notification mechanism. [Device correlation][S08] [DXGI mapping and budget][S09] [Budget notifications][S10]

**OpenRC proposal.** Investigate a small read-only native probe tied to the already-created D3D12 rendering device. Use the active adapter returned by Godot, with LUID correlation as a corroboration option rather than a requirement to enumerate again. Keep dedicated capacity separate from the process/node/segment-scoped budget and usage, and record timestamp and query availability. `AvailableForReservation` is not free VRAM. Start as diagnostics, without automatic resource mutation. [Query scope][S36] [Memory-field definitions][S37]

**Experiment.** The pinned engine returns its D3D12 logical device and physical adapter handles; the accessor enforces the render thread. First prove safe native-extension use, synchronization and teardown through that path. On a hybrid Windows machine, compare independently observed active GPU with the probe under each available OS GPU preference and after a renderer change. Exercise absent D3D12, wrong-thread calls, failed `IDXGIAdapter3` acquisition, unavailable budget, event-registration failure and teardown. Requery after an observed budget-change event without assuming such an event must occur on demand. [Pinned handle mapping][S32] [Accessor and guard][S34] [Render-thread scheduling][S35]

**Decision gate.** A known-supported reference configuration must produce a correct non-unknown result; other records must match the active device or explicitly report unknown. Never persist a raw LUID as a permanent calibration identity. A wrong-thread zero result is an integration error, not missing hardware. Unregister the notification cookie and safely drain probe-owned waiters/queued work before teardown. Measure query overhead and main-thread impact before enabling the probe routinely.

**Transfer limit.** DXGI is Windows-specific. Godot's driver-resource API is not a promise that ordinary GDScript can safely dereference native pointers; Compatibility has no RenderingDevice. Handle retrieval is confirmed at beta2; safe extension lifetime and synchronization remain a feasibility gate. [Godot API scope][S11]

**Owner and output:** Windows/native rendering owner; F03/F06/F08, Phases 2 and 4. Deliver an active-device correlation receipt and a structured, optional memory snapshot.

### R08 — Vulkan, DRM and GLX: prove Linux cross-API identity

**Source evidence.** `VK_EXT_physical_device_drm` can associate a Vulkan physical device with Linux DRM nodes, including explicit absence. Another optional extension exposes PCI coordinates. `GLX_MESA_query_renderer` can query the current GLX renderer, with platform and availability limitations. These are different identifiers with different scopes. [Vulkan DRM][S12] [PCI properties][S13] [GLX/Mesa query][S14]

**OpenRC proposal.** Investigate corroborated mapping between the active Compatibility renderer and the active Vulkan physical device, recording each in its actual launch epoch. A matching marketing name or a separately created Vulkan device is insufficient. GLX vendor/device attributes alone do not provide a DRM node, PCI address or unique instance. Keep device-model identity separate from physical-device correlation, and leave records unmerged when evidence is ambiguous.

**Experiment.** On a two-GPU Linux system, collect active-context facts before and after an eligible renderer transition. The pinned Godot Vulkan driver exposes its actual `VkPhysicalDevice`; qualify the native bridge on the render thread instead of creating a second device to guess the answer. Include identical-model devices where available, changed enumeration order, a software renderer, missing extension, unknown IDs and an unrecognized name. Treat Wayland/EGL as a separate path; a GLX result must not imply EGL coverage. [Pinned Vulkan mapping][S33] [Thread requirement][S34]

**Decision gate.** The fixture corpus must produce zero false cross-device calibration reuse and no unbounded transition. At least one explicitly supported native case must produce correct non-unknown correlation; otherwise retain the work as an unresolved feasibility study. Missing or ambiguous identity must yield unknown and a conservative plan, without blocking ordinary launch.

**Transfer limit.** PCI locations and DRM node numbers are correlation evidence, not universal permanent serial numbers. Compare the same DRM node type or use a separately verified primary-to-render-node mapping; revalidate session-scoped associations. Vendor/device model IDs cannot distinguish two identical cards. Any native bridge must first be qualified against the exact Godot backend and resource lifetime.

**Owner and output:** Linux/platform and rendering owners; F01/F03/F04, Phase 2. Deliver a cross-backend evidence matrix with explicit unsupported cases.

### R09 — Unreal/Lyra: compute a recommendation before applying it

**Source evidence.** Epic documents a hardware benchmark that derives CPU/GPU performance indices and recommended scalability groups, followed by a separate apply-and-save operation. Lyra also documents configuration priorities; device profiles can override scalability values. [Lyra scalability and device profiles][S15]

**OpenRC proposal.** Preserve the current policy as the baseline, then add a pure resolver that accepts hardware facts, valid measurements, requested settings and recovery constraints. Its output should contain a recommendation, proposed eligible plan, reasons and uncertainty. Actual effective state follows application and available readback. Computation alone should neither write preferences nor restart the renderer.

**Experiment.** Replay frozen inputs through both the current and candidate models. Include unknown families, precise mobile variants, memory boundaries, missing CPU/GPU evidence, manual settings, recovery vetoes and renderer fallback. For native validation, hold out devices or workload classes from fitting. Define wrong-tier decisions against an independent pacing-and-readability oracle; compare measured target misses, not just agreement with a snapshot generated from the candidate itself.

**Decision gate.** Identical inputs must produce identical results and reasons. Recommendation-only execution must cause zero settings writes or renderer restarts. Explicit user intent must remain authoritative within actual capabilities. New thresholds require held-out evidence under a predeclared error tolerance and the existing visual/performance gates.

**Transfer limit.** Unreal's synthetic indices and thresholds are not Godot scores. Its exact priority order is not OpenRC's contract: a device profile must not silently replace the user's supported choice. A richer model is justified only if it improves decisions beyond the uncertainty of the existing evidence.

**Owner and output:** policy/rendering with UI; F05/F09/F18/F20, Phases 2–4. Deliver a pure resolved-plan interface, traceable decision corpus and held-out comparison report.

## C. Qualification, pacing and measurement validity

### R10 — SuperTuxKart: repeatable routes and time spent missing the target

**Source evidence.** SuperTuxKart's benchmark uses a replay on a demanding track and warns that camera and multiplayer workload affect applicability. Its developer article supplements FPS with time spent in slow frames and excess duration beyond a target. [Performance guide][S16] [Benchmark design, July 2024][S17]

**OpenRC proposal.** Keep the short first-flight check as opportunistic feedback and add an optional repeatable qualification route using existing replay/graphics tools. Fix aircraft, scenery, camera, weather, accepted inputs, renderer and relevant settings. Report the actual workload class so evidence from a light view cannot silently qualify every activity.

**Experiment.** On one CPU-limited and one GPU-limited host, repeat baseline/candidate routes and then validate the selected tier on a second workload. Retain p50/p95/p99 intervals, deadline misses, longest bursts and time-weighted over-budget behavior. For target period T and measured intervals d_i, proposed raw diagnostics are sum(d_i where d_i > T)/sum(d_i) and sum(max(0, d_i-T))/sum(d_i). Record units, timestamp scope, the actual refresh/target, pause and missing-sample rules. Predeclare a jitter tolerance for acceptance so nominal 16.67 ms samples do not all become failures against an exact 16.666… ms threshold; retain the raw metric separately.

**Decision gate.** The repeated route must meet declared repeatability and the project's pacing gates. A candidate tier must be remeasured after selection. Time-weighted diagnostics supplement existing acceptance; SuperTuxKart's own thresholds must not be imported as OpenRC pass criteria.

**Transfer limit.** A replay cannot establish live pilot control, every vehicle class, thermal sustainability or latency at the transmitter. Native input/camera acceptance remains separate. Keep cold-load and first-use effects visible rather than trimming every inconvenient interval from the benchmark.

**Owner and output:** PT/VQ measurement owners; F07/F09/F17/F20, Phases 3–4. Deliver a versioned route manifest, raw intervals and an independently specified reducer.

### R11 — Forza Motorsport: settings transitions and refresh-rate edge cases

**Source evidence.** Forza Motorsport's February 2024 Update 5.0 notes report fixes for erratic frame rate after Revert and failure to improve performance after moving from High to Low. Update 5.1 separately fixes stutter or a lock below 60 FPS in Featured Multiplayer on PC at refresh rates such as 100/165 Hz. These are historical, product-specific defects. [Update 5.0][S18] [Update 5.1][S31]

**OpenRC proposal.** Treat applying, reverting and restoring graphics as workload transitions with explicit completion. The benchmark and UI must refer to the same completed generation of settings. Add a refresh/cap/VSync matrix to the native campaign, alongside the audit's specific LOD-reapplication and reset-transaction repairs.

**Experiment.** For live-changeable controls such as Scene detail, run High → Low → Revert, Auto → Manual → Auto and Restore → Revert from the supported Home/flight settings routes. Test the High/Standard renderer restart only from Home; in flight or Pause, verify its refusal preserves state. Inspect viewport LOD, AA, shadows, reconstruction, applied dimensions and calibration generation. On available 60/100/120/144/165 Hz displays, compare supported caps and VSync/VRR states with external presentation evidence. Separate transition, pipeline rebuild, settling and steady workload. [Existing restart boundary][rendererRestart]

**Decision gate.** Revert must restore all owned effective settings and produce no delayed disk action. A new quality setting must be reflected by all consumers before calibration resumes. Required pacing cases must satisfy declared display-specific limits without regression. A 60 FPS cap on a fixed 100 Hz display cannot be assumed to have equal refresh spacing; diagnose achievable behavior before labelling it a bug.

**Transfer limit.** Forza's release notes do not disclose root causes or prove the same display defect in OpenRC. They justify a high-value regression matrix. Do not assert that changing every cap will improve performance, or that average FPS verifies the presentation result.

**Owner and output:** UI/rendering with PT; F10/F11/F13/F18, Phases 1, 3 and 4. Deliver an application/revert matrix and exported display-pacing receipts.

### R12 — Intel PresentMon: distinguish submitted, rendered and displayed frames

**Source evidence.** PresentMon documents metrics for the interval between Present calls, changes to the displayed image, and the time a frame was displayed. Display-related fields can be unavailable when a frame was not displayed. Process, swapchain and presentation-mode context matter. [PresentMon metric definitions][S19]

**OpenRC proposal.** Add an independent Windows observation path to the existing native graphics campaign. Keep engine process-loop intervals, GPU work and displayed intervals in separate fields, each with source, version, units, validity and missing-value semantics. Preserve dropped and unavailable observations; never fill them with zero.

**Experiment.** Pin a supported PresentMon build and inspect its actual output schema. Capture the exported app's intended PID and swapchain under VSync on/off, a frame cap, a scene transition and a deliberately overloaded visual workload. Correlate time windows and compare uncaptured, engine-only and externally observed runs. Include any generated-frame path only if the instrumentation distinguishes it reliably.

**Decision gate.** A run cannot be qualified from the wrong process or swapchain. Every advertised metric must be available and interpreted according to the pinned version, or explicitly unavailable. Observer overhead must remain within the relevant campaign's declared bound. The acceptance report must show both process-loop and presentation outcomes when both are available.

**Transfer limit.** PresentMon is a Windows measurement route, not a universal graphics SDK. A display event is not an optical input-to-photon measurement. Keyboard/mouse latency fields do not qualify the RC transmitter path, and a rendered-frame count does not prove all frames reached the display.

**Owner and output:** PT/DT measurement owners; F12/F20, Phase 4. Deliver a versioned capture recipe, schema validator and timing-scope glossary.

### R13 — Factorio: protect simulation cadence while diagnosing graphics

**Source evidence.** Factorio's historical development article distinguishes rendering FPS from simulation UPS. When rendering cannot keep pace, it can skip rendering updates while preserving simulation updates; CPU-heavy simulation is a separate limitation. The article also explains why intermittent frame delays matter beyond the average. [Factorio Friday Facts 70, January 2015][S20]

**OpenRC proposal.** Make the fixed 240 Hz simulation an invariant of graphics optimization. Diagnose complete-session CPU work, rendering CPU work, GPU work and simulation/wall progress separately. When a graphics reduction fails to help a CPU-bound case, preserve that negative result instead of repeatedly lowering image quality.

**Experiment.** Use the same accepted input tape and physical scenario for a presentation-heavy case and a simulation-heavy case. Change one qualified visual control at a time. Record exact/tolerance replay outcomes, simulation tick timing, unpaused simulation/wall ratio, frame intervals and input/control evidence. Include a low-render-cost configuration that still misses the CPU target to verify the controller's behavior.

**Decision gate.** Graphics changes must preserve the existing state/input/checkpoint contract and 240 Hz cadence. The simulation/wall ratio must stay within 0.99–1.01 for the required workload. A CPU-limited outcome must not trigger an unsupported promise that lowering internal pixels will solve it. Any tick-cost claim must use the owning statistic and scope.

**Transfer limit.** Factorio's 60 UPS architecture is not OpenRC's architecture. This investigation does not propose changing simulation frequency, skipping physics, simplifying collision, widening tolerances or rewriting goldens. It also does not prove that every CPU bottleneck can be removed through a graphics option.

**Owner and output:** PT with simulation and rendering owners; F09/F12/F20, Phases 3–4. Deliver a bottleneck-evidence contract and a graphics/simulation independence report.

### R14 — Unreal/Fortnite and Godot: separate pipeline cold starts from steady calibration

**Source evidence.** Epic describes PSO precaching informed by materials, meshes and required rendering state, including Fortnite experience and remaining version-specific gaps. Godot's 4.6 documentation distinguishes shader work from driver pipeline compilation, describes precompilation/ubershaders for Forward+/Mobile, and notes that changes such as MSAA can trigger new pipelines. [Epic PSO article, February 2025][S21] [Godot pipeline compilation guide][S22]

**OpenRC proposal.** Give calibration explicit preparation, settling, valid sampling, evaluation and post-change validation states. Keep first-use and loading regressions as separate evidence. Use the existing warmup and graphics tools, extending only the missing observable boundary; do not classify every hitch as either permanent GPU weakness or harmless warmup.

**Experiment.** Compare declared process-cold, verified cache-cold and warm runs. Use an isolated cache-cold setup where the platform supports and verifies it; otherwise mark driver-cache state unknown. A private app-data directory alone does not prove a cold driver cache. Visit first night/storm/smoke appearances and profile application without clearing a user's global cache. Measure the settled workload after warmup; repeat after changing AA or reconstruction, and reject obsolete-generation samples with an explicit reason.

**Decision gate.** Only complete, single-generation steady samples may promote a profile. Incomplete or contaminated samples must remain retryable; attribute contamination to pipelines only with supporting counters/timestamps. Cold/load runs must independently meet their owning goals; reducing hitches by hiding more time in preparation is not free. Report preparation duration and the first-interactive-frame boundary.

**Transfer limit.** Epic's PSO implementation and reported compile counts are not portable to Godot. The cited Godot guide is version 4.6; implementation decisions must be checked against OpenRC's pinned 4.8 beta2. Compatibility and RenderingDevice paths require separate treatment.

**Owner and output:** rendering/loading with PT; F07/F08/F10/F20, Phases 3–4. Deliver a calibration state diagram, cold/warm manifests and first-use hitch attribution.

## D. Controlled adaptation, power and visual acceptance

### R15 — EA SPORTS FC 26: adapt resolution only for the right bottleneck

**Source evidence.** EA describes FC 26 dynamic resolution as responding when GPU-limited while pursuing a frame-rate target. Its PC guide also explains that different controls affect CPU, GPU and video-memory load differently. The document does not publish the controller's full algorithm. [FC 26 PC deep dive, September 2025][S23]

**OpenRC proposal.** Build a measured cost map for existing controls: pixel-sensitive GPU cost, render-CPU cost, memory pressure, transition cost and visual importance. Investigate dynamic internal resolution only when trustworthy measurements indicate a pixel-sensitive GPU limit. Keep output resolution and HUD requirements separate from internal rendering scale.

**Experiment.** Test two identical-output scenarios: one GPU/pixel-limited and one CPU-limited. Run the approved internal-scale ladder while holding simulation, camera and other graphics controls constant. Measure GPU/CPU intervals, target misses, memory where available and pilot readability. Then compare a fixed scale with a bounded dynamic candidate on the same route, including a scene transition and a missing-timing case.

**Decision gate.** The GPU-limited case needs improvement beyond run variation while meeting the visual and pacing contract. The CPU-limited case must not repeatedly sacrifice resolution without demonstrated benefit. Missing or stale timings must suspend adaptation or use an explicitly qualified fallback. Every scale change must invalidate or segment workload-dependent calibration.

**Transfer limit.** This is a hypothesis about OpenRC's existing controls, not evidence that FC 26's policy is directly reusable. Do not import cloth or physics quality reductions. A resolution reduction can alter readability even when it improves FPS, particularly for distant aircraft and fine lines.

**Owner and output:** rendering/reconstruction with PT and pilot owner; F08–F12, Phases 3–4. Deliver a cost map, bounded scale experiment and adopt/reject decision.

### R16 — Unity Adaptive Performance: design a controller that can hold steady

**Source evidence.** Unity Adaptive Performance 5.1.6 documents provider-dependent thermal/performance information and a scaler system with bounds, target-impact estimates and action delays. Available information depends on the platform/provider. The package is a framework, not evidence that every device supplies the same reliable signal. [Adaptive Performance manual][S24]

**OpenRC proposal.** Prototype a presentation-only controller with explicit observe, settle, adjust, cooldown and unavailable states. Make degradation and recovery asymmetric. Change one control at a time, enforce bounds, honor manual ownership and attach every sample to the active settings generation. Treat an absent provider as a normal supported condition.

**Experiment.** Replay recorded and synthetic timing sequences containing sustained overload, one spike, alternating load, recovery, stale samples and missing data. Compare a small predeclared grid of observation windows, hysteresis bands and cooldowns before any live deployment. Then qualify the best bounded candidate on native hardware, including user changes and a display/scene transition during cooldown.

**Decision gate.** In a defined steady-load sequence, the controller must settle without repeated direction reversals. Outliers must not cause immediate quality changes, and manual settings must remain unchanged. After any adjustment, the next decision requires fresh settled evidence from the new generation. Recovery time and number of adjustments must remain within predeclared limits.

**Transfer limit.** Unity's package and providers cannot be presumed available in Godot or on desktop systems. Do not adopt a physics-frequency scaler. A trace simulation proves controller logic only; native validation must establish measurement validity, transition cost and useful performance.

**Owner and output:** rendering policy with PT; F09/F10/F12, Phases 3–4. Deliver an offline controller comparison and a disabled-by-default prototype only if its decision gates pass.

### R17 — Fortnite: qualify useful GPU headroom and an idle Home policy

**Source evidence.** Epic's 2023 power whitepaper describes a visually reviewed internal-resolution ceiling on PS5/Xbox Series X and separate lobby-inactivity policies. Its PC energy mode changed frame rate while retaining resolution because varied AA options complicated quality guarantees. Observations are platform- and method-specific. [Fortnite power whitepaper, especially pages 6–8 and 13][S25]

**OpenRC proposal.** Investigate two clearly separated operating states within one energy study. First, test a frame-cap-only policy in an eligible inactive Home screen, with immediate restoration on interaction. Later, test whether a visually qualified internal-resolution ceiling produces a more sustainable flight experience. Qualify any idle resolution reduction separately for each supported reconstruction/AA path. Keep the project's energy and Apple owners involved.

**Experiment.** In Home, compare baseline and a conservative candidate while idle, interacting, changing focus and entering flight. Disable the idle policy during capture, benchmarking or other declared foreground work. In active flight, compare qualified fixed ceilings under matched output, frame target, thermal/power state and route. Measure complete-workload energy or power with stated scope, not GPU utilization alone.

**Decision gate.** Home behavior must never activate in live flight because the sticks are held steady. Input and flight-entry recovery must meet a predeclared response bound and the normal loading/pacing goals. Flight headroom is accepted only with preserved visual/control quality and repeatable sustainable benefit. Keep idle and active-flight results separate.

**Transfer limit.** Fortnite's scale percentages, inactivity timeout and reported energy savings are not OpenRC defaults. Lower utilization alone does not prove lower system energy. Native output, reconstruction quality and actual display behavior must be verified on the tested platform.

**Owner and output:** UI/rendering and energy/platform owners; F10/F12/F20, Phase 4. Deliver a Home-state eligibility table and separate idle/flight energy receipts.

### R18 — Boat Attack: evaluate reversible responses after thermal soak

**Source evidence.** Unity's Adaptive Performance 4.0 article demonstrates Boat Attack on an unfolded Samsung Galaxy Z Fold3. The example observes a thermal/performance problem and changes rendering workload through scalers. It is a vendor demonstration on a specific mobile device, not a cross-platform controlled OpenRC result. [Boat Attack case, June 2022][S26]

**OpenRC proposal.** Investigate whether presentation-only adjustments can sustain the selected experience after a laptop or fanless system warms up. Use a supported thermal signal if available; otherwise report sustained performance decline without inventing a temperature diagnosis. Maintain visual and control cues that pilots rely on.

**Experiment.** Select a bounded intervention, such as a qualified shadow setting or internal scale, and compare it with an unchanged baseline under matched initial conditions. Follow the owning sustained-run protocol. Include recovery, plugged/unplugged cases as separate claims, and a platform without thermal telemetry. Keep weather, smoke cues, collision and simulation workload constant.

**Decision gate.** The candidate must show a reproducible sustained benefit beyond variation and preserve the normal pacing, simulation and pilot-acceptance gates. Missing thermal data must remain unavailable. The controller must recover predictably within its declared bounds without cycling settings, concealing a leak, or silently making the physical scenario easier.

**Transfer limit.** Samsung provider behavior and mobile temperature thresholds do not define macOS, Windows or Linux policy. The Boat Attack demo does not establish an OpenRC effect size. For Apple baseline/finalist acceptance, the existing three independent 30-minute active-flight runs per role remain required; a short screen cannot replace them.

**Owner and output:** platform/energy with rendering and pilot owners; F12/F17/F20, Phase 4. Deliver a sustained before/after record with availability and power-state boundaries.

### R19 — Apple: benchmark the actual application, display and scaler path

**Source evidence.** Apple documents Game Mode for supported Apple-silicon Macs in native fullscreen. The macOS 26 release notes identify direct Terminal execution as a Game Mode issue and describe opening the app bundle as a workaround. Metal HUD documents Game Mode, layer/scaling, thermal and performance observations, including conditional MetalFX fields. [Game Mode][S27] [macOS 26 release notes][S28] [Metal HUD metrics][S29]

**OpenRC proposal.** Extend the existing DT-MAC-08b owner and Apple evidence manifest. Record app-bundle launch path, actual Game Mode state, display refresh, native drawable/output dimensions, internal scale, renderer and available scaler observations. Compare the packaged player route with diagnostic launch routes before interpreting a difference as a graphics optimization.

**Experiment.** On one qualified Apple host, compare supported packaged launch and diagnostic launch under matched fullscreen, output, cap and workload. Then compare the relevant reconstruction configurations with an identical output target. Capture short HUD observations separately from timed runs, and retain native frame intervals for the existing percentile reducer. Check behavior when the user has disabled Game Mode.

**Decision gate.** Every claimed configuration must identify the actual launch/display/scaler path or explicitly state what is unverified. The user-facing native-output requirement must remain satisfied. A HUD observation alone cannot close all viewport or pixel-completion claims; measured workload and visual acceptance remain necessary.

**Transfer limit.** Game Mode is already assigned to DT-MAC-08b; this is a qualification refinement. The documented Terminal issue is scoped to the cited OS release notes. Metal HUD's rolling averages are not frame-time p95/p99, and MetalFX-specific fields are available only for relevant effects.

**Owner and output:** existing Apple/DT-MAC-08b and reconstruction owners; F08/F12/F20, Phases 3–4. Deliver a launch/display manifest and verified observation matrix.

### R20 — AMD FSR2: qualify temporal reconstruction around pilot perception

**Source evidence.** AMD's FSR2 integration manual describes motion-vector conventions, depth and jitter inputs, reactive-mask handling for applicable content, history reset after discontinuities and mip-bias considerations. These requirements help explain why temporal reconstruction must be evaluated on moving content and transitions. [AMD FSR2 manual][S30]

**OpenRC proposal.** Use those failure mechanisms to audit the engine integration and build pilot-specific temporal tests. Qualify silhouette, orientation and landing cues at small projected sizes, propeller motion, thin wires, transparent smoke, dark aircraft and scene/camera changes. Compare identical output targets rather than interpreting equal internal resolution as equal presentation quality.

**Experiment.** First inspect which hooks and reconstruction version the pinned engine actually provides; do not assume all SDK controls are exposed. Capture matched moving routes with the supported native/AA baseline and candidate temporal path. Include close, 20/50/100 m and the existing farther acceptance range, camera cuts, zoom changes, reset, smoke, night and landing approach. Record projected aircraft size and HUD/aids.

**Decision gate.** Randomized matched clips and the owner pilot circuit must show no new repeatable loss of attitude, subject or landing cues. Temporal artifacts and transition failures must be attributed and resolved or excluded by a clear supported-setting boundary. Performance must also meet the campaign gate. A favorable average FPS or image-similarity score cannot override a pilot-visibility failure.

**Transfer limit.** The cited FSR2 manual does not prove that OpenRC's pinned Godot bundles that exact SDK revision or exposes its reactive-mask controls. Do not promise a fix that requires an unavailable engine hook, and do not silently upgrade the renderer to obtain it.

**Owner and output:** reconstruction/visual-quality with pilot and PT owners; F08/F10/F18/F20, Phase 4. Deliver a versioned temporal-risk checklist and matched motion-acceptance pack.

## E. Implementation portfolio and dependencies

### What to do first

The strongest initial investment is in recovery, ownership and measurement validity. Those changes address known defects in the preceding audit and make every later performance experiment easier to interpret. More adaptive behavior should follow evidence that the system can identify its own applied workload, reject invalid observations and restore a working state.

| Priority | Work package | Research inputs | Required output before moving on |
| --- | --- | --- | --- |
| P0 | Recoverable renderer changes and transactional settings | R01, R05, R11 | Finite transitions, explicit failure results, preserved manual intent, no deferred reset after Revert, Home-only renderer restart |
| P0 | One traceable recommendation/application contract | R02, R03, R09 | Separate requested, recommended, proposed, configured and observed states; one reason vocabulary; all consumers agree |
| P1 | Correct device/evidence identity | R04, R06–R08 | No false calibration sharing, local evidence invalidation, optional native probes with demonstrated scope and overhead |
| P1 | Reproducible calibration and pacing evidence | R10–R14, R19 | Single-generation complete samples, repeatable route, candidate revalidation, cold/warm separation and timing-scope receipts |
| P2 | Bounded presentation adaptation | R15, R16, R18, R20 | Bottleneck-sensitive changes, stable controller, visual acceptance and sustainable native benefit |
| P2, small independent screen | Idle Home energy policy | R17 | Explicit Home eligibility, frame-cap-only first candidate, prompt restoration and measured energy benefit |

P0/P1/P2 express engineering priority, not a promise about calendar duration. Native probes, display combinations and thermal campaigns depend on actual hardware access. A probe that remains uncertain can be deferred while correctness work proceeds with explicit unknown states.

### Integration with the six-phase audit plan

| Phase | Actions informed by this research | Exit evidence |
| --- | --- | --- |
| 0 — Freeze the baseline | Retain the audited source/runtime identities, adversarial cases, current decisions and native baselines. Inventory existing A0–A7 status and assigned owners before adding tasks. | Every comparison identifies its baseline, dirty patch if any, input data and available hardware; no historical run is presented as a new result. |
| 1 — Startup and user intent | Apply R01/R05/R06 and the transactional part of R11. Separate graphics reset from physical scenario; preserve requests across failure, migration and return to Automatic. | Finite process-level recovery, checked persistence outcomes, complete restore/revert contract and explicit renderer restart boundary. |
| 2 — Identity and resolved policy | Apply R02–R04 and R07–R09 to the existing centralized policy. Add evidence availability, confidence and scope; qualify native handle access before policy use. | Deterministic proposed plan, correct active-device observations on supported cases, no false matches, accurate effective-state reporting. |
| 3 — Calibration | Use R10/R11/R13/R14 and the measurement prerequisites of R15/R16/R19. Segment workload generations, retain retryable failures, remeasure changed tiers and extend covered activities. | Complete representative samples; rejected/expired evidence never promotes; every accepted tier validated after its own application. |
| 4 — Hardware qualification | Execute R10–R20 as applicable to named hosts. Keep pacing, presentation, simulation, visuals, energy and thermal evidence distinct; qualify actual exports. | Required native cases and sustained gates pass; untested platforms/backends remain unqualified; held-out errors and uncertainty reported. |
| 5 — Release and explanations | Publish reasons, provenance, versioned migrations, release limitations and rollback conditions through the existing owning plan. Enable a new automatic behavior only for qualified scope. | Reproducible decision receipts, understandable UI/report, preserved manual controls and tested recovery to the prior policy. |

The repository's VQ-07h A1 centralization is already recorded as completed in the audit baseline. Extend that owner instead of building a parallel resolver or rewriting completed work from scratch. Apple Game Mode remains under DT-MAC-08b. Source research belongs in dated research evidence; implementation status belongs in the canonical [automatic graphics plan][autoPlan].

### Shared data contract to investigate

These are proposed responsibilities and fields, not a demand for a new framework. Reuse existing objects where their ownership is clear.

| Record | Essential distinction | Why it matters |
| --- | --- | --- |
| Device facts | Model identification versus active physical-device correlation; provider, confidence and renderer epoch | Similar strings and identical models must not silently share evidence. |
| Capability facts | Supported, unsupported, unavailable, query failed; backend and engine scope | An integration error or unavailable API is not an unsupported GPU. |
| Requested state | Automatic/manual ownership and saved user value | Recovery and optimization must not erase intent. |
| Proposed plan | Eligible values, reason codes, uncertainty and policy version | Recommendation can be inspected before any mutation. |
| Applied observation | Configured value, verified value if available, source and completion time | A property write is weaker evidence than observed execution. |
| Workload identity | Renderer/backend, driver/engine, output/internal pixels, AA/scaler, relevant effects, camera/activity and generation | Old samples cannot qualify a materially changed workload. |
| Calibration receipt | Target, timing scope, window, completeness, exclusions, expiry and result | An incomplete attempt must not become a permanent successful cache entry. |
| Resource observation | Capacity, process budget, usage, segment/node, timestamp and availability | Allocation counters, budget and physical memory are different quantities. |
| Transition receipt | Trial/fallback budget, prior state, pending confirmation and persistence outcome | Recovery must work across processes and survive partial failure. |

For native identity work, the safe starting boundary is an optional read-only diagnostic. Obtain the active global RenderingDevice resource on the render thread; copy qualified observations into a session-tagged result; avoid retained raw handles and work after teardown. Use policy-neutral output until ownership, synchronization, overhead and false-match behavior have passed their native gates. The pinned source confirms handle retrieval, not this entire integration contract. [D3D12][S32] [Vulkan][S33] [Accessor][S34] [Scheduling][S35]

### Common acceptance contract

**Keep existing gates authoritative.** The general campaign requires at least 10 seconds warmup and 60 seconds sampling in three alternating baseline/candidate pairs. At the existing 60 Hz gate, process-loop p95 must be at most 18 ms and p99 at most 25 ms, with unpaused simulation/wall ratio 0.99–1.01. Attribute recurring gameplay intervals over 50 ms. The active Compatibility delivery retains its combined +0.5 ms frame-p95 cost ceiling against the frozen baseline; the allowance does not reset on each merge. Retain loading, lifecycle, native export, exact/tolerance replay and readability requirements. These are process-loop criteria, not proof that every displayed frame meets 16.67 ms. [General numerical and human acceptance][graphicsGates]

**Use the Apple campaign where applicable.** Short candidate decisions require at least five independent alternating pairs, initially 30 seconds warmup plus 120 seconds measured. Baseline/finalist sustained qualification requires three independent 30-minute active-flight runs per role, excluding the 30-second warmup. AC and battery results remain separate. The existing adoption screen expects a meaningful improvement beyond variation and observer uncertainty, ordinarily at least 5% in the affected complete workload or removal of a reproducible hitch/leak/gate failure; a smaller defect repair can be justified explicitly. [Apple acceptance and campaign][appleGates]

**Predeclare new criteria.** Before an adaptive experiment, record the target/cap/refresh combination, exact timing and observer scope, allowed deadline misses, jitter tolerance, hitch-burst limit, controller adjustment bound, recovery time, required headroom and acceptable model error on held-out cases. Use the project's owning limits where they exist. If a necessary new criterion remains unspecified, the result is exploratory and cannot qualify a default promotion.

**Preserve the workload.** Compare identical accepted physics inputs and scene identity; hold visual-capture overhead outside timed runs. Native output and internal resolution must be recorded independently. General qualification starts at 1080p, extends upward when evidence supports it, and uses 720p as the later fallback case. Apple Retina claims preserve the native-output/reconstructed-result boundary. Do not obtain a graphics pass by changing 240 Hz physics, collision, aircraft definitions or the physical RC circuit. [Project instructions][agents] [Graphics campaign][graphicsGates]

**Measure uncertainty honestly.** Report per-run distributions and paired deltas, not a pooled set of correlated frames presented as independent trials. Keep available, unsupported, failed, stale and unknown measurements distinct. State unavailable hardware, failed runs, substitutions and exclusions. A speedup on one GPU does not establish a minimum specification or all-platform support.

**Retain enough to reproduce the decision.** Every experiment should retain its manifest, exact source/runtime and package identity, requested/effective settings, workload generation, raw relevant measurements, reducer/schema versions, observer cost, logs, visual/replay result, and adopt/retain/defer outcome. This is a proposed extension of the existing evidence workflow, not a new telemetry upload requirement.

### What should not be copied directly

- GPU marketing-name rules, legacy blacklists or synthetic benchmark thresholds from another game.
- A fixed fraction of nominal VRAM as a universal safe working budget.
- Foreign dynamic-resolution percentages, inactivity timeouts or thermal thresholds without OpenRC qualification.
- Physics-rate, collision or control-simulation reductions as graphics optimizations.
- Average FPS, a HUD average or a successful capability query as sufficient proof of the final experience.
- An engine SDK integration plan that assumes unexposed APIs or silently changes the pinned runtime.

### Proposed first reviewable bundle

Begin with five bounded outputs: a renderer-transition specification; a settings precedence/transaction table; a proposed/applied evidence contract; a versioned calibration state model; and one native measurement recipe with explicit missing-value behavior. Connect these to the existing F01/F02/F07–F15/F18 defects before expanding the hardware database or enabling runtime adaptation.

The research supports these design directions. It does not yet establish new OpenRC speedups, energy savings, visual gains or a wider supported hardware floor. Those conclusions require the experiments and decision gates above.

## F. Primary-source register

All sources below were accessed for this investigation on 21 November 2026. Historical articles are used for their mechanisms and lessons; their bugs, thresholds and platform support are not represented as current OpenRC behavior. Pinned code links preserve the inspected implementation. Moving manuals must be rechecked against the selected implementation version before development.

| Sources | Primary material | Version or scope |
| --- | --- | --- |
| [S01][S01], [S02][S02] | Warzone 2100 release and recovery source | Release 4.6; source `b8246a859a73ad04927e19f2f9e7732e45273dd5` |
| [S03][S03] | OpenMW engine initialization | Source `0f597313c938ad239d53685adb36b2af11ac5f84` |
| [S04][S04] | Luanti dynamic shadows | Source `84bd3cc0115dbdd259ef9a876cb1b0bd230e3cf6` |
| [S05][S05] | SuperTuxKart graphics restrictions | Source `b2a9f223326422aa2dd4eea28319b0c5115fde03` |
| [S06][S06] | 0 A.D. hardware detection | Archived source `61a3b9507d974084e6badb88a0826bd89a6d5b8b` |
| [S07][S07] | Valve Steamworks hardware recommendations | Current official developer guidance as retrieved |
| [S08][S08]–[S10][S10], [S36][S36], [S37][S37] | Microsoft D3D12/DXGI adapter and memory APIs | Windows API semantics; session, process and segment scopes |
| [S11][S11] | Godot RenderingDevice class | Stable documentation for API scope; exact implementation checked separately |
| [S12][S12]–[S14][S14] | Khronos Vulkan DRM/PCI and Mesa GLX extensions | Optional extensions; platform and context limitations |
| [S15][S15] | Epic Lyra scalability and device profiles | Official moving documentation as retrieved; thresholds are project-specific |
| [S16][S16], [S17][S17] | SuperTuxKart benchmark guide and developer article | Replay benchmark guide; July 2024 methodology article |
| [S18][S18], [S31][S31] | Forza Motorsport release notes | Updates 5.0 and 5.1, February 2024; historical defects |
| [S19][S19] | Intel PresentMon console documentation | Moving upstream README; pin actual tool/schema for experiments |
| [S20][S20] | Factorio Friday Facts 70 | January 2015 architecture discussion |
| [S21][S21] | Epic game engines and shader stuttering | February 2025 article; Unreal-specific PSO mechanisms |
| [S22][S22] | Godot pipeline-compilation guide | Version 4.6 documentation; not a substitute for beta2 source verification |
| [S23][S23] | EA SPORTS FC 26 PC deep dive | September 2025 official product explanation |
| [S24][S24] | Unity Adaptive Performance user guide | Package 5.1.6; provider-dependent signals and scalers |
| [S25][S25] | Epic Fortnite power whitepaper | 2023; console and PC policies explicitly distinguished |
| [S26][S26] | Unity Boat Attack thermal/performance demonstration | June 2022; Adaptive Performance 4.0, specific Samsung host |
| [S27][S27]–[S29][S29] | Apple Game Mode, macOS release notes and Metal HUD | Platform-specific behavior; release-note issue scoped to macOS 26 |
| [S30][S30] | AMD FidelityFX FSR2 integration manual | FSR2 technique documentation; does not identify Godot's bundled SDK revision |
| [S32][S32]–[S35][S35] | Godot D3D12/Vulkan resource access and thread contract | Exact `cafc17a192acf67903910a68aeb3c076c0907a4b` source |

[audit]: source-audit.md
[baseline]: https://github.com/bultodepapas/OpenRCsimulator/tree/57abea025f62b20233ca281d58d2acbee4ab8b8e
[agents]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/AGENTS.md
[autoPlan]: ../../../../plans/automatic-graphics.md
[rendererRestart]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/app/app_root.gd#L2005-L2032
[graphicsGates]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/docs/plans/advanced-graphics.md#L319-L334
[appleGates]: https://github.com/bultodepapas/OpenRCsimulator/blob/57abea025f62b20233ca281d58d2acbee4ab8b8e/docs/plans/apple-silicon-performance.md#L190-L205
[S01]: https://wz2100.net/news/version-4-6-0/
[S02]: https://github.com/Warzone2100/warzone2100/blob/b8246a859a73ad04927e19f2f9e7732e45273dd5/lib/sdl/resume_init_helpers.cpp#L124-L326
[S03]: https://github.com/OpenMW/openmw/blob/0f597313c938ad239d53685adb36b2af11ac5f84/apps/openmw/engine.cpp#L566-L635
[S04]: https://github.com/luanti-org/luanti/blob/84bd3cc0115dbdd259ef9a876cb1b0bd230e3cf6/src/client/shadows/dynamicshadowsrender.cpp#L116-L145
[S05]: https://github.com/supertuxkart/stk-code/blob/b2a9f223326422aa2dd4eea28319b0c5115fde03/data/graphical_restrictions.xml
[S06]: https://github.com/0ad/0ad/blob/61a3b9507d974084e6badb88a0826bd89a6d5b8b/binaries/data/mods/mod/hwdetect/hwdetect.js#L177-L398
[S07]: https://partner.steamgames.com/doc/steamhardware/recommendations?l=english
[S08]: https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12device-getadapterluid
[S09]: https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-1-4-improvements
[S10]: https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_4/nf-dxgi1_4-idxgiadapter3-registervideomemorybudgetchangenotificationevent
[S11]: https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html
[S12]: https://docs.vulkan.org/refpages/latest/refpages/source/VK_EXT_physical_device_drm.html
[S13]: https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDevicePCIBusInfoPropertiesEXT.html
[S14]: https://registry.khronos.org/OpenGL/extensions/MESA/GLX_MESA_query_renderer.txt
[S15]: https://dev.epicgames.com/documentation/en-us/unreal-engine/scalability-and-device-profiles-in-lyra-sample-game-for-unreal-engine
[S16]: https://supertuxkart.net/cs/Performance_testing
[S17]: https://blog.supertuxkart.net/2024/07/why-average-fps-and-1-low-fps-are.html?m=1
[S18]: https://support.forza.net/hc/en-us/articles/26287905493139-Forza-Motorsport-Update-5-0-Release-Notes-February-14-2024
[S19]: https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md
[S20]: https://www.factorio.com/blog/post/fff-70
[S21]: https://www.unrealengine.com/tech-blog/game-engines-and-shader-stuttering-unreal-engines-solution-to-the-problem
[S22]: https://docs.godotengine.org/en/4.6/tutorials/performance/pipeline_compilations.html
[S23]: https://www.ea.com/games/ea-sports-fc/fc-26/news/pitch-notes-fc26-pc-deep-dive
[S24]: https://docs.unity3d.com/Packages/com.unity.adaptiveperformance@5.1/manual/user-guide.html
[S25]: https://cdn2.unrealengine.com/reducing-fortnites-power-consumption-layout-v03-ffedbeb1adeb.pdf
[S26]: https://unity.com/blog/engine-platform/mobile-performance-optimization-with-adaptive-performance-40
[S27]: https://support.apple.com/en-la/105118
[S28]: https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes.md
[S29]: https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics.md
[S30]: https://gpuopen.com/manuals/fidelityfx_sdk/techniques/super-resolution-temporal/
[S31]: https://support.forza.net/hc/en-us/articles/26616515185043-Forza-Motorsport-Update-5-1-Release-Notes-February-23-2024
[S32]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/d3d12/rendering_device_driver_d3d12.cpp#L5960-L5966
[S33]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/vulkan/rendering_device_driver_vulkan.cpp#L7289-L7295
[S34]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_device.cpp#L8970-L8977
[S35]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/RenderingServer.xml#L39-L44
[S36]: https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_4/nf-dxgi1_4-idxgiadapter3-queryvideomemoryinfo
[S37]: https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_4/ns-dxgi1_4-dxgi_query_video_memory_info

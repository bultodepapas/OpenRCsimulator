# Apple Silicon optimizations: reuse in the general game

Reviewed **2026-11-06**. Documentation-only audit under DT-MAC-00-R4 / VQ-01c, with SF/NK/FL ownership retained for simulation and recording.

**Execution follow-up, 2026-11-06:** the branch-only repairs below are now integrated into `main` through `cbd1aa8ae` (PR #8). Native Windows checks and six 1080p render-target timing runs are recorded in [section 7](#7-native-windows-follow-up-2026-11-06). The default cache-on path passed its short software pacing campaign; a comparative speedup remains inconclusive. Runtime defaults were not changed.

**Conclusion:** most recent Apple Silicon work that removes application work is already in shared game code. Windows and Linux already take those paths where the relevant effect is active. The useful next delivery is to integrate the remaining correctness repairs, measure these shared changes on non-Apple hardware, and selectively extend the existing graphics policy. There is no separate Mac shader implementation that needs copying into the general game.

“Already implemented” below means present in the inspected source, not a demonstrated speedup on every platform or inclusion in every downloadable build.

## Scope and source identity

- Inspected branch: `codex/m1-native-validation-20261106`, HEAD `e72d878b6b4a89209dfe1a992ba119921dcdd34c`.
- Main review window: November 2–6, 2026; older CPU/loading work is included only to avoid recommending work already done.
- Compared local refs: `main` = `bf4745d687d1f4e996d6114a7630de3ab9c478a0`; `origin/main` = `3df2791752fe2c1faad132fcb11febbb0ae788d1`; release tag `v0.1.10`. No fetch or remote publication check was performed. These are local snapshots, not claims about GitHub's current state.
- Existing uncommitted `app/sim/flight_session.gd` changes and the untracked `test_downwash_air_reuse.gd` / UID are separate work. They were preserved and are not counted as delivered optimization.
- Method: retained evidence, current source inspection, commit diffs and ancestry checks. Graph discovery lacked several recent symbols, so direct source reads were used for those paths. No new runtime benchmark, Mac session, engine build or physics experiment was run.

The [Apple master plan](../plans/apple-silicon-performance.md), [global performance plan](../plans/global-performance-visual-quality.md) and [optimization priorities](../plans/optimization-priorities.md) remain the operating/planning authorities. This report is a dated portability assessment, not another implementation plan. Older sections of the [technical background](../APPLE-SILICON-TECHNICAL-BACKGROUND.md) retain historical beta1/default-renderer statements. The priorities document's superseded “M1 unmeasured” and Stik-only native-scope entries were corrected during the section 7 follow-up. Current source, the [NK-3 guide](../../research/native-kernel/README.md) and later [R4 evidence](desktop-delivery-investigations/DT-MAC-00-R4/README.md) determine present status.

## 1. Optimizations already shared

| Mechanism and owner | Current implementation and reach | Evidence and limits | Action |
| --- | --- | --- | --- |
| Skip shader work with no contribution — DT-MAC-06b / VQ | [Grass filtering and pilot-anchor work](../../app/render/grass_surface.gdshaderinc), [cloud lattice wrapping](../../app/render/cloud_field.gdshaderinc), and inactive twilight terms in ground, grass, sky and water. No Apple OS gate. `b438f95ad` contains the second shader batch. | The six shaders plus lighting WeakRef reuse produced **17.6–23.2% higher sustained process-loop FPS** in three 30-minute M1 runs per role. This is a combined bundle result on the historical instrumented Metal circuit, not a per-shader or Windows/Linux claim. [Evidence](desktop-delivery-investigations/DT-MAC-02/README.md#repeated-30-minute-metal-comparison). | **Already done.** Preserve the exact zero-contribution/filter behavior; qualify other backends before assigning a gain. |
| Periodic cloud cache, C2/C5b — DT-MAC-06b / atmosphere | [CloudShadowMap](../../app/render/cloud_shadow_map.gd) publishes validated 2048² RG16F textures; [shared shader include](../../app/render/cloud_shadow_map.gdshaderinc) serves ground/near-grass shadows and low-frequency sky relief. Default-on with a renderer, default-off headless, with independent ground/sky switches. No Apple gate. | Historical M1 profiled screen: **26.20 → 23.45 ms GPU**, 10.5% less GPU time. Linux GL and Windows GL/Vulkan numerical/visual evidence also exists, but does not establish their speedup. [C5b evidence](desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-06b-c5b-float-noise-tile-corrected-c5-diagnosis-and-default-on-2026-11-05). | **Already done.** Integrate consumer-publication repairs with it; measure memory and first-bake cost on lower-memory targets. |
| Geometric shoreline instead of ground-fragment `discard`, D1 — DT-MAC-06b / LU | [Horizon.with_hole](../../app/render/horizon.gd) clips the mesh; [LakeWorld](../../app/render/lake/lake_world.gd) prepares replacements transactionally. The [ground shader](../../app/render/ground.gdshader) no longer discards shoreline fragments, on any platform. | One historical M1 profiled comparison: **28.09 → 25.75 ms GPU**. Still differences were localized to shoreline edges. This is a short screen; the magnitude on desktop GPUs is unknown. [D1 evidence](desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-06b-d1-ground-discard-removal-and-combined-screen-2026-11-05). | **Already done.** Retain explicit refusal for unsupported cuts and the later unchanged-mesh/helicopter repair. Do not generalize removal of `discard` to vegetation. |
| Incremental sky radiance, E1 — DT-MAC-03b-b / VQ | [Atmosphere.SKY_PROCESS_MODE](../../app/render/atmosphere.gd) is `PROCESS_MODE_INCREMENTAL`. Standard skies share it; [flowing High worlds](../../app/render/high_graphics_profile.gd) retain their REALTIME path. | In one M1 Metal diagnostic, p99.9 fell **22.08 → 15.86 ms** and frames exceeding twice the median fell 20 → 2. Compatibility evidence was weaker; ordinary p99 did not improve. [E1 evidence](desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-03b-b--e1-one-second-sky-hitch-2026-11-05). | **Already done.** Measure tail latency and sky transitions on other backends; this is primarily a hitch repair. |
| Bounded observation and allocation reuse — DT-MAC-04b/d, UI-FS/FL | [Statistics speed-window storage](../../app/statistics/detector.gd) and [recorder intervention snapshots](../../app/sim/flight_log.gd), `734bfb26a`, are shared GDScript. [Lighting WeakRef reuse](../../app/render/atmosphere.gd), `9de477232`, is shared but **Compatibility-only**. | Frozen-reference/lifecycle checks exist. Two complete M1 CPU pairs averaged about **0.52% higher** candidate CPU, an inconclusive result. The lighting helper's sampled baseline cost was only 0.012 ms/frame; its renderer guard excludes it on Metal, so do not attribute the Metal bundle's gain to it. [DT-MAC-02 evidence](desktop-delivery-investigations/DT-MAC-02/README.md). | **Already done.** The detector still sorts independent copies; the recorder still flushes bounded packets synchronously. Measure complete observer/recording cost before further changes. |
| Per-tick capability and battery facts — NK-2a | [FlightSession](../../app/sim/flight_session.gd), `399d00c6f` and `69a201645`, reuses bounded facts within the tick. Shared implementation; no Apple dependency. | Historical headless battery-query comparisons reduced median CPU callback cost by **6.4% for P-51** and **6.1% for Timber**; Stik runway was effectively unchanged. [Evidence](native-kernel/NK-2a/battery-queries-2026-10-28/README.md). These are not rendered-frame or M1 measurements. | **Already done before the recent Mac campaign.** Preserve invalidation and stage boundaries; do not cache state-dependent aero outputs across RK4 stages. |
| Measurement integrity and GPU diagnostics — DT/PT | [Sustained fixture and reducers](../../research/performance/README.md), [debug bridge](../../tools/debug/README.md), observed reconstruction/dimensions, source identities and invalid-run rejection are shared tooling. Apple host-state collection is a separate platform adapter. | These repairs improve attribution and prevent false performance claims. They do not directly increase game FPS. Recent native checks are retained in [R4](desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-resumed-20261106). | **Reuse now** for Windows/Linux campaigns; keep unknown GPU measurements and provider execution explicit. |

The cloud cache is an approximation with measured error bounds, not a byte-exact shader replacement. Its original failure involved a Metal sky consumer reading a `ViewportTexture` incorrectly; the current stable `ImageTexture` publication is the portable implementation. Pending, failed, mismatched-seed and capacity cases retain analytic evaluation. At four retained tiles, RG16F texel payload alone can reach **64 MiB**; bake/readback transients and resource overhead are additional. This is a memory-versus-compute tradeoff, not free acceleration.

The shader, shoreline and sky optimizations also reach other vehicle scenes that use the same rendering modules. That does not qualify another vehicle's physics, loading or complete-session performance.

## 2. Apple-specific work and portable ideas

| Apple work | What is already present | What can transfer |
| --- | --- | --- |
| Mobile/Metal as the Apple Silicon Standard renderer — DT-MAC-05b/c | [project.godot](../../app/project.godot) has `renderer/rendering_method.arm64="mobile"`; ordinary x86_64 Standard remains Compatibility. Five short M1 pairs measured a median **32.9%** Metal-versus-GL FPS gain, with an accepted appearance change. [Evidence](desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-05c-five-pair-compatibility-versus-metal-campaign-2026-11-05). | Transfer the **controlled renderer comparison and recovery process**, not this default or percentage. Mobile/Vulkan needs separate Windows/Linux evidence. The override is technically architecture-wide, not Mac-only; revisit its scope before introducing non-Mac ARM64 packages. |
| MetalFX Spatial and Auto — DT-MAC-07 / VQ-07 | [MetalFX policy](../../app/render/metalfx_policy.gd) requires Metal, a suitable renderer and runtime device support. Spatial is available on supported devices; Temporal remains opt-in. [Auto](../../app/render/reconstruction.gd) only considers MetalFX Spatial, then Native. At 1920×1080 it chooses Native; a supported 2560×1600 target chooses Quality. | Reuse actual-output-size accounting, Native fallback, explicit manual preference, resize handling and recovery in a future provider-neutral Auto policy. Existing FSR/DLSS options already supply integration seams. Selecting them automatically would be **new policy and qualification work**, not importing MetalFX into Windows/Linux. |
| Renderer/provider recovery — DT-MAC-05b/07a | [RendererGuard](../../app/app_state/renderer_guard.gd) is written generically around the resolved RD Standard method; MetalFX has its own activation/persistence handling. It is not a blanket guard for every High/FSR/DLSS launch. | Keep the generic guard with any future Standard renderer promotion. Extending provider-specific recovery is plausible if a supported provider needs it. Stable process callbacks do not prove a visible image or successful SDK execution. |
| Native host diagnostics, raw-clock joins and packaging | Apple-specific host collection and bundle identities support reliable Mac evidence. Frame streams, bounded collection, integrity rules and reducers are shared. | Reuse the schema and validation in each platform's existing collector. Do not port Apple framework calls, clock assumptions or bundle formats verbatim. |
| Shader baking, Game Mode, Metal rate maps/FP16/engine work | These remain proposed or conditional in the [Apple work order](../plans/apple-silicon-performance.md#next-campaign-dt-mac-00-r4), rather than completed general-game optimizations. | Transfer the question—first-use compilation, pixel cost or presentation stalls—only after attribution. There is no completed application patch here to import. |

In particular, “Auto” being visible on Windows/Linux does **not** mean it already automatically chooses FSR or DLSS. Its current provider list is explicitly MetalFX-only, with Native fallback. Do not silently replace that policy using GPU-brand strings or enable a custom-engine experiment in the standard package.

**Native physics is a separate boundary.** [NativeStage._load_library](../../app/sim/native_stage.gd) explicitly rejects platforms other than Linux x86_64 and verifies engine, library and source receipts. NK-3's current scope is broader than the old Stik-only descriptions, but its historical fleet results and current exclusions must be read in the [native guide](../../research/native-kernel/README.md). There is no completed ARM64 evaluator to import. An ARM port requires a math/toolchain strategy, reference equivalence, lifecycle, packaging and admission evidence; requesting `native` does not prove the current session actually uses it. The shared GDScript optimizations already benefit reference sessions on Mac and Windows.

## 3. Original integration snapshot versus release inclusion

Commit ancestry was checked locally. “Yes” means the commit is in that ref's history; it does not verify the bytes of a downloaded package.

| Change group | Current HEAD | Local `main` | `v0.1.10` tag |
| --- | --- | --- | --- |
| Second shader batch `b438f95ad` | Yes | Yes | Yes |
| Statistics/recorder `734bfb26a`, Compatibility WeakRefs `9de477232`, capability/battery facts `399d00c6f` / `69a201645` | Yes | Yes | Yes |
| Cloud cache, D1 shoreline, E1 sky and renderer foundations `e9bb60291`, `fc018b38e` | Yes | Yes | No |
| MetalFX Auto `c20a8bb0e` | Yes | Yes | No |
| Cloud lifecycle/variant controls `0e49383e1`, publication accounting `8717e4c43` | Yes | Yes | No |
| Durable MetalFX guard/application ordering `dd2c17a04` | Yes | No | No |
| Unchanged-versus-refused lake cuts and helicopter startup `0fced1b46` | Yes | No | No |
| Copied-material cache publication and finite GPU-probe readbacks `3f08b7b9e` | Yes | No | No |
| All-mode benchmark dimensions `a1e6e66cb`, contiguous observations `de19806bc` | Yes | No | No |
| GPU diagnostic integrity `f2084f3b8` | Yes | No | No |
| Composed-terrain statistics correctness `e72d878b6` | Yes | No | No |

**Concrete import opportunity:** reconcile the rows absent from `main` into whichever integration/release branch still lacks them. They protect shared behavior and evidence, even when discovered through Mac testing. Recheck the destination ref first; do not duplicate commits already integrated elsewhere or cherry-pick a large feature commit merely because its subject mentions Apple.

The statistics correction deserves explicit inclusion: the optimized observer's field-only height bound could skip wheel contact on the raised RC circuit. [FixedWingAdapter](../../app/statistics/fixed_wing_adapter.gd) now uses composed environment height/bounds while retaining authoritative wheel queries. Retained [UI-FS-08-R2 evidence](flight-statistics/UI-FS-08-R1/README.md#ui-fs-08-r2--composed-terrain-correction-2026-11-06) reports 19 of 82 new regression checks failing before the fix and all 82 passing afterward. It is a general-game correctness repair found alongside this review, not an Apple speedup.

For an older release branch missing the cloud/shoreline work, carry the implementation **and** its lifecycle, material-copy, failure and lake-startup repairs as a reviewed dependency set. Copying only the shader would omit the cache's readiness/seed contract or the geometry required after removing `discard`. This audit did not merge, cherry-pick, stage or publish changes.

## 4. Experiments that should not be imported as wins

| Experiment | Observed disposition | Recommendation |
| --- | --- | --- |
| Conservative cloud-density bounds (`three`, `two_three`) | Present as opt-in [variants](../../app/render/cloud_shader_variants.gd); default `off`. Both original variants failed the unchanged native Metal numerical gate. A reference-fallback candidate passed numerics but regressed the layered-cloud screen and was not integrated. [Evidence and snapshot limitations](desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-06b-r2--dt-mac-02b-r2-native-verification-2026-11-06). | Keep off. Windows finite-sample agreement does not justify global promotion or weaker tolerances. |
| Sun-disc zero-support guard `a1f32faee` | Two baseline/two candidate M1 runs showed **0.13% lower** candidate mean FPS; reverted by `36ce206fd`. [Solar screen](desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-resumed-20261106). | Do not import the perf-labelled commit alone. A correct-looking early return can produce no useful frame benefit. |
| Bit-mask cloud wrapping | Numerically matched the tested images but GPU time was **28.42 versus 28.40 ms** in the historical screen; reverted. [Attribution](desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-03b-c-gpu-pass-and-ground-shader-attribution-2026-11-05). | Retain the current simpler implementation. This is different from the accepted wrapped-neighbor reuse. |
| Original full-density sky relief tile C5 / packed-byte workaround | Rejected visual/consumer behavior; later diagnosis corrected the explanation. C5b's stable float texture and retained high octaves supersede it. | Import neither the failed implementation nor its obsolete diagnosis. Use current C5b and its probe controls. |
| Two-octave lattice atlas, half-resolution sky, aircraft-centered native crop | Research proposals with no accepted complete-workload gain in this review. | Potentially portable GPU experiments, after fresh attribution. Preserve full-resolution celestial detail/UI, motion readability and complete scene occlusion. |
| Lower MSAA or global resolution defaults | Latest corrected M1 2× MSAA single screen was about **4.4%** above baseline median, below the 5% screen and without motion acceptance. | Keep existing defaults. Retina/internal-resolution diagnostics do not establish a suitable 1080p quality reduction. |

## 5. Recommended sequence for the general game

These are the original engineering priorities, not measured future speedups or new track IDs. Item 1 was subsequently completed by PR #8; section 7 records the first bounded Windows work on item 2.

1. **Integrate the missing repairs first — DT/PT/VQ/LU/UI-FS.** Review the branch gaps above, including tests and dependencies. Keep cloud analytic fallback, transactional lake publication, composed-terrain observer bounds and durable provider recovery. This is the highest-confidence import work; its benefit is correctness and dependable measurement.
2. **Qualify the already-shared changes at actual 1920×1080 — VQ-01c / DT.** Use the existing sustained fixture, reducers, area checkers and debug bridge. Compare one mechanism at a time on a named Windows/Linux target, with the same renderer/profile, aircraft, input circuit, scenery, MSAA and VSync policy. Include a lower-memory/integrated GPU when available; an RTX 3090 cannot establish that floor. Measure cache-on/off separately for ground and sky, first-bake/loading cost, steady memory, sky-tail latency and moving-aircraft readability. Rollback D1 requires the matching geometry/shader baseline, not just a uniform switch.
3. **Only if still GPU-bound, adapt policy or test one remaining shader cost — VQ-07 / DT-MAC-06b.** A provider-neutral Auto policy is the clearest reusable Apple policy idea, especially above 1080p, but requires supported-provider selection, execution/fallback reporting and visual evidence. Lattice/half-resolution-sky experiments are alternatives when attribution still identifies cloud cost. Do not combine a renderer change, upscaler, MSAA reduction and cloud rewrite in one result.
4. **Only if CPU-bound, re-profile the complete session and observers — SF/NK/UI-FS/AUD.** Reuse existing accepted-state/tick preparation mechanisms. The M1 rendering results do not justify a physics rewrite, scheduler or ARM intrinsics. Preserve float64, 240 Hz, RK4 order, accepted-tick transactions and vehicle-independent kernel contracts.

Use the existing [performance acceptance gates](../plans/global-performance-visual-quality.md#4-measurement-and-acceptance-contract) and [optimization stop rules](../plans/optimization-priorities.md#6-acceptance-and-stop-rules): improvement must exceed paired-run variation and meet the owning workload threshold, or remove a named reproducible hitch/memory defect. Do not add percentages from different campaigns. Higher resolutions follow 1080p; 720p remains last priority.

## 6. What the retained measurements actually establish

The historical seven-file bundle has sustained M1 evidence. The later cloud, shoreline, renderer and reconstruction screens use other source/configuration identities and cannot be added to that percentage or described as one fully qualified shipping configuration.

The corrected `de19806bc` M1 campaign used attribute-aware checkout bytes, Godot 4.8-beta2 and contiguous dimension observations. Three Native uncapped circuits reported **15.741–15.831 ms p95**, and three Auto→Native VSync circuits **17.127–17.135 ms p95**, at an **estimated 1920×1080 render target**. Each used 30 s warmup plus 120 s measurement. These are valid short software screens on the built-in Retina display, not sustained final-package acceptance or physical 1080p presentation proof. The Retina Auto result remained ineligible for an effective-MetalFX claim because execution was unknown. [Current evidence](desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-resumed-20261106).

Older raw-blob exports bypassed checkout EOL attributes and caused descriptor-integrity failures. Their reports explicitly restrict them to the nonstock snapshots; the corrected reruns take precedence for checkout-level conclusions. Likewise, earlier single profiled GPU runs are useful attribution evidence, not substitutes for current unprofiled paired campaigns.

This review therefore supports **shared implementation and a concrete integration backlog**. It does not establish a new cross-platform FPS gain, current full-suite pass, downloaded-package integrity, physical flight validation or moving-aircraft acceptance. Report links and whitespace are checked separately; runtime files remain unchanged by this task.

## 7. Native Windows follow-up, 2026-11-06

The user requested continuation beyond the source audit. The remaining practical step was to verify the existing shared implementation on Windows. No missing application port was found, and no speculative renderer, reconstruction, MSAA or physics change was introduced.

**Integration is complete for the listed repairs.** Work began at `8e5f2f0ba`; during collection, PR #8 merged into `main`, followed by an unrelated audit commit. At the final integration check, both local `main` and `origin/main` were `61fe7ba89`. Every repair listed as absent from `main` in section 3 is now an ancestor of both refs. This integration occurred independently of these checks; no merge or publication was performed by this verification task. The release-tag inclusion table remains a historical statement about `v0.1.10`.

**Identity and method.** Windows 11 Pro 26100, Ryzen 9 5900X, RTX 3090, NVIDIA 617.42, and the SHA-512-verified official Godot 4.8-beta2 Windows executable. The existing sustained-flight fixture ran six fresh processes in order **off/on, on/off, off/on**, with 10 s warmup and 60 s collection. Both ground and sky caches were explicitly disabled or enabled together; density bounds stayed off. Standard/OpenGL, Native reconstruction, 4× MSAA, Medium scenery, pilot view, calm reference Stik circuit, hashing, Dummy audio and 1 Hz resource sampling were held fixed. VSync was disabled for throughput comparison.

All six receipts observed a **1920×1080 viewport/render-target estimate**, unchanged configuration, render-server progress, and no focus/pause/contact/fault violations. They share all **4,581 visible application/fixture input hashes** and both complete state/input/auxiliary hash windows, ticks 1–6,000 and 6,001–12,000. Different final partial windows were excluded from equality claims. Concurrent commits changed documentation/instructions only. Imported-cache identity, physical presentation, the full product route and whole-observer overhead remain outside this qualification.

| Check | Result |
| --- | --- |
| Pinned editor import | Passed |
| Cloud lifecycle, renderer guard, reconstruction, lake world, statistics terrain | **360 assertions passed** across five existing suites; one intentional renderer-guard write-failure warning |
| Native cloud-density probe, Compatibility/OpenGL | **30 cases passed:** 24 ordinary cases plus six blank-texture controls that correctly detected failure |
| Same probe, Mobile/Vulkan | **30 cases passed**, with the original density bounds unchanged |
| Native frame reducer regressions | 79 tests run: 78 passed, one optional engine-path test skipped |
| Six flight captures | All collection-valid and active-flight eligible; source/configuration identities consistent |

The numerical GPU probes exercise canvas, spatial and sky consumers at 512². They do not establish exact image equivalence, motion readability or 1080p performance by themselves.

| Collection order | Cache | Mean process-loop FPS | p95 / p99 frame interval (ms) | Individual software pacing gate |
| --- | --- | ---: | ---: | --- |
| 1 | Off, repeat 1 | 225.84 | 6.571 / 14.217 | Pass |
| 2 | On, repeat 1 | 189.69 | 8.565 / 11.325 | Pass |
| 3 | On, repeat 2 | 234.06 | 6.539 / 8.855 | Pass |
| 4 | Off, repeat 2 | 53.65 | 27.851 / 30.530 | Fail: p95 and p99 |
| 5 | Off, repeat 3 | 233.91 | 5.851 / 7.718 | Pass |
| 6 | On, repeat 3 | 205.25 | 6.881 / 9.293 | Pass |

**Decision:** retain the current shared default. Cache-on passed all three short software pacing runs; cache-off passed two. However, paired mean-FPS differences were **−16.0%, +336.3%, −12.3%**. The sign reversal and large within-baseline variation do not support a reliable comparative gain, nor a global rollback of the cache. Neither average the slow baseline away nor use it to claim an enormous speedup. The next performance investigation should isolate the source of this variation and measurement overhead before considering a graphics-policy change.

The existing frame-diagnosis tool found 2,255 over-budget intervals and a 259.522 ms maximum in the slow off run, versus one over-budget interval and an 18.025 ms maximum in off repeat 3. GPU times were unavailable. The slow run also had a 231.104 ms maximum synchronous stream write and unusually slow OS polling: 62.840 ms p95, with a 6.454 s first poll during startup. These are diagnostic leads, not joined causal evidence; startup polling cannot by itself explain a measured-frame hitch or the sustained slowdown. Resource sampling completed, but neither those process-wide RAM readings nor this short campaign establishes cache memory cost or a leak-free plateau.

Before the fresh six-run block, one off and one on attempt lost focus, paused and produced incomplete captures. They remain explicitly rejected. A separate valid preliminary off run is also excluded from the fresh block. No failure threshold, focus safety, duration or numerical tolerance was relaxed.

[Compact evidence and raw-artifact hashes](apple-silicon-cross-platform-checks-2026-11-06.json) retain source/engine identities, per-run metrics, reducer verdicts, resource context and failed-attempt records. Raw logs and streams remain under ignored `tmp/cross-platform-cloud-20261106-r1/`; no images were added. The full app/visual CI, VSync pacing, 30-minute soak, final-package acceptance, other GPUs and moving-aircraft review remain unclaimed. All task-owned Godot processes finished before reduction.

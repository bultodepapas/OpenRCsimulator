# Apple Silicon optimization — master implementation plan

Updated 2026-11-06 (R4 work order: [next campaign](#next-campaign-dt-mac-00-r4)) · **Owner:** DT/PT, with VQ/GDU, SF/FL, UI/AUD and vehicle owners at their existing boundaries. **Historical long-soak baseline:** `9de47723282b5c4126418b58ceeac273d66c3122`, with the common clock-instrumentation patch identified in dated evidence. **Current repair baseline:** `de19806bc`; [resumed native checks and dated performance limits](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-resumed-20261106). **Status:** bounded observer/shader optimizations, native measurement repairs, display recovery hardening and corrected Retina dimension reporting implemented. The historical three 30-minute M1 runs per role establish 17.6–23.2% higher sustained process-loop FPS for that named instrumented Metal circuit, not the later source. Whole-observer and full product/release qualification remain open.

This plan and the [technical background](../APPLE-SILICON-TECHNICAL-BACKGROUND.md) are the two authoritative Apple optimization documents. The background contains implementation facts, research and limitations; this document contains the execution sequence and gates. Existing research remains dated evidence and tool READMEs remain command authorities. The [desktop delivery plan](../DESKTOP-DELIVERY-PLAN.md) retains release ownership. No optimization or new platform support is authorized as completed by this plan.

The objective is the maximum practical **sustained performance with readable aircraft and unchanged simulation contracts**. The product priority remains 1920×1080/60 Hz, then higher resolutions, then 720p compatibility. The available M1 has only its built-in 2560×1600 Retina panel, currently set to 1440×900 logical pixels; the user authorizes this native display for the M1 campaign. Record measured viewport, drawable and internal pixels separately. A built-in-display run can qualify that named M1 configuration but cannot establish 1080p output. Newer community Macs extend named coverage; they do not replace the M1 baseline. iOS has a separate prerequisite branch because the current repository has no iOS delivery path.

The [completed technical soak](../research/desktop-delivery-investigations/DT-MAC-02/README.md#repeated-30-minute-metal-comparison) retains all six raw captures and exact identities. Final-five-minute gains were 15.1–22.6%; 73 shared state/input hash windows matched. The separate 60 Hz pacing target was not met.

The initial resumed 2026-11-06 campaign used a task snapshot that incorrectly
materialized normalized Git blobs instead of checkout bytes required by
`.gitattributes`. Its three 120-second Native screens, ten-minute Auto/VSync
sample and later native UI checks remain evidence only for those nonstock LF
inputs; they do not qualify a normal checkout. The descriptor integrity guard
correctly refused Workshop saves. The corrected export and rerun belong to the
[dated evidence](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-resumed-20261106).
The window
server reported a 2880×1800 screen property; this is not a new physical-panel
measurement. Logical UI, estimated render-target and presentation pixels remain
separate evidence.

The attribute-aware `bf4745d68` checkout rerun passed descriptor checks, 165
native graphics assertions at each target size, the Home/Fly/Settings resize
route and the full 52-step debug smoke. `a1e6e66cb` additionally observes viewport
dimensions in every benchmark mode; old unobserved receipts fail its current
qualification gate. `de19806bc` additionally requires contiguous observation
coverage and correctly accounts for deferred seals; review repairs harden
MetalFX marker persistence, letterboxed Auto selection, copied cloud materials
and transactional lake startup. Focused Windows software and GPU checks passed.
The direct Windows SSH route now works with the owner's enrolled dedicated key.
The attribute-aware `de19806bc` snapshot passed native functional checks, both
165-assertion graphics suites and the full 52-step smoke. Three 30 s/120 s runs
each pass the current software pacing gates at an estimated 1920×1080 target:
Native uncapped p95 is 15.741–15.831 ms; Auto/Native with VSync p95 is
17.127–17.135 ms. These short technical circuits do not establish sustained
product, moving-aircraft readability or physical presentation qualification.

## 1. Priorities, invariants and decision rules

1. Prefer a source-proven correctness/tooling repair before requiring hardware. Do not repeat completed acquisition, streaming, renderer-isolation, culling, caching or MetalFX-policy work.
2. Do not invent performance gains from source inspection. Prepare workloads, fixtures, receipts, reducers and bounded failure behavior off-Mac; require native evidence before promoting a renderer, preset, native solver or performance claim.
3. Keep one hypothesis and mechanism per candidate. If a baseline miss is CPU/observer-bound, reconstruction is not its repair. If it is GPU/pixel-bound, an ARM64 evaluator port is not its first repair. Estimate engineering effort after attribution, not from advertised GPU throughput.
4. Preserve float64 state, 240 Hz, RK4 order, validation, accepted-tick transactions, input sampling, collision identity, exact replay policies and the vehicle-independent kernel. Never weaken a guard, lower physics rate, loosen tolerance or re-record goldens to pass a performance gate.
5. Freeze the exact engine identity per campaign. The current pin is Godot 4.8-beta2 (`cafc17a192acf67903910a68aeb3c076c0907a4b`); historical beta1 campaigns remain separate. Engine upgrades, Apple Clang changes, shader changes, SDK changes and backend changes are independent candidates. Preserve the beta1 universal-template workaround only where applicable.
6. Reuse official Godot, Apple tools, existing repository collectors, free plotting tools and retained licensed assets. Build only missing glue with a demonstrable contract; no replacement profiler, telemetry backend, asset library, renderer or GPU flight solver.
7. A failed optional path must leave a usable reference/Native/Standard route. No chip-name-only feature gates, global App Nap disabling, forced CPU affinity, automatic privilege escalation or surprise launch-time stress tests.
8. Timing runs are serial on an otherwise idle host. Independent developers may work on separate files, but shared app interaction, imports, engine builds and benchmark CPU/GPU load cannot overlap a campaign.

**Priority definitions:** P0 unlocks reliable evidence or fixes a source-proven fault; P1 addresses a measured user-facing limit with existing architecture; P2 introduces a new native/platform/engine boundary and requires stronger evidence. Relative size is small (bounded module/tool), medium (several existing owners) or large (platform/compiler/engine qualification); these are planning classes, not calendar promises.

### Status and owner map

| Existing step | Current status and destination |
| --- | --- |
| DT-MAC-00 / 00-R1 / 00-R2 | Completed historical investigations; retained in background provenance. This consolidation is DT-MAC-00-R3. |
| DT-MAC-01 | M1 Air/8 GB ARM64 native inventory and editor import recorded; complete baseline manifest and qualification open — phase 3. |
| DT-MAC-02a/b | Getter/template/preflight and bounded v3 capture implemented and exercised natively; whole-observer overhead and remaining workload coverage stay open — phases 1–3. |
| DT-MAC-02c/d/e/f/g/h | 02c Aqua/resource repair and 02d v3 incident/Perfetto handling implemented and checked on Mac. 02e adds bounded host series, raw-clock correlation and a sleep check, with native tests. 02h native development export, strict signature, exact package replay and fixed session probe passed. Full release/trust/quarantine, app-route observation and voluntary share bundle remain open — phases 1, 2 and 8. |
| DT-MAC-03a/b | Source-build reference replay was exact on M1; a frozen technical circuit and five valid short pairs show 23.8–24.5% more process-loop FPS. Three fresh 30-minute runs per role show 17.6–23.2% higher sustained FPS, with matching physics/input hashes and valid raw-clock joins; other cases, observer uncertainty and broader attribution remain open — phase 3. |
| DT-MAC-04a–d | 04b statistics-window and recorder-copy candidates implemented with frozen-reference checks; partial native CPU comparisons establish no gain. 04d reuses lighting WeakRefs with focused checks and native image parity; the short object-count warning is bounded registry retention. The combined seven-file Metal bundle has a measured sustained gain; the WeakRef contribution is not isolated and remaining work stays open — phase 4. |
| DT-MAC-04n1–n4 | Conditional ARM64 NK-3 feasibility, evaluator parity, admission and package work — phase 10, under SF/NK policy. |
| DT-MAC-05a | Isolated renderer tools implemented; native parity/comparison open — phase 5. |
| DT-MAC-05b/c | Product restart/recovery and renderer decision — phases 8 and 5 respectively. |
| DT-MAC-06a/b–d | Second shader batch removes inactive grass/twilight work and redundant cloud wrapping. Native images and offscreen moon/twilight motion checks passed with quantified tiny differences. Five valid short pairs and three 30-minute pairs establish a sustained gain for that instrumented Metal circuit; observer uncertainty, moving-aircraft readability and broader qualification remain open — phases 8 and 6. |
| DT-MAC-07a–c | MetalFX policy/Settings prepared; real execution, failure/reset, motion/lifecycle and benefit open — phase 7. |
| DT-MAC-08 / 08a / 08b / 09 | The named technical circuit has three accepted 30-minute runs per role. Final product-route/package sustained qualification, community coverage and promotion remain open — phase 9. |
| DT-MAC-10 / 11 / 12 / 13 | Conditional engine-level Metal/new reconstruction/presentation work — phase 12. |
| DT-MAC-13i1–i4 | iOS feasibility/delivery/lifecycle/qualification branch — phase 11; does not declare a shipped mobile product. |

Shared code retains its existing owners: DT/GDU exports and pins, PT measurement, VQ reconstruction/profile, LU/FW/SM landscape effects, UI preferences/routes, AUD audio, SF/FL kernel/recording and each vehicle's validation. Register an implemented cross-track decision in the existing decision log when that decision is actually adopted; this plan does not silently change NK-3's Mac reference-only policy.

<a id="next-campaign-dt-mac-00-r4"></a>
### Next campaign (DT-MAC-00-R4, 2026-11-05)

The [R4 research refresh](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md) found no upstream Metal speedup to adopt. Metal 4 is in no release. It did find source-proven pass costs in the pinned Mobile/Metal path. The optimized M1 build runs 4.10 MP internal pixels at ≈ 36 FPS, p95 ≈ 31 ms. That is 1.98× the 1080p pixel load. The next campaign executes DT-MAC-03b attribution first and then selects one track. Each item states its decision rule. Numbers below are screening rules, not results.

| Order | Step | Work | Decision / exit |
| --- | --- | --- | --- |
| 0 | Prerequisite (owner) | Direct Windows SSH verified on 2026-11-06; preserve that dedicated key and the existing Linux key. Follow the [M1 guide](../tools/macos-m1.md), check disk before transfer and use a fresh verified source snapshot. Optionally install full Xcode for `xctrace`, if disk allows. | Native preflight receipt and every file in the selected snapshot's export manifest verified in the fresh review workspace |
| 1 | DT-MAC-03b-a sweep | Current source on the repository's **4.8-beta2** pin; the beta1 round-6 numbers are not a baseline for it. First one default 30 s + 120 s screen, then the [sustained-fixture sweep options](../../research/performance/README.md#repeatable-active-flight-dt-mac-03): `--sustained-render-scale` 1.0 / 0.75 / 0.5 × `--sustained-msaa` 2 / 1 / 0 (4× / 2× / off). One 30 s warmup + 60 s screen each, Metal HUD log (`MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1`, plus encoder timing in a separate run) and `sample <pid> 10` for main-thread stacks. HUD runs are diagnostic only. | FPS(0.5)/FPS(1.0) ≥ 1.7 and HUD GPU time ≈ frame interval → **GPU track**. Ratio < 1.2 → **CPU track** (DT-MAC-04a/b). Otherwise both, CPU first. |
| 2 | DT-MAC-03b-b hitches | Attribute the 120–160 ms maxima and >50 ms frames using pipeline-compilation monitors, frame diagnostics and `sample` during Home→Fly and first lake/sun views. | Hitch cause named per event class, or a discriminating follow-up measurement |
| 3a | DT-MAC-06b GPU track | One candidate at a time, five-pair protocol: (i) Retina **1080p-class internal 3D**, scale 0.75 → 1920×1200 with native UI; (ii) MSAA 2× on Apple; (iii) price the S5/S6 pass costs with a diagnostic scene lacking water/sun-glare/afterimage materials, then replace only the cheapest consumer (sun-glare depth occlusion, afterimage mipmapped screen read). | ≥ 5 % workload gain and moving-readability acceptance. (i) must also pass the visual gate before becoming a Mac default proposal. |
| 3b | DT-MAC-04a/b CPU track | `sample`/Time Profiler stacks of the main thread at 240 Hz. Apply the existing observer/session rules. | As in phase 4 |
| 4 | DT-MAC-05a/05c renderer | Add Compatibility over **ANGLE/Metal** (`--rendering-driver opengl3_angle`) as a control beside GL and Mobile/Metal. Confirm the template contains ANGLE and look parity. | Measured default proposal for Apple Silicon. Promotion still waits for DT-MAC-05b recovery. |
| 5 | DT-MAC-08b export | Native macOS export stage on the M1: **Game Mode** metadata (`LSApplicationCategoryType` games through the preset's plist content) and the **Metal shader baker**. Measure load and first-use hitches. | Exported fullscreen build shows Game Mode active. Baker reduces measured Home/Fly or first-use cost without a package/startup regression. |
| — | Diagnostic only | One A/B of `GODOT_MTL_SYNC_MODE=none` against barriers on the frozen candidate. | Record the result. Change nothing unless it is beyond noise, and then report upstream. |

Keep phases 10–12 (NK-3 ARM64, iOS, Metal 4 and engine work) parked. R4 found no trigger.

#### Audit follow-up (DT-MAC-06b-R1 / DT-MAC-02b-R1, 2026-11-05)

The local `optimization help.md` audit contains two dated reviews. Its later
section corrects the earlier C5 diagnosis; neither its synthetic experiments nor
the historical profiled M1 pair establish current sustained 1080p acceptance.
Implementation and focused evidence are retained in the
[R4 follow-up](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#optimization-help-follow-up-2026-11-05).

| Recommendation | Current disposition / next gate |
| --- | --- |
| UID omissions, benchmark effective state, profiler eligibility and source identity | Repaired; new receipts bind runtime rendering sources and actual observed configuration. Historical receipts remain historical and cannot silently satisfy the stricter gate. |
| Cloud publication/failure, separate ground/sky controls and graphical probes | Implemented with analytic pending/failure fallback, bounded retry and canvas/spatial/sky checks. Native Metal lifecycle, motion and sustained qualification remain open. |
| Stale MetalFX confirmation; shoreline clipping publication | Activation tokens and transactional lake attachment implemented. Process responsiveness is explicitly not display confirmation. Unsupported cuts refuse the lake/session instead of publishing mismatched physics. |
| Conservative density bounds | Default remains `off`. Both original variants failed the unchanged native M1 Metal numerical gate on 2026-11-06. A disposable reference-fallback `two_three` passed numerical checks but regressed the layered-cloud screen; it was not integrated. See the [native follow-up](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-06b-r2--dt-mac-02b-r2-native-verification-2026-11-06). |
| Two-octave lattice atlas; half-resolution sky | Next independent GPU experiments after the repaired baseline. Retain analytic fallback, seed/readiness identity and full-resolution sun/moon/IBL behavior; require incremental memory, transition and complete-frame evidence. No claimed gain or default change. |
| Aircraft-centered native crop | Separate rendering experiment after the cloud comparison: share complete scene/occluders, synchronized pose, padded crop and full-resolution UI. Camera geometry alone is not seam/readability/performance proof. |
| Native Metal rate maps, FP16, memoryless attachments, ARM64 physics | Conditional engine/native branches; no new trigger or available on-device proof. Do not fork the engine or change simulation arithmetic as part of this repair. |
| Packed three-sample relief cache; solar-halo lookup | Retain the guide's rejection/deprioritization. Measured interpolation error and shared solar angle work do not justify integrating these candidates. |
| Ground anchor/cache, hidden-layer relief, screen/depth dependencies, presets, shader baking and presentation | Keep the existing single-candidate attribution/export/pacing gates. Native Mac shader baking requires a non-headless native export and measured first-use behavior; no preset or queue policy is promoted by source inspection. |

The documented M1 key was absent from the current Windows workspace and the
known WSL checkout location during the 2026-11-05 follow-up. On 2026-11-06 the
existing key was found on `vscode-megatron`; the native follow-up above retains
the new checks and rejected experiments. Sustained/product qualification remains
open. No new library or asset is needed for these repairs and experiments.

**Step 1 result (2026-11-05):** [GPU track](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-03b-a-attribution-sweep-2026-11-05). FPS(0.5)/FPS(1.0) was 2.34, and the main thread waited on GPU completion in 57 % of samples. MSAA off versus 4× gained only 10 %. At scale 0.75 (1920×1200 internal), p50 was 17.9 ms and p95 20.8 ms, each from one short screen. Next is step 3a, candidate (i), then per-pixel shader cost. The CPU track (3b) is not entered. Step 2 hitch attribution remains open.

**Step 3a attribution (2026-11-05):** [per-pass and per-stage evidence](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-03b-c-gpu-pass-and-ground-shader-attribution-2026-11-05). The opaque pass is 79 % of GPU time. The single ground material costs ≈ 11 ms of 28.4 ms. Its cloud shadow is the largest stage, at 3.6 ms. Vegetation is negligible. An exact integer-wrap rewrite of the shared cloud noise gave no gain and was reverted. The candidates below each need owner visual acceptance:

| Candidate | Mechanism | Expected scope (from attribution, not a result) |
| --- | --- | --- |
| C1 Retina 1080p-class 3D scale | Existing MetalFX Spatial Quality (67 %) preset on Metal; bilinear only as a Compatibility fallback. [Screen](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-06b-c1-retina-input-scale-screen-2026-11-05) | Screened at −9.6 ms GPU (28.3 → 18.7 ms), with MetalFX executing (+2.2 ms in Tonemap) and distant-aircraft stills close to Native. Product route: DT-MAC-05b/05c renderer selection with recovery and DT-MAC-07a honest status |
| C2 + C5b Cloud noise tile | **Implemented (default, 2026-11-05).** A half-float RG16F `ImageTexture` per seed: ground and near-grass shadows from the full fbm, sky relief from octaves 0–2 plus per-pixel octaves 3–4. `OPENRC_CLOUD_SHADOW_MAP=0` disables it. [Evidence](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-06b-c5b-float-noise-tile-corrected-c5-diagnosis-and-default-on-2026-11-05) | −2.75 ms GPU at native (26.2 → 23.4 ms); images within 2/255 on Metal and GL |
| D1 Ground shoreline without `discard` | **Implemented (default).** Geometric bank cut in the ground mesh replaces the shader's `discard`, which disabled Apple hidden-surface removal. [Evidence](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-06b-d1-ground-discard-removal-and-combined-screen-2026-11-05) | −2.3 ms GPU at native (28.1 → 25.8 ms). C1 + C2 + D1 screened at 61 FPS, p95 17.3 ms; needs the five-pair and sustained protocol |
| E1 Incremental sky radiance | **Implemented (default).** `Sky.PROCESS_MODE_INCREMENTAL` replaces QUALITY. The 1 s cloud-drift step had refiltered the cubemap in one frame. [Evidence](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-03b-b--e1-one-second-sky-hitch-2026-11-05) | Removes the 1 Hz 20–35 ms hitch on Metal (p99.9 22.1 → 15.9 ms); weak GL evidence (max 101 → 47 ms). Closes the main step-2 periodic hitch; load-time hitches remain |
| P1 Apple Silicon renderer default | **Implemented (owner accepted the RD look, 2026-11-05).** `rendering_method.arm64="mobile"`, a Standard restart that follows it, and a per-build post-initialization renderer guard that restarts once into Compatibility. Native M1: default `mobile`, simulated crash marker → GL restart, clean launch confirms. [Evidence](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-05b-apple-silicon-default-renderer-and-recovery-2026-11-05), [decision](../DECISIONS.md#apple-features-follow-verified-engine-boundaries) | Five-pair screen: Metal +32.2–36.3 % FPS over GL at native 2560×1600 ([pairs](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-05c-five-pair-compatibility-versus-metal-campaign-2026-11-05)). MetalFX Spatial promoted with a per-build crash guard ([07a](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-07a-metalfx-spatial-promotion-and-guard-2026-11-05)). Open: exported/quarantined package, Intel/Rosetta keep-GL check, three 30-minute sustained runs, a Retina MetalFX default decision |
| C5 Sky relief from the noise tile | Superseded by C5b. The visible flattening came from a Metal sky shader reading the `ViewportTexture` as black, not from interpolation. | — |
| C1 MetalFX "Auto" default | **Implemented (owner, 2026-11-05).** MetalFX Spatial when the 3D input stays ≥ 1,000 rows (Quality on a Retina 2560 × 1600 panel), else Native; older unflagged "native" preferences migrate. [Evidence](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-07b-metalfx-auto-default-owner-2026-11-05) | Sustained 3 × 30-minute qualification of the full default configuration in progress |
| C3 Distance-gated ground detail | Fade relief/turf/photo terms by screen footprint earlier | ≤ −2.5 ms; visible near-field change |

## 2. Execution graph and strategic testing

**Critical path:** phase 1 portable launch/resource correctness → phase 3 M1 reference/attribution → selected phase 4 or 5/6 → phase 8 safe product integration → phase 9 final qualification. Phase 2 diagnostics preparation can run beside source-only phase 1; only required missing channels must block baseline evidence. The first technical attribution can use direct-flight v3 with live physics/input, existing v3 reducers and separate Home/Fly smoke. Defer optional Perfetto migration and product-route collection until needed; product-route collection and bundle-aware release identity are mandatory before claiming final normal-product/release qualification. Phase 7 requires a verified GPU-pixel bottleneck and working renderer. Phases 10–12 are independent conditional projects and must not delay a qualified baseline without evidence that they are necessary.

A branch may finish with **retain baseline / trigger absent**, with a concrete reason. This is valid for optional tuning, MetalFX, NK-3, iOS and advanced APIs. Mandatory correctness, package, pilot or performance failures remain open; they cannot be relabeled optional.

### Test catalogue

Use the [tool index](../tools/README.md) and owning READMEs for invocation. Godot tests use the checked runner and a fresh import when required; inspect engine diagnostics, not just exit status. Names below are existing files unless explicitly called a proposed case. Add cases to the existing family rather than a parallel harness.

| ID | Exact checks / purpose | When needed |
| --- | --- | --- |
| T0 documentation | Existing `tools/ci/check_docs.py` link/anchor logic, targeted local-link checking of these documents, `git diff --check`, current source/path verification. CI's guide allowlist does not automatically cover every new Markdown file. | This audit and documentation-only edits; no game run required. |
| T1 acquisition/platform tools | `tools/godot/test_macos_preflight.py`, `test_macos_universal_template.py`; `tools/debug/test_debugctl.py`; relevant getter/template fixtures named in tool guides. | Only changed getter/template/preflight/launch paths, plus native smoke in phase 3. |
| T2 measurement/data integrity | `tools/godot/test_resource_samples.py`, `test_resource_runner.py`, `test_frame_capture.py`, `test_incident_bundle.py`, `test_perfetto_export.py`; `research/performance/test_native_summary.py`, `test_frame_diagnose.py`; checked `test_frame_samples.gd`, `test_frame_diagnostics.gd`. | Collector/schema/reader/helper change; run the affected producer and downstream consumers together. |
| T3 renderer policy | `tools/graphics/test_launch.py`, `test_prepare_research.py`; checked `test_high_graphics_profile.gd`, `test_high_graphics_restart.gd`, `test_scene_detail.gd`. | Trial selection, effects identity, policy or restart change. |
| T4 reconstruction/settings | Checked `test_metalfx_policy.gd`, `test_reconstruction.gd`, `test_reconstruction_history.gd`, `test_camera_history.gd`, `test_display_preferences.gd`, `test_advanced_graphics_settings.gd`; affected provider failure/history tests. | Reconstruction, camera reset seam, AA ownership, preference or effective-mode change. |
| T5 local visual/lifecycle | Lake: `test_lake_planar_reflection.gd`, `test_lake_probe_ambient.gd`, `test_world_sky.gd`, `test_water_director.gd`. Foliage: `test_treeline.gd`, `test_field_tree_detail.gd`, `test_near_grass.gd`, `test_imported_tree_rendering.gd`. Existing area capture checkers and native moving clips. | Only the changed effect and shared consumers; static tests cannot close motion/readability. |
| T6 loading/observers | `research/performance/test_loading_probe.py`; checked `test_flight_loading.gd`, `test_flight_loading_surface.gd`, `test_launch_trim_cache.gd`, `test_launch_trim_async.gd`, `test_ui_preview_resources.gd`; relevant audio/statistics/recorder checks selected from the actual changed callbacks. | Loading, worker/cache, ownership, observers or recording; add focused cancellation/alias/stale-generation tests only if behavior is introduced. |
| T7 numerics/native | Existing exact `.orfl` replay and candidate comparisons; checked `test_golden.gd`, `test_replay_integrity.gd`, `test_replay_policy.gd`; native `test_native_stage.gd`, `test_native_session.gd`, `test_native_replay.gd`, helicopter equivalents; NK-3 stage/trajectory/family/weather/fleet and mutation controls. | Same-host unchanged physics for integrated changes; full native acceptance only when changing/admitting native code. H9 cross-platform policy is a different gate. |
| T8 native performance/product | Existing frame reducers, session baseline, loading probe, debug smoke on a suitable debug build, native developer captures, release control runs and named pilot cases. | After fixtures pass; smallest affected cases during iteration, full required matrix for finalists. |
| T9 integrated release | Required repository source/parse/unit/integration checks using `app/test.sh` partitions and current CI policy; relevant visual suite, resource/package/export checks and final downloaded Mac artifact. | Once per final frozen integration candidate; full requalification after an engine/kernel/ABI-wide change. New changes invalidate affected results. |

Do not run the 40+ minute full suite for each documentation edit, JSON fixture or MSAA hypothesis. Use focused checks to reject candidates cheaply. Do not suppress required CI checks: current scope policy remains authoritative. Reuse a previous result only if relevant source, data, configuration, engine and artifact identities match; list exclusions. A baseline failure stays in the failure ledger with owner and scope. The old DT-MAC-02 partial suite is historical evidence, not a current green baseline.

### Campaign protocol and acceptance budgets

Freeze these targets before A/B runs. They are proposed/existing owning-track budgets, **not achieved measurements**. If a target must change, explain and freeze the revision before comparing a candidate.

| Metric | Required method and acceptance |
| --- | --- |
| Frame pacing | On the named actual display/output, declare 60 Hz/cap/VSync and measured viewport/drawable/internal pixels. Evaluate 1080p separately when a suitable display is available. Existing DT process-loop proposal: p95 ≤18 ms, p99 ≤25 ms; report maxima, >33.3 ms and >50 ms events and consecutive bursts. Presentation evidence is separate. |
| Throughput | Separate uncapped experiment with the same visible workload; do not use VSync-clamped FPS to claim CPU/GPU savings. Never sum overlapping CPU/GPU timers as frame time. |
| Physics | Preserve the owning Gate P ≤500 µs/tick target and its regime/statistic definition. Also report individual complete-session p50/p95/p99 and tail cases; a batch mean does not establish a per-tick tail gate. Unpaused sim/wall ratio 0.99–1.01. |
| Adoption | Improvement beyond run variation and observer uncertainty; predeclared practical screen is ≥5% in the affected complete workload or removal of a reproducible hitch/leak/gate failure. Reject unexplained >5% required-case regression. A smaller proven defect repair can be justified explicitly. |
| Loading | Existing DT goals Home ≤5 s process-cold / ≤3 s warm; Fly ≤2 s. Record request, validated ready, first draw and interactive-ready events separately. A paused first draw does not pass interaction. |
| Memory | Before candidate tests, record a justified working ceiling on the actual floor host with OS headroom. No sustained candidate-attributable pressure/swap increase or unexplained retained growth through warm lifecycle cycles. No arbitrary “VRAM fraction” or additive RSS+GPU budget. |
| Correctness | Required local checks, same-host exact replay where promised, current H9 cross-platform policy, unchanged collision/physics identity. No golden rewriting or tolerance widening. |
| Visual/control | No repeatable loss of orientation, silhouette, landing cues, smoke cues, UI readability or control response; fixed-camera moving comparisons and owner pilot acceptance. |
| Diagnostic overhead | Proposed screen: ≤1% relative increase in combined app+helper CPU-seconds per active wall-second (not one percentage point of psutil CPU%) and ≤0.2 ms frame-p95 increase, without new repeatable >50 ms hitches; also report p99, helper CPU/RSS, disk cost and repeat variation. Use both uncapped cost and 60 Hz pacing so VSync cannot hide cost; for a near-zero CPU baseline report absolute CPU-ms/s and freeze an absolute ceiling before the trial. If noise prevents this bound, state unresolved, use a lower rate or external short traces, and do not subtract overhead to manufacture a pass. |

For short candidate decisions use at least **five independent alternating baseline/candidate pairs**, initially 30 s warmup + 120 s measured, with comparable initial thermal/power conditions. Report per-run distributions and paired differences; correlated frames are not independent trials. Use pilot, render-fixture and active-physics results as distinct groups. A one-off capture diagnoses; it does not establish a speedup.

For loading use at least five fresh-process and five warm in-process trials with cache state recorded. For an initial lifecycle screen use 10 warm transitions, then 20 for changes affecting resource ownership; the final DT campaign retains **50 Home/flight cycles**. For baseline/finalist sustained qualification use **three independent 30-minute active-flight runs**, with 30 s warmup excluded and explicit reducer minima of 30/1,800 s. Short rejected candidates do not need three soaks each. Repeat AC and battery as separate claims where applicable, after the core AC pass; unchanged binary/settings with multiple claimed power profiles still need profile-specific evidence.

Each receipt includes source commit/dirty patch and relevant input hashes; engine/templates/package/native/SDK identities; host model/RAM/GPU/OS; actual output and internal dimensions; renderer, driver, effects, AA, reconstruction, scenery and camera; aircraft/field/weather/seed/input identity; observers, power/cache/focus state; sample scope/unit/availability/completeness; failures/exclusions; per-run and paired results; visual/replay result; accept/reject decision and rollback. A timed-out, capped, paused, recovered-prefix or substituted-backend run cannot count as a complete intended workload.

## 3. Phase 1 — repair portable measurement prerequisites

**Priority/size:** P0, small-to-medium. **Dependency:** source audit only; can start without M1. **Benefit:** usable, truthful native evidence and less wasted hardware time. **Scope:** PT/DT tools and tests, no runtime optimization or engine change.

### DT-MAC-02c — native launch and resource availability

**Files:** `tools/debug/debugctl.py`, its tests; `tools/godot/resource_samples.py`, `run_checked.py` and affected consumer tests.

**Tasks:**

1. Make rendered launch platform-aware: native Aqua on Darwin without DISPLAY/WAYLAND; retain Linux display/Xvfb, Windows, explicit headless, exported-binary and wrong-port/PID safeguards. Route Mac memory observations through the existing resource sampler instead of the Linux `/proc` helper.
2. Distinguish stable unsupported optional process-I/O fields from denied/failed required channels. Probe capability once; retain null/reason. Preserve PID identity, counter reset, sampling coverage and process-disappearance failures.
3. Preserve old resource schema meaning or version it and migrate both incident and Perfetto consumers in the same change. A new required-channel completeness result may coexist with a partial legacy receipt; do not relabel lost samples complete.
4. Validate horizon and capacity together: initially 1 Hz, 2,100 OS samples, covering launch + 30 s warmup + 1,800 s flight + stop margin. Compare timestamps against the actual frame interval; counts alone cannot prove coverage.

**Tests:** T1 debug launch fixtures and T2 sampler/runner/consumer fixtures, including Darwin backend with no `io_counters`, access denied, missing RSS, PID reuse, early exit, counter resets, cap and Linux/Windows compatibility. Synthetic clock tests replace real 30-minute waits here.

**Completion:** Aqua command construction needs no Xvfb; unsupported optional channels are explicit without hiding missing required coverage; old reports remain readable; no host privileges or simulator behavior changed. Short native launch/sampling checks and all six later 30-minute raw-clock joins passed; broader workload and observer gates remain open.

### DT-MAC-02d — preserve long-stream evidence end to end

**Files:** existing frame stream reader/reducers; `incident_bundle.py`, `perfetto_export.py`, their tests and owning guides.

**Tasks:** reuse the v3 validator rather than implement another JSONL reader; include manifest and sidecar as one attachment unit; preserve v2. Validate basename/path containment, count/sequence/hash, finite metrics, duplicate/reordered/missing chunks, interruption and unsupported version. Reconcile producer 256 MiB allowance with downstream combined-input/event caps; stream or bound conversion instead of loading arbitrary data. The current shared reader rejects incomplete streams: preserve that strict acceptance path. If incidents must retain an interrupted prefix, add an explicit diagnostic-only reader mode with independent validity/completeness fields and no route into soak acceptance. Preserve an abrupt-crash sidecar even if no summary/trailer exists, labeling unverified/incomplete ranges; a file hash never proves completion. Retain clock anchor uncertainty and scopes. At 60 Hz a 30-minute stream has 108,000 frame slices; twelve metric tracks can produce about 1.4 million timeline events, exceeding the current one-million-event hard cap (about twice that at 120 Hz). Keep complete raw v3 data and use explicit time-window/track selection or segmented traces with interval/coverage manifests. Never silently downsample or label a selected window a complete-session timeline. Until this is complete, use v3-aware reducers and keep the raw pair separate from the old incident route.

**Tests:** T2 targeted producer/reader/bundle/timeline tests with 60/120 Hz 30-minute-equivalent streams, old v2 fixtures, bad hash, oversized file, path traversal, late output collision, absent terminator and stop failure. No full game run.

**Completion:** valid long streams round-trip through the bundle/reducers with preserved identity/completeness; any selected/segmented timeline declares its exact scope and caps; damaged or oversized streams fail explicitly; no sidecar loss or silent timeline truncation. A timeline with uncertain clock alignment cannot claim exact per-frame OS causality.

### DT-MAC-02h — reference-release identity independent of NK-3

**Priority/dependency:** mandatory for final Mac release replay/benchmark evidence; source-editor investigation can proceed while this is open. **Owners/files:** SF/FL/DT; `app/sim/flight_log.gd`, `app/app_state/native_package.gd` or a separated generic artifact-identity owner, `app/tools/flight_log_cli.gd`, `tools/flight_log/flight_log.py`, `research/performance/session_probe.gd`, `session_baseline.py` and release receipt tools.

**Tasks:** separate generic verified release identity from Linux NK-3 admission. Introduce a versioned Mac bundle identity covering the final executable, separate PCK, solver-relevant resources and any actual native sidecars. Define hash/receipt publication around signing without circular self-hashes or post-signing mutation; artifact consistency is distinct from trust/signature verification. Do not enable the Linux OS guard or label a Mach-O-only hash `packaged-executable-v1` and call it complete. Preserve existing Linux exact-replay identities and refuse unknown kinds. Update log/replay and release benchmark validators that currently assume solver identity equals executable SHA; explicit native Godot selection fixes the Python tool's Linux default during development.

**Tests:** T7 plus `tools/flight_log/test_flight_log.py`, checked `test_flight_log.gd`, `test_flight_log_inputs.gd`, `test_flight_log_report_write.gd`, relevant release manifest and package tests. Add fixtures for missing/changed/substituted PCK, executable, sidecar, receipt, wrong bundle/architecture and signed-byte drift; Linux legacy logs continue to verify. On the Mac, record and exactly replay a complete reference flight from the actual package and run its reference release session probe. Check candidate identity changes remain explicit and cannot be passed as exact replay.

**Completion:** reference-only Mac release identity is verifiable without an installed NK-3 solver; final executable and loaded solver contents are bound, missing identity fails closed, and package replay/benchmark validation accepts only the correct artifact. Editor/source replay is labeled separately until this native gate passes.

**2026-11-02 implementation:** the exporter adds a sibling receipt inside the Mac
ZIP and checks bundle bytes/permissions against the staged Godot archive.
Manifest v2 binds receipt/input/probe digests; generic v1 verification remains
available for historical integrity checks, while current publication requires v2.
Synthetic package and identity fixtures pass. Native final export, signature
verification, downloaded/quarantined launch and exact package replay are still
required. [Contract and installation limits](../../tools/release/README.md#mac-reference-bundle-identity-dt-mac-02h).

## 4. Phase 2 — bounded Apple diagnostics, only where needed

**Priority/size:** P0 for required missing host context, otherwise P1/medium. **Dependency:** phase-1 schema decisions. **Benefit:** explain sustained thermal/memory/power behavior and make community reports useful. **Scope:** existing tools plus minimal native glue; no profiler or network service.

### DT-MAC-02e — optional native host-state companion

**Implementation (2026-11-03):** the preflight retains its bounded Foundation/JXA
snapshot. An optional Foundation/Dispatch/IOKit companion now supplies bounded
host series and notifications, capture association, process-lifetime supervision
and helper/source identity checks. Native M1 compile, smoke and 18 host tests
pass, including notification flooding. The opt-in v2 path joins bounded direct
raw-uptime anchors and checks sleep independently; legacy UTC validation remains
unchanged. Frame, resource and Perfetto integration also passed natively.
Initial memory-pressure knowledge and whole-observer overhead remain separate
gates. All six later 30-minute technical flights passed required host/resource
coverage and raw-clock/sleep checks.
[Evidence](../research/desktop-delivery-investigations/DT-MAC-02/README.md#dt-mac-02e--03-active-flight-campaign-preparation-2026-11-03).

**Tasks:** first test whether installed free tools supply adequate bounded observations. If not, add a developer-invoked Foundation/Dispatch/IOKit companion under the existing tooling owner. Pin its source, compiler, SDK, deployment floor and ARM64 build identity. It reports host thermal category, low-power boolean, AC/battery source and memory-pressure events; existing psutil retains process CPU/RSS/system memory. Do not query an unrelated MTLDevice and label it game allocation.

Read thermal state **before** subscribing to change notifications, register, then re-read to detect a transition during initialization; record the interval/uncertainty when snapshots differ. Apply the same read/register/re-read race handling to low-power state and record later changes. Initial memory-pressure state is unknown until observed; an event stream with no event does not prove no pressure. Collection completeness describes the observation interval, separately from whether the pressure value is known. If the campaign requires a known initial state, obtain an independently verified public/manual observation or keep that gate open. Keep unsupported/denied/error distinct. Do not request private temperature, clock or per-process GPU APIs.

Use the same fresh capture ID supplied by the owning session/runner, monotonic timestamps, paired clock anchors with uncertainty, typed units/scope, sequence and final hash/count/status. Proposed bounds: ≤3,600 s, 1 Hz snapshots with 4,096 capacity, a separate 1,024-event cap and explicit byte limit. Coalescing/drop counts are visible. Use fresh single-writer output, no user paths in shareable rows, no network, daemon or startup registration. Supervise stop/cancel/timeout/helper death and reap the child. Failure marks relevant diagnostics incomplete without stopping healthy flight.

**Tests:** T2 injected native-source/protocol fixtures for initial query order, unsupported OS/API, unknown enum, events before readiness or during registration, floods, write failure/full disk, death/stop race, malformed/duplicate time and mismatched capture IDs; Linux/Windows no-helper path; complete no-event pressure stream with unknown value remains distinct from missing observations. Native compile/API smoke in phase 3; diagnostic on/off timing there.

**Completion:** bounded host-only series, clear availability and lifetime, unchanged non-Apple startup, reproducible tool build and all failure tests pass. If free tools suffice, record that choice and omit the helper. Native numerical/kernel code is not a dependency.

### DT-MAC-02f — observe the real app route and coarse phases

**Source constraints checked (2026-11-02):** user arguments bypass normal Home
startup. Use an explicit app action or environment opt-in for product capture.
The current frame schema assumes one monotonic simulation timeline; Home and
flight resets require explicit phase/epoch validity. Early stop remains incomplete
until a versioned stop contract exists. Reuse the writer and diagnostics rather
than inventing ticks or relabeling interrupted captures complete.

**Files:** existing frame collector and its owning Main/AppRoot lifecycle, loading probe and optional narrow platform bridge only if necessary.

**Tasks:** give the existing collector an explicit bounded owner for Home → Fly → Home/Workshop with saved settings and active input, preserving direct-flight captures. Start/stop without auto-quitting the game; include pause/focus/transition markers and phase ownership. Generate one fresh capture ID in the normal packaged session owner and pass it to frame, resource and helper collectors; retain existing runner IDs for direct captures. Reject mismatched/absent association rather than inventing a join. Keep release data collection independent of the debug-only authenticated bridge. Record requested/effective renderer, output/drawable/internal pixels, unknown fields and reconstruction changes; do not infer drawable pixels from window points.

Use existing engine signposts and external Instruments first. If attribution still lacks required application phase boundaries, add opt-in coarse signposts for load, flight construction, world switch and capture lifecycle with paired IDs and cancellation. Avoid per-tick/native calls and dynamic personal strings. Any Apple bridge must have explicit absent/no-op behavior on other platforms and matched package/signature identity; no second preferences store or rendering queue.

**Tests:** T2 collector and T6 ownership/loading fixtures; proposed cases for cancel/return Home/free owner/late callback/no helper/collector off, unchanged saved preferences, failed setup, multiple intervals and exact replay. T1/T3 only if launch identity changes.

**Completion:** required before normal-product-route sustained acceptance, but not before the first explicitly technical direct-flight attribution. One collector can observe both technical and product routes with honest labels; teardown is bounded, report interruption explicit, output/UI pixels distinguished, normal input retained. Same source later needs a short capture on the named actual M1 display and measured overhead; 1080p output remains a separate product target. An injected fixture is not release-route execution proof.

## 5. Phase 3 — establish the M1 reference and choose the first candidate

**Priority/size:** P0/medium. **Dependency:** usable phase-1 tools and required phase-2 channels, or documented external equivalents. **Benefit:** identifies the limiting subsystem and avoids expensive wrong work. **Owner:** DT/PT + SF/FL/VQ.

### DT-MAC-01 / 03a — identity, baseline and software admission

1. Inventory actual M1 model, CPU/GPU variant, RAM, cooling class, macOS/build, monitor/refresh, power modes, free storage and relevant SDK/tool versions. Verify the retained Air/8 GB description; do not silently assume a 7-core or 8-core GPU.
2. Freeze source and import/config/assets identities. Verify official ARM64 getter, native execution, resource import and exact template/export identity. On universal packages inspect actual release payload/UUID and dependency slices; Rosetta is a separate result. Keep personal preferences and radio calibration isolated during experiments.
3. Run platform-launch/preflight/resource smoke and focused reference replay/H9 checks. Keep explicit `gdscript_reference` control; verify native refusal/fallback is truthful. Do not demand an absent Mac NK-3 library.
4. On the available M1, verify the actual built-in display output, drawable and internal pixels, 60 Hz/cap/VSync, UI scale, MSAA and fixed scene detail. Its 2560×1600 panel currently uses 1440×900 logical pixels; a 1920×1080 window request does not prove 1080p drawable output. Test actual 1080p separately when available, without blocking this named built-in-display M1 result.
5. Record the unmodified technical baseline with complete live physics/input and separately exercise normal Home/Fly. A sustained normal-product-route claim requires DT-MAC-02f; exact release replay/reference benchmarks require DT-MAC-02h. Source-editor exact replay can support provisional attribution while those gates remain open. Retain an exact-replay baseline `.orfl` with source/config identity, complete flag, markers and CSV/report; log-on/off runs remain separate workloads.

**Tests:** native T1 smoke; focused T7 reference replay and H9 policy; T8 initial Home/Fly/Workshop and short performance checks. Recheck historical audio/reference failures on the selected snapshot only when they intersect required baseline gates; record all inherited failures, no golden rewriting.

**Completion:** another developer can reproduce the named baseline from its manifest; actual architecture/pixels/backend and required data coverage are known; launch/flight failures are explicit. No renderer winner or tuning claim yet.

### DT-MAC-03b — attribution and baseline soak

Use a bounded 30-second CPU profile and, on a Metal candidate only, appropriate GPU trace/capture. With Compatibility, report GPU timing unavailable and use supported external evidence rather than calling it CPU-bound by subtraction. Compare full live callback time with detached session/evaluator probes; include input, collision, publication, observer, audio, recording and scenery scopes. Do not reinterpret `step_usec` as complete frame or callback cost.

Minimum workload manifest:

| Case | Purpose and fixed controls |
| --- | --- |
| Stik normal circuit, approach, ground contact | Baseline flight/control, fixed pilot camera and input tape where applicable. |
| P-51 plus an electric aircraft | Different evaluator/visual/propulsion load; use current catalog/data identity, not historical X8 eligibility. |
| Club field and Green paradise | Vegetation/terrain/water differences; same weather/time/scenery tier per pair. |
| Lake/reflection view, smoke maneuver, dusk/night | Exercise actual expensive effects independently before a combined worst required scene. |
| Distant aircraft against sky/cloud/trees and close pass | Orientation/readability; fixed FOV, zoom/aid, trajectory and projected size. |
| Home/Fly/Workshop, aircraft/landscape change | Cold/warm loading and lifecycle/retention; paused periods are labeled. |
| Helicopter/ground activity if offered in the release | Independent route/software/performance gate; fixed-wing success does not qualify them. |

Run diagnostic-off, frame-only, frame+resource and helper-enabled controls. Choose the lightest collection satisfying required evidence. Execute the three baseline soaks once the short runs are valid; compare early/final five-minute windows, pacing, active sim/wall, memory/pressure, thermal/power and recorded pauses. Do not create a long soak out of restarted short processes.

**Tests:** T8 matched short cases, existing session baseline/load probe, targeted native trace and three baseline soaks; T2 synthetic tests need not repeat unless collector changes.

**Completion:** ranked bottleneck report with affected budget, scope, measurement uncertainty, reproducible trigger and one recommended candidate. Freeze the floor-host memory ceiling with observed OS headroom. If evidence cannot attribute a miss, next work is a discriminating measurement, not speculative tuning.

## 6. Phase 4 — highest-ROI CPU, loading, observer or memory repair

**Priority/size:** P1/small per candidate. **Dependency:** phase-3 attribution, or an independently reproduced source correctness defect. **Benefit:** remove demonstrated work/stalls without changing graphics API or numerical contracts. Select only matching subphases; do not implement all rows by default.

### DT-MAC-04a — script/session and collision cost

**Scope/tasks:** profile `FlightSession`, `Simulation`, collision queries and accepted-state consumers; distinguish array/Dictionary allocation, repeated immutable decoding and stage work. Existing tick facts, deflection reuse, prepared configuration and spatial rejection are already implemented. Try one bounded reuse/rejection only if cost is material. Preserve invalid input, mutable configuration guards, ordering, alias isolation, earliest collision and stable-ID ties; caches need byte/count bounds and explicit reset/restore/config invalidation.

**Validation:** relevant local unit/oracle and T7 same-host exact fingerprints/replay; affected collision oracle cases for bins, grazing, rotation, ties and shoreline; detached attribution plus full active-session A/B. **Exit:** unchanged semantics and positive whole-workload result beyond noise, including ground/event worst cases. Otherwise retain baseline. Native port is phase 10, not a hidden extension of this patch.

### DT-MAC-04b — live observers, audio and recording

**Scope/tasks:** trace actual `stepped` subscribers and per-frame work. Optimize duplicated read-only derivation or presentation updates only when consumer timing contracts allow. Keep physical contact commits, statistics credit and audio cue/event ordering. Compare `.orfl` off/on: it synchronously flushes bounded 240-tick chunks/events; separately inspect CSV Trace's accumulated rows and whole-file save. Do not assume both recorders have the same boundedness/durability.

If disk stalls are demonstrated, propose a bounded transport at the recorder owner with copied immutable data, ordered publication, backpressure/drop policy consistent with exact logging, drain/cancel/error handling and explicit incomplete status. Do not silently drop exact-replay ticks or defer durability without a contract decision.

**Validation:** T6 affected observer/audio/recorder cases plus T7 exact replay, marker/hash/row order and fault/reset tests; forced slow/full disk/cancel tests only if transport changes. Native log-on/off and full callback A/B. **Exit:** measured stall/CPU reduction without lost samples, changed cues, unbounded queue, modified physics or concealed write errors.

Current 04b candidates reuse packed statistics values and independent recorder
boundary bytes. They preserve the original event/snapshot and recording packet
contracts in frozen-reference checks. The [dated evidence](../research/desktop-delivery-investigations/DT-MAC-02/README.md#dt-mac-04b--06b-optimization-candidates-2026-11-02)
owns source hashes and native comparisons. This does not close the full active-session,
log-on/off, release or sustained gates.

### DT-MAC-04c — loading and first-interactive frame

**Scope/tasks:** use existing Home/Fly loading probe to separate import/I/O, validated data, scene building, shader first-use, trim preparation and teardown. Inspect current caches/async trim work before adding more. Select one dominant phase: immutable resource reuse, existing threaded resource request, detached pure-data preparation or bounded render warmup. Workers never mutate the active SceneTree or installed model; adoption uses generation/cancellation ownership and main-thread attachment. No flight before validation/readiness.

**Validation:** T6 cache/preparation/loading/failure/cancel/late-result tests; five process-cold and five warm trials; first drawn versus interactive-ready checks; 20 warm lifecycle cycles if ownership changes. T7 if session preparation changes. **Exit:** improved declared phase and full load time, no readiness regression, bounded retention and preserved direct/headless/capture/Workshop semantics. Do not add all four strategies to fix one phase.

### DT-MAC-04d — retained resources and imported textures

**Incremental implementation (2026-11-02):** Compatibility lighting updates reuse
existing weak-reference wrappers while preserving fresh lighting snapshots. The
short-soak object warning was attributed to the existing bounded registry;
the unchanged M1 baseline passed a 12-cycle full smoke. The candidate passed
20 cycles, focused lifecycle/render checks and 12 byte-identical native offscreen
captures. The later seven-file Metal comparison shows 17.6–23.2% higher sustained FPS over three 30-minute pairs; it does not isolate this Compatibility-only WeakRef change.
[Evidence and native limits](../research/desktop-delivery-investigations/DT-MAC-02/README.md#dt-mac-04d-lighting-reference-reuse-2026-11-02).

**Scope/tasks:** inspect world/preview/aircraft/audio/reflection lifetimes and current VQ-02a texture inventory. Measure actual GPU formats, mip/filter/color-space behavior, source/import identities and resident estimates. Fix one leak, duplicate resource or demonstrated import problem via its source pipeline. Preserve generated aircraft names/hinges and visual/collision contracts. Do not assume ASTC flag means every Mac resource uses ASTC or sum RSS with GPU estimates.

**Validation:** affected resource/import/generator checks, T5 motion/color/normal/marking cases, 20 warm transitions with weak-reference/resource evidence and process context; T8 matched memory/pressure/load timing. **Exit:** bounded retention or verified format/residency improvement without readable-detail loss or a newer-family-only dependency. Full 50-cycle/soak test waits for phase 9 finalist.

## 7. Phase 5 — choose a renderer with common features

**Priority/size:** P1/medium. **Dependency:** phase-3 baseline and fixed outcome of any shared phase-4 changes. **Benefit:** potentially lower CPU/GPU/power cost through existing Godot Metal; amount unknown. **Owner:** VQ/DT/GDU.

### DT-MAC-05a — native parity using prepared trials

Reuse `prepare_research.py` and `launch.py`; do not rebuild them. Freeze linked assets and separate imports/user profiles. Pin Standard/common effects, scenery tier and Native AA/reconstruction; explicit environment manifest prevents accidental High effects or startup multi-bounce. Confirm actual effective method/driver and shader behavior before timing.

| Candidate | Experiment |
| --- | --- |
| A Compatibility/OpenGL | Reference and recovery. |
| A2 Compatibility/ANGLE over Metal | Same shaders as A through `opengl3_angle`. Verify template inclusion, look and first-use compile cost ([R4](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md)). |
| B Mobile/native Metal | First lower-complexity candidate; verify screen/depth effect costs. |
| C Forward+/native Metal | Common feature set first; no silent SSAO/shadow/reflection additions. |
| D Mobile or Forward+/Vulkan-MoltenVK | Conditional same-OS control for a Metal-specific issue; skip absent a discriminating question. |
| E High/native Metal | Separate product-quality cost, only after common-feature C. |

Parity cases: sky/exposure, reversed-Z water/depth/refraction, lake/planar/probe paths, sun glare, alpha/scissor foliage/MSAA, smoke/particles, shader globals/instancing, shadows and all secondary viewports; day/dusk/night and moving thin aircraft. Unsupported features must be an explicitly reviewed product tradeoff, not invisible benchmark removal.

**Tests:** T3 fixtures only if trial policy changed; T5 affected shader/feature checks and native 1080p matched images/motion; short lifecycle transitions. API/Shader Validation belongs in separate correctness runs. **Exit:** actual shader/feature matrix and backend identity, required look preserved or candidate rejected. No timing promotion from a headless launch.

### DT-MAC-05c — measured renderer decision

Run five short alternating A/B and A/C pairs for the representative baseline cases; use uninstrumented release-equivalent controls and separately instrument attribution. Compare CPU callback, GPU when available, frame/presentation cadence, pipeline events, memory and energy/thermal context. Treat High separately. Preserve a negative result and keep Compatibility if it wins or optional routes cannot meet correctness.

**Tests:** T8 matched short campaign and replay check on integrated presentation configuration. **Exit:** selected candidate or retain-baseline receipt with quantified tradeoffs and remaining native package gate. A source-copy experiment does not yet authorize persistent renderer selection in the product.

## 8. Phase 6 — one attributed GPU or pipeline change at a time

**Priority/size:** P1/small-to-medium per change. **Dependency:** actual render-pass/counter evidence and phase-5 parity; can also optimize retained Compatibility where relevant. **Benefit:** reduce the measured limiter with existing controls. **Owner:** VQ plus owning effect/import track.

### DT-MAC-06b — pixel/attachment/pass cost

Try 4× versus 2× native MSAA first only if resolves/fill/bandwidth are material; then one shadow atlas/caster, reflection resolution/update or optional pass change. On Mobile inspect water/sun screen/depth reads and resulting copy/resolve/subpass boundaries before proposing an effect-preserving alternative. Depth/history/material outputs cannot be made memoryless if later sampled. Engine graph or queue changes belong in phase 12.

**Tests:** T5 relevant lake/sky/foliage checks; matched moving aircraft/leaf edges/propeller/night/smoke; T8 GPU pass and full-frame A/B with memory. **Exit:** net relevant workload gain, required quality retained, no extra leak/resize issue. Reject a faster screenshot with worse flight cues.

### DT-MAC-06c — geometry, transparency and material residency

If submission/vertices dominate, inspect current bounded MultiMesh cell size, LOD thresholds, shadow participation and material/surface duplication. If transparent overlap dominates, inspect actual smoke/card coverage, not draw count alone. Near grass is already opaque; do not replace it with blended cards. Open-terrain occlusion must earn its CPU cost. Texture work follows current import/provenance pipeline and actual supported GPU formats.

**Tests:** T5 relevant geometry/material/import cases; collision-world identity, silhouettes/wind/coverage and distant orientation; T8 drawn primitives/draws, CPU submission, GPU and memory together. **Exit:** meaningful net gain with stable physical obstacles and bounded batches. A giant MultiMesh that breaks culling is not an accepted batching improvement.

### DT-MAC-06d — first-use pipeline stalls

Attribute shader versus pipeline work with existing counters and short native traces. Investigate mixed 4× main/2× planar viewport MSAA only when planar High and compilation events reproduce the hitch. Compare fixed-resource reuse, needed material variants and bounded warmup before export-pipeline work. If Metal shader baking is justified, add a separate exact Mac-native non-headless build stage; retain Linux cross-export gates and inspect final package contents. Intermediate baking does not remove final hardware-specific compilation.

**Tests:** affected T3/T5 checks, cold/warm first-appearance cases, corrupted/invalidated cache and changed settings where applicable; package/resource tests only when baking/export changes. **Exit:** reproduced stalls reduced without unacceptable startup/package/memory cost; cache identity and unsupported-host fallback documented. No global cache deletion or universal distribution of machine-specific cache blobs.

## 9. Phase 7 — qualify existing MetalFX trials conditionally

**Priority/size:** P1 for Spatial when pixel-bound; P2 for missing engine reset/failure seams. **Dependency:** verified Metal renderer/parity, actual GPU-pixel limit and Native 1080p baseline. **Benefit:** less internal pixel work only if scaler/history overhead and visual cost permit it. Existing policy, options and localization are already implemented.

### DT-MAC-07a — effective execution and creation/failure contract

Inspect exact engine creation/substitution paths, optional scaler allocation results and failure reporting. Add only a narrow upstream-first engine status/null-handling seam if needed; no private queue or application-side scaler competing with Godot. Receipt separates requested provider, validated inputs/property readback, observed effect, substitution/failure reason and unknown. A once-only warning or mode enum is insufficient.

**Tests:** T4 policy fixtures covering missing RD/constants, invalid bounds, unsupported method/driver, corrupted preference, rejected request → identical retry → Native → valid retry; engine failure-injection for scaler creation/substitution when engine code changes. Native capture of actual pass and a supported failure/recovery case. **Exit:** honest effective mode and safe observed failure behavior; otherwise leave trial unqualified/off by default. Do not claim current Native policy handles all SDK failures.

### DT-MAC-07b — Spatial first, then Temporal

Spatial: start at 0.85 input scale on supported Mobile/Forward+; retain accepted native AA and full-output UI. Report actual internal dimensions or clearly labeled nominal estimate. Compare full GPU time and whole-session pacing/memory against Native; lower scale only after readability passes.

Temporal: require Forward+, actual features and valid engine-queried scale range; decode millionths correctly. Let Godot own depth/motion/jitter/AA. Add an engine-consumed reset acknowledgement or verified safe context recreation for actual discontinuities; the current return-to-Native latch remains the fallback until then. Never reset ordinary motion every frame, and do not copy FSR sharpening controls into MetalFX.

**Tests:** T4 plus moving distant markings, propellers/hinges, wind foliage, smoke, thin geometry/disocclusion and close/ground cues; separate Native/Spatial/Temporal A/B. **Exit:** effect executed, required motion accepted and net gain beyond noise; no provider advertised as qualified from an injected capability fixture.

### DT-MAC-07c — lifecycle and recovery

Exercise camera switch, crash focus, teleport/reset, scene/aircraft/landscape replacement, resize/fullscreen/Retina scale, output/provider change, minimization and resume after discontinuity. Verify requested/submitted/acknowledged reset separately; context/resources retire through engine-owned GPU completion. Repeated provider switches restore saved Native MSAA and maintain full-resolution UI.

**Tests:** T4 ownership/retry/history/settings tests; native allocation/lifetime and 20 transition cycles; T8 short active-physics/replay check. **Exit:** no stale history, progressive allocation, wrong AA or false provider label; Native recovery remains reachable. Final long-soak acceptance occurs in phase 9. If the trigger is absent or qualification fails, retain Native and record why.

<a id="10-first-test-session-on-the-available-m1"></a>
## 10. First test session on the available M1

This checklist preserves the existing incoming link. It executes phase 3, not an additional campaign.

1. Inventory actual host; freeze source/editor/templates/import/package and private settings. Confirm ARM64 and the expected Mac reference backend.
2. Exercise native tool/preflight/bridge/resource smoke. Confirm sample horizon, required channels and no Xvfb route on Aqua. Record unsupported channels.
3. Establish actual native 1080p/60 Hz Compatibility output, fixed detail/aircraft/weather/camera, interactive controls and Home/Fly/Workshop behavior. Capture exact local replay separately from pilot flight.
4. Run short release controls and bounded attribution, including observer-on/off. Stop and fix malformed evidence before a long run.
5. Run the three baseline active-flight soaks once; retain summary+stream, hashes and coverage. Classify real bottleneck, memory ceiling and untested gates.
6. Select one candidate from phase 4 or common-feature phase 5. Keep community packages and optional native solver work off the critical path until the reference is reproducible.

Commands live in the [Mac tooling guide](../../tools/godot/README.md#native-apple-silicon-setup-and-preflight-dt-mac-02a), [renderer trials](../../tools/graphics/README.md#isolated-mac-renderer-trials-dt-mac) and [performance tools](../../research/performance/README.md). Their existing commands must be run on the Mac, not counted as already executed here.

## 11. Phase 8 — safe product policy and voluntary sharing

**Priority/size:** P1/medium. **Dependency:** a selected short-run candidate plus proven collection semantics; final default promotion waits for phase 9. **Benefit:** make gains usable and recoverable without sacrificing cross-platform behavior. **Owner:** UI/VQ/DT/PT.

### DT-MAC-05b / 06a — persistent selection and recovery

Renderer initialization precedes GDScript preferences. The existing temporary High restart and 15-second settings confirmation cannot recover a process that never initializes. Design an existing-owner pre-engine bootstrap or bounded two-stage restart with requested choice, last-known-good configuration, attempt marker, initialization acknowledgement and failed/hung-start recovery. Keep a direct Standard launch route, bounded retries and stale-attempt handling; preserve calibration and unrelated saved preferences.

Replace the Auto adapter-name assumption only with a tested capability/measurement policy. Keep manual choices, unknown-hardware conservative behavior, versioned migration and explanation of temporary fallback. One shared application, no M1/M2/M3 forks. Keep quality fixed in qualification; later adaptive quality is conditional, with hysteresis/cooldowns, recorded transitions and presentation-only controls. Never auto-change renderer in flight or reduce physical collisions/control sampling.

**Tests:** T3/T4 preference, restart and unsupported-driver fixtures; proposed killed-before-init, hung-init, stale marker, success-then-crash distinction and failed retry cases; native external-display/Retina/fullscreen/minimize/resume paths; Windows/Linux existing-provider regression tests. **Exit:** real failed initialization recovers without a loop or lost calibration, requested/effective state is truthful, unknown device remains usable. Default selection remains provisional until the final artifact passes.

### DT-MAC-02g — share-safe community diagnostic bundle

Reuse the existing bundle/stream infrastructure, adding an explicit allowlist export mode. Keep raw developer data local. Product collection is off by default and provides start/stop, bounded destination/retention, delete, field preview and explicit manual sharing through an existing support channel. No automatic upload or new telemetry service; no tester contact is performed by this planning task.

Include version/capture ID, release/source identity, model/RAM/OS and public GPU label, requested/effective graphics/backend, actual pixel/refresh/power context, fixed workload ID, validated metrics and completeness/availability. Omit raw commands, absolute paths, environment, hostname/account/serial/UUID, radio serials, arbitrary notes/logs, screenshots and flight/input recordings by default. Optional crash/GPU traces require separate explicit attachment review and must not be advertised as safely redacted by a regex. Sanitized output gets its own hash; raw hash is not anonymity.

Developer sidecars can require local tooling, but the eventual user flow must not require Xcode, Python, root, shell commands, debugger attachment or an open debug endpoint. Package any necessary helper with the app, verify architecture/signature/lifetime, and keep collection functional or explicitly unavailable on unsupported systems. Do not add MetricKit until delayed field diagnostics solve a demonstrated problem; if selected later, account for OS availability, historical/delayed payloads, opt-out and no-report behavior separately from frame capture.

**Tests:** T2 bundle/parser tests plus proposed allowlist sentinels for usernames/paths/serials/tokens, wrong IDs, malformed/untrusted archives, traversal, quotas, cancel/delete, missing helper, offline/no-network and explicit user-choice persistence. Native packaged flow on M1; collector-overhead controls from phase 3. **Exit:** a user can inspect exactly what leaves the machine and voluntarily share a bounded usable bundle; default/off path adds no background process or network activity.

## 12. Phase 9 — sustained qualification, package and community coverage

**Priority/size:** P0 for release claims/medium. **Dependency:** selected integrated candidate and required local tests. **Benefit:** prevents a short benchmark win from becoming a hot, unstable or unreadable release. **Owner:** DT with UI/AUD/VQ/SF and vehicle owners.

### DT-MAC-08 — M1 finalist

Freeze final source/configuration and release export. Repeat three uninterrupted 30-minute active-flight runs with 30 s warmup, comparable initial conditions, complete v3/resources/required host-state coverage and minimal observers. Compare baseline/finalist early and final windows; report pacing tails/bursts, sim/wall, memory/pressure, thermal and native errors. Run 50 warm Home/flight cycles with relevant Workshop/world transitions, power/focus/sleep/wake/display changes and actual audio/controller reconnect. Perform owner pilot orientation/control acceptance independently of scripted/replayed evidence.

Qualify AC first on the M1 built-in display; battery/Low Power and 120 Hz/VRR are distinct profiles. Then test actual 1080p and higher outputs when available; lastly 720p fallback. A built-in-display result does not establish 1080p qualification, and no failure at 1080p can be hidden by a 720p default. Do not claim energy improvement from a short battery slope or relative Energy Impact.

**Tests:** T8 final required workload, lifecycle and physical-device matrix; T7 final integrated same-host replay and applicable cross-platform policy. **Exit:** required targets met through the final window and visual/control gates accepted, or named limitation/failure retained without a broad support claim.

### DT-MAC-08b — exact native package and release checks

Keep Linux export/NK gates intact; introduce explicit native-Mac stages only as needed. Require DT-MAC-02h bundle-aware identity and final reference-release exact replay even when Mac NK-3 is absent. Verify universal/single-slice policy, actual ARM64 execution, dynamic dependencies, resources, beta workaround, UUID/symbol identity, sign/notarize/staple requirements under DT and downloaded/quarantined behavior. Test the final distributed bytes, not just an editor project. Diagnostic builds with attach entitlements are separate from final release; never leave `get-task-allow` or disable library validation merely to make profiling convenient.

**Tests:** T9 once on the frozen final integration; existing package/resource/version/manifest checks; actual downloaded native launch, recovery and representative flight on oldest claimed OS compatible with that hardware plus a named newer OS. Hosted CI can qualify automated launch/software checks, not physical GPU/radio/thermal behavior. **Exit:** exact bytes and each claimed architecture/OS route have evidence; source, package and native sidecars agree. Signing/trust or unsupported OS gaps remain explicit.

### DT-MAC-08a / 09 — community coverage and promotion

Publish a reproducible optional tester procedure and sanitized local report schema through normal project documentation when implemented. Begin with named M2–M5 configurations as access permits; newer actual devices get additional rows. Record chip variant, GPU cores, RAM, cooling/chassis, OS, power and display separately. Announced models are not tested hardware; a base/newer chip is not equivalent to an older Max/Ultra. Retain the M1 control after any newer-device optimization.

Use three separate ledger columns: **launch**, **software/visual correctness**, **sustained performance/control**. Short volunteer logs are screening evidence; only complete required runs close the relevant row. Validate untrusted bundles before analysis, group comparable workloads and disclose selection bias/missing configurations. Do not require every chip/SKU to finish the first M1-qualified release, but do require evidence for every generation/profile named in a broad performance claim. The earlier M1–M5 objective remains five open rows until measured, not a blanket promise inferred from M1.

**Tests:** required common-path smoke/performance/readability on each claimed host; full suite reruns only for changes or platform-specific coverage needs, not for every incoming JSON report. **Exit:** selected default/manual presets match measured coverage, rollback available, release notes name supported/untested configurations and optional branches. Core completion requires mandatory M1 and claimed-package gates; optional feature completion requires that feature's own gates.

## 13. Phase 10 — conditional NK-3 ARM64 project

The [native kernel feasibility and implementation specification](../../APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md) expands DT-MAC-04n1–n4 with the source assessment, primary references, six-phase work breakdown, effort estimates and benchmark/test matrix. This master plan retains priority, status and promotion ownership; dated evidence identifies the implementation actually tested.

The [twelve-investigation reinforcement, 2026-11-12](../research/native-kernel/apple-silicon-plan-reinforcement-2026-11-12.md) adds observable numerical/binding controls, A/A and run-level comparison rules, actual M1 tool/energy availability, early signed-host/translocation feasibility, final stapling/receipt order and a coordinated identity/CI requalification matrix. These requirements are integrated into the specification; evaluator and product hardware qualification remain pending. Resolve host loading and supported receipt access before fleet investment, and re-estimate if a custom product engine or trust redesign is required.

The subsequent [isolated M1 experiments](../research/native-kernel/apple-silicon-m1-experiments-2026-11-12.md) prove access, a focused math test and standalone compilation, while exposing a NaN odd-tail mismatch in naive NEON/vDSP candidates and substantial short-vector repeat variation. They add lane/tail permutation controls; they do not qualify the native evaluator, close a phase or establish complete-session gains.

**2026-11-13 initial implementation:** the user selected the experimental port. The
[dated implementation evidence](../research/native-kernel/DT-MAC-04n1/README.md)
records the scalar ARM64 builder, guarded fixed-wing source/package routes,
separate native replay identity and actual M1 checks. Ordinary Mac launches
remain reference. This testing route can exercise unqualified fixed-wing
configurations; it is not a promoted or runtime-enforced qualified fleet.
The bounded M1 assessment verified 1,386 healthy stock fleet cases with 42 rows
open. Five source pairs per completed case measured 45.5–46.0% shorter callback elapsed time
for Jensen and 55.6–55.9% for ideal-supply Electric 6S; these are elapsed callback
times, not process CPU savings. The Extra long case failed.
These detached source results do not qualify FPS, final packages or sustained
product behavior. Sanitizer loading, required native CI and distribution trust
remain open. Automatic admission and production delivery are deferred; historical
research below is not a claim that the implemented routes are absent.

**2026-11-14 source-editor adoption:** the owner subsequently requested the
five-area implementation and native default. The [source-default ledger](../research/native-kernel/DT-MAC-04n4/README.md)
records B5 source `9386f5e5...` and the actual canonical marker. Admission is
restricted to 1,382 freshly verified stock rows, configuration mutations are
guarded, and missing/stale/unqualified inputs retain reference. Forty-six rows
remain open and the aggregate fleet verdict remains fail. All 17 positive
oracles, diagnostic-host ASan/UBSan controls, three callback cases, five short
and three 30-minute pairs, independent resource reductions and required native
Mac/Linux/Windows CI passed. The canonical automatic route and exact replay,
technical Home lifecycle and full marked native/reference candidate tape passed.
Home/replay technical controls used headless/Dummy with scenery audio disabled;
audio-enabled shutdown retains four audio objects with both evaluated backends
and remains open. Source-editor physics adoption on this M1 does not qualify
public signed distribution, physical display/control acceptance, broad Apple
hardware, energy savings or a stable complete-product performance gain.

The [2026-11-13 gap audit](../../APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md#16-plan-gap-and-performance-audit--2026-11-13)
retains the historical work order. The linked source-default ledger distinguishes
completed implementation from the remaining product and distribution gates.
Source-editor performance work is independent of deferred public distribution.

**Priority/size:** P2/large. **Entry:** M1 reference still misses the relevant budget after justified script/observer work, the evaluator is a material limiter, and SF/NK owners explicitly select a port under existing backend policy. **Benefit:** possible evaluator cost reduction; no extrapolation from Linux ratios. This branch can stay deferred while renderer and diagnostics ship.

### DT-MAC-04n1 — math/toolchain feasibility, outside app

Inspect `nk_math.hpp`, build/devtools/run scripts, actual Apple Clang flags/SDK/libm and the pinned ARM64 Godot. Current x86 SSE2 left-first arithmetic and glibc assumptions cannot be reused blindly. Build a disposable math/literal oracle for finite values, signed zeros, NaN sign/payload/class, Inf, subnormals, overflow, comparisons/clamps, transcendental functions, constants and dictionary encoding. Keep `-fno-fast-math` and explicit `-ffp-contract=off`; verify compilation database and conflicting flags. Pin exact inputs and match dSYM UUIDs.

**Tests:** existing math/literal oracle extended for actual target, valid and malformed cases, deliberate negative control and ABI smoke; native sanitizer loader positive controls before trusting a report. No expensive full fleet yet. **Exit:** same-host ARM64 reference exactness is achievable without changing kernel policy; otherwise stop port and retain reference. H9 tolerance does not replace same-host native exactness.

### DT-MAC-04n2 — evaluator and harness portability

Adapt existing stage/family interfaces, not RK4/kernel ownership. Add target-specific dylib/descriptors/tool receipts and Mach-O inspections; preserve Linux build behavior. Adapt `session_baseline.py`'s Linux `.so` package assumption and source/runner identities deliberately. Reuse isolated devtools; do not copy Linux `RTLD_DEEPBIND`/preload assumptions to Mac.

**Tests:** ≥10,000 actual stage inputs across air/ground/hull and malformed cases; all five trajectory cases with ≥960 accepted ticks: trim/runway/maneuver must finish the full requested tape without fault/pause/crash; only takeoff/lake may terminate in a matching crash after that minimum. Complete every fault/restore/pending-weather prerequisite; exact negative mutation must fail with comparisons, not a timeout. Run intended family/weather/source oracles and actual native coverage counters. **Exit:** no hidden reference fallback counted as native, source-bound exactness and lifecycle pass; report refused configurations honestly.

### DT-MAC-04n3 — admission, replay and fleet

Extend loader/package identity only after target gates exist. Keep missing/corrupt/stale/wrong-ABI/wrong-slice/already-loaded refusal and reference recovery. Preserve prepared configuration mutation guards, atomic reset/restore and backend-pinned checkpoint/log identities. Execute a current-source fleet declaration; historical X8 terminals cannot qualify MoonRunner X99 or unknown Workshop variants. The four currently excluded MoonRunner rows block a full-fleet claim until fresh evidence resolves them. A narrowed qualified surface must be enforced in actual runtime admission with reference fallback outside it, not merely documented in a report. Helicopter and ground vehicle remain separate.

**Tests:** T7 native loader/session/replay/fallback and actual current fleet/family gates; current verifier/mutant/toolchain/installation tests. **Exit:** exact candidate's admitted surface is explicit; all required rows classified as completed/refused/terminal with intended policy and no missing cases. Incomplete prefixes are not successful flights.

### DT-MAC-04n4 — native release performance and package

Build optimized ARM64 sidecar with exact engine/source/data/harness receipt. Validate each delivered universal slice or safe reference fallback for absent slices, dependencies, final signatures and downloaded package. Run five reference/native paired complete live-session cases, not only research-stage timing; check p95/tails, input/audio/render observers and sim/wall. Reuse phase-9 campaign results only when they cover the same final signed artifact and configuration. If this port changes a previously qualified artifact, rerun affected final gates. A cross-backend `.orfl` comparison is a candidate with `solver_changed`, never an exact replay. The current candidate CLI selects reference: compare a native recording to a reference candidate on the same tick/input tape, preserving each backend's own exact replay. The inverse direction needs an explicitly implemented and tested candidate backend selector.

**Tests:** T9 for the ABI/platform integration plus exact package replay/fallback; T8 final 1080p/thermal acceptance. **Exit for product/distribution admission:** material complete-workload benefit, same-host exactness, stable package and no cross-platform regressions. Only then consider automatic admission of a distributed Mac product through a recorded owner decision. The separately recorded source-editor adoption above does not satisfy these product gates. No catalog item may require NK-3 to fly.

## 14. Phase 11 — separate iOS/iPadOS feasibility and delivery

**Priority/size:** P2/large, independent of Mac optimization completion. **Entry:** explicit platform/product scope and physical target devices. **Benefit:** establish whether a sustainable compatible port is feasible; there is no existing iOS export to tune. **Owner:** DT/UI/VQ/SF/AUD with a named mobile integrator.

### DT-MAC-13i1 — export and reference feasibility

Select exact Godot/templates, Xcode/SDK, deployment floor, device classes, architecture and distribution path. Verify pinned engine iOS capabilities from source/toolchain, not current stable docs. Prepare minimal native reference flight in a disposable export with real app assets and package identity. Define signing/provisioning/development-device prerequisites; iOS simulator evidence is separately labeled.

**Tests:** export/import/resource/architecture checks and actual development-signed physical-device launch with GDScript reference. **Exit:** reproducible supported package plus initial whole-session timing/memory data; no iOS support claim from Mac success or simulator-only execution.

### DT-MAC-13i2 — lifecycle, input and resource limits

Define usable touch/controller route, safe areas/orientation/text, disconnect/reconnect/lost-input safety and RC hardware limitations. Handle foreground/background, lock, suspend, memory warning/jetsam diagnosis, save/restore, audio interruptions/route changes and thermal behavior. Do not let diagnostics callbacks advance physics or count suspended time as flight. Use existing session boundaries and fixed 240 Hz/float64; if budgets cannot be met, report feasibility failure rather than silently reducing simulation fidelity.

**Tests:** focused platform lifecycle/input/audio/session fixtures plus actual device interruption/controller/UI checks. **Exit:** safe usable flight route, bounded resource recovery and explicit supported controls/device requirements.

### DT-MAC-13i3 — shared diagnostics with an iOS adapter

Reuse versioned schema, availability, retention and consent; use a supported iOS platform integration for public host/app APIs. Do not spawn macOS CLI helpers, rely on `/proc`, expose the debug bridge to pilots or assume desktop dylib loading. Export/delete through platform UI. MetricKit remains optional delayed diagnostics with availability, no-report, multiple/historical payload and opt-out semantics.

**Tests:** common T2 schema/redaction fixtures; iOS plugin packaging, unsupported API, memory warning, suspend/cancel and sharing UI on physical device. **Exit:** bounded local voluntary collection without Xcode for users, unchanged non-iOS behavior and no automatic transmission.

### DT-MAC-13i4 — actual mobile qualification

Compare eligible Mobile/Metal and other supported paths at fixed features and actual output/aspect ratio, prioritizing 1080p where supported; then higher and finally disclosed 720p fallback. Use short pairs before finalist sustained tests, native thermal/memory evidence, moving aircraft/control review and battery context. Qualify phone/tablet/chassis/OS separately; desktop M1 acceptance is not an iPad pass.

**Tests:** focused mobile changes followed by one complete platform integration release pass and physical sustained/control/lifecycle campaign. **Exit:** named device/OS/control/performance coverage or an explicit unfulfilled feasibility gate. Any mobile default must preserve desktop behavior and the shared kernel contract.

## 15. Phase 12 — upstream-first advanced engine opportunities

**Priority/size:** P2/large. **Entry:** a supported consumer and attributed bottleneck that app-level work cannot adequately solve. **Benefit:** uncertain until a prototype proves it. These are independent optional branches, not prerequisites for first Metal or MetalFX qualification.

| Subphase | Concrete work | Validation and completion |
| --- | --- | --- |
| DT-MAC-10 Metal 4 | Inspect latest upstream source/issues; pin one implementation/patch set with editor/templates/symbols. Review allocator reuse after GPU completion, residency, barriers, cross-queue events, native callbacks, drawable/presentation and teardown. Name maintainer/upstream removal path before accepting a fork. | Engine correctness/API validation and resource/barrier tests; all OpenRC shaders/lifecycle; same OS/hardware/common-effect MTL3/MTL4 pairs, then uninstrumented M1/newer-host release. Keep MTL3 when unsupported/no meaningful benefit. |
| DT-MAC-11 newer temporal APIs | Check exact SDK/runtime/device descriptor support and engine exposure for new neural/input/subrectangle/motion conventions. | Compare identical inputs, verify actual scaler path, motion/reset/failure and net cost. No feature claim from enum, OS, chip label or marketing demonstration. |
| DT-MAC-12 interpolation | Separate engine presentation feasibility: correct depth/motion/history, UI composition, drawable scheduling, VRR, cut/reset bypass and queue depth. | Real rendered rate remains independently qualified; measure control-to-photon/latency by a valid method, presented/generated counts separately, plus fallback and sustained power. Generated frames never advance simulation or inflate the real-frame gate. |
| DT-MAC-13 advanced memory/rendering | One measured engine consumer for memoryless attachments, loading/submission, tile/mesh/indirect work, ray-traced denoising or ML; reuse supported implementation first. | Prove lifetime/synchronization/visibility/quality and whole-frame gain on supported hardware, preserving M1/M2 baseline. If current raster app has no consumer, record trigger absent and do not create one. |

**Tests:** changed engine/API focused tests first; T3–T7 relevant app checks; T9 once after a chosen engine candidate integrates; T8 full final hardware qualification. No full app campaign for every abandoned engine prototype. A custom engine with no maintenance/update owner is not an accepted performance strategy.

## 16. Review, evidence handoff and completion

Every implementation PR states the trigger, exact files/owner, one changed mechanism, expected metric and why, results and limits, and how to recover the previous configuration. Scope tests to that mechanism; broaden only for changed shared contracts, failures or final integration. Keep generated artifacts tied to source pipelines. Run deliberate mutations in disposable copies and never hand-edit physics/generated data.

Retain compact dated evidence under existing DT-MAC/owning-track homes; raw traces and unnecessary images stay in ignored output. Evidence carries actual tested source/package hashes rather than assuming a moving checkout is immutable. The source identity above is the inspected baseline; recheck relevant runtime/tool inputs against it before executing the plan, and retain any later dirty-patch identity. Concurrent unrelated documentation/asset cleanup is not Apple optimization evidence.

**Mandatory core finish:** native M1 and claimed-package gates pass, selected settings are recoverable, required tests/replay/visual/control evidence is complete, and source/artifact identity is reconciled. **Broader claims:** only named device/OS/profile rows actually qualified may be advertised. **Optional finish:** each branch either passes its own gates or records an evidence-based deferred/trigger-absent decision; optional failure cannot waive a mandatory core target.

DT-MAC-02c/d have source repairs, focused fixtures and short native Mac checks.
DT-MAC-02h final-ZIP integration passed native development export, strict signature,
fixed session-probe and exact packaged replay checks. Full release and downloaded
trust/quarantine remain open. Three bounded runtime candidates preserve numerical
contracts; five M1 static ground-shader views match byte for byte and the RC view
passed with background variability isolated by a same-shader repeat. Partial CPU
comparisons establish no gain. The corrected collector passed 60-second Metal
and Compatibility screens, but both miss the pacing budget. The optional Spatial
85% screen also misses it and leaves actual scaler execution unverified.
The integrated parse gate passed all 1,561 scripts; full CI, attribution, moving
visual/control coverage and sustained qualification remain open. Low free disk
space prevents the four-copy local mutation prelude and undermines a sustained
memory/swap campaign until adequate headroom is available. No renderer default,
thermal result, iOS support or distributed-release acceptance is promoted.
[Dated candidate and M1 evidence](../research/desktop-delivery-investigations/DT-MAC-02/README.md#dt-mac-04b--06b-optimization-candidates-2026-11-02).

The subsequent six-shader batch has focused checks, native sampled cloud parity,
bounded grass differences, Compatibility/Metal static views and exact offscreen
moon/twilight stills. Single 2560×1600 render-only pairs measured p95
37.291 → 30.939 ms on Metal and 47.959 → 34.243 ms on Compatibility. Repeated
attempts lost window drawability and were excluded. A new native development ZIP
passed signature, packaged-source, session, rendered-capture and exact replay
checks; its actual dirty Mac source identity is recorded. Repeated/sustained
performance, moving-aircraft acceptance and full release/CI gates remain open.
[Second-batch identities and evidence](../research/desktop-delivery-investigations/DT-MAC-02/README.md#dt-mac-06b-shader-work-reduction-second-batch-2026-11-02).

**2026-11-03 evidence update:** the later controlled seven-file Metal campaign supersedes the missing repeated/sustained timing evidence above for its instrumented technical circuit. All six 30-minute captures passed; measured gains were 17.6–23.2%, with 15.1–22.6% retained in the final five minutes. This advances DT-MAC-02/03 and the combined DT-MAC-06 bundle, while whole-observer uncertainty, normal-product routing, physical controls/readability, the absolute pacing budget and full release/CI stay open. [Complete scope and receipts](../research/desktop-delivery-investigations/DT-MAC-02/README.md#repeated-30-minute-metal-comparison).

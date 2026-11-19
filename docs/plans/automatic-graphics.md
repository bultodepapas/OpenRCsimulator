# Automatic graphics configuration: audit and phased plan (VQ-07h)

2026-11-18 · Owner request: audit and consolidate before expanding further. This plan is a VQ-07h subplan of the [advanced graphics plan](advanced-graphics.md). It builds on the [global plan's](global-performance-visual-quality.md) VQ-06a/b preset and Scene detail work and introduces no new track namespace. Decisions live in [DECISIONS](../DECISIONS.md#compatibility-baseline-and-a-windows-nvidia-package); evidence lives in the linked research folders. An independent review challenged the first draft, and its corrections are included below.

**Status, 2026-11-18:**

- **Owner decision:** "proceed with the plan, native kernel always". The plan is approved, and the native physics kernel ships and is used on every platform, Windows included (A6 is promoted).
- **A0 delivered.** [`auto_graphics_report.gd`](../../app/render/auto_graphics_report.gd) explains every automatic decision. AppRoot logs a `Graphics auto:` line at launch, and the bridge command `graphics_auto` returns the full report.
- **Legacy snapshot.** [`auto_graphics_snapshot.json`](../../app/tests/data/auto_graphics_snapshot.json) holds 1,558 decisions generated from the pre-refactor code: Steam GPUs, Mesa and Apple names × Windows, Linux and macOS × 720p–4K and MacBook panels. `test_auto_graphics_snapshot.gd` guards it.
- **A1 delivered, output-identical.** [`auto_graphics_policy.gd`](../../app/render/auto_graphics_policy.gd) holds every threshold and decision: renderer, Scene detail, first-launch values and calibration limits. `renderer_preference.gd`, `scene_detail.gd`, `auto_calibration.gd`, `auto_graphics_report.gd` and AppRoot delegate to it; their old constant names alias it. The snapshot reproduces all 1,558 decisions, and the test fails if a threshold copy reappears. The hardware profile is still the report's input dictionary; a separate `HardwareProfile` class waits until A4 adds CPU and RAM terms.
- **A3 step 1 delivered.** Every capability row states its `provenance` (`measured`, `measured-circular`, `benchmark-derived` or `extrapolated`) and a `correction` factor, 1.0 until A5 evidence exists. Today: the RTX 3090 and the M1 are measured (the M1's correction is 1.09, below), 46 rows benchmark-derived (2026 iGPUs, Arc, RDNA 4, Apple M) and 269 extrapolated. `lookup()` applies the correction and returns the provenance, so the runtime report shows how far each estimate is trusted. Decisions are unchanged.
- **A5 partly delivered (software and the 3090 only).**
  - Calibration now classifies CPU-bound frames from the renderer's CPU time and real frame intervals against a refresh- and cap-aware floor. A CPU-bound frame never raises Scene detail; GPU verdicts stay GPU-only. The verdict stores the CPU p95, the interval p95, refresh and SubViewport state as evidence.
  - `debugctl bugit` now includes the `graphics_auto` report and a one-line graphics summary.
  - The [worst-case protocol](../research/visual-quality-implementation/VQ-07/worst-case-2026-11-18/README.md) ran on the 3090 at 1080p, 1440p and 4K.
  - Still open: process and physics CPU in the classification, GPU clock state, the integrated-GPU Mobile/Compatibility measurement, the flying live route and the lab machines.
- **A4 step 1 delivered: Automatic Extreme.** `AutoGraphicsPolicy.extreme()` admits Extreme where Automatic picks High, High is running, VRAM ≥ 8 GB, CPU threads ≥ 8, and 1.25× the High estimate fits the 4.3 ms budget. The factor is the measured 3090 worst case. The reviewed snapshot diff changes 442 of 1,558 decisions, all High → Extreme: Windows 239, Linux 203, Mac none. Lens effects Automatic follows to Ultra. Calibration drops a missed Extreme to High and never raises to it. Verdicts now record their measured level (format 3), so a "down" measured at High still caps a later Automatic Extreme at Medium, and a policy upgrade is measured again. The host facts are read once per launch. The base model, the other tiers and Ultra shadows or planar reflections are unchanged; those need their owners' qualification.
  - Still open (independent review): the 8-thread CPU floor is a weak proxy, and calibration has no CPU-bound "down" path. The plan forbids adding one before lab CPUs are measured. The GTX 1070 passes the 1080p gate with about 2% margin.
- **A7 step 1 delivered: transparency in Settings.**
  - The Graphics info tooltip states Automatic's mode and Scene detail for this GPU, how far the estimate is trusted (measured, benchmarks, extrapolated or not in the table), and the in-flight GPU p95 once measured.
  - "Restore graphics defaults" says it also measures again. It already acts as the plan's Re-detect action.
  - The text lives in the tooltip because the page must still fit at 1080p; all eight languages are translated.
  - Still open: a Help/Support route to the full report (today `debugctl graphics_auto` and bug reports).
- **A6 Mac: the M1 row is measured (2026-11-19).** The Apple track's [DT-MAC-03b ladder](../research/desktop-delivery-investigations/DT-MAC-03b/README.md) ran the real Home → Fly route on the M1 under beta2 on an **external 1080p display** mirrored to the panel, so it is 1080p evidence, not native-panel (Retina) evidence. One owner holds the Mac for rendered measurements, so this plan runs no separate M1 anchor.
  - **Correction 1.09.** Clean 1080p frames with the GPU about 98% busy: Forward+ 17.45 ms (L09 on High) and Mobile 13.05 ms (L10). Against the 3090's 1.07 and 0.77 ms they imply `rel` 0.061 and 0.059, so the M1 row keeps the 0.055 base (the other Apple rows' benchmark ratios use it) and gains a correction of 1.09. Its High estimate at 1080p moves from 19.5 ms (+12%) to 17.9 ms (+3%) against the measured 17.45 ms. `build_gpu_capability.py` computes it from the recorded measurements; `capability.json` keeps them as cross-checks, and the test reproduces both within 5% (in-sample calibration, not validation).
  - **Scope.** It is cooled throughput: frame intervals bound GPU time from above, but the Mac had external cooling, a fanless Air in sustained play measured `rel` 0.045–0.055, and the anchor (scripted circle) and M1 (real route) workloads differ. Thermal headroom belongs to A3 step 2's power envelope. Above 1080p the single `rel` underestimates the M1 (2560×1600: 20.3 ms modelled against 22.4 ms from the M1 fit), which matters only without MetalFX. The Settings tooltip says "measured on this GPU model"; the scope lives in the row's provenance.
  - **Decisions.** None of the 1,558 snapshot decisions changes. The M1's Mac Scene detail would flip from Low to Medium only at 2.85–3.11 MP of rendered pixels, which no Apple panel or common scaled mode reaches at the Automatic MetalFX scale (3200×2000 and 3360×2100 sit just outside). Its `rel` stays far from 0.15 (High), 0.18 (120 Hz) and the High renderer budget.
  - **The Mac rules hold at 1080p.** Automatic picks Standard and Scene detail Medium on the M1 at 1080p, measured at 78.3 fps cooled. Forward+ would cost 21–27%. Scene detail High would cost 2.3% ± 2.2%, and a fanless Air in sustained play loses up to a third at heavy settings while `thermalState` stays `fair`, so Medium stays. With VSync on a 60 Hz panel every level holds a 60 fps mean; the 120 Hz cap rule does not apply. The pacing misses and Home's GPU cost belong to the Apple track (DT-MAC-03b recommendations 6–7).
  - **Still open:** the Retina branch with the panel alone (A6 below).
- **AI companion pins renewed after these edits (2026-11-18).**
  - Behavior manifest: `app_root.gd` and `main.gd`. Their edits are graphics, shadow and update-check only, with no companion admission or launch change.
  - Solver re-bind `5511bbbc → 90499aa6`: all 9 tapes identical ([receipt](../research/ai-companions/AFC-02/rebinds/2026-11-18-5511bbbc-to-90499aa6.json)), run from an LF clone in WSL. A CRLF Windows checkout makes `rebind.py` and `get-godot.sh` fail.
- **A6 Windows CPU wired into CI (not yet observed on hosted runners).** `native-kernel-windows` ran green on the hosted runner and is now required. The release export packages its qualified DLL. A new required `native-kernel-windows-package` job qualifies the exported archive on Windows before `release`. Details: [Windows release packages](../../research/native-kernel/README.md#windows-release-packages-nk-4-owner-decision-2026-11-18-native-kernel-always).

**Goal:** on first launch, any supported computer starts with the highest graphical quality it can sustain smoothly, with no player configuration. The examples range from an RTX 5090 to an integrated laptop GPU and a MacBook at its native panel.

## 1. Audit of the current system

### 1.1 What exists

| Decision | Where | Inputs | Output |
| --- | --- | --- | --- |
| Renderer (Standard/High) | [`renderer_preference.gd`](../../app/app_state/renderer_preference.gd) `plan()`, `auto_profile()` | GPU row, screen pixels, OS, saved mode, renderer guard, calibration | `user://renderer.cfg` override, which takes effect in exported builds only |
| GPU knowledge | [`gpu_capability.gd`](../../app/render/gpu_capability.gd) and [`capability.json`](../../app/data/gpu/capability.json), from [`build_gpu_capability.py`](../../tools/graphics/build_gpu_capability.py) | Adapter name (GL, Vulkan, Metal, ANGLE or Mesa) | Row id, `rel`, class, VRAM; the High cost estimate |
| Scene detail Automatic | [`scene_detail.gd`](../../app/render/scene_detail.gd) | Capability row; on Macs the rendered pixels; calibration; legacy name markers | Low/Medium/High |
| First-launch display values | `first_run_settings()` with the [`display_preferences.gd`](../../app/app_state/display_preferences.gd) hook | GPU class and `rel`, OS, Retina scale, refresh rate | MSAA, Mac full screen, 60 fps cap |
| Reconstruction Automatic | [`reconstruction.gd`](../../app/render/reconstruction.gd) `auto_mode()` | Metal capabilities, output rows | MetalFX Spatial or Native |
| Measured correction | [`auto_calibration.gd`](../../app/render/auto_calibration.gd) | GPU p95 during the first flight | Scene detail ±1; reject automatic High |
| Recovery | [`renderer_guard.gd`](../../app/app_state/renderer_guard.gd) | Unconfirmed RD launch per build | Falls back to Compatibility and blocks High for that build |
| Derived knobs | `flag_quality.gd` and Scenery tiers | Scene detail level | Follow Scene detail automatically |
| Independent knobs | `shadow_settings.gd` (shadows track), birds, meadow, max FPS, VSync | Fixed defaults | Not hardware-aware |

Coverage: 317 rows (144 discrete, 72 laptop, 100 integrated, 1 software). The Steam survey fixture `app/tests/data/steam_gpus_2026_10.json` resolves all 181 named GPUs, which covers about 96% of the surveyed share. About 300 checks guard these pieces.

### 1.2 What works

- **Detect once, store, never override the player.** Every automatic value is either re-derived (Scene detail Automatic) or stored once (first-launch values, calibration). Explicit choices always win, and Restore defaults returns to the recommendation.
- **Safety nets.** Unknown GPUs get safe defaults. A renderer that never confirms falls back per build. Editor-binary development, tests and captures are isolated from the saved renderer through the `.template` override. GPUs are keyed by normalized name, so OpenGL and Vulkan names agree.
- **A measured anchor and a self-correcting loop.** One machine anchors the data (§2), and the first-flight calibration corrects wrong estimates from real GPU time.

### 1.3 Weaknesses found

| # | Finding | Consequence |
| --- | --- | --- |
| W1 | **The decision logic is spread across six places**, each with its own thresholds: renderer budget 4.3 ms; Scene detail at rel 0.04/0.15; MSAA at rel 0.10; Mac 120 Hz at 0.18; calibration at 85%/30% of a 60 Hz frame. | Settings can contradict each other, and every new knob adds another heuristic. Nothing explains a decision end to end. |
| W2 | **Only High has a cost estimate.** Scene detail and MSAA use `rel` cut-offs. The Mac pixel rule duplicates `Reconstruction.auto_mode` and is only partly wired to it. | Tiers do not follow the frame budget at the player's resolution. Windows Scene detail ignores resolution entirely. |
| W3 | **The ceiling is too low for top GPUs.** Automatic never selects Extreme Scene detail or the optional planar reflections, and targets 60 fps only. An RTX 5090 gets the same bundle as an RTX 3060. | The owner's "RTX 5090 at maximum" requirement is not met. |
| W4 | **Compatibility is the default for most weak hardware**, even though it is never the cheapest renderer measured (§2). | Integrated GPUs, where GPU time decides smoothness, get an expensive path. |
| W5 | **CPU, RAM and power are not modeled.** Windows releases ship without the native physics kernel: 742 µs per tick against about 380 µs native. Compatibility costs 1.0–1.3 ms of render CPU per frame. | Weak-CPU laptops can be CPU-limited while the GPU looks fine, and calibration cannot tell CPU-bound from GPU-bound. |
| W6 | **One scalar per GPU.** `rel` is a single raster estimate. VRAM variants (RTX 3060 8/12 GB, 4060 Ti 8/16 GB), laptop power limits (35–140 W) and memory bandwidth are not represented. Driver quirks are not recorded. | Variants share one row. Bandwidth-bound integrated GPUs and Max-Q laptops may be overestimated. |
| W7 | **Most data is estimated.** Only the RTX 3090 is measured in this workload. The M1 row is derived from its own measurement (§2). Calibration verdicts stay on each player's machine. | Accuracy cannot improve beyond the estimates without new measurement. |
| W8 | **There is no transparency.** No UI or log explains why a computer got its settings, the renderer choice is not shown, and the only "re-detect" is Restore defaults. | Support and validation are hard, and players cannot see what Automatic did. |
| W9 | **The documentation is fragmented.** DECISIONS holds one long VQ-07h paragraph. STACK still describes Compatibility as the renderer, and the policy is spread over four documents. | Hard to maintain. This plan becomes the canonical home (A7). |
| W10 | **Renderer recovery handles only High.** `plan()` blocks and writes state only for `forward_plus` (`high_blocked_build`), and calibration can only reject High. The guard's Compatibility fallback is a command-line override that never clears a saved override for another renderer. | Adding any other automatic renderer, such as Mobile, would restart through the fallback on every launch of a failing build. |
| W11 | **The adapter name comes from the first, OpenGL, process.** On hybrid (Optimus) laptops that name can be the iGPU, while Vulkan or D3D12 later selects the dGPU. | Hybrid laptops can be misclassified. |
| W12 | **"Standard" means different renderers on different hosts.** It is Compatibility on Windows and Linux but Mobile on Apple Silicon, and Settings offers only a binary High/Standard restart. | Profile names (the look) and renderers must be separated before a third automatic profile exists. |

## 2. Evidence and extrapolation

**Measured anchors:**

- [RTX 3090 renderer and resolution matrix](../research/visual-quality-implementation/VQ-07/rtx3090-matrix-2026-11-17/README.md).
- [Setting costs at 4K](../research/visual-quality-implementation/VQ-07/knob-costs-2026-11-18/README.md).
- [Graphics ladder on the 3090 at 4K in the real route](../research/visual-quality-implementation/VQ-07/graphics-ladder-2026-11-19/README.md):
  - flight is CPU-bound at every tier, while Home is GPU-bound;
  - FSR2 never speeds up a CPU-bound frame;
  - the separate render thread gives +15–33 % but is experimental.
- [Native physics](../research/visual-quality-implementation/VQ-07/rtx3090-matrix-2026-11-17/README.md#native-kernel-follow-up-2026-11-18).
- The 7-core M1 under Mobile/Metal: 23.4 ms GPU at 2560×1600 ([DT-MAC-00-R4](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md)). That run used Medium detail, a research copy and beta1.
- The same M1 under beta2 in the real route at 720p, 900p and 1080p, on Mobile and Forward+ ([DT-MAC-03b](../research/desktop-delivery-investigations/DT-MAC-03b/README.md)).
- The [Mac display probe](../research/visual-quality-implementation/VQ-07/mac-display-probe-2026-11-18/README.md).

**GPU cost per renderer on the 3090.** These are root-viewport GPU times for the scripted pilot circle at MSAA 4× and Scene detail High; MP is rendered megapixels. The values are fitted linear terms:

| Renderer | Fixed (ms) | Per megapixel (ms) | Render CPU per frame (ms) | VRAM at 1080p |
| --- | --- | --- | --- | --- |
| Compatibility (OpenGL), 4 points | 0.93 | 0.176 | 1.0–1.3 | 0.78 GB |
| Forward+ (Vulkan), 4 points | 0.41 | 0.322 | 0.29–0.37 | 1.23 GB |
| Mobile (Vulkan), **interpolation only** | (0.32) | (0.219) | 0.23–0.24 | 0.99 GB |

The Compatibility and Forward+ fits reproduce their four points within about 5%. The Mobile row joins two points from different run sets, 1080p from the matrix and 4K from the knob benchmark. It has no residual, and it stays out of decisions until 720p and 1440p Mobile rows exist.

**How far the model extends.** For another GPU, the shipped High estimate divides the whole cost by `rel`. Only the per-pixel slope supports that. The 3090 runs at 450–700 fps, 5–17× under load, so its fixed term probably includes driver, queue and clock-state overhead that does not scale with raster throughput. Dividing that term by a small `rel` alone gives 8–19 ms for Iris Xe. Predictions for weak GPUs below are therefore **upper-bound-leaning and unvalidated** until A5 measures one.

**The first independent check, the M1 (DT-MAC-03b), supports that caveat.** Its 1080p frames give `rel` 0.059–0.061 on both renderers, now the row's correction. Across 720p, 900p and 1080p (L09, Mobile) its frame time fits 3.1 ms + 4.7 ms/MP within 0.08 ms. Against the 3090's Mobile terms the slope ratio is 0.047 but the fixed ratio 0.10: the M1's fixed share is 24% at 1080p, the 3090's 41%. Dividing the whole 3090 cost by one `rel` therefore overestimates the M1 by 1% at 1080p, 7% at 900p and 18% at 720p. The 720p run was close to CPU-bound, so its true GPU share is smaller still. This is one machine and the 3090's Mobile terms are interpolated, but it is the direction A4's refit (only the slope divided by `rel`) assumes. That refit needs its own per-row value: dividing only the slope would put the M1 at 0.047, not the 0.060 that matches its whole 1080p frame.

**Predicted GPU time per 1080p frame.** These come from the fixed + slope model divided by `rel`. Every `rel` except the 3090's is an estimate, and the weak-GPU rows carry the caveat above.

| GPU | rel | Compatibility | Forward+ | Mobile (interp.) | Forward+ at 4K |
| --- | --- | --- | --- | --- | --- |
| RTX 5090 | 1.90 | 0.7 | 0.6 | 0.4 | 1.6 |
| RTX 3090 (measured) | 1.00 | 1.3 | 1.1 | 0.8 | 3.1 |
| RTX 3060 | 0.43 | 3.0 | 2.5 | 1.8 | 7.2 |
| RTX 4060 Laptop | 0.40 | 3.2 | 2.7 | 1.9 | 7.7 |
| Arc B390 (iGPU) | 0.30 | 4.3 | 3.6 | 2.6 | 10.3 |
| GTX 1060 | 0.21 | 6.2 | 5.1 | 3.7 | 14.7 |
| GTX 1650 | 0.16 | 8.1 | 6.7 | 4.8 | 19.3 |
| Radeon 780M | 0.12 | 10.8 | 9.0 | 6.5 | 25.7 |
| Iris Xe | 0.05 | 25.9 | 21.5 | 15.5 | 61.6 |
| Steam Deck | 0.04 | 32.4 | 26.9 | 19.4 | — |
| UHD 620 | 0.02 | 64.9 | 53.8 | 38.8 | — |

**What the evidence says:**

1. **GPU and CPU limits differ per machine.** On the 5900X, the 3090 is not GPU-limited at 1080p.
   - The live route's 3.4–4.5 ms frames are mostly CPU. Even the scripted route is 71% GPU at only 1.5 ms of wall time.
   - The model predicts mid-range cards are already GPU-relevant: a GTX 1060 at about 5 ms exceeds the measured live-route frame.
   - Every dedicated GPU in the table stays well below 16.7 ms, so with a reasonable CPU all of them can hold 60 fps.
   - Integrated GPUs are clearly GPU-limited, if the model holds.
   - No claim is made for other CPUs. Automatic must model both CPU and GPU (W5).
2. **Compatibility is never the cheapest renderer measured.**
   - On GPU it costs more than Forward+ below about 3.6 MP (≈1440p).
   - It costs more than Mobile at every measured point, including 4K (2.38 against 2.13 ms).
   - On CPU it costs 3.5–5× the RD renderers at every resolution.
3. **Mobile is the cheapest measured renderer**, on GPU at 1080p and 4K and on CPU everywhere. That makes it the candidate efficient path for GPU-limited integrated graphics. Four facts temper this:
   - In this project Mobile delivers only the Standard look. `HighGraphics` and `ShadowSettings._high_active()` require Forward+, so Mobile has no SSAO, no PCSS, 2 cascades instead of 4 and no sky reflections. Temporal MetalFX and frame generation also require Forward+.
   - [`viewport_color.gd`](../../app/render/viewport_color.gd) forces an RGBA16F `use_hdr_2d` buffer on Mobile. That costs extra bandwidth on shared-memory iGPUs, which the 3090 cannot reveal.
   - DT-MAC-00-R4 finding S3 shows Mobile's subpasses do not stay in tile memory on Metal.
   - Mobile has been visually accepted only on Apple Silicon (DT-MAC-05b).
4. **High-end GPUs are underused.** The model gives an RTX 4090 or 5090 more than 10× headroom at 1080p and about 4× at 4K. The known Ultra candidates are:
   - **Extreme Scene detail.** It costs trees and draw calls, which is CPU work a GPU-ms model cannot price.
   - **Ultra shadows.** These add only filter 4 over High's current 8192 atlas, which is small.
   - **The optional planar reflections**, which need their own qualification.

**Limits.** These numbers come from one scripted view. GPU polls are cached readings, and their freshness is unverified. The [worst-case protocol](../research/visual-quality-implementation/VQ-07/worst-case-2026-11-18/README.md) (night lights, storm, lens rain, planar lake, Extreme) has since been measured on the 3090 only: +13–25% GPU over the base scene, and about 1 ms of planar-mirror wall time outside the root GPU query.

## 3. Renderer strategy (Forward+, Mobile, Compatibility)

**The owner's hypothesis:** Forward+ should be the default for almost all hardware, and Compatibility may be unnecessary. **Verdict: partly confirmed.**

- **Forward+ (High)** should be the default for every dedicated GPU whose predicted cost fits the budget. That is already about 82% of the Steam top-45 share at 1080p. It is faster than Compatibility at 1080p on the measured card, carries the High lighting features, and its CPU cost is a quarter of Compatibility's.
- **The best default for weak and integrated GPUs is not Forward+.** Forward+ has the highest per-pixel cost, and Intel's Vulkan driver is the one with the most Godot issues. The evidence points to **Mobile on Vulkan, D3D12 or Metal** as an "Efficient" profile, with the caveats in §2. Mobile is already the Apple Silicon decision (DT-MAC-05b), where it gave 1.33× Compatibility's frame rate on the M1.
- **Compatibility should not be deleted.** It is still required:
  - on hardware without Vulkan, D3D12 or Metal (Intel HD 4000–4600 on Windows, pre-GCN AMD, Fermi), where Godot falls back automatically;
  - as the renderer guard's recovery target;
  - on Intel and Rosetta Macs;
  - for CI captures under llvmpipe;
  - as the reference of the calibrated Standard look, which most visual evidence and goldens use.
- **Not shipped: Windows arm64.** If it ships, the `rendering_method.arm64="mobile"` project key would select Mobile there, not ANGLE.
- **Proposed roles:**
  - Forward+ (High): the default wherever it fits.
  - Mobile (Efficient): the default for integrated and weak GPUs once A2 validates it.
  - Compatibility (Legacy): fallback and reference only.
  - The project file keeps Compatibility as the safe baseline that engine and CI rely on, and Automatic selects the others through the existing override. The accepted cost is one extra restart on a fresh install that selects another renderer.
  - Profile names (the look) must be separated from renderers (W12). Apple Silicon's "Standard" is already Mobile.

**"Core".** This plan reads "Core" as the core renderer configuration: the `project.godot` renderer keys and their feature overrides (`.mobile`, `.arm64`), the `.template` renderer override, `rendering_device/driver`, the OpenGL and ANGLE fallbacks, and the renderer guard. A2 makes these consistent. If "Core" meant something else, for example the OpenGL core profile, A2 is where to adjust.

## 4. Phased plan

Each phase is one reviewable step with its own evidence, under step ids **VQ-07h-A0…A7**. Section 5 gives the order.

### A0. Decision report, legacy snapshot and reference baseline

- **What:**
  - Build one structured "graphics decision report". Its inputs:
    - GPU: adapter, row, class, `rel`, and both adapter names on hybrid laptops (the first OpenGL process and the RD session, W11).
    - System: OS and architecture, RD availability, RAM, CPU threads and name.
    - Display: pixels, scale and refresh.
    - Calibration.

    Its outputs carry a reason each. It is written to the log at launch and exposed as a debug-bridge command (`graphics-auto`).
  - **Before any refactor, generate the legacy decision snapshot from the current code.** It covers every Steam fixture GPU × {720p, 1080p, 1440p, 4K, MacBook native} × {Windows, Linux, macOS}. Commit it as a fixture, so A1 cannot produce its own baseline.
- **Why:** nothing can be validated or supported while decisions stay implicit (W8). The snapshot protects the refactor.
- **Affected:** `renderer_preference.gd`, `scene_detail.gd`, `gpu_capability.gd`, `debug/debug_bridge.gd`, `tools/debug`.
- **Validation:** golden reports for fixed fake inputs. The report changes no decision.

### A1. Consolidate into one policy, output-identical

- **What:** keep today's file locations and data, and add two pieces.
  - **`HardwareProfile`** detects once per launch: GPU row, class, `rel`, VRAM, adapter key, driver info (`OS.get_video_adapter_driver_info`), RD availability, `OS.get_memory_info()`, `OS.get_processor_count()` and name, display pixels, scale and refresh, OS and architecture, calibration.
  - **`AutoGraphicsPolicy`** is one pure function from a profile to the full bundle, with reasons. The bundle covers renderer, Scene detail, MSAA, reconstruction, frame cap and window mode, and later shadow and vegetation.
  - Today's entry points become thin adapters over the policy: `renderer_preference.auto_profile`, `scene_detail_level`, `first_run_settings`, the Mac pixel rule (calling `Reconstruction.auto_mode`) and the calibration offsets.
  - The legacy name markers in `scene_detail.gd` are retired only when the coverage test shows no GPU depends on them.
- **Why:** removes W1 and W2, puts every threshold in one place, and makes new knobs cheap.
- **Affected:** the modules above plus `display_preferences.gd`. The shadows, Scenery and UI owners are coordinated for their knobs.
- **Validation:** the A0 snapshot must reproduce **exactly** with today's constants: 0.40/0.325, the `rel` cut-offs and the calibration thresholds. Any refit, including this plan's 0.41/0.322 fit and per-renderer models, is a separate reviewed table diff in A4. It is never part of the refactor.

### A2. Renderer strategy (Efficient = Mobile), behind measurement

- **What:**
  1. **Gate:** A5 has measured Mobile against Compatibility on at least one Intel and one AMD integrated GPU at 1080p: GPU and CPU time, pacing and stability. Mobile's forced `use_hdr_2d` buffer is costed separately, and dropped where HDR 2D is not needed.
  2. Run a visual parity review of Mobile against the Standard look on Windows, as DT-MAC-05b did on Mac. Decide the Windows rendering driver per vendor (D3D12 or Vulkan for Intel) from the research and a measured A/B.
  3. Generalize recovery before adopting any new automatic renderer (W10):
     - a per-renderer blocked build in `plan()`;
     - calibration that can retreat from any automatic renderer;
     - a guard fallback that clears or blocks a saved non-High override, so a failing build cannot restart every launch.
  4. Separate profile names from renderers in code and the Settings UI (W12), with translated labels.
  5. If accepted, Automatic selects Mobile for integrated and weak GPUs through the same override and guard, and Compatibility becomes fallback only.
  6. Update STACK and DECISIONS.
- **Why:** W4, W10, W12 and the evidence in §2–3.
- **Affected:** `renderer_preference.gd`, `renderer_guard.gd`, `auto_calibration.gd`, `high_graphics_profile.gd`, `viewport_color.gd`, `project.godot` comments, `settings_screen.gd` and the i18n files.
- **Validation:** paired runs on the named machines (p95/p99 and pacing), owner visual acceptance, and the guard tested with forced failures for each automatic renderer. Captures stay on Compatibility.

### A3. Data model: provenance first, more fields only when they predict

- **Step 1:**
  - Give every row its provenance: measured, benchmark-derived or extrapolated. Record circular derivations such as the M1's.
  - Add one **measured correction factor** per row, filled from A5 lab machines and from calibration reports.
  - Refresh the Steam fixture quarterly, with a test that the new survey still resolves completely.
  - Extend coverage to the full DX12 tail and to handheld and arm64 names.
- **Step 2, only where A5 shows a field predicts something:** move to `openrc-gpu-capability v2`, adding:
  - a bandwidth class;
  - VRAM variants with a rule to pick among them;
  - a laptop power envelope;
  - architecture and API support;
  - known driver quirks with fixed versions, for example the AMD driver ranges in Godot #109378.
- **Why:** W6 and W7. Variants and laptops differ, and provenance tells the policy how far to trust a row.
- **Affected:** `build_gpu_capability.py`, `capability.json`, `gpu_capability.gd`, the fixtures.
- **Validation:** generator `--check`; the coverage test; and for each measured machine, prediction within ±30% of measurement after its correction.

### A4. Intelligent bundle, from quality ceiling to efficiency floor

- **What:** the policy picks the best bundle per machine under a budget. The budget is 60 fps at the platform's target resolution; the refresh-rate target applies only where predicted headroom is at least 2× (an owner decision).
  - **The model refit:** per-renderer fixed and slope terms, with only the slope divided by `rel` unless A5 shows otherwise. Reviewed as a snapshot diff.
  - **An "Ultra" tier for top GPUs:**
    - Extreme Scene detail, priced by CPU and draw-call measurement rather than the GPU model;
    - Ultra shadows (filter 4);
    - MSAA 4×;
    - planar reflections, only after their own qualification.
  - **An "Efficient" tier for integrated GPUs:** Mobile, MSAA 2× or off, Scene detail Low or Medium, and render scale through MetalFX, FSR or bilinear where the renderer allows.
  - **A CPU term:** processor class, thread count, native-kernel availability and render CPU per renderer. Weak CPUs avoid Compatibility and draw-heavy detail.
  - **A RAM term:** shared-memory iGPUs with 8 GB or less stay conservative.
- **Dependencies:** the Efficient tier needs A2's gate. Ultra needs A5's worst-case-scene protocol and CPU measurements.
- **Why:** W3 and W5. This is the owner's "5090 at maximum, integrated as good as it can be while smooth" requirement.
- **Affected:** the policy; `shadow_settings.gd` (an automatic quality value, coordinated with the shadows track); `scene_detail.gd` (Extreme becomes automatically reachable for qualified tiers); Settings labels.
- **Validation:** the snapshot diff, and worst-case scenes under budget for each tier on the lab machines. On integrated GPUs, Automatic beats the previous default on p95 with equal or better image quality, by owner review.

### A5. Measurement loop and hardware lab

- **What:**
  - **First:** measure Mobile against Compatibility on at least one integrated GPU, and define the worst-case scene protocol (night lights, rain, planar lake, the live route).
  - Make calibration refresh-aware, and sample with VSync off or in a known clock state. Classify CPU-bound against GPU-bound from render CPU, process and physics time, so a slow CPU does not lower GPU settings.
  - Add an **opt-in "graphics report" export**: the decision report plus calibration, attached to bug reports and the debug bridge. It lets measured rows enter the table with provenance.
  - Assemble a reference lab of 6–8 machines:
    - owned: the RTX 3090 and an M1;
    - borrowed or community: a GTX 1650/1060-class card, an RTX 3060 Laptop, Intel Iris Xe or UHD, an AMD 780M/890M or a Steam Deck on Linux, an Intel Arc 140V, and a newer Apple M chip.

    That set spans most of the Steam share. Every machine runs one protocol: scripted route, live route and worst-case scene, at the platform's target resolution.
- **Why:** W7. Estimates must converge to measurements.
- **Affected:** `auto_calibration.gd`, the `research/performance/` tools, `tools/debug`, and one research folder per machine.
- **Validation:** after its row update, each lab machine's prediction falls within tolerance of its measurement. Calibration verdicts agree with lab results.

### A6. Platform completion

- **Windows CPU:** ship the native physics kernel in Windows release packages. This needs an owner and CI-track decision, because the Linux packaging pipeline must be extended (W5).
- **Mac:**
  - Validate the Retina branch on the M1 with the panel alone (display mirror off): native full screen, MetalFX reconfiguration during the full-screen transition, the notch, and ProMotion where available.
  - ~~Rerun the M1 anchor under beta2 at High detail.~~ Done at 1080p by DT-MAC-03b (correction 1.09, status above); the native-panel point comes with the Retina validation.
  - Add newer Apple chips through the lab.
- **Linux:** acquire a GPU-equipped Linux host to validate Automatic High and Mesa naming. The current SSH host has no GPU.
- **Hybrid laptops:** use the RD-session adapter name for classification (W11).
- **Validation:** each platform produces named-machine evidence under A5.

### A7. Player transparency and documentation

- **What:**
  - Settings shows "Automatic: GPU name → tier (reason)" for the graphics mode, with a translated "Re-detect" action that clears calibration and first-launch values.
  - The decision report is reachable from Help or Support.
  - Consolidate the VQ-07h paragraphs in DECISIONS into short decisions linking here, and update STACK.
- **Why:** W8 and W9.
- **Affected:** `settings_screen.gd` (UI track), i18n `.po` files, DECISIONS, STACK, `tools/graphics/README.md`.
- **Validation:** UI and layout tests at 1080p and at MacBook native resolution; language checks.

## 5. Order, risks and owner decisions

**Order:**

1. **A0:** the decision report and the legacy snapshot from current code.
2. **A1:** the output-identical consolidation.
3. **A5:** lab measurements, starting with one integrated GPU (Mobile against Compatibility) and the worst-case protocol.
4. **A3 step 1:** provenance and the correction factor.
5. **A2:** the renderer strategy, including the recovery generalization.
6. **A4:** the bundle and its model refit, as a reviewed snapshot diff.
7. A3 step 2 and the A6 platform items as hardware arrives; A7 last.

**Risks:**

- The 3090-derived ratios may mispredict bandwidth-bound and tile-based GPUs, and the fixed term may not scale with `rel` at all. A5 and calibration bound this.
- Mobile's look and feature set differ from both Compatibility and Forward+, so A2's visual gate is required.
- Hybrid laptops may be classified from the wrong adapter (W11).
- Ultra settings may expose unqualified features, so each needs its own evidence before Automatic may select it.
- The policy refactor must stay output-identical to the A0 snapshot.

**Owner decisions needed:**

1. The Efficient (Mobile) direction, subject to A2's evidence.
2. ~~Shipping the native kernel in Windows packages (A6)~~ **Approved 2026-11-18: native kernel always.**
3. The target refresh policy: 60 fps everywhere, or display refresh where headroom allows.
4. The hardware lab: which machines can be borrowed, and whether community testers report through the opt-in graphics report.

# Automatic graphics: current-main review, 2026-11-22

## Review identity and conclusion

Reviewed `main` at **`7940a4081e10994f34c858c4acac3d7a1a271464`**, the v0.3.3 preparation commit. Compared with the original [source audit](automatic-graphics-audit-2026-11-21/source-audit.md), its [20 investigations](automatic-graphics-audit-2026-11-21/research.md), the [canonical implementation plan](../../../plans/automatic-graphics.md), and PR 19 head `65496b21acf655bf13bc954d3cc15d01db09aef7`. [PR 19](https://github.com/bultodepapas/OpenRCsimulator/pull/19) is **merged**, through `29fe2d7e4641d5da5064eb6e580bb835771ead5c`; reviewed main is 30 commits ahead of its head. This is a reconciliation of implemented behavior and remaining work, not another initial audit or a new hardware benchmark.

**Assessment:** retain the merged repairs and the new per-option ownership design. The implementation has materially improved. The old plan overstates several remaining defects and understates the new rendered evidence. However, the system still lacks complete renderer recovery and a trustworthy measured-adjustment lifecycle. The new output-budget policy also contains a small, source-confirmed planning/application mismatch. Correct these boundaries before widening automatic quality. For performance work, prioritize the already recorded menu/loading stalls and the M1's observed GPU pressure over another general GPU survey.

The canonical plan remains the sole owner of implementation order and acceptance. This dated document records the evidence behind its updated status. No runtime, GPU database, snapshot, physics, asset or historical verification receipt was changed by this review.

## 1. What main has already improved

| Change on main | Assessment against the plan | Scope still open |
| --- | --- | --- |
| Complete-only calibration persistence, a process-local insufficient-sample cooldown, and retry after a failed write | The F07 repair is integrated. An incomplete result no longer becomes a permanent accepted verdict. | Workload identity, validity, and adjustment validation are separate F08–F12 work. [Calibration persistence][calibration-store] |
| Transactional Restore, including equal defaults, Revert/Close, failed deletion and targeted live refresh | The F13 repair is integrated. Failed deletion is visible and retryable after the display portion commits. Reset retires an old collector and updates LOD/lens/flags. | General calibration completion still does not perform the same coherent application. [Settings transaction][settings-reset]; [live refresh][live-refresh] |
| Graphics Restore preserves `rc_track` | F16 is fixed for that operation. The physical circuit is excluded from the shared graphics-default key list. | Do not claim a new native next-flight identity run from this source review. [Graphics keys][graphics-keys] |
| `auto_trial_build` records a Standard → High trial and latches Standard when the successful High child reverses the recommendation | The original F01 alternating-adapter sequence now terminates. The added sequence test persists state across simulated process boundaries. This is a useful, small mitigation. | The full A1-R1 parent-armed recovery transaction, pre-script failure and explicit High guard remain open. [Latch][renderer-latch]; [sequence test][renderer-test] |
| Specific GPU model lookup before Mesa fallback; Vega 56/64 before generic Vega; family-only rows receive conservative defaults | The original RX 6800M, Vega and unlisted RTX/RX/workstation witnesses are addressed. Midrange devices also face the new 0.75 relative-throughput floor for Extreme. | Variant suffixes, ambiguous identities and model-derived memory still need work. [Lookup][gpu-lookup]; [family flags][gpu-family]; [policy][policy] |
| First launch uses a planned output size, gives large desktops a 1080p window, and keeps native borderless output on small panels and Apple Silicon Retina | This is closer to the requested display policy than budgeting all desktops by monitor resolution. | N01 below: saved oversized windows are budgeted before the actual fit clamp. Frozen startup and live output also need separate report labels. [Output calculation][output-policy]; [startup][startup] |
| Ownership is retained per automatically managed quality option; a kept manual edit releases that option; legacy files are preserved until a kept Restore | Keep this design. It is more precise than resetting a whole preset or guessing ownership from today's defaults. The tests cover relaunch, GPU changes, manual MSAA/window preservation, failed Restore and protected storage. | Renderer Auto intent is a different store and still has no supported return control. A startup save failure is session-only with a warning; it is not durable success. [Ownership][ownership]; [ownership tests][ownership-tests] |
| Startup and Settings call `AutoGraphicsReport.runtime(false)` | The original F19 interactive driver-query dependency is removed in source. An asynchronous driver-query subsystem is unnecessary to close that original path. | Diagnostic callers still use the synchronous default. Add bounded enrichment only if needed; no measured startup/menu speedup is established here. [Startup][startup]; [report][report]; [Settings summary][settings-summary] |

### Decision-table changes are substantive

Comparing the committed JSON at PR 19 head with reviewed main gives the same **1,558 case keys**, **134 renderer changes** and **299 scene-tier changes**. All 1,558 serialized strings changed because the compact representation also gained fields; that count alone overstates the behavioral change.

For Windows/Linux 1080p, the RTX 3060 fixture changed from High renderer / Extreme scene to High renderer / High scene, 2× MSAA and Medium shadows. The RTX 5090 D V2 fixture now pins High / Extreme / 8× MSAA / Ultra shadows. These are selected policy outputs, not measured performance. The compact snapshot does not serialize every bundle member, so focused assertions must also protect fields such as shadow distance, aircraft lighting and birds. [Snapshot][snapshot]; [compact format][compact]; [first-launch tests][first-launch-tests]

The current generated table has **317 rows: 264 extrapolated, 51 benchmark-derived and two labeled measured**. The two measured rows are the RTX 3090 anchor and M1 workload correction. They are useful inputs, but not a held-out hardware qualification set. [Complete capability table][capability-table]; [provenance assignment][gpu-family]

## 2. Finding-by-finding reconciliation

“Fixed” below means the stated original failure mechanism is repaired in source, with the cited test/receipt scope. It does not mean current-main native or release qualification. “Partial” explicitly preserves both the improvement and the remaining acceptance work.

| ID | Current status | Current-main evidence and remaining action |
| --- | --- | --- |
| **F01** | **Original alternation fixed; recovery partial** | The successful Standard → High → Standard reversal latches Standard for the build. Retain it while implementing parent-verified transition state and bounded failure recovery. [Latch][renderer-latch] |
| **F02** | **Open** | Explicit restart sets `OPENRC_GRAPHICS_PROFILE=high`; guard eligibility excludes that profile. The child writes its first marker after scripts start. Cover explicit production High and failures before child initialization. [Restart][restart]; [guard][guard] |
| **F03** | **Partial** | Generic Radeon names with a reported Mesa codename now get distinct keys. Format 4 and generic name keys remain; old ambiguous evidence can still be loaded when the new description has no codename. Migrate or reject uncorrelated legacy verdicts. [Identity/load][identity] |
| **F04** | **Original precedence witnesses fixed; variants open** | RX-before-Mesa and Vega ordering are repaired. The `^rtx 5090\b` prefix still consumes D V2 as the base 5090. Add variant-aware matching before calling a result specific. [Lookup][gpu-lookup]; [generator][gpu-generator] |
| **F05** | **Original top-tier family witnesses fixed; confidence partial** | Family flags now block unlisted RTX/RX and broad workstation promotion. Specific-prefix false matches can bypass that flag, and broad Intel Iris/Arc patterns need an explicit documented confidence rule. [Family flags][gpu-family]; [policy][policy] |
| **F06** | **Open** | `vram_gb` is still a model estimate used by the 4 GB High and 8 GB Extreme gates. Distinguish estimate, verified dedicated capacity, shared/unified memory and budget. The old A2000 witness is now blocked by its family flag. [Memory gates][memory-gates] |
| **F07** | **Fixed to merged repair scope** | Incomplete results are not saved or accepted; insufficient attempts have a process-local cooldown, and failed persistence remains retryable. Keep the historical receipt's scope. [Persistence][calibration-store]; [receipt](automatic-graphics-audit-2026-11-21/README.md) |
| **F08** | **Open** | Unknown pixel/MSAA fields still match; the High veto checks output size but not the effective internal size, AA or other changed workload facts. No full workload/version acceptance contract exists. [Matching/veto][validity] |
| **F09** | **Open** | `needed()` compares the uncalibrated automatic tier with the measured tier. A stored Medium → High adjustment is not automatically validated at High; a downshift is not a successful measurement of the resulting tier. [Scheduling/application][tier-validation] |
| **F10** | **Open** | The collector accumulates samples and records `current_workload()` at completion. Only the reset generation retires it; a material graphics change can leave mixed pre/post observations in one result. [Collector][collector] |
| **F11** | **Partial** | Kept Restore now updates live consumers. Normal calibration completion still only reloads `SceneDetail.calibration` and logs the result, without the targeted viewport/consumer refresh. Reuse the new refresh boundary. [Completion][completion]; [live refresh][live-refresh] |
| **F12** | **Open** | The budget remains 60 Hz; CPU pressure blocks upward adjustment but does not choose a CPU-sensitive reduction. Missing/insufficient CPU or interval evidence is represented as zero and can permit a GPU-driven upgrade. Preserve unknown explicitly. [Evaluation][evaluation]; [existing synthetic test][cpu-test] |
| **F13** | **Fixed to merged repair scope** | Pending reset participates in transaction semantics; failed clear is retryable and the live reset is coherent. Broader storage recovery belongs to F15. [Settings transaction][settings-reset] |
| **F14** | **Open** | Settings only requests Standard or High, and `save_choice()` only accepts those values. Restore quality defaults does not restore renderer Auto. [Choice][renderer-choice]; [Settings control][settings-control] |
| **F15** | **Partial** | Preference/guard readback and explicit reset errors exist. Guard startup ignores a failed marker save; explicit restart ignores failed/unsupported `save_choice()`; display persistence still writes directly. Report durable, session-only, failed and unsupported outcomes consistently. [Guard][guard]; [restart][restart]; [display save][display-save] |
| **F16** | **Fixed for graphics Restore** | `rc_track` is outside graphics-default keys, preserving the selected physical scenario. [Graphics keys][graphics-keys] |
| **F17** | **Open scope gap** | The calibration attachment remains on the eligible flight route, not all playable activities. Show unsupported scope; add routes only with their lifecycle and workload contract. [Completion/attachment][completion] |
| **F18** | **Open** | The summary's renderer comes from raw model decisions, while stored calibration is loaded without a report-level validity decision. Saved intent, guard fallback and High veto can disagree with that text. Use the resolved effective plan. [Report][report]; [Settings summary][settings-summary] |
| **F19** | **Original interactive path fixed; diagnostic remainder** | `runtime(false)` removes the driver query from startup and Settings. Diagnostic default `runtime()` remains synchronous. Do not keep the original startup task open or claim an unmeasured speedup. [Report][report]; [startup][startup] |
| **F20** | **Open; defaults expanded intentionally** | The new top bundle is documented, but the independent hardware and option-specific gates are incomplete. Existing 3090/M1 screens cannot qualify a 5090, laptop variation or the wider database. [Top bundle][top-bundle]; [decision][decision]; [stutter evidence][stutter] |

## 3. Material remaining cases

### 3.1 N01 — saved output is budgeted before it is fitted to the monitor

**Priority: P2; high implementation return. Source-confirmed control-flow and arithmetic, not a native reproduction.**

`AutoGraphicsPolicy.output_pixels()` reads a saved window-resolution string verbatim. AppRoot stores that count before renderer selection. Later, the window application constrains the requested size to the current usable monitor rectangle, minus 32 horizontal and 64 vertical pixels for accessibility of window controls. The two paths do not share the same resolved dimensions. [Output calculation][output-policy]; [startup][startup]; [window clamp][window-clamp]

Concrete conditional witness: a saved 3840×2160 window, a 1920×1080 usable desktop, and desktop RTX 3060. Planning uses 8,294,400 pixels. Application fits approximately 1806×1016. With the current table's 0.50 relative estimate and its stored anchor, the model predicts **6.19 ms** at the saved 4K size versus **2.15 ms** at the policy's minimum 1080p budget. That crosses the **4.3 ms** automatic High gate. The scene estimate similarly selects Medium for the 4K budget versus High for the smaller output. These values are calculations of the shipped policy, not measured GPU times. [Policy][policy]; [anchor constants][anchor]; [3060 row][rtx3060]; [prediction formula][prediction]

**Repair:** resolve planned window dimensions once from validated saved mode/resolution, usable rectangle and platform display rules; consume that result in renderer selection, scene recommendation and actual window application. Preserve the deliberate frozen-per-launch policy where needed for stable world construction. Report frozen startup output separately from observed output after a live resize. Add a saved-4K/smaller-monitor integration case plus borderless, Retina, reserved-dock and unknown-usable-rectangle cases. This does not require a new performance ladder.

### 3.2 Renderer recovery is narrower than the new latch

The latch solves a successful child that changes its mind. It cannot create a child-side marker before the child executes scripts. Explicit High restart also sets an environment profile excluded by the guard. `RendererGuard.begin()` ignores `save_state()` failure, and the manual restart proceeds even when `save_choice()` returns false. The present code therefore cannot promise the complete recovery contract in A1-R1. These are traced failure paths; this review did not deliberately crash an exported game. [Guard][guard]; [restart][restart]; [renderer startup][renderer-startup]

The build-wide latch is deliberately conservative: one reversing trial blocks automatic High for that build, even if a later GPU, driver or monitor change would make it suitable. Explicit High clears it, and a new build can retry. Preserve this behavior until a stronger, bounded transition identity is available; do not relax the block solely to gain quality.

**Repair sequence:** parent-written and verified pending transition, last workable renderer, bounded automatic/fallback attempts, honest failed-write outcomes, then a supported Automatic control. Test early child failure, inherited High environment, failed marker writes and failed fallback before a managed exported-process check. Reuse current stores and guard ownership rather than adding a parallel recovery subsystem.

### 3.3 Variant and memory evidence remain conflated

The exact fixture name **NVIDIA GeForce RTX 5090 D V2** matches the base 5090 prefix and receives `rel=1.66`, `vram_gb=32` and the maximum automatic bundle. NVIDIA specifies **24 GB GDDR7** for [RTX 5090 D v2](https://www.nvidia.cn/geforce/graphics-cards/50-series/rtx-5090-d-v2/); [standard RTX 5090](https://www.nvidia.com/en-us/geforce/graphics-cards/50-series/rtx-5090/) has 32 GB. This proves a wrong model/capacity attribution. It does **not** prove an 8 GB gate crossing—both exceed it—or demonstrate that this GPU misses OpenRC's frame target. The snapshot currently preserves the misclassification. [Generator][gpu-generator]; [snapshot][snapshot]

A cheap regex ordering fix for this variant is worthwhile, but it does not complete F06. The durable design needs separate model estimate and observed memory fields, and a declared rule for unrecognized suffixes. Broad Iris/Arc rows should also receive an explicit confidence classification rather than silently assuming every matching suffix identifies a known device. Preserve known, supported aliases and laptop distinctions.

### 3.4 Identity and calibration validity still need migration

Appending a Mesa codename only when the normalized name is `radeon graphics` fixes the supplied two-chip collision. However, format 4 is unchanged. A legacy verdict under `gpu radeon graphics | <renderer>` can still be reused when a later adapter reports no chip suffix, even though the original physical device cannot be established. Synthetic `Intel(R) Graphics (ADL GT1)` and `(RPL GT2)` descriptions also normalize to the same generic key; these are code-level witnesses, not newly observed native device strings. [Identity/load][identity]

An incremental repair can conservatively invalidate ambiguous legacy evidence without first building a native device-identification bridge. For future acceptance, include the strongest available device correlation, renderer/API, relevant version, effective output/internal pixels, AA/scaler, material effects, activity and target. A missing fact remains unknown. The same validator must govern both favorable adjustments and a persisted High veto.

Sampling must capture a workload generation before warmup, discard or separate observations when it changes, and then validate the applied tier after an adjustment. Merely attaching the current dimensions when a sample ends does not establish what was measured. Existing reset-generation handling and the targeted live-refresh hook are useful building blocks. [Collector][collector]; [validity][validity]; [completion][completion]

The CPU-evidence contract has a particularly small, actionable gap: a current synthetic test explicitly accepts 50 CPU and interval samples as nonblocking while adequate fast GPU samples permit `scene_offset=+1`. In production, invalid render-CPU readings are also converted to zero. The test is evidence of the contract, not proof this sparse-sample combination occurred on a user's device. Require valid CPU/interval coverage for promotion; missing evidence should retain the existing level. [Evaluation][evaluation]; [test][cpu-test]

### 3.5 The maximum bundle is intentional, but acceptance is inconsistent

The new source, tests and first-launch examples intentionally seed 8× MSAA and Ultra/Far shadows at `rel >= 1.50` when Extreme qualifies. The broader [decision record][decision] supports per-option estimated defaults and delegates thresholds to the plan; it does not itself specify this bundle. This is not an accidental code regression. The same [plan at the reviewed commit][reviewed-plan], however, says automatic Ultra shadows require their own quality, memory and performance gates. The available source does not provide a matching 5090 qualification receipt.

**Recommendation:** reconcile the rollout scope explicitly with the owner. Keep the factual description of the shipped bundle, identify it as estimate-selected and unqualified for target performance, and gate any further expansion on option-specific evidence. Prefer withholding unqualified maximum effects from future automatic promotion while retaining manual access; a runtime change to the current default should be a separate, reviewed policy decision with a deliberate snapshot diff. Do not silently rewrite the historical gate to imply evidence exists.

## 4. What the new machine evidence changes

The [2026-11-21 stutter map][stutter], including its November 22 Linux addition, is newer than the earlier headless GOD TEST record. It records rendered native-physics runs. It explicitly calls them single-pass detection, not a repeated baseline or hardware qualification; raw runs and frame streams are retained outside Git and were not independently replayed here.

| Machine/evidence | What is now supported by the recorded report | What remains unproven |
| --- | --- | --- |
| **RTX 3090 Windows PC** | 1080p window, Forward+/Vulkan, native physics; all three recorded routes valid/complete. Flight means were 174–185 FPS with simulation pace 1.000. Settings/Controls transitions had roughly 0.28–0.76 s single stalls; first selection reached 2.8 s. | A current-main A/B, renderer-crash recovery, reset-specific acceptance, physical presentation and other devices. The recorded source predates parts of the latest first-launch policy. |
| **ANGEL MacBook Air M1** | Mobile/Metal with native physics, three valid/complete routes. Mean GPU utilization was 94–96%; Home was 42–51 FPS initially and 35–39 after return. Flight means 74–97 FPS coexist with tail misses; the fourth consecutive run's jet/Corsair p99 was 27–33 ms. | The built-in Retina panel: this run used mirrored external 1920×1080 borderless output. Thermal state was not separately recorded, so thermal throttling is a hypothesis, not an attribution. No new maximum-quality qualification follows. |
| **Megatron CT 206, Intel UHD 630** | A separate shared Linux/Weston host, Forward+/Medium fixed workload, verified native physics. Flight was 9–14 FPS; two routes timed out, sim/wall fell to about 0.43–0.66, and loading stalls reached 36–45 s. | **This is not Primis CT 405**, and it is not an Auto/Low test. Wayland undrawable intervals also leave render evidence incomplete. It cannot show that the new basic policy failed or qualify a physical desktop. |
| **Primis, Intel UHD 630** | Existing lightweight managed rendering evidence and lane limits remain reusable. | No new completed Primis tour is established by the Megatron record. The [Linux-tour commit][linux-tour] reports Primis unavailable during source freeze after a node watchdog event. |

**Priority consequence:** investigate a single reproducible menu/loading transition using existing GOD TEST/debug traces before making a broad quality reduction. Similar stalls on 3090 and M1 identify a valuable cross-platform investigation, but do not establish a shared root cause. F19's driver query has already left startup/Settings, so do not assert it caused or still causes those stalls. Attribute construction, loading, resource upload, cache/driver work and persistence with a targeted trace before choosing a fix.

Then address M1 Home and the affected flight view with a native-panel comparison, confirmed effective scaler and thermal/power observations. On Intel, first verify the actual basic Automatic/Low path in Primis's admitted lightweight lane. The forced Forward+/Medium Megatron tour is useful stress evidence, not a reason to run another heavy nine-launch campaign on Primis.

## 5. Required corrections to the plan

The accompanying canonical-plan reconciliation makes the following changes:

1. Marks PR 19 merged and the original F01, F04/F05 and interactive F19 witnesses addressed, while preserving their remaining scope.
2. Keeps per-field quality ownership and the 1080p/native-Retina strategy, adds N01's shared achievable-output resolver, and retains the recovery task with narrower remaining work.
3. Removes completed reset/circuit/cache work from the pending backlog; historical receipts remain unchanged.
4. Names the remaining migration, unknown-timing, application/validation and effective-report gaps precisely.
5. Records the maximum-bundle acceptance conflict without pretending that the implemented choice was accidental or already hardware-qualified.
6. Adds the new native stutter evidence, distinguishes Megatron from Primis, and moves a bounded menu/loading investigation ahead of broad performance retuning.
7. Preserves all 20 investigations as reusable design evidence. Their recovery, effective-capability, player-intent, workload, pacing and thermal ideas remain relevant; their older execution order does not override current implementation status.

Implementation should proceed through independently reviewable changes. The plan's small deterministic cases are the first proof for correctness. A managed native/exported check follows only for the platform behavior changed; a timed A/B is needed only for an actual performance or quality claim. The three available GPUs cannot qualify the entire generated hardware table.

## 6. Verification performed for this review

Two independent read-only reviews covered GPU classification/calibration and renderer/settings lifecycle. The lead re-read material source paths, reconciled the actual merged history, compared committed snapshots and checked NVIDIA's primary specification. Repository root and scoped instructions, documentation conventions and the OpenRC tooling skill were read.

| Check | Result and limits |
| --- | --- |
| Main identity / PR status | `main` resolved to `7940a408…`; PR 19 merged; 30 commits ahead of its head. Rechecked during the review. |
| `python3 tools/graphics/build_gpu_capability.py --check` | Passed: shipped table current, 317 rows. |
| `python3 -m unittest tools.graphics.test_build_gpu_capability -v` | Five tests passed locally. They cover generation, row/provenance structure and in-sample fits, not target-GPU performance. |
| Committed snapshot comparison | Same 1,558 keys; 134 renderer and 299 scene-tier changes. No snapshot was regenerated. |
| N01 / variant / validity witnesses | Source-traced and, for output sizes and model cost, calculated from current formulas. No new Godot or native reproduction was performed. |
| Historical repair tests | The [PR 19 receipt](automatic-graphics-audit-2026-11-21/README.md) remains evidence for its original Linux headless/reference snapshot. It is not relabeled as a current-main run. |
| Current-main CI | At 13:37 UTC on 2026-11-22, GitHub reported 48 check runs: 14 successful, six skipped and 28 in progress; no completed failure at that observation. Full automated verification was still pending. [CI run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45026329184) |
| Documentation verification | Local references/anchors, pinned repository source links and `git diff --check` passed for the accompanying documentation change. No runtime qualification is implied. |

No new MacBook, Primis or 3090 sessions were launched from this workspace. Existing recorded hardware evidence informs prioritization; native access and ownership must be reconciled through the existing platform/pool routes for a future candidate.

## Pinned source references

All code links below point to the reviewed main commit rather than a moving branch. The [full comparison](https://github.com/bultodepapas/OpenRCsimulator/compare/65496b21acf655bf13bc954d3cc15d01db09aef7...7940a4081e10994f34c858c4acac3d7a1a271464) includes unrelated work; this review limits conclusions to graphics and relevant evidence.

[calibration-store]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_calibration.gd#L294-L341
[settings-reset]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/settings_screen.gd#L1352-L1407
[live-refresh]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L2199-L2214
[graphics-keys]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/display_preferences.gd#L236-L244
[renderer-latch]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/renderer_preference.gd#L108-L143
[renderer-test]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tests/test_renderer_preference.gd#L161-L184
[gpu-lookup]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/gpu_capability.gd#L102-L130
[gpu-family]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/graphics/build_gpu_capability.py#L246-L264
[gpu-generator]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/tools/graphics/build_gpu_capability.py#L63-L74
[policy]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_graphics_policy.gd#L79-L152
[output-policy]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_graphics_policy.gd#L155-L177
[startup]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L425-L463
[ownership]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/display_preferences.gd#L158-L211
[ownership-tests]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tests/test_display_preferences.gd#L402-L459
[report]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_graphics_report.gd#L32-L89
[settings-summary]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/settings_screen.gd#L1215-L1232
[snapshot]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tests/data/auto_graphics_snapshot.json
[compact]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_graphics_report.gd#L23-L29
[first-launch-tests]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tests/test_gpu_capability.gd#L260-L298
[restart]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L2034-L2050
[guard]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/renderer_guard.gd#L33-L134
[identity]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_calibration.gd#L255-L291
[memory-gates]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_graphics_policy.gd#L92-L120
[validity]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_calibration.gd#L344-L392
[tier-validation]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_calibration.gd#L395-L426
[collector]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_calibration.gd#L107-L148
[completion]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L1772-L1791
[evaluation]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_calibration.gd#L191-L252
[cpu-test]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/tests/test_auto_calibration.gd#L100-L125
[renderer-choice]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/renderer_preference.gd#L195-L208
[settings-control]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/ui/settings_screen.gd#L465-L476
[display-save]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/display_preferences.gd#L367-L413
[top-bundle]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/auto_graphics_policy.gd#L180-L206
[decision]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/docs/DECISIONS.md#L698-L704
[stutter]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/docs/research/god-test/2026-11-21-stutter-map.md
[window-clamp]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_root.gd#L2177-L2190
[renderer-startup]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/app_state/renderer_preference.gd#L174-L191
[reviewed-plan]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/docs/plans/automatic-graphics.md#L149-L153
[linux-tour]: https://github.com/bultodepapas/OpenRCsimulator/commit/0f4d033e132198ee12f3ef1eea2dbc6c209427de

[capability-table]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/data/gpu/capability.json
[anchor]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/data/gpu/capability.json#L4-L11
[rtx3060]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/data/gpu/capability.json#L730-L738
[prediction]: https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/render/gpu_capability.gd#L133-L140

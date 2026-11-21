# VQ-07h: automatic graphics audit and first implementation

**Date:** 2026-11-21. **Source base:** [`1f24cb067ca73cc20963f65ad613e7deb4c3899b`](https://github.com/bultodepapas/OpenRCsimulator/commit/1f24cb067ca73cc20963f65ad613e7deb4c3899b), rechecked against remote `main` after implementation. **Engine:** official `4.8.beta2.official.cafc17a19`. **Owners:** VQ-07h A1-R2 / A5-R1, with Settings and AppRoot.

The [canonical phased plan](../../../../plans/automatic-graphics.md) owns execution order and current status. This directory retains the [source audit with F01–F20 evidence](source-audit.md), the [20 external research investigations and primary sources](research.md), and the verification receipt for the first bounded repair. The original audit used `57abea025f62b20233ca281d58d2acbee4ab8b8e`; its original baseline-first execution order is superseded by the canonical plan.

Implementation commit: [`56f4078c2862`](https://github.com/bultodepapas/OpenRCsimulator/commit/56f4078c2862edff61dc588b68421add9b26f3f0).

## What this branch implements

| Finding / boundary | Result |
| --- | --- |
| **F07: incomplete calibration** | `save_result()` refuses incomplete evidence; `needed()` and `SceneDetail.calibrated()` ignore legacy incomplete verdicts. Insufficient attempts cannot overwrite an earlier complete result. The same adapter/renderer/output/internal-pixel/MSAA workload waits until a later process or a successfully kept Restore before another attempt; a changed workload can retry. A failed complete-result write remains eligible. |
| **F13: Restore transaction** | A pending reset is dirty even if all values already equal the defaults. Revert and Close cancel it; display-trial expiry preserves the separate Restore intent. A failed display save leaves it pending. A failed calibration deletion retains the in-memory evidence and reports the already committed display portion accurately. An unchanged retry skips rewriting the display file. Private profiles do not own the production reset. |
| **Reset-time sampling and live application** | Successful deletion increments a reset generation. A paused or reattached collector with old samples retires before it can emit a verdict, write the cache or create a cooldown. A targeted AppRoot signal reapplies viewport LOD and automatic lens/flag effects without replaying reconstruction, camera or window configuration. Failed/cancelled resets preserve the collector and evidence. |
| **F16: physical circuit** | `rc_track` is removed from the graphics-default key set and its telemetry comparison. Restore preserves On/Off through save/reload and option resolution. Actual paused-flight integration preserves the installed circuit identity and tick. Existing circuit tests independently cover terrain/collision consumers; a new next-flight identity end-to-end comparison is not claimed. |
| **Player explanation** | Settings explains insufficient GPU samples and how to retry. A partial reset failure has its own message. Both messages are translated in all eight non-English catalogs. This does not close the broader requested-versus-effective report finding F18. |

The AppRoot presentation-only edit changes a file covered by the conservative companion behavior manifest. Its source hash and the aircraft profile's manifest reference were renewed together. Controller, solver, aircraft dynamics and engine identities were not changed. Companion admission, profile and presentation checks passed with the renewed identities.

## Verification performed

All runs below used the checked Godot runner on the available **Linux headless/Dummy** environment. Where a flight was instantiated, the log explicitly selected the **GDScript reference** because the native stage library was not installed. These are software and lifecycle checks, not native-backend, rendered-GPU, pilot or performance qualification.

| Checked script | Result / relevant coverage |
| --- | --- |
| `test_auto_calibration.gd` | 109 checks passed: acceptance, legacy incomplete records, prior-result preservation, retry cooldown, interrupted/failed attempts, reset-generation invalidation and existing timing/scope decisions. |
| `test_graphics_reset_transaction.gd` | 19 checks passed: equal defaults, Revert/Close, save/delete failures, independent retry, private profiles, cooldown explanation, reset-time LOD, circuit persistence and telemetry classification. |
| `test_auto_graphics_snapshot.gd` | 1,582 checks passed, covering the same 1,558 policy decisions; no decision snapshot regenerated. |
| `test_display_preferences.gd` | 175 checks passed. |
| `test_settings_ui.gd` | Passed, including existing preview, expiry, failed-save and callback cancellation cases. |
| `test_ui_settings_integration.gd` | Passed through the actual AppRoot paused-flight route. Live LOD/lens/flags changed together; the reconstruction policy object, viewport settings, window geometry, paused tick and installed circuit identity were retained. |
| `test_advanced_graphics_settings.gd` | 159 checks passed. |
| `test_scene_detail.gd` | Passed. |
| `test_rc_track_flight.gd` | 79 checks passed for the circuit's existing physical and rendering consumers. |
| `test_telemetry_app.gd` | Passed. |
| `test_ui_language.gd` | Passed after the final catalog changes, including inventory, format arguments and glyph coverage under the script's headless scope. |
| `test_companions_behavior_manifest.gd` | 39 checks passed; intentional invalid-UTF-8 fixtures emit parsing messages while refusal assertions pass. |
| `test_companions_profiles.gd` | 95 checks passed. |
| `test_companions_presentation.gd` | 13 checks passed. |

The 14 selected script runs reported **zero checked diagnostic errors**. Settings integration and telemetry each emitted the existing native-unavailable warning; the language suite emitted it twice when starting flights. Initial resource import reported eight existing OBJ ambient-material warnings. An existing leaked test-only Node was cleaned up in the calibration test, and its final run has no warnings. The [compact machine-readable receipt](verification.json) retains exact run times, counts, log/report hashes and changed source identities; full local logs remain under `tmp/graphics-roi-checks/`.

The independent Good Enemy review led to the reset-generation guard, honest partial-save retry, accurate insufficient-sample wording and the targeted live-effects signal. The final narrow source review found no blocking issue in that handoff. It independently confirmed the manifest hashes; it did not run hardware tests.

Reproduce an individual software check using the pinned engine and the existing runner:

```sh
python3 tools/godot/run_checked.py --timeout 180 -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script res://tests/test_graphics_reset_transaction.gd
```

Use the configured test pool when available. Do not use this standalone example to bypass admission on an enrolled host.

## Evidence reused and remaining gates

The latest [three-aircraft GOD TEST tour](../../../../research/god-test/2026-11-20-performance-tour.md) was headless reference-backend functional evidence (`performance=not_qualified`). The [measurement-hardening follow-up](../../../../research/god-test/2026-11-21-measurement-hardening.md) tested monitoring/admission tooling offline. Their existing runners and fixtures are reusable; neither supplied new M1, Primis or 3090 performance results.

The documented 3090 controller-stall fix and Home resolution budget were already implemented before this branch. Their historical gains are retained in the canonical plan as prior evidence, not attributed to this patch. The M1 external-1080p ladder does not qualify its native Retina panel. The separate Megatron UHD 630 renderer comparison is not a Primis measurement.

No remote machine was contacted or launched in this follow-up. `testctl.py pool hosts` failed because `/tmp/OpenRC/testpool/config.json` was absent; no fleet connector or enrolled-host credentials were available in this session. The canonical plan specifies the smallest remaining rendered checks on the MacBook M1, Primis Intel UHD 630 and RTX 3090. Primis remains a light/medium rendered-functional lane, with a shared headless compositor and constrained memory.

Required CI and the relevant rendered/package checks remain release gates. This is a draft implementation with focused local verification, not a merged release or a claim of complete automated or native qualification.

**Still open:** finite renderer recovery and explicit High guarding; adapter matching/correlation and memory confidence; general workload-change segmentation; High-veto workload validity; validation after automatic tier changes; calibration-completion LOD/effect application; unsupported-activity scope; effective-state reporting and diagnostic latency. Reset-specific lifecycle repairs above do not close those broader findings.

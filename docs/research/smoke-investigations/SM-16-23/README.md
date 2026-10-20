# Smoke overhaul implementation evidence — SM-16–23

2026-10-20 · Windows / Godot **4.7.2.stable.official.ed1daf0bf**, OpenGL Compatibility. Core implementation is integrated; rollout qualification remains open. [Current contract](../../../SMOKE.md), [execution plan](../../../../SMOKE_SYSTEM_MASTER_PLAN.md) and [commands](../../../../tools/smoke/README.md) remain authoritative. This record describes software and rendering evidence, not measured aerosol physics or aircraft flight validation.

## Baseline and implemented scope

The [baseline source receipt](baseline-source-receipt.json) was captured at **2026-10-20 21:28:22 UTC**, against HEAD `51ad43579850b1890fc21e0f5559ef8e67976899`. It identifies the actual pre-implementation dirty working tree, not a clean checkout of that commit. Per-file SHA-256 hashes and original source copies under ignored `tmp/smoke-overhaul-baseline/` preserve its identity. Baseline checks passed 62 legacy engine-smoke checks and 36 profile checks; the retained [native baseline](baseline-native.json) passed 27 checks. Synthetic RPM/fast-pass fixtures in that report are distinct from actual accepted-source flight behavior.

Delivered changes include profile v2 with independent density/rate/motion and smooth birth palettes; explicit v1 readers and reviewed migration proposals; companion v3 stable engine/outlet bindings; ten-path proof v2; cached moving transforms and scaled physical birth apertures; accepted source tapes and a shared stock/Workshop service; bounded coherent motion, entrainment and dilution; demand allocation with at most four active emitters and 768 slots; and Workshop Stop/Pause/Restart, palette/copy controls and plume framing. Physical solver data, forces, fuel consumption and physical recipe identity were not changed for smoke.

Stik/P-51 ordinary exhaust and requested pumps share authored physical outlets. Avanti is show-only. Extra has no verified source outlet; electric installs have no ordinary combustion exhaust. The helicopter activity explicitly reports unavailable smoke until the HX-700/X-Cell propulsion/geometry pairing is established. Stale saved builds require original bindings and explicit migration; library browsing does not rewrite immutable revisions. The legacy comparison backend remains available pending native acceptance.

## Focused verification

The following retained reports passed with zero engine errors. Counts are checks within each fixture, not distinct physical validations. Logs and checked-run reports are retained under `checks/`; their original absolute invocation/output paths identify the originating machine.

| Fixture | Result / receipt |
| --- | --- |
| Source service and activity integration | [Unified smoke 41/41](checks/test_smoke_system-59yvalna/report.json); [Avanti 29/29](checks/test_avanti_smoke-4t_kcm8g/report.json); [legacy engine integration 62/62](checks/test_engine_smoke-duszx7gc/report.json). |
| Profiles, stable sources and transforms | [Profile schedule 36/36](checks/test_smoke_profiles-f7xl6lg3/report.json); [v2 renderer 41/41](checks/test_smoke_renderer_v2-sg8ernrm/report.json); [stable bindings 28/28](checks/test_smoke_bindings-t3zngd23/report.json); [presentation schema/migration 77/77](checks/test_workshop_presentation-6grpvkx2/report.json). |
| Fleet placement and source proofs | [Customization 159/159](checks/smoke-contract-bore-aircraft-lt9t1hlg/report.json); [development/native-PCK source proofs 97/97](checks/smoke-contract-sources-1qq4tgwu/report.json). |
| Immutable persistence and reviewed transfer | [Store 141/141](checks/smoke-contract-store-lwxk8w9f/report.json); [bundle 28/28](checks/test_workshop_bundle-evkg5h2k/report.json); [profile transfer 18/18](checks/test_workshop_profile_transfer-auoqn8s2/report.json); [frozen trial 44/44](checks/test_workshop_trial-zo3e59t1/report.json). |
| Workshop and controller fixtures | [Workshop integration 12/12](checks/test_workshop_smoke-mu90c1iz/report.json); [smoke AUX 60/60](checks/test_smoke_aux-yh3tr0m2/report.json); [controller AUX 38/38](checks/test_controller_aux_runtime-4s1scd4_/report.json); [controller setup passed](checks/test_controller_aux_setup-19txega7/report.json). |

Expected negative-fixture warnings remain in AUX overlap/reassignment and frozen-trial invalidation reports. The bundle fixture deliberately parses invalid UTF-8. These are not clean-log claims. Generator reproducibility/schema checks also passed **12/12**, including shared-engine outlets, strict fields and source-pin changes; run commands are in the tools guide. These focused results do not substitute for a complete repository/package/platform gate.

## Native motion and lifecycle probe

The final retained [renderer receipt](renderer/native.json), copied from `tmp/smoke-renderer-native-scaled-bore-final/`, reports **49 checks, zero failures** on an NVIDIA GeForce RTX 3090. It pins renderer/shader/scheduler/test source hashes. [Smooth swept output](renderer/smooth-swept-native.png), [paused output](renderer/paused-native.png) and [expired output](renderer/expired-native.png) accompany it. Visible mask coverage was 129 pixels; expired coverage was zero; paused multicolor output was pixel-identical.

The isolated orthographic 640×360 fixture uses a 6 m camera size and color-channel weights to estimate projected red-smoke centroids against a gray background. Eight draws without a new request drain the last GPU command before readback. The constant-target projected oracle error was **0.000067852 m**. The maximum projected centroid drift across **30/60/144 FPS** after five seconds of dynamic motion was **0.00687993 m**. These are single-side image projections on one backend, not hidden 3D particle positions, full-fleet trail continuity or physical trajectory identification.

This probe includes uniform bore scaling and independent plume width. Broader rendered clearance, high-speed curves, dense crossings, night/water/canopy intersections and target-display preference remain open. Fractional presented-pose/source alignment is integrated but still requires its complete activity/native qualification; supplied wash can lead presentation by less than one physics tick.

## Captures, performance and remaining qualification

The existing [Avanti capture receipt](avanti/capture.json) retains tailpipe, flight-trail and OFF residual/expiry views with its own source hashes. It predates the final capture refresh and must not be labeled the final accepted fleet appearance. **Final Avanti, Stik and P-51 captures: PENDING root refresh.**

**Matched performance measurement: PENDING.** [performance-status.json](performance-status.json) preserves the earlier unsuccessful/nonisolated timing attempt; it supports no idle-host delta or release-budget conclusion. Root will add the final matched workload and receipts. Capture/readback runs are not timing samples.

**50 native lifecycle cycles passed**, following three warmups: [lifecycle report](lifecycle/lifecycle.json), [checked runner](checks/lifecycle/report.json). The combined native/lifecycle suite passed 788 checks with zero errors or warnings. Each cycle configured four emitters (144 slots for the short-lifetime fixture), reset, emitted, stopped with residuals, paused, resumed through expiry, and released its scene. All post-release snapshots matched the warm baseline: 1,521 objects, 15 resources, 3 nodes and zero orphans. Renderer-reported video bytes stayed at 16,774,351. Static allocation increased 151,172 bytes while retaining bounded result records; this is not a flat OS-RSS claim. The measured cycles took 18.648 seconds. This isolated renderer fixture does not establish 50 complete Home/flight cycles or the separate **30-minute wall-time soak**, minimum-spec scene budget, supported native-platform matrix, real-radio/controller qualification or pilot acceptance.

Remaining SM-24/25 work includes those gates, fresh-checkout/package onboarding and final consolidation after qualification. No new physical calibration, smoke-fluid endurance, atlas benefit, cross-vendor image equivalence or broad visual-quality acceptance is claimed here.

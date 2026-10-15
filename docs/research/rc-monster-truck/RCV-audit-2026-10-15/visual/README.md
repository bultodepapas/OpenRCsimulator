# RCV visual and effects audit

Date: 2026-10-15. This review covers the MT8 render adapter, author rig, ground effects, wet effects, damage view, contact overlay and ground cameras. It leaves production files unchanged.

## Findings

The runtime adapter maps the accepted FRD chassis state to the supplied MT8 art correctly. An asymmetric pose probe matched all four rendered hub centers to the accepted wheel stations and A-arm travel, kept the model CG on the simulated position through yaw, confirmed steering and signed wheel-spin directions, and confirmed that soft-stop travel beyond the art envelope is reported while only the drawing saturates. The generated rig and its geometry constants match the pinned author delivery. No articulation correction is indicated.

The contact debug overlay reconstructs hubs from the same FRD corner coordinates, compression-positive travel and CG datum used by physics and the render adapter. The camera adapters consume world render positions and terrain height at that boundary. No frame-sign or pose mismatch was found in these paths.

Wet effects have fixed 32-instance pools for water and mud plus eight rings. Their render clock is capped at 0.1 s per update; malformed accepted telemetry clears visible activity; pause freezes clock and particles; reset hides the pools, clears activity and stops the voice while keeping the pools reusable. Dust and grime use bounded per-instance particles/materials, and reset clears their cosmetic state. Damage rebuilds from the cached source arrays, reuses an unchanged private mesh for identical damage, and restores the original mesh and bumper transforms on reset. The tests below cover those contracts.

The author generator `gen_rig_gd.py` is absent from the delivered source package. The repository pipeline copies and hash-checks the author's generated rig, rather than regenerating it. No generated rig was edited; any future articulation change needs the generator or must remain in the runtime adapter.

## Evidence

- [`probe_model_adapter.gd`](../../../../../research/rc-monster-truck/audit-2026-10-15/visual/probe_model_adapter.gd): 8 cross-boundary checks, 0 failures, run with headless Godot 4.7.2.
- [`test_mt8_visual.gd`](../../../../../research/rc-monster-truck/visual/test_mt8_visual.gd): 46 author-rig checks, 0 failures, including 27 travel/steering poses, wheel stations, damper alignment and signed rotation.
- [`build_visual.py --check`](../../../../../research/rc-monster-truck/build_visual.py): bundled GLB, spec and rig match their pinned source bytes.
- [`test_rcv_render_audit.gd`](../../../../../app/tests/test_rcv_render_audit.gd): 34 current-tree checks, 0 failures; verifies private damage mesh reuse/reset, source immutability, dust input rejection and pause/reset.
- [RCV-water ground-effects log](../../RCV-water/checks-final/test_rcv_ground_effects.log): 91 checks, 0 failures. [Wet-effects log](../../RCV-water/checks-final/test_rcv_wet_effects.log): 79 checks, 0 failures.

The archived RCV-water full verification receipt is not wholly green because its unrelated `test_ui_home` check exits 1; the focused effect logs above pass. No GPU capture was launched during this audit. Existing native effect captures remain in [RCV-effects](../../RCV-effects/README.md). These checks establish software behavior only; the supplied geometry is a blockout and the vehicle parameters remain estimates, not measured RC hardware.

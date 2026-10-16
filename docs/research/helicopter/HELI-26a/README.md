# HELI-26a: advanced HX-700 mechanical motion

**2026-10-15 · Windows · Godot 4.7.2-stable · Blender 5.2.2 LTS.** This work targets only the advanced articulated HX-700. The existing neutral export now has a working interactive mechanism inspector. [Current controls and reproduction](../../../../assets/aircraft/hx-700/articulated/README.md) are authoritative; [remaining flight gates](../../../plans/helicopter.md#811-articulated-hx-700-delivery-integration) remain separate.

## Implemented mechanism

The offline extractor reads the immutable owner's `.blend` in a disposable process with automatic Python execution disabled. It records 31 object transform recipes and their explicit scalar-property dependencies, including parent-inverse frames and XYZ Euler order. A restricted arithmetic compiler emits native GDScript equations, pins the construction/source identities and excludes source aerodynamic precompensation. It does not execute Blender driver strings at runtime.

The inspector drives three cyclic servo horns, tail servo, fixed/rotating swash, main/tail grips and blades, tail rod/bellcrank/slider/yoke and source transmission transforms. Grips and blades remain siblings, so feather pitch is applied once. Mast alignment, gearbox cases and the nonrotating swash/slider are preserved. Collective, cyclic and tail remain distinct inputs, with the source's phase-dependent mechanical coupling retained.

Every candidate is checked before any node transform is committed. All nine rod distances must remain within 2 µm of the neutral construction length. Endpoint orientation transports the neutral frame by a deterministic shortest rotation; rod meshes retain their neutral transforms/scales. Out-of-range/nonfinite inputs and an unreachable +100 mm rod are refused atomically. This removes the need to use Blender's Stretch To as a runtime rod-length law.

## Verification

[Verification receipt](verification.json), [native motion checks](motion-native-tests.log), [fresh-import checks](motion-fresh-tests.log), [package checks](motion-package-tests.log).

- **66 motion checks passed** in the working project, a minimal project with a fresh import cache, and an isolated PCK. These are repetitions of the same checks in three dependency environments, not 198 independent physical tests.
- **44 independent Blender poses** cover neutral, collective ±10°, cyclic ±8° on both axes, tail ±15°, combined controls and four rotor phases. Actual bound nodes' native `global_transform` values are compared with source-world samples. Maximum position difference: **0.403434 µm**; maximum basis-column difference: **1.34243 × 10⁻⁶**. Ball-link twist is underconstrained and intentionally excluded from basis equivalence; all endpoint positions are checked.
- **721 continuous combined poses** preserve servo continuity and every rigid link, with maximum length residual **0.133 µm**. **972 full-travel poses** include collective ±13°, cyclic ±10° with the source ring limit, tail ±20° and twelve phases. Every pose stays within the 2 µm closure bound.
- Tests verify signed tail pitch, equal collective pitch on both main blades, fixed swash/slider frames, unchanged gearbox cases, rendered rod alignment, instance isolation, invalid-request rollback and repeated pose reads at 30/60/144 Hz without accumulated motion.
- **Seven UI checks** pass in the same three environments: control-to-pose units/order, slow rotation, keyboard pause/reset with a focused slider, canopy/blade visibility and rejected-pose retention. [Native UI log](motion-ui-native-tests.log); [packaged UI log](motion-ui-package-tests.log).
- The existing **38 construction-admission checks** also pass. Fresh/package fixtures retain imported scenes, all texture dependencies, raw GLB and construction bytes. Missing profile, raw GLB or texture payloads remain rejected. The motion test uses its independent oracle outside the PCK; all model and motion runtime dependencies are inside it.
- Two separate Blender extractions reproduce the source snapshot and oracle byte-for-byte. The original `.blend` remains unchanged, SHA-256 `1919de349b74286bc36770ab2d7d08f743fd8a4062608d488c7e4e276103725f`. Snapshot SHA-256: `24f99dd8c7c1c9a79e4421198c27c837e44b3aa8eed9c4dfd0b4ee0293f13db3`; oracle SHA-256: `da7888a45377d4f1628d9cbe2495804c1d6e4da2a863dbd82edc819a14b3d6d7`.

## Native inspection

The fresh-project captures use Compatibility/OpenGL on an RTX 3090 at 1440×900: [neutral](neutral.png), [collective](collective.png), [cyclic](cyclic.png), [tail](tail.png), [assembled](assembled.png). The interactive panel exposes control angles, individual servo outputs and blade pitch, with head/tail/whole-model cameras, slow rotation and canopy/blade visibility. Inspection colours intentionally distinguish components; they do not qualify source PBR conversion.

## Scope

This is a bounded kinematic inspector, not a newly qualified flight model. The original source's two-pass swash reconstruction is accepted only for the tested input domain and only while its measured linkage residuals pass. No general convergence guarantee is claimed. Source maintenance adjustments are pinned to neutral; tail-belt shape-key tension, subtrim and rod adjustment controls are not exposed. No actuator lag, load/voltage response, achieved flight servo state, coning or elastic-blade dynamics is introduced.

No legacy model code, flight solver, physics data, replay format or golden flight was changed. The full application test suite and production release export were not rerun for this inspection-only change. `app/test.sh` includes compiler freshness and discovers the new native test. Flight integration, source-material baking, flight LOD/blur, distribution admission and physical/hardware qualification remain open.

# MT8 render/effects audit

Audit date: 2026-10-14. The headless render audit uses the bundled MT8 model and checks render-only damage/effects without changing the imported model or its materials.

## Findings and fixes

- Non-finite chassis speed could still drive tire dust and cosmetic grime. A non-finite wheel-slip value was converted to zero, which still allowed speed-driven dust on a malformed wheel sample. Non-finite speed or any non-finite member of the four-wheel slip array now clears dust levels and returns before grime can accrue.
- A road callback returning an infinite `height_m` could install a non-finite emitter transform and emit particles. Road height is now type- and finite-checked before positioning or emission; an invalid sample produces no dust or grime. Wheel render positions are checked before calling the road sampler.
- `GroundEffects.prepare()` attached its node before validating the model and overlay. Failed preparation now leaves the node unattached.
- A second `GroundDamageView.prepare()` could use the current deformed private mesh as a new source and break reset-to-original behavior. A prepared view now rejects repeated preparation.

The runtime fixes are limited to `ground_effects.gd` (finite telemetry/sample gates and attach-after-validation) and `ground_damage_view.gd` (reject repeated preparation). Regression coverage is in the new `test_rcv_render_audit.gd`; `test_rcv_ground_effects.gd` and `ground_grime_overlay.gdshader` are unchanged. The audit verifies private damaged geometry, source-array/material identity, cached identical damage, bumper reset, visibility preservation, valid dirt effects, invalid telemetry, pause/reset behavior, and immutable GLB/texture bytes. No source GLB or material was edited.

## Verification

Godot 4.7.2 stable, headless:

- `test_rcv_render_audit.gd`: 34 checks, 0 failures; [log](render-final.log).
- `test_rcv_ground_effects.gd`: 91 checks, 0 failures; [log](render-effects-final.log).
- `test_rcv_effects_activity.gd`: 17 checks, 0 failures; [log](render-activity-final.log).

The first failing audit run reproduced non-finite speed/height failures (29 checks, 8 failures). A follow-up run reproduced the repeated-prepare/reset failure (34 checks, 5 failures). These were fixed and the checked-in regression harness now passes. There is no preserved pre-fix console log; the regression cases are retained in `test_rcv_render_audit.gd`.

No native Compatibility capture was taken. The changes affect malformed telemetry and failed/repeated setup paths; valid-input rendering parameters are unchanged. The headless checks validate numeric effect state and source-resource immutability, not screenshot appearance.

## SHA-256 receipt

Hashes recorded after the final audit run:

| File | SHA-256 |
| --- | --- |
| `app/assets/vehicles/mt8-bisonte/MT8_Bisonte.glb` | `7967bb46673ae5b4178a3d40ad8c3b8e1a9d0350b1cc73e2084f52ab496bb0a6` |
| `app/assets/crash/smoke.png` | `33f894c2279bee9f77874dbfa3c0e9f071a0ee5e1a7065dcc40196029d699f58` |
| `app/vehicles/ground/ground_effects.gd` | `4b2a4fac94dd70a8b0f4ccbae8a9699787b3fa0c10f371f0dfafabc3307d654b` |
| `app/vehicles/ground/ground_damage_view.gd` | `dc43d6b86c2947bc3367e248d12634fc62d986239fdb9b666b15b74c3c32c31e` |
| `app/vehicles/ground/ground_grime_overlay.gdshader` | `05d1ba1b11fe7d6b69550ee4d852117be33cc63905f492ee43a8e9efacdbe987` |

The two bundled source-asset hashes are also asserted unchanged across the render audit run.

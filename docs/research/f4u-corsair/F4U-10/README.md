# F4U-10: presentation of the F4U Corsair

Built 2026-10-22 for the [F4U plan](../../../F4U-PLAN.md). Presentation only; nothing here changes the physics.

| Item | Result | Source |
| --- | --- | --- |
| Paint slots | `body` (fuselage, cowl, canopy frame, tail-wheel doors), `wing` (centre and outer panels, ailerons, six flaps, main-gear doors), `wing_tip`, `tail` (stabilizer, fin, elevator, rudder), as `standard_albedo` tints over the g1.3 livery texture | The four `paint_*` materials the author delivered, mapped surface by surface from the GLB ([customization-bindings.json](../../../../assets/aircraft/customization-bindings.json)) |
| Registration | Up to 12 characters on each side of the rear fuselage, 0.16 × 0.04 m at 1.05 m aft of D0 | Measured on the `fuselage_core` mesh (side 0.102 m out at mid-height) |
| Smoke | Show smoke at both wingtips and the tail cone; engine exhaust (`source_running`) and an exhaust smoke pump (`source_and_request`) with the `gasoline_two_stroke` preset, which fits the Moki's 50:1 premix | Wingtip and tail-cone landmarks from g1.3 metadata |
| Exhaust anchor | The left middle exhaust stack exit, direction estimated outboard, down and aft; compiled into the model geometry and exposed by `render/airplane.gd` for imported scenes, which carry no builder metadata | g1.3 landmark `R43 | Escape unido -1 2` |
| Propeller | Drawn at the physical 30 in diameter (0.762 m), not g1.3's 0.900 m scale three-blade: shaft propellers now scale to their physical size as glow propellers already did, so the visual disc matches prop-strike geometry. The P-51's visual and physical propellers are both 26 in, so it is unchanged | [render/airplane.gd](../../../../app/render/airplane.gd) |
| Lights | The generic night kit samples the model: navigation lights, wing strips and a landing light | `test_night_kit.gd` passes for the Corsair |
| Liveries | Midnight Blue (default, embedded). Coastal Three Tone and Scarlet 308 are delivered as textures and editable sources but cannot be selected: the app has no texture-livery switch yet | g1.3 `textures/liveries/` |

## Verification

[verify_f4u.gd](../../../../app/aircraft/verify_f4u.gd) checks the propeller scale, the exhaust anchor and that the slots resolve; the customization, smoke, Workshop and Home suites pass with the Corsair.

## Limits

No radial engine recording exists; the gasoline twin bank stands in. A texture-livery selector is a separate feature.

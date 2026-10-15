# P51-V13: scale lights for the P-51D

2026-10-15 · Revision 1 · **Status: implemented and verified in software.**
- The FW-35 night kit lights the P-51 from the model's own lenses, not from the model's bounds.
- The tail light rides on the rudder.
- The landing lamp lowers with the left gear leg and works only with the gear down and locked.

Prefix: P51-V13. [P-51 guide](../../../P51-PLAN.md) · Gear: [P51-11b](../P51-11b/README.md) · Night kit: [FW-35b](../../field-world/FW-35b/README.md)

## Evidence

- **Navigation lights:** the P-51D carries red (left) and green (right) wing-tip lenses and a white tail light at the base of the rudder. The model has had these lenses since V10.
- **Landing light:** on the P-51D the landing light sits in the left main-wheel well, so it shines only with the gear lowered (pilot-community and restoration sources; secondary). The CARF 1:4.3 manual does not specify a lighting installation.

## Before

The night kit placed every light from the model's bounding box:
- The tip lights were at the tip centres, not on the modelled lenses.
- The tail light floated aft of the airframe's bounding box and did not move with the rudder.
- The landing light was in the left wing's leading edge, which the P-51D does not have. It also stayed lit with the gear up.

## Change

**Optional interface (shared kit).** A model root may publish meta `light_anchors`: model-local positions keyed `nav_left`, `nav_right`, `nav_tail` and `landing`. Each anchor may also name:
- a node to `follow`, with an offset in that node's frame;
- a `gear_gated` flag.

[`aircraft_lights.gd`](../../../../app/render/world/aircraft_lights.gd) uses these anchors. `update_dynamic()` runs each presented frame from [`ground_gear.gd`](../../../../app/render/ground_gear.gd). It moves the following lights and opens gated lamps only at extension 1, which is down and locked. The gate combines with the ALL/NAV/OFF mode, so selecting ALL cannot light a stowed lamp. Kits without anchors get no per-frame work and stay unchanged; the FW-35b test passes 34/34.

**P-51 anchors.** [`p51d_model.gd`](../../../../app/aircraft/p51d_model.gd) publishes them:

| Light | Position | Basis |
| --- | --- | --- |
| Red and green tip lights | 3 mm outboard of each modelled lens | A sprite inside the lens sphere is depth-hidden by the lens |
| White tail light | 11 mm aft of the rudder's tail-light lens, following the rudder | V10 lens on the rudder base |
| Landing lamp | A 24 mm forward-facing lens on the front of the left oleo, at 30 % of the leg | Estimate. The lamp lowers out of the left well with the leg, so it is stowed in the well when the gear is up; beam 6° down from the nose, as in the kit |

The lamp is a new 12-segment disc on the left gear's parts node, so it moves with the same kinematics as the P51-11b contact paths. Node and hinge names are unchanged.

## Verification

Godot 4.7.2, native Windows ([logs](tests/)).

- [`test_p51_lights.gd`](../../../../app/tests/test_p51_lights.gd) passes 13/13:
  - The anchors are published and the tip lights sit 15.5 mm from the lens centres, outboard.
  - The tail light keeps 11 mm behind its lens as the rudder swings ±26°; worst error 5.8 × 10⁻⁸ m.
  - The landing light sits at the lamp lens face, and its crash host is that lens.
  - Gear gate: off and stowed with the gear up, off at extension 0.999, on at 1.0. Neither ALL nor NAV mode overrides the gate.
  - Through a real flight session and the ground-gear observer, the lamp is dark at the airborne start and through the 4 s extension, and lit once the gear is down and locked.
  - The Ugly Stik's kit has no following or gated lights, and the gear state never changes it.
- `test_night_kit` (FW-35b) passes 34/34, `verify_p51` 249/249, `verify_p51_clearance` 28/28 and `test_p51_retracts` 14/14.
- The model manifest was regenerated (`build_models.py`; `--check` current).

## Limits

- **Lamp mounting:** the position on the leg is an estimate. The full-size lamp is in the well, not on the leg.
- **Light values:** brightness, beam width and range are the kit's generic RC estimates (FW-35).
- **Validation:** software verification is not physical validation.

**Owner review requested:**
- the night-kit owner (FIELD-WORLD) for the optional anchor interface;
- the ground-physics owner for the `ground_gear.gd` call.

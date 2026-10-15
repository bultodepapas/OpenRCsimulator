# P51-11b: retractable gear for the P-51D

2026-10-15 · Revision 1 · **Status: implemented and verified in software.**
- The P-51 is a `retractable_taildragger` on the shared retractable-point-gear law.
- Airborne flights start clean and the runway start is down and locked.
- Sequenced doors, inclined main trunnions and a forward-retracting tail wheel are animated from the same kinematic data as the physics contact paths.

Prefix: P51-11b. [P-51 guide](../../../P51-PLAN.md) · [Tools](../../../../research/p51/p51-11/README.md) · Flaps and smoke: [P51-11a](../P51-11a/README.md)

## Evidence for the mechanism

The CARF 1:4.3 manual (the kit the P-51's flap angles and engine installation already follow; [PDF](https://carf-models.com/files/product/9b/86/19/carf_models_mustang_instructions.pdf), SHA-256 `c27824e3…c7d7ce`) describes the RC installation:

- **Main gear:** the "P-51 Retract Set" is mounted in the wing. The retracted wheel sits in the wing opening, closer to its front edge (p. 23).
- **Strut covers:** linked to the leg (pp. 24–25).
- **Inner gear doors:** worked by an air cylinder (pp. 24–25).
- **Sequencing:** gear and doors are sequenced with Ultra Precision UP-2/UP-4 valves (p. 25).
- **Tail wheel:** the mount sits 133–273 mm from the fuselage tail and the gear-door opening is *forward* of it (299–429 mm), with doors on two Robart 165 air cylinders (pp. 14–16). The tail wheel therefore swings forward and up.

The full-size P-51D likewise enclosed the main gear in the wings and the tail wheel in the fuselage, on one hydraulic lever.

## Kinematics: one source for physics and picture

`source.json` → `geometry.json` `gear.retraction`:

| Value | Model | Basis |
| --- | --- | --- |
| Right main trunnion | (0.4229, −0.1439, 0.0641) m | The deployed leg top the builder already computed on the wing skin, now source data |
| Main hinge axis (right; left mirrors to [x, −y, −z]) | (−0.203428, 0.197039, −0.959058) | Solved ([`gear_fit_probe.gd`](../../../../research/p51/p51-11/gear_fit_probe.gd)) |
| Main swing | 97.6° | Same solve |
| Tail pivot | (y −0.0898, z 1.3118) m, 30 mm above and aft of the steering point | Fit study |
| Tail swing | 85° forward | Fit study |
| Door phase | 0.2 of the travel at each end | Estimated sequencer timing |
| Inner door opening | 85° | Estimated |

The solve takes the leg to inboard, slightly aft and up, with the stub axle pointing down, so the wheel lies flat. Any rigid motion that does this is one rotation, so the result is a real single-axis hinge: inclined, like the Mustang's.

A pure fore-and-aft axis cannot work. It keeps the wheel at its deployed station, 6 cm ahead of the root leading edge, which is about 18 of 48 tyre sample points outside the airframe. The chosen hinge puts all 48 points inside the wing skins or fuselage; with a 5 mm margin 4 points touch, because a 27 in tyre nearly fills the root. The tail wheel at 85° is fully inside the tail cone.

Two V06 visual estimates were corrected to this evidence:
- **Inner doors:** they now start 0.05 m from the centreline, so they cover the stowed wheels.
- **Tail doors:** they now lie mostly forward of the tail axle (`aft_fraction` 0.2, was 0.6).

The physics paths ([`derive_physics.py`](../../../../research/p51/p51-05/derive_physics.py)) carry each deployed wheel-bottom point rigidly through the same rotation and the same smoothstep sequence (legs move over 0.2–0.8 of the travel), 129 uniform samples. The builder ([`p51d_model.gd`](../../../../app/aircraft/p51d_model.gd)) animates the identical numbers:

- **Hierarchy:** each main leg (strut, oleo, scissors, axle, wheel, strut cover) hangs from `main_gear_<side>_pivot`. The tail strut and wheel hang from `tail_gear_pivot`, above the unchanged steering node. The inner and tail doors have their own hinge pivots.
- **Rendering:** `ground_gear.gd` now calls a procedural builder's `set_gear()` with the session's accepted extension (the imported-rig path is unchanged). The built pose is down and locked.
- **Agreement:** animated wheel bottoms follow the physics paths within 0.8 µm at nine samples.

## Physics

| Item | Value | Basis |
| --- | --- | --- |
| Capability | `retractable_taildragger` (new, shared) | Taildragger topology checks plus the retraction module, on `gear.retractable_point_contacts.v1` |
| Travel | 4.0 s each way | Pneumatic RC retracts with sequenced doors (estimate); the full-size gear took 10–15 s |
| Drag area | 0.022 m² | The gear-down item of the drag build-up (0.020 m², ×1.1); moved out of CD0 |
| Drag centre | Wheel-bottom points weighted 0.45/0.45/0.10 | Estimated drag moment arm |
| CD0 | 0.0286 gear up (was 0.0447 with the gear) | Same build-up |

- **Starts:** airborne flights begin stowed and the qualified runway start begins down and locked. The shared interlock refuses retraction with weight on the wheels.
- **Gear-down drag:** total gear-down drag is unchanged. It now acts at the wheels, below the CG, so it also pitches the nose down.
- **Calibrations:**
  - The P51-19 glide calibration already used gear-up drag, so it is unchanged.
  - P51-25's body term moved from −0.0830 to −0.0833 because its CL_ref drag is now clean, as RM L6J25 flew.

## Results

| Case | Gear down | Gear up | Reference |
| --- | --- | --- | --- |
| Full-throttle level speed | 51.6 m/s (115 mph) | 58.3 m/s at 7,595 rpm | Top Flite Giant owner ≈ 115 mph; propeller zero thrust J 0.76–0.81 (67.7 m/s at that rpm) |
| Idle glide L/D at 1.4 Vs | 6.9 (band 4–8.5) | Flatter, below the clean airframe's 10.9 | P51-08 band |
| Full-throttle climb at 1.4 Vs | — | 15.5 m/s | Band 5–16 |

The envelope test now flies its sourced gear-down bands with the gear down, and adds gear-up checks against the physical limits. The landing flies with the gear lowered (touchdown 0.82 m/s sink, 35 m past the threshold, heading within 4.5°). The probe's approach case lowers the gear too.

**Known effect.** The lift-off check (a P51-22 open item) worsens from 25.3 to 26.7 m/s: the gear drag now pitches the nose down at rotation. That is physically right and not compensated.

## Shared changes made by this step (owner review requested)

- [`aircraft_contract.gd`](../../../../app/physics/aircraft_contract.gd), the contract JSON, the schema builder and `aircraft-modules-v1.json`: the `retractable_taildragger` capability and its module ID.
- [`migrate.py`](../../../../research/aircraft-standardization/migrate.py): ID-gated P-51 acceptance of its complete flap module (fixing a P51-11a `--check-known` regression that `app/test.sh` would have caught) and of its complete retraction module, in the Ventage Jet's pattern.
- [`ground_gear.gd`](../../../../app/render/ground_gear.gd): the procedural `set_gear` hook.

## Verification

Godot 4.7.2, native Windows ([logs](tests/)).

- **New and changed checks:**
  - [`test_p51_retracts.gd`](../../../../app/tests/test_p51_retracts.gd) passes 14/14: data, stowed airborne start, 4 s sequenced extension (0.20 at 0.8 s, 0.50 at 2 s), exact module drag, runway start down and locked, ground interlock, the P51-11c brakes, physics/visual path agreement and door states.
  - The P-51 envelope test passes 17/17.
  - `verify_p51` and the clearance, flaps and body-directional tests pass.
- **P51-15 probes:** all 34 airborne and 5 ground cases complete at [240](candidate-airborne-240.json) and [480 Hz](candidate-airborne-480.json) ([ground 240](candidate-ground-240.json), [480](candidate-ground-480.json)). The gear-down landing agrees between the rates: 0.817 / 0.816 m/s sink, 34.7 m in, heading within 4.5°.
- **Python checks:** schema, register, migration (`--check-known` and tests), modules, model manifests, descriptors and checkout, crash economics, the P-51 generators and the inventory oracle pass. The oracle's CD0 sentinel was updated to the gear-up value, with the reason.
- **Not caused by this step:**
  - `test_retractable_gear_ground` (Ventage Jet) fails identically at clean HEAD. It hard-codes six inputs while the Ventage Jet now also has flaps.
  - `research/propwash/e0b2/derive_geometry.py --check` reports the Ugly Stik handoff stale from float formatting alone. I reverted my regeneration of that file; it belongs to the propwash owner.
  - `test_aircraft_catalog` and `test_engine_smoke` are still blocked by the removed `AVANTI_ID`.

## P51-11c: main-wheel brakes

The CARF manual does not specify a brake installation. Giant-scale pneumatic retracts of this class offer air-operated wheel brakes, so the P-51's GP-03 wheel profile ([`wheel_profiles.json`](../../../../app/data/ground/wheel_profiles.json)) now declares brakes on the mains and none on the steerable tail wheel:

| Item | Value | Basis |
| --- | --- | --- |
| Main brake torque | 2.0 N·m each, `available` | Estimate: 2 × 2.0 N·m / 0.0857 m = 46.7 N, about 0.22 g at 21.5 kg; below the friction limit of the 43 % static wheel load (about 6 N·m at μ 0.8) |
| Tail wheel | none | Steerable tail wheel without a brake |

The brake command is the session's existing wheel-brake input; nothing aircraft-specific was added to the ground law.

**Result.** From the same 10.2 m/s taxi run, with full up elevator and a heading-hold rudder, full brakes shorten the rollout from 119.0 m to 93.3 m. The tail wheel stays loaded (no nose-over) and the heading stays within 6°.

**Finding for the ground-physics owner (GP-02).** The shared tyre law caps the longitudinal tyre force at (wheel mass / spin relaxation) × slip, with wheel mass = I/r² (0.05 kg here) and relaxation 0.03 s. That is about 1.7 N per m/s of slip per wheel. So the estimated brakes deliver an average extra deceleration of only about 0.12 m/s² over the rollout, against the 2.2 m/s² their torque implies. The P-51 data is not tuned around this; the cap belongs to the shared law. The check is therefore "the brakes act", not their full-scale effect.

## Limits

Retract timing, door phases, drag area and drag centre are estimates. The hinge axis is a fit to the scaled outline, not a measured trunnion. Moving gear mass is not modelled (the shared contract rejects it). Contacts are terminal unless locked down. Software verification is not physical validation.

# E0b2 — Stik hub and neutral tail geometry

2026-10-07 · **Status: implemented and verified; propwash remains disabled.** Main-line ROADMAP M2 E0b2. Owns the generated Stik thrust-point quantity and this geometry handoff; does not change the model team's geometry or aerodynamic coefficients.

## Change

The existing `propulsion.propeller.thrust_line_offset` is now **[-0.414176, 0, 0] m**, in the file's aft/right/up axes about the plan CG. The disc centre is **[-0.293276, 0, 0] m** in LE coordinates; the corresponding body FRD arm is **[+0.414176, 0, 0] m**. Before E0b2 the point was at the CG. This makes the hub explicit for subsequent wash/crossflow work without adding fields to the runtime schema.

The [generator](../../../../research/propwash/e0b2/derive_geometry.py) owns only that provenanced quantity in the aircraft JSON and the [neutral geometry handoff](geometry.json). It reads the editable visual geometry and requires exact agreement with the model team's compiled `ugly_stik_geometry.gd`. `--check` refuses stale outputs without rewriting them; `app/test.sh` runs it and four geometry tests.

## Coordinate evidence

The transform is `LE = [visual.z - wing.leading_z, visual.x, visual.y - equipment.shaft_y]`. It is already used by the [render adapter](../../../../app/render/airplane.gd) and documented by the model team's [equipment handoff](../../../../research/ugly-stik/model-v3/equipment_handoff.py). The visual hub is `[0, -0.005, -0.408276] m`; wing LE is visual z = -0.115 m. The physics frame explicitly sets z = 0 on the shaft, so the visual -5 mm height must not become a thrust moment arm.

The coordinate is **derived from estimated installation geometry**, not measured on the owner's airframe. The existing propeller mass centroid (-0.286 m LE, 7.276 mm aft of the disc centre) is a different quantity and stays unchanged. No inertia or CG changes are implied.

## Tail handoff

Three groups preserve actual neutral planar contours: left and right stabilizer/elevator, and fin/rudder. The generator reproduces the visual builder's 4 mm hinge gaps and elevator notch (half-width 30 mm, aft cut begins at 24 mm). It partitions each elevator half into inner and outer polygons; no guessed taper fit replaces the outline. All coordinates/areas carry units and provenance.

| Surface | Raw source polygon area (m²) | Neutral relieved/notched area (m²) | Existing aerodynamic area (m²) |
| --- | ---: | ---: | ---: |
| Horizontal, both halves | 0.0955433573 | 0.0925891573 | 0.0956 |
| Fin + rudder | 0.0483871613 | 0.0475888393 | 0.0484 |

Each horizontal half spans 0.2794 m. Its LE height is **-0.040640 m**, 5 mm above the existing free-tail pressure reference at -0.045640 m. Vertical contours span LE heights -0.026670…0.183134 m. The handoff records existing aerodynamic areas and reference positions separately: changing them would alter the established tail/oracle calibration and is outside E0b2. The ventral fin (0.0043922493 m²) is explicitly excluded because the current vertical aerodynamic surface excludes it.

**E0b3 handoff:** the runtime slipstream module currently accepts linear-chord strips, not polygons. Choose and verify a bounded strip representation against these contours, including the height-reference discrepancy, before enabling Stik wash. The loader still rejects combining downwash-gradient and slipstream data; E0b3 must reconcile their tail laws. E0b4 owns wake decay and area-weighted coverage. These polygons do not claim flow shielding, pressure-centre locations, deflected-control coverage or validated tail authority.

## Verification

[Full suite](suite-summary.log): **106 sections pass** in a fresh local clone, including golden flights and identical 30/60/144 fps states. Only the pinned engine binary was reused; imports were rebuilt and no ignored asset directories were copied. The final strengthened geometry/mutation checks also pass in that clone. Skill lint reports zero errors and the same 12 existing warnings before/after.

- `test_aircraft_data.gd`: 87 checks pass, including three-axis hub agreement against compiled geometry, prop diameter, forward location and exact equality of all six propulsion components for 15 speed/rpm cases (stopped, powered and windmill drag).
- The axial move changes signed-zero bytes in seven isolated load arrays (`+0.0` versus `-0.0`); their numeric values are exactly equal. Do not round away or retune forces to satisfy a byte comparison. All **16 complete flight fingerprints remain byte-identical** before/after (four aircraft × trim/stall/spin/ground, 960 ticks each); goldens need no regeneration.
- Four [Python tests](../../../../research/propwash/e0b2/test_geometry.py) cover known rectangle/triangle clipping, both coordinate origins, independent notch/gap area accounting, mirrored halves and changes to CG/hub/shaft/notch.
- Seven [isolated mutations](mutations.log) are rejected: hub reset to CG, changed hub provenance, stale footprint area, visual source/runtime disagreement, omitted shaft-height datum, omitted elevator notch and omitted fin hinge relief. Restored freshness and geometry tests pass.

## Cost

[Raw summary and fingerprints](cost.json). Median µs per full 240 Hz tick, three batches of 120 ticks per fixture, before/after the data change. The runtime executes the same operations; timing differences on the shared host do not establish a speed change or close Gate P.

| Aircraft / fixture | Before | After |
| --- | ---: | ---: |
| Ugly Stik / ground | 285.9 | 275.2 |
| Ugly Stik / spin | 279.8 | 242.6 |
| Ugly Stik / stall | 261.2 | 297.1 |
| Ugly Stik / trim | 240.2 | 236.5 |
| Extra 300S / ground | 222.1 | 246.2 |
| Extra 300S / spin | 232.5 | 247.4 |
| Extra 300S / stall | 267.1 | 237.4 |
| Extra 300S / trim | 253.8 | 221.6 |
| P-51D / ground | 303.1 | 306.3 |
| P-51D / spin | 240.2 | 255.9 |
| P-51D / stall | 477.8 | 474.2 |
| P-51D / trim | 423.2 | 441.4 |
| Avanti S / ground | 225.1 | 248.0 |
| Avanti S / spin | 252.9 | 232.7 |
| Avanti S / stall | 287.8 | 271.2 |
| Avanti S / trim | 267.2 | 260.1 |

## Reproduce

```bash
python3 research/propwash/e0b2/derive_geometry.py --check
python3 research/propwash/e0b2/test_geometry.py
python3 research/propwash/e0b2/check_mutations.py
$(app/get-godot.sh) --headless --path app --script res://tests/test_aircraft_data.gd
app/test.sh
```

For intentional geometry/CG changes, run the generator without `--check`, review its two outputs, then repeat verification. The measurement command is in `cost.json`.

Sources are the repository's geometry, builder and existing coordinate handoff (MIT repository code; no external assets copied). This step verifies consistency with those sources, not the installation or aerodynamic performance of a real Stik.

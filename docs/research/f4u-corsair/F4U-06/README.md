# F4U-06: provisional wing and tail geometry from R59

Measured 2026-10-21 for the [F4U plan](../../../F4U-PLAN.md); re-extracted at 1/4.5 on 2026-10-22 after the owner's scale change (every length × 10/9 of the 1/5 file, ratios and angles unchanged, checked field by field). Provisional: g1 must preserve R59's silhouette, so these sections can seed the physics source now, but g1 metrology replaces them. Published values come from [F4U-01](../F4U-01/README.md).

## Method

[extract_geometry_r59.py](../../../../research/f4u-corsair/F4U-06/extract_geometry_r59.py) poses R59 neutral in memory, as the F4U-00 review did, and intersects mesh edges with station planes in the R59 root frame (+X aft, +Y right, +Z up, full size). Right wing: inner gull panel, outer panel, three flaps and aileron, planes every 0.04 m in y. Right stabilizer with elevator, the same spacing. Fin with rudder, planes every 0.04 m in z. Leading and trailing edges are the extreme x points of each slice; incidence is the chord-line angle (leading edge up positive); thickness is the slice's vertical extent. The same script records control-surface extents, fuselage stations, nose, crash-hull points and gear paths, and writes them at 1/4.5 in the physics le frame to [geometry-r59.json](../../../../assets/aircraft/f4u-corsair-250/geometry-r59.json). The figures below are those sections at full size. Blender 5.2.2 LTS on R59 SHA-256 `94edd59b…4dc3`.

**Driver evaluation.** R59's gear and control rig runs on drivers fed by custom properties. Assigning an ID property from Python does not tag the datablock, and a frame change refreshes only time-dependent drivers, so the first gear sampling stayed frozen in the down pose. The script now tags the controls and every driven object before each evaluation. All 119 distinct driver expressions were audited as plain arithmetic and no text block auto-runs, so Blender's simple-expression evaluator handles them with auto-run scripts disabled (`-Y`).

**Gear paths.** Each path follows one material point of a tyre (its lowest vertex with the gear down) through R59's `tren_retraccion` rig, 129 samples uniform in extension. At 1/4.5 the main contact point moves 0.319 m aft and 0.363 m up when stowed; the tail contact 0.156 m aft and 0.180 m up. Paths end on the gear-down contacts with zero error.

## Results (full size; multiply lengths by 1/4.5 and areas by 1/20.25 for the model)

| Quantity | R59 | Published | Difference |
| --- | --- | --- | --- |
| Wing area, both sides to the centreline | 29.34 m² (315.8 sq ft) | 314 sq ft | +0.6 % |
| Root chord (y ≤ 0.6 m) | 2.691 m | 105.00 in = 2.667 m | +0.9 % |
| Horizontal tail area | 5.40 m² (58.1 sq ft) | 55.9 sq ft | +4 % |
| Horizontal tail span | 5.08 m (16.7 ft) | 16.5 ft | +1 % |
| Vertical tail area above z = 3.1 m | 2.08 m² (22.4 sq ft) | 22.00 sq ft | Matches when the fin is cut where it leaves the fuselage |
| Thickness ratio | 17–19 % inboard of y = 1.6 m, ≈14 % at y = 2–4 m, 13.4 % at y = 5 m, 8–9.5 % near the tip | NACA 23018 root, 23009 tip | Consistent |
| Inner gull panel | Chord midline falls ≈21° from the fuselage side (y ≈ 0.7 m) to the knee at y ≈ 1.8 m | Not recovered | To check against drawings |
| Outer panel dihedral | +10.0° (fit over y = 2.9–5.6 m) | Not recovered (OCR) | To check |
| Wing incidence | ≈0° at the root, rising to +0.5–0.9° outboard (wash-in relative to the root frame); isolated 2° values where flap and aileron pieces define the trailing edge | Not recovered | R59 is a visual reconstruction; prefer a documented value |
| Stabilizer incidence, dihedral | 0.0°, −0.3° | 1.25° incidence (NACA RM A7C05; reference line not stated) | Open |
| Fin offset | 0° | 2° left | R59 omits it; the physics can apply it without a visual change |

Planform and areas agree with the published aircraft within a few per cent, which supports using R59 (and therefore g1) for the physics planform. Angles (gull, dihedral, incidence) lack a primary source and should not be treated as validated.

## Comparison with g1.3 (2026-10-22)

g1.3's metadata landmarks, converted from its Blender frame to the le frame (`[−y, x, z]`, both from D0), agree with `geometry-r59.json`: right wingtip, tail-cone end, rudder trailing edge, propeller hub and all three wheel centres within 0.3 mm; span 2.77777 m in both. Differences:

| Item | geometry-r59.json | g1.3 | Consequence |
| --- | --- | --- | --- |
| Main-wheel contact, lateral | 12 mm inboard of the wheel plane (lowest R59 vertex) | 12.5 mm outboard left, 1.3 mm outboard right (lowest g1.3 vertex); heights agree within 0.2 mm | The lowest vertex of a low-poly tyre is laterally ambiguous. Use the wheel-plane contact (`nominal_ground_contact_m`) when F4U-08 resamples paths from g1.3's `GearRetract` |
| Visual propeller | R59's active four-blade, 0.8918 m | Three-blade, 0.9003 m; same hub | Propeller crash probes move 4 mm; take the diameter from g1.3 at F4U-05 |
| Spinner tip | On the thrust axis by construction | 5.2 mm higher (retained R49 hub dome) | Spinner crash probe only |

The physics sections stay with R59: g1.3 is a simplified copy of the same surfaces, so slicing it would add simplification error, not information.

## Limits

Extreme-point leading and trailing edges overstate chord slightly where hardware or seams protrude; the inner slices also include the fuselage-buried root and fillet. The gull values come from the chord midline, not the spar line. Full-size Reynolds-number data are not adopted by this measurement.

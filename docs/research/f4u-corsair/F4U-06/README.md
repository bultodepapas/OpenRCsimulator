# F4U-06: provisional wing and tail geometry from R59

Measured 2026-10-21 for the [F4U plan](../../../F4U-PLAN.md). Provisional: g1 must preserve R59's silhouette, so these sections can seed the physics source now, but g1 metrology replaces them. Published values come from [F4U-01](../F4U-01/README.md).

## Method

[measure_sections_r59.py](../../../../research/f4u-corsair/F4U-06/measure_sections_r59.py) poses R59 neutral in memory, as the F4U-00 review did, and intersects mesh edges with station planes in the R59 root frame (+X aft, +Y right, +Z up, full size). Right wing: inner gull panel, outer panel, three flaps and aileron, planes every 0.04 m in y. Right stabilizer with elevator, the same spacing. Fin with rudder, planes every 0.04 m in z. Leading and trailing edges are the extreme x points of each slice; incidence is the chord-line angle (leading edge up positive); thickness is the slice's vertical extent. Output: [r59_sections.json](../../../../research/f4u-corsair/F4U-06/r59_sections.json). Blender 5.2.2 LTS on R59 SHA-256 `94edd59b…4dc3`.

## Results (full size; multiply lengths by 0.2 and areas by 0.04 for 1/5)

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

## Limits

Extreme-point leading and trailing edges overstate chord slightly where hardware or seams protrude; the inner slices also include the fuselage-buried root and fillet. The gull values come from the chord midline, not the spar line. Full-size Reynolds-number data are not adopted by this measurement.

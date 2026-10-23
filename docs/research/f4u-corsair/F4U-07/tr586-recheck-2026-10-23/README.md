# F4U-07: NACA TR 586 section data checked against the page images

Done 2026-10-23 for the [F4U plan](../../../../F4U-PLAN.md). Until this check, the Corsair's section maximum lift came from the OCR text layer of [NACA TR 586](https://ntrs.nasa.gov/citations/19930091662) (Jacobs and Sherman, 1937). This check reads the scanned pages themselves.

## Method

The NTRS file is a scanned PDF behind a 436-byte prefix, with one JPEG per page. The page images were extracted with the Python standard library and read directly. Table I, "Important airfoil section characteristics", is on report pages 39–40 (PDF pages 44–45). Figure 34 (report page 25) plots the same 23012 section maximum lift against effective Reynolds number, and serves as an independent graphical cross-check. The scan is not kept in the repository.

## Result

| Quantity in [source.json](../../../../../assets/aircraft/f4u-corsair-250/source.json) | OCR value | Table I | Figure 34 |
| --- | --- | --- | --- |
| 23012 cl_max at the eight effective Reynolds numbers | 1.00, 1.15, 1.19, 1.28, 1.41, 1.53, 1.67, 1.72 | the same | the same within 0.02 |
| 23012 effective Reynolds numbers | 0.112 … **0.874** … **8.19** million | 0.112, 0.221, 0.449, **0.884**, 1.760, 3.400, 6.070, **8.160** million | — |
| 23012 α₀, slope, cm | −1.2°, 0.096/deg, −0.008 | −1.2° (−1.3° at 0.449 million), 0.096 at 0.449 and 0.884 million, −0.007 to −0.012 | — |
| 23015 | 1.60 at 3.88 million, 1.73 at 8.37 million; −1.1°, 0.098, −0.008 | the same | — |

The OCR layer had misread two Reynolds numbers. Every lift, slope and moment value was right. `source.json` now carries the two corrected numbers, and `derive_physics.py` regenerated the physics file (`a76daa38…`):

| Output | Before | After |
| --- | --- | --- |
| `aero.envelope.CL_max` | 1.155667 | 1.155345 |
| `wing_station_incidence` (stall offsets, rad) | 0.024787, −0.002576, −0.022212 | 0.024836, −0.002535, −0.022301 |

Nothing else changed. The costing dossier (which pins the physics hash), the economy runtime and the Workshop descriptor were regenerated through their generators.

## Flight effect

The F4U-12 [software baseline](../../F4U-12/README.md#software-baseline) tape, replayed as an open-loop candidate on the corrected data ([candidate.json](candidate.json), [comparison.json](comparison.json)), shows `complete: true`. Over its 10 s, the largest differences are 0.9 mm in position, 0.13 mm/s in velocity and 2.2 × 10⁻⁵ rad/s in angular rate. `solver_changed` is true because of [GP-02-R1](../../../ground-physics/GP-02/rolling-2026-10-23/README.md); on this airborne tape that change alone produced no difference. The candidate is a comparison, not exact replay.

## Still unchecked

The NACA RM A7C05 values recovered from OCR (chords, outer-panel dihedral, control travels; see [F4U-01](../../F4U-01/README.md)) remain unchecked against page images. The physics uses the R59 geometry, not those values.

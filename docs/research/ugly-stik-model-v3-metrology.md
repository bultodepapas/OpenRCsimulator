# Jensen sheet 1 metrology for model v3

This is the US-02 sheet 1 reading for the Jensen Das Ugly Stik plan. Raw page-pixel picks and the conversion record are in [`us02-jensen-sheet1-metrology.json`](../../research/ugly-stik/model-v3/us02-jensen-sheet1-metrology.json). The measured source is the local Jensen plan PDF (page 1, embedded 1-bit scan); review crops are under `references/ugly-stik/model-v3/`, especially `us02-jensen-100dpi-1.png`, `us02-p1-side-mid-100-ruler.png`, `us02-p1-top-mid-100-ruler.png`, and `us02-p1-tailplan-100-ruler.png`.

[`recompute_us02_metrology.py`](../../research/ugly-stik/model-v3/recompute_us02_metrology.py) recomputes and checks all stored derived fields from the page-pixel picks without changing the source coordinate arrays. Run `python3 research/ugly-stik/model-v3/recompute_us02_metrology.py`; the audit passes for this record.

The PDF page width is 48.29 in. A 100 dpi render is 4,829 px wide, so nominal scale is 100 px/in (0.000254 m/px). An independent sheet check reads the wing chord as 1,207 px = 12.07 in; the title block implies 12.00 in from 720 sq in / 60 in, a +0.58% scan residual. Treat all converted lengths as candidates with this scale error plus the pixel-pick error. Shared model anchors remain unchanged: wing LE z = −0.115 m, shaft y = −0.005 m, F1 z = −0.291276 m, wing span = 1.524 m, and chord = 0.3048 m. Longitudinal conversion uses the D1 reading x=808 at wing LE and x=114 at F1. The plan does not draw the engine/thrust line; vertical coordinates below use the side-face midpoint y≈2596 px as a proxy and are not certified thrust-relative heights.

The fuselage frame readings are:

| Frame | Page x (px) | Candidate z (m) | Side roof/bottom y (px) | Side height (m) | Top-view edges y (px) | Width (m) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| F4 | 2020 ± 8 | 0.1928 | 2404 / 2783 ± 4 | 0.0963 | 1361–1768 ± 5 | 0.1034 |
| F5 | 2510 ± 8 | 0.3173 | 2437 / 2782 ± 4 | 0.0876 | 1378–1754 ± 5 | 0.0955 |
| F6 | 3140 ± 8 | 0.4773 | 2522 / 2780 ± 4 | 0.0655 | 1420–1720 ± 8 | 0.0762 |

I reserved x=2800 px as a holdout between F5 and F6; its candidate z is 0.3910 m. The observed side roof/bottom are 2476/2781 px; interpolation predicts 2476.1/2781.1 px, below reading resolution. Its top width is 346 px versus 341 px interpolated, a +5 px (1.27 mm) residual. Each plan-view edge pick is uncertain by about 5 px, so this residual is below the combined edge-pick and interpolation uncertainty; the holdout does not resolve a departure from linear width taper. The detailed raw comparison is in the JSON.

At the wing root, the side-view LE is y=2377 px (visually ranged 2367–2386 px); the roof/seat probe at x=880 is y=2421 px (2420–2422 px range). Under the side-face vertical proxy these become y≈+0.0506 m and +0.0395 m. Keep these as visual candidates until the physical engine/thrust datum is established.

For the horizontal tail, the plan-detail root centerline is y≈1550 px and the farthest drawn tip is y≈450 px: 1,100 px semi-span, or 0.2794 m at scan scale (0.5588 m full span). The half-plan has leading-edge x≈3838 px, straight hinge x≈4412 px, and scalloped elevator TE nominal x≈4562 px. That gives a plan-detail chord of 724 px (0.1839 m), an elevator width of about 150 px (0.0381 m, 20.7% chord), and hinge at 79.3% chord. Mapped with the shared longitudinal anchor, these are z≈0.6546 m, 0.8004 m, and 0.8385 m respectively. The JSON records sampled outline points in page coordinates so another reader can review or revise the trace.

The side-view horizontal-tail seam independently falls at x≈4415 ± 8 px, consistent with the plan hinge within the pixel-pick range. Its rounded elevator capsule ends near x≈4605 ± 10 px, about 43 px aft of the scalloped plan-detail edge. These are separate view readings; use the plan view for planform and the side view for vertical placement (center near y=2755 ± 8 px, about −0.0454 m relative to the side-face proxy). Do not average the two trailing edges into a fabricated contour. The plan-detail hinge and elevator boundary are more actionable than the rounded capsule for hinge fraction.

Applying the shared z mapping to each sampled scalloped plan-view elevator TE point gives the following candidate coordinates. The values preserve the drawn scallop instead of substituting the nominal x=4562 TE station:

| Source page point (x,y px) | Candidate (z, lateral) m |
| --- | ---: |
| (4594, 600) | (0.846644, 0.241300) |
| (4584, 700) | (0.844104, 0.215900) |
| (4564, 800) | (0.839024, 0.190500) |
| (4563, 900) | (0.838770, 0.165100) |
| (4561, 1000) | (0.838262, 0.139700) |
| (4568, 1100) | (0.840040, 0.114300) |
| (4560, 1200) | (0.838008, 0.088900) |
| (4577, 1300) | (0.842326, 0.063500) |
| (4561, 1400) | (0.838262, 0.038100) |
| (4571, 1500) | (0.840802, 0.012700) |

The plan labels the ventral sub-rudder as 3/16-inch sheet. A coarse side silhouette can be bounded by page points near (3450,2765), (4370,2790), and (4370,2925) px, but the aft edge curves and overlaps the fuselage/tail-skid line, so these are only rough triangle anchors. The vertical fin/rudder absolute profile is intentionally omitted here: an unlabelled enlargement factor makes the callout unsuitable for absolute scaling, and the assembled side-view silhouette is being measured independently from the full page.

No calibration-v1 tail values are reused. The pixel readings are measurements of the published drawing; the metre values remain scan-scaled model candidates, not verified airframe dimensions.

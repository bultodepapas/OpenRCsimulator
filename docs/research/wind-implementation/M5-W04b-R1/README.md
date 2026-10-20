# Windsock construction, motion and verification

**2026-10-19 · M5-W04b-R1 · Targeted source review**

This note records airport windsock construction and behavior from FAA and ICAO sources. It informs visual implementation; it is not a wind-tunnel study or validation of the simulator's windsock dynamics.

## Implemented presentation

The field retains its authored 2.5 m sleeve, 0.45 m throat and 0.18 m open tail. Five orange/cream bands, tapered cage hoops, reinforcement seams and downloaded Fabric001 maps communicate the construction. The mast stays fixed; the boom and cage swivel together about its vertical bearing. The sleeve flattens sideways when slack, hangs in calm air, and fills toward a cone under positive airflow through the mouth. Small traveling ripples are restricted to the flexible sleeve and stop with the simulation clock.

`app/render/windsock_motion.gd` advances damped yaw, droop and crossflow modes at 120 Hz. Thirteen centreline knots preserve a straight first 3/8 and seven equal-length flexible links; their summed length is invariant. Inflation uses lagged positive axial inflow, with the 15 kt reference as its full-extension anchor. Gravity droop relaxes as inflation grows; bounded vertical air-flow response scales with squared speed. Response rates, intermediate extension and flutter remain estimates.

The fixed-wing scene samples **the actual committed `FlightSession.wind_at()` vector at every 240 Hz tick**, including seeded OU turbulence. It aligns the basket on session reset. `World.update()` uploads the latest state once per frame; it never advances weather RNG or aircraft state. The existing wind NED/render conversion is explicit. Other world callers can use the same visual update with their supplied wind. A static sleeve mesh deforms in the vertex shader; it is not rebuilt each frame. The original motion delivery retained a fixed-mast-only shadow; the subsequent [VQ-04a-F2 shadow follow-up](../../visual-quality-implementation/VQ-04a/windsock/README.md) shares the moving cloth/cage geometry with the field mask.

## Verification, 2026-10-19

Native Windows Godot 4.7.2-stable, Compatibility/OpenGL 3.3, NVIDIA RTX 3090 and AMD Ryzen 9 5900X. [Capture measurements and source hashes](verification.json), [CPU batches](cost.json), [response sheet](response-sheet.png), and [gust/turn sequence](gust-and-turn.gif) retain this run's evidence.

| Check | Result |
| --- | --- |
| Dedicated windsock motion | 35 checks passed: calm sag, invariant length, four wind-to headings, gentle/full flow, low-speed swivel, vertical/tiny upgusts, reversal/deflation, finite extremes, pause/reset, 30/60/144 FPS grouping, real Main/OU wiring and read-only physical state |
| Existing windsock geometry / field-data validation | 17 / 121 checks passed |
| Wind field / turbulence / trace / HUD | 59 / 29 / 29 / 9 checks passed |
| Wind flight integration | Latest rerun: 51 checks passed, including fleet wind loads and checkpoint replay. Earlier transient Extra trim failures occurred during unrelated concurrent aircraft/trim edits; those files were not changed by this work |
| Shader clock / world presentation context | 7 / 17 checks passed |
| Projected field shadows | 58 checks passed, including fixed-mast-only windsock silhouette |
| Existing end-to-end controls | Passed keyboard axes, throttle, trim, pause/restart, recording and Timber input checks |
| Native motion captures | 140 PNG hashes checked; calm, 1.5, 7.72 and 15 m/s, reversal before/mid/after, vertical gust, and 61-frame gust/turn/calm tape; near and actual pilot-relative views |
| Production field ablation | Three views, independent exact repeat, scenery off/on; zero clipped whites and all pixel changes inside current cue bounds |
| Geometry cost | Three draws and 5,266 triangles, under the existing 6,000-triangle limit |
| CPU cost | Median batch mean 5.25 µs per 240 Hz observer call and 43.48 µs per render upload; p95 batch means 5.43 / 44.93 µs. Headless desktop component measurement, excluding the flight solver and GPU |

At the two-second capture, calm tail drop is 1.304 m, light-wind inflation is 0.194, and 7.72 m/s axial flow reaches 0.997 inflation with 0.084 m residual drop. During a reversal after 0.2 s, inflation falls to 0.776 while the bearing has turned about 43°. These are implementation outputs, not measured real-sock transients.

Run focused scripts using the pinned engine with `--headless --path app --audio-driver Dummy --script res://tests/test_windsock_motion.gd` and `test_windsock.gd`. [Ground-tool commands](../../../../tools/ground/README.md#windsock-motion-m5-w04b-r1) reproduce rendered captures and the CPU probe. The complete app suite and physical/readability gates were not run or closed by this work.

## Remaining limits

The reduced modes do not solve fabric stress, self-contact, individual panel pressure or measured material mass/stiffness. Inflation saturates near 15 kt, so this is relative wind feedback rather than an anemometer above that reference. The actual field remains spatially uniform; no pole-height shear, obstacle wake or propeller wash is invented. Moving ground shadows are covered by the follow-up above; self-shadowing remains absent. Steady wind has bounded artistic flutter; it is not a measured turbulence spectrum.

Same-time updates hold state. Rewind and gaps over 0.5 s reset the visual model rather than replaying an unavailable wind history; exact presentation replay requires the same tick sample tape from reset. Windsock lag is not serialized in flight checkpoints. Finite wind input is capped at 40 m/s for presentation stability. Native captures and headless CPU batches do not establish full-session frame-time or lower-end hardware acceptance.

## Source-backed facts

- The FAA lists [AC 150/5345-27F](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/1040591) as active, issued 2021-12-15. The [AC PDF](https://www.faa.gov/documentLibrary/media/Advisory_Circular/150-5345-27F-Wind-Cone.pdf) describes airport/heliport fabric wind-cone assemblies. The AC is advisory; its applicability section says it is generally voluntary, with specified federal grant and Passenger Facility Charge project exceptions.
- The sock is a fabric truncated cone. The FAA's two nominal sizes are 2.5 m long with a 0.45 m throat, and 3.75 m long with a 0.9 m throat. The throat framework holds the opening round in calm air and supports the first 3/8 of the sock length rigidly. The sock and its frame act together as a wind vane and rotate around a vertical shaft; the bearing/bushing must permit free movement.
- The FAA spec says to taper the cone so it becomes fully extended at 15 kt (about 7.72 m/s). At 3 kt (about 1.54 m/s) or above, the assembly should rotate freely and indicate true wind direction within ±5°. The 3 kt value is a movement/direction criterion, not a stated inflation threshold.
- The FAA's [AIM guidance on airport visual indicators](https://www.faa.gov/air_traffic/publications/atpubs/AIM/aim0403.html) says the large end points into the wind. Its [TAF wind convention](https://www.faa.gov/air_traffic/publications/atpubs/aim_html/chap7_section_1.html) states, for example, that `18010KT` means wind blowing from 180°. Therefore a sock's throat faces the meteorological “from” direction and its tapered body trails toward the “to” direction.
- ICAO's [Annex 14, Volume I catalogue](https://store.icao.int/en/annex-14-aerodromes) lists the 9th edition (July 2022) with Amendment 18. An official [ICAO AP-ADO/TF/7 working paper](https://www.icao.int/sites/default/files/APAC/Meetings/2026/2026%20AP-ADO-TF-7/03-Working%20Papers/WP16-AI5-Development-of-Guidance-Material-on-the-Use-of-As-Far-As-Practicable-AFAP-Rev.1-A.pdf) reproduces Annex 14, 5.1.1.3: an aerodrome indicator should be a fabric truncated cone, at least 3.6 m long and 0.9 m across the large end, visible from 300 m, and provide a clear surface-wind direction plus a general speed indication. It prefers a single white or orange color where practical. If two colors are needed for changing backgrounds, it recommends orange/white, red/white, or black/white in five alternating bands, with darker end bands. That paper is a regional guidance proposal which reproduces the clause, not an Annex amendment.
- FAA fabric colors are natural white, yellow, or orange; its AC prohibits lettering and logos. ICAO's visibility guidance is background-dependent, rather than requiring stripes on every sock.

## Implementation implications and evidence boundary

Use the incoming horizontal air-flow direction for azimuth: the large throat faces upstream and the cloth trails downstream. Preserve the rigid circular throat and supported first 3/8 while allowing the remaining fabric to droop or extend. The 3 kt and 15 kt points are useful anchors if a visual estimate is needed between a limp sock and a fully extended one.

The cited documents do **not** give a calibrated partial-extension curve, throat/tail radius profile, material mass or stiffness, flutter amplitude, damping, or response time. Any interpolation between calm and 15 kt, body curvature, sag, gust lag, or fabric motion beyond those construction constraints is an implementation estimate. Do not describe those choices as measured or physically validated. The real-airport dimensions are reference sizes, not a compliance claim for this RC field.

## Primary sources

- FAA, [AC 150/5345-27F status page](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/1040591) and [full PDF](https://www.faa.gov/documentLibrary/media/Advisory_Circular/150-5345-27F-Wind-Cone.pdf), especially §§1.1–1.2, 3.2–3.5, and 4.2.4–4.2.6.
- FAA, [AIM §4-3-4, Visual Indicators at Airports Without an Operating Control Tower](https://www.faa.gov/air_traffic/publications/atpubs/AIM/aim0403.html).
- FAA, [AIM Chapter 7 §1, TAF wind encoding](https://www.faa.gov/air_traffic/publications/atpubs/aim_html/chap7_section_1.html).
- ICAO, [Annex 14, Volume I current catalogue entry](https://store.icao.int/en/annex-14-aerodromes); [AP-ADO/TF/7 WP/16, Attachment D](https://www.icao.int/sites/default/files/APAC/Meetings/2026/2026%20AP-ADO-TF-7/03-Working%20Papers/WP16-AI5-Development-of-Guidance-Material-on-the-Use-of-As-Far-As-Practicable-AFAP-Rev.1-A.pdf), reproduced clause 5.1.1.3.

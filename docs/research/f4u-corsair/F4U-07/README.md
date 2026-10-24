# F4U-07: provisional physics data for the 1/4.5 Corsair

Derived 2026-10-22 for the [F4U plan](../../../F4U-PLAN.md). The same day it was revised with measured section data and slotted flaps, then moved from the 1/5 DLE-111 configuration to the 1/4.5 CARF-class Corsair with a Moki S250 radial and a 30x18 three-blade, at the owner's direction. Software derivation from provisional inputs; not physical validation. In the catalog since [F4U-09](../F4U-09/README.md).

## What exists

| File | Role |
| --- | --- |
| [source.json](../../../../assets/aircraft/f4u-corsair-250/source.json) (v2) | Authored inputs with sources: D1/D4/D5 (CARF 1:4.5, 30x18 three-blade, Moki S250), two mass anchors for this kit, the CARF manual's setup, three smaller Corsair setups, the Moki operating points, NACA full-size data, measured and XFOIL section data, slotted-flap digitization |
| [geometry-r59.json](../../../../assets/aircraft/f4u-corsair-250/geometry-r59.json) | 1/4.5 geometry measured on R59 ([F4U-06](../F4U-06/README.md)) |
| [ground_effect_vlm.py](../../../../research/f4u-corsair/F4U-07/ground_effect_vlm.py) → `vlm_ground_effect.json` | Image-method VLM of the measured gull planform; Trefftz-plane drag |
| [fit_propeller.py](../../../../research/f4u-corsair/F4U-07/fit_propeller.py) → `prop_calibration.json` | Blade-element model (P51-06 `bem.py`) fitted to the Mejzlik 32x18 2-blade ([mejzlik_32x18.json](../../../../research/f4u-corsair/F4U-07/mejzlik_32x18.json)) and the P-51's 26x12 2- and 3-blade tables |
| [derive_physics.py](../../../../research/f4u-corsair/F4U-07/derive_physics.py) → `f4u_corsair_250.json`, [derivation.md](../../../../research/f4u-corsair/F4U-07/derivation.md) | Native `openrc-aircraft v2` output, written to `app/data/aircraft/` |
| [probe.gd](../../../../research/f4u-corsair/F4U-07/probe.gd) | Production loader, trims, flare authority, top speed and flight modes |

Sources for every input are in [F4U-01](../F4U-01/README.md). The method follows the P-51 generator, with Corsair-specific geometry, data and checks:

| Item | Method |
| --- | --- |
| Wing | Measured inverted-gull planform. Dihedral enters through a strip integral carried by `aero.surfaces.wing_body_cl_beta`. VLM tail downwash and ground effect for that planform. |
| Sections | NACA TR 586 measured 23012 cl_max(Re) and lift slope. XFOIL supplies only the thickness trend. |
| Throws, flaps, thrust angles | The CARF manual for this kit, on this airframe's widest surface chords. Low rate and expo from three smaller Corsair manuals. |
| CG | Mean of three Corsair manuals' CG fractions; CARF gives its CG only relative to an unstated spar station and serves as a cross-check. |
| Engine and propeller | Moki S250 torque level from the Moki manual's two static points (32x18 2-blade at 4,300 rpm, 30x18 3-blade at 4,400 rpm), estimated four-stroke shape, ignition cut at 6,000 rpm. No 30x18 three-blade table exists: the calibrated blade-element model supplies it. |
| Slotted flaps | Fitted to Roskam's digitized single-slotted data and checked against NACA TR 664. |
| Retraction paths | From R59's own gear rig. |

## Results (provisional)

| Quantity | Value | Basis |
| --- | --- | --- |
| Flight mass | 21.5 kg (dry 21.1 kg) | Mean of the CARF specification (18–21 kg dry, plus half the tank) and Model Airplane News' 24.0 kg Moki-powered review aircraft |
| CG, neutral point, static margin | 25.7 % MAC, 36.9 % MAC, 11.2 % | CG from three manuals; CARF's spar rule gives 27.5 % MAC if its spar sits at 30 % chord (21.9–30.8 % for 25–33 %). Neutral point calibrated as before |
| CL_max, 1-g stall, start speed | 1.16, 14.4 m/s, 23 m/s | TR 586 section data at the larger chord's Reynolds numbers |
| Throws | Normal rate aileron 10.8°, elevator 8.9°, rudder 17.2°; high rate 13.5°, 11.2°, 25.9° | Normal = the CARF manual's recommended set (20/15 mm aileron mean, 20 mm elevator, 70 mm rudder); high = normal ÷ the median low/high ratio of three Corsair manuals; the elevator stays inside CARF's 35 mm take-off allowance (corrected 2026-10-23, see below) |
| Flaps | 0° take-off, 30° landing; slotted fit gain 0.839, limit 22.9°, stall shift 0.10 | CARF: no take-off flap, at most 30° on approach (35° useful, 45° mechanical) |
| Thrust angles | 2.5° right, 0.5° up | CARF manual |
| Wing incidence, stabilizer | +2° wing, 1.25° stabilizer, both to the thrust line | Wing: F4U-1 pilot's handbook AN 01-45HA-1, Appendix I p. 64 (corrected 2026-10-23, see below). Stabilizer: NACA RM A7C05 (F4U-4), reference line assumed |
| Flap speed advisory | 28.2 m/s EAS (HUD only) | AN 01-45HA-1 Section I p. 14: flaps-down restricted speed 130 kt at 50° to 200 kt at 20°, so 177 kt at the model's 30°, mapped at equal CL at the handbook's lightest charted weight (10,000 lb) |
| Engine, propeller | Peak torque 13.97 N·m (bmep 7.0 bar); installed 8.06 kW at the 6,000 rpm limit (72 % of 15 hp); static 4,274 rpm, 28.0 kgf, T/W 1.30 | The two Moki points give 13.09 and 14.86 N·m; the three-blade's static rpm lands 3 % under the manual's 4,400 |
| Roll response | pb/2V 0.062 at the CARF normal throw, 0.078 at the high rate | Full-size 0.064 (NACA RM A7C05) |
| Top speed | 53.5 m/s (193 km/h) | Full-throttle level trim. CARF: "never noticeably exceed 200 km/h" |

### Flight modes (physics/flight_modes.gd on the simulated equations)

| Speed | Short period | Phugoid | Roll τ | Dutch roll | Spiral |
| --- | --- | --- | --- | --- | --- |
| 18.7 m/s (1.3 Vs) | 0.85 Hz, ζ 0.87 | 0.100 Hz, ζ 0.14 | 0.117 s | 0.45 Hz, ζ 0.19 | +0.0011 1/s (doubles in 632 s) |
| 23 m/s | 1.00 Hz, ζ 0.88 | 0.081 Hz, ζ 0.22 | 0.093 s | 0.48 Hz, ζ 0.18 | stable |
| 30 m/s | 1.29 Hz, ζ 0.89 | 0.064 Hz, ζ 0.36 | 0.071 s | 0.58 Hz, ζ 0.17 | stable |
| 38 m/s | 1.63 Hz, ζ 0.88 | 0.054 Hz, ζ 0.57 | 0.056 s | 0.70 Hz, ζ 0.17 | stable |

All meet MIL-F-8785C Level 1 bounds used as a reference frame (damping ratios direct, times Froude-scaled by √(1/4.5)).

## Verification (2026-10-23, Windows, Godot 4.7.2)

`probe.gd`: 22 checks, 0 failed. The production `AircraftData.load_file` accepts the file and keeps identity, span (2.778 m) and inventory mass. Level trims run from 2.1° of up elevator at 18.7 m/s through neutral near 27 m/s to 1.3° down at 38 m/s; power-off flares at 1.15 and 1.10 Vs need 3.5° and 4.0° of the 11.2° throw (with the R59 incidence: 4.5° up to 1.0° up, and 6.0° and 6.5°). `fit_propeller.py --check`, `ground_effect_vlm.py --check` and `derive_physics.py --check` pass.

## Cross-checks of the engine and propeller

| Check | Model | Reference |
| --- | --- | --- |
| Static rpm, 30x18 three-blade | 4,274 | Moki manual: 4,400 |
| Static thrust of a Moki S300 on a SEP 34x18 at 3,950 rpm (Mejzlik 32x18 Ct) | 28.9 kgf | 29.92 kgf, forum measurement |
| Torque per litre, Moki S300 at that point (Mejzlik 32x18 Cp) vs the S250 anchor | 12.4 N·m when scaled to 250 cc | 13.1 N·m |
| Propeller calibration | rms 4.4 % (32x18 2B), 4.8 % (26x12 2B), 8.1 % (26x12 3B) | Mejzlik tables, J ≤ 0.76 |

Single forum reports span 4,200–5,200 rpm on 32x18 two-blades. The Mejzlik 31x12 and 30x13 three-blade tables (low-pitch twin-engine blades) miss one shared calibration by 12–19 % and are not fitted.

## Method corrections found while deriving

- **Trefftz-plane drag.** The P-51 VLM's midpoint drag read is valid only for a straight quarter-chord line; on this planform it gave e = 1.31. See [LEARNINGS](../../../LEARNINGS.md).
- **XFOIL at model Reynolds numbers.** Against NACA TR 586, XFOIL (Ncrit 9) over-predicts the 23012's cl_max by about 16 % and its lift slope by about 20 % at Re 0.5–1 million.
- **Calibration transfer.** The P-51's body-yaw factor (3.6 × DATCOM) does not transfer: on the Corsair it would invert the measured directional stability.
- **Propeller tables.** A calibrated blade-element model over-predicts low-pitch three-blades by 17–37 % in the cruise band; a manufacturer table governs where one exists. The 30x18 three-blade has none, so its tables carry the calibration's uncertainty.
- **Rated power.** The Moki S250's 15 hp needs about 8.9 bar of bmep at 6,000 rpm; the manual's own static points imply 7.0 bar, so the installed peak is 72 % of the rating.
- **Throw mapping.** The first 1/4.5 derivation put CARF's single recommended set into `max_throw`, so the default normal rate flew 80 % of the manual's throws. The contract's `max_throw` is the full surface travel and `rates.normal` the default fraction; CARF's set is now the normal rate. The standard flight-test card exposed it (F4U-12).
- **Wing incidence.** The R59 visual master models the wing at 0.5° to the thrust line (chord-weighted), so with RM A7C05's 1.25° stabilizer the tail sat at a higher incidence than the wing. The F4U-1 pilot's handbook gives +2° (AN 01-45HA-1, Appendix I p. 64, read from the page image, 2026-10-23). With it, CL0 rises from 0.111 to 0.200 and Cm0 from −0.026 to −0.008. Cruise trims near neutral elevator instead of 2.9° up, the flare needs about 2.5° less up elevator, and top speed falls from 57.7 to 53.5 m/s, under CARF's 200 km/h note. R59's station-to-station twist stays in the strip offsets.
- **Loader item limit.** One inventory item may weigh at most 5 kg; the 5.4 kg engine is split into its core and its mount and collector ring.

## Limits

Geometry is the R59 visual master. The wing incidence is the full-size handbook's; the CARF kit publishes none, and its scale-moulded fuselage is assumed to keep it. The stabilizer setting is the F4U-4's (RM A7C05) against an assumed reference line, and the gull angles lack a primary source. TR 586 values were checked against the page images on 2026-10-23 ([recheck](tr586-recheck-2026-10-23/README.md): two Reynolds numbers corrected, CL_max 1.155667 → 1.155345). The thin outer sections (9–11 %) clamp at the 12 % trend, so tip stall may come earlier than modelled. The body yaw term is DATCOM's, uncalibrated. The Moki torque shape and peak-power rpm are estimated; Mejzlik tables and the calibrated model stand in for the wooden Menz and SEP propellers. Gear travel follows the GP-06c reserve-drop rule ([F4U-08](../F4U-08/README.md)). The CARF manual's handling notes are checked in [F4U-12](../F4U-12/README.md#ground-handling): the tail-up landing is consistent, the full-power nose-over is not reproduced. Flight-identified behavior requires F4U-14 evidence.

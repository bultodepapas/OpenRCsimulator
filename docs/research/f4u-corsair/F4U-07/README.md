# F4U-07: provisional physics data for the 1/4.5 Corsair

Derived 2026-10-22 for the [F4U plan](../../../F4U-PLAN.md). The same day it was revised with measured section data and slotted flaps, then moved from the 1/5 DLE-111 configuration to the 1/4.5 CARF-class Corsair with a Moki S250 radial and a 30x18 three-blade, at the owner's direction. Software derivation from provisional inputs; not physical validation and not yet in the catalog.

## What exists

| File | Role |
| --- | --- |
| [source.json](../../../../assets/aircraft/f4u-corsair-250/source.json) (v2) | Authored inputs with sources: D1/D4/D5 (CARF 1:4.5, 30x18 three-blade, Moki S250), two mass anchors for this kit, the CARF manual's setup, three smaller Corsair setups, the Moki operating points, NACA full-size data, measured and XFOIL section data, slotted-flap digitization |
| [geometry-r59.json](../../../../assets/aircraft/f4u-corsair-250/geometry-r59.json) | 1/4.5 geometry measured on R59 ([F4U-06](../F4U-06/README.md)) |
| [ground_effect_vlm.py](../../../../research/f4u-corsair/F4U-07/ground_effect_vlm.py) → `vlm_ground_effect.json` | Image-method VLM of the measured gull planform; Trefftz-plane drag |
| [fit_propeller.py](../../../../research/f4u-corsair/F4U-07/fit_propeller.py) → `prop_calibration.json` | Blade-element model (P51-06 `bem.py`) fitted to the Mejzlik 32x18 2-blade ([mejzlik_32x18.json](../../../../research/f4u-corsair/F4U-07/mejzlik_32x18.json)) and the P-51's 26x12 2- and 3-blade tables |
| [derive_physics.py](../../../../research/f4u-corsair/F4U-07/derive_physics.py) → `f4u_corsair_250.json`, [derivation.md](../../../../research/f4u-corsair/F4U-07/derivation.md) | Native `openrc-aircraft v2` output, staged beside the script until F4U-09 |
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
| Throws, high rate | Aileron 10.8°, elevator 8.9°, rudder 17.2° | CARF: 20/15 mm aileron (mean), 20 mm elevator, 70 mm rudder |
| Flaps | 0° take-off, 30° landing; slotted fit gain 0.839, limit 22.9°, stall shift 0.10 | CARF: no take-off flap, at most 30° on approach (35° useful, 45° mechanical) |
| Thrust angles | 2.5° right, 0.5° up | CARF manual |
| Engine, propeller | Peak torque 13.97 N·m (bmep 7.0 bar); installed 8.06 kW at the 6,000 rpm limit (72 % of 15 hp); static 4,274 rpm, 28.0 kgf, T/W 1.30 | The two Moki points give 13.09 and 14.86 N·m; the three-blade's static rpm lands 3 % under the manual's 4,400 |
| Roll response | pb/2V 0.062 at the CARF throw | Full-size 0.064 (NACA RM A7C05) |
| Top speed | 57.7 m/s (208 km/h) | Full-throttle level trim. CARF: "never noticeably exceed 200 km/h" |

### Flight modes (physics/flight_modes.gd on the simulated equations)

| Speed | Short period | Phugoid | Roll τ | Dutch roll | Spiral |
| --- | --- | --- | --- | --- | --- |
| 18.7 m/s (1.3 Vs) | 0.86 Hz, ζ 0.86 | 0.098 Hz, ζ 0.15 | 0.123 s | 0.47 Hz, ζ 0.20 | +0.015 1/s (doubles in 46 s) |
| 23 m/s | 1.01 Hz, ζ 0.88 | 0.078 Hz, ζ 0.23 | 0.094 s | 0.50 Hz, ζ 0.19 | stable |
| 30 m/s | 1.29 Hz, ζ 0.89 | 0.061 Hz, ζ 0.40 | 0.071 s | 0.59 Hz, ζ 0.19 | stable |
| 38 m/s | 1.63 Hz, ζ 0.89 | 0.049 Hz, ζ 0.63 | 0.056 s | 0.72 Hz, ζ 0.18 | stable |

All meet MIL-F-8785C Level 1 bounds used as a reference frame (damping ratios direct, times Froude-scaled by √(1/4.5)).

## Verification (2026-10-22, Windows, Godot 4.7.2)

`probe.gd`: 22 checks, 0 failed. The production `AircraftData.load_file` accepts the file and keeps identity, span (2.778 m) and inventory mass. Level trims from 18.7 to 38 m/s use 4.5° to 1.0° of up elevator; power-off flares at 1.15 and 1.10 Vs need 6.0° and 6.5° of the 8.9° throw. `fit_propeller.py --check`, `ground_effect_vlm.py --check` and `derive_physics.py --check` pass.

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
- **Loader item limit.** One inventory item may weigh at most 5 kg; the 5.4 kg engine is split into its core and its mount and collector ring.

## Limits

Geometry is the R59 visual master; wing incidence, stabilizer setting and gull angles lack a primary source. TR 586 values are read from a degraded OCR layer. The thin outer sections (9–11 %) clamp at the 12 % trend, so tip stall may come earlier than modelled. The body yaw term is DATCOM's, uncalibrated. The Moki torque shape and peak-power rpm are estimated; Mejzlik tables and the calibrated model stand in for the wooden Menz and SEP propellers. Gear travel is borrowed from the P-51. The CARF manual's handling notes (full power on take-off lifts the tail beyond the low-rate elevator, tail-up landings) are F4U-08/12 targets. Flight-identified behavior requires F4U-12 traces and F4U-14 evidence.

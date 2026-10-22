# F4U-07: provisional physics data for the 1/5 Corsair

Derived 2026-10-22 for the [F4U plan](../../../F4U-PLAN.md); revised the same day with measured section data, three Corsair setups, an engine anchor and slotted flaps. Software derivation from provisional inputs; not physical validation and not yet in the catalog.

## What exists

| File | Role |
| --- | --- |
| [source.json](../../../../assets/aircraft/f4u-corsair-250/source.json) (v2) | Authored inputs with sources: provisional D1/D4/D5 defaults (FokkeRC 1/5, three-blade, DLE-111), four mass anchors, three Corsair setups, the DLE-111 anchor, NACA full-size data, measured and XFOIL section data, slotted-flap digitization |
| [geometry-r59.json](../../../../assets/aircraft/f4u-corsair-250/geometry-r59.json) | 1/5 geometry measured on R59 ([F4U-06](../F4U-06/README.md)) |
| [ground_effect_vlm.py](../../../../research/f4u-corsair/F4U-07/ground_effect_vlm.py) → `vlm_ground_effect.json` | Image-method VLM of the measured gull planform; Trefftz-plane drag |
| [derive_physics.py](../../../../research/f4u-corsair/F4U-07/derive_physics.py) → `f4u_corsair_250.json`, [derivation.md](../../../../research/f4u-corsair/F4U-07/derivation.md) | Native `openrc-aircraft v2` output, staged beside the script until F4U-09 |
| [probe.gd](../../../../research/f4u-corsair/F4U-07/probe.gd) | Production loader, trims, flare authority, top speed and flight modes |

Sources for every input are in [F4U-01](../F4U-01/README.md). The method follows the P-51 generator, with Corsair-specific geometry, data and checks:

| Item | Method |
| --- | --- |
| Wing | Measured inverted-gull planform. Dihedral enters through a strip integral carried by `aero.surfaces.wing_body_cl_beta`. VLM tail downwash and ground effect for that planform. |
| Sections | NACA TR 586 measured 23012 cl_max(Re) and lift slope. XFOIL supplies only the thickness trend. |
| Throws, flap settings, CG | Three Corsair manuals: medians for throws and flaps, the mean for the CG. |
| Engine and propeller | DLE-111 power anchored on a reported static rpm with a Mejzlik 27x10. The Mejzlik 26x12 3-blade manufacturer table is used directly, with the BEM only beyond its range. |
| Slotted flaps | Fitted to Roskam's digitized single-slotted data and checked against NACA TR 664. |
| Retraction paths | From R59's own gear rig. |

## Results (provisional)

| Quantity | Value | Basis |
| --- | --- | --- |
| Flight mass | 16.0 kg | Mean of three gasoline Corsairs at constant wing loading (11.8–18.8 kg) |
| CG, neutral point, static margin | 25.7 % MAC, 36.9 % MAC, 11.2 % | CG from three manuals; neutral point calibrated to NACA 30 % (stick-free, power on) + XP-51 power shift + stick-free allowance |
| CL_max, 1-g stall, start speed | 1.14, 13.9 m/s, 22 m/s | TR 586 section data; XFOIL alone gave 1.32 |
| Throws, high rate | Aileron 14.5°, elevator 10.5°, rudder 13.5° | Medians of three manuals on this airframe's widest chords |
| Flaps | 17.4° take-off, 24.8° landing; slotted fit gain 0.839, limit 22.9° (rms 0.21°), stall shift 0.10 | Roskam Fig. 8.17 / 8.31–8.34; method within 8 % of TR 664 |
| Engine, propeller | Installed peak 7.67 kW (92 % of 11.2 hp); 5,917 rpm static; 26.8 kgf; T/W 1.68 | Mejzlik 27x10 at 6,800 rpm (spread 5.7–7.6 kW); the distributor's independent 25.5 kgf claim agrees within 5 % |
| Top speed | 53.5 m/s (193 km/h) | Full-throttle level trim; inside the 40–65 m/s band for 1/5 warbirds |

### Flight modes (physics/flight_modes.gd on the simulated equations)

| Speed | Short period | Phugoid | Roll τ | Dutch roll | Spiral |
| --- | --- | --- | --- | --- | --- |
| 18.1 m/s (1.3 Vs) | 0.89 Hz, ζ 0.83 | 0.115 Hz, ζ 0.15 | 0.114 s | 0.47 Hz, ζ 0.20 | +0.004 1/s (doubles in 169 s) |
| 22 m/s | 1.04 Hz, ζ 0.84 | 0.097 Hz, ζ 0.22 | 0.088 s | 0.52 Hz, ζ 0.19 | stable |
| 30 m/s | 1.39 Hz, ζ 0.85 | 0.077 Hz, ζ 0.39 | 0.064 s | 0.67 Hz, ζ 0.17 | stable |
| 38 m/s | 1.76 Hz, ζ 0.85 | 0.066 Hz, ζ 0.58 | 0.050 s | 0.82 Hz, ζ 0.17 | stable |

All meet MIL-F-8785C Level 1 bounds used as a reference frame (damping ratios direct, times Froude-scaled by √(1/5)). They agree qualitatively with RM A7C05: short period satisfactorily damped, lateral oscillation damped at low altitude.

## Verification (2026-10-22, Windows, Godot 4.7.2)

`probe.gd`: 22 checks, 0 failed. The production `AircraftData.load_file` accepts the file and keeps identity, span and inventory mass. Level trims from 18 to 38 m/s use 5.2° to 1.3° of up elevator; power-off flares at 1.15 and 1.10 Vs need 6.0° and 6.5° of the 10.5° throw (below about 1.08 Vs the steady solve leaves the stall blend, not an authority limit). Top speed, modes and damping as above. `derive_physics.py --check` and `ground_effect_vlm.py --check` pass.

## Method corrections found while deriving

- **Trefftz-plane drag.** The P-51 VLM's midpoint drag read is valid only for a straight quarter-chord line; on this planform it gave e = 1.31. See [LEARNINGS](../../../LEARNINGS.md).
- **XFOIL at model Reynolds numbers.** Against NACA TR 586, XFOIL (Ncrit 9) over-predicts the 23012's cl_max by about 16 % and its lift slope by about 20 % at Re 0.5–1 million. The first derivation's −0.10 correction was too small.
- **Calibration transfer.** The P-51's body-yaw factor (3.6 × DATCOM) does not transfer: its DATCOM baseline used an estimated side area, and on the Corsair it would invert the measured directional stability.
- **Propeller tables.** The P-51-calibrated BEM over-predicts the 3-blade's thrust by 17–37 % at J 0.59–0.67, the cruise and top-speed band, so the manufacturer table now governs where it exists.
- **Neutral point.** Raymer's fuselage term alone leaves it near 46 % MAC; the calibrated term (0.026/deg) sits in the P-51's family (0.033).

## Limits

Geometry is the R59 visual master; wing incidence, stabilizer setting and gull angles lack a primary source. TR 586 values are read from a degraded OCR layer. The thin outer sections (9–11 %) clamp at the 12 % trend, so tip stall may come earlier than modelled; the full-size left roll-off in the power-on stall is not modelled. The body yaw term is DATCOM's, uncalibrated. Engine level rests on forum reports (±14 % in power) and a simulated Mejzlik table; gear travel is borrowed from the P-51. Owner decisions D1/D4/D5 can change mass, power and propeller. Flight-identified behavior requires F4U-12 traces and F4U-14 evidence.

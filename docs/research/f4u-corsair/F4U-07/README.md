# F4U-07: provisional physics data for the 1/5 Corsair

Derived 2026-10-22 for the [F4U plan](../../../F4U-PLAN.md). Software derivation from provisional inputs; not physical validation and not yet in the catalog.

## What exists

| File | Role |
| --- | --- |
| [source.json](../../../../assets/aircraft/f4u-corsair-1-5/source.json) | Authored inputs: provisional D1/D4/D5 defaults (FokkeRC 1/5, three-blade, DLE-111), kit and reference-setup values, NACA full-size data, XFOIL 230-series section reductions |
| [geometry-r59.json](../../../../assets/aircraft/f4u-corsair-1-5/geometry-r59.json) | 1/5 geometry measured on R59 ([F4U-06](../F4U-06/README.md)) |
| [ground_effect_vlm.py](../../../../research/f4u-corsair/F4U-07/ground_effect_vlm.py) → `vlm_ground_effect.json` | Image-method VLM of the measured gull planform; Trefftz-plane drag (below) |
| [derive_physics.py](../../../../research/f4u-corsair/F4U-07/derive_physics.py) → `f4u_corsair_1_5.json`, [derivation.md](../../../../research/f4u-corsair/F4U-07/derivation.md) | Native `openrc-aircraft v2` output, staged beside the script until F4U-09 |
| [probe.gd](../../../../research/f4u-corsair/F4U-07/probe.gd) | Production loader and trim probe |

The method follows the P-51 generator. The Corsair differs in four places: the measured inverted-gull planform and its strip-integrated dihedral (carried by `aero.surfaces.wing_body_cl_beta`), NACA 230-series sections from XFOIL with stated corrections, the VLM's tail downwash and ground effect for that planform, and retraction paths taken from R59's own gear rig.

## Results (provisional)

| Quantity | Value | Basis |
| --- | --- | --- |
| Flight mass | 18.5 kg | Target inside the 16–21 kg inference ([F4U-01](../F4U-01/README.md)) |
| CG | 27.7 % MAC | Phoenix 1.8 m Corsair manual (110 mm), scaled ×1.389 |
| Neutral point, static margin | 36.9 % MAC, 9.2 % | Calibrated hypothesis: NACA 30 % (stick-free, power on) + 3.4 % power shift (XP-51) + 3.5 % stick-free allowance |
| CL_max, 1-g stall, start speed | 1.32, 13.9 m/s, 22 m/s | Schrenk on the measured chord; XFOIL clmax − 0.10 |
| Throws, high rate | Aileron 14.5°, elevator 10.5°, rudder 15.2°; flaps 13.1° / 22.3° | Phoenix mm at each surface's widest chord: lower bounds |
| Static rpm, thrust, T/W | 5,421 rpm, 22.9 kgf, 1.24 | DLE-111 rating × the P-51 installed ratio 0.807; Mejzlik 26×12 3-blade BEM. Distributor claim 25.5 kgf |
| Ground effect at the wheels | Induced drag ×0.64 at x 0.157 | VLM fit rms 0.004 (induced), 0.011 (tail) |

## Verification (2026-10-22, Windows, Godot 4.7.2)

`probe.gd`: 9 checks, 0 failed. The production `AircraftData.load_file` accepts the file, including the wheel-profile step, and keeps identity, span and mass. Level trim from 18 to 38 m/s uses 5.0° to 1.1° of up elevator; the power-off glide at 1.4 Vs is −5.2° (L/D ≈ 10.9). Power-off flare trims at 1.15 and 1.10 Vs need 5.4° and 5.9° of the 10.5° throw; below about 1.08 Vs the steady solve stops converging in the 4° stall blend, which is not an authority limit. `derive_physics.py --check` and `ground_effect_vlm.py --check` pass.

## Method corrections found while deriving

- **Trefftz-plane drag.** The P-51 VLM reads trailing-leg induced velocity at the bound-vortex midpoints, valid only for a straight, unswept quarter-chord line. On this planform it gave e = 1.31 even with the wing flattened. Reading the legs 100 spans downstream and halving gives e = 1.013 flat and 1.021 for the gull; the same change gives 1.013 against the P-51's 1.017. See [LEARNINGS](../../../LEARNINGS.md).
- **Neutral point.** Raymer's fuselage term alone left the neutral point at 43.8 % MAC (16 % static margin), stiffer than the full-size data allows. The P-51 needed a calibrated term several times Raymer's; this derivation calibrates to an F4U target instead of borrowing the P-51's value, which would leave the wider-cowled Corsair unstable.
- **UTF-8 reads.** Generators that rely on `open()` defaults fail on Windows (cp1252) for the Stik data file. The F4U generator reads every JSON as UTF-8.

## Limits

Geometry is the R59 visual master; wing incidence, stabilizer setting and gull angles lack a primary source. Sections are XFOIL predictions with estimated corrections. The fuselage yaw term is DATCOM's, uncalibrated. Engine level, flap effectiveness (plain-flap K' for a slotted flap) and gear travel are borrowed or estimated. The fin has no offset; 1.5° right thrust stands in for the full-size 2° left fin offset. Owner decisions D1/D4/D5 can change mass, power and propeller. Flight-identified behavior requires F4U-12 traces and F4U-14 evidence.

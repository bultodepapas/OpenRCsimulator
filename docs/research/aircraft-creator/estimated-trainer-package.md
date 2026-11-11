# Estimated trainer package: derivation and checks

**Dated research record, 2026-11-10.** Steps AC-05 (packages) and AC-06 (definition, compiler, accepted candidate) of the [Aircraft Creator plan](../../plans/aircraft-creator.md).

## Scope and evidence limits

- Airframe package `conventional-trainer-estimated-v1` and power package `electric-4s-800kv-apc12x6-estimated-v1`, both labelled `experimental`.
- First slice only: wing and aft tail, aileron/elevator/rudder, single tractor electric motor, finite battery (`ocv_resistance`), no landing gear, `terminal_hull`, no flaps.
- Every number is a software estimate. Nothing is calibrated against a real aircraft, a wind tunnel or a flight log. The checks below show that the compiled record is accepted by the unchanged flight loader, is internally consistent and flies stably in the unchanged `FlightSession`; they do not show that it flies like the player's airplane.
- The numerical domain is qualified only by the runs listed under [Measured results](#measured-results-template-aircraft): one aircraft (the template), calm air, one manoeuvre. The domain bounds are development limits, not a calibration claim.
- The compiler adds no vehicle branch and no physics law and changes no physics source file. The in-memory file boundary is `app/workshop/creator/record_loader.gd`, built on the loader's public functions; the compiler test proves it returns the same result as `AircraftData.load_file` for a bundled record. (A first draft split `load_file` inside `aircraft_data.gd`; it was withdrawn the same day because that file's bytes are pinned by solver-identity and legacy gates.)

## Where things live

| Part | Path |
| --- | --- |
| Authoring record, validation, template, mass proposal | `app/workshop/creator/definition.gd` |
| Package loader and closed forms | `app/workshop/creator/packages.gd` |
| Package data (every number with unit, kind, source) | `app/data/creator/*.json` |
| Compiler, live read-out, domain admission | `app/workshop/creator/compiler.gd` |
| Trusted owner | `app/workshop/creator/accepted_candidate.gd` |
| Checks | `app/tests/test_creator_compiler.gd`, `app/tests/test_creator_flight.gd` |

Donor of the borrowed data: `app/data/aircraft/synthetic_stik_electric_4s_battery.json` (rectangular AR 5 Stik, OpenFlightSim UltraStick25e coefficient set, UIUC APC Sport 11x6 propeller tables, synthetic electric data). It was read in full; no existing aircraft file was changed.

## How the runtime uses the set

Read from `app/physics/aero.gd` and the loader (`aircraft_data.gd`):

- Attached flow uses the coefficient set ("oracle"): forces and moments act at the aero reference point (ARP) and are transferred to the CG.
- Outside it the loads blend to a local law: six wing strips whose lift acts at the ARP's x, plus a horizontal and a vertical tail surface at their own `position`. The loader solves the strip section slope so that strips plus tail reproduce `CLa` and `CL0`.
- The tail's lift is `lift_slope·(α + incidence)`; `control_effectiveness` multiplies the elevator angle; with `downwash_gradient` the loader derives the free tail law (`free_slope = lift_slope/(1 − dε/dα)`), which pitch rate and elevator see.
- `wing_section_cm_ac` is a pure couple on every strip; `body_cy_beta` and `wing_body_cl_beta` add the fuselage side force and the wing-body dihedral effect to the local law, and the loader then requires `CYb` and `Clb` to equal fin + declared body term.
- The loader enforces `CYdr`, `Cndr`, `Cldr`, `Cnb` against the fin within 1e-8.

The package therefore puts the ARP on the wing's aerodynamic centre and derives every pitch and fin coefficient from one tail, so both regimes describe the same airplane.

## Formulas

Reference: S = b·(c_root + c_tip)/2, c = S/b, AR = b²/S, λ = c_tip/c_root, MAC = ⅔·c_root·(1 + λ + λ²)/(1 + λ). Package assumption: straight taper with an unswept quarter-chord line and a flat wing in the plane z = 0, so the ARP is `[0.25·c_root, 0, 0]`. Tail pressure centres: quarter chord of the horizontal tail at the centreline; quarter chord at mid height of the fin. Arms l_h, l_v are measured from the ARP.

| Quantity | Formula | Source |
| --- | --- | --- |
| Wing slope a_w | Helmbold: 2π·AR/(2 + √(AR² + 4)) | Helmbold (1942); donor source strings |
| Downwash dε/dα | 0.844 × 2·a_w/(π·AR) | Far-wake lifting-line value, factor anchored on the donor's vortex-lattice 0.457 at AR 5 (`docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md` T2) |
| Tail free slope a_h,free | 0.9·Helmbold(AR_h) | Donor: "Helmbold tail of AR 3.27 with η 0.9" |
| Tail effective slope a_h (`lift_slope`) | a_h,free·(1 − dε/dα) | Loader's free tail law |
| Fin slope a_v | 0.9·Helmbold(2·h²/S_v) | Reflection-plane assumption; gives 2.34/rad for the donor fin against its provisional 2.4/rad |
| CLa | a_w + a_h·S_h/S | Loader relation (`_induced_map`) |
| Cma | −a_h·(S_h/S)·(l_h/c) | Tail moment about the wing AC; fuselage and propeller neglected |
| Tail `incidence` | −dε/dα·CL0_wing/(a_w·(1 − dε/dα)) | Tail parallel to the wing chord; only the wing's zero-alpha downwash acts (loader then derives free incidence 0) |
| CL0 | CL0_wing + (S_h/S)·a_h·incidence | Consistency with the loader's strip offset |
| Cm0 | cm_ac·MAC/c + Cma·incidence | Strip couple (D11j) plus tail |
| CLq, Cmq | 2·a_h,free·(S_h/S)·(l_h/c), −2·a_h,free·(S_h/S)·(l_h/c)² | Donor closed forms (D11g) |
| CLde, Cmde | a_h,free·τ_e·S_h/S, −CLde·l_h/c | Flap effectiveness τ_e = 0.55 |
| `control_effectiveness` (horizontal) | τ_e/(1 − dε/dα) = Cmde/Cma | Donor rule |
| CYdr, Cndr, Cldr, Cnb | a_v·S_v/S·τ_r, −CYdr·l_v/b, CYdr·z_v/b, a_v·(S_v/S)·(l_v/b) | Loader-enforced fin relations, τ_r = 0.55 |
| CYb, Clb | −a_v·S_v/S + body side force, −a_v·(S_v/S)·z_v/b + wing-body term | Loader relations with the declared body terms |
| Cnr | −2·(l_v/b)·Cnb − CD0/3 | Donor closed form (D11f) |
| Clp | donor Clp × Helmbold(AR)/Helmbold(5) × (1 + 3λ)/(2·(1 + λ)) | Roll damping scales with the wing slope; strip-theory planform factor for straight taper |
| k_induced | 1/(π·e·AR), e = 0.7812 | Donor k at AR 5 |
| CD90 | 1.11 + 0.018·AR | Viterna (NASA CR-1983), as the donor |
| `wing_aileron_effectiveness` | \|Clda_right\|/(0.125·CLa) | Donor rule |
| CLadot (reference only) | CLq·dε/dα | The runtime carries the lag as a state |
| Neutral point, static margin | x_np = x_ARP − (Cma/CLa)·c; (x_np − x_cg)/c | |
| `start.level_speed` | √(2·m·g/(ρ·S·0.44)), ρ 1.225 kg/m³, g 9.80665 m/s² | Lift coefficient of the donor at its 15 m/s start |
| Stall speed (read-out) | same with CL_max 1.1 | |

Donor known answers reproduced by the same functions (test): CLq 3.13, Cmq −7.40, Cnr −0.1324, tail free slope 3.17, downwash 0.457.

## Borrowed values and why they apply

- From the donor's UltraStick25e set, unchanged: CL0 (as the wing's zero-alpha lift), Cm0 (as the wing section moment), CD0, CL_minD, CLda_each, CDda_each, CDdr, CDde, CYp, CYr, Clr, Clda_right/left, Cmda_each, Cnp, Cnda_right/left, and Clp as the reference of the scaling rule. They describe a stick-type sport model with a rectangular AR 5 wing and strip ailerons; the definition carries no aileron, hinge-line, dihedral or airfoil data, so the domain keeps the wing near that shape.
- Body terms: donor CYb and Clb minus the donor's own fin terms (−0.2388 and −0.0537 per rad), declared as `body_cy_beta` and `wing_body_cl_beta`. They are not rescaled with the player's fuselage.
- Envelope and tail surface constants (CL_max 1.1, CL_min −0.8, blend width 6°, sideslip blend 15–25°, attached limit 8°, tail limits 12°/24°, tail CD0, k, CD90): donor values, themselves estimates.
- Power package: motor, battery, ESC law, propeller diameter, rotor inertia and Ct/Cp tables are the donor's (a synthetic estimated fixture; the tables are measured UIUC APC Sport 11x6 data applied to a 12x6). Hardware masses and sizes (motor 0.20 kg, propeller with adapter 0.066 kg, ESC 0.065 kg, battery 0.35 kg) are catalogue-range estimates, not a product.
- Airframe mass proposal: areal densities from the donor inventory (wing 1.12 kg/m², tail 1.08 kg/m², fuselage shell 0.89 kg/m² × 0.8 for taper), four 45 g servos, 25 g receiver, 70 g hardware. Always `estimated`; a measured or manual item is never replaced.

## Package domain (development bounds)

A definition outside a bound is refused with `DOMAIN_REFUSED` at the named field.

| Bound | Range | Reason |
| --- | --- | --- |
| Wing span | 0.9–2.2 m | Chord Reynolds numbers of the borrowed drag and stall data |
| Aspect ratio | 4–7 | Borrowed roll/yaw/aileron data and the single downwash calibration point are for AR 5 |
| Taper ratio | 0.6–1 | Borrowed aileron and roll data are for a rectangular wing |
| Mass | 1–4 kg | Around the donor (2.9 kg) and the UltraStick25e (2.0 kg) |
| Wing loading | 3–8 kg/m² | Donor 6.2; keeps the level speed between 10 and 17 m/s |
| Horizontal tail aspect ratio | 2.5–6 | Helmbold tail with η 0.9 (donor 3.3) |
| Fin height/chord | 0.7–2.5 | Reflection-plane fin slope (donor 1.0) |
| Horizontal tail volume | 0.35–0.8 | Donor 0.49 |
| Vertical tail volume | 0.025–0.08 | Donor 0.051; fuselage yaw neglected |
| Static margin | 8–30 % of c | The neglected fuselage and propeller terms move the real neutral point forward by a few percent; 8 % keeps a positive real margin |
| Static thrust/weight | 0.5–2 | Hand launch needs a thrust surplus; above 2 the model lacks propeller wash on the tail |
| Hub ahead of fuselage nose | 0–0.12 m, inside the nose section | Tractor installation sanity |

The loader accepted the template geometry rescaled to AR 3.5–8 and taper 0.5–1 (stall blend start ≥ 9.1°, section slope 5.7–6.2/rad); the narrower bounds above come from the borrowed data, not from loader limits (scratch probe, not committed).

## Deviations from the first proposal, and why

1. **Tail incidence and Cm0.** Not `incidence = Cm0/Cma`: the section moment is declared as `wing_section_cm_ac` and the tail incidence is the wing's zero-alpha downwash on a tail parallel to the wing chord. With both, the oracle and the local law agree (see results); the folded form would have double-counted.
2. **CYb and Clb** are fin + a declared body term, not the donor's totals, so the player's fin changes them and both regimes agree.
3. **Downwash** uses a 0.844 factor on 2·a_w/(π·AR) so the donor geometry reproduces the project's vortex-lattice value.
4. **Rate derivative arms** are taken from the ARP, not the CG, so no aerodynamic coefficient depends on the mass distribution (moving the battery changes only balance and thrust-line offset).
5. **Inventory `name` is the stable ID.** Display text is not part of the physical bytes; renaming an item keeps the record hash.
6. **Too many inventory items** is `FIELD_INVALID` at `inventory` (252 player items + 4 package items = the 256 limit).
7. **JSON numbers.** The engine's JSON number parser is not correctly rounded: a value read back from the record bytes can differ from the written one by about 1e-13 relative. The bytes stay the identity and the loader's values are the ones that fly; the candidate summary reports mass, CG and inertia as the loader derived them.

## Measured results (template aircraft)

Template (`Definition.template()`): span 1.5 m, chord 0.30 m, S 0.45 m², AR 5; mass 1.975 kg; CG x 0.0935 m (31 % chord); neutral point 0.1278 m (43 %); static margin 11.4 %; wing loading 4.39 kg/m²; level speed 12.64 m/s; stall speed 7.99 m/s; tail volumes 0.471 and 0.043; static thrust 27.3 N, thrust/weight 1.41; inertia Jxx 0.113, Jyy 0.225, Jzz 0.334, Jxz −0.0095 kg·m². CLa 4.62, Cma −0.813, Cmq −6.67, CLq 3.00, Cmde −0.824, Cnb 0.108, Cnr −0.111, CYb −0.483, Clb −0.075 (per rad). No loader warning.

Commands (Windows, repository root; engine `.tools/Godot_v4.8-beta2_win64_console.exe`), 2026-11-10:

```sh
python tools/godot/run_checked.py --label creator-compiler --timeout 300 -- <engine> --headless --path app --audio-driver Dummy --script res://tests/test_creator_compiler.gd
python tools/godot/run_checked.py --label creator-flight --timeout 300 -- <engine> --headless --path app --audio-driver Dummy --script res://tests/test_creator_flight.gd
python tools/godot/run_checked.py --label aircraft-data --timeout 300 -- <engine> --headless --path app --audio-driver Dummy --script res://tests/test_aircraft_data.gd
```

| Check | Result |
| --- | --- |
| `test_creator_compiler.gd` | 155 checks, 0 failed |
| `test_creator_flight.gd` | 45 checks, 0 failed (16 s wall) |
| `test_aircraft_data.gd` (loader source unchanged) | 88 checks, 0 failed |
| Oracle against local law, attached flow (α −3…6°, elevator and rudder 0.05 rad) | Largest coefficient difference: lift 0.00026, pitch 0.00097, yaw 0.00003 |
| Trim at 12.638 m/s, 30 m, calm | α 4.43°, throttle 0.371, 4322 rpm, elevator 0.151 of travel (up), roll 0.022, yaw 0.031 |
| Hands off, 20 s | Airspeed 12.638–12.650 m/s, altitude 29.870–30.000 m, bank ≤ 0.39°, pitch 4.34–4.43°; 68 C drawn from the battery |
| Stick +0.3 for 0.25 s | Roll: p +0.565 rad/s; pitch: q +0.522; yaw: r +0.241; negative sticks mirror them |
| Hand launch (default field, calm, full throttle, hands off 4 s) | Commits; lowest 1.83 m (release 1.90 m), slowest 6.55 m/s, 30.8 m high after 4 s; no crash. Bank reaches 90° within 4 s: nothing counters the propeller torque at full throttle, the pilot must |
| Step refinement, 4 s pitch/roll/yaw pulse manoeuvre | 240 vs 480 Hz: position 5.7 mm, attitude 0.011°, airspeed 0.002 m/s. 480 vs 960 Hz: 2.9 mm, 0.0055°, 0.001 m/s (first order: sticks are sampled per tick) |

Refinement uses the existing way to change the tick (`Engine.physics_ticks_per_second` before the session reset, as `test_aircraft_ground_dynamics.gd` does); no new solver path.

## Open items

- No comparison with a real aircraft or a second estimator (vortex lattice, flight log) for any player geometry.
- Fuselage and propeller contributions to Cma and Cnb are neglected; the static-margin floor only covers them by assumption.
- The definition has no dihedral, airfoil, aileron or hinge-line input; the borrowed roll and control data cannot follow the player's wing. The local strip law gives about two thirds of the oracle's aileron roll moment with the donor's rule (as on the donor).
- The crash hull is built from the stated dimensions (flat outlines, box fuselage), not from the imported 3D model.
- Hands-off full-throttle hand launch rolls to 90° of bank in 4 s (thrust/weight 1.41 with the one power package); not checked with a pilot or wind.
- Stall, spin, sideslip beyond the blend, wind and turbulence were not exercised. Only the template flew; other in-domain geometries were compiled and loaded, not flown.
- The GDScript language-server warning scan (`tools/debug/gdscript_warnings.py`) was not run on the new files.
- Battery, motor and propeller data are the donor's synthetic values; no measured power system.

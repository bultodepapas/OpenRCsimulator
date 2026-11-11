# Estimated trainer package: derivation and checks

**Dated research record, 2026-11-10; extended 2026-11-11** with the wing-dihedral input, the dynamic modes and the explanation of the behaviour after a large upset (AC-12). Steps AC-05 (packages), AC-06 (definition, compiler, accepted candidate) and AC-12 (handling review) of the [Aircraft Creator plan](../../plans/aircraft-creator.md). The step-refinement campaign has [its own record](AC-12-numerical-campaign.md).

## Scope and evidence limits

- Airframe package `conventional-trainer-estimated-v1` and power package `electric-4s-800kv-apc12x6-estimated-v1`, both labelled `experimental`.
- First slice only: wing and aft tail, aileron/elevator/rudder, single tractor electric motor, finite battery (`ocv_resistance`), no landing gear, `terminal_hull`, no flaps.
- Every number is a software estimate. Nothing is calibrated against a real aircraft, a wind tunnel or a flight log. The checks below show that the compiled record is accepted by the unchanged flight loader, is internally consistent and flies stably in the unchanged `FlightSession`; they do not show that it flies like the player's airplane.
- The numerical domain is qualified only by the runs listed under [Measured results](#measured-results-template-aircraft) and in the [AC-12 campaign](AC-12-numerical-campaign.md): calm air, open-loop manoeuvres of a few seconds. The domain bounds are development limits, not a calibration claim.
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
| Handling probe and step-refinement campaign (research) | `research/aircraft-creator/ac12/` |

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

Reference: S = b·(c_root + c_tip)/2, c = S/b, AR = b²/S, λ = c_tip/c_root, MAC = ⅔·c_root·(1 + λ + λ²)/(1 + λ). Package assumption: straight taper with an unswept quarter-chord line; the ARP stays at the wing root, `[0.25·c_root, 0, 0]`, and the rise of a dihedral wing's panels above it is neglected. Tail pressure centres: quarter chord of the horizontal tail at the centreline; quarter chord at mid height of the fin. Arms l_h, l_v are measured from the ARP.

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
| Wing-body term (`wing_body_cl_beta`) | donor term + κ·[D(player wing, Γ) − D(donor wing, 2.86°)], D = −a_w·Γ·(1 + 2λ)/(6·(1 + λ)) | [Wing dihedral](#wing-dihedral-2026-11-11) |
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

- From the donor's UltraStick25e set, unchanged: CL0 (as the wing's zero-alpha lift), Cm0 (as the wing section moment), CD0, CL_minD, CLda_each, CDda_each, CDdr, CDde, CYp, CYr, Clr, Clda_right/left, Cmda_each, Cnp, Cnda_right/left, and Clp as the reference of the scaling rule. They describe a stick-type sport model with a rectangular AR 5 wing and strip ailerons; the definition carries no aileron, hinge-line or airfoil data, so the domain keeps the wing near that shape.
- Body terms: donor CYb and Clb minus the donor's own fin terms (−0.2388 and −0.0537 per rad). The first is declared as `body_cy_beta`. The second is the donor's wing-body term at its own 2.86° of dihedral; since 2026-11-11 the player's dihedral moves it (next section). Neither is rescaled with the player's fuselage.
- Envelope and tail surface constants (CL_max 1.1, CL_min −0.8, blend width 6°, sideslip blend 15–25°, attached limit 8°, tail limits 12°/24°, tail CD0, k, CD90): donor values, themselves estimates.
- Power package: motor, battery, ESC law, propeller diameter, rotor inertia and Ct/Cp tables are the donor's (a synthetic estimated fixture; the tables are measured UIUC APC Sport 11x6 data applied to a 12x6). Hardware masses and sizes (motor 0.20 kg, propeller with adapter 0.066 kg, ESC 0.065 kg, battery 0.35 kg) are catalogue-range estimates, not a product.
- Airframe mass proposal: areal densities from the donor inventory (wing 1.12 kg/m², tail 1.08 kg/m², fuselage shell 0.89 kg/m² × 0.8 for taper), four 45 g servos, 25 g receiver, 70 g hardware. Always `estimated`; a measured or manual item is never replaced.

## Wing dihedral (2026-11-11)

The definition gained one required field, `wing.dihedral_deg`: the geometric dihedral of each wing panel, measured from the root outward, in degrees. Sanity range −5…15°, package domain 0…8°, template 5° (a typical aileron trainer has 3–6° per panel; the value was chosen before any mode was computed). It carries evidence (`manual`, `measured`, `estimated`) like the other player fields. The flight record has no field for the angle: it acts through the derived `wing_body_cl_beta` and `Clb`, whose sources name the angle and who supplied it. The crash hull's wing tips rise by (b/2)·tan Γ.

**Relation.** In sideslip β a panel with dihedral Γ sees its angle of attack change by ±β·Γ. Integrating the lift change over the span (strip theory, the textbook derivation: Etkin and Reid, *Dynamics of Flight*; Cook, *Flight Dynamics Principles*, wing with dihedral) gives for straight taper λ

```text
D(Γ) = −a_w · Γ · (1 + 2λ) / (6 · (1 + λ))        (−a_w·Γ/4 for a rectangular wing)
```

with a_w the wing's lift slope. Strip theory ignores the induced flow of an antisymmetric loading and overstates the effect. Lifting-line theory for an elliptic wing shows that the same loading mode carries both roll damping and the dihedral effect, with the slope a₀·AR/(AR + 4) instead of the symmetric a₀·AR/(AR + 2): the strip value keeps the share (AR + 2)/(AR + 4), 0.78 at AR 5. The package uses one factor κ = 0.7192 on D, anchored like the downwash factor on this repository's own number for the donor wing: −0.01335 per rad of sideslip per degree of dihedral, from the runtime's induced map ([D10-R5](../flight-dynamics/stik-roll-sideslip-2026-10-19/README.md), section 3), against the strip value 0.018561.

**The borrowed term already contained dihedral.** D10-R5 decomposes the donor's wing-body term −0.0537 into −0.0382 for the Stik's 2.86° of dihedral and −0.0155 of high-wing interference. The package therefore does not add the player's dihedral on top of the borrowed value. It moves the borrowed value by the difference of the relation:

```text
wing_body_cl_beta = −0.0537 + κ · [ D(player wing, Γ) − D(donor wing, 2.86°) ]
```

A player wing equal to the donor's (AR 5, rectangular, 2.86°) reproduces the previous record exactly; a flat wing keeps −0.0155. The interference share is not rescaled with the player's fuselage or wing height.

| Template wing | 0° | 2.86° (package before this input) | 5° (template) | 8° |
| --- | --- | --- | --- | --- |
| `wing_body_cl_beta` | −0.0155 | −0.0537 | −0.0823 | −0.1223 |
| `Clb` (fin −0.0212 + wing-body) | −0.0367 | −0.0749 | −0.1035 | −0.1435 |

**Both regimes.** The loader requires `Clb` = fin term + `wing_body_cl_beta`, and the local strip law adds the same number as the rolling couple ½ρ·S·b·Clβ_WB·u·v, fading over the declared sideslip blend. Measured roll due to sideslip about the CG, oracle against local law, template wing: flat −0.0431 / −0.0427, 5° −0.1099 / −0.1094 at α 0–4°; the local law alone keeps −0.107 at α 12° and −0.105 at 16°. The couple is a consistency closure, constant in α: it is not a post-stall model.

**Neglected under the same strip model**, all with their size at the 8° bound for the template wing (κ·a_w = 3.06 per rad):

| Derivative | Dihedral term | Size | Why neglected |
| --- | --- | --- | --- |
| CYb | −κ·a_w·Γ² | −0.023 at 5°, −0.060 at 8° (5 % and 12 % of −0.483) | Below the uncertainty of the borrowed body side force, which is not rescaled |
| Cnb | two opposing terms of order 0.1·Γ·CL | below 0.005, under 5 % of the fin's 0.108 | Small against the neglected fuselage term |
| CYp | 3·Γ·Clp | −0.12 at 5°, −0.19 at 8°, larger than the borrowed −0.0375 | Side force due to roll rate is a minor term: at a roll helix angle of 0.05 it is 2 % of the lift |
| Clr, Cnp | none at first order for an unswept wing | — | — |
| Clp, CLa | factor cos²Γ | at most −2 % | Inside the estimate's uncertainty |

The plain strip value (κ = 1) would be 39 % larger and lifting-line theory's elliptic share 8 % larger than the calibrated factor: ±1° of dihedral moves `Clb` by 0.013, so the angle the player states matters more than the choice between them.

## Package domain (development bounds)

A definition outside a bound is refused with `DOMAIN_REFUSED` at the named field.

| Bound | Range | Reason |
| --- | --- | --- |
| Wing span | 0.9–2.2 m | Chord Reynolds numbers of the borrowed drag and stall data |
| Aspect ratio | 4–7 | Borrowed roll/yaw/aileron data and the single downwash calibration point are for AR 5 |
| Taper ratio | 0.6–1 | Borrowed aileron and roll data are for a rectangular wing |
| Wing dihedral | 0–8° | Small-angle strip relation calibrated at 2.86°; terms of order Γ² neglected; no anhedral or polyhedral |
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

Template (`Definition.template()`): span 1.5 m, chord 0.30 m, S 0.45 m², AR 5, dihedral 5°; mass 1.975 kg; CG x 0.0935 m (31 % chord); neutral point 0.1278 m (43 %); static margin 11.4 %; wing loading 4.39 kg/m²; level speed 12.64 m/s; stall speed 7.99 m/s; tail volumes 0.471 and 0.043; static thrust 27.3 N, thrust/weight 1.41; inertia Jxx 0.113, Jyy 0.225, Jzz 0.334, Jxz −0.0095 kg·m². CLa 4.62, Cma −0.813, Cmq −6.67, CLq 3.00, Cmde −0.824, Cnb 0.108, Cnr −0.111, CYb −0.483, Clb −0.1035 (per rad; −0.0749 before the dihedral input). No loader warning.

Commands (Windows, repository root; engine `.tools/Godot_v4.8-beta2_win64_console.exe`), re-run 2026-11-11 with the dihedral input:

```sh
python tools/godot/run_checked.py --label creator-compiler --timeout 300 -- <engine> --headless --path app --audio-driver Dummy --script res://tests/test_creator_compiler.gd
python tools/godot/run_checked.py --label creator-flight --timeout 300 -- <engine> --headless --path app --audio-driver Dummy --script res://tests/test_creator_flight.gd
```

| Check | Result |
| --- | --- |
| `test_creator_compiler.gd` | 196 checks, 0 failed (155 on 2026-11-10; 41 dihedral checks added) |
| `test_creator_flight.gd` | 56 checks, 0 failed (45 on 2026-11-10; spiral check added) |
| `test_aircraft_data.gd` (loader source unchanged) | 88 checks, 0 failed (2026-11-10; not re-run, no loader byte changed) |
| Oracle against local law, attached flow (α −3…6°, elevator and rudder 0.05 rad) | Largest coefficient difference: lift 0.00026, pitch 0.00097, yaw 0.00003; roll due to sideslip 0.0007 |
| Trim at 12.638 m/s, 30 m, calm | α 4.43°, throttle 0.371, 4321 rpm, elevator 0.151 of travel (up), roll 0.020, yaw 0.029 |
| Hands off, 20 s | Airspeed 12.638–12.646 m/s, altitude 29.880–30.000 m, bank ≤ 0.25°, pitch 4.36–4.43°; 68 C drawn from the battery |
| Stick +0.3 for 0.25 s | Roll: p +0.548 rad/s; pitch: q +0.522; yaw: r +0.245; negative sticks mirror them |
| Hand launch (default field, calm, full throttle, hands off 4 s) | Commits; lowest 1.83 m (release 1.90 m), slowest 6.55 m/s, 32.3 m high after 4 s; no crash. Explained under [Behaviour after a large upset](#behaviour-after-a-large-upset-ac-12-2026-11-11) |
| Small roll upset (stick 0.2 for 0.4 s), then hands off 8 s | Bank 7.5° → 28.6° with a flat wing, 6.9° → 12.1° at 5°, 6.6° → 5.4° at 8° |
| Step refinement, 4 s pitch/roll/yaw pulse manoeuvre | 240 vs 480 Hz: position 5.4 mm, attitude 0.011°, airspeed 0.002 m/s. 480 vs 960 Hz: 2.7 mm, 0.0057°, 0.001 m/s (first order: servos and the downwash lag advance once per tick). Domain-wide: [AC-12 campaign](AC-12-numerical-campaign.md) |

Refinement uses the existing way to change the tick (`Engine.physics_ticks_per_second` before the session reset, as `test_aircraft_ground_dynamics.gd` does); no new solver path.

## Dynamic modes at trim (2026-11-11)

`research/aircraft-creator/ac12/handling.gd` linearizes the real equations at each case's level trim with the existing `physics/flight_modes.gd` (central-difference Jacobian of `physics/linearize.gd`, controls and shaft speed frozen, downwash lag as the ninth state). The table gives the eigenvalues of the **full 9-state matrix**, solved with NumPy (`eigenvalues.py`). `flight_modes.gd` itself reports 4×4 block projections that drop the propeller's longitudinal–lateral coupling: they agree within 2 % on the oscillatory modes and the roll time constant, but put the spiral root lower (template +0.034 instead of +0.061 1/s; 1.0 m span +0.026 instead of +0.199). Every corner carries the template's 5° of dihedral unless stated.

| Case | Level speed | Short period | Phugoid | Roll τ | Dutch roll | Spiral root | Spiral time |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Template, dihedral 5° | 12.64 m/s | 1.57 Hz, ζ 0.95 | 0.116 Hz, ζ 0.28 | 0.065 s | 0.69 Hz, ζ 0.27 | +0.061 1/s | doubles in 11.5 s |
| Template, dihedral 0° | 12.64 | 1.57, 0.95 | 0.116, 0.28 | 0.064 | 0.72, 0.25 | +0.186 | doubles in 3.7 s |
| Template, dihedral 2.86° (package as reviewed) | 12.64 | 1.57, 0.95 | 0.116, 0.28 | 0.065 | 0.70, 0.26 | +0.117 | doubles in 5.9 s |
| Template, dihedral 8° | 12.64 | 1.57, 0.95 | 0.117, 0.29 | 0.066 | 0.67, 0.28 | −0.025 | halves in 28 s |
| Static margin 0.29 (2.37 kg) | 13.84 | 1.84, 0.67 | 0.133, 0.21 | 0.060 | 0.78, 0.25 | +0.071 | doubles in 9.8 s |
| Static margin 0.085 | 12.64 | 2.04, 0.97 | 0.108, 0.33 | 0.065 | 0.69, 0.28 | +0.063 | doubles in 11.0 s |
| Aspect ratio 4 | 12.80 | 1.49, 0.93 | 0.120, 0.27 | 0.072 | 0.73, 0.27 | +0.061 | doubles in 11.4 s |
| Aspect ratio 7 | 12.64 | 1.69, 0.96 | 0.110, 0.30 | 0.057 | 0.63, 0.28 | +0.062 | doubles in 11.3 s |
| Span 1.0 m (1.41 kg, thrust/weight 1.98) | 16.01 | 1.60, 0.62 | 0.133, 0.47 | 0.061 | 0.96, 0.33 | +0.199 | doubles in 3.5 s |
| Span 2.0 m (3.15 kg, thrust/weight 0.88) | 11.97 | 1.92, 0.89 | 0.108, 0.25 | 0.064 | 0.59, 0.30 | +0.042 | doubles in 16.5 s |

- The longitudinal modes and the Dutch roll are well damped in every corner, and the roll subsidence is fast. A short period with ζ near 1 is two real roots that merge with the downwash-lag root (−6 to −33 1/s); the pairing changes with the lag length, so its frequency is not monotonic in the static margin.
- The spiral mode is the weak one. Dihedral moves it as textbook theory says: the simple criterion Clβ·Cnr − Cnβ·Clr is −0.0077, −0.0035, −0.0003 and +0.0041 at 0°, 2.86°, 5° and 8°. With the template's 5° it is about neutral (doubling in 11.5 s), as on many aileron sport models. It turns stable between 5° and 8°.
- The 1.0 m span corner is spirally worse than its coefficients say (+0.199 against a neutral criterion): the propeller of the one power package is large for that airframe and couples the axes. The projections miss this.

## Behaviour after a large upset (AC-12, 2026-11-11)

The independent review of 2026-11-11 measured two things it could not explain. Both were reproduced on the package as reviewed (dihedral 2.86°) and on the present one, for the template and six corners, in 10 s and 13 s flights at 240 Hz. Each flight was repeated with the propeller's reaction torque cancelled and the roll and yaw trims (which only balance it) at zero, and again with the rotor's gyroscopic momentum cancelled as well. The runtime has no such switch and gains none: the probe wraps the session's stage evaluator in the research script and leaves thrust and shaft dynamics alone.

**(a) Hand launch at full throttle, hands off.** Bank is the wing's angle against the horizon. Euler roll is larger at the steep pitch angles of these flights; it passed 90° in every case, as the review reported.

| Case | Shaft torque ÷ full-aileron roll moment at release (6.5 m/s) | Bank after 1 s | Largest bank in 10 s: as flown / no torque / no torque, no gyro |
| --- | --- | --- | --- |
| Template, 5° | 55 % | 17° left | 71° / 47° / 0° |
| Template, 2.86° (as reviewed) | 55 % | 17° left | 72° / 40° / 0° |
| Template, 0° and 8° | 55 % | 18° and 16° left | 73° and 71° / 30° and 55° / 0° |
| Aspect ratio 4 (span 1.34 m) | 62 % | 22° left | 83° / 47° / 0° |
| Aspect ratio 7 (span 1.78 m) | 47 % | 12° left | 59° / 50° / 0° |
| Span 2.0 m | 23 % | 6° left | 89° / 87° / 4° |
| Span 1.0 m | 187 % | 53° left | 88° / 66° / 9° |

- With both propeller effects cancelled the airplane does not bank. It flies a loop: level-flight elevator trim, 1.4 times its weight in thrust, speed rising from 6.5 to 20 m/s. The pitch excursion is a pure consequence of full power on level trim.
- The first bank is the **reaction torque**: 0.556 N·m at release, half of what full aileron can give at 6.5 m/s on a 1.5 m wing and nearly twice as much on a 1.0 m wing. Its steady roll rate against roll damping alone is 35°/s (178°/s at 1.0 m).
- With the torque cancelled the bank grows the other way and more slowly: **gyroscopic precession** of the rotor during the pitch-up yaws the nose right.
- The **spiral mode** then holds or grows whatever bank exists. Dihedral changes this part only: bank after 3 s is 43°, 37°, 32° and 24° at 0°, 2.86°, 5° and 8°.

**(b) One-second full-aft pull from level trim, then hands off for 12 s.**

| Case | Largest α | As flown: height, airspeed, bank after 13 s | No torque, no gyro: height, bank |
| --- | --- | --- | --- |
| Template, 5° | 21° | −69 m, 19.9 m/s, 43° | +0.4 m, 1° |
| Template, 2.86° (as reviewed) | 21° | −65 m, 20.2 m/s, 44° | +0.3 m, 4° |
| Template, 0° / 8° | 21° | −62 m, 44° / −73 m, 41° | −1.6 m, 19° / +0.4 m, 0° |
| Static margin 0.29 | 10° | −1.7 m, 14.9 m/s, 11° | −0.8 m, 0° |
| Static margin 0.085 | 22° | −52 m, 19.3 m/s, 41° | −12 m, 20° |
| Aspect ratio 4 / 7 | 21° | −85 m, 49° / −68 m, 36° | +0.1 m, 2° / +0.2 m, 7° |
| Span 1.0 m | 21° | −191 m, 28.1 m/s, 76° | +0.8 m, 8° |
| Span 2.0 m | 20° | −51 m, 17.2 m/s, 29° | −1.7 m, 4° |

- The pull **stalls the wing** (α 21° against a blend that starts near 9°) wherever the elevator can do it. At static margin 0.29 it cannot (α 10°), and that airplane is back within 2 m with 11° of bank.
- Without the propeller's asymmetry the stalled airplane recovers by itself: the **phugoid** (period 8.6 s, ζ 0.28) brings it back within 2 m and 1 m/s in 12 s. The longitudinal dynamics are not the problem.
- With it, the stalled wing **drops**: 50–100° of bank within 2 s. The stalled strips are roll-unstable (the local law's documented post-stall roll instability, D8b-R2d), so any asymmetry grows; with a flat wing or the aft balance even what is left after both cancellations (rounding, as far as this probe can tell) reaches 20° in these runs.
- The airplane then sits in a **spiral dive** at 30–50° of bank and 17–20 m/s, sinking about 5 m/s. Two things keep it there: the spiral mode is near neutral, and the roll and yaw trims that balance the propeller at 12.6 m/s are out of balance at 20 m/s. Even the stable spiral root of 8° dihedral (−0.025 1/s) would remove only a quarter of a bank in 12 s.

**Which of this is physically expected, and which is the estimate.**

- Expected in kind for such an airplane: a torque roll on a full-throttle hand launch of a model whose static thrust is 1.4–2 times its weight; a loop when full power meets level trim; a wing drop when full up elevator stalls it with power on; no hands-off recovery from a spiral dive within 12 s when the spiral mode is near neutral. A pilot counters all four. None is a solver artefact: the bank vanishes when the propeller's two asymmetric terms are removed, and the step-refinement campaign bounds the integration error separately.
- Set by the one power package, not by the airframe estimate: thrust/weight 1.41 on the template and 1.98 at 1.0 m span is aerobatic-class power on a trainer. At 1.0 m span the torque at the standard release exceeds full aileron authority.
- A limit of the estimate that makes the model worse than a real airplane is likely to be: **Clr is a constant**, borrowed at the level-flight lift coefficient, while for a real wing it falls with CL (about CL/4). In the 20 m/s dive the real spiral mode would be more stable. Putting the dive's value (0.045 instead of 0.1086) into the in-memory model, as a sensitivity and not a package change, ends the template's pull at −43 m, 16.7 m/s and 30° instead of −69 m, 19.9 m/s and 43°.
- Limits whose direction is unknown: the size of the wing drop depends on the strip law past the stall and on borrowed stall data (CL_max 1.1); the wing-body couple stays constant in α although a real wing's dihedral effect changes past the stall; the model has no propeller wash on the tail or fin.
- Not covered: wind, a pilot in the loop, any comparison with a real airplane. These are attributions inside an estimated model, not a handling validation.

## Open items

- No comparison with a real aircraft or a second estimator (vortex lattice, flight log) for any player geometry.
- Fuselage and propeller contributions to Cma and Cnb are neglected; the static-margin floor only covers them by assumption.
- The definition has no airfoil, aileron or hinge-line input; the borrowed roll and control data cannot follow the player's wing. The local strip law gives about two thirds of the oracle's aileron roll moment with the donor's rule (as on the donor).
- Dihedral: one calibration point (the donor's wing); the wing-fuselage interference share (−0.0155) is not rescaled with the player's fuselage or wing height, although the definition states both; CYb, Cnb and CYp terms of order Γ and Γ² are neglected; no anhedral, polyhedral or tip dihedral.
- Clr and Cnp are constants borrowed at the level-flight lift coefficient. The spiral mode is therefore right only near the level speed (see the upset section). Making them follow the lift needs a runtime law, not package data.
- The crash hull is built from the stated dimensions (wing outline with raised tips, flat tail outlines, box fuselage), not from the imported 3D model.
- Hand launch: the standard release is at full throttle. With the one power package the propeller torque is 23–62 % of the full-aileron roll moment at release for 1.3–2.0 m spans and 187 % at 1.0 m. A launch throttle or a torque/authority bound belongs to AC-09; not checked with a pilot or wind.
- The 4×4 mode projections of `flight_modes.gd` understate the spiral root of these candidates; the full matrix needs an external eigenvalue solver.
- Stall, spin, sideslip beyond the blend, wind and turbulence were not exercised beyond the two upset cases. Corners other than the template flew only in the research probe and the AC-12 campaign, not in a pilot's hands.
- The GDScript language-server warning scan (`tools/debug/gdscript_warnings.py`) was not run on the new files.
- Battery, motor and propeller data are the donor's synthetic values; no measured power system.

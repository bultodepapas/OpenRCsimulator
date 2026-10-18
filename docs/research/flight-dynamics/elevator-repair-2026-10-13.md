# Elevator flight dynamics: root-cause investigation and repair plan

2026-10-13 · Revision 2 · **Status: diagnosis complete; roadmap steps 1–4 (D11i, E0a2c, D8a-R2, D11j) implemented and verified by software checks, see §11; steps 5–8 open.** Owner: main physics ([ROADMAP](../../ROADMAP.md)). Evidence and reproducible harness: [research/flight-dynamics/elevator-repair/](../../research/flight-dynamics/elevator-repair/README.md). This file was created at the path the investigation request named; the repository keeps active plans at `docs/<NAME>-PLAN.md`, so the owner may relocate it.

## 1. Executive diagnosis

Reported: the Ventage Jet pitches "as if thrust-vectored", the Ugly Stik rolls or corkscrews on elevator, the P-51 pitches inconsistently, the Extra is better but unproven.

Every symptom was reproduced through the production session loop (servos, engine, RK4 at 240 Hz, calm air) with elevator steps of ±25, 50 and 100 % stick at each aircraft's start speed (1.6 × its 1-g stall speed) and at 1.4 × that speed. The evidence supports four findings, in decreasing order of certainty:

| # | Finding | Class | Aircraft | Confidence |
| --- | --- | --- | --- | --- |
| F1 | The three generated aircraft (Extra, P-51, Ventage Jet) encode the tail's downwash inside static "effective" tail parameters. The nonlinear local tail then uses them as physical values: pitch damping in the local regime is half the oracle's, lift due to pitch rate a quarter, there is no α̇ term in either regime, and the elevator's inflated effectiveness pushes the tail into its flat-plate "stall" from ~50 % stick, cutting full-stick nose-up authority by 35–45 %. The loader already implements the correct representation (E0a2 free-tail law, Ugly Stik only); the generators do not emit the one field that enables it. | Confirmed shared defect (data pipeline + model coupling) | Extra, P-51, Ventage Jet | High |
| F2 | Every elevator-induced roll or corkscrew is the local strip model's post-stall autorotation. The attached oracle with the same stall never rolls (roll-rate maxima fall from 100–600 °/s to below 40 °/s in the counterfactual). It triggers whenever α crosses the static stall start, which the elevator reaches with 25–50 % stick at 1.6 Vs because the simulator applies the manuals' high rates with no dual rates or expo and the keyboard commands full throw. | Confirmed mechanism; severity unvalidated (D8b-R2) | All four | High for the mechanism; the physical severity is open |
| F3 | The P-51's local regime omits the wing section's camber pitching moment (ΔCm ≈ +0.031, about 1.4° of elevator), so the regime switch itself is a trim step; combined with a static margin of 5 % that shrinks to 2.5 % at α 10° and a 7–10 N·m·s propeller angular momentum, its pitch response starts slowly, then overshoots, then yaws. | Confirmed aircraft-specific gap + data uncertainty | P-51 | High for the gap, medium for its weight in the feel |
| F4 | The Ventage Jet's elevator demands 2.3° of α per degree of deflection with a 30° throw while its estimated wing stalls at 10.3° (CL_max 0.85 ± 0.10, 4° blend): statically, 9 % of the stick reaches the stall; dynamically a quarter stick reaches 21° α in 0.56 s and nz only 2.3 g, so the body rotates (66 °/s) three times faster than the flight path turns (25 °/s). That is the "thrust-vectoring" feel. | Data/estimation deficiency amplified by F1 and F2 | Ventage Jet (and, less, Extra) | High for the numbers, medium for the realism judgement |

Rejected after inspection and measurement: sign or axis errors in the input→surface→coefficient→moment chain; rigid-body integration (240 vs 480 Hz identical to display precision); hidden torque injection, artificial damping or rotation limits (none exist); thrust-line, P-factor and gyroscopic moments (small and physical except the P-51's, which are physical and large); servo and keyboard rate limits; inertia products; ground effect and wind (off in the tests).

The repair is small and layered: emit the free-tail field from the three generators (restores regime consistency, measured), add the wing camber moment to the strips (P-51), add dual rates and expo as an input feature (not physics), then continue the post-stall lateral work (D8b-R2) and the per-aircraft data items with measurements. No part of the flight model needs replacing.

## 2. Current physics architecture: elevator input to aircraft motion

| Stage | Where | What happens |
| --- | --- | --- |
| Raw input | [keyboard.gd](../../app/input/keyboard.gd), [rc_input.gd](../../app/input/rc_input.gd) | Keyboard: Down arrow = pitch +1 (stick back). Radio: raw axis, unshaped ("radios already apply expo and rates"); gamepads get expo 0.3. |
| Command shaping | [commands.gd](../../app/input/commands.gd) `step_commands`, [spec.gd](../../app/spec.gd) | Rate limit 4 units/s: a keyboard press reaches full stick in 0.25 s. Trims are added and clamped in `FlightSession.flown_commands`. |
| Servo | [flight_session.gd](../../app/sim/flight_session.gd) `_pre_step` | Each servo slews toward its command at `controls.servo_rate` (full throw in 0.11–0.18 s), once per tick, held through the RK stages. |
| Surface angle | `Commands.surface_deflections_deg` | `elevator_deg = pitch × throw_deg.elevator` (+ = trailing edge up). Throws are the manuals' high rates: Ugly 20° (estimated), Extra 23.9°, P-51 15°, Ventage Jet 30°. |
| Convention | [aero.gd](../../app/physics/aero.gd) `deflections_from_surfaces` | `δe = −deg_to_rad(elevator_deg)`: data convention + trailing edge down. The only sign crossing; verified consistent with `Cmde < 0` (stick back → nose up) and independently by [AV-16](../research/avanti-realism/AV-16/pitch-sweep.md). |
| Regime weight | `Aero.local_flow_weight` | 0 = attached empirical oracle, 1 = local strip/tail model; smoothstep from `attached_limit` 8° to the wing's stall start (12–13°) on any strip's geometric angle, or from 8° to `tail_local_limit` 12° on the tail's effective angle, which includes `control_effectiveness × δe`. |
| Oracle | `Aero._global_loads` | `Cm = Cm0 + Cmα α + Cmδe δe + …`, rate term `¼ρ V c Cmq q`, about the ARP then transferred to the CG; stall blend to flat plate beyond `envelope.a1`. With a `downwash_gradient` (Ugly only) the lagged wing CL adds the Cmα̇ term. CLadot in the data is never read. |
| Local model | `Aero._local_loads` | Six equal-area wing strips with the D11d induced-flow map, plus one horizontal and one vertical surface: flow = v + ω × r, lift ⊥ flow, drag ∥ flow, moment = r × F. Tail angle = atan2(w_t, u_t) [− k_ε CL_wing] + τ δe + incidence; linear to `tail_local_limit`, flat-plate from `tail_stall_end`. |
| Loads | [dynamics.gd](../../app/physics/dynamics.gd) | aero + propulsion ([propulsion.gd](../../app/physics/propulsion.gd): thrust on the thrust line, reaction torque, P-factor/normal force tables; [turbine.gd](../../app/physics/turbine.gd): gross thrust at the nozzle, ram drag at the intakes) + slipstream (P-51) + ground. |
| Rigid body | [rigid_body.gd](../../app/physics/rigid_body.gd) | ω̇ = J⁻¹(M − ω × (Jω + h_rotor)); quaternion kinematics; body FRD, NED position. |
| Integration | [simulation.gd](../../app/sim/simulation.gd), [integrator.gd](../../app/physics/integrator.gd) | RK4 at `physics_ticks_per_second` = 240 (`max_physics_steps_per_frame` 12), inputs and aux held through the stages. Godot's rigid bodies are not used for flight. |

Data entering this chain for the three generated aircraft is written by `research/<aircraft>/…/derive_physics.py` and must be regenerated, never hand-edited.

## 3. Reproduction evidence

Conditions: production working tree of 2026-10-12 (ground-effect work uncommitted; it adds nothing at 300 m), each aircraft trimmed level at its start speed V₀ and at 1.4 V₀, 300 m, calm air, reference atmosphere. Pitch command stepped at t = 0.5 s and released at 2.0 s (servo slew included, keyboard ramp not), 5 s total, 1200 ticks. Full tables: [steps-comparison.md](../../research/flight-dynamics/elevator-repair/results/steps-comparison.md).

### 3.1 Static pitch derivatives at the V₀ trim, production data

Central differences of the two aerodynamic regimes at the same state (rates zero). "or" = attached oracle, "loc" = local strip/tail model. CLq and Cmq per q̂ = q c/2V.

| Aircraft (V₀) | Trim α, δe, stick | Cmα or / loc | Cmq or / loc | CLq or / loc | Cmδe or / loc | Cmα̇ or / loc | α per δe |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ugly Stik (15 m/s) | 4.26°, −5.26°, 26 % | −0.867 / −0.990 | −7.53 / −7.33 | 2.95 / 2.89 | −0.853 / −0.992 | lag state (−3.59) in both | −0.98 |
| Extra 300S (17) | 5.38°, −2.93°, 12 % | −0.613 / −0.626 | −8.86 / **−4.52** | 5.81 / **1.42** | −1.030 / −1.036 | none / none | −1.68 |
| P-51D (25) | 4.11°, −6.12°, 41 % | −0.224 / −0.241 | −7.53 / **−4.49** | 5.45 / **0.85** | −0.854 / −0.863 | none / none | −3.81 |
| Ventage Jet (29) | 4.05°, −1.73°, 6 % | −0.398 / −0.413 | −6.95 / **−3.52** | 6.25 / **0.84** | −0.912 / −0.915 | none / none | −2.29 |

The Ugly Stik is consistent across regimes (D11g made the oracle's rate derivatives its own). The other three lose about half their pitch damping and three quarters of their lift-due-to-pitch-rate whenever the local regime is active, and have no α̇ damping anywhere.

Elevator-induced regime switch and tail saturation (pitching-moment coefficient at the V₀ trim α):

| Aircraft | Blend reaches 1 at δe | Full nose-up Cm: oracle / local | Full nose-down Cm: oracle / local |
| --- | --- | --- | --- |
| Ugly Stik | −20° (full) / +15° | +0.219 / +0.250 (blend +0.226) | −0.374 / −0.365 |
| Extra | ±12° (50 %) | +0.382 / **+0.245** | −0.480 / **−0.265** |
| P-51 | +7.5° nose-down; nose-up stays attached | +0.145 / +0.178 | −0.304 / **−0.152** |
| Ventage Jet | ±15° (50 %) | +0.449 / **+0.284** | −0.507 / **−0.250** |

For the P-51 the local model also sits +0.031 above the oracle at every elevator angle (δe = 0, α 4.11°: −0.079 vs −0.048): the strips carry no section pitching moment, while the generator's Cm0 includes the wing camber moment (≈ −0.030 after removing the tail-incidence part).

### 3.2 Step responses, production

δe is the surface angle during the hold (+ TE up); q and α peaks with their time after the step; nz the load-factor peak; p, φ the roll-rate and bank maxima over 5 s. Stall start a1: Ugly 12.1°, Extra 13.3°, P-51 11.6°, Ventage Jet 10.3°.

| Aircraft, V | Stick | δe | q peak °/s @ s | α peak ° @ s | nz | p max °/s | φ max ° |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ugly 15 m/s | +25 % | +10.3 | 23 @ 0.29 | 8.0 | 1.5 | 7 | 16 |
| | +50 % | +15.3 | 46 @ 0.31 | **12.2** | 1.9 | **126** | 83 |
| | +100 % | +20.0 | 117 @ 1.50 | **17.2** @ 0.54 | 2.2 | **269** | 180 |
| | −100 % | −14.7 | −101 | −14.4 | −2.8 | 299 | 180 |
| Ugly 21 m/s | +50 % | +12.6 | 66 | 7.8 | 3.1 | 95 (tail slide, V 1.4 m/s) | 48 |
| Extra 17 m/s | +25 % | +8.9 | 48 @ 0.42 | **13.3** | 2.2 | **115** | 76 |
| | +50 % | +14.9 | 159 @ 1.50 | **27.9** @ 0.47 | 2.4 | **341** | 180 |
| | +100 % | +23.9 | 169 @ 0.24 | **44.6** @ 0.50 | 2.3 | 93 | 41 |
| Extra 24 m/s | +25 % | +7.3 | 62 | 8.7 | 3.1 | 13 | 24 |
| P-51 25 m/s | +25 % | +9.9 | 49 @ 0.78 | **19.6** @ 1.06 | 2.3 | **229** | 155 |
| | +50 % | +13.6 | 71 @ 0.46 | 24.0 | 2.4 | 206 | 135 |
| | +100 % | +15.0 | 78 @ 0.43 | 25.9 | 2.4 | 211 | 157 |
| | −100 % | −8.9 | −103 | −22.1 | −2.1 | 259 | 180 |
| P-51 35 m/s | +25 % | +9.1 | 67 @ 1.29 | 14.7 | 3.7 | 216 | 108 |
| Ventage Jet 29 m/s | +25 % | +9.2 | 66 @ 0.32 | **21.1** @ 0.56 | 2.3 | 60 | 27 |
| | +50 % | +16.7 | 109 @ 0.27 | **36.0** @ 0.58 | 2.2 | 3 | 2 |
| | +100 % | +30.0 | 176 @ 0.33 | **83.1** @ 0.94 | 2.8 | 207 | 104 |
| | −50 % | −13.3 | −133 @ 0.37 | −27.9 | −2.3 | **414** | 180 |
| Ventage Jet 41 m/s | +25 % | +8.4 | 178 @ 1.50 | 19.4 | 4.6 | **406** | 180 |

Hands-off runs at every trim hold their state exactly (zero drift in 5 s). Pitch moments from propulsion stay within ±0.5 N·m for the Ugly, Extra and Ventage Jet (aero ±10–40 N·m); the P-51's thrust line 7.1 cm above its CG plus P-factor gives −2.3 N·m at trim and up to −18 N·m at full throttle in a 35 m/s push, and its 4-blade propeller's gyroscopic pitch moment reaches 8–24 N·m during fast pushes. Both are physical consequences of the declared geometry and rotor inertia.

### 3.3 Counterfactuals

`oracleStall`: a disposable copy of `app/` in which `Aero.local_flow_weight` returns 0 (the attached oracle with its own stall blend, everywhere). `freetail`: production code, each generator's own dε/dα injected into the data (Extra 0.4734, P-51 0.4391, Ventage Jet 0.5088 from their `derivation.md` tables). `480 Hz`: production at twice the tick rate.

| Case | production α peak / p max | oracleStall α / p | freetail α / p | 480 Hz α / p |
| --- | --- | --- | --- | --- |
| Ugly 15, +50 % | 12.2° / 126 | 11.5° / 30 | (already free-tail) | 12.2° / 126 |
| Ugly 15, +100 % | 17.2° / 269 | 31.4° / 17 | — | 17.2° / 269 |
| Extra 17, +25 % | 13.3° / 115 | 11.9° / 9 | 12.0° / 11 | — |
| Extra 17, +50 % | 27.9° / 341 | 25.4° / 3 | 19.2° / 231 | — |
| Extra 17, +100 % | 44.6° / 93 | 39.4° / 6 | 26.2° / 346 | — |
| P-51 25, +25 % | 19.6° / 229 | 12.8° / 10 | 15.5° / 211 | — |
| P-51 25, +100 % | 25.9° / 211 | 22.5° / 9 | 19.3° / 197 | — |
| P-51 35, +25 % | 14.7° / 216 | 8.7° / 9 | 12.3° / 15 | — |
| Ventage Jet 29, +25 % | 21.1° / 60 | 20.2° / 2 | 14.7° / 281 | 21.1° / 60 |
| Ventage Jet 29, +50 % | 36.0° / 3 | 33.5° / 2 | 20.6° / 221 | 36.0° / 3 |
| Ventage Jet 29, +100 % | 83.1° / 207 | 73.1° / 8 | 31.8° / 3 | 83.1° / 207 |
| Ventage Jet 29, −50 % | −27.9° / 414 | −24.9° / 7 | −17.3° / 416 | −27.9° / 414 |
| Ventage Jet 41, +100 % | 81.0° / 17 | 70.4° / 4 | 31.8° / 3 | 81.0° / 17 |

Reading: (a) the oracle stalls just as deeply but never rolls, so the roll departures are the local strip model's post-stall behaviour, not the pitch pipeline; (b) the free-tail law cuts α overshoot by 30–60 % and pitch-rate peaks by 20–30 % and restores full-stick authority, but a quarter to half stick on high rates still crosses the stall, after which the strip autorotation remains; (c) the time step is not a factor.

Static effect of the free-tail injection ([static-freetail.txt](../../research/flight-dynamics/elevator-repair/results/static-freetail.txt)): local Cmq becomes −8.60 (Extra), −8.06 (P-51), −7.19 (Ventage Jet) against the oracle's −8.86 / −7.53 / −6.95; the lag state adds the Cmα̇ root (−16, −18, −32 s⁻¹); full nose-up Cm at full stick returns to the oracle's value (Extra +0.382, Ventage Jet +0.420); short-period damping at trim rises from 0.69 to 0.89 (Extra) and 0.65 to 0.78 (Ventage Jet), and the P-51's short period becomes overdamped (real roots −6.9 and −2.8 s⁻¹), which `flight_modes.gd` currently reports as an "unexpected mode structure".

### 3.4 Stick fraction that reaches the wing stall at 1.6 Vs

Static estimate (a1 − α_trim) / (α per δe) / throw, and the measured dynamic result:

| Aircraft | Static stick to a1 | Measured | Manual's normal-flight rate (not implemented) |
| --- | --- | --- | --- |
| Ugly Stik | 40 % | 25 % attached, 50 % at a1 | 20° is already the estimated low rate |
| Extra | 20 % | 25 % at a1 | low rate 0.6 of travel ≈ 14.1° ([EX-08](../research/extra-300-realism/EX-08/airborne-audit.md)) |
| P-51 | 13 % | 25 % → 19.6° | low rate 12° (JSON source: Hangar 9 1.50 manual) |
| Ventage Jet | 9 % | 25 % → 21.1° | elevator D/R 50 % with 40 % expo in normal mode ([manual p. 4](../research/avanti-s-controls-and-installation.md)) |

## 4. Root-cause analysis

### 4.1 F1: the generated aircraft lack the free-tail law (confirmed, shared)

Code and data path: `derive_physics.py` (Extra `ex05`, P-51 `p51-05`, Ventage Jet `av06`) writes `aero.surfaces.horizontal.lift_slope = CLα_h η (1 − dε/dα)`, `control_effectiveness = τ_e k_flap / (1 − dε/dα)` and `incidence = (i_h − ε0)/(1 − dε/dα)`, i.e. the downwash folded into static effective values, and the oracle's `Cmq = −2 CLα_h η (S_h/S)(l_h/c)² × 1.1` with the undownwashed slope; `CLadot` is written to `reference_coefficients` and never read by the runtime. The loader ([aircraft_data.gd](../../app/physics/aircraft_data.gd) `_induced_map`, E0a2) derives the free law (`free_slope`, `elevator_tau`, `downwash_per_cl`, `free_incidence`, `downwash_lag_length`) only when `downwash_gradient` is present; the generators compute `deps` but do not emit it, so [aero.gd](../../app/physics/aero.gd) `_local_loads` takes the `else` branch: pitch rate and elevator act on the downwashed slope 1.67–1.84 instead of the free slope 3.27–3.40, no downwash state exists, and the stall bookkeeping sees `1.0–1.16 × δe` instead of `0.55–0.61 × δe`.

Physics: the tail's angle is α_t = α − ε + i_t + q l_t/V + τ_e δe with ε lagging the wing by l_t/V; pitch rate and elevator are not downwashed (MIT 16.333 Lecture 7: Cmq = −2 η V_H CLα_t l_t/c̄, Cmα̇ = −2 η V_H CLα_t (dε/dα) l_t/c̄). Using the downwashed slope for q halves Cmq; omitting the lag drops Cmα̇, which is 0.4–0.5 × Cmq for these tails (JSBSim's c172x carries Cmq −12.4 and Cmadot −5.2; NASA's AirSTAR identification shows the two terms are nearly collinear in flight and both needed). The repository's own research ([02-aerodynamics §5, T5](../research/roadmap-investigations/02-aerodynamics-rc-scale.md)) named this defect and fixed it for the Ugly Stik (E0a2a/b, D11g); it was not propagated to the generators.

Evidence that distinguishes it from alternatives: the Ugly Stik, which has the field, is regime-consistent (table 3.1) and its behaviour is unchanged by the counterfactual except in post-stall roll; injecting the field into the three others restores consistency without touching code (3.3); the oracle-only counterfactual shows the same stall depth, so F1 is not the whole story (F2, F4).

### 4.2 F2: elevator-induced roll is post-stall strip autorotation (confirmed mechanism)

In the local regime each strip's stall weight follows its own geometric angle, including p·y/V; once the mean angle crosses a1 the flat-plate branch gives the strips a negative lift slope (−7 to −12 /rad at α 12°, table in [static-production.txt](../../research/flight-dynamics/elevator-repair/results/static-production.txt)), so the roll derivative changes sign and the slightest asymmetry (lateral trim against engine torque, gyroscopic yaw of the propeller or turbine spool, Jxy of the Ugly's balance mass) grows into 200–600 °/s of roll within 0.2 s. The oracle has no spanwise freedom and never rolls under the same inputs. This is the D8b-R2 mechanism, now shown on all four aircraft and on pushes as well as pulls. A real wing autorotates past the stall too (that is a snap roll); what is unvalidated is the gain and abruptness (three strips per side, estimated post-stall curves, no hysteresis or stall progression). Do not treat it as a bug to damp away; treat it as unvalidated post-stall data and resolution.

### 4.3 F3: P-51 (confirmed gap, data uncertainty)

(i) Missing wing camber moment in the strips: ΔCm ≈ +0.031 between regimes (3.1), a trim step of about 1.4° of a 15° throw whenever the regime switches (pulls beyond ~8° α). (ii) The CG sits 13.1 % c behind the wing-body ARP and 9.7 cm above it; the transfer term r × F makes Cmα −0.305 at α 0 but −0.108 at α 10° (the lift's forward tilt acting below the CG), so the static margin is 7 % at trim and 2.5 % near the stall. (iii) α per δe is 3.8: the heaviest and slowest-starting response of the four (q̇ 316 °/s² at full stick against 654–1100 for the others, Jyy 6.8 kg·m²) that then goes to 20–26° α. (iv) Propeller angular momentum 7.3 N·m·s at trim, 10 at 35 m/s: pitch rates of 1–2 rad/s yaw it by 7–20 N·m, and the autorotation of F2 completes the "inconsistent" feel. The neutral point (34.2 % MAC) was calibrated to full-size XP-51 evidence without Reynolds similarity ([P51-REALISM-PLAN](../P51-REALISM-PLAN.md)).

### 4.4 F4: Ventage Jet (data/estimation deficiency)

Static margin 8.5 % MAC comes from anchoring the neutral point so that the manual's 3D CG (260 mm) is 3 % stable ([derivation](../../research/avanti-s/av06/derivation.md)); CL_max 0.85 ± 0.10 is a DATCOM estimate, the 4° blend width an input; together they put the stall start at 10.3°, which the 30° elevator reaches at 9 % stick. The generated `Cmde` (−0.95) and `Cma` (−0.85 about the ARP) are textbook-consistent, so the authority per degree is plausible for an aft-CG aerobatic jet; the unrealism is the combination with full high rates, no expo and an abrupt estimated stall.

### 4.5 Rejected hypotheses and how they were excluded

| Hypothesis | Result |
| --- | --- |
| Sign or axis error (input, surface, coefficient, moment transfer, body rates) | Read end to end: pilot + = TE up → `δe` = −rad → `Cmde δe` > 0 → nose up; local tail: TE down raises tail lift → nose down. Every step response has the right sign; AV-16 reached the same conclusion independently. |
| Rigid-body or quaternion integration, time step | Standard Euler equations with the gyroscopic term and renormalised quaternion; 240 and 480 Hz responses identical to display precision; AV-16 240/480 Hz agreement. |
| Direct torque injection, artificial damping, angular-rate clamps, "stabilisation" | None in `app/physics` or `app/sim`; only aero, propulsion, slipstream, ground and gyroscopic moments enter `RB.derivative`. |
| Duplicated forces or stage-reuse errors | Loads are a pure function of (state, aux, t); the k1 reuse (H2) is covered by existing tests; hands-off runs hold the trim exactly. |
| Thrust line / engine pitching moments | Ugly: thrust through the CG; Extra and Ventage Jet: < 0.5 N·m; P-51: −2.3 N·m at trim from a 7.1 cm offset declared by its generator (physical). |
| Products of inertia, CG mismatch | Jxy, Jyz ≤ 0.01 kg·m² (Ugly), zero for the others; the loader rejects a CG more than 1 mm from the plan CG. |
| Servo or command rate limiting | 0.11–0.18 s servo, 0.25 s keyboard ramp; responses develop over 0.3–1 s. |
| Ground effect, wind, atmosphere | 300 m, calm, reference density: the ground-effect path returns NAN and adds nothing. |
| Pitch inertia too low | Rather the opposite: virtual balance masses add 39 % (Ugly), 6 % (Extra), 9 % (P-51), 10 % (Ventage Jet) to Jyy. Unmeasured (VAL-6), but not a cause of excess authority. |

### 4.6 Remaining uncertainty

Post-stall gain and abruptness (F2); CL_max, stall widths and neutral points of the three generated aircraft; measured mass, CG and inertia (VAL-5/6); the tail's own stall law at large flap deflection (the flat-plate transition at 12–24° of combined angle is an estimate shared by all four aircraft and still saturates nose-down authority by 25–40 % after the free-tail repair); whether owners fly with rates and expo on their radios. Tests that distinguish them are listed in §8.

## 5. Research

| Source | Used for | Status |
| --- | --- | --- |
| MIT OCW 16.333 Lecture 2 and [Lecture 7](https://ocw.mit.edu/courses/16-333-aircraft-stability-and-control-fall-2004/2aca82b5d1a5aacf39ceffcfe4e5b517_lecture_7.pdf) | α_t = α_FRL + i_t − ε, ε = ε0 + (dε/dα) α, elliptic dε/dα = 2 CLα_w/(π AR); downwash lag Δt = l_t/U0; CZα̇ = −2 η V_H CLα_t dε/dα, Cmα̇ = CZα̇ l_t/c̄; CZq = −2 η V_H CLα_t, Cmq = CZq l_t/c̄ | Text extracted and checked this session |
| Grauer, Morelli, Murri, [Flight Test Techniques for Quantifying Pitch Rate and Angle of Attack Rate Dependencies](https://ntrs.nasa.gov/api/citations/20170001231/downloads/20170001231.pdf) (NASA Langley) | Cmq is the tail's lift during pitch rotation, Cmα̇ approximates unsteady aerodynamics; the two are nearly collinear in ordinary manoeuvres and need designed inputs to separate | Text extracted this session |
| [JSBSim c172x aerodynamics](https://raw.githubusercontent.com/JSBSim-Team/jsbsim/master/aircraft/c172x/c172x.xml) | Coefficient build-up with explicit Cmq (−12.4) and Cmadot (−5.2), CLq 3.9, CLadot 1.7, all scaled by qbar S c̄ and c̄/2V; a reference for keeping both rate terms | Fetched this session |
| [Godot Engine class reference](https://docs.godotengine.org/en/4.4/classes/class_engine.html) (`physics_ticks_per_second`, `max_physics_steps_per_frame`) | Fixed-tick semantics and catch-up limit behind [project.godot](../../app/project.godot) (240 Hz, 12 steps per frame) | Search result; the flight solver does not use Godot's physics bodies |
| MIL-F-8785C short-period requirements (DTIC [ADA119421](https://apps.dtic.mil/sti/pdfs/ADA119421.pdf)) | Sanity band for short-period damping: Level 1 ζ 0.35–1.30 (Category A) as recalled; the document could not be fetched (HTTP 403), so verify Table IV before citing values | Not verified this session |
| UMN Ultra Stick 25e / 120 flight identification (Dorobantu et al. 2013, via [sensitivity.gd](../../research/sensitivity/sensitivity.gd) and [02-aerodynamics §T3](../research/roadmap-investigations/02-aerodynamics-rc-scale.md)) | Froude-scaled bands: short period 1.30 Hz ζ 0.55 (US120); the Ugly Stik sim sits between the two Sticks | Repository evidence |
| Repository research: [02-aerodynamics §5, T2, T5, X-aero-2, E0a-2](../research/roadmap-investigations/02-aerodynamics-rc-scale.md), [flight-repair-implementation](../research/flight-repair-implementation.md), [D8b-R2](../research/flight-robustness/D8b-R2/README.md), [AV-16 pitch sweep](../research/avanti-realism/AV-16/pitch-sweep.md), [test_tail_downwash.gd](../../app/tests/test_tail_downwash.gd), [D11g derivation](../../research/aero/d11g/derive_rate_derivatives.gd) | The defect was predicted ("damping changes by regime … local tail uses a downwash-reduced slope for the pitch-rate term without adding Cmα̇"), the fix designed (E0a-2) and delivered for the Stik only | Current |
| Manuals via repository notes: [Ventage Jet controls](../research/avanti-s-controls-and-installation.md) (D/R and expo per flight mode), [EX-08 airborne audit](../research/extra-300-realism/EX-08/airborne-audit.md) (low-rate travel fractions), P-51 JSON `controls.max_throw` source (Hangar 9 1.50 low/high rates) | Normal-flight rates are 50–60 % of the implemented throws with 30–40 % expo | Current |

Engineering implications: the loader's free-tail representation is the textbook one and should be the only one; the local tail's stall bookkeeping must use the physical flap effectiveness τ_e, not τ_e/(1 − dε/dα); the strips need the section pitching moment to match the oracle's Cm0 for cambered wings; rates and expo are an input matter and must not be emulated by altering aerodynamic data.

## 6. Proposed corrections

Separated by certainty. None replaces the flight model; each is independently testable.

### Confirmed bugs

**C1. Free-tail law for the generated aircraft (F1).** In `research/extra-300/ex05/derive_physics.py`, `research/p51/p51-05/derive_physics.py` and `research/avanti-s/av06/derive_physics.py`, emit `aero.surfaces.horizontal.downwash_gradient = {value: deps, unit "1", kind "derived", source: <the existing dε/dα note>}` next to `lift_slope`; regenerate the three JSONs through the generators and the ID-gated standardiser; no loader or aero code change. The loader then derives `free_slope = lift_slope/(1 − deps)` (= CLα_h η), `elevator_tau = control_effectiveness × (1 − deps)` (= τ_e k_flap), `free_incidence`, `downwash_per_cl = deps/CLα_w` and `downwash_lag_length`; `FlightSession` adds the lag state; `Aero._global_loads` adds the oracle's Cmα̇ term. Static tail loads are unchanged by construction (E0a2a test), the elevator's static power is unchanged (`Cmde` kept), and the measured effects are those of §3.3. The Ugly Stik is untouched (byte-identical goldens).

**C2. Regime-consistency test (02-aerodynamics X-aero-2).** New headless test over every catalog aircraft at its start-speed trim and at α 0, 4, 8°: central-difference CLα, Cmα, Cmq, Cmδe and the static Cm of `_global_loads` versus `_local_loads` within bands (Cmq and CLα ±10 %, Cmα ±15 % of CLα·0.03, Cmδe ±5 %, static Cm ±0.01). Red today for three aircraft (3.1); green after C1 except the P-51's static Cm (C3).

**C3. Wing section pitching moment in the strips (F3-i).** Add an optional per-aircraft quantity (e.g. `aero.surfaces.wing_section_cm_ac`, "1", or per strip) applied in `_local_loads` and `_wing_lift_coefficient`'s companion as a pure couple per strip, `M_i = q_i S_i c_i Cm_ac` along body y (attached share only, fading with the stall weight like the lift). Generators emit it from their camber-line estimate (P-51 ≈ −0.030; Extra and Ventage Jet 0 for symmetric sections). Absent field = 0 = byte-identical. Decide separately whether the Ugly Stik's Cm0 (−0.0278, folded into its tail incidence by calibration) stays as is; do not double count.

**C4. `flight_modes.gd` classification.** Accept an overdamped short period (two real longitudinal roots besides the lag root) and report it as ζ ≥ 1 with the two time constants; `test_modes.gd` keeps its bands. Without this, C1 makes `FlightModes.analyze` fail for the P-51 (§3.3).

### Probable issues (fix after measurement or decision)

**P1. Dual rates and expo as an input feature (F2, F4).** Per-aircraft rate profiles sourced from the manuals (Ventage Jet normal 50 % + 40 % expo; Extra low 0.6 travel; P-51 low 12/15; Ugly keep 20°), applied in [commands.gd](../../app/input/commands.gd)/`FlightSession` between the stick and the servo, with the keyboard defaulting to the normal profile and a switch to high rates; radios keep passing through (their own rates) with the profile optional. Physics throws stay the mechanical maxima in the data. This is a product decision for the owner (D6/UI tracks), explicitly not an aerodynamic change.

**P2. Post-stall lateral behaviour (F2, continuation of D8b-R2).** Measure the strip model's post-stall roll derivative and departure gain versus α and compare with published rectangular-wing post-stall data; evaluate stall progression (per-strip widths), a bounded dynamic-stall/hysteresis state and strip count on the four aircraft; qualify against owner flights at normal rates. No damping, clamp or rudder bias.

**P3. P-51 pitch data (F3-ii…iv).** Review the neutral-point anchor and the vertical CG/ARP offset against a model-scale reference (kit CG, measured CG/inertia under VAL-5/6); document the throttle–pitch coupling and gyroscopic yaw as physical, with their magnitudes.

### Tuning deficiencies (data provenance, no code)

**T1. Ventage Jet stall and neutral point:** CL_max 0.85 ± 0.10, blend width 4°, neutral point anchored on a manual CG assumption. Replace with polar evidence or a planform-specific calculation before Gate 2; record the sensitivity (a1 10.3° → 12.3° for CL_max 1.0).

**T2. Extra and P-51 CL_max** (1.05 and 1.02, estimated); **T3. inertia**: the virtual balance masses add 6–39 % to Jyy; VAL-6 swing tests replace them.

### Future realism enhancements

**E1.** Tail stall law with the flapped section's CL_max (the combined-angle flat-plate transition saturates nose-down authority by 25–40 % even after C1). **E2.** Dynamic stall and spanwise progression (M5). **E3.** Pilot cues for validation flights: HUD load factor and α, so owners can compare pulls with the manuals' expectations.

## 7. Aircraft-specific considerations

| Aircraft | What changes with C1–C4 | What remains |
| --- | --- | --- |
| Ventage Jet | Local Cmq −3.5 → −7.2, Cmα̇ added, full-stick Cm +0.28 → +0.42, α peak at full stick 83° → 32°, short period ζ 0.65 → 0.78; trim unchanged (−1.73°). | Stall at 10.3° reached at 9 % of the 30° throw: needs P1 (normal rate 15° with 40 % expo) and T1. Post-stall departures (P2). The turbine's ram-drag normal force is small (< 1 N·m) and correct in sign. |
| Ugly Stik | Nothing (already free-tail; goldens byte-identical). | Roll departure at ≥ 50 % stick at 15 m/s is the D8b-R2 post-stall mechanism; the 20° throw is an estimate; Jyy carries a 39 % virtual-mass share. |
| Extra 300S | Local Cmq −4.5 → −8.6, Cmα̇ added, full nose-up Cm +0.245 → +0.382, 25 % stick stays attached at 17 m/s (α 12.0° vs 13.3°), ζ 0.69 → 0.89. | 50 % stick still stalls at 17 m/s (19° α) and departs; the manual's low rate (≈ 14°) would make 50 % ≈ 7°. CL_max estimated. |
| P-51D | Local Cmq −4.5 → −8.1, Cmα̇ added, nose-down authority −0.15 → −0.27 at full stick, α peak at 25 % stick 19.6° → 15.5°; C3 removes the +0.031 regime step; C4 needed for the modes tool. | Static margin 7 → 2.5 % with α, α per δe 3.8, 41 % of the throw used by trim, gyroscopic coupling up to 24 N·m: physical given the data, but the data (NP, CG height, inertia) is unmeasured. |

## 8. Validation strategy

Automated (headless, `app/test.sh`):

1. C2 regime-consistency test on all catalog aircraft (red first, green after C1/C3).
2. Loader tests: the generated JSONs declare `downwash_gradient`; derived `free_slope`, `elevator_tau` equal the generators' CLα_h η and τ_e k_flap within 1e-9 (extend `test_tail_downwash.gd` to the three aircraft); static tail lift equal to the former law in the attached range.
3. Step-response regression: the harness cases of §3.2 recorded after C1 as bands (q peak, α peak, nz within ±5 %, 240 and 480 Hz within 1 %), one file per aircraft; a deliberate physics change re-records them with its proof, as the goldens do.
4. Attached-regime symmetry: for every pull whose α stays below a1, roll rate must stay below 30 °/s and bank below 20° (already true today: F2 is post-stall only).
5. Modes: `test_modes.gd` bands for the Stik unchanged; new bands for the three aircraft after C4 (short period ζ 0.5–1.0 or overdamped, phugoid damped), reported alongside the MIL-F-8785C Level 1 band 0.35–1.30 as a sanity reference once verified.
6. Goldens and replay: Stik goldens byte-identical; the three aircraft's checkpoints gain the lag aux component (the H9 replay policy already names "downwash"); `test_trace_metadata` and checkpoint tests updated accordingly.
7. Performance: `bench_physics.gd` before/after C1 (one extra aux state and one wing-CL evaluation per tick, as the Stik already pays), within the 500 µs tick budget.

Manual (owner, after P1 is decided): at each aircraft's start speed with the normal rate profile, a quarter-stick pull must give a clean 1.5–2.5 g pull-up without stall or roll; a full-stick pull on high rates may stall and should be judged against the pilot's expectation of a snap; loops with the manuals' stated rates (Extra 0.3 stick, P-51 0.7, Ventage Jet 0.10–0.25 from 50 m/s); pushes to −1 g; throttle steps at constant stick for the P-51 (pitch change ≤ 2°). Ratings per the Gate 2 −2…+2 scale.

Acceptance criteria with a physical basis: at 1.6 Vs the maximum attached load factor is (1.6)² = 2.56 g, so the elevator travel that reaches CL_max is the whole usable normal-rate range; a quarter of the normal rate must not reach the stall (criterion for P1 and T1); short-period damping ratio between 0.5 and 1.0 in both regimes (current `test_modes.gd` floor, inside the MIL-F-8785C band); oracle and local regimes within the C2 bands so that no input can change the damping by switching regimes.

## 9. Risks and dependencies

- **Regenerated data changes identity hashes, trims and handling expectations** of the three aircraft (P-51 trim elevator −6.12° → −6.25°; loop/stall checks in `test_extra_handling.gd`, `test_p51_handling.gd`, `test_avanti_handling.gd` will move). Re-record with the measured deltas in the commit; do not retune to keep old numbers.
- **Checkpoint/replay layout** gains one aux state for three aircraft: old checkpoints of those aircraft become incompatible (same as E0a2b did for the Stik); the replay tolerance policy already covers the component.
- **FlightModes** fails for the P-51 until C4; the sensitivity and validation dashboards that call it must tolerate an overdamped short period.
- **Uncommitted parallel work** touches `aero.gd`, `aircraft_data.gd`, `dynamics.gd`, `flight_session.gd` and the Stik JSON (ground-effect module). C1 touches only the three generators and their outputs; C3 touches `aero.gd` and the loader and must be coordinated with that track after it lands.
- **Generator currency checks** (`derive_physics.py --check` in `test.sh`) require regenerating each JSON in the same change as its generator.
- **P1 is a product change**: it alters what every player feels; keep it opt-out, keep physics throws as the mechanical maxima, and never express it as aerodynamic data.
- **P2 can be mistaken for tuning**: any change to stall widths, strip counts or post-stall laws needs its own evidence and the D8b-R2 promotion limits.

## 10. Implementation roadmap

| Order | Step (proposed ID) | Work | Proof |
| --- | --- | --- | --- |
| 1 | D11i | Regime-consistency test (C2), red on three aircraft | Test output listing the §3.1 deltas |
| 2 | E0a2c | Generators emit `downwash_gradient`; regenerate Extra, P-51, Ventage Jet; extend `test_tail_downwash.gd`; re-record handling checks and checkpoints | D11i green for Cmq/CLα/Cmδe; step-response bands recorded (§8.3); Stik goldens unchanged; bench within budget |
| 3 | D8a-R2 | `flight_modes.gd` overdamped short period (C4); modes bands for the three aircraft | `test_modes.gd` and the P-51 analysis both pass |
| 4 | D11j | Wing section Cm_ac in the strips (C3), P-51 generator emits it | D11i static-Cm band green; P-51 regime step removed |
| 5 | D6e (owner decision) | Dual rates and expo profiles (P1), keyboard default normal | Manual checks of §8; quarter-stick criterion met on all four |
| 6 | D8b-R2 continuation | Post-stall lateral gain and progression (P2) on four aircraft | Published-data comparison, owner acceptance (D8b-R2h) |
| 7 | DATA/VAL-5/6/8 | Ventage Jet stall/NP evidence (T1), CL_max and inertia measurements (T2/T3), P-51 CG/NP review (P3) | Measured inputs with uncertainty replacing estimates |
| 8 | M5 (future) | Tail stall law with flap CL_max (E1), dynamic stall (E2), pilot cues (E3) | Separate plans |

Steps 1–4 are small, independently reviewable and need no new aircraft data beyond values the generators already compute; they restore one pitch dynamics per aircraft in every regime. Steps 5–7 decide how much of the remaining violence is realism and how much is estimated data, which only measurements and the owner's flights can settle.

## 11. Implementation record (2026-10-13)

Steps 1–4 are implemented; the evidence page [E0a2c](../research/aero-consistency/E0a2c/README.md) lists the files, the measured deltas and the checks run.

| Step | Result |
| --- | --- |
| D11i | `app/tests/test_regime_consistency.gd`: 13 failures on the pre-repair data (every Cmq check of the three generated aircraft plus the P-51 static Cm), 0 after. |
| E0a2c | The three generators emit `downwash_gradient`; regenerated JSON and derivation tables; local Cmq −4.5/−4.5/−3.5 → −8.6/−8.1/−7.2 against the oracle's −8.9/−7.5/−6.9; full-stick nose-up Cm restored to the oracle's (Extra +0.382, Ventage Jet +0.420). |
| D8a-R2 | `flight_modes.gd` reports an overdamped short period (P-51: roots −6.9 and −2.8 s⁻¹) instead of failing; `test_modes.gd` unchanged and green. |
| D11j | `wing_section_cm_ac` (contract, schemas, loader, strips, P-51 generator): the P-51's static regime step +0.031 → +0.001. |
| Steps (§3.2 cases) | Extra 17 m/s quarter stick: α 13.3° → 12.0°, roll 115 → 11 °/s; P-51 25 m/s quarter stick: 19.6° → 12.8°, roll 229 → 29 °/s; Ventage Jet full stick: 83° → 32° α; Ugly Stik byte-identical. Rows `prod_repaired` in [steps-comparison.md](../../research/flight-dynamics/elevator-repair/results/steps-comparison.md). |

| D6e | Implemented the same day ([evidence](../research/radio-input/D6e/README.md)): optional `controls.rates.normal` in the data (the three generators emit their manuals' normal rates; Extra 0.39/0.59/0.58 travel, P-51 0.78/0.80/0.67, Ventage Jet 0.5/0.5/0.8 with expo 0.2/0.4/0.6), `Commands.expo`/`shape_sticks`, `FlightSession.rate_profile` ("full" by default so every scripted check is unchanged; the flight scene uses "normal" for keyboard and gamepad sticks, `--rates=full` for the maximum throws, radios pass through), `test_rates.gd`. |

Still open from this plan: an in-flight rate switch (UI track), the D8b-R2 post-stall lateral work, and the Ventage Jet/P-51 stall and neutral-point data items.

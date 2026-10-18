# E0a2c, D11i, D11j, D8a-R2: one pitch dynamics per aircraft in both aero regimes

2026-10-13 · Status: implemented and verified by software checks; physical validation open. Diagnosis: [elevator investigation](../../flight-dynamics/elevator-repair-2026-10-13.md). Harness and reduced results: [research/flight-dynamics/elevator-repair](../../../../research/flight-dynamics/elevator-repair/README.md).

## What changed

| Step | Change | Files |
| --- | --- | --- |
| D11i | Regime-consistency test: at each catalog aircraft's start-speed trim the attached oracle and the local strip/tail model must agree on Cmq (±12 %), CLα (±10 %), Cmδe (±8 %, Stik exception 20 % documented in the test), Cmα (±0.20) and the static Cm (±0.012); Cmq also at α 0, 4, 8°. Red before the repair for the Extra, P-51 and Avanti (13 failures), green after. | `app/tests/test_regime_consistency.gd` |
| E0a2c | The three generators emit `aero.surfaces.horizontal.downwash_gradient` (the dε/dα they already computed), so the loader derives the free tail law for them as it does for the Stik: free slope CLα_h·η, physical elevator τ_e·k_flap, downwash as the lagged wing lift, Cmα̇ in both regimes. Regenerated data and derivation tables. | `research/extra-300/ex05/derive_physics.py`, `research/p51/p51-05/derive_physics.py`, `research/avanti-s/av06/derive_physics.py`, the three `app/data/aircraft/*.json`, their `derivation.md` |
| D11j | Optional `aero.surfaces.wing_section_cm_ac` (unit 1, −0.3…0.1): the cambered section's pitching moment as a pure couple on every strip of the local wing, q·S_i·c_i·Cm_ac, using the strips' local chords stored by the loader. Absent = no arithmetic (byte-identical). The P-51 generator emits its thin-airfoil value ×0.8 (−0.0286); the oracle's Cm0 already carried it. | `app/physics/aircraft_data.gd` (`_surfaces`, `_induced_map`), `app/physics/aero.gd` (`_local_loads`), contract and schemas, parameter register, `AIRCRAFT_CONTRACT.md` |
| D8a-R2 | `flight_modes.gd` classifies an overdamped short period (two negative real roots besides the lag root) and reports it as ζ ≥ 1 with the roots; the P-51 with the free tail law is such a case. | `app/physics/flight_modes.gd` |
| Tests | `test_downwash_lag.gd` now expects the lag state on the three aircraft and checks that the same data without the gradient has none; `test_aero_flow.gd` and `test_slipstream_scalar.gd` strip the free-tail fields and the section moment before comparing with their frozen references (both predate the P-51's free tail law); `test_shaft_refinement.gd` see below. | `app/tests/` |

The Ugly Stik data and goldens are untouched and byte-identical (`test_golden.gd`, `test_aero_flow.gd`).

## Measured effect (software evidence)

Static derivatives at the start-speed trim, oracle / local ([before](../../../../research/flight-dynamics/elevator-repair/results/static-production.txt), [after](../../../../research/flight-dynamics/elevator-repair/results/static-repaired.txt)):

| Aircraft | Cmq before | Cmq after | Cmα̇ (lag root) after | Full nose-up Cm before → after (oracle) | Static Cm step before → after |
| --- | --- | --- | --- | --- | --- |
| Extra 300S (17 m/s) | −8.86 / −4.52 | −8.86 / −8.60 | −16.1 s⁻¹ | +0.245 → +0.382 (+0.382) | 0.000 → 0.000 |
| P-51D (25 m/s) | −7.53 / −4.49 | −7.53 / −8.08 | −17.6 s⁻¹ | +0.178 (local) | +0.031 → +0.001 |
| Avanti S (29 m/s) | −6.95 / −3.52 | −6.95 / −7.19 | −31.8 s⁻¹ | +0.284 → +0.420 (+0.449) | 0.002 → 0.002 |

Elevator steps through the session loop (quarter, half and full stick at the start speed; [full table](../../../../research/flight-dynamics/elevator-repair/results/steps-comparison.md), rows `prod` → `prod_repaired`):

| Case | α peak before → after | Roll-rate max before → after |
| --- | --- | --- |
| Extra 17 m/s, +25 % | 13.3° → 12.0° (stall start 13.3°) | 115 → 11 °/s |
| Extra 17 m/s, +100 % | 44.6° → 26.2° | 93 → 346 °/s (still stalled; see below) |
| P-51 25 m/s, +25 % | 19.6° → 12.8° | 229 → 29 °/s |
| P-51 25 m/s, +100 % | 25.9° → 18.2° | 211 → 107 °/s |
| P-51 35 m/s, +25 % | 14.7° → 9.8° | 216 → 10 °/s |
| Avanti 29 m/s, +25 % | 21.1° → 14.7° | 60 → 281 °/s |
| Avanti 29 m/s, +100 % | 83.1° → 31.8° | 207 → 3 °/s |
| Ugly Stik (all) | unchanged | unchanged |

Short period at trim (full Jacobian): Extra 1.46 Hz ζ 0.69 → 1.72 Hz ζ 0.89; Avanti 0.87 Hz ζ 0.65 → 0.89 Hz ζ 0.78; P-51 0.71 Hz ζ 0.82 → overdamped (roots −6.9 and −2.8 s⁻¹). 240 and 480 Hz responses agree to display precision.

## What it does not fix

Whenever a pull still crosses the wing's stall start (the Avanti at a quarter stick on its 30° high-rate throw, the Extra and P-51 from half stick), the local strip model's post-stall autorotation still rolls the airplane; the oracle-with-stall counterfactual never does. That is the D8b-R2 topic (post-stall gain and progression) and the input question (the manuals' normal rates and expo are not applied), both in the plan.

## Side effect on the coupled shaft refinement check

`test_shaft_refinement.gd` measured the P-51's whole-session RPM convergence under the coupled-RK4 shaft integrator and expected fourth order (error ratios 13–20 when halving the tick). With the free tail law the P-51 carries the downwash-lag state, which the session advances once per tick and holds through the RK stages (the E0a2b design the Stik already had); that hold limits the refinement of every state to second order (measured ratios 4.09 / 4.07 at errors of 4.6e-5, 1.1e-5 and 2.8e-6 rpm, against 16.4 / 16.2 at 1.3e-6 … 5e-9 rpm without the lag). The test now checks the integrator's order on the same data without the gradient and bounds the lagged case (ratios 3–6, 240 Hz error below 1e-5 rpm). Integrating the lag inside the RK stages would restore fourth order; it is a design change to the sampled-state layout (checkpoints, replay policy) and is not part of this repair.

## Checks run

`test_regime_consistency`, `test_modes`, `test_tail_downwash`, `test_downwash_lag`, `test_aero_flow`, `test_aero`, `test_golden`, `test_extra_handling`, `test_extra_installation`, `test_p51_handling`, `test_p51_envelope`, `test_p51_ground`, `test_avanti_handling`, `test_aircraft_contract`, `test_aircraft_data`, `test_envelope_integrity`, `test_induced_integrity`, `test_ground_effect`, `test_checkpoint`, `test_start_choice`, `test_runway_start`, `test_trace_metadata`, `test_trim`, `test_trim_integrity`, `test_wind_flight`, `test_atmosphere_flight`, `test_contact_policy`, `test_handling`, `test_physical_envelope`, the AS-01 schema/register/migration checks, the three generators' `--check`, the P51-15 inventory and AV-15 geometry/sensitivity checks; then `app/test.sh` (see the commit message for its result).

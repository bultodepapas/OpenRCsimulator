# M5-GE-1: wing and tail ground effect as an opt-in aircraft module

**Status:** implemented and software-verified, 2026-10-12. Step M5-GE-1 (main-line physics, ROADMAP M5), absorbing the tail-downwash part of the proposed M5-GE-2. Physical validation of the Stik's flare and liftoff remains open (VAL-8/PT2).

## Problem

Every flare and liftoff happens inside one span of the ground, where the ground's image vortex system reduces the wing's induced downwash: more lift at the same angle of attack, less induced drag at the same lift, and less downwash at the tail (a nose-down trim change). The [aero knowledge base, T6](../../roadmap-investigations/02-aerodynamics-rc-scale.md#t6-ground-effect) quantified this for the AR 5 Stik wing with an image-method VLM (+16 % lift, −34 % induced drag and −51 % tail downwash on the wheels) and listed it as a proposed M5 step. The simulator applied no height dependence at all, so the automated Stik landing and takeoff of the M2 milestone flew without the float and trim change every RC pilot knows.

## Design

Ground effect is a conditional v2 aircraft module, `aero.ground_effect`, with four fitted law constants carrying their own evidence kind and source ([contract](../../../AIRCRAFT_CONTRACT.md#physical-modules-and-parameter-effects), [module semantics](../../aircraft-standardization/AS-01/module-semantics.md#wing-and-tail-ground-effect)). Only the Stik declares it. Any aircraft without it, every static solve (trim, linearisation, flight modes) and every evaluation above the fade height take the byte-identical legacy load path; the oracle parity suites pass unchanged.

The law is σ(x) = c·x^e / (1 + c·x^e), x = height / span, faded with a C¹ smoothstep to exactly 1 at `FADE_SPAN_RATIO` = 2 spans ([`ground_effect.gd`](../../../../app/physics/ground_effect.gd)):

| Factor | Constants (Stik) | Applied to | Source |
| --- | --- | --- | --- |
| σ_i per wing strip | c = 33, e = 1.5, `borrowed` | The strip keeps (1 − σ_i) of its induced angle a0·(α_i + α_s) − base/a0 as extra attached lift; its induced drag k·(CL − CL_minD)² scales by σ_i. The attached oracle applies the same increments with per-strip σ (banked roll moment) and the mean σ for drag. | Raymer's K_eff/K = 33(h/b)^1.5/(1 + 33(h/b)^1.5), after McCormick [S1]; Wieselsberger's image theory [S2] and the T6 VLM agree within 0.05 for h/b 0.10–0.25 |
| σ_ε at the strips' mean height | c = 25, e = 2, `estimated` | The wing's downwash at the horizontal tail, `downwash_per_cl × CL_wing`, in the local tail law; in the oracle as a free-slope increment k_ε·(CL_free − σ_ε·CL_ge) at the tail's arm, and the D11g lag term scales by σ_ε. | Fit of the T6 tail ratios per unit wing lift (same-α ratio ÷ same-α lift ratio): 0.20/0.42/0.62/0.87/0.97 at h/b 0.10/0.17/0.25/0.5/1.0, within 0.012 |

Strip heights are the aero reference point's height at each station (the strips' force application point), so a bank lowers one wing's strips and the low wing gains lift. The session samples the field terrain height under the CG from the wheels' own [`ground_terrain.gd`](../../../../app/physics/ground_terrain.gd), only when the CG is below `reach()` (fade height plus the farthest strip's distance from the CG, 3.81 m for the Stik), and passes it through `Dynamics.loads` into `Aero.loads` and the lagged-downwash derivative. The runway static solve ([`ground_start.gd`](../../../../app/physics/ground_start.gd)) sees the same ground, so a wind-on runway start remains an exact equilibrium.

Why σ on the induced angle rather than a direct lift-ratio table: the same factor then gives the same-CL induced-drag reduction that Wieselsberger and Raymer define, and lift and drag stay consistent by construction. The price is a lower lift gain than the full image VLM, which also carries the bound-vortex image: the strips give L/L∞ ≈ 1.12 at the Stik's wheel height (strip h/b 0.215) where the T6 table interpolates to ≈ 1.12 at that height but 1.16 at h/b 0.17. Phillips and Hunsaker [S3] show these ratios also depend on planform, aspect ratio and CL, and the published closed forms disagree by about 2× in (1 − σ) (McCormick's (16h/b)²/(1 + (16h/b)²) and the Torenbeek/Phillips–Hunsaker 1 − exp(−4.01(2h/b)^0.717) are weaker than Wieselsberger and Raymer), so the constants are data to be re-fitted from a planform-specific VLM or measurements, not code.

## Implementation

| File | Change |
| --- | --- |
| `app/physics/ground_effect.gd` | New: `enabled`, `law`, `factors` (σ per strip, mean, σ_ε; empty when inactive), `reach` |
| `app/physics/aero.gd` | `loads`/`wing_lift_coefficient`/`wing_strip_loads` take `ground_up`; `_global_loads` and `_local_loads` take the factors; inactive paths unchanged statement for statement |
| `app/physics/dynamics.gd`, `app/sim/flight_session.gd` | `ground_up` threaded through `loads`/`loads_from_air`; `_ground_up()` terrain sample with the reach cutoff; the lagged downwash derivative and trace metadata (`ground_effect_model`) |
| `app/physics/aircraft_data.gd` | `_ground_effect` parser (unit `1`, bounds, unknown keys, requires the strip induced map and the free tail law); derived `strip_alpha_zero` and `strip_row_sum` |
| `app/physics/ground_start.gd` | The runway equilibrium evaluates aero with the terrain height under the CG when the module is present |
| `app/data/schema/aircraft-contract-v2.json`, `research/aircraft-standardization/build_schema.py`, `parameter_register.py` | Object rule, quantity paths and the four schema fields; regenerated v2 schema and the 152-path register |
| `app/data/aircraft/jensen_ugly_stik_60.json` | The module with its sources; the semantic identity changes with it |
| `research/flight-robustness/d8b-r2/candidates/*.json` | Regenerated by `make_candidates.gd` (they copy the Stik file) |
| `app/tests/test_ground_effect.gd` | New |
| `app/tests/test_wind_flight.gd`, `app/tests/check_math_sensitivity.py` | The same-state load comparison passes the session's ground; the H7 oracle-branch anchor follows the new call |
| `app/tests/test_swirl_optimization.gd`, `research/propwash/e0b6p/native/verify.gd`, `research/propwash/e0b6p/prepared-model/verify_lifecycle.gd`, `research/aircraft-data/schema/cases.py` | Fixtures that drop the Stik's `downwash_gradient` also drop the dependent module; DATA-4a gains the coupled schema-pass/loader-fail case and two module rejections |

## Verification

Software checks on the 2026-10-12 working tree (Godot 4.7.2, Linux headless). Known-answer values and measured increments are from `app/tests/test_ground_effect.gd`; the full run log of each suite is retained in [verification.md](verification.md).

| Check | Result |
| --- | --- |
| Induced law against Raymer's form (fade only above h/b 0.25) | within 0.0084 up to h/b 0.25, 0.015 to 1.0 |
| Induced law against Wieselsberger (h/b 0.10–0.25) and the T6 VLM induced-drag ratios | within 0.044 / 0.043 |
| Tail law against the T6 downwash ratios per unit lift (h/b ≤ 0.5) | within 0.012 |
| σ(0) = 0, σ = 1 exactly from the fade height; C¹; nondecreasing | pass |
| Byte-identical loads: 30 m with a ground, Extra at 0.5 m, 1 cm below reach within 1e-6 | pass |
| Fixed α (15 m/s trim) descending from 3.5 m to the wheels | lift rises monotonically: L/L∞ 1.0021 at 2 m, 1.0170 at 1 m, 1.0545 at 0.5 m, 1.1185 on the wheels (CG 0.258 m, strip h/b 0.215, σ̄ 0.775, σ_ε 0.551); ΔCm −0.0280 there, worth 1.9° of up-elevator (−0.8° at 0.5 m, −0.2° at 1 m) |
| Same lift at wheel height (α lowered 4.26° → 3.68°) | drag 0.978 of free air; at the same α it is 1.008 because the polar's lift-dependent term is near its minimum at this CL |
| Banked 20° at 0.8 m | the low wing gains lift; mirror bank opposite within 1 % |
| Oracle vs strip increments at 0.4 m | lift within 5 %, drag within 15 %, nose-down within 15 % |
| Session at 0.6 m on the default field | terrain sampled, load path and lagged downwash carry it, 48 ticks without fault, metadata named |
| Contract and loader | unknown field, missing constant, wrong unit, out-of-range exponent and a missing free tail law are refused; absence derives without the module and with another identity |

Ground maneuvers with the module on the Stik (baseline = the same tests before this change):

| Test | Before | After |
| --- | --- | --- |
| `test_takeoff_roll.gd` lift-off, neutral stick, full throttle | t 2.325 s, x 22.73 m, V 20.62 m/s, pitch 2.84° | t 2.371 s, x 23.69 m, V 20.99 m/s, pitch 2.28°; V(x) within 0.14 % of the 1-D integral at 5 m and 1.95 % at 20 m (band 3 %) |
| `test_landing_maneuver.gd` 240 Hz east (E3c1a test pilot, sink-rate command) | touchdown 8.300 s, sink 0.393 m/s, stop 43.27 m at 41.21 s, compression 31.4 mm | touchdown 8.296 s, sink 0.400 m/s, stop 44.03 m at 41.57 s, compression 34.1 mm; 240/480 Hz refinement bounds unchanged |

The neutral-stick liftoff comes 1 m later because the tail, in less downwash, holds the nose down during the roll (pitch 2.3° instead of 2.8° at lift-off), the trim change Goranson measured [S4]; the closed-loop test landing keeps its commanded sink rate and shows the float as a 0.8 m longer rollout. Neither is a validation of the real Stik's flare.

Unchanged by construction and re-run: the H4/H12 byte-exact oracle parity (20,001 comparisons), the four air goldens and the H7 one-ULP/branch replay, trim, flight modes, downwash lag (Cmα̇), damping regimes, envelope, spin, slipstream, electric sessions, checkpoints, runway starts, stiction, wind (51 checks, after the runway solve fix), trace acceptance (14), the pull-up CLI (3) and the aircraft contract (1,940 checks). The complete `app/test.sh`, `research/test-tools.sh`, the DATA-4a schema/loader agreement (1,913 cases) and the AS-01 schema tests are listed in [verification.md](verification.md).

## Limits

- Fitted generic constants; no Stik measurement. The lift gain is below the full image-VLM value (no bound-vortex image), the tail law's height is the wing's, and the published forms disagree by ~2× in (1 − σ). Same-α drag near the polar's CL_minD barely changes because the model's lift-dependent drag is near its minimum there; the same-CL reduction is exactly σ on that term.
- Separated (flat-plate) flow, the tabulated-polar continuations and the slipstream tail increment are unchanged by height.
- Trim, linearisation and flight modes are computed out of ground effect; the first tick near the ground sees the module.
- Strip heights follow the aero reference point (z 0.07 m above the datum for the Stik, so h/b 0.215 on the wheels); the research used the datum (0.17).
- Software verification only. Flare/liftoff traces against a pilot or video (VAL-8/PT2) decide whether the float and trim change are right for the real Stik.

## Sources

- S1. D. P. Raymer, *Aircraft Design: A Conceptual Approach*, AIAA; ground-effect factor K_eff/K = 33(h/b)^1.5 / (1 + 33(h/b)^1.5), after McCormick. The form is quoted, citing Raymer, in US patent 8,251,306 ([USPTO full text](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/8251306)); the book itself was not fetched.
- S2. C. Wieselsberger, "Wing resistance near the ground," NACA TM 77, April 1922 (translation of *Zeitschrift für Flugtechnik und Motorluftschiffahrt* 10, 1921): [NTRS 19930081293](https://ntrs.nasa.gov/citations/19930081293). The rational form 1 − (1 − 1.32 h/b)/(1.05 + 7.4 h/b) used as the comparison is the standard textbook approximation of its result for 0.033 < h/b < 0.25.
- S3. W. F. Phillips and D. F. Hunsaker, "Lifting-Line Predictions for Induced Drag and Lift in Ground Effect," *Journal of Aircraft* 50(4):1226–1233, 2013, [doi:10.2514/1.C032152](https://doi.org/10.2514/1.C032152), [USU repository](https://digitalcommons.usu.edu/mae_facpub/81): the ratios are not unique functions of h/b. Their Eq. 5 form (after Torenbeek, *Ground Effects*, 1982), 1 − exp(−4.01(2h/b)^0.717), is implemented in [AeroSandbox](https://aerosandbox.readthedocs.io/en/master/_modules/aerosandbox/library/aerodynamics/inviscid.html).
- S4. R. F. Goranson, "A Method for Predicting the Elevator Deflection Required to Land," NACA WR L-95 (ARR L4I16), 1944, [NTRS 19930092912](https://ntrs.nasa.gov/citations/19930092912): the change in downwash angle near the ground is among the largest contributors to the elevator deflection required to land.
- S5. In-repo image-method VLM table and estimates: [02-aerodynamics-rc-scale.md, T6](../../roadmap-investigations/02-aerodynamics-rc-scale.md#t6-ground-effect).
- Godot 4.7 GDScript: `const` cannot hold a `PackedFloat64Array` literal (the test uses a member variable); `%e` is not a supported format specifier ([GDScript format strings](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_format_string.html)).

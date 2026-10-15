# P51-25: fuselage directional destabilization calibrated to P-51D steady sideslips

2026-10-15 · Revision 1 · **Status: implemented and verified in software. Power-off rudder per sideslip matches the P-51D's 0.55 °/°. Powered values remain 0.68–1.0 °/° because the slipstream module has no propeller sidewash (next step). The P51-22 loop departure is now reported truthfully instead of passing by accident.** Prefix: P51-25. [Plan](../../../P51-REALISM-PLAN.md) · [Tools](../../../../research/p51/p51-25/README.md)

## Question

[P51-24](../P51-24/README.md) corrected the rudder area but left the model needing 1.75° of rudder per degree of steady sideslip, against 0.55 for the production P-51D (NACA RM L6J25 Table I, 200 mph). The model's Cnβ was the vertical fin alone because the shared consistency rule required Cnβ = fin. A real fuselage, spinner, canopy and propeller in yaw are destabilizing.

## Checks before changing anything

- **Roll power (no change needed).** Rudder-fixed aileron steps through the session give pb/2V per degree of total aileron of 0.0029–0.0032 ([before](baseline-roll.txt)). The XP-51's is 0.0032 (NACA MR L-566 Fig. 28). Aileron power is not the cause.
- **Dutch roll (independent evidence).** XP-51 Fig. 26 (cruise, CG 25.1 % MAC) gives a period of 3.64 s at 203 mph, the equal-CL point (CL 0.307). With the dimensionless period P·V_EAS/(b·√μ₀), which is valid at equal kz/b and CL, the full-size value is 8.66. The fin-only model gave 5.05 (0.58×), so it oscillated too fast, consistent with excess Cnβ ([before](baseline-modes.txt)).
- **Rejected alternative: weaken the fin.** Scaling the fin sidewash factor by 0.45 in a disposable generator run reaches the sideslip target, but it also cuts CYβ by 37 %, Cnr by 45 % and the rudder power that P51-24 had just validated. The evidence points to a missing destabilizing term, not to a weak fin.

## Module: `aero.surfaces.body_cn_beta`

This is a shared, opt-in module (1/rad, ≤ 0). When it is absent, every load is byte-identical.

- **Oracle:** the attached oracle keeps Cnβ as the whole-aircraft total. The [loader](../../../../app/physics/aircraft_data.gd) rule becomes Cnβ = fin force × arm + `body_cn_beta`.
- **Local model:** [`Aero._local_loads`](../../../../app/physics/aero.gd) adds the pure couple ½ρ·S·b·Cnβ_B·u·v, using body-axis air velocity. This is the Munk slender-body form ∝ sin 2β. It is linear in β at small angles and equals the oracle increment there, with the exact ratio cos α·cos β·sin β/β. It is zero at zero flow and broadside.
- **Fade with sideslip:** the couple fades out over the aircraft's declared linear-sideslip range (`envelope.sideslip_blend`, 15°→25°, the same weight that moves the oracle's β terms to sin β). Its evidence is small-sideslip attached flow. Unfaded, Munk's sin 2β peaks at 45°, where the local fin is stalled. The first candidate turned the scripted spin into an unrecoverable flat spin at β ≈ −45° ([fin-only spin](spin-fin-only.txt) recovers). A real fuselage's destabilizing moment levels off once crossflow separates. The fade makes no claim beyond the evidence.
- **Tests:** [`test_body_directional.gd`](../../../../app/tests/test_body_directional.gd) has 14 checks. They cover byte identity when absent or zero (400 states), Mz-only changes, the exact law including the fade, oracle/local agreement within 1 − cos 8° at |α| ≤ 8°, continuity through the fade, zero flow and broadside, and loader rejection of a positive value, a wrong unit and Cnβ ≠ fin + body.

## Calibration

[`derive_physics.py`](../../../../research/p51/p51-05/derive_physics.py) solves the attached steady sideslip [Clδa Cldr; Cnδa Cndr]·[δa; δr] = −β·[Clβ; Cnβ] for the total Cnβ that gives 0.55 °/°.

**The coefficients are about the ARP, but the airplane balances about its CG.** The runtime adds r × F (ARP 64 mm ahead of and 97 mm below the CG). A first solve without this transfer left the runtime at 0.447 °/° instead of 0.55. [`deriv_probe.gd`](../../../../research/p51/p51-25/deriv_probe.gd) located the difference: at a glide trim the runtime is pure oracle (blend 0), and its effective derivatives about the CG are Clβ −0.064 (data −0.080), Cnβ +0.046 and Cldr 0.0145 (data 0.0197) ([decomposition](derivatives-final.txt)). The generator now transfers the β and δr terms with side force dFy/dβ = qS·(CYβ − CD) and dFy/dδr = qS·CYδr. Its fin-only prediction of 1.749 then equals the runtime's 1.750.

| Value | Result |
| --- | ---: |
| Cnβ fin (about ARP) | 0.1395 |
| `body_cn_beta` | −0.0830 |
| Cnβ total, about ARP / about CG | 0.0565 / 0.0457 |
| DATCOM fuselage alone (comparison) | −0.0232 (28 % of the body term) |

The remainder lumps the bubble-canopy fuselage, the large spinner and the propeller in yaw.

**Calibration basis.** RM L6J25 flew all its sideslips in the climbing condition at normal rated power, at 10,000 ft, with the CG at 25.5 % MAC. At 200 mph IAS that is about CL 0.40 and Tc 0.08. The body term is an airframe property, so it is calibrated power-off. This assumes a small full-size power effect at that point: the report gives no power-off data, and its higher-power 103 mph value (0.46) is lower, not higher.

## Results

The lateral directional checks below use the runtime equations ([sideslip](candidate-sideslip.txt) vs [P51-24](baseline-sideslip.txt), [modes](candidate-modes.txt) vs [fin only](baseline-modes.txt), [roll](candidate-roll.txt)).

| Quantity | Full-size | Fin only (P51-24) | Fin + body |
| --- | --- | ---: | ---: |
| Rudder per sideslip, glide 25.7–45 m/s | 0.55 (P-51D, 200 mph, climb power) | 1.75 | **0.550–0.552** |
| Rudder per sideslip, level 25.7 / 35 / 45 m/s | — | 2.03 / 1.79 / 1.74 | 1.00 / 0.74 / 0.68 |
| Aileron per sideslip (dihedral effect) | XP-51 0.20–0.24 | 0.19 | 0.28 |
| Dutch roll at 28.6 m/s: dimensionless period | 8.66 (XP-51) | 5.05 | **6.91** |
| Dutch roll: cycles to half amplitude | 0.5–0.6 cruise, < 1 all conditions | 0.58 | 0.42 |
| Spiral time constant at 28.6 / 45 m/s (negative = divergent) | — | −21 / −48 s | −109 / +87 s |
| pb/2V per total aileron degree, rudder fixed | 0.0032 (XP-51) | 0.0029–0.0032 | 0.0027–0.0030 |

The changes follow lateral-directional theory: lower Cnβ gives a slower, better-damped Dutch roll, a more stable spiral (Clβ·Cnr against Cnβ·Clr), more adverse-yaw sideslip in rudder-fixed rolls, and more aileron to hold a given sideslip. The aileron per sideslip rises because a weaker fin needs less rudder, whose roll moment had partly held the wings level. Its 0.28 is above the XP-51's, but the P-51D has a different fuselage and dorsal fin and no D value is published.

## Handling and regression evidence

Godot 4.7.2, native Windows ([logs](tests/), [summary](tests/summary.txt)).

- **New and changed checks:** `test_body_directional` passes 14/14. `verify_p51` passes 248/248.
- **Schema and generator checks:** schema `--check`, parameter register (170 paths), `derive_physics --check`, Workshop descriptors, the inventory oracle, `test_schema_v2` and `test_modules` pass.
- **Shared aero:** `test_attached_flow` (20,000 byte-exact comparisons), aero continuity, envelope/induced integrity, downwash lag, all slipstream/swirl/wash tests, `test_ground_effect`, `test_trim`, `test_modes`, `test_golden`, checkpoints, trace metadata and flight logs pass.
- **Other aircraft:** Extra, Timber and Avanti handling and the aircraft data/catalog/contract tests pass. `test_rudder_authority` (Ugly Stik) prints byte-identical values to P51-24; its failure is the owner's known item.
- **Spin recovery:** the yaw rate is 0.25 rad/s 3 s after the recovery input ([final spin](spin-final.txt)).
- **Power-off stall recovery:** 81 m (83 m before) against the unsourced 80 m band (P51-19 open item). In the probe the power-off stall no longer rolls over (peak roll 180° → 5°).
- **Lift-off:** 25.3 m/s, the known P51-22 item.
- **Loop: corrected test, known failure.** The handling test's loop check integrated body pitch rate q. A banked rolling departure also reaches 360°, so the result had read 345° fin-only and 434° with the body term. The traces show no loop in either case: the full-throttle 0.7-stick pull reaches α 17.6° in 0.75 s and departs ([fin only](loop-fin-only.txt): peak pitch 31.5°, |β| 10°; [final](loop-final.txt): peak pitch 46°, |β| 20°). A new check requires the attitude to pass the vertical (> 80°) with |β| < 10°. Genuine loops by the Ugly Stik and the Extra at gentler pulls pass it (pitch 87–90°, |β| ≤ 2.3°). The P-51 departs at every stick setting tried (0.30: 124° in 8 s; 0.45/0.55: |β| 9–16°), with or without the body term. It now fails honestly as part of the open P51-22 powered-tail item.
- **P51-15 probes:** all 34 airborne and 5 ground cases complete at 240 and 480 Hz ([airborne 240](candidate-airborne-240.json), [480](candidate-airborne-480.json), ground [240](candidate-ground-240.json), [480](candidate-ground-480.json); baseline: [P51-24 candidate](../P51-24/candidate-airborne-240.json)). [Comparison](compare-240.md):
  - Rudder pulses give 27–55 % larger sideslip peaks and 38–48 % larger yaw-rate peaks.
  - Throttle steps now produce 6° of sideslip (was 2°) and visible roll, the P-51's familiar torque behaviour.
  - Trim rudder is 0.111 (was 0.091).
  - The heading-hold takeoff is unchanged (peak rudder 0.449, heading error 6.9°).
  - With no rudder at all, the unguided takeoff swerves 67° (was 43°) before staggering airborne. The real P-51D needs firm right rudder on takeoff.
  - At 240 vs 480 Hz, sideslip and yaw-rate peaks agree within 1 %. The exception is the stochastic gentle-practice weather case (18 %), which is reported individually as in P51-17.

## Open items

1. **Powered directional stiffness (next step).** In level flight the slipstream adds Cnβ +0.042 and Cndr −0.013 about the CG, so rudder per sideslip rises to 0.68–1.0. The full-size trend runs the other way: 0.46 at 103 mph, the highest thrust coefficient. [`slipstream.gd`](../../../../app/physics/slipstream.gd) adds the wash along the shaft axis and states that the transported direction is not modelled. A propeller in sideslip also turns its jet toward its axis and reduces the angle the fin sees. That sidewash is the probable missing term. It belongs to the slipstream module and needs primary power-on data before any change.
2. **Loop departure and lift-off:** P51-22, owned by the R02/R06 powered wing/tail slice.
3. **kz/b of the full-size airplane** is unknown, so the Dutch-roll comparison assumes equal kz/b. The model's is 0.241.

## Limits

RM L6J25 slopes are approximate (±1°). The comparison is dimensionless across a large Reynolds-number and propeller difference. The body term lumps several physical sources into one coefficient and carries no damping (Cnr). The fade range is the aircraft's existing estimated sideslip blend, not a fuselage measurement. Software verification is not physical validation.

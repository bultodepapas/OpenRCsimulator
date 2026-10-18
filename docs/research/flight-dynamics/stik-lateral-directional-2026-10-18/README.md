# Ugly Stik lateral-directional gates: diagnosis and candidates (2026-10-18)

Status: **research only; no runtime, data or test changes.** Two strict physics programs fail on the default airplane and are the only allow-listed gates that block a stable tag: `test_rudder_authority` (|r| ≤ 15°/s 1.5 s after a rudder doublet) and `test_yaw_damping` (R02: local Cnr within 7 % of a fin-plus-wing-profile estimate over α 0–11°). This record explains both, tests one physical hypothesis against flight-identified aircraft, and evaluates two candidates. Each candidate needs an owner decision before adoption. Scripts are in [`research/flight-dynamics/stik-lateral-directional/`](../../../../research/flight-dynamics/stik-lateral-directional/); outputs are in [`results/`](results/).

## 1. The recovery gate samples an oscillation at one instant

The reference doublet (15 m/s, full rudder right 0.5–1.0 s, left 1.0–1.5 s, then neutral) gives r(3.0 s) = −15.13°/s at 240 Hz and −15.20°/s at 480 Hz, so the result is not a numerical artefact. The mirrored doublet gives +14.22°/s and passes. [`probe.gd`](../../../../research/flight-dynamics/stik-lateral-directional/probe.gd) splits r into the coordinated-turn rate r_turn = (g/V)·sin φ·cos θ and the uncoordinated remainder ([decomposition](results/doublet-decomposition.txt)):

| t, s | φ | β | r, °/s | r_turn | r − r_turn |
| --- | --- | --- | --- | --- | --- |
| 1.5 | 16.3° | 0.4° | −88.2 | 10.7 | −99.0 |
| 2.0 | 4.9° | 17.2° | 43.0 | 3.3 | 39.8 |
| 2.5 | 12.2° | −9.9° | 25.1 | 8.1 | 17.0 |
| 3.0 | 18.5° | 2.7° | −15.1 | 12.1 | −27.2 |
| 4.0 | 14.1° | −1.6° | 6.8 | 8.9 | −2.1 |
| 6.0–12.0 | 16.5° → 29.8° | ≈ 0.3° | 9.8 → 14.8 | ≈ r | ≈ 0 |

- At 3.0 s the airplane is still in a Dutch roll: β changes sign every ≈ 0.67 s and r moves from −20°/s to −6°/s within ±0.1 s of the sample. The verdict depends on the phase.
- The time-domain Dutch roll (0.73–0.75 Hz; half-cycle log decrements ζ 0.21, 0.21, 0.32) matches the linear model (0.744 Hz, ζ 0.247).
- After about 4 s the flight is a coordinated turn in a slowly divergent spiral (linear τ −12.7 s): the bank grows from 16° to 30° and the airplane descends 17 m by 12 s.
- The autorotation the [rudder audit](../../ugly-stik-rudder-audit.md) reported (r 379°/s at 3 s) is gone. The test attributes its 15°/s screen to that audit, but the audit defines only the 25° sideslip screen.

With a 92°/s peak, the 3 s sample stays at about 92·exp(−ζ·ω_n·1.5 s). That is ≈ 15°/s for ζ 0.25 and ≈ 9°/s for ζ 0.32, so the gate effectively asks for the Dutch roll damping of a real airplane.

## 2. Dutch roll and spiral against flight-identified Stik-family aircraft

The [sensitivity comparison](../../../../research/sensitivity/results.md) already compared the model with the University of Minnesota identifications of the Ultra Stick 120 (Froude-scaled to the same CL) and Ultra Stick 25e (Dorobantu et al. 2013). The model's Dutch roll is 1.25–1.45× too fast (nondimensional) and less damped (ζ 0.23–0.25 against 0.31–0.33). Its spiral diverges, while the US120's is stable (τ 4.3 s). For the approximate Dutch roll, ω ∝ √(Cnβ/Izz) and ζ ∝ |Cnr|/√(Cnβ·Izz). A Cnβ that is too high is the one change that moves both the frequency and the damping the wrong way, and the spiral criterion Clβ·Cnr − Cnβ·Clr also loses stability with Cnβ (0.00728 − 0.01384 < 0 now).

## 3. Cause: the isolated fin with unit efficiency

The Stik's `Cnb` = a_v·S_v/S·l_v/b = 0.1274 is the isolated fin ([flight-repair implementation](../../flight-repair-implementation.md)). It omits the fin's sidewash and dynamic-pressure efficiency and the fuselage's destabilizing moment. [`directional_prediction.py`](../../../../research/flight-dynamics/stik-lateral-directional/directional_prediction.py) predicts both terms from the plan geometry alone ([output](results/directional-prediction.txt)):

| Term | Method | Value |
| --- | --- | --- |
| Fin efficiency η_v(1 + dσ/dβ) | USAF DATCOM via Nelson: 0.724 + 3.06·(S_v/S)/(1 + cos Λ) + 0.4·z_w/h + 0.009·AR; high wing, z_w = −0.0595 m (positive down), h = 0.0973 m | 0.684 |
| Fuselage Cnβ | Raymer eq. 16.50: −1.3·Vol/(S·b)·√(h/w), Vol 7.28 L from the nine plan stations | −0.0130 /rad |
| Fuselage Cnβ | Munk slender body, k2 − k1 0.936 (fineness 9.6) | −0.0192 /rad |
| **Predicted total** | 0.684 × 0.1274 + body | **0.068–0.074 /rad** |

For comparison only, the Ultra Stick 25e's OpenFlightSim value is 0.0723 /rad. The script does not use it. [`directional_hypothesis.gd`](../../../../research/flight-dynamics/stik-lateral-directional/directional_hypothesis.gd) changes only the derived in-memory Cnβ ([table](results/hypothesis-modes-and-doublet.md)):

| Variant | Cnβ | Dutch roll at the 25e CL (ω·b/2V ratio, ζ) | Spiral | Doublet β peak / r peak / r(3 s) |
| --- | --- | --- | --- | --- |
| References | — | 1.00×, ζ 0.33 (25e); US120 0.57 Hz ζ 0.31 | stable (US120) | screens 25° / 120°/s / 15°/s |
| Data now | 0.1274 | 1.40×, 0.238 | unstable | 20.4° / 92.6 / −15.13 |
| Predicted, Raymer | 0.0741 | **0.98×, 0.326** | stable | 24.5° / 99.1 / −5.3 |
| Predicted, Munk | 0.0679 | 0.92×, 0.344 | stable | 25.1° / 99.9 / −3.3 |

The independent prediction reproduces the 25e's Dutch roll frequency and damping and changes the spiral to the sign of both references. The references are sister aircraft, not the Jensen airframe; the Dutch roll match is a strong consistency check, not a measurement.

## 4. R02 yaw gate: an induced-operator defect in the local strip law

Below `attached_limit` (8° for the Stik) the airplane flies the coefficient oracle. The local strips take over towards stall, at large sideslip and at high local rates; R02 tests that law. In `Aero._local_loads` and the wake source, a strip's lift is `CL_i = CL0_i + a·Σ_k E_ik·α_k·w_k` with donor weight w_k = (V_k/V_max)·(1 − stall_k). For non-uniform onset speed, lifting-line theory gives Γ_k ∝ u_k·CL_k and an induced angle w_ind,i/u_i, so the exact donor weight is u_k/u_i (the [R11 identity](../../physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/README.md#yaw-damping-verification-and-the-independent-d11f-comparison) g = u·CL). The current weight matches it only for uniform onset, and a yaw rate makes u_i = U − r·y non-uniform. In sideslip it also attenuates induced flow by about cos β.

[Candidate patch](results/candidate-induced-operator.patch) (weight u_k/u_i; no calibration changed). Wing Cnr from production central differences minus the fin terms, against the AVL 3.52 six-panel matched wing (R11):

| α | AVL | Production | Candidate |
| --- | --- | --- | --- |
| 0° | −0.01426 | −0.01459 | −0.01459 (identical bytes) |
| 4° | −0.01404 | −0.01184 (−15.7 %) | −0.01258 (−10.4 %) |
| 11° | −0.01349 | −0.00543 (−59.8 %) | −0.00928 (−31.2 %) |

The candidate passes R02 (4.83 % at α 11°), but it is **not recommended**:

- It corrects one of the five factors R11 listed. The force closure is the larger remainder: R11's D11f Kutta–Joukowski closure on the same CL gives −0.0119, and −0.0135 with matched camber.
- Removing the cos β attenuation also moves the wing's sideslip and cross derivatives. At 10 m/s (local regime) the Dutch roll damping falls from 0.3026 to 0.2825 ([programs](results/aero-programs-candidate-induced-operator.txt)), the opposite of what the flight references ask.
- The coefficient form divides by u_i. A nearly stagnant strip (ground pirouette, a station where U = r·y) receives unbounded CL and a finite induced drag without flow, and can overflow.
- Cruise modes are unchanged ([modes](results/modes-candidate-induced-operator.txt)): the oracle flies cruise.

The robust form keeps the circulation as the unknown: Γ = a₀E(W + u·α₀) uses no division, lift is ρΓu → 0 as u → 0 and induced drag is ρΓw_ind. With Kutta–Joukowski force closure this is the D11f model, within 4 % of AVL at α 11°. That replaces the per-strip whole-aircraft induced-drag parabola, so it is a redesign of the local law across the fleet, not a patch.

## 5. Candidate for the Dutch roll and the recovery gate

The contract already has the opt-in `aero.surfaces.body_cn_beta` used by the P-51 (P51-25). The loader requires Cnb = fin term + body term, and the local law applies the same Munk couple, so both regimes stay consistent without new code. [Candidate patch](results/candidate-body-cn-beta.patch): `body_cn_beta` = (0.684 − 1)·0.1274 − 0.0130 = **−0.0532** and Cnb 0.0742, two leaves, kind `estimated`. Like the P-51's calibrated term, this places the fin-efficiency deficit in the body couple, so the fin's side force and fin-height roll coupling keep efficiency 1.

| Program on the candidate | Result |
| --- | --- |
| `test_rudder_authority` | r(3 s) **9.90°/s** and r peak 79.2°/s pass; β peak **25.42°** fails the 25° screen ([log](results/candidate-body-cn-beta-rudder-test.log)) |
| `test_modes` | All lateral bands move as intended: 15 m/s Dutch roll 0.530 Hz ζ 0.326, spiral stable (λ −0.050); bands need re-recording |
| `test_golden` | `roll_15`, `pull_throttle` and `rudder_doublet` move 0.96–2.4 m; deliberate re-recording needed |
| `test_yaw_damping` | Its "local Cnβ = fin-derived" check must include the body term; R02 unchanged (Cnr is unaffected) |
| `test_aero`, `test_aircraft_data`, `test_aircraft_contract`, `test_damping_regimes`, `test_regime_consistency`, `test_trim`, `test_envelope`, `test_spin`, `test_handling`, `test_sf_law_properties` | Pass ([summary](results/candidate-body-cn-beta-programs.txt)) |

The β peak scales with Cnδr/Cnβ. The rudder sits on the same fin and shares its dynamic-pressure ratio η_v but not the sidewash, while its 25° throw is `estimated`; with η_v 0.9 the peak would be about 23°. The 25° screen is the edge of the model's lateral transition, not a handling requirement. Fleet modes with this candidate: [modes](results/modes-candidate-body-cn-beta.txt).

## 6. Decisions for the owner

1. **Recovery metric.** Replace the single r(3 s) sample with a phase-independent measure, for example the peak uncoordinated yaw rate |r − (g/V)·sin φ·cos θ| over one Dutch roll period after release, or a log-decrement ζ bound tied to the flight-identified band. It needs a deliberately chosen threshold.
2. **Cnβ.** Adopt `body_cn_beta` −0.0532 for the Stik (and regenerate the glow variants through `build_installations.py`), with deliberate golden and band re-recording and a flight-log A/B on the same tape, or wait for the measurements below. Decide the rudder's share of η_v together with it.
3. **R02.** Keep the gate pending. Its resolution is the circulation/Kutta–Joukowski local law validated against AVL for all lateral wing derivatives, a separate plan.

Measurements on the owner's Jensen Stik that would settle the open terms: rudder and aileron throws at the horn (ruler), a hands-off bank-drift flight from 20° bank in calm air (spiral sign and time constant), a filmed rudder doublet (Dutch roll period and decay), and the VAL-6 swing test for Izz and Ixx (the roll inertia ratio is 0.0172 against the 25e's 0.0282).

## Reproduction

From the repository root:

```bash
python3 -I research/flight-dynamics/stik-lateral-directional/directional_prediction.py
G="$(app/get-godot.sh)"
"$G" --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/probe.gd" -- --seconds=12 [--reverse] [--hz=480] [--csv=out.csv]
"$G" --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/directional_hypothesis.gd"
"$G" --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/modes_fleet.gd"
```

Candidates were measured on disposable copies of `app/` with the patches above applied; the copies lack `../assets`, which only `test_controls` reads (it passes 17/17 in the tree).

## Limits

- The references are other airframes compared nondimensionally. DATCOM's empirical sidewash relation and Raymer's body term are conceptual-design estimates; DATCOM vertical-tail side force differs from wind-tunnel data by up to 11 % in the TU Delft comparison, and the high-wing z_w/h of −0.61 is at the edge of typical configurations.
- Propeller slipstream at power can raise the fin's dynamic pressure; neither the data nor this prediction includes it in the oracle.
- No candidate is a physical validation; acceptance stays with the flight measurements above and Gate 2.

## Sources

- R. C. Nelson, *Flight Stability and Automatic Control*, 2nd ed., McGraw-Hill, 1998 (vertical-tail efficiency from USAF DATCOM); z_w sign convention (positive down) confirmed in [Virginia Tech AOE 3134 notes](https://archive.aoe.vt.edu/lutze/AOE3134/YawMoment.pdf); high-wing unfavourable sidewash in [Nicolosi et al., "A comprehensive review of vertical tail design"](https://www.fzt.haw-hamburg.de/pers/Scholz/ewade/2016/Paper_F_Nicolosi.pdf).
- D. P. Raymer, *Aircraft Design: A Conceptual Approach*, 6th ed., AIAA, eq. 16.50, as implemented in [FAST-GA](https://fast-ga.readthedocs.io/en/stable/_modules/fastga/models/aerodynamics/components/fuselage/compute_cn_beta_fuselage.html).
- DATCOM accuracy context: [TU Delft vertical-tail study](https://repository.tudelft.nl/file/File_816fa12f-41dd-4c4f-a618-ebda43c94786).
- Flight identifications and the US120/25e comparison: [sensitivity results](../../../../research/sensitivity/results.md); AVL and D11f references: [R11 diagnosis](../../physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/README.md).

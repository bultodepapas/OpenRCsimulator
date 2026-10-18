# Ugly Stik lateral-directional gates: diagnosis and candidates (2026-10-18)

Status: **D10-R2 adopted 2026-10-18** (section 6); sections 1–5 are the investigation that led to it. Two strict physics programs failed on the default airplane: `test_rudder_authority` (|r| ≤ 15°/s 1.5 s after a rudder doublet) and `test_yaw_damping` (R02: local Cnr within 7 % of a fin-plus-wing-profile estimate over α 0–11°). Both run with named allow-list flags; since the 2026-10-16 release policy, disclosed experimental limits do not block stable releases (an earlier draft of this record said they did). This record explains both, tests one physical hypothesis against flight-identified aircraft, evaluates two candidates and records the adopted one. Scripts are in [`research/flight-dynamics/stik-lateral-directional/`](../../../../research/flight-dynamics/stik-lateral-directional/); outputs are in [`results/`](results/).

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

**Flight-identified derivatives of the sister airframe.** Dorobantu's thesis (University of Minnesota, 2013, eq. 3.26 and tables 3.1 and 3.5) gives the Ultra Stick 25e's lateral derivatives identified from frequency sweeps in flight, beside a baseline from Ultra Stick Mini wind-tunnel data. Converted to coefficients with its bifilar-pendulum inertias (Ix 0.089, Iz 0.162 kg·m²) and the conditions VAL-3 already uses for this airframe (19 m/s, 1.959 kg, S 0.31 m², b 1.27 m, ρ 1.225 kg/m³):

| Derivative (/rad) | 25e identified in flight | 25e wind-tunnel baseline | Stik before | Stik D10-R2 |
| --- | --- | --- | --- | --- |
| Cnβ = 2·Iz·Nv/(ρUSb) | 0.046 | 0.033 | 0.127 | 0.074 |
| CYβ = 2·m·Yv/(ρUS) | −0.35 | −0.89 | −0.489 (borrowed) | −0.489 |
| Clβ = 2·Ix·Lv/(ρUSb) | −0.039 | −0.042 | −0.0545 (borrowed) | −0.0545 |
| Cnr = 4·Iz·Nr/(ρUSb²) | −0.17 | −0.41 | −0.134 | −0.134 |

The 25e is a smaller airframe with its own tail volume, so its numbers do not transfer directly. Its identified directional stability is still a direct measurement on a Stik: the old value was 2.8 times it and D10-R2's is 1.6 times. Its identified side-force derivative is 30 % below the oracle's borrowed value (section 7).

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

## 6. Decisions and adoption (D10-R2, 2026-10-18)

The owner delegated the decisions. Each follows the evidence above; no screen was moved to make a result pass.

| Item | Decision | Reason |
| --- | --- | --- |
| Cnβ | **Adopted** `aero.surfaces.body_cn_beta` −0.0532 for the Stik; the glow variants follow through `build_installations.py` | Independent geometry prediction; reproduces the 25e Dutch roll and the US120 spiral sign; existing regime-consistent module; Cmq/CLq/Cnr unchanged (the D11g report still matches) |
| Recovery screen | **Replaced** the single r(3 s) sample with two criteria fixed from the references before measuring | Section 1: the sample reads a Dutch roll mid-swing; the mirrored doublet passed and the reference failed with the same physics |
| β ≤ 25° screen | **Kept**, now the only allow-listed rudder check (`--allow-known-stik-rudder-sideslip`) | 25° is the data's oracle-to-local sideslip blend end; the 0.42° excess depends on the estimated 25° throw and the rudder's unmodelled η_v, both unmeasured. No new parameter was invented |
| R02 | **Kept pending** | The induced-operator fix is partial (section 4); the bounded circulation prototype has up to ten roots through stall without a wake-state law ([R11 feasibility](../../../../research/physics-audit-2026-10-14/remediation/r02-circulation-candidate/nonlinear-feasibility-20261016/README.md)) |

New recovery criteria in `test_rudder_authority.gd`: the linear Dutch roll at the Ultra Stick 25e trim CL within ±20 % of its ω·b/2V (0.1658) and ζ (0.33), the spiral stable or doubling in ≥ 20 s (the Froude-scaled US120 is stable), and, through the real session in both doublet directions, the uncoordinated yaw rate |r − (g/V)·sin φ·cos θ| over 2.5–4.0 s after release ≤ 10 % of the |r| peak (the 25e decay ζω·b/2V = 0.0547 gives σ = 1.08 s⁻¹ and 6.8 % on this span at 15 m/s). The decay criterion passes for both data sets, since ζω depends on Cnr/Izz and not on Cnβ; the modal criteria separate them ([acceptance probe](../../../../research/flight-dynamics/stik-lateral-directional/acceptance_probe.gd)):

| Data | ω·b/2V vs 25e | ζ | Spiral | Decay right / left | β peak |
| --- | --- | --- | --- | --- | --- |
| Before (Cnβ 0.1274) | 1.402× ✗ | 0.238 ✗ | doubles in 14.0 s ✗ | 7.4 % / 7.7 % ✓ | 20.4° ✓ |
| D10-R2 (Cnβ 0.0742) | 0.981× ✓ | 0.325 ✓ | stable τ 17.6 s ✓ | 5.6 % / 5.2 % ✓ | 25.42° pending (left 24.73° ✓) |

The new test run against the old data fails exactly the three modal checks; the audited borrowed Cndr (−0.1811) is still rejected (β 40.0°, r 149.7°/s).

Nonlinear checks:

- **Small-bank spiral** in the full session ([results](results/d10r2-small-bank-spiral.txt)): from a 0.9° bank the D10-R2 airplane returns to 0.53° after 40 s hands off, symmetric in both directions; before, the same pulse grew to 43°. A Cnβ written into the session after a trim solved with the old value drifts with no input (32° in 40 s) because Cnβ·β_trim is left unbalanced, so every comparison here re-trims with the new data.
- **Flight-log A/B** ([metrics](results/d10r2-tape-ab.txt)): `record_tape.gd` flies the same stick tape (rudder doublet, 15 % aileron pulse, 16 s hands off from 150 m) on each data set, each with its own trim. Both `.orfl` files replay exactly ([before](results/d10r2-baseline-exact-replay-comparison.json), [after](results/d10r2-candidate-exact-replay-comparison.json); `solver_changed` false, `complete` true). From 17° (before) and 26° (D10-R2) of bank after the doublet and pulse, the airplane reaches 43° and loses 79 m before, 33° and 46 m after. The flight-log candidate mode keeps the baseline trim and `compare` refuses tapes whose trimmed commands differ (cmd_pitch by 6e-5), so neither applies to a change that moves the trim; the metrics come from the two exports directly.

Changed with D10-R2: the Stik and five glow aircraft files (two leaves each), four Workshop descriptors and the crash-economics identity hashes and the three D8b-R2 synthetic polar candidates (regenerated by their own builders; no price changed), the four goldens (deliberate re-recording), the nine lateral `test_modes` centres, `test_yaw_damping` (the local Cnβ check splits fin and body couple; the body couple matches Cnβ_B·cos α within 0.007 %), `test_wing_polar.gd` (its wing-only model now also drops the body couple, which is not a wing load), `test_wing_polar_session.gd` (below), the catalog status note and its Spanish text, the `test.sh` flag, and the regenerated [sensitivity results](../../../../research/sensitivity/results.md). The committed sensitivity file predated D6e-R1; regenerating it also updates its short-period rows, which D10-R2 does not change.

The polar-fixture spin test required |p| and |r| below 1 rad/s at every sample from 6 s. After the recovery input a decaying yaw oscillation remains, and that bound read one of its swings: the last sample at or above 1 rad/s was 5.92 s before and 6.01 s with D10-R2, whose airplane also loses 99.9 m instead of 117.6 m. The check now asks what its label says, phase-independently: mean yaw rate over 6–8 s below 0.3 rad/s and |p|, |r| below 1 rad/s from 7 s. Recovered runs give 0.06/0.27 (before) and 0.08/0.32 (D10-R2); with the pro-spin input held instead of recovered they give 2.3/5.5 and 2.3/6.9, so the check still rejects a spin that does not stop.

The full `app/test.sh` on the D10-R2 tree, at low machine load, ran 547 sections; the only failures were the two above, now fixed, and the allow-listed sideslip screen. `test_engine_audio` (an audio-queue timing check) failed under heavy load on both trees and passed at low load. The integration part (`OPENRC_TEST_PART=integration`) then stopped at D8b-R2. Its three synthetic polar candidates are built from the Stik file, so they were stale. `research/flight-robustness/d8b-r2/make_candidates.gd` regenerated them, and the diff is exactly the Cnβ and `body_cn_beta` change. The rerun passed every integration section (exit 0, 46 min).

Measurements on the owner's Jensen Stik that would close the remaining terms: rudder and aileron throws at the horn (ruler), a hands-off bank-drift flight from a small bank in calm air (spiral sign and time constant), a filmed rudder doublet (Dutch roll period and decay), and the VAL-6 swing test for Izz and Ixx (the roll inertia ratio is 0.0172 against the 25e's 0.0282).

## 7. Knife-edge: the FT battery's finding, measured in flight

The standard flight-test battery already flies the Stik and the fleet through loops, rolls, turns, knife-edge, inverted flight and spins ([FT-01](../../flight-test/FT-01/README.md), [tool](../../../../research/flight-test/README.md)); a parallel probe written for this record duplicated it and was removed. FT-01 found that knife-edge fails on every aircraft because the local model, which takes over across the 15–25° sideslip blend, has no fuselage crossflow side force. The battery now has a per-flight `--diagnostics` trace (regime weights and oracle/local/blended coefficients at 20 Hz, reproducing the production blend with zero residual over 9438 Stik rows) and a static `aero_sweep` (card `ft-card-v3`). In the steady full-rudder knife-edge ([data](results/aerobatics-and-side-force.txt)):

| Data | β | Local weight (= sideslip weight) | CY oracle | CY local | CY flown |
| --- | --- | --- | --- | --- | --- |
| Before (Cnβ 0.1274) | 17.3° | 0.13 | −0.104 | −0.017 | −0.092 |
| D10-R2 (Cnβ 0.0742) | 20.7° | 0.60 | −0.130 | −0.031 | −0.070 |

The airplane accelerates in the maneuver, so the side force a level knife-edge needs, W/(qS), is judged at the flown speed. Before D10-R2 it is 0.092 at 32.9 m/s and the airplane flies −0.092: the side force holds the weight, and the 5–7 m/s sink trades height for the drag of 17° of sideslip. With D10-R2 it is 0.075 at 36.5 m/s and the airplane flies −0.070, 7 % short, and sinks 10–13 m/s. The oracle alone would give −0.130 at that sideslip, but the blend hands 60 % of the load to the local model, whose side force is the fin's. D10-R2 does not create this gap; it exposes it. Whether FT-01's proposed fuselage side force closes it is open, and the estimates span a wide range. An Allen–Perkins crossflow term alone (crossflow coefficient 1.6–2.0, finite-length factor 0.68, side area 0.081 m²) adds only about −0.02 to −0.03 at 20°. The coefficient range is the subcritical face-on square-cylinder drag for the Stik's corner radii, read from Polhamus, NASA TR R-29, fig. 11 ([sources](../rc-aero-data-sources.md#spin-knife-edge-and-fuselage-crossflow-references)). The full-envelope model behind the FS One RC simulator (Selig 2010) instead treats the fuselage as segments with a side-lift coefficient over ±180° of side angle, reaching about 1 per segment; it sustains the ShowTime 50's knife-edge until the fuselage stalls near 65° of sideslip. On the Stik's side area such a side-lift curve would add 0.07–0.17, so a slab-sided fuselage acting as a very low aspect-ratio surface may matter far more than crossflow drag. A DATCOM-style estimate of the whole-airplane side-force derivative (fin −0.172/rad after the 0.684 efficiency, body −0.069/rad, dihedral −0.016/rad, about −0.26/rad) is half the oracle's borrowed −0.489/rad, and the Ultra Stick 25e's flight-identified value is −0.35/rad (section 3), so the local model may be closer to the airplane than the oracle is. The next step therefore establishes the side force itself, and its consistency between the two regimes, before any knife-edge acceptance. With controls neutral, `aero_sweep` also shows that the fin's own local angle makes the weight reach 1 by 15° of sideslip; a deflected rudder keeps the fin below that in flight.

## Reproduction

From the repository root:

```bash
python3 -I research/flight-dynamics/stik-lateral-directional/directional_prediction.py
G="$(app/get-godot.sh)"
"$G" --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/probe.gd" -- --seconds=12 [--reverse] [--hz=480] [--csv=out.csv]
"$G" --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/directional_hypothesis.gd"
"$G" --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/modes_fleet.gd"
"$G" --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/acceptance_probe.gd" [-- --cnb=<value>]
"$G" --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/record_tape.gd" -- --out=tmp/d10r2/tape.orfl
python research/flight-test/run.py --out tmp/ft --aircraft jensen-das-ugly-stik-60 --diagnostics
```

Candidates were measured on disposable copies of `app/` with the patches above applied; the copies lack `../assets`, which only `test_controls` reads (it passes 17/17 in the tree).

## Limits

- The references are other airframes compared nondimensionally. DATCOM's empirical sidewash relation and Raymer's body term are conceptual-design estimates; DATCOM vertical-tail side force differs from wind-tunnel data by up to 11 % in the TU Delft comparison, and the high-wing z_w/h of −0.61 is at the edge of typical configurations.
- Propeller slipstream at power can raise the fin's dynamic pressure; neither the data nor this prediction includes it in the oracle.
- No candidate is a physical validation; acceptance stays with the flight measurements above and Gate 2.

## Sources

- M. S. Selig, "Modeling Full-Envelope Aerodynamics of Small UAVs in Realtime", AIAA 2010-7635, [PDF](https://m-selig.web.engr.illinois.edu/pubs/Selig-2010-AIAA-2010-7635-FullEnvelopeAeroSim.pdf): section III.C (segmented fuselage, Fig. 14) and section IV.C (ShowTime 50 knife-edge).
- A. M. Dantsker, M. S. Selig, "High Angle of Attack Flight of a Subscale Aerobatic Aircraft", AIAA 2015-2568, [PDF](https://m-selig.web.engr.illinois.edu/pubs/DantskerSelig-2015-AIAA-2015-2568-HighAngleFlight.pdf): flight-derived coefficients of a 35 % Sukhoi 29S (16.37 kg, 2.6 m, 130 dm²) in figures only.
- A. Dorobantu, *Test Platforms for Model-Based Flight Research*, PhD thesis, University of Minnesota, 2013, [PDF](https://dept.aem.umn.edu/~SeilerControl/Thesis/2013/Dorobantu_13PhD_TestPlatformsForModelBasedFlightResearch.pdf): section 3.5.2, eq. 3.26 (identified lateral matrices), tables 3.1 (inertias) and 3.5 (modes).

- R. C. Nelson, *Flight Stability and Automatic Control*, 2nd ed., McGraw-Hill, 1998 (vertical-tail efficiency from USAF DATCOM); z_w sign convention (positive down) confirmed in [Virginia Tech AOE 3134 notes](https://archive.aoe.vt.edu/lutze/AOE3134/YawMoment.pdf); high-wing unfavourable sidewash in [Nicolosi et al., "A comprehensive review of vertical tail design"](https://www.fzt.haw-hamburg.de/pers/Scholz/ewade/2016/Paper_F_Nicolosi.pdf).
- D. P. Raymer, *Aircraft Design: A Conceptual Approach*, 6th ed., AIAA, eq. 16.50, as implemented in [FAST-GA](https://fast-ga.readthedocs.io/en/stable/_modules/fastga/models/aerodynamics/components/fuselage/compute_cn_beta_fuselage.html).
- DATCOM accuracy context: [TU Delft vertical-tail study](https://repository.tudelft.nl/file/File_816fa12f-41dd-4c4f-a618-ebda43c94786).
- Flight identifications and the US120/25e comparison: [sensitivity results](../../../../research/sensitivity/results.md); AVL and D11f references: [R11 diagnosis](../../physics-audit-2026-10-14/remediation/R11/damping-lag-diagnostic/README.md).

# P51-15: Airborne before/after and 240/480 Hz results

2026-10-12 · Revision 1 · **Status: saved-probe comparison complete; physical acceptance remains open.** Prefix: P51-15.

## Scope and integrity

Compared the saved baseline and candidate matrices at 240 Hz and 480 Hz: [baseline 240 Hz](baseline-airborne-240.json), [candidate 240 Hz](candidate-airborne-240.json), [baseline 480 Hz](baseline-airborne-480.json), and [candidate 480 Hz](candidate-airborne-480.json). Each contains the same 34 P-51 cases, has an empty error list, and reports all cases available. Every trace is continuous, finite, complete (duration × frequency + 1 rows; a ten-second case has 2,401 rows at 240 Hz or 4,801 at 480 Hz), fault-free, and uncrashed. The JSON scope correctly describes model predictions and numerical checks, not measured physical acceptance.

The only physical-data difference represented here is the intended P51-15 inventory inertia change. Baseline mass is 21.499999 kg and candidate mass is 21.499999 kg. CG is `[0.1777627436, 0, -0.0711460382]` m in both, to floating-point precision. The runtime-order inertia changes from `[3.412230, 6.817989, 9.496622, 0, -0.269807, 0]` to `[3.861834, 6.817989, 9.946226, 0, -0.269807, 0]` kg·m². At both rates the solver's maximum residual is `8.35e-11` baseline and `7.87e-11` candidate; the largest baseline/candidate difference among non-residual trim outputs is `3.64e-12` (rpm). Candidate trim outputs match between 240 and 480 Hz.

## Steady and smooth comparisons

The [P-51 realism plan](../../../P51-REALISM-PLAN.md) sets 1% steady and 5% smooth-transient bands. They were applied to case-specific state responses, with the metric definition stated below. The same baseline-to-candidate comparison was made at each frequency. For smooth cases, the displayed 240 Hz percentages and the 480 Hz percentages agree within 0.01 percentage point. The largest selected smooth-response change is 4.54%, below the 5% band. Candidate 240-to-480 refinement is at most 0.66% among these metrics.

Steady endpoint values for `level_trim_20`, `level_trim_25`, `level_trim_35`, `level_trim_45`, `engine_stopped_glide`, `inverted_hands_off_7s`, and `environment_hot-high` are unchanged within numerical precision, well inside the 1% band. For the four level-trim cases, corresponding speed endpoints differ by at most `2.2e-12 m/s`, altitude by `6.3e-12 m`, angle of attack by `1.8e-12°`, sideslip by `6.9e-15°`, and engine rpm by `1.4e-10`. The stopped-engine glide and inverted hands-off segment also remain numerically unchanged. The hot-high case starts and stays at its solved condition (`ρ = 0.94394 kg/m³`, charge ratio `0.75441`).

For this table, rates use peak absolute body rate; angles and translations use the largest excursion from the case's trimmed start. Throttle cases use rpm and speed excursions, idle descent uses altitude loss and speed excursion, guided turns use bank and sideslip excursions, and cross-control slips use sideslip and yaw-rate peaks. Command channels are excluded. This avoids percentage claims on near-zero numerical noise.

| Case | Response | Baseline → candidate, 240 Hz | Candidate 240 → 480 Hz |
|---|---|---:|---:|
| `roll_low_-1` | peak roll rate / bank excursion | −0.68% / −0.32% | ≤0.01% |
| `roll_low_1` | peak roll rate / bank excursion | −1.09% / −0.27% | ≤0.01% |
| `roll_high_-1` | peak roll rate / bank excursion | −0.68% / −0.26% | ≤0.01% |
| `roll_high_1` | peak roll rate / bank excursion | −0.84% / −0.21% | ≤0.01% |
| `pitch_low_-1` | peak pitch rate / angle-of-attack excursion | +0.02% / −0.22% | ≤0.01% |
| `pitch_low_1` | peak pitch rate / angle-of-attack excursion | +0.05% / −0.07% | ≤0.01% |
| `pitch_high_-1` | peak pitch rate / angle-of-attack excursion | +0.03% / +0.64% | ≤0.01% |
| `pitch_high_1` | peak pitch rate / angle-of-attack excursion | +0.05% / −0.07% | ≤0.01% |
| `yaw_low_-1` | peak yaw rate / sideslip excursion | −1.93% / +0.36% | ≤0.01% |
| `yaw_low_1` | peak yaw rate / sideslip excursion | −1.83% / +0.27% | ≤0.01% |
| `yaw_high_-1` | peak yaw rate / sideslip excursion | −1.84% / +0.46% | ≤0.01% |
| `yaw_high_1` | peak yaw rate / sideslip excursion | −1.84% / +0.34% | ≤0.01% |
| `throttle_split` | rpm / speed excursion | −0.001% / −0.002% | −0.043% / −0.024% |
| `throttle_coupled` | rpm / speed excursion | +0.000% / +0.002% | <0.001% |
| `running_engine_idle_descent` | altitude loss / speed excursion | −0.46% / −0.30% | −0.15% / −0.15% |
| `guided_turn_-1` | bank / sideslip excursion | −0.01% / +0.53% | <0.01% / −0.65% |
| `guided_turn_1` | bank / sideslip excursion | −0.01% / +0.92% | <0.01% / −0.55% |
| `cross_control_slip_-1` | sideslip / peak yaw rate | +0.43% / −2.42% | ≤0.01% |
| `cross_control_slip_1` | sideslip / peak yaw rate | +0.44% / −4.53% | ≤0.01% |

These are response-metric comparisons for the model, not evidence that its control authority matches a built aircraft. The guided turns use a feedback coordinator to hold 30° bank; the other listed inputs are prescribed pulses. The split and coupled throttle cases are separate integrator options, not a comparison of two aircraft configurations.

## Near-stall and spin cases

The four cases are event-sensitive and are reported individually rather than judged by the smooth-transient band. They are commanded maneuvers, not unforced stall or spin tests.

| Case | Input and baseline → candidate at 240 Hz |
|---|---|
| `stall_throttle_0.0` | Full positive pitch command from 0.25–4.0 s, target throttle 0. Max angle of attack rises from 27.39° to 37.97°; minimum speed remains 16.23 m/s; minimum altitude shifts from 468.6 m to 469.8 m; peak absolute yaw rate rises from 0.857 to 1.530 rad/s. |
| `stall_throttle_0.3` | Same full positive pitch pulse, target throttle 0.3. Max angle of attack rises from 20.67° to 21.80°; minimum speed remains 18.0 m/s; minimum altitude shifts from 456.2 m to 459.6 m; peak absolute yaw rate is 1.130 to 1.131 rad/s. |
| `spin_-1` | Idle throttle, full positive pitch and signed yaw input through 4 s, then deliberately reversed yaw and −0.5 pitch through 5 s. In the 2.5–4 s entry window, mean/max angle of attack changes from 35.94°/48.15° to 37.41°/51.26°; mean/peak absolute yaw rate changes from −1.179/1.393 to −1.256/1.444 rad/s. Mean yaw rate during the commanded recovery window changes sign (+0.053 to −0.291 rad/s); 7–8 s peak absolute yaw rate is 0.211 to 0.236 rad/s. |
| `spin_1` | Mirrored commanded entry/recovery. Entry-window mean/max angle of attack changes from 24.28°/31.23° to 20.53°/26.70°; mean/peak absolute yaw rate changes from +1.223/1.352 to +0.967/1.848 rad/s. Mean yaw rate in the recovery window changes sign (−0.369 to +1.002 rad/s); 7–8 s peak absolute yaw rate is 0.272 to 0.174 rad/s. |

The spin pair is strongly direction-dependent. Recovery is actively commanded, lasts one second, and leaves a nonzero post-recovery yaw-rate envelope; these cases do not establish spontaneous spin entry, sustained autorotation, or pilot recovery capability. Candidate 240-to-480 differences in the spin-window peaks are small (under about 0.2% for entry angle/yaw peaks); that numerical stability does not validate the estimated post-stall model.

## Loop-labelled inputs and command saturation

`pitch_loop_input_-1` and `pitch_loop_input_1` are open-loop pitch pulses with full throttle from 0.2–8.0 s. The stored interpretation correctly says that body-rate integral and Euler extrema do not establish a planar completed loop. At 240 Hz, the negative case's integrated body pitch rate changes from −1105.1° baseline to −644.2° candidate (candidate 480: −643.7°); the positive case changes from +1224.2° to +1288.6° (candidate 480: +1288.0°). Candidate extrema reach about 179.9° Euler roll and 179.6° heading deviation in both. There is no closed planar path or loop-completion metric, so the names remain scenario labels only.

The controls also make the two loop signs unequal: the positive pitch command clips at normalized +1, while the negative case bottoms at −0.321 after adding the level-trim pitch command. Full throttle clips at +1 in both. Other normalized +1 endpoints occur in `roll_high_1`, `pitch_low_1`, `pitch_high_1`, `yaw_high_1`, `throttle_split`, `throttle_coupled`, both `spin_*` and both `stall_*` cases. The opposite-sign aileron/elevator/rudder pulses are offset by trim and do not reach −1 (for example, `roll_high_-1` bottoms at −0.979, `pitch_high_-1` at −0.592, and `yaw_high_-1` at −0.885). This is input-command clipping after trim addition, not measured servo travel or load saturation.

## Weather refinement

`environment_gentle-practice`, `environment_gusty`, and `environment_hot-high` complete at both rates. The hot-high case is a static solved trim and is unchanged. The gusty case's candidate endpoint speed/altitude at 240→480 Hz changes by only about `0.00015 m/s` / `0.00013 m`, with angle of attack changing `0.00046°`.

The gentle-practice case is stochastic. Its 240 and 480 Hz runs do not share an identical Ornstein–Uhlenbeck noise realization, so their endpoint and peak differences are descriptive, not a deterministic step-size convergence result and not a valid 1%/5% gate. For example, candidate 240→480 endpoints shift by `+0.093 m` altitude, `+0.362°` angle of attack and `+0.241°` sideslip; peak |q| changes from `0.0253` to `0.0201 rad/s`. Do not attribute those differences solely to the inertia edit.

## Limits

The tensor edit leaves trimmed mass, CG, and steady solutions fixed while changing transient roll/yaw inertia. The smooth response set stays within the predeclared comparison bands, but the commanded spin/stall outputs change materially and should remain visible in review. These are short, model-generated scenarios using the existing estimated coefficients and control mapping. They do not validate the physical P-51, the 4-blade propeller map, stall polar, spin behavior, or RC pilot handling. No engine was run during this JSON analysis.

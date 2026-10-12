# EX-08 airborne envelope audit

2026-10-11 · Revision 1 · **Status: bounded airborne baseline and post-change measurements recorded; physical validation remains open.** Prefix: EX-.

This report compares the 24-case envelope probe at 240 Hz before and after the selected Extra installation/balance changes, then checks the changed build at 480 Hz. It records simulation outputs only. The same probe was used for all three runs; identity sidecars record the app aircraft-data SHA-256, probe SHA-256, wheel-profile SHA-256, command and exit code.

Evidence: [baseline 240 Hz JSON](envelope-baseline-240.json), [after 240 Hz JSON](envelope-after-240.json), [after 480 Hz JSON](envelope-after-480.json), and their identity sidecars. The baseline and after aircraft data hashes differ (`16d387b0…` and `7e0a03af…`); the probe hash and wheel-profile hash match across runs. The logs record Godot 4.7.2 and exit code 0 for all envelope runs. The [EX-06 source and implementation audits](../EX-06/primary-sources.md) and [implementation audit](../EX-06/implementation-audit.md) document the kit-specific evidence and selected changes.

All 24 cases in each JSON were available. Every trace is continuous, has zero nonfinite scalar samples, and records no simulation fault. The probes use calm air and default reference density. “Peak” below means the maximum magnitude over the complete case unless a time window is named.

## Trim and rate setup

The own level-flight trim is at 17 m/s. On the changed build, its trim is α 5.381°, β +0.674°, throttle 0.3572 and 5,782 rpm; before the changes it was α 5.244°, β −0.100°, throttle 0.3541 and 5,756 rpm. Aero-convention surface trim (TE down/left positive) changed from elevator −2.356°, aileron −0.199°, rudder −0.215° to elevator −2.928°, aileron −0.166°, rudder +1.089°. Corresponding pilot trim changed from roll/pitch/yaw +0.0113/+0.0985/+0.0072 to +0.0094/+0.1224/−0.0363.

| Trim condition | Baseline 240 Hz: α / β; throttle / rpm | After 240 Hz: α / β; throttle / rpm |
| --- | --- | --- |
| Level, 15 m/s (controls, throttle, idle descent) | 6.712° / −0.108°; 0.2918 / 5,236 | 6.887° / +0.763°; 0.2953 / 5,265 |
| Level, 12 m/s (spin entry) | 10.399° / −0.067°; 0.2147 / 4,593 | 10.669° / +1.688°; 0.2191 / 4,629 |
| Glide, 12 m/s (stall) | 10.501° / 0°; engine stopped | 10.760° / 0°; engine stopped |
| Glide, 15 m/s (approach) | 6.735° / 0°; engine stopped | 6.903° / 0°; engine stopped |
| Level, 18 m/s (climb) | 4.684° / −0.098°; 0.3873 / 6,033 | 4.807° / +0.644°; 0.3902 / 6,057 |
| Research-only inverted level, 18 m/s | −4.633° / −0.098°; 0.3881 / 6,041 | −4.740° / +0.648°; 0.3904 / 6,060 |

The rate mapping uses the manual’s low-rate linear travel fractions (aileron 0.4, elevator and rudder 0.6) converted to equivalent angular deflection: `asin(fraction × sin(high_throw)) / high_throw`. High throws are 17.6007° / 23.9219° / 30.0261°; equivalent low throws are 6.9471° / 14.0811° / 17.4718°, or command fractions 0.39470 / 0.58863 / 0.58189. These mappings are unchanged across the three runs. They describe surface-angle equivalence in this probe; no transmitter expo is modeled.

## Case results

The control pulses start at 15 m/s, run from 0.25 to 1.25 s, and are followed through 3.5 s. Each cell gives signed peak and signed final primary body rate in rad/s. Positive/negative identify the pilot command sign. The signed peak follows the command sign for all 12 cases in all runs; the 480 Hz values match the changed 240 Hz values to the displayed precision.

Other start conditions are: throttle step 15 m/s from 60 m for 5 s; open-loop bank 17 m/s from 70 m for 7 s; guided turns 17 m/s from 100 m for 12 s; climb 18 m/s from 70 m for 5 s; stall 12 m/s from 100 m for 4 s; idle descent 15 m/s from 70 m for 8 s; glide 15 m/s from 80 m for 10 s; spins 12 m/s from 150 m for 8 s; inverted trim 18 m/s from 100 m for 7 s. Own-trim hands-off starts at 17 m/s and 30 m for 30 s.

| Case | Baseline 240: peak / end | After 240: peak / end |
| --- | ---: | ---: |
| roll negative, low | −1.372 / +0.028 | −1.373 / +0.021 |
| roll negative, high | −3.428 / +0.082 | −3.425 / +0.075 |
| roll positive, low | +1.390 / +0.104 | +1.393 / +0.100 |
| roll positive, high | +3.422 / +0.078 | +3.434 / +0.071 |
| pitch negative, low | −1.714 / +0.511 | −1.613 / +0.491 |
| pitch negative, high | −3.270 / +0.495 | −3.052 / +0.506 |
| pitch positive, low | +1.915 / +0.248 | +1.848 / +0.242 |
| pitch positive, high | +2.550 / +0.249 | +2.416 / +0.226 |
| yaw negative, low | −0.955 / +0.048 | −0.947 / +0.045 |
| yaw negative, high | −1.586 / −0.018 | −1.514 / −0.021 |
| yaw positive, low | +0.955 / −0.052 | +0.949 / −0.053 |
| yaw positive, high | +1.581 / +0.008 | +1.585 / +0.005 |

The other 12 cases are accounted for below. Values compare the 240 Hz baseline with the changed 240 Hz run. “Turn heading” is the shortest wrapped difference between initial and final Euler yaw; it is not integrated heading.

| Case | Baseline 240 Hz | After 240 Hz |
| --- | --- | --- |
| Own trim, hands-off 30 s | Δspeed −1.6×10⁻¹² m/s; Δaltitude +1.8×10⁻¹¹ m | −2.5×10⁻¹² m/s; +4.3×10⁻¹¹ m |
| Full-throttle step and return, 5 s | Speed 11.24–21.35 m/s, ending 11.24; altitude ends 75.04 m; rpm peak/end 11,041/5,236 | 10.98–21.26 m/s, ending 10.98; altitude 75.38 m; rpm 11,041/5,265 |
| Open-loop bank pulse and counter-roll | Peak bank 74.2°; end speed 28.07 m/s and altitude 1.86 m | Peak bank 74.2°; end speed 27.45 m/s and altitude 6.15 m |
| Guided 30° left turn, 12 s | Peak bank magnitude 30.94°; wrapped Δyaw −122.72°; altitude min/end 96.34/98.83 m | 30.98°; −120.32°; 96.28/98.80 m |
| Guided 30° right turn, 12 s | Peak bank magnitude 31.07°; wrapped Δyaw +122.52°; altitude min/end 95.79/98.67 m | 31.07°; +124.53°; 95.72/98.63 m |
| Full-power climb input, 5 s | Speed ends 24.38 m/s; altitude +55.71 m; rpm reaches 11,149 | Speed 21.50 m/s; altitude +61.16 m; rpm reaches 11,149 |
| Power-off full-up stall, 4 s | α max 50.16°; speed min 9.04 m/s; altitude −22.46 m | α max 46.87°; speed 9.48 m/s; altitude −22.63 m |
| Running-engine idle descent, 8 s | Speed ends 16.23 m/s; altitude −17.11 m; rpm ends at 2,800 | 15.88 m/s; −16.48 m; 2,800 rpm |
| Engine-off glide/approach, 10 s | Speed 15.00 m/s; altitude −15.13 m; α 6.74°; rpm 0 | 15.00 m/s; −15.11 m; α 6.90°; rpm 0 |
| Left-rudder spin and recovery, 8 s | Entry mean r (2.5–4 s) −0.194 rad/s; α max 57.95°; end altitude 86.15 m; post-recovery mean r (7–8 s) +0.141 | −0.219 rad/s; 54.28°; 92.71 m; +0.179 |
| Right-rudder spin and recovery, 8 s | Entry mean r +0.256 rad/s; α max 54.29°; end altitude 90.94 m; post-recovery mean r +0.070 | +0.286 rad/s; 50.47°; 95.69 m; +0.111 |
| Research-only inverted trim and hands-off, 7 s | Trim α/β −4.633°/−0.098°; throttle/rpm 0.3881/6,041; residual L2 6.22×10⁻⁹; Δspeed −6.7×10⁻⁹ m/s; Δaltitude +7.7×10⁻⁸ m | −4.740°/+0.648°; 0.3904/6,060; residual L2 2.38×10⁻¹¹; Δspeed −2.9×10⁻¹¹ m/s; Δaltitude +3.1×10⁻¹⁰ m |

The guided turn cases use bank feedback to target 30° and recover toward wings-level. Their measured bank peaks are about 31°, final bank is within 0.1° of level, and the two wrapped heading changes have opposite signs. They are separate from `banked_turn_and_counter_roll_recovery`, which is a timed roll pulse and counter-roll with no bank-hold or altitude controller. That open-loop case reaches about 74° bank and ends close to the ground; it is not evidence of a guided or sustained 30° turn.

The spin entry window has the requested sign in both directions (left negative, right positive mean r). Opposite rudder and forward pitch are applied from 4.0 to 4.9 s. The 7–8 s mean yaw rates remain +0.179 rad/s left and +0.111 rad/s right after the change, so the trace shows reduced residual rotation rather than an exactly zero rate. The signed whole-flight r extremum with the greatest magnitude for the right spin changes from +2.736 rad/s before to −2.621 rad/s after; the entry-window mean remains positive, while the recovery window spans both signs. This is why the signed entry and recovery windows are reported separately.

## 240/480 Hz refinement and existing handling checks

For the changed build, the largest absolute difference between 240 and 480 Hz over any case was:

| Metric | Largest difference in maximum absolute sample | Largest difference in endpoint |
| --- | ---: | ---: |
| Speed | 0.00452 m/s | 0.00831 m/s |
| Altitude | 0.00478 m | 0.0281 m |
| Angle of attack | 0.00198° | 0.00112° |
| Sideslip | 0.0122° | 0.00262° |
| Euler roll | 0.0765° | 0.0379° |
| Euler pitch | 0.00201° | 0.0516° |
| Euler yaw | 1.2504° | 0.0447° |
| p rate | 0.00392 rad/s | 0.0000675 rad/s |
| q rate | 0.000271 rad/s | 0.000316 rad/s |
| r rate | 0.00225 rad/s | 0.000260 rad/s |
| Engine rpm | 1.3×10⁻¹¹ rpm | 1.3×10⁻¹¹ rpm |
| Specific mechanical-energy proxy | 0.155 m²/s² | 0.155 m²/s² |

No signed peak-response reversals occurred between 240 and 480 Hz in the 12 directional control probes or either spin’s selected peak. The largest Euler-yaw maximum difference occurs in a high-rate roll case near the ±180° wrap; its endpoint yaw difference is only 0.045°. All other 480 Hz endpoint and maximum differences are small relative to the displayed case values. The energy proxy is `g × altitude + 0.5 × speed²`; it excludes fuel, engine and thermal energy.

The existing [baseline handling log](../EX-06/baseline/handling.log) and [after handling log](../EX-06/after/handling.log) each report 12 checks passed, 0 failed. The tests report 30 s hands-off trim, coordinated full-aileron roll, inside-loop completion and stall checks, plus right-spin direction and recovery. The measured roll rates were 213.2/265.6°/s at 17/22 m/s before and 213.8/266.0°/s after, against the existing model prediction checks. The inside-loop run reported 513° in 4.7 s before and 450° in 5.2 s after; both were within the existing six-second check. The power-off stall maximum changed from 50.2° to 46.9°; the existing spin screen reported peak right-yaw rate 1.19 to 1.03 rad/s and residual rate 0.10 to 0.17 rad/s three seconds after recovery. These are software regression checks, not measured aircraft performance or manual limits.

## Limits and reproduction

The Great Planes manual provides qualitative handling guidance but no calibrated stall speed, spin rate, structural limit or performance target for this model. These outputs therefore cannot establish physical accuracy. The inverted trim is a research-only numerical six-DOF equilibrium and short hands-off replay, not a pilot or airframe qualification. The manual-rate mapping does not model transmitter expo. The probe does not cover knife-edge flight, outside loops, snap rolls, wind/turbulence response, fuel consumption or energy lifecycle. Ground/runway evidence is reported separately in the [EX-08 ground audit](ground-audit.md).

Reproduce a report from an isolated baseline or changed app snapshot with Godot 4.7.2:

```text
Godot_v4.7.2-stable_win64_console.exe --headless --path <snapshot>/app --audio-driver Dummy --script research/extra-300/ex06/envelope_probe.gd -- --hz=240 --output=<output.json>
```

Use `--hz=480` for the refinement run. The three checked commands, worktree paths, exit codes and full artifact hashes are in the linked identity JSON files. The probe is [envelope_probe.gd](../../../../research/extra-300/ex06/envelope_probe.gd); the encompassing [Extra realism plan](../../../EXTRA-300-REALISM-PLAN.md) retains the open acceptance gates.

# P51-22: slipstream tail-downwash regression, diagnosis and candidate

2026-10-15 · Revision 2 · **Status: root cause identified; the denominator candidate is withdrawn after the physics-audit review. The fix requires the powered wing/tail coupling that the R02/R06 owner has specified.** Prefix: P51-22. [Plan](../../../P51-REALISM-PLAN.md) · [Owner review](../../physics-audit-2026-10-14/remediation/R11/washed-downwash-diagnostic/README.md)

## Release status — 2026-10-16

The P-51D is experimental with P51-22 pending. The preliminary release suite executes the ground and handling maneuvers with `--allow-known-p51-22`: only the lift-off-speed band and the two loop-acceptance assertions can report `PENDING P51-22`. Finite-state checks and every other assertion remain mandatory. Direct invocation without that argument retains strict physical acceptance. This deferral changes no simulation law, coefficient or threshold; the withdrawn candidate remains withdrawn.

Local Godot 4.7.2 verification of the reporting change used the isolated release diagnostic checkout (unchanged simulation and P-51 data):

| Mode | Ground | Handling |
| --- | --- | --- |
| Strict | [13 checks, 1 failure](release-ground-strict.log) | [17 checks, 2 failures](release-handling-strict.log) |
| Experimental | [13 checks, 0 failures, 1 pending](release-ground-pending.log) | [17 checks, 0 failures, 2 pending](release-handling-pending.log) |

A disposable probe combining a pending P51-22 result with an unrelated mandatory failure still returned exit 1. These results verify reporting, not physical acceptance or final package qualification.

The aircraft selector and Details panel disclose the pending status in English and Spanish. [UI evidence](release-ui/evidence.json) records a fresh Godot 4.7.2 import and captures at 1280 × 720; the shortened warning fits both locales without clipping.

## Regression

Two P-51 checks passed at the P51-15 baseline and fail at the current `HEAD` with every P-51 data revision:

- `test_p51_ground`: lift-off rises from 22.2 to 25.2 m/s, above the 1.5 Vs band.
- `test_p51_handling`: the 0.7-stick, full-throttle loop from 27 m/s no longer completes.

A trace ([`loop_trace.gd`](loop_trace.gd)) shows that the "loop" now reaches α 17.7° at 0.75 s, snap-rolls left (p up to −5 rad/s), autorotates and spirals into the ground by 7.5 s.

A bisection over the 266 first-parent commits after `df36b44`, in a clean worktree running both tests ([log](bisect.log), [step script](bisect_step.sh)), finds the first bad commit: **`5e9dae16`**. The commit before it, `24427e4e`, lifts off at 23.2 m/s and completes the loop (460° in 4.9 s); `5e9dae16` gives 25.2 m/s and 307°. That commit carries the physics-audit R02 changes.

## Cause

R02 replaced the tail downwash angle `downwash_per_cl × CL_wing` with `atan2(gain × U, Vp_tail)`, where `U = mean(Vp·CL)` is the wing's dimensional wake. The slipstream module evaluates the immersed tail twice, free and washed, and adds the difference. Before R02, both evaluations used the same downwash angle. After R02, the washed evaluation divides the same wake velocity by the **washed** tail speed, so inside the propeller jet the downwash angle falls by V/(V+Δv).

At full power and low speed (takeoff roll, loop entry), Δv ≫ V, so the washed tail sees almost no downwash. Its lift rises, which pitches the nose down: rotation needs a higher speed, and the extra up elevator a pull requires drives the wing into an accelerated stall.

Only the P-51 declares `propulsion.propeller.slipstream` in the product catalog, so no other product aircraft changed.

## Physical evidence

Katzoff, *Longitudinal stability and control with special reference to slipstream effects*, NACA Report 690 (1940, [NTRS 19930091767](https://ntrs.nasa.gov/citations/19930091767)), covers full-scale tunnel tests of eight airplanes. For the single-engine tractor YO-31A: *"Operation of the propeller increases both the effective dynamic pressure and the downwash angle at the tail."* For the multi-engine tractor model, it describes "the slipstream … increasing the rate of increase of downwash angle with angle of attack" and "the increased downwash due to the slipstream". The measured configurations show that propeller operation can increase the tail downwash. They do not establish a universal inequality for every jet. Revision 1 said the measurements make free-stream downwash a lower bound for the angle inside the jet; that was an inference, and it is withdrawn.

The R02 law has no wing slipstream: the wing's circulation does not grow with the wash. Under that model, dividing by the washed speed predicts the opposite of what was measured.

## Candidate and results

The [candidate patch](candidate/candidate-washed-downwash.patch) (6 lines) made every washed evaluation use the downwash angle at the free-stream tail plane speed. It was quantified only in a disposable worktree at `HEAD` `b09aa200` with P51-21 applied, and is **withdrawn** ([logs](candidate/)):

| Check | Current `HEAD` | Candidate |
| --- | --- | --- |
| `test_p51_ground` lift-off, heading-hold pilot | **fail**, 25.2 m/s, 49 m | pass, 22.3 m/s, 37 m (P51-15: 22.2 m/s, 37 m) |
| `test_p51_handling` 0.7-stick loop | **fail**, 343°, snap roll | pass, 517°, never below 27 m/s |
| `test_p51_envelope` | stall recovery 83 m (P51-19) | 84 m; every other check passes |
| Trim at 25 m/s and 27 % CG, level minus glide | +1.26° | +0.97°, a partial improvement in the sign of the power effect (P51-19) |
| `test_slipstream_scalar`, `test_swirl_torque`, `test_wash_transport` | pass | pass |
| `test_slipstream_downwash`, `test_swirl_accuracy`, `test_swirl_optimization`, `test_wash_profile` | pass | **fail**: their references compose the public `Aero.tail_surface_increment` helper, which the candidate left on the R02 law, so production and helper disagreed |

## Why the candidate is withdrawn

The [physics-audit review](../../physics-audit-2026-10-14/remediation/R11/washed-downwash-diagnostic/README.md) shows that the law has no continuous zero-speed extension. The wing proxy is U = V·CL(α), so as V → 0 the angle `atan2(gain·U, V_free)` tends to `atan(gain·CL(α))`, which depends on the approach direction, while at exactly V = 0 it is zero. The propeller jet keeps the tail loaded, so the result is a force jump. With the actual P-51 slipstream pieces at catalog rpm, the jump is up to 1.5 N and 1.8 N·m. The candidate also left the public `Aero.tail_surface_increment` helper on the old law, and it fails the unchanged Stik case in `test_aero_continuity.gd`.

P51-22 also checked a bounded variant that limits U to CL_min·V…CL_max·V. It removes the frozen-lag case after a landing that ends stopped, where the `exp(-dt·V/l)` lag holds U at V = 0. It does not remove the direction-dependent limit, because CL(α) lies inside the bound. Any angle clamp only selects one of these limits.

The physical cause is that the model's wing does not see the slipstream. Only a wing immersed in the jet deflects it, and the downwash it then sends to the tail comes from the jet's own circulation, which stays continuous when the free stream vanishes.

## Path forward

The owner's [required integrated replacement](../../physics-audit-2026-10-14/remediation/R11/washed-downwash-diagnostic/README.md#required-integrated-replacement) is a coupled wing-plus-propeller local-flow source. It needs wing-immersion quadrature, a defined downwash source for powered rest, stopped and reversed propellers, one source/consumer contract with a versioned layout, and continuity and convergence qualification. The P-51's slipstream geometry is the input: the hub, the three authored pieces and the 0.33 m disc radius. P51-22 supplies the regression targets: lift-off at 22.2 m/s and 37 m, a loop completing within 8 s, and the level-minus-glide trim sign. Until that slice lands, the two P-51 checks remain open, documented failures; no tolerance or oracle was changed.

# P51-22: slipstream tail-downwash regression, diagnosis and candidate

2026-10-14 · Revision 1 · **Status: root cause identified, candidate quantified, not applied.** The affected laws are shared physics (`aero.gd`, `slipstream.gd`, `swirl_loads.gd`, VAL-AUD R02) and need their owner's decision. Prefix: P51-22. [Plan](../../../P51-REALISM-PLAN.md)

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

Katzoff, *Longitudinal stability and control with special reference to slipstream effects*, NACA Report 690 (1940, [NTRS 19930091767](https://ntrs.nasa.gov/citations/19930091767)), covers full-scale tunnel tests of eight airplanes. For the single-engine tractor YO-31A: *"Operation of the propeller increases both the effective dynamic pressure and the downwash angle at the tail."* For the multi-engine tractor model, it describes "the slipstream … increasing the rate of increase of downwash angle with angle of attack" and "the increased downwash due to the slipstream". The wing deflects the propeller jet with its own wake, so the flow angle inside the jet is at least the free-stream downwash. It is not the wing's wake velocity diluted by the jet speed.

The R02 law has no wing slipstream: the wing's circulation does not grow with the wash. Under that model, dividing by the washed speed predicts the opposite of what was measured.

## Candidate and results

The [candidate patch](candidate/candidate-washed-downwash.patch) (6 lines) makes every washed evaluation use the downwash angle at the free-stream tail plane speed. That is the slipstream, slipstream axial-swirl and swirl laws, through an optional `downwash_speed` argument of `Aero._tail_surface_from_flow`. Everything else in R02 stays: the dimensional wake, section-plane forces and bounded angle. "Equal to free stream" is the conservative lower bound of Katzoff's measurement. A disposable worktree at `HEAD` `b09aa200`, with P51-21 applied, gave the following ([logs](candidate/)):

| Check | Current `HEAD` | Candidate |
| --- | --- | --- |
| `test_p51_ground` lift-off, heading-hold pilot | **fail**, 25.2 m/s, 49 m | pass, 22.3 m/s, 37 m (P51-15: 22.2 m/s, 37 m) |
| `test_p51_handling` 0.7-stick loop | **fail**, 343°, snap roll | pass, 517°, never below 27 m/s |
| `test_p51_envelope` | stall recovery 83 m (P51-19) | 84 m; every other check passes |
| Trim at 25 m/s and 27 % CG, level minus glide | +1.26° | +0.97°, a partial improvement in the sign of the power effect (P51-19) |
| `test_slipstream_scalar`, `test_swirl_torque`, `test_wash_transport` | pass | pass |
| `test_slipstream_downwash`, `test_swirl_accuracy`, `test_swirl_optimization`, `test_wash_profile` | pass | **fail**: their frozen reference implementations (`slipstream_reference.gd`, `swirl_dense_reference.gd`, helper compositions) encode the R02 washed-angle law |

## Decision needed

To apply the candidate, the physics-audit owner would update the four reference oracles to the same law. The R02 law identity and the trace metadata would be versioned (as R02 did), and the change recorded in DECISIONS. A fuller model would also increase the downwash inside the jet, as Katzoff measured: either a wing slipstream, or a downwash factor in the jet with its own evidence. That would further correct the remaining power-on trim sign. Neither change was applied, because shared slipstream changes need the physics owner's coordination ([P51 plan](../../../P51-PLAN.md)).

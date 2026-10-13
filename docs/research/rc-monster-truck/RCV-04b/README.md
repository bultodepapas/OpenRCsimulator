# RCV-04b: coupled four-corner support

**Date:** 2026-10-13. **Scope:** continue useful implementation and testing while the external Blender model is prepared. The [active plan](../../../plans/rc-monster-truck.md) owns remaining work; the [bench guide](../../../../research/rc-monster-truck/README.md#rcv-04b-four-corner-support) owns equations, interfaces and runnable commands. This report is a dated software-verification record.

## What landed

A float64 seven-DOF vertical rig couples sprung-body heave, roll and pitch to four vertical unsprung masses. Its 14-state layout uses a fixed small-angle mount Jacobian, disjoint body/hub masses, passive springs/dampers and unilateral elastic tire contact. It uses two RK4 substeps per public tick without changing the aircraft solver. A strict separate profile loader verifies units/provenance, geometry, finite numbers and static support feasibility.

The equilibrium solver distributes load through the four elastic supports and rejects an impossible all-contact solution. Zero gravity has an explicit neutral planar branch. The research runner provides heave, roll, pitch, front-left support lift and drop experiments, identified CSV/JSON exports and optional kernel timing. Fresh output paths prevent an old success sidecar from accompanying a failed new run. Direct numerical and real-process tests cover malformed input, named experiment identities, runtime envelope failure, output integrity and reproducibility.

Three Luna Max agents implemented/reviewed bounded kernel, loader and independent-reference/CLI-test paths. The lead integrated the work, wrote numerical tests and runner, reviewed mechanics, recorded verification and updated the canonical test hooks. No car mesh, menu, aircraft dynamics or generated aircraft data was changed by this RCV work.

The sole shared verification-tool fix changes the transcendental scanner's reported relative paths to POSIX form. Its isolated negative-control test previously searched for `physics/injected.gd` while native Windows printed a backslash path. The one-line formatting fix restores that existing test without changing scanning rules. The previous bare `log` violation in lake physics was resolved by another concurrent track; it is not an RCV fix.

## Numerical evidence

The independent Python reference builds `K = k_s C^T C + K_t` and `D = c_s C^T C` from four spring-extension rows, with diagonal generalized mass. It propagates the 14-state linear system with a matrix exponential, independently of the GDScript RK4. It checks the static equations, semigroup consistency, positive contact load and undamped perturbation energy. It is a synthetic oracle, not a measured RC truck.

- Maximum static generalized force/moment residual: **4.33e-14** in the corresponding N/N·m components.
- Maximum relative thirds-semigroup residual: **9.463e-12**.
- Undamped reference relative energy drift over 5,001 samples: **3.174e-12**.
- Minimum sampled reference corner normal load: **12.442314 N**.

The implementation comparisons use the maximum error over all 14 states and five reference times, normalized by 1 m, 1 rad, 1 m/s or 1 rad/s according to the channel. Before the first run, the coarse/fine limits were fixed at 2e-3/2e-6; separate position/angle limits were 2e-5/2e-8 in the corresponding unit. These are engineering test budgets for this synthetic profile, not physical error bounds.

| Public Hz | Internal RK4 Hz | Damped max normalized error | Undamped max normalized error |
| --- | --- | --- | --- |
| 240 | 480 | 1.496423e-5 | 4.732781e-4 |
| 480 | 960 | 7.367104e-7 | 2.553201e-5 |
| 960 | 1920 | 3.946337e-8 | 1.451490e-6 |
| 1920 | 3840 | 2.25612e-9 | 8.59582e-8 |

All acceptance limits pass without retuning parameters or widening tolerances. Smooth refinement ratios approach 16 (damped 20.31, 18.67, 17.49; undamped 18.54, 17.59, 16.89). The separate maximum 240 Hz generalized-position errors were 7.679754e-8 damped and 5.559018e-6 undamped. This combines metre/radian channels after normalization; it is not a claim that every angular error is a displacement in metres.

Other checks establish:

- Equal static corner support and force/moment equilibrium; forward-CG axle loads agree with the lever-arm law; left/right axle loads remain symmetric.
- Symmetric heave matches the existing quarter-car trajectory; it does not create roll/pitch. The reported maximum comparison difference rounded to zero at the test's displayed precision.
- A front-left support lift raises the left side and nose; front-right excitation produces the mirrored response.
- Translating all supports and masses at constant vertical velocity preserves the solution after changing reference frame.
- Internal suspension forces cancel in total vertical momentum. Four support-work terms minus damper loss match the local mechanical-energy derivative, with residual **3.435e-9 W** in the selected check.
- Undamped coupled perturbation-energy drift at 1920 public Hz is **1.461097e-7 relative**, below 1e-4.
- Same-build repeated state is byte-identical, and input arrays remain unmodified.
- Zero-gravity neutral plane equilibrium succeeds; a nonplanar saddle and malformed road input are refused.

The 30 mm drop separates and reacquires contact and stays finite at all four rates. No positive per-public-tick energy gain was observed in that test. Independent trapezoidal integration of damper power bounds the accumulated energy/work residual to less than 0.5% of initial energy above equilibrium. Observed relative residuals are **9.25015e-5, 2.20512e-5, 1.62243e-5, 1.43158e-6** at 240/480/960/1920 public Hz. Endpoint normalized errors versus 1920 Hz are 6.05364e-7 at 240 and 1.18466e-7 at 960. No fourth-order claim is made across contact transitions or for the trapezoidal work quadrature.

## Reproducibility and checks

[Verification receipt and relevant source hashes](verification.json), [native output](verification.log), and [timing records](performance.json) identify the checked working-tree snapshot. The repository was dirty and shared with concurrent tracks; Git HEAD alone does not identify the source used. No aircraft golden fixture was regenerated. Commands are in the [bench guide](../../../../research/rc-monster-truck/README.md#run-four-corner-experiments).

The focused verification includes parsing the new scripts, both oracle-freshness checks, the existing 83-check quarter-car suite, the new 111-check support suite, both CLI suites (6 and 8 test methods), four existing golden flights, the float64 guard, global transcendental routing and the scanner's isolated negative control. A focused fresh clone with `core.autocrlf=true` checks the new profile/reference byte identity and generator imports/freshness. It is not a fresh clone of the complete application.

The complete `app/test.sh` suite, native Linux execution, menus/rendering and exported game packages are outside this run. Only checks explicitly recorded in the receipt are claimed. The runner's public-sample angle limit is tested with a deliberately tiny roll inertia on a disposable profile; it stops without a success sidecar. Timing on/off and repeated runs produce identical CSV state/force bytes.

## Timing and remaining limits

The timing records contain serial runs of heave, front-left support lift and drop, in that order, at 240 public Hz for five seconds each. Each run warms a separate state for 240 ticks and then measures 1,200 full `Rig.step` calls including both RK4 substeps and all stage road queries. Telemetry, CSV, rendering and application/session work are excluded. RCV agents had finished runtime work; other activity on the shared workstation was not controlled. Per-run median/p95/p99/max and public contact-change tick costs are recorded in microseconds, without a pass/fail hardware threshold.

| Scenario | Median µs | p95 µs | p99 µs | Maximum µs | Contact-change ticks / maximum µs |
| --- | --- | --- | --- | --- | --- |
| Heave | 65 | 125 | 158 | 377 | 0 / not applicable |
| Front-left support lift | 67 | 110 | 158 | 240 | 0 / not applicable |
| Drop | 65 | 116 | 139 | 324 | 3 / 104 |

These observations do not qualify the plan's complete-vehicle 500-microsecond target. A full truck still needs tire spin/traction, steering, drivetrain, collision broadphase, contact manifolds, session/checkpoint work and representative hardware testing. Kernel cost is an early diagnostic only; optimization decisions should preserve the numerical gates.

This rig can study coupled suspension and static support, but cannot establish full 6DoF rollover, finite-radius obstacle contact, dynamic unsprung inertia transport, or jump attitude control. Its x-forward/y-left/z-up frame is a local bench frame, not the aircraft or Blender binding contract. Changing the CG lever arms in the test does not perform a real ballast/inertia update. RCV-04 and RCV-05 remain partial/pending as specified in the active plan; production mechanics and art integration remain separate gates.

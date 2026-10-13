# RCV-04a: independent suspension bench

**Date:** 2026-10-13. **Scope:** first implementation slice authorized while the external Blender developer prepares the truck. This is a reduced numerical bench, not a playable car or a complete RCV-04 gate. The [active plan](../../../plans/rc-monster-truck.md) owns status; [bench guide and commands](../../../../research/rc-monster-truck/README.md) own operation and equations.

Three Luna Max agents implemented/reviewed bounded parts: the quarter-car kernel, independent Python oracle, and headless experiment runner. The lead implemented the strict data contract and tests, integrated the pieces and verified the resulting code. An independent review prompted an additional moving-road trajectory test. No Blender scene or aircraft mesh was edited.

## Delivered boundary

- Four-value packed-float64 vertical state with separate sprung/unsprung masses, bilateral spring, passive damper, unilateral elastic tire, gravity, equilibrium and energy accounting.
- Strict, fail-closed `openrc-suspension-bench` v1 input with finite numbers, exact fields/units, provenance, positive mass/rates and feasible static sag. It is intentionally separate from the planned full `openrc-ground-vehicle` contract.
- Two fixed RK4 substeps per public tick, using only the shared integrator's existing `axpy`; the shared aircraft integrator, state/session and catalog are unchanged by RCV.
- Release, drop and prescribed vertical road-lift experiments, sampled CSV plus identified JSON summary. The profile hash and validation use the same input-byte snapshot.
- Reproducible independent linear reference, numerical/negative tests, CLI tests and additive standard test-runner hooks.

The synthetic parameters do not establish a truck mass inventory, suspension hardpoints, material coefficients, powertrain choice, real tire calibration or Blender geometry. There are no steering, longitudinal tire, rollover, body-contact, menu, rendering, controller, sound or checkpoint implementations in this slice. No performance or physical acceptance gate is closed.

## Numerical protocol and findings

The reference uses the matrix exponential of the linear two-mass system about static equilibrium. The implementation uses time-domain RK4; the reference generator does not. It checks its semigroup consistency and undamped perturbation energy, and samples tire load densely to ensure the linear contact branch remains applicable. Minimum sampled reference tire load was **12.233177 N**; maximum relative thirds-semigroup residual was **1.397e-11**; maximum relative undamped reference energy drift was **2.089e-12**.

The primary error is the maximum of position errors divided by 1 m and velocity errors divided by 1 m/s, over all four state values and times 0.05, 0.1, 0.25, 0.5 and 1 s. Before the first run, the 240/1920 Hz limits were fixed at 2e-3/2e-6. Subsequent review added stricter separate position limits of 20 micrometres at 240 Hz and 20 nanometres at 1920 Hz. These are software acceptance limits for the selected synthetic profile, not manufacturer tolerances.

**Initial failure and correction:** one RK4 step per 240 Hz tick produced an undamped error of **6.044768e-3**, exceeding the fixed 2e-3 limit. The profile and that limit were retained; the kernel now takes two fixed equal substeps at every public rate. This is evidence for this bench configuration only, not proof that two substeps suffice for a complete truck or arbitrary edited parameters.

| Public tick rate | Internal RK4 rate | Damped maximum normalized error | Undamped maximum normalized error |
| --- | --- | --- | --- |
| 240 Hz | 480 Hz | 1.141907e-5 | 3.437950e-4 |
| 480 Hz | 960 Hz | 5.744982e-7 | 1.848294e-5 |
| 960 Hz | 1920 Hz | 3.125006e-8 | 1.048539e-6 |
| 1920 Hz | 3840 Hz | 1.80372e-9 | 6.242588e-8 |

Smooth refinement ratios trend toward 16: damped 19.88, 18.38, 17.33; undamped 18.60, 17.63, 16.80. Worst 240 Hz position errors were 0.054876 micrometres damped and 4.077118 micrometres undamped. Undamped energy drift at 1920 public Hz was **6.010609e-8 of initial perturbation energy**, below 1e-4.

Static equilibrium, translated equilibrium, exact free fall while separated, equal-and-opposite suspension loading, passive damping, state immutability, stage timestamps, and byte-identical same-build repeats pass. A translating road/mass trajectory gives the same solution after removing the imposed constant translation velocity; this exercises actual road-height values at RK stages. A local finite-difference check verifies road work minus damper dissipation equals the mechanical-energy derivative.

Contact events have a separate budget and no fourth-order claim. The 50 mm drop separates and reacquires contact at all four rates, remains finite, and has maximum per-public-tick energy gain below **1 mJ**. Observed positive gains were 18.8644 microjoules at 240 Hz and 19.3806 microjoules at 960 Hz; the other two rates had no positive sampled-tick gain. These are small numerical contact-crossing errors, not physical energy sources. Endpoint errors versus 1920 public Hz were 1.15558e-5, 2.66312e-7 and 1.25318e-7 at 240/480/960 Hz. This verifies the selected reduced drop, not a full-vehicle landing.

## Verification record

[Machine-readable receipt and source hashes](verification.json) and [native output](verification.log) identify the checked snapshot. The workspace was shared and dirty; unrelated tracks changed source throughout the task. The recorded Git commit alone does not describe the working tree. Raw-byte source hashes identify the relevant files and golden fixtures; no aircraft golden was regenerated.

| Check | Observed result |
| --- | --- |
| Godot 4.7.2 parse of both new physics scripts, numerical test and research runner | Pass |
| Numerical/data-contract test | **83 checks, 0 failed** |
| Real-process CLI suite | **6 test methods pass**, including three scenarios, all refinement rates, deterministic output, malformed inputs and profile/output collision refusal |
| Independent fixture generator `--check` | Pass |
| Focused fresh Git clone with `core.autocrlf=true` | Profile and fixture bytes preserved; generator `--check` passes |
| Existing four aircraft golden flights | **4 pass**, auxiliary/discrete state included; worst position difference 4.2633e-14 m |
| Float64 guard over all physics/sim scripts | Pass |
| Transcendental guard scoped to new ground-vehicle scripts | Pass |
| Existing global transcendental guard | Fails on pre-existing `app/physics/lake_surface.gd:497`, a bare `log(ratio)` |
| Existing guard self-test on native Windows | Fails because emitted `physics\\injected.gd` is compared with a POSIX `physics/injected.gd` expectation |

The two existing guard issues were diagnosed and left outside this track. The complete `app/test.sh` suite and Linux runtime were not run; no all-project-green claim is made. The fresh-clone check above covers the two new identified JSON artifacts and their generator, not a whole-application fresh-clone acceptance run.

A manual run of the documented two-second, 240 Hz drop command exported **481 finite samples**, including 438 contact samples; the maximum sampled contact force was **44.361055 N**. CSV/JSON exports are reproducible local outputs, not committed measurement datasets or truck calibration evidence.

## Remaining gates

RCV-04 remains open for mechanical layout/variable inertia selection, half-car and full-body comparisons, complete momentum accounting and complete-tick performance. RCV-01 baseline/envelope decisions and RCV-03 full vehicle schema are also open. Next work can use this bench to constrain four-wheel support and suspension tests while independently preparing the session/catalog seam; the Blender asset is required later for visual integration, not for these numerical checks. The chosen electric powertrain in the plan remains a recommendation, not a newly inferred user selection.

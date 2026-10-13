# HELI-04-R1 — Dimensional transient inflow reference

This note qualifies a small independent Python reference for transient induced velocity. It is a numerical comparison for the chosen approximation, not physical validation and not a claim that the simulator's runtime event detector or helicopter session is ready.

## Model and source limits

The literal Johnson steady mean-inflow law remains the target. Its C = 0.75 and M = 0.95 branches retain their source discontinuities. The added state is dimensional induced velocity, `vi_mps`, positive down the wake axis for positive thrust:

```text
dvi/dt = (target_mps - vi_mps) / tau_s
tau_s  = 0.849 R / (4 max(Veff, Vfloor))
Veff   = hypot(crossflow_mps, vi_mps + climb_mps)
```

The fixed-flow cases pass their declared effective speed directly to the lag law. `Vfloor` is positive, so the lag remains finite at zero rotor speed and residual wake can decay toward zero. The normalized `lambda = vi/(omega R)` is an output diagnostic; `vi_mps` is the integrated state.

Gavrilets, Mettler and Feron's hover relation is `tau_lambda = 0.849/(4 lambda_trim Omega_mr)` (their §4.1.1, Eq. 1). Substituting `lambda_trim Omega_mr = vi/R` gives the dimensional hover form `0.849 R/(4 vi)`. This reference extends that hover relation by replacing trim induced speed with a stage-dependent effective-flow magnitude and adding a floor. That extension is a selected first-order model approximation: it is neither the Johnson steady law nor a transient law validated by Johnson.

Chen and Hindson's NASA TM-88327 compares linearized Carpenter–Fridovich and Pitt–Peters dynamic-inflow models against helicopter transient and frequency-response measurements. Those models include inflow and flapping modes and show response behavior such as collective-step overshoot. They provide primary evidence that real dynamic inflow is richer than a single scalar lag; they do not validate this reference's flow-dependent time constant or floor. The chosen lag should remain provisional until model-to-data or an appropriate flight-response comparison is completed.

## Reference and oracle

`research/helicopter/reference/dynamic_inflow.py` provides `derivative(vi_mps, target_mps, radius_m, effective_speed_mps, velocity_floor_mps)` and the stage-coupled `evaluate(...)`. Returned rates use m/s² and time constants use seconds. `evaluate` gets the equilibrium target from the existing literal Johnson reference, then computes `Veff` from the current induced-velocity state and flight flow.

`dynamic_oracle.json` uses schema `openrc-dynamic-inflow-oracle-v1`. It contains six fixtures and 102 samples total, with 17 entries per fixture. Each fixture has its constants, dimensional initial state, forcing profile, known event metadata, and samples containing `time_s`, `expected_vi_mps`, and diagnostic `expected_lambda`. The profiles include:

- an exact hover target step at 0.0173 s with fixed effective flow;
- increasing and decreasing sweeps through C = 0.75 at 0.0373 s, with `z = -1.428` and instability disabled;
- increasing and decreasing sweeps through M = 0.95 at 0.03873 s, with `z = -1.3` and instability enabled;
- a smooth feedback-flow ramp that exercises stage-dependent `Veff`.

The C and M crossing times do not align with the 240 Hz tick. Their JSON event records preserve the normalized epsilon and left/right target limits, so a consumer can reproduce one-sided endpoint inputs without replacing the literal source branches. The step event is also serialized with its exact before/after target values. `make_dynamic_oracle.py` regenerates the JSON and supports `--check`.

For the trajectories, the independent reference predicts the midpoint state and integrates each frozen-coefficient first-order lag by its exponential convolution at 10 μs intervals; known discontinuities split its microsteps. The target-step fixture uses the closed-form exponential directly. A 5 μs refinement agrees with the 10 μs path within 1e-6 m/s for the worst seam and feedback cases.

## Numerical qualification

The error measure is maximum absolute `vi_mps` difference at each integrator's own output ticks against the dense reference. The tolerance is 1e-3 m/s. Seam-sweep results are:

| Path | Peak error | Result |
| --- | ---: | --- |
| RK4 at 240 Hz, unsplit | 0.01155635 m/s | Fails |
| RK4 at 480 Hz, unsplit | 0.01021960 m/s | Fails |
| RK4 at 960 Hz, unsplit | 0.00053260 m/s | Passes |
| RK4 at 240 Hz, exact known seam splits | 0.00105767 m/s | Fails narrowly |
| RK4 at 240 Hz with localized refinement | 0.00037627 m/s | Passes for these prescribed events |

The worst case is the decreasing M seam. The raw 240 Hz path does not meet the stated tolerance; the gate remains open for ordinary 240 Hz integration. Exact known-event splitting alone also misses. The localized procedure refines only macrosteps intersecting `[event - h, event + h]`: neighboring affected ticks use four equal RK4 substeps, and the crossing tick is split at the exact event, with each half divided into two equal substeps. Each affected tick therefore uses at most four RK4 substeps (16 RHS evaluations), with one-sided target inputs at the event. For the step fixture, splitting at its declared 0.0173 s forcing change reduces the 240 Hz error to 2.35e-6 m/s; omitting that discontinuity produces 0.00617688 m/s error.

The 480 Hz and 960 Hz aggregate unsplit results include the target-step fixture. Their non-monotonic peak errors (0.03426380 and 0.02889901 m/s) come from RK4 stages straddling the known forcing jump; they show why a prescribed step must also be split. The table above isolates the Johnson seam sweeps, while `qualification.per_fixture` in the JSON keeps the step and each seam's errors visible separately.

The seam procedure is supplied the exact crossing time and side values from each fixture. It measures an integration strategy only; it does not demonstrate automatic state-dependent seam detection, behavior under simultaneous controls, or 14-state session integration. The full-session readiness gate remains separate.

Run the independent checks with:

```powershell
python -m unittest discover -s research/helicopter/reference -p test_dynamic_inflow.py -v
```

The tests cover finite zero-flow decay, sign symmetry, the analytic step response, dense-reference refinement, literal seam values, raw and split RK4 error, local refinement, event metadata, and deterministic oracle generation. Passing these checks establishes numerical consistency of this reference and fixture set only.

## Sources

1. V. Gavrilets, B. Mettler, and E. Feron, “Dynamic Model for a Miniature Aerobatic Helicopter,” §4.1.1, Eq. 1. [Paper PDF](https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf). The repository's source notes also link the [MIT thesis record](https://dspace.mit.edu/handle/1721.1/17609).
2. R. T. N. Chen and W. S. Hindson, *Influence of Dynamic Inflow on the Helicopter Vertical Response*, NASA TM-88327 (1986). [NASA report record](https://ntrs.nasa.gov/citations/19870015049) · [PDF](https://ntrs.nasa.gov/api/citations/19870015049/downloads/19870015049.pdf).

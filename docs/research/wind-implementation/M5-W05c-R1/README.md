# M5-W05c-R1 — Station airflow and unwashed aerodynamic gradients

2026-10-25. Second P0 slice of the [advanced wind masterplan](../../../advanced-wind-atmospheric-physics-masterplan.md), following the [position/time adapters](../M5-W05b-R1/README.md). **Experimental kernel verified in software; no spatial scenario or live flight path is enabled.** The [wind guide](../../../WIND-PLAN.md) owns current product behavior.

## Delivered boundary

The new [`WindAircraftFlow`](../../../../app/physics/wind_aircraft_flow.gd) samples the existing environment at six wing stations, the horizontal and vertical tails, and an optional propeller hub or turbine intake. [`Aero.ambient_spatial_loads`](../../../../app/physics/aero.gd) converts the wing/tail ambient differences into a force/moment correction through the existing local aerodynamic laws. This establishes the load calculation needed before spatial weather can enter flight sessions.

The implementation changes two runtime files, adds two focused test scripts, and leaves generated aircraft data, session wiring, weather configuration and accepted load-law identity unchanged. There is no new dependency, weather multiplier, direct wind force, attitude disturbance or shared-kernel vehicle branch.

| Contract | Inputs and output | Ownership and limits |
| --- | --- | --- |
| `WindAircraftFlow.geometry(model)` | Normalized aircraft → flat float64 FRD metre arms and station indices | Six existing left-to-right wing stations, horizontal tail, vertical tail, optional propulsion point. Geometry validation rejects malformed/nonfinite points. |
| `WindAircraftFlow.sample(state, model, environment, time_s)` | Full supplied body stage, normalized model, `wind_world` provider, finite nonnegative seconds → detached arrays | Samples datum O and every point at the same time. Returns positions/winds in NED, relative velocity/ambient deltas in FRD, indices, `uniform`, law and errors. No cache, random draws, weather evolution or state mutation. |
| `Aero.ambient_spatial_loads(state, air, controls, model, rho, deltas, wake=NAN, ground_up=NAN)` | Existing normalized aero inputs plus exactly eight ambient-delta triples → `ok`, six loads, six deltas, law, uniform flag and diagnostics | Loads are `[Fx,Fy,Fz,Mx,My,Mz]`, N and N·m in the same body datum as `Aero.loads`. Exclude the hub/intake triple. On refusal there are errors and **no usable partial loads**. |

The station bundle law is `m5-w05c-r1-fixed-datum-station-relative-flow-v1`; the experimental load helper law is `matched-unwashed-station-delta-v1`. These are diagnostic algorithm identifiers, not admitted weather formats or a change to recorded `Aero.LOADS_LAW`.

### Coordinates and stage consistency

Let O be the existing authored rigid-body datum, `r_i` its FRD station arm, `R(q)` the repository's supplied-stage body-to-NED quaternion transform and `W(x,t)` NED air transport velocity:

```text
x_i          = x_O + R(q) r_i
v_air,O      = Air.compute(state, W(x_O,t)).v_air
delta_v_i    = R(q)^T [W(x_O,t) - W(x_i,t)]
v_air,i      = v_air,O + omega × r_i + delta_v_i
```

All state and calculations use float64 scalars/packed arrays. The sampler uses the stage quaternion as supplied, matching `Air.compute`, rigid-body derivatives and ground-effect geometry. It does not normalize an intermediate RK stage independently; normalization belongs to the existing integrator's accepted-step boundary. For a slightly nonunit stage quaternion the notation `R^T` means the repository's conjugate-quaternion operation, preserving its numerical convention rather than introducing a different rotation mid-stage.

Wing/tail points reuse `Aero._arm` and normalized authored positions. Propulsion `offset` and `intake_offset` are already relative to O but use `[aft,right,up]` axes; convert to `[-x,y,-z]` without subtracting `cg_le` again. A changing fuel/battery mass datum does not move these authored points. This module does not shift the final wrench to a live mass center; existing force ownership must perform its usual conversion once.

`relative_body` is diagnostic complete local flow. **Only `delta_body` belongs in the aero helper:** passing complete point velocity would duplicate ground velocity and `omega × r`. Identical station/datum wind components produce exact zero deltas, retaining the uniform-field limit without extra subtraction/rotation roundoff. Returned buffers are detached from caller/provider data.

### Matched force calculation

```text
L_new = L_legacy(reference)
      + [L_raw_surfaces(reference + station_deltas, held_wake)
         - L_raw_surfaces(reference, held_wake)]
```

Both raw passes reuse `_local_loads` with identical body state, rates, controls, density, ground-effect factors and held dimensional wake. They include wing/tail forces, their existing arms and section moments. They exclude body residual terms; the legacy baseline owns those once. The difference is not weighted by `local_flow_weight`: otherwise the global attached-flow branch could suppress a real ambient gradient. The tests include a partially blended reference case.

With a finite wake argument, use that source in both passes. With `NAN`, resolve the existing reference wing lift-velocity source once, including its flap/polar/ground-effect law; each pass then applies the existing tail ground-effect scale once. Do not recompute a spatial source for only one pass. The baseline still receives the caller's original wake argument. Legacy active-flap `Aero.loads` can distinguish `NAN` from an explicitly supplied instantaneous wake through its clean-baseline path; the new code preserves that behavior. The paired correction is byte-identical for those two equivalent held-source inputs, and each final load equals its own legacy baseline plus correction.

For all-zero deltas the helper calls `Aero.loads` directly, before domain restrictions, and returns zero correction. Thus calm, uniform wind, stall, reversed flow, angular rates, flaps and ground effect retain the legacy arithmetic. Existing `_wing_flow` and `_local_loads` callers retain their default arguments and arithmetic.

### Initial domain and explicit refusal

The nonzero-gradient bridge accepts only the following provisional domain:

- Both reference and perturbed local station flows are finite and forward (`u > 0`).
- At each same station, physical alpha and beta changes are at most 3°. This comparison includes the same rigid-body rotation on both sides; it does not mistake `omega × r` for a weather gradient.
- Section-plane pressure changes are at most 25% relative to that station's unperturbed value. The plane is `(u,w)` for wings/horizontal tail and `(u,v)` for the vertical tail. Density is held, so the test uses squared plane speeds.
- Both sides remain inside the existing sideslip boundary. Wing effective incidence is fully attached under both the classical envelope and an enabled tabulated polar; tails remain inside their existing local attached limit with the held wake.

These eligibility bounds are conservative engineering limits, **not measured RC weather limits or clamps**. They are stricter than merely forbidding a stall crossing: an already separated station also refuses a nonzero correction. Zero deltas still preserve the legacy result in any supported regime. Strong gradients, one-wing stall, spatial wake feedback and transition handling require a separately qualified law. A future session caller must propagate refusal through its existing transaction; silently discarding a spatial correction is not acceptable.

## Verification

Pinned Windows engine: `4.8.beta1.official.4d10419ca`. [verification.json](verification.json) identifies tested source bytes, 14 successful focused/regression scripts, the baseline/parse receipts and six flight comparisons. [checks/](checks/) retains checked-runner reports and engine logs. New scripts were parsed outside `app/` before promotion; both new `test_*.gd` files are automatically discovered by the existing `app/test.sh` unit loop. The full release suite was **not** run.

| Coverage | Result and purpose |
| --- | --- |
| [`test_wind_aircraft_flow.gd`](../../../../app/tests/test_wind_aircraft_flow.gd) | 85 checks: station transforms, same-time queries, known linear field, exact uniform deltas, one rotational contribution, immutable/detached data, current fleet geometry, optional hub/intake axes, nonunit stage quaternion parity, invalid inputs/provider results/overflow. |
| [`test_spatial_wind_aerodynamics.gd`](../../../../app/tests/test_spatial_wind_aerodynamics.gd) | 175 checks: all nine fixed-wing catalog models plus the battery configuration; exact uniform legacy equality including signed zero; independent pressure- and angle-driven wing-load oracles; both tails; blended reference; active flap/ground-effect held wake; body residual ownership; conservative/input refusals; world-field → station bundle → load checks. |
| Existing aerodynamic reference checks | `test_aero_flow`: 22,500 selector and 22,501 local comparisons. `test_attached_flow`: 22,500 air-data and 22,500 global-load byte comparisons. `test_aero`, `test_aero_continuity`, `test_flap_aero`, `test_ground_effect`, `test_strip_induced`, `test_wing_polar`: pass. |
| Existing propwash checks | `test_slipstream_scalar`: 30,001 projected-load comparisons; `test_slipstream_downwash`: 15 checks. Existing production wash arithmetic remains unchanged. This does not qualify spatial wash. |
| Existing stage/rollback integration | `test_spatial_wind_flight`: 130 checks across ten configurations; actual RK stage positions/times and bad-midpoint full transaction rollback still pass. |
| Existing golden flights | `test_golden`: all four pass without rerecording; existing tolerances apply. |

### Independent gradient oracle

Use symmetric wing strips at `y_i`, zero rates, identity attitude, forward airspeed `U`, constant positive section `CL0`, zero lift slope, no induced map/twist/flaps/polar, and `W_N(E)=s E`. Then `delta_u_i=-s*y_i`. Summing the strip lift moment gives the exact even-pair result:

```text
delta_Mx = rho * (S / n) * CL0 * U * s * sum(y_i²)
```

Positive `s` decreases right-wing relative speed/lift and produces positive FRD roll; reversing the field reverses the moment. This independently detects wrong wind sign, missing station differences, extra blend weighting and incorrect span arms. A rotated world-coordinate fixture exercises the entire sampling-to-load path against the same oracle. Tail-only checks use the independently existing tail increment helper with matched flow/wake. The synthetic fields/models are in-memory test fixtures, not saved aircraft or approved weather data. These are equation tests, not atmospheric-spectrum or aircraft-coefficient validation.

A second attached-wing oracle isolates angle-dependent lift with `CL0=0`, `CLa>0`, zero section drag and `W_D(E)=-g E`. The local vertical relative velocity is `w_i=g*y_i`; the expected force and roll are:

```text
Fz_i     = -0.5 * rho * (S/n) * CLa * U * sqrt(U²+w_i²) * atan2(w_i,U)
delta_Mx = sum(y_i * Fz_i)
```

An upward gust increasing to the right (`g>0`) gives negative FRD roll; reversing it reverses the result. This checks that the new wind increment reaches the section-angle lift law as well as the velocity/force reconstruction. It complements the constant-`CL0` pressure-asymmetry oracle; one cannot substitute for the other.

### Baseline and candidate flight tapes

Before modifying `aero.gd`, `test_flight_log.gd` recorded and exactly replayed six baseline tapes: **3,247 checks, zero failures**. [baseline-verification.json](baseline-verification.json) retains that receipt. The same initial states and recorded tick/input tapes were replayed under the candidate solver with the original aircraft files.

| Specimen | Recording, shared CSV and reports |
| --- | --- |
| Jensen Ugly Stik 60 | [Evidence](flights/jensen_ugly_stik_60/) |
| Extra 300S 60 with turbulent weather | [Evidence](flights/gp_extra_300s_60/) |
| P-51D Mustang 120 | [Evidence](flights/p51d_mustang_120/) |
| Avanti S A200 | [Evidence](flights/sebart_avanti_s_a200/) |
| Turbo Lumber Evolution | [Evidence](flights/turbo_lumber_evolution/) |
| Stik glow 61FX | [Evidence](flights/stik_glow_61fx_2t/) |

All candidate reports have `complete: true`, `solver_changed: true`, no error and no first divergence. Each has 261 rows (initial state plus 260 ticks at 240 Hz); all 1,566 exported rows are byte-identical across the complete CSV channel sets. Each folder retains `baseline.orfl`, one identical `flight.csv`, baseline export/candidate replay reports and comparison JSON. The recording preserves the source/config identities and roll-reversal marker.

Baseline solver fingerprint: `110c4ba539c7482e71a3e1ec3f30bbbdf6602d4f848b9f8e3cab6b11aea996ce`. Candidate: `8ddd4a8afa53a042ef992d09b3b5468732f63e9a3ec1dc31235527088b1e4e1f`. This is short numerical compatibility evidence, **not an exact-replay claim across source identities**, a spatial flight qualification, physical validation or pilot acceptance. No golden files or recording identities were rewritten.

[baseline-source/manifest.json](baseline-source/manifest.json) records all baseline solver source hashes. On an isolated copy of the tested candidate sources, replace `aero.gd` with the retained pre-edit bytes and omit the newly added `wind_aircraft_flow.gd` to reconstruct that exact baseline fingerprint. Do not make these changes in a shared active tree. The evidence source is outside `app/` and is not an alternative runtime implementation.

Implementation started at `9f12c79e1490c4c72895d450910d9c916743d7b9`. After the flight comparisons, another track modified `flight_session.gd`/`vehicle_model.gd` and added `wheel_coupling.gd`. The preexisting session/model bytes are retained under `baseline-source/app/sim/`; the latter new source is excluded from these historical solver receipts. Reconstruction using those inputs matched both complete recorded fingerprints exactly. This task did not replace, stage or commit the other track's files. The receipts qualify the identified source bytes, not those later ground changes or the entire mutable working tree.

### Reproduction

From the repository root, run the pinned engine through the existing checked runner:

```powershell
python tools/godot/run_checked.py --timeout 180 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_wind_aircraft_flow.gd
python tools/godot/run_checked.py --timeout 180 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_spatial_wind_aerodynamics.gd
```

The other commands are retained in their check reports. Use the existing [flight-log workflow](../../../FLIGHT-LOGGING.md) to replay/export a retained tape to a new output directory. Later source/data edits require a newly identified candidate comparison.

## Remaining gates

1. **M5-W05c-R2 — matched propulsion and wash:** feed hub/intake ambient velocity into every powertrain's existing inflow calculation with rotation once; make washed-minus-free tail increments use the same local ambient field. Preserve one final load owner and the existing live-datum conversion. Qualify each propulsion/finite-resource route before session admission.
2. **Spatial admission and recording:** version provider configuration, clock/epoch, checkpoint/log identities and a common multi-aircraft world. Integrate the sampler into actual RK evaluations only with explicit refusal/rollback. Current sessions still use body-datum uniform weather.
3. **Spatial starts and observers:** runway equilibrium needs candidate-position sampling; windsock, smoke and sound need their own field positions. A hub sample in a diagnostic bundle does not establish propulsion integration.
4. **Broader aerodynamic domain:** qualify gradient-sensitive transition selection and source/wake evolution before one-wing stall, flow reversal or strong shear. Add body stations only if a justified model needs them; body residuals currently remain at O.
5. **P1/P2/P3:** authored shear/gust agendas, coherent spatial turbulence, balanced thermals and terrain flow retain the masterplan's separate evidence and acceptance gates. Defaults remain unchanged in this slice.

The diagnostic sampler rebuilds geometry and allocates detached arrays; the load helper runs two raw surface evaluations plus its baseline/domain checks. Geometry precomputation, shared stage buffers and cost measurement are needed before enabling multi-aircraft runtime sampling. No target-host CPU budget, 1080p qualification, long-flight handling, soaring or measured-weather validation is claimed here. P0 remains open.

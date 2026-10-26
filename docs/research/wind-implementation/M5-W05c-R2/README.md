# M5-W05c-R2 — powered-stage airflow and matched local propwash

2026-10-25. **Experimental integration implemented; product spatial weather admission remains closed.** This slice follows the [station-flow/unwashed-load kernel](../M5-W05c-R1/README.md). The [wind guide](../../../WIND-PLAN.md) owns current behavior; the [advanced masterplan](../../../advanced-wind-atmospheric-physics-masterplan.md) owns the remaining atmosphere design.

The new stage contract carries one local hub/intake velocity through propulsion and samples the ambient field at actual propwash force points. Each washed-minus-free pair uses the same ambient velocity, controls, rates, density and wake source. The atmosphere applies no separate force or angular disturbance. Existing weather v1–v4 and production `FlightSession.air_data` still select the old uniform path. No aircraft, weather data, default, UI or kernel layout changes in this slice.

## Changes and ownership

| Existing behavior / correction | Implementation and integration | Complexity / dependency | Verification |
| --- | --- | --- | --- |
| R1 provided detached diagnostic stations and an unwashed correction, without a complete powered-stage input. | [`wind_aircraft_flow.gd`](../../../../app/physics/wind_aircraft_flow.gd): `stage_air`, held-time `StagePointSampler` and `matches_stage`; retain sampler lifetime in the returned Air dictionary. | Medium; R1 geometry, pure `Environment.wind_world`, existing float64 transforms. | Fleet geometry, full point equation, common time, lifetime, stale/invalid receipts. |
| Dynamics owned the load sum but consumed only datum ambient flow. | [`dynamics.gd`](../../../../app/physics/dynamics.gd): complete spatial receipt selects R1 correction once, one propulsion contribution and one wash increment. Partial spatial fields refuse. | Medium; conservative R1 attached-flow domain remains. | Independent composition and malformed/stale receipt tests. |
| Legacy propulsion paths differed in whether they included hub rotation. | [`propulsion.gd`](../../../../app/physics/propulsion.gd): `stage_air_velocity` uses explicit full point flow as supplied, otherwise preserves each old fallback. [`glow/flight.gd`](../../../../app/physics/glow/flight.gd) uses it for propeller loading and local cooling. | Medium; existing propulsion equations and datum/rotor ownership. | Propeller, turbine, glow, finite-liquid and actual electric/glow/turbine stage checks; absent-key parity. |
| Wash subtractions used datum ambient flow even when the unwashed loads could be spatial. | [`slipstream.gd`](../../../../app/physics/slipstream.gd) and [`swirl_loads.gd`](../../../../app/physics/swirl_loads.gd): query actual force arms; reuse each local ambient sample in the matched pair. Wake geometry uses ambient-only source correction. | High; fixed existing occupancy/quadrature/downwash laws. | Independent six-axis tail oracle, segmented reference, frozen smooth-swirl reference, exact zero-delta parity. |
| Transport target and source loads could use different propulsion inflows. | [`wash_transport.gd`](../../../../app/physics/wash_transport.gd): stage target/derivative/settled wrappers use explicit point inflow for thrust/torque and ambient source flow for wake/convection. Old APIs remain. | Medium; existing scalar axial transport law and distance validation. | Independent target/derivative equation, invalid input, exact legacy parity. |
| Some session evaluators rebuilt datum Air or bypassed an injected full stage receipt. | [`flight_session.gd`](../../../../app/sim/flight_session.gd) and [`liquid_fuel_flight.gd`](../../../../app/sim/liquid_fuel_flight.gd): route the same stage Air through shaft, turbine, wash and wheel consumers. The production Air producer stays unchanged. | Medium; existing VehicleModel transactions, finite-resource evaluators and rollback. | Actual stage injection, finite-liquid consumption, invalid-midpoint rejection with no published accepted tick. |

## Stage contract and equations

`WindAircraftFlow.stage_air(state, model, environment, time_s, rho)` returns `{ok, errors, air, flow}`. It requires a valid powered model with an authored propeller hub or turbine intake. R1's diagnostic `sample` still supports an absent propulsion point, but this powered-stage builder explicitly refuses it. A future glider adapter needs its own complete supported contract.

World coordinates are float64 NED metres; velocity is NED m/s. Body quantities use FRD; quaternion order and raw RK-stage transforms follow the repository. Density is kg/m³ and time is nonnegative simulation seconds. Let O be the authored rigid-body datum and `r_i` the actual force arm in body axes:

```text
x_i             = x_O + R(q) r_i
v_O             = v_ground_body - R(q)^T W(x_O,t)
delta_i         = R(q)^T [W(x_O,t) - W(x_i,t)]
v_i             = v_O + omega × r_i + delta_i
propulsion_flow = v_hub_or_intake
wake_source     = v_O + delta_hub
```

The supplied quaternion is not normalized independently in a trial stage. The conjugate operation follows existing stage arithmetic; accepted-step normalization remains the integrator's responsibility. Authored offsets retain R1's fixed-datum and coordinate conversion rules. Existing final wrench/live-mass conversion remains the sole owner of that conversion.

| Air field | Meaning / ownership |
| --- | --- |
| Existing `v_air`, `V`, `qbar`, angles | Datum Air from `Air.compute`; do not subtract wind again. |
| `spatial_air_law` | `m5-w05c-r2-point-air-v1`; explicit experimental input law. Not a saved weather/replay law. |
| `spatial_state`, `spatial_time_s`, `spatial_rho` | Detached body snapshot, held sample time and density. |
| `aero_station_delta_body` | Eight triples: six wings, horizontal tail, vertical tail; **ambient deltas only**, without rotation. |
| `propulsion_air_body` | Complete hub/intake relative velocity including `omega × r` once. Consumers use it directly. |
| `wake_source_delta_body` | Ambient-only hub correction. The inherited wake geometry closure excludes body rotation here. |
| `ambient_delta_body_at(arm)` | Pure held-stage ambient-only delta at any actual wash force arm. |
| `spatial_sampler` | Strong owner of the callback target for the lifetime of this Air receipt. |

`matches_stage` checks the law, exact body bytes, density, shape/finite fields and live sampler. It validates the receipt's time as finite/nonnegative but does **not** compare it to an external stage clock or model identity: `Dynamics` receives neither. Callers must rebuild at every stage/model/time and never persist or cache this object across stages. The provider must not advance RNG or mutate its accepted field during queries. The sampler retains detached body/reference arrays but shares the provider; this is a synchronous stage contract, not an immutable world snapshot protocol.

A bound Godot method `Callable` does not keep its `RefCounted` target alive. An initial test exposed a dead callback immediately after builder return. Keeping `spatial_sampler` in Air fixes this; a lifetime test guards the actual post-return call. No owner cycle is introduced.

### Force composition

```text
L_unwashed = L_legacy(reference)
           + [L_raw(reference + station_deltas, held_wake)
              - L_raw(reference, held_wake)]

L_wash = sum_i [L_i(v_O + delta_i + omega×r_i + induced_i)
               - L_i(v_O + delta_i + omega×r_i)]

L_body = L_unwashed + L_propulsion(v_hub_or_intake) + L_wash
```

The equations show ownership, not a new aerodynamic model. Existing tail/downwash, wake edge, swirl sign, force arms and density laws remain. The smooth swirl correction is itself the matched axial-plus-swirl minus axial-only difference. Ground loads and gravity keep their existing owners; wheel friction remains ground-relative.

The same local sample feeds both sides of each subtraction. Legacy piece coverage samples its established force centroid and arm, including load-plane offsets. Segmented sidewash samples each segment force centroid: its internal Gauss nodes average swirl geometry, so they are not independent force stations. Smooth swirl samples every positive-area Gauss force node. Invalid point samples propagate nonfinite loads and trigger the existing transaction refusal; there is no silent fallback to datum wind. A stopped source or zero-area node need not query a field that contributes no load.

When Dynamics computes washed propulsion, one stage thrust/torque pair feeds both body propulsion and wake. A caller supplying spatial-stage propulsion loads must also supply a finite matching pair. Coupled glow already has that pair and reuses it. Transport evaluates its existing target from the same inputs but retains its inherited axial lag equation:

```text
d(dv_lag,i)/dt = (dv_target - dv_lag,i) * convection_speed / distance_i
```

This is not a fully convected 3D wake. Source flow uses `v_O + delta_hub` for geometry/reverse fade/convection, while powered-device inflow uses the full `v_hub`. That deliberate separation preserves the inherited wake closure's rotational convention and prevents counting `omega × r` twice. Wake direction/radius history, spatial wing-wake feedback and strong gradients require later model work. The existing rejection of transported wash with unsupported coupled-glow configurations remains.

### Compatibility and refusal boundaries

The explicit point-inflow law stays selected even when the sampled wind is uniform. Some older shaft/RPM routes use datum inflow and omit hub rotation; the new law may therefore change their thrust/torque under nonzero body rates even in uniform air. This is an intentional experimental point-flow correction, not a claim that every new-law uniform result equals the old one. Switching laws when `flow.uniform` becomes true would introduce a discontinuity and could miss variation at wash nodes between standard stations.

Absent the new keys, all legacy fallback arithmetic remains selected. Zero ambient deltas retain existing surface/wash arithmetic for matched propulsion inputs. The six recorded-flight comparisons exercise this preserved product path. No old configuration or checkpoint is silently migrated.

Nonzero unwashed corrections still require both reference and perturbed local flow to satisfy R1's attached forward-flow bounds: at most 3° physical alpha/beta changes and 25% section-plane pressure changes, plus existing sideslip/tail/polar eligibility. These are provisional refusal limits. This slice does not qualify separated flow, one-wing stall, flow reversal or strong shear. Body residuals remain at O and density remains one stage-datum sample. Nor does it introduce spatial admission into starts, trim, telemetry, smoke or sound.

## Verification

Pinned engine: **Godot 4.8.beta1.official.4d10419ca**, Windows console, 240 Hz simulation. [verification.json](verification.json) retains exact source identities and all successful checked-runner receipts. New tests were parsed outside `app/` before integration; the existing test loop discovers them. The full `app/test.sh` release suite was **not** run.

| Coverage | Result |
| --- | --- |
| [`test_spatial_propulsion_flow.gd`](../../../../app/tests/test_spatial_propulsion_flow.gd) | 29 checks: explicit/full vs legacy inflow, one point rotation, turbine, glow torque/cooling and finite-liquid response. |
| [`test_spatial_wash.gd`](../../../../app/tests/test_spatial_wash.gd) | 30 checks: independent tail equations, actual force points, frozen smooth-swirl oracle, segmented pairing, source/transport target and invalid samples. |
| [`test_spatial_powered_stage.gd`](../../../../app/tests/test_spatial_powered_stage.gd) | 235 checks: nine catalog aircraft plus battery configuration, combined loads, receipt lifetime, actual electric/glow/turbine session stages, stale/partial receipts and bad-midpoint rollback. |
| R1 and routing regressions | `test_wind_aircraft_flow`: 85; `test_spatial_wind_aerodynamics`: 175; `test_spatial_wind_flight`: 130 checks across ten configurations. |
| Propulsion / wash regressions | Scalar propulsion: 25,001 byte comparisons; scalar slipstream: 30,001 projected-load comparisons; segmented parity: 381 checks; sidewash: 10; swirl optimization: 7; wash transport: 43; slipstream downwash: 15. |
| Powered-session regressions | Glow stage reuse: 2,005 comparisons including 2,000 byte-exact loads; glow hub inflow: 168; glow flight: 110; finite-liquid session: 48; electric: 98; battery: 103; turbine continuous: 46; coupled shaft: 99. |
| Golden flights | All four pass under existing tolerances; no rerecording. |

All **22** selected scripts completed with zero engine errors/warnings and no failed checks. The inherited segmented reference fixture initially failed compilation after its parent's optional sampler argument was added. Its fix only extends the signature with an unused optional `Callable` and a comment; reference arithmetic stays unchanged. The successful rerun contains 381 checks. Raw successful logs and reports are under [checks/](checks/).

The failed-midpoint test compares body/previous state, auxiliary and continuous state, RNG, controls/modes, tick, last loads and mass/inertia data. It also checks the paused/fault response and absence of a published accepted-step signal. It does not compare `flight.checkpoint()` after fault, because that API intentionally returns an empty dictionary for a faulted flight.

### Frozen baseline and six candidate tapes

Before runtime edits, `test_flight_log.gd` recorded and exactly replayed six tapes: **3,247 checks, zero failures**. [Baseline receipt](baseline-verification.json). Each tape retains 260 ticks plus the initial row, a roll-reversal marker and source/config identities. The same tick/input tape and original aircraft file were used for each candidate run.

| Specimen | Retained evidence |
| --- | --- |
| Jensen Ugly Stik 60 | [Recording, CSV and reports](flights/jensen_ugly_stik_60/) |
| Extra 300S 60 with turbulent weather | [Recording, CSV and reports](flights/gp_extra_300s_60/) |
| P-51D Mustang 120 | [Recording, CSV and reports](flights/p51d_mustang_120/) |
| Avanti S A200 | [Recording, CSV and reports](flights/sebart_avanti_s_a200/) |
| Turbo Lumber Evolution | [Recording, CSV and reports](flights/turbo_lumber_evolution/) |
| Stik glow 61FX | [Recording, CSV and reports](flights/stik_glow_61fx_2t/) |

All candidate reports have `complete: true`, `solver_changed: true`, no error and no first divergence. **All 1,566 full CSV rows are byte-identical** to baseline; one shared CSV per aircraft is retained. The 1.0833 s tapes establish short numerical compatibility of the old product path. They do not establish exact replay across solver identities, long-flight behavior, physical realism or spatial-weather handling.

Baseline solver SHA-256: `a47d31c6aa5cb73bf94feb4deb4130396a0a5d27863bc45cc4e2791dd45cc18d`.

Candidate solver SHA-256: `7742f61a2028dbf758bbacffa4f5f525049544b05cf5a2a69488a519e256c21b`.

### Source isolation and reproduction

Work started at `b85ce1047a3e7798ab22b330675fc0c9e4bce912`. Concurrent ground/audio/lighting changes appeared during implementation and were later committed externally. Tests and candidate flights ran in an isolated worktree containing the exact baseline solver sources plus the nine wind-owned runtime changes. Three unrelated ground hunks were removed **only from the tested session copy**: ground-registry installation, lake-normal trace metadata and lake-normal configuration identity. Root work was preserved.

[baseline-source/manifest.json](baseline-source/manifest.json) and [candidate-source/manifest.json](candidate-source/manifest.json) list every solver source hash. Baseline bytes for all nine edited runtime paths are retained. [candidate-source/app/sim/flight_session.gd](candidate-source/app/sim/flight_session.gd) retains the exact tested shared integration file. Every other owned runtime/test source matches the working tree bytes identified in `verification.json`. Both full solver fingerprints were reconstructed from sorted `res://` paths plus exact `.gd` bytes, matching the recording reports. These receipts do not qualify concurrent ground edits or the entire mutable repository.

Reproduce in a disposable checkout of the identified baseline: apply only the wind changes, use the retained tested session source, and verify the candidate manifest before running. To reconstruct the baseline fingerprint, replace those nine runtime files with their retained pre-edit bytes. Do not replace shared working-tree files. Native source line endings contribute to the fingerprint; preserve the exact bytes.

Use the existing [checked runner](../../../../tools/godot/README.md) and [flight-log workflow](../../../FLIGHT-LOGGING.md). Example from the repository root:

```powershell
python tools/godot/run_checked.py --timeout 180 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_spatial_powered_stage.gd
```

Other exact commands are in the check reports. Run a checkout's own `tools/flight_log/flight_log.py` with an explicit pinned `--godot` path; the tool derives its application directory from its own location. Retained export reports read the baseline recording bytes; candidate replay reports execute the new solver. Always use a fresh output directory for a new comparison.

## Remaining gates

1. **M5-W05c-R3 — spatial admission/identity:** specify a versioned persisted field, seed/epoch and checkpoint/log receipt; establish common multi-aircraft clock ownership. Bind producer selection and the point-inflow law to that identity. Prove reset, failed setup, restore and replay before activating it.
2. **Starts and observers:** sample candidate positions in runway equilibrium/trim; make windsock, smoke, audio and telemetry query their own relevant positions. A correct flight-stage consumer does not establish correct starts or observations.
3. **Domain and wake qualification:** retain explicit refusal outside the current attached-flow envelope. Qualify gradient-dependent transitions, induced-flow source updates and moving wake geometry before strong shear/rotor scenarios. Extend the powered contract for gliders only with a valid force owner and tests.
4. **P1–P3 atmosphere:** coherent turbulence spectra, gust agendas, shear, balanced thermals and terrain flow retain the masterplan's model, performance and physical acceptance gates. Existing gentle-practice and dead-calm configurations remain unchanged.
5. **Cost:** the prototype rebuilds geometry and allocates detached stage arrays; every nonzero unwashed correction evaluates two raw surface passes in addition to the baseline/domain checks. Wash adds a query per actual contributing force point. Precompute immutable geometry, measure allocations/query counts and benchmark fleet batches before user activation. No target-host CPU, rendering-resolution or multi-aircraft budget is qualified here.

P0 remains open. This slice establishes force/data ownership and transactional software behavior, without claiming measured atmosphere spectra, RC flight validation, owner handling approval or new weather scenarios.

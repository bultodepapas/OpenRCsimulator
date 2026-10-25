# M5-W05b-R1 — Position/time atmosphere adapters

2026-10-25. First implementation slice of the [advanced wind masterplan](../../../advanced-wind-atmospheric-physics-masterplan.md), authorized after the audit. **Software integration verified; P0 as a whole and physical qualification remain open.** The [wind guide](../../../WIND-PLAN.md) owns current behavior.

## Delivered boundary

The existing weather law now has a position/time entry point. Aircraft evaluators pass the position of their actual integration-stage body datum instead of implicitly querying one time-only field. This establishes the required seam for later spatial weather while retaining every accepted v1–v4 wind law.

| API | Input and result | Ownership |
| --- | --- | --- |
| `WindField.sample_world(position_ned, time_s)` | Float64 NED metres, nonnegative simulation seconds → float64 NED air velocity in m/s | Validates position, then delegates to the unchanged legacy `sample(time_s)` law. No RNG draws. |
| `Environment.wind_world(position_ned, time_s)` | Same coordinates/time/vector | Samples the provider and adds the owner's existing sampled turbulence exactly once. Empty turbulence means none. Wrong shape/type, nonfinite values, negative time and addition overflow return `[NaN, NaN, NaN]`. |
| `Environment.air_world(position_ned)` | Float64 NED metres → existing atmosphere dictionary with `ok`/`errors` | Uses NED down, not AGL. `standard_column` remains `field_elevation_m - down_m`; reference/custom air remains uniform. Invalid positions fail explicitly. |
| `FlightSession.wind_at(time_s, body_state)` | Optional 13-value body state → NED m/s | Supplied state selects its datum; omitted state selects the accepted endpoint for observers. The pending-weather-reset guard remains active. |

The first adapter deliberately uses existing packed-array/dictionary contracts. It does not yet implement the masterplan's batch buffers, sample-clock record, components/gradient output or shared immutable spatial identity. No new schema, aircraft parameter, UI setting or weather preset is introduced. There is no migration of saved settings.

Changed runtime paths:

- [`wind_field.gd`](../../../../app/physics/wind_field.gd) and [`environment.gd`](../../../../app/sim/environment.gd): pure adapters; legacy `sample()` and `wind()` bodies retained.
- [`flight_session.gd`](../../../../app/sim/flight_session.gd): `air_data`, `_wash_loads` and `_wheel_evaluate` use their supplied stage state. Existing coupled electric, glow, liquid-fuel and turbine paths receive this through `air_data`. Airborne restart samples its launch position. Density/charge formulas and force ownership are unchanged.
- [`helicopter_flight_session.gd`](../../../../app/sim/helicopter_flight_session.gd): hover reset samples `_start`; stage evaluation, telemetry and checkpoint preflight use their evaluated body position. Existing turbulence/column admission restrictions remain.
- [`multirotor/plant.gd`](../../../../app/physics/multirotor/plant.gd): the research plant samples the supplied stage body's position. This does not qualify per-rotor spatial inflow.

The shared `Simulation`/`VehicleModel` kernel, aerodynamic equations, contact equations, propulsion models and generated aircraft data were not changed. No wind force, attitude disturbance or additional acceleration was introduced. The interactive `gentle-practice` and technical calm defaults retain their existing parameters.

## Verification

Pinned Windows console engine: `4.8.beta1.official.4d10419ca`. [verification.json](verification.json) identifies tested sources, all 17 successful script receipts and six flight comparisons. [checks/](checks/) retains checked-runner reports and logs. Tests parse their loaded dependencies; new scripts were parsed outside `app/` before promotion. The complete `app/test.sh` release suite was **not** run.

| Coverage | Result |
| --- | --- |
| `test_spatial_wind_contract.gd` | 169 checks: byte-identical legacy samples for built-in v1–v4 profiles; constant/linear provider dispatch; query-order repeatability; detached outputs; noise added once; invalid point/time/output/type/overflow handling; column altitude. |
| `test_spatial_wind_flight.gd` | 130 checks over all 9 admitted fixed-wing catalog models plus the battery-pack variant: supplied-position air data; matched constant-versus-linear body-datum loads/derivatives; actual RK stage positions/times; read-only queries; invalid midpoint rollback of body, previous, aux, continuous, input, RNG modes, tick and loads; no accepted-tick signal on failure. |
| `test_wind_world_consumers.gd` | 6 checks: helicopter reset/stage/observer/checkpoint positions and multirotor stage position. The helicopter fixture returns calm air while recording positions, isolating routing from hover-trim capability. |
| Existing wind/OU/flight/trace | `test_wind_field`, `test_wind_turbulence`, `test_wind_flight`, `test_turbulence_flight`, `test_wind_trace`: all pass. Includes Galilean invariance, wind-on runway hold, fourth-order forcing refinement, seeded continuation and trace contracts. |
| Existing atmosphere/ground/kernel | `test_atmosphere_column_session`, `test_ground_start_environment`, `test_runway_transaction`, `test_sf_environment`, `test_rk_stage_time`: all pass. |
| Existing rotorcraft/research plant | `test_heli_session`, `test_heli_ground_start`, `test_dr_multirotor_kernel`: all pass. |
| Existing golden flights | `test_golden`: all 4 pass without rerecording; existing tolerances apply. |

The synthetic linear aircraft fixture is a small divergence-free field used to detect wrong sampling positions. It is not accepted scenario data and does not validate a turbulence spectrum. All surfaces still receive body-datum wind; the matched-uniform test checks that boundary, not distributed loading.

### Baseline and candidate flight tapes

Before changing aircraft consumers, `test_flight_log.gd` preserved six `.orfl` recordings and verified their exact replay: **3,247 checks, zero failures**. The unused adapter methods already existed at that recording boundary; consumers still used the legacy time-only route. [baseline-verification.json](baseline-verification.json) retains the run receipt.

The same aircraft files and recorded tick/input tapes were then replayed in **candidate mode** under the updated solver. All six reports declare `complete: true`, `solver_changed: true`, no error and no first divergence. Each contains 261 rows (initial plus 260 ticks at 240 Hz); all 1,566 exported rows are byte-identical between baseline export and candidate export, including their complete channel sets. One identical `flight.csv` per specimen is retained rather than duplicating its bytes.

| Specimen | Retained recording, CSV and reports |
| --- | --- |
| Jensen Ugly Stik 60 | [Flight evidence](flights/jensen_ugly_stik_60/) |
| Extra 300S 60, turbulent weather | [Flight evidence](flights/gp_extra_300s_60/) |
| P-51D Mustang 120 | [Flight evidence](flights/p51d_mustang_120/) |
| Avanti S A200 | [Flight evidence](flights/sebart_avanti_s_a200/) |
| Turbo Lumber Evolution | [Flight evidence](flights/turbo_lumber_evolution/) |
| Stik glow 61FX | [Flight evidence](flights/stik_glow_61fx_2t/) |

Each folder contains `baseline.orfl`, `flight.csv`, `baseline-export.json`, `candidate-replay.json` and `comparison.json`. Source/configuration identities and the roll-reversal marker remain in the recording/reports. The full baseline solver fingerprint is `a9b6e6c401122d4ba85c7aebbe8678789e5748878c85349d686b17c120d36548`; candidate is `110c4ba539c7482e71a3e1ec3f30bbbdf6602d4f848b9f8e3cab6b11aea996ce`.

This is numerical compatibility evidence, **not an exact-replay claim across different source identities**, long-flight coverage, physical validation or pilot acceptance. Exact replay under changed sources correctly remains subject to the existing identity gate. No goldens or recording headers were rewritten to bypass it.

For reproducibility, [baseline-source/manifest.json](baseline-source/manifest.json) lists every baseline solver source hash. Four retained source replacements reconstruct the exact pre-consumer source identity from the tested candidate tree; the combined path/bytes hash was verified against the recording fingerprint. Use an isolated matching checkout when reconstructing it. These are evidence copies outside `app/`, not runtime alternatives. Candidate source hashes are in the main verification receipt.

Implementation began at `498767e39859dff33ea8f38dc6caf2a6456455aa`. Concurrent external commit `f3d0a163c5d12143764e74ac8e5f6a612b135586` included the wind runtime/tests with unrelated shared-tree work during verification. This task did not stage or create that commit; evidence identifies actual source bytes rather than claiming an isolated whole-tree build. Unrelated work was preserved.

### Reproduce focused checks

From the repository root, use the pinned engine and the existing checked runner:

```powershell
python tools/godot/run_checked.py --timeout 180 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_spatial_wind_contract.gd
python tools/godot/run_checked.py --timeout 180 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_spatial_wind_flight.gd
python tools/godot/run_checked.py --timeout 180 -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_wind_world_consumers.gd
```

The same runner commands for existing checks are recorded in their reports. Use the [flight logging workflow](../../../FLIGHT-LOGGING.md) to export or compare a retained tape into a new output directory. Candidate replay requires its matching original aircraft data. Later source/data changes require a new explicitly identified comparison.

## Remaining implementation gates

1. **Distributed force ownership (M5-W05c-R1/R2):** qualify station geometry and matched aerodynamic/propulsion deltas before enabling gradients. Maintain live-datum, rotational velocity, wash, downwash and moment-arm accounting; body-datum sampling alone cannot create the correct asymmetric wing/tail response.
2. **Spatial admission/identity (M5-W01d-R1, W05b-R2):** version configuration, sample clock/epoch, checkpoint/log contracts and shared companion identity before accepting a nonuniform user scenario. A fixture subclass is not a persisted provider contract.
3. **Start and observer locations:** fixed-wing `GroundStart.solve` still accepts one uniform vector. Add candidate-state sampling before admitting spatial runway starts. Windsock, smoke, field/audio and other observers need their own positions; a one-argument aircraft endpoint query does not establish a cue's local wind.
4. **P1 field models:** implement/verify height profiles, resolved gust agendas, coherent spatial turbulence and their spectra/covariance/boundary conditions. Keep the current defaults until the new candidate's acceptance gates pass.
5. **P2/P3:** balanced thermal circulation, heating/stability coupling, terrain and obstacle approximations remain prospective. No soaring or terrain-flow claim follows from these adapters.

No target-host CPU/1080p qualification was performed. The added position arrays and finite checks need measurement with the future multi-point sampler before a performance budget can be claimed. Headless regression wall times and short recording observer timings are diagnostics only. M5-ATM-4-R1 documentation reconciliation is complete; the broader P0 exit gate remains open.

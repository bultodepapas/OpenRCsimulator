# M5-W05d-R3 — tailless spatial airflow and hand launch

2026-10-26. Owner: M5-W, using the existing X8 capability contract. [Current wind guide](../../../WIND-PLAN.md), [X8 plan](../../../X8-PLAN.md), [preceding optimization](../M5-W05d-R2/README.md).

## Problem and correction

R2 reproduced failed v5 airborne starts for both X8 configurations: `WindAircraftFlow.geometry` and the spatial Aero entrypoints required a horizontal tail that the accepted tailless model deliberately omits. Inspection also found that weather sampling used unswept wing positions while the X8 force law used derived swept stations. The new session regression exposed another failure: hand launch called the time-only weather query, which spatial weather refuses.

Only three runtime files change in the isolated comparison:

| File | Correction and ownership |
| --- | --- |
| `app/physics/wind_aircraft_flow.gd` | Recognize the normalized `airframe_layout: tailless` / elevon capability; use existing derived `surfaces.tailless.station_x`; reserve the absent H slot without querying it. Existing fin/hub indices, datum, rotations and force ownership stay fixed. |
| `app/physics/aero.gd` | Validate the explicit layout before either spatial law; require zero inactive H increments; omit absent H domain checks. The narrow helper uses the same swept rotation arms as the established wing law. The existing wing/elevon/fin loading and matched surface-difference laws are reused. |
| `app/sim/flight_session.gd` | Resolve hand-launch position before sampling spatial wind at release height and time zero for heading. Initialize the v5 motor from complete local hub inflow. Preserve the ground-relative throw and the original legacy launch arithmetic. |

Aircraft source/generated data, kernels, weather providers, timestep, presets and schemas are unchanged. No dummy tail, randomized motion, independent moment or aircraft-specific weather factor is added. The normalized capability is required; missing geometry alone never selects a new airframe law. Validation is still primarily owned by `AircraftData`; the spatial adapter additionally rejects malformed tailless station arrays, nonfinite positions, invalid chords/coverage, missing fin/elevon declarations and incompatible horizontal geometry.

## Geometry, sampling and force contract

Six wing slots remain 0–5. Slot 6 remains the horizontal-tail ABI slot; for tailless aircraft `horizontal_index=-1`, its arm and ambient increment are exact zero, and its diagnostic position/wind/relative velocity are datum values. It is never a physical query, angular-flow contribution or force. The existing vertical aggregate remains slot 7; the pusher remains slot 8. Thus the aerodynamic increment remains 24 float64 values and the complete geometry remains 27. An X8 sample performs nine provider queries: datum, six wing stations, fin and hub.

Authored wing coordinates are aft/right/up; body axes are forward/right/down. Wing station arms are

```text
r_i = [-(station_x[i] - cg_le.x), ARP.y - cg_le.y + station_ys[i], -(ARP.z - cg_le.z)]
x_i = x_O + R(q) r_i
delta_i = R(q)^T [W(x_O,t) - W(x_i,t)]
v_air_i = v_ground_O - R(q)^T W(x_O,t) + omega × r_i + delta_i
F/M = unchanged baseline + raw_surfaces(delta) - raw_surfaces(zero)
```

Here `cg_le` establishes the authored fixed datum O; it is not a moving live-CG reference. Both raw passes hold the original wake/controls/body state fixed. The existing aerodynamic law already knows how to omit the horizontal tail. Nonzero values in its inactive slot are refused by both public spatial entrypoints. The sampler retains detached arrays and does not mutate the model. All conventional arithmetic and operation order remain unchanged.

The hand-launch helper's north/east position is independent of heading. A neutral placement query therefore finds the location without inventing a wind sample; terrain supplies release height, and the actual spatial query chooses the along-runway heading. Hub air uses the established point-Air producer at time zero. Spatial v5 forbids legacy OU amplitudes, so an old OU index/window cannot contribute before reset. The thrown state is ground-relative and `_reset_airborne_start` already skips adding wind to it. No continuous flight force is evaluated by the start helper.

Existing law identifiers remain unchanged: this admits a previously refused normalized layout into the same mathematical laws. Prior valid conventional checkpoints retain their geometry. No prior valid X8 v5 flight is asserted. ORFL source fingerprints change and exact replay correctly remains source-bound.

## Verification

The final integrated run passes **1,147 checks plus four golden flights**, through the checked runner:

| Program | Checks / failures |
| --- | ---: |
| `test_tailless_spatial_wind` | 121 / 0 |
| `test_tailless_spatial_session` | 77 / 0 |
| `test_wind_aircraft_flow` | 88 / 0 |
| `test_spatial_aero_continuation` | 91 / 0 |
| `test_spatial_wind_aerodynamics` | 189 / 0 |
| `test_spatial_powered_stage` | 277 / 0 |
| `test_spatial_wash` | 30 / 0 |
| `test_spatial_weather_session` | 101 / 0 |
| `test_x8_flying_wing` | 37 / 0 |
| `test_hand_launch` | 136 / 0 |
| `test_golden` | 4 tapes / 0 |

The geometry test independently constructs rotated station positions and rigid-body point velocities under a manufactured linear field with nonzero body rates. It checks swept stations, query count, force/moment response, uniform exact-byte limits through attached/stall/reverse/zero-speed cases, slot rejection and input immutability. The manufactured field is an integration oracle, not a meteorological model. Two older fleet tests had fixed counts of ten; they now retain a minimum twelve-configuration floor and explicitly require X8 ideal/pack participation.

The session test covers both X8 variants, airborne and hand-launch starts, finite mean/gust/turbulence weather, east/west launch directions, ground-relative throw speed, independently sampled hub inflow, complete recordings, exact replay and checkpoint continuation. Each source route advances one simulation second; recordings preserve its first 120 ticks. The existing fleet test accepts two seconds per configuration, including both X8 variants; its runway, thermal, receipt-tamper and failed-midpoint rollback checks remain green. Checkpoint restore intentionally pauses; the session test explicitly resumes before exercising the product contact gate.

**Controlled replay:** [parity receipts](replays-final/parity.json) cover eleven preserved baseline recordings: six conventional legacy flights, a conventional v5 flight, and both legacy X8 variants in airborne/hand-launch routes. Baseline exact replay reports `complete=true`, `solver_changed=false`; final candidate replay reports `complete=true`, `solver_changed=true`. Every CSV cell matches across all **2,111 rows**. Candidate runs remain candidate experiments even when values match. Four new spatial X8 recordings also [replay exactly](replays-final/spatial-exact.json), with 121 rows each and unchanged candidate solver identity. Full ORFL packets, CSV, metadata, markers and CLI receipts are retained. The new test tapes contain deterministic small control inputs; they are not piloted flights.

Initial negative receipts are retained under `checks/`: the fixed fleet counts, missing hand-launch query integration, a fixture that forgot restore pauses, and a hub oracle that initially omitted the authored-to-body axis conversion. The oracle was corrected; its numerical tolerance was not widened. The initial baseline import timed out while importing assets; the completed retry and candidate import are retained. Candidate import reported two regenerated UID warnings without script errors. An independent source review found no blocker after checking capability ownership, conventional arithmetic and reset-time turbulence semantics.

## Source identity and reproduction

Pinned engine: `4.8.beta1.official.4d10419ca`, Windows. Baseline commit: `7282d395cfbb41bf9ebbfdfb16c0bc0fcd5c6446`, plus the existing dirty glow operating-point source. The isolated baseline/candidate were copied before editing; the comparison changes exactly the three runtime paths above.

| Solver | SHA-256 |
| --- | --- |
| Baseline | `2fb428d86afdad17cff903ec2c4f65fb548da2e86f189fd98b10a41dc8711819` |
| Candidate | `7d1e63f999d6e87f902bde6aa40c3ac82bca8a206e5090eddff8c39cb86dfc5f` |

[Baseline](baseline-manifest.json) and [candidate](candidate-manifest.json) manifests bind every physics/simulation/failure source. `baseline-source/` preserves the dirty glow source and four files with mixed line endings; other baseline bytes reconstruct from the commit plus the recorded line-ending style. `candidate-source/` contains only the three changed runtime files. `verification-source/` retains the new/updated test programs.

Create two disposable checkouts of the baseline commit, then run `restore_sources.py --repo <repository> --destination <checkout>` for baseline and add `--candidate` for candidate. The helper refuses the source repository as its destination and verifies every restored source hash and complete solver identity. Import each checkout using the pinned engine before running checks. Use the existing [checked runner](../../../../tools/godot/README.md) and [flight-log workflow](../../../FLIGHT-LOGGING.md); retained reports contain exact original commands. Substitute the reconstructed app/log paths. For solver comparisons, hold the aircraft JSON fixed and use the CLI's explicit `--candidate` mode. `compare_replays.py` records the original orchestration; its `tmp/wind-tailless-r3` paths describe the captured workspaces.

`integrated-checks/` records the final shared-tree run. Other ground-physics work changed two unrelated sources during this session; [post-run observation](integrated-source-observation.json) distinguishes that tree from the isolated experiment. Those edits were preserved. The controlled replay manifests, rather than a shared HEAD, establish the before/after source identity. This is targeted verification, not a claim that the entire repository suite ran.

Both source reconstructions were run and verified all 155 source hashes and their solver identities. [Payload hashes](payload-manifest.json) bind the retained evidence; [fresh evidence-only checkout checks](checkout-verification.json) verify byte preservation with both `core.autocrlf=true` and `false`, without changing the shared Git index. This is evidence preservation, not full-application clone qualification.

## Acceptance and remaining work

The known X8 software admission and hand-launch integration failures are closed. Conventional and legacy X8 compatibility is supported by the retained trajectories, not a universal cross-platform equivalence claim. No physical parameter tuning or new aerodynamic force law is introduced.

The accepted X8 model still uses one aggregate vertical element for its winglets. Resolving separate winglet gradients requires an aircraft-model change and separate validation. Full-angle spatial aerodynamics, spectral calibration, pilot gates W-A/W-B, longer maneuvers, thermal meteorology, terrain/obstacle flow, weather transitions and shared companion admission remain open. The interactive default remains legacy gentle-practice; Calm is preserved.

No new performance claim is made. Another track's full test suite was active on the host, so this slice does not repeat timing measurements or close the 240 Hz/1080p gates. Next performance work remains a controlled full-session comparison with active gusts/thermals, followed by measured stage-receipt overhead work with explicit model/cache ownership. Removing an absent-tail query is correct geometry, not permission to omit real force points or reduce simulation frequency.

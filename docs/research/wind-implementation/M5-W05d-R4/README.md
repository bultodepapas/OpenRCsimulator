# M5-W05d-R4 — lean stage Air receipts

2026-10-26. Owner: M5-W. [Wind guide](../../../WIND-PLAN.md), [preceding compatibility fix](../M5-W05d-R3/README.md), [earlier profiling and performance limits](../M5-W05d-R2/README.md).

## Change and contract

Production `FlightSession` used `WindAircraftFlow.stage_air` at four boundaries: ordinary force stages, runway residual candidates, hand-launch motor initialization, and checkpoint candidate validation. Each caller used only `ok`/`air`, but every call also assembled and returned full diagnostic station positions, winds, relative velocities, copied geometry and an index dictionary. Repeated wash-point queries also resliced the same body pose and recomputed the same quaternion conjugate.

Two runtime files change:

- `app/physics/wind_aircraft_flow.gd`: add the trailing optional `include_flow=true` argument. The default retains the existing full result; explicit false omits the top-level `flow` key. Public `sample()` remains diagnostic. Both routes share one private sampling loop, with the same calculations, validation, provider queries and failure behavior. The lean route retains the complete ambient delta array and the actual hub/intake relative velocity. The point sampler prepares detached position, raw body-to-NED quaternion and conjugate once for that stage.
- `app/sim/flight_session.gd`: the four production callsites explicitly request the lean result. They continue to consume the same Air contract. No force, integration, reset or checkpoint law changes.

The existing ephemeral receipt remains complete: exact body state/time/density, aerodynamic ambient deltas, propulsion point velocity, wake-source delta, retained sampler owner and callable. `spatial_sampler` is an opaque lifetime handle; its internal fields are not a caller API. The sampler's old body member is replaced by the detached pose fields. No in-repository consumer accessed that member. Neither full nor lean callers may mutate the retained context or reuse a receipt across stages, times or models.

The sampler uses the supplied RK-stage quaternion without normalization. Every real aerodynamic point is still queried in the same order, including the pusher/intake; X8's absent horizontal slot remains unqueried and zero. Local rigid-body velocity and ambient increments are still calculated and checked even when their diagnostic arrays are not retained. Failed/overflowing point flow therefore cannot become admissible merely because diagnostics are disabled. The existing sampler-owner reference keeps callbacks alive after the outer result is discarded.

There is no geometry/model cache, cross-stage cache, query RNG, new force, altered mode count, reduced physics frequency, aircraft tuning, default change or schema migration. Existing law identifiers remain valid; ORFL source fingerprints correctly change.

## Work removed and limits

For the current nine-slot layouts, lean stages skip three 27-element diagnostic sequences, the returned 27-element offsets copy, and the diagnostic/index dictionaries. They retain the same 27-element ambient delta computation and all local-flow checks. This describes logical packing/copy work removed; it is not a measured heap-allocation or percentage-speedup claim. Wash callbacks reuse the detached stage pose while continuing to evaluate wind at every requested physical point and held stage time.

Host inspection found other full test suites active, including ground-physics and lighting work. No timing benchmark was run alongside them. The change removes identified repeated work, but its net provider/full-flight cost and the 240 Hz/1080p gates still need quiet-host measurement. The stricter physics budget remains open. Test durations and headless verification are not performance qualification.

## Verification

The isolated candidate passes **1,993 checks plus four golden flights**:

| Program | Checks / failures |
| --- | ---: |
| `test_spatial_stage_lean` | 668 / 0 |
| `test_wind_aircraft_flow` | 88 / 0 |
| `test_spatial_powered_stage` | 277 / 0 |
| `test_spatial_wash` | 30 / 0 |
| `test_spatial_weather_session` | 101 / 0 |
| `test_spatial_weather_trace` | 351 / 0 |
| `test_tailless_spatial_wind` | 121 / 0 |
| `test_tailless_spatial_session` | 77 / 0 |
| `test_spatial_aero_continuation` | 91 / 0 |
| `test_spatial_wind_aerodynamics` | 189 / 0 |
| `test_golden` | 4 tapes / 0 |

The new test compares full and lean Air fields byte-for-byte across all twelve catalog ideal/pack configurations, uniform and manufactured linear fields, both aero entrypoint laws, nonzero body rates and slightly nonunit quaternions. It also compares finite force/moment bytes and complete provider query traces during receipt construction and wash loading. The default diagnostic keys/shapes remain covered. Other cases exercise detached inputs, retained callback lifetime, interleaved stages and times, malformed callback arms, failed callback samples, malformed state/geometry/environment/time/law/density, missing hub, qbar overflow, and failure at each datum/station query. Numerical overflow uses explicitly manufactured finite geometry/rates, not modified aircraft data.

An initial overflow test incorrectly assumed that large finite angular rates alone overflowed the actual trainer's arms; both routes correctly accepted those finite values. The corrected fixture uses a detached, longer tail arm to create an actual overflowing cross product. The failed receipt is retained; runtime validation was not weakened. The independent reviewer found no blocker in the final two-file diff.

The existing spatial trace test now accepts an optional `--aircraft=<res-path>` argument, retaining Jensen as its default. This reuses the existing recorder, analytic wind checks and exact replay for an additional Extra 300S baseline, rather than introducing another recorder.

[Twelve preserved baseline recordings](replays/parity.json) cover six conventional legacy flights, Jensen and Extra in spatial wind, and both X8 variants in spatial airborne/hand-launch routes. They retain **2,172 CSV rows**, with every cell unchanged in the final candidate. Exact baseline replay completes with `solver_changed=false`; candidate replay completes with `solver_changed=true`. Candidate comparisons are open-loop solver experiments, not exact-replay or physical-validation claims. ORFL packets, events/markers where present, complete CSV exports and reports are retained in `logs/` and `replays/`. The X8 cases include active gust/turbulence; the conventional spatial trace cases use the neutral height profile. Longer maneuvers and stronger thermal/gust combinations remain qualification work.

After integration, the shared-tree lean test passes 668 checks and the spatial session test passes 101. [Before](integrated-before.json) and [after](integrated-after.json) source observations match. Three unrelated aircraft-contract/data/hull-support sources differ from the isolated candidate and were preserved. The controlled comparison is the isolated experiment, not an assumed shared HEAD. No whole-repository suite or new pilot/physical acceptance is claimed.

## Reproduction and identities

Pinned engine: `4.8.beta1.official.4d10419ca` on Windows. Baseline commit: `eed518c86f0fda8a6d9f03b9b797cd15a88b7ca6`. [Baseline](baseline-manifest.json) and [candidate](candidate-manifest.json) manifests bind all 157 physics/simulation/failure sources. Exactly the two runtime paths above differ.

| Solver | SHA-256 |
| --- | --- |
| Baseline | `3ff1a8a311cdae4e9cf784dbfb30653ae8cfaf6428483489722c99648cf3a94f` |
| Candidate | `4b3a269239a22c8dc08bad00e51e11c36df33441b3bbc5df460bc1e8ef67fb0b` |

Create disposable checkouts of the baseline commit. Run `restore_sources.py --repo <repository> --destination <checkout>` for baseline, adding `--candidate` for candidate. The helper restores recorded line endings and retained source overlays and verifies every source hash plus the solver fingerprint. `candidate-source/` retains the two changed runtime files; `verification-source/` retains both test changes. Import each reconstructed app with the pinned engine before testing.

Use the existing [checked runner](../../../../tools/godot/README.md) and [flight-log workflow](../../../FLIGHT-LOGGING.md). Retained runner reports contain the original commands; replace local `tmp/wind-stage-r4` paths with the reconstructed paths. `compare_replays.py` records the original orchestration. For solver comparisons, hold aircraft JSON fixed and use the CLI's explicit candidate mode. [Payload hashes](payload-manifest.json) and [fresh evidence-only checkout checks](checkout-verification.json) protect the retained bytes under both Git autocrlf settings; they do not qualify a full application clone.

## Next gate

Repeat controlled full-session timing with active gust agendas and thermals on a quiet host, preserving modes, points, fixed-step frequency and input tapes. Measure receipt construction and repeated wash sampling separately before changing immutable model ownership or introducing caches. Wind evolution, spectral/physical calibration, terrain/obstacle flow, thermal heating, pilot gates and shared companion admission remain open in the wind plan. Spatial presets stay opt-in and Calm remains available.

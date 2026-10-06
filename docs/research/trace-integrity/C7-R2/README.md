# C7-R2 — active flight metadata

2026-10-06 · **Status: implemented and verified.** Scope: [C7-R2](../../../../ROADMAP.md#audit-repairs).

## Verified defect

`FlightSession.trace_meta()` labels every aircraft `no propwash`. However,
`Dynamics._load_components()` adds slipstream loads when the loaded propulsion
dictionary contains that configuration. The P-51 enables it. Its RPM also evolves
through shaft torque balance, while Stik/Extra use throttle lag and Avanti uses
the turbine ECU/spool model. The old header distinguishes none of these paths.

The active CSV schema is `openrc-trace v3` (34 columns); AGENTS still says v2.
The existing aircraft hash is SHA-256 of Godot's sorted-key JSON serialization
of parsed input, with default float precision. It is not an exact file hash;
DATA-3 remains responsible for exact input identity.

Inspected: `sim/flight_session.gd`, `sim/trace.gd`, `sim/recorder.gd`,
`sim/simulation.gd`, `physics/dynamics.gd`, `physics/aero.gd`,
`physics/propulsion.gd`, `physics/turbine.gd`, `physics/aircraft_data.gd`.

## Implemented contract

CSV columns and dynamics stay unchanged. `metadata_schema: openrc-flight-meta v1`
versions the new header contract separately from `openrc-trace v3`.

| Header | Meaning |
| --- | --- |
| `aero_model` | Global derivatives when the envelope is absent; otherwise local surfaces with bounded attached oracle |
| `propulsion_model` | Propeller RPM lag, propeller shaft balance, or turbine ECU/spool; selected from loaded configuration |
| `propwash_model` | Tail slipstream increment when configured; otherwise none |
| `propulsion_features` | JSON booleans for propeller normal force/P-factor, rotor gyroscopic coupling and turbine ram corrections |
| `engine_rpm_semantics` | Propeller shaft RPM or turbine spool RPM |
| `state_layout`, `aux_layout` | Ordered JSON column names, owned by the rigid-body/session state definitions |
| `recording_start_tick`, `recording_start_aux`, `recording_start_engine_running` | Snapshot when recording begins, including a mid-flight T-key recording; independent of the original trim |
| `aircraft_data_hash_convention` | Names the existing sorted-JSON hash and its precision limitation; preserves the old hash field |
| `loads`, `state_timing` | Tick 0 evaluates reset state/aux; later loads use state k−1 with updated aux k, while rows contain state k |

Model names describe **configured paths**, not whether they generate nonzero
forces at that instant. A glide still declares its propulsion model and separately
reports the engine stopped. Layouts and auxiliary values are JSON; auxiliary
serialization requests full float precision, but decimal parsing is not promised
to reproduce every bit (the engine probe observed servo differences ≤1.4e−17).
The CSV still stores nine decimal places. DATA-3 and H8/H9 retain exact identity
and replay/checkpoint responsibilities.

Compatibility: existing CSV readers that ignore unknown comments retain the same
34 columns. The current `check_trimmed_flight.py` smoke gate requires the versioned
header and checks layouts, model identifiers, feature types/consistency and the
start snapshot against the first row. Historical unversioned headers fail that
gate; they remain readable CSV, not newly accepted comparison evidence. Golden
flight data is unchanged. Unknown metadata schemas require explicit reader work.

## Verification

- `test_trace_metadata.gd`: 128 checks pass across four aircraft, reloads,
  recording at tick 12, full layout-to-row mapping, stable snapshots, same-ID
  configuration changes and engine-off glide.
- Two focused process tests pass: all four real app headers and rejection of
  missing, malformed or internally contradictory metadata.
- Four three-second source flights have byte-identical numeric CSV against the
  pre-change C7-R1 baseline. [Flight evidence](flights.json) stores the hashes,
  old aero label and full corrected headers.
- Isolated Windows/Linux/macOS exports succeed. All four Linux exported flights
  pass the current checker and match source numeric rows and model metadata.
  Windows/macOS packaging checks pass; native gameplay on those OSes was not run.
- Full `app/test.sh` passes: 161 scripts parse, 60 GDScript test programs, 11
  trace process tests, and identical state hashes at 30/60/144 FPS. Static lint
  stays at zero errors and 11 pre-existing warnings. [Verification record](verification.json).

This verifies evidence plumbing; it does not validate aircraft fidelity, create
a complete replay checkpoint, or close the owner/GPU/radio gates. No external
research was needed: the configured branches are established by the source and
executed tests above.

## Reproduce

From the repository root:

```bash
app/test.sh
$(app/get-godot.sh) --headless --path app -- --aircraft=p51d-mustang-120 --trace=/tmp/c7-r2.csv --t=3
python3 app/tests/check_trimmed_flight.py /tmp/c7-r2.csv --duration=3
```

Repeat with the IDs in [flights.json](flights.json). For the before/after proof,
capture the same commands from C7-R1 (`e3eb8d9`) in a separate checkout, remove
comment lines and compare CSV bytes. `app/export.sh` verifies all desktop packs;
run its Linux binary with the same trace arguments from outside the source tree.

Suggested commit message:

```text
fix(trace): describe active aircraft models and recording state (C7-R2)

Proof: 128 metadata checks, real-app header mutation checks, full app/test.sh,
desktop exports, and four source/export flights with unchanged numeric CSV.
```

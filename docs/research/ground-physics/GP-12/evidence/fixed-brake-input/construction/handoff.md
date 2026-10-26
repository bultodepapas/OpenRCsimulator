# GP12 fixed-gear shared brake — review handoff

Detached only. No app source, stock aircraft/profile, shared documentation,
staging or commit was changed by this task. `review.patch` applies cleanly to
the three exact prehashes in `promotion-manifest.json`; all new paths must be
absent before guarded installation. The manifest has ten payloads.

Final selected checks: production-test projection 256/256, focused Python role
inspector 13/13, six retained ORFL candidate tapes 30/30 across 96 ticks. The
six original files retain their exact hashes. Every tape reports solver_changed
true; row equality is a bounded candidate result, not exact-source equivalence.
`review-receipt.json` pins terminal strict receipts and `loaded-source-pins.json`.
The earlier 140/237-check runs are earlier/subset scopes, not additional unique
acceptance. Repeated 256-check draft/projection receipts are separate executions.

Runtime changes are limited to hardware-aware Session input admission/mapping,
conditional fixed-law checkpoint/configuration/metadata, Main B eligibility,
and legacy Trace v17. All force arithmetic remains owned by existing laws.
Positive external demand requires hardware. A zero release remains admitted
without it, including after accepted unbraked reload; an invalid mixed packet
cannot partially apply controls/release. The old unsupported fixed-turbine Trace
case stays refused when the new law is absent.

The permanent output-hash fixture is derived from the unchanged OLD Session
SHA2bc02a0f… and Trace SHA1c529262…; it is read-only in the proposed test. Only
created_utc is replaced by a declared fixed presentation sentinel. The original
wall-clock-dependent fixture and failing projection receipts remain retained;
physical checkpoint and continuation hashes did not change in that correction.
No candidate/current source regenerates expected hashes after installation.

Synthetic inputs are generated at test time by Data.validate_and_derive and the
existing WheelProfiles custom-path loader. Torque provenance explicitly says
software fixture, not stock calibration. Runtime-created tmp profile/authoring/
CSV/log files are outputs, never preexisting input dependencies. The only
installed test inputs are the permanent frozen hash and CSV fixtures in payload.

Path transformations for installation: detached Session/Trace preloads become
res://sim paths; Main preload becomes res://sim/flight_session.gd; the focused
input-only Main subclass becomes res://tests/fixtures/fixed_brake_main_input.gd;
expected hashes become res://tests/fixtures/fixed_brake_legacy_outputs.json.
`test_projection.gd` reverses only those resource bindings to the reviewed draft
while executing the actual proposed test body. It passed strict 256/0.

After guarded promotion, production commands from the repository root:

```
python tools/godot/run_checked.py --warnings-as-errors --require-text "Fixed brake candidate: 256 checks, 0 failed" --timeout 180 --out tmp/gp12-fixed-brake-production -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --audio-driver Dummy --path app --script res://tests/test_fixed_gear_brake_input.gd
python -m unittest discover -s app/tests -p test_fixed_brake_trace_contract.py
```

`app/test.sh` automatically parses the new GDScripts and discovers the new top
level test_*.gd in its existing unit shard loop; no GDScript registration is
needed. The new Python test needs an explicit existing integration-partition
invocation to become a full-suite gate. No app/test.sh edit is in this payload.
Suggested existing selected regressions are retractable gear/Trace, flaps
Session/UI, Trace, ORFL inputs/replay and the complete endpoint tests. No broad
suite was run or claimed here.

See consumer-matrix.md for v17 support. The focused shape/role inspector states
physics_validation_available=false. Existing physical validators remain
fail-closed; no brake command is stripped to pass an old equation oracle. Stock
authoring, differential/airborne braking and physical braking calibration remain
outside this slice.

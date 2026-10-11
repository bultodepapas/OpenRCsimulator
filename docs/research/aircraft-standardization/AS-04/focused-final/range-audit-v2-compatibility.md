# AS-04 — Propeller range-audit v2 compatibility

2026-10-11 · Prefix: AS-

**Status: Passed.** The offline range auditor now accepts `openrc-aircraft v1` and `openrc-aircraft v2` inputs for `glow_prop` only. Historical v1 input may still omit `propulsion.kind`; v2 must declare it. Turbine and electric propulsion remain unsupported.

Trace metadata must declare the same aircraft format as the hashed input. Exact input-byte SHA-256 validation and coverage-to-aircraft hash binding remain strict. Coverage stays `openrc-propeller-coverage v1`; trace stays `openrc-trace v3`.

The 23-test suite passed. A parity test compares the production Jensen Ugly Stik v2 propeller extraction and audit results with its reviewed `migration.legacy_input()` view. Negative cases cover unsupported aircraft versions, missing v2 propulsion kind, electric propulsion, mismatched trace format, and a mismatched v2 input hash. `git diff --check` passed. Godot was not needed for this offline tool change.

Console output and source hashes: [focused test log](range-audit-v2-compatibility.log).

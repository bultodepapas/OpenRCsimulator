# D1-R2 — strict shaft power-table validation

2026-10-06 · **Status: implementation in progress.** Scope: [D1-R2](../../../../ROADMAP.md#audit-repairs).

## Confirmed defect

The P-51 shaft power curve bypasses the shared table validator. On baseline
`56416cf`, the [loader probe](probe.gd) accepts numeric strings, missing `kind`,
missing `source`, in-memory NaN power and an infinite final RPM
([results](before.json)). The last two extend the original audit's demonstrated
coercion/provenance gap; they do not mean the checked-in aircraft data is corrupt.
NaN/Infinity probes exercise the public in-memory validation entry point, not
standard JSON literals.

Inspected: `AircraftData._shaft`, `_xy_table`, `_q`, full loader error handling,
the P-51 generated curve and `FlightSession` startup/reload guards. The existing
`_xy_table` already requires numeric finite pairs, increasing x, units and
provenance. Reuse it, then retain the shaft's strictly positive RPM/power rules.
No new physical upper bounds or aircraft-data edits are needed.

## Change and focused proof

`_shaft` now uses `_xy_table` for shape, numeric types, finiteness, increasing RPM,
units and provenance, then requires positive RPM/power. Shared table unit checks
now require a string before comparison: numeric/list units previously raised a
GDScript operand error instead of reporting invalid data. Valid table flattening
is unchanged; no schema version, generated aircraft data or flight equations change.

- [After probe](after.json): all five formerly accepted invalid inputs are rejected
  with `propulsion.engine.shaft.power_curve` in their diagnostics.
- `test_shaft_data.gd`: 117 checks pass. Covers missing/malformed metadata and
  rows; bad types/NaN/Infinity in both columns at first/middle/last rows; positive
  and ordering constraints; valid mixed integer/float pairs and all evidence kinds.
- File/session checks refuse an invalid initial aircraft, prevent resume, and
  preserve the active model, trim, state, auxiliaries and clock on failed reload.
- [Four real app flights](flights.json), three seconds each, pass the current trace
  checker and retain the exact numeric CSV hashes recorded for C7-R2.
- Full app suite pending. Static lint: zero errors, same 11 baseline warnings.

This repairs input acceptance, not shaft dynamics or independent flight fidelity.

## Reproduce

From the repository root:

```bash
$(app/get-godot.sh) --headless --path app --script res://tests/test_shaft_data.gd
$(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/aircraft-validation/D1-R2/probe.gd" -- /tmp/d1-r2-probe.json
app/test.sh
```

Run the probe in a separate checkout at `56416cf` for the before result. The
probe mutates in-memory copies; the test's temporary JSON lives in `user://` and
is removed after use. Source and tests are repository-owned; no external data
or new dependency is introduced.

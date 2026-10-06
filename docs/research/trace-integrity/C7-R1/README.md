# C7-R1 — Complete, finite flight-trace acceptance

2026-10-06 · **Status: implemented and verified.** Implements [ROADMAP C7-R1](../../../../ROADMAP.md#audit-repairs). Baseline: `v0.1.0-rc4` (`bf16ab9`). The [audit](../../project-audit-2026-10-06/README.md#confirmed-bug-the-appexport-trimmed-flight-acceptance-can-pass-without-a-flight-or-with-nan-results) remains the historical finding.

## Change

- The `--trace` route validates its path and duration before building the scene. Duration must be numeric, finite and positive, round to at least one physics tick, and fit the signed tick counter. Default: three seconds; positive half-ticks round up.
- Recording starts at tick zero in a valid flight. Every requested step must advance exactly once without a simulation fault, and the recorder must receive every sample. Failure exits nonzero without saving a partial trace or overwriting an existing file; a save error also fails the process.
- `check_trimmed_flight.py` checks the v3 columns, finite values in every numeric cell, sample count, tick continuity, time at every sample, and the declared tick interval before the existing trim/ground checks. Expected duration and tick rate come from the caller, not the trace endpoint. Defaults remain three seconds and 240 Hz.
- App tests and export smoke request three seconds explicitly; the capture trace requests 1.5 seconds. A request of 0.01 seconds at 240 Hz rounds to two ticks: the initial sample plus two simulated samples.
- Numerical-fault injection exists only in the excluded test fixture `probe_trace_failure.gd`; the shipped app has no fault-injection option.

## Verified evidence

[regressions.json](regressions.json) compares the released checker with this repair using mutations of a genuine rc4 trace:

| Input | rc4 exit | Repaired exit |
| --- | --- | --- |
| Complete three-second flight | 0 | 0 |
| Initial sample only | 0 | 1 |
| NaN in final altitude, speed, pitch and RPM | 0 | 1 |

The nine process tests pass inside `app/test.sh` (37 s on this host). The complete suite passes: 160 scripts parse, 59 GDScript test programs, model contracts, golden flights, app traces and identical state at 30/60/144 fps. The static linter reports zero errors and the same 11 pre-existing warnings. [Check summary](verification.json).

The process tests additionally cover truncated/extra samples, NaN in every column, Inf at the beginning/middle/end, duplicate/skipped/fractional ticks, bad clocks/schema/metadata, trim drift, invalid CLI durations/paths, rounding/defaults, write failures, and injected initial/first/last-tick or missing-recorder-sample failures. Existing output survives failed recording.

Windows, Linux and macOS exports passed from an isolated clone with the repair applied: packaged field/tree resources, build identity, Linux smoke, Windows version fields, and macOS universal/ad-hoc-signature checks. [exported-flights.json](exported-flights.json) records additional runs of the repaired Linux export for all four aircraft: 720 ticks, 721 finite samples, three seconds each. Numeric CSV rows are byte-identical to the downloaded rc4 binaries; only metadata such as build identity/time differs. This change does not alter flight dynamics.

## Reproduce

```sh
python3 app/tests/test_trace_acceptance.py
app/test.sh
app/export.sh
$(app/get-godot.sh) --headless --path app -- --trace=/tmp/C7-R1.csv --t=3
python3 app/tests/check_trimmed_flight.py /tmp/C7-R1.csv --duration=3
```

Run exports in an isolated checkout to preserve other local build artifacts. The full rendered capture suite is not required for this trace-only change; its 1.5-second trace contract is covered directly. These are software integrity checks, not aerodynamic validation. Active-feature metadata and exact aircraft-file hashing remain C7-R2/DATA-3.

## Commit message

```text
fix(trace): reject incomplete and non-finite flights (C7-R1)

Proof: app/test.sh; 9 process tests; isolated three-platform exports;
four exported flights retain byte-identical numeric rows against rc4.
```

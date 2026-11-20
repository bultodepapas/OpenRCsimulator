# Round-three retained evidence

The [report](../round-3.md), [evidence index](../round-3-evidence.json), [source identities](../round-3-source-identity.json) and [portable runner](../../../../research/performance/audit-2026-11-19/round3/README.md) define the scope.

`runs/` contains the **13 final checked launches** from the consolidated reproduction package. Logs and receipts retain their original bytes and paths. Zero engine errors were recorded. The current auto-calibration control has one ObjectDB-at-exit warning; the remaining launches have zero warnings.

`exploration/` contains **nonqualifying attempts**, including missing-asset/class-cache/dependency setup, incomplete probe iterations, a loading-fixture exit timeout and a ptrace rejection before Godot started. Their failure is not evidence of an additional production bug. They are excluded from the final launch count and positive conclusions. Earlier successful exploratory checks were superseded by the consolidated collection.

The timestamp and absolute paths in receipts describe the collecting environment. The user-facing report date is 2026-11-19 in America/Bogota; collection timestamps are UTC. Fixtures, injected values and stand-ins are described in the manifest and report. The logs establish the stated component observations, not a GPU, native-backend or full-game performance result.

Raw engine logs preserve whitespace emitted by the checks so their recorded byte hashes remain valid.

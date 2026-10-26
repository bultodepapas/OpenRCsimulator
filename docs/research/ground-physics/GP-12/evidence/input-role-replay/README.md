# GP-12: recorded input roles

2026-10-26. `FlightLogCLI.input_names` validates channel meaning before CSV creation;
`prepare_replay` independently compares recorded and installed roles after checkpoint
restore. Numeric width alone cannot distinguish a future fixed brake from flaps or
retract commands. Historical absent-layout logs retain the original 4/5/6/7 meanings.
Declared layouts must have the exact supported order, strings and feature indices.
Invalid JSON is refused without an engine error.

The explicit `fixed-gear-shared-wheel-brake-input-v1` reader branch requires named
inputs and brake index4 and rejects conflicting gear metadata. It enables **no
aircraft hardware, force, Session input or keyboard behavior**. Actual fixed-brake
Session/trace/Workshop admission remains pending. The log writer and simulation
sources are unchanged, so this tool-only change does not alter solver identity.

## Verified scope

| Check | Result |
| --- | --- |
| Installed role contracts and six actual stock recordings | 232 assertions, 0 failures |
| Existing flight-log suite, six aircraft and 260 ticks each | 3,247 assertions, 0 failures |
| Independent malformed-selector review | 48 assertions, 0 failures |
| Python wrapper tests | 16 tests, pass |

Both installed Godot scripts ran with warnings-as-errors and zero engine diagnostics.
The 232-check suite includes all 17 initial/stepped numeric samples for each of six
16-tick recordings, exact replay, valid-checksum hostile role edits, detached inputs,
future layouts and a frozen original complete-column oracle for widths4/5/6/7.
The JSON oracle hash normalizes CRLF to LF, preserving ordinary checkout portability.
The existing suite also checks observer equivalence, bounded recording, reset closure,
corrupt/truncated files and refusal to overwrite. These are software checks, not
physical calibration or a full application-suite result.

Independent review caught a typed-Variant comparison bug before promotion: a nonstring
law selector logged an engine error despite process exit0. The rejected source and
checked-runner failure remain under `independent/`; exact TYPE_STRING validation and
14 additional root assertions corrected it. The earlier218 and final232 root counts
are separate revisions, not additive independent evidence. Draft232 repeats installed232.

`recordings/` retains the six complete installed fixtures plus one deliberately
mislabelled, checksum-correct file that must be refused. Full260-tick raw recordings
remain in ignored tmp; their numerical verification report is retained here. The
selected source snapshots and source fingerprints do not constitute an entire
repository closure. Construction scripts retain historical absolute paths and are
not general user tools; rerun current tests through the repository checked runner.

`manifest.json` binds every payload; folder attributes preserve raw evidence bytes.
No physics golden flight was re-recorded. No stock advanced contact was enabled.

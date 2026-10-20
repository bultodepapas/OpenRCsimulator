# VQ-01c / PT1h-R3 diagnostic evidence — 2026-10-19

The [tool guide](../../../../../research/performance/README.md#cpu-gpu-and-memory-diagnosis)
owns usage. This record validates opt-in observation, bounded collection and
offline diagnostic accuracy; it does not establish physical or hardware
performance acceptance. The shared worktree/host had concurrent work.

## Native smoke

Godot 4.7.2, Windows Compatibility/OpenGL, RTX 3090, Ryzen 9 5900X, 1280×720,
60 FPS cap, Dummy audio, scripted route, requested one-second warm-up and
three-second sample. The capture completed with 182 retained frames, 180 positive
GPU samples and two zero/unknown samples. No invalid numeric readings were
reported. Final observer metadata records `stopped=true` and
`viewport_measurement_enabled=false`.

The polling/merge bracket measured median 29 µs and maximum 55 µs. This excludes
driver instrumentation, sample retention and report serialization and is not a
general overhead guarantee. No profiling-on/off speedup or acceptance claim is
made. Wall p95/p99 were 16.847/17.032 ms; the explicit 16.667 ms investigation
threshold counted 91 over-budget intervals in 64 bursts. Tight thresholds near a
60 FPS cap naturally include small scheduling differences; those counts alone do
not establish a performance defect.

- [Raw native frame report](native-run.json.gz): original bytes, gzip compressed;
  includes runtime source/config identities and raw metrics.
- [Combined engine log](native-engine.log.gz): includes the existing maple-tree
  material/wind warning and its source location; no engine error was hidden.
- [Checked invocation](native-check.json.gz): process exit zero, complete capture,
  no engine errors and one warning under the default non-strict warning policy.
- [Offline diagnosis](native-diagnosis.json): explicit budget, worst-frame
  locations/context, memory deltas, warning details and measurement limitations.

The report's captured SHA-256 values for `main.gd`, `frame_samples.gd` and
`frame_diagnostics.gd` were matched against the reviewed runtime sources before
retaining evidence. `code_revision=unavailable` remains disclosed; source hashes
identify the working-tree bytes rather than asserting a clean commit. Absolute
paths in receipts describe the original machine; decompress into a fresh folder
and supply the relocated JSON/log explicitly to repeat the reduction.

## Regression campaign

- Collector: 86 checks on native Windows and WSL Linux, including exact frame-limit
  completion, incomplete retained prefixes, warm-up exclusion, invalid options and
  consistent metric shape.
- Observer: 23 checks on Windows headless/native and Linux headless, including
  unavailable timing, finite fallback with invalid counts, repeated stop and a
  freed viewport. Native Windows rendering is also exercised by the production
  smoke above. macOS behavior was not executed.
- Offline reducer: 23 Python tests, including a known hitch, exact budget boundary,
  contiguous burst counts, same-index context, memory deltas, absent/zero GPU data,
  inconsistent capabilities, invalid observer readings, malformed/nonfinite input,
  combined byte limits, log errors/warnings and destination preservation.
- Existing native-summary and visual-capture reducers: 17 and 25 tests respectively
  passed on Windows. The 17 native-summary tests also passed on Linux.
- Production CLI: diagnostics off, headless diagnostics on, and a two-frame
  retention failure passed on Windows. The latter exits nonzero and writes exactly
  the incomplete two-frame prefix. Linux follow-up results are recorded below.

The first Linux CLI campaign passed the two diagnostics-enabled cases but the
cold diagnostics-off case reached its 90-second process deadline before any frame
report was written (73 log bytes, zero engine diagnostics, `complete=false`).
The functional harness deadline was increased to 180 seconds for the full scene
and source-provenance work on a Windows-mounted checkout. Frame sample durations,
limits and performance gates were not relaxed.

The diagnostics-off Linux rerun passed in 53.336 seconds with the updated deadline;
all three CLI scenarios are therefore verified on both platforms. Seven shell
partition regressions passed after integration wiring. The final 23 offline
diagnosis tests passed on Windows and Linux, including a parent-added overflowed
metadata case that must still publish an invalid verdict. The existing checked
runner/summary discovery ran 41 tests on Windows: 37 portable checks passed and
four optional engine checks were skipped in that invocation; the three new capture
cases were exercised separately as described above. Retained JSON/log hashes agree with
the checked invocation and diagnosis; edited Python parsed, documentation links
resolved and `git diff --check` passed.

The GDScript observer test is picked up by the existing unit-script partitioner;
the production CLI checks run in `app/test.sh`'s integration partition. The offline
reducer tests run in `research/test-tools.sh`. Full project CI, exports and extended
native performance runs are outside this focused verification.

## PT1h-R4 resource and storage evidence

Verified 2026-10-19 with Python 3.11.9 / native Windows, Python 3.12 / WSL Linux,
psutil 7.2.2 and the pinned Godot 4.7.2 engine. Usage is documented in the
[resource tool guide](../../../../../tools/godot/README.md#process-ram-io-and-storage-pt1h-r4).

The final native Windows **headless** production capture ran the scripted scene,
one second of frame warm-up and three seconds of frame capture. OS sampling spans
startup through exit: 19 samples over an 18.906-second checked invocation, using
the default one-second interval with thread counting disabled. It observed
606,187,520 bytes peak RSS (578.1 MiB), zero invalid/unavailable resource readings,
and one engine warning for the known unsupported maple-tree wind material. The
181-frame report completed. This is functional RAM/I/O evidence, not a GPU run,
leak diagnosis, hardware performance gate or physical validation result.

Recorded poll overhead was 2,628 microseconds median and 480,867 maximum. The
maximum demonstrates the cooperative OS-call limit. A separate parent-reviewed
backend profile isolated expensive Windows thread enumeration (about 14.5 ms
median) and occasional long swap queries; thread counting is therefore optional.
The default runner does not import psutil, query counters or write resource output.

The complete `app/` storage scan found 3,800 regular files, 694,497,971 logical
bytes (662.3 MiB), including 308,845,027 bytes of `.godot` imports and 209,035,318
bytes of assets. A cached Linux Godot binary under `app/.tools/` was the largest
individual file. Root-volume free space was 12,258,426,880 bytes, about 1.2%.
These are dated metadata observations of a shared working tree. No cleanup was
performed; logical file bytes do not describe allocated blocks or export size.

During an earlier capture the host's available RAM fell to 2,281,472 bytes.
The pressure series is retained separately; system pressure is not attributed to
Godot. Another initial run emitted a four-instance ObjectDB leak warning; a verbose
rerun and the final capture did not reproduce that warning. Both logs are retained.
The warning remains unresolved; neither a rising startup RSS nor a successful
process exit establishes a leak-free runtime.

| Verification | Result |
| --- | --- |
| Final Windows `unittest discover -s tools/godot -p 'test_*.py'` | 79 discovered: 75 passed, four optional Godot tests skipped. Production Godot capture executed separately above. |
| Linux full diagnostic suite before final clock/thread-option refinements | 78 discovered: 72 passed, four optional Godot and two Windows junction tests skipped. |
| Final Linux `test_resource*.py` | 21 passed, including the controlled allocation/write fixture and runner integration. |
| Controlled process accuracy | 32 MiB touched allocation, required RSS increase of at least 12 MiB, and at least 1 MiB observed write-counter increase where supported. Unsupported counters must remain null with a reason. |
| Storage failure regressions | Bounded traversal/errors, exclusions, exact fixture sizes, hard-link semantics, symlink/junction skipping, deterministic top-file ties and exclusive output. |

The parent tightened the final live fixture to take its baseline after the
interpreter's readiness handshake, excluding interpreter startup allocations.
That targeted accuracy test passed again on both Windows and Linux.

The new mock/filesystem tests run through existing discovery. CI's integration job
also installs the optional pinned backend to exercise real counters. Full CI and
exports were not executed in this focused change.

[resources-manifest.json](resources-manifest.json) identifies each compressed
artifact and its uncompressed bytes. `resources-native.json.gz`,
`resources-check.json.gz`, `resources-engine.log.gz` and `resources-frames.json.gz`
retain the final capture. `resources-storage-app.json.gz` retains the storage
scan. `resources-pressure.json.gz`, `resources-initial-warning.log.gz` and
`resources-verbose-recheck.log.gz` retain the earlier observations. Final resource
tool hashes match the reviewed source; the frame report supplies runtime source
identity. Decompress into a new folder for inspection; absolute paths describe the
original host. No golden flight was changed.

## PT1h-R5 incident packaging and timeline correlation

Verified 2026-10-19 with Godot 4.7.2, Python 3.11.9 on Windows, Python 3.12.3
on WSL Linux, psutil 7.2.2, and the official Windows
[Perfetto v58.2 release](https://github.com/google/perfetto/releases/tag/v58.2).
Current commands and limits live in the
[tool guide](../../../../../tools/godot/README.md#incident-bundles-and-perfetto-timelines-pt1h-r5).

The checked runner now supplies one UUID capture identity to the engine and its
resource report. Frame capture and resource sampling record monotonic/UTC anchors
at their start and end. Frame durations remain monotonic; UTC is only approximate
cross-process alignment. Both offline tools use standard-library adapters to
existing ZIP and Perfetto formats. No addon, logger callback, normal-play polling,
simulation change or golden-flight update was introduced.

The final native **headless** scripted run retained 181 frames over 3.016537 s
and 56 OS samples. Peak sampled RSS was 606,347,264 bytes. The checked invocation
passed with the existing unsupported maple-tree wind warning. Its bundle and
timeline both report complete. A separate deliberate two-frame retention limit
produced engine exit 1, two frames totaling 0.005714 s, and 38 OS samples. Both
offline tools returned 1 for that partial evidence and retained the failure.

The parent independently loaded both traces into Perfetto Trace Processor and
compared **every** imported frame timestamp/duration and RSS value with the source
reports. All matched, and the parser reported no import errors. A separate known
hitch fixture imported exactly `(start 0 ms, duration 20 ms)` and
`(start 20 ms, duration 100 ms)`. Both ZIPs passed CRC checks and every manifest
size/SHA-256 matched its stored bytes. This validates conversion and packaging;
it does not establish GPU performance, leak freedom or causal attribution.

Review and real captures caught and fixed three meaningful gaps: a valid resource
series incorrectly marked partial, an incomplete frame prefix incorrectly rejected
for being shorter than the requested duration, and a sampler-construction failure
publishing a malformed resource file. Failed sampler construction now explicitly
reports no published artifact while preserving the engine verdict. Tests also
cover mismatched capture IDs, clock drift/coverage, invalid and unknown metrics,
duplicate/malformed JSON, source mutation, links, budgets, missing/tampered files,
exclusive output and injected disk-full failures. Invalid observer counters are
omitted instead of drawing sanitized zero values as measurements.

Focused verification:

- Windows diagnostic suite: 119 tests, including actual-engine checks.
- Linux diagnostic suite: 119 discovered, 113 passed, six skipped (optional engine
  classes and Windows junction cases). All three real Linux frame-capture checks
  passed separately, including disabled diagnostics and the capped prefix.
- Frame collector: 86 checks passed on both systems; diagnostic observer:
  23 checks passed on Windows. Full project CI and exports were not run.

The four-instance ObjectDB warning recurred in the initial complete Windows run.
It did not recur in the verbose capped run or final delivery run. Its log is
retained below; the cause remains unresolved. A repeatable lifecycle-growth
investigation is still appropriate before claiming a memory leak or its fix.

[incident-manifest.json](incident-manifest.json) records artifact hashes and
reviewed source identities. The retained files are:

- [Complete incident ZIP](incident-delivery-incident.zip) and
  [failed-prefix incident ZIP](incident-capped-incident.zip): checked receipt,
  engine log, resource report, frame report and manifest.
- [Complete timeline](incident-delivery-timeline.json.gz),
  [failed-prefix timeline](incident-capped-timeline.json.gz) and
  [known-hitch trace](incident-known-hitch-trace.json.gz): decompress before opening
  in Perfetto.
- [Independent verification](incident-verification.json): exact import checks,
  clock uncertainty/drift, bundle results and trace-processor binary hash.
- [ObjectDB warning log](incident-objectdb-warning.log.gz): initial recurrence.

Resource attachments in bundles receive receipt/invocation integrity checks;
their numeric measurements are validated by the timeline exporter, not by the
packager. Optional `.orfl` attachments remain caller-selected and replay-unverified.

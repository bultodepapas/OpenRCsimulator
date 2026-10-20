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

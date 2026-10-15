# R11: atmosphere preferences fixture on a clean checkout

2026-10-15. The frozen Linux candidate's [second canonical run](../next-candidate/materialized-20261015-07-01/canonical-app-test-02.log) stops at three preference assertions. The fixture writes to `res://../tmp/` without creating that parent. The candidate excludes old scratch output, so the directory is absent. No atmospheric force or preference serialization defect is established by those failures.

The Linux diagnosis creates only the empty scratch parent and reruns the unchanged test: 96 checks, zero failures. The original canonical failure remains recorded; this focused retry does not make that canonical run pass.

The repaired fixture creates its own process-specific directory before saving and removes its own file/directory afterward. It retains all existing runtime assertions and adds one explicit setup assertion. Production preferences and atmosphere code are unchanged.

Root's separate physical Windows copy reproduces the old test with no scratch parent: [96 checks, three failures](old_clean.log). The new fixture starts from the same absent-parent condition and passes [97 checks, zero failures](new_clean.log). Neither qualified run has an engine/script error; no owned temporary file remains. The [receipt](verification.json) records commands, engine/input hashes and the sole source delta. [Previous fixture](previous-test.gd) preserves the original implementation.

An earlier reduced copy omitted a preloaded shader. Its [output](before.log) is retained as an incomplete-context attempt and excluded from the qualified comparison. The receipt adds the actual shader inputs before the paired old/new runs. This fixture repair is separate from the frozen Linux candidate; the canonical suite and remaining aerodynamic gates retain their reported status.

# GDU-03 application verification

2026-10-25, official Godot 4.8-beta1, native Windows. **All 709 unit scripts
have a successful checked invocation**, with no missing script. This is the
union of isolated partitions, the documented remaining-unit continuation loops
and focused corrected runs, not one uninterrupted `app/test.sh` invocation.
[Coverage](unit-coverage.json) lists the selected report/log hashes for every
script, its current test-source hash and the seven superseded failed invocations.
The later UI continuation has one separately excluded driver-marker mismatch;
its fresh accepted invocation is the selected result.

| Unit partition | Scripts covered |
| --- | ---: |
| 0 of 4 | 178 |
| 1 of 4 | 177 |
| 2 of 4 | 177 |
| 3 of 4 | 177 |

The existing checked-runner summarizer validates the completed collections.
Failure receipts remain separate evidence of the investigated defects; a later
passing run does not erase them. The [selected warnings](warnings.json) retain
29 input-validation, source-admission and budget-fallback diagnostics. The one
unexplained [test-owned tree node leak](../integration/tree-detail-cleanup/README.md)
was corrected and its verbose rerun no longer leaks.

Two existing experimental **physical** gates remain explicitly pending:
Stik rudder sideslip and the R02 yaw-alpha comparison. Their named suite flags
are unchanged. Successful script execution does not close those physical gates.

The suite copy at `D:/OpenRCsimulator-experiments/gdu03-suite` began with a
34,670-file source manifest and received recorded, controlled corrections.
Early partitions preceded the final core corrections. Separate
[numerical](../numerical/final-core/README.md),
[strict replay](../tooling/final-core/README.md) and
[companion](../companions/final-core/README.md) follow-ups validate those final
sources. Later UI/test corrections were checked from root while the unchanged
integration copy ran. After its EX-14h stop, five corrected scripts were copied
with a retained [overlay and final parse verification](overlay-verification.json).
All five parse successfully; the timestamped audit finds no content difference
across 3,344 selected tracked app files, apart from line endings in three shell
scripts. The original 1,300-script parse remains bound to its frozen sources;
no moving-source parse claim is made.

Two attempted concurrent Windows editor imports failed to copy the native
extension's shared hot-reload DLL. They ran no unit tests. The continuation
loops reuse the already successful import and keep separate user profiles;
the normal suite importer and all error checks remain intact.

The existing offline tool suite also passes: **559 unittest cases**, including
16 declared platform/opt-in skips. Its 24 test invocations and completion log
remain in the suite copy's `tmp/gdu03-offline/`.

The [integration partition](../integration/final/README.md) now has complete
logical coverage through its retained prefix and exact continuations. It
preserves the original Extra fit and obsolete tick-schedule failures, their
corrections and the separately validated expected CLI rejections. This is not
one uninterrupted suite pass.

Four later parallel UI edits remain separate from that frozen source. Their
[current-root checks](late-ui/README.md) pass livery 285, responsive 672,
aircraft flow and screen-stack lifecycle, with all 1,860 observed source/config
hashes stable throughout. Those four successful reports now supply the selected
unit results. The [final app audit](final-source-audit.json) accounts for the
four known late differences and finds no unexpected source difference.

The separate [package checks](../exports/README.md) pass for all three frozen
release archives, including actual Windows/Linux headless launch and a Windows
release capture at 1920×1080. They precede the late UI edits. Neither remote CI
nor release qualification is claimed here.

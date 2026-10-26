# GP-14b checked event cohort

2026-10-26 · Official Windows Godot `4.8.beta1.official.4d10419ca`, headless/Dummy audio. **Eight selected scripts, 453 checks, zero failures and zero engine diagnostics.** This is software verification, not full-suite, physical bounce/damage, native-audio or 1080p qualification.

[manifest.json](manifest.json) retains commands/receipts, source and engine hashes, review findings and the original pre-run promotion identity. The four promoted event-runtime/test hashes were unchanged at packaging. Other dependency snapshots were captured at packaging; this collection does not claim every repository dependency was frozen across all runs. Do not attribute these checks to later source edits.

| Script | Checks | Receipt |
| --- | ---: | --- |
| Shared events | 88 | [report](checks/events/report.json) |
| Existing accident classifier | 55 | [report](checks/accidents/report.json) |
| Real aircraft/session integration | 33 | [report](checks/live_session/report.json) |
| Statistics lifecycle | 51 | [report](checks/lifecycle/report.json) |
| Counter resets | 48 | [report](checks/resets/report.json) |
| Statistics store | 49 | [report](checks/store/report.json) |
| Background writer | 18 | [report](checks/writer/report.json) |
| Detector and explicit fleet coverage | 111 | [report](checks/detector_fleet/report.json) |

Every receipt has `complete=true`, `ok=true`, process exit 0 and the required zero-failure completion text. Aircraft-data provenance notices remain in the live log; they are not evidence of calibrated parameters.

The real Avanti test advances observed and unobserved simulations for 900 accepted ticks. The observed gear-up slide continues and emits one nonterminal semantic crash. Every body state and final complete kernel checkpoint match byte-for-byte. Rejected intervals emit nothing. Pure tests cover bounce grouping, terminal recontacts, unknown historical support, deterministic IDs, immutable subscribers, snapshot rejection, bounded persisted detail and continued subscriber delivery after detail overflow.

Independent Sol High review found terminal-edge omission and impossible checkpoint hop history. Both were corrected and tested; [review](review/gp14-events-review.md). The original detector suite also failed three fleet assumptions identically on unchanged baseline and candidate because the newly present X8 has no wheel profile. Both failing receipts are retained under `prior-failures/`. The revised suite retains all nine reviewed wheel profiles, explicitly checks both gearless X8 variants and their 28 stable hull IDs, and rejects future unreviewed entries. It does not invent belly-landing eligibility; [audit](review/gp14-x8-audit.md).

Reproduce using the [checked script runner](../../../../../tools/shared.md#one-godot-script) and exact commands in each report. Report paths intentionally identify the original main-tree run. Copies under `source/` identify the reviewed snapshot; `* -text` preserves evidence bytes across checkout newline settings.

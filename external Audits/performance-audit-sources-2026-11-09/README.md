# Original performance audit sources — 2026-11-09

These are the three supplied performance audit rounds, recovered and integrated
on 2026-11-15. For current implementation status, priorities, repository state and
qualification limits, read the [authoritative reconciliation](../../docs/research/performance-report-2026-11-09.md#current-reconciliation-2026-11-15).

| Round | Original report | Original patch | Evidence |
| --- | --- | --- | --- |
| 1 | [Mathematical performance review](OpenRC-performance-review.html) | [OpenRC-performance.patch](OpenRC-performance.patch) | [Compact round 1 package](../../docs/research/performance-audit-intake-2026-11-15/performance-evidence-round1-compact.zip) |
| 2 | [Performance follow-up](OpenRC-performance-followup.html) | [OpenRC-qualified-optimizations.patch](OpenRC-qualified-optimizations.patch) | [Public round 2 package](../../docs/research/performance-audit-intake-2026-11-15/performance-evidence-round2-public.zip) |
| 3 | [Senior-developer handoff](OpenRC-performance-handoff-round3.md) | Three candidate diffs are included in the report | Source analysis and validation plan; no executed candidate benchmark was claimed |

The two HTML reports and two standalone patches are byte-for-byte originals.
Their patch names reflect their historical qualification, not applicability at the
current revision. Several changes are now implemented; the old companion
endpoint-minimum rewrite is superseded by the interval-CPA implementation.
The Round 3 diffs remain historical proposals: its companion root omission is now
implemented, while its contact-key map and meadow metadata cache are unqualified
candidates. Do not apply a historical patch as a bundle to current main.

The Round 3 Markdown is a content export of the supplied Page titled
*OpenRC Simulator Performance Handoff Round 3 November 9 2026*.
It contains the Page title as an H1,
then all 148 Markdown blocks in their original order, separated by two newlines,
with a final newline. Page UI metadata, access settings and block IDs are not part
of the report. The exported Markdown SHA-256 is
`0618bc9ba3329a6f05a35c534be6c37430a45f67afce7474eb1cb5b4a3f8644b`.

[Packaging and per-member provenance](../../docs/research/performance-audit-intake-2026-11-15/README.md)
record source sizes, SHA-256 values, the three generated-file omissions from
round 1, and the two private attachment URL redactions in one archived ledger
snapshot from round 2. The five standalone source documents and all other retained
archive members preserve their exact original bytes. HTML can be downloaded for local viewing; Markdown is readable
directly on GitHub.

These continuations belong to the A33 performance thread. The existing A34
five-finding audit is a separate report and keeps its identifier.

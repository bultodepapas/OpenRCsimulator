# Performance audit source intake — 2026-11-15

The [current performance report](../performance-report-2026-11-09.md#current-reconciliation-2026-11-15)
owns findings, priorities and implementation status. This directory owns the
archival evidence and verification of its intake. Original reports and patches
are indexed in [external Audits](../../../external%20Audits/performance-audit-sources-2026-11-09/README.md).

## Contents

| File | Purpose |
| --- | --- |
| [performance-evidence-round1-compact.zip](performance-evidence-round1-compact.zip) | 280 retained members from round 1; exactly three generated-file omissions. |
| [performance-evidence-round2-public.zip](performance-evidence-round2-public.zip) | Public round 2 derivative, 471 members; two private attachment URLs redacted in one historical ledger copy. |
| [evidence-provenance.json](evidence-provenance.json) | Original archive and standalone document identities; all 754 original members with size, SHA-256 and disposition. |
| [PACKAGING.md](PACKAGING.md) | Exact package identities, exclusions and embedded-manifest interpretation. |
| [repository-state.json](repository-state.json) | Pinned main commit, source blobs, platform settings, draft PR heads, observed CI state and review limits. |
| [public-link-redactions.json](public-link-redactions.json) | Publication-required handling of personal attachment links in 25 older audit records: three repository-local replacements and 51 explicit omissions; all other text and citation query parameters preserved. |
| [integration-validation.json](integration-validation.json) | Intake checks and hashes of the staged deliverables; excludes its own self-referential hash. |

## Preservation and validation

All 751 retained members were re-read. Of these, 750 preserve their original bytes;
one historical ledger copy in round 2 has exactly two private ChatGPT attachment
URLs replaced with explicit omission markers. No other bytes in that member changed.
The external provenance manifest records both original and public member hashes,
without repeating the private URLs. Both original embedded manifests are preserved
as historical source records; use the external provenance manifest for the public
derivatives and their exact omissions or redactions.

The only file omissions are two generated Godot editor documentation caches and the
regenerable bulk Git-tree listing. No report, patch, benchmark, check log, fixture,
source snapshot or reproducer was excluded. Automatic publication review rejected
personal attachment URLs in the completed-work ledger and its inherited audit tree.
The branch therefore replaces three personal links with the recovered repository
copies and renders 51 other personal links as their displayed labels with an
explicit omission note. These 54 links span 25 older audit records; the manifest
above records their original and public identities without repeating private URLs.
The duplicate historical ledger snapshot in the evidence ZIP has its two URLs
redacted separately as described above. Original inputs remain unchanged. The original archive hashes and the
exact omitted-member hashes remain in the provenance record.

The report/patch standalone copies were compared with their archive members.
Round 3 preserves all 148 Markdown blocks from the original Page; its source
identity and export recipe are in the source index. All new and changed Markdown
links were checked for file targets and local heading anchors. Source links use the
reviewed commit where a line-specific claim must stay stable.

This intake ran content, provenance and package checks only. It did not run
Godot, import assets, build native kernels, change production code or create
new performance measurements. Prior evidence remains tied to its original
hardware, source, renderer, workload and qualification boundaries.

Archive integrity can be checked independently without extracting or executing
their contents:

```sh
python -m zipfile -t docs/research/performance-audit-intake-2026-11-15/performance-evidence-round1-compact.zip
python -m zipfile -t docs/research/performance-audit-intake-2026-11-15/performance-evidence-round2-public.zip
```

Use `evidence-provenance.json` for per-member byte identity, including the
round 1 omissions. The historical reproducer scripts are review material; choose
the current repository's checked-run and native admission workflows before
executing them.

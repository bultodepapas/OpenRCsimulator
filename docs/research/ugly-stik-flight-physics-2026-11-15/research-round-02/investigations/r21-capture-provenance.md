# R21 — Capture history must distinguish unknown from unchanged

**Decision:** integrate truthful coverage, image-integrity and receipt labels in the Python report; prototype producer-side accepted-source provenance separately. **Priority:** P1. **Baseline:** `08f0c08348395c0d6d9f7e224f66460828f59a7f`.

**Implementation update:** the report changes and positive observation counts are implemented on this branch. [Verification](../verification.md) records synthetic-state and real temporary-PNG checks, while [implementation review](../implementation-review.md) documents the independent challenge. No native scenario was rendered in this research round.

## Code and evidence

`app/scenery/runway_scenario.gd` writes a v1 manifest with aircraft ID, engine, adapter, timestep, start, views, times and sampled state. It does not write the accepted aircraft input hash, accepted power-source mode or full code identity. `tools/scenery/scenario_report.py::compare` joins by `(view, t_s)`, ignores previous-only keys and trusts declared image-hash equality. With no overlapping keys it can return `identical`; a repeated key silently overwrites a row. `history_index` uses `all()` over a missing/empty sync list, producing a green pass.

The [retained runway probe](../../follow-up-01/evidence/runway-evidence.json) demonstrates the metadata-path failures with synthetic manifests and intentionally no images. It must remain a historical observer, not be relabeled as a rendered test. The current wrapper preserves full images only in `latest` and `previous`; historical entries contain lighter manifests, sync records and filmstrips. History review therefore cannot retroactively verify deleted full-frame bytes.

## External research

W3C PROV separates entities, activities, agents and derivations so a data product can be related to the process and inputs that produced it ([LEAD-S06](https://www.w3.org/TR/2013/REC-prov-dm-20130430/)). We can use that distinction without adopting RDF or claiming PROV conformance: accepted aircraft bytes, simulation activity and rendered artifact are different identities.

Playwright's own snapshot guidance warns that render environment differences affect screenshots and recommends matching the baseline environment ([LEAD-S07](https://playwright.dev/docs/test-snapshots)). That is a useful comparison-design lesson, not evidence that a browser snapshot framework should test Godot. Identical pixels cannot establish identical accepted physics inputs; changed pixels can arise from renderer/environment differences. Keep those conclusions separate in the report.

## Selected integration

Index both frame rosters and reject ambiguous keys. Report matched, current-only and previous-only frames. A partial intersection may still show useful changes, but its overall verdict must state incomplete coverage; a zero intersection is not comparable. Report actual sampled-state differences and image differences separately from declared context differences. Compare known context fields such as aircraft, start, timestep, scenery, engine and adapter without claiming that equal fields prove identical source bytes.

A pair of absent accepted input hashes is `unknown`, not `same`. The report should explicitly identify the missing accepted-source fields in legacy v1 manifests. Adding guessed values from the current disk or from a catalog ID would falsify provenance. The producer extension must obtain identity and mode from the accepted live session, then be qualified with a native capture and a changed-input counterexample.

The independent review found an additional boundary: matching claimed image hashes can conceal missing or altered PNG files. Verify each matched image's actual SHA-256 before using the equality shortcut. Keep a clear evidence error for absent or mismatched bytes and dimension changes. This adds file reading, so no speedup is claimed. Full rendering is unnecessary to test these byte-level contracts; tiny generated test fixtures are sufficient, and their scope must be stated.

Retain the existing list-shaped sync receipt for compatibility. History requires the expected unique checks and boolean outcomes. Missing, empty, partial, duplicate or malformed receipts become `UNKNOWN`; a sound complete failing receipt remains `FAIL`. The independent review also demonstrated vacuous success inside the check generator, so new checks now record observation counts and an explicit outcome: no ground sample, cross-camera group or constant-RPM interval is `UNKNOWN`. Unknown outcomes remain `ok: false` for older consumers and return nonzero status. An observed failure takes precedence over an unknown observation. Complete legacy receipts without counts preserve their declared result with observation coverage explicitly unverified; their past measurement sufficiency cannot be reconstructed.

## Acceptance and future work

Use positive controls for unchanged pixels/state, changed pixels and changed sampled state; negative controls for no/partial overlap, duplicate keys, different aircraft, absent source identity, missing/tampered images and incompatible dimensions. Verify history labels for complete pass/fail and all incomplete cases. Test the actual PNG loading/diff path with temporary image fixtures. Preserve declared versus verified source distinctions in JSON and HTML.

A native 1080p-first capture qualification, accepted pack-versus-ideal identity, full expected capture schedule and per-check sample counts remain necessary before treating this fixture as representative of ordinary Home flight. The report repair cannot supply that missing experiment.

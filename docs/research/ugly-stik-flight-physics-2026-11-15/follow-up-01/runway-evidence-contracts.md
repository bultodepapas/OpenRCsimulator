# Runway comparison and history: synthetic report-integrity probe

At repository HEAD `00610ce3df391560dc195444d797bb81f2f83270`, the runway comparison report can claim **“identical” when no frame keys overlap or when a previous frame disappeared**. The history index can claim **“sync pass” when the sync receipt is missing or empty**. The same comparison also reports “identical” for synthetic equal frame rows with different aircraft IDs. These are confirmed output contracts of the unchanged report functions on deliberately constructed metadata, not an observed defect in a shipped capture or a rendered-flight result.

## Evidence and scope

On 2026-11-15, I executed the read-only Python probe [`runway_evidence_probe.py`](../../../../research/ugly-stik-audit-2026-11-15/follow-up-01/runway_evidence_probe.py) against `tools/scenery/scenario_report.py` from the audited checkout. Its imported source hash was unchanged before and after the probe:

```text
scenario_report.py SHA-256  45d9e9ecf59f7e0a4e676f5a5f826478c6b3cc6dc5d7954b13cd42a2ee1e2adc
probe script SHA-256        39488ee4aa499dfceac7ba549267514bdf2afe8eda7231f21010db7f246da3d2
JSON receipt SHA-256        742da5df0850195c12e131dacf5beec43f828199b2b65df0903126a386993cb9
result                      comparison_cases=5 history_cases=4 validation_errors=0
```

The retained receipt [`runway-evidence.json`](evidence/runway-evidence.json) contains all exact comparison manifests, returned dictionaries, history inputs, generated HTML, dependency versions, and source hash. Python was 3.12.14, NumPy 2.3.5 and Pillow 13.0.0. The zero validation errors mean **the audit's expected observations were reproduced**; they do not mean the reporting behavior passed a product acceptance test.

These are minimal synthetic dictionaries for direct calls to `compare()` and `history_index()`, not full captured scenario manifests passed through `main()`. Every declared frame digest is the same invented `a` repeated 64 times. There are no PNG files; the image-loading function was replaced by a failing sentinel, establishing that these calls did not decode or compare any image. State values are fabricated. Temporary run folders and history output were deleted after the calls, so temporary paths appearing in the receipt are descriptive only. No Godot engine, flight, capture, GPU, application UI, or full sync-check suite ran.

The probe can be rerun against the same unchanged snapshot using a new output path outside the repository:

```sh
python3 research/ugly-stik-audit-2026-11-15/follow-up-01/runway_evidence_probe.py \
  --repo "$PWD" \
  --out "$PWD/../audit_followup_runway_rerun.json"
```

The script intentionally expects the audited behavior; after a correction, a changed observation should make its validation fail. Replace it with acceptance tests for the new contract rather than preserving these labels as the desired behavior. When relocating the script and evidence, pass `--repo` explicitly and preserve the original receipt/source identity.

## Observed `compare()` results

Each key below is `(view, t_s)`; `P1` means `("pilot", 1.0)` and so on. For the same-frame controls, the two rows share both fabricated checksums and all sampled state fields. The aircraft-ID case changes only the top-level `aircraft` field. The positive state-change control changes `north_m` by `0.001` m, above `STATE_TOL` of `1e-6` m.

| Synthetic case | Current / previous keys | Observed verdict and emitted rows | Interpretation |
| --- | --- | --- | --- |
| Identical matched positive control | `[P1, P2]` / `[P1, P2]` | `identical`; two `identical` rows | The expected equal-sample path is working under these invented inputs. |
| Same rows, different aircraft ID | `[P1, P2]` / `[P1, P2]` | `identical`; two `identical` rows | The verdict does not flag different top-level aircraft IDs; it is only an output comparison for these sampled fields. |
| No overlapping frame keys | `[P9]` / `[P1]` | `identical`; one `new frame` row | There was no matched frame from which an identity verdict could be supported. |
| Previous frame removed | `[P1]` / `[P1, P2]` | `identical`; only the matching P1 row | P2 appears only in the previous manifest and is omitted from the comparison output. |
| Changed sampled state positive control | `[P1]` / `[P1]` | `physics changed`; the matching row says image `identical` and includes `north_m: 0.001` | The state-difference branch is exercised even when the image hash shortcut is taken. |

The behavior follows the current implementation directly: `tools/scenery/scenario_report.py:98–105` indexes previous rows by `(view, t_s)` and iterates only current rows; `:107–110` tests the sampled state and equal declared image hashes; `:124–127` derives the overall label from state changes or rows whose status is exactly `changed`. A `new frame` row contributes neither, and previous-only rows are never visited. The code also does not consult the top-level aircraft ID or source identity before producing the verdict. `tools/scenery/scenario.sh:25–28` feeds the prior output-root run to this comparison when present, so a change of inputs between adjacent runs is possible; the reproduction does not claim that a particular real pair did so.

The current `old_rows` dictionary would also overwrite duplicate `(view, t_s)` keys, a **source-derived risk** not independently exercised by these five cases. Absence of overlap and missing historical rows are the directly reproduced findings.

## Observed `history_index()` results

The probe generated four independent history folders, each containing a minimal synthetic `scenario.json`. It varied only the synthetic sync receipt:

| Receipt supplied | History label generated | Meaning |
| --- | --- | --- |
| No `sync.json` file | `sync pass` | Incorrectly presents unavailable evidence as a pass. |
| `sync.json` containing `[]` | `sync pass` | An empty receipt is also presented as a pass. |
| `[{"ok": true, ...}]` | `sync pass` | Positive control for the current display function; this one-item synthetic list does not prove a real full check set is complete. |
| `[{"ok": false, ...}]` | `sync FAIL` | Negative control for the current display function. |

`tools/scenery/scenario_report.py:173–177` substitutes `[]` for a missing receipt and calls `all()`; `all([])` is true. This observation concerns the history HTML label, not the exit code or correctness of a completed `sync_checks()` run. The probe did not run the separate full report CLI or render history in a browser.

## Future correction and acceptance boundary

1. **Separate sample differences from comparison coverage and provenance.** Compute both current-only and previous-only `(view, t_s)` sets and matched coverage. Preserve per-frame differences for intentional before/after comparisons. A pair with no matches must say unavailable/not comparable; partial coverage must disclose added and removed keys, and must not present an unqualified overall “identical.” A complete set with equal sampled outputs may say so, while separately disclosing source identity same/changed/unknown. Preserve raw state/image delta information even when a deliberate source change is being compared.
2. **Include aircraft/source identity.** Carry and display accepted aircraft ID, data path and exact input hash/mode from the scenario session, as planned in the integration follow-up. A changed ID or source should be visibly different; absent legacy metadata must be shown as unknown rather than inferred from today’s default. The basic fixture's existing baseline should be preserved unless an intentional, documented source-mode change is chosen. Different hashes should not prohibit useful intentional comparisons.
3. **Distinguish unavailable history evidence from failure and pass.** Display an explicit unknown/unavailable status for a missing, malformed, empty or incomplete sync receipt. Only label a run pass when a valid, nonempty receipt covers the defined complete check set and each result is a boolean pass; a valid failed result remains FAIL. Preserve historical missing receipts as unknown rather than manufacturing a verdict from current tools. Validate the receipt contract before indexing fields so bad history does not accidentally become a pass or crash the entire index.
4. **Automate targeted regressions.** Cover equal matched frames; different aircraft and input hashes; same-ID mode change; legacy unknown source; no common keys; added-only, removed-only and mixed key sets; duplicate keys; actual state change above and at tolerance; identical versus changed image branches; missing, empty, malformed, incomplete, all-pass and failed sync receipts. Verify JSON and HTML/history communicate the same coverage and provenance. A separate real-render capture in a fresh output root is required to validate the actual image branch and the tool's complete capture workflow; this probe provides no such evidence.

All project runtime and report source files remained unchanged during this probe. The retained source and receipt are published with this appendix; proposed corrections remain open.

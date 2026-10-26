# GP-12 frozen legacy oracle repair

Replaces the promoted test's old/current aliases with independent immutable expected data. No runtime arithmetic or original evidence is changed. The three promotion payloads are listed in `promotion-manifest.json`; production test imports use only `res://` paths. Validation changes only the two fixture paths because these new fixtures are not yet installed.

`ground_contact_capacity_legacy_steps.bin` is a byte-exact copy of the retained38160-byte `legacy-step-parity.bin`, SHA256 `ffc52cf1a57e4a7a07e4d57851238acc3961dd7409ceade70dcd4a879237de18`. The test uses only captured `original_result` as expected output; `draft_result/equal` are checked as capture provenance. It pins the two law strings, two original input fixture hashes and unique law/fixture pair identities. The four records are **two accepted gentle single-tick advances with full state/receipt, and two hard `error_control_exhausted` refusals without state/receipt**. This is not an accepted hard trajectory baseline.

`ground_contact_capacity_legacy_rows.bin` is121452 bytes, SHA256 `d5f96330e89f1ac55a1c6df474a35cd6925008064a1c9c6b2f45e22c4bd6eba9`. It was captured once by `capture_old_rows.gd` from the verified PREPROMOTION frozen owner and old traction implementation (original hash86987e1e…, recorded in `capture-provenance-before.json`). All70 frozen scripts and10 data assets matched the old manifest before and after capture/checks. It stores exact prepared/CG and16 old state/ground/brake inputs plus complete old output bytes. Current code never generates expected values. Cases reproduce the old4 heights×2 banks×2 brake combinations.

The repaired test pins both complete fixture hashes before decoding, validates bounded record shapes/provenance with typed selectors, refuses malformed examples, calls the current row/Step implementation once per frozen case, compares full output bytes and checks row-input immutability. Both fixture names already match `/app/tests/fixtures/ground_contact_*.bin -text`; `git check-attr` returned text unset, so no attribute edit is required.

Passing checked evidence: original-row capture35/0 and repaired installed-runtime validation103/0, marker `Traction capacity producer: 103 checks, 0 failed`. Independent disposable mutations prove discrimination with expected process1 and **zero engine errors/warnings**:

- Legacy row force-rate×1.01:12 affected frozen row cases fail.
- Successful receipt `absolute_impulse_sum`+0.125:the two accepted gentle outcomes fail.
- Actual refusal reason suffix:the two refused hard outcomes fail.

All negative controls leave fixture bytes unchanged. The mutant failures are evidence of detection, not passing regression runs. Two unsuccessful harness preparations (CRLF generator lookup/missing generated script, then one inferred-bool parse issue) remain retained and are excluded from passing counts. No additional test expansion or full-suite claim is made.

`report.json` binds receipts, exact payloads and unchanged source proof. `review.patch` is the test-only delta. `promote_root.py` was added separately by root and was not executed by this worker. Root owns the actual three-path promotion and subsequent canonical evidence retention.

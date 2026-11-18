# TELEM-00/01 verification evidence

Date: 2026-11-18. Baseline: 39fa2746ae4f4ba8698b87db279adcfe84ef5d17.
Candidate: design/transparent-telemetry-2026-11-18; only new telemetry planning/research/prototype paths and four narrow documentation-index/decision edits. No application, shader, physics, aircraft-data, release or active workflow change.

## Executed checks

| Check | Observed result |
| --- | --- |
| Python 3.12.14; jsonschema 4.26.0 and exact dependency pins in requirements.txt | Available in the verification environment |
| python3 -m unittest discover -s research/telemetry -p 'test_*.py' -v | **62 tests passed** |
| python3 research/telemetry/generate_contracts.py --check | Generated batch/report schemas and OpenAPI proposal match their source |
| python3 research/telemetry/generate_examples.py --check | Synthetic JSON and Markdown examples match their source |
| Independent reviewer rerun | Same 62 tests and both generator checks passed |
| Local documentation links/anchors | **125 new local links/anchors passed**, using the repository's existing check_docs parser/target logic |
| git diff --cached --check and scoped changed-file inspection | Passed; 30 files in the intended docs/research scope; no runtime or active workflow changes |

The tests exercise pre-grant probe silence, nested schema rejection, invalid UTF-8/depth/nonfinite input, duplicate keys/sequences, identifier trailing newlines, custom-field leaks, GPU availability, independent cadence arithmetic, suspend gaps, stale consent/attempt callbacks, retry classes/horizon/byte/attempt limits, fake-ingress idempotency/conflicts/backpressure, approved releases, trusted closed-day timing, distinct-token thresholds, contribution caps, suppression, weighting and deterministic report output.

The canonical payload encodes 1,800 observed draws across 30,000,000 microseconds: exactly 60 render-cadence FPS by definition. The example report uses twenty synthetic sessions; no machine or player was measured.

## What was not run

No Godot process, rendered consent UI, native performance campaign, packet capture, receiving service, database migration/transaction test, deployment, provider deletion drill, real GitHub report or live scheduler. The application is unchanged, so broad physics/visual/native gates were not run for this design-only branch. Existing hosted CI gates are not replaced by these local checks.

ClientModel and IngressModel are in-memory specifications, not production transport or persistence implementations. Daily GPU aggregation is verified only for its stated fixed schema/closed-day model; a weekly report, aircraft table and all operational deletion claims remain pending.

## Final scope and link result

The lead checked 125 new local documentation links/anchors with no failures, then inspected the complete staged 30-file change. Generated contracts/examples match their sources; the final 62-test suite passed after the review corrections. Every newly added file is below 32 KiB; pre-existing indexes retain their earlier content. The branch has no executable application integration, deployment secret, user data or live publisher. Its content remains a design and offline implementation starter.

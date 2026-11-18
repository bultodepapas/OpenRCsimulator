# TELEM-00-R1 verification evidence

Date: 2026-11-18. Baseline: `48ae3016a655acf7d062da3f32d72b9050c9e59a`.
Scope: adaptive research, telemetry planning/indices, a new offline publication model, generated tests and exact test dependency pins. No application, aircraft/physics, shader, export, active workflow or live service change.

## Executed offline checks

| Check | Result / meaning |
| --- | --- |
| Python 3.12 environment with existing pinned jsonschema plus Hypothesis 6.170.15 and sortedcontainers 2.4.0 | Test-only packages installed in an isolated scratch virtual environment; no game dependency |
| Full focused unittest discovery | **97 tests passed**, including the original 62 and 35 added tests |
| Hypothesis settings | Six data properties capped at 80 examples each; one state machine capped at 120 examples of up to 50 actions; deterministic generation and no example database |
| Generated contracts/examples | Existing source remains authoritative; checks run with no schema or fixture change |
| Research register | Exactly F01–F30, each once across nine evidence files; original 38 are not recounted |
| Disposable mutation: remove duplicate-key rejection | New generated decoded-key test detects the fault with an assertion failure |
| Disposable mutation: remove queue purge on revoke | New consent state machine detects the fault with an assertion failure |
| Integrated local Markdown links and anchors | **211 checked; zero errors**, using the repository's existing documentation parser against Git objects |
| Candidate scope and whitespace | **29 changed files**, all under `docs/` or `research/`; `git diff --cached --check` passes |

The configured Hypothesis bounds are not a count of distinct executed scenarios or exhaustive coverage. Examples use synthetic bytes and reports. The shorter-body regression demonstrates that a valid session-start payload can be below 600 bytes; invalid-UTF-8 properties now use a guaranteed invalid prefix instead of that false size assumption.

## Reproduction

Use the [starter commands](../../../../research/telemetry/README.md#run) in an isolated Python 3.12 environment with its exact requirements. The lead additionally ran only the relevant new tests during edits. Both generator checks verify the unchanged v1 schemas and synthetic examples. No registry/network access occurs in these checks after dependency installation.

For the two deliberate fault checks, the lead copied `research/telemetry/` to separate disposable scratch directories, excluding bytecode caches. One copy replaced the duplicate-key exception with a no-op; the other replaced `ClientModel.disable`'s queue clear with a no-op. The corresponding `test_properties.GeneratedPayloadTests.test_duplicate_decoded_keys_are_rejected` and `test_properties.TestConsentStateMachine` each exited 1 with a test assertion failure, not an import/setup error. The integration tree was never mutated. This demonstrates sensitivity to those two faults only.

## Boundaries of the result

The publication model is sequential and in memory. It verifies local intent decisions, not a distributed lock, real GitHub authentication, immutable repository identity/visibility, complete remote discovery, durable restart or a legitimate human review. Public inventory reservations cover known synthetic entries; they do not prove a complete disclosure inventory or formal privacy. Recovery from stale backups and actual concurrent writers remains a production gate.

Toxiproxy, mitmproxy, Schemathesis, PresentMon, MangoHud, Perfetto, ASV, HdrHistogram, PostgreSQL, pgBackRest, NGINX, Uvicorn and the multilingual example applications were researched, not installed or qualified by this task. No native Godot UI, packet capture, physical erasure drill, live receiver, real publication or target-hardware performance test was run. The branch does not activate telemetry. Local focused checks do not replace hosted CI or release qualification.

The [review record](review.md) tracks concrete corrections, independent checks and remaining trust boundaries. The link check covered all local links in affected telemetry Markdown files, plus new or affected local links in changed indices; external URL availability and unrelated repository documentation were outside that check. The lead checked the staged scope and diff before branch publication. Hosted CI is not claimed as part of this local evidence.

## Final candidate verification

Date: 2026-11-18. Review baseline: `a16a2dbc2e0fdf3d22cdf7c2dd23bbfca24dd2e8`. The preceding 97-test and 211-link results describe that earlier research follow-up. This section records the final merge-preparation corrections and is the current local evidence for the starter.

The lead exported all 16 tracked `research/telemetry` files from the staged Git tree into a new empty directory. A fresh Python **3.12.14** virtual environment was created without system site packages, and all eight exact requirements were installed. The two `run` blocks from the actual [CI workflow](../../../../.github/workflows/telemetry-contracts.yml) were executed against that clean snapshot, with an isolated runner temp directory and Hypothesis storage. Both exited zero:

- `pip check`: no broken requirements.
- `generate_contracts.py --check`: contracts match their generator.
- `generate_examples.py --check`: synthetic examples match their generator.
- Complete unittest discovery: **123 tests passed**, including the generated properties/state machine; **26 more tests than the review baseline**.

The workflow YAML was parsed and its shell blocks passed Bash syntax checking. Structural checks confirmed ordinary push/pull-request/manual events, `contents: read`, immutable checkout at `11d5960a326750d5838078e36cf38b85af677262`, no persisted checkout credentials, sparse telemetry checkout, a ten-minute timeout and no publisher secrets or live telemetry calls. The pin was verified in the official actions/checkout repository; Ubuntu 24.04's official runner inventory includes Python 3.12. This local reproduction does not execute GitHub's checkout action or establish a hosted runner result.

Independent re-reviews and their exact scope are recorded in the [final review](review.md#final-merge-preparation-review). The publication reviewer ran the integrated 121-test candidate; the final two admission/suspension additions and generated state machine were independently rechecked by the contract reviewer. The lead then ran the full 123-test clean-snapshot candidate. No deliberate mutation was made in the integration checkout, and the previous two disposable mutation receipts remain limited to their stated earlier faults.

Final integration checks: **220 local Markdown links/anchors checked with zero errors** across telemetry documents plus introduced/affected index links; **25 files changed** by this review and **48 files in the complete telemetry branch delta**. `git diff --cached --check` passes. The staged telemetry subtree and workflow are byte-identical to those used in the clean-snapshot test. A three-way Git merge-tree against main `d60cf725c8f40379ef10768678ae1e873764839f` completed without conflict. No unrelated main history was merged or rewritten.

The latest main increment after the architecture audit changed a capture-only flood-light probe and native-kernel evidence; it did not change the proposed telemetry integration interfaces. This source/merge inspection does not qualify native behavior or future main revisions. Hosted CI and the repository's existing required merge checks must be inspected on the proposed revision; no production or native-runtime qualification is claimed here.

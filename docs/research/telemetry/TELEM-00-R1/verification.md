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

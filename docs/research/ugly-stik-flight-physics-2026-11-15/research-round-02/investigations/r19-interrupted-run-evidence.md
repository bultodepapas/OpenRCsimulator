# R19 — Interrupted runs must leave usable evidence

**Decision:** integrate a bounded repair in the Python flight-card runner. **Priority:** P1. **Evidence baseline:** `08f0c08348395c0d6d9f7e224f66460828f59a7f`; the plan was published as `973ac3b42708102a6ebc95b64b3e42e688aae573` before this investigation. This concerns the reliability of research output, not flight dynamics.

**Implementation update:** the bounded repair is present on this research branch, including catalog-discovery failure receipts. Final executed evidence and scope are recorded in [verification](../verification.md) and [implementation review](../implementation-review.md). A malformed profile rejected by validation does not prevent a good peer's summary. A later summary-reduction error instead withholds the whole partial summary, records the error and preserves all job receipts; it does not promise a separate summary for every good peer.

## Question and observed code

Can an interrupted or malformed aircraft job preserve enough information to distinguish a simulator failure, an invalid report and a failed wrapper? In `research/flight-test/run.py`, `godot()` captures both output streams with UTF-8 replacement. The `fly()` timeout handler, however, keeps stdout only when it is already a string and discards stderr. It then parses `profile.json` before writing `run.log`. `json.loads`, direct `report['results']` access and result iteration can raise. `dict(pool.map(fly, ids))` propagates that exception before the aggregate manifest is written.

The retained [failure-path report](../../follow-up-01/evidence-contracts-and-failure-paths.md) and its [raw evidence](../../follow-up-01/evidence/tool-evidence.json) identify concrete counterexamples. The probe launches a real Python child for the timeout path; it substitutes child results for malformed-profile paths. Those are wrapper tests, not Godot flights. A complete positive control is also retained. The proposed implementation will rerun that observer and retain a separate post-change receipt.

## External research and limits

Python 3.12 documents captured `TimeoutExpired` stdout and stderr as bytes even when `text=True`, with `None` possible when no data was observed ([LEAD-S01](https://docs.python.org/3.12/library/subprocess.html#subprocess.TimeoutExpired)). Therefore the old string-only branch loses precisely the documented representation. Decode each stream with the runner's declared encoding and replacement policy. Concatenating separately captured streams cannot reconstruct their temporal interleaving; the log must not imply otherwise.

The executor documentation says an exception from a mapped function is raised when its result is retrieved ([LEAD-S03](https://docs.python.org/3.12/library/concurrent.futures.html#concurrent.futures.Executor.map)). That supports classifying expected per-job data/launch errors inside the job boundary. It does not justify swallowing arbitrary programming exceptions. Python's JSON decoder also accepts duplicate object names and nonfinite constants by default ([LEAD-S02](https://docs.python.org/3.12/library/json.html#standard-compliance-and-interoperability)). A small explicit profile reader can reject those ambiguous forms without adding a dependency. These are Python contracts, not a crash-consistent storage guarantee.

## Alternatives and integration design

Replacing the runner with a general workflow engine would enlarge the dependency and migration surface. Switching every job to `submit/as_completed` alone would not repair parsing or lost logs. The narrower choice keeps the current executor and card selection behavior, normalizes both streams, writes the child log before parsing, catches expected launch/read/parse/schema errors, and records them separately from the child return code. A timeout remains a failure even if an old-looking complete profile exists in that fresh job directory.

Use a shared, standard-library profile reader for the runner and comparator. Validate the result container, result objects, boolean flags, metrics/table shapes and unique case identities. Missing summary metadata must be diagnosed rather than causing a later unrecorded crash. Preserve the original profile bytes for investigation. A completed test with `valid: false`, a skipped test, or a `null` measurement remains scientific output; the wrapper must not invent a physical pass criterion.

Reject nonpositive/nonfinite timeout values and nonpositive job counts before launching work. Keep expected test-roster and loaded-input-hash checks. Write one per-aircraft receipt when each job completes and an aggregate receipt after the jobs; this preserves completed peers if a later expected job fails. An unwritable filesystem or forced termination during a write remains a separate limitation, not a promised success.

## Acceptance and remaining work

The focused checks must exercise an actual timed-out child with output on both streams; string, bytes and absent timeout output; malformed JSON; wrong container types; missing metadata; duplicate identities; a launch error; and a two-worker batch with one valid and one invalid profile. Logs and receipts must survive, both jobs must be represented, and only eligible profiles may enter the summary. Preserve the existing fresh-directory, identity and roster regressions. The final verification record will identify the executed tests and hashes.

Whole process-tree supervision, durable checkpoint journals, external `--app` source manifests and a versioned evidence schema are useful follow-up work. The repository already has `tools/godot/run_checked.py`; assess reuse of its process supervision separately before replacing the flight runner's contract. This patch does not claim to solve every interruption mode.

# Frozen report publication and uncertain writes

Status: **offline sequential model**, not a GitHub integration, lock, durable database or approval service.
Implementation: [publication.py](../../../research/telemetry/publication.py); adversarial cases: [test_publication.py](../../../research/telemetry/test_publication.py).
Evidence: follow-up F08/F10/F19 in the [research register](../../research/telemetry/TELEM-00-R1/README.md).

## Why publication needs its own protocol

A remote create can succeed while its response is lost. A search returning no result cannot prove the previous write will never become visible. A workflow retry, repository concurrency group or local lease cannot recall an already in-flight GitHub request. Automatic retry of a non-idempotent create may duplicate it.

Publication also creates an observable disclosure history. A changed row, status or coverage value is another release of information; editing the issue does not reliably erase the old value. A minimum count and omitted session IDs do not establish anonymity. Initial reports stay private. Any future public release must be reviewed as a complete set of outputs, including corrections, status changes and overlapping daily/weekly reports.

## Identity and review receipt

The starter handles only `daily-gpu-v1/<UTC day>/<approved release>`, checks a supplied deployment release allowlist and requires the report to match an independently requested key. The trusted destination repository is part of the ledger identity; ASCII owner/repository and bot-login casing are normalized consistently, with bounded string-only identities. Production must resolve and bind immutable repository and bot IDs, verify actual visibility and publisher identity at the write boundary, and handle rename/transfer aliases.

The frozen artifact includes both a deterministic title (`OpenRC telemetry: <day> / <release> / daily GPU v1`) and the complete Markdown body with its controlled marker. Its content digest is SHA-256 of UTF-8 JSON with exactly the `body` and `title` keys, sorted keys, compact separators and no ASCII escaping. Titles are required, editable [GitHub issue fields](https://docs.github.com/en/rest/issues/issues); an unchanged body does not establish an unchanged disclosure. The marker is a lookup aid, never authorization by itself. No session token or raw input belongs in the ledger.

For public output, a review receipt must bind the exact report key, destination, expected bot author, title/body content digest and digest of the complete relevant release inventory. In the offline model, a supplied typed receipt must match the current digest of all known public intents, including creating, unknown and review-required entries. A receipt for one author cannot approve another author against an otherwise identical empty inventory. Preparing another public intent reserves it by changing that inventory; an approval against the previous digest becomes stale. This is a sequential in-memory demonstration. **Its hash is not proof that a person reviewed anything**, nor that the ledger knows every remote disclosure.

Production needs an authenticated approval source and a checked inventory of all related previous, proposed, pending and unknown artifacts, audiences, scopes, statuses, covered days and correction history. Serialize the inventory-bound reservation across cooperating writers so a competing/delayed release cannot invalidate the review between approval and dispatch. Inventory changes require re-review, not a one-time hash check followed by an uncoordinated write. The model does not implement that distributed boundary or prove safe composition. A trusted `private` policy is not proof that GitHub is actually private; restrict and monitor visibility/transfer changes, and treat exposing previous private issue history as a new public disclosure.

Changing the intended digest, audience or expected publisher identity requires review. The starter deliberately has no automatic correction/update transition. A later correction protocol must preserve the old disclosure record and consider issue edit history/copies before it is implemented. Approval of a daily report does not automatically approve an extra dimension, a new weekly table or a different audience.

## State transitions

| Current state / observation | Permitted action | Required invariant |
| --- | --- | --- |
| No intent; validated closed report and required review receipt | Persist `creating` intent, then make one create attempt | Persist before any remote side effect; exact target and immutable title/body |
| `creating` seen again, process restart or ambiguous outcome | Reconcile; preserve `unknown` when uncertain | Never reset to a blind create solely because a response or lookup is absent |
| Complete discovery with exactly one verified issue and no related conflict | Bind issue number and mark `published` | Match repository, issue kind, expected bot author, exact title, marker and complete body |
| Incomplete discovery or zero matches | Keep reconciliation pending | Absence of a visible match is not proof of no remote write |
| Multiple verified issues, a related altered artifact, or a changed/missing known published artifact | Persist review-required and stop | Positive conflict evidence is retained even from partial discovery; no later callback or smaller result set clears it |
| Published intent with identical digest/policy | No-op | No repeated update or extra disclosure |
| Changed content/status/coverage/audience | Review required | Treat the full observable history as retained |
| Completion with stale/invalid token or unrelated remote artifact | Ignore/refuse | A Boolean cannot impersonate an integer attempt token; cannot bind another destination, PR or author |

The model's counter supplies local attempt identity only. It does not fence another process or GitHub. Production needs one trusted writer per key, transactionally durable state, bounded database/network deadlines, recovery after store failure and an explicitly reviewed way to resolve conflicts. The starter has no automatic conflict-clearing transition. GitHub repository concurrency is an additional cooperating-job guard, not the state store or cross-repository coordination mechanism. A failed workflow must not cancel an earlier writer and assume its remote request disappeared.

## Reconciliation and failure boundaries

Use the stored issue number when known and verify the target identity. The model's prepare no-op means no write is needed from its local ledger; it is not a remote audit. Successful reconciliation requires complete discovery even for a previously published entry. Inspect related candidates before filtering exact matches: an ordinary issue from the expected repository/bot with the same marker, exact title or already bound issue number but changed content is positive conflict evidence. One exact issue plus an altered same-key issue requires sticky review, not a successful match. Multiple exact matches also establish a conflict even when pagination is incomplete. A valid-token completion carrying a related altered artifact has the same review outcome.

An adapter must explicitly establish ordinary issue kind; absent/unknown/falsy kind values are not accepted as proof. Inspect complete, bounded paginated candidates through a trusted adapter; exact controlled marker alone is insufficient. Treat API permission/rate failures, partial pages, delayed visibility and an active prior writer as unresolved. If ambiguity cannot be resolved, alert the operator and leave the last valid publication unchanged. No publication failure changes player consent or triggers raw-data retrieval.

The fake model assumes trusted inputs for time, deployment policy, review receipt and discovery completeness. Tests cover this interface's outcomes, not authentication, completeness of GitHub's listing/search, durable restart or real concurrent processes. It can publish an already frozen aggregate after raw data has expired; this does not extend raw retention or permit recomputing an expired day.

## Implementation acceptance

Port the tests to the actual database and fake remote adapter with controlled barriers. Crash after durable intent, after server-side create and before recording success; lose a response; delay visibility; run two workers; expire a lease while a request remains in flight; fail the ledger commit; and return wrong-author/destination/PR candidates. Verify no blind second create while any outcome is unknown. Test stale approved digests and changed statuses separately from transport idempotency.

Finally qualify permissions, real issue behavior and review provenance in an explicitly selected private synthetic destination. No telemetry destination, publisher workflow, issue or comment is created by this plan or model. The separate contract-test workflow runs offline checks only.

Also restore a deliberately stale ledger snapshot or fail over to a lagging replica after a remote create. Pause publication and reconcile complete remote history and outstanding writers before admitting new creates; a durable write later lost to rollback is not remembered by a fresh ledger. Bootstrap and migrations of existing report destinations need the same recovery rule. Test competing public approvals against one inventory, delayed creates after another reservation, and a repository visibility change. These remain production acceptance gates, not claims of the offline tests.

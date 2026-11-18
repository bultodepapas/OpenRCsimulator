# GitHub delivery research and implementation design

Status: research and proposed design; no collector or reporting workflow has been deployed.

Research date: 2026-11-18. Every source below was opened and inspected; search results were used for discovery only. All sources are official GitHub documentation or repositories maintained by GitHub/Octokit. Limits and interfaces must be checked again when implementation is pinned.

## Decision

Use GitHub as the maintainers' **aggregate report and engineering triage destination**, with a separate HTTPS ingestion service and private telemetry store. The game must never contain a GitHub personal access token, GitHub App private key, or installation token. The preferred first implementation is a scheduled workflow in a private operations repository, fetching **already aggregated, disclosure-filtered results** and updating one report issue per reporting period. A GitHub App is only needed when an external reporting service or another repository must write the destination repository.

A second, independent route is **Export diagnostics → Preview → Open GitHub report form → user submits**. This is useful before an automatic backend exists, but is not anonymous: a GitHub issue has a GitHub author, and public repository attachments are publicly retrievable. Explain that distinction before opening the browser. Do not silently put machine details into a URL query string.

These are engineering conclusions drawn from G01–G15; GitHub does not advertise its Issues/Actions APIs as a player telemetry ingestion service.

## Investigations

<a id="g01"></a>

### G01 — REST API capacity and backoff

Source: [GitHub REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).

Verified: unauthenticated public reads generally allow 60 requests/hour; authenticated users generally have 5,000/hour. GitHub App installations start at 5,000/hour, with documented scaling exceptions. Secondary limits include 100 concurrent requests, usually 900 REST points/minute, and generally 80 content-generating requests/minute or 500/hour. Most REST mutations cost five secondary-limit points. Limits may change and endpoints may impose lower limits.

Decision: neither per-frame nor per-session issue creation is viable. Batch into a small number of maintainers' reports; serialize publication, inspect response rate-limit headers, honor `Retry-After`/reset times and apply bounded exponential backoff. A `403` is not automatically retryable: distinguish rate limiting from permission failures. An outage must never block gameplay.

<a id="g02"></a>

### G02 — `repository_dispatch` is a privileged trigger

Source: [Create a repository dispatch event](https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event).

Verified: accepted fine-grained credentials need `Contents: write`. `event_type` is limited to 100 characters. `client_payload` allows at most ten top-level properties; the JSON payload must be less than 64 KB. A successful call returns `204`; validation/spam can produce `422`.

Decision: reject direct game-to-dispatch ingestion. A public game binary cannot protect the required credential. If a future backend triggers a report, send only a bounded report identifier through dispatch, keep the secret on that backend, and verify that the workflow actually completes. `204` means the trigger was accepted, not that data was durably ingested or a report published. Prefer polling aggregate reports to avoid needing this broader permission.

<a id="g03"></a>

### G03 — Workflow scheduling and delivery are not a real-time queue

Source: [Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).

Verified: `repository_dispatch` needs the workflow on the default branch. Scheduled workflows also use the default branch, may be delayed or dropped during load, and public repositories' schedules can be disabled after 60 inactive days. The shortest schedule interval is five minutes.

Decision: reporting can be eventually consistent; ingestion cannot depend on Actions scheduling. Use a weekly window with explicit bounds and a durable publication watermark. Use a nonzero minute, a manual catch-up trigger, a stale-report monitor and a rerunnable report job. Do not advertise exact delivery times. A workflow left only on this design branch will not become a working scheduled report.

<a id="g04"></a>

### G04 — GitHub App credentials can remain server-side and narrowly scoped

Source: [Generate a GitHub App installation token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app).

Verified: installation tokens expire after one hour and can be narrowed to selected repositories and permissions. Omitting those restrictions leaves the full installation's authorized scope. Octokit can manage creation and renewal. Current documentation warns against assuming a fixed token length.

Decision: for an external publisher, install a dedicated reporting App on exactly the report repository and request only `Issues: write` plus metadata access. Keep its private key in the server secret manager; never in the editor or telemetry payload. Do not request `Contents: write` when only issues are published. Record expiry from the API, treat tokens as opaque, rotate/revoke operationally.

<a id="g05"></a>

### G05 — Issue Forms provide a reusable manual reporting UI

Source: [Syntax for issue forms](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms).

Verified: YAML files under `.github/ISSUE_TEMPLATE` define inputs, dropdowns, checkboxes and validation. Responses become the issue's Markdown body. The feature remains documented as public preview.

Decision: provide an optional performance-report form with app version, scenario, aircraft category/catalog identifier, graphics settings and a user-reviewed sanitized report. Do not ask for contact details, entire logs or crash dumps by default. A checkbox should acknowledge public visibility and GitHub identity if the target is public. Required form fields improve reports but are not a security boundary; API clients can create issues without using the form.

<a id="g06"></a>

### G06 — Attachments are not an anonymous private intake channel

Source: [Attaching files](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files).

Verified: public-repository attachments are accessible without authentication; private/internal attachments require repository access. Files are uploaded immediately when attached, before the final issue is necessarily submitted. Text, CSV and JSON attachments are supported; the general non-media limit is 25 MB.

Decision: export a compact sanitized JSON or Markdown report with a preview inside the application. Explain visibility before the browser upload. Do not offer a public attachment workflow as the default automatic telemetry transport. A GitHub-generated anonymized attachment URL does not make the file contents or submitting issue author anonymous.

<a id="g07"></a>

### G07 — Actions artifacts and logs have explicit retention and access implications

Source: [Manage GitHub Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository).

Verified: the documented default artifact/log retention is 90 days; repository settings allow 1–90 days for public repositories and 1–400 days for private repositories, bounded by organization policy. Changes are not retroactive. The documentation describes expanded retention scope from October 2026.

Decision: artifacts are optional derived report outputs, not a raw event database. Set short explicit retention for report-generation intermediates, avoid printing raw data to logs and test expiry behavior. Issue bodies and Git history are separate durable surfaces; artifact expiry does not erase them. Never commit raw session payloads to a repository.

<a id="g08"></a>

### G08 — OIDC avoids a standing cloud-read secret in Actions

Source: [GitHub Actions OpenID Connect](https://docs.github.com/en/actions/concepts/security/openid-connect).

Verified: a configured cloud trust relationship can exchange a workflow identity token for short-lived cloud credentials. Claims identify the originating workflow and permit scoped authorization.

Decision: when the chosen backend supports it, use OIDC for read-only access to an **aggregate-only report endpoint or storage prefix**. Restrict trust to the intended repository, trusted default ref/workflow/environment and expected audience. `id-token: write` belongs only on the report job; it is not permission to read all telemetry. Raw session access must be technically denied to that identity. Provider-specific trust configuration remains implementation work.

<a id="g09"></a>

### G09 — Untrusted fields can inject code into workflow scripts

Source: [Script injections](https://docs.github.com/en/actions/concepts/security/script-injections).

Verified: GitHub event fields, including titles and bodies, can contain attacker-controlled strings. Substituting them into shell/JavaScript source can execute those strings as code.

Decision: do not interpolate player data or API result text into `run:` or an action's JavaScript source. Parse bounded JSON as data, use a fixed Markdown renderer and parameterized API calls, and only permit catalog-defined aircraft IDs. Test malicious quotes, shell substitutions, Markdown links and mentions. Report titles must be generated from trusted period/build metadata. Avoid putting free-form player content in automatic reports.

<a id="g10"></a>

### G10 — Workflow hardening is available without a custom security framework

Source: [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use).

Verified: GitHub recommends least-privilege tokens, careful handling of secrets, and pinning actions to full commit SHAs from their actual upstream repository. Secret redaction is not guaranteed for transformed values.

Decision: pin and review reused actions before activation; use Dependabot/update review for revisions. Run the publisher only from trusted code, never a PR's checked-out code with publication credentials. Use an isolated job, bounded runtime and explicit permissions. Logs should contain counts, status and report IDs, never payloads, headers or credentials. A pull-request contract test job must have no telemetry/backend secrets.

<a id="g11"></a>

### G11 — `GITHUB_TOKEN` is sufficient for same-repository reporting

Source: [Use GITHUB_TOKEN for authentication](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token).

Verified: workflow jobs can grant only the permissions needed, and official examples create issues with `issues: write`. Actions may access `github.token` even when the token is not passed explicitly.

Decision: prefer the ephemeral job token for a report workflow writing to its own repository; do not introduce an App private key unless cross-repository/external publication requires it. A simple report job needs `issues: write`, `contents: read` if checking out reviewed reporting code, and `id-token: write` only for OIDC. No workflow, administration or package write permission is needed.

<a id="g12"></a>

### G12 — Issues API is suitable for bounded aggregate publications

Source: [Create/update issues REST API](https://docs.github.com/en/rest/issues/issues#create-an-issue).

Verified: creating an issue requires `Issues: write` for fine-grained credentials, creates notifications, can be secondarily rate limited, and returns `410` if issues are disabled. Issue responses expose author identity.

Decision: maintain one deterministic issue per reporting period or update a designated report issue. Avoid creating an issue for every client/session/error. Persist the destination issue number and a generated report key; reconcile a timeout after create before retrying. Alert maintainers on disabled Issues or lost permission. Route only actionable regression summaries to a separate bug issue after deduplication.

<a id="g13"></a>

### G13 — Reuse `actions/create-github-app-token` when an App is required

Source: [actions/create-github-app-token](https://github.com/actions/create-github-app-token), MIT license.

Verified: the official action creates installation tokens, supports repository/permission narrowing, and normally revokes the token in its post step. The inspected README currently uses v3 examples and explicit `permission-issues: write`.

Decision: reuse this action rather than hand-writing JWT and token exchange in YAML. Pin a reviewed immutable revision at implementation. Explicitly set destination repository and permissions; do not rely on defaults. Do not pass its short-lived token to another job or ship it to the game. This action is not needed for the preferred same-repository `GITHUB_TOKEN` route.

<a id="g14"></a>

### G14 — Reuse `actions/github-script` for small report updates

Source: [actions/github-script](https://github.com/actions/github-script), MIT license.

Verified: the action exposes authenticated Octokit APIs, supports an external script file, configurable retries, and documents passing variable data via environment variables instead of source interpolation. Its current README uses v9 examples; several failure statuses, including `403`, are excluded from automatic retries by default.

Decision: put rendering/upsert logic in a normal reviewed, unit-tested script, not a large YAML string. A pinned action can call it with an aggregate fixture or endpoint result. Add explicit rate-limit handling and idempotency rather than assuming built-in retries cover every failure. Never copy its illustrative full-context logging example into telemetry code.

<a id="g15"></a>

### G15 — Reuse Octokit for a standalone reporting service

Source: [octokit/octokit.js](https://github.com/octokit/octokit.js), MIT license.

Verified: Octokit provides REST/GraphQL clients, GitHub App auth, pagination and request retry/throttling support. The App abstraction can obtain an installation-scoped client. Request cancellation/timeouts are configurable.

Decision: use Octokit if publishing from a Node service. Pin the package and lockfile; reuse its authentication and throttling rather than building a GitHub client. Configure finite timeout/retry budgets and adapt logging to avoid payload disclosure. SDK retry support does not make issue creation idempotent; application-level report keys and timeout reconciliation remain necessary.

## Channel comparison

| Channel | Player account needed | Credential location | Privacy/operational tradeoff | Decision |
| --- | --- | --- | --- | --- |
| Game directly creates issues or dispatches | Usually user auth or a shared credential | Client if shared | Shared write credential is extractable; account identity defeats anonymous submission; notifications and limits | Reject |
| Game exports, user submits an Issue Form | GitHub account for issue submission | User's browser session | Explicit and useful; issue identity and repository visibility apply; no silent submission | Optional manual route |
| Collector creates one issue per upload | No | Collector | Still exposes session-level data and creates noise; GitHub rate and notification load | Reject |
| Collector stores privately; Actions fetches disclosure-filtered aggregates | No | OIDC/job token on trusted runner | Small operational footprint; a backend and disclosure gate are still required | Preferred initial automatic route |
| Collector + external reporting service + GitHub App | No | Server secret manager | Flexible scheduling and destinations; requires App/key operations | Supported alternative |
| Raw events committed as files or uploaded as Actions artifacts | No or implicit bot | Server | History/access/retention surfaces are unsuitable for raw event privacy | Reject |

## Concrete delivery contract proposed for the implementation plan

1. The collector accepts only the approved event schema after the in-game consent decision. Backend data validation is independent of client validation. No GitHub calls occur on a player's machine.
2. An aggregation job produces a versioned report dataset for a closed weekly window. It removes ephemeral session IDs, timestamps below day/week granularity, arbitrary strings and individual session records. Apply the project's minimum cohort rule and complementary suppression before the result becomes accessible to the report publisher. A threshold is a disclosure mitigation, not proof of anonymity or distinct-person counting.
3. An authenticated endpoint returns only allowlisted report cells: period, game build/channel, sample counts, hardware tiers, renderer/OS families, aircraft catalog categories/IDs where cohort size permits, weighted FPS/frame-time summaries and explicitly defined denominators. No report request may change dimensions ad hoc to reveal a small cohort.
4. A default-branch workflow reads this endpoint, validates a strict aggregate schema and renders deterministic Markdown. Proposed publication identity: `telemetry-summary:v1:YYYY-Www:channel`. The reporting store maintains its issue number and last successful content digest. A comment marker assists reconciliation but is not the sole authority; verify destination repo, expected bot author and report key.
5. Serialize each report key and update the existing issue if content changes. On ambiguous create timeout, reconcile by stored key/marker before issuing another create; duplicates must not be produced by blind retries. Successful publication records GitHub issue URL, content digest and completion time. GitHub status never influences gameplay or data collection consent.
6. The initial destination should be private operations reporting. Public summary publication requires an additional disclosure review and contains only approved aggregate tables. Even private GitHub receives no raw event/session records. No automated public posting is activated by a planning branch.
7. Define a conservative maximum report size and row count (proposal: 100 rows, 32 KiB Markdown). Summarize overflow, never attach the omitted raw rows. An empty report must distinguish no data, minimum-cohort suppression, backend failure and ingestion disabled.

## Failure and privacy test backlog

| Test | Expected result |
| --- | --- |
| Search packaged game and release assets for GitHub credential patterns | No App key, PAT or installation token exists |
| Consent undecided, declined, revoked or settings reset | No telemetry-induced GitHub request; collector behavior follows consent contract |
| Publisher attempts to fetch raw session storage | Access denied by backend authorization |
| Aggregate contains a session ID, custom aircraft name, path or unrecognized property | Schema validation rejects the publication |
| Small hardware/aircraft cohort or subtraction exposes a suppressed cell | Report gate suppresses/coarsens dependent cells |
| Report fields contain backticks, quotes, shell substitutions or `@mentions` | Remain data or are rejected; no execution or unintended notification |
| API returns `429` with `Retry-After`, or rate-limit `403` | Bounded delayed retry; no tight loop |
| API returns permission `403`, `401`, `410` or invalid-data `422` | Fail with useful status; no blind retry loop |
| Create succeeds but response times out | Reconciliation recovers the existing issue; no duplicate |
| Two runs publish same window concurrently | One logical report, deterministic final body |
| Scheduled job is dropped, delayed or disabled | Staleness detection and manual catch-up work; data ingestion continues |
| A fork PR changes publisher code | No backend secrets or publication rights available |
| Manual diagnostics export opened before consent | Preview only; no automatic upload, URL payload or browser launch |
| Public manual attachment workflow | Clear warning shown before upload; GitHub identity/public visibility acknowledged |
| Artifact/log expiry passes | Intermediates expire as configured; documentation does not imply issue/history deletion |
| Backend timeout or invalid report | Previous report preserved and marked stale through operational monitoring; no misleading zero |

## Implementation boundaries and open decisions

No infrastructure, paid service, workflow schedule, GitHub App or issue publication was activated for this research. The implementation owner must choose the private destination, collector/storage provider, approved dimensions and cohort policy, retention windows, report readers, maintenance owner and cost ceiling. The preferred routing does not depend on the game's engine. Repository-specific integration points belong in the main implementation plan.

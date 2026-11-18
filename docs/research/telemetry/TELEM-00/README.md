# TELEM-00 — transparent game telemetry research

Research and repository audit: **2026-11-18**.
Pinned source: [39fa2746ae4f4ba8698b87db279adcfe84ef5d17](https://github.com/bultodepapas/OpenRCsimulator/commit/39fa2746ae4f4ba8698b87db279adcfe84ef5d17).
Branch: design/transparent-telemetry-2026-11-18.

## Outcome

**38 distinct investigations**, conducted in three parallel workstreams, inform a small Godot adapter, strict receiving contract and aggregate GitHub reporting design. Each investigation records a concrete question, inspected primary evidence and an adoption/rejection consequence. The count is of substantive investigations, not search queries or duplicated URLs. An independent Good Enemy reviewed the design and executable prototype; the lead accepted, corrected and tested the findings.

[Active implementation plan](../../../plans/telemetry.md) · [Repository integration audit](repository-audit.md) · [Independent review resolutions](review.md) · [Actual verification](verification.md) · [Offline starter](../../../../research/telemetry/README.md).

No production telemetry, hosted service, scheduled publisher or GitHub issue was activated. Reports/examples are synthetic. Research versions are observations on this date, not production dependency approval.

## Investigation register

| ID | Question / investigated mechanism | Evidence and decision |
| --- | --- | --- |
| TOOL-01 | Godot HTTPRequest and Performance: reuse the engine | [Primary sources and finding](tools.md#tool-01) |
| TOOL-02 | OpenTelemetry Collector: reuse server-side routing | [Primary sources and finding](tools.md#tool-02) |
| TOOL-03 | GameAnalytics for Godot: mature game taxonomy, incompatible defaults | [Primary sources and finding](tools.md#tool-03) |
| TOOL-04 | Aptabase for Godot: useful minimal sender, audit identity and retention | [Primary sources and finding](tools.md#tool-04) |
| TOOL-05 | Sentry for Godot: optional crash diagnostics, not base analytics | [Primary sources and finding](tools.md#tool-05) |
| TOOL-06 | PostHog: rich analytics with explicit anonymous-event configuration | [Primary sources and finding](tools.md#tool-06) |
| TOOL-07 | Matomo: HTTP ingestion and a useful privacy-proxy pattern | [Primary sources and finding](tools.md#tool-07) |
| TOOL-08 | TelemetryDeck: HTTP option with identity semantics to verify | [Primary sources and finding](tools.md#tool-08) |
| TOOL-09 | Countly Unity: consent design reference and a device-ID warning | [Primary sources and finding](tools.md#tool-09) |
| TOOL-10 | Unity Analytics: explicit consent state controls collection | [Primary sources and finding](tools.md#tool-10) |
| TOOL-11 | OpenTelemetry C++: established SDK, unnecessary game dependency today | [Primary sources and finding](tools.md#tool-11) |
| G01 | REST API capacity and backoff | [Primary sources and finding](github-delivery.md#g01) |
| G02 | repository_dispatch is a privileged trigger | [Primary sources and finding](github-delivery.md#g02) |
| G03 | Workflow scheduling and delivery are not a real-time queue | [Primary sources and finding](github-delivery.md#g03) |
| G04 | GitHub App credentials can remain server-side and narrowly scoped | [Primary sources and finding](github-delivery.md#g04) |
| G05 | Issue Forms provide a reusable manual reporting UI | [Primary sources and finding](github-delivery.md#g05) |
| G06 | Attachments are not an anonymous private intake channel | [Primary sources and finding](github-delivery.md#g06) |
| G07 | Actions artifacts and logs have explicit retention and access implications | [Primary sources and finding](github-delivery.md#g07) |
| G08 | OIDC avoids a standing cloud-read secret in Actions | [Primary sources and finding](github-delivery.md#g08) |
| G09 | Untrusted fields can inject code into workflow scripts | [Primary sources and finding](github-delivery.md#g09) |
| G10 | Workflow hardening is available without a custom security framework | [Primary sources and finding](github-delivery.md#g10) |
| G11 | GITHUB_TOKEN is sufficient for same-repository reporting | [Primary sources and finding](github-delivery.md#g11) |
| G12 | Issues API is suitable for bounded aggregate publications | [Primary sources and finding](github-delivery.md#g12) |
| G13 | Reuse actions/create-github-app-token when an App is required | [Primary sources and finding](github-delivery.md#g13) |
| G14 | Reuse actions/github-script for small report updates | [Primary sources and finding](github-delivery.md#g14) |
| G15 | Reuse Octokit for a standalone reporting service | [Primary sources and finding](github-delivery.md#g15) |
| P01 | Visual Studio Code: inspection and settings controls | [Primary sources and finding](privacy.md#p01) |
| P02 | Go telemetry: public metric proposals and approved counters | [Primary sources and finding](privacy.md#p02) |
| P03 | KDE software privacy policy: device details without device identity | [Primary sources and finding](privacy.md#p03) |
| P04 | Mozilla data-collection principles: pseudonymity and transport metadata | [Primary sources and finding](privacy.md#p04) |
| P05 | Mozilla data-review process: enforceable schema governance | [Primary sources and finding](privacy.md#p05) |
| P06 | Go telemetry privacy notice: inspectable local reports | [Primary sources and finding](privacy.md#p06) |
| P07 | W3C fingerprinting guidance: combinations matter | [Primary sources and finding](privacy.md#p07) |
| P08 | IETF RFC 9458: an established option for separating IP and payload | [Primary sources and finding](privacy.md#p08) |
| P09 | ICO anonymisation glossary: correct terminology | [Primary sources and finding](privacy.md#p09) |
| P10 | ICO consent guidance: a real choice with an affirmative action | [Primary sources and finding](privacy.md#p10) |
| P11 | KDE KUserFeedback: reusable UI and no-ID design | [Primary sources and finding](privacy.md#p11) |
| P12 | Glean collection toggles and deletion requests: inspect SDK side effects | [Primary sources and finding](privacy.md#p12) |

## How the evidence changed the design

- Godot already exposes measurements and HTTP. Keep its pinned engine and avoid a native analytics SDK solely for transport.
- SDK names or “anonymous” marketing do not establish the required data properties. GameAnalytics identity/config requests, Aptabase IP-derived enrichment and Sentry automatic logs need explicit treatment.
- GitHub is a useful destination for engineering summaries; client-side credentials and per-session public issues are unsuitable.
- Show an affirmative choice before collection, a persistent off control, actual payload inspection and a truthful distinction between raw minimized reports and public aggregates.
- Reuse current local classifiers and measurements through a fresh allowlisted projection; do not upload developer traces, full diagnostics or saved flight statistics.
- Short retention, delayed reporting and session counting must be designed together. The integrated contract uses daily closed cohorts, a 48-hour raw/dedup maximum and explicitly filtered weekly observations.

## Additional implementation references

These support the starter/backend choice and are not needed to inflate the 38-investigation count:

| Source, checked 2026-11-18 | Finding / design consequence |
| --- | --- |
| [python-jsonschema validation](https://python-jsonschema.readthedocs.io/en/stable/validate/) | Reuse Draft202012Validator, check the schema itself and add explicit cross-field semantics. Format annotations do not automatically enforce all formats. The installed/tested version is 4.26.0. |
| [FastAPI request bodies](https://fastapi.tiangolo.com/tutorial/body/) | Existing HTTP routing and request-model framework; the project still must enforce pre-parse limits, unknown-field rejection, logging policy and durable acknowledgment. No FastAPI server is implemented by this branch. |
| [PostgreSQL row security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) | Explicit database roles/permissions are necessary; owners and privileged roles can bypass row policies. Publisher access must be restricted to approved aggregate data. |
| [Godot OS](https://docs.godotengine.org/en/stable/classes/class_os.html) and [RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html) | Hardware, logical CPU count, physical-memory and renderer APIs exist, but availability/meaning vary by platform. Runtime validation must use the repository's exact engine/export. |

## Method and evidence limits

Three bounded research helpers inspected official docs and maintainer repositories for tools (11), GitHub delivery (15), and privacy/consent (12). Those initial full-context helpers inherited the main runtime; do not claim an independently verified helper model/effort. After reading repository routing instructions, the independent reviewer was requested as gpt-6.1-terra with max effort using a fresh context. The provider's effective model/effort was not independently verified.

The lead inspected repository source and selected original sources, resolved the architecture and authored/verified the integrated contract model. Helper output is supporting evidence, not authority or a substitute for the actual checks. The [review record](review.md) names accepted corrections and remaining gates.

Research facts are separate from proposed policy. Hosting prices, live provider settings, legal applicability, native Godot SDK behavior and performance overhead were not measured or established here. Failed/unavailable source routes are noted in their investigation instead of silently treated as confirmed. The current design owns concrete retention limits and copy; exploratory research is not an alternate operating policy.

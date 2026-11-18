# Existing telemetry tools: research and adoption decisions

Research date: **2026-11-18**. Target confirmed by repository inspection: the production application is Godot/GDScript under `app/`. This document records **11 distinct investigations**, with official project documentation and maintainer repositories as primary evidence. Product claims about anonymity are treated as claims to audit, not as proof that OpenRC Simulator's proposed hardware dataset is anonymous. Recommendations below are engineering judgments for this project.

## Recommendation

Reuse the existing game's performance instrumentation and **Godot's built-in HTTPRequest**, place a small bounded, consent-controlled adapter around a strict event schema, and send to a project-controlled privacy ingress. That ingress must validate and minimize the payload before persistence or forwarding. Use established backend libraries and, if metrics/log routing warrants it, an **OpenTelemetry Collector** behind the ingress. The Collector is a transport/processing component, not the dashboard, database, consent manager, or public abuse-control layer.

Do not add a large third-party game SDK merely to send a few aggregate measurements. The rejected SDKs remain useful sources for batching, consent, event taxonomy, and optional crash-reporting design. This is reuse of tested primitives; the custom work is the game-specific consent, aggregation, schema, and privacy contract.

### Selection summary

| Candidate | Project fit | Decision | Principal reason |
| --- | --- | --- | --- |
| Godot HTTPRequest + existing instrumentation | Native GDScript, no extra binary | Adopt primitives | Smallest controllable collection boundary; explicit bounded requests and cancellation |
| OpenTelemetry Collector | Backend routing and operational metrics | Candidate backend component | Standard receivers/processors/exporters; needs ingress translation for custom game JSON |
| GameAnalytics Godot | Official GDExtension, purpose-built gaming analytics | Do not adopt for base anonymous mode | Persistent player identity and automatic behavior require material changes/audit |
| Aptabase Godot | Lightweight GDScript event SDK | Inspiration; conditional alternative | Small SDK, but server daily IP/UA identity, geolocation and retention differ from proposed policy |
| Sentry Godot | Official GDExtension, excellent diagnostic tooling | Optional later diagnostics only | Logs and crash snapshots exceed base telemetry contract |
| PostHog | Rich product analytics | Backend-only alternative after strict mapping | Anonymous-event mode exists, but identity and enrichment must be configured explicitly |
| Matomo | Mature HTTP analytics | Alternative, not first choice | Web visit/event model needs adaptation; privacy proxy settings are opt-in |
| TelemetryDeck | Cross-platform HTTP ingestion | Alternative, not first choice | Hash-based user recognition is not the proposed no-stable-identity model |
| Countly Unity | Mature consent design reference | Inspiration only | Wrong engine SDK; default device identification unsuitable |
| Unity Analytics | Consent lifecycle design reference | Inspiration only | Wrong engine; no reason to introduce Unity services into Godot |
| OpenTelemetry C++ | Native metrics/logs/traces SDK | No native client dependency in phase 1 | C++ extension/build complexity is unnecessary for GDScript aggregate batches |

<a id="tool-01"></a>

## TOOL-01 — Godot HTTPRequest and Performance: reuse the engine

**Question:** Can the engine supply collection and transport without an analytics SDK?

**Evidence:** [HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html), [Performance](https://docs.godotengine.org/en/stable/classes/class_performance.html), [Godot license guidance](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html). Checked 2026-11-18. Godot is MIT licensed; use the project's pinned engine version when implementing rather than silently upgrading to whatever `stable` resolves to later.

`HTTPRequest` supports HTTPS, completion callbacks, cancellation, timeout, a response body limit, and optional threading. Defaults are inappropriate for a bounded telemetry sender: timeout is zero (unlimited), response body limit is unlimited, and redirects are allowed. `Performance.get_monitor()` supplies FPS, memory and render counters; some monitors are debug-only and some update at intervals of up to one second.

**Design consequence:** Explicitly configure timeout, response byte cap and `max_redirects = 0`; use one in-flight **unthreaded asynchronous** request and a tested wall-clock deadline, with no main-loop wait for delivery. Repository integration review identified a silent-peer worker join hazard documented in `app/app_state/update_checker.gd` (UI-16-R1): do not set `use_threads = true`, and do not add a shutdown flush/join. Cancel on disable and invalidate completion callbacks with a consent generation. Collect only supported release-build measurements; represent unavailable values as unavailable, never as measured zero. Keep frame-time histograms in game code and reuse existing monotonic `FrameSamples` instrumentation. Preserve GPU timing availability/freshness distinctions; never upload the raw diagnostics bundle. Tests must exercise exported release builds, not just the editor.

<a id="tool-02"></a>

## TOOL-02 — OpenTelemetry Collector: reuse server-side routing

**Question:** Which infrastructure work can be delegated to an established component?

**Evidence:** [Repository and license](https://github.com/open-telemetry/opentelemetry-collector), [configuration](https://opentelemetry.io/docs/collector/configuration/), [security guidance](https://opentelemetry.io/docs/security/config-best-practices/), [core releases](https://github.com/open-telemetry/opentelemetry-collector/releases), [contrib releases](https://github.com/open-telemetry/opentelemetry-collector-contrib/releases). Checked 2026-11-18. Core repository is Apache-2.0. Observed latest core release: **v0.165.0**, displayed November 6; contrib: **v0.165.1**, displayed November 9. These are research observations, not an installed or production-approved dependency lock.

The Collector supplies receivers, processors, exporters and pipelines. Official security guidance recommends encryption, authentication, limited components, resource protection and sensitive-data scrubbing. Configuration can be validated with the Collector binary. A standard OTLP receiver expects OTLP; it does not automatically understand the project's custom JSON event contract.

**Design consequence:** Keep the Collector private. A small ingress validates game events and converts approved data using a maintained backend OpenTelemetry SDK if this route is selected. Exclude IP/header enrichment and host/process auto-detection from player telemetry. Use schema allowlists before forwarding, then redaction as defense in depth. Choose only required components and pin an exact image digest in implementation. Do not expose debug exporters or detailed payload logs in production. Backend, queue, retention and dashboard decisions remain explicit architecture tasks.

<a id="tool-03"></a>

## TOOL-03 — GameAnalytics for Godot: mature game taxonomy, incompatible defaults

**Question:** Does a ready-made gaming SDK satisfy the anonymous FPS/hardware/aircraft use case?

**Evidence:** [Official Godot SDK](https://github.com/GameAnalytics/GA-SDK-GODOT), [Godot integration](https://docs.gameanalytics.com/event-tracking-and-integrations/sdks-and-collection-api/game-engine-sdks/godot/), [releases](https://github.com/GameAnalytics/GA-SDK-GODOT/releases), [Godot asset listing](https://store.godotengine.org/asset/gameanalytics/gameanalytics/), [desktop C++ configuration](https://docs.gameanalytics.com/event-tracking-and-integrations/sdks-and-collection-api/open-source-sdks/cpp/configuration/), [event taxonomy](https://docs.gameanalytics.com/events-metrics-and-filtering/event-types/event-types-introduction/). Checked 2026-11-18. The official asset listing declares MIT; hosted-service terms are separate. Observed latest Godot SDK release: **3.2.0**, displayed October 21; recent release history includes Godot compatibility and network fixes.

The Godot SDK is a GDExtension and has desktop health-event support. Its event model includes session, progression, design and performance events. The desktop C++ SDK documentation says a random user ID persists across sessions. Submission is enabled by default; disabling event submission can still leave remote configuration fetching active. A custom user ID must be set before initialization.

**Design consequence:** Reuse the distinction between gameplay events and periodic health aggregates. Reject a direct default integration for base mode: no persistent player ID, no remote-config requests while off, and no undisclosed automatic events are project requirements. A future spike would have to inspect the exact Godot wrapper plus desktop SDK and verify all egress by packet capture. FPS tracking does not itself prove the desired statistical definition or acceptable overhead.

<a id="tool-04"></a>

## TOOL-04 — Aptabase for Godot: useful minimal sender, audit identity and retention

**Question:** Is there a small open-source GDScript analytics client worth reusing?

**Evidence:** [Godot SDK](https://github.com/aptabase/aptabase-godot), [platform documentation](https://aptabase.com/docs), [server repository](https://github.com/aptabase/aptabase), [self-hosting repository](https://github.com/aptabase/self-hosting). Checked 2026-11-18. SDK: MIT. Server repository: AGPL-3.0. SDK README requires Godot 4.2+. The viewed SDK repository showed only two commits and no visible versioned release; the commits endpoint was unavailable through the research tool, so a latest commit date or pinned revision was **not verified**.

The SDK uses an autoload, `HTTPRequest`, batches of up to 25 events, one in-flight request, and an in-memory queue capped at 1,000 events. It requeues network/5xx failures and drops 4xx responses. Those are helpful transport patterns, but 429 is also 4xx and requires an explicit project retry policy rather than copying this classification blindly.

Platform documentation describes a daily server hash from IP address and user agent, country/region derivation, automatic OS/version/locale information, short-lived session identifiers and analytics retention up to five years. Therefore the hosted defaults do not match a policy forbidding IP-derived identity or geolocation and requiring shorter retention.

**Design consequence:** Use as readable implementation inspiration or evaluate a narrowly scoped, attributed reuse after source review. Do not inherit vendor privacy claims. A self-hosted option still needs explicit server configuration/code verification, log review and retention enforcement. Queue purging on opt-out, consent generation fencing and bounded retry age are additional requirements.

<a id="tool-05"></a>

## TOOL-05 — Sentry for Godot: optional crash diagnostics, not base analytics

**Question:** Can established crash tooling replace custom crash-report infrastructure?

**Evidence:** [SDK repository](https://github.com/getsentry/sentry-godot), [releases](https://github.com/getsentry/sentry-godot/releases), [configuration](https://docs.sentry.io/platforms/godot/configuration/options/), [data collected](https://docs.sentry.io/platforms/godot/data-management/data-collected/), [native backend limitations](https://github.com/getsentry/sentry-native). Checked 2026-11-18. SDK: MIT. Observed latest release: **2.5.1**, displayed November 12. Versions 1.x/2.x require Godot 4.5+; supported targets include desktop and web.

Sentry's Godot extension builds on its native SDKs. `auto_init` defaults to true and runs before scenes/scripts. `attach_log` defaults to true. Device/OS details are sent by default, and Crashpad reports include thread stacks in minidumps. Screenshot and scene-tree attachments default off. `send_default_pii = false` does not remove sensitive text accidentally present in logs. Native backend documentation also records cases where crash callbacks such as `before_send` are not invoked.

**Design consequence:** Consider Sentry only for a later, separate crash-diagnostics choice with clearly different disclosure. Disable automatic initialization, log attachment, screenshots and scene-tree capture before any initialization; review all native cache files and backend-specific crash paths. A text redaction callback is insufficient to prove crash snapshots contain no personal information. Do not route raw crash dumps, logs or stack snapshots into public GitHub issues. Basic telemetry should report bounded error categories/counters instead.

<a id="tool-06"></a>

## TOOL-06 — PostHog: rich analytics with explicit anonymous-event configuration

**Question:** Could a general analytics backend replace custom queries and dashboards?

**Evidence:** [Anonymous versus identified events](https://posthog.com/docs/data/anonymous-vs-identified-events), [JavaScript API reference](https://posthog.com/docs/libraries/js/reference). Checked 2026-11-18. This investigation evaluates the hosted/API behavior; no Godot SDK version or full server license audit was completed, so no native dependency is selected.

PostHog distinguishes event capture without person profiles from identified events. Backend SDKs/API default to identified events unless person processing is explicitly disabled. Its current guidance permits a fresh random identifier reused for a visit/session. An identifier already associated with a person can still link the event to that person even when person updates are disabled.

**Design consequence:** A server-side adapter could map sanitized game data to PostHog with session-only random identity and person processing disabled. Explicitly forbid identify/alias/group calls, stable distinct IDs, autocapture, replay and marketing properties. Validate IP/GeoIP handling and retention for the exact ingestion path before selection. Powerful funnels are not worth weakening the base policy. Product dashboards must describe sessions, not imply deduplicated people or machines when no stable identity exists.

<a id="tool-07"></a>

## TOOL-07 — Matomo: HTTP ingestion and a useful privacy-proxy pattern

**Question:** Can a mature self-managed analytics product handle custom events without proprietary game integration?

**Evidence:** [Tracking HTTP API](https://developer.matomo.org/api-reference/tracking-api), [privacy-proxy configuration](https://matomo.org/faq/how-to/configure-the-tracker-proxy-to-remove-visitor-ip-addresses/), [privacy settings](https://matomo.org/faq/general/configure-privacy-settings-in-matomo/). Checked 2026-11-18. Evaluated as HTTP integration; exact Matomo release/plugin licenses remain implementation-spike inputs.

Matomo accepts event requests with category, action, optional name and numeric value. Its API recommends a persistent visitor ID but still tracks without one, with reduced visitor-count accuracy. The tracker proxy forwards client IP by default; an optional privacy feature removes it before Matomo receives the request. Ordinary IP anonymization at Matomo occurs after the request reaches Matomo.

**Design consequence:** The proxy pattern is useful: remove client network identity at the earliest controlled boundary, and do not forward `X-Forwarded-For` or similar headers downstream. Web visit semantics and custom numeric events require adaptation for frame-time distributions. Do not put raw hardware descriptions or user-defined aircraft names into free-text event names. Assess operational cost and retention before choosing it over a simpler event store.

<a id="tool-08"></a>

## TOOL-08 — TelemetryDeck: HTTP option with identity semantics to verify

**Question:** Does a privacy-oriented cross-platform analytics API avoid a custom event backend?

**Evidence:** [Anonymization design](https://telemetrydeck.com/docs/articles/anonymization-how-it-works/), [Ingest API v3](https://telemetrydeck.com/docs/ingest/v3/). Checked 2026-11-18. Current documented HTTP API: v3. No Godot SDK version or self-hosting/license claim is made here.

SDKs hash/salt a supplied or generated user identifier; documentation describes recognition across platforms when the same identity and salt are reused. The generic v3 event endpoint requires a `clientUser` string and hashes it server-side. Its separate web endpoint derives daily identity from IP and user agent and adds geographic information. These are different ingestion paths with different enrichment rules.

**Design consequence:** Hashing a stable ID is not the project's intended no-stable-identity behavior. A fresh session-only random value through the non-web endpoint might support the desired event model, but requires verification of server metadata, retention, configuration and disclosure. Do not claim unlinkability merely because the original identifier cannot be recovered. Do not use the web endpoint as a shortcut for desktop telemetry.

<a id="tool-09"></a>

## TOOL-09 — Countly Unity: consent design reference and a device-ID warning

**Question:** What consent mechanisms and hidden identity defaults should the design learn from?

**Evidence:** [Unity SDK documentation](https://support.countly.com/hc/en-us/articles/360037813851-Unity), [SDK repository](https://github.com/Countly/countly-sdk-unity). Checked 2026-11-18. SDK repository: MIT; documentation identifies SDK line 24.8.X and was displayed as updated November 3. This is an inspiration investigation, not a Godot integration proposal.

Countly exposes separate consent controls for sessions, events, location, crashes and other features. Consent gating must be enabled before initialization. Unity's device-unique identifier is the documented default identity source, including hardware-derived values on Windows. Consent state persistence is the integrator's responsibility; changing device identity can alter consent behavior and inflate user counts.

**Design consequence:** Reuse separate lifecycle handling and explicit pre-initialization gates, but not the identity model or SDK. The OpenRC Simulator adapter must persist a versioned preference itself, handle corrupt state conservatively, and keep metrics labeling honest when sessions cannot be deduplicated into people. Granular configuration must not leave background feature requests active after telemetry is disabled.

<a id="tool-10"></a>

## TOOL-10 — Unity Analytics: explicit consent state controls collection

**Question:** What does a mainstream engine's telemetry consent flow teach this design?

**Evidence:** [Opt-in SDK flow](https://docs.unity.com/en-us/analytics/privacy-and-consent/manage-data-privacy/sdk-compliance-opt-in), [privacy entry point](https://docs.unity.com/en-us/analytics/privacy-and-consent/manage-data-privacy). Checked 2026-11-18. The documentation distinguishes Unity 6.2+/Analytics SDK 6.1+ from older combinations. No Unity dependency is proposed for this Godot project.

Modern Unity Analytics uses an explicit consent state through the Developer Data framework. Older SDK examples begin collection only after `StartDataCollection()` is called. Unity also documents that separate services can require separate privacy handling.

**Design consequence:** Model preference, consent and collection separately. A default-on recommendation in the welcome UI is not a granted state until the user chooses the affirmative action. Closing the notice or continuing without telemetry must leave collection and transmission disabled. A future crash SDK cannot silently inherit base analytics consent if its payload is materially broader. Apply the same behavior uniformly rather than adding an IP geolocation lookup to choose a privacy flow.

<a id="tool-11"></a>

## TOOL-11 — OpenTelemetry C++: established SDK, unnecessary game dependency today

**Question:** Should the Godot application embed a native OpenTelemetry SDK?

**Evidence:** [C++ language status](https://opentelemetry.io/docs/languages/cpp/), [C++ repository](https://github.com/open-telemetry/opentelemetry-cpp), [exporters](https://opentelemetry.io/docs/languages/cpp/exporters/). Checked 2026-11-18. Repository: Apache-2.0. Documentation marks traces, metrics and logs stable. No concrete C++ package version is selected.

The project supplies metric/log/trace APIs and exporters and supports modern C++ toolchains. It can be appropriate for native backend/instrumented engine work, but GDScript is not a directly supported language in this SDK. Embedding it would require extension/build/packaging maintenance in addition to game consent and collection code.

**Design consequence:** Keep the initial game adapter in GDScript and reuse mature backend SDKs at the ingress where needed. If later native profiling proves necessary, benchmark a native SDK with a bounded exporter and explicit resource attribute allowlist; never let host/process resource detection attach machine names, process paths or user identifiers. Performance instrumentation and operational observability are separate data products from public aggregate analytics.

## Concrete implementation-spike checklist

These are work items, not claims of completed implementation:

1. Pin the actual production Godot version and audit supported release-mode monitors against that version.
2. Implement a bounded **unthreaded asynchronous** `HTTPRequest` adapter with no redirects, one request in flight, finite timeout plus wall-clock deadline, response cap, jittered retry, queue age/byte limits, and purge/cancel on disable. Reuse the repository's silent-peer handling lessons; never wait on shutdown for telemetry delivery.
3. Use a fixed application user-agent with no machine/browser fingerprint; redact request metadata at the earliest project-controlled ingress and confirm upstream provider logging policy.
4. Compare direct strict-schema persistence against mapping to OTLP plus a private Collector. Choose the simpler design that satisfies the actual dashboard queries; never add both without a clear need.
5. If Collector is selected, pin and verify image digest, validate configuration using that exact binary, inspect selected component maturity, and keep administrative credentials entirely server-side.
6. Capture network traffic for fresh start, accept, decline, disable during a request, offline retry, corrupt settings, app update and exit; prove no telemetry request precedes acceptance and no queued telemetry survives disable.
7. Compare gameplay with telemetry off/on on representative low-end hardware. Verify frame-time measurement overhead, not just sender throughput.
8. Do not install GameAnalytics, Aptabase, Sentry, PostHog or other client SDKs until an explicit feature justifies their broader behavior and that behavior passes the same packet/payload tests.

## Evidence handling and limits

The investigated URLs above were read, not merely listed from search results. Version numbers describe the pages observed on the research date; they must be pinned and rechecked during implementation. SDK licenses do not establish hosted-service terms, data-processing agreements, permitted retention, or legal compliance. No provider has been configured, no dependency has been installed, and no telemetry has been sent as part of this research.

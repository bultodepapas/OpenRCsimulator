# Telemetry architecture and integration

Status: proposed production design; the standalone contract model is the only executable work in this branch.
Baseline and phase status: [master plan](../telemetry.md).
Sources: [tool evaluation](../../research/telemetry/TELEM-00/tools.md), [repository audit](../../research/telemetry/TELEM-00/repository-audit.md).

## Data flow and trust boundaries

~~~mermaid
flowchart TD
  A["Consent and release policy"] --> B["Read-only game observations"]
  B --> C["Allowlist and bounded summaries"]
  C --> D["Memory queue and HTTPS sender"]
  D --> E["Private schema-validating ingress"]
  E --> F["Short-lived private records"]
  F --> G["Daily aggregates and disclosure gate"]
  G --> H["Trusted GitHub report job"]
  C --> I["Player payload preview"]
~~~

The first gate owns collection, queue creation and transmission. A hidden SDK, crash handler or remote-configuration fetch cannot bypass it. An ordinary TLS receiver sees a network IP; omitting it from JSON is not proof of anonymity. Receiving infrastructure is part of the privacy design.

## Reuse and scope

| Existing source | Reuse | Boundary |
| --- | --- | --- |
| app/app_root.gd | Interactive Home initialization, accepted activity changes, Settings and route decisions | Keep direct/technical and input-report paths off; all vehicle activities need explicit coverage |
| app/ui/startup.gd, screen_stack.gd, settings_screen.gd | Splash handoff, modal ownership, navigation, privacy category | Consent appears after locale/UI readiness; never interpret a splash dismissal as consent |
| app/app_state/preferences_file.gd | Existing atomic-write and protected-file lessons | Separate consent store and schema; do not silently infer a grant from other settings |
| app/app_state/build_info.gd | Verified export/development distinction and published build identity | Never send arbitrary describe strings, local paths or dirty build identities |
| app/app_state/aircraft_catalog.gd, vehicle_roster.gd | Stable shipped IDs and activity families | Home selection alone is not a flight; custom content maps to custom |
| app/render/frame_samples.gd | Monotonic interval and coverage semantics | Do not enable its large raw trace/disk stream in base telemetry |
| app/render/frame_diagnostics.gd | Capability, GPU freshness and memory interpretation | start() probes exact hardware and acquires timing; never start it for telemetry before grant or upload metadata wholesale |
| app/render/render_timing_lease.gd | Shared measurement ownership if optional GPU observations are introduced | No independent viewport timing enable/disable flag |
| app/statistics/service.gd | Accepted fixed-wing event classifications and detached notifications | Never serialize data/store, persistent IDs, history, source hashes or exact timelines |
| app/app_state/update_checker.gd | Bounded asynchronous HTTP lifecycle and silent-peer lesson | Keep update and telemetry preferences separate; its timeout/opt-out semantics are not copied blindly |
| app/render/auto_calibration.gd, auto_graphics_report.gd, gpu_capability.gd; app/app_state/renderer_preference.gd | Newer main d407acd has independent graphics recommendations, local calibration and renderer-mode ownership | Their hardware probes and shared timing lease continue independently of product telemetry consent. Never upload their raw dictionaries, adapter-keyed calibration file, diagnostics or logs. |
| tools/analytics/ | Existing website/GitHub traffic reporting, separate audience | Does not collect runtime game behavior; do not merge identities or denominators |

The original baseline had no universal whole-graphics presets. In newer main d407acd, renderer modes Automatic/Standard/High and separate scene-detail levels exist, but they are not whole-settings presets. The v1 wire context records renderer/driver, coarse resolution, vsync/cap and current_default/custom only. It does not capture those detailed settings; custom can represent materially different configurations. Do not claim comparable graphics configurations or explain individual graphics-setting effects from this context alone.

## Proposed module interfaces

New runtime modules remain outside app/ until a later implementation PR passes parsing and focused tests. This branch adds documentation, the research prototype and an offline contract-test workflow; it adds no runtime adapter or receiver.

| Module | Proposed interface | Responsibility |
| --- | --- | --- |
| policy.gd | effective_state(build, route, consent, local_off) | Pure admission result; no network or hardware calls |
| consent_store.gd | load(), grant(notice), disable(), save_outcome() | Versioned local choice; unknown state is closed |
| service.gd | start_after_grant(), observe_frame(...), observe_activity(...), disable() | Sole owner of the consent generation and session lifetime |
| hardware_profile.gd | classify_approved_sources() | Read after grant; exact strings are transient inputs, enums are outputs |
| frame_aggregate.gd | observe(wall_us, draws), close(reason) | Fixed-size histogram/counters; no simulation mutation or frame log |
| event_projector.gd | approved_context(...), approved_activity(...) | Construct a fresh finite-key object, never sanitize by deleting known bad keys |
| queue.gd | enqueue(bytes, epoch, created_monotonic), expire(now), purge() | Bounded memory FIFO, exact immutable bytes for preview/retries |
| sender.gd | tick(now), cancel(epoch), completion(token, result) | One asynchronous request, retry/deadline/size/host limits |
| privacy_screen.gd | render_effective_state(), preview(), choice_signal | Explanations and choices; never owns a second collection flag |

Use a single service under AppRoot for eligible product runs, not a global analytics autoload. Pass already accepted context from app/session adapters; no callback may add forces, alter inputs, step simulation, or affect replay.

## Admission and lifecycle

Eligibility requires a clean, approved exported build, the ordinary interactive route, a reviewed notice in the active offered locale, the current affirmative grant, a compiled HTTPS endpoint and no local force-off. Unknown build/route/locale/state fails closed. Source/editor, headless, direct-argument, replay, benchmark, capture and automated test routes are disabled. Exported debug builds are also disabled for production. A separately built, explicitly invoked and non-shipped qualification binary may use approved replay/input fixtures and the same production observer, projector, serialization and lifecycle, after explicit tester admission. Its only compiled endpoint is an isolated local test origin; it has no production origin or real player data. Its real timing and coarse host categories are controlled QA observations, not synthetic measurements. Record equivalence to the shipped adapter and test shipped ordinary-route off safety separately.

Policy is checked before telemetry-specific probes, before sealing a batch and immediately before submission. Independent gameplay graphics detection, local calibration and local statistics retain their own behavior and are not product-telemetry probes. Disabling first closes the gate and increments a monotonically increasing consent generation, then cancels the request, drops queue and preview, clears aggregates/session keys, and saves denial. Late callbacks carry the old generation and cannot requeue or restart anything. Re-enabling creates a new generation/session; it never resurrects old bytes.

If denial cannot be saved, collection remains off for the current process and the UI explains that the next launch may ask again or load the last stored setting. A durable deny marker is best effort, not a guarantee on unwritable storage. Corrupt, unknown or newer consent schemas fail closed; no fallback to a stale enabled backup. Material scope/recipient changes require a new notice; a prior off choice is retained without nagging.

Service suspension is a separate sticky policy latch. A 401/403/410 response or explicit service-suspension transition closes collection for that process; toggling off/on cannot clear it. A new eligible process or explicitly verified deployment configuration is required. The offline model permits only a fresh instance, with no in-process reset API. Unknown or non-Boolean eligibility never grants admission.

## Identity and timing

Use a cryptographically random 128-bit session token held only in RAM after admission. Rotate the active collection epoch at process restart, re-enable, UTC day boundary and at most four hours. A sealed batch from the old epoch may retain that token in RAM for the remainder of its existing ten-minute queue lifetime, including across the boundary; it cannot collect new observations or migrate to the new epoch. Cancel any still in-flight old-epoch request at that original deadline and fence late callbacks. The token correlates windows for deduplication/contribution limits, not people. Rotation does not produce a unique-user measure. Never derive it from hardware, account, local statistics IDs, time or IP.

A separate random batch ID plus immutable body identifies retries. A record sequence is monotonic within one session. No absolute client timestamps or precise session start time are sent. Server receipt day owns daily attribution. Session IDs and dedup keys have a 48-hour maximum retention, including operational copies; see the [retention contract](data-contract.md#retention-and-aggregation-lifetimes).

## Measurement boundaries

Observe render-process wall intervals using Time.get_ticks_usec; do not interpret Godot's smoothed/scaled delta as a display timestamp. Prime the first sample. Reset the clock at pause, loss of drawable/focus state, activity/context change and known OS resume. Exclude any interval >5 seconds and count it as excluded, without inferring its cause; this also omits genuine foreground freezes longer than five seconds. Ordinary 100–5000 ms hitches remain observations. This is a censored measure, not a complete freeze record.

Close a window normally as soon as its eligible interval sum reaches 30,000,000 microseconds; an earlier context, lifecycle or size-bound closure is partial. Apply the exact completeness and 60,000,000-microsecond hard-bound rules in the data contract. Summaries contain a process-interval histogram and an independently observed engine render-draw count. Render cadence is not physical monitor presentation, and frame generation is not proven by that counter. Keep native rendered rate distinct from any later measured presented rate.

Do not attach a telemetry observer to every 240 Hz physics tick. Read already accepted aggregate/session values at the application boundary. Local takeoff/landing classifiers remain authoritative; do not create a parallel detector. Unsupported activity classifications are unknown, never zero successful landings.

## Transport contract

| Limit | v1 design value |
| --- | --- |
| Endpoint | Exactly one compiled HTTPS origin/path; no query parameters or user-provided URL |
| Request | POST application/json, maximum 32 KiB UTF-8 after serialization; no compression in v1 |
| Events | 1–16 closed events per batch; no partial server acceptance |
| In-flight work | One request; use_threads=false; no synchronous wait |
| Timeout | 5-second request timeout plus monotonic deadline, tested during a silent connection |
| Response | Maximum 4 KiB, redirects=0, TLS verification enabled |
| Queue | At most 256 KiB / 32 sealed batches, oldest first eviction, maximum age 10 minutes |
| Cadence | At most one normal send per 60 seconds, randomized by 0–10 seconds |
| Retry | Full-jitter exponential delay 5…300 seconds; honor a valid longer Retry-After |
| Retry horizon | At most 5 retries per batch, also subject to age, hour budget and current grant |
| Hour budget | 90 attempts and 256 KiB transmitted body bytes including retries per fixed 3,600-second window anchored at the first counted request; preserve it across disable/re-enable and reset on a new process. Boundary bursts can exceed those limits within a rolling hour; ingress has independent caps. |
| Persistence | No telemetry payload/session token on disk; consent choice only |
| Shutdown | Cancel and drop; no final flush, retry, worker join or exit delay |

HTTP 202 means the whole validated batch and its dedup receipt are durably committed; a duplicate same-body batch also returns 202. Do not acknowledge before durable commit. 400/409/413/415/422 permanently drop that batch with a bounded local status code; 401/403/410 suspend the uploader until a new eligible process/configuration. Only connection failures, 408, 429 and 5xx are retryable. Never follow a redirect. No report body appears in error logs.

A server Retry-After beyond the queue lifetime causes expiry, not an early retry. With no disk queue, restart loses pending data. Disclose incomplete coverage. A public application identifier, Origin header or version string is not authentication and does not prevent forgery.

## Reuse choices and alternatives

Selected: Godot engine primitives, published catalogs, jsonschema's Draft 2020-12 validator, an ordinary database transaction and trusted GitHub APIs. A thin product-specific adapter is needed to enforce fields, consent and lifecycle; it is not a new general analytics platform.

GameAnalytics, Aptabase and PostHog are credible alternatives, but their identifier/enrichment/configuration behavior needs more work to meet this contract. Sentry is a later separate crash-diagnostics option; default auto-initialization and log capture cannot enter base mode. The research records licenses, versions observed and limitations.

OpenTelemetry is optional for backend operational metrics or later vendor portability. Its Collector does not ingest this arbitrary JSON automatically and is not the database or disclosure gate. If selected later, translate sanitized events with an official backend SDK and pin reviewed Collector components. Do not add that layer unless actual routing needs justify it.

## Fault containment

All product-telemetry failures are contained outside simulation and gameplay. Existing local auto-graphics recommendations and calibration may independently adjust graphics; disabling telemetry must not disable them. A full queue drops observations; a full database rejects ingestion; a failed publisher leaves the previous report and a stale status. None pauses flight. Local exceptions use fixed categories only. A production safety stop returns 410 or ships a local force-off configuration; it never remotely turns telemetry on, expands fields, or fetches anything from clients that are already off.

# Consent, transparency and player control

Status: **implemented in the client (TELEM-02/03), inactive in every build until activation (TELEM-14)**.
Authority: [master plan](../telemetry.md). Code: [policy](../../../app/telemetry/telemetry_policy.gd), [consent store](../../../app/telemetry/telemetry_consent_store.gd), [notice screen](../../../app/ui/telemetry_screen.gd), Settings → Interface in [settings_screen.gd](../../../app/ui/settings_screen.gd). Evidence: [privacy investigations P01–P12](../../research/telemetry/TELEM-00/privacy.md), [implementation verification](../../research/telemetry/TELEM-02/README.md).

## Product decision

Recommend telemetry on at the first ordinary exported launch. The recommended choice is visibly marked, but collection stays off until the deliberate, telemetry-specific **Enable telemetry and continue** action. Continue without telemetry, Escape, controller back, closing the window and input held while the notice appears never grant. The notice only appears after the branded intro has faded and every held skip input was released (AppRoot does not process before that handoff), and its two choices stay disabled until nothing is pressed for 0.6 s.

Both actions are equally visible and reachable. A saved grant starts collection automatically on later eligible launches; a saved decline is never re-prompted after routine updates. Every eligible launch states the effective choice on Home ("Telemetry is on · Settings → Interface" or "Telemetry is off · Settings → Interface").

The ICO source is a useful consent reference, not a universal legal determination. Actual distribution, recipients, children-related product choices and applicable requirements must be reviewed against the deployed design. Do not use IP geolocation to choose a weaker flow.

## Shipped copy

The English source strings live in [telemetry_screen.gd](../../../app/ui/telemetry_screen.gd) and [settings_screen.gd](../../../app/ui/settings_screen.gd); translations in `app/i18n/*.po`. The text below is the English and Spanish copy players see. `%s` is the operator named in the release configuration.

**Help improve OpenRC Simulator** — Recommended: share technical telemetry.

> If you choose Enable, we will send performance summaries such as FPS and frame-time ranges, broad CPU/GPU and memory categories, operating system, graphics renderer and API, resolution range, VSync/frame-rate cap, whether graphics settings are customized, and the built-in aircraft and activities you use. We also send the broad input method, activity duration and outcome, supported takeoff/landing and model-aircraft crash counts, and fixed categories of software errors. Model-aircraft crash counts are not application crash dumps. We use these reports to find slow configurations and improve the simulator.
>
> We do not send your name, email, account, device serial number, custom aircraft names, saved flight history, control inputs, files, screenshots or raw logs. A temporary random session code groups reports. It is not saved on this device and a new code is created at launch; the receiving service retains it for at most 48 hours after receipt. Our receiving service processes your IP to receive the connection, but the analytics database does not store it. Hardware and session data can still be distinctive, so we do not promise complete anonymity.
>
> Reports go to the receiving service operated by %s. Only reviewed summaries may be published on GitHub. You can inspect the data and turn telemetry off at any time in Settings → Interface. The simulator works the same with telemetry off.

**Enable telemetry and continue** · **Continue without telemetry** · links **See exactly what we send** · **Privacy notice**

The **Privacy notice** adds: pending data stays only in memory for at most ten minutes; the session code changes at least every four hours and at the UTC day boundary; raw reports, temporary codes and duplicate-check keys expire within 48 hours of receipt; code-free summary tables within 180 days; reviewed public GitHub summaries can remain indefinitely; any IP-based abuse protection is memory-only for at most 15 minutes; telemetry is separate from update checks. It ends with "Operator · Contact · Receiving service (origin)" from the release configuration.

Spanish (reviewed with the owner's language): **Ayúdanos a mejorar OpenRC Simulator** — Recomendado: compartir telemetría técnica. The paragraphs follow the English meaning exactly; see `app/i18n/es.po`. Actions: **Activar la telemetría y continuar** · **Continuar sin telemetría** · **Ver exactamente lo que enviamos** · **Aviso de privacidad**; location **Ajustes → Interfaz**.

The deployed retention and IP statements are **targets the operator must verify** before activation ([delivery](delivery.md#retention-and-logging-feasibility)); the copy may not ship enabled until they hold.

## Languages

[REVIEWED_NOTICE_LOCALES](../../../app/telemetry/telemetry_policy.gd) is `en`, `es`. All nine offered languages carry translations of every telemetry string (the catalog test requires it), but in German, French, Italian, Brazilian Portuguese, Russian, Japanese and Simplified Chinese telemetry is **off** and Settings says "Telemetry is not offered in this language yet." Switching to such a language closes the gate and drops pending data without changing the saved choice; switching back to a reviewed language resumes with a new session. To offer another language: a fluent reviewer checks its notice text and layout at 1920×1080 and large text, then add the code to `REVIEWED_NOTICE_LOCALES` in one reviewed change.

## Settings → Interface

The Interface page, after Updates, has **Share technical telemetry** (one switch), a status line and **See exactly what we send** / **Privacy notice**. Status lines: on (with batches sent this session), off, off until you choose, not offered in this language, paused by the receiving service, unreadable saved choice, not available in this build, plus a save-failure line. The switch is disabled where it cannot take effect (unavailable build, unreviewed language, suspended service).

**See exactly what we send** shows the exact sealed batches in memory byte for byte, then the events not yet sealed (with a placeholder batch ID). Before admission nothing exists to show. Off closes the gate immediately; no confirmation.

Not implemented (deliberately deferred): copy/export of a sanitized report, a separate "clear pending" action (off already clears), and the manual GitHub diagnostics projector below.

If saving the choice fails, Settings appends "Could not save the telemetry choice (error N). It applies to this session; check it again after restarting." A failed save never reopens the current gate. A decline removes any earlier grant before writing, and removes it again if the write fails, so a failed decline makes the next launch ask again instead of resuming (there is no restorable older grant: the file is replaced, never backed up).

The preview shows batches already sealed and events already numbered. The window being measured and an activity in progress appear once they close; error counters are added as one bounded `error_count` event per category when the batch is sealed.

## State machine (as implemented)

| Event | Prior state | New effective state | Side effects |
| --- | --- | --- | --- |
| Fresh profile | Any | Ask (off) | No probe, queue or request; notice appears once over Home |
| Unreadable/foreign/newer consent file | Any | Off (`unreadable`) | Not asked automatically; Settings explains; Enable replaces the file |
| Enable for the current notice, eligible build, reviewed language | Ask/off | On | New consent generation and memory-only session; only new observations |
| Continue without / Escape / close | Ask | Off (`declined`) | Saved; not asked again |
| Turn off | On | Off immediately | Generation advances first, request cancelled silently, queue/windows/activity/token dropped, choice saved |
| New notice version | Enabled | Ask | Stop and purge before asking; no automatic acceptance |
| Headless, direct/technical arguments, automation environment, test settings file, development/debug/dirty/untagged/manual export, missing release configuration | Any | Unavailable | No service node, consent-file read, probe or request |
| Service 401/403/410 | On | Off (`suspended`) for this process | Purge; saved choice unchanged; Enable refused until a new process |
| Language without a reviewed notice | Any | Off (`locale`) | Purge; saved grant does not resume until a reviewed language is active |
| Re-enable later | Off | On if eligible | New session; no historical replay |

## Meaning of privacy promises

The notice version in a submitted batch is an untrusted client assertion, not proof that a person affirmatively accepted it. Before activation, the operator must assess whether local-only choice evidence is sufficient for the actual distribution and processing obligations. Do not introduce a stable identifier as a shortcut.

We exclude direct identity and persistent cross-launch tracking. Temporary session IDs make raw reports linkable within a bounded session. Hardware combinations can still be identifying. Do not label raw records "fully anonymous", "untraceable" or "zero personal data".

The network host processes IP addresses. The receiver stores no IP or user agent, logs no body, and keys its in-memory abuse limiter with an HMAC of the address under a key rotated every 15 minutes. Hosting/proxy logs must be configured to match and named in the deployed notice; if a provider cannot, change it before enablement.

Declining sends nothing. Turning off sends no final or acknowledgment ping. Delivered bytes cannot be recalled. We cannot search records by player because no player identifier exists; explain automatic expiry and provide the operator contact.

The separate GitHub update checker keeps its own setting ("Check for updates automatically", same page). Telemetry off means no telemetry requests, not that every network feature is off. Local flight logs, statistics and diagnostics are separate local features.

## Manual diagnostics and crash reporting

Pending: a separate local manual-report projector exporting only approved build/context fields and user-selected aggregate diagnostics, never session_id, batch_id, seq or raw events. Show before opening GitHub:

> This report is optional. A GitHub issue identifies your GitHub account. In a public repository, the issue and attachments may be readable by anyone. Review and remove anything you do not want to share.

Never put a report in a URL, auto-submit or attach local logs. Crash SDKs need a separate design and notice; base consent does not cover memory dumps.

## Accessibility and acceptance

Implemented and tested headless at 1920×1080: equal actions, no default-focused grant before arming, Escape declines, held-input arming, status in Settings, translations present in all nine languages with glyph coverage. Still required before activation: rendered review of the notice at 1920×1080, above 1080p and 1280×720 (Apple Silicon Retina at native panel resolution), large text scales, controller traversal, and a screen-reader pass. The automated tests do not qualify rendered layout or assistive technology.

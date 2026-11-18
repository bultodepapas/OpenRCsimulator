# Telemetry follow-up: multilingual disclosures, F28–F30

Research notes for OpenRC Simulator, 2026-11-18. All searches were in English. Findings describe inspected sources, not a deployed OpenRC feature or an independent runtime verification of the other products.

<a id="f28"></a>

## F28 — Nextcloud: localized choice, identifiers and persistence

**Question.** Does a localized anonymity and control promise establish that the actual survey lacks a reusable identifier and that category choices persist?

**English discovery queries.** `Nextcloud usage survey app French localization survey data download identifier`; `"nextcloud/survey_client" "Collector.php" "id"`; `"survey_client" "instanceid" "'items'"`; `"Nextcloud" "survey_client" "id" Collector.php anonymized`.

**Primary evidence.** The [German survey-client translation](https://github.com/nextcloud/survey_client/blob/master/l10n/de.json) (German; moving `master`, accessed 2026-11-18) describes default-off sharing, category choices, anonymized data, monthly sending, and replacing a previous report with an empty one. These are product-copy claims. In [issue #305](https://github.com/nextcloud/survey_client/issues/305), a user of Nextcloud 29 reported that after unchecking categories, sending, and reloading, every box appeared checked again. This is one historical report, not a reproduced current defect or proof that an off switch failed.

A separate [first-person server issue](https://github.com/nextcloud/server/issues/28105) includes a 2021 network-error trace for Nextcloud 22.1.0.1 and survey-client 1.10.0: the attempted report contains an `id` field and detailed environment fields. This observation does not establish successful delivery, the identifier's origin, persistence, or equivalence to Nextcloud's instance ID. The direct collector source was unavailable to inspect. Do not infer anonymity or deanonymization from the label or this one trace.

**Transfer decision and test.** Retain OpenRC's proposed no-persistent-installation-ID rule and finite payload allowlist, with only short-lived session and batch tokens. When an actual UI exists, select off, restart/reload, and assert both the displayed state and a synthetic network spy remain off; cover failed writes, corrupted choice files, and revocation with queued bytes. Do not promise deletion of already aggregated data merely because local collection stops. Compare every localized disclosure against the versioned outbound schema.

<a id="f29"></a>

## F29 — Element: analytics and diagnostic-report consent

**Question.** Can a single analytics choice be assumed to cover crash logs and manually submitted diagnostics?

**English discovery queries.** `site:github.com/element-hq/element-x-android "analytics" "crash" "settings"`; `"element-android" "opt-in" "analytics" "bug reports"`; `site:translate.element.io "crash" "ru"`.

**Primary evidence.** Element's [Russian Android translation export](https://translate.element.io/download/element-android/element-app/ru/?format=json) contains distinct report labels for application logs, crash logs, screenshots, and key-share history, plus a prompt following an abnormal exit and language explaining a text-only option. Its [translation metadata](https://translate.element.io/projects/element-android/element-app/ru/) identifies `develop` and last remote commit `08dc499968`; the export was accessed 2026-11-18 and contains some unfinished strings. The [Android developer guide](https://github.com/element-hq/element-android/blob/develop/docs/_developer_onboarding.md#rageshake) separately describes a prompted bug report that can include a screenshot, logs from multiple starts, logcat, and key-sharing history. A [2022 Matrix project update](https://matrix.org/author/thib/page/20/) describes opt-in analytics and an Android 1.3.14 startup screen.

These sources establish distinct kinds of information and described user-facing flows, but they span versions and do not demonstrate that all current controls are independent or that any current build behaves as translated. We did not run Element or verify actual defaults, routing, retention, or a particular release's UI.

**Transfer decision and test.** Keep OpenRC's proposed automatic telemetry free of logs, screenshots, crash dumps and arbitrary diagnostic text. If a future diagnostic feature is approved, require an explicit, separately described action and consent for each attachment type; analytics consent alone cannot authorize it. In synthetic integration tests, exercise analytics off with a separately initiated diagnostic, analytics on without diagnostic consent, and revocation while a request is pending. Capture outbound bodies and logs to verify category separation, no automatic diagnostic upload, and truthful persistence across restart. This is a proposed OpenRC contract, not a claim about Element's runtime.

<a id="f30"></a>

## F30 — OpenTTD: localized disclosure and lost endings

**Question.** Does a game survey's opt-in preview imply its localized documentation is complete and its end-of-session data represents every session?

**English discovery queries.** `OpenTTD Spanish translation game options window survey Spanish wiki`; `OpenTTD survey telemetry Spanish translation consent payload exit crash source github`; `OpenTTD Spanish translation "survey" language strings consent github`.

**Primary evidence.** The [Spanish OpenTTD game-options manual](https://wiki.openttd.org/es/Manual/Opciones%20del%20Juego) describes language selection and older options, but its inspected page contains no survey section. The [English counterpart](https://wiki.openttd.org/en/Manual/Game%20options%20window) describes opt-in and preview. The Spanish page references pre-0.7 versions, so its omission may reflect stale documentation; it does not establish the current Spanish UI is missing a notice. OpenTTD's [survey disclosure](https://survey.openttd.org/participate) says reports can be sent on leaving, exiting, or crashing and lists settings, installed content, companies, duration and basic hardware.

The [survey implementation](https://docs.openttd.org/source/d3/d5e/network__survey_8cpp_source.html), snapshot `20261112-master-gbcbec5e63f` accessed 2026-11-18 and independently reopened by the lead, builds those categories, skips transmission unless participation is `Yes`, and limits the blocking wait to two seconds. Its preview conditionally redacts a build key and formats JSON differently. Thus preview information and outbound bytes are not literally identical in that case. Failure, abrupt termination, offline use or the deadline can lose an ending; this is an inference about possible incomplete observation, not a measured loss rate.

**Transfer decision and test.** For each OpenRC notice language, review the same consent, payload, revocation and loss explanations against the applicable schema. Test preview against a synthetic captured batch, explicitly documenting any redacted values or formatting differences; simulate offline exit, timeout, abrupt termination and revocation. Treat missing endings as unknown, never zero failures or a complete denominator. The opt-in project's broader survey fields are not a reason to expand OpenRC's narrower allowlist.

# Telemetry follow-up: multilingual investigations F25–F27

Research evidence retained after lead review. Sources accessed **2026-11-18**; no external software was installed or run. These are three investigations, not counts of URLs.

**Search-method correction.** Four early discovery queries used French or Italian terms, contrary to the English-only search requirement. They were discarded: `site:manpages.debian.org/fr popularity-contest fichier identifiant envoi statistiques paquets`; `site:docs.krita.org/it crash log dati risoluzione problemi file registro diagnosi`; `"popularity-contest" "fr" "Debian" "paquets" "identifiant"`; and `site:debian.org "concours de popularité" "paquets" envoyer identifiant`. I then repeated discovery with the English queries below and reopened each retained French, German and Italian source and its English corroboration. The mistake is not counted as another investigation.

<a id="f25"></a>

## F25 — Debian popularity contest: selection and rare signatures

**Question.** What can a voluntary software-usage survey teach about misleading participation measures and rare cohorts?

**Exact English discovery queries.** `Debian reference manual French popcon usage votes noatime`; `site:debian.org/doc/manuals/debian-reference French reference popcon biased statistics noatime`; `site:sources.debian.org/src/popularity-contest/1.78/FAQ/ reporting privacy unique id rare packages`.

**Inspected primary sources / version.** French: [Debian Reference 2.152](https://www.debian.org/doc/manuals/debian-reference/pr01.fr.html) and [Debian privacy policy](https://www.debian.org/legal/privacy.fr.html). English corroboration: [Reference](https://www.debian.org/doc/manuals/debian-reference/pr01.en.html), [privacy policy](https://www.debian.org/legal/privacy), and the packaged [popularity-contest 1.78 FAQ](https://sources.debian.org/src/popularity-contest/1.78/FAQ/). The policy is live and the FAQ describes that package version; current service behavior and retention were not independently tested.

**Findings.** The French policy describes explicit opt-in, a random 128-bit host ID for correlating submissions, possible IP/email metadata, and identification risk from rare package signatures. The French Reference cautions that `noatime` can suppress usage votes and that figures are not absolute measures; its denominator is submissions. The English 1.78 FAQ says access/change times are rounded to 12-hour intervals, a weekly run is randomized, and the public summary omits UUIDs. It nevertheless describes a rare-package absence inference. The sampled population and instrumentation are specific to Debian, not simulator players.

**Inference / change and test.** Keep OpenRC's temporary session IDs, participant-only coverage labels and frozen, disclosure-reviewed reports; do not infer distinct people or replace unknown measurements with zero. Suppress rare categories and assess information across repeated reports, not merely whether direct IDs were removed. Use synthetic cases with a single rare approved category, overlapping snapshots and an unavailable measurement; assert suppression, resistance to those specific differencing attempts, and visible missing coverage. No anonymity guarantee follows from a threshold or this historical example.

<a id="f26"></a>

## F26 — Syncthing: consent version and release channel

**Question.** How can a versioned usage-reporting choice differ from reporting behavior on another build channel?

**Exact English discovery queries.** `site:github.com/syncthing/syncthing gui/default/assets/lang/lang-de.json usage reporting report format changes candidate`; `site:docs.syncthing.net usage reporting configuration version unique id candidate releases`; `site:github.com/syncthing/syncthing "URAccepted" "URUniqueID" "usage"`.

**Inspected primary sources / revision.** German: Syncthing's [official UI locale](https://github.com/syncthing/syncthing/blob/main/gui/default/assets/lang/lang-de.json), moving `main`. English: [v2.0.0 configuration manual](https://docs.syncthing.net/v2.0.0/users/config.html), [current release-channel documentation](https://docs.syncthing.net/users/releases), [current security documentation](https://docs.syncthing.net/users/security), and moving `main` [configuration implementation](https://github.com/syncthing/syncthing/blob/main/lib/config/optionsconfiguration.go). The code and live docs were not pinned to the same release or executed.

**Findings.** The German locale has a changed-report-format prompt and a candidate-release reporting notice; those strings alone do not prove runtime behavior. The English v2.0 manual describes `urAccepted` values for undecided, declined and accepted report versions, `urSeen` for the highest displayed version, and an ID generated for enabled usage reporting. The inspected code generates an ID when reporting is accepted and no ID exists. Current English channel documentation describes usage reports as optional on stable and mandatory on candidate releases; the security page describes preview and periodic posting. The configuration manual separately describes automatic crash reporting as enabled by default. No claim is made that a particular user's current build or disable transition was tested.

**Inference / change and test.** Adopt the useful separation between the version *shown* and the version actually *accepted*, without copying the persistent ID, candidate override or default crash reporter. In OpenRC, denial must remain effective for every build/channel; material scope changes require a fresh affirmative grant, while a past denial is retained. Test old accepted notice, explicit denial, unknown/new schema, release candidate, local force-off and restart. Assert no telemetry probe, queue or request without an eligible current grant, and test crash/reporting paths separately. Reverify any reused upstream version rather than assuming locale strings enforce settings.

<a id="f27"></a>

## F27 — Krita: local diagnostics versus transmission

**Question.** How should a privacy screen distinguish telemetry from separately generated local diagnostics and manual bug reports?

**Exact English discovery queries.** `Krita manual Italian logs usage information crashes sharing bug reports`; `Krita Italian manual log viewer enabled save text file debug`; `site:docs.krita.org/it reference manual sharing logs crash system information`.

**Inspected primary sources / revision.** Italian: Krita Manual **5.3.0** [log collection](https://docs.krita.org/it/reference_manual/sharing_krita_logs.html) and [log viewer](https://docs.krita.org/it/reference_manual/dockers/log_viewer.html). English corroboration: [log collection](https://docs.krita.org/en/reference_manual/sharing_krita_logs.html) and [general settings](https://docs.krita.org/en/reference_manual/preferences/general_settings.html). The manuals describe supported workflows, not a tested Krita build.

**Findings.** Both languages describe a local usage log with the last ten sessions, opening times, system details and created/opened/saved filenames; system information and crash backtraces are distinct artifacts. The Italian log-viewer guide says its enable setting persists between sessions and the user can save text. English settings state that the bug-report log is locally stored and user-uploaded. This documents the specified log workflow; it does not prove every build or extension has no other network activity.

**Inference / change and test.** OpenRC's documented F10 flight recording is a separate local action. State narrowly that disabling telemetry stops the telemetry collection/upload path; do not imply that manually created local flight logs vanish or that all networking stops. Keep the planned manual report as a fresh allowlisted, user-previewed projection, identify the GitHub recipient/visibility, and require the player to perform any attachment/submission. Never attach the existing raw flight/diagnostics archive. Test telemetry off with a separately initiated local recording, then preview a synthetic report containing private filename and hardware canaries: the preview must be inert, the projected file must exclude prohibited values, and no network request or submission may occur automatically. This is a proposed qualification, not a claim that OpenRC's unimplemented telemetry already passes.

# Telemetry follow-up — adaptive research and implementation preparation

Date: 2026-11-18. Starting commit: [48ae3016](https://github.com/bultodepapas/OpenRCsimulator/commit/48ae3016a655acf7d062da3f32d72b9050c9e59a).
This extends the [original 38 investigations](../TELEM-00/README.md); it does not recount them as new work.
Deliverables and retained discovery queries are in English. The unconventional round inspects primary material in eight other languages. The search-method correction below records noncompliant early discovery queries and their repeated English discovery honestly.

## Method

Investigate ten questions first, review their evidence, then select ten narrower questions from what those findings expose. Finally investigate ten unconventional examples, including original material in other languages. One investigation means one substantive question and its decision consequence, not one search result or URL. Technical conclusions rely on maintainers' repositories, first-party tutorials, documentation, original issue reports or research authors. Issue/forum observations are leads, with their actual version and reproduction limits retained.

The lead inspects material original evidence, resolves the design and integrates the code. Three bounded helpers research independent questions; requested route is gpt-6.1-terra with max effort, fresh context. Effective provider model/effort is not independently verified. A separate review examines the integrated candidate. No helper result or source page authorizes deployment or publication of telemetry.

## Checkpoint after the first ten investigations

**This checkpoint was made before dispatching the second round.** F01–F10 had been read and assessed. The existing narrow Godot adapter, direct receiver and aggregate GitHub destination remain the preferred architecture. Broad analytics SDK selection is no longer the most useful next question.

| First-round evidence | Lead decision | Direction for the next round |
| --- | --- | --- |
| F01–F04: process intervals, draw counts, presented frames and displayed frames are different; focus does not prove physical visibility | Keep the render-cadence label; add independent metric-definition and visibility qualification | Existing capture/fault tools, transport observation and measurement interpretation |
| F05: relay acknowledgement can precede database commit or include intentional drops | Keep the direct atomic receiver; no raw relay in the pilot | Exercise uncertain delivery and transaction boundaries with established tools |
| F06: reverse-proxy defaults can persist bodies and IP-bearing error context | Qualify every logging/temp path with synthetic canaries | Inspect the application-server layer and error-path testing |
| F07: date partitions complicate global uniqueness; row deletion is not physical erasure | Prefer ordinary logged, unpartitioned pilot tables with indexed expiry; retain the hard storage deadline as an unqualified deployment requirement | Transaction conflicts, backup chains and feasible separation of raw and aggregate storage |
| F08: thresholds and edited reports have observable disclosure history | Keep initial reports private and freeze reviewed public snapshots; do not claim person-level anonymity or DP | Whole-report release inventory and reproducible publication state |
| F09: stateful combinations extend the example-based tests | Add a bounded test-only generative harness using an established library | API fuzzing and independently specified invariants |
| F10: find-then-create is not atomic; a lost response can leave an unknown remote write | Preserve uncertainty and reconcile; never blindly create again | Practical durable coordination and provider failure semantics |

The second round will pursue these gaps, rather than add another undifferentiated list of analytics vendors. The final unconventional round will seek useful counterexamples in other software communities and languages, with transfer limits stated.

## Evidence and verification

The canonical [implementation plan](../../../plans/telemetry.md) owns current decisions. Dated research describes observed sources, not installed tools or production qualification. This follow-up records accepted, adapted and deferred proposals alongside the actual offline checks; game runtime, provider retention and real publication remain separate gates.

## Investigation register

**30 new investigations; 68 across both research packages.** The first checkpoint preceded round two; each entry records its question, English discovery, inspected primary sources, inference, transfer decision and limits.

### Round 1 — test the architecture

| ID | Investigation | Evidence |
| --- | --- | --- |
| F01 | PresentMon: present calls are not display changes | [Sources and consequence](round1-measurement.md#f01) |
| F02 | MangoHud: a concrete percentile-definition mismatch | [Sources and consequence](round1-measurement.md#f02) |
| F03 | Perfetto: alignment requires explicit clocks and loss accounting | [Sources and consequence](round1-measurement.md#f03) |
| F04 | Godot maintainer issue: callback and visibility edge cases | [Sources and consequence](round1-measurement.md#f04) |
| F05 | Vector: delivery and acknowledgements | [Sources and consequence](round1-operations.md#f05) |
| F06 | NGINX: temp files and request logging | [Sources and consequence](round1-operations.md#f06) |
| F07 | PostgreSQL: expiry and recoverable copies | [Sources and consequence](round1-operations.md#f07) |
| F08 | Can the present token threshold make repeated aggregate releases anonymous? | [Sources and consequence](round1-disclosure.md#f08) |
| F09 | Can generative tests find consent, retry and malformed-input sequences missed by examples? | [Sources and consequence](round1-disclosure.md#f09) |
| F10 | Does a reusable comment action solve publication concurrency and idempotency? | [Sources and consequence](round1-disclosure.md#f10) |

### Round 2 — follow the evidence

| ID | Investigation | Evidence |
| --- | --- | --- |
| F11 | Toxiproxy: test uncertain delivery at a known commit boundary | [Sources and consequence](round2-measurement.md#f11) |
| F12 | mitmproxy: synthetic HTTPS inspection is not a no-egress proof | [Sources and consequence](round2-measurement.md#f12) |
| F13 | HdrHistogram: corrected latency is a different population | [Sources and consequence](round2-measurement.md#f13) |
| F14 | airspeed velocity: bind comparisons to a compatible benchmark context | [Sources and consequence](round2-measurement.md#f14) |
| F15 | PostgreSQL: transaction and expiry races | [Sources and consequence](round2-operations.md#f15) |
| F16 | pgBackRest: backup-chain retention | [Sources and consequence](round2-operations.md#f16) |
| F17 | Uvicorn, Starlette and FastAPI error paths | [Sources and consequence](round2-operations.md#f17) |
| F18 | Can Schemathesis exercise the proposed receiver's HTTP contract? | [Sources and consequence](round2-disclosure.md#f18) |
| F19 | What does durable execution actually guarantee for remote publication? | [Sources and consequence](round2-disclosure.md#f19) |
| F20 | Can a pooled FPS change identify a release regression? | [Sources and consequence](round2-disclosure.md#f20) |

### Round 3 — unconventional and multilingual

| ID | Investigation | Evidence |
| --- | --- | --- |
| F21 | OBS Studio, Brazilian Portuguese: viewing and sharing a diagnostic log | [Sources and consequence](round3-measurement.md#f21) |
| F22 | Godot, Japanese: focus and readable consent under expansion | [Sources and consequence](round3-measurement.md#f22) |
| F23 | GIMP, Spanish: targeted issue material differs from performance logs | [Sources and consequence](round3-measurement.md#f23) |
| F24 | Fcitx, Chinese: a warning can travel with an unreviewed dump | [Sources and consequence](round3-measurement.md#f24) |
| F25 | Debian popularity contest: selection and rare signatures | [Sources and consequence](round3-operations.md#f25) |
| F26 | Syncthing: consent version and release channel | [Sources and consequence](round3-operations.md#f26) |
| F27 | Krita: local diagnostics versus transmission | [Sources and consequence](round3-operations.md#f27) |
| F28 | Nextcloud: localized choice, identifiers and persistence | [Sources and consequence](round3-disclosure.md#f28) |
| F29 | Element: analytics and diagnostic-report consent | [Sources and consequence](round3-disclosure.md#f29) |
| F30 | OpenTTD: localized disclosure and lost endings | [Sources and consequence](round3-disclosure.md#f30) |

## Checkpoint after twenty investigations

F11–F20 narrowed the implementation work to independent fault boundaries, error-path canaries, transaction/backup semantics, a test-only generative harness and frozen publication intent. The lead prepared these mechanisms instead of installing a general analytics platform. The unconventional round then tested transparency and diagnostics assumptions against OBS, Godot's Japanese UI guidance, GIMP, Fcitx, Debian, Syncthing, Krita, Nextcloud, Element and OpenTTD.

## Search-method correction

Two helpers violated the English-only discovery instruction in **ten early queries**: six OBS/Fcitx queries and four Debian/Krita queries. The lead required English rediscovery and reopening of the retained evidence. The exact discarded queries and the corrected English queries are recorded in [round 3 measurement](round3-measurement.md) and [round 3 operations](round3-operations.md). They are not extra investigations, and this record does not claim that every executed query complied. Later discovery and the integrated writing use English. Source languages include Brazilian Portuguese, Japanese, Spanish, Chinese, French, German, Italian and Russian; localized strings alone are never treated as runtime proof. The Nextcloud entry used available German primary material rather than the initially suggested French route.

## Lead integration decisions

| Evidence | Accepted/adapted work | Deferred or rejected |
| --- | --- | --- |
| F01–F04, F13–F14, F20 | Explicit metric populations, visibility qualification, known arithmetic fixtures and context/mix limitations | No profiler SDK or modeled HDR samples in automatic telemetry |
| F05–F07, F15–F17 | Direct atomic receiver, unpartitioned pilot candidate, exact expiry/race specification, full error/temp/backup inventory | No generic raw relay, unlogged durability shortcut or claim that row deletion proves erasure |
| F08, F10, F19, F25 | Frozen snapshots, unknown outcomes, current public-inventory reservations and sticky conflict model | No automatic public correction, exactly-once promise or formal/person-level anonymity claim |
| F09, F18 | Pinned Hypothesis tests now; schema/HTTP qualification specified for a later real receiver | No live Schemathesis run, production endpoint or new runtime dependency |
| F11–F12 | Commit-barrier and synthetic interception/egress experiments specified | Tool research does not establish network qualification |
| F21–F24, F26–F30 | Local/manual/automatic data separation; exact artifact preview; persistent denial; expanded-text/focus tests; missing endings remain unknown | No automatic raw log attachment, persistent ID, candidate override, blocking exit upload or inference of current behavior from old/localized text |

The [verification record](verification.md) and [independent review](review.md) distinguish executed checks from the production gates. Current requirements live in the [master plan](../../../plans/telemetry.md), [validation laboratory](../../../plans/telemetry/validation-lab.md) and [publication protocol](../../../plans/telemetry/publication-protocol.md). No new collection category was added to the wire schema by this follow-up.

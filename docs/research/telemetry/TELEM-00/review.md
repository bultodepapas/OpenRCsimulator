# Independent review and lead resolutions

Date: 2026-11-18. Scope: the proposed architecture plus integrated offline Python contracts/model/fixtures. Source baseline: 39fa2746ae4f4ba8698b87db279adcfe84ef5d17. The lead owns the final design and verification.

A bounded Good Enemy reviewed the source seams and then the actual candidate. Requested helper route: gpt-6.1-terra, max effort, fresh context; provider-effective model/effort was not independently verified. It returned concrete reproductions and independently ran the 62-test suite and both generators in check mode, all passing.

## Findings that changed the candidate

| Finding | Resolution / evidence |
| --- | --- |
| Short-lived IDs cannot yield an exact weekly distinct-player count | Defined closed-day cohorts, 48-hour receipt-based raw/dedup expiry, ID-free daily output and explicitly filtered weekly session-day observations |
| Public thresholds could leak through totals or count repeated windows as people | Fixed one-dimensional daily GPU table, distinct temporary tokens, 120-window contribution cap, whole-table suppression on any small cell, no total; adversarial tests |
| Raw diagnostics collect full hardware strings and local flight history has persistent identifiers | Narrow new projection only after grant; no raw metadata/store serialization or backfill; source audit and data contract |
| A failed opt-out persistence write could leave the old saved grant | Immediate current-process off with truthful save-failure UI; durable behavior remains a production test gate |
| A late completion could acknowledge a newer retry in the same consent generation | Unique request-attempt token as well as consent generation; explicit stale-attempt test |
| Regex end anchors accepted a final newline in IDs/release/period | Exact ID/period lengths and strict release end; adversarial newline fixtures |
| Missing draw data was implicitly counted as a rendered frame, while a real zero became unknown | Default draw observation is unknown; preserve observed zero; independent known/unknown/zero tests |
| Intel Xeon was classified as Core and marketing punctuation hid Intel Arc | Narrow token-based examples, known-other fallback and counterexample tests |
| A “daily” reducer had no trusted receipt day or exact close window | Require trusted receipt-day/body tuples and UTC as-of time; reject mixed/open/expired days; close +1 h and start +47 h boundaries tested |
| A daily report labeled only by ISO week implied a complete weekly result | Required closed_day scope and exact UTC date; weekly orchestration remains explicitly unimplemented |
| Syntactically valid fake release tags could create cardinality | Fake ingress has a fixed approved-release set; production deployment manifest and caps are required |
| First-run notice omitted input class, activity outcomes/counts and software errors | Lead expanded both EN and ES copy to match the actual schema, including model-aircraft crashes vs app dumps |
| “No individual journey” conflicted with a temporary activity sequence | Qualified as no persistent cross-launch journey and disclosed short-lived session/activity trace |

The reviewer reported no other blocking finding within the offline candidate's declared scope. The lead inspected/applied the final two wording corrections after that report. A clean review is not proof of runtime privacy, hardware performance, legal applicability or an operating backend.

## Remaining required evidence

Actual Godot UI and consent persistence; exported package routing; packet/silent-peer/cancellation behavior; real frame/heap overhead; concurrent durable ingestion; provider/IP/log/backup deletion; multi-instance preference behavior; weekly pooling/aircraft tables; and GitHub idempotency/permissions/scheduling remain open in [verification](../../../plans/telemetry/verification.md). They were not waived or simulated into passing release status.

The [recorded checks](verification.md) distinguish executed prototype results from these future gates. No review created a production endpoint or transmitted player data.

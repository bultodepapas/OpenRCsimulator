# Telemetry audit: deeper correctness and optimization review

**Review date:** 22 November 2026, America/Bogota. **Audited runtime:** [`7940a4081e10994f34c858c4acac3d7a1a271464`](https://github.com/bultodepapas/OpenRCsimulator/tree/7940a4081e10994f34c858c4acac3d7a1a271464). A fresh fetch found `origin/main` still at that baseline. This report extends the [first audit](README.md); its 13 findings and original test results remain historical evidence, not newly executed tests.

The deeper pass adds **five correctness/recovery findings, two validation gaps and three optimization opportunities**. Four of the five findings have local behavioral counterexamples; one follows from traced source and existing controller fixtures. Both validation gaps were reproduced with deliberately invalid inputs. Two optimization opportunities have bounded measurements, and one is a source-level hypothesis awaiting target-hardware profiling. These are ten review entries, not ten confirmed production incidents.

The original two High findings remain the first repair priority: accepted numeric data can block daily rollup, and actionable rollup/retention warnings can be lost on their way to the independent monitor. This pass adds failure cases around error delivery, input attribution, recovery and independent data sources, plus evidence of repeated rollup and archive work.

## Findings and evidence map

Severity follows the [first-pass definitions](README.md#prioritized-findings). Gap and opportunity priorities are planning recommendations rather than defect severity.

| ID | Category / priority | Result | Evidence and detail |
| --- | --- | --- | --- |
| TA22-R2-F01 | Medium / P2 | An error recorded after the initial batch remains unsent through ten ineligible minutes because no ordinary event triggers sealing; pending status and preview are empty. | Actual Godot service, injected clock/context and fake sender; [client report](second-pass-client.md) |
| TA22-R2-F02 | Medium / P2 | Ground activity is labeled with the aircraft controller registry's input class even when the ground vehicle uses its own gamepad or keyboard selection. | Producer/consumer source trace and existing controller fixture; AppRoot telemetry projection not executed end to end; [client report](second-pass-client.md) |
| TA22-R2-F03 | Medium / P2 | A public/private collection overlap can discard new private community data while the private sync exits successfully. | Actual importer, disposable SQLite and fake SSH; [operations report](second-pass-operations.md) |
| TA22-R2-F04 | Low / P3 | An identical retry of an already stored batch receives 503 once the raw-storage quota is full. | Actual ingress and SQLite; [details below](#ta22-r2-f04--low-full-storage-quota-rejects-an-already-stored-identical-retry) |
| TA22-R2-F05 | Medium / P2 | A stale receiver timestamp selects an obsolete overview window, hiding independently refreshed GA4 data. | Actual overview date/metric logic with presentation helpers stubbed; [operations report](second-pass-operations.md) |
| TA22-R2-G01 | Validation gap / P2 | Non-finite refill rates and invalid capacity values are accepted at startup; constructed settings bypass a limiter or prevent admission. | Actual environment parser and limiter; [details below](#ta22-r2-g01--validation-gap-capacity-settings-are-not-fully-validated) |
| TA22-R2-G02 | Validation gap / P2 | A malformed upstream GA4 date can turn a nonzero count into an apparently observed zero without a report-quality flag. | Synthetic invalid upstream response through the real collector; [operations report](second-pass-operations.md) |
| TA22-R2-O01 | Optimization / P2 | Rollup retains a full day's decoded input and serializes each event for deduplication three times in the measured workload. | Actual local rollup, three workload sizes; [details below](#ta22-r2-o01--optimization-opportunity-repeated-rollup-work-and-full-day-materialization) |
| TA22-R2-O02 | Optimization / P2 | The client observer repeats property reflection, backend summary and dictionary/queue allocations on the frame path. | Source counts; no CPU or FPS impact measured; [client report](second-pass-client.md) |
| TA22-R2-O03 | Optimization / P3 | Archive loading performs an asset query per observation and reconstructs historical intervals; retained snapshot rows grow with observations and assets. | Synthetic SQL query counts and row counts; [operations report](second-pass-operations.md) |

## TA22-R2-F04 — Low: full storage quota rejects an already stored identical retry

**Condition and impact.** A client may lose the response to a successfully stored batch and retry the same bytes. If raw storage reaches its configured live-page quota before the retry arrives, the receiver returns 503 even though it already has the data. This produces unnecessary retries and a misleading storage-failure response for an idempotent acknowledgement. The demonstrated batch remains stored once; this finding does not demonstrate lost or duplicated data, and rejecting genuinely new data at capacity is correct.

**Source evidence.** [`RawStore.ingest`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/storage.py#L162-L184) checks `_size(conn) >= max_bytes` before examining whether the batch ID and digest already exist. The [architecture's retry rule](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/docs/plans/telemetry/architecture.md#L102-L119) says identical retries return 202; the [data contract](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/docs/plans/telemetry/data-contract.md#L112-L120) requires acknowledgement without counting the event twice. Existing duplicate and full-store tests cover the conditions independently.

**Reproduction.** The [receiver probe](../../../../research/telemetry/audit-2026-11-22/round2/receiver_boundaries_probe.py) stores one valid batch, measures 32,768 live-page bytes, then reopens that temporary database with its configured quota equal to the existing usage. It exercises real in-process HTTP ingress. This represents a full configured budget, not a physically full filesystem.

| Operation | Actual result |
| --- | --- |
| Initial valid batch with space | HTTP 202 |
| Same bytes, same ID, quota now full | HTTP 503 |
| Different valid batch, quota full | HTTP 503 |
| Stored batch rows after both retries | 1 |
| Same original bytes after restoring headroom, 240 seconds after the initial receipt | HTTP 202; original receipt unchanged |

**Repair and acceptance.** Resolve duplicate/conflict identity inside the transaction before applying the new-storage budget, preserving the original receipt and retention deadline. Cover identical retry, conflicting body, conflicting event sequence, new batch and expired batch at the capacity boundary. A fix must retain atomicity and must not refresh an old batch's TTL merely to acknowledge it. Physical I/O failure remains a separate failure mode. [Captured evidence](../../../../research/telemetry/audit-2026-11-22/round2/evidence/receiver-boundaries.json).

## TA22-R2-G01 — Validation gap: capacity settings are not fully validated

**Condition and classification.** These are operator-controlled environment settings, not remote request fields. The default values were not shown to be invalid. The problem is failure to reject settings that cannot implement their stated capacity or rate behavior, leaving startup apparently successful with ineffective or permanently blocking controls.

The [integer parser](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/config.py#L15-L23) checks syntax but not positivity. The [float parser](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/config.py#L26-L36) rejects negative values and NaN through its comparison, but accepts positive infinity. The [configuration builder](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/config.py#L105-L130) validates the purge interval's bounds but does not impose corresponding rate/capacity ranges.

The same receiver probe confirms all five settings are accepted:

| Setting suffix after `OPENRC_TELEMETRY_` | Supplied value | Demonstrated consequence |
| --- | --- | --- |
| `CLIENT_REFILL_PER_S` | `inf` | With burst 1 and a fixed clock, all ten client checks are admitted; the finite zero-refill control admits one. |
| `GLOBAL_REFILL_PER_S` | `inf` | Accepted by the same parser; the probe does not separately measure this limiter's end-to-end behavior. |
| `CLIENT_BURST` | `0.5` | A bucket capped below one token cannot admit the first one-token request. |
| `MAX_CLIENTS` | `-1` | The first new-client check is refused because the configured capacity cannot hold any client. |
| `MAX_RAW_BYTES` | `-1` | Accepted configuration; the source's nonnegative live-page usage necessarily satisfies its full-store comparison. |

The actual [limiter refill and admission paths](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/limits.py#L50-L99) execute in the probe. The infinite client refill result is specific to the tested finite-capacity, fixed-clock setup; it is not a claim that the ordinary defaults allow unlimited traffic.

**Repair and acceptance.** Require finite rates, a burst large enough to admit one request, and positive integer capacities. Decide and document whether a finite zero refill is a supported deliberate policy; the probe uses it as a valid control, so rejecting it indiscriminately is unnecessary. Fail startup with the offending variable name before opening the service. Table-driven configuration checks should include infinity, NaN, negatives, zero, sub-token bursts and valid finite boundaries. [Captured evidence](../../../../research/telemetry/audit-2026-11-22/round2/evidence/receiver-boundaries.json).

## TA22-R2-O01 — Optimization opportunity: repeated rollup work and full-day materialization

**Source and hypothesis.** [`records_for_day`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/storage.py#L188-L193) fetches every matching raw body into memory. [`run_rollup`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/rollup.py#L173-L190) then decodes and groups the input by release and retains prepared outputs before committing. [`unique_events`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/rollup.py#L54-L67) serializes each traversed event to obtain a digest. GPU, vehicle and [insight-cell aggregation](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/insights.py#L98-L102) independently traverse deduplication. The measured workload contains performance events, yet the vehicle path also traverses them before deciding there is no vehicle data.

**Measurement design.** The [retained probe](../../../../research/telemetry/audit-2026-11-22/round2/rollup_cost_probe.py) uses the real raw and aggregate stores and unchanged rollup implementation. Every synthetic batch contains 16 contract-valid performance events. Fixture creation and its pre-validation happen before timing; the production rollup's own body revalidation remains inside the timed operation. Each workload size runs in a fresh Python process, with three sequential uninstrumented rollups for timing, followed by a separate fourth run using `tracemalloc`, an encode-call wrapper and a SQL trace. The instrumented run's duration is not reported as performance evidence.

| Batches / events | Stored body MB | Median wall time, 3 runs | Peak traced Python MB | Event digest encodes | Raw-body SELECTs |
| --- | ---: | ---: | ---: | ---: | ---: |
| 40 / 640 | 0.240 | 0.213 s | 1.121 | 1,920 | 1 |
| 160 / 2,560 | 0.959 | 0.918 s | 4.304 | 7,680 | 1 |
| 480 / 7,680 | 2.878 | 2.688 s | 12.767 | 23,040 | 1 |

MB means 1,000,000 bytes. All measured rollups committed their day; GPU and insight-cell statuses were ready, and the vehicle status was no data. All three workloads performed **three event digest encodes per input event**. The largest workload's three ordinary times were 2.688, 2.648 and 2.781 seconds. Exact observations are retained in [rollup-cost.json](../../../../research/telemetry/audit-2026-11-22/round2/evidence/rollup-cost.json).

**What this establishes.** The repeated serialization is measurable implementation work, and peak traced allocations increase with this input series. The measurements use local Python 3.12.14 and SQLite on a shared Linux host. `tracemalloc` is not process RSS; it excludes important native/OS allocations and does not characterize the whole service's resident memory. The three sequential timings include whatever OS cache effects arose naturally. The fixtures are small, regular, one-day workloads, not a production distribution or capacity test. There is no justified extrapolation to the configured 2 GiB storage ceiling, no demonstrated production OOM, and no measured speedup because no optimization has been implemented.

**Candidate work and acceptance.** Evaluate validating/normalizing/deduplicating once per equivalent logical scope and feeding the necessary reducers without reserializing every event. Consider bounded cursor batches or streaming, provided snapshot consistency, per-session limits, disclosure thresholds, deterministic ordering and atomic day publication remain intact. Account for the database lock/read-snapshot consequences of a longer stream. Compare candidate outputs against baseline on duplicates, conflicts, multiple releases, mixed event families and late arrivals, then measure ordinary elapsed time and peak memory separately. Keep the first-pass numeric-admission repair ahead of performance tuning.

## Verification, provenance and limits

The [round-two reproduction package](../../../../research/telemetry/audit-2026-11-22/round2/README.md) contains four probes, a runner, compact JSON results and source/probe hashes. The runner requires an external output directory and uses synthetic temporary databases and fake network transports. The Godot probe copies exact source dependencies into an isolated minimal project and uses the repository's checked runner; existing host-admission checks remain in force.

- **Client:** one additional checked Godot counterexample reproduced errors-only starvation and verified clearing on admission closure, no sending while off, and no replay on re-enable. Engine logs contained no errors or warnings. The pinned engine was `4.8.beta2.official.cafc17a19`.
- **Receiver:** one Python probe reproduced the full-quota retry behavior and accepted-configuration/limiter cases.
- **Operations:** one Python probe reproduced private-overlap discard, malformed GA4 date handling and stale-receiver overview windows, and measured two archive query-count fixtures. Presentation helpers were stubbed for the overview case; this is not a rendered dashboard acceptance test.
- **Rollup:** three workload sizes, each with three ordinary timings and one separately instrumented run, committed successfully. Encode-call and SQL-read counts are retained alongside individual timings.
- **Source review:** ground input-class attribution and client frame-path work were traced without claiming rendered/native controller or target-hardware performance qualification.

The first pass's 370 distinct Python passes, two Windows-specific skips, five existing Godot suites and loopback bridge result were **not rerun for this documentation/probe-only extension**. They remain in the original [verification report](verification.md). No runtime implementation, production configuration, deployment, live player data or notification destination was changed. Future fixes require their own affected-consumer checks and the repository's applicable CI/release gates. A successful counterexample means the undesirable baseline behavior reproduced, not that the defect was repaired.

## Follow-through priorities

1. Retain the original High-priority order: repair numeric admission/aggregation consistency and actionable alert propagation with recovery-deadline evidence.
2. Close missing error-only flushes and ground input attribution; preserve consent closure and queue lifetimes. Add the confirmed counterexamples as expected-correct regression cases in a repair branch.
3. Make private import outcomes actionable and decouple fresh independent sources from stale receiver window selection. Harden configuration and GA4 response validation without converting unknown data into zero.
4. Measure a semantically equivalent rollup candidate and the actual client observer on supported target hardware before accepting performance claims. Measure representative archive size and latency before selecting a retention or compaction policy.
5. Repair full-quota idempotent acknowledgement and retain conflict/TTL controls. Expand later review to restart/clock changes, rollup/retention concurrency, backup-to-reader recovery and release/native-platform coverage where evidence is still incomplete.

This is a dated second review, not a claim of two days of continuous observation. Further passes should compare current source with this baseline, report genuinely new evidence and avoid counting the same underlying defect again.

# Receiver, aggregation and publication audit

This report is part of [TELEM-AUDIT-2026-11-22](README.md). All source links are frozen at `7940a4081e10994f34c858c4acac3d7a1a271464`. Findings concern that source snapshot. Local experiments used synthetic data and temporary SQLite databases; they establish no incident in the deployed service.

## TA22-R01 — An admitted integral JSON number aborts the entire daily rollup

**Severity: High / P1. Evidence: reproduced through the real ingress and rollup code. Status: newly identified in this audit.**

### Condition and consequence

An otherwise valid, approved-release batch represents an integer metric as an integral JSON number with a decimal part, such as `"interval_count": 1800.0`. In the pinned runtime, the receiver accepts and durably stores it. The later private insight-cell validator rejects the accumulated Python `float`. Since the rollup prepares every release and table before committing any of them, this single record prevents completion of the whole receipt-day transaction.

This is a disagreement between two boundaries of the same pipeline: an HTTP 202 does not imply that the admitted measurement is aggregatable. A changed serializer can produce this representation without changing the mathematical value. The consequence extends beyond the problematic record to otherwise healthy observations in the day. No deliberate production submission or observed production data loss is claimed.

### Source evidence

| Boundary | Evidence | Implication |
| --- | --- | --- |
| Decode and schema admission | [`contract.py:85–120`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/contract.py#L85-L120) | `json.loads` preserves `1800.0` as a float; the pinned JSON Schema validator accepts its integral mathematical value. There is no subsequent integer normalization. |
| Durable admission | [`ingress.py:78–103`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/ingress.py#L78-L103) | The accepted body enters raw storage and returns 202. |
| Accumulation | [`insights.py:119–126`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/insights.py#L119-L126) | Adding the accepted metric promotes the cell metric to a float. |
| Cell validation | [`insights.py:153–176`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/insights.py#L153-L176) | `type(metrics[n]) is not int` raises `ContractError("insight_cell")`. |
| Transaction boundary | [`rollup.py:166–190`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/rollup.py#L166-L190) | All release reports and cells must succeed before the single `agg.put_rollup`. |
| Recovery deadline | [`rollup.py:13–38`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/rollup.py#L13-L38) and [`storage.py:1–16`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/storage.py#L1-L16) | A day can be rolled only before day-start + 47 hours; raw data has a 48-hour TTL. An unresolved failure can become unrecoverable within the intended retention policy. |

### Executed counterexample

The audit exercised ingress and daily aggregation in process with 21 schema-valid synthetic batches. The [retained result](../../../../research/telemetry/audit-2026-11-22/evidence/python-probes.json) contains:

```text
healthy_batches: 20
healthy_http_statuses: [202]
poison_http_status: 202
stored_batches: 21
rollup_error: insight_cell
daily_statuses: {}
rollup_commits: {}
```

The script's historical output key `poison_http_status` names the synthetic altered record; it does not describe a real attack. The result demonstrates acceptance followed by a failed day transaction. The all-release blast radius follows from the single commit boundary; the fixture uses one release.

### Repair and acceptance criteria

Choose one consistent numeric representation contract. Prefer canonicalizing validated integer-valued metrics to bounded Python integers before subsequent computation, or explicitly reject unsupported representations during ingress. Apply the same rule when reading already stored batches; fixing only new ingestion leaves previously admitted records capable of blocking the next rollup.

Add a property test that takes admitted bodies through the complete rollup, covering ordinary integers, integral decimal and exponent forms, histogram elements, activity counts and error counts. Preserve the existing bounds and rejection of invalid/nonfinite numbers. Include a day with multiple healthy releases and the boundary case in one release. The day must either aggregate correctly or be stopped through a deliberate, observable quarantine policy with an explicit completeness status. Silently dropping data and presenting the day as complete would create a different defect.

Rehearse the recovery before the 47-hour eligibility boundary and expose the failure to the independent monitor. This last step depends on TA22-O01 in [operations](operations.md).

## TA22-R02 — Concurrent publishers can create two issues for one frozen report

**Severity: Medium / P2. Evidence: reproduced with two database connections and an in-process fake GitHub client. Status: newly identified in this audit.**

### Condition and consequence

Two `publish --execute` invocations act concurrently on the same durable intent whose `create_attempts` is zero. Such an intent can remain after an incomplete discovery or an interrupted run before creation. Both publishers read the old state, both finish discovery without an existing issue, and both create an issue. Each reports success. The final database row records only the last issue number.

The experiment does not require different digests, bot identities or repositories. It defeats the documented “create at most once” property for overlapping executions of the same approved report. A later discovery can detect the duplicate, but that detection does not prevent the duplicate external side effect.

### Source evidence

[`publisher.py:165–167`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/publisher.py#L165-L167) states the intended property. The intent is read at [`188–200`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/publisher.py#L188-L200), and its previously read `create_attempts` is consulted after remote discovery at [`202–220`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/publisher.py#L202-L220). The durable update to `creating`/1 has no atomic predicate on the expected state, digest, author or attempt count: [`storage.py:396–416`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/storage.py#L396-L416).

Individual SQLite transactions serialize the writes, but they do not make a stale read followed by an unconditional update into an exclusive claim.

### Executed counterexample

[`publisher_race.py`](../../../../research/telemetry/audit-2026-11-22/evidence/python-probes.json) creates one intent in a disposable aggregate database, opens two independent `AggStore` instances, and uses a barrier in fake discovery so both publishers have read the intent before either proceeds. Fake issue creation is protected by a lock to count side effects accurately.

```text
outcomes: [('published', 2), ('published', 1)]
created: 2
final intent: 2
```

The winning order/number can vary. The asserted defect is two successful create operations for one intent. No GitHub API was called and no issue was created during the audit.

### Repair and acceptance criteria

Claim the create attempt atomically before issuing the remote request. A compare-and-set update should match the expected immutable report identity and eligible attempt state; only the caller that changes one row may create. Losing callers should reconcile or return a bounded pending/unknown result. Preserve the conservative rule that an uncertain remote result must not trigger a blind retry.

Use a concurrency regression with separate database connections, and preferably separate processes, against both an existing pending intent and an initial simultaneous invocation. Assert one remote create at most, a consistent final ledger, and correct handling of incomplete pagination, lost responses, delayed issue visibility, explicit refusal, and sticky manual-review states. A process-local mutex alone cannot enforce this across independent CLI processes.

## Controls that held in the audited source and focused tests

The review covered every module under `services/telemetry/openrc_telemetry`, its tests, the reference implementation and generated contracts. Positive evidence matters because the repairs should preserve these properties:

- Ingestion bounds body size and structure, rejects duplicate keys and unsupported values, gates releases, and maps storage failure to a non-success response. Database primary keys and transactions enforce batch/event retry conflicts. See [`contract.py`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/contract.py), [`ingress.py`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/ingress.py), and [`storage.py`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/storage.py).
- Raw data and ID-free aggregates use separate stores. Uvicorn access logging is disabled in the managed serve path. These source controls do not verify upstream proxy logs or deployed volumes. See [`cli.py:99–119`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/cli.py#L99-L119).
- The previous overlapping small-cell disclosure issue is addressed by the conservative maximum-per-day lower bound in [`insights.py:197–231`](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/services/telemetry/openrc_telemetry/insights.py#L197-L231). It is not reported here as an unfixed finding.
- Digest approval, bot identity checks, closed-week gating, and conservative unknown-outcome reconciliation remain useful publisher controls; TA22-R02 identifies the missing interprocess claim around them.

The baseline receiver/reference suites and actual Godot-to-receiver loopback test passed; [verification](verification.md) records exact counts, retained outputs and limits. Passing tests did not exercise the two new counterexamples above.

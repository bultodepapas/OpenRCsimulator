# Production telemetry audit, 2026-11-21

The first read-only production observation was at **19:58 Bogotá time** (2026-11-22 00:58 UTC). It used the deployed receiver at `50553346f0e0` and the private dashboard at `9e220092a6ab`. Counts and field names were aggregated in place. The audit output contains no session or batch identifiers, addresses, or individual payloads.

| Check | Observed result |
| --- | --- |
| Public receiver | HTTPS `/healthz` returned 200. The receiver, daily rollup timer and dashboard build timer were active. The installed contract accepted `check-release v0.3.2`. |
| Stored traffic | 90 accepted batches in the observed UTC day. All 90 were v0.3.0, schema 1, with notice `2026-11-18`. There were no rejection or rate-limit counters for that day at inspection time. |
| Event mix | 155 performance windows, 12 activity summaries and 5 `session_started` events. These are event and batch counts. The client can rotate its temporary session token within one process. |
| Context fields | Fourteen finite categories covering OS, architecture, CPU and GPU families, thread and RAM bands, graphics renderer and driver, resolution band and basis, VSync, FPS cap, graphics profile and input class. |
| Performance and activity fields | Frame-interval totals and histogram, window and draw status, excluded gaps, activity context and stock vehicle category. Activity summaries contain observed active and simulated time, outcome, completeness and supported takeoff, landing and model-aircraft crash counters. The observed schema has no physics evaluator. |
| Retention observation | Oldest logical raw batch age was 10.3 h and WAL size was zero. The raw volume had `backup=0`, and the hypervisor listed no retained CT snapshot. Those observations cover the inspected store and its current configuration. The full all-copy deletion and logging drill remains open. |
| Dashboard health | HTTPS returned 200. The private health report had no receiver issues and reported a partial GA4 source separately. The first activity day was still inside the wait for the rollup eligibility boundary. |
| v0.3.2 packages | All three ZIP SHA-256 digests matched the release manifest for clean source `6b2228c7633a34e38cb05d92e3ca50893810e02b`. Windows, Linux and macOS each contained the same 264-byte telemetry configuration with the expected HTTPS origin, operator and contact. The observation window contained no v0.3.2 batch. [Published release](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.3.2) |

## Findings and corrections

- **Disclosure floor.** Ten session-days that contribute to two vehicle cells could be counted as 20 in a combined row. Private insights v2 counts a conservative union by summing each day's largest constituent count. Reports mark uncertain combined counts with `≥`. The dashboard excludes legacy combined rows and derives its headline lower bound from the largest disclosed row. [Receiver](../../../../services/telemetry/openrc_telemetry/insights.py) · [dashboard](../../../../tools/telemetry/dashboard.py)
- **Observation coverage.** The dashboard distinguishes received batches, missing coverage, and a completed rollup whose cohorts are all below the floor. It marks known receiver-wide admission or storage interruptions and excludes those weeks from release-age comparison. Existing per-day outcome counters have receiver-wide scope. [Dashboard](../../../../tools/telemetry/dashboard.py)
- **Retention monitoring.** An automatic purge could delete a row while a reader blocked WAL truncation. The purge loop now records the busy checkpoint and retries after 15 seconds. The regression holds a real SQLite read transaction across the first purge and verifies truncation after the reader releases. [Purge loop](../../../../services/telemetry/openrc_telemetry/cli.py) · [regression](../../../../services/telemetry/tests/test_storage.py)

## Deployment and verification

The cutover completed at **20:15 Bogotá time**. The dashboard moved first so it could read legacy snapshots safely before the receiver began emitting insights v2. The dashboard candidate retained the chart update already deployed at `d51e8761d745`. Active release directories are `audit-5a0e1a2cc1fe` (receiver) and `audit-79a0be3bf92d` (dashboard), named for their source archive digests. The prior releases remain available for rollback. The service data and automatic schedules were preserved.

- In the unchanged production receipt day, the new receiver wrote a complete rollup for v0.3.0 with 24 private aggregate cells. The default floor of 20 disclosed zero weekly tables. The dashboard showed that the cohort was below the floor. Of the 155 received performance windows, 118 met the steady, complete and observed-draw eligibility conditions. The post-deployment observation still held the original 90 batches, all from v0.3.0.
- The public HTTPS health endpoint returned 200 and the receiver admitted v0.3.2 in `check-release`. The refreshed private dashboard showed the corrected count semantics, no receiver issues, and GA4 partial coverage. Its private snapshot path returned 404. Receiver, rollup, snapshot and dashboard timers were active after the cutover.
- The isolated release candidates passed 141 receiver tests with the Godot end-to-end check skipped and 99 dashboard, archive and backup tests. The staged receiver passed 42 additional checks on the deployed Debian runtime. The staged dashboard rendered the existing private snapshot before activation. The generated contracts and examples matched source.

## Open evidence

Observe schema 2 from an opted-in v0.3.1 or v0.3.2 client and verify the bounded evaluator field when an activity summary arrives. The read-only production audit injected no synthetic batches. Complete the all-copy retention drill, delivered-alert rehearsal and Windows/Linux/macOS consent qualification under the [telemetry plan](../../../plans/telemetry.md#completion-plan-telem-1626).

Source inspection also found two client-specific cases to qualify separately. Failure to remove or replace a saved grant can leave the prior choice on disk while the current process stops sending. Session rotation currently occurs when an event is appended, so a window or activity that crosses a token boundary needs an explicit timing test. Both require focused client tests and release delivery evidence. [Consent store](../../../../app/telemetry/telemetry_consent_store.gd) · [client service](../../../../app/telemetry/telemetry_service.gd)

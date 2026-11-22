# Telemetry audit: second-pass reproduction package

Report: [deeper correctness and optimization review](../../../../docs/research/telemetry/TELEM-AUDIT-2026-11-22/second-pass.md). Runtime baseline: `7940a4081e10994f34c858c4acac3d7a1a271464`.

These probes use synthetic inputs and disposable local storage. **Exit zero means the expected baseline behavior reproduced**, including undesirable behavior; it does not mean a repair passed. Nothing in this package contacts a deployed receiver, GitHub, Google or an SSH host. The receiver uses in-process HTTP, the operations probe substitutes transport fixtures, and the client uses an in-memory sender. No player profile or real credential is loaded.

## Run the focused checks

Use the Python 3.12 environment and baseline requirements described in the [parent reproduction package](../README.md#python-probes). Keep the checkout stable. The audit used Python 3.12.14 and the pinned `4.8.beta2.official.cafc17a19` engine. Use the [existing Godot tooling](../../../../docs/tools/shared.md#one-godot-script) to obtain and verify that executable; configured pool/host-admission rules continue to apply.

From the repository root:

```bash
python research/telemetry/audit-2026-11-22/round2/run.py \
  --out /tmp/openrc-telemetry-round2 \
  --godot "$(app/get-godot.sh)"
```

Choose a fresh directory outside the checkout. Omit `--godot` to run only the two Python probes. The runner explicitly puts child temporary files outside the repository, preserving the dashboard's external-path guards. It retains original stdout/stderr, parsed results and a result summary. For Godot it copies the exact literal dependency closure into an isolated minimal project, retains source hashes, performs a checked import and then executes the checked probe. It neither edits the app nor bypasses admission.

| Probe | Entries covered | Evidence boundary |
| --- | --- | --- |
| [errors_only_idle_probe.gd](errors_only_idle_probe.gd) | F01 | Actual service with fake clock/context/sender; includes off-state clearing, late callback and re-enable controls |
| [receiver_boundaries_probe.py](receiver_boundaries_probe.py) | F04, G01 | Real ingress and temporary SQLite; actual configuration parser and limiter |
| [operations_probe.py](operations_probe.py) | F03, F05, G02, O03 | Actual importer/GA4 collector/archive; overview date and metric logic with presentation helpers stubbed |
| [rollup_cost_probe.py](rollup_cost_probe.py) | O01 | Actual rollup and stores; synthetic contract-valid performance events |

F02 and O02 are source-level findings/hypotheses in the [client report](../../../../docs/research/telemetry/TELEM-AUDIT-2026-11-22/second-pass-client.md). No additional rendered controller or frame-time acceptance test is claimed.

## Optional rollup measurement

Append `--measure-rollup` to the runner in a fresh output directory. It runs workloads of 40, 160 and 480 batches, each with 16 performance events. Each workload gets its own Python process. Setup occurs outside timing; three ordinary timings are followed by one separate traced run for Python allocations, digest-encoding count and raw-body query count. Expect timing variation on a shared host. The runner enforces a bounded timeout and retains stdout/stderr.

This is not a production load test, process-RSS measurement, capacity forecast, target-hardware benchmark or optimized-candidate comparison. A future change must preserve aggregation/disclosure semantics before timing comparisons are useful. The report distinguishes ordinary timing from instrumented measurements.

## Retained evidence

- [client-probe.json](evidence/client-probe.json): checked client result and original diagnostic output, including consent/admission controls.
- [receiver-boundaries.json](evidence/receiver-boundaries.json): quota retry and invalid-configuration signatures.
- [operations-result.json](evidence/operations-result.json): overlap discard, malformed date, stale-source window and two archive fixtures.
- [rollup-cost.json](evidence/rollup-cost.json): individual uninstrumented times and separate measurement counts/peaks.
- [source-sha256.json](evidence/source-sha256.json): exact baseline files used by the new reports/probes, plus new probe and runner hashes.
- [verification.json](evidence/verification.json): execution scope, environment, source identity and known limitations.

JSON evidence is a compact projection of the local captures, not a replacement for the stated methodological limits. Synthetic fixture dates can lie after the audit date; they are fixed test clocks, not observations from the future. Source permalinks and original first-pass results remain in the [audit report set](../../../../docs/research/telemetry/TELEM-AUDIT-2026-11-22/README.md).

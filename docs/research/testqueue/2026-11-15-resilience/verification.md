# Verification and evidence limits

Audit date: **15 November 2026**. Source baseline:
`c048a4e6834646400070a488b293344dc1e1fd80`. The [audit](README.md) owns
findings; the [implementation plan](../../../plans/mcp-queue-resilience.md) owns
proposed repairs and their acceptance gates. This record does not close those gates.

Later implementation results belong to the separate
[handoff](implementation.md) and [evidence record](implementation-evidence.json).
The counts and defect observations below are retained unchanged for this baseline.

## Local focused checks

Existing fixture groups ran in the Linux audit environment, with private temporary
roots. **119 distinct test cases: 116 passed and 3 Windows-only cases skipped.**
The independent reviews ran the core/worker and pool groups; the lead ran the MCP
group and reviewed the recorded results. Groups below do not overlap.

| Existing fixture group | Result | What it supports |
| --- | --- | --- |
| `test_store`, `test_scheduling`, `test_wait`, `test_processes` | 40 cases: 37 passed, 3 skipped | Local state, admission, observation and supported fake-process containment. Windows-only skips remain unqualified here. |
| Four selected `test_worker.WorkerFixture` cases below | 4 passed | Uncertain cleanup, canceled preparation, ownership/cancellation, surviving-child cleanup. |
| `test_pool_policy`, `test_pool`, `test_pool_batch`, `test_pool_checked`, `test_pool_concurrency`, `test_pool_mcp`, `test_remote_agent` | 55 passed | Existing placement, durable pool/transport, batch and collection contracts; stubs or task-owned fake processes. |
| `tools/debug/test_mcp_server.py` | 20 passed | Existing direct MCP calls, argument routing and ownership behavior. These tests do not establish concurrent message intake. |

Reproduction commands run from the repository root. Use a fresh private directory
for `TMPDIR`, `TEMP` and `TMP`; `PYTHONDONTWRITEBYTECODE=1` is recommended to avoid
bytecode writes. The original core/worker invocations used the private directory
but omitted that bytecode flag; their test counts above are unchanged:

```bash
PYTHONPATH=tools/testqueue python -m unittest \
  tools.testqueue.test_store tools.testqueue.test_scheduling \
  tools.testqueue.test_wait tools.testqueue.test_processes

PYTHONPATH=tools/testqueue python -m unittest \
  tools.testqueue.test_worker.WorkerFixture.test_uncertain_cleanup_keeps_claim_and_never_passes \
  tools.testqueue.test_worker.WorkerFixture.test_canceled_preparation_acknowledges_nonexecution \
  tools.testqueue.test_worker.WorkerFixture.test_queued_and_running_cancellation_and_ownership \
  tools.testqueue.test_worker.WorkerFixture.test_failed_adapter_cleans_its_surviving_child

python -m unittest \
  tools.testqueue.test_pool_policy tools.testqueue.test_pool \
  tools.testqueue.test_pool_batch tools.testqueue.test_pool_checked \
  tools.testqueue.test_pool_concurrency tools.testqueue.test_pool_mcp \
  tools.testqueue.test_remote_agent

python -m unittest discover -s tools/debug -p 'test_mcp_server.py' -v
```

An initial core invocation without `PYTHONPATH=tools/testqueue` reported one
`test_processes` import error among 29 cases. The corrected 40-case invocation
above passed with three skips. This was a fixture import/setup issue; it is not
counted as an additional test group or concealed as a production defect.

## Reproduced baseline observations

The lead reran all six committed probe programs with private temporary roots,
`PYTHONPATH` containing the repository, and a 40-second limit per program.
All six exited zero. **Zero means the baseline defect or limitation was
reproduced, not repaired.** These are research probes, not desired-behavior
regression tests to add unchanged to required CI.

The [raw reproduction record](reproduction-results.json) preserves stdout, stderr,
exit status, baseline and environment: Python 3.12.14 on Linux x86_64; the first
five were recorded on 15 November 2026 at 21:06 UTC and the additional recovery
probe at 21:14 UTC. The
[probe guide](../../../../research/testqueue/resilience/README.md) provides a bounded
reproduction command.

| Program | Distinct observations | Findings |
| --- | --- | --- |
| `reproduce_prelaunch_failure.py` | Log-open failure: zero process creations, `UNKNOWN`, four claims, same-boot reconciliation refused, next job queued. | F01 |
| `reproduce_scheduler_failure.py` | Scheduler and diagnostic-write errors stop the scheduler; clearing faults leaves `READY` and queued work. | F02 |
| `reproduce_preparation_timeout.py` | One-second execution budget does not bound blocked preparation; cancellation retains claims until preparation returns, then confirms no start. | F05 |
| `reproduce_mcp_dispatch.py` | A held tool prevents later control messages being read; a zero-wait call still uses the independent 30-second status RPC budget. | F04/F05 |
| `reproduce_pool_failures.py` | Invalid pre-receipt input; transient pre-receipt dispatch-lock failure; two independent roots on one host; observer budget overrun; 129-marker validation disagreement. | F03/F05/F07 |
| `reproduce_local_recovery_misclassification.py` | Lost acceptance reply followed by an unavailable snapshot causes a false pool `NOT_DISPATCHED`/confirmed-cleanup result while the private authority retains a live job and four claims; later pool status makes no RPC. | F14 |

There are **eleven distinct observations across six programs**, separate from the
119 existing tests. Transport and selected process boundaries are mocked. The
two-root scenario proves separate admission domains in the code, not a duplicated
live enrollment. The validation mismatch is reproduced without SSH; indefinite
remote recovery is a source-derived consequence, not a recorded live network test.

F14 uses a real owned fake Python process, an injected reply loss, direct fixture
RPC and a mocked Windows platform label on Linux. The original process remains
alive during the false result; the probe then cancels its own handle and confirms
cleanup. An initial probe-authoring assertion compared an extra submission field
with the smaller recovery response; that assertion was corrected before the
retained lead run. No native Windows containment is inferred from this probe.

## GitHub CI observations

The [compact CI record](ci-observations.json) separates source identity, prior
success, still-running work, artifact metadata and access limits.

- At **21:06:45 UTC**, the provider returned 23 jobs for
  [run 43758986877](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43758986877)
  at the audited `c048a4e` baseline: 12 succeeded, 2 were skipped and 9 remained in
  progress. The provider's `total_count` was also 23. This observation establishes
  neither a final pass nor a final failure.
- The earlier [Windows queue run 43736986157](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43736986157)
  and [main CI run 43736986190](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43736986190)
  completed successfully at `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`.
  [The comparison](https://github.com/bultodepapas/OpenRCsimulator/compare/e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc...c048a4e6834646400070a488b293344dc1e1fd80)
  reports 11 commits and 79 changed files, with no changes to `tools/testqueue/`,
  `tools/debug/`, `tools/godot/`, `tools/godtest/`, `tools/release/`,
  `research/performance/` or the Windows queue workflow. This is supporting native
  fixture evidence for unchanged queue code, not a completed run of the new head.
- At the baseline, the queue tree is `3317046fabc259486bda982dbe9bece67c229fbf`;
  the debug tree is `ecc031df0ea273be4ad66e4058e0000a2e94b911`.
  The audit branch does not modify either runtime tree beyond the queue README.
- The earlier main run's `captures-app` and `release-builds` artifacts total
  **7,168,836,247 bytes**, approximately **6.68 GiB**. This is one run's provider
  inventory, not a bill, transfer measurement or general average. Their recorded
  expiry is 13 February 2027. No artifact was deleted.
- Reading legacy `main` branch protection returned **HTTP 403**, `Resource not
  accessible by integration`. The rulesets listing was empty. Actual required-check
  enforcement remains **unverified**: an empty rulesets response cannot rule out
  legacy branch protection.

CI success is not evidence that the failure injections cannot happen; those cases
expose missing recovery coverage. Native process fixtures also do not qualify
real simulator performance, desktop coexistence, graphics or physical hardware.

## Document and scope validation

The publication check passed for 19 changed files: 11 Markdown files, two JSON
records and six Python probes. The repository's `tools/ci/check_docs.py` parser
validated all **34 new local Markdown links** against the staged Git tree; JSON
parsing, Python syntax parsing and `git diff --check` also passed. This is
document/evidence validation; no runtime behavior changes are asserted.

## Remaining evidence needed for implementation

No current machine telemetry, failing production receipt, live queue database,
real SSH transport campaign, target-GPU capture or simulator throughput benchmark
was collected. Neither Mac's current available storage was measured. Physical
independence of the Linux route and CI runners remains unverified. No active
worker, simulator, authority, CI run or machine was stopped or reconfigured.

The plan requires native per-platform process/restart/cancel tests, a redacted
incident bundle and measured resource/latency campaigns before enabling its new
behavior. Existing fleet records are dated evidence, not substitutes for those gates.

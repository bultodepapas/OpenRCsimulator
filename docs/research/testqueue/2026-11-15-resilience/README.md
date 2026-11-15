# MCP queue resilience and resource-pool audit

Date: **15 November 2026**. Owner: shared-host test admission (**TQ**), with CI
owners retaining workflow and release policy. Baseline:
[`c048a4e6834646400070a488b293344dc1e1fd80`](https://github.com/bultodepapas/OpenRCsimulator/commit/c048a4e6834646400070a488b293344dc1e1fd80).

## Assessment

The queue has a substantial safety foundation: durable request identities,
ownership checks, atomic local claims, isolated projects, verified process-tree
cleanup, conservative uncertainty handling and verified result collection. Keep
those controls. The immediate problem is **availability and recovery around that
foundation**, followed by resource accounting and throughput.

Three isolated reproductions show concrete ways work can stop progressing:

1. A failure opening a log **before any process starts** can quarantine the entire
   local host as `UNKNOWN`; same-boot reconciliation refuses it.
2. A scheduler error followed by failure to record that error can terminate the
   scheduling thread while the host continues to report `READY`.
3. A transient failure before a pool receipt exists can strand a batch row in
   `BLOCKED`/`UNKNOWN`; resuming observation never resubmits that row even after
   the original fault clears.

The MCP server also processes messages serially, so a long tool prevents that
client from reading a later ping, cancellation notification or stop command.
Execution timeouts already exist, but preparation, transport, observation and
collection do not share a reliable end-to-end deadline contract.

A further recovery defect can falsely report `NOT_DISPATCHED` and confirmed
cleanup after a lost local acceptance reply if the original inputs later become
invalid. The owning authority can still hold a running job. Treat this as a
priority repair alongside the availability failures; see F14 and the runbook.

These are confirmed failure mechanisms in the audited source, **not a forensic
identification of Sergio's particular live incident**. No failing live receipt,
authority database, supervisor log or current fleet telemetry was available in
this session. No personal-machine worker was restarted, canceled or reconfigured.

The [implementation plan](../../../plans/mcp-queue-resilience.md) defines repairs,
owners, sequencing, acceptance and rollback. The [recovery runbook](runbook.md)
distinguishes safe current operations from proposed APIs. The
[verification record](verification.md) retains reproduction and CI evidence.
This branch delivers research, reproducible probes and a plan; it does not deploy
the proposed queue changes.

## Scope and method

Inspected the local authority/store, process containment, scheduling policy,
snapshot pipeline, CLI integration, MCP protocol loop, pool planner and batch
supervisor, SSH agent, result collection, workflow triggers and required-result
policy. Independent bounded reviews covered local safety, distributed scheduling
and CI; the lead inspected the accepted source arguments and integrated the plan.
Fixtures use private temporary roots and stubbed transport or fake subprocesses.
They do not constitute native simulator, GPU, throughput or physical validation.

Line references below identify the pinned baseline. Linked source files remain
the authoritative implementation; proposals are explicitly future work. The
operating contract is [tools/testqueue/README.md](../../../../tools/testqueue/README.md).

## Existing behavior worth preserving

| Control | Evidence and consequence |
| --- | --- |
| Stable request identity and durable receipts | `integration.py:15–51`, `store.py:62–107`, `pool.py:158–171,259–272`: identity-based authority recovery can find the original request after a lost reply. F14 identifies an unsafe pool recovery classification around this capability. |
| Ownership independent of bridge port | `worker.py:207–222,257–272`, `integration.py:120–159`: session control requires an owner capability; another client cannot silently adopt a live session. |
| Atomic local admission | `store.py:132–168`: claims and dispatch are allocated transactionally; an unknown attempt blocks new execution. |
| Exclusive-work fairness | `worker.py:345–385`: an eligible exclusive waiter blocks younger work from continually refilling slots. GUI-ineligible jobs can be bypassed by usable headless work. |
| Process lifetime, not launcher return | `processes.py:9–17,281–289`, `worker.py:505–557`: descendants inside the supported containment boundary remain owned through cleanup, including after root exit. External Windows broker/service launches and deliberately escaped POSIX descendants are outside that guarantee. |
| Safe input and evidence handling | `snapshots.py`, `pool.py:38–52,341–389`, `remote_agent.py:309–350,529–563,605–610`: frozen bytes, constrained extraction, pinned engine identities, complete checked verdicts and artifact hashes are verified. |
| No blind failover after dispatch ambiguity | `pool.py:278–339`, `pool_batch.py:154–175`: recovery keeps the same request and destination. Failed tests are not silently rerun into a pass. |
| Existing cross-host execution | The orchestrator plan records bounded checked-job acceptance on Windows, Linux, ANGEL and ANGELA_AIR. That dated record is useful, but does not establish today's host health or measured speedup. |

## Findings and priority

**P1** means repair before expanding shared-host concurrency or CI delegation.
**P2** means improve after the safety and recovery gates. A documented limitation
is distinguished from a reproduced defect; severity describes its operational
importance, not an assertion that it caused the reported live incident.

| ID | Priority | Finding | Evidence type |
| --- | --- | --- | --- |
| F01 | P1 | Pre-spawn I/O failure becomes host-wide `UNKNOWN` | Isolated reproduction |
| F02 | P1 | Scheduler can die while readiness remains `READY` | Isolated reproduction |
| F03 | P1 | Pre-receipt batch failure has no recovery transition | Isolated transient and invalid-input reproductions |
| F04 | P1 | Long MCP tools block the control channel | Stubbed message-stream reproduction |
| F05 | P1 | Deadline scopes differ; preparation and collection can outlive observation | Preparation and observer reproductions; source inspection |
| F06 | P1 | Lost ownership has no same-boot local reconciliation; remote cancel is absent | Deliberate safety limit and missing capability |
| F07 | P1 | Physical-host exclusivity depends on configuration/root conventions | Two-root acceptance reproduction; conditional deployment risk |
| F08 | P2 | The automatic pool cannot use existing reviewed functional concurrency | Current source policy, not a safety defect |
| F09 | P1 | Preparation and capacity estimates lack atomic per-volume reservations | Source-level admission gap |
| F10 | P2 | Slow probes/transfers delay unrelated dispatch and cache estimates miss actual reuse | Source-level scheduling inefficiency |
| F11 | P1 | Native Windows fixture trigger/gate coverage is incomplete | Concrete dependency/trigger mismatch |
| F12 | P2 | CI optimization remains in shadow; large artifacts use long retention | Current policy and measured artifact inventory |
| F13 | P2 | Remote runtime/protocol identity is not fully bound to admission | Source-level provenance and compatibility gap |
| F14 | P1 | Local pool recovery can falsely confirm nonexecution after acceptance | Lost-reply/input-validation failure path; isolated fixture evidence |

### F01 — Distinguish proved nonlaunch from uncertain launch

`Worker.execute()` sets `start_attempted = True` before `OwnedProcess.start()`
(`worker.py:495–501`). Opening `worker.log` is the first operation in `start()`
(`processes.py:318–323`), before process creation. If that open fails, the exception
path sees a start attempt without a process identity and sets `UNKNOWN`
(`worker.py:558–574`). `Store.allocate()` quarantines the host globally
(`store.py:138–146`). Reconciliation delegates to `confirm_stopped()`, which only
accepts a changed boot identity on the same host (`processes.py:248–278`).

The fixture injected `PermissionError` at that log open. **Zero process-creation
calls** occurred, yet four claims remained and another headless job stayed queued.
Same-boot reconciliation refused the first attempt. The safe intent is correct;
the classification unnecessarily applies the strongest quarantine to a provable
nonlaunch.

Repair the start contract so it explicitly reports `NOT_CREATED`,
`CREATED_OWNED`, or `CREATION_UNCERTAIN`, and journals the launch boundary.
Only proof of noncreation or verified teardown can finalize/release. A missing
PID, an exception class or elapsed time alone is insufficient. Test failures
before creation, during native containment assignment and after creation separately.

### F02 — Readiness can outlive the scheduler

`Worker.schedule()` catches a scheduling exception, then writes a
`SCHEDULER_ERROR` event without guarding failure of that diagnostic write
(`worker.py:337–343`). A full, read-only or failing database can fail both
operations. The second exception exits the sole scheduling thread. `hosts`
continues to derive condition only from `self.draining` (`worker.py:196–202`).

The fixture injected both errors, then removed them. The scheduler was dead,
`stopping` was false, the host reported `READY`, and the job remained queued.
Existing attempt threads need not have stopped, so restarting the entire worker
to repair this condition could interrupt valid work.

Add a guarded diagnostic fallback, loop heartbeat, dispatcher-thread identity,
last successful dispatch observation and a degraded readiness state. Supervise
and recover the scheduler loop **within the existing authority**, preserving its
attempt objects, handles and claims. Failure to persist state must pause new
admission; it must never fabricate completion or drop existing reservations.

### F03 — A batch can become permanently blocked before a receipt exists

`run_batch()` converts every submit exception into `BLOCKED` with status `UNKNOWN`
(`pool_batch.py:141–157`). Later iterations submit only `WAITING` rows and observe
blocked rows through `pool.status()`, which requires the missing receipt
(`pool.py:316–324`). The MCP supervisor calls `pool.recover()` only when that
receipt exists (`pool_mcp.py:157–164`).

Two distinct cases reproduced this:

- A transient dispatch-lock timeout before receipt creation. After the fault
  cleared, batch resume performed zero resubmissions and remained incomplete;
  a direct same-ID submission could reach a stubbed healthy authority.
- A readable but invalid frozen manifest. The permanent validation rejection
  became uncertainty, and resume replaced the useful error with a missing-file
  error instead of producing a definitive invalid-input result.

**Normal no-capacity `WAITING` is already reconsidered**; this finding is about
exceptions before the dispatch boundary. Introduce typed outcomes for retryable
pre-dispatch failure, permanent input rejection and possibly dispatched work.
Persist the boundary and attempt history. Retry a proved nondispatched transient
failure with bounded backoff; finalize a permanent rejection with evidence; retain
same-host reconciliation whenever dispatch may have occurred. Do not infer safe
resubmission from receipt absence alone if state might have been lost or corrupted.

A related protocol mismatch also needs a definitive rejection path. Local/MCP
validation accepts 129 completion markers (`presets.py:59–61`,
`pool_mcp.py:42–47`), while remote validation refuses more than 128 and also
rejects carriage returns/NULs (`remote_agent.py:147–150`). The validation mismatch
was reproduced without SSH. `Pool.remote()` flattens nonzero remote exits into
`RuntimeError` (`pool.py:77–87`), so a known remote `INVALID` refusal can remain
`SUBMISSION_UNCONFIRMED` and be replayed indefinitely (`pool.py:259–303`). That
repeated transport path is a source-inspection conclusion. Share versioned
validation and preserve authenticated request-bound refusal codes; never treat
every SSH error as proof of nonacceptance.

### F04 — The MCP input loop cannot service controls during a long tool

`serve()` reads one line, runs `handle()` synchronously and only then reads the
next (`mcp_server.py:357–374`). `handle()` discards notifications, including
`notifications/cancelled` (`:319–321`). Bridge calls default to a 600-second timeout
(`:158–164`); this is not a proven end-to-end ceiling, and some tools make several
calls. Managed `sim_launch` requests zero readiness wait, but still performs a
status RPC before checking that wait deadline (`integration.py:98–103`,
`common.py:151–158`). Snapshot capture is also synchronous and precedes its durable
submission receipt (`integration.py:15–44`).

The no-network reproduction held a stubbed tool and queued cancellation, ping
and stop messages. Only the first message was read until the stub was released;
the original call then completed and the queued stop ran afterward. Existing
MCP tests exercise correctness of individual calls but do not prevent this stall.

The checked-batch `sim_test_launch` already has a detached-supervisor design;
reuse that pattern for expensive preparation. Separate message ingestion and
cached status from long execution, and use immutable session/request context.
Simply adding a thread pool is unsafe: `_captured()` redirects process-global
stdout/stderr and session routing mutates `os.environ` (`mcp_server.py:178–182,
215–238`; `integration.py:68–70`). Session mutations still need ordered ownership.

MCP request cancellation and cancellation of an accepted durable job are different
operations. Preserve the existing policy that leaving an observer does not kill
owned work. Cancellation support in the negotiated 2025-11-25 protocol is optional;
this finding concerns the application's requested responsiveness, not an invented
protocol compliance requirement. See primary references below.

### F05 — Existing timeouts do not bound the complete lifecycle

| Current boundary | What is implemented | Remaining gap |
| --- | --- | --- |
| Local execution | Monotonic deadline after `process.start()`; interactive default 1,800 s; validated maximum 21,600 s (`presets.py:34–36`, `worker.py:502–537`). | Verification/copy precede this deadline; artifact hashing follows it (`worker.py:428–454,553–557`). |
| Local waiter | `common.wait()` checks its deadline after a status RPC (`common.py:151–159`). | Even `timeout=0` uses the RPC's independent default 30 s socket timeout. It is not an end-to-end response limit. |
| MCP batch observer | One-hour loop; each `run_batch` receives at most 30 s (`pool_mcp.py:154–172`). | Synchronous operations inside the loop may exceed that budget. Stopping observation does not cancel the job. |
| SSH/transfer | RPC subprocess timeout 45 s; upload up to 1,800 s (`pool.py:77–81,237–254`). | These limits are not capped by the remaining batch/observer budget. |
| Remote execution | One deadline covers import plus check after preparation (`remote_agent.py:586–613`). | Transfer, archive hashing/copy/extraction and result inventory have different or absent bounds; the same input timeout does not mean identical local/remote lifecycle coverage. |
| Queued or uncertain work | Queued requests have no automatic expiry; unknown claims are retained. | No explicit pending-age policy, next recovery deadline or guaranteed escalation outcome. |

The preparation fixture blocked copy with a one-second execution timeout, then
requested cancellation. State remained `DISPATCHING` with retained claims until
copy resumed; cancellation then finalized safely before any engine start. This
is evidence that cancellation is cooperative and the execution deadline excludes
preparation, not evidence that the safety behavior should be weakened.

Use separate **request, queue, preparation, execution, cleanup and collection**
policies. Observation timeouts return a durable ticket. Progress thresholds
request diagnosis; they do not authorize killing a healthy run. Only an explicitly
accepted hard stage/execution limit or an owned cancellation may initiate teardown.
The plan specifies per-phase ownership and remaining-budget propagation.

### F06 — Recovery is safe but operationally narrow

The local store changes active attempts to `UNKNOWN` on authority startup
(`store.py:54–57`). `confirm_stopped()` accepts only same-host reboot evidence;
its docstring explicitly refuses same-boot absence/zero-count heuristics. This is
deliberate: reconstructing ownership from a reused PID or a missing Job name is
unsafe. The nearby worker reconciliation comment must not be read as a promise
that querying a Job Object currently makes same-boot release possible.

The Windows `OwnedProcess` uses `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`
(`processes.py:325–333`). A controller restart cannot be assumed to preserve running
jobs if it owns the last Job handle. A safe upgrade must drain or introduce
supervisors whose lifetime is independent of the restartable control process.

The checked pool exposes launch/status/recover, but no active remote cancellation
tool (`mcp_server.py:102–117`; remote agent action dispatcher). `recover` is not
cancel and must not become an implicit rerun. Retain these honest limits until a
durable owned cancel protocol and platform-specific recovery proof exist.

Design independent attempt guardians, explicit cancellation intent and a recovery
loop that inspects the original attempt. Keep genuine uncertainty quarantined.
Controller restart survival and guardian-crash behavior need separate acceptance
tests; no design can promise uninterrupted execution through machine failure.

### F07 — Host identity is not yet an enforced shared capacity domain

`Pool.__init__()` rejects duplicate configured **IDs** (`pool.py:72–75`), but does
not deduplicate physical machines or parent hypervisors. Remote exclusivity uses
`<root>/pool.lock` and scans only that root (`remote_agent.py:264–305,566–577`).
Two aliases or roots on one physical host can therefore establish independent
admission domains. The fixture accepted `STARTING` in two roots on one machine,
while refusing a second request in the same root; process launch was mocked.

This is a conditional configuration risk, **not evidence that the live pool is
misconfigured**. The guide already requires one root per physical host. Enforce
the rule using a machine identity and single host admission broker, and record a
parent capacity identity for Windows/WSL/VM views or shared physical devices.
Allow genuinely independent hosts to continue when another host is quarantined;
preserve global quarantine within an affected physical host until resource-scope
isolation is independently proved.

### F08 — The pool distributes hosts but leaves functional concurrency unused

The local worker supports reviewed functional headless sharing, but the automatic
pool creates `workload: auto` (`pool.py:182–190`). Local host probing marks **any**
claim as busy (`:89–110`), and remote supervision holds one root lock for the full
attempt. Consequently the automatic pool's conservative capacity is effectively
one checked attempt per eligible host, regardless of configured local slots.

This was a reasonable initial safety policy. Increasing `--headless-slots` alone
will not make this pool use them. Add a reviewed workload catalog and let the
worker admit typed CPU/memory/volume requirements atomically. Keep unknown
scripts, interactive work, composite suites and performance measurements
exclusive until their adapters are qualified. A filename heuristic is a guard,
not proof that arbitrary code is safe to parallelize.

### F09 — Preparation and resource estimates can compete outside admission

Snapshot capture occurs before the local job owns claims (`integration.py:15–44`).
Local materialization checks free space per copy but does not reserve it
transactionally (`worker.py:435–448`). Pool selection uses a fixed 512 MiB job
memory estimate and source-copy storage estimates (`pool.py:187–190`,
`pool_policy.py:114–128`); import/output growth and concurrent clients can exceed
them. The configured local CPU/memory quantities are slots, not measured limits
(`worker.py:114–115`). Remote execution locking starts after incoming transfer.

Add preparation/import/transfer tokens and per-volume reservations before heavy
I/O. Include immutable source, writable copy, imports, output allowance and free
space reserve, with accounting for shared Windows/VM volumes. Reserve measured
memory envelopes and keep usable headroom for Sergio's desktop. A low-space
condition stops new admission; it does not delete active inputs or evidence.
The low free space recorded for ANGELA_AIR makes this an immediate fleet concern,
but its current free space must be measured rather than inferred from that record.

### F10 — Global probe waits and sequential preparation reduce responsiveness

Host probes run in parallel, but `_submit()` waits for all results while holding
the pool-wide `dispatch.lock` (`pool.py:191–210`). One slow SSH probe can delay
otherwise healthy-host scheduling. After that lock is released, `run_batch()`
still calls each submit synchronously; archive verification and upload for one
row delay preparation of later rows (`pool_batch.py:135–158`,
`pool.py:221–254`). Status and collection are likewise sequential within a batch.

Content-addressed archives are already reused, but `probe_host()` does not import
an actual remote cache inventory and defaults `cached_inputs` to an empty list
(`pool.py:113–122`). The planner's warm-cache branch is therefore not informed
by actual remote archive presence. The runtime avoids some uploads later, while
placement still charges the cold transfer estimate.

Move bounded probing outside short admission transactions, cache observations with
explicit freshness and use worker-side atomic reservation as authority. Prepare
independent hosts through a small bounded executor; cap hashing, compression and
transfer separately. Publish verified cache identities and measured stage costs.
An unavailable host should produce a bounded exclusion reason, not hold unrelated
work behind its network timeout. No measured throughput improvement is claimed.

### F11 — Windows queue CI does not cover all of its own dependencies

The path list in `.github/workflows/testqueue-windows.yml:4–28` omits dependencies
read by the fixture suite it executes. Concrete examples are
`research/native-kernel/run.py`, `research/native-kernel/macos_engine_identity.py`,
`research/performance/session_probe.gd` and
`tools/release/macos_reference_receipt.py`. See
`research/performance/test_session_baseline.py:523–528,843–852,917–921` and
`session_baseline.py:57–64`. `.mcp.json` is also outside the trigger list; direct
server-call tests do not validate that registration.

The separate Windows workflow is not enumerated by the main workflow's
`CI required` aggregate (`ci.yml:1014–1038`). A green aggregate alone therefore
does not establish native Windows queue verification. Current branch protection
was not obtained; the name of a job is not proof of enforcement.

Create one always-scheduled policy gate with internal dependency selection and
an explicit native Windows result when queue-related inputs change. Do not make
a path-filtered workflow unconditionally required: skipped workflows can leave
required checks pending. Include missing/failed/canceled results and intentional
nonselection in gate fixtures, and preserve tag/manual/release behavior.

### F12 — Optimize CI using the existing plan and measured evidence

`tools/ci/policy.py` still has `SHADOW = True`; recommendations do not reduce full
production coverage. The unit matrix has eight modulo shards plus integration;
visual group parallelism is a manual, nonblocking shadow experiment. Preserve
the existing [release/CI plan](../../../plans/release-ci-efficiency.md), required
case reconciliation and cold/warm cache parity rather than activating selective
testing without qualification.

One completed main run reports `captures-app` **2,496,652,310 bytes** and
`release-builds` **4,672,183,937 bytes**, with expiry on 13 February 2027. Their
upload steps omit explicit retention; most compact diagnostics have seven-day
retention. This is a concrete storage opportunity, not a measured billing or
speed improvement. Inventory release/replay consumers before choosing shorter
retention for ordinary successful runs; retain failure evidence and tagged-release
provenance. No artifacts were deleted by this audit.

The audited workflows do not explicitly route jobs through the personal pool.
Whether any CI runner shares a physical host with it was not verified. If trusted
CI is later delegated through the pool to personal hardware, it
must acquire the same physical-host admission as MCP and CLI work. Keep public
fork/PR code off the trusted personal fleet: the cooperative queue is not a
sandbox, and this repository is public. Runner isolation and credential separation
are material prerequisites, not reasons to install a new runner during the audit.

### F13 — Bind the deployed agent and protocol as well as source and engine

The remote probe advertises `protocol`, but the coordinator does not check it
(`remote_agent.py:249–261`, `pool.py:101–113`). No deployed-agent/process-adapter
content identity is explicitly bound by the coordinator to the execution receipt.
The snapshot's engine-version check is conditional on the getter existing
(`pool.py:175–181`); remote probe hashes the executable without independently
invoking its version (`remote_agent.py:202–213`).

Existing source/archive and executable-hash verification remains valuable. This
finding is a compatibility/provenance gap, not an observed bad engine or runtime.
Require compatible protocol and reviewed runtime identities before placement,
retain them per attempt, and preserve native bundle dependencies where relevant.
Use versioned deployed runtime directories and drain before replacing the code
that owns active work. Reject incompatible/missing identity with a clear
configuration result, rather than allowing it to become dispatch uncertainty.

### F14 — Recover accepted identity before revalidating submission inputs

`Pool.recover()` replays local `submit` instead of first asking the authority for
the accepted request (`pool.py:278–299`). `Worker.submit()` validates the source
and snapshot before reaching the store's existing-request lookup
(`worker.py:274–318`, `store.py:62–107`). After acceptance with a lost reply,
missing or changed original inputs can therefore make the replay raise
`ValueError` or `FileNotFoundError`, even while the accepted attempt runs from its
isolated materialization.

The pool catches those local exceptions and writes `NOT_DISPATCHED` with
`FINISHED`, `INFRA_FAILED` and `cleanup: CONFIRMED`. Subsequent pool status returns
that cached terminal result without contacting the authority
(`pool.py:293–321`). The MCP batch supervisor can also enter this path
(`pool_mcp.py:157–164`). A validation failure on a replay does not establish that
the original request was never accepted.

The local authority's execution claims remain independent; this finding does
**not** demonstrate that the authority releases them or starts a duplicate. It
does demonstrate an untrustworthy pool lifecycle/cleanup assertion and possible
loss of useful observation of running work. Never use that assertion to clear
claims, delete inputs/evidence or launch replacement work.

The isolated reproduction used a real task-owned fake Python process and an
injected lost acknowledgement, then made its private snapshot manifest unavailable.
Pool recovery returned confirmed cleanup while the authority still reported
`RUNNING`, a live owned process, four claims and one attempt. The next pool status
made zero RPC calls and repeated the false terminal result. The fixture then
canceled only its own handle and verified cleanup. This Linux fixture mocks the
local Windows platform label and transport boundary; it is not native Windows
or real simulator acceptance.

First recover accepted identity with the request secret, then observe the actual
job. If acceptance cannot be established or ruled out, retain uncertainty. A
typed nonacceptance response must be request-bound and fenced against a delayed
original submission; broad exception types are not proof. Add the lost-reply plus
changed/missing-input race to R1's required regression matrix.

## Fleet implications

| Machine | Grounded inventory | Recommended role and limits |
| --- | --- | --- |
| Windows / DEVIL | User-reported AMD 5900X; repository records Ryzen 9 5900X / RTX 3090 in `docs/plans/ai-flight-companions.md:97–100`; local rendered evidence is dated. | Windows correctness, owned interactive sessions, native NVIDIA/1080p graphics and isolated performance. Functional CPU checks can share only after measured admission; reserve GPU/desktop for work that actually needs it. |
| Remote Linux / `openrc-linux` | Existing SSH route and dated checked-job acceptance; current CPU/RAM/storage and physical parent were not queried. | Portable headless checks, source analysis and suitable builds after engine/architecture qualification. Consider an always-on controller only after availability/topology is known; moving the controller is not a prerequisite for repairs. |
| ANGEL | Dated 14 November record: MacBookAir10,1, M1, 8 GiB; approximately 124 GiB free then. | Native ARM64/macOS checks and qualified Metal work. Start with one admitted attempt and separate graphical campaigns. |
| ANGELA_AIR | Same dated model/RAM record; approximately 6 GiB free then. | Smaller cached headless/native checks when current storage allows. Reject oversized preparation cleanly; do not fill the machine to obtain parallelism. |
| Workflow CI | Workflow-selected Windows/Linux/macOS environments; physical runner topology was not independently verified. | Public PR gates and platform coverage; workflow success does not qualify personal GPUs, desktop sessions or radio hardware. |

The Mac figures are explicitly historical. Do not add their RAM, disk or CPU
capacities as though they were one machine. Check thermal/power/sleep state,
engine identity, user activity and shared physical parents before raising limits.
Performance baselines and candidates stay on the same reserved physical host.

## Primary references and applicability

Retrieved on 15 November 2026. These sources support platform/protocol semantics;
the repository and reproductions support the code findings.

- [MCP 2025-11-25 lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
  and [cancellation](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation):
  request timeouts, cancellation races and limits; this version is advertised by
  the audited server. Do not silently adopt different semantics from newer drafts.
- [Python subprocess contract](https://docs.python.org/3.12/library/subprocess.html):
  process creation and timeout behavior; a timeout on an SSH client does not prove
  remote work has stopped.
- [Microsoft Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects):
  descendant management and last-handle kill behavior. Preserve the existing
  stronger process-handle verification; a missing object name is not new proof.
- [Linux cgroup v2](https://docs.kernel.org/admin-guide/cgroup-v2.html): possible
  delegated containment/accounting and population observation. Availability and
  permissions on the actual Linux host remain unverified; this is not a Mac adapter.
- [SQLite WAL](https://www.sqlite.org/wal.html): local-host database ownership;
  remote workers must communicate through APIs rather than share a WAL database.
- [GitHub concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency):
  cancellation and pending-run policy. A concurrency group is not automatically
  an unlimited FIFO queue or a cross-tool physical-host lock.
- [GitHub required checks](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks)
  and [self-hosted security](https://docs.github.com/en/actions/reference/security/secure-use):
  skipped-workflow gating and the trust boundary for public repository execution.

## Decision

Repair the existing Python/SQLite authority and checked-pool protocols in small
stages. Do not replace them with a new distributed framework to solve these
specific defects. Reconsider a separate backend only after measured service or
multi-controller requirements justify its operational cost. The nonnegotiable
contract is: **a deadline may end waiting or request owned cancellation; only
proof of nonlaunch or completed teardown may release execution capacity.**

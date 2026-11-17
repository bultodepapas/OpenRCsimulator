# Queue resilience implementation and senior review handoff

Owner: **TQ-04**. This is the implementation follow-up to the
[dated audit](README.md) and [repair plan](../../../plans/mcp-queue-resilience.md).
Branch: `audit/mcp-queue-resilience-2026-11-15`.

**Status: tested review candidate; no fleet deployment or merge authorization.**
The audit was published at `413c8c88a57dc35d77e68a5808dad9a6a47aeff3`, against
runtime baseline `c048a4e6834646400070a488b293344dc1e1fd80`. This follow-up
incorporates `main` at `273a7e4c0617fdf4cacc39c360796fd79afa5f2c`, including
`c930dcdbf`'s explicit operator abandonment. Its unrelated aircraft/research
changes are preserved. Review the resilience changes against the merged parent,
not as replacements for that concurrent work.

The storage follow-up below also integrates `main` at
`cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`. Its ClearView and aircraft changes
are preserved in a separate merge; they are not queue implementation changes.

The **16 November re-audit** below integrates the newer `main` at
`6dfe1b9179af408f6b765b91ca164e626570db9f`. It supersedes earlier statements
that the last required CI run was pending. The system remains a partial review
candidate: the healthy-process continuity defect is reproduced, not closed.

## What is implemented

| Boundary | Candidate behavior | Main evidence |
| --- | --- | --- |
| Process creation, F01 | The adapter reports proved nonlaunch only before entering process creation. The worker requires both the typed exception and that instance's confirmation. Ambiguous creation retains quarantine. | `test_processes`, `test_worker` |
| Allocated thread cannot start | A one-way grant prevents execution until `Thread.start()` returns. Even a spawned thread followed by an exception receives a denied grant. Confirmed nonlaunch finalizes as infrastructure failure; failed persistence retains a fence. | Pre-start, post-spawn and repeated journal-failure tests in `test_worker` |
| Cleanup uncertainty plus broken storage | Establish an in-memory fence under the worker lock before attempting an `UNKNOWN` write. Retry that same journal transition before new allocation. Already allocated preparations also check the fence before launching. | Cleanup failure plus SQLite transaction failure with a compatible waiting job |
| Dispatcher death/readiness, F02 | Preserve one scheduler loop, guard the error-reporting path, use bounded backoff, report thread/heartbeat/error health, and require a committed storage recovery check before clearing degradation. Unreadable claims are `null`, never an invented empty inventory. | Scheduler double-failure, recovery, stale heartbeat and unavailable inventory tests |
| Ambiguous pool acceptance, F14 | Query the original authority with the saved identity before input validation or replay. Only replay the identical request to its bound destination. An exception is never cleanup or nonacceptance proof. | Unit recovery cases and a real task-owned fake process surviving lost acceptance plus missing snapshot |
| Historical false terminal results | Reopen legacy `NOT_DISPATCHED` receipts and affected completed/collecting batch rows for observation. Preserve old status/collection records and recollect under `recovery-1`. Cached MCP status exposes recovery required without SSH. | `test_pool_legacy_batch`, `test_pool_recovery` |
| Failure before dispatch, F03/F05 | Typed lock/preflight I/O deferral retries the same row with capped backoff. A returned invalid-input refusal rejects that invocation. Persist `SUBMITTING` before calling the pool; interruption becomes observation-only, including when no receipt is found. | `test_pool_submission` |
| Input/result identity | Use the exact manifest object returned by verification. Bind the batch's raw receipt hash to that same read. Bind engine-pin policy bytes to their verified file hash. Pool and interactive submissions carry expected source/manifest digests; observed local/remote results are checked against retained identity. | Snapshot replacement, forged-scope, engine-pin substitution/removal, local digest and remote payload tests |
| MCP intake, F06 | Fixed ordered tool lane, separate cached batch-status lane, bounded message queues, explicit overload, and independent protocol intake/output. Output backpressure cannot strand later accepted actions. | Concurrent stdio, stalled sink, unread OS pipe and admission-race tests |
| Observation budget, F04 | Use one monotonic deadline across socket connect/send/each receive. Zero wait performs no status call. Preserve accepted handles on timeout and mark a returned prior status stale. No observer timeout invokes cancellation. | Private loopback silent/trickle peers, socket cleanup, handle retention and wait tests |
| Request validation, F05 | Local, MCP and remote checked entry points agree on marker count, length and prohibited control characters. | `test_request_limits` |
| Windows selection, F11 | Add five omitted dependency/registration paths to both PR and main-push filters; validate repository MCP registration without launching a server. | Workflow diff and `test_mcp_registration`; Windows Actions run remains separate evidence |

The runtime implementation is in
[worker/process ownership](../../../../tools/testqueue/worker.py),
[pool recovery](../../../../tools/testqueue/pool.py),
[batch state](../../../../tools/testqueue/pool_batch.py),
[snapshot verification](../../../../tools/testqueue/snapshots.py),
[observation RPC](../../../../tools/testqueue/common.py), and the
[MCP server](../../../../tools/debug/mcp_server.py). The
[operating guide](../../../../tools/testqueue/README.md) owns user-facing commands.

## Safety decisions for review

### A timeout stops observation, not ownership

The new deadline applies to `common.wait()` and its socket steps. It does not
shorten an accepted execution budget. `wait_observation` marks a prior result as
`STALE`, with `DEADLINE_EXPIRED` or `RPC_STEP_TIMEOUT`; the actual lifecycle state
is retained. When no observation exists, `ObservationTimeout` identifies the job
and reason. Managed interactive launch with zero wait returns its accepted
handle and `observation: NOT_REQUESTED`. A first-observation timeout returns that
same handle with `observation: TIMEOUT`.

Snapshot creation, local filesystem I/O, admission before acceptance, SSH upload,
collection and worker-lock acquisition do **not** acquire hard end-to-end bounds
from this patch. A 30-second pool observation budget can still enter an older
inline transfer with a longer transport limit. Do not describe R3/R4 as complete.
Hard execution limits remain the preexisting, explicitly admitted job policy.

### Nonlaunch requires a witness

`ProcessNotStartedError` is insufficient by itself: the same `OwnedProcess`
instance must confirm its pre-create failure. Crossing the creation boundary
without ownership/cleanup proof remains uncertain. A thread-start failure has a
different witness: its immutable denied gate prevents the thread from entering
execution, even if the thread exists. Neither a missing PID nor elapsed time is
used as that witness.

Failed persistence cannot reopen capacity. Pending unknown/nonlaunch journal
transitions remain fenced in memory and retry on the existing scheduler.
Durable `UNKNOWN` retains the existing store's quarantine. A process restart
still converts unresolved durable attempts conservatively; this is not guardian
continuity or general immunity to storage failure.

### Receipt absence is not global nonexecution

Batch version 2 persists `SUBMITTING` before entering the pool call. A completed
typed preflight rejection can move a fresh row to `REJECTED`; it contains no
fabricated cleanup result. A crash before recording that returned rejection
leaves uncertainty. An interrupted `SUBMITTING`, legacy version-1 `WAITING`,
or pool receipt missing its execution request is reobserved/blocked, not freshly
submitted because a file is absent.

The existing JSON journal fsyncs file contents and renames, but does not qualify
directory-entry durability across power loss on every platform. The conservative
no-request behavior deliberately avoids claiming that an earlier receipt cannot
have been lost. Stronger platform persistence semantics and migration belong to
R4/R5; do not weaken these guards to make a stuck row disappear.

### Recover the same authority and the same inputs

New pool receipts bind configuration bytes and, for local execution, the original
authority root. A changed config fails closed. Legacy receipts without that
binding permit observation only; automatic replay is refused. Keep the original
configuration and request secret privately. Do not remap a host alias or copy a
receipt to a different root to force recovery.

Remote observation must carry the original request ID and canonical payload
hash. Only a structured request-bound remote `NOT_FOUND` refusal can lead to
same-ID replay; an older unbound error envelope or transport exception cannot.
The standalone remote agent adds protocol/request identity to its refusal
envelope. No remote runtime was installed during this work.

For snapshots, comparing the two digest *strings* after rereading a file was
insufficient: changed scope/source fields could retain those strings. Callers
now consume the actual verified object, and pin checks read bytes matched to
that object's file hash. The execution path verifies the accepted digests again
before and after materialization. This remains per-file verification, not an
atomic multi-file filesystem snapshot. Legacy callers can still omit the optional
expected digests; enforcing a versioned client/runtime contract remains open.

### Preserve the explicit operator exception

Upstream `abandon` requires an owner handle, a drained worker, no executing
supervisor, and its Windows orphan-absence check. It records
`INFRA_FAILED / UNCONFIRMED / INCOMPLETE`, rather than claiming proved cleanup.
The merged candidate additionally refuses abandonment while **any** pending
attempt fence/journal exists, preventing a later retry from resurrecting an
abandoned attempt whose claims were already released. The regression checks all
three registries. No timer, recovery loop or MCP notification calls `abandon`.

## MCP concurrency and delivery contract

| Lane | Bound | Behavior |
| --- | --- | --- |
| Ordered simulator/mutating tools | One worker, 32 waiting calls | Preserves process-global session environment and captured stdout. `sim_stop` remains ordered behind an earlier tool. |
| Cached `sim_test_status` | One worker, 8 waiting calls | Reads local receipts without SSH; slow filesystem access can still block this lane. |
| Protocol intake | Input lines capped at 1,048,576 characters | Handles ping/list/validation independently of a long tool. Oversized messages are discarded with a protocol error. |
| Replies | One writer, 64 queued messages | A saturated queue waits at most 0.2 seconds per publication before abandoning delivery. The abandonment transition and final tool admission share a short lock. |
| EOF | Drain accepted tool calls; then at most 0.5 seconds for reply delivery | Remaining or partially written replies can be lost, including for a slow reader. This does not cancel the accepted calls. |

No protocol lock is held across stdout write/flush. A blocked writer can remain
as one daemon thread until the pipe unblocks or the process exits. Real stdio
uses the raw descriptor so that this thread does not retain Python's buffered
stdout lock during interpreter shutdown. The unread-pipe fixture exercises the
actual subprocess exit path. This is a bounded-delivery policy, not a guarantee
that a client receives every response.

Queue bounds count messages, not response bytes. A large screenshot or cached
batch can still allocate a large object/result. Pagination/output-byte budgets
remain R3/R8 work. Input EOF also cannot interrupt an accepted tool that itself
blocks indefinitely. Full asynchronous session-context/guardian work is not
implemented by adding these lanes.

Wire-level JSON-RPC IDs and durable `sim_test_launch` argument IDs are different.
Use a fresh wire ID for each call while reusing the durable batch ID to recover
work. The advertised MCP versions end at 2025-11-25, whose
[request contract](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-11-25/basic/index.mdx)
requires session-unique wire IDs. The in-flight duplicate guard is bounded;
this patch does not add a forever-growing session ID ledger or implement the
newer stateless protocol. Cancellation notifications remain silent and never
terminate owned simulator work; explicit owned stop/cancel retains its contract.

## Verification and evidence

The [implementation evidence](implementation-evidence.json) records distinct
suite counts, commands, skipped cases, source hashes and CI observations. It is
separate from [the historical audit record](verification.md), whose 119 baseline
cases and defect reproductions remain unchanged. Historical defect probes are
not success gates for the repaired source.

The first implementation's integrated local run covers the complete queue and debug fixture directories,
checked/resource runners, the performance admission consumer and GOD TEST.
It covers **492 distinct cases: 482 passed, 10 skipped, no failures or errors**.
The groups were queue 254, debug 120, checked runner 22, resource runner 14,
performance admission 64 and GOD TEST 18. Queue and debug were rerun after the
Windows CI corrections below; the other unchanged groups retain their prior run.
Fixtures use private roots, loopback peers and task-owned fake processes. They
do not launch Godot, connect to the fleet, qualify the RTX GPU or benchmark useful
throughput. Windows-only ownership cases and native engine/desktop opt-ins are
recorded as skips on Linux; they are never counted as passes.

The most consequential regression scenarios are:

- Lost acceptance while a real fake process continues, followed by a missing
  snapshot: same job, same claims, no second submit.
- Forged scope with copied digest strings, a replaced valid snapshot, engine-pin
  substitution/removal and a batch hash/verification race.
- Failed cleanup plus an unavailable UNKNOWN transaction; a compatible younger
  job must not start. Repeated failed nonlaunch journal writes also retain the
  fence until persistence recovers.
- A thread that starts and then raises, demonstrating that its denied gate
  actually receives the thread and prevents execution.
- Legacy terminal/collection phases, a missing receipt alongside independent
  live work, preserved old artifacts and a legitimate failed test staying failed.
- Silent/trickling socket peers, blocked output, unread full stdout pipe, EOF,
  overload, distinct protocol IDs, and disconnection racing final admission.

Initial test setup errors and intermediate assertion updates were resolved before
the integrated run. No old failing assertion was discarded to bless the original
defect; changed contracts receive explicit desired-behavior tests. Review notes
also rejected a proposed wire-ID-reuse requirement after checking the supported
MCP specification, instead of restoring a blocking I/O lock.

### First GitHub CI pass and corrections

The first PR checks ran at `86777e923e6b6f1894878449d02b3125c05c5600`:

- [Windows queue fixtures](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43769880597)
  ran 253 queue cases with one failure, one error and three skips. A fixture that
  clears the environment exposed an eagerly evaluated system-username default,
  even when an owner is configured. Owner lookup is now lazy and explicitly
  tested. Another assertion compared canonical and unresolved temporary path
  spellings; it now compares canonical roots while retaining the original
  authority-binding check. Later Windows groups did not run after that failure.
- [Required CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43769880612)
  passed 130 policy/documentation fixtures and the Linux queue group (253 cases,
  eight skips), then release preflight rejected the missing
  `app/tests/test_extra_visual_details.gd.uid`. The script without its sidecar is
  already present in integrated `main` at `273a7e4c0`; production jobs did not run.
- [MetalFX source controls](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43769880593)
  passed.

The failed runs remain part of the evidence. The corrected revision
`1b0a6225e9c37585e6d051c7e5c6abd6b6c344a1` subsequently passed
[Windows queue regressions](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43771061290)
(492 cases: 487 passed, five skipped) and
[MetalFX source controls](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43771061301).
The [required CI run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43771061269)
reached production qualification but failed
[unit shard 6](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43771061269/job/132987956878)
at `res://tests/test_skin_fleet.gd`: four of 592 checks failed for the
`gp-extra-300s-60` paint/stock/kit identity. The earlier completed commands in that
shard passed; later commands did not run. Other production, native and visual jobs
in that run passed. The relevant aircraft and skin paths are unchanged between
the integrated `273a7e4c0` parent and `1b0a6225`; this is an inherited blocker.
The newer `cfb5acd5` main still changes geometry without completing the matching
skin-identity review. Do not bless a changed paint identity by replacing its hash:
the aircraft owner must qualify the geometry/UV/template compatibility or regenerate
the kit through its owning pipeline. No test selection or preflight rule is weakened.

### Inherited release-preflight prerequisite

A separate follow-up adds only the missing application sidecar. The exact
`4.8.beta2.official.cafc17a19` editor generated it from the unchanged original
script in a private minimal project, using `--headless --import` through
`run_checked.py`. The binary matched the repository's pinned SHA-512. The editor
exited zero with complete output and no error or warning records. Its generated
UID was checked against all 2,009 existing tracked application sidecar blobs,
verified from local Git objects: no collision.

This was metadata generation, not a simulator run, aircraft test or complete
production import. Full local application materialization was unavailable in
this partial clone. The required CI run must verify the complete source and
preflight; the application script itself remains unchanged. The machine-readable
evidence retains engine, script, sidecar and log identities.

## Storage cleanup follow-up

### Findings that constrain deletion

The queue has several distinct copies and owners: a client snapshot, coordinator
archive, remote incoming archive, remote per-job archive, writable materialized
source, imported assets, profiles, temporary output and collected results. These
are not interchangeable cache entries. The inspection found:

- A failed coordinator archive build could leave its fixed `.pending` copy behind
  and already reserve a selected host. The build's failure did not prove that an
  older temporary or shared archive was unused.
- Local pool placement measured the coordinator's volume, although the execution
  authority can keep attempts on another volume. This could report available
  capacity where the attempt filesystem was full.
- A successful remote job retained a separate `input.tar` after extraction, while
  the original verified incoming archive still existed. This is a narrow redundant
  copy with a reviewable lifetime; the whole job directory is not.
- Full capture evidence can reside inside `attempt/source/app/captures`, and
  arbitrary checked jobs can write useful source/profile/temp output. Existing
  artifact inventories do not establish a complete contract for these paths.
- `FINISHED` can represent explicit abandonment with `cleanup: UNCONFIRMED`.
  Released execution claims, file age, an empty PID list or a collected infrastructure
  report cannot authorize workspace deletion. Missing remote artifact inventories
  and interrupted collection remain evidence gaps.
- Shared snapshots and archives can have queued or concurrent readers. The existing
  archive creation lock does not cover the later upload lifetime. Remote upload
  `.pending` files and log/SQLite-event growth have no complete retention contract.

### Implemented changes and safety boundaries

| Change | Implemented boundary | Failure behavior |
| --- | --- | --- |
| Coordinator archive construction | Unique temporary per invocation; verify regular-file identity, flush and verify contents before publication. Prepare outside the global dispatch lock and before a destination receipt; select again afterward. | Remove only that invocation's identifiable unpublished temporary. Transient I/O can defer before dispatch; an unremovable/replaced temporary or invalid cache requires inspection and blocks repeated automatic builds. |
| Execution-volume observation | Worker `hosts.storage` reports the attempt filesystem's free bytes, scope and observation time. Query capacity before acquiring the admission lock. | Unavailable or older telemetry is `DISK_UNKNOWN`; do not substitute coordinator capacity. The individual filesystem call can still block. |
| Preparation diagnostics | Record the owned attempt output directory immediately after exclusive creation. | Preparation failures retain a discoverable directory and incomplete evidence; this does not create an artifact-completeness or deletion claim. |
| Remote redundant input | After durably confirmed `FINISHED / PASSED / COMPLETE / CONFIRMED`, verify both archive copies and pin the verified incoming inode as `retained-input.tar`. Persist unlink intent before removing only `input.tar`. | Separate `storage_cleanup` status retains uncertainty without changing the test outcome. All source, profiles, temp, captures, reports, logs, records and shared cache names remain untouched. |
| Explicit retry | `reclaim-input` addresses one original request ID and canonical payload digest under the host pool lock. | Busy/conflicting/unsupported requests refuse; repeated completed cleanup is idempotent. The public digest binds identity and is not an authentication secret. |

The [operating guide](../../../../tools/testqueue/README.md#storage-after-a-remote-checked-job)
owns commands and status meanings. Remote reclamation is limited to supported
POSIX descriptor-relative/no-follow operations, hard links and a private directory
with cooperating processes under one account. It does not provide isolation from
hostile same-account mutation. Windows retains its input copy. Hashing permits at
most 16 GiB per file with a cooperative 30-second budget; blocked filesystem calls
can exceed that budget. Hashing retains the host lock, so its post-execution I/O
cost must be measured on the real machines before claiming a throughput benefit.

The pin keeps archive bytes available without creating another archive copy.
Reported reclamation is logical bytes, not guaranteed physically freed space.
Python documents [platform-specific descriptor and link support](https://docs.python.org/3.12/library/os.html#os.supports_dir_fd);
Linux separately documents [directory synchronization](https://man7.org/linux/man-pages/man2/fsync.2.html)
and [unlink/open-file lifetime](https://man7.org/linux/man-pages/man2/unlink.2.html).
The implementation checks supported operations and synchronizes both the retained
link and the intent/result directory updates. If deletion is interrupted after
intent, retry reports the observed absence without inventing a deletion witness.
If every corrective journal write fails, no implementation can promise a durable
corrective status; retain the original host evidence for inspection.

No age-based sweep, fleet cleanup, local attempt deletion, shared-cache GC,
snapshot pruning or log rotation is enabled. Disk estimates and the archive
headroom check are advisory, not atomic volume reservations. The upload/request
gap and incomplete collection paths still need the work below. Worker updates
must wait for an idle/drained boundary; missing new storage telemetry is not a
reason to restart an occupied authority.

### Follow-up verification

The exact combined queue source passes **542 distinct cases: 532 passed, ten
skipped, zero failures or errors** across the same six groups. Queue now has 304
cases, including 50 new archive/storage/retention cases; debug has 120, checked
runner 22, resource runner 14, performance admission 64 and GOD TEST 18. Each
group was rerun on this candidate, with duplicate case IDs checked. Skips remain
platform/native opt-ins; this is Linux fixture evidence, not a fleet campaign.

Fault coverage includes disk-full writes, publication and fsync failure, denied
unlink, replaced/link/reparse paths, missing/corrupt backup, unsupported links,
hash budgets, mutated inputs, before/after-intent interruptions, final journal
publication failure, busy/conflicting retry, preserved source/capture evidence,
placement reselection and a second batch invocation after failed cleanup. The
independent source/fixture review found no publication-blocking safety regression
within the documented cooperating-directory boundary; the lead ran the integrated
tests. The reviewer did not claim an independent test run.

A bounded read-only storage inventory covered this sparse development workspace
only: 2,503 files and 33,784,681 logical bytes, with a complete scan. It does not
measure the Windows/Linux/Mac fleet or demonstrate reclaimed fleet capacity. Test
cleanup acted only on private fixture files. The evidence JSON retains the scan
scope, commands, hashes, case counts and explicit limitations.

The latest main integration also needs 13 ClearView GDScript UID sidecars.
The exact pinned editor generated these from unchanged staged upstream scripts in
an isolated minimal project: complete exit-zero import, no errors or warnings.
All new IDs are distinct and checked against the complete application sidecar
inventory. The sidecars are a separate metadata prerequisite, not a claim that
ClearView, aircraft appearance or the full simulator has been qualified locally.
PR #13 must run fresh Windows and required CI checks for the published follow-up;
the inherited aircraft identity blocker above remains open.

## 16 November re-audit of current main and the review branch

### Current source and CI evidence

The re-audit starts from published branch `926614263ea70973c205981f7898558989d35edd`
and merges `main` at `6dfe1b9179af408f6b765b91ca164e626570db9f`, preserving the
43 changed paths in the two newer main commits, including ClearView motion/source
observations, Extra geometry and the Apple Silicon closeout plan.
Queue implementation findings were compared against both main and the audit
branch; this is not an assumption that previously proposed work landed in main.

| Revision/evidence | Observed result | Consequence |
| --- | --- | --- |
| [Branch required CI, 43788625222](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43788625222) | Completed with failure. `test_skin_fleet.gd` failed 4 of 592 checks; `test_ui_language.gd` failed 14 assertions. | The previous branch cannot be described as fully green. The queue fixtures passing is separate evidence. |
| [Branch Windows fixtures, 43788625296](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43788625296) | Passed on the earlier `9266142` revision. | Useful baseline for Windows containment; it does not qualify the new console/collection changes. |
| [Branch MetalFX controls, 43788625172](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43788625172) | Passed source controls. | This is not an Apple GPU campaign. |
| [Current main CI, 43882413757](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43882413757) | Failed release preflight on 19 missing UID sidecars; production jobs were skipped. | Main's current application/native tests were not run to completion. Fourteen sidecars already exist on the audit branch; this pass generates the remaining five. |

The seven non-Spanish catalogs each lack the same 11 source messages on current
main. The candidate adds all 77 translations, retaining existing entries and
format-argument order. The pinned editor generated five UID sidecars from the
unchanged upstream scripts in a private project; all five are distinct and do
not collide with any of the 2,023 individually verified indexed application UIDs.
Those prerequisites do not change test selection or weaken the required gate.

The Extra 300S skin identity remains an aircraft-owner blocker. Current main
changes geometry again while leaving `app/assets/skin-kit/models.json`,
`procedural_skin.gd`, `custom_skin.gd` and `test_skin_fleet.gd` unchanged. A changed
paint identity must be qualified using the owning skin/geometry workflow, not
accepted by replacing an expected hash. A same-engine comparison of
all relevant old/current paint surfaces (paths, transforms, meshes, UVs and
materials; the prior review counted fourteen), or kit regeneration if incompatible,
remains open under `tools/skins/README.md`. No current surface count is claimed.

### Additional implemented boundaries

**Collection publication and recovery.** The collector now snapshots its accepted
status/receipt binding under the existing job lock, copies into an isolated
generation, checks portable path identities, sizes, hashes, report/log inventory
membership, the selected report's strict JSON value, command and required markers,
and then publishes a manifest. Failed copies or publication preserve all previous
generations. Destination locks also serialize different coordinator roots writing
to the same output location. Cache reuse revalidates evidence; JSON booleans do
not alias integers, and case/Unicode spelling checks include directory prefixes.
Normal and diagnostic reports are reconstructed from bound evidence rather than
trusted solely because a manifest names their files. Active batch resume also
revalidates current-format generations locally; missing/corrupt evidence blocks
the row while retaining its history. Intact evidence does not need a live host.
MCP status remains explicitly cached metadata without continuous artifact hashing.

Local request/control files are excluded from collection. Remote copies use a
bounded reader over noninteractive SSH with host-key verification. Declared
artifacts are capped at 128 MiB/4,096 files, collection JSON at 4 MiB, and retained
failed stages at three per job/output parent. No automatic deletion follows a
failed transfer. These are cooperating-reader budgets, not a receiver-side quota
against a compromised SSH peer. POSIX files and directory entries are synchronized;
Windows power-loss durability is still unqualified. The selected checked report
can establish its test result, but the manifest is not a complete workspace or
all-stage evidence inventory; successful-import evidence is not an independent
new collection prerequisite. Full workspace retirement remains prohibited.

**Checked completion.** A failed/incomplete import cannot be labeled a completed
requested test. The adapter retains the import verdict and returns incomplete;
incomplete or malformed checked results cannot pass. Legacy failed imports and
remote timeout/runner-exit records can be collected as diagnostics with their
original outcome. `diagnostic_only` cannot satisfy a passing functional check or
batch. Older unverified completed collections reobserve the original identity
and preserve prior results; they are not execution retries.

**Windows background commands.** Both queue gate layers and targeted Python
launch sites now request `CREATE_NO_WINDOW`: engine probes, Git snapshot/history
operations, SSH/SCP, checked runner processes, debug launch/import/cleanup and
GOD TEST source probes. The patch retains the existing output/exit handling, Job membership, process
groups and owned-cancellation calls; native validation must confirm their
behavior on the combined revision. No global `SW_HIDE` is used;
native simulator GUI windows keep normal visibility. Existing detached supervisors
retain their detached semantics. Microsoft documents that
[`CREATE_NO_WINDOW`](https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags)
applies to console processes and is ignored for native GUI applications or when
combined with `DETACHED_PROCESS`/`CREATE_NEW_CONSOLE`.

The directly launched console layers are testable in hosted Windows; this does
not prove every shell-created grandchild or an external MCP client's initial
launcher remains invisible. A controlled interactive desktop check is still
required. No fleet worker was restarted to apply the candidate.

### Confirmed open continuity defect

A private fixture injected one `sqlite3.OperationalError` into the local
worker's `RUNNING / CREATED_OWNED` journal update after the fake owned process had
written `started.json` and was observed alive. The worker tore it down and
reported `FINISHED / INFRA_FAILED / cleanup: CONFIRMED`; its normal `ended.json`
was absent. The reproduction used only its own fixture process and retained its
command, hashes and result in the evidence record.

The local worker and remote stage supervisor still couple journal failures to
owned process teardown. The local hard deadline is also armed after a potentially
blocking post-start write. Moving a timeout into another thread that still needs
the same worker/storage lock is insufficient. The required fix must keep process
ownership and accepted monotonic execution/cancellation policy independent of
storage availability, order terminal journal retries, retain claims until proved
teardown plus durable finalization, and reject stale transitions. No partial
guardian implementation is represented as solving this P0 in the candidate.

### Re-audit verification

The lead ran the six existing regression groups on the combined code candidate
`8e9938f17dfb54524a2fbc9187374ce53ce87997`: **582 distinct cases, 571 passed,
11 skipped, zero failures/errors**. Case IDs were checked for duplicates across
groups, and all initially frozen source files remained unchanged during the run.

| Group | Cases | Passed | Skipped |
| --- | ---: | ---: | ---: |
| Queue, ownership, collection and Windows launch policy | 344 | 335 | 9 |
| Debug/MCP | 120 | 119 | 1 |
| Checked runner | 22 | 21 | 1 |
| Resource runner | 14 | 14 | 0 |
| Performance admission | 64 | 64 | 0 |
| GOD TEST tooling | 18 | 18 | 0 |

The performance group initially could not load four omitted files in this sparse
checkout; exact indexed upstream blobs were materialized before its successful
64-case run. Those setup failures remain recorded, without treating them as code
regressions or silently discarding their logs. Skips cover native Windows Job,
locking/path/attribute and desktop behavior, plus the explicit actual-engine
failure-matrix opt-in. They are not passing coverage.

The exact pinned editor passed UID generation with no error/warning records. A
separate checked Godot catalog subset passed **45 assertions**, using the existing
test's verbatim catalog/check functions, the real registry, all eight catalogs and
the exact indexed font binaries/import sidecars. System font fallback was disabled
for the bundled CJK checks. An earlier fixture used default import settings; it is
explicitly superseded for glyph claims. The 77 translations still require
native-speaker review.

Exact commands, source hashes, grouped regression results, pinned-editor UID
generation, the scoped Godot catalog check, review findings and platform limits
are appended under `reaudit_2026_11_16` in the evidence JSON. The draft PR owns the
fresh published-revision Actions links; historical runs above do not substitute
for those checks. The unchanged full `test_ui_language.gd` instantiates the main
application and was not run in the sparse local workspace. The isolated catalog
subset does not qualify Home, persistence, layout, aircraft assets or native GPUs.
Resume-time local verification still precedes the batch polling deadline; slow or
blocked filesystem operations can exceed that nominal budget. This pass does not
claim a hard end-to-end deadline for preparation, transfer or collection.

## 17 November Windows integration and continuity repair

Branch `integrate/testqueue-resilience-20261117` merges this branch (`4b4a9fe24`)
onto `main` `2a3cf04db` as `2ec329f34`. Only the seven non-Spanish catalogs
conflicted (both sides appended distinct entries; all kept, no duplicate `msgid`).
The 19 branch UID sidecars have their scripts and collide with no tracked UID.

### Continuity repair (closes the P0 above in fixtures)

| Defect | Repair | Regression (fails on `2ec329f34`, passes on candidate) |
| --- | --- | --- |
| Post-start journal exception tore down the healthy process and rewrote its outcome `INFRA_FAILED` | Post-start `RUNNING`/`CLEANING`/`FINISHED` writes go through one newest-wins pending journal, retried by the monitor each second and by the scheduler before any allocation. | `test_post_start_journal_failure_keeps_the_owned_process_running` |
| Hard deadline armed after a blocking write; monitor needed the worker lock every 0.1 s | Deadline armed at the creation boundary; a per-attempt watchdog enforces it through the process lock and session bridge only. Process handles moved from `lock` to `_process_lock` (order `lock` → `_process_lock`). | `test_hard_deadline_is_enforced_while_the_monitor_hangs_in_storage`, `test_hard_deadline_and_teardown_do_not_wait_for_a_stalled_journal` |
| Failed terminal write lost the transition (thread died) or relabeled a pass | `_finalize` keeps the verdict pending; claims stay until it is durable; a fenced attempt never finalizes as proved cleanup. `Store.update` refuses transitions on a durable `FINISHED` attempt (`StaleTransition`). | `test_failed_terminal_journal_keeps_claims_and_the_real_verdict` |
| `hosts` blocked behind a held worker lock (20 s observed) | 1 s bounded acquire, then `DEGRADED`, `claims: null`; adds `pending_journals`/`journal_errors`. | Both deadline tests assert a prompt degraded response |
| Unreadable `ready.json` during the adapter's atomic replace (Windows sharing violation) killed the process | Read failure is retried on the next pass. | Covered by inspection; no deterministic Windows race fixture |
| Remote: post-start `state.json` failure killed the child; result read failure after proved teardown became `UNKNOWN`; terminal write had no retry; next stage inherited the closed process identity | Non-fatal observation with retry; result block moved after proved teardown (`result_unreadable`); six ordered terminal attempts before the host lock is released, otherwise fail closed; identity cleared per stage; `status()` reports instead of crashing when its quarantine write fails. | Four new `test_remote_agent` cases |

New teardown no longer holds the storage lock. A `_closing` set keeps the
earlier guarantee that no new attempt crosses its launch gate while another
teardown is unresolved; occupancy probes that meet a busy process lock report
unknown occupancy (fail closed) and the launch gate waits. `abandon` also refuses
while pending journals or teardowns exist. An independent Good Enemy review of
the first candidate found no deadlock, lost terminal record or early claim
release, and raised the hung-call deadline gap, lock-wait inversion and test
lock-order findings that the watchdog, bounded occupancy probe and `_owned_view`
test helper resolve.

### First Windows-native run of every group

Windows 11 Pro 10.0.26100, Ryzen 9 5900X, Python 3.11.9 (Microsoft Store),
private `TMP`/`TEMP` and a private empty `OPENRC_TESTQUEUE_ROOT`:

| Group | Cases | Passed | Skipped |
| --- | ---: | ---: | ---: |
| Queue | 352 | 320 | 32 |
| Debug/MCP | 120 | 119 | 1 |
| Checked runner | 22 | 21 | 1 |
| Resource runner | 14 | 14 | 0 |
| Performance admission | 75 | 74 | 1 |
| GOD TEST tooling | 18 | 18 | 0 |
| **Total** | **601** | **566** | **35** |

Zero failures or errors. The queue skips are 27 POSIX retention, two POSIX
collection, one POSIX process-group, one Linux/WSL preflight and the opt-in native
desktop campaign; the Windows-only Job/lock/path cases skipped on Linux ran and
passed here. These are fixtures with task-owned fake processes, not a native
Godot, desktop or fleet campaign.

The first baseline on the same merge without isolation reported 4 queue, 48 debug,
31 checked-runner and 2 GOD TEST failures/errors. All debug/checked/GOD TEST cases
came from inheriting this workstation's real enrollment (no worker was running);
the four queue cases hashed `sys.executable`, which a Microsoft Store Python alias
cannot open. The remote fixture now uses a dedicated engine file, and the queue
guide documents the private root for enrolled workstations. Neither was a runtime
defect; hosted CI runners are not enrolled.

### Efficiency and usability round (merged to local `main`)

Fast-forwarded onto `main` as `d9e68b84c`, then:

| Change | Behavior | Regression |
| --- | --- | --- |
| Robust duration history (`pool_history.py`) | Nine-sample window per host/script, tagged by pool job (retried collection adds no sample), median estimate, tiny/overflowing values floored or ignored. Unmeasured hosts borrow speed-scaled peer medians and at least the peers' setup instead of the full timeout. Unreadable history no longer takes a host offline. One-way format. | `test_pool_history` (7), `test_history_feeds_placement_and_corrupt_history_keeps_host_online` |
| Batch ordering | Longest expected test first; one history read per distinct script. | `test_longest_expected_test_is_submitted_first` |
| Saturated-constraint skip | A `WAITING` answer defers same-or-narrower rows to the next pass instead of re-probing every host per row; a per-script history refusal does not saturate. | `test_waiting_constraint_skips_only_same_or_narrower_rows_in_that_pass`, `test_script_specific_history_refusal_does_not_hold_back_other_rows` |
| `sim_test_status` summary | Counts, attention list with report/log, `next_action` (recovery only for a stopped supervisor), `suggested_poll_seconds`, serial pending seconds. Cached data only. | `test_status_summary_is_compact_actionable_and_cached` |
| Bounded capacity probe | One shared in-flight `disk_usage` observation; `hosts` waits at most 1 s, then reports it unavailable (ineligible, never free). | `test_stalled_capacity_query_is_bounded_unknown_and_not_duplicated` |

The ordering, skip and capacity regressions fail on `d9e68b84c`. A Good Enemy
review of the first candidate found no invariant violation and raised per-script
saturation starvation, duplicate samples on collection retry, misleading
recovery advice under a live supervisor, an inflated ETA including blocked rows,
an `OverflowError` path and an optimistic cold-host setup; all are fixed and
tested. The same hermetic Windows-native six-group run on the final candidate
reports 614 cases (queue 365, debug 120, checked 22, resource 14, performance 75,
GOD TEST 18), 579 passed, 35 skipped, 0 failures. Placement benefit is not
measured: no fleet comparison is claimed.

## Remaining senior work and deployment gates

| Priority | Remaining boundary | Concrete next review/acceptance |
| --- | --- | --- |
| P0 for continuity claims | **Closed in fixtures on 17 November** (see below): storage failure no longer stops a healthy owned process, a watchdog enforces the deadline even while the monitor hangs in storage, terminal journals are ordered and claims stay held until durable. A worker *process* restart still converts live attempts to `UNKNOWN`; a remote supervisor whose filesystem call hangs still blocks its single thread. | Separate guardian process (R4) for restart continuity and authenticated remote cancellation; native Windows/Linux/Mac fault campaign before rollout. |
| P0 for rollout | Native Windows process semantics and the operator exception need the exact combined candidate. | Review Windows Actions fixtures, then an idle/private native campaign: start ambiguity, cleanup failure, pending journals, owned cancel and foreign-process preservation. Hosted fixtures do not qualify the interactive desktop. |
| P1 | **Closed in fixtures 17 November:** `hosts` waits at most 1 s for the worker lock and at most 1 s for the shared capacity probe, then reports `DEGRADED`/unknown capacity. | Observe native behavior on a stalled volume during the campaign. |
| P1 | Preparation/upload/collection remain synchronous in parts of the pool. | Give each stage owned background lifetime, progress and remaining-budget propagation; do not equate reporting expiry with cleanup. |
| P1 | Physical host/VM/alias identity, memory/volume reservations and runtime version negotiation remain incomplete. | Implement R4/R5 before increasing capacities or routing CI onto personal machines. |
| P1 | Pool placement still serializes per host. Durations are now robust medians with peer estimates and batches run longest-first (17 November), but are uncalibrated against fleet measurements. | Measure cold/warm setup, transfer, execution and collection; implement fair global ordering across batches under R6. |
| P1 | Windows workflow still has path filters; stable required-gate integration and rule visibility are incomplete. | Confirm repository rules with authorized access, validate selected/missing/canceled results, keep full required CI policy intact. |
| P1 | Immutable collection is implemented, but complete artifact ownership, cache-reader leases and atomic volume reservations are not. | Continue R8: protect source-contained captures, qualify complete per-preset inventory before workspace retirement, bind shared readers and retain interrupted uploads until nonuse is proved. |
| P2 | Output-byte budgets, paginated status, bounded event/log retention and incident diagnostics. | Add limits that preserve active/unknown evidence and report unavailable observations honestly; do not treat the new copy reclamation as general GC. |

The Windows Ryzen 5900X/RTX3090, Linux host and both Macs remain the intended
qualification fleet, not claimed test environments for this patch. Keep current
capacity settings. Confirm whether Linux shares physical resources with Windows;
do not count a VM/WSL guest twice. Start Macs at their already approved capacity
and qualify sleep/wake, SSH loss and cooperative process-group limits separately.
Keep graphics/performance runs on a reserved physical host at 1920×1080 first.
No speedup percentage or increased GPU utilization is claimed without matched
native measurements.

### Suggested senior review order

1. Review the process witness, denied thread gate, pending journals and explicit
   operator exception together. Check the negative controls before changing any
   quarantine or claim-release rule.
2. Review pool recovery, version-2 migration and identity binding. Retain old
   receipts/artifacts; confirm legacy ambiguity stays observation-only.
3. Review MCP lane safety and its bounded, potentially lossy delivery contract.
   Confirm the intended clients retain durable IDs and handles across disconnects.
4. Review storage cleanup against its narrow unlink target, durable anchor/intent,
   same-account boundary and failure tests. Confirm old workers become ineligible
   instead of receiving invented disk capacity; plan compatible idle upgrades.
5. Require CI for the final PR revision, inspect skipped/native boundaries and
   review any interaction with newly landed `main` changes. Merge only after the
   maintainer's review; this candidate does not merge itself.
6. Deploy one drained/idle boundary at a time with retained runtime/config/state
   identities. Do not replace the running process owner. Reconnect MCP clients
   after updating the server; deploy compatible remote agents before relying on
   request-bound refusal behavior.

Batch version 2 is deliberately refused by old version-1 supervisors. Rollback
must not relabel interrupted submissions as `WAITING`, rewrite receipts, remove
claims or downgrade state files. Preserve the newer state and stop new admissions;
let current ownership/collection resolve under a compatible version. Native
backup/restore and broader rollout acceptance remain part of R9.

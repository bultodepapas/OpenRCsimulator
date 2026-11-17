# Shared-host test admission

The [15 November 2026 resilience audit](../../docs/research/testqueue/2026-11-15-resilience/README.md)
records known recovery/control gaps and a [baseline recovery runbook](../../docs/research/testqueue/2026-11-15-resilience/runbook.md).
The [implementation handoff](../../docs/research/testqueue/2026-11-15-resilience/implementation.md)
records the tested repair candidate, evidence and remaining gates. The
[TQ-04 repair plan](../../docs/plans/mcp-queue-resilience.md) distinguishes partial
implementation from proposed guardian/resource work. This guide describes the
source on this branch; deployed hosts may still run the older audited version.

## Automatic multi-host checked tests

`testctl.py pool` coordinates independent headless GDScript checks across the
Windows authority and SSH agents on ANGEL, ANGELA_AIR and Linux. Host configuration
on DEVIL is `C:\ProgramData\OpenRC\testpool\config.json`. SSH aliases and private
keys belong to the user's SSH configuration. Override the configuration with
`--config PATH` after `pool`, or `OPENRC_TESTPOOL_CONFIG`.

### MCP checked batches

Agents can submit independent headless checked scripts directly through the
`openrc-sim` MCP server, without opening an interactive simulator session. Reconnect
the MCP client after updating the server so it discovers `sim_test_launch`,
`sim_test_status` and `sim_test_recover`. The server uses the configured pool above.
The repository's `.mcp.json` registers it for compatible clients. On DEVIL it is
also registered in the user's Codex MCP configuration with the absolute server
path and `OPENRC_TESTPOOL_CONFIG`; `codex mcp get openrc-sim` inspects that entry.
Existing Codex sessions must reconnect to load the new tools.

1. Choose a unique, stable `request_id` (1–80 letters, digits, `_` or `-`) and
   call `sim_test_launch` with 1–64 `jobs`. Each job accepts `script` and optional
   `platform`, `require` (literal completion markers), `timeout` (seconds; default
   90) and `host` (configured host ID). Optional `source` selects a checkout;
   otherwise the repository root is used.
2. The call returns promptly while source freezing and dispatch proceed in the
   background. Keep the candidate stable until `sim_test_status` reports
   `source_frozen: true`. Status reads durable state only: `supervisor_active`,
   `supervisor`, optional `result` (`INCOMPLETE`, `PASSED` or `FAILED`), snapshot,
   job outcomes and collected artifact locations. It does not launch work.
   Read its `summary` first: counts (`passed`, `failed`, `rejected`, `blocked`,
   `running`, `queued`), `attention` (each failed, rejected or blocked test with
   its report/log or error), `next_action` and, while incomplete,
   `suggested_poll_seconds`, `pending_test_seconds_serial` (serial sum of
   historical medians for queued and running tests; parallel hosts finish sooner,
   advisory, not a deadline) and `unmeasured_pending_tests`. `summary` is the
   first field so it survives client-side truncation of long replies.
   `next_action` recommends recovery only when the supervisor is not running,
   a new request ID only when no snapshot was frozen, and operator inspection
   when only blocked rows remain. An unknown request ID returns an explicit error. `jobs` remains authoritative.
3. Inspect the checked outcomes, cleanup and collected evidence. A failed test is
   not retried. If interrupted or a reply is lost, use `sim_test_recover` with the
   same ID; recovery retains the frozen snapshot, request identity and selected
   host, and never reruns a failed test. An uncertain attempt is not moved to a
   different host. Repeating `sim_test_launch` with the same ID and inputs is
   idempotent; reusing the ID with changed inputs is refused.

The supervisor observes the batch for up to one hour, retrying receipt recovery
and artifact collection without rerunning tests. It may then stop with an
incomplete batch; recovery resumes that batch. Stopping observation does not
cancel remote jobs. Infrastructure failures retain their available diagnostics
and cannot qualify a passing batch.
If freezing is interrupted before a snapshot manifest exists, exact inputs were not
frozen and no tests were dispatched. Submit a new request ID for a stable source.

Protocol ping/list/validation and cached `sim_test_status` have independent intake
from the ordered simulator tool lane. Other tools, including `sim_stop`, still
execute in order. The lanes have fixed workers and bounded queues; overload is
an explicit nonacceptance error. A disconnected or saturated observer cannot
block accepted calls behind reply publication. After input EOF, accepted calls
finish, then reply delivery has a 0.5-second drain window; queued or partial replies
may be lost. Individual reply bytes are not capped. Recover durable work by its
original batch ID or session handle. Use a fresh JSON-RPC wire ID for each call;
that wire ID is separate from the stable batch `request_id` argument.

For example, pass these argument objects to the named MCP tools:

```text
sim_test_launch: {"request_id":"mathcheck20261114a","jobs":[{"script":"res://tests/test_math3d.gd","require":["0 failed"],"timeout":90}]}
sim_test_status: {"request_id":"mathcheck20261114a"}
sim_test_recover: {"request_id":"mathcheck20261114a"}
```

The MCP default targets the caller's OS. Set `platform` to `windows`, `linux` or
`darwin` for a specific OS, or explicitly to `any` only for a reviewed portable
check. A pass on one host does not establish coverage on the other platforms.
Tests with performance, graphics, interactive or composite-suite requirements
retain their existing dedicated entry points and acceptance gates.

### CLI checked batches

```powershell
python tools/testqueue/testctl.py pool hosts
python tools/testqueue/testctl.py pool run --script res://tests/test_math3d.gd --script res://tests/test_camera_math.gd --require "0 failed"
```

`run` freezes the candidate once and distributes its independent scripts. It
prints a durable batch manifest/state pair before dispatch. Each job has its
own project, imports, profile, deadline and results. Explicit pool jobs default
to `--platform any`, declaring that their checks may run on any configured OS.
Use `--platform windows`, `linux` or `darwin` when the required coverage is OS
specific. Different platforms in one batch use a JSON manifest with a `snapshot`
path and `jobs` array, each containing `script`, `platform`, `timeout`, `require`
and optional `host`. A pool snapshot is created with `pool snapshot --source PATH`.

Batches submit the longest expected test first (fleet-best historical median, or
the timeout when unmeasured; ties keep manifest order), so short tests fill the
tail. When one submission answers `WAITING` for its platform/host constraint,
rows with the same or a narrower constraint wait for the next pass instead of
repeating a probe of every host; a refusal caused only by that script's history
does not hold back other scripts. Ordering never changes eligibility or identity.

```powershell
python tools/testqueue/pool_batch.py --config C:/ProgramData/OpenRC/testpool/config.json --manifest batch.json --state batch-state.json --timeout 3600
python tools/testqueue/testctl.py pool status JOB_ID
python tools/testqueue/testctl.py pool collect JOB_ID
python tools/testqueue/testctl.py pool recover JOB_ID
```

Reusing the batch command resumes its saved IDs. Finished attempts must have
complete checked evidence, confirmed cleanup and locally verified artifacts
before the batch passes. Failed tests remain failed. SSH ambiguity retains the
selected host and request identity. `recover` retries that identical submission
on the same host only after querying the original authority and only when the
saved destination permits replay. New receipts bind configuration bytes and the
local authority root. Restore the original configuration if recovery reports a
changed destination. Legacy unbound receipts permit observation, not automatic
replay. A receipt missing dispatch metadata stays `UNKNOWN/UNCONFIRMED`.

Batch state is version 2. `SUBMITTING` is persisted before calling the pool;
interrupted calls and legacy version-1 `WAITING` rows are reobserved rather than
blindly resubmitted. Proved predispatch lock/I/O deferral uses `RETRY_WAIT` with
0.25-second initial backoff capped at 30 seconds. Returned invalid-input refusal
uses `REJECTED`, without asserting global nonexecution or cleanup. Old
`NOT_DISPATCHED` and associated terminal/collection results require reobservation;
their previous status/artifacts remain available and new collection uses
`recovery-1`. MCP cached status exposes `recovery_required: true` and `INCOMPLETE`
for those records. Old supervisors refuse version-2 state; do not downgrade it.
The lower-level `pool submit` returns exit 3 when no host is eligible and nothing
was submitted. `pool run` and the batch driver retain and wait for pending work.

### Verified collection and retry

`pool collect JOB_ID` publishes a new immutable generation under
`results/JOB_ID/collection-<binding-sha256>/`. The binding covers the retained
request/destination and the exact finished status observation. The returned
`report`, `log`, `pool_status` or `pool_report` paths are authoritative; callers
must not assume the old `results/JOB_ID/report.json` layout. Legacy nonexecution
recovery retains its `recovery-1` parent. Existing files are preserved.

Collection first writes an isolated pending directory. It checks the declared
sizes and hashes, the selected report's inventory digest and strict parsed JSON
value, command, required markers and settings, and the report/log membership in that same inventory. Passing
reports also require complete evidence, confirmed process cleanup and matching
log error/warning counts and required markers. A fresh manifest is published only after verification. A retry
revalidates an existing generation instead of overwriting it or reading a stale
log from an older directory. For a local authority, it can reuse verified
evidence after the original attempt directory is no longer available, provided
the authority still confirms completion. A new remote collection still requires
original-authority status; local batch revalidation is described below.

Local collection copies only `checks/`, `imports/`, `worker.log` and `verdict.json`
when declared by the worker. Private request/control files are not copied.
Remote collection copies the remote inventory through a bounded Python reader
over noninteractive SSH; it retains the configured host-key policy. The limits
are 128 MiB of declared artifacts, 4,096 files and 4 MiB per collection JSON.
Paths must be portable and must not traverse links, device aliases or conflicting
file/directory names. Cooperating processes under one private account are assumed;
these checks are not isolation from a hostile writer under the same account.

Interrupted transfers retain their pending evidence and never replace an earlier
verified generation. Three retained pending attempts block further collection in
that job/output directory. Inspect them before retrying, or explicitly select
another output root:

```powershell
python tools/testqueue/testctl.py pool collect JOB_ID --out C:/OpenRC/review-results
```

This cap is not a general disk quota or automatic garbage collector. Collection
does not delete remote originals, workspaces, snapshots, failed output or unknown
attempts. POSIX publication synchronizes files and directory entries; Windows
power-loss durability remains separately unqualified. Filesystem operations can
still block beyond a cooperative observation budget.

An incomplete import, interrupted remote runner or legacy failed attempt can
produce a `diagnostic_only: true` collection retaining its original outcome and
available evidence. It cannot satisfy a passing batch or the functional checked
runner. New results carry `collection_format: openrc-pool-collection-v1`.
Completed batch rows with older unverified collections require original-identity
observation and collection; their previous results remain in history. MCP cached
status exposes recovery required without issuing network requests. Recollection
does not submit a new execution attempt.

MCP status labels its evidence observation `CACHED_METADATA`: it reads retained
metadata without continuously hashing large artifacts. An active batch resume
revalidates a completed generation locally before accepting it again, without
contacting the authority when that evidence is intact. A missing or changed
generation blocks collection; it cannot keep passing from cached metadata alone.
Direct `pool collect` also revalidates existing generations.

### Background consoles on Windows

Queue launch gates, engine probes, snapshot/history Git commands, SSH/SCP
helpers, checked runners and debug launch/cleanup helpers request
`CREATE_NO_WINDOW` for background console processes. The launch sites retain their
existing pipes/logs, Job Object assignment and cancellation code. Preserving these
behaviors on the combined Windows revision remains a native validation gate. Native simulator GUI windows retain their normal
visibility; no global `SW_HIDE` policy is applied. The MCP batch supervisor and
the Windows remote supervisor start with `CREATE_NO_WINDOW` and a new process
group, never `DETACHED_PROCESS`: a detached process has no console to inherit,
so every helper below it that lacks the flag (Git, SSH, shells, console wrappers)
opened its own visible window. Measured on Windows 11 26100 (17 November 2026):
an unflagged `git`/`cmd` pair under a detached parent produced 4 visible console
windows, and none under the hidden-console parent.

These changes affect newly launched helpers after the compatible runtime is
installed. Updating or restarting a worker must wait for an idle/drained boundary.
Hosted Windows fixtures can verify console visibility and retained I/O for owned
fake processes; the user's interactive desktop still needs a controlled check.
Creation flags apply to the targeted launch, not every descendant a shell or
external program may create; shell-launched grandchildren need native checking.
The launcher used by an external MCP client is outside these child-process
settings and may need separate diagnosis if its own initial window remains.

Placement rejects unavailable/busy hosts, incompatible platforms, mismatched
engine hashes and insufficient storage/memory. The estimate combines observed
load, recorded per-test duration, import setup and configured transfer bandwidth.
`history.json` keeps the newest nine successful durations per host and script,
tagged with their pool job so a retried collection adds no second sample (legacy
single numbers are read as one sample). Placement uses the median, so one cold
or loaded run does not dominate. A host that has not run a script borrows other
hosts' medians, scaled by the median speed ratio over scripts both have run
(`duration_source: peer`), and assumes at least the peers' median import setup,
instead of competing with the full timeout. Unreadable or overflowing history is
ignored rather than taking a host offline. History only ranks eligible hosts and
orders submissions; it never admits, reserves or retries. The window format is
one-way: older pool code refuses history-based placement for those scripts, so
keep `history.json` with the version that wrote it (or move it aside) on rollback.
Host probes (SSH, remote engine hashing, the local `hosts` call) run before the
pool's dispatch lock; under the lock only local receipts are re-read, and any host
that received a receipt since the probe stays reserved. `BUSY` names the
reserving receipt; an unreadable receipt is reported instead of stopping placement.
Bandwidth starts as an estimate. Repeated source archives are content-addressed,
verified and reused over SSH; each attempt still receives writable isolation.
Initial capacity is one exclusive attempt per remote host. Windows submissions
retain the existing queue's admission and ownership. Long-lived remote jobs are
detached from SSH and supervised with process-group cleanup and durable state.
Cooperative POSIX containment retains its documented limits.

For local placement, `hosts` reports free space on the worker's attempt filesystem,
not necessarily the coordinator's filesystem. An older worker without this storage
observation, or one reporting it unavailable, is ineligible for pool placement with
`DISK_UNKNOWN`. The observation runs in one shared background probe; if the volume
does not answer within 1 s, `hosts` reports it unavailable ("pending") instead of
waiting, and a stalled probe is never duplicated.
Update the worker only at an idle, drained boundary after confirming
its claims are clear; do not restart active work to refresh the observation.

When a remote host is selected, the coordinator prepares and verifies its archive
before writing a dispatch receipt. It releases the dispatch lock during preparation,
then probes and selects again before recording a destination; that selection may
change before a receipt exists. Once a destination is recorded, the existing
original-host recovery rule applies. Failed archive builds discard only the unique
unpublished temporary whose identity that invocation can verify. If its identity or
removal is unresolved, or an archive needs inspection, the batch can remain blocked;
preserve the reported path and investigate rather than sweeping temporary files.

The regular checked runner can opt into automatic placement in a shell.

```powershell
$env:OPENRC_TESTPOOL_CONFIG = 'C:/ProgramData/OpenRC/testpool/config.json'
# Declare portability only for a reviewed cross-platform check or batch.
$env:OPENRC_TESTPOOL_PLATFORM = 'any'
```

Without the platform override, the hook preserves the caller's OS. It routes
only the registered engine's headless script calls and preserves requested
output directories, required markers and diagnostic settings. Custom engines,
graphics, resource measurements, recognized timing scripts and composite
suite/CI/capture flows continue through their existing host-specific entry points.
Automatic migration of those composite/graphical workloads remains future work.
Hardware-specific benchmarks need a fixed machine and their native acceptance.

Deployment requires `remote_agent.py`, `processes.py` and `common.py` under the
configured remote `runtime/tools/testqueue/`, native Python and the verified
engine. Use one pool root per physical host for every client. The config pins
each remote engine SHA-256 and the shared exact engine version. Inputs include
the frozen source manifest; extracted files and target profile transformations
have separate receipts. Private configuration, generated snapshots, caches,
reports and runtime copies remain outside Git.

The experimental local worker owns each admitted process tree until verified teardown.
It classifies exclusive and parallel work across worktrees, isolates writable projects and
profiles, and preserves uncertain attempts as `UNKNOWN`. It does not change simulator
physics. Broader remote presets and native graphical qualification remain in the
[implementation gates](../../docs/plans/agent-test-orchestrator.md).

## Start one authority

For the configured Linux connection, use the [Linux SSH guide](../../docs/tools/linux-ssh.md).
SSH access alone does not qualify remote graphical or composite workloads.

Use Python 3.11 or newer. The worker uses the standard library; no package installation
or separate queue server is required. Run it in the intended logged-in Windows user's
session, with the exact official engine pinned by the checkout:

```powershell
python tools/testqueue/testctl.py serve --engine .tools/Godot_v4.8-beta2_win64_console.exe
```

The default authority is `C:\ProgramData\OpenRC\testqueue`, outside all checkouts.
Provision access for the intended development account. All participating clients must
use that same authority. If that volume lacks space, provision one shared
`OPENRC_TESTQUEUE_ROOT` on another local volume for the worker **and every client**.
Never place the live SQLite database on SMB, SSHFS or another network filesystem.
A machine-wide Windows mutex rejects another enrolled worker even with a different
root. Private fake-process fixtures deliberately use independent test domains.

Starting `serve` enrolls the chosen root in enforced mode. Existing `debugctl` and MCP
launch/control, GOD TEST CLI, `app/test.sh`, `app/capture.sh`, `app/run-landscape.sh`
and local CI enter the same boundary. Nested operations validate an opaque inherited
attempt capability against the live authority. An environment flag or bridge port
alone cannot authorize a launch. Unenrolled checkouts/hosted CI retain their existing
execution behavior. Once enrolled, an unavailable worker refuses managed launches.
Do not remove enrollment/lock files as a recovery shortcut.

To stop the worker normally, drain it, close owned sessions and confirm `hosts`
has no claims before stopping the foreground process. Interrupting a busy worker
retains unresolved claims for reconciliation.

This is cooperation among trusted development tools under one OS account. It does
not prevent a person from invoking the engine outside those tools, or protect secrets
from another process under the same account. External Godot occupancy blocks admission
and is never killed or adopted. Rendered work requires an active, unlocked user desktop;
losing that desktop fails the attempt and initiates owned cleanup.

## Jobs and session ownership

```powershell
python tools/testqueue/testctl.py hosts --json
python tools/testqueue/testctl.py list --json
python tools/debug/debugctl.py launch --mute
# Copy the returned handle into the caller's environment for subsequent commands.
$env:OPENRC_TESTQUEUE_HANDLE = '<job>:<opaque secret>'
python tools/debug/debugctl.py look
python tools/debug/debugctl.py stop
```

CLI `launch` waits up to ten minutes for readiness. If still queued, it returns a
successful accepted result with `ready: false`, the job and handle; the request remains
queued. Ownership is retained before waiting. Use `status` and `wait` to follow it, or
`cancel` with its owning handle. Managed MCP `sim_launch` returns after acceptance;
use `sim_session_status` until `ready: true`, or `sim_stop` to cancel queued/running work.
An MCP server retains the handle from its own launch. A fresh
MCP client does not silently acquire the last session. Session controls, including
read operations and stop, require that handle. The service brokers the bridge token.

For a focused script, first create a frozen snapshot in a **new** output directory
whose parent exists, then submit the declared preset:

```powershell
python tools/testqueue/testctl.py snapshot --out D:/OpenRC-queue-inputs/check-001 --imports
python tools/testqueue/testctl.py submit --preset checked --owner physics-agent --snapshot D:/OpenRC-queue-inputs/check-001 --options '{"script":"res://tests/test_simulation.gd","require":["0 failed"],"timeout":90}'
python tools/testqueue/testctl.py status <job> --json
python tools/testqueue/testctl.py wait <job> --timeout 600
python tools/testqueue/testctl.py result <job> --json
python tools/testqueue/testctl.py cancel '<job>:<opaque secret>'
```

The `checked` preset accepts test/tool scripts within the submitted application and
literal requested completion markers. Ordinary focused `run_checked.py` commands
using the registered editor, `--path app` and a test/tool script enter this preset
automatically and preserve checked verdicts. Unsupported engine options or resource/
performance capture require a separately qualified inherited runner. Review a
script's real completion text before selecting its markers. Options are JSON, never
an arbitrary shell command. `suite`, `capture` and `ci` require full repository scope;
their existing admitted entry points capture that scope automatically. `godtest`
rejects mutable external manifests and output/snapshot overrides. `landscape` rejects
external project/script selection. Presets may fail on unsupported dependencies;
their existence does not advertise native platform qualification.

Submission writes a private receipt **before** the RPC. After a lost response,
`testctl resubmit <receipt.json>` repeats the same request, secret and snapshot.
Reusing an ID with different inputs or credentials is refused, and the original
receipt survives. Status/result never return owner or inherited secrets.
`testctl recover <receipt.json>` retrieves an existing handle without verifying
the snapshot or creating a job. `testctl cancel-submission <receipt.json>` cancels
that request even if the first submit is still in flight. Resubmit tries recovery
first, so an already accepted job remains recoverable after its inputs disappear.

MCP retains an unresolved submission receipt before sending it. If the reply is
lost, retrying the same `sim_launch` reuses that request; different launch inputs
are refused until it is resolved or stopped. `sim_session_status` recovers an existing
handle without rehashing inputs or creating a session. `sim_stop` records durable
cancellation by request ID even before acceptance, so a delayed submit cannot start
after stop. An unconfirmed status remains explicit when the authority has no job yet.
Preserve the printed receipt if the client exits; another client can recover it with
`testctl resubmit` and use the returned owning handle. The authority upgrades schema
1 to 2 in place, preserving jobs/claims; older workers refuse schema 2. Drain before
upgrading and preserve the existing authority root and database.

`wait` returns immediately for `UNKNOWN` so callers can see the required reconciliation.
Timing out or a client disconnecting does not cancel a job. Finite execution
has a monotonic deadline. Interactive sessions default to a thirty-minute maximum;
all jobs are bounded to six hours. Queued requests have no automatic expiry.

## Parallel and exclusive admission

Every submission and status includes `scheduling`: policy version, selected mode,
workload, reason and resource claims. Callers submit typed preset options, never their
own resource amounts. Classification is deterministic; it does not inspect arbitrary
GDScript and prove that it is safe to run concurrently.

| Request | Mode | Admission contract |
| --- | --- | --- |
| `godtest`, `suite`, `ci`, `capture`, `landscape` | Exclusive | Composite work can include timing or shared-desktop operations. |
| `debug-session`, `debug-smoke`, including headless sessions | Exclusive | The unrestricted bridge can start profiling or focus-sensitive work later. |
| `checked`, default `workload: auto` | Exclusive | Unknown scripts are conservative by default. |
| `checked`, `headless: true`, `workload: functional` | Parallel | A trusted developer declares a reviewed functional check with no timing or shared-device dependency. |
| Recognized benchmark/performance/profile/latency/soak/stress/memory script names, or `workload: performance` | Exclusive | Performance classification overrides a functional declaration. A filename alone is not a proof about arbitrary script semantics. |
| `aircraft-screenshot` | Parallel | Fixed studio still renderer, one catalog aircraft, 1920×1080, no flight window, debug port, arbitrary arguments or animation. |

An exclusive attempt waits for **all** managed claims to drain and blocks all other
dispatch through preparation, execution, teardown and evidence collection. Any
`UNKNOWN` attempt quarantines new execution across the host, including records made
by an earlier queue version without an exclusive marker. An eligible exclusive waiter
blocks younger work from continually refilling slots. Requests that cannot run because
the desktop is locked or reserved do not prevent eligible functional headless work.
Human reservations also block headless exclusive performance work.

Headless slots and studio-capture slots both default to one. To allow two independent
studio renders after checking native GPU/RAM/disk headroom:

```powershell
python tools/testqueue/testctl.py serve --engine .tools/Godot_v4.8-beta2_win64_console.exe --headless-slots 2 --capture-slots 2
```

Create a fresh frozen snapshot as above, then submit a studio capture:

```powershell
python tools/testqueue/testctl.py submit --preset aircraft-screenshot --owner aircraft-agent --snapshot D:/OpenRC-queue-inputs/check-001 --options '{"aircraft":"jensen-das-ugly-stik-60","timeout":300}'
```

The worker verifies the studio script and Python launch dependencies against its
startup identity, including added package initializers/shadow modules. It rechecks
the materialized copy before execution, so a queued job cannot silently use an older
adapter after an authority upgrade. All clients must use matching reviewed tooling.
The aircraft/project inputs remain the candidate being tested; this is a trusted
development workflow, not a sandbox for untrusted code. The still and its manifest
must agree on aircraft, source identity, checksum and actual 1920×1080 PNG data.
An exit-zero runner or completion marker alone cannot pass. Studio screenshots
establish model presentation only, not flight behavior or frame-rate performance.

For a reviewed functional script, add `"workload":"functional"` to the `checked`
options. Resource sampling through `run_checked(..., resources=True)` also validates
an actual exclusive inherited grant. Unknown wrappers or tests with timing assertions
must remain exclusive. Do not label a benchmark functional to increase throughput.

The exclusivity guarantee covers admitted attempt execution. Client-side snapshot
creation and submission-time snapshot verification still happen outside resource
claims; direct/unwrapped research launchers and unrelated host applications can also
compete. Prepare snapshots before a timing campaign and keep that host otherwise
quiet. Per-copy disk checks are not atomic reservations across concurrent copies.
Increasing slot counts is an opt-in capacity setting, not hardware qualification.

The named research launchers `session_baseline.py` and `run_visibility_capture.py`
now refuse standalone execution on enrolled hosts. They require both an exclusive
inherited grant and their actual headless/rendered scope, including engine identity
probes. They have no standalone queue adapter. Other unwrapped research tools remain
outside this boundary. GOD TEST `resume` also reports its unsupported standalone
state before reading retained suites or launching retries on an enrolled host.

## Recovery and evidence

Resource allocation and dispatch intent are transactional. The database is opened
only by the authority, using schema-version checks, WAL and full synchronization.
The worker holds a singleton guard; a restart converts unresolved dispatch/running/
cleanup records to `UNKNOWN` and retains their claims. Cancellation is durable before
a delayed start can proceed. Execution is not automatically retried and claims
do not expire. Typed predispatch pool deferrals and pending journal writes can
retry without creating another execution attempt.

Proved failures before process creation finalize as infrastructure failures with
confirmed nonlaunch. An allocated execution thread must receive a one-way grant
after thread startup succeeds; a denied grant cannot launch, even if the thread
was created before startup raised. Ambiguous start or cleanup failure retains
quarantine. If the quarantine write fails, an in-memory fence blocks allocation
and preallocated launches until the same journal transition becomes durable.

After an owned process is created, storage is observation, not ownership. The
admitted hard deadline is armed from a monotonic clock at the creation boundary
and enforced by a separate per-attempt watchdog that touches only the session
bridge and the process lock, so it fires even while the monitor thread hangs
inside a storage call. Process handles, cancellation enforcement and teardown use
that process lock, never the storage/admission lock; the monitor waits at most
0.05 s per pass for the storage lock, and occupancy probes never wait out another
attempt's teardown (busy ownership is unknown occupancy). A failed or blocked `RUNNING`/`CLEANING`/`FINISHED` journal keeps
the attempt's newest transition pending. Its monitor retries it each second, and
the scheduler retries it before any new allocation. The process keeps running,
its outcome is never rewritten as an infrastructure failure, and its claims stay
held until teardown is proved **and** the terminal record is durable. An
unobservable cancel flag delays cancellation; it is never a cancellation or a
reason to stop healthy work. A new attempt does not cross its launch gate while
another attempt's teardown is still unresolved. The store refuses any transition
on an attempt whose `FINISHED` record is already durable. A worker restart still
converts undurable attempts to `UNKNOWN`.

`hosts` includes scheduler thread/liveness, last successful scan/dispatch, age,
error and recovery state, `pending_quarantines`, `pending_journals` and
`journal_errors`. Any pending journal reports `DEGRADED`. The same scheduler
recovers with capped backoff after dispatch/diagnostic faults. Unavailable claim
inventory is `null`, not an empty list. If the worker lock stays busy for 1 s
(stalled storage or scheduler), `hosts` answers `DEGRADED` with `claims: null`
instead of waiting. Scheduler health is not proof that capacity is free: inspect
claims, reservations and attempt states too. A stalled capacity volume is also
bounded (1 s) and reported as unknown storage. Other operations wait at most
25 s for the worker lock and then answer `WORKER_BUSY`; clients treat that like
a socket-step timeout (nothing changed, observe again) instead of a refusal.

The remote supervisor follows the same rule: a failed post-start `state.json`
write is retried while the owned child keeps running, a stage result that cannot
be read after proved teardown is `result_unreadable` (not cleanup uncertainty),
and the terminal record gets six ordered attempts before the host lock is
released. If they all fail, the stale `RUNNING` record is later observed as
`UNKNOWN` and quarantines the host. A filesystem call that hangs rather than
fails still blocks that single supervisor thread.

`wait` shares a monotonic socket deadline across connection, send and every read.
A prior nonterminal observation returned on timeout carries
`wait_observation: {state: STALE, reason: DEADLINE_EXPIRED|RPC_STEP_TIMEOUT}`.
With no observation it raises an explicit observation timeout identifying the
job. Zero wait issues no status RPC. Managed MCP launch retains the accepted
handle and returns `ACCEPTED / NOT_REQUESTED`; an initial positive observation
timeout retains the same handle with `observation: TIMEOUT`. This does not cancel
the job, bound preparation/filesystem I/O, or alter its accepted execution limit.

Windows containment assigns a blocked Python launch gate to a kill-on-close Job Object
before it can execute the adapter. A Job completion port observes member processes;
retained process handles and lifetime accounting witness teardown. Root exit and
Job active-count zero alone are insufficient. Unobserved membership or failed cleanup
quarantines the attempt. Direct children and descendants that inherit the Job are
covered; external broker/service launches are outside that boundary and unsupported.

After a lost supervisor, same-boot reconciliation remains deliberately conservative:
the old per-process handles cannot be recovered. `testctl reconcile <handle>` releases
an unknown attempt only after proving that the same physical host has rebooted since
its durable prelaunch identity. It does not kill by recorded PID. Preserve the journal
and use an ordinary host reboot when necessary; never delete a stale lock or edit
claims to manufacture proof of cleanup.

An operator who explicitly accepts the remaining cleanup uncertainty can close a
same-boot Windows orphan with `testctl abandon <handle> --reason "owner request"`.
Drain the worker first and wait for all executing attempts to finish. The command
authenticates ownership and requires the recorded gate to be absent or signaled
and its named Job Object absent. Access errors refuse release. It records the
operator's reason, preserves the original identity and audit trail, and releases
only that attempt's claims. The terminal result is `INFRA_FAILED` with
`cleanup: UNCONFIRMED` and `evidence: INCOMPLETE`. This administrative exception
requires an explicit operator decision each time. After closure, restore admission
with `testctl drain off`. Ordinary cancellation and reconciliation retain their
existing process-tree proof requirements. Abandonment is also refused while any
attempt has a pending in-memory fence/journal retry or an unresolved teardown;
let that journal recover first.

### Storage after a remote checked job

After a remote checked job durably records `FINISHED`, `PASSED`, `COMPLETE` evidence
and process `cleanup: CONFIRMED`, the remote supervisor attempts to remove only its
redundant job-local `input.tar`. It verifies that file and the retained incoming
archive against the original digest, and pins a verified `retained-input.tar` hard
link in the job before recording unlink intent. The anchor retains the verified
archive even if the shared incoming name is later replaced. Files that fail these
checks are not removed.

`storage_cleanup` is separate from process `cleanup` and the test outcome:
`PENDING` means storage work or its journal is unresolved; `RECLAIMED` reports
`logical_bytes_removed`, not guaranteed physical space; `SKIPPED` means the cleanup
did not act; and `ABSENT_AFTER_INTENT` means the file is absent after a durable
intent but the deletion could not be witnessed, so removed bytes are unknown.
Status or a duplicate launch does not retry storage cleanup. Inspect its reason or
pending state and use the original host and identity for a single-job retry:

```sh
# On the original remote host, set these from pool status and that host's config.
printf '{"request_id":"%s","payload_sha256":"%s"}\n' "$TQ_REQUEST_ID" "$TQ_PAYLOAD_SHA256" | \
  python3 "$TQ_REMOTE_AGENT" reclaim-input --root "$TQ_REMOTE_ROOT"
```

Use the remote `request_id` and exact lowercase `payload_sha256` from that job's
status. The digest binds the original request; it is not a secret or an ownership
credential. A mismatch returns `CONFLICT`; a busy host lock returns `BUSY`. This
action does not launch tests or sweep other jobs.

Reclamation requires POSIX descriptor-relative no-follow operations and hard links;
it is unsupported on Windows. Hashing is limited to 16 GiB per file and a cooperative
30-second budget; a blocked filesystem call can exceed the deadline. A private
queue directory with cooperating processes under one account is required. The checks
confine path operations and refuse detected changes, but cannot make unlink atomic
against an arbitrary same-account writer.

Source trees, profiles, temporary directories, captures, logs, artifacts, job
records, journals, locks, shared snapshots and caches remain protected, including
failed, incomplete and `UNKNOWN` work. Full capture evidence can live inside an
attempt's source tree. The queue does not yet provide shared-cache garbage collection
or atomic storage reservations; remote upload can still leave a partial file before
remote admission checks. A completed infrastructure-failure collection does not
prove that all remote diagnostics were inventoried. Preserve remote evidence until
independently verified. For a bounded read-only size inventory, use
[`storage_audit.py`](../godot/README.md#process-ram-io-and-storage-pt1h-r4);
its logical sizes and partial-scan indicators do not authorize deletion.

### Operator storage and reconciliation tools

Measured on 17 November 2026, retention filled every queue disk. Each local
checked attempt keeps a writable copy of the frozen tree (about 3 GB), and each
remote job keeps its extracted source; local attempts held 52 GB on `C:` and
`angel` 45 GB. Remote jobs now hard-link the verified incoming archive into the
job instead of copying it (one copy less; placement counts one upload plus the
extraction). The explicit operator tools below never touch failed, incomplete or
`UNKNOWN` work, logs, reports or job records:

```powershell
python tools/testqueue/local_gc.py                     # dry run; --execute removes
python tools/testqueue/testctl.py pool gc --host angel  # dry run; --execute removes
python tools/testqueue/testctl.py pool reconcile JOB_ID [--operator-confirm]
python tools/testqueue/testctl.py pool remote-reconcile --host angel JOB_ID
```

- `local_gc.py` removes `<attempt>/source` only for unclaimed attempts recorded
  `FINISHED/PASSED/COMPLETE/CONFIRMED`. It reads the store read-only and never
  follows a link, junction or reparse point.
- `pool gc` first collects (or re-verifies) each remote `PASSED` job on this
  coordinator, then asks the remote agent to remove that job's source and archive
  copies, then removes incoming archives older than an hour that no unfinished
  job uses (refused if an unfinished journal is unreadable).
- `pool reconcile` releases a coordinator receipt that never reached execution.
  Local receipts use the authority's durable submission tombstone. A remote
  authority that has no record of the request releases the host only with
  `--operator-confirm`, because a remote run has no tombstone.
- `pool remote-reconcile` closes a remote `UNKNOWN` quarantine only when the host
  lock is free and the host rebooted or no process remains in the recorded gate's
  PID/process group.

Unpinned placement also skips a host whose newest two finished attempts of the
same source ended `INFRA_FAILED` (`BUSY: CIRCUIT_OPEN …`); a different source or
a later test result closes it. A local worker that sees an unmanaged simulator
reports `occupancy.external_simulators: true`, and placement treats it as busy
instead of queueing work behind the user's session. `hosts` also reports
`queued` local jobs (they hold no claim yet), so placement spreads work to other
hosts instead of stacking it behind a busy desktop. A passed local checked
attempt removes its own writable source copy as soon as its verdict is durable.

Snapshots bind actual dirty/untracked bytes, deletions, relevant metadata, launcher
digests, referenced aircraft authoring files, installed native inputs and optional
prepared imports. Stored input and per-attempt materialization are both verified.
Admission uses the exact verified manifest object. Batch receipt hashes and
engine-pin policy reads are bound to the same verified inputs; new pool and
interactive requests also pin expected source and manifest digests.
Writable source, `.godot`, profile, temp and output directories are independent.
History-dependent presets receive a separate local clone of Git history. Copies are
verified per file and inventories rechecked; this is **not an atomic multi-file
filesystem snapshot**. Coordinate a stable candidate with other writers. Imported
caches are frozen inputs, not proof of compatibility. Missing caches are imported
inside the owned attempt. Admission requires a 512 MiB disk reserve before source
copy and before materialization; it never deletes unrelated data to make room.

Results preserve each runner's verdict and completion evidence, checked diagnostics,
engine/version/digests, host/boot/process identity, source/adapter manifest, cleanup
status and artifact checksums. `PASSED` requires exit success, a complete runner
verdict and required artifacts. Missing evidence is `INFRA_FAILED/INCOMPLETE`, even
after an underlying exit zero. Capture receipts and GOD TEST case reports are checked
against their actual artifacts. Queue diagnostics establish no physics, GPU,
performance, radio or Mac qualification.

`reserve --owner <name>` reserves a free desktop and returns a release handle;
`release <handle>` removes that reservation. Reservations do not expire automatically.
`drain on` stops new dispatch while existing jobs finish; `drain off` resumes it.
CPU/memory units are conservative configured admission
slots, not measured hardware limits; do not increase concurrency before measuring
headroom and qualifying adapters. The scheduler is FIFO among feasible jobs with
an eligible-exclusive waiting barrier.
The local authority has no remote-host substitution, priority override or owner
transfer. The checked pool above selects a host before a new attempt is submitted.

## Verification

Set `TEMP`, `TMP` and `TMPDIR` to a local volume with at least the snapshot reserve.
On an **enrolled** workstation, also point `OPENRC_TESTQUEUE_ROOT` at a fresh empty
private directory (as the `tools/ci` fixtures do). Otherwise the debug, checked-runner
and GOD TEST fixtures inherit the host's real enrollment and fail because they
require a running worker; hosted CI runners are not enrolled and do not show this.
Fixture engines are dedicated files, never `sys.executable`: a Microsoft Store
Python alias cannot be opened for hashing.
For MCP checked-batch changes, run the focused client and coordinator fixtures:

```powershell
python -m unittest tools.testqueue.test_pool_mcp tools.debug.test_mcp_server
```

For broader changes to queue ownership or the debug bridge, select the affected
suite when its scope is justified:

```powershell
python -m unittest discover -s tools/testqueue -p 'test_*.py'
python -m unittest discover -s tools/debug -p 'test_*.py'
```

Fake runners measure actual Windows process creation/exit times for contention,
orphan children and declared headless/studio-capture overlap. Contract fixtures cover ownership, delayed
cancellation, restart quarantine, lost acknowledgements, snapshot mutation and
missing evidence. POSIX process-group fixtures establish only their weaker cooperative
boundary; the scheduler does not advertise a qualified Linux/macOS worker.

The opt-in native campaign is `python -m unittest -v tools.testqueue.test_native`.
Set `OPENRC_TESTQUEUE_NATIVE_ENGINE` to the pinned console executable and
`OPENRC_TESTQUEUE_ROOT` to a fresh local evidence directory first. It requires an
active desktop with no unmanaged Godot sessions, uses two real 1920×1080 sessions,
and retains evidence outside the checkout. It stops only its own attempts and worker.
The default suite skips this campaign.

The dedicated `Windows test queue regressions` workflow runs process, queue, MCP and
checked-runner fixtures on a hosted Windows runner when their sources change. It
does not run the graphical campaign or qualify simultaneous real studio captures.

Local evidence and outstanding platform gates live in the
[TQ plan](../../docs/plans/agent-test-orchestrator.md). Keep generated logs/images
outside Git and retain failures rather than weakening assertions.

# Shared-host test admission

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
on the same host. A preparation interrupted before a durable execution request
can be closed as `NOT_DISPATCHED`; its files and failure remain available.
The lower-level `pool submit` returns exit 3 when no host is eligible and nothing
was submitted. `pool run` and the batch driver retain and wait for pending work.

Placement rejects unavailable/busy hosts, incompatible platforms, mismatched
engine hashes and insufficient storage/memory. The estimate combines observed
load, recorded per-test duration, import setup and configured transfer bandwidth.
Bandwidth starts as an estimate. Repeated source archives are content-addressed,
verified and reused over SSH; each attempt still receives writable isolation.
Initial capacity is one exclusive attempt per remote host. Windows submissions
retain the existing queue's admission and ownership. Long-lived remote jobs are
detached from SSH and supervised with process-group cleanup and durable state.
Cooperative POSIX containment retains its documented limits.

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
a delayed start can proceed. There is no automatic retry or claim expiry.

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

Snapshots bind actual dirty/untracked bytes, deletions, relevant metadata, launcher
digests, referenced aircraft authoring files, installed native inputs and optional
prepared imports. Stored input and per-attempt materialization are both verified.
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

## Storage inspection

`testctl.py storage` provides local inventory and an explicit capacity diagnostic.
It reuses the [existing scanner](../godot/README.md#process-ram-io-and-storage-pt1h-r4),
does not contact the queue authority, and does not create/read queue state or
classify a path as safe to delete. It does not allocate storage, reserve capacity,
launch a test or run cleanup. Use `python -B` so the interpreter does not create
bytecode caches; without `-B`, normal Python startup/import behavior can write them.

Select existing, trusted, stable local directories. The following PowerShell
paths and budgets are examples, not configured host locations or calibrated
limits; substitute the host's approved roots. The command does not create them.

```powershell
python -B tools/testqueue/testctl.py storage inventory --root 'D:\OpenRC-agent-data' --top 20 --max-seconds 5
python -B tools/testqueue/testctl.py storage budget --root 'D:\OpenRC-agent-data' --peak-bytes 8589934592 --reserved-bytes 4294967296 --floor-bytes 21474836480
```

The second example asks whether an additional 8 GiB peak fits after 4 GiB of
other future commitments and a 20 GiB free-space floor. It is illustrative;
measure actual workload growth before choosing host policy. Run separately on
each relevant volume. C: and D: letters do not prove separate physical disks,
and two roots on one volume must not be treated as two pools of free space.

### Inventory contract

Repeat `--root` for up to four non-overlapping directories. The command refuses
duplicate/ancestor roots, detected identity aliases, selected paths inside a
case-insensitive `.git` component, `..`, and observed symlink/junction/reparse
components. Windows UNC and detected mapped-network drives are refused.
Operators must still avoid remote or nested network mounts; portable path
checks cannot identify every mount topology or alias.

| Option | Default | Bound / meaning |
| --- | --- | --- |
| `--top` | 20 | 1–100 largest regular-file paths per root |
| `--max-entries` | 25,000 | 1–100,000 encountered entries per root |
| `--max-seconds` | 5 | Greater than zero, at most 30; cooperative per-root scan time |
| `--max-depth` | 128 | 1–1,024 directory levels |
| `--exclude PREFIX` | None beyond `.git` | Repeatable root-relative, component-boundary prefix |
| `--out NEW_FILE` | JSON on stdout | Optional exclusive new file; existing local parent required |

All `.git` component casings are skipped, including a distinct `.GIT` on a
case-sensitive filesystem; other exclusions use native case behavior. File
contents are not read. Logical bytes count scanned regular-file paths and can
count the same hard-linked content more than once. They do not measure physical
allocation or reclaimable space. Volume free space is shown separately, and
results from different roots are not summed. Excluded or unreadable data,
limits and concurrent changes can make coverage incomplete.

An incomplete root makes the report partial. If a later root becomes unavailable
after initial validation, earlier results are preserved and that root has an
explicit unavailable record without an invented size. Inspect each root's
status and partial reasons; a successful earlier scan does not complete a later one.

Time limits are cooperative, not hard deadlines: a blocked filesystem call can
overrun them, and total scan time can reach the root count times the per-root
limit. Run after producers stop for a more consistent observation. Directory
identity checks detect common replacement races, but concurrent ancestor changes
or swap-and-restore can still follow a changed path. This is not a security
boundary for a hostile or actively rearranged filesystem.

### Budget contract

All three byte inputs are required nonnegative decimal integers; zero is valid.
`--peak-bytes` is the new operation's additional peak growth. `--reserved-bytes`
is other promised future growth not already reflected in volume usage;
`--floor-bytes` is free space to preserve. Assessment is:

```text
observed_fit when peak_bytes <= observed_free - reserved_bytes - floor_bytes
```

The command neither discovers those commitments nor writes a reservation.
Several agents can observe the same headroom, so this result cannot authorize
concurrent allocation by itself. Unavailable capacity is indeterminate rather
than a fit. The [storage lifecycle plan](../../docs/plans/agent-storage-lifecycle.md)
defines the pending atomic controller and its wider lifecycle accounting.

### Output and exit status

With no `--out`, the report is emitted to stdout. With `--out`, only the explicitly
requested new JSON file is created; its parent must already exist, and existing
files are not overwritten. Windows alternate-stream/device path syntax is
rejected lexically. Output-parent checks are strongest where descriptor-relative
no-follow access is available; concurrent replacement remains a Windows limit.
Native Windows and case-insensitive macOS behavior have not yet been qualified.

| Exit | Inventory | Budget |
| --- | --- | --- |
| 0 | Complete within the stated scope | Observed fit at sampling time |
| 1 | Partial report, including a root lost after validation | Insufficient observed headroom |
| 2 | Invalid selection/arguments or output error | Invalid input/path, unavailable capacity or output error |

Usage/output errors are reported on stderr and may have no JSON report.
Preserve useful findings in the existing task handoff rather than accumulating
committed inventory files. Source evidence and option tradeoffs live in the
[24-investigation research set](../../docs/research/agent-storage/README.md).

Focused verification:

```powershell
python -B -m unittest tools.testqueue.test_storage -v
```

## Verification

Set `TEMP`, `TMP` and `TMPDIR` to a local volume with at least the snapshot reserve.
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

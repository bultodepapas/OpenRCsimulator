# Shared-host test admission

The experimental local worker owns each admitted process tree until verified teardown.
It queues competing rendered jobs across worktrees, isolates writable projects and
profiles, and preserves uncertain attempts as `UNKNOWN`. It does not change simulator
physics. Remote distribution and native graphical qualification remain in the
[implementation gates](../../docs/plans/agent-test-orchestrator.md).

## Start one authority

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

`launch` waits up to ten minutes for readiness. If still queued, it returns the job and
handle; the request remains queued. Use `status` and `wait` to follow it, or `cancel`
with its owning handle. An MCP server retains the handle from its own launch. A fresh
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

`wait` timing out or a client disconnecting does not cancel a job. Finite execution
has a monotonic deadline. Interactive sessions default to a thirty-minute maximum;
all jobs are bounded to six hours. Queued requests have no automatic expiry.

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
Headless slots default to one. CPU/memory units are conservative configured admission
slots, not measured hardware limits; do not increase concurrency before measuring
headroom and qualifying adapters. The initial scheduler is FIFO among feasible jobs.
There is no remote-host substitution, priority override or owner transfer.

## Verification

Set `TEMP`, `TMP` and `TMPDIR` to a local volume with at least the snapshot reserve,
then run:

```powershell
python -m unittest discover -s tools/testqueue -p 'test_*.py'
python -m unittest discover -s tools/debug -p 'test_*.py'
```

Fake runners measure actual Windows process creation/exit times for contention,
orphan children and headless overlap. Contract fixtures cover ownership, delayed
cancellation, restart quarantine, lost acknowledgements, snapshot mutation and
missing evidence. POSIX process-group fixtures establish only their weaker cooperative
boundary; the scheduler does not advertise a qualified Linux/macOS worker.

The opt-in native campaign is `python -m unittest -v tools.testqueue.test_native`.
Set `OPENRC_TESTQUEUE_NATIVE_ENGINE` to the pinned console executable and
`OPENRC_TESTQUEUE_ROOT` to a fresh local evidence directory first. It requires an
active desktop with no unmanaged Godot sessions, uses two real 1920×1080 sessions,
and retains evidence outside the checkout. It stops only its own attempts and worker.
The default suite skips this campaign.

Local evidence and outstanding platform gates live in the
[TQ plan](../../docs/plans/agent-test-orchestrator.md). Keep generated logs/images
outside Git and retain failures rather than weakening assertions.

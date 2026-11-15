# Safe recovery with the current queue

Applies to baseline `c048a4e6834646400070a488b293344dc1e1fd80`, inspected
15 November 2026. Commands are existing interfaces; proposed automatic recovery,
remote cancellation and phase deadlines live in the
[implementation plan](../../../plans/mcp-queue-resilience.md).

## 1. Identify which queue layer is uncertain

Record the original request ID, job ID, host ID, source digest, phase and timestamp.
Preserve the original receipt and owner handle privately. A batch request ID,
pool job ID and local-authority job ID are different identifiers; use the one
returned by the corresponding tool. Never use a new request ID to investigate an
attempt that might already have started.

| Observation | Meaning and first action |
| --- | --- |
| MCP call has not returned | The synchronous server may still be preparing inputs or waiting on a bridge/status RPC. A timed-out client is not proof that its request was rejected. Recover its original receipt/identity. |
| Local `QUEUED` | Inspect `reason`, claims, desktop reservation and authority health. Capacity, GUI availability or an exclusive predecessor can legitimately block dispatch. |
| Local `UNKNOWN` | Teardown or launch certainty is not proved. The host retains claims. Inspect the original attempt and preserve quarantine. |
| Pool `WAITING` | No eligible host was selected; inspect candidate exclusions, OS/host pin, available memory/disk and engine identity. |
| Pool `BLOCKED`/`UNKNOWN` | Inspect the row error and whether its original job receipt exists. The pre-receipt recovery defect in F03 can leave this stuck; missing receipt alone is not universal proof of nonexecution. |
| `SUBMISSION_UNCONFIRMED` | Submission may have reached the selected host. Recover that exact request there; do not fail over. |
| `supervisor_active: true` | A supervisor lock is held. This does not prove useful progress or that an operation is within its nominal observer budget. |
| `COLLECTION_BLOCKED` / completed test without verified artifacts | Recover collection of the same attempt. Do not rerun the test to obtain replacement evidence. |

The [audit](README.md) separates confirmed defects from conservative safety
behavior. No elapsed-time threshold in the current system authorizes clearing an
unknown claim.

## 2. Observe without launching replacement work

From the original enrolled Windows environment:

```powershell
python tools/testqueue/testctl.py hosts --json
python tools/testqueue/testctl.py list --json
python tools/testqueue/testctl.py status '<local-job-id>' --json
python tools/testqueue/testctl.py result '<local-job-id>' --json
```

For a checked pool job, use the original private configuration and returned ID:

```powershell
python tools/testqueue/testctl.py pool --config 'C:/ProgramData/OpenRC/testpool/config.json' hosts
python tools/testqueue/testctl.py pool --config 'C:/ProgramData/OpenRC/testpool/config.json' status '<pool-job-id>'
```

These pool observations contact hosts and may refresh durable status, including
detecting a disappeared supervisor; they do not launch or cancel a test. In MCP,
`sim_test_status` reads cached batch state without SSH. `sim_session_status`
observes the session owned by that MCP server or explicit handle. Preserve errors
and timestamps when the authority is unreachable instead of calling a new launch.

Do not instantiate the production `Store` class as a diagnostic database reader:
its startup recovery changes active attempts to `UNKNOWN`. Use the authority's
status interface and an approved consistent backup procedure when needed.

## 3. Resume the original observer or receipt

**Current recovery defect F14:** pool/MCP recovery can replay local submission and
falsely report `NOT_DISPATCHED` with confirmed cleanup if the original acceptance
reply was lost and the source/snapshot later becomes invalid. The original job
can still run. Prefer identity-based observation first. If a pool receipt already
contains that terminal classification, pool status repeats it without querying
the authority; obtain the original local job through authenticated authority
recovery and inspect its status directly. Do not clear claims or launch a
replacement based on this pool result. Have the queue owner handle this case
until the identity-first recovery repair is implemented.

| Operation | Existing behavior |
| --- | --- |
| `sim_test_recover` with the original batch `request_id` | Starts/resumes the batch supervisor. Waiting jobs may proceed; blocked rows with receipts can replay pool recovery and encounter F14. It does not cancel remote jobs or intentionally rerun failed tests. |
| `testctl.py recover '<local-submission-receipt.json>'` | Retrieves an existing local handle by request identity. If no job exists it reports `SUBMISSION_UNCONFIRMED`; it does not submit or revalidate the snapshot. |
| `testctl.py resubmit '<local-submission-receipt.json>'` | Recovers first, otherwise may submit the exact recorded local request. This is an execution-affecting retry, not an observation command. |
| `testctl.py pool ... recover '<pool-job-id>'` | Replays the saved request on its original host, or finalizes a saved pre-request preparation failure as not dispatched. The local replay exception handling has F14; it is not equivalent to read-only local recovery. |
| `testctl.py pool ... collect '<pool-job-id>'` | Collects and verifies artifacts from a confirmed finished attempt. |

Use recovery only with the original configuration, snapshot and credentials.
The local CLI expects a flat local submission receipt; a pool receipt is a
different document with a nested `request`. Do not pass it as the local receipt
or rewrite it. The queue owner can use its original request ID/secret with the
existing authenticated authority `recover` operation without replaying submission.
`sim_test_recover` refuses a changed configuration digest. If snapshot freezing
was interrupted before any manifest/dispatch, the current MCP design reports the
source was not frozen; its guide calls for a new request against stable inputs.
That documented case is different from a missing/corrupt receipt after possible
dispatch. Preserve the evidence needed to tell them apart.

If F03 repeats, retain the useful first error and hand the request to the queue
owner for the bounded repair. Repeatedly pressing recover will not fix a permanent
schema error or the no-receipt transition gap. Do not edit the receipt to bind
different inputs to an accepted identity.

## 4. Cancel only an explicitly owned local job

For a local-authority job that its owner intends to stop:

```powershell
python tools/testqueue/testctl.py cancel '<job>:<owner-secret>'
python tools/testqueue/testctl.py status '<local-job-id>' --json
```

MCP `sim_stop` requests cancellation of that server's owned session. For a local
submission whose acceptance reply was lost, `cancel-submission '<receipt.json>'`
persists cancellation by request identity, preventing a late original submit.

A cancellation acknowledgement is not cleanup confirmation. Continue observing
until `FINISHED` with `cleanup: CONFIRMED`, or retain the reported uncertainty.
`wait --timeout` stops waiting; it does not cancel work and its timeout is not a
strict end-to-end RPC limit in this baseline.

**There is no current `sim_test_cancel`, pool cancel, or remote-agent reconciliation
command.** The plan adds them. Do not substitute a process-name kill, old PID,
SSH-session termination or deletion of the remote lock/journal.

## 5. Quarantine and maintenance

`drain on` pauses new local admission and preserves running work:

```powershell
python tools/testqueue/testctl.py drain on
```

Use it as a deliberate maintenance action, not an audit probe. Inspect active
claims before any upgrade, restart or capacity change. The currently combined
Windows worker owns Job handles; stopping it may terminate its contained jobs.

Current local `reconcile '<owner-handle>'` accepts an unknown attempt only when
its durable same-host identity proves a later boot. It deliberately refuses
same-boot PID/name/absence heuristics. A reboot interrupts work and is **not an
automatic timeout remedy**. Schedule it only after all owners' active work and
the user's session are safely handled; do not reboot just to clear a dashboard.
The remote agent has a separate journal and no implemented reconciliation route;
reboot alone does not clear its `UNKNOWN` record.

Never delete or edit claims, state files, lock files or enrollment to bypass
admission. `release` only releases an owned manual desktop reservation; it is not
a force-clear operation for process claims. Other independent, verified physical
hosts may handle other jobs while the affected host stays quarantined.

## 6. Minimal incident evidence

Capture this information once per incident, without private credentials or large
snapshots in Git:

- Audit/source commit and deployed worker/protocol version, OS/architecture,
  physical host/boot identity, relevant engine identity and private config digest.
- Request/job/attempt IDs and timestamped status transitions; first error, latest
  progress, retry count and cancellation intent.
- The original receipt, snapshot manifest identity, selected host and planner
  exclusions; redact owner secrets, endpoint auth, SSH routes and personal paths
  before sharing.
- Scheduler/guardian status, current claims, relevant supervisor/worker log tail,
  disk/memory headroom and desktop availability.
- Cleanup evidence and artifact manifests, including missing/incomplete evidence.
  Preserve the original local records; do not replace them with a successful rerun.

Classify the incident against F01–F14, or record a new cause with its evidence.
Healthy-running versus stalled cannot be decided from `UNKNOWN` or CPU usage
alone. The improvement plan's job is to make the missing proof and safe next
action visible, then automate only the actions justified by that proof.

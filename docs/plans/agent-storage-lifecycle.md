# Agent storage lifecycle plan

**Owner:** developer tooling and shared-host test-queue maintainers.
**Prefix:** STOR. **Baseline:** `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`.
**Opened:** 2026-11-15.

Bound the storage created by parallel agents while preserving source, active
jobs, recovery state and accepted evidence. Keep useful parallel coding and
qualified headless tests; do not serialize all agents to hide a storage problem.

The [research synthesis](../research/agent-storage/README.md) owns the 24 web
investigations and 32-option comparison. The
[test-queue operating guide](../../tools/testqueue/README.md#storage-inspection)
owns available commands. This plan owns remaining implementation and proof.

## Ownership and scope

Owned work is the storage command in `tools/testqueue/`, narrow reuse/fixes in
`tools/godot/storage_audit.py`, storage guidance in `AGENTS.md` and
`docs/SUBAGENTS.md`, and this plan/research set. Changes to queue admission,
snapshot identity, remote collection, engine caches and release retention must
be coordinated with their existing owners. Simulation, physics acceptance,
rendered-session exclusivity and hosted CI policy remain with their tracks.

No host root, quota, retention duration, background service or automatic
deletion policy is installed by the inspection phase. C: and D: were not
accessible for a real capacity survey. Directory layouts and controls below
describe proposed implementation, not available CLI flags.

## Steps and acceptance

| ID | Work | Proof / status |
| --- | --- | --- |
| STOR-00 | Inspect repository lifecycle and research current tools/incidents | Delivered in the dated research set: 24 questions, sources and applicability limits. No live host inventory. |
| STOR-01 | Bounded multi-root inventory and explicit capacity diagnostic | Implemented in this branch; focused software checks and limits are recorded below. No reservation or deletion. |
| STOR-02 | Register host/volume roots, artifact ownership and capacity policy | Pending. Stable identity, canonical boundaries, protected roots, no implicit enrollment of legacy data; validate native Windows paths and mount changes. |
| STOR-03 | Atomic capacity admission for all cooperating writers | Pending. Concurrent request fixtures cannot spend the same headroom; persistence failure refuses new work. Include preparation and staging peaks. |
| STOR-04 | Separate process teardown, retention and payload removal state | Pending. Preserve existing `cleanup` semantics, verified evidence handoff, unknown-claim quarantine and request recovery. |
| STOR-05 | Idempotent eligible-payload finalizer and startup/scheduled sweep | Pending. Exact-root validation, dry-run explanation, no-follow deletion, interrupted-delete recovery and no deletion of protected work. |
| STOR-06 | Remote collection acknowledgement and transport-payload retirement | Pending. Lost/duplicate acknowledgements and retries preserve verified evidence, immutable inputs and live references. |
| STOR-07 | Managed authoring-worktree and cache integration | Pending. Covers supported creation paths and reports bypasses; native cache tools retain live entries; no mutable hard-link snapshots. |
| STOR-08 | Measure Windows placement, copy-on-write and cache economics | Pending. Physical allocation, independent writes, cold/warm performance, import/output peaks and actual C:/D: backing identified. |
| STOR-09 | Backup/restore and gradual operational rollout | Pending. Restore unique inputs from an independent target; compare dry-run candidates, then enable only qualified managed roots and measure residual growth. |

## Capacity model

One host authority should coordinate storage promises for every managed writer,
including snapshots prepared before test submission. A `Get free space → copy`
sequence in each agent is racy even if each agent behaves correctly alone.
Register the actual volume and backing dependency; two roots on one volume do
not provide two independent budgets. For virtual disks also account for the
host volume that stores the backing file.

At allocation, while holding the authority's transaction/serialization boundary,
observe free space and evaluate:

```text
new_peak_growth <= observed_free - protected_floor - outstanding_future_growth
```

The new diagnostic accepts those quantities explicitly but performs no
transaction, ledger write or reservation. Its `reserved_bytes` input means
future commitments not already counted in observed volume use.

The controller must define a conservative upper bound for each workload's
remaining growth: source/materialization, archive and extraction overlap,
engine copies, imports, temporary files, logs, captures and exports. Until
remaining-growth accounting is qualified, a controller may apply an additional
guard that charges every live allocation's full initial budget. That deliberately
over-reserves as files are written and must be labeled a full-budget safety
allowance, separately from remaining growth. It is not the diagnostic's
`reserved_bytes` input: do not feed already-consumed allocation sizes into that
field. Do not subtract logical file sizes and call the result a precise physical
measurement. Any refined accounting method needs its own qualification.

Persist the reservation and artifact identity before materialization. If the
ledger cannot commit, do not start the copy. Recheck free space before each
major phase, because unrelated processes can consume it. A configured floor
must protect controller/database/temp headroom as well as the OS. A low-space
event stops new allocations and requests owned-job cancellation through the
existing queue if necessary; it does not authorize deleting unknown data.

Define overrun behavior explicitly. Cooperative estimates are not hard filesystem
quotas; native quota/VHD controls are optional additional layers after their
scope is qualified. Never advertise this model as protection against arbitrary
unmanaged writers. Retained failures, pending deletion and internal trash stay
accounted for. Release promises only after verifying the outcome and transferring
any retained payload to an explicit bounded retention allocation.

## Ownership records and lifecycle

The future schema needs a run/artifact identity, parent run and owner, host and
volume identity, registered root, relative path, creation purpose, content/input
identity where applicable, budget, lifecycle state, references, retention reason
and cleanup result. A supplied path or marker file alone is not trusted
ownership proof. Queue control state and recovery receipts live outside any
bulk payload tree eligible for removal.

Keep process state independent of storage state. A possible storage sequence is
`ALLOCATED → MATERIALIZING → IN_USE → RETAINED/ELIGIBLE → REMOVING → REMOVED`;
failures remain visible and recoverable. `UNKNOWN` process ownership prevents
progress to eligible storage, even when a retention deadline has passed.
Use the current verified-reboot reconciliation for uncertain process attempts;
do not replace it with TTL expiry or PID inspection.

Before declaring an artifact eligible, establish all of the following:

1. Its exact path is inside an enrolled disposable root on the recorded host
   and volume, with no escaping links/reparse points or identity change.
2. All writers and readers are covered by verified lifecycle state; no active,
   unknown, locked or pinned reference remains.
3. Unique source, dirty/untracked/ignored work and required evidence have an
   explicit retained home or verified handoff. Git cleanliness alone is insufficient.
4. Remote collection, if required, has a durable checksum-verified acknowledgement.
5. Retention policy permits removal, and cleanup intent can be persisted.

Record intent before deleting. Verify path identity immediately before acting;
the future deleting implementation needs a stronger platform-qualified no-follow
boundary than the present read-only scanner. Recover missing/already removed
paths idempotently, without dropping the request/attempt identity needed by
existing recovery APIs. A rename into quarantine or trash is still retained
storage. Do not create a full backup copy merely to delete a disposable copy.

## Integration sequence

1. Register and inventory one explicitly chosen local disposable root. Existing
   folders remain unowned candidates until reviewed. Preserve references,
   user data, tools, authored assets, registered worktrees and accepted evidence.
2. Connect capacity admission to `Pool.snapshot`, local preparation and remote
   acceptance before changing parallelism. Budget creation can precede dispatch,
   so test-queue slot ownership by itself is insufficient.
3. Extend worker and remote outcomes with storage state while preserving current
   process `cleanup`, result verdicts, request IDs and recovery receipts.
4. Add verified collection acknowledgement before retiring remote archives or
   per-job payloads. Digest-keyed shared inputs retain reference protection.
5. Run the same bounded finalizer at normal completion and during reconciliation.
   A later Windows Task Scheduler or Linux service invokes this controller;
   no standalone blanket directory-deletion task is introduced.
6. Integrate coding worktree tools and qualified cache managers. Measure results
   before enabling optional copy-on-write or relocating installations.

Disk Steward remains an on-demand audit/review role. The lead agent owns closure
of delegated storage and records unresolved retention in the existing handoff.
Routine counting, admission and cleanup belong to deterministic code. Avoid a
permanent LLM loop that repeatedly scans drives or decides deletion from names.

## Required failure and native qualification matrix

| Boundary | Acceptance evidence before automatic cleanup |
| --- | --- |
| Concurrent allocation | Several simultaneous requests cannot collectively exceed the admitted budget; roots sharing a volume share a ledger. |
| Source protection | Dirty, untracked, ignored, pinned, referenced and offline worktrees remain protected; external deliveries are never inferred disposable. |
| Process uncertainty | Supervisor crash, lost handle, stale heartbeat and reused PID retain claims; only existing verified reconciliation releases uncertainty. |
| Filesystem identity | Windows junction/reparse, case aliases, mount/volume replacement and link-swap attempts cannot redirect deletion; qualify native Windows separately from POSIX. |
| Storage exhaustion | Full metadata/temp volume and failed transaction prevent allocation; failures at each deletion-journal step recover without losing ownership. |
| Remote handoff | Lost acknowledgement, repeated collection, partial transfer and corrupted artifact retain recoverable payload and never erase the sole valid evidence. |
| Crash during removal | Restart resumes only recorded eligible work; failed/busy removal remains charged and visible; already removed paths settle safely. |
| Shared payloads/caches | A final live reference prevents eviction; another job's inputs and writable environment remain intact. |
| Measurement | Logical size, actual allocation, host/guest free space and reclaimed-space observations are labeled separately. |
| Backup | Selected unique source/inputs can be restored and verified from a target independent of the working disk. |

## Validation record

Focused checks on Linux, 2026-11-15:

| Check | Result |
| --- | --- |
| `python -B -m unittest tools.testqueue.test_storage -v` | 22 tests: 21 passed; native Windows junction fixture skipped. |
| `python -B -m unittest discover -s tools/godot -p 'test_storage_audit.py' -v` | 17 tests: 16 passed; native Windows junction fixture skipped. The existing case-exclusion contract was updated for deliberate all-platform `.git` case folding. |
| Existing CLI receipt recovery/cancel, exact resubmit recovery and missing-request receipt reuse contracts | 3 passed; no unrelated queue/process suite was run. |
| New documentation targets, ledger structure and whitespace | New relative links resolve in the materialized review files; R01–R24 are unique, 54 distinct web source links are retained, and options 1–32 are present. `git diff --check` and new-file whitespace checks passed. |

The three existing contracts are
`ContractFixture.test_cli_receipt_recovery_and_cancel_do_not_create_jobs`,
`ContractFixture.test_cli_resubmit_recovers_without_reopening_snapshot` and
`ContractFixture.test_cli_resubmit_missing_request_reuses_exact_receipt` in
`tools.testqueue.test_contracts`. These are **40 passing checks and two native
Windows skips**, not a Windows qualification or full-repository CI result.

Native Windows execution, case-insensitive APFS, live C:/D: capacity, automatic
admission, remote acknowledgement and destructive cleanup remain unqualified.
The new boundary fixtures include stream/device-name rejection, overlapping
roots, observed reparse points, partial scans, capacity failure and exclusive
outputs. No full Godot run was performed for this read-only CLI addition; it
does not alter the simulation or launch game tests.

Independent review identified a Windows separator-normalization bug in the
reused scanner and requested explicit treatment of path-replacement races,
partial multi-root results and Python bytecode output. Corrections and their
fixtures are part of this branch. The supported inspection commands use
`python -B` to suppress interpreter bytecode caches. Scans remain cooperative,
non-atomic observations of trusted, stable local roots; they are not a
hostile-filesystem security boundary or a hard wall-clock deadline.

After the remaining controller work is qualified, compare representative
parallel runs using peak physical allocation, retained bytes after completion,
cleanup latency/failure count, cache hit rate, rebuild time and bytes written.
Do not report zero leftovers by deleting the evidence needed to explain a
failed run.

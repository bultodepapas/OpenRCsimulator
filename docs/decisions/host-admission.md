# Shared host admission

Scope: the decisions, alternatives and evidence behind shared host admission. These records retain the context of each choice; linked guides and the [current roadmap](../../ROADMAP.md) own implemented behavior and remaining work. [Decision index](../DECISIONS.md).

## Keep host admission outside worktrees and retain uncertain claims

**TQ-00/TQ-01, experimental local implementation.** Use one host-local authority,
durable attempts and Windows Job supervision above existing port/capture locks.
Reservations follow verified process-tree teardown. A lost worker retains claims as
UNKNOWN; heartbeat loss and launcher exit never establish cleanup. Owner capabilities
also gate existing CLI/MCP controls. See the [operating contract](../../tools/testqueue/README.md).

The initial combined worker uses Python's SQLite locally to avoid adding an otherwise
unused controller/service/plugin deployment to the developer desktop. This is a
provisional deployment choice, not evidence that existing queues lack these features:
[Jenkins Lockable Resources](https://plugins.jenkins.io/lockable-resources/) supports
remote resource clients and stale leases. Local inventory found Java and a Docker CLI,
but no running Jenkins installation. A live Jenkins contention/restart/disconnect
comparison remains a TQ-00 gate. OpenRC still needs snapshots, ownership and worker
containment with either backend; do not build a generic backend framework meanwhile.
[SQLite WAL](https://www.sqlite.org/wal.html) requires same-host access, so remote
workers must use structured transport rather than share this database.

**TQ-04 resilience direction, 2026-11-15; partial implementation under review.** The
[resilience audit](../research/testqueue/2026-11-15-resilience/README.md) reproduces
avoidable nonlaunch quarantine, dead-scheduler readiness, pre-receipt recovery
gaps and falsely confirmed nonexecution during local replay. The
[repair subplan](../plans/mcp-queue-resilience.md) keeps the existing authority
and proof-based release contract, separates observation/progress deadlines from
explicit owned cancellation, and gates higher concurrency on physical-host and
resource reservations. Repair these failures before expanding the pool; a new
queue backend is not a prerequisite. Independent guardians and remote cancel are
proposed work, not capabilities of the current combined worker.

The [implementation handoff](../research/testqueue/2026-11-15-resilience/implementation.md)
records the candidate repairs and their negative controls. Keep typed nonlaunch
proof, pending journal fences, identity-first recovery and conservative version-2
batch migration. Bounded MCP output delivery may lose replies; it must not block
accepted work or admit new actions after delivery is abandoned. Preserve the
concurrent upstream operator-abandonment exception as explicit incomplete evidence;
automatic recovery must never use it or bypass pending journal fences. Fleet
capacity and native qualification have not changed.

**TQ-04-R8, narrow storage candidate.** Reclaim a redundant successful remote
input copy only after verifying and pinning the original archive and journaling
intent; record storage uncertainty separately from process cleanup. Remove failed
coordinator temporaries only when owned by that invocation. A terminal state or
file age cannot establish nonuse: source trees can hold capture evidence, abandoned
attempts can retain unconfirmed cleanup, and shared archives can have readers.
Broader retention waits for explicit evidence ownership and reader lifetimes in
the [same repair plan](../plans/mcp-queue-resilience.md#storage-cleanup-and-retention-acceptance).

**TQ-04-R8 collection, 2026-11-16; review candidate.** Publish isolated, immutable
evidence generations bound to the original request and finished status, with an
explicit collection format and verified reuse. An interrupted copy must not
overwrite the files behind an earlier passing report. Reobserve/recollect older
unverified batch results under the same execution identity and preserve their
history. Local control files are excluded, diagnostic-only results cannot pass,
and collection does not grant authority to delete a workspace. The selected
checked-evidence contract is intentionally narrower than a complete per-preset
artifact inventory; broaden retention only after the ownership, reader-lifetime
and native durability gates in the [handoff](../research/testqueue/2026-11-15-resilience/implementation.md#16-november-re-audit-of-current-main-and-the-review-branch).

**TQ-04-R8 / TQ-05-F0.7, reproducible remote inputs, 2026-11-25.** A remote checked job
that finished with confirmed cleanup may lose, after the coordinator re-verifies its
collected evidence, only bytes it can regenerate: archive copies, Godot's import
cache, Python bytecode and source files whose size and SHA-256 match the job's own
verified inventory. Files the run wrote or changed stay as reported residue, which
answers the capture-evidence concern above; `UNKNOWN`, unconfirmed and
operator-reconciled jobs are never touched. Placement may run this, time-bounded, for
a host it refuses for disk; a remote `run` refused `BUSY` meanwhile wrote no job and
is deferred under the same ID. Retained failures
had filled the Linux host (24 of 25 GB) while rows waited on disk for hours. Local
`retention.py` already removes whole failed checked sources (TQ-05-F0.1).

**TQ-04-R1, explicit local refusals, 2026-11-25.** An explicit refusal from the
local authority is settled by that authority's durable submission tombstone after
`recover` shows no acceptance; it is not inferred from the reply. Transport
failures stay uncertain, and a refused replay waits ten minutes so a late original
can still be found. A transient error reply therefore ends the row `REJECTED`
(relaunch) rather than reserving the host. An acceptance landing between `recover`
and `cancel_submission` is canceled, never duplicated; an atomic tombstone-if-absent
operation would remove that window. Checked submissions no longer require the frozen
worktree to exist; history presets still do.

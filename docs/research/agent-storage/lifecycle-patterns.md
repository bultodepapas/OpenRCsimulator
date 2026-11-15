# Agent storage: lifecycle and failure investigations

Checked **2026-11-15**. R17–R24 complete the 24-question investigation set.
These are source findings and design inputs, not measurements of the user's
C: or D: drives. The [synthesis](README.md) ranks the options; the
[execution plan](../../plans/agent-storage-lifecycle.md) owns pending work.

## R17 — Worktrunk cleanup completion and internal trash

**Question:** What can a worktree manager teach us about successful removal?

**Exact query:** `site:worktrunk.dev remove worktrees hook background cleanup preserve ignored files`.

**Evidence:** Worktrunk's [remove documentation](https://worktrunk.dev/remove/)
describes background deletion by default and a foreground option that waits
for completion. Its force-removal backup excludes ignored files and submodules.
The [FAQ](https://worktrunk.dev/faq/) describes an internal trash location used
during removal; the [hook reference](https://worktrunk.dev/hook/) distinguishes
blocking pre-hooks from background post-hooks. These are project-documented
behaviors, not an audit of every failure path.

**Finding and limit:** A command returning or a directory moving into trash
does not establish that its storage was released. Git cleanliness cannot prove
that ignored files are expendable. Worktrunk's experimental process reaping is
not equivalent to OpenRC's durable process ownership and teardown evidence.

**OpenRC idea:** Expose pending, failed and verified payload removal, including
bounded retries and residual paths. Count internal trash and failed staging
against the storage budget. Keep any future worktree integration behind the
project's existing ownership checks; do not adopt force removal, branch deletion
or process termination based on working-directory matches as defaults.

## R18 — Shared Git objects and backup independence

**Question:** Does a cheap local clone remain independent when its source is cleaned?

**Exact query:** `site:git-scm.com/docs/git-clone shared alternates corrupt source repository prune hardlinks`.

**Evidence:** The official [git-clone manual](https://git-scm.com/docs/git-clone)
warns that clones using shared object alternates can become corrupt when
needed objects are removed from the source repository. `--reference` can also
borrow objects; `--dissociate` copies borrowed objects to break that dependency.
The manual also warns about races while cloning a changing local source and
documents `--no-hardlinks` for independent local object copies.

**Finding and limit:** Sharing Git objects is useful, but object retention is
part of the dependency contract. A second directory on the same disk is not an
independent backup. These Git mechanisms do not deduplicate every checked-out
asset, generated import or build output.

**OpenRC idea:** Prefer managed worktrees for isolated authoring where their
shared repository semantics fit. Keep history-dependent test presets intact
until their exact requirements are qualified. If an object pool is introduced,
retain referenced objects explicitly or dissociate consumers before pruning.
Back up irreplaceable work to an independent target with a tested restore path;
do not count borrowed Git storage or local snapshot copies as that backup.

## R19 — Godot caches, logs and version-specific incidents

**Question:** Which game-development outputs can grow, and what does deleting
them cost?

**Exact query:** `site:github.com/godotengine/godot/issues .godot cache disk space growing imported shader cache`.

**Evidence:** In [issue #73174](https://github.com/godotengine/godot/issues/73174),
opened 2023-02-12 and still open when checked, a Godot 4.0 RC1 user reported
approximately 700 MB of shader cache. Discussion explains hardware/driver
dependencies and regeneration costs. In [issue #109333](https://github.com/godotengine/godot/issues/109333),
opened 2025-08-05, a Godot 4.5 beta user reported excessive repeated headless
progress output; it was closed as completed on 2025-08-07 through a linked fix.
The [import guide](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/import_process.html)
describes generated resources under `.godot/imported`.

**Finding and limit:** Neither older report proves a current defect in OpenRC's
pinned Godot 4.8 beta. Regeneration can trade freed space for repeated writes,
imports and shader stutter. The entire `.godot` tree is not one interchangeable
cache, and source-side import configuration has a different retention role.

**OpenRC idea:** Measure cold and warm runs; retain useful bounded caches with
appropriate engine/platform/rendering identities. Keep writable per-attempt
imports isolated. Bound diagnostic logs through the existing runner, preserving
failure evidence instead of suppressing errors or clearing all caches after
every task.

## R20 — Content-addressed caches and idle garbage collection

**Question:** Can build-system cache policies provide a useful design without
changing OpenRC's build system?

**Exact query:** `site:bazel.build disk cache garbage collection max size max age concurrent`.

**Evidence:** Bazel's [versioned 7.4 remote-cache guide](https://bazel.build/versions/7.4.0/remote/caching)
documents disk-cache garbage collection using maximum-size and maximum-age
settings, performed while the server is idle. The flags are experimental in
that documented version. Its cache design uses action results and a
content-addressable store. This is an architectural example, not a proposed
Bazel dependency or a claim about the current OpenRC toolchain.

**Finding and limit:** Deduplicating immutable content and retiring unused
entries can reduce repetition. Idle collection is not a reservation for a
concurrent writer, and a bounded central cache does not automatically bound
per-job extraction, temporary packaging or exported results.

**OpenRC idea:** Extend the existing digest-keyed transfer reuse before adding
another cache service. Account for the canonical payload, staging archive and
each writable materialization separately. Publish immutable entries only after
hash verification and prevent their eviction while referenced. Couple age and
size policies to the future host admission ledger, rather than assuming a
cache's own cleanup target guarantees free disk space for every job.

## R21 — Age-based cleanup and participating locks

**Question:** Can operating-system temporary-file cleanup safely replace job ownership?

**Exact query:** `site:freedesktop.org software systemd man latest tmpfiles.d age cleanup BSD locks`.

**Evidence:** The official [tmpfiles.d reference](https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html)
defines age-based cleanup rules and mechanisms for cooperating applications to
protect active directories through BSD locks. [systemd-tmpfiles](https://www.freedesktop.org/software/systemd/man/latest/systemd-tmpfiles.html)
applies those rules. File-age interpretation and lock participation are
mechanisms with explicit scope, not a general proof that a process has ended.

**Finding and limit:** An old directory can still belong to a live or
unreconciled job. A process that does not participate in the expected locking
protocol is not protected by that protocol. OpenRC's `UNKNOWN` attempts must
retain their claims under the existing conservative reconciliation contract.

**OpenRC idea:** Have the scheduler invoke the project-owned controller, with
eligibility revalidated at deletion. Consider native tmpfiles only after a
durable, non-reusable quarantine and cooperating lock protocol can prevent a
previously eligible directory from acquiring new users; otherwise keep it
advisory. Never apply a generic age rule to source worktrees, queue journals,
references or unknown attempts. Task-finalization cleanup and a later orphan
sweep serve different failure cases; both need the same eligibility rules and
an idempotent implementation.

## R22 — Process trees and filesystem cleanup

**Question:** Does terminating an agent establish that all its children and
temporary files are gone?

**Exact query:** `site:learn.microsoft.com Windows job objects kill on job close child processes cleanup`.

**Evidence:** Microsoft's [Job Objects guide](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
documents process association, inherited membership and exceptions such as
breakaway behavior or some brokered launches. Kill-on-close applies when the
last relevant Job handle closes. The [process termination guide](https://learn.microsoft.com/en-us/windows/win32/procthread/terminating-a-process)
states that terminating a process does not automatically terminate its children.

**Finding and limit:** The visible agent process ending is insufficient
evidence for deleting its workspace. Even verified process-tree teardown says
nothing about whether the files were retained, exported or removed. Platform
APIs also have limits that must remain reflected in OpenRC's supported launch
boundary.

**OpenRC idea:** Preserve the existing queue's owned-process observation and
reboot-based recovery of uncertain attempts. Add separate payload retention
and removal state after teardown, rather than changing the meaning of
`cleanup="CONFIRMED"`. A timeout, absent PID, quiet heartbeat or closed chat
session must not authorize deletion. The future storage sweeper consumes
verified lifecycle state; it does not invent new process-ownership evidence.

## R23 — Cleanup metadata when the disk is already full

**Question:** What happens if a controller cannot record its cleanup decision?

**Exact query:** `site:sqlite.org disk full SQLITE_FULL transaction rollback journal WAL disk space`.

**Evidence:** SQLite's [transaction reference](https://www.sqlite.org/lang_transaction.html)
explains that errors including `SQLITE_FULL` can roll back a statement or an
entire transaction. Its [result-code reference](https://www.sqlite.org/rescode.html)
notes that a full temporary-file volume can cause the error even when the
main database's volume has space. [Journal-size controls](https://sqlite.org/pragma.html)
are maintenance controls, not an application storage reservation.

**Finding and limit:** A cleaner may need free space to preserve durable
intent, journal changes and recovery evidence before it can free bulk data.
Changing journal durability or deleting database files to get past this
failure would undermine ownership recovery. The cited behavior is a failure
mode to test, not a claim that OpenRC has already encountered it.

**OpenRC idea:** Reserve small protected metadata headroom and refuse new
allocations if ownership cannot be persisted. Record deletion intent, perform
the eligible removal, verify the result and then record completion. Recover
every interruption point idempotently; retain unresolved state on persistence
failure. Inject full-disk and lost-write failures before enabling automatic
cleanup on real hosts.

## R24 — Storage requests, limits and observation gaps

**Question:** How do mature schedulers distinguish promised capacity from observed usage?

**Exact query:** `site:kubernetes.io docs ephemeral storage requests limits emptyDir eviction deleted files open`.

**Evidence:** Kubernetes' [ephemeral-storage guide](https://kubernetes.io/docs/concepts/storage/ephemeral-storage/)
describes requests, limits, writable layers, logs and temporary volumes. It
also documents an accounting gap in directory-scan mode: deleted files still
held open can consume disk without appearing in the scan. The
[quota reference](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
distinguishes admission quotas from node-wide physical constraints.

**Finding and limit:** A directory total and a scheduler's promises answer
different questions. Other writers, shared blocks, open files and unsupported
storage layouts can make naive subtraction misleading. Eviction after a
threshold is exceeded is not the same as reserving space before a copy starts.

**OpenRC idea:** Borrow the separation of requested peak growth, observed
volume free space and configured limits. Use one serialized ledger per host
and physical storage dependency, with reservations for all concurrent tasks.
Include snapshots, staging, imports, logs, exports and failed deletion in the
accounting model. Recheck actual free space at allocation boundaries; do not
sum repeated volume observations. This is a design pattern, not a proposal to
install Kubernetes for a desktop simulator.

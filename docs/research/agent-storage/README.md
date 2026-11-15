# Agent storage research and recommendations

**Research date:** 2026-11-15. **Repository baseline:**
`e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`.

**Recommendation:** Give every agent-created workspace a bounded lifecycle,
and enforce that lifecycle through the existing host/test infrastructure.
Use concise agent rules and the Disk Steward role to support it. A second AI
agent watching folders is useful for review, but is not a reliable replacement
for durable ownership, capacity reservations and verified cleanup.

This expansion contains **24 distinct internet investigations** and evaluates
**32 options** below. It combines current official documentation, firsthand
incident reports and inspection of the pinned repository. No live C:, D: or
remote-host inventory was available; no recovered-space total, drive capacity,
filesystem, cache hit rate or hardware qualification is claimed.

The [operating guide](../../../tools/testqueue/README.md#storage-inspection)
owns the new inspection commands. The
[storage lifecycle plan](../../plans/agent-storage-lifecycle.md) owns implementation
status and acceptance. This document preserves the evidence and reasoning.

## What the repository already does, and where storage accumulates

| Observed at the baseline | Practical implication | Source |
| --- | --- | --- |
| A bounded, read-only logical-size scanner already exists. | Reuse and improve it; do not add a competing recursive scanner. | [`storage_audit.py`](../../../tools/godot/storage_audit.py) |
| Every `Pool.snapshot()` call uses a fresh UUID directory. | Repeated launches can retain multiple snapshots of similar inputs. | [`pool.py`](../../../tools/testqueue/pool.py), `snapshot` |
| The local worker copies frozen source into each attempt; some presets copy engine binaries and history. | A worktree alone cannot replace the current qualified isolation contract. | [`worker.py`](../../../tools/testqueue/worker.py), attempt preparation |
| Transfer archives are already reused by source digest; each remote attempt still copies `input.tar` and extracts its own source. | Improve existing transfer reuse before introducing another central cache. Count both archive and extraction. | [`pool.py`](../../../tools/testqueue/pool.py), [`remote_agent.py`](../../../tools/testqueue/remote_agent.py) |
| Source-copy/materialization checks look for 512 MiB of observed headroom beyond estimated input size. | These checks do not reserve that space or provide atomic host-wide admission for parallel jobs and future imports/exports. | [`snapshots.py`](../../../tools/testqueue/snapshots.py), [`worker.py`](../../../tools/testqueue/worker.py), [`remote_agent.py`](../../../tools/testqueue/remote_agent.py) |
| `cleanup="CONFIRMED"` records process teardown. The reviewed completion/collection paths do not remove their retained payloads. | Add a separate storage outcome; do not reinterpret existing process evidence. This finding is scoped to the reviewed paths. | [Recovery contract](../../../tools/testqueue/README.md#recovery-and-evidence), [`Pool.collect`](../../../tools/testqueue/pool.py) |
| Uncertain attempts retain claims; reconciliation requires proof that the same host rebooted. | Age, missing heartbeats and an absent PID cannot authorize cleanup. | [Recovery contract](../../../tools/testqueue/README.md#recovery-and-evidence) |
| Writable source, imports, profiles, temp and output are isolated. Snapshot verification rejects hard-linked files. | Preserve isolation and verification when evaluating space-saving copies. | [`snapshots.py`](../../../tools/testqueue/snapshots.py), snapshot verification |
| Ignored paths include references, tools, worktrees and generated results with different retention roles. | `.gitignore`, a `tmp` name or a clean Git status is not deletion authority. | [Tool rules](../../TOOLS.md#developer-setup), [`.gitignore`](../../../.gitignore) |

These are code and contract observations, not a measured attribution of the
user's disk consumption. The first host inventory must confirm which categories
actually dominate before choosing an optimization.

## Investigation ledger

Each linked document records exact search queries, sources, evidence status,
limitations and an OpenRC recommendation. A query with supporting follow-up
searches counts as one investigation, not several. Issue reports describe the
reporter's environment; they are not a prevalence estimate or proof of a
current universal defect.

| ID | Question / evidence theme | Record |
| --- | --- | --- |
| R01 | Claude orphaned subagent worktrees versus current automatic cleanup | [Agent workspaces](agent-workspaces.md) |
| R02 | Worktree hooks that do not cover every creation/removal path | [Agent workspaces](agent-workspaces.md) |
| R03 | Codex shell-created worktrees and shared-allocation accounting | [Agent workspaces](agent-workspaces.md) |
| R04 | Deleted tasks and unregistered temporary copies | [Agent workspaces](agent-workspaces.md) |
| R05 | Cursor worktree limits and expensive cleanup scans | [Agent workspaces](agent-workspaces.md) |
| R06 | Git worktree removal, pruning and offline/locked worktrees | [Agent workspaces](agent-workspaces.md) |
| R07 | Standalone worktree garbage collectors and their safety scope | [Agent workspaces](agent-workspaces.md) |
| R08 | VS Code session/worktree cleanup and preview controls | [Agent workspaces](agent-workspaces.md) |
| R09 | Windows inventory tools and size interpretation | [Storage platforms](storage-platforms.md) |
| R10 | Dev Drive/ReFS block cloning versus mutable hard links | [Storage platforms](storage-platforms.md) |
| R11 | WSL guest deletion versus VHDX host allocation | [Storage platforms](storage-platforms.md) |
| R12 | BuildKit cache GC and full-disk incidents | [Storage platforms](storage-platforms.md) |
| R13 | Tool-managed package caches and concurrent environments | [Storage platforms](storage-platforms.md) |
| R14 | Bounded compiler caches and when they apply | [Storage platforms](storage-platforms.md) |
| R15 | Deduplicating backups, retention and pruning headroom | [Storage platforms](storage-platforms.md) |
| R16 | NTFS/FSRM/VHD limits and their actual enforcement scope | [Storage platforms](storage-platforms.md) |
| R17 | Worktrunk background removal and internal trash | [Lifecycle patterns](lifecycle-patterns.md) |
| R18 | Git alternates, shared objects and independent backups | [Lifecycle patterns](lifecycle-patterns.md) |
| R19 | Godot cache costs and version-specific log growth | [Lifecycle patterns](lifecycle-patterns.md) |
| R20 | Content-addressed caches and idle garbage collection | [Lifecycle patterns](lifecycle-patterns.md) |
| R21 | Native age cleanup and participating locks | [Lifecycle patterns](lifecycle-patterns.md) |
| R22 | Windows process containment versus file removal | [Lifecycle patterns](lifecycle-patterns.md) |
| R23 | Full-disk failure while persisting cleanup state | [Lifecycle patterns](lifecycle-patterns.md) |
| R24 | Storage requests, limits and observation gaps | [Lifecycle patterns](lifecycle-patterns.md) |

## Options evaluated

**Adopt** means recommended design or policy, not a claim that the controller
already exists. **Pilot** needs measurements and native qualification.
**Conditional** applies only if that tool or storage layer is present.
The execution plan distinguishes delivered code from pending work.

| # | Option | Expected benefit and main limit | Decision / evidence |
| --- | --- | --- | --- |
| 1 | Short storage rules in `AGENTS.md` | Stops casual recursive copies; instructions alone cannot enforce quotas or survive a crash. | Adopt; R01–04 |
| 2 | Storage ownership in every subagent brief | Makes creator, root, expected growth and handoff explicit. Parent remains responsible after child exit. | Adopt; R02, R22 |
| 3 | Disk Steward review role | Useful for diagnosis and retention decisions; avoid a permanently polling LLM with unrestricted deletion. | Adopt on demand; R05, R24 |
| 4 | Bounded read-only inventory | Identifies categories and incomplete scans without generating another mandatory report file. | Adopt first; R05, R09 |
| 5 | One managed disposable root per host/volume | Limits cleanup scope and makes leftovers attributable. Legacy directories require review before enrollment. | Adopt; R01–04 |
| 6 | Prefer D: for qualified bulk scratch, preserve C: headroom | Keeps bulky outputs away from the system volume when suitable. Moving data does not cap growth or guarantee a separate physical disk. | Adopt configurable placement; R09–11 |
| 7 | Atomic host-wide capacity reservations | Prevents several agents independently spending the same free space. External writers still require monitoring. | Highest-priority controller work; R12, R24 |
| 8 | Per-run peak and retained-byte budgets | Covers imports, exports, logs and staging, not only source size. Needs measured workload classes and overrun handling. | Adopt; R19, R23–24 |
| 9 | Deterministic finalizer with separate disk state | Frees eligible payloads at completion and records failure. A killed supervisor can miss finalization. | Adopt with reconciliation; R02, R04, R22 |
| 10 | Periodic/startup orphan reconciliation | Recovers missed finalizers using durable ownership. Age is a retention filter only after eligibility is proven. | Adopt after controller qualification; R21–23 |
| 11 | Size-and-age bounded reusable caches | Preserves useful warm data while preventing indefinite growth. Active entries need leases/reference protection. | Adopt per tool; R12–14, R20 |
| 12 | Managed Git worktrees for coding | Shares repository objects and gives branches separate working files; imports and binaries can still multiply. | Adopt where appropriate; R06, R18 |
| 13 | Worktree lifecycle wrappers/hooks | Records supported creation paths; shell bypasses and failure paths require reconciliation. | Adopt as integration, not sole authority; R01–02 |
| 14 | Worktrunk or `wtgc` as operator tools | Existing free tools provide inventory/removal workflows. Their force/trash/process rules are not OpenRC's queue contract. | Pilot advisory integration; R07, R17 |
| 15 | Reuse frozen inputs by content digest | Avoids identical snapshots; dirty bytes, manifests, platform inputs and live references must all participate in identity. | Extend existing reuse carefully; R20, repo audit |
| 16 | Retire redundant transport archives after acknowledgement | Removes `input.tar` and staging duplication when no longer needed for recovery. Lost acknowledgements must retain ownership. | Adopt future protocol; R04, R20 |
| 17 | Copy-on-write materialization on supported volumes | Can make isolated copies cheap initially; later writes grow them. Native API, allocation and independent-write tests required. | Pilot ReFS/APFS/Btrfs as applicable; R03, R10 |
| 18 | Hard-link mutable game files between agents | Saves file bytes but shares in-place writes and conflicts with current snapshot checks. | Reject for mutable snapshots; R10, repo audit |
| 19 | Shared pinned engine/template installations | Avoids repeated tool downloads/copies where identity and immutability can be guaranteed. Some presets require isolated copies. | Pilot with existing pin verification; repo audit |
| 20 | Shared package-download caches, separate environments | Reuses immutable packages while retaining per-task dependencies and locks. Use each tool's own cleanup command. | Conditional; R13 |
| 21 | `sccache` or `ccache` for native builds | Reduces repeated compilation and bounded outputs; no benefit for work that never compiles native code. | Conditional, benchmark hit rate; R14 |
| 22 | Selective Godot import/shader cache retention | Reduces repeated writes and cold-start cost; engine/renderer/driver compatibility and writable isolation matter. | Measure before changing; R19 |
| 23 | Bounded logs, captures and failed-run evidence | Prevents incidental output from dominating storage while preserving diagnostics and accepted proof. | Extend existing caps/retention; R19 |
| 24 | Native NTFS user quotas or Server FSRM quotas | Can add enforcement, but their user/volume/filesystem/OS scope may not match agent folders. | Conditional; R16 |
| 25 | Dedicated bounded VHD for disposable data | Adds a ceiling and an isolation boundary; dynamic maximum does not reserve physical host space. | Pilot only if simpler budgets are insufficient; R16 |
| 26 | BuildKit GC and managed container cache limits | Uses the owning tool's accounting and retention. Periodic GC is not host-wide admission. | Conditional; R12 |
| 27 | WSL/Docker virtual-disk reclamation | Can return released guest space to the host when supported. Requires layer-specific checks and operator maintenance. | Conditional; R11–12 |
| 28 | Deduplicating incremental backups to an independent target | Protects irreplaceable work without a full game copy per task. Restore tests and pruning reserve remain essential. | Adopt backup design; R15, R18 |
| 29 | Separate backup retention from cache retention | Prevents backing up reproducible copies and deleting unique ignored inputs as if they were caches. | Adopt; R09, R15, R19 |
| 30 | Sparse authoring checkouts / partial Git clones | Can reduce selected source/history downloads; not every test, asset pipeline or history preset supports them. | Pilot only for narrow authoring tasks; [Git sparse-checkout](https://git-scm.com/docs/git-sparse-checkout), [clone](https://git-scm.com/docs/git-clone) |
| 31 | Protected metadata reserve and recoverable deletion journal | Lets the controller record intent and recover even near capacity. Must handle persistence failure before admitting more work. | Adopt; R23 |
| 32 | Count/byte/age dashboards and cleanup receipts | Makes active, retained, pending and failed storage visible; a scan itself must be bounded and low frequency. | Adopt compact existing-state views; R04–05, R17, R24 |

## Decisions changed by the expanded research

1. **Reuse current product cleanup, but account for its scope.** Claude, Cursor
   and VS Code now document cleanup features. Their presence does not establish
   ownership of OpenRC's shell-created copies, frozen snapshots or remote payloads.
   Enable suitable native features after reviewing their policies; integrate
   their result rather than creating another unbounded worktree directory.
2. **A cleanup request needs a visible outcome.** Background deletion, internal
   trash and a closed task can all precede actual removal. Track residual bytes
   and pending/failed state until verification succeeds. Do not report logical
   folder size as physically reclaimed space.
3. **The cleaner must remain small.** Bound inventory by roots, entries, time
   and depth; scan known roots rather than every drive at each agent launch.
   Use existing metadata and tool-native cache indexes where appropriate.
4. **Prevent full disks before trying to repair them.** Serialize capacity
   decisions, include archive/extraction peaks and reserve metadata headroom.
   Periodic garbage collection alone cannot stop simultaneous copies from
   exhausting a volume between sweeps.
5. **Keep valuable caches when they pay for themselves.** Compare warm/cold
   elapsed time, peak allocation and bytes written. Deleting every cache after
   every task can replace storage pressure with repeated writes and imports.
6. **Protect unique work outside Git.** References, authored assets, user
   settings, accepted evidence and untracked/ignored work require explicit
   retention or a verified handoff. A copy-on-write clone or second partition
   on one physical disk does not provide an independent backup.

## Initial placement and retention design

Use C: and D: as configurable locations, not hard-coded assumptions. First map
volume identity, filesystem, free space and physical backing. A proposed layout
has a small durable controller/state area, a bulk disposable workspace area, a
bounded reusable-cache area and an independent backup target. These can be
separate directories on one eligible volume; they need not become new drives.
Prefer D: for bulk data when its capacity and performance support the workload.
Keep process-scoped temporary paths inside the owned attempt where the launcher
supports that; changing global Windows TEMP is not a prerequisite.

Successful disposable attempts should become eligible promptly after verified
teardown and evidence handoff. Failed attempts can retain bounded diagnostic
material for a configured period. Active, unknown, pinned, unique or unverified
payloads remain protected. Age applies to already eligible data; it never
manufactures ownership or process-teardown proof.

Back up canonical source, authoring inputs, irreplaceable ignored references,
configuration and accepted evidence. Exclude regenerable imports, transport
archives and redundant frozen copies only after confirming their regeneration
and ownership role. Use incremental deduplication and a measured retention
budget; verify a restore from the independent target before relying on it.
Keep backup pruning headroom separate from workspace admission. The detailed
restic tradeoffs and full-disk report are recorded in R15.

No fixed GiB threshold or retention duration is enabled by this branch. Measure
representative small checks, import-heavy checks and exports first; choose
per-volume floors and workload peaks from those observations. The goal is
bounded retained storage and preserved useful parallelism, rather than a claim
that any one percentage is safe for every C: or D: configuration.

## Evidence limits and validation home

The new command reports logical bytes of scanned regular-file paths and volume
free space separately. Hard links/shared blocks, open deleted files, excluded
metadata and incomplete scans prevent equating their difference with reclaimed
space. The budget command is an observation with explicit inputs; it does not
reserve or enforce capacity. Native Windows and case-insensitive macOS paths
remain separate qualification gates.

Implementation checks, independent review findings and remaining gates belong
in the [plan's validation record](../../plans/agent-storage-lifecycle.md#validation-record).
Do not create periodic committed cleanup reports or duplicate raw inventories
in this research directory.

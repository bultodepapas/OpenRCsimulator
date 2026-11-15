# Agent workspace storage investigations

Checked **2026-11-15**. These eight internet investigations examine worktree
growth, lifecycle hooks and cleanup tools. A firsthand report establishes what
its author observed in a particular environment; it does not establish that the
same behavior affects every current release. Product documentation describes
intended behavior, not proof that every implementation path succeeds.

The [research synthesis](README.md) connects these findings to the repository
audit. Proposed work and acceptance evidence belong in the
[agent storage lifecycle plan](../../plans/agent-storage-lifecycle.md).

## R01 — Claude subagent worktree growth

- **Question:** Can isolated subagent worktrees accumulate substantial storage,
  and how does the current documented cleanup policy compare?
- **Exact query:** `site:github.com/anthropics/claude-code/issues/63087 orphaned worktrees 80 GB`
- **Evidence and status:** A [firsthand issue](https://github.com/anthropics/claude-code/issues/63087),
  opened 2026-05-28 and closed as a duplicate, reported 27 orphaned worktrees
  using 80 GB. Current [Claude worktree documentation](https://code.claude.com/docs/en/worktrees)
  describes a periodic sweep of Claude-created subagent and background-session
  worktrees, with safeguards for retained work and an ownership marker.
- **Finding and limit:** The report is evidence of a historical symptom, not
  proof that current Claude releases lack a sweep. The documented sweep does
  not cover manually created worktrees or hook-created worktrees without the
  marker.
- **OpenRC idea:** Track ownership and lifecycle state for each snapshot and
  materialization. Inventory leftovers after interruption, while retaining
  unknown process attempts until the existing verified-reboot reconciliation
  resolves them.

## R02 — Worktree lifecycle hooks and missed paths

- **Question:** Are creation and removal hooks sufficient to account for every
  workspace and its cleanup?
- **Exact query:** `site:code.claude.com/docs/en/hooks "WorktreeRemove" "WorktreeCreate" hook`
- **Evidence and status:** The current [Claude hooks reference](https://code.claude.com/docs/en/hooks)
  states that `WorktreeCreate` does not run for a worktree created through Bash;
  when a subagent or workflow agent finishes, a worktree created by a custom
  creation hook is retained without running `WorktreeRemove`. A
  [firsthand issue](https://github.com/anthropics/claude-code/issues/78978),
  opened 2026-07-19 and closed as a duplicate, reported a missing removal hook
  on a particular interactive exit path in Claude Code 2.1.214.
- **Finding and limit:** The older report does not prove a current universal
  hook defect. The current documentation itself defines distinct paths with
  different hook coverage.
- **OpenRC idea:** Make cleanup idempotent and record its result durably;
  reconcile known artifacts after interruptions. Keep process teardown and disk
  removal as separate outcomes, and do not treat one callback as proof of both.

## R03 — Shell-created worktrees and parallel copies

- **Question:** How much can parallel agent-created checkouts grow, and what
  does their allocation measure mean?
- **Exact query:** `site:github.com/openai/codex/issues/58740 shell worktrees long running disk copies`
- **Evidence and status:** An [open firsthand report](https://github.com/openai/codex/issues/58740),
  opened 2026-11-01, traced 61 surviving paths to deduplicated Codex shell
  worktree-creation calls. Its earlier inventory across Codex and Claude found
  225 directories with approximately 324.47 GiB of Btrfs referred allocation.
  A separate [open request](https://github.com/openai/codex/issues/50528),
  opened 2026-10-03, reported checkout growth and proposed copy-on-write
  provisioning for supported filesystems.
- **Finding and limit:** The first report says its allocation is neither
  exclusive physical usage nor guaranteed reclaimable space. Its paths are not
  all abandoned or safe to remove; the copy-on-write observations are also
  user-reported and workload-dependent.
- **OpenRC idea:** Report job ownership and label logical, allocated and
  reclaimable estimates accurately. Evaluate copy-on-write materialization only
  where supported and retain isolated `.godot`, profile and temporary state.

## R04 — Task removal and unregistered copies

- **Question:** Can a task disappear while its workspace or temporary copies
  remain on disk?
- **Exact query:** `site:github.com/openai/codex/issues/51631 deleting worktree task cleanup disk`
- **Evidence and status:** An [open firsthand issue](https://github.com/openai/codex/issues/51631),
  opened 2026-10-07, reported that deleting a Codex CLI 0.160.1 task left its
  worktree and requested a deletion-specific hook and visible failure state.
  Another [open report](https://github.com/openai/codex/issues/35383), opened
  2026-07-25, observed 118 matching temporary directories and 202 GB under
  `/private/tmp` while the managed worktree store showed zero entries.
- **Finding and limit:** Both describe particular environments. The latter
  measurement is for `/private/tmp` and is not independently verified as the
  exclusively reclaimable size of those copies.
- **OpenRC idea:** Keep cleanup-pending or cleanup-failed state until actual
  removal is confirmed. Inventory known per-job materializations as well as
  Git-registered worktrees; completion alone is not disk removal.

## R05 — Cursor cleanup policies and scan cost

- **Question:** What do another agent tool's worktree limits and size scans
  reveal about the cost and scope of cleanup?
- **Exact query:** `site:cursor.com/docs/configuration/worktrees automatic cleanup worktrees 2026 disk user reports`
- **Evidence and status:** Current [Cursor documentation](https://cursor.com/docs/configuration/worktrees)
  describes periodic, machine-wide count-based cleanup and says discovery can
  include worktrees created outside the manager under its worktree root. In an
  [October 2026 forum discussion](https://forum.cursor.com/t/main-process-not-renderer-crashes-with-v8-heap-oom-at-4-gb-on-macos-3-24-9-and-3-24-12-heap-climbs-silently-5-9-mb-s-after-launch/174308),
  a respondent confirmed the reported unbounded size walk could exhaust memory
  and restart after launch in Cursor 3.23/3.24. The forum thread is a report and
  response, not a formally tracked issue with a verified resolution.
- **Finding and limit:** A path being discovered under a directory does not
  establish OpenRC ownership. The scan incident is version- and workload-specific.
- **OpenRC idea:** Bound and incrementally resume disk scans, showing unknown
  or stale estimates explicitly. Use thresholds for review, not permission to
  delete active or unknown work.

## R06 — Git worktree removal versus metadata pruning

- **Question:** Does Git worktree pruning reclaim existing checkout directories?
- **Exact query:** `site:git-scm.com/docs/git-worktree prune remove locked untracked working tree documentation`
- **Evidence and status:** The [Git worktree manual](https://git-scm.com/docs/git-worktree),
  checked 2026-11-15, distinguishes removal of a live linked worktree from
  pruning administrative records for missing worktrees. It also documents
  locked worktrees and repair of registrations disconnected by a move. This is
  primary documentation, not an issue report; issue date and status do not apply.
- **Finding and limit:** Pruning metadata does not remove a live checkout. A
  clean Git status alone does not prove ignored artifacts, unpushed work,
  running processes or linked dependencies are disposable; a missing path may
  be moved or temporarily unavailable.
- **OpenRC idea:** Classify live managed directories, missing registrations and
  unknown paths separately. Explain each decision and retain ambiguous cases;
  age alone must not imply process death or stale-lock expiry.

## R07 — Dedicated worktree cleanup tooling

- **Question:** What review and safety features does a worktree cleanup tool
  provide beyond Git's basic commands?
- **Exact query:** `site:github.com/ben-ranford/wtgc worktree garbage collector disk cleanup scan safety`
- **Evidence and status:** The [wtgc project README](https://github.com/ben-ranford/wtgc),
  checked 2026-11-15, describes a dry-run-first inventory with size and reason
  fields. Its documented eligibility checks include cleanliness, local merge and
  remote reachability; ambiguous, detached, primary, locked and dirty worktrees
  are retained. Branch deletion is separately opt-in. This is the project's
  own tool documentation, not an issue report; issue date and status do not apply.
- **Finding and limit:** The README is not an independent security audit or a
  guarantee that the tool understands OpenRC job ownership, processes, Godot
  state or test artifacts.
- **OpenRC idea:** Adopt explainable inventory and separate branch-retention
  decisions, with eligibility governed by OpenRC's job registry and existing
  process-safety rules.

## R08 — Session cleanup review and failure states

- **Question:** How does another agent-session manager expose leftover
  worktrees, uncertain sizes and failed cleanup?
- **Exact query:** `site:code.visualstudio.com/docs/agents worktree cleanup session storage suggestions inactive`
- **Evidence and status:** Current [VS Code session documentation](https://code.visualstudio.com/docs/agents/run/sessions/manage-sessions),
  checked 2026-11-15, describes a review interface with paths, branches and
  estimated sizes; failed removals can be retried, and unknown size does not
  establish zero usage or confirmed removal. Preview automatic cleanup has
  separate completion and deletion periods, both off by default, and retains
  worktrees when required Git evidence is unknown. This is primary product
  documentation, not an issue report; issue date and status do not apply.
- **Finding and limit:** Normal VS Code cleanup can commit nonignored changes
  and deletes ignored files when removing a worktree; automatic cleanup is a
  preview. These behaviors do not establish an OpenRC policy.
- **OpenRC idea:** Show per-job state, measured-versus-unknown size,
  preservation reasons and retryable failures. Preserve user data and record
  disk removal separately from the existing `cleanup=CONFIRMED` process teardown.

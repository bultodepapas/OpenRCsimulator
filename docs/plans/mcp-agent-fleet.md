# Agent-first test fleet: audit and phased plan

Owner: **TQ shared-host test admission**, steps **TQ-05-F0…F5**. Parents:
[agent test orchestrator](agent-test-orchestrator.md) and the safety-focused
[resilience subplan](mcp-queue-resilience.md) (TQ-04-R1…R9). Operating contract:
[queue guide](../../tools/testqueue/README.md).

Adding a fifth host, an Intel iGPU Linux container on PRIMIS, is planned separately in
[TQ-06](primis-intel-test-host.md).

This plan covers what R1–R9 leave open: agent ergonomics, end-to-end speed,
unattended progress and smarter use of the four machines. Every R-plan invariant
(its §2) remains binding. In particular, no change may duplicate an accepted
attempt, kill a foreign process, release a claim without proof, let unverified
evidence pass or contaminate a performance measurement. Where a step touches an
R step, that R step's gate also applies (§6).

**Status: in progress (20 November 2026).** F0.1, F0.3, F0.6, F1.1–F1.6 and
F2.1–F2.2 are implemented; F0.2, F0.4 and F0.5 partly. Each row records its proof.
F3.4 is implemented for remote hosts. F2.3–F2.6, the rest of F3, F4 and F5 remain.

An independent review of the implemented code (20 Nov) led to these fixes:

- Retention compares fully resolved paths.
- A reused archive refreshes its mtime.
- The watchdog records its authority root and resumes only requests changed within 6 h.
- A `PASSED` row without verified evidence shows as `PASSED_UNVERIFIED`.
- `sim_test_run` stops waiting on `NEEDS_OPERATOR`.
- The test lane has four workers.

Open policy questions from that review:

- `ERROR` is never auto-resumed, even for a transient cause.
- `NEEDS_OPERATOR` caused by a host outage is not auto-resumed when the host returns.
- The circuit half-open can admit several queued jobs at once.
An independent review challenged the first draft; its accepted corrections are
folded in.

## 1. Audit, 20 November 2026

Read-only audit of `main` at `e9fe3f923` plus the live authority
(`C:\ProgramData\OpenRC\testpool`, `C:\ProgramData\OpenRC\testqueue`). Other
agents were using the fleet during the audit. Nothing was cancelled, restarted,
recovered or deleted. Numbers come from the 115 MCP batches (14–19 November),
their receipts, the System event log and live probes.

### 1.1 Measured baseline

| Measure | Value |
| --- | --- |
| MCP batches / jobs | 115 / 232; median **1 job per batch** (agents iterate one test at a time, e.g. eight versions of one fixture) |
| Batch result | 31 `PASSED`, 47 `FAILED`, 25 `INCOMPLETE`, 12 never produced a batch |
| Batches left unfinished | **37 (32 %)**, none with a live supervisor: 11 still claim `RUNNING` 1–5 days later, 10 hit the 1-hour supervisor cap, 14 `ERROR`, 1 `SNAPSHOTTING`, 1 `WAITING` |
| Finished rows by outcome | 78 passed, 51 test failed, 28 `INFRA_FAILED` (18 %; on remotes this also includes an incomplete check such as a missing marker or parse error, `remote_agent.py:1051-1053`), plus 11 `COLLECTION_BLOCKED` and 2 `BLOCKED/UNKNOWN` |
| End-to-end wall time, finished batches | p50 **156 s**, p90 3,164 s |
| Remote stage p50 (ANGEL / ANGELA) | snapshot 30 / 43 s, freeze→accepted 48 / 49 s (p90 303 / 865 s), import 17 / 6 s, **execution 2.4 / 2.8 s**, finish→batch done 42 / 40 s (p90 168 / 431 s) |
| Windows snapshot p50 | 44 s (p90 69 s) |
| `sim_test_status` reply | 0.7–50 KB; local read 2–4 ms |
| Host probe (`pool hosts`) | 2.3 s with all four hosts online; ANGEL load 9.7 on 8 cores, still offered work |
| Storage on `C:` | **~117 GB** of queue data (56.7 GB local snapshots, 40.2 GB attempts, 11.4 GB pool snapshots, 8.4 GB archives); **1.9 GB free**. `D:` 104 GB free, `U:` 22.6 GB free |
| Windows pool capacity at audit time | **0**: `busy_reason: an unmanaged simulator is running` |
| Godot processes outside the queue | Six headless runs launched directly from agent shells (`timeout … Godot --script …`). One started 19 November 20:50 had consumed **9,100 CPU-seconds** and was still running 14 hours later |
| Unexpected shutdowns (Event 6008) | 14, 15 and 17 November. Supervisors alive then stopped with empty logs and were never resumed; others died without a reboot |

Test execution is a few seconds out of minutes of waiting. The rest goes to
snapshotting, serial probing/transfer, fixed polling and collection. Agents
respond rationally and run Godot directly. Those runs count as "unmanaged
simulators", which removes Windows from the pool. That makes the queue slower
still and reinforces the bypass.

### 1.2 Findings

Severity: **S1** blocks or loses work, **S2** wastes most time or capacity,
**S3** ergonomics. Line references are `tools/testqueue/` unless noted.

| ID | Sev | Finding | Evidence |
| --- | --- | --- | --- |
| A1 | S1 | **Nobody restarts dead supervisors.** Each batch has its own detached supervisor. A crash, reboot or client teardown leaves `RUNNING` forever, and a slow batch stops at the 1-hour cap. Only an agent calling `sim_test_recover` resumes it. Nothing documented restarts `testctl serve` after a reboot either. | `pool_mcp.py:61-72, 251-302`; 37 orphaned batches; Event 6008 |
| A2 | S1 | **The disk is full and retention is manual.** ENOSPC, `snapshot needs … reserve` and `insufficient disk` appear among supervisor and row errors. `local_gc.py` and `pool gc` exist but nothing runs them. | §1.1; `worker.py:952`; `local_gc.py` |
| A3 | S1 | **Any process named `*godot*` blocks all local work**, including headless functional jobs and the agents' own direct runs. A late appearance turns an already copied attempt into `INFRA_FAILED`. | `worker.py:87-97, 825-832, 1011-1019` |
| A4 | S1 | **A transfer failure wedges a remote host.** Remote `mkdir`, hash check, `scp` (1,800 s), verify and publish run outside the `try` with `check=True` and without `BatchMode`/`ConnectTimeout`. The receipt stays `PREPARING`, a repeated ID returns that receipt instead of retrying, and the host stays reserved until `reconcile --operator-confirm`. | `pool.py:495-500, 585-603, 297-304, 638-642` |
| A5 | S1 | **The circuit breaker cannot tell causes apart and has no timeout.** Two `INFRA_FAILED` results for one source digest close that host to unpinned work on that digest. That includes host-transient refusals (external Godot, low disk) and incomplete checks. It reopens only for a new digest or pinned work. | `pool.py:253-279, 534-539`; `remote_agent.py:1030, 1051-1064` |
| A6 | S1 | **`UNKNOWN` quarantines a whole host.** Only a reboot or an owner-held `abandon` clears it. Worker restarts convert in-flight attempts to `UNKNOWN`. Agents see only a bare `BUSY`. | `store.py:59-61, 146-150`; `worker.py:373-391, 554-568` |
| A7 | S2 | **Every pool job is exclusive.** `_preflight` sends `workload: 'auto'` ("unclassified", exclusive). The pool also treats any claim or queued row as host-busy. For pool work DEVIL (24 cores, 32 GB free) runs one test at a time, and `--headless-slots` has no effect on it. MCP cannot declare `functional`. | `pool.py:455-456, 199-207`; `presets.py:131-156`; `pool_mcp.py:43-46` |
| A8 | S2 | **Snapshots and imports are redone every time.** Each batch freezes a fresh full snapshot (30–54 s). Each local attempt copies and re-hashes ~3 GB. Remotes re-import each job. Source archives are already reused by digest; snapshots, local materialization and imports are not. | `pool.py:313-318, 595-596`; `snapshots.py:311-393`; `worker.py:943-965`; `adapter.py:51-60` |
| A9 | S2 | **One batch's loop is serial and slow to notice progress.** Submits, statuses and collections run one after another, and collection uses one SSH per artifact. A first upload blocks that batch's other hosts (`dispatch.lock` is released, so other batches proceed). The MCP supervisor works in 30 s windows with 5 s sleeps, re-verifies finished rows and re-runs `pool.recover` over SSH for `BLOCKED` rows every cycle. | `pool_batch.py:159-199, 230-308`; `collection.py:178-190`; `pool_mcp.py:280-297` |
| A10 | S2 | **Every placement re-probes the whole fleet.** Every `submit()` probes every host (remote: SSH plus a full engine hash), and a remote selection probes twice. An offline Mac costs 8–45 s per row. Receipts are globbed and parsed on every pass, and `jobs/` is never pruned. | `pool.py:136-155, 249-304, 522, 562`; `remote_agent.py:604-663` |
| A11 | S2 | **Placement ignores the facts that matter.** Transfer rate is a constant 10 MiB/s. `cached_inputs` is always empty. Busy hosts are excluded rather than scored by when they free. There is no speed class, no Mac power/sleep state and no foreground-user headroom. | `pool.py:206-227`; `pool_policy.py:162-170`; live probe |
| A12 | S2 | **The fleet is invisible from the default path.** The MCP default platform is the caller's OS, and status never mentions idle hosts. Agents pinned `darwin` 125 times and `windows` 85 times; whether Windows being blocked drove that is not established. | `pool_mcp.py:40`; request history |
| A13 | S2 | **Sessions, queued jobs and reservations never expire.** `debug-session` is exclusive for up to 30 min even when idle. Queued requests never expire and are not cancelled when their client disappears. Reservations and drain have no expiry. | `presets.py:34, 147`; `worker.py:352-370, 806-843` |
| A14 | S2 | **Snapshot inputs break easily.** Sources under `tmp/` (nested worktrees, `node_modules`) change during capture or fail `git rev-parse`. `__pycache__/*.pyc` enters archives, which remotes then refuse (`unsupported archive path`). | supervisor and row errors |
| A15 | S3 | **Agents cannot see the fleet or why they wait.** No MCP tool shows hosts, queue depth, quarantine, drain or disk. Placement reasons stay in `rows[].status.decision`. `next_action` says "poll" for: `WAITING` with no eligible host, a silent `RETRY_WAIT` (e.g. coordinator archive space), a stuck `SUBMITTING`, or a lone `COLLECTION_BLOCKED`. | `pool_mcp.py:151-229`; `pool.py:369-372, 555-559` |
| A16 | S3 | **The common case costs too many calls and too much text.** It takes launch plus N polls of up to 50 KB each. There is no wait, cancel, list or inline failure excerpt. `sim_test_launch` and `sim_test_recover` share the ordered lane with 600 s bridge calls, so they can wait behind a simulator action. | `mcp_server.py:115-131, 559` |
| A17 | S3 | **Collection can report a raw `KeyError` as its reason** (`'log'`, 3 rows). | row errors |

R1–R9 already plan guardians, physical-domain reservations, verified cache
inventory, measured concurrency and evidence-ownership-first retention. They do
not cover:

- A1's supervision model.
- A3.
- A4's path and A5's cause typing.
- A7's MCP declaration.
- A12, A13's leases, A15 or A16.

These are the main subject here.

## 2. Goals and measures

An agent should get a trustworthy result for one short test faster through the
fleet than by running Godot itself, in one or two tool calls, without babysitting.
Targets are proposals. Measure them against §1.1 with the same scripts and report
sample counts, cache state and competing load.

| Measure | Baseline | Target |
| --- | --- | --- |
| One short test, warm inputs, idle eligible host | 156 s p50 | ≤ 30 s p50 after F3; ≤ 20 s once F2+F3 are both in |
| Unfinished batches without a typed terminal or `NEEDS_OPERATOR` state | 32 % | 0 for batches with a frozen manifest, after a crash, reboot or client exit. Pre-manifest batches report "resubmit" |
| Rows ending with an untyped failure cause | most `INFRA_FAILED` | 0. Every non-pass carries a cause code (test, incomplete evidence, host transient, transfer, disk, unknown) |
| Agent calls to run and read one test | ≥ 3 + polls | 1–2 |
| Default status size | up to 50 KB | ≤ 3 KB, with failing lines inline |
| Fleet view | CLI only, 2.3 s | MCP, ≤ 100 ms from cache, freshness stated |
| Unmanaged Godot sightings by agent tooling | 6 at audit time | trend to 0 per day after F4 |
| Authority volume free space | 1.9 GB | above an explicit admission floor, with a typed pause instead of ENOSPC |
| Batch of N jobs on H free hosts | not measured | makespan ≤ 1.5 × (longest-first lower bound from history medians + one warm setup) |

## 3. Design principles

1. **Agents submit intent and read results.** They never keep work alive or
   triage infrastructure.
2. **Make the queue the fastest correct path.** Reuse frozen inputs by content
   address. A reused input is still an exact verified identity.
3. **Every wait has a typed reason, an alternative and an estimate.** "Poll" is
   never the whole answer.
4. **Score hosts, don't just filter them.** Offline hosts cost nothing after the
   first miss.
5. **Exclusive stays the default for unknown work.** Parallelism comes from
   explicit declarations backed by canary evidence.
6. **Bounded retry for proved transients, quarantine with a reason for
   uncertainty, and a stop state instead of endless polling.**
7. **Smallest mechanism first.** Use Python, SQLite and SSH. Add a watchdog
   before a new daemon, and fix loops before new protocols.

## 4. Phases

**D** marks a step that needs an owner decision (§7). Each step is one small,
reviewable change with focused fixtures.

### F0: emergency and correctness fixes

| ID | Work | Proof |
| --- | --- | --- |
| TQ-05-F0.1 | Restore headroom on `C:`. The existing `local_gc.py` found 0 candidates, so `retention.py` adds reference-checked removal of redundant attempt sources, snapshots and archives. See the [queue guide](../../tools/testqueue/README.md#operator-storage-and-reconciliation-tools). | **Done 20 Nov:** 6 fixtures; owner-approved run removed 101.5 GB with 0 errors (C: 1.9 → 93 GB free), held 31 inputs of unfinished work; worker `READY` afterwards. Journal `testpool/retention/retention-20261120-102314.json` |
| TQ-05-F0.2 | Snapshot hygiene: exclude `__pycache__`, `*.pyc` and `node_modules` from snapshot scope. Refuse, before freezing and with a clear message, a source that is not its own checkout root (e.g. a worktree nested in another checkout's `tmp/`). | **Partial:** `capture` never freezes `__pycache__`/`.pyc`. `Pool.snapshot` retries "changed/disappeared during snapshot" up to 4 times with a fresh destination, removing only its own partial one, because a live MCP run failed when another agent edited `app/`. A failed freeze now says "run again with a new request_id". `capture` already refuses a source that is not a worktree root. 4 fixtures in `test_agent_view` |
| TQ-05-F0.3 | Remote transfer path (A4 only): move `mkdir`/hash/`scp`/verify/publish inside the guarded section. Use one shared `ssh_options()` (BatchMode, ConnectTimeout, ServerAliveInterval) for every ssh/scp. A failure proved before `run` records a typed `TRANSFER_DEFERRED` receipt state. A repeated ID re-enters the transfer on the same bound host instead of returning `PREPARING`. | **Done:** receipt state `TRANSFER_DEFERRED` with `transfer`/`transfer_history` holds no host. `status`/`recover` report it as `WAITING` without writing. The batch retries the same ID with backoff, and a crash right after the deferral resumes as `RETRY_WAIT`. `ssh_options()` is used by `remote()`, the transfer and collection. 10 fixtures in `test_pool_transfer`. Open: a coordinator crash *during* a transfer still leaves `PREPARING` (needs the R1 outcome-contract decision). Retry is unbounded until F2.2 |
| TQ-05-F0.4 | Typed causes: remote and local outcomes carry `cause` (`TEST`, `INCOMPLETE_EVIDENCE`, `HOST_TRANSIENT`, `TRANSFER`, `DISK`, `UNKNOWN`). The circuit breaker counts only source-specific causes and goes half-open after a TTL with one probe attempt. | **Partial:** the circuit ignores host-transient refusals (external Godot, disk, quarantine, busy, desktop) and half-opens 10 min after its newest failure; 2 new fixtures in `test_pool_reconcile`. A typed `cause` field on every outcome is still open: remote `INFRA_FAILED` also covers incomplete checks |
| TQ-05-F0.5 | Make deferrals visible: coordinator archive space and other `RETRY_WAIT` causes surface as typed reasons in status. They remain deferrals, not failures. | **Partial:** `RETRY_WAIT` rows carry their `reason_code` (`SUBMISSION_DEFERRED`, `TRANSFER_DEFERRED`) into `tests[].waiting` and `summary.waiting`. Archive-space deferral text is not yet a separate code |
| TQ-05-F0.6 | Typed collection errors instead of raw exception text (A17). | **Done:** collection errors that are not typed refusals now name their exception type (`KeyError: 'log'` instead of `'log'`). The 17 Nov `KeyError` path is no longer present in the current collector |
| TQ-05-F0.7 | **D** Relocate the authority and pool roots to a larger local volume, after F0.1 and with no `UNKNOWN`/unresolved attempts. Receipts bind absolute roots and the config digest (`pool.py:418, 570`; `pool_mcp.py:236, 269`), so finish or close old batches through supported recovery first, or keep the old root readable for them. Back up SQLite with the supported mechanism. | `hosts` reports the new volume; an old batch still recovers or is closed with a reason |

### F1: agent-facing MCP, read side first (A12, A15, A16)

These steps change no execution path. Existing tools keep working.

| ID | Work | Proof |
| --- | --- | --- |
| TQ-05-F1.1 | `sim_fleet`: per host `online`, typed `busy_reason`, free slots, queue depth, disk/RAM, load, `last_seen`, rough expected wait. Also unmanaged Godot processes (PID, age, CPU, command line via the existing optional `psutil`), and quarantine, drain and reservation with the command that clears each. Served from a short-TTL cache with freshness shown. | **Done (`agent_view.fleet`):** hosts with a typed `busy_code` from the probe (`EXTERNAL_SIMULATOR`, `RUNNING_QUEUE_WORK`, `QUEUED_LOCAL_WORK`, `HUMAN_RESERVATION`, `CONDITION_*`, `RESERVED_BY_RECEIPT`, `CIRCUIT_OPEN`, `RUNNING_POOL_JOB`, `QUARANTINED`, `ENROLLED_HOST`), active pool jobs per host, local Godot processes (age, CPU, script, managed) and idle hints. 15 s cache; live refresh 2.5 s, cached 57 ms (the first version took 14.8 s until psutil filtered by name first). The first live view showed the 14 h unmanaged run (9,254 CPU s). Pending: free slots, expected wait, clear commands |
| TQ-05-F1.2 | Compact status by default (`detail: "summary"`, ≤ 3 KB). It gives per-test outcome, cause, host, duration, failing check lines and log tail inline, and a typed `waiting_reason` (`NO_ONLINE_HOST_FOR_PLATFORM`, `HOST_BUSY`, `DISK_FLOOR`, `QUARANTINED`, `CIRCUIT_OPEN`, `TRANSFER_DEFERRED`, …) with the alternative, e.g. "`linux` free now; portable checks may use `platform:any`". `detail: "full"` returns today's rows. | **Done:** live replies 1.0–3.4 KB vs 7–19 KB full; failing lines and missing markers inline (e.g. the real `cannot read …aircraft-contract-v2.json` cause). Codes: `NO_HOST_FOR_PLATFORM`, `NO_ONLINE_HOST_FOR_PLATFORM`, `HOST_BUSY`, `DISK`, `CIRCUIT_OPEN`, `QUARANTINED`, `NO_ELIGIBLE_HOST`, plus the `RETRY_WAIT` reason code. `next_action` names them. Fixtures in `test_agent_view` |
| TQ-05-F1.3 | `sim_test_list`: recent batches with one-line results, so a new session can find its own work. | **Done**; fixture |
| TQ-05-F1.4 | Lanes: give `sim_test_launch`/`sim_test_recover`/`sim_fleet` their own bounded lane, so they never wait behind a 600 s simulator call. Ordered simulator mutations keep their FIFO. | **Done:** two-worker test lane for launch/recover/run/fleet/list; transport fixture with a blocked `sim_launch` |
| TQ-05-F1.5 | `sim_test_run`: launch plus wait up to `wait_s` (default 60, so it stays under typical client tool timeouts; max 300) in the test lane. It returns the compact result, or the ticket plus estimate. `request_id` is optional; when omitted the server generates a fresh one and returns it, so an explicit rerun is a new attempt. Reusing an ID stays idempotent. | **Done:** fixtures for generated ID, timeout (observe only), early exit on a dead supervisor and `wait_s` bounds. Live run 1 died at snapshot (concurrent edits), which led to the F0.2 retry. Live run 2 froze in 129 s, moved a 1 GB archive in ~95 s and executed in under 1 s on ANGEL, which confirms F3 as the main latency target |
| TQ-05-F1.6 | Rewrite server `INSTRUCTIONS`, [`tools/debug/README.md`](../../tools/debug/README.md), the `openrc-tools`/`openrc-debug` skills and AGENTS tool notes around the one-call flow and `sim_fleet`. | **Done:** server `INSTRUCTIONS`, tool descriptions, AGENTS tool note, both `openrc-tools` skill copies, the debug README and the queue guide point to `sim_test_run`/`sim_fleet`. A trial with a fresh agent session is pending |

### F2: unattended progress and a responsive loop (A1, A9, A10)

| ID | Work | Proof |
| --- | --- | --- |
| TQ-05-F2.1 | Start at logon and watch: a scheduled task starts `testctl serve` with the pinned engine, plus a watchdog. Every minute the watchdog calls the existing idempotent `pool_mcp.recover` for any batch with a frozen manifest, a non-terminal result and no live supervisor. Pre-manifest batches are marked "resubmit", never recovered. Per-batch isolation is unchanged. | **Done, reboot campaign pending:** root cause found on 20 Nov: all 18 live MCP server processes (Claude Code and Codex) run inside a Job Object, so supervisors died with their agent session. Supervisors now start with `CREATE_BREAKAWAY_FROM_JOB` (normal start if the job forbids it); a native fixture shows a plain child killed by a kill-on-close job while the breakaway child survives. `watchdog.py` resumes requests changed within 24 h, skips `ERROR`/`NEEDS_OPERATOR`, caps resumes at 6 a day, lists stale ones and starts `testctl serve` when the authority does not answer. It runs from the `\OpenRC\TestWatchdog` logon task (pythonw, 60 s); its first live pass resumed nothing and listed 22 stale requests. Fixtures in `test_supervisor_lifetime` |
| TQ-05-F2.2 | Replace the 1-hour cap with progress rules. Keep observing while any row is queued, running or collecting. Rows `BLOCKED`/`COLLECTION_BLOCKED` with no change for a bounded number of cycles become `NEEDS_OPERATOR`, with a reason and the exact command. The supervisor then stops polling them. An optional owner batch deadline ends observation, never execution. | **Done:** `Progress` replaces the cap. Remaining rows blocked and unchanged for 15 min, or no change at all for 6 h, end in `NEEDS_OPERATOR` with detail/action, which status shows. `BLOCKED` recover runs at most every 5 min, and the pause is 2 s instead of 5 s. The owner batch deadline is not implemented |
| TQ-05-F2.3 | Per-host concurrency inside one batch: bounded per-host workers for submit, status and collection, so a slow upload or collection on one host does not idle the others. | Fixture with one stalled host |
| TQ-05-F2.4 | Probe cache: a host-state cache (≈ 10 s TTL, exponential backoff up to 5 min for offline hosts). Cache engine hashes by (path, size, mtime) and confirm them at admission. One fresh probe of the **selected** host just before dispatch; a typed `BUSY` after transfer requeues without counting as a failure. Remove the second probe; prune or index `jobs/` receipts after terminal collection. | Offline host adds ≤ one backoff check per pass; placement latency measured |
| TQ-05-F2.5 | Collection and polling: one bounded archive stream per remote job instead of one SSH per artifact. Wake the supervisor on state change (store/receipt mtime) instead of fixed 5 s + 30 s windows. Stop re-verifying already verified rows each cycle. | finish→result p50 ≤ 5 s |
| TQ-05-F2.6 | Stage timing: record snapshot, transfer, queue, import, execution and collection durations per row and show them in status and `sim_fleet`. This baseline feeds F3–F5. | Status fixture; daily JSON summary outside Git |

A persistent SSH channel per host (Windows OpenSSH lacks ControlMaster) is
deferred until F2.6 shows handshakes are a material share of wait time. A
remote protocol change also requires R-plan invariant 10 pinning on every host.

### F3: fast inputs (A8, A14)

| ID | Work | Proof |
| --- | --- | --- |
| TQ-05-F3.1 | Content-addressed snapshots: a read-only verified file store keyed by hash. Each snapshot is a manifest over it: base tree plus dirty/untracked overlay. A warm re-snapshot hashes only files whose size/mtime changed. The manifest digest remains the exact identity. | Warm snapshot ≤ 3 s; identical manifests for identical bytes; store files read-only |
| TQ-05-F3.2 | Remote base plus overlay: each remote keeps verified base archives. Only changed files are sent and assembled into the job's private tree on the remote. Measure real bandwidth per host. | Warm transfer ≤ 2 s; `cached_inputs` from verified remote inventory (R8) |
| TQ-05-F3.3 | Attempt materialization stays a real copy for anything Godot can write (`res://` sidecars such as `.import`/`.uid`, `.godot`, profile, output). Hard links are allowed only for files proved unwritten, with read-only permissions tested on NTFS, APFS and ext4. Otherwise keep copying but skip the second full re-hash when the store already verified the bytes. | Isolation fixtures, including a sidecar write attempt; local setup time measured |
| TQ-05-F3.4 | Import cache keyed by engine identity plus the digest of every input that affects import and class/UID caches (assets, `.import`, scripts, `project.godot`). Warm hits only for identical inputs; a miss imports and populates; a mismatch is never used. **Do this first in F3.** On 20 Nov a live `test_math3d` run on ANGEL (load ~20) ended `INFRA_FAILED`: the default 90 s budget expired at 31 % of a cold full-project reimport, and the test never started. Until this lands, compact status reports such rows as `why: import timeout` with a hint. | **Done for remote hosts (20 Nov), with a different design:** seed only `.godot/imported/` from a per-host, per-engine cache that is published after a passing import. Godot's own per-asset md5 check replaces the composite key, and class/UID caches are always rebuilt. Copy-on-write clone on APFS/Linux, never hard links. Seeding and publication never fail a job. Proof: 4 fixtures on Windows plus the remote-agent suite run natively on ANGEL and Linux (24/24). Deployed by atomic swap to ANGEL, ANGELA and Linux while idle; the previous agent is kept as `remote_agent.py.prev-tq04`. Live on Linux: cold import 397 s published 2.07 GB / 1,352 files; the next run on changed source imported in 21.5 s plus a 4.3 s seed, and passed. The Macs could not publish because every import failed on a missing `macos.arm64` library in `openrc_ground_vehicle.gdextension`. That was a queue defect, not a native-kernel one: snapshots shipped the coordinator's git-ignored Windows/Linux native install to the Macs. Fixed the same day: remote hosts drop installed `app/native` descriptors with no library for their OS/arch and record `native_adaptation`; 2 fixtures, native suites 26/26 on ANGEL, ANGELA and Linux, and deployed. Live: `test_math3d` then passed on both Macs (cold import 478/467 s published their caches); the warm round imported in 16.0/16.3 s after a 0.2 s APFS-clone seed and passed. That round's 814 s wall time was mostly the 158 s snapshot and about 600 s of 1 GB `scp`, so F3.2 delta transfer is next. The local Windows worker still imports cold |

### F4: close the bypass (A3)

| ID | Work | Proof |
| --- | --- | --- |
| TQ-05-F4.1 | **D** Owned dev lane: `sim_test_run mode:"dev"` (and a `testctl devrun` CLI) runs one script against the caller's live checkout through the local authority. The process is owned, bound to a deadline (default 300 s), counted and quickly killed. Results are labelled `evidence: UNFROZEN` and cannot qualify a batch, release or CI gate. It writes only to its own profile and output directories. | Within ±15 % of a direct run; no process outlives its deadline; cannot pass a batch |
| TQ-05-F4.2 | **D** External Godot by role: use `psutil` command lines to classify unmanaged processes as headless or rendered. Unmanaged headless processes stop blocking functional slots, but still block exclusive, rendered and performance work, and every one is reported in `sim_fleet`. Never kill or adopt them. A late conflict requeues the attempt before launch instead of `INFRA_FAILED`. | Fixtures; native check with one unmanaged headless run |
| TQ-05-F4.3 | After F4.1 meets its target, update AGENTS/CLAUDE and the skills so agents prefer the dev lane over raw `Godot --script` on enrolled hosts. Repository launchers (`app/test.sh`, `tools/ci/check-local.sh`) keep their existing admission. | Sighting metric trends down |

### F5: placement, parallelism and fairness (A7, A11, A13), after R5/R6

| ID | Work | Proof |
| --- | --- | --- |
| TQ-05-F5.1 | Let MCP and pool jobs declare `workload: "functional"` per job; today it cannot reach the authority. Unknown stays exclusive. **D** Seed a reviewed allowlist from R6 canary evidence (no timing thresholds, fixed ports or shared devices). | Exclusive and timing fixtures unchanged |
| TQ-05-F5.2 | Capacity from measurement, as R6 specifies: trial two Windows functional slots and observe RAM/CPU/IO and the owner's foreground experience before raising. Linux needs R5 physical-parent identity first. Macs stay at one. Lower DEVIL slots automatically while the owner has a rendered session or high foreground load. | Native canary report |
| TQ-05-F5.3 | Placement v2: expected completion = time until a slot frees + measured transfer (0 when verified cached) + warm/cold setup + per-host duration median. Use longest-first across the batch and deterministic ties. Add Mac power/sleep/battery (`pmset`), a per-host flakiness penalty, and load that excludes the queue's own work. Most batches have one job, so the main gains are host choice and cache warmth. | Decision records show components; replayed batches vs. current placement |
| TQ-05-F5.4 | Fair share: owner identity per agent session, round-robin with aging, and the eligible-exclusive barrier preserved. | Two-owner fixture |
| TQ-05-F5.5 | Leases: interactive sessions renew while their MCP server lives. Idle timeout (default 10 min) or client exit ends them through owned cancellation. Queued requests take an optional queue deadline; reservations take an expiry. | Dead-client fixture; no orphan exclusive |
| TQ-05-F5.6 | `sim_test_cancel`: queued and local running jobs through existing owned cancellation now. Remote running jobs only once R4 provides owned remote cancel; until then the reply says the remote job continues. | Fixtures; R4 gate for remote |
| TQ-05-F5.7 | Agent scenario suite: five scripted concurrent agents cover one-call runs, a host going offline, a sleeping Mac, the disk floor, a watchdog restart, a reboot and a cancel race. It runs on every queue/MCP change and feeds R9's native campaign. | Suite in `tools/testqueue/`; Windows workflow coverage |

## 5. Sequencing

```mermaid
flowchart LR
  F0["F0 emergency + fixes"] --> F1["F1 MCP read side"]
  F0 --> F2["F2 unattended progress"]
  F1 --> F4["F4 close the bypass"]
  F2 --> F3["F3 fast inputs"]
  F3 --> F4
  F3 --> F5["F5 placement + parallelism (after R5/R6)"]
  F4 --> F5
```

Start with F0.1 (an owner operation) and F1.1/F1.2, which change no execution
path and give the largest visible improvement to agents. F2.1 (watchdog)
follows immediately. F5 must not precede R5 physical-domain identity and the
R6 canary.

## 6. Relation to TQ-04-R1…R9

| This plan | R step | Relationship |
| --- | --- | --- |
| F0.3, F0.4, F0.5 | R1 | Additional proved-predispatch and cause-typing paths; same outcome contract and invariants |
| F1.4, F1.5 | R3 | Extends the bounded lane model; ordered simulator mutations unchanged |
| F2.1, F2.2 | R3, R4 | Watchdog restarts controllers only; guardians (R4) remain separate |
| F2.3–F2.5, F3.2 | R6, R8 | Planned per-host async preparation, slow-host circuit and verified cache inventory |
| F0.1, F0.7 | R8 | Uses existing GC only. Broader retention remains R8's evidence-ownership-first sequence; this plan adds none |
| F5.1–F5.3 | R5, R6 | Gated on physical-domain identity and measured canaries |
| F5.6 | R4 | Remote running-job cancel requires guardian ownership |
| F5.7 | R9 | Feeds the native fault campaign; does not replace it |

## 7. Decisions needed

| ID | Question | Recommendation |
| --- | --- | --- |
| D1 (F0.7) | Which volume holds the authority and pool roots? | `D:` (104 GB free) after F0.1, unless the owner wants the `U:` cache drive and it has room. Confirm the volume is local, never network, for SQLite. |
| D2 (F4.1) | Offer an owned, unfrozen dev lane that can never qualify results? | Yes. It removes the reason agents bypass the queue and bounds their runaway runs. |
| D3 (F4.2) | Should unmanaged headless Godot block only exclusive, rendered and performance work? | Yes, with reporting. Never kill. |
| D4 (F5.1) | Seed a functional allowlist from canary evidence? | Yes. Keep unknown exclusive. |
| D5 (F1.2) | Should status suggest `platform:any` when caller-OS hosts are unavailable, keeping the caller-OS default? | Yes. Coverage remains explicit. |

## 8. Limits

These are software observations from one authority over five days, read
statically and from retained receipts. They establish no throughput gain, no
Mac/Linux containment qualification and no rendered or performance acceptance.
§2 targets are proposals until measured with matched inputs. The classification
of the 37 unfinished batches is from cached state and was not re-observed at
their authorities. The physical parent of the Linux host remains unverified (R5).

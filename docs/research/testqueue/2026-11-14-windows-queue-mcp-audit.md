# OpenRC Simulator — Windows Test Queue and MCP Audit

**Date:** 14 November 2026, America/Bogota\
**Audience:** senior developers, test infrastructure owners and Windows maintainers\
**Track:** TQ-01 / TQ-04, with PT1h debug/MCP and local-CI integration\
**Repository:** [bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator)\
**Audited baseline:** `main` at `95fe1177f26929a12bd032c12e7ac3352eef304d`\
**Implementation commit:** `6913c918e2664d01818526e3162e71e761263796`\
**Review branch:** `audit/windows-testqueue-20261114`

## 1. Executive assessment

The queue already has a substantial ownership and recovery foundation: one host authority, transactional resource claims, persistent cancellation, frozen source inputs, per-attempt writable directories, Windows Job Object containment, and conservative recovery when cleanup cannot be proven. Replacing that foundation with another queue would add migration risk without addressing the immediate defects. The appropriate improvement is to make admission reflect the work's actual contract and repair the lifecycle and evidence gaps around it. [S1][S2][S3][S12]

The central baseline problem is that **headless versus rendered is not a sufficient scheduling policy**. A rendered GOD TEST could overlap a headless job because their claims use different resource names and each consumes only one CPU/memory unit. An unrestricted debug session can start profiling after launch. Conversely, a fixed studio still does not need the same interaction contract as an arbitrary flight session. [S1][S2][S5]

The implementation now classifies requests before execution, reserves exclusive work against all managed claims, prevents eligible exclusive requests from being starved by younger jobs, and introduces a restricted `aircraft-screenshot` preset that can share capacity with other eligible work. General debug sessions and unclassified scripts remain exclusive. A reviewed headless functional test can explicitly request sharing; that declaration remains a trusted developer assertion, not proof produced by static analysis.

The review also identified and repaired pending MCP ownership loss, a closed-process observation race, incorrect local-CI evidence requirements, delayed reporting of quarantined jobs, and screenshot artifact overwrites. Independent review of the candidate caught two additional integration hazards before delivery: legacy uncertain attempts without the new exclusive claim, and mutable or outdated screenshot launch dependencies. Both are covered by regressions.

**Verification result:** 257 local Python tests ran: **251 passed, 6 skipped, no failures**. The skips include Windows-specific process tests and the opt-in graphical campaign. These results establish the tested orchestration behavior on Linux. They do not establish native Windows graphics behavior, real parallel GPU throughput, or a quiet physical host. The added Windows workflow is ready for hosted execution; the real 1920×1080 Windows campaign remains required.

**Release recommendation:** review the bounded implementation and qualify it in stages. Keep the capture capacity at one until simultaneous real studio renders are validated on the intended Windows machine. Do not claim a measured performance improvement: overlap was demonstrated with owned fake processes, not benchmarked with the simulator.

## 2. Scope, method and prior work

The source review followed the request from CLI/MCP admission through preset validation, snapshot verification, resource allocation, process start, bridge ownership, cancellation, cleanup and result collection. It covered `tools/testqueue`, `tools/debug`, the relevant checked-runner and GOD TEST hooks, local-CI shell integration, the existing studio renderer, and the workflow paths that exercise these tools.

The baseline was fetched from the repository and pinned before editing. Earlier local copies of `tools/testqueue` and `tools/debug` were checked against the current Git tree identities before their audit findings were used. All implementation work was isolated on the named review branch. The changes do not alter the flight physics, aircraft geometry or accepted simulation data.

The review read the existing [TQ plan](../../plans/agent-test-orchestrator.md) and [consolidated external audit ledger](../../../external%20Audits/CONSOLIDATED-AUDITS.md). The ledger already records completed debug work and remaining native, device, profiler and release gates. Those historical findings are not counted again as newly discovered defects. The TQ plan's earlier Windows evidence remains a partial campaign, not blanket qualification of the new scheduler. [S12][S13]

Evidence is separated into four categories throughout this report:

- **Confirmed baseline defects:** supported by the inspected source and a focused reproduction or regression.
- **Candidate hardening:** integration problems discovered while reviewing the new policy, corrected before delivery.
- **Remaining implementation gaps:** code or workflow boundaries that the change does not close.
- **Qualification gaps:** behavior that requires an actual Windows desktop, GPU or other unavailable target evidence.

The code was reviewed independently for counterexamples involving shared desktop focus, port ownership, delayed startup, legacy database records and process cleanup. The review did not connect to or modify the user's Windows PC, run a real simulator, conduct radio/device tests, or claim production acceptance from mocks.

## 3. Scheduling policy delivered

### 3.1 Classification at request time

Each accepted submission and job status exposes a `scheduling` object containing the policy version, mode, workload, reason and resource claims. The authority derives these values; a caller cannot submit arbitrary resource amounts. The current policy is implemented in [presets.py](../../../tools/testqueue/presets.py).

| Request | Selected mode | Rationale |
| --- | --- | --- |
| GOD TEST, full suites, CI, composite captures and landscape runs | Exclusive | These adapters can include timing, resource measurements or shared-desktop behavior. |
| Debug sessions and debug smoke, including headless sessions | Exclusive | Their bridge can later execute profiling, arbitrary commands and interactive actions. |
| Checked script with no reviewed declaration | Exclusive | Unknown work has no established parallel contract. |
| Checked, headless script with `workload: functional` | Parallel | The developer declares that the check has no timing or shared-device dependency. |
| `workload: performance`, or a recognized timing/benchmark script name | Exclusive | Performance takes precedence over a functional declaration. |
| `aircraft-screenshot` | Parallel | One fixed studio still, one catalog aircraft, isolated source/profile/output and no debug bridge. |

The script-name guard recognizes common benchmark, performance, profiling, latency, soak, stress and memory names. It is a conservative backstop. A benchmark hidden inside an arbitrarily named script cannot be identified reliably from a filename, and the implementation does not claim otherwise. New functional checks must be reviewed before using the declaration.

### 3.2 What exclusivity guarantees

An exclusive attempt requires all managed claims to be empty. Its exclusive claim blocks every other allocation, including a job asking for a different resource class. The decision is made inside the same SQLite transaction that records dispatch intent. Claims remain held through preparation, execution, verified process teardown and evidence collection.

Any `UNKNOWN` attempt blocks new execution across the managed host. This intentionally includes records written by the previous queue version, whose resource rows did not contain an exclusive marker. Recovery still requires the existing proof of cleanup; no expiry timer, PID guess or automatic deletion releases the claim.

The scheduler also protects an eligible exclusive waiter: younger requests cannot keep refilling available slots while its predecessors drain. A request that cannot run because its desktop is locked or reserved does not unnecessarily idle eligible functional headless work. Human reservations block headless exclusive performance work as well as rendered work.

This is **managed execution exclusivity**, not an operating-system guarantee that all CPU, GPU and disk activity has stopped. Snapshot creation and submission verification still occur before allocation, and unwrapped applications remain outside the authority. Section 7 identifies the work needed for stronger measurement isolation.

### 3.3 The parallel screenshot contract

The new preset reuses [the existing studio renderer](../../../tools/readme/capture_aircraft.gd). It renders the model with its own `SceneTree` and viewport, rather than starting the full flight window. The worker supplies the executable, script, 1920×1080 resolution, Dummy audio, still-only mode and attempt-owned output path. The caller supplies one validated catalog aircraft ID and a bounded timeout.

The preset has no arbitrary script or shell argument endpoint, does not create a debug bridge port and does not expose interactive controls. It receives the existing frozen-source and per-attempt isolation behavior. Because the studio script records Git identity, its adapter also prepares the required private Git history before capture.

The authority freezes a fingerprint of the studio script and relevant Python launch inventories at startup. This includes package initializers and added shadow modules. It compares the submitted snapshot and rechecks the materialized copy before launch, including after a worker upgrade. The project and aircraft remain the candidate being tested; this is integrity checking for trusted development sources, not a sandbox for hostile code.

Success requires all of the following:

1. The checked runner completes and observes `README_RENDER_OK: 1 vehicles, 0 animation frames`.
2. The manifest identifies exactly the requested aircraft and one still.
3. Start/end source identities agree and match the expected source commit and capture tool.
4. The manifest and actual file checksum agree.
5. The file is a structurally valid 1920×1080 PNG with valid bounded image data and no animation frames.
6. The worker proves owned-process cleanup and collects the result.

The default capture capacity remains one. `--capture-slots 2` enables two eligible studio attempts; it does not make general debug windows parallel. A studio screenshot can also overlap a declared functional headless check within the configured capacities.

## 4. Confirmed baseline defects and corrections

Severity describes impact in this infrastructure: **P1** can invalidate isolation, ownership or reliable execution; **P2** can produce incorrect outcomes, retained evidence or significant operational blockage. It is not a claim of an external security exploit.

| ID | Severity | Baseline problem | Disposition |
| --- | --- | --- | --- |
| TQA-01 | P1 | Performance work could overlap a headless job. | Fixed with a global exclusive claim and conservative classification. |
| TQA-02 | P1 | A queued MCP launch could lose its retained owner handle after waiting. | Fixed with ownership at acceptance, managed-MCP return immediately after acceptance and status/cancel support. |
| TQA-03 | P1 | Occupancy inspection could access a closed `OwnedProcess` during evidence collection. | Fixed by serializing observation/teardown and removing the closed object before collection. |
| TQA-04 | P2 | FIFO among feasible jobs offered no protection for work waiting for an idle host. | Fixed for eligible exclusive waiters with a draining barrier. |
| TQA-05 | P2 | Local CI quick/full evidence did not match what the runner actually produced. | Fixed with mode-specific requirements and attempt-owned diagnostic paths. |
| TQA-06 | P2 | `wait()` hid `UNKNOWN` until timeout and could accept stale session data as ready. | Fixed with immediate quarantine reporting and RUNNING-only readiness. |
| TQA-07 | P2 | Same-server screenshots within one second reused a filename. | Fixed with a UUID suffix and collision regression. |
| TQA-08 | P2 | An application argument named `--headless` prevented insertion of the real engine flag. | Fixed by examining only engine arguments before `--`. |

### TQA-01 — Performance isolation was incomplete

**Trigger:** run a rendered GOD TEST while a headless check is active, or admit a headless check while the rendered job is active.

**Cause:** baseline `claims()` allocates `cpu: 1`, `memory: 1` and either `headless: 1` or `rendered: 1`. The worker's default CPU and memory capacities allow both classes simultaneously. Neither class expresses a requirement for an idle managed host. [S1][S2]

**Impact:** test execution can be correct while performance observations are contaminated by another admitted process. Increasing headless slots expands the potential interference.

**Correction:** exclusive claims conflict with every retained claim, and all new work conflicts with a held exclusive claim. Generic debug sessions are also exclusive because classification must cover the commands they can execute after launch. Resource sampling in the checked runner validates an actual exclusive inherited grant.

**Evidence:** policy tests, store conflict tests, a mixed headless/capture/exclusive ordering test and a regression refusing resource sampling under a shared grant. These prove admission behavior, not physical host quiescence.

### TQA-02 — Pending MCP ownership could be lost

**Trigger:** `sim_launch` submits a durable job but the 600-second readiness wait expires while it is still queued.

**Cause:** `open_debug()` originally stored `OPENRC_TESTQUEUE_HANDLE` only after a session became ready. It returned failure for a non-ready job even though the queue retained that job. The MCP layer converted the result to a tool error. The stdio server could also remain blocked in the readiness wait. [S4][S5]

**Impact:** the original request could later launch without the server retaining its ownership handle, and a retry could enqueue another request.

**Correction:** retain the accepted handle before waiting, preserve it on status failure, and refuse duplicate launches until the prior job is terminal. Managed MCP returns after acceptance and offers `sim_session_status`; `sim_stop` can cancel pending or running work. CLI callers retain the existing wait, with an explicit accepted/pending result and an early recovery receipt on stderr.

**Evidence:** queued launch, status failure, duplicate launch, later readiness, cancellation and terminal-state regressions. General long-running MCP calls are still synchronous; see R04.

`sim_session_status` observes the public job status; it does not itself authenticate a supplied secret. Bridge controls and cancellation still validate the owning handle at the authority.

### TQA-03 — Closed-process observation race

**Trigger:** an attempt finishes and closes its process object, then spends time hashing or collecting artifacts while another request is being scheduled or is about to start.

**Cause:** the baseline left the closed object in `worker.active` until the end of `execute()`. `_external_conflicts()` called `pids()` on every active object; `OwnedProcess` rejects handle operations after close. Cleanup and occupancy inspection also lacked shared serialization. [S2]

**Impact:** a scheduler iteration could fail, or a different prepared attempt could become `INFRA_FAILED` before launch. A direct reproduction with a closed object in `active` raised the expected runtime error.

**Correction:** process observations and teardown use the worker lock. A closed object is removed before result I/O, while its durable claim remains retained. Cleanup failure becomes `UNKNOWN` before another scheduler pass can admit work.

**Evidence:** a regression verifies that occupancy inspection cannot observe a closed object after teardown; existing descendant, cancellation and uncertain-cleanup fixtures continue to pass. Holding the worker lock during bounded cleanup may briefly delay control RPCs, which is a tradeoff to measure.

### TQA-04 — Exclusive work needed fairness

The baseline loops over queued jobs and admits each feasible request. Once a global exclusive requirement is introduced, that policy alone allows younger parallel jobs to repeatedly refill resources and delay the exclusive request indefinitely. [S2]

The correction creates a barrier at the first eligible exclusive waiter. Canceling that waiter releases the barrier; unrelated desktop ineligibility does not block useful functional headless work. Regressions cover draining both resource classes, cancellation and reservations. Per-owner quotas and general priority aging remain separate opportunities.

### TQA-05 — CI evidence could produce false failures

**Quick mode:** the shell intentionally runs a partial Python preflight, yet the queue adapter required at least one checked Godot report for every CI mode. A successful quick run therefore could not satisfy the adapter's completion rules. [S7][S8]

**Full/release modes:** the shell replaced the worker-provided diagnostic paths with directories below the materialized source tree, while the adapter inspected the attempt's `checks` directory. Those reports were also outside normal collected output because source is excluded from artifact hashing.

**Correction:** the adapter validates the selected CI mode. Quick success uses its completed shell receipt and remains explicitly partial. Full/release retain checked-report requirements, including expected labels. After inherited admission is validated, the shell preserves the worker-owned diagnostic directories; private runs still create fresh local paths.

**Evidence:** mocked receipt tests for quick and full modes, required-label failure tests, a shell fixture for admitted output paths, and the five existing local-preflight tests. Native Windows still cannot run the Linux/WSL-only local-CI shell as a qualified adapter.

### TQA-06 — Quarantine was not surfaced promptly

The original `wait()` returned on `FINISHED`, readiness or deadline. `UNKNOWN` requires explicit reconciliation and cannot self-heal, so waiting until a long timeout delayed actionable information. A stale `session` field could also satisfy the old readiness condition after the attempt left RUNNING. [S6]

The waiter now returns immediately for `UNKNOWN` and accepts session readiness only in RUNNING. Four focused tests cover quarantine, cleaning, readiness and a non-canceling timeout. Claims remain preserved; returning to the caller is not a cleanup decision.

### TQA-07 — Screenshot evidence could be overwritten

MCP named screenshots by wall-clock second and server PID. Two screenshots from the same server in one second therefore shared a path, and the path returned by the first response could later reference different pixels. [S5]

The filename now includes a UUID. A regression freezes the timestamp, takes two captures and verifies distinct retained paths. This preserves evidence identity without changing screenshot content or the bridge contract.

### TQA-08 — Headless argument parsing was inconsistent

The validator correctly distinguishes engine arguments from application arguments after `--`, but the flag-insertion branch searched all arguments. With `headless: true` and `argv: ["--", "--headless"]`, the actual engine switch was not inserted. [S1]

The existing inherited-scope guard prevented this from becoming a demonstrated rendered-admission bypass; the observed result is a safe failure. The correction checks the engine portion only and inserts the engine flag before the delimiter. The regression verifies the exact argument order.

## 5. Candidate hardening and risks avoided

These are review findings about introducing concurrency safely, not additional baseline incidents.

### H01 — Legacy quarantine must survive the new policy

An old unresolved GOD TEST or debug attempt may have only `rendered/cpu/memory` claims. Merely adding an `exclusive` resource to new jobs would allow new shared work to overlap that old uncertain attempt after restart. The implementation now treats every `UNKNOWN` attempt as a host-wide admission block. A regression reopens a store with legacy claims and verifies that both headless and rendered sharing are refused.

### H02 — Bind what actually launches the screenshot

Checking only the studio `.gd` file would leave the submitted Python adapter, imports, added package initializers and shadow modules mutable. The candidate now binds their inventories and bytes to the authority's startup identity. It repeats the check after materialization, because accepted jobs can survive an upgrade. Regressions cover modified adapters, added initializers/shadow files and a queued job whose authority has changed.

### H03 — Avoid parallel unrestricted debug sessions

Two isolated adapters redirect `debugctl.SESSIONS` to different attempt directories. The baseline port reservation uses a lock under that directory and probes whether a TCP port is currently free. Two modules with separate directories can therefore both reserve the same free default port before either process listens. This was reproduced without Godot. [S7][S9]

General debug sessions remain exclusive, which prevents the new managed sharing policy from exposing that collision. The studio preset has no debug port. A host-owned port allocator would still be needed before parallel unrestricted debug sessions could be supported; this review does not claim to have replaced the old allocator.

### H04 — Filesystem isolation is not desktop isolation

The full application's focus-loss behavior can pause a flight or open a pause screen. A second window can therefore change the first capture's state even when profiles, outputs and caches are separate. Generic debug commands can also start profiling after admission. The studio renderer avoids the flight application and unrestricted bridge, but real GPU/desktop behavior still requires native testing. [S5][S11]

## 6. Verification and CI evidence

### 6.1 Local candidate checks

| Suite | Discovered | Passed | Skipped | Result |
| --- | ---: | ---: | ---: | --- |
| `tools/testqueue` | 94 | 90 | 4 | Pass |
| `tools/debug` | 105 | 104 | 1 | Pass |
| Checked runner | 22 | 21 | 1 | Pass |
| Resource runner | 14 | 14 | 0 | Pass |
| GOD TEST unit fixtures | 17 | 17 | 0 | Pass |
| Local CI preflight fixtures | 5 | 5 | 0 | Pass |
| **Total** | **257** | **251** | **6** | **No failures** |

The queue's four skips on Linux are the three Windows Job Object fixtures and the opt-in Windows desktop campaign. The other suites retain their platform-specific skips. The additional focused reruns are not added to the total, avoiding double-counting the same tests.

The process fixtures demonstrate overlapping lifetimes for two declared headless jobs, two studio-class fake jobs, and a studio-class job with a functional check. They verify independent source/profile/temp paths. The scheduler tests verify exclusive waiting across both resource classes, refusal of younger refill, cancellation, reservations and legacy quarantine. The screenshot adapter tests verify command restrictions and fail closed on absent, mismatched or malformed image evidence.

Additional checks passed: shell syntax, workflow YAML parsing, `git diff --check`, and 42 documentation-link inspections. An existing studio PNG was accepted by the new image validator; this is format compatibility evidence only, not a new capture campaign.

Reproduce the local suites from the candidate checkout:

```bash
python -m unittest discover -s tools/testqueue -p 'test_*.py'
python -m unittest discover -s tools/debug -p 'test_*.py'
python -m unittest discover -s tools/godot -p 'test_run_checked.py'
python -m unittest discover -s tools/godot -p 'test_resource_runner.py'
python -m unittest discover -s tools/godtest -p 'test_*.py'
python -m unittest discover -s tools/ci -p 'test_local.py'
```

Use a local temporary volume with at least the snapshot reserve. Run these as private fixtures without a live inherited attempt capability. The local-CI fixture suite is Linux/WSL-oriented.

### 6.2 Observed baseline CI

The inspected baseline run is [43618805692](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43618805692), at the pinned `95fe1177...` revision. It was still in progress at the observation cutoff on 14 November 2026, with multiple completed failures. These results belong to the baseline, not to the local implementation commit.

| Observed job | Evidence | Interpretation |
| --- | --- | --- |
| [CI selection and release preflight](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43618805692/job/132519617879) | Successful; log records 59 queue tests and 4 skips. | Existing Ubuntu queue coverage ran. It did not execute the Windows-only process tests. |
| [RC native Windows build](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43618805692/job/132520455644) | Successful. | A native component build is not queue, MCP or desktop qualification. |
| [Godot integration](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43618805692/job/132520455723) | Failed on missing `research/native-kernel/build_macos.py` in a package fixture. | The failure occurred before later tool-regression commands in that step could complete. |
| [Godot units shard 4](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43618805692/job/132520456248) | Log shows type-inference parse errors for `generation` and `needs_off` in `airship_scene.gd`. | Separate application defects; do not attribute them to the queue patch. |
| Windows NK-4 and macOS native qualification | Both reported failure in the observed run. | Full baseline CI cannot be represented as green. Root causes were outside this bounded queue repair. |

The existing workflow does invoke debug/MCP and GOD TEST fixtures through `research/test-tools.sh`; the issue is platform placement and dependence on earlier jobs/commands succeeding, not total absence of those suites.

The candidate adds [a dedicated Windows queue workflow](../../../.github/workflows/testqueue-windows.yml) with a bounded sparse checkout, Python 3.12, standard-library fixtures and retained logs. It is independent of the application's long integration step. **Its definition was inspected locally; no successful hosted run is claimed in this report.** It intentionally does not launch the graphical simulator campaign.

## 7. Remaining bugs, limitations and improvement opportunities

| ID | Priority | Remaining item | Proposed owner and acceptance evidence |
| --- | --- | --- | --- |
| R01 | P1 | Snapshot creation and submission-time verification are outside execution claims. | TQ: coordinate preparation with timing campaigns; prove that managed hashing/copying cannot start during an exclusive measurement. |
| R02 | P1 | Per-copy disk checks are not atomic volume reservations. | TQ/storage: reserve estimated bytes transactionally and include imports, outputs, engine copies and history; test two jobs competing for the final free capacity. |
| R03 | P1 | Some research launchers bypass admission, including performance baselines. | Performance/TQ: inventory and wrap launch paths; test refusal when an enrolled authority is unavailable and prevent late unmanaged launches from contaminating measurements. |
| R04 | P2 | Long MCP commands remain synchronous and block later cancellation/control messages. | MCP: add request-scoped cancellation and bounded asynchronous execution without transferring session ownership. |
| R05 | P2 | Parallel unrestricted debug sessions still lack a shared port allocator. | Debug/TQ: allocate ports at the authority and test simultaneous independent clients; keep debug sessions exclusive until then. |
| R06 | P2 | Native Windows simultaneous studio captures remain unqualified. | Windows/graphics: execute the campaign in section 8 before increasing capture slots. |
| R07 | P2 | CPU/memory/GPU capacities are configured slots, not measured budgets. | Performance/TQ: establish conservative per-preset RAM/VRAM peaks and throughput curves. |
| R08 | P2 | Queue, preparation, execution and collection timeouts are not independent. | TQ: bound each phase and report its deadline; test cancellation during slow copy/hash/collection. |
| R09 | P2 | General owner fairness, quotas and bounded aging remain absent. | TQ-04: prevent one owner flooding parallel capacity; preserve the exclusive barrier and explicit resource conflicts. |
| R10 | P2 | GOD TEST resume cannot launch retries through the current enrolled CLI route. | GOD TEST/TQ: add a source-bound resume adapter or explicitly expose its unsupported state. |
| R11 | P2 | Restarting on a different authority root does not import old durable claims. | TQ/operations: retain one canonical root and consider a host-level enrollment identity check; test accidental root changes. |
| R12 | P2 | Per-attempt Git clones and partial-tree Git diff identity can be expensive. | TQ/studio: measure snapshot/history/identity phases; preserve provenance while avoiding unnecessary full-history copies or binary diffs. |
| R13 | P2 | Backup/restore, retained artifacts and durable remote transfer remain unqualified. | TQ-04: test recovery from a consistent database/artifact backup and preserve failed evidence. |

### R01 — Preparation can still disturb an exclusive measurement

`integration.submit()` inventories, hashes and copies a snapshot before its submit RPC. The worker then verifies that snapshot before placing the job in the queue. Both phases can consume substantial CPU and disk while another exclusive attempt is running. Explicit `testctl snapshot` has the same limitation. [S4][S10]

A correct execution lock alone cannot establish a quiet benchmark host. The next design should treat preparation as admitted resource-consuming work, or establish a preparation/measurement barrier with durable ownership and cancellation. Prebuilding snapshots before a measurement campaign is an operational mitigation, not completion of this feature.

### R02 — Disk headroom can be double-counted

Each copy independently checks that free space exceeds its own source size plus the 512 MiB reserve. Two jobs can both pass that check while competing for the same remaining bytes. The estimate also omits some future output, import growth, engine copies and Git history. [S2][S10]

Add reservations by physical volume with conservative estimates and post-copy reconciliation. Do not reclaim space by deleting unrelated snapshots, outputs or user files. Native disk pressure, cancellation and recovery tests should establish that a partial copy never becomes an accepted input or a false test failure.

### R03 — Unwrapped launchers remain an isolation boundary

The reviewed `research/performance/session_baseline.py` uses `subprocess.Popen` directly, and `research/performance/run_visibility_capture.py` uses `subprocess.run` directly. These paths are outside the README's enumerated admitted entry points. A launcher started after a managed benchmark begins can compete even though all queue claims are correct. [S14][S15]

Keep the current claim precise: the queue coordinates cooperating admitted tools under one OS account. Broader enrollment requires a launcher inventory and tests of the real entry points, including child processes and retries. A diagnostic observation of external occupancy should not be misrepresented as enforcement against arbitrary applications.

### R04 — MCP cancellation needs its own lifecycle design

The launch-specific patch removes the post-acceptance readiness wait from managed `sim_launch`, but snapshot preparation and server-side verification still run synchronously before acceptance. During that phase, the stdio handler cannot process a later `sim_stop`. The handler also still processes other tool calls synchronously and ignores notifications, so a long flight, profile or screenshot command can delay a subsequent stop request. [S4][S5]

The negotiated MCP specification supports optional request cancellation and describes races with already-completed requests. A future implementation should track request IDs, separate canceling a tool operation from canceling the durable queue job, and retain ownership through cleanup. It must not release a session because a client stopped waiting. [S16]

### R08/R12 — Measure phase costs before increasing concurrency

The current execution deadline starts after materialization. Large preparation and artifact-hash phases can hold claims substantially longer than the requested process timeout. The studio source-identity routine also runs Git status and a binary diff twice; with a partial materialized tree, its worktree status describes that materialization rather than the submitter's original complete checkout. The queue manifest remains the authoritative record of captured bytes. [S2][S10][S11]

Record queue wait, verification, copy, history, imports, execution, cleanup and collection separately. Evaluate snapshot reuse only with immutable content identities and private writable caches. Do not infer speedup from the number of workers or weaken source verification to improve a timing number.

## 8. Windows qualification and rollout plan

### Stage 1 — Keep the conservative configuration

Start with one headless slot and one capture slot on a local authority root. Drain the old worker, close owned sessions and inspect all claims before replacing it. Preserve the existing database and retained evidence. An old unresolved attempt must remain quarantined under the new worker; changing roots or deleting lock files is not recovery.

Run the dedicated Windows process/MCP workflow and the existing Python suites on the intended Python version. Confirm that the Windows-only process tests actually execute and that the graphical campaign is reported as skipped unless deliberately enabled. A passing hosted Windows job closes a process-fixture gate, not the user's desktop/GPU gate.

### Stage 2 — Execute the real 1080p ownership campaign

Use the existing opt-in native test with the pinned Windows console executable and a fresh evidence directory, on an active unlocked desktop without unmanaged simulator sessions. Preserve the host, boot, engine and source identities. The campaign must validate two independent clients, correct handle refusal, serialized generic sessions, cancellation, complete cleanup and refusal when the enrolled worker is unavailable. The updated native assertion expects exclusive admission rather than the old rendered-slot reason.

### Stage 3 — Qualify parallel studio captures

With `--capture-slots 2`, submit two different catalog aircraft from independent snapshots. Verify overlapping owned process lifetimes, distinct project/profile/import/temp/output paths, correct model IDs, valid complete manifests and actual 1920×1080 PNGs. Inspect the images for blank frames, wrong models, clipping or focus-related changes. Repeat with one studio capture and one declared functional headless check.

Then place an exclusive performance job between active shared work and younger shared requests. Confirm that the performance job begins only after all predecessors' cleanup and collection finish, and that younger work starts only after its own release. Include cancellation of the waiting exclusive request, a locked desktop, a human reservation, and an injected cleanup failure.

### Stage 4 — Measure efficiency without losing coverage

Compare serial and parallel runs using identical source, engine, aircraft, resolution, renderer, imports and output requirements. Record total completion time, queue-wait distribution, per-phase duration, peak RAM/VRAM, disk consumption and failure rate. Include repeated runs and retain failures. Choose the largest capacity that improves throughput without unacceptable memory pressure, capture failures or measurement contamination.

Performance comparisons themselves must be exclusive. Any gain from faster screenshots must not be reported as a simulator frame-rate gain. Keep the functional/screenshot/performance classifications visible in receipts so reviewers can understand what was allowed to overlap.

## 9. Team handoff and review order

The implementation is one focused commit plus this audit. Review the production changes in this order:

1. [Preset policy](../../../tools/testqueue/presets.py) and [transactional claims](../../../tools/testqueue/store.py): conservative defaults, trusted declarations and global exclusion.
2. [Worker lifecycle](../../../tools/testqueue/worker.py): fairness, legacy quarantine, authority identity, process locking and retained claims.
3. [Studio adapter](../../../tools/testqueue/adapter.py): fixed command, history/import preparation and evidence validation.
4. [MCP](../../../tools/debug/mcp_server.py) and [integration](../../../tools/testqueue/integration.py): accepted versus ready, retained ownership, cancellation and unique screenshot paths.
5. [Local CI](../../../tools/ci/check-local.sh), [checked runner](../../../tools/godot/run_checked.py) and [Windows workflow](../../../.github/workflows/testqueue-windows.yml).
6. The corresponding regression fixtures and [operating guide](../../../tools/testqueue/README.md).

The implementation adds no runtime package dependency. The operating behavior changes are intentional: unrestricted debug sessions and unknown checks are now exclusive, pending managed-MCP launches are successful accepted requests rather than launch failures, and any uncertain cleanup blocks new execution. Users relying on previous headless debug concurrency should migrate genuinely functional work to the checked contract instead of bypassing admission.

The branch is a review candidate. Publishing it does not qualify the Windows graphical path, merge it into `main`, install a worker or change a live authority. The next promotion decision should use the actual branch's hosted results plus the native acceptance evidence above.

## 10. Source references

Baseline links are pinned to the audited commit. Candidate implementation links above point to files in this branch. External references explain protocol/OS constraints; they are not substitutes for the repository's own tests.

[S1]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/tools/testqueue/presets.py#L11
[S2]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/tools/testqueue/worker.py#L124
[S3]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/tools/testqueue/store.py#L96
[S4]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/tools/testqueue/integration.py#L15
[S5]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/tools/debug/mcp_server.py#L164
[S6]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/tools/testqueue/common.py#L145
[S7]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/tools/testqueue/adapter.py#L18
[S8]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/tools/ci/check-local.sh#L57
[S9]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/tools/debug/debugctl.py#L457
[S10]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/tools/testqueue/snapshots.py#L306
[S11]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/tools/readme/capture_aircraft.gd#L237
[S12]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/docs/plans/agent-test-orchestrator.md
[S13]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/external%20Audits/CONSOLIDATED-AUDITS.md
[S14]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/research/performance/session_baseline.py#L976
[S15]: https://github.com/bultodepapas/OpenRCsimulator/blob/95fe1177f26929a12bd032c12e7ac3352eef304d/research/performance/run_visibility_capture.py#L43
[S16]: https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation

Microsoft's [Job Object completion-port reference](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_associate_completion_port) documents that ordinary completion notifications are not guaranteed and that PID reuse requires retaining process handles when identity matters. This supports preserving the existing conservative cleanup design: absence of a notification, a dead-looking PID or the launcher's exit is not sufficient proof to release ownership. The queue should retain uncertainty when its teardown evidence is incomplete.

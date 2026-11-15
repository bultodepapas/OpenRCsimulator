# Shared-host test orchestration

Owner: shared-host test admission, prefix **TQ**. Operating contract:
[tools/testqueue](../../tools/testqueue/README.md). This implements the local safety
foundation from the supplied OpenRC Test Orchestration Plan v0.2 (2026-11-12),
reviewed against current source rather than assuming its bca0965 baseline still applies.
Physics, hosted CI policy and other tracks' acceptance gates remain with their owners.

| Step | Work | Evidence and status |
| --- | --- | --- |
| TQ-00 | Inventory and reuse decision | Jenkins documentation and local availability assessed; provisional embedded SQLite choice in DECISIONS. Jenkins live contention/restart/disconnect comparison remains open. Remote topology, budgets and native adapters are unverified. |
| TQ-01 | Local ownership foundation | Durable authority, atomic claims, frozen inputs, Job supervision, cancellation, explicit CLI/MCP control and protected shell entry points implemented. Native Windows fake-process and contract fixtures cover contention, lifetime, isolation and failure evidence. Real simulator qualification remains open. |
| TQ-02 | Linux distribution | Source-bound independent checked jobs now run through the [configured Linux SSH host](../tools/linux-ssh.md), with idempotent transport, isolated imports and retained evidence. Composite adapters, software-capture qualification and coordinated host/storage budgets remain open; see the distributed checked-test evidence below. |
| TQ-03 | Mac qualification | [Both M1 SSH routes and current tools](../tools/macos-m1.md#two-m1-windows-workflow) have native headless checked-job evidence with pinned engines. Broader profile/preferences and calibration preservation, a logged-in GUI adapter and graphical qualification remain open. GOD TEST's Darwin refusal remains. |
| TQ-04 | Operational refinement | Basic FIFO, manual reserve/release and drain implemented; the checked pool collects verified artifacts. Per-owner quotas, bounded aging, explicit retry history, separate queue/idle/collection policies, backup/restore campaign and automated evidence retention remain pending. |

## Scheduling review candidate, 14 November 2026

### Distributed checked-test implementation, 14 November 2026

The [automatic pool](../../tools/testqueue/README.md#automatic-multi-host-checked-tests)
adds explicit multi-host headless checked batches, measured-duration placement,
platform requirements, SSH agents, durable same-host recovery and verified local
artifact collection. Windows uses the existing authority. ANGEL, ANGELA_AIR and
Linux have deployed agents and pinned engine identities. The source archive is
verified against the original snapshot's bytes before transfer; target imports
and unique user profiles are generated separately.

The [MCP checked-batch interface](../../tools/testqueue/README.md#mcp-checked-batches)
exposes asynchronous launch, durable status and same-request recovery to agents.
Its default is the caller's platform; cross-platform placement requires an explicit
`any` declaration. Native MCP acceptance used a four-host math-check matrix:
all four jobs passed with verified local artifacts after the original MCP client
exited. A new client observed the same completed IDs, and recovery did not rerun
them. Launch returned in 0.125 seconds; a fresh-client status call returned in
0.156 seconds. These are responsiveness observations, not throughput benchmarks.
Receipts are `acceptance/mcp-launch.json` and `acceptance/mcp-final.json` under the
pool root, with the frozen batch at `mcp/mcp-946ebd68d67b45008868ff3ce8e32618`.
Focused pool/transport/MCP fixtures passed 74 tests; the final collection and
receipt-concurrency follow-up passed 23 overlapping tests. These cover lost
launch replies, interrupted freezing, same-ID recovery, per-job receipt locking
and terminal infrastructure failures without checked reports. Codex registration,
agent guidance and mirrored tool skills now route compatible checks to this API.

Native existing math checks passed on Windows, both M1s and Linux, including an automatically
selected Linux run and an automatic batch selecting available Macs. Each checked
run reported 20 checks, zero failures and confirmed cleanup. Native transport
fixtures passed ten cases each on Windows, Linux and ANGEL. The coordinator,
planner, batch, hook and transport fixtures passed 37 cases on Windows; the
existing checked-runner suite passed 22 cases with one platform skip.
Local raw receipts are under `C:\ProgramData\OpenRC\testpool\acceptance`, with
per-job reports in `results` and retained batch states in `batches`.
The Windows acceptance first exposed an old running authority's metadata-copy
failure. After draining to zero active claims, restarting with the existing
metadata fix and resuming admission, the new Windows native attempt passed with
verified collection. Prior failed receipts remain retained.

TQ-02 now has a bounded checked-job transport. TQ-03 graphical qualification,
composite suite/CI distribution, automatic benchmark migration, cancellation of
active remote jobs and automated cache/evidence retention remain open. Initial
remote capacity is one exclusive attempt per physical host. The planner's
estimates and fixture timings establish no measured end-to-end speedup.

The review against `95fe1177f26929a12bd032c12e7ac3352eef304d` adds explicit
exclusive/parallel admission, an eligible-exclusive waiting barrier, global UNKNOWN
quarantine (including legacy claims), a restricted aircraft studio-still preset and
pending MCP session ownership/status. The operating policy and trust boundaries live
in the [queue guide](../../tools/testqueue/README.md#parallel-and-exclusive-admission).
It also fixes closed-process occupancy observation, quick/full CI evidence routing,
same-second MCP screenshot overwrite and inherited resource-sampling admission.

Linux candidate checks: queue 94 tests (4 skips), debug/MCP 105 (1 skip), checked
runner 22 (1 skip), resource runner 14, GOD TEST 17 and local CI fixtures 5. These
257 tests include 251 passes and 6 skips. A focused Windows workflow is added for
queue/process/MCP fixtures. Hosted execution and the real Windows 1080p campaign
remain separate gates; this entry does not claim their completion. In particular,
two real studio captures still need qualification before increasing capture slots.
Client-side snapshot creation/verification, coordinated disk reservations and direct
research-launcher enrollment remain follow-up work. No hardware speedup is claimed.

## Windows audit follow-up, 14 November 2026

Reviewed the [Windows queue/MCP audit](https://github.com/bultodepapas/OpenRCsimulator/blob/audit/windows-testqueue-20261114/docs/research/testqueue/2026-11-14-windows-queue-mcp-audit.md)
and reused its implementation commit `6913c918e2664d01818526e3162e71e761263796`.
The eight confirmed findings and legacy quarantine/studio dependency hardening are
integrated. Additional independent review found a lost-submit-reply ownership gap:
MCP now retains its receipt before RPC, recovers the original handle without input
verification, and replays only the same launch request. Status never creates a job.
Stop records cancellation by request identity before a delayed original submit can
become dispatchable. Schema 2 preserves these cancellations across restart; migration
retains version-1 jobs and claims. The CLI exposes recovery and submission cancellation.

Native Python 3.12 also exposed Windows path/handle `ctime` disagreement that rejected
unchanged snapshots and host-helper identities. Both comparisons use Windows birth
time while preserving POSIX change time and the remaining file/hash checks. The two
research launchers named in R03 now require exclusive inherited admission with their
actual headless/rendered scope; standalone adapters remain unavailable. GOD TEST
resume reports its unsupported enrolled standalone state before inspecting old suites.

Verification used Python **3.12.12 on native Windows**, private fixture authorities
and a fresh shared-object clone with the Windows workflow's sparse inputs plus the
working patch over `c66df1efc`. Another session committed the production edits during
this work; the frozen verification copy excludes unrelated concurrent controller edits.

| Suite | Tests | Passed | Skipped |
| --- | ---: | ---: | ---: |
| Queue and Windows process containment | 106 | 103 | 3 |
| Debug/MCP | 107 | 106 | 1 |
| Checked runner | 22 | 21 | 1 |
| Resource runner | 14 | 14 | 0 |
| GOD TEST fixtures | 18 | 18 | 0 |
| Session baseline/research admission | 64 | 64 | 0 |
| **Total** | **331** | **326** | **5** |

All suites passed. Skips cover POSIX-only fixtures and opt-in real-engine/desktop
campaigns. Checked-runner process teardown needed execution outside the tool sandbox,
which denied `taskkill` on its own child fixtures; the native run passed without a
cleanup implementation change. Raw logs and the frozen candidate patch are retained
under ignored `tmp/testqueue-audit-fix/` (`sparse-*-windows.log`, `verification.patch`).
Shell syntax, workflow YAML parsing, 26 Python parse checks, new local document links
and whitespace checks passed. The Windows workflow includes all six suites and pins
the tested Python 3.12.12. No hosted run or real simulator/GPU result is claimed.

The five local-CI shell fixtures also passed under WSL Ubuntu/Python 3.12.3 from a
Linux-line-ending export of the tested shell/queue sources at `c66df1efc`; the mounted
Windows checkout's CRLF scripts cannot represent a Linux CI checkout. Their retained
log is `tmp/testqueue-audit-fix/local-ci-wsl.log`. Combined: **336 tests, 331 passed,
5 skipped, no failures**. Repeated diagnostic runs are not added to this total.

R01 preparation outside claims, R02 volume reservations, general unwrapped launchers,
request-scoped MCP cancellation and the audit's other operational/hardware gates
remain open. Keep capture capacity at one until the actual parallel 1080p campaign
is qualified. Software fixtures establish no physical validation or measured speedup.

The native release gate requires five independent worktrees/clients, actual simulator
lifetime exclusion, nested GOD TEST/checked flows, worker crash/cancel recovery,
unmanaged-session preservation and complete evidence on the supported Windows desktop.
All configured launchers must refuse bypasses while the authority is unavailable.
Fake runners establish orchestration logic and real OS process containment, not
rendered simulator acceptance. The host must be free of unmanaged sessions before
attempting that campaign. Do not kill another agent's Godot process to qualify it.

At this Windows audit, the first implementation used a local combined coordinator/worker
with a loopback JSON protocol. SQLite is not a remote shared database. That local
worker does not advertise remote hosts or accept `any-qualified`; the separate checked
pool described above now provides bounded remote jobs. Windows authority state
must reside on a local volume with sufficient space. A machine-wide singleton also
prevents independent worktree/root authorities from owning the same Windows host.

Implementation checks use `tools/testqueue/test_*.py`; retained generated fixtures
belong outside the checkout. The working tree changed concurrently during development;
some initial queue files were included by another track's d06844f commit. Final
verification applies to the integrated working candidate, not that incomplete commit.

## Local evidence on 12 November 2026

Native Windows fixtures verify actual process lifetimes, including five competing
rendered owners and retained orphan children. WSL fixtures cover the cooperative
POSIX boundary. The admission suite passes 59 cases on each platform, with two
Windows skips and four WSL skips. Existing debug/MCP (102 cases), GOD TEST (17), checked-runner (21)
and Linux CI orchestration (125) fixtures pass with their platform-specific skips.
The new admission suite also runs in the hosted scope job and local quick checks.

The opt-in native campaign reached a real **1920×1080** Home session on NVIDIA
RTX 3090 / OpenGL compatibility, with the pinned 4.8 beta2 Windows binaries. An
incorrect owner handle was rejected. A newly appearing unmanaged simulator then
blocked the second request, so the full contention campaign is **not qualified**.
The first owned session stopped with confirmed cleanup; the interrupted preparation
of the second attempt retains its conservative dispatch claim in that private test
authority. This exposed the need for cancellation during large copies; verification
and materialization now check durable cancellation, with a nonexecution regression.
The native harness cancels all requests before waiting for teardown.

Raw native evidence is retained outside Git under
`D:\OpenRC-testqueue-evidence\native-20261112-r2` (JSON/SQLite/logs, no committed
images). Reproduce with the opt-in campaign in the operating guide on a reserved,
otherwise idle Windows host. These observations establish no performance benchmark,
physical validation or Linux/Mac adapter qualification.

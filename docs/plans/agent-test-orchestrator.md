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
| TQ-02 | Linux distribution | [SSH configured and connected](../tools/linux-ssh.md) with the existing pinned identity on 2026-11-12 after the VM was brought online. Linux x86_64, Python 3.12.3 and the clean existing checkout were verified. The remote checkout lacks queue sources. Persistent worker, structured idempotent transport, host/parent/storage budgets, isolated imports and software-capture qualification remain pending. POSIX helper tests do not close this gate. |
| TQ-03 | Mac qualification | [Both M1 SSH routes and current tools](../tools/macos-m1.md#two-m1-windows-workflow) verified on 2026-11-14 with a focused native headless math check. Remote-worker qualification still needs actual resolved profile-path proof, preferences/calibration preservation, adapter-bound ARM64 engine identity and a logged-in GUI adapter. GOD TEST's Darwin refusal remains. |
| TQ-04 | Operational refinement | Basic FIFO, manual reserve/release and drain implemented; per-owner quotas, bounded aging, explicit retry history, separate queue/idle/collection policies, backup/restore campaign and durable artifact transfer remain pending. |

## Scheduling review candidate, 14 November 2026

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

The first implementation uses a local combined coordinator/worker with a loopback JSON
protocol. SQLite is not a remote shared database. Remote hosts remain unadvertised;
`any-qualified` is refused until a platform adapter has been qualified. Windows state
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

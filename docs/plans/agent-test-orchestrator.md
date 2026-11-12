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
| TQ-02 | Linux distribution | Pending persistent SSH worker, structured idempotent transport, host/parent/storage budgets, isolated imports and software-capture qualification. POSIX helper tests do not close this gate. |
| TQ-03 | Mac qualification | Pending actual resolved profile-path proof, preferences/calibration preservation, ARM64 engine identity and logged-in GUI adapter. GOD TEST's Darwin refusal remains. |
| TQ-04 | Operational refinement | Basic FIFO, manual reserve/release and drain implemented; per-owner quotas, bounded aging, explicit retry history, separate queue/idle/collection policies, backup/restore campaign and durable artifact transfer remain pending. |

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

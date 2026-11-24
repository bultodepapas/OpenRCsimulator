# Telemetry system audit — 22 November 2026

**Decision:** prioritize the receiver's admission/aggregation mismatch and the independent monitor's missing actionable warnings. The audited code can accept data that prevents completion of a daily rollup, while the separate health check can remain green during the available recovery window. Client measurement errors, queue deadline violations and conditional operational weaknesses also need repair before the telemetry is used as a reliable basis for product decisions.

This is an evidence-backed code and operational-design audit of OpenRC Simulator's telemetry stack. The first pass contains **13 findings: 2 High, 10 Medium and 1 Low**, with conditions and confidence stated individually. Nine findings have local behavioral counterexamples, one conditional scheduling issue has a systemd calendar check, and three findings are supported by traced source paths without a rendered application reproduction. A separately reproduced consent-persistence problem is retained as a previously documented residual risk, outside the count of 13.

## Deeper review added the same day

The [second pass](second-pass.md) adds **five correctness/recovery findings, two validation gaps and three optimization opportunities** against the same runtime baseline. It includes [client](second-pass-client.md) and [operations](second-pass-operations.md) detail, six new behavioral counterexample cases, two measured optimization paths and two source-level entries. These categories are separate from the 13 first-pass findings below. The [round-two package](../../../../research/telemetry/audit-2026-11-22/round2/README.md) retains the new probes, measurements and provenance; the original verification totals are not presented as rerun results.

## Current-main follow-up — 23 November 2026

The [dated follow-up](follow-up-2026-11-23.md) separately reviews current `main` at pinned `85fc06ff3ed0074586691c1a7fce70687ea1558a` (98 commits past the original baseline). Its source review found targeted implementation/test changes for the **two original High findings**, plus several client, publisher, credential and backup findings; **the original November 22 counts below describe the original baseline**, not confirmed defects in the newer head. The follow-up also traces a **new conditional dynamic-internal-resolution measurement gap** and retains a **bounded SQL quota-threshold demonstration** with exact limits and caveats. Its [round-three evidence](../../../../research/telemetry/audit-2026-11-22/round3/README.md) is documentation and one synthetic SQLite probe only; it does not verify production fixes or rerun the Python/Godot suites.

## Source identity and deliverables

| Item | Identity |
| --- | --- |
| Repository | [bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator) |
| Audited baseline | [`7940a4081e10994f34c858c4acac3d7a1a271464`](https://github.com/bultodepapas/OpenRCsimulator/commit/7940a4081e10994f34c858c4acac3d7a1a271464), refreshed `origin/main`, “PT1-CI-00: prepare OpenRC Simulator v0.3.3” |
| Audit branch | [`audit/telemetry-2026-11-22`](https://github.com/bultodepapas/OpenRCsimulator/tree/audit/telemetry-2026-11-22) |
| Audit date | 2026-11-22, user-facing date in America/Bogota; UTC is explicit in all telemetry boundary examples |
| Change scope | Reports, synthetic reproductions, retained evidence and research-index link |
| Source evidence | Immutable baseline permalinks in every finding; [135-file primary-source inventory](../../../../research/telemetry/audit-2026-11-22/evidence/source-inventory.json) with SHA-256 hashes |

The work used an isolated branch/worktree. The findings apply to the pinned source snapshot. The current production deployment, credentials, proxy configuration, user database and notification delivery were not accessed. Historical live observations from the 19 and 21 November audits are dated evidence, not proof of today's deployed state.

## Reports

| Report | Contents |
| --- | --- |
| [Client and local HUD](client-and-hud.md) | Context and epoch boundaries, crash counting, simulation pause, queue/pending age, HUD terrain composition, local export cleanup and consent residual risk |
| [Receiver and publication](receiver-and-publication.md) | Admitted numeric representation blocking rollup; concurrent publication race; controls that should be preserved |
| [Operations](operations.md) | Warning propagation, credential file permissions, backup usability and timer timezone alignment |
| [Verification](verification.md) | Exact test scope, retained results, reproduction method, environment adjustments and limitations |
| [Scope and remediation](scope-and-remediation.md) | System map, reviewed boundaries, prior-audit reconciliation, ordered repair plan and deployment acceptance evidence |
| [Reproduction package](../../../../research/telemetry/audit-2026-11-22/README.md) | Five Python and six Godot counterexamples, portable runners, output and source hashes |

## Prioritized findings

Severity expresses impact and repair priority for this project; it is not a claim of exploitation or a CVSS score. **High / P1** means a broad failure or missed time-sensitive recovery that should be addressed first. **Medium / P2** means incorrect measurements, a bounded lifecycle violation, or an operational failure requiring a stated condition. **Low / P3** means a narrow recovery or maintenance defect with limited demonstrated impact. A positive counterexample proves the particular behavior, not its frequency among players.

| ID | Severity | Finding and consequence | Evidence |
| --- | --- | --- | --- |
| [TA22-R01](receiver-and-publication.md#ta22-r01--an-admitted-integral-json-number-aborts-the-entire-daily-rollup) | High | `1800.0` is accepted as an integer-valued metric, then rejected during cell encoding; the entire receipt-day rollup remains uncommitted. | Real ingress + rollup, 21 stored synthetic batches |
| [TA22-O01](operations.md#ta22-o01--high-actionable-receiver-warnings-do-not-reach-the-independent-health-check) | High | Dashboard warnings about an overdue rollup and retention proximity are dropped from machine health; the independent checker returns healthy. | Real dashboard and checker, synthetic snapshot |
| TA22-C01 | Medium | A complete performance window can mix 1080p and 2160p observations and be labeled entirely 2160p. | Pinned Godot, actual service |
| TA22-C02 | Medium | UTC/four-hour session boundaries rotate only on append; open observations can migrate into the new epoch. | Pinned Godot; previously open boundary now reproduced |
| TA22-C03 | Medium | One accident and its terminal revision increment the crash metric twice, including across five-minute slices. | Real detector events + actual service |
| TA22-C04 | Medium | A focused simulation pause can remain eligible and accumulate active-flight time with no simulated-time progress. | Source path; rendered crash flow unqualified |
| TA22-C05 | Medium | Sealed in-flight data survives its queue deadline; pre-seal aging also conflicts with the player-facing ten-minute pending-data claim. | Two pinned Godot counterexamples |
| TA22-R02 | Medium | Concurrent publishers can create two GitHub issues from one approved intent; the ledger retains one number. | Two SQLite connections + fake GitHub |
| TA22-O02 | Medium, conditional | OAuth credentials are written as mode 0644 under umask 022; other local users can read them if ancestor permissions/ACLs allow traversal. | Fake OAuth; POSIX permission check |
| TA22-O03 | Medium | Backup validation accepts a structurally unusable GitHub-history database that the real archive reader cannot load. | Synthetic SQLite archive + actual reader |
| TA22-O04 | Medium, conditional | CT backup uses local time while export/pull use UTC, allowing a multi-hour ordering gap on a non-UTC CT. | Unit source + systemd calendar in America/Bogota |
| TA22-H01 | Medium, conditional | Local flight HUD height above ground omits enabled RC-track relief, affecting displayed AGL and warning thresholds. | Composed-terrain producer/consumer source trace |
| TA22-L01 | Low, conditional | A failed local recording metadata write leaves an orphan temporary file and blocks reuse of that basename. | Export/error-cleanup source trace |

Detailed client/HUD IDs are in [client-and-hud](client-and-hud.md); operations IDs are in [operations](operations.md). The consent case, WAL/all-copy deletion qualification, CI/release coverage and live-host checks are recorded separately rather than counted again as new defects.

## What the tests establish

- **370 distinct Python tests passed; 2 Windows-specific tests remain skipped on Linux.** The receiver discovery run initially skipped the Godot bridge; that same bridge was then executed separately and passed against a real loopback receiver. It is counted once.
- **Five existing core Godot suites passed** under the pinned `4.8.beta2.official.cafc17a19`: queue, service, sender, admission and contract. Their checked-run logs have no errors or warnings.
- Generated schemas and examples match their sources.
- **Five Python and six Godot audit counterexamples reproduced.** A successful counterexample means the undesirable baseline behavior was observed. These are not repair tests passing against a fixed implementation.

Full output, hashes and caveats are in [verification](verification.md). This is focused source and headless integration evidence, not a full application/CI run, native-platform release qualification, target-hardware benchmark or live production audit.

## Recommended repair order

1. Make numeric admission and downstream aggregation agree, including already stored records. Wire actionable rollup and retention alerts through the independent monitor and verify delivery before the 47-hour rollup boundary.
2. Repair client context/epoch boundaries, unique-accident counting, actual simulation-pause eligibility, and monotonic pending/in-flight deadlines. Add the counterexamples as regressions with expected-correct assertions.
3. Add an atomic publication claim; protect OAuth files; validate backups by actual reader/restore behavior; make timer timezone/dependency ordering explicit.
4. Supply the HUD with the authoritative composed terrain, clean up failed local recording metadata, and close the documented consent and deployment qualification decisions.

The [remediation matrix](scope-and-remediation.md#repair-sequence-and-acceptance) defines concrete acceptance evidence for each work item. This branch records the audit and its reproductions; finding closure requires a separately reviewed repair and verification record.

## Current-main follow-up — 24 November 2026

The [fourth-pass report](follow-up-2026-11-24.md) pins main at `19e9e69dda17261a7761625958d038a646608e8c` and adds two conditional rollup input-integrity findings (absent source and stale eligibility at snapshot time), a publisher discovery-budget planning gap, offline model evidence, and prior-pin CI job results. The original findings and prior dispositions remain historical; no production fix or full new-head suite pass is claimed. [Round-four probe and receipt](../../../../research/telemetry/audit-2026-11-22/round4/evidence/rollup-boundaries.json).

# Repository state reviewed on 2026-11-15

**Reviewed main:** [`ad21070798bfb9658785576a9c0b8bfc9a71fc7f`][main].
**GitHub observation:** 2026-11-15 **07:11:04 America/Bogota**
(12:11:04 UTC). This is a dated snapshot; later workflow completions and commits
must be checked separately.

The repository has progressed substantially since the original audit: its
reviewed main is **151 commits ahead** of
`45d86d250f6e38a3d9b60d30c01bdc2396571efe`. The first five findings have received
scoped corrections. Three round-two defects remain in inspected source, and
current main does **not** have a clean CI result. The audit integration preserves
both original reports and their evidence while updating the existing pending
queue and completed-work ledger.

## Source and integration scope

| Property | Observed value |
| --- | --- |
| Repository | [bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator), public, default branch `main` |
| Historical audit | `45d86d250f6e38a3d9b60d30c01bdc2396571efe`, 2026-11-09 |
| Reviewed main | `ad21070798bfb9658785576a9c0b8bfc9a71fc7f` |
| Reviewed tree | `cca9ad99ee0d1a6b5f70f1a960c8f8f36f488bf8` |
| Main commit time | 2026-11-15 06:42:39 America/Bogota / 11:42:39 UTC |
| Main subject | Add comprehensive tests for pool checked, concurrency, MCP, policy, and remote agent functionality |
| Pinned project engine | Godot 4.8.beta2.official.cafc17a19 |
| Integration branch | `audit/consolidated-review-2026-11-15`, based on the reviewed main |
| Integration change | Original reports/ZIPs, integrity and source manifests, dated status review, canonical audit navigation and pending actions |

This review used a sparse text checkout and Git objects for source comparisons.
Missing imported/binary assets in that checkout were not classified as game
defects. The branch's runtime source and generated aircraft data remain those of
the reviewed base; the publication is an evidence and documentation integration.
It does not implement the three remaining runtime corrections.

The public integration omits two pre-existing personal ChatGPT resource links
from the updated audit ledger, retaining its local report references and explicit
uninspected-source limits. Three official Godot documentation links in the A34
summary retain their destinations with tracking parameters removed. The four
original audit deliverables remain byte-identical.

## Audit disposition

See the [full reconciliation](README.md) for derivations, historical controls,
source links and qualification limits. The [source manifest](source-review.json)
records inspected paths and their Git identities.

| Findings | Current conclusion | Remaining boundary |
| --- | --- | --- |
| F01 reverse-flow wing law | Repair is present, with retained regression/native comparison evidence | No fresh execution on this review commit; numerical consistency is not aircraft calibration |
| F02 graphics-dependent obstacles | Selected scenario collision is independent of visual quality; regression checks are authored | Explicit scenery-off is a separate scenario; broad target rendering/performance remains outside this intake |
| F03 stale locks | Qualified version-2 lease recovery corrects the original numeric-parser cause | Legacy three-field, unsupported and ambiguous locks remain deliberately read-only |
| F04 optional preloads | The originally measured material/selected-resource paths are corrected | Ground-effect script preloads and shared texture residency need actual-path measurement; no current whole-app memory saving established |
| F05 cloud seed binding | Actual eligible layer seeds are bound and selected | Cloudy-to-cloudy cache admission is already tracked under A28 / DT-MAC06b |
| F06 swept lake normal | Wrong horizontal signs remain in the positive-down normal helper | Reproduce the old full-session witness on the new surrounding session before quoting a current crash magnitude |
| F07 bank crash tolerance | Swept lake queries still omit prepared aircraft-specific limits | Add independent energy and depth cases; authored X99 limits remain estimates |
| F08 repeated quarantine | An existing per-slot quarantine still disables writes despite an owned writer lock | Test repeated corruption, healthy healing, distinct damaged bytes and deletion-fence integration |

The [pending queue][pending] assigns A35 F06/F07 to the existing ground/lake
owners and A35 F08 to flight statistics. It retains the lower-priority glare
profiling lead, optional-resource follow-up and cloud-transition work without
inflating the defect count. A34's local-wing closure question remains research.
The [completed ledger][completed] retains its delivered scopes and evidence;
this intake does not erase working corrections or turn historical checks into
new passes.

## Current CI: failures are confirmed, overall execution is incomplete

The [machine-readable snapshot](ci-status-2026-11-15.json) records the workflow
and job URLs, timestamps, conclusions, inspected failure excerpts and open PR
heads. All three workflows below refer to reviewed main `ad210707`.

| Workflow | Status at observation | Interpretation |
| --- | --- | --- |
| [Windows test queue regressions][windows-run] | Completed, failure | The queue-contract step ran 164 tests with two failures and three skips; later steps were skipped |
| [MetalFX source controls][metalfx-run] | Completed, success | Source-control validation passed; this does not qualify native MetalFX image quality, latency or speed |
| [CI][ci-run] | In progress, with three failed jobs already completed | Seven jobs were unfinished in the returned 23-job snapshot; pending jobs are not passes |

### Windows path-comparison failures

The [failed queue job][windows-job] names
`test_launch_is_local_and_idempotent_across_clients` and
`test_supervisor_freezes_once_and_resumes_original_manifest` in
`test_pool_mcp.PoolMcpTests`. Mocked calls differ between raw `RUNNER~1`
temporary-directory paths and resolved `runneradmin` paths.

The [fixture][pool-test] keeps its raw temporary path, while
[`pool_mcp.py`][pool-source] resolves the production source/directory paths. This
explains the observed representation mismatch. It is not evidence that the
scheduler loses jobs or that flight simulation is broken. A correction should
compare the intended canonical path contract and retain real Windows process
containment checks. No CI fix or rerun was performed during this intake.

### Controls dialog label assertion

[Godot units 0][units0-job] reports **25 of 26** checked invocations passed and
one failed. `test_controls_setup_p0.gd` fails the compound Save/Discard/Keep
editing label assertion, with process exit 1 and no classified engine errors
or warnings.

Current [dialog construction][controls-source] assigns `tr("Save current")`,
while the [test][controls-test] expects literal `"Save"`. That is a concrete
source mismatch and the likely cause of the logged assertion. The log does not
print all three actual labels, so this remains an inference, not a fresh runtime
diagnosis. Follow-on Save/Discard/Keep behavior checks reported OK in that
invocation. Align the expectation with the intended product copy and rerun the
focused contract before changing behavior.

### Aerodynamic provenance gate

[Godot integration 0][integration-job] reports **six of seven** checked
invocations passed and one failed. The failed
`research/aero/d11g/derive_rate_derivatives.gd` invocation rejects
`aero.coefficients.Cmq.source`, `CLq.source` and `Cnr.source` because they do not
match current or qualified historical provenance. It exits 1 with three
classified engine errors.

The cause was not investigated in this integration. Resolve the relationship
between the generated coefficient records and their actual source identity;
blindly replacing provenance hashes would not establish validity. The observed
failure does not by itself disprove the F01 reverse-flow correction or establish
physically wrong coefficients.

### Shaft fixture source identity

[Godot units 2][units2-job] reports **103 of 105** checked invocations passed,
one skipped and one failed. `test_shaft_publication.gd` reports
`FAIL source-bound shaft fixture loads` and
`fixture manifest or source identity differs`. Its failed invocation has no
classified engine errors or warnings. Cause and any required fixture rebind
remain uninvestigated.

The separate skipped lighting-skin pixel invocation explicitly requires a native
renderer at 1920×1080; it must not be counted as passing image qualification.

These four failure groups belong in CI triage alongside the three unresolved
audit defects. They are not relabeled as additional historical audit findings.
Native builds or another successful source-control job cannot substitute for a
complete green run at the final integration candidate.

## Open work on other branches

The GitHub observation returned three open draft PRs targeting `main`:

| PR | Scope | Recorded head |
| --- | --- | --- |
| [#12](https://github.com/bultodepapas/OpenRCsimulator/pull/12) | Guarded MetalFX trials and native RT input diagnostics | `f5219d7d682a7f2470bbf2af88c2cf64c1fe7833` |
| [#11](https://github.com/bultodepapas/OpenRCsimulator/pull/11) | Bounded circuit mesh cache and parked ORM texture-read reuse | `7171aef8111aa7005267d3eb2bff64caa311ffdb` |
| [#10](https://github.com/bultodepapas/OpenRCsimulator/pull/10) | Report preservation and debug contracts, PT1h-R13/R14 | `644f4e7370fc4d0cb4efe254b25cebd4ea329b70` |

These open branches are not counted as merged main-branch remedies. Their full
contents and PR claims were not requalified by this documentation integration.

## Checks performed for this integration

The [integration check record](integration-checks.json) records the completed
artifact, source-identity, link and whitespace checks. Both original archive
verification helpers passed; their receipt/source counts are documented in the
[evidence index](README.md#contents-and-provenance). A separate review checked
the embedded SHA-256 lists directly, without executing archive code.

This integration did not launch a Godot audit witness, full flight, native render
capture, physical-controller session, crash-durability experiment, aircraft
calibration or performance benchmark. The observed GitHub failures are actual runs on the
reviewed main, while the old ZIP witnesses remain executions at `45d86d2`.
This distinction is necessary to assess both the progress already made and the
work that still needs a checked current-source reproduction.

[main]: https://github.com/bultodepapas/OpenRCsimulator/commit/ad21070798bfb9658785576a9c0b8bfc9a71fc7f
[pending]: ../../../external%20Audits/CONSOLIDATED-AUDITS.md
[completed]: ../../../external%20Audits/COMPLETED-AUDIT-WORK.md
[windows-run]: https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453322
[metalfx-run]: https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453317
[ci-run]: https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453445
[windows-job]: https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453322/job/132800644383
[units0-job]: https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453445/job/132801393947
[integration-job]: https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453445/job/132801393957
[units2-job]: https://github.com/bultodepapas/OpenRCsimulator/actions/runs/43710453445/job/132801394013
[pool-test]: ../../../tools/testqueue/test_pool_mcp.py#L13
[pool-source]: ../../../tools/testqueue/pool_mcp.py#L77
[controls-source]: ../../../app/ui/controller_setup.gd#L482
[controls-test]: ../../../app/tests/test_controls_setup_p0.gd#L258

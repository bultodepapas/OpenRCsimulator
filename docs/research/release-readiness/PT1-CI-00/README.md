# PT1-CI-00 — release and test-efficiency audit

2026-10-31. Initial source/history audit followed by implementation and verification records below. [Execution plan](../../../plans/release-ci-efficiency.md).

## Source identity and recovered proposal

- Reviewed working source: `c4dc202d0eae01efa951e467b784453eeaf02a47`; clean at the start.
- Located the earlier proposal in local remote-tracking ref `origin/ci/local-checks`, tip `d48dbeb9f3fc5ec3d798bf04760d6e90fc17f6c3`. `git merge-base --is-ancestor f1fbc4805 HEAD` returned 1: it is not integrated into this reviewed main.
- [Original change f1fbc4805](https://github.com/bultodepapas/OpenRCsimulator/commit/f1fbc4805fef35f4489f0e5a4fc31617a67df810) introduces `tools/ci/{scope.py,test_scope.py,check-sources.sh,check-local.sh}`, scoped CI and a separate prototype workflow. `2d8c2dd3b` clarifies WSL checkout placement; `d48dbeb9f` links the pinned Linux toolchain.
- The original commit reports 15 scope regressions and Linux preflight results. Those are historical author evidence, **not tests rerun against current main**. No old code was restored or executed in this review.

## Retained findings

| Inspected source | Finding and implication |
| --- | --- |
| Old `scope.py`, via `git show origin/ci/local-checks:tools/ci/scope.py` | All changed `.md` files are treated as safe. Current [Timber manifest](../../../../research/timber/tt01/manifest.py) and [X8 manifest](../../../../research/skywalker-x8/X8-00/manifest.py) hash source-delivery `README.md`; this shortcut can miss a mandatory freshness failure. Preserve NUL paths and conservative event/error handling, replace the extension exclusion. |
| Old `check-local.sh` / `check-sources.sh` | Predate current checked pre-schema import, added schemas/generators, and release native prerequisites. The old release mode builds only Linux ground-native before export. It cannot certify today's Windows/Linux ground and Linux NK-3 package inputs. |
| [Current workflow](../../../../.github/workflows/ci.yml) | Unrestricted push and PR triggers; no concurrency control. Eight unit jobs plus one integration job; prototype remains a release dependency. Export already runs alongside app/visual checks after native builds, and publication waits for all listed dependencies. |
| [App runner](../../../../app/test.sh) and CI generator step | P-51 physics, Timber and X8 checks repeat inside the same integration job. Import also runs before CI schema probes and again at app-runner entry. Remove duplicates only with matching command/input/environment contracts; preserve safe standalone defaults. |
| App runner helicopter calls | `--oracle` integration calls and ordinary discovered unit calls differ. Filename equality does not imply equal independent-reference coverage. |
| [Partition regressions](../../../../app/tests/test_ci_partitions.py) | Fixed-brake historical-source prefetch repeats the unit modulo assignment. Any balancing change must update both through one assignment source and preserve failure/empty/exact-once checks. |
| [Diagnostic runner guide](../../../../tools/godot/README.md) | Validating present reports does not prove every intended invocation was launched. A required roster and final coverage reconciliation are needed for skipped/partitioned work. |
| [Capture runner](../../../../app/capture.sh) | Shared output lock and a final complete-set manifest prevent naïvely parallelizing several copies. Partition ownership, comparison dependencies and aggregation must be explicit. |
| [Release contract](../../../../tools/release/README.md) | Exactly six final files, source/input drift checking and commit/tag/run/repository verification already exist. Same-run build-once promotion is implemented; cross-run reuse must not impersonate the consumer run. |

## Observed Actions execution times

Retrieved with `gh run list --workflow ci.yml` and `gh run view <id> --json jobs,headSha,url`. Job duration is `completedAt - startedAt`; only successful executed jobs contribute to totals, excluding skipped publication. Values are minutes, rounded to two decimals. No new workflow run was started.

| Successful run (2026-10-30 UTC) | Source | Visual job | Integration job | Unit-job min–max | Export job | Sum of successful job minutes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| [41108674992](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/41108674992) | `b060041fd39944d0179c112d17e643931a819f59` | 122.95 | 86.68 | 16.10–32.30 | 23.62 | 437.88 |
| [41084585940](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/41084585940) | `c1084681e0d9f144587cf127f270e626e00298ac` | 100.30 | 99.13 | 13.40–26.45 | 22.97 | 437.33 |
| [41048644689](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/41048644689) | `3c2394a8755c010b677d63a28782ac40fe799105` | 101.37 | 77.85 | 14.18–34.25 | 19.77 | 406.50 |

In run 41108674992, `app/capture.sh` accounts for 119.47 visual-job minutes; integration's `app/test.sh` takes 76.02 minutes and the preceding import 6.45. This supports investigating visual and integration phases before simply adding unit shards. It does not identify individual slow capture cases or establish an optimization result.

The first two sampled histories include the same source commit in another run, but event/ref/build/cache conditions were not normalized. These three observations are not a paired experiment, a billing calculation or a p95 estimate. Current-HEAD run 41200545486 was still in progress when inspected and was excluded. Case-level costs, artifact transfer costs, branch-protection configuration and matched full-suite baseline/candidate runs remain PT1-CI-00/07 work.

## Scope and verification

The review inspected the earlier branch, current scripts/contracts and existing remote results. It did not run Godot, build native binaries, export, publish, change repository settings, remove tests or validate physical/native-GPU behavior. The accompanying plan requires meaningful selector, roster, aggregation and release-negative fixtures during implementation. Documentation verification consists of relative-link target checks and `git diff --check`; no simulation run is warranted for this documentation-only update.

## Implementation follow-up

2026-10-31. Implemented directly on `main`, without creating a task branch or PR. The implementation files under test match commit `aa58bad845bb36283d58d858c43a2f4faa2dfdfd`; the subsequent documentation commit is `ce789cae7e570b91776cebc47c1ffc9cf16dadfb`. These commits appeared concurrently in the shared tree; this implementation session issued no commit, push, repository-settings or publication command. Unrelated runtime/UI edits were preserved.

Delivered behavior:

- One workflow, with early source/tag/version/notes preflight, main/tag/manual support, PR-only cancellation, a conservative selection receipt and a final required-job/parse/unit-roster check. Main has no branch protection (API returned `Branch not protected`) and the repository ruleset list was empty; settings remain unchanged. Scope skipping stays disabled in shadow mode.
- All 17 original generator checks are in `tools/ci/check-sources.sh`. Nine repeated commands were removed from the integration path: P-51 derive, four Timber and four X8 checks. The commands and arguments remain unchanged; oracle-specific and physical-pending policies are preserved.
- Local quick/full/release commands; optional source/parse/runtime phase selectors; exact parse/unit completion receipts. Unique receipt filenames preserve repeated local runs. CI retains the combined integration job and eight modulo unit shards.
- Optional capture groups and `timings.tsv`; default complete capture commands and 46 manifest entries retain the tested fixture schedule. Partial groups have no complete-set marker. No new visual matrix/reducer or parallel renderer is enabled.
- Editor caches now contain verified editor download/binary/receipt paths rather than the whole `.tools` tree. Import reuse and dependency pins are unchanged.
- Same-run publication helper with six-file and remote-tag verification, exact downloaded-byte checks, identical-retry no-op and rejection of partial/different releases. Tag preflight includes the manifest's 160-character boundary.

Validation on WSL Ubuntu (disposable fixtures unless stated otherwise):

| Check | Result |
| --- | --- |
| `bash tools/ci/check-local.sh quick` | Passed: 13 CI-partition tests, 30 export-identity tests and 39 CI-tool tests; final run after the unique-receipt repair |
| Release-tool discovery | 40 tests passed; GitHub operations mocked, fixture Git fetch limited to a disposable local remote |
| Website locale checks with the existing pinned requirements in an isolated venv | 5 tests passed; all eleven generated languages/dictionaries/sitemap match |
| Website download tests | 8 passed |
| Analytics history tests | 12 run, 2 platform cases skipped; remaining 10 passed |
| Workflow validation | `actionlint` 1.7.12 passed; official downloaded archive SHA-256 verified against its published checksum file; shellcheck integration disabled |
| Shell syntax, relevant diff whitespace and documentation link targets | Passed |

Failure controls include missing/duplicate/changed/partial roster receipts, missing history, code renamed to Markdown, hashed README input, mixed domains, tag/manual selection, failed/cancelled/unexpectedly skipped jobs, generator failures, partial capture outputs, source/tag/version mismatches, invalid or changed release files and incomplete release retries. The review caught and repaired repeated-local-run receipt collisions and the preflight tag-length mismatch.

At this first implementation checkpoint, no Godot/full app run, rendered pixel comparison, cold full checkout, native build, simulator export or public release had been performed. Subsequent checks are recorded below. The new cache path has not been cold/warm measured. Complete heterogeneous integration-case inventory, five representative shadow runs, full package rehearsal, scope activation and measured savings remain open in the plan. Fixture scheduling agreement is not visual equivalence or physical qualification. Nine duplicate invocations are removed by construction; no percentage speedup is claimed.

### Scope validation and local isolation follow-up

2026-10-31. Continued on the shared `main` checkout based on `70709ff4b600fbce361b0bea9f88726c60bcff86`, preserving concurrent UI work. The tested code subsequently appeared in concurrent commit `fabc7ef8a7adbe8553eab9365966c9cfc99bf6ba`; this session issued no commit or push. The v2 selection receipt now records the PR head and independently recomputes event identities, changed paths and required jobs from Git in the aggregate. Deletions, mode changes and non-regular files force full scope. The aggregate uses a depth-two checkout for merge parents and fetches a missing base only from the validated event; receipt fields cannot choose a network ref.

The scope job now checks new local document links and previously valid links broken by changed targets within six audited guides. This includes inbound references from another guide in that set, but not a whole-repository backlink scan or external URL checks. Unrelated inherited broken links remain excluded. Markdown handling is bounded to the documented guide syntax. A blanket plans exemption was rejected: `research/fuel-systems/FUEL-00-R1/build_document.py` reads and hashes `docs/plans/fuel-mass-balance.md`.

Full local checks now isolate Godot preferences and caches per invocation, while retaining the caller's export-template and Playwright download locations. A regression verifies fresh profiles, complete app selection despite inherited shard variables, and prototype cache preservation.

Validation of these changes:

- WSL `bash tools/ci/check-local.sh quick`: **113 tests passed** (13 partitions, 30 export identity, 70 CI tools), including 25 selector and 20 document cases.
- Real committed-document smoke from `ce789cae7e570b91776cebc47c1ffc9cf16dadfb` to `70709ff4b600fbce361b0bea9f88726c60bcff86`: 15 new or potentially affected local links checked successfully.
- End-to-end scope/document CLI smoke on `fabc7ef8a7adbe8553eab9365966c9cfc99bf6ba`, using its real parent and a synthetic main-push event: 11 new or potentially affected links checked successfully. This checks local CLI wiring, not a hosted event.
- `actionlint` 1.7.12, shell syntax and `git diff --check` passed. A separate bounded source review found no concrete new selection or aggregate defect; it is not hosted Actions evidence.

The Windows backing volume filled during preparation of disposable verification copies, despite Linux reporting virtual free space. Truncated copies and downloaded inputs were not used as verification evidence: tracked files were restored from the pinned Git snapshot, inputs were downloaded again and verified, and WSL was restarted with owner authorization. The incomplete capture copy was removed. Verify physical host storage before WSL preparation. Shadow mode remains enabled; these fixture results do not establish runtime equivalence, measured savings or publication readiness.

### Unit-backed parse coverage

The implementation at `4b89082c1eabf1e84766de827ec5992daeb61dfc` removes duplicate standalone parsing only where the full run requires execution of the same unit script. At that source, 1,552 discovered GDScript files comprise 867 unit scripts and 685 other scripts. All 867 unit executions remain; 685 explicit parse invocations cover the complement. Rosters are discovered at execution time rather than hard-coded to these counts. Ordinary standalone integration and parse phases still parse all scripts.

The pinned Godot source loads the script before testing `check_only` in [Main::start](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/main/main.cpp#L4082-L4099). Reload parses, analyzes and compiles the script; the [compiler also visits member functions and inner classes](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/modules/gdscript/gdscript_compiler.cpp#L2770-L2789). Thus required execution covers compilation of unused functions too; it does not establish that their runtime branches execute.

Eight real-engine controls used the pinned `4.8.beta1.official.4d10419ca` and checked runner in disposable projects: valid source passed both `--check-only --script` and `--script`; syntax errors in an unused function, type errors in an unused function, and type errors in an unused inner-class function each failed both modes. All eight reports are complete. Local artifacts: `D:/OpenRC-ci-recovery-20261031/review-unique/parse-semantics-qbmp5b4d/results`. Expected failures are separate from positive suite evidence. The fixed-brake wrapper still executes its exact unit script through the checked runner with the required markers.

V2 phase receipts bind the complete phase roster and runner inputs, declare the parse coverage mode, and reject source drift before completion. The CI aggregate independently checks one parse receipt and eight exact, disjoint modulo unit receipts against its checkout; their union must cover every script. Failure controls include missing units, wrong unit subsets, duplicate shards, altered coverage and changed source. The opt-in flag is restricted to the combined CI integration mode; the full local wrapper clears inherited selectors.

An independent source review of the combined runner, workflow, local wrapper and verifier found no concrete lost coverage or gate bypass. Final WSL quick validation passed **116 tests**: 13 partitions, 30 export identity and 73 CI tools, including the additional wrong-subset and duplicate-shard controls. Those controls and documentation appeared in concurrent commit `6d30cf96a9cbacd4802faf615a66bce6232cd59d`; the production CI/runner code remains identical to `4b89082c1`. Release-tool fixtures were rerun separately: **40 passed**. Workflow validation with `actionlint` 1.7.12, individual `bash -n` checks of the four changed shell entrypoints and whitespace checks scoped to this task passed. These checks do not replace a completed full app run.

### Hosted implementation observation

At 14:07 UTC on 2026-10-31, read-only inspection found a new main-push [run 41208201712](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/41208201712) at `6d30cf96a9cbacd4802faf615a66bce6232cd59d`. This session did not push or dispatch it. The new selection/preflight job succeeded, including orchestration regressions, source/version/notes checks, the shadow selection receipt and document-link validation. The Linux and Windows ground-native jobs, website job and same-workflow prototype also succeeded. All eight unit jobs, integration, visuals and NK-3 qualification were still in progress; the final aggregate and export were not complete. This is initial hosted wiring evidence, not a completed shadow run or full release qualification.

At 14:23 UTC, unit shards 0, 4 and 5 had succeeded, while two application checks had failed:

- [Units 1, job 124557980440](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/41208201712/job/124557980440): `test_landscapes.gd` emitted an engine error for missing `shadow_field_policy` metadata in `field.gd:493`. The checked runner rejected it despite process exit zero; 56 earlier invocations passed.
- [Units 6, job 124557980422](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/41208201712/job/124557980422): `test_settings_ui.gd` failed the default category-3 fit check at 1920×1080: page height 749 exceeded body height 700. The process exited one; 79 earlier invocations passed.

No test was excluded, retried or relaxed to hide these failures. They prevent this run from establishing complete qualification. The remaining jobs were still running at that observation. Local diagnostic excerpts are retained in `D:/OpenRC-ci-recovery-20261031/hosted-failure-summaries-41208201712.json`.

Read-only source triage at `d5ad6f8131cd80335bb044d6189034d9e0d4f5c2` found both failures in concurrent shadow/UI changes, with no evident fix yet. `field.gd` retrieves optional metadata with a null default, while Green Paradise has no shadow policy; an explicit presence guard must retain its existing projected-shadow fallback. The new visible Graphics-page Shadows row is the likely cause of the measured layout overflow (source-based inference, not a paired capture). Repair must preserve the 1080p fit assertion and all controls. These runtime paths were left to their active track; CI scheduling and diagnostic rejection were not weakened.

The same run's [export job 124562920364](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/41208201712/job/124562920364) subsequently failed after a successful 254-second import: metadata capture rejected a change in source cleanliness. The log did not inventory changed paths. At `6d30cf96a`, five new shadow scripts lacked tracked UID sidecars; `ce789cae7` had none missing. Matching local sidecars have pinned-engine generation provenance in `D:/OpenRC-shadow-verification2-20261031/tmp/shadow-verification2-inputs.json`. This strongly supports import-generated UID files as the cause, but the hosted changed-path inventory is unavailable. The source-owner fix is to track those generated sidecars, preserving the cleanliness gate. Follow-up CI code now checks tracked, nonempty application script/shader sidecars before expensive jobs and retains failed-export engine logs and source path inventories separately from release assets.

The follow-up passed 10 preflight fixtures, then the complete quick command passed **123 tests** (13 partitions, 35 export identity/packaging/native-receipt tests and 75 CI tools) with isolated Linux temporary fixtures. Missing, untracked and empty script/shader sidecars fail the preflight; distinct committed sidecars pass. This is a presence check, not validation of UID content or uniqueness. A disposable exporter using the real manifest capture reproduces import-created UID drift and retains its path and engine log without producing a release manifest or success handoff. Controls preserve the original failure status even if diagnostic copying or Git fails, and preserve the successful six-file contract. Diagnostic Git calls have a 30-second limit and two-second kill grace; no source contents are collected. The updated workflow passed `actionlint` 1.7.12, the actual LF export script passed `bash -n`, and task-scoped whitespace checks passed.

The shared tree subsequently incorporated these changes and the shadow owner's generated sidecars in `28d6a4b77b41cd193bce6d904ad237b9fc3c05d3`. The real preflight CLI passed on that clean commit with a synthetic main-push context. This session issued no staging, commit or push. This proves the local source/pin/UID prerequisite check, not a new hosted full run or resolution of the earlier runtime failures.

### Interrupted full-suite qualification

A disposable clean snapshot at `ce789cae7e570b91776cebc47c1ffc9cf16dadfb` ran the pinned Linux engine with isolated profiles. The cold import completed in 201.273 seconds; a restart's warm import completed in 5.666 seconds. These are separate setup observations, not a paired full-suite performance result.

The restarted run completed 820 checked reports, including 807 of 1,552 explicit parse invocations. A further invocation was interrupted and has no complete report. No unit scripts had started. The task stopped its own processes when free space on the Windows backing volume fell below 1 GiB; C: subsequently reached zero. **The full suite did not pass or complete.** These results predate the unit-backed parse optimization and do not qualify the latest concurrent UI changes. Battery input hash verification also explicitly skipped absent `references/battery-energy`; only fit-result consistency ran for that check.

Local evidence remains under `/home/bulto/openrc-ci-validation-ce789-20261031/tmp/full-suite-ce789-restart-20261031/` (`suite.log`, `partial-results.xml`, `disk-observations.txt`, `checks/`). WSL later failed to start and was restarted with owner authorization; focused verification resumed with disposable outputs on D:. The storage failure's root cause was not established. Full optimized runtime and rendered qualification remain open.

The first focused retry on ordinary `/mnt/d` passed the 13 partition tests but failed one of 30 export-identity fixtures: the packaged Linux executable had mode `0777` rather than required `0755`. DrvFS without metadata did not preserve the requested `chmod`. A temporary second D: mount with POSIX metadata support preserved `0755`; all 13 partition and 30 export-identity fixtures passed on that mount. No permission assertion or package gate was weakened, and no persistent WSL configuration was changed.

### Local package rehearsal

The nonpublishing rehearsal uses the immutable `ce789cae7e570b91776cebc47c1ffc9cf16dadfb` snapshot, the pinned Linux editor and verified templates, and original native receipts. Source, staging and isolated profiles are on D: through a temporary DrvFS mount with POSIX metadata. It does not qualify later application changes or the added failure-diagnostic code.

The first exporter attempt exceeded its unchanged 600-second import limit and retained partial output at `D:/OpenRC-ci-recovery-20261031/export-environment/export-output-ce789`. No package set was produced. A separate checked preparation import completed in 798.387 seconds with zero errors or warnings; its complete report is `checks/ce789-preimport-rlg2rhzj/report.json` under that environment. This preparation does not turn the cold failure into a pass or establish a speedup. Any subsequent warmed export is recorded separately and retains all original export gates.

Global status also exposed a historical research filename through DrvFS as `console.log` followed by a carriage return. The Windows name ends in U+F00D and its content matches tracked blob `0bcf738ebc2d3a5e130e5efeb7eb5778e20c8c5b`; it predates import. The file was not removed or renamed. The exporter checks tracked changes throughout the repository and untracked application files; an outside-application untracked alias alone is not its source-drift criterion. A complete scoped identity check is required before the single warm retry; an interrupted check is not accepted merely because a partial diff file is empty.

### Unit invocation timing inventory

The [retained observation](unit-timings-41200545486.json) covers the eight completed unit jobs in [run 41200545486](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/41200545486), source `c4dc202d0eae01efa951e467b784453eeaf02a47`. Download sizes and SHA-256 match GitHub artifact metadata; the existing checked-log summarizer accepted all 880 reports. The pinned source roster reconciles exactly: 867 distinct unit scripts, each once in its expected modulo shard, plus eight imports and five fixed-brake support invocations. These are invocation counts, not assertion counts.

| Shard | Unit scripts | Sum of unit invocation seconds | Full job seconds |
| --- | ---: | ---: | ---: |
| 0 | 109 | 514.336 | 1,030 |
| 1 | 109 | 745.330 | 1,199 |
| 2 | 109 | 912.071 | 1,380 |
| 3 | 108 | 966.520 | 1,926 |
| 4 | 108 | 782.649 | 1,302 |
| 5 | 108 | 831.177 | 1,416 |
| 6 | 108 | 636.823 | 1,164 |
| 7 | 108 | 532.144 | 989 |

The slowest unit job is 1.481 times the mean. Ordinary imports take 344.9–450.7 seconds each. Fixed-brake support adds 416.864 seconds to shard 3, including a 402.784-second historical-reference bootstrap; its unit report alone is only 7.741 seconds. Future balancing must group that support cost with the test and its history-prefetch assignment. Counting filenames or timing only the direct test would misclassify this work.

The five slowest direct unit reports are `test_ui_modal_responsive.gd` (208.619 s), `test_half_power_start.gd` (140.031 s), `test_latency_patch_cli.gd` (106.845 s), `test_input_report_cli.gd` (102.042 s) and `test_ui_home_layout.gd` (101.916 s). At the 13:19:57 UTC snapshot, integration and visuals were each still running after at least 60.95 minutes, exceeding the slowest completed unit job's 32.10 minutes. Unit balancing alone cannot shorten that run's overall path. This is one observed run, not a paired speedup, p95 or billing result; no test or acceptance threshold was removed based on these timings.

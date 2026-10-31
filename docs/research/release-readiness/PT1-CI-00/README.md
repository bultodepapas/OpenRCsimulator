# PT1-CI-00 — release and test-efficiency audit

2026-10-31. Read-only source/history and GitHub Actions inspection; documentation changes only. [Execution plan](../../../plans/release-ci-efficiency.md).

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

No Godot/full app run, rendered pixel comparison, cold full checkout, native build, simulator export or public release was performed. The new cache path has not been cold/warm measured. Complete heterogeneous integration-case inventory, five representative shadow runs, full package rehearsal, scope activation and measured savings remain open in the plan. Fixture scheduling agreement is not visual equivalence or physical qualification. Nine duplicate invocations are removed by construction; no percentage speedup is claimed.

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

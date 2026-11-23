# Hosted audit follow-up and concurrent upstream integration

This supplement records evidence collected after the initial [audit report](CI_AUDIT_REPORT.md), whose source census and historical baseline remain bound to `85a2475f60029a4b6b09f23f643119bceea84a45`. The [structured follow-up](CI_HOSTED_FOLLOWUP.json) records exact source identities and the UID-generation checks. [PR #21](https://github.com/bultodepapas/OpenRCsimulator/pull/21) carries subsequent hosted status without rewriting the historical sample.

## First PR execution and fixture correction

On `ce31055c`, [run 45075562784](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45075562784) passed both prerequisites, website/prototype checks, the full application import and the new required Godot-to-receiver test. The downloaded telemetry receipt recorded the pinned engine, three batches sent, zero queued or dropped, and no engine diagnostics. The prototype artifact was also downloaded and its digest and all three PNGs verified. The main report records the exact artifact IDs and hashes.

The offline step failed in its first program. After supersession made the archived log available, it confirmed the independently reproduced assertion: `127 != 1` in `test_ci_import_precedes_schema_and_publishes_failures`; 14 cases ran and one failed. The fixture accidentally executed intervening YAML as Bash. Commit [1d276c00](https://github.com/bultodepapas/OpenRCsimulator/commit/1d276c00ba70f9586227bcb03dd95c2fded4a93b) bounds extraction at the next step and checks import-before-schema ordering separately. All 14 partition and 14 adjacent phase cases passed, and a deliberately reversed order still failed. No assertion was removed to obtain a pass.

## A later upstream change stopped the replacement at preflight

During the audit, `main` advanced by 17 commits to [843f357c](https://github.com/bultodepapas/OpenRCsimulator/commit/843f357c07af842054f3ccd6728f93beca9a57ef), affecting 92 paths. Those product changes were made outside this audit. The replacement [run 45078157682](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45078157682) actually tested merge `1098412605263554f647702e0ae469af87111824`, whose Git parents are `843f357c` and `1d276c00`. The verified merge tree is `a90d786e0c079bc86ed04a02d0d642b9c9c7e0ef`. Its preflight rejected five newly introduced GDScripts with missing tracked UID sidecars.

| Job | Observed outcome |
| --- | --- |
| [Preflight](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45078157682/job/137380124664) | Failed in 82s, including 78s checkout. Its one-second source check listed the five missing sidecars. |
| [Tooling](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45078157682/job/137380124945) | Passed in 129s. Sparse checkout took 4s; actionlint, 139 CI cases and 459 queue cases run: 447 passed and 12 skipped. The extra queue case came from the concurrent upstream changes. |
| [CI required](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45078157682/job/137380783700) | Failed in 12s. Sparse checkout took 5s, then the selection-artifact download failed because preflight had emitted no receipt. The later policy step skipped. This inherited ordering gives a less specific final message; the producer reports the actual source defect. |

Only three jobs ran; 17 job entries skipped, including all simulator, native and visual work. Elapsed workflow time was 181s. Summed active job time was 223s, or 3.72 unweighted runner-minutes. This is direct evidence that the prerequisite barrier contains a source failure. It is not a controlled billing or speedup estimate. This attempt did not reach the corrected offline fixture. Its telemetry-contract and portable-tooling sibling workflows passed.

## Branch-only UID repair and integration

The audit branch incorporates the verified merge tree above and adds these five sidecars:

- `app/render/flight_dynamic_resolution.gd.uid`
- `app/render/flight_resolution_policy.gd.uid`
- `app/tests/probe_completed_gpu_frame.gd.uid`
- `app/tests/probe_flight_resolution_stress.gd.uid`
- `app/tests/test_flight_resolution_policy.gd.uid`

Godot `4.8.beta2.official.cafc17a19` generated them through a normal editor import in an isolated project containing the five exact upstream scripts, their ten transitive GDScript dependencies, and the existing dependency UIDs. All 25 source/dependency inputs retained their upstream Git blob hashes. Import, five individual parse checks and a live UID-to-resource-path check passed: seven checked processes with zero errors and zero warnings. Each new ID is canonical, distinct, and absent from the 2,174 distinct tracked upstream application UIDs. The five GDScript bodies were not changed by this repair. These checks establish metadata and parse validity; they do not qualify the new GPU experiment or its hardware behavior.

This is a merge into the dedicated audit branch. The audit did not update `main`, merge the PR, publish a release or change administrative branch rules. The original workflow snapshots still match because the concurrent upstream commits changed no workflow. The original test census and performance observations remain frozen; they are not a claim that every new upstream product assertion received an independent audit. The combined source has 2,073 application GDScripts and 1,164 top-level unit scripts, compared with 2,067 and 1,163 at the audit baseline. Hosted roster reconciliation must use its actual merge checkout and include the additional scripts.

## Additional local offline coverage and resource limits

All 31 invocations in `research/test-tools.sh` passed across separate successful suite executions on the pre-integration audit source: 1,753 cases, of which 1,724 passed and 29 explicitly skipped. This includes the changed 354-case native discovery and seven mass/trace cases.

One unmodified disk-backed harness invocation stopped after 1,648 cases because two GOD TEST snapshot cases require 512 MiB of free space and the local volume had 236 MiB available. All 212 GOD TEST cases passed separately on tmpfs; the final 105 release cases also passed separately. Conversely, the checked-runner physical-I/O assertion required a disk-backed temporary directory because this host's tmpfs did not accrue the measured disk writes. That whole 328-case suite passed on disk, with 26 expected skips. The audit does not claim one uninterrupted green harness invocation on this constrained host, or apply those old-source counts to newly added upstream tests.

## Third PR execution: repaired offline route and independent qualification failures

At head `847d8d1a`, [run 45079559400](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45079559400) tested merge `22a1ae368a75b94977d8dfa46cc4888499424ce7`. Its tree is exactly the audit head's tree, `b9866328c22696399e3a53d423c3679cba8a9f2e`. Source preflight passed in 91 seconds and tooling in 129 seconds. Tooling ran 139 CI cases and 459 queue cases: 447 passed and 12 skipped. Website, prototype, both RC native builders and the Linux RC production lane also passed at the observation cutoff.

The checked full-project import passed in 353 seconds. The mandatory real-client telemetry step then passed in six seconds. Artifact `14777221087` was downloaded and independently verified: the 1,398-byte ZIP has SHA-256 `d83e955801b6023bbc3b9b2d016341e4d30a3e6b0f8254ac342fdd73f9a737f3`; its pinned-engine receipt records zero engine errors/warnings and `sent=3 queued=0 dropped=0 local_drops=0`. The corrected offline step passed in **132 seconds**, reaching the expanded native and mass/trace route. These passed steps do not turn the full workflow into a pass.

Seven completed unit shards failed in companion admission. Several logs explicitly identify the same two stale source hashes; the normal-Home and presentation failures follow the same admission path. The companion manifest itself is unchanged between the audit baseline, upstream `843f357c` and the integrated audit head. The two changed source bodies are byte-identical between upstream and the integrated head:

| Qualified source | Accepted/baseline SHA-256 | Upstream/integrated SHA-256 |
| --- | --- | --- |
| `app/app_root.gd` | `7b80a6a17a6ff8b05a1af6f8e800bc589c7154d022c6a2c22b4b1e4e58712b89` | `75626bac8dfacf87bddb436520a0f3370a97714595a142f4bf3c6fb076a9cc7d` |
| `app/scenery/collision_world.gd` | `ef91c3944b2e0cac4d650d5513a696e8b6d5ad6b3d23a6a232f2196dda972274` | `8be7c632c8bd8499ebff09221ff1375e7bd5415bb192fba591700bc1454bc8d6` |

The same normal-Home, profiles, manager and observation cases passed on the earlier `ce31055c` PR source, with 60, 95, 53 and 21 checks respectively. The newer changes affect normal-Home routing and real gate-member collision proxies. The resulting qualification refusal is meaningful protection. Renewing its manifest requires the [documented behavior process](../AI-FLIGHT-COMPANIONS.md), actual Club-world route clearance and production admission; [solver tape rebind](../../tools/companions/README.md) does not renew this separate identity. These results explain an upstream product/source-consistency failure, not a regression from native Python discovery.

The [unit-5 job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45079559400/job/137385028504) also exposed a diagnostic weakness in `test_companions_behavior_manifest.gd`: after correctly rejecting the stale source, it dereferenced success-only identity fields, raised a script error and reached the 60-second timeout. The branch now exits with its failed-check summary before that dereference. Its expected-refusal branch and positive/mutation assertions remain in place. In a complete isolated project materialized with effective Git checkout attributes, normal stale-source mode reported seven checks/two failures and exited 1 in 7.628956 seconds with the final complete source closure; expected-refusal mode passed all eight checks in 7.468117 seconds. Both produced zero engine errors or warnings. The isolated candidate positive/mutation path passed 39 checks in 8.140680 seconds; its deliberate malformed-UTF-8 control emitted the expected decoder diagnostics. A preliminary raw-blob materialization had different data-file line endings and is excluded from these results. A prompt failure is the intended result when the source is unqualified; this change does not admit it.

## Bounded native reset evidence renewal

The later NK-3 policy step failed independently of the now-passing offline step. A matched pinned-editor reproduction, without running the offline suite first, passed trajectory policy 130/0, changed fleet policy from baseline 598/0 to candidate 598/16, and isolated the sixteen assertions to eight reference-owned runway resets. The existing typed comparator passed **460 checks across eight exact expected cases**. Every baseline capture matched its accepted V6 pin. Only the checkpoint-configuration and collision-world identities differed; physical frame, setup, refusal, outcome and reference ownership were identical.

The [retained V7 qualification record](../research/native-kernel/NK-3/fleet-collision-world-2026-11-22/README.md) includes both compressed captures, their raw and stored hashes, source and editor identities, comparison receipt and reproduction commands. Commit [7aa7e270](https://github.com/bultodepapas/OpenRCsimulator/commit/7aa7e270e20f5687962ca3e5d36e6852feb27e23) adds exactly eight V7 values and preserves V6. The renewed Linux fleet passed 598/0, trajectory 130/0 and native Python discovery 354/354, including 67 campaign cases. All eight old observations and all eight coherently rehashed physical-state mutations remained rejected. The comparison observer's cleanup was corrected without changing either captured output byte. This evidence covers bounded reference-owned reset refusals; it does not qualify native flight, companion routes or hardware behavior.

The completed [Linux NK-3 job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45079559400/job/137385028507) independently confirmed the same stale identities with a verified native library present. Its earlier build, mutation, library-loading, native session/replay/helicopter, glow and admission gates passed. The paired runtime-domain step reported 634 checks and 25 failures: the sixteen reference assertions, eight paired reset assertions using the same proof predicate, and one accumulated-error assertion. The final runtime-domain marker requires zero suite failures, so its absence follows from that tally. The renewed source must still pass the actual native-request run with all 634 checks and `NK3_RUNTIME_DOMAIN_NATIVE verdict=pass`; the local 598-check reference-only result does not establish that outcome.

## Companion behavior renewal with complete source and production admission

After the stale-source rejection was reproduced, the two-file candidate passed a separately recorded [bounded companion renewal](../research/ai-companions/AFC-02/rebinds/2026-11-22-ci-audit-behavior/README.md). Commit [50a63d29](https://github.com/bultodepapas/OpenRCsimulator/commit/50a63d290d97d89b708f2a32289cc5182781963f) changes only the two behavior-source hashes and the aircraft profile's manifest reference. The production loader, admission rules, controller and solver code are unchanged.

The isolated project contained all 6,015 tracked application files and 27 attested external aircraft-authoring records. Actual Git checkout filters supplied the required CRLF bytes for 29 files. The final 23 checked processes all produced their expected status: 22 succeeded and one intentionally rejected the stale manifest. The source inventories, exact drivers, logs, checked reports, setup exclusions and independent solver review are retained with the [receipt](../research/ai-companions/AFC-02/rebinds/2026-11-22-ci-audit-behavior/bounded-checks.json), SHA-256 `c7deb56b2dd6cea3c9de725a902f6e0530c8770b6b011a4dcc4e044adb48abe0`.

| Bounded exercise | Verified result |
| --- | --- |
| Strict profiles and manifest | 95 profile and 39 positive/mutation assertions passed; stale-source normal mode still exited 1 and the explicit refusal mode passed. |
| Actual Club collision world | 40 trajectory, 117 gate/destruction and 49 airspace assertions passed. Both circuit sampling limits were exercised. The built world had 7,295 proxies, including 72 protected proxies, with a measured 28.2949 m minimum vertical gap after the declared allowances. |
| Normal Home admission | Three fresh processes requested one, two and three companions. At 240 accepted ticks, all requested companions were active and airborne with zero faults/crashes. Each process recorded the solver override disabled before and after flight and the correct runtime manifest identity. |
| Lifecycle and other consumers | The strict shell admitted three, paused and restarted with two. Draft, manager, observation, presentation, session, restore and seed checks passed; lifecycle exercised 50 headless and ten visual/audio node rebuild cycles. |

At the behavior-renewal commit `50a63d29`, the 203-file normalized solver identity remained `7e404f01db1146361acea77bc76ac08edc31458daa97b35c01b4538977e34982`, with identical physics/simulation/failure Git trees at baseline, upstream and the pre-renewal audit head. The later macOS source renewal and separate solver rebind are recorded below. The new behavior manifest is `e4a313309845c057d7de6c229bcdf07503351967068468003c3984c7ec25ed88`. Postflight verification found exactly the two proposed JSON differences and no other modified application or external source.

The accepted evidence covers ordinary Stik/Club operation under official Linux Godot 4.8-beta2, headless, with the GDScript reference backend. It does not qualify GPU experiments, native or packaged execution, arbitrary routes, continuous-flight safety or physical aircraft. Eight OBJ ambient-material import warnings and nine reference-backend warnings are disclosed. Initial raw-blob line endings, missing external authoring records and a refused existing output path are excluded setup attempts, not successful qualifications. The diagnostic test's separate six-line correction is verified by its exact archived external driver bytes.

## macOS stock-world renewal and the separate solver rebind

The completed [macOS ARM64 job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45079559400/job/137385028494) reported 72 checks with one failure: its old stock-world identity/count expected 6,139 proxies while the current world had 7,295. All 2,400 isolated guard calls matched the frozen current world. The job stopped before installation and the final default-route exercise. Linux V7 does not repair this separate macOS domain contract.

Following the existing DT-MAC-04n-R1 procedure, commit [c320d34d](https://github.com/bultodepapas/OpenRCsimulator/commit/c320d34d77197d2a34a5e41feced445a80f51712) changes exactly three literals: the actual Mac world hash, the count and the platform-independent quantized fingerprint. The Mac hash is `7e5fcff5098591708406da39142768107a594eac142b3862c2f684695876cc64`; the portable fingerprint is `f020b4c86b7e98df77eacc2a35e2a95a3fc17a046e2cb9b5d719ac82abfd16a2`. The pinned Linux editor passed all nine portable checks, including moved, removed, renamed and non-finite proxy controls. The woodland metadata change preserved all these measurements. [Mac source and diagnostic evidence](../research/native-kernel/DT-MAC-04n-R1/2026-11-22-ci-audit/README.md)

Changing a file in `app/sim` changes the companion solver identity. The unmodified official rebind tool therefore compared the committed source against the accepted solver revision using all nine retained tapes. Eighteen replay processes produced byte-identical CSV hashes for **25,929 rows on each side**. Stored gzip, expanded ORFL and both replay input identities were reverified. The only changed solver source was `app/sim/native_macos_domain.gd`. Commit [0e57e797](https://github.com/bultodepapas/OpenRCsimulator/commit/0e57e797c5acc7a664ec8d4478838641c16276cc) keeps the generated profile, qualification registry and official receipt together. The new solver identity is `0954434e94c8dd31cb6183c8de34da00c81736545228a95249e899a936ef617b`. [Official nine-tape receipt](../research/ai-companions/AFC-02/rebinds/2026-11-22-7e404f01-to-0954434e.json)

The first baseline-copy attempt exhausted local memory before any verdict and receives no qualification credit. The completed solver-mode comparison ran one replay at a time, with independently copied source/project metadata and a shared immutable imported-resource directory. All 1,433 imported files, totalling 2,392,284,441 bytes, had identical ordered path/content manifests before and after. This retained-tape CSV comparison is bounded evidence; it is not exact replay, physical qualification or native-route acceptance.

Three fresh ordinary Home launches then used the exact combined app tree at `0e57e797` (`44faebf550d6257ef086760c2f50662faaf82957`). All 6,015 app files and 27 external authoring records matched the committed source before and after. One, two and three requested companions were respectively admitted, active and airborne at 240 accepted ticks, with zero faults/crashes. Every launch recorded the new live 203-file solver identity, the accepted profile and the override disabled before/after. All three airspace results matched the earlier count-specific evidence. Durations were 25.261, 27.583 and 29.782 seconds; each run emitted one disclosed reference-backend warning. [Final source and Home receipt](../research/ai-companions/AFC-02/rebinds/2026-11-23-ci-audit-home/README.md)

The replacement hosted Mac job must still rebuild/install its evidence, pass stage/lifecycle/replay and emit `MACOS_DEFAULT_ROUTE verdict=pass` through the actual no-flag native route. Linux headless Home success does not establish that result, and the virtual M1 job does not qualify physical-M1 performance or distribution.

## Deterministic woodland renewal and an unresolved geometry regression

The completed [integration job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45079559400/job/137385028525) also rejected the woodland recipe. This was its sole failed `app/test.sh` integration section; the earlier native-fleet policy step had failed separately. The unchanged generator, run on 24 verified inputs, changed exactly eight JSON leaves: two source hashes, four counts and two positive clearance measurements. Commit [e02863c0](https://github.com/bultodepapas/OpenRCsimulator/commit/e02863c0957c3501dc53df0a3bdeb5624f931d17) contains that generated file and the four updated literal fixture expectations.

All six Python cases passed, and an intentionally overlapping nine-metre patch was rejected by the original geometric predicate. The official headless editor passed 54 woodland habitat assertions. The complete 49-case companion airspace report was byte-identical to the earlier evidence, including the world identity and 7,295 proxies. A three-companion Home launch again reached 240 accepted ticks with zero faults/crashes and matched the earlier structured record. These results preserve the prior collision-world evidence across a metadata regeneration. They do not qualify pixel readback or whole-scene rendering. [Source-bound record and raw checks](../research/visual-quality-implementation/L6c/tree-completion/woodland-edges/2026-11-22-ci-audit/README.md)

The separate full-scene LU-34 check exposed an unresolved product regression:

| Source-geometry category | Measured triangles | Existing allowance | Excess |
| --- | ---: | ---: | ---: |
| Merged procedural cells | 178,746 | 175,000 | 3,746 (2.14%) |
| Miscellaneous geometry | 9,365 | 8,000 | 1,365 (17.06%) |

The current app produced identical counts for all eight categories before and after the woodland metadata regeneration. The earlier [pre-upstream hosted test](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45075562784/job/137372676695) passed the same allowances on scenery source matching the audit baseline. Total source triangles increased from 1,033,047 to 1,058,908. Close vegetation accounts for 16,803 of the 25,861 added triangles and remains below its separate 150,000 allowance; the original passing log did not print the exact earlier cell/miscellaneous split.

The audit preserves both failing limits and their category definitions. A proper fix must identify expensive nodes, reduce their source geometry and pass both `test_scenery_build.gd` and `test_landscape_vegetation.gd`, plus relevant rendered/physical-boundary checks. Source counts concern geometry and memory work; they do not measure frame time or target-GPU performance. This regression remains a reason to keep the PR in draft.

## Unit diagnostics after the first failure

The new [unit keep-going commit](https://github.com/bultodepapas/OpenRCsimulator/commit/93657c77c375fd1d63996f2b53aa414a975381f2) addresses the mechanism that delayed discovery of the scene-budget failure. Previously, `OPENRC_KEEP_GOING=1` applied to integration sections while the unit loop exited at the first error. Each unit now uses the existing section subshell with active errexit and pipefail. Successful scripts alone enter the completed roster. A failed unit prevents a complete receipt, while later scripts can supply diagnostics under the explicit option.

All 16 partition cases passed in 33.782 seconds and all 16 phase cases in 63.355 seconds. Controls exercised a process exit 7, exit-zero engine and shader diagnostics, the historical-brake wrapper's exit 9, default fail-fast, all-mode continuation and preservation of earlier valid receipts. All 19 selected probes were visited in the keep-going refusal cases, and no failed-run complete receipt was created. A prior unrelated source failure can still coexist with a valid unit-only receipt, while the final invocation remains nonzero. Later failures can cascade through shared project/cache state; they need attribution. More diagnostic work on a failed run is a deliberate tradeoff, with no claimed hosted time saving.

## Telemetry event coverage correction

Critical review found that adding a main-only branch filter also removed baseline tag-triggered telemetry execution. The branch now explicitly declares `tags: ['**']` alongside `branches: [main]`, preserving every tag push while removing duplicate topic-branch push runs. Main and PR path filters, manual dispatch and PR-only cancellation remain. The [official event semantics](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onpushbranchestagsbranches-ignoretags-ignore) explain that GitHub ignores path filters for tag events. All eight workflows pass actionlint with the corrected definition. No tag or release was created to exercise this event.

## Late visual failure: a moved shader function invalidated the mutation helper

The archived [visual job 137385028425](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45079559400/job/137385028425) on `847d8d1a` failed at 2026-11-22 23:56:18 UTC with `L9c surface review failed: cannot apply no-filter mutation to the current ground shader`. The preceding vegetation, horizon, atmosphere and cloud checks had progressed to this separate failure. It is a preparation failure in a negative-control harness; it is not a rendered-image rejection and is independent of the LU-34 source-budget finding.

Upstream extracted the unchanged analytic `square_filtered` body from `app/render/ground.gdshader` into `app/render/meadow_surface.gdshaderinc`. The runway still calls it, and meadow rows now share it. Both ground visual checkers call a helper whose regex expected the definition in the former file. The helper and these production source bytes are identical at `847d8d1a` and `3cc86387`.

Commit [e47284bb](https://github.com/bultodepapas/OpenRCsimulator/commit/e47284bb2f8750ad10fdd53519e84ab837353236) changes exactly the unique runway assignment in the disposable mutation project to the original raw ±1 square wave. Zero or multiple active assignments raise before the copied shader is written. The source shader, the shared include and all other copied shader bytes remain unchanged. This preserves the intended runway-only negative control without changing meadow filtering. The surface and stripe-reference receipts now hash the shared include; the stripe-reference receipt also hashes the helper that creates its mutant. All rendered measurement predicates and thresholds remain unchanged.

The existing GPU-independent stripe suite now runs during `all` and `ground` capture setup, after the required import and before the first production capture. It retains `ground:stripe-tests`, and the strict ordered receipt roster follows the new order. A controlled exit 12 stops both dispatches in setup without a full/group success receipt. Other groups retain their selected checks. This targets delayed feedback without removing any rendered gate.

| Local verification at the repair | Observed result |
| --- | --- |
| `env PYTHONDONTWRITEBYTECODE=1 python tools/ground/test_stripes.py` | 21 passed; unittest 0.419 s, process wall 0.752 s. Actual checkout shader/include fixtures; byte preservation and zero/duplicate-target refusal. |
| `env PYTHONDONTWRITEBYTECODE=1 python tools/ci/test_capture_groups.py` | 24 passed; unittest 41.346 s, process wall 41.555 s. Full/partial dispatch, strict membership and early failure without successful receipts. |
| Historical-helper negative control | The new source tests fail against the actual `3cc86387` helper on the current shader, reproducing the obsolete mutation-anchor error. |
| Separate CRLF control | Both raw-runway and disabled-surface mutations preserve every byte outside the target statement in the disposable copy; source bytes stay unchanged. |
| Bash syntax, whitespace and independent review | Passed; reviewer found no weakened predicate, missing group check or broadened production shader mutation. |

These local commands used CPython 3.12.14, NumPy 2.3.5 and Pillow 13.0.0. The hosted visual environment pins NumPy 2.5.3 and Pillow 12.3.0. Results and command output were captured in the session transcript; no durable raw suite log or suite-start wall-clock timestamp was recorded. Xvfb was unavailable locally. **Rendered L9c and L9c-R1 acceptance remains pending** on the repaired head and pinned hosted environment. The added tests verify source/dispatch behavior, not pixels or GPU performance.

The repair changes the application tree from `44faebf550d6257ef086760c2f50662faaf82957` to `dc5e9586d1ca8486e468e13d32ea897f98e7c573`. The complete app-tree diff contains only `capture.sh`. Production GDScript, shader and solver bytes retain their prior identities; the directly observed Home1/2/3 launches remain explicitly bound to the earlier app tree. They are not relabeled as new launches at the repaired head. All six changed harness/source-test files and their SHA-256 values appear in the [structured follow-up](CI_HOSTED_FOLLOWUP.json).

## Hosted observations on the renewed source before the visual repair

[Primary run 45087773718](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45087773718) evaluates head `3cc863879f4e088e50efd0768e2a6f3edaaaa607` using merge `c25851c0a5a87b9831af380924c9c7d2fa755fa0`. Its parents are main `843f357c` and that audit head, and its tree exactly matches audit tree `283112606f25e728c3b6543848bd9e2953994c48`. The observations below are bounded to that source, before the additional visual-harness change.

| Hosted result by 2026-11-23 00:40 UTC | Outcome and evidence |
| --- | --- |
| Source preflight and tooling | Passed in 85 and 123 seconds. Archived tooling output verifies the linter checksum, 141 CI cases and 459 queue cases, including 12 skips. |
| Website, prototype and both RC native builders | Passed. Linux RC production also passed in 576 seconds. |
| Windows NK-4 native qualification | Passed in 880 seconds. Actual native stage, session, replay and helicopter markers pass; the deliberate stage mutant is rejected. [Job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45087773718/job/137410819772) |
| Linux NK-3 native qualification | Passed in 1,209 seconds. The paired runtime-domain step prints `NK3_RUNTIME_DOMAIN_NATIVE verdict=pass` and `NK3 fleet policy: 634 checks, 0 failed`. Earlier stage/session/replay/helicopter/admission checks and the deliberate mutant control also pass. This closes the previously pending V7 native-request check on this source. [Job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45087773718/job/137410819726) |
| App integration step observation at 00:41:14 UTC | Full resource import, mandatory real-client telemetry and repaired trajectory/V7 fleet policy passed. The offline measurement/validation step failed; step metadata does not identify its failing subcommand. App integration and all eight unit shards were still running. This new failure needs archived-log attribution and receives no pass credit. [Job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45087773718/job/137410819853) |
| Telemetry contracts | Passed in 44 seconds. [Run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45087773694) |
| Portable GOD TEST matrix | Linux, macOS and Windows all passed, in 30, 26 and 33 seconds. [Run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45087773669) |

At this observation cutoff, the actual macOS native/default route, app integration, all unit shards and visual aggregate had no completed passing verdict. The old visual helper remains present in this run's source. Publishing the repaired branch supersedes its ongoing PR execution; any later cancellation does not invalidate the completed job observations or turn incomplete jobs into successes. No full aggregate or hosted performance gain is claimed.

## Qualification still required

The final published follow-up must pass every selected production gate, including actual macOS native/default-route qualification, companion unit shards, complete discovered-script rosters and the repaired rendered negative controls. Linux and Windows native checks passed on `3cc86387` as recorded above; no complete final-head verdict is inferred. The separately verified LU-34 source-budget regression remains unresolved and is expected to keep its required consumer red until the geometry is corrected. The repaired offline step already passed on `847d8d1a`; the later renewals have independent source-bound evidence. Cancelled runs and preflight rejections are not successful qualifications. PR events leave main/tag-only export and release transfer paths unexecuted. Keep the PR in draft while reviewing the current check results. The recommendations for controlled rendering comparisons, export-import diagnosis and administrative check enforcement remain applicable.

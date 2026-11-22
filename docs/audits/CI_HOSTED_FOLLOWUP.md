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
| [Tooling](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45078157682/job/137380124945) | Passed in 129s. Sparse checkout took 4s; actionlint, 139 CI cases and 459 queue cases passed, with 12 queue skips. The extra queue case came from the concurrent upstream changes. |
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

## Qualification still required

The latest audit-head PR run must pass preflight, the corrected offline fixture, the complete discovered-script roster and every selected production gate. The earlier cancelled run and the later preflight rejection are not successful qualifications. PR events also leave main/tag-only export and release transfer paths unexecuted. Keep the PR in draft while reviewing the current check results. The main report's recommendations for controlled rendering comparisons, export-import diagnosis and administrative check enforcement remain applicable.

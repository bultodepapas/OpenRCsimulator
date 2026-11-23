# CI audit checkpoint after execution-environment loss

**Recorded:** 23 November 2026 UTC. **Branch:** audit/ci-quality-performance-overhaul-2026-11-22. **Pull request:** [#21, draft](https://github.com/bultodepapas/OpenRCsimulator/pull/21).

The audit implementation is preserved, but **final qualification is incomplete**. The execution environment became unavailable during the current-source Godot import. No successful recovery, renewed companion behavior manifest or fresh Home admission is claimed. The original geometry budget failures remain enforced.

[Comprehensive audit](CI_AUDIT_REPORT.md) · [Structured checkpoint](CI_AUDIT_CHECKPOINT.json) · [Hosted history](CI_HOSTED_FOLLOWUP.md)

## Source and publication boundary

The implementation through [2485e36e](https://github.com/bultodepapas/OpenRCsimulator/commit/2485e36e90f6c6ee155592b8da70dd65c3663ffd) has application tree **8eecf1ffd605a97f4fbf956772a0396e358fb9c6**. Documentation-only checkpoint updates do not change that application tree.

The integration preserves all 59 changed paths through upstream main commit **bfbad672617ef2bc8b3065ac0e81bbd10fd2a5ab**, which adds 12 commits after the main source used by the completed audit run on 8ce11eb2. Thirty changed paths are under app. An independent local reconstruction checked all **6,020 application paths**, file modes and effective checkout bytes, including 29 explicit CRLF conversions, and 27 external aircraft authoring records.

All 203 normalized solver inputs reproduce the accepted SHA-256 **0954434e94c8dd31cb6183c8de34da00c81736545228a95249e899a936ef617b**. This does not qualify the changed startup code. The sole stale behavior-manifest entry is res://app_root.gd: its normalized source hash changes from 75626bac8dfacf87bddb436520a0f3370a97714595a142f4bf3c6fb076a9cc7d to a34c738b48f52f2ac64f60a3230a77de22b2a901fe1cc9013937060a2171cac2.

The changed call supplies current display capabilities to automatic graphics selection. That branch executes during ordinary nonheadless first-install startup. Headless Home admission, when rerun, will establish companion admission and collision behavior; it cannot alone establish first-install renderer or MetalFX hardware behavior. **No behavior or profile pin was changed after this upstream integration.**

## Retained implementation

| Commit | Net change and evidence |
| --- | --- |
| [438e3aa3](https://github.com/bultodepapas/OpenRCsimulator/commit/438e3aa3d9b7e09558edc93d3c379253c3eba020) | Stop advancing injected telemetry time while a real HTTP request is active. Preserve the production sender/queue, five-second request timeout, 20-second drain deadline and all delivery/storage/privacy predicates. Delayed success, rejected response and stalled response controls are retained in the [original receipt](telemetry-clock-2026-11-23/receipt.json). |
| [220e6493](https://github.com/bultodepapas/OpenRCsimulator/commit/220e6493aa5995ef6b8fc1c11e8c16b866b0f3f5) | Integrate the complete upstream change set, withdraw provisional product mesh changes and their default capture gate, and enroll 22 existing scenery generator cases plus the countryside bake comparison. |
| [e6a7f824](https://github.com/bultodepapas/OpenRCsimulator/commit/e6a7f82426729995fca6608210f17cc99b30de51) | Regenerate woodland input evidence and two exact census expectations for the new forage boundary. Keep every placement, rule and clearance unchanged. |
| [2485e36e](https://github.com/bultodepapas/OpenRCsimulator/commit/2485e36e90f6c6ee155592b8da70dd65c3663ffd) | Defer the optional diagnostic prototypes as well. Final review found unchecked JSON completion, and native framebuffer validation was unavailable. The established furniture capture tool is restored; the new hedge tool is absent from the net diff. |

The earlier architecture, structural workflow lint, native/trace coverage, readiness, screenshot freshness, unit keep-going diagnostics, shader-mutation controls and bounded qualification work remain in the branch. Their complete decisions and source-specific verification are in the [audit report](CI_AUDIT_REPORT.md).

## Generator coverage

The source phase of app/test.sh now invokes the 11 existing Club placement cases, verifies the countryside bake against the committed file, and runs the 11 countryside cases. The existing all, integration and integration-source partitions share this route. No new runner, Blender dependency or third-party Python package is added.

The isolated fixture launched from outside the repository with no inherited PYTHONPATH. The placement suite enters the repository root for its tools.scenery package import. The countryside suite uses its absolute script path and sibling module import. Effective CRLF bytes for app/data/fields/default.json are required because the generated countryside records the source byte hash.

| Observed local command | Outcome |
| --- | --- |
| Existing place.py --check | Pass; 2.990 seconds process wall time. |
| Placement unittest module | 11 pass; 6.142 seconds wall time. |
| bake_countryside.py --check | Exact retained output match; 0.196 seconds. |
| Countryside test script | 11 pass; 29.516 seconds wall time. |
| Disposable countryside output with one added newline | Correctly rejected, exit 1; 0.184 seconds. |
| Existing app partition fixture | 16 pass in 30.139 seconds; Bash syntax and whitespace checks also pass. |

The enrolled app/test.sh SHA-256 is **bf5203372cb510e69a1af19271aa4e2f4bcdb6ef4bf58fe100053f7f7bdbbb4c**. Independent review confirmed the imports, partition selection and failure propagation. These timings establish local cost only. No hosted increase or decrease is extrapolated.

The current Linux portable GOD TEST rehearsal separately passed **217 tooling cases and 31 frame-watch cases**, then produced the nine-case dry-run plan. This is portable tooling evidence, not GPU/flight acceptance. Current-source Windows/macOS results remain independent.

## Woodland

Against the already-qualified 8ce11eb2 woodland document, regeneration changes exactly four leaves: source hashes for scenery/default.json and imported_hedge.gd; checked fence segments **44 to 46**; and checked patch polygons **5 to 6**. The two new fence segments and crop polygon account for the census change. Every placement, footprint, envelope, prior clearance margin and exclusion rule compares equally.

The unchanged generator produces four patches and 472 source triangles. Its deterministic check and all six original Python cases pass. The generated output SHA-256 is **a6987f9cb9457c71027ea60765f169381c52883ed4b42fe73bfd30f0668b077c**. The earlier eight-leaf renewal in CI-16 belongs to a different comparison baseline; it is not silently reused as this later result.

## Geometry and rejected alternatives

| Local complete-field cohort | Cells, allowance 175,000 | Other, allowance 8,000 | Decision |
| --- | ---: | ---: | --- |
| Unmodified bfb production geometry | 180,468 | 9,365 | Retained, with original failing gates. |
| Furniture stride-two experiment | 176,484 | 9,365 | Withdrawn. |
| Furniture experiment plus 424 fitted wild cards | 176,484 | 8,941 | Withdrawn. |

The new forage fence accounts for all 1,722 additional Cells triangles. After valid woodland regeneration, the three existing consumers—scenery build, landscape vegetation and farm tractor—each reproduced one shared budget assertion failure, exited 1 and reported zero engine errors or warnings. Their limits and category definitions were not changed.

The previous experiment [a0474179](https://github.com/bultodepapas/OpenRCsimulator/commit/a0474179efe023658461547dc01c4d4fdcc33eaa) passed the counters on the earlier nonmipmapped atlas/field. Its [dated local evidence](geometry-budget-2026-11-23/README.md) remains historical, including bounded color/debris differences and collision checks. It did not establish rendered equivalence or frame-time benefit.

For the newer planted forest atlas, actual imported alpha-preserving mip levels retain samples across a 15/16-by-1 rectangle. Any fixed triangle containing the four demonstrated corners has at least **1.875 times the original source-card area**. This is a geometric lower bound, not measured fragment work or GPU time. The original fitted triangle clips those accepted coarse-mip samples. The audit therefore keeps the upstream forest atlas, mip filtering, both hedge quads and furniture.

Remaining valid reductions still fail both caps and introduce maintenance or appearance tradeoffs without a measured hardware benefit. Exact duplicate/degenerate and covered-face investigations did not supply sufficient equivalent savings. Source-triangle totals multiply shared MultiMesh geometry by instances; they are regression proxies, not an allocation-by-allocation measurement of resident mesh memory. Per-view primitives, draws, shadows, texture use and actual hardware timing need their own measurements.

An optional culling diagnostic was also explored, but it is **deferred and not shipped**. It had local parse, binding, projection and refusal evidence only. Its single-card counterexample would still require confirmation at an actual multi-instance Club batch boundary. Loaded sampled-texture identity and durable JSON writes need qualification before promotion.

## Completed hosted evidence on 8ce11eb2

[Run 45091058487](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45091058487) tested merge a1fd7faa1d35f955b35c0d1711ddfa9aec1c5426, whose tree exactly matches 8ce11eb2. The required aggregate failed. There were 29 job entries: **18 success, four failure and seven skip**.

The full visual job passed in **113 minutes 24 seconds**, including L9c surface and L9c-R1 stripe controls and the final 46 fresh images/trace check. An existing classified completed-import SIGABRT retry recovered. This is not a pristine-attempt claim. The 2.54 GB archive was not downloaded; the completion evidence is the actual job log and artifact metadata.

Linux and Windows native correctness, both RC builders and both RC production lanes passed. The downloaded macOS artifact independently verifies the installed default route's 74 checks, 72 domain checks, 2,400 isolated calls and separate stage/session/replay controls. A virtual Apple M1 qualifies hosted software correctness, not physical-Mac performance.

All 947 app-integration harness invocations passed. The separate mandatory telemetry step failed after the receiver stored three batches but the driver reported two sent and one dropped. Unit shards 3 and 7 exposed three consumers of the same geometry overages. The [structured hosted record](CI_HOSTED_FOLLOWUP.json) retains all 29 jobs and their timestamps.

Summed active time was **512.25 unweighted runner-minutes** across 22 executed entries. This PR source differed from the historical main sample and did not select export/package jobs. No causal speedup, billing reduction or final-candidate green aggregate follows from that comparison.

## Interrupted qualification and evidence limits

The fresh current-source Godot import ended with process exit **−9 after 153.315 seconds**. It had no engine errors and eight ambient OBJ warnings. The cause of the kill is unknown.

One recovery privately copied 64 cached model scene/MD5 pairs only after checking unchanged model sources, import settings, 112 external resource references and output digests against the retained pinned-engine cache. It kept this candidate's new forest import. Complete source verification was repeated. The recovery reached 99% of editor scan before the shared execution transport disconnected. Reconciling its original session 7967 returned “No usable execution environment is available.” **No final exit, successful checked receipt, new collision identity, tamper-control outcome or fresh Home1/2/3 admission was observed.**

The immutable GitHub commits retain the implementation, earlier telemetry control packet and historical experiment packets. Post-bfb local measurement files, the new full raw receipt packets and the last workspace report draft were not recovered after disconnection. The checkpoint JSON records the observations and original file hashes available in the session. It is a transparent transcription of those observations, not a substitute for unavailable raw engine logs.

## Required continuation

1. Recover or recreate the exact frozen source and verify the pinned editor/import state. Reconcile the original process if the workspace returns; do not launch a duplicate blindly.
2. Run normal stale-source refusal, expected refusal and tamper controls. Renew only the changed app-root behavior entry and its linked profile manifest identity after bounded behavioral qualification.
3. Run fresh ordinary Home launches with one, two and three companions and no override. Record actual collision identity and admission outcomes. Keep the unchanged solver/tapes intact.
4. Resolve the current scenery budget failures through a justified product or allocation decision supported by per-view and target-hardware evidence.
5. Inspect the final source-specific GitHub gate, including all required shard receipts, native lanes, telemetry and rendering. Keep the PR in draft while required checks fail or remain incomplete.

No default-branch write, release publication or enforcement change was made.

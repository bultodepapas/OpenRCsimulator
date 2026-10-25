# UI-34c / DT-11a — selected flight preparation in Home

2026-10-25. Runtime `73086db4d`, frozen control `25bb32b5c`, companion rebind `cf21cea5a`. Follow-up `1edaa833f` enables native preparation and repairs branded startup. The [execution plan](../../../../MENU-REDESIGN-PLAN.md#selected-preparation-while-home-is-visible) owns remaining acceptance; [primary-source research](../menu-prefetch-2026-10-25.md) explains the approach.

## Implemented behavior

Native Home defaults to `scene_trim`; headless preparation stays off. The probe explicitly selects `off`, `scene`, `trim` or `scene_trim`. A 350 ms stable-selection delay, Home's first actual draw, a settled preview and fixed-wing eligibility gate preparation. The common scene loads first, then the selected numeric request. Temporary validation nodes are freed before the numeric worker starts; no active simulation runs behind Home.

Fly adopts pending work. Preview construction waits while the scene loader runs, including cached/procedural callbacks; only the latest request survives. The scene shares the existing two-resource broker. Numeric arguments remain private, object-free and byte-keyed; two accepted results share the existing 1 MiB aggregate key bound. One additional pending/private result is owned until final validation or discard. These are cache bounds, not process-memory limits.

Cancellation and Quit keep main processing while workers drain. Root-owned scene jobs survive departing consumers. A bounded cache-owned frame callback collects abandoned numeric work and disconnects. Workshop, ground and Natural Random drain preparation before candidate construction. Pending A survives A→B→A; completed private A yields once B settles. Field intent changes immediately while visual rebuilding waits.

Final candidate validation still runs. An injected rejection exposed a reset retry that could synchronously solve and cache after rejection; staged failure now parks the invalid session without retry. Synchronous technical setup retains its behavior. Selected-weather/fuel ordering, solver arithmetic, physics data and golden recordings are unchanged.

Branded startup also uses the existing dedicated ordinary-load owner. Its old nested `load_threaded_request` path leaked 57 count-zero RefCounted objects on the frozen control. Corrected native boot, idle preparation and Quit report zero leaked objects. Startup drains pending work on close and restores the original quit policy before AppRoot attaches. Three pre-existing `MOON_UMBRA_*` unclaimed StringNames remain in verbose output; this is not an entirely clean engine-shutdown claim.

## Matched native measurements

Windows, pinned Godot 4.7.2 `ed1daf0bf`, Compatibility, Ryzen 9 5900X, RTX 3090, NVIDIA 617.42, fullscreen **1920×1080**, Dummy audio. Five fresh-process pairs alternate control/candidate order; each has a first and warm flight with **5 s Home dwell**. All 20 first draws are active; all checked runs finish without errors/warnings. [Raw pairs and medians](native-summary.json), [source identities](source-identity.json), [checked receipts](native-checks.json).

| Median | Control, off | Candidate, combined |
| --- | ---: | ---: |
| First click → ready | 7.482 s | **1.698 s (−77.3%)** |
| Warm click → ready | 1.350 s | 1.348 s |
| Home → ready, including dwell | 12.491 s | 6.702 s |
| First loading feedback | 16.661 ms | 16.602 ms |
| Largest Home dwell frame per run | 37.146 ms | 36.522 ms |
| Largest loading frame per run | 275.949 ms | 282.173 ms |
| Static allocation growth during first dwell | 0.572 MiB | 18.701 MiB |

The worst candidate Home dwell frame across five pairs is 39.738 ms; the worst loading frame is 291.298 ms. Preparation uses menu time but does not split indivisible world/contact builders. First Home draw medians are 5.706/5.551 s; that difference is not attributed to this change.

OS/import/shader caches were uncontrolled. Our source suite was paused at a shell boundary throughout the cohort. An idle language server and later transient language-server processes were observed; no other rendered app was observed during the pairs. These are repeated matched observations, not a perfectly exclusive host, cold-cache claim or general qualification. The probe explicitly enabled preparation before the default-enable/startup follow-up; its route bypasses the intro.

## Experiments and resource lifetime

[Mode/dwell experiments](mode-experiments.json) are single observations, not replicated comparisons:

| Turbo configuration | First click → ready |
| --- | ---: |
| Combined, immediate Fly | **7.357 s** |
| Combined, 2 s dwell | 4.382 s |
| Combined, 10 s dwell | 1.653 s |
| Scene only, 5 s dwell | 6.061 s |
| Trim only, 5 s dwell | 3.491 s |

Combined 5 s dwell gives Stik 1.663/1.412 s first/warm and Avanti jet 1.866/1.522 s. Debounce 0/750 ms gives 1.768/1.641 s in single 5 s samples; neither is established as better than 350 ms. Keep the stable-intent guard.

The [20-transition native soak](native20.json), with 500 ms dwell, completes every cycle active: Home has 809 nodes and zero reported orphan nodes throughout. Static memory before Fly is 220.818 MiB at cycle 2 and 221.342 MiB at cycle 20 while the probe retains growing report arrays. [Sampled peak RSS](native20-resources.json) is 1528.9 MiB across 76 samples. [Strict exit receipt](native20-report.json) is clean and preparation/audio drain. Static allocator counts are not RSS/VRAM; this short run does not establish DT-12's 50-cycle/30-minute gate.

A debug-bridge selection trial during a reloaded common scene accepted Extra and settled its warm preview within 462 ms including command round trips. Its 30-frame window had a 206 ms maximum attributed to preview construction. The preview was settled at the next query, so this does not qualify fully cold blocked previews or pure input latency. [Selection and boot observations](lifecycle-observations.json) retain their limits.

## Software verification

[Checked receipts](checked-runs.json) retain engine/log identities. New tests cover 29 numeric, 15 coordinator and 11 setup-notification checks. Expanded flight loading covers 28; existing cache/async tests cover 47/24. Startup has 36 checks covering pending/paused/duplicate close, raw free before/during fade, skip/handoff and failed load. The Home UI suite, six loading-probe groups and four unchanged golden flights pass.

Matched Stik/Turbo cards (`trim_sweep,stall_power_off,vmax,roll_rate`) have four valid cases per aircraft and [zero changes beyond tolerance](flight-compare.md). Nine companion tapes produce [byte-identical CSVs](companion-rebind.json); this is software parity, not renewed physical qualification. Debug-bridge headless smoke completes 14 steps, 145 seeded UI actions and three flight/Home cycles, with no errors, growing counters or leaked objects at exit. The final native branded boot reaches an active Stik flight and quits with zero leaked objects; this functional run shares the host with source-suite work and is excluded from timings. The [full source suite](source-suite.json) stops at two existing model-clone fixture failures, both reproduced on the frozen baseline: CRLF bytes in the expected LF clone and a missing F4U livery GLB/import sidecar in the temporary clone. Later all-script/integration/export gates were not reached.

[Working-tree integration](main-working-tree-integration.json) applies our exact changes to main without staging or committing its unrelated in-progress merge. Main index and MERGE_HEAD hashes remain unchanged. The 36 startup checks and AppRoot parse pass there; [final source identities](final-source-identity.json) match. Five pre-existing conflicted aircraft customization/Workshop JSON files prevent claiming a complete integrated runtime pass until their owner resolves the merge.

## First-view investigation: runway start

2026-10-25 follow-up: the user reported an inside-aircraft view before the pilot view on runway launch. Saved settings selected Avanti. Inspection confirmed that `PilotCamera.create()` activated an identity/origin camera and staged Main could report completion before its first `_render_pose()`. Camera position changes directly to the pilot station; there is no pilot-position transition to tune.

The camera now enters the tree at the configured pilot eye. Valid staged interactive and explicit `--quick-flight` launches place their final aircraft/camera pose before `startup_finished`, without advancing ticks, polling input or modifying the session checkpoint. Capture, trace, scripted and ordinary technical launches retain their existing first-process behavior. Sixteen focused checks pass with strict diagnostics on both production Godot 4.7.2 and the native 4.8-dev trial, including runway/airborne readiness, quick-flight's first pose and checkpoint byte identity. The earlier staged fix also passed 91 existing camera checks, 28 integrated loading checks and all six probe fixture groups.

[Earlier Home per-draw evidence](camera-handoff.json) records nine native diagnostic cycles at 1920×1080, including current-main Avanti runway before/after. Before the fix, Avanti had 14/9 origin-camera frames, all hidden by the loading surface. Afterward it has zero origin frames and zero completed-but-unplaced camera frames; both first visible draws use the pilot view and active flight. These Home runs did not reproduce a visible flash. The optional probe observer records first reveal rather than inferring camera readiness from a valid session alone.

The user then identified the agent-launched tests. **The exact visible flash is now reproduced in the older native graphics snapshot's `--quick-flight` route.** It bypasses Home's loading surface and had neither camera correction. At 1920×1080, Movie Maker frame 0 is inside the Ugly Stik fuselage and frame 1 is the pilot view. After the fix, both frames show the pilot view. [First-frame evidence](quick-flight-camera.json) retains commands, frame hashes/dimensions, source identities and strict check receipts. This supersedes the earlier unconfirmed-symptom conclusion for that test route.

The [native preparer](../../../../../tools/graphics/native/README.md) now imports the pinned pilot-camera helper and only Main's `_ready` function, preserving the older graphics trial's dependencies. It includes the focused regression test; repeat preparation produces an identical receipt and package preflight passes without exporting. Movie Maker uses a `movie` feature override for actual 1080p output because window resolution alone leaves its historical 720p viewport ([Godot documentation](https://docs.godotengine.org/en/latest/tutorials/animation/creating_movies.html)). Captures remain under ignored `tmp/`. Fixed FPS, image readbacks and encoding exclude these runs from performance acceptance. Both forced three-frame exits report 19 retained ObjectDB instances; the final recording also reports low disk space but completes all frames. Those captures do not qualify shutdown stability; both focused headless runs have zero engine errors or warnings.

## Remaining work, in order

1. Improve immediate Fly: after freezing and validating its request, start managed numeric work before world construction, then adopt at the existing validation boundary. Compare identical 0/2/5 s dwell and exactly one solve. This next slice is not implemented here.
2. Split measured field/contact/sound and preview construction above 100 ms. Preserve rendered loading feedback and the readiness barrier; do not move costs to first use.
3. Complete cold blocked-preview and native setup/route matrices, package/export gates and DT-12. Global immediate Fly ≤2 s and Home ≤5 s remain open.
4. Investigate default-weather/full-fuel trim followed by selected-setup refitting with explicit parity evidence. Persistent disk caching is not yet justified.

The pinned Windows Thread backend has no priority hook: LOW does not protect menu cadence there. Bound concurrency and measure it. [Windows backend](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/windows/thread_windows.cpp#L48), [hook contract](https://github.com/godotengine/godot/blob/4.7.2-stable/core/os/thread.h), [thread safety](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html). Commands and probe semantics remain in the [performance tools guide](../../../../../research/performance/README.md#homefly-loading-and-lake-geometry).

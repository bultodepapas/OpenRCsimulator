# Validation and benchmark protocol

2026-11-15 · Proposed evidence for the [implementation work order](05-integrated-implementation-plan.md). No benchmarks in this document were executed by this audit. The existing [VQ numerical/human gates](../../plans/advanced-graphics.md#numerical-and-human-acceptance), [FSR completion plan](../../plans/amd-fsr-completion.md), [Apple master](../../plans/apple-silicon-performance.md) and desktop gates remain authoritative.

## 1. Preserve identities and define the claim

Every run needs application commit/tree and any overlay hashes; engine/editor and export-template identity; patch/SDK/runtime identity; package and import data; GPU/CPU/driver/OS; actual renderer/API and display server; monitor/refresh/VRR, window/present mode, AC/battery and power policy; aircraft/field/weather/time/camera and input-tape identity where the workload supports replay; AA/effects/scene detail; requested and effective provider/scale; and actual versus estimated drawable/internal pixel sizes. Save run completion, failure/exclusion reasons and source hashes alongside the summary.

Physical F6 trials use **live transmitter input**, documenting transport, stick movement, threshold and operating conditions instead of replay. The [current latency-patch parser](../../../app/input/latency_patch.gd) rejects `--scripted`, `--frametimes`, `--trace`, `--capture` and `--visual_pose` in that route. Collect those incompatible diagnostics in separate matched runs; do not remove the live-input guard or pretend the optical and scripted observations came from one run.

State which question the comparison answers. A within-build Reflex mode comparison isolates its request. Official-versus-fork comparison includes engine differences. Native-versus-temporal reconstruction includes a different AA method unless deliberately controlled. A scene with physics/input disabled measures rendering under that fixture, not active-flight smoothness. GPU completion is not presentation, and an OS present callback is not physical scanout.

The [input manifest](evidence/source-manifest.json) preserves this audit's inspected source identities; it is not a benchmark receipt or a complete binary/asset dependency closure.

## 2. Reuse the project tools

Use the [tool index](../../tools/README.md), [frame diagnosis](../../tools/graphics.md#frame-diagnosis), [debug bridge](../../../tools/debug/README.md), [GOD TEST](../../../tools/godtest/README.md), native graphics/MetalFX guides and existing collectors. On shared hosts use [test-queue ownership](../../../tools/testqueue/README.md); a port is not ownership. Reserve the GPU, retain the session handle and stop it cleanly. Use source- and preference-isolated workspaces. Do not add another ad-hoc FPS collector or run parallel workloads during a performance comparison.

The documentation-only audit needs link/content/source checks. Future code changes use the smallest relevant existing checked tests, then the required candidate/CI gates; broad physics tests are not a substitute for a rendered provider test.

### Strengthen only the contracts the next decision needs

The [M0 work budget](05-integrated-implementation-plan.md#m0--bounded-measurement-repair) is the authoritative five-engineering-day limit for the initial repair/attribution milestone. The following are focused checks of those repairs, not a request for new test executables or a complete new platform matrix.

| Existing boundary | Required strengthening | Discriminating check / failure behavior |
| --- | --- | --- |
| `frame_diagnostics` and debug `render_probe` share the rendering-server flag | One lease owner keyed to a live viewport generation; idempotent teardown. | Start A/B and stop in both orders; repeated starts/stops; two viewports; delete/recreate viewport. The remaining consumer stays active and a freed RID is never reused as old state. Extend their existing tests. |
| Sample collection and offline reduction | Distinguish numeric value, validity, scope, polling sequence and actual completed-sample identity where provided. Preserve old report compatibility. | Inject missing, negative, non-finite, ambiguous zero, stale/duplicate identity and generation-change cases. Equal durations alone are not duplicates. Unknown completion/age remains unknown and blocks adaptive feedback. |
| Baseline/candidate identity | One existing manifest/receipt links source, package, renderer, actual drawable, requested/effective mode, cap and workload. | A deliberately mismatched identity or incomplete run is rejected by the existing reducer. Keep a historical receipt readable without upgrading its evidence scope. |
| Observation cost | Measure ordinary collection versus added diagnostics in separate matched blocks. | Proposed added process-loop p95 ceiling 0.2 ms, with uncertainty; scene census, traces and captures are outside timed acceptance. If unresolved, disable intrusive observers and keep DRS ineligible until its persistent feedback cost is qualified. |
| Decision output | One candidate result in its existing owner evidence. | The result names a product change or retain/defer verdict. More counters, screenshots or tools are not a passing product outcome. |

The first M0 hardware row is one **available** native reference configuration, preferably the existing Windows NVIDIA package for shared reconstruction/Reflex questions, or the existing M1 path when that is the available target. Do not wait for Apple, Windows, Linux, AMD and Intel simultaneously. Qualify other rows as their implementations become finalists. A fixed-provider comparison may proceed with explicitly limited GPU attribution; DRS may not consume a sample whose required association is missing.

External reference studies [R13](investigations/R13-presentmon-existing-capture.md), [R14](investigations/R14-tracy-bounded-attribution.md), and [R15](investigations/R15-godot-timing-contract.md) explain how to reuse PresentMon, optional Tracy and exact-version Godot timing. An extra profiler is conditional on an unresolved question; these are not three required installations. There is no new executable, service, dashboard, profiler protocol or cross-platform telemetry framework in M0's deliverables.

## 3. Minimum experiment design

1. Start at **actual 1920 × 1080 output**. Identify the native drawable rather than assuming a window's logical size is pixels. Run the named primary target before 1440p/4K; treat 720p as last fallback evidence.
2. Freeze source, selected engine/template, content and power/display conditions. Use the same real input/tick tape where applicable, keeping simulation time and camera conditions comparable. Start with a baseline that meets correctness/lifecycle gates.
3. Record at least the existing **10-second warmup, 60-second measurement and three alternating A/B pairs** for an eligible controlled screen. A/B/A bracketing helps reveal thermal or background drift; it does not replace repetitions. Do not discard inconvenient complete runs. A short screening pass does not replace the longer desktop/endurance gates.
4. Separate cold-start/first-use compilation from warmed flight. Preserve both results. Disable intrusive validation/readback capture during timed production comparisons after correctness was checked separately; record instrumentation overhead and whether the validation layer is enabled.
5. Isolate each mechanism initially: fixed reconstruction, dynamic policy, Reflex modes and a single RT effect. Reflex qualification may proceed independently of DRS after the common baseline. Record combined-mode acceptance afterward, because independently acceptable features may interact.
6. Publish all eligible run distributions and exclusions. Analyze matched blocks and repeat across independent sessions, reporting between-session variation and uncertainty; adjacent runs can share thermal/background effects, and thousands of autocorrelated frames are not independent experiments. Three pairs are a screening minimum, not proof of a precise estimate. A performance claim requires repeatable evidence exceeding noise, not one favorable average.

Before collection, write the candidate's **one primary metric**, useful-effect threshold, protected metrics and allowed repeat rule in the existing evidence record. A formal VQ optimization claim uses the owning plan's 5% complete-workload threshold or a named reproducible hitch/memory correction; do not choose whichever statistic improves afterward. A visual feature uses its predeclared visual defect and cost envelope. A descriptive F6/Reflex comparison reports the physical difference and uncertainty against a predeclared useful latency threshold and no-regression guards; a small supported difference may inform a mode choice without being labeled an accepted VQ optimization. Permit one predeclared repeat campaign for a named uncertainty/confounder; if the verdict remains unresolved, retain baseline or experimental status. More samples are not an automatic next task.

### The verification funnel limits work before implementation

| Stage | Scope now | Deliverable / next action |
| --- | --- | --- |
| M0 / inexpensive screen | One host, actual 1080p, one representative active-flight route, ordinary collection, one candidate and the control that distinguishes the suspected mechanism. | Choose the first correction; reject invalid/no-benefit paths early. This is not release qualification. |
| M1 / M2 / M3 / M4 finalist | Only the changed feature's relevant history, ownership, failure, motion and measurement cases. For DRS, Native/best fixed/adaptive; for Reflex, Off/On/Boost within one build; for RT, raster/effect plus raw visibility correctness. | Implement and validate the smallest feature. Include negative cases, not every possible combination. |
| M5 combined/export | The accepted features together, affected cross-feature cases, exact export/startup/recovery, full owning hardware/pilot/lifecycle obligations. | Accept a named row, keep experimental, retain baseline or defer. Expand the matrix only for a support claim or changed dependency. |

Time spent **using existing tools to qualify a finalist** is distinct from engineering a new tool. M0 and later attribution caps constrain development/initial investigation; they do not waive required native, physical-input or package checks. If those checks cannot be completed, narrow the support claim and keep the affected feature unqualified.

## 4. Required workload and failure matrix

| Case | What it distinguishes |
| --- | --- |
| Ground contact and runway idle with active physics | CPU/session/observer bottlenecks; a lower resolution must not hide simulation slowdown. |
| Pilot flight with a small rolling aircraft against sky, terrain and trees | Attitude/silhouette readability, ghosting and scale-transition distraction; detecting a dot is insufficient. |
| Low approach, chase/zoom, fast pan and camera cut | Temporal history, disocclusion, shadows/contact cues and motion-vector consistency. |
| Dense vegetation, water and auxiliary viewports | Alpha-tested geometry, additional GPU passes, fixed versus scalable cost and the incompleteness of root-only GPU timing. |
| Propeller/rotor, smoke, night lighting and changing weather | Transparent/reactive/history failure cases and RT coverage; qualify applicable vehicles separately. |
| Cap/VSync/VRR, CPU-limited and GPU-limited controls | Whether a wait or CPU load, rather than scalable GPU work, explains the target miss. |
| Resize/fullscreen, Retina/monitor transition, pause/minimize/focus/restore | Generation changes, incorrect dimensions, stale timing, reset, suspend/resume and display recovery. |
| Home → Fly → Workshop → Fly; aircraft/scene change | Ownership, old resources, scale/provider restoration and scene acceleration-structure lifetime. |
| Missing SDK, allocation failure, feature unavailable, stale result and backend loss | Honest effective state, bounded fallback, safe resource retirement and preserved user request. |

Use the rows applicable to the changed behavior. Finalists/combined integration need at least 20 repeated warm ownership cycles where specified; desktop package qualification separately retains its 50-cycle and 30-minute soak obligations. These are not mandatory repeats for every localized edit. Missing active-flight, full material coverage or a named hardware row remains an open gate.

## 5. Measurements and interpretation

| Measurement | What to record and what it cannot prove |
| --- | --- |
| CPU | Main/process interval, complete simulation/tick/observer work and render-thread/setup time separately. A viewport render-CPU timer excludes much of the game. |
| GPU | Valid, sequence-associated intervals and measured scope; main scalable pass, auxiliary viewports, upscaler, AS build, RT and denoise where available. Do not sum overlapping intervals or reuse stale subviewport readings. |
| Frame pacing | p50/p95/p99/max and recurring hitch counts, real completed render IDs/intervals, cap/wait state and target attainment. Average FPS alone is inadequate. |
| Physics | Simulation/wall-time ratio, dropped/catch-up behavior, source/input/replay identity and existing equivalence gates. Keep the existing 0.99–1.01 campaign gate where applicable. |
| Memory | Current/peak render allocations, process memory, growth by ownership cycle and observed device limits; distinguish allocated versus resident/private/unified memory. |
| Dynamic scale | Requested maximum/floor, effective integer dimensions, sample age, controller state/reason, every scale event, transition cost and settling/reset evidence. |
| Presentation | Real versus generated frames, OS present IDs/times only where observable, compositor/refresh state, dropped/repeated frames; physical display evidence separately. |
| Latency and energy | RC stick-to-patch and stick-to-visible-control response separately; PCL/software metrics; power/clock/thermal state for Reflex On versus Boost. |

At 60 Hz, the ideal frame budget is `1000 / 60 = 16.667 ms`. The existing campaign's process-loop **p95 ≤18 ms and p99 ≤25 ms** are explicit acceptance thresholds, not a mathematical guarantee of every-refresh delivery. A 60-FPS average, generated cadence or positive GPU ticket cannot establish a locked 60-Hz physical presentation.

At 1080p, a per-axis scale of 0.85 renders about 72.25% as many base pixels; 2/3 renders about 44.44%. These are geometry-of-resolution calculations, **not predicted FPS gains**. A useful screening model is `GPU time ≈ fixed cost + scalable pixel cost × scale² + reconstruction cost`; shadows, geometry, CPU work and upscaler overhead can dominate. Measure the terms and the full frame rather than assuming inverse-square speedup.

## 6. Feature-specific pass and stop conditions

### Dynamic resolution

Test the policy with deterministic sequences: over-budget GPU, under-budget GPU, CPU-bound target miss, cap wait, one spike, noisy threshold, stale/duplicate/zero samples, viewport loss, provider fault, range conflict, settings preview/revert and user Off. Verify state, bounded updates, no oscillation, no disk writes per frame and no physics changes. Test both stop orders for simultaneous GPU-timing consumers.

On hardware, compare Native, the best eligible fixed mode and adaptive mode under matched load. The controller passes only if the predeclared complete-workload benefit, transitions and full-frame tails pass and pilot readability does not regress. Record each scale event with observed old/new integer dimensions, known sample identity/age, generation and suspend/reset reason; inspect both steady-state distributions and event-centered windows so a short transition hitch is not hidden in a long average. Report floor residency and target misses. A repeatable CPU bottleneck, unbounded history loss, missed input generation, unsafe allocation or a prettier GPU average with worse presentation is a stop condition. A fixed mode that already meets the goal can close the work without an adaptive option.

### Reflex and Boost

Compare Off, On and On + Boost within the same fork/build and presentation condition. Check Sleep/markers even while Off, frame-token association, serialized SDK state access, failure and lifecycle. Complete the exact SDK's verification/flash path where available and keep that qualification open if it is missing. A missing vendor flash path does not block a correctly instrumented F6 optical or normal-player VSync/window comparison; report those results separately from full SDK verification.

For optical measurements, keep threshold, transport, display scan position, camera placement/exposure and frame interval fixed. The existing F6 minimum of 30 transitions is a screen; at least 100 per condition across repeated sessions is a starting target, not a guarantee of a precise p95. At that count only about five observations lie above p95. Report a confidence interval and session variation, and collect more or call the result inconclusive when uncertainty exceeds the decision threshold. A 240-FPS camera samples at about 4.17 ms; it cannot cleanly resolve a 1-ms difference without a more suitable method and uncertainty analysis. Do not label a mouse click metric as radio latency. Use stick-to-patch and stick-to-first-visible-control response as distinct endpoints.

### Ray tracing

First validate exact hit/miss/instance identities, offscreen casters, transforms, shader/AS barriers and GPU lifetime with a small CPU oracle. Then require actual direct-light integration, complete relevant geometry/material/alpha coverage, correct deformation and current scene generation. An old diagnostic snapshot must never be consumed as a current effect.

The RT report proposes **2.0 ms extra GPU p95 and 128 MiB incremental peak allocated GPU resources** as initial review ceilings on a named test GPU, including composite work and all AS, scratch, scene, history, denoise, in-flight duplication and SDK-private resources where observable. Missing allocation visibility is a stated limit, not zero usage; allocation is distinct from physical residency/process RAM. These are planning limits, not measurements or reserved headroom: a tighter whole-frame budget wins. If no headroom exists or relevant scene coverage fails, keep raster. Validate raw and reconstructed visibility, not only a smooth final image. The first visible fixture already applies visibility exactly once to direct sun; final-color darkening is not an acceptable intermediate result.

### Frame generation and combinations

FG remains separately gated. Real simulation/render cadence, generated OS-presented frames and physical presentation must have different counters. No synthetic-frame rate can satisfy the real-frame or input-response gate. Repeat motion/history and latency checks after combining FG, reconstruction or RT; transparent smoke/propeller inputs and multiple ownership generations are known current concerns.

## 7. Result format

The later [execution playbook](11-test-and-execution-playbook.md) maps this plan to existing script arguments, success markers, admission and comparison constraints. The [offline DRS examples](../../../research/performance/graphics_handoff/README.md) add 38 contract tests for the requested engineering handoff. They do not collect measurements, add an M0 executable, or substitute for application/native/physical tests. Their [separate receipt](evidence/handoff-validation.json) records the actual software checks and deliberately unperformed hardware rows.

Every proposed change ends with one of: **accepted for the named configuration**, **retained as experimental**, **retain baseline**, or **inconclusive because specified evidence is missing**. Attach exact identities, completed cases, failed/excluded runs, distributions, visual/latency judgments and remaining hardware rows. Keep existing owners' status separate from this dated audit. No new support claim follows merely because a settings item or native capability check exists.

Use the existing evidence folder and report format, with one compact decision block: objective; baseline/candidate; affected files; primary metric/threshold; protected cues; actual checks and exclusions; result/uncertainty; instrumentation engineering time; implementation time; verdict and smallest next action. This is a content requirement, not authorization to build a new schema framework. A milestone with no passing candidate can finish with a supported retain/defer decision; it cannot claim a performance improvement merely because measurement was repaired.

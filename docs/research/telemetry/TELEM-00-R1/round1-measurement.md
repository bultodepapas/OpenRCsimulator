# Telemetry follow-up: first-wave measurement investigations F01–F04

Research date: 2026-11-18. All search queries and this report are in English. Baseline: OpenRC Simulator repository HEAD `48ae3016a655acf7d062da3f32d72b9050c9e59a`; `docs/STACK.md` identifies Godot 4.8-beta2 as the pinned engine. The telemetry documents and offline model are proposals, not proof of shipped behavior. The external pages below were inspected on the research date; `main`, `master`, and Godot `stable` are moving references and are not equivalent to the pinned Godot beta. No external measurement tool was installed or run, no application compatibility was verified, and no runtime files were modified.

<a id="f01"></a>

## F01 — PresentMon: present calls are not display changes

**Falsifiable question.** Does a PresentMon measurement called FPS establish that OpenRC's `performance_window` draw-count rate equals the number of display changes, including dropped and generated frames?

**Exact English search queries.**

- `site:github.com/GameTechDev/PresentMon metrics MsBetweenPresents MsBetweenDisplayChange application frame presentation definitions`
- `Intel PresentMon console application MsBetweenPresents MsBetweenDisplayChange MsBetweenAppStart dropped frames generated displayed NA CSV official`

**Inspected primary evidence.** Intel's maintained PresentMon [`README-ConsoleApplication.md`](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md) and [`README-CaptureApplication.md`](https://github.com/GameTechDev/PresentMon/blob/main/README-CaptureApplication.md), `main` as viewed 2026-11-18; [releases](https://github.com/GameTechDev/PresentMon/releases) listed v2.6.0 as latest on that date, but the readmes inspected are not asserted to be that exact release. Local context: `docs/plans/telemetry/data-contract.md` and `verification.md` at the baseline revision.

**Finding.** The capture documentation distinguishes Presented FPS, the rate of `Present()` calls, from Displayed FPS, the rate of frame changes measurable at the display. The console documentation separately defines `MsBetweenPresents` and `MsBetweenDisplayChange`; `DisplayedTime` is `NA` for a frame not displayed. Frame type can distinguish application-rendered from driver/SDK-generated frames when the necessary instrumentation exists. The console's `--track_frame_type` option requires application and/or driver instrumentation; a blank field or absence of classification is not proof of no generated frames. `--exclude_dropped` intentionally removes nondisplayed rows. The documentation describes application/compositor presentation measurement, not an optical sensor's direct proof of panel photons.

**Inference and limits.** OpenRC's monotonic process-interval distribution and engine draw-count rate measure different points in the pipeline from present calls and display changes. Equality is a conditional empirical result, not a definition. PresentMon's Windows/ETW workflow is an optional external comparator, not proof of compatibility with OpenRC's specific renderer, driver, or presentation mode. Frame generation, dropped frames, multiple swap chains, different observation windows, missing metrics, and capture loss can invalidate a naive comparison.

**Specific proposed verification change.** Add an optional controlled Windows graphics run: record the exact PresentMon binary version, CSV schema/flags, app release/renderer, process and swap chain, presentation mode, observation boundaries, and availability; retain dropped rows and the frame-type status. Compare OpenRC's interval counts and draw-count ratio against separately reported present-call and display-change counts/rates over matched eligible intervals. For a case first shown to have one present per draw and no relevant loss, generated frames or drops, define a boundary-alignment tolerance in advance and investigate any excess; for other cases, explain differing counts instead of forcing equality. Collect trace-disabled versus trace-enabled runs separately to expose measurement overhead. Keep any detailed capture local under the project diagnostic policy; do not transmit its raw rows as product telemetry.

**Follow-up lead.** Establish which pinned-beta exported renderer/API combinations PresentMon can actually observe and whether a reliable marker can align its trace and `FrameSamples` capture without modifying product telemetry.

<a id="f02"></a>

## F02 — MangoHud: a concrete percentile-definition mismatch

**Falsifiable question.** Does a MangoHud value labeled `1%` necessarily use the same definition as the contract's example of the reciprocal of the mean of the slowest 1% of frame intervals?

**Exact English search queries.**

- `site:github.com/flightlessmango/MangoHud fps frametime logging sampling method log interval`
- `site:github.com/flightlessmango/MangoHud/blob/master/src/ "fpsmetrics" "frametime"`
- `site:github.com/flightlessmango/MangoHud "fpsMetrics" "sorted_values" 1000`

**Inspected primary evidence.** Maintainer's [MangoHud README](https://github.com/flightlessmango/MangoHud/blob/master/README.md), [`src/fps_metrics.h`](https://github.com/flightlessmango/MangoHud/blob/master/src/fps_metrics.h), [sample configuration](https://github.com/flightlessmango/MangoHud/blob/master/data/MangoHud.conf), and [release list](https://github.com/flightlessmango/MangoHud/releases), accessed 2026-11-18. The release page displayed v0.8.4, short revision `992103e`, as latest; code inspected was moving `master`, so the two are not assumed identical.

**Finding.** The inspected `fpsMetrics::calculate` sorts its retained frametimes descending. Its `AVG` branch computes `1000 / mean(frametimes)`; a decimal percentile branch selects one sorted frametime by index and returns `1000 / selected_frametime`. The `update` path caps its retained vector at 10,000 values; the separate constructor accepting a supplied vector must not be assumed to share that cap. The README separately documents a default 500 ms `fps_sampling_period`, configurable `log_interval` (default 0), local `mangoplot`, and public uploaded benchmark pages. It does not establish from those descriptions that every logging or online-summary path uses the inspected `fpsMetrics` algorithm.

**Inference and limits.** The inspected percentile is a reciprocal order statistic, not generally the reciprocal mean of the slowest 1%. For a synthetic 200-interval tape with 198 intervals of 10 ms, one of 25 ms and one of 100 ms, this code's `0.01` selection yields 40 FPS while the reciprocal of the mean of the two slowest is 16 FPS. This is a mathematical comparison of definitions, not an observed MangoHud run. A sampled HUD value, local log, online summary, and OpenRC's mergeable histogram may cover different intervals or have different selection rules. The repository describes Vulkan/OpenGL monitoring, but OpenRC compatibility and performance have not been established.

**Specific proposed verification change.** Add this 200-interval fixture to the measurement-definition tests and documentation: assert the two independently calculated statistics differ; v1's fixed bins remain percentile bounds, not an exact 1% low. For optional Linux investigation, first pin the tool revision and validate the actual log's columns, sampling schedule, recording boundaries and renderer capture path, then compare only like-defined process/present metrics on the same controlled workload. Record HUD/logging off/on overhead. Keep test data local; never use the documented automatic/public upload for player data. Do not copy MangoHud's GPU hardware inventory into base telemetry.

**Follow-up lead.** Inspect the exact pinned logger's data source and zero-interval semantics, then perform a disposable exported-build compatibility check on actual Vulkan and OpenGL paths before proposing it as a regression oracle.

<a id="f03"></a>

## F03 — Perfetto: alignment requires explicit clocks and loss accounting

**Falsifiable question.** Can a Perfetto trace's event timestamps be compared directly with Godot's `Time.get_ticks_usec()` solely because both are described as monotonic?

**Exact English search queries.**

- `site:perfetto.dev clock domains trace timestamps clock snapshot tracing overhead buffers clock sync`
- `Perfetto trace clock synchronization boottime monotonic clock snapshots official documentation overhead buffers lost events`

**Inspected primary evidence.** Perfetto's [clock synchronization guide](https://perfetto.dev/docs/concepts/clock-sync), [TracePacket/ClockSnapshot reference](https://perfetto.dev/docs/reference/trace-packet-proto), and [buffer/data-loss guide](https://perfetto.dev/docs/concepts/buffers), all accessed 2026-11-18; Godot's [Time documentation](https://docs.godotengine.org/en/stable/classes/class_time.html) `stable` as viewed on that date. Local `app/render/frame_samples.gd` implements a monotonic frame-sampling path and an approximate UTC cross-process anchor; it does not by itself qualify a Perfetto clock mapping.

**Finding.** Perfetto documents multiple clock domains, clock-snapshot-based mappings, and drift around suspend/resume. Clock conversion depends on available snapshots and a valid mapping path. The newer TracePacket reference describes a synthetic `BUILTIN_CLOCK_TRACE_FILE` default and format-dependent fallback/override behavior; the clock-sync conceptual page discusses `CLOCK_BOOTTIME` for its Linux/Android examples. Inspect the actual trace's configured/imported clock rather than assuming one universal default. Godot documents its monotonic tick count as microseconds since engine start, so it has a different stated origin from an arbitrary trace timeline. Perfetto describes low-overhead buffer writes as a design goal, not a numeric overhead guarantee; producer/shared/central/kernel buffer losses and ring-buffer overwrites are possible.

**Inference and limits.** Monotonicity alone proves neither common epoch nor exact cross-domain alignment. A fixed offset estimated before suspend may no longer be valid afterwards. Missing clocks or lost events make the affected comparison inconclusive; `data_loss` statistics alone do not substitute for checking whether the requested interval is present. No Godot-to-Perfetto integration or Linux/macOS/Windows support for this game has been verified.

**Specific proposed verification change.** Treat tracing as an optional, separately cost-qualified lab method. Identify each clock, units and actual trace primary clock; use a reproducible common marker or bounded pair of clock readings with a documented uncertainty, verify their mapping at both ends, and re-anchor across suspend/resume. Record trace start/end and required event coverage. Inspect `select * from stats where severity = 'data_loss' and value != 0`, plus relevant ftrace overrun and central-buffer overwrite/discard counters because not every coverage problem is expressed by that query. Reject or explicitly qualify comparisons with missing markers, unbounded mapping uncertainty, dropped events, or an overwritten analysis interval. Compare otherwise identical trace-on/off runs with the existing alternating-run performance campaign. Keep diagnostic traces local and separate from telemetry: they may contain process, thread and timing metadata outside the product contract.

**Follow-up lead.** On one Linux test machine, investigate whether the existing OpenRC test/capture tools can emit a bounded common marker without adding a persistent native dependency or altering production observations.

<a id="f04"></a>

## F04 — Godot maintainer issue: callback and visibility edge cases

**Falsifiable question.** Does a focus-loss/minimized/`window_can_draw` gate necessarily identify every episode when a window is not visibly presented, and does process `delta` exactly equal elapsed wall time through those transitions?

**Exact English search queries.**

- `site:github.com/godotengine/godot/issues fps window minimized focus frames drawn delta process`
- `Godot engine _process delta get_ticks_usec issue 91548 maintainer explanation delta smoothing engine documentation`
- `site:docs.godotengine.org/en/4.8/classes/class_displayserver.html "window_can_draw"`

**Inspected primary evidence.** Godot project member-authored [issue #109759](https://github.com/godotengine/godot/issues/109759), including the original Linux/X11 reproduction and later comments; [issue #91548](https://github.com/godotengine/godot/issues/91548), including member explanations; Godot official [`MainLoop`](https://docs.godotengine.org/en/stable/classes/class_mainloop.html), [`DisplayServer`](https://docs.godotengine.org/en/stable/classes/class_displayserver.html), [`Time`](https://docs.godotengine.org/en/stable/classes/class_time.html), and [`Engine`](https://docs.godotengine.org/en/stable/classes/class_engine.html) pages, accessed 2026-11-18. These stable docs and historical reports are not a qualification of OpenRC's pinned 4.8-beta2; `docs/STACK.md` and `app/render/frame_samples.gd` identify the beta and beta2 source commit `cafc17a192acf67903910a68aeb3c076c0907a4b` in the inspected repository.

**Finding.** In #109759 a Godot project member reports intermittent process/physics callback skips when switching focus, with a reproduction reported on Godot 4.2.1 through 4.4.1 and a then-master revision on Linux/X11; the issue is labeled confirmed and remains open in the inspected page. A later commenter separately reports roughly one-second stalls in a Godot 4.7.2 Linux/Wayland setup, then narrows their reproduction to a rendered GL window, vsync and full occlusion; they report minimization alone did not reproduce their case. This is a contributor's case report, not proof of a general rule or the same root cause as the original issue. In #91548, a Godot member explains that engine delta and a script's measurement are taken at different points; the issue was closed as expected. Current official documentation says `_process` runs before rendering, and its delta can be capped, fixed or smoothed; `get_ticks_usec` is monotonic. `window_can_draw` reports whether anything can be drawn, but its documentation does not promise a complete physical-visibility or occlusion detector. `get_frames_drawn` is distinct from process frames and documented as always zero in headless/disabled render-loop cases.

**Inference and limits.** The existing contract correctly primes/reset clocks at known focus, minimize, drawable and resume boundaries, but the sources do not establish that these signals cover every obscured interval on every compositor. The Wayland report alone does not establish that focus remains unchanged during occlusion, nor that beta2 reproduces it. An unfocused window may still be visible; excluding it is the current conservative eligibility policy, not evidence of invisibility. A long interval alone cannot reliably distinguish an occlusion stall from a real hitch.

**Specific proposed verification change.** Extend exported-build graphics qualification with a state matrix: visible focused, visible unfocused, minimized, fully occluded, restored and a deliberate foreground 100 ms hitch, for the pinned beta, relevant Linux X11/Wayland paths where available, and Windows/macOS. Include an always-on-top nonactivating occluder if the platform permits, so occlusion and focus can vary independently. At transitions record the actual callbacks/signals, `window_can_draw`, draw-count deltas, wall intervals and expected eligibility; verify re-priming avoids bridging gaps and that genuine foreground hitches are retained. If no reliable occlusion signal exists for a case, record unknown coverage and avoid claiming visible-only measurement; decide whether an explicit eligibility/coverage field or a narrower interpretation is needed before changing the schema. No universal threshold or unverified platform behavior is assumed.

**Follow-up lead.** Review the exact beta2 platform implementations and test whether reliable occlusion notifications exist for each supported window system; keep unsupported or ambiguous states explicit.

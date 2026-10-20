# Debugging tools investigation — 2026-10-19

Scope: project diagnostic commands, retained evidence and failure reporting under
PT1h-R2, with the performance-output repair owned by VQ-01b. This is dated research;
the [checked runner guide](../../tools/godot/README.md), [tool index](../TOOLS.md)
and [flight logging manual](../FLIGHT-LOGGING.md) own current usage.

## Findings and implemented response

| Local evidence / gap | Response | Verification boundary |
| --- | --- | --- |
| Godot runtime diagnostics can accompany exit zero; earlier shell checks were inconsistent. | PT1h-R1 introduced the shared bounded CLI wrapper and retained stream/context reports; this follow-up adds raw-log SHA-256. | Actual pinned Godot parse/runtime/resource failures and a hung SceneTree are exercised on Windows and Linux. Suppressed diagnostics cannot be recovered. |
| Per-command JSON had no collection view; missing reports could disappear from a naive glob-based summary. | PT1h-R2 validates every immediate run directory, recomputes log policy and exports standard JUnit with actionable hints. Empty, incomplete, changed and contradictory evidence cannot pass. | One case per invocation, never inferred assertion counts. No expected-suite inventory is claimed; CI retains the shell failure independently. |
| VQ-01b performance reruns deleted previous same-name report/manifest outputs before launching. | Refuse nonempty performance directories under the existing lock; retain prior complete and partial evidence. Reject nonfinite deadlines and linked output directories. | Disposable fixtures prove byte preservation and no subprocess launch; fixed sampling protocol unchanged. No fresh GPU benchmark is claimed. |
| Visual readability report used an unclosed output stream, exposed by regression warnings. | Close the UTF-8 report stream deterministically. | Existing visual inventory regression reads the resulting report. |
| Flight-log report output could fail after analysis had succeeded. | Prior FL-01 repair checks creation, write/flush status and returns a failed verdict. | Existing writer regressions include unavailable destination and Linux `/dev/full`. No recording or physics changes. |
| Input-report destination can replace an existing file. | Retain as an explicit limitation; use a unique destination. | Not repaired by this change. |

No profiler, debug overlay, plotting package or test framework is recreated. The
new offline adapter serves the repository-specific `openrc-godot-check v1` format
and uses Python's standard XML writer. It adds no code to the simulation/render
loop. Digests establish artifact consistency, not authenticity. Summarize only
after producers stop; external concurrent mutation is outside the evidence contract.

## Twenty sources reviewed

Accessed 2026-10-19. Official documentation and repository code/issues establish
API/behavior context. Reddit and forum reports provide investigation ideas, not
reproductions in OpenRC or proof of current Godot defects. Rolling `stable`/`main`
pages are not dependency pins; executable checks use this project's Godot 4.7.2.

| # | Source | Useful observation and local decision |
| --- | --- | --- |
| 1 | [Godot logging](https://docs.godotengine.org/en/stable/tutorials/scripting/logging.html) | Built-in logs rotate; stdout buffering and backtrace settings affect retained evidence. Capture emitted process streams, keep stderr enabled and avoid installing another always-on logger. |
| 2 | [Godot CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html) | Profiling has overhead and attribution limitations. Diagnose in a separate session; do not equate wrapper wall time with simulation cost. |
| 3 | [Godot profiler](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/the_profiler.html) | Inclusive/self time and full-frame measurements answer different questions; profiling is optional because it costs time. Prefer this existing free tool for script CPU attribution. |
| 4 | [Python 3.11 subprocess](https://docs.python.org/3.11/library/subprocess.html) | Pipe handling, buffered output and timeout cleanup need explicit design. Keep bounded streaming and process cleanup regressions rather than replacing them with unbounded capture. |
| 5 | [GitHub Actions Python testing](https://docs.github.com/en/actions/tutorials/build-and-test-code/python) | JUnit and retained artifacts fit existing CI workflows. Export standard XML and preserve evidence after failed test steps using the already pinned upload action. |
| 6 | [Godot #83042: export failure returned zero](https://github.com/godotengine/godot/issues/83042) | Historical 4.1.2 report, with a later fix, illustrates operation status versus emitted diagnostics. It motivates testing both; it is not evidence that all current exports have this bug. |
| 7 | [Godot #77508: headless import timing](https://github.com/godotengine/godot/issues/77508) | Historical deferred/threaded import completion issue. Keep explicit `--import`, process completion and deadlines; do not add a guessed frame-count delay. |
| 8 | [Godot #111048: headless cold import crash](https://github.com/godotengine/godot/issues/111048) | Version/project-specific crash reports motivate retaining process status separately from log classifications. No blanket cache deletion or project workaround is adopted. |
| 9 | [GUT command line](https://github.com/bitwes/Gut/blob/main/documentation/docs/Command-Line.md) | Free established testing framework with command-line exit/reporting options. Reuse JUnit conventions; replacing the project's existing suites is unnecessary for this gap. |
| 10 | [GdUnit4 command line](https://github.com/godot-gdunit-labs/gdUnit4/blob/master/documentation/doc/_advanced_testing/cmd.md) | Existing JUnit/HTML tooling and framework-specific exit codes reinforce explicit adapter contracts. Do not interpret an arbitrary nonzero code as a count of failed assertions. |
| 11 | [Godot Debug Menu](https://github.com/godot-extended-libraries/godot-debug-menu) | Free MIT debug overlay is available if interactive metrics later need one. No duplicate overlay or additional runtime dependency is justified by this audit. |
| 12 | [Reddit: profiling process time](https://www.reddit.com/r/godot/comments/125esa9/profiling_process_time/) | March 2023 report of frame drops with little script attribution. Use subsystem isolation and distinguish total frame time from `_process`; its reported UI cause is not assumed here. |
| 13 | [Reddit: low FPS with low script time](https://www.reddit.com/r/godot/comments/12ad488/when_profiling_performance_of_the_game_what_to_do/) | April 2023 discussion motivates checking native/rendering work before changing simulation code. No user benchmark is adopted as a threshold. |
| 14 | [Reddit: identify performance issue](https://www.reddit.com/r/godot/comments/1tdx57o/identify_performance_issue/) | May 2026 serial/plotting/logging discussion suggests runaway-output scenarios. Test floods and bound bytes; anecdotal print-rate claims do not set our limits. |
| 15 | [Reddit: using profiler output](https://www.reddit.com/r/godot/comments/1ng4gic/so_like_how_do_you_actually_use_the/) | September 2025 difficulty interpreting noisy output motivates clear next actions, scenario identity and explicit measurement boundaries. |
| 16 | [Forum: more precise debug tools](https://forum.godotengine.org/t/any-advanced-profiler-or-more-precise-debug-tools/81837) | Godot 4.3 physics/navigation attribution discussion suggests isolated probes before engine-level conclusions; it does not identify an OpenRC fault. |
| 17 | [Forum: profiler times not adding up](https://forum.godotengine.org/t/profiler-times-not-adding-up/120804) | August 2025 discussion highlights selected-frame/window confusion. Preserve measurement window and scenario metadata rather than summing incompatible aggregates. |
| 18 | [Forum: missing engine errors in log file](https://forum.godotengine.org/t/why-are-engine-error-messages-not-in-log-file/46768) | A Godot 4.2.1 Mono report motivates capturing console stderr as well as stdout. It does not prove that current GDScript logs omit those errors. |
| 19 | [Forum: terminal output present, editor output missing](https://forum.godotengine.org/t/godot-print-not-showing-in-output-panel-solved-winsock-reset/137107) | April 2026 Windows report supports a console fallback. Its system-network reset is not adopted or recommended from a single anecdote. |
| 20 | [Forum: Godot 4.5 Logger class](https://forum.godotengine.org/t/how-to-use-the-new-logger-class-in-godot-4-5/127006) | Buffered custom logger discussion raises flush/crash and threading concerns. Prefer built-in facilities; verify callback restrictions in official docs rather than copying a forum logger. |

## Choose the diagnostic that answers the question

| Symptom | Existing tool / next action |
| --- | --- |
| CI says success but Godot printed an error | Checked runner; inspect `reason`, child status and first source context, then the retained raw log. |
| A run vanished or an artifact looks inconsistent | Collection summary; retain invalid directories and rerun into a fresh collection. |
| Low FPS with little GDScript time | Godot CPU/visual profilers and existing render counters; compare the same window/scenario on native hardware. |
| Flight differs after a proposed physics change | Preserve `.orfl`, verify exact replay, compare one explicit candidate with the same tick/input tape per the flight logging manual. |
| Repeated performance capture | Fresh `--out`; preserve source/config identity and all three samples. Xvfb/llvmpipe is harness evidence, not GPU approval. |

## Regression evidence

Portable fixtures cover changed logs of identical size, relocated artifacts,
missing/malformed reports, contradictory success, warning/completion policies,
invalid metadata and limits, XML control characters, existing output preservation,
and aggregate-duration overflow. Actual-engine fixtures exercise zero-exit script
errors, parse/resource failures and a hung SceneTree. Visual fixtures cover
completed/partial output preservation, lock release, linked paths, nonfinite
deadlines, successful three-report publication and a failed new run without a
complete manifest.

Final parent-reviewed results on 2026-10-19:

| Check | Native Windows | WSL Linux |
| --- | --- | --- |
| `python -m unittest discover -s tools/godot -p 'test_*.py'` with `OPENRC_TEST_GODOT` | 38 passed | 37 passed, Windows junction test skipped |
| `python app/tests/test_visual_quality_cases.py` | 25 passed | 24 passed, Windows junction test skipped |
| `python3 app/tests/test_ci_partitions.py` | Linux-only harness | 7 passed |

Linux visual tests used the exact hashed dependencies from
`app/tests/requirements-visual.txt` in an isolated environment. Windows used Python
3.11.9; WSL used Python 3.12. The actual simulation plus deliberately failing
runtime script produced exactly two JUnit invocations: one pass, one failure,
preserving the zero child exit and GDScript source location. The workflow YAML
parsed, edited Python files parsed, documentation links resolved and
`git diff --check` passed. Delegated performance-tool changes were inspected and
the parent reran both platform suites after review fixes.

Commands and final local results are recorded in the checked runner guide. These
are focused software regressions, not a full CI run, a physical validation gate or
a hardware performance acceptance result. Deliberate failures use disposable
directories; no golden flights or production simulation state are changed.

## PT1h-R3 / VQ-01c: opt-in CPU/GPU and frame diagnosis

The follow-up adds `--frame-diagnostics` to the existing frame logger, a finite
sample-retention budget, and `research/performance/frame_diagnose.py`. Current
commands, limits, exit codes and interpretation live in the
[performance tool guide](../../research/performance/README.md#cpu-gpu-and-memory-diagnosis).
This extends the existing logger/reducer rather than replacing Godot's free
Profiler, Visual Profiler, monitors or GPU-profile CLI.

Official [viewport timing APIs](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu),
[performance monitors](https://docs.godotengine.org/en/stable/classes/class_performance.html)
and [debugger panel](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/debugger_panel.html)
were rechecked before implementation. Rendering CPU excludes scripts/physics;
root-viewport GPU timing is not whole-frame wall time, and zero/delayed values
need explicit interpretation. The macOS Compatibility exclusion is conservative,
based on the documented Visual Profiler limitation, rather than a locally tested
claim about that platform's low-level timing API.

The parent reviewed both delegated components, requested fixes to byte accounting
and unavailable/invalid-measurement handling, and ran the resulting tools against
synthetic failures and the production app. Retained native data, source hashes,
results and limitations are in [VQ-01c diagnostic evidence](visual-quality-implementation/VQ-01c/diagnostics/README.md).

## PT1h-R4: process RAM, I/O and storage

The next audit found that engine allocator/render counters did not cover process
resident memory, system pressure, volume capacity or project file sizes. The
checked runner now integrates optional pinned psutil sampling; a bounded metadata
audit groups Godot imports, assets and retained outputs. Neither changes runtime
or simulation state. Current commands and limits have one home in the
[resource tool guide](../../tools/godot/README.md#process-ram-io-and-storage-pt1h-r4).

Additional primary references checked for this implementation:

| Source | Applied finding |
| --- | --- |
| [psutil 7.2.2 release API](https://github.com/giampaolo/psutil/blob/release-7.2.2/docs/index.rst) | RSS/VMS platform differences, direct-process identity, unavailable I/O counters and oneshot caching. Reused the free library instead of implementing OS-specific bindings. |
| [Exact package release](https://pypi.org/project/psutil/7.2.2/) | Optional dependency pin, isolated installation and supported desktop platforms. |
| [Python scandir](https://docs.python.org/3.11/library/os.html#os.scandir) | Incremental metadata traversal with explicitly closed iterators and no file-content reads. |
| [Python disk_usage](https://docs.python.org/3.11/library/shutil.html#shutil.disk_usage) | Filesystem capacity is distinct from the logical sizes of paths included in a scan. |
| [Python performance clock](https://docs.python.org/3.11/library/time.html#time.perf_counter) | High-resolution elapsed/sampling clocks avoid the coarse Windows monotonic readings observed during review. |

Parent review corrected equal-size top-file ordering, Windows exclusion casing,
resource-output failure receipts and sampling clock precision. A stronger live
fixture exposed the Windows Python venv launcher: sampling its PID underestimated
the allocating child. The fixture now launches the base interpreter, checks a
32 MiB touched allocation and a flushed 1 MiB write, and retains explicit unknown
counter behavior. Production usage likewise requires the direct Godot executable.

Measured Windows thread counting was substantially more expensive than RAM/I/O
queries, so `--resource-threads` is opt-in. OS calls can still stall under pressure;
sampling cost is recorded, and the tool does not promise a hard polling deadline.
Denied counters, replaced/exited PIDs, reset counters, sample limits, full-disk
publication failures, scan limits, unreadable paths and linked paths have regression
coverage. Final verification and retained captures are in the existing
[diagnostic evidence](visual-quality-implementation/VQ-01c/diagnostics/README.md#pt1h-r4-resource-and-storage-evidence).

## Further debugging and logging candidates

Research follow-up, accessed 2026-10-19. These are adoption ideas, not implemented
features or verified compatibility claims. The project uses standard Godot 4.7.2
with GDScript and Compatibility rendering. Prefer an existing tool plus a small
OpenRC adapter; install one pinned dependency at a time after a disposable smoke
test. No additional package was installed during this research.

### Nineteen candidates and their project fit

| Candidate / primary source | Useful capability | OpenRC fit and limitation |
| --- | --- | --- |
| [Godot Logger and logging facilities](https://docs.godotengine.org/en/4.7/tutorials/scripting/logging.html) | Built-in file rotation and engine-message/error callbacks. | First choice for a bounded structured event adapter carrying session/frame/tick context. Callbacks can run on background threads, must not touch scene objects directly, and do not see early engine initialization; retain the external checked runner. |
| [GDLogger, formerly GoLogger](https://github.com/Burloe/GDLogger) | Categorized file logging, editor log viewer and instance IDs. | Current README says Godot 4.7+; older search results still describe GoLogger 4.3+. Candidate if category/file management is needed; benchmark writes and verify retention/failure behavior before adoption. |
| [LimboConsole](https://github.com/limbonaut/limbo_console) | Registered commands, completion, history and command scripts. | Preferred small command console for `diag.status`, `diag.mark` and `diag.capture`. Gate development commands and autoexec explicitly; do not allow commands to silently invalidate replay evidence. |
| [Panku Console](https://github.com/Ark2000/PankuConsole) | Native log viewing, expression watches, runtime property inspector and expression execution. | Alternative when live inspection matters more than a small command surface. Use one console; mutable expression/property tools belong in development sessions. |
| [Debug Draw 3D](https://github.com/DmitriySalnikov/godot_debug_draw_3d) | Existing 3D arrows, lines, shapes and text overlays. | Visualize lift/drag/thrust, CG, terrain normals and contact points. Feed detached simulation snapshots through the rendering boundary. Check native binaries on each export target; its README documents editor telemetry and an opt-out setting. |
| [Godot Debug Menu](https://github.com/godot-extended-libraries/godot-debug-menu) | Existing in-game performance/hardware overlay. | A lightweight metrics-display candidate if a console is unnecessary. Avoid duplicating the existing frame collector or presenting engine allocation counters as process RAM. |
| [RenderDoc](https://github.com/baldurk/renderdoc) | Frame capture and graphics-state inspection, including OpenGL and Vulkan. | First graphics investigation for vegetation, transparency, shadows and unexpected passes. Validate capture with this Compatibility renderer/driver; a captured frame is not a clean timing benchmark. |
| [apitrace](https://github.com/apitrace/apitrace) | Graphics API recording, replay and state inspection. | OpenGL fallback for renderer/driver problems that survive project-level isolation. Match executable architecture, bound trace duration and expect large files. |
| [Perfetto](https://perfetto.dev/docs/getting-started/other-formats) | Mature timeline viewer and SQL analysis; accepts Chrome trace JSON counters/events. | Best next offline adapter: combine measured frame data, resource counters and event markers. Establish session identity and clock alignment; never invent function spans from aggregate frame metrics. |
| [Tracy](https://github.com/wolfpld/tracy) | Instrumented CPU/GPU zones, allocations and lock analysis. | Reserve for native evaluator/engine investigations. The [older Godot module](https://github.com/AndreaCatania/godot_tracy) shows legacy build commands; it is not evidence of a drop-in Godot 4.7 integration. |
| [Process Monitor](https://learn.microsoft.com/en-us/sysinternals/downloads/procmon) | Windows filesystem, registry and process/thread events with filters and stacks. | Find the exact failing asset path, access denial, repeated import read or unexpected log write. Filter to the direct engine and record a short reproduction; file probes returning not-found are not automatically defects. |
| [VMMap](https://learn.microsoft.com/en-us/sysinternals/downloads/vmmap) | Windows committed-memory categories and working-set breakdown, with export. | Investigate which memory class grows across repeated scene/workshop transitions. RSS trends alone cannot distinguish retained allocations, mappings, caches and shared pages. |
| [Process Explorer](https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer) | Windows process hierarchy, handles and loaded DLLs/mapped files. | Check launcher versus engine identity, unexpected child processes, open-file ownership and native dependency loading. Complements the bounded sampler rather than replacing evidence capture. |
| [WPR/WPA](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/) | ETW recording and Windows performance analysis. | Investigate scheduling, CPU/disk activity and OS-side stalls around a hitch. Use an appropriate recording profile; resolve native stacks with matching symbols. |
| [heaptrack](https://github.com/KDE/heaptrack) | Linux heap allocation profiling with stack information. | Deeper allocation attribution after a repeatable growth case exists. Native allocation stacks are not automatically GDScript object ownership; symbolized engine builds may be needed. |
| [GUT](https://github.com/bitwes/Gut) | Established Godot unit-testing framework. | Consider for isolated new fixtures requiring its features. Preserve current physics/replay gates and existing tests; a framework migration alone does not improve diagnostic accuracy. |
| [gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) | Assertions, mocking and scene testing within Godot. | Candidate for console interactions and UI/scene lifecycle tests. Select a release matching the engine and use one test framework per new integration. |
| [Sentry Godot SDK](https://github.com/getsentry/sentry-godot/blob/main/README.md) | Crash/error reporting, release context, attachments and player feedback. | Later playtest/release option when remote reports are wanted. Native extension and service deployment add scope; local capture remains the default. Its current README requires Godot 4.5+ for SDK 1.x/2.x. |
| [Godot Advanced Logger](https://github.com/DYNMC-Motorsports/GodotAdvancedLogger) | Structured logs, channels, console/watch panels and external sinks. | Useful design reference, but it requires a .NET Godot project even though it exposes a GDScript facade. Do not change this project's runtime just to acquire logging. Performance claims need local measurement. |

### Recommended next experiments

1. **Correlated incident capture.** Adapt Godot's logging interface to retain a
   bounded event queue with severity, category, session ID, frame, simulation tick
   and source context. Package recent events with existing checked-run/resource
   reports, build/aircraft identity and an existing `.orfl` when available. Options:
   category filters, byte/event limits, duplicate suppression and explicit capture
   triggers. Test log floods, background callbacks, disk full and interrupted flush;
   report dropped records and incomplete captures.
2. **Offline Perfetto export.** Reuse the viewer for frame intervals, CPU/RAM/I/O
   counters and markers such as scene load, aircraft switch or recording start.
   Specify a shared clock origin or measured synchronization uncertainty. Validate
   a known synthetic hitch and missing/partial data; draw no unsupported causal
   conclusions from coincident events.
3. **Repeatable memory-growth scenario.** Exercise Home → flight → Home and
   Workshop open/close with a fixed scenario, settling period and cycle count.
   Record resource/orphan counts and process memory at the same lifecycle point.
   Follow suspicious repeatable growth with VMMap or heaptrack; distinguish cache
   warm-up from continued growth. A deliberate retained-node fixture must fail.
4. **Visual physics probes with Debug Draw 3D.** Toggle individual force/contact
   layers, vector scales and draw budgets. Convert float64 state only at the render
   boundary. Confirm known axes/signs and prove diagnostics do not alter the fixed
   input-tape result. The library supplies drawing; OpenRC supplies the semantics.
5. **Small LimboConsole integration.** Expose read-only status, markers and capture
   commands, with help and completion. Test keyboard focus, hidden-console cost,
   malformed arguments and release-export behavior. Keep arbitrary simulation
   mutation outside accepted replay/qualification sessions.

Start with incident capture and the offline timeline: both build on evidence the
project already collects. Use ProcMon/VMMap/WPR on demand before adding more runtime
instrumentation. The current intermittent ObjectDB warning is a useful first case
for the lifecycle scenario, not an established leak cause.

### Implemented follow-up: PT1h-R5

The first delivered slice is a bounded local incident ZIP and offline Perfetto
adapter for existing frame/resource captures. Shared capture IDs and paired clock
anchors support approximate correlation; incomplete prefixes remain explicit.
This does not yet add a runtime event queue, scene markers, console or lifecycle
probe. See the [usage guide](../../tools/godot/README.md#incident-bundles-and-perfetto-timelines-pt1h-r5)
and [reviewed tests/evidence](visual-quality-implementation/VQ-01c/diagnostics/README.md#pt1h-r5-incident-packaging-and-timeline-correlation).

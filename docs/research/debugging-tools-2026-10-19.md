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

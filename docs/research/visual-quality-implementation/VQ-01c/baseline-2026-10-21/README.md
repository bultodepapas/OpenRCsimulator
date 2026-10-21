# VQ-01c / DT-10a — current baseline triage

2026-10-21. **First triage slice delivered; baseline qualification remains open.**
The first implemented repair restores the real Home/Fly loading probe after Home's
deferred launch changed its timing contract. Current measurements prioritize launch
reliability and first-load construction. They do not justify adding rendering cost.

## Identity and limits

Runtime baseline: `22396c6edc86bc5e8ec8d2ef3040207602924290`, initially clean.
The [initial manifest](source-manifest.json.gz) hashes 3,630 tracked inputs and both
engine executables. [Final verification](source-verification.json) found only the
loading probe, its tests and its tool documentation changed within that scope;
application and aircraft source bytes are unchanged. Shared-tree commit `188a1831`
subsequently incorporated the probe and initial tests. The final tests also correct
fixture typing/ownership and check the actual timeout frame count.

Godot 4.7.2 `ed1daf0bf`, Windows 11 Pro 26100, Ryzen 9 5900X, RTX 3090,
NVIDIA OpenGL 617.42 / Windows driver 32.0.16.1742, Balanced power plan.
Native output: 1280×720, Compatibility, 4× MSAA, VSync, explicit 60 FPS cap,
Dummy audio, screen 0, window position 80,80. [Active display inventory](displays.json)
shows a 1920×1080 virtual desktop; CIM's additional physical 4K/120 Hz monitor does
not establish which physical display presented these frames. No display-latency,
minimum-hardware, audio-device or exported-package acceptance is claimed.

Native runs were serialized, without screenshot readback or concurrent benchmark
work. The workstation was not reserved from user/background activity. The import
process in [host.json](host.json) belongs to setup, before timed runs. Imported,
OS and shader caches were not cleared or characterized. These are source/editor
observations, not a release benchmark or comparison against older campaigns.

## Implemented collection repair and tests

The old probe emitted Fly and immediately required `app.flight`. Current
`Home._on_fly()` first disables Fly, then awaits a process frame before emitting
`fly_requested`. The retained [original failure](loading/loading-01-flumq395/report.json)
therefore identifies a measurement assumption, not a product launch failure.

The [probe](../../../../../research/performance/loading_probe.gd) now waits at most
four process frames for the real handoff, validates startup/session readiness,
rejects cancellation/rejection/timeout, and refreshes Home after each return.
`fly_sync_usec` remains signal-dispatch time; the new `fly_ready_usec` includes the
deferred handoff. First-draw time also includes the subsequent post-draw wait.
Normal callbacks, focus safety and isolated-settings cleanup remain in force.
An external process timeout bounds construction that blocks a frame.

Verification:

- [88 Python tests pass](checks/python-suite.log).
- [Frame collector: 86 checks, zero failures](checks/frame-collector-vfx24qjh/engine.log).
- [Loading regression checks pass](checks/loading-regressions-fixed.log): deferred
  success, retryable rejection, cancellation, bounded pending timeout, startup error
  and unflyable session; existing success/failure/audio retention/file guards pass.
- Five native processes each complete two real Home/Fly/Home cycles. All successful
  reports release observed mixer playback and remove their isolated settings.
- The initial new test fixture failed to parse; its [failed log](checks/loading-regressions.log)
  is retained. The corrected fixture owns/frees its mock nodes and types its results.

No production file changed, so no full app suite, golden-flight update, new physical
validation or package acceptance is claimed. Reproduction commands and metric
semantics belong to the [tool guide](../../../../../research/performance/README.md#homefly-loading-and-lake-geometry).

## Loading observations

[Raw loading runs](loading/), [rows and distributions](loading-summary.json).
Six fresh processes attempted with the repaired probe; five completed, providing
five first-Fly and five warm-repeat observations. Each uses the Stik, real Home
defaults and an isolated airborne start. Fresh-process does not mean cold caches.

| Interval | Minimum / median / maximum, seconds | Interpretation |
| --- | --- | --- |
| Home first draw, engine elapsed | 8.760 / 9.111 / 9.878 | Already exceeds the 5 s process-cold target; excludes parent launch overhead and does not prove Home usability |
| Home first draw from app-source load | 4.883 / 5.192 / 5.611 | Narrower attribution interval, not an alternative launch gate |
| First Fly validated scene ready | 3.042 / 3.388 / 3.761 | Most first-Fly delay precedes first draw; component cause remains unmeasured |
| First Fly first draw | 3.167 / 3.824 / 4.018 | All five exceed 2 s; three are paused at first draw |
| Warm Fly first draw | 1.637 / 1.869 / 2.096 | All five unpaused; one exceeds 2 s |

Home returns take 0.951–1.638 s, with 777 Home nodes and zero orphan nodes in every
successful cycle. Two cycles per process cannot establish bounded long-term memory
or the 50-cycle/30-minute soak. A valid timing report is not interactive acceptance.

`loading-fixed-02` exited with code **3221226525** before a timing report, with no
engine diagnostic explaining it. Its [checked record](loading/loading-fixed-02-_8xx7kx6/report.json),
log and leftover test-owned settings sidecar are retained. The four later attempts
completed. Cause remains unknown; neither the repaired probe nor production startup
is cleared of that incident by successful retries.

## Native frames and attribution limits

[Individual reductions](native-summary.json) use the existing reducer without
changing its thresholds. Standard runs use 10 s warmup + 60 s sample, default Stik
live-input route. They are not an owner-flown circuit or a full aircraft matrix.

| Standard run | p95 / p99 / maximum, ms | Simulation/wall | Result |
| --- | --- | --- | --- |
| `stik-live-01` | 17.461 / 18.054 / 280.469 | 0.996669 | Numeric percentile/ratio gates pass; isolated long stall remains unattributed |
| `stik-live-02` | 29.889 / 30.624 / 31.507 | 0 | Paused at tick zero; ineligible |
| `stik-live-03` | 18.427 / 19.167 / 20.785 | 1.000009 | Active; p95 misses 18 ms target |

The three-run baseline does not qualify. Paused timing is never averaged into active
flight, and the passing first run does not establish a repeatable performance margin.

A separate 60 s diagnostic flight stayed active: p95/p99 21.984/31.148 ms,
simulation/wall 0.999987. [Frame diagnosis](native/stik-diagnostic-01-diagnosis.json)
and [monitor distributions](diagnostic-shape.json) retain the attribution data.
Viewport rendering CPU p95 was 1.403 ms and GPU p95 3.970 ms; these exclude other
engine/script work and may be delayed. They do not prove the cause of whole-frame
tails or establish GPU headroom. Observer polling p95 was 25 µs, not the total
instrumentation overhead. No matched observer on/off comparison was performed.
The separate process sampler observed 1,205 MiB peak RSS across 81 samples, not VRAM
or a memory-leak result. Instrumented timing is not pooled with standard runs.

Two 15 s diagnostics remain separate: a single OS foreground request did not
prevent a tick-zero pause; a read-only SceneTree startup observer stayed active but
deferred app creation. Neither establishes the pause cause or a production fix.
Tree-wind qualification and aircraft-data warnings are retained in the logs.

## Ranked work and next pass/fail decision

| Order / owner | Evidence and expected return | Small next action and acceptance |
| --- | --- | --- |
| 1 — VQ-01c / DT / UI | Pause/startup reliability prevents trustworthy comparison; highest dependency value | Retain focus events, pause reason/holds, menu state and tick at the standard startup route. Reproduce both normal foreground startup and intentional focus loss. Any repair must keep intentional loss safely paused, preserve explicit resume, and pass at least three uninterrupted 60 s controls. Bound attribution to half an engineering day before reviewing the unresolved cause. |
| 2 — DT-11a / UI/session | Home and all five first-Fly draws miss loading targets; broad benefit on every launch | Split existing construction into load/import, validation, model/world and first-draw intervals without changing order. Profile one foreground control; choose only its dominant repeatable phase. Bound attribution to half a day, then implement one candidate or retain baseline. |
| 3 — DT-10a / H / VQ | Active p95 varies across the threshold; one 280 ms interval is unexplained | On a named physical display, separate VSync/cap and uncapped diagnostic trials, then attribute script/physics/render waits. A change needs three alternating pairs, existing correctness gates, and >5% affected complete-workload gain or removal of a reproduced named hitch. |
| 4 — VQ-01d / CAM, then selected Compatibility work | Current visual/pilot acceptance is still missing; no measured added-cost allowance | Refresh the frozen-snapshot motion reference, verify actual backgrounds and collect owner orientation/circuit evidence before appearance tuning. Existing clips remain historical; none were refreshed in this triage slice. |

The first selected repair was the loading collector and is implemented above.
The **next product optimization target is first-load construction**, conditional on
phase attribution; no specific cache, asset rewrite or renderer migration is selected
without that evidence. Prefer existing free tools and retained resources.

For a loading candidate, run five alternating fresh-process controls/candidates with
one warm repeat each; retain all failures. Require unchanged validation/readiness,
retry/cancel behavior, source/output parity where promised, normal focus safety and
clean bounded teardown. Report both improvement and remaining Home/Fly target misses;
do not silently replace interactive readiness with first draw. Recheck native pacing
and run the existing lifecycle checks when ownership/caches change.

## Retained evidence

[Manifest](evidence-manifest.json) maps every original artifact to its retained path,
raw SHA-256 and stored SHA-256. Large JSON uses deterministic gzip (`mtime=0`);
decompression reproduces the original bytes. Logs and checked-run records preserve
commands, timestamps, failures and exit codes. Absolute scratch paths in those records
identify the original run; retained files are mapped by the manifest. The one-off
scripts preserve the executed setup/reduction, not an additional production tool.

This closes the bounded triage/collector-repair slice only. VQ-01c/d, current-package,
physical-display, aircraft/weather coverage and owner-pilot gates remain open.

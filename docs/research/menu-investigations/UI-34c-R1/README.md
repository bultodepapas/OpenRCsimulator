# UI-34c-R1 — Home/Fly loading audit

2026-10-24. **Audit and plan only; no loading optimization implemented.** Owner: UI-34c with DT-11a construction/performance coordination. [Execution plan](../../../MENU-REDESIGN-PLAN.md#12-home-to-flight-loading-ui-34c-and-dt-11a). The current flow acknowledges Fly with a changed button caption, then blocks the main thread for seconds. It needs both persistent loading feedback and less synchronous construction.

## Method and limits

Native Windows, Ryzen 9 5900X, RTX 3090 / NVIDIA 617.42, Godot 4.7.2 `ed1daf0bf`, Compatibility, actual **1920×1080** window/viewport. Initial HEAD was `9038a6494ad3088f818f9f2f7521f3f5c9e7119e`; it advanced to `914ba5674f2f0088946cfd44be9d6aba180cf10b` during evidence collection. Another session changed UI/audio source during the audit; import metadata also refreshed. These are exploratory current-tree observations, not a frozen candidate comparison or release qualification. [Samples and inspected-source hashes](samples.json) preserve that distinction; hashes taken after execution cannot prove every byte loaded at startup.

The debug bridge used an isolated profile, native audio, verbose resource logging, VSync enabled, no configured FPS cap and MSAA enum 2 (4×). Default Stik setup: Club field, runway, evening, 1.5 m/s wind from 090°, full fuel, keyboard controls. Readiness/preview checks preceded measured Fly actions. `press text=Fly` activates the real button; the Spanish rendered caption is VOLAR while the bridge exposes its source label. Frame history was reset before each measured transition. Screenshots were taken outside timed windows and remain ignored.

The first launch failed before Home because new menu `.ogg` resources were not imported. It was stopped, then the canonical bridge `launch --import` refreshed imports. That failed launch is excluded from loading samples. The successful bridge session logged no engine/script errors and stopped with no crash or leaked objects. Raw session: `tmp/debug-bridge/20261024-171235-47870/`; failed session: `tmp/debug-bridge/20261024-171211-47870/`.

A separate fresh process ran the existing [loading probe](../../../../research/performance/README.md#homefly-loading-and-lake-geometry) through the checked runner, three cycles, native 1080p, Dummy audio, no verbose bridge. Although the command requested `--max-fps 60`, the actual report records `max_fps: 0` after application preferences; VSync remained enabled. Do not combine its first-draw timings with debug frame durations as identical metrics. OS/import/driver caches were uncontrolled; fresh process does not mean cold disk/GPU cache.

## Observations

### Debug-bridge blocking frames

These are the largest observed frame intervals around each action, **not complete click-to-interactive latency**.

| Case | Samples | Maximum frame interval |
| --- | ---: | ---: |
| First Stik Fly, Club, runway/evening | 1 | **4669.11 ms** |
| Repeated Stik Fly in the same process | 5 | 1699.72, 1734.42, 1823.25, 1806.67, 1728.68 ms; median **1734.42 ms** |
| Stik return to Home | 5 | 937.29, 946.93, 945.17, 931.55, 1454.47 ms; median **945.17 ms** |
| First jet Fly after its preview, already-warm application | 1 | **2911.89 ms** |
| Stik / Green paradise / airborne / evening, already-warm application | 1 | **925.47 ms** |

The first Stik load frame reports +4382 objects, +826 nodes and +122.94 MiB engine static memory. Subsequent frames are 301.5 and 71.4 ms with the 12-tick catch-up limit. These are transient construction deltas, not retained RAM/VRAM or a diagnosed leak. The jet also has a long post-load catch-up tail; steady-flight qualification is outside this audit. A different landscape and start change multiple inputs, so the Green result does not isolate scenery cost.

### Existing loading probe: validation and first draw

[Raw result](loading-probe.json), [checked receipt](checked-report.json), [engine log](loading-engine.log).

| Cycle | Validated scene ready | First post-draw | Paused / tick at first draw | Return Home first draw |
| --- | ---: | ---: | --- | ---: |
| First | 4.437 s | **4.638 s** | **Yes / 1** | 1.141 s |
| Warm 1 | 1.890 s | **2.042 s** | No / 12 | 1.231 s |
| Warm 2 | 2.170 s | **2.334 s** | No / 12 | 1.156 s |

The first paused draw is not interactive readiness; its pause cause was not isolated. The two active warm draws also exceed the existing 2 s Fly target. `fly_sync_usec` is only 90–114 µs because it measures signal dispatch before the deferred handoff; reporting that field as launch time would conceal the delay. Initial Home takes 8.043 s from app-resource load through first draw (14.631 s engine elapsed), which keeps initial loading open too.

The probe is complete, all three Home returns report zero orphan nodes and 869 nodes, and bounded teardown releases its tracked audio. The checked runner reports zero errors/warnings. This is not a 20-cycle memory check, DT-12 soak, real-device input-latency measurement or full test suite.

## Source diagnosis

Graph discovery was used first; stored line ranges were stale, so the following symbols were verified in current source. Line references describe this snapshot.

| Finding | Source / consequence |
| --- | --- |
| Feedback is a button caption, not a persistent loading screen. | `Home._on_fly`, `app/ui/home.gd:1587`: disable Fly, set `Preparing flight…`, await one `process_frame`, emit. The audit did not capture the exact acknowledgement draw; that yield is not a measured post-draw guarantee. |
| Resource load and scene activation are synchronous. | `AppRoot.start_flight`, `app/app_root.gd:593`; `_create_flight:810` calls `load`/`instantiate`. After construction of the candidate object, Home is detached and `add_child(flight)` at about 715 runs `Main._ready` synchronously. A Home-owned indicator cannot cover the remaining work. |
| Flight reconstructs substantial state already represented on Home. | `Main._ready`, `app/main.gd:328`, loads/validates field at 435, builds another aircraft/world through `_build_world:2509`, and runs `FlightSession.setup` at 608. `FlightSession._load_selected_aircraft`, `_prepare_aircraft` and `set_field` read/validate data, solve the initial state and prepare surfaces. These checks must remain correct. |
| Existing caches are not a prepared flight. | HomeScene keeps three preview model/shadow entries; the AppRoot-owned `HomePreviewResources` broker keeps at most two scene references and one active request. Home exit cancels its consumer and clears held references. Flight builds an independent model. Runway/fuel capability caches already exist in `aircraft_catalog.gd`; they are not missing work. |
| Construction continues to dominate warm interaction visibly, but finer attribution is incomplete. | Five warm Fly stalls remain above 1.69 s. `World.build` already exposes `field_build_ms`, a useful phase seam. Add spans around resource load, world/scenery/model/session and disposal before choosing more caches. |

[First Stik timeline](stik-first-timeline.txt) contains an 804 ms gap after `main.tscn` load completion and a 629 ms gap after a smoke shader load log; [warm timeline](stik-warm-timeline.txt) retains 419/295/248 ms gaps around construction. These are time **between log messages**, not exclusive timings of the named preceding resource. They do not prove that smoke, shaders or audio caused those gaps. The jet timeline's printed hitch header disagrees with its log-frame range; use the retained frame JSON for its maximum, not that header. Phase instrumentation is still needed.

## Planning implications

1. Deliver persistent loading feedback first, with a measured first draw and preserved rollback. Explicitly label this first slice as feedback only while synchronous stalls remain.
2. Divide the measured construction path into bounded stages so the overlay can draw and input can be handled. Retain the existing synchronous driver for deterministic direct routes, sharing the same preparation logic.
3. Prefer reuse of immutable field/geometry/resource preparation over retained live worlds or sessions. Measure a cache's full-flow benefit, memory and content invalidation. New aircraft-validation caching is not automatically high value.
4. Trial preparation during idle Home time only after presentation/foreground preview work. Account for immediate Fly, abandoned selection, cancellation and total process-to-flight time; no fleet preload.

The [2026-10-21 whole-scene warmup experiment](../../visual-quality-implementation/VQ-01c/loading/scene-warmup-2026-10-21/README.md) already rejected preloading `main.tscn` before Home: Home slowed about 26%, combined gain missed its gate, and candidates added shutdown warnings. [Release attribution](../../visual-quality-implementation/VQ-01c/loading/package-attribution-2026-10-21/README.md) also shows source/editor and exported first-load costs differ. Neither historical 720p campaign is today's 1080p qualification; both prevent an unsupported blanket-preload recommendation.

The [canonical plan](../../../MENU-REDESIGN-PLAN.md#12-home-to-flight-loading-ui-34c-and-dt-11a) owns the proposed phases, cache policy, cancellation/identity rules, renderer constraints and acceptance matrix. No physics, generated geometry, dependencies or golden recordings were changed for this audit. No new UI artwork or screenshots are committed.

## Reproduction

Use [openrc-debug](../../../../.agents/skills/openrc-debug/SKILL.md) and the [debug bridge reference](../../../../tools/debug/README.md), setting `OPENRC_GODOT` to the pinned native executable on Windows. Launch with `--verbose --resolution 1920x1080` and an isolated profile; use `--import` when assets need it. Select the session's explicit `OPENRC_DEBUG_BRIDGE` port.

At Home, `frames reset=true`, `press text=Fly`, `wait frames=6`, `frames --json`, `state` and `timeline --hitch`. For warm repeats, measure `home` separately, reset history, then Fly again. Visit jet via the Aircraft catalog and let the preview settle before timing Fly. Select Green/Stik and confirm airborne start before its sample. Inspect `logs --summary` and `stop`.

Separately run the loading probe's documented checked/native invocation at **1920×1080**, output to a new ignored directory, `--cycles=3`. Retain actual renderer/settings and pause state from the result. The checked receipt contains the exact command used here. Raw local output is under `tmp/fly-audit-20261024/`; compact results are retained beside this report. Acceptance A/B work must first freeze a stable source/import snapshot and expand sample counts as the plan specifies.

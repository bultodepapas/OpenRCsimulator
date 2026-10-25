# UI-34c / DT-11a — preparation while Home is visible

2026-10-25. Internet research and source inspection at `ede383b569798b28e50fe8ec184d097826948ef6`, using Godot 4.7 documentation. No runtime change or new engine experiment in this follow-up. The [execution plan](../../../MENU-REDESIGN-PLAN.md#selected-preparation-while-home-is-visible) owns the proposed implementation; the [R5 report](README.md) owns existing measurements.

## What is worth advancing

The latest consecutive frozen candidate's first Turbo flight took 7.353 s. Its recorded phases include:

| Phase | Elapsed time | Candidate technique |
| --- | ---: | --- |
| Preparing flight scene | 1.668 s | Start the existing dedicated scene job after Home draws; adopt it on Fly. |
| Checking flight | 4.001 s | Prepare the exact numeric request for the selected aircraft; reuse its pending/completed job. |
| Preparing contacts | 281 ms | Later: advance immutable collision preparation or split the miss into resumable chunks. |
| Building field scenery | 235 ms | Split main-thread construction; a deferred call alone cannot divide it. |
| Preparing sound / instruments | 173 / 107 ms | Profile their internal construction before choosing resource retention or incremental building. |

Source: [pair 5 candidate](pair-5-candidate.json), first cycle. Scene and flight-check spans total about 5.669 s, 77% of that one run's readiness interval. This identifies work to investigate; it does **not** predict a 77% speedup, a two-second launch, or enough overlap from five seconds in Home. These are elapsed phase spans, not isolated CPU costs. Menu contention, startup dependencies, selected setup, discarded work and final validation remain relevant.

## Primary-source findings

| Technique | What the documented contract actually supports |
| --- | --- |
| Background resource loading | Poll completion across frames. Retrieving an unfinished request blocks the calling thread. Loading a PackedScene and instantiating it are separate operations. [Background loading](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html). |
| Strong-reference cache | A resource leaves the engine cache when all references disappear. A retained bounded owner is needed to preserve the benefit across Home/flight. [Resource](https://docs.godotengine.org/en/4.7/classes/class_resource.html). |
| `preload()` | Script dependencies are loaded when the script loads. Adding a large static preload to Home can delay the first menu draw instead of using time after it. [Loading versus preloading](https://docs.godotengine.org/en/4.7/tutorials/best_practices/logic_preferences.html#loading-vs-preloading). |
| Low-priority speculative worker | `Thread.start()` accepts low priority, but the pinned Windows backend registers only thread naming, leaving the priority hook null. LOW therefore gives no native scheduling protection here. The API also has no setter to promote an already-running worker. [Thread API](https://docs.godotengine.org/en/4.7/classes/class_thread.html), [Windows backend](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/windows/thread_windows.cpp#L48), [optional platform hook](https://github.com/godotengine/godot/blob/4.7.2-stable/core/os/thread.h), [hook invocation](https://github.com/godotengine/godot/blob/4.7.2-stable/core/os/thread.cpp). |
| Limited concurrency | Resource loading and private CPU work can run outside main, but active scene-tree operations and shared-resource mutation require care. Uploading/reading GPU data can synchronize with rendering. More loading subthreads can slow main. [Thread-safe APIs](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html), [ResourceLoader](https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html#class-resourceloader-method-load-threaded-request). |
| Incremental main-thread work | `call_deferred()` runs at idle time and can drain more deferred calls in that same cycle. It does not establish a new frame or divide an expensive builder. Explicit checkpoints and smaller work units are needed. [Object.call_deferred](https://docs.godotengine.org/en/4.7/classes/class_object.html#class-object-method-call-deferred). |
| Compatibility shader warmup | Draw the actual required meshes/effects inside the camera frustum for a frame, possibly behind opaque 2D UI. Merely loading, hiding or placing them off-camera does not establish this warmup. [Stutter guidance](https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html#stutter). |
| Renderer-specific shortcuts | Hidden-instance pipeline preparation and Shader Baker guidance target Forward+/Mobile; Shader Baker has no effect in Compatibility. [Pipeline compilation](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html). A hidden SubViewport may not update with its default visibility-dependent mode. [SubViewport](https://docs.godotengine.org/en/4.7/classes/class_subviewport.html). |

The R5 dedicated loader remains the mechanism for the pinned scene-load issue; this research does not re-adopt nested `load_threaded_request` for Main or change the engine. Nor does it move the whole scene tree to a worker. OpenRC already draws the held candidate behind its loading surface. Another identical warmup frame adds no new coverage; only a measured, previously absent material/effect variant justifies an additional visual experiment.

## Current code prevents a naive prefetch

1. **The scene job starts inside Fly.** `app_root.gd:start_flight` creates `ui/flight_scene_load.gd` only after the selected resource finishes and the preview broker drains. Moving the trigger requires an owner that survives Home and an adoption path, not a second loader. The two-resource broker must account for the retained scene and selected model without another unbounded cache.
2. **An idle broker is only a momentary observation.** A model selection can arrive during speculative scene loading. A resource coordinator must govern both admission paths. Foreground intent stops new speculation, but an already-running engine load cannot be preempted; a queued preview may wait for drainage. Measure this selection latency explicitly.
3. **Busy trim currently duplicates work.** `sim/launch_trim_cache.gd:begin_staged_solve` calls `_solve()` synchronously whenever a reservation exists, without matching its key. `sim/flight_session.gd:setup_staged` owns its Thread locally. A Home prefetch therefore cannot be adopted and can cause a second solve on main.
4. **Preview readiness is not the full setup signal.** The initial preview may already be ready before the listener connects. `ui/home.gd:_cycle_battery_mode` and `_cycle_fuel_fill` change selected values without notifying AppRoot through a setup-change signal. Start explicitly after the initial Home draw and observe every relevant setup change; only following preview events is insufficient.
5. **The first trim is not yet the selected-weather/fuel trim.** Main calls session setup before weather and fuel setup. `_selected_airborne_trim_request` initially uses the default atmosphere/full fuel; later `_refit_selected_trim` may solve again. Preparing only the final selected conditions does not match the first request. Reordering setup is a separate behavioral change, requiring validation-order and rejection parity as well as numerical equality.

The exact initial request already contains reference speed, throttle target, speed bound, full normalized model, gravity, throws, density, engine charge ratio and maximum alpha. Its existing byte key and private round-trip arguments should remain authoritative. Battery model/content belongs in that identity; paint or lighting need not invalidate numeric work when the resulting arguments are identical. Aircraft provenance, model construction, contacts and session validation must still run on Fly.

## Candidate to test, with explicit limits

After the first Home draw, a settled selected preview and a short stable-selection interval, start one speculative task. Trial a 350 ms interval against 0/750 ms; these are experimental values, not user-visible mandatory delays. First prepare the common fixed-wing scene with the existing loader; then prepare one selected numeric request. Subsequent inspection confirmed Home already preloads FlightSession; exposing the numeric entry point does not add that dependency graph to first-Home parsing. The common flight scene still loads after Home draws. No active simulation is created during menu preparation.

Fly accepts immediately and presents its existing loading feedback. It adopts the same scene job and, after reconstructing the exact numeric key, the same trim job. A completed raw result may wait privately until final candidate validation. A pending match must never fall into synchronous recomputation. A speculative miss, busy different key, unsafe/oversized arguments or thread-start failure should skip/defer speculation rather than run a solve in Home. Preserve the separate technical synchronous entry contract.

Use a generation and one latest pending selection. Invalidating a consumer does not terminate the running calculation: an obsolete job drains while main continues processing; it cannot publish stale results. Rapid A→B→A changes must be tested because useful work can otherwise be discarded and restarted. Cooperatively interrupting a numeric solver is a later independent design, not a property of Thread. Keep the existing two-resource, two-result/1 MiB-key and one-collision-entry/8 MiB bounds; measure in-flight arguments/results and RSS/VRAM separately from those bounds.

First preserve the existing initial trim request and order. Then investigate eliminating the default-weather/full-fuel solve followed by the selected-setup refit. A persistent worker, offline collision preparation and a persistent disk cache are later candidates only if their own costs dominate; none is required to establish the initial Home-to-Fly handoff.

## Evidence needed before enabling it

Extend the existing loading probe with a declared stable-selection dwell and preparation diagnostics; use the debug bridge for actual selection changes and cancellation. Compare baseline, scene-only, numeric-adoption-only where independently loadable, and combined preparation. Measure immediate Fly, Fly during the debounce, and 2/5/10 s dwell at 1080p with identical dwell in both roles. Keep total process-to-Home, Home-to-active-flight including dwell, post-click delay and menu responsiveness separate.

Record job starts, exact-key hits, pending adoptions, duplicate solves, obsolete work time, blocked preview time, maximum frames and counts above 33/50/100 ms, and memory. Require zero duplicate solves for a pending matching key, no Home-first-draw regression, responsive selection, exact raw-result parity and safe Cancel/Quit. Cover battery/fuel/weather changes, rapid selection, an imported heavy model, Stik and Turbo, then the existing route/lifecycle matrix. Full and exported-package gates remain in the execution plan. No new speedup is claimed by this research.

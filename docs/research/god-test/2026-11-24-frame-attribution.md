# Where the three-aircraft tour lost frames

On 24 November 2026 we reanalysed the six completed Windows and ANGEL recordings from 21 November. The strongest shared lead is the opening of Controls. On the M1, slow circuit frames also cluster at half-second intervals. On PRIMIS, a separate experiment localized a multi-second freeze to the first rendered flight with cold shader caches. Each finding points to a different experiment in the [investigation plan](../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Loading and menu transitions

All six recordings used native physics at 240 Hz. Windows used an RTX 3090 with Forward+/Vulkan at 1920×1080. ANGEL used Mobile/Metal on a mirrored external 1920×1080 display. These are application callback intervals from one pass per aircraft. Each loading column distinguishes the whole request from its single worst interval. [Original tour and hardware](2026-11-21-stutter-map.md)

| Host | Aircraft | Fly request to draw marker | Worst loading interval | Worst opening Settings | Worst opening Controls |
| --- | --- | ---: | ---: | ---: | ---: |
| Windows | Stik | 4.21 s | 1,101 ms | 297 ms | 757 ms |
| Windows | jet | 6.12 s | 1,077 ms | 281 ms | 643 ms |
| Windows | Corsair | 6.75 s | 1,036 ms | 314 ms | 670 ms |
| M1 | Stik | 5.78 s | 2,668 ms | 318 ms | 415 ms |
| M1 | jet | 5.40 s | 2,651 ms | 295 ms | 458 ms |
| M1 | Corsair | 8.02 s | 2,849 ms | 285 ms | 457 ms |

- **Opening menus.** In each of the 12 openings, over 98% of the worst interval fell between the open request and the driver's confirmation that the screen owned input. The scene node count rose by exactly 2,112 for Controls and 800 for Settings in every case. The paused tick stayed fixed from request to confirmation. The driver checks the screen after a process-frame boundary. The interval includes signal dispatch, constructing and attaching the UI, layout and waiting for the next frame. Current code builds the Controls sections synchronously in its constructor, then configures devices and profiles before pushing the screen. Timing these operations can distinguish their costs. [Controls builder](../../../app/ui/controller_setup.gd) · [Settings builder](../../../app/ui/settings_screen.gd) · [Screen entry points](../../../app/app_root.gd)
- **First selection on Windows.** Of the Stik's 2,798.440 ms interval, **2,517.503 ms elapsed before the selection phase began**. Only 280.937 ms overlapped that phase, which lasted 342.906 ms in total. All six selection peaks crossed the start boundary and ended with the weather dialog on the screen stack. The frozen driver checks the catalog and loads its benchmark pilot before starting selection. The time spent in those individual operations is unknown. The 2.80 s pause was real, but using it as the cost of changing aircraft would send work to the wrong code path. [Driver and phase events](../../../app/debug/godtest_driver.gd)
- **Flight loading.** Every peak in the loading column was entirely between Fly and the draw marker. All six matching bridge rows ended on the loading screen at tick zero. Windows recorded pipeline-count increases of 93, 93 and 99 in those rows. The Mac rows recorded a net gain of 23 resources each, with no reported pipeline delta. These endpoint observations give the loading probe a target. A counter cannot time a compiler call or identify which load stage occupied the interval. [Existing loading probe](../../../research/performance/loading_probe.gd)
- **Other transitions.** Lighting selection and Apply peaked at 320–639 ms across the six recordings. Returning Home peaked at 370–763 ms. The recorded phases include dialog close or world replacement. Separate those boundaries before assigning the full pause to saving preferences or rebuilding the field. [Phase map](2026-11-21-stutter-map.md#marked-freezes-by-phase)

## M1 circuit cadence

The Stik, jet and Corsair averaged 97, 79 and 74 FPS on the M1, yet had 12, 65 and 92 circuit intervals above 33.333 ms. Home ran at a sustained 42–51 FPS on arrival. We tested the visible half-second spacing in flight separately for each aircraft. The first half determined the timing window. The second half supplied the counts below. Each window covered 100 ms out of every 500 ms.

| Aircraft | Slow frames in first half | Predicted centre within each 500 ms, relative to circuit start | Second-half slow frames inside window | All second-half frames inside window |
| --- | ---: | ---: | ---: | ---: |
| Stik | 6 | 10.8 ms | 6 / 6 | 539 / 3,220 |
| Jet | 36 | 130.4 ms | 29 / 29 | 1,069 / 6,269 |
| Corsair | 59 | 327.3 ms | 33 / 33 | 849 / 5,106 |

All **68 of 68** slow frames in the second halves landed in the predicted windows, which contained only **16.8%** of all frame endpoints there. This is an exploratory result within the recorded tours. A periodic cause can coexist with sustained GPU load. The recorded 94–96% mean GPU utilization does not tell us which operation made those frames late.

The watcher polled every 500 ms with incident snapshots disabled. Its saved incidents cover 105 of the 169 slow frames with matching engine frames and at least 90% time overlap. **Zero of those 105** carry the bridge's same-row diagnostic-query flag. The flag has limited timing coverage. Test the observer by changing its period, then repeat the workload with independent timing and the bridge absent. The controller service also refreshes on a 0.5 s timer. The tour selected keyboard input, and that path already skips the storage lease when no default is pending. Time the actual refresh before changing it. [Watcher](../../../tools/debug/frame_watch.py) · [Controller service](../../../app/input/controller_service.gd)

## Earlier controlled experiments

| Trigger | What the intervention established | What remains open |
| --- | --- | --- |
| Opening seconds of Club Field flight on PRIMIS, UHD 630, Compatibility/OpenGL | About 1.5 s after reveal, near tick 391, the longest opening interval was 6,710 ms with cold Mesa and Godot shader caches, 1,250 ms with Mesa reused, and 276 ms with both reused. The stock cold draw itself spanned 6,691 ms. Disabling the cloud-map readback left a 6,755 ms interval. | One run per cache condition, uncontrolled filesystem cache. Identify the render pass or driver call on the restored Club Field. The earlier crash warmup experiment saved 65–73 ms during warmup and left the opening hitch. [Cache and warmup experiments](2026-11-22-intel-green-club-screen.md) |
| Sustained low FPS on PRIMIS | Fixed Forward+/Medium produced 8.7–13.6 circuit FPS. The cap of 12 physics steps per frame means a 10 FPS loop can execute only 120 of the required 240 steps per second. The Automatic/Compatibility 75% bundle delivered 40.2–50.6 FPS and real-time circuits. Controlled visual changes measured terrain shading in Home (9.21 ms median) and trees in flight (3.60 ms p95). | The Stik Automatic case had incomplete first-Home coverage. The masks changed the visuals. Club Field was restored in `2014cafbb` after those measurements. Remeasure subcomponents and player options on that scenery and preserve aircraft visibility. [Linux tour](2026-11-22-linux-uhd630-comparison.md) · [Ablations](2026-11-22-intel-green-club-screen.md) |
| Linux test-host flight loading froze for 36–45 s | Switching the device-less host from ALSA null to Dummy removed a spinning audio thread and brought total flight loading to roughly 5–11 s. | This accounts for the lab audio failure. Remaining draw/loading peaks have separate evidence. [Host diagnosis](2026-11-22-linux-uhd630-comparison.md#causes-and-fixes) |
| Earlier Windows 2 Hz stall and first-impact freezes | The controller storage lease cost about 7 ms on an NVMe profile and 26 ms on USB flash. The repaired path raised the 1% low at 4K/120 Hz from 60–62 to 91–109 FPS in the matched setting. A separate fresh-profile Compatibility crash still produced 47–766 ms depending on settings and contact. | Retest physical controller timing separately. For first impact, match the contact, effect set, renderer and cache. Two 1.0–1.7 s Windows freezes outside process work also lack attribution. [Controller experiment](../visual-quality-implementation/VQ-07/graphics-ladder-2026-11-19/README.md) · [Crash comparison](../visual-quality-implementation/VQ-07/ladder-analysis-2026-11-19/README.md) |

## Reproduce the offline measurements

Windows used `D:/OpenRC-perf/tour-20261121-r1` for Stik and jet and `tour-20261121-r1-retry` for the completed Corsair. ANGEL used `~/OpenRC-m1-work/godtour-20261121/tour-r4`. The Mac source receipt names the local commit `3dd5a79ce` (“final transition/focus candidate”). The original map names its upstream candidate. The [measurement ledger](2026-11-24-frame-attribution.json) identifies both frozen source digests, raw file hashes, frame indices and exact microseconds. No game was relaunched for this analysis.

1. Run the repository's `validate_stream(case_dir, frametimes)` on each receipt. All six streams passed hash, sequence, counts and completion checks, totalling **156,888 intervals**. Reconstruct each interval as `[end_usec - wall_usec, end_usec]`. Select the longest interval assigned to each phase by the collector. Intersect it with event times on the engine monotonic clock. For the selection boundary use the phase record's `start_usec`. For menus use `menu_open_requested` and `menu_opened`. The corresponding bridge rows have the same process-frame number and overlap more than 98% of the selected interval. [Stream validator](../../../tools/godtest/analysis.py)
2. For each M1 circuit, split at the midpoint of the recorded phase wall time. For first-half endpoints of intervals longer than 33,333 µs, take the circular mean of `(end_usec - phase_start_usec) modulo 500,000`. Count second-half endpoints within ±50,000 µs of that centre, wrapping at the period. Keep slow and all-frame denominators separately. For query coverage deduplicate incident rows by process-frame number, match the time interval, then check flag 16. The ledger's incident-list digest hashes the concatenated lowercase SHA-256 strings of the incident files in directory-name order.

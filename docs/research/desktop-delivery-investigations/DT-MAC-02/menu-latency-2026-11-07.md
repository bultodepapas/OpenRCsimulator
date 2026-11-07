# Native M1 menu latency — 2026-11-07

The reproducible long stalls come from **synchronous Home-world and aircraft
construction on the main thread**. Deferred dispatch and threaded resource
loading do not defer that subsequent construction. This is a diagnosis, not
an implemented performance repair.

## Identity and method

- Source `997e212784dbf873a7b054ddbbc68e7905495adf`, from the frozen
  [ANGEL setup](../../../tools/macos-m1.md#angel-windows-access-and-native-setup).
- MacBookAir10,1, Apple M1, 8 GiB, native ARM64, macOS 27.0 / 26A5425a, AC power;
  Godot `4.8.beta2.official.cafc17a19`, Mobile/Metal, Standard profile, 4× MSAA.
- Requested/reported viewport and window: 1920×1080, 3D scale 1.0. Native drawable
  pixels were not independently established.
- Q90A main display reports 1920×1080 at **30 Hz**, mirroring the internal Color
  LCD, which reports 60 Hz. Stock VSync enabled; frame limit unlimited.
- Native workspace `/Users/g/OpenRC-m1-work/angel-setup-20261107`; baseline
  `tmp/research/app`, diagnostic copy `tmp/menu-diagnosis-20261107/diagnostic-project/app`.
- Evidence on DEVIL: `D:\OpenRCsimulator-evidence\angel-menu-diagnosis-20261107`.
  It retains repro command files, JSON observations, four engine/JSONL sessions,
  native samples, checked imports, screenshots and diagnostic source patches/hashes.
  Bulky evidence and images stay outside Git.

The isolated project's private name protects player preferences. Its disabled
multi-bounce setting is ignored by Mobile. Diagnostic copies of `home_scene.gd`
and `field.gd` retain elapsed phase timings; production application files were
not edited. Both diagnostic imports passed with zero errors. Quantitative warm
repetitions ran without the script profiler or native sampler. Temporary VSync
and visibility interventions were restored; all owned Godot processes stopped.

Navigated real rendered Home Flight/Aircraft/Practice/RC garage, six Settings
categories, Controls, Help, the Corsair paint picker and Workshop's Appearance,
Lighting, Smoke, Mechanical audio, Flight setup and Compare pages. No Workshop
build or edit was saved.

## Reproduction and exact blocking path

| Case | Measured observation |
| --- | --- |
| Six real Time of day presses, no script profiler | Maximum frames 1,612.65 / 1,562.21 / 1,511.42 / 1,232.99 / 1,533.26 / 1,519.71 ms; five had no pipeline-count increase |
| First live Corsair preview, diagnostic V2 | 897.7 ms frame; synchronous `show_aircraft` took 862.345 ms; 16 new pipeline compilations in that frame |
| Return to retained Corsair | `show_aircraft` 2.179 ms; no hitch event in the 45-frame window, maximum frame 54.9 ms |
| Return to retained Stik | `show_aircraft` 0.659 ms |
| First rendered Home, profiled/verbose session | 9,594 ms frame with 377 new pipeline compilations; first-use construction/compilation context, not a shader-only timing |

Ordinary combined navigation also had smaller 115–274 ms outliers. The paint
picker's first open had a 107 ms frame. These measurements do not imply equal
cost for every menu. The first Corsair experiment sampled too early; the later
capture explicitly waits for `not app.home_scene.preview_pending`, including
the deferred completion frame.

The real time button reaches [`set_time_of_day`](../../../../app/app_root.gd),
then `_queue_home_scene_rebuild` → `_flush_home_scene_rebuild` →
`_rebuild_home_scene`. The deferred callback still synchronously removes HomeScene
and calls `HomeScene.new`, rebuilding its world and selected aircraft. The old
scene is queued for deletion afterward.

Three warm same-preset Evening calls bracketed by `Time.get_ticks_usec` took
**1,464.589 / 1,500.387 / 1,478.288 ms** around that complete method. Their Home
constructors took 1,450.516 / 1,488.604 / 1,467.127 ms:

| Constructor phase | Warm Evening range |
| --- | ---: |
| Validation and field/config loading | 25.1–33.1 ms |
| `World.build` | 721.7–728.1 ms |
| Its landscape/field stage | 667.9–675.9 ms |
| Aircraft preview construction | 689.1–738.4 ms |
| Shadow-object and camera creation | Below 0.2 ms combined |

Existing labelled field-builder steps locate repeated work at **218–220 ms near
grass**, **209–211 ms scenery**, 66–69 ms lake, 66 ms projected shadows, 45–50 ms
ground and 50–51 ms flight cues. Most of that geometry is unchanged by the hour
selection, but the synchronous builder executes it again.

Two finer V2 Stik samples at Night split its approximately 736–737 ms preview:

| Preview phase | Sample 1 | Sample 2 |
| --- | ---: | ---: |
| `AirplaneBuilder.build` | 399.693 ms | 392.338 ms |
| Pose/bounds/shadow-geometry collection group | 63.538 ms | 70.987 ms |
| `_update_aircraft_lights` | 272.089 ms | 273.182 ms |
| Other measured preview stages combined | Below 1 ms | Below 1 ms |

The first live Corsair preview differs: builder 183.210 ms, geometry group
230.829 ms, night-light update 447.115 ms. Its resource-ready callback performs
this work synchronously on the live tree.

These are **inclusive elapsed times**, not CPU-cycle counters. The builder
includes dependency/manifest validation, mesh construction, derived bindings,
aircraft data and customization. The night phase includes geometry fitting,
kit construction and emission setup. Their dominant inner functions were not
separately measured. Threaded GLB loading alone cannot remove procedural Stik
construction. The Home cache holds only three previews and their measurements;
replacing HomeScene discards that reuse. A cached-call time is a lower bound,
not proof that a safe lighting transition can cost the same.

## Continuous pacing, CPU and GPU

Warm stock Home and Settings process-loop intervals stayed near **33.34 ms /
30 FPS**, consistent with the main screen's reported 30 Hz and enabled VSync.
The VSync intervention below supports that pacing explanation. Actual display
presentation timestamps were not measured; this is separate from the second-long
construction stalls.

A separate unprofiled, fixed-view A–B–A–B–A temporarily disabled VSync:

| Phase | Median wall frame | Reported FPS |
| --- | ---: | ---: |
| Full field A1 | 18.48 ms | 54.1 |
| Field hidden B1 | 16.59 ms | 60.3 |
| Full field A2 | 18.43 ms | 54.2 |
| Field hidden B2 | 14.57 ms | 68.7 |
| Full field A3 | 18.43 ms | 54.3 |

This establishes a whole-field effect on actual frame duration, not an individual
shader cost. Root render-CPU observations were 1.35–1.42 ms with Field and
0.77–0.78 ms without it. Root GPU last readings changed from about 18.62 to 4.90 ms,
but their freshness/alignment is unverified: **these are not verified per-frame
GPU costs**. Xcode's `xctrace` is an unavailable stub on this CLT-only host; no
synchronized Metal per-pass attribution is claimed.

Warm script-profile samples showed about 1.5–1.6 ms of script work. They sample
one frame per approximately one-second print and miss transient callbacks; they
cannot exclude the measured rebuild. Native samples are retained, but unnamed
addresses in the stripped official engine do not identify Godot functions. A
final one-second OS sample recorded 31% of one CPU, 1.17 GB RSS, 1.57 GB system
available memory and 271 MB used swap; it does not explain earlier outliers or
establish absence of pressure. All four retained JSONL sessions have zero error
events. The physics catch-up label means counted engine physics callbacks reached
the per-frame maximum. The label does not establish an active flight solver or
the temporal cause of the delay; the measured synchronous construction does.

## Limits and corrective boundary

One earlier profiled walk had an 8.3-second outlier without a recorded preset;
its exact cause remains unattributed. A fresh diagnostic process measured first
Moonrise/Night environment preparation at 42.6/43.2 ms, versus 13.1/2.4 ms cached.
The lunar search is not assigned to that outlier or the repeated 1.5-second pause.

Repair Home's lighting/preview lifecycle: retain safe geometry/model measurements
or stage existing builders with measured chunk bounds, latest intent and rollback.
Preserve independent flight validation. Flight's in-place lighting API alone
does not cover Home's stars, moon and flowing sky. Existing Home rebuild,
time-of-day, preview-request and bounded-cache tests define required behavior;
cross-world reuse needs new fresh-build appearance and ownership comparisons.

Upstream references checked November 7: [background loading](https://docs.godotengine.org/en/latest/tutorials/io/background_loading.html)
and [pipeline compilation](https://docs.godotengine.org/en/4.6/tutorials/performance/pipeline_compilations.html).
This diagnoses this pinned source/engine and host; package, synchronized GPU,
sustained-flight and physical qualification remain separate.

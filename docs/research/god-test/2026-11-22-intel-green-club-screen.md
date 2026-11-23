# PRIMIS UHD 630 · Green Paradise and Club Field

VQ-07h-A2-R1 L0/L1 · 22 November 2026 · Source `bfbad672617ef2bc8b3065ac0e81bbd10fd2a5ab`. [Execution plan](../../plans/low-end-gpu-performance.md)

## Home

The first Green sample completed at 58.2 process FPS. During the switch to Club in that process, the PRIMIS watchdog stopped the container after host MemAvailable stayed below 1536 MiB for 15 s. The task recovered the retained Green sample after restarting the test container and ran the next sequence in separate processes and profiles. All three processes exited cleanly before the exclusive slot was released.

| Run order | Landscape | Process FPS | p50 ms | p95 ms | p99 ms | Frames over 50 ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | Green Paradise | 59.4 | 16.88 | 17.50 | 17.91 | 0 |
| 2 | Club Field | 25.3 | 39.66 | 40.97 | 42.13 | 0 |
| 3 | Green Paradise | 59.6 | 16.83 | 17.38 | 17.71 | 0 |

Each window covered roughly 18 s after a 12 s warmup. The Ugly Stik preview, camera transform and 40° FOV matched. Home used the same daylight, Classic sky and default weather profile in all three runs. The engine was stock Godot 4.8 beta 2, with Intel UHD Graphics 630, Mesa 25.0.7, Compatibility/OpenGL through Xwayland on a private Weston output, Dummy audio, Low detail, main MSAA off, VSync off and an uncapped process loop. The bridge verified 1920×1080 window and viewport coordinates and a fixed Native bilinear scalar of 0.75 before and after each window. The Home budget was held through the bridge during each measurement and resumed afterwards. The nominal internal size is 1440×810. Driver drawable and actual internal extents were unavailable on this route.

Club took about 22.8 ms more per process frame at the median. That result prioritizes an isolation test inside Club. The landscape switch changes geometry and materials together. These short windows provide process timing on a virtual output. They leave presentation, whole-session memory behavior and the product acceptance pairs open.

## Club ground material

On the same rough-ground mesh in a separate Club process, the bridge set `meadow_count` and `club_infield_edge_count` to zero and disabled `club_field_detail` and `grass_photo_enabled`. It checked the applied parameters, fixed scale, Home route and camera in each window, then restored all four parameters. Each state had a 10 s warmup and roughly 18 s of process intervals.

| Ground state | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: |
| A · Stock | 39.88 | 40.56 | 41.34 |
| B · Decorative inputs disabled together | 36.71 | 37.63 | 69.95 |
| Restored A | 39.92 | 40.88 | 41.45 |

The group moved the median by about 3.2 ms, roughly 8% of Club's frame time and 14% of the Home landscape gap. In B eight intervals exceeded 50 ms, compared with zero in each A. The p99 rose by about 29 ms and recovered after restoration. A single window leaves the cause of the tail open. Test individual active inputs and retain the stock material until a repeatable candidate improves frame times without worsening the tail. The largest part of Club's cost remains unattributed.

## Native flight

Stock GOD TEST initially stopped at `Home weather dialog was not opened`. Changing from Club to Green admitted a staged Home rebuild, which left the loading surface on top when the driver opened Weather. The comparison ran after adding a readiness wait to the [driver](../../../app/debug/godtest_driver.gd). The final fix also waits for queued rebuilds and checks that the installed backdrop matches the requested landscape. Both landscapes then completed the separate airborne `recover` smoke with the final fix, native physics and clean exit.

The comparison used an airborne Ugly Stik with the same `right_circuit` pilot, calm wind, clear sky, daylight and seed 20261110. The observed backend was native ABI 2 at 240 Hz. The pinned engine and native binary matched the installed receipt and all 138 mirrored inputs. The private source copy used the binary receipt's CRLF form for 21 mirrored JSON inputs, with matching content. Each case used a fresh process and profile, the same virtual 1080p renderer and applied 75% bilinear scale at phase boundaries. Dynamic resolution, VSync and the frame cap were off.

| Circuit | Process FPS | p50 ms | p95 ms | p99 ms | Frames over 50 ms | Sim/wall in window | Full circuit wall s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Green 1 | 64.1 | 16.27 | 17.99 | 19.56 | 1 | 1.000 | 75.86 |
| Club | 43.9 | 22.37 | 30.95 | 33.21 | 9 | 0.972 | 84.08 |
| Green 2 | 63.8 | 16.28 | 17.76 | 19.19 | 0 | 1.000 | 75.08 |

The timing columns use complete intervals in the 60 s window following a 10 s warmup. The repository reducer verified stream hashes, clocks and phase assignments. The selected windows had no focus loss, pause, crash or interval without a drawn frame. Each full circuit advanced about 75.02 s of simulation. Club's full-circuit simulation/wall ratio was 0.892. Its largest interval was 6746 ms, ending 8.70 s into the circuit, followed by a 907 ms interval ending at 11.97 s. The Club flight load phase took 15.04 s compared with 8.16 and 4.13 s for Green. These timings locate the worst loss in early rendered flight, with slower recurring frames still visible in the warm window. The landscape comparison changes scene contents and field-relative flight conditions. It does not attribute the stalls to shader compilation, memory pressure or another specific cause.

### First and second Club entry in one process

Two additional Club circuits with the final driver used the same process and profile. Each advanced 34.50 s of simulation. The Mesa cache was shared with the prior campaign cases.

| Entry | Fly loading s | Flight p50 ms | p95 ms | p99 ms | Longest frame ms | Sim/wall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| First | 7.54 | 21.72 | 31.97 | 46.13 | 1116.75 | 0.962 |
| Second | 2.52 | 21.63 | 31.74 | 33.62 | 112.90 | 0.998 |

The second entry shortened loading by about 5 s and sharply reduced the largest flight interval, with similar median flight cost. Prioritize tracing first-use work in Club through Fly and the opening pilot-view draw. Isolate private cache state and record construction and rendering stages before choosing a change. Steady rendering still needs its own pass attribution.

Raw streams, engine logs, manifests, runtime identities, teardown receipts and the reducer are retained under `U:/OpenRC-intel-green-club-20261122`. The Python suite ran 217 tests with 7 skips. These exploratory runs used a virtual output. Product adoption still requires the affected-workload gate and visual checks.

## 23 November · Loading and first-use trace

The follow-up used `64b73545a` on PRIMIS with the same 1080p virtual output, 75% fixed scale, Compatibility/OpenGL and native flight. A private diagnostic copy recorded the wall interval between Godot's pre-draw and post-draw signals, existing load stages, and the duration of the crash-effect warmup. Godot and Mesa used campaign-owned caches. The watchdog stopped both attempts when host MemAvailable stayed below 1536 MiB for 15 s, at 1131 MiB and 1464 MiB. The frame streams are incomplete prefixes. The recovered data supports the observations below.

| Attempt | Retained observation |
| --- | --- |
| Both caches cold | The longest observed draw spanned 36.92 s during startup. Another draw spanned 9.62 s at Home. The watchdog stopped the case during Fly, before flight readiness. |
| Fresh Godot profile, Mesa cache reused from the interrupted attempt | Startup's longest observed draw spanned 6.35 s. Fly reached readiness in 17.91 s. Its longest checkpoint wait was 4.26 s at Preparing instruments. Preparing sound took 3.83 s of work elapsed, including 3.63 s in the crash-effect shader warmup's two forced draws. The first circuit retained a 6.81 s process interval near 1.35 s of simulation before the watchdog stopped the run. |

The startup draw was shorter in the partially warmed attempt. The restart and uncontrolled filesystem cache limit that comparison. The opening-flight hitch recurred at the same point after the partial warmup. No matching draw signal span survived for that flight interval. Two consecutive draws during Preparing sound took 2.34 s and 1.28 s. Their sum is close to the separately recorded 3.63 s warmup duration. [Mesa cache controls](https://docs.mesa3d.org/envvars.html#envvar-MESA_SHADER_CACHE_DIR) · [Godot Compatibility loading guidance](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html)

GOD TEST now retains the flight loading receipt with per-stage timestamps and checkpoint waits, so future trials can match it to the frame stream. The next hardware comparison needs enough memory headroom to complete the cold test. Attribute work inside the two crash-warmup draws before choosing a change and keep the first-crash path in the comparison. [Loading receipt format](../../../tools/godtest/PERFORMANCE_TOUR.md#metrics-evidence-and-verdicts)

The checked Linux loading regression passed 57 checks, including stage order and the sum through readiness, on the headless reference route. The Python tool suite passed 210 tests with 7 skipped. The interrupted streams, watchdog observations and private instrumentation are retained under `U:/OpenRC-intel-l3-20261123`.

## 23 November · Crash warmup viewport isolation

The PRIMIS container had 6 GiB of RAM and 512 MiB of swap for this follow-up. The host watchdog now allows 45 s of continuous node memory pressure below 1536 MiB and stops the container after 10 s below 768 MiB. The installed policy was checked for recovery, sustained pressure and critical pressure. The cold baseline completed even after the journal recorded 1285 MiB of node memory available. [Current PRIMIS operating guide](../../tools/primis-testlab.md#when-primis-is-offline-or-refuses-work)

On `0659c9a78`, a private candidate suppressed updates to the main viewport during the two forced crash warmup draws. It left the isolated 64×64 viewport eligible for both light variants and restored the main viewport's update mode afterward. The pinned engine still emits global frame signals and visits other eligible viewports during each forced draw. [Pinned draw dispatch](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/rendering_server_default.cpp) · [Pinned viewport traversal](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_viewport.cpp)

The loading probe used the real Home Fly button for a Club airborne Ugly Stik with keyboard selected. Each pair used fresh processes, a copy of the same initialized Godot shader cache and a shared campaign Mesa cache. It verified Compatibility/OpenGL on UHD 630, native physics, 1920×1080 viewport coordinates, 75% render scale and main MSAA off. It measured the opening 480 physics ticks after the first draw. The window was virtual and the shared node remained in normal use.

| Pair and order | Fly to first draw, A / B | Warmup, A / B | Longest opening interval, A / B |
| --- | ---: | ---: | ---: |
| 1 · A then B | 8530 / 8143 ms | 214 / 145 ms | 276 / 283 ms |
| 2 · B then A | 8229 / 8174 ms | 214 / 149 ms | 290 / 278 ms |
| 3 · A then B | 8229 / 8184 ms | 222 / 149 ms | 290 / 279 ms |

A is the stock warmup. B saves 65–73 ms inside the warmup, with a median paired gain of about 0.7% through the first flight draw. The opening peaks stayed near 280 ms.

The separate caches-cold runs reached the first flight draw in 23.40 s on stock and 22.32 s on the candidate. Warmup took 3.70 s and 3.44 s. The opening peaks were 6.89 s and 6.72 s, respectively. The candidate's draw signals bracketed 6.70 s of its 6.72 s peak, starting at physics tick 392. That locates the dominant wait between renderer signals in this run. A pass, shader compile or driver call still needs attribution. These two cases ran in sequence, with independent empty shader caches and uncontrolled filesystem and host cache state. Only the candidate recorded individual draw intervals.

Stock remains in use. The viewport isolation fell short of the L6 adoption gate and left the cold opening stall reproducible. Both cold runs and all six warm runs completed without a watchdog stop. Impact and package acceptance were outside the screen. Run reports, logs, the isolated candidate and trace are retained under `U:/OpenRC-intel-warmup-20261123`.

## 23 November · Scale, terrain and first-use matrix

The campaign followed the original protocol's I1, I3, I5 and I6 comparisons and the Club G3/G4 cases. It used a frozen copy of `main` at `c6656d4bd`, a private profile per process and the pinned Godot 4.8 beta 2 engine. PRIMIS ran the UHD 630 with Mesa 25.0.7, Compatibility/OpenGL through Xwayland on a private 1920×1080 Weston output, and Dummy audio. The tests observed window and viewport coordinates and the effective scale. Driver drawable and internal pixel extents remain unverified. [Original experiment protocol](2026-11-22-intel-gpu-experiments.md)

### Home · scale and single changes

All 17 windows used the same Club Home scene and Ugly Stik camera, Low detail, main MSAA off, Native bilinear, no frame cap and VSync off. The probe held the Home budget during measurements and restored it afterward. It warmed each state for 10 s and analyzed complete process intervals within 16 s. Each variant was bracketed by stock at 75%. The binding, scale, camera and visibility checks passed before and after every window. The product's Home adaptation and actual display presentation need separate observations.

| Variant | p50 ms | p95 ms | p99 ms | Intervals over 50 ms | p50 gain vs adjacent stock |
| --- | ---: | ---: | ---: | ---: | ---: |
| Stock controls, range | 40.35–40.50 | 41.03–41.49 | 41.47–42.95 | 0 each | — |
| 67% scale | 34.62 | 35.52 | 65.21 | 8 | 14.26% |
| Painted parcels off | 39.34 | 39.95 | 40.51 | 0 | 2.75% |
| Infield edge treatment off | 40.42 | 41.19 | 42.21 | 0 | 0.16% |
| Club turf detail off | 39.81 | 40.52 | 41.00 | 0 | 1.54% |
| Grass photo detail off | 39.50 | 40.31 | 41.03 | 0 | 2.24% |
| All four terrain changes | 37.30 | 38.06 | 38.65 | 0 | 7.69% |
| Perimeter hedge hidden | 40.40 | 41.14 | 41.72 | 0 | 0.02% |
| Aircraft shadow hidden | 40.02 | 40.70 | 41.69 | 0 | 0.88% |

The grouped terrain change reproduced the earlier median gain. This time its longest interval was 39.34 ms and the earlier p99 rise did not recur. Each single terrain switch saved less than 1.2 ms. The source terrain material used five painted parcels and eleven infield edges. The RC surface flag was unbound and defaults to false. The visible-only masks apply to this Home view. They leave other hedge batches, active-flight shadow refresh and independently bound terrain consumers open. [RC detail shader default](../../../app/render/rc_ground_detail.gdshaderinc)

The fixed 67% scale cut typical frame time by 5.76 ms relative to adjacent stock. Its 16 s window included eight intervals between 54.59 and 72.48 ms. The physical node sampler began during the following restored control, so the origin of this tail remains open.

### Home · painted parcels and photo detail together

G4 repeated the Home method in a fresh process at 75%. It tested all four combinations of the two strongest terrain terms from G3. Infield edges and Club turf detail retained stock bindings in every arm.

| Painted parcels / photo detail | p50 ms | p95 ms | p99 ms | Intervals over 50 ms |
| --- | ---: | ---: | ---: | ---: |
| Both on, four restored controls | 39.80–39.95 | 40.46–40.67 | 41.09–41.74 | 0 each |
| Off / on | 38.65 | 39.38 | 74.15 | 8 |
| Off / off | 37.71 | 38.37 | 38.81 | 0 |
| On / off | 38.94 | 39.64 | 40.27 | 0 |

Together the two switches lowered the median by about 2.15 ms (5.3–5.6% against the four stock controls). Their combined reduction was close to the sum of the single-arm reductions in this process. The parcels-only tail did not appear in the first G3 window with that same switch. The two-term result is a candidate for longer trials while preserving surface and landing cues.

### Native pilot flight · fixed scale

I1 ran three fresh processes with the same scripted right circuit, airborne Ugly Stik, pilot camera, daylight and calm weather. The field hash and 240 Hz native backend matched. Main MSAA, flight dynamic resolution, VSync and the frame cap were off. The cases shared a campaign Mesa cache that could accumulate entries across the sequence. Each row uses complete process intervals in the 60 s window after the first 10 s of the circuit. The frame stream validator checked all three receipts. Delivered rows were focused, drawable, unpaused and had at least one draw. All three completed about 75.02 simulated seconds and exited normally.

| Run order | Process FPS | p50 ms | p95 ms | p99 ms | Longest ms | Over 50 ms | Sim/wall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A1 · 75% | 43.75 | 21.91 | 31.11 | 33.38 | 917.53 | 11 | 0.963 |
| B · 67% | 47.27 | 21.62 | 27.80 | 29.56 | 44.06 | 0 | 1.000 |
| A2 · 75% restored | 42.50 | 24.51 | 30.89 | 32.52 | 51.41 | 2 | 1.000 |

The 67% arm improved p95 by 10.0% and p99 by 9.1% relative to the restored 75% control. Both held simulation pace. The first 75% run had a 917.53 ms interval in the measured window, so its tail and pace have a first-run confound. The large Home tail at 67% did not appear in this flight arm. This single A–B–A sequence establishes a flight lead for 67%. Repetition, distant-aircraft readability and physical presentation remain unqualified.

### First use · shader caches and cloud readback

I5 used the real Home Fly button for the same Club airborne Stik at 75% with the native backend. The opening trace paired frame signals and recorded accepted ticks. The four conditions ran in fresh processes with isolated Godot profiles. The two cold arms also had separate empty Mesa caches. A2 reused the Mesa cache from A1. A3 reused that Mesa cache and a copy of A1's Godot shader cache. Filesystem cache state was uncontrolled. There was one run per condition.

| Condition | First Home s | Fly to first draw s | Longest opening interval ms | Longest draw ms · tick | Mesa cache misses |
| --- | ---: | ---: | ---: | ---: | ---: |
| A1 · Both shader caches cold | 54.81 | 22.26 | 6709.91 | 6690.92 · 391 | 1493 |
| A2 · Mesa reused, Godot profile new | 21.08 | 9.31 | 1250.17 | 1231.77 · 392 | 25 |
| A3 · Both shader caches reused | 18.38 | 8.28 | 276.38 | 257.25 · 391 | 0 |
| B · Both cold, analytic cloud path | 55.30 | 21.88 | 6755.39 | 6736.13 · 394 | 1490 |

The cold stock trace independently located the stall between the engine's draw signals. The I6 sampler de-duplicated DRM client IDs on the verified i915 device. One roughly 3 s sample pair fully inside each cold peak accounted for about 0.23% render-engine time on the Godot client. The signal interval and cache results point toward first-use work on the render or driver thread. They leave the exact call and shader variant open.

The R13 measurements timed the cloud cache's `get_image()` and observed successful tile publication. Readback took 84–89 ms; publication finished 8–22 s before the first flight draw in the three stock cases. Setting `OPENRC_CLOUD_SHADOW_MAP=0` produced no readback or tiles and switched to the existing analytic path. The cold opening peak remained 6.76 s. This separates that hitch from the 2048² cloud readback under the tested conditions. [R13 proposal and scope](2026-11-22-intel-render-internals.md#r13-measure-the-cloud-caches-first-use-gpu-to-cpu-to-gpu-round-trip)

### Host counters and disposition

Within the sampled steady circuit windows, median render-engine time on the Godot i915 client was 93.7% at the first 75% run and 94.3% at 67%, with 17 sample pairs per run. The restored 75% circuit lacks host samples. Device-wide and completed per-frame GPU timings remain unmeasured. The host-memory samples reached 1387 MiB available and 5121 MiB charged to the 6144 MiB container, including cache. No swap usage, limit hits, OOM events or cgroup CPU throttling appeared in the retained samples. Every experiment finished with the watchdog active.

The Home and flight evidence supports keeping the 67% setting as a flight candidate and testing a focused parcel/photo material change for Home. Adoption requires three alternating pairs and visual checks. The leading opening-flight question is the first-use render or driver work around tick 391. The scoped masks and cloud readback instrumentation were restored. Raw intervals, cache logs, host counters, verification receipts and the private experiment scripts are retained under `U:/OpenRC-intel-matrix-20261123`.

## 23 November · Which Club features cost the most?

G3 changed one visual family at a time in an installed Club Field. The app inputs match `main` at `64920d74e`. PRIMIS used the pinned Godot 4.8 beta 2, Mesa 25.0.7, Compatibility/OpenGL on UHD 630, a 1920×1080 virtual output, Low detail, Native bilinear at 75%, and main MSAA, VSync and frame cap off. The Home preview used stock daytime Classic sky. The private probe preserved the field instance and camera inside each comparison. It held the Home render budget during the comparisons and restored it before exit.

### Default Home view

Each variant was bracketed by restored stock. Windows used an 8 s settle and 12 s of complete process intervals. Runtime readback verified the camera, viewport settings and active masks at both boundaries.

| Visual change | Variant p50 ms | Variant p99 ms | p50 gain vs adjacent stock |
| --- | ---: | ---: | ---: |
| Replace rough-field shader with a flat lit material on the same mesh | 31.22 | 32.66 | **9.21 ms** |
| Hide field treeline and imported tree batches | 36.44 | 72.27 | **3.78 ms** |
| Zero the solar disc uniform | 37.55 | 38.74 | 2.85 ms |
| Replace the sky background with a color | 38.68 | 40.34 | 1.76 ms |
| Hide the directional sun light | 39.06 | 40.25 | 1.34 ms |
| Zero visible clouds and hide the storm bank | 39.25 | 41.03 | 1.16 ms |
| Hide both bird groups | 40.20 | 41.80 | 0.13 ms |
| Hide and suspend the lake reflection probe | 40.47 | 41.52 | −0.07 ms |

Stock p50 ranged from 40.19 to 40.44 ms. The terrain replacement cut the median by 22.8% and held the viewport's draw count at 360. It changes the visual result and screens the material as a whole. The 9.21 ms difference is larger than the earlier parcel/photo subset, which saved about 2.15 ms. Those measurements overlap. The tree test changed 360 draws to 347 and recorded five intervals above 50 ms. The probe selected the field treeline and children tagged as trees by the vegetation catalog. Hedges and other vegetation kept their original visibility.

The i915 client counters support the ranking. Across three roughly 3 s intervals per Home arm, the sampled aggregate render-engine time divided by process frames was 37.7–37.8 ms for the controls around flat ground and 28.9 ms for flat ground. The tree comparison gave 37.5–37.6 ms for its controls and 34.0 ms with trees hidden. This estimates render-engine work over each sampled interval. Individual GPU frame completion remains unobserved.

The disc switch can also change the source of the glare effect. Turning off the directional light changes the scene's lighting. The sky background comparison can affect its lighting and reflection contribution. Each timing is the net effect of that diagnostic state in this view. The lake's entire tested bounding box was behind the default camera.

### Home view toward the lake

The second lens kept the same camera position and turned it toward the lake. All nine tested lake-bounds points were in the frustum. The water mask removed one viewport draw. Stock p50 was 25.21–25.44 ms. Each variant had its own adjacent controls at the same pose.

| Visual change | Variant p50 ms | Variant p99 ms | p50 gain vs adjacent stock |
| --- | ---: | ---: | ---: |
| Replace the sky background with a color | 22.48 | 23.96 | 2.94 ms |
| Zero visible clouds and hide the storm bank | 23.31 | 24.22 | 2.10 ms |
| Hide the water surface | 24.51 | 25.42 | 0.86 ms |
| Hide field treeline and imported tree batches | 24.74 | 25.90 | 0.51 ms |
| Hide both bird groups | 25.27 | 26.06 | 0.08 ms |
| Hide and suspend the lake reflection probe | 25.30 | 26.24 | −0.02 ms |

The lake basin and field were present in every arm. The reflection probe reported one refresh throughout the warmed windows. Its result covers a settled reflection. A weather change or a new capture has a separate cost. Cloud savings increased as the frame showed more sky. The sky, clouds and solar-disc measurements overlap.

### Native pilot flight · trees and terrain

Five circuits used one process, the airborne Ugly Stik, the pilot view, calm weather and Classic sky. Each cycle rebuilt the same Club scene. Both visual masks were applied after the flight was ready, checked at both ends of their respective circuit and restored before returning to Home. The native simulation ran at 240 Hz. The validated stream supplied 60 s of complete process intervals per cycle after a 10 s warmup. The earlier scale matrix used Clear sky and represents a separate workload.

| Run order | p50 ms | p95 ms | p99 ms | Over 50 ms | Sim/wall |
| --- | ---: | ---: | ---: | ---: | ---: |
| Stock | 30.03 | 36.55 | 39.30 | 9 | 0.995 |
| Trees hidden | 28.48 | 33.01 | 34.54 | 2 | 1.000 |
| Stock restored | 30.12 | 36.66 | 38.13 | 4 | 1.000 |
| Flat terrain material | 28.72 | 33.89 | 35.66 | 1 | 1.000 |
| Stock restored | 30.05 | 36.58 | 38.12 | 4 | 1.000 |

In flight, the trees and ground masks reduced p95 by 3.60 ms and 2.73 ms, respectively, relative to the average of their adjacent controls. The terrain shader is the largest measured Home cost and the tree family is the larger of the two flight leads. Prioritize simpler base-grass shading for a terrain detail setting. For trees, split field cards from imported batches before selecting a reduction that preserves collision cues. These masks change the visual result. Adoption and Automatic selection require repeated paired measurements and image, readability and cue checks.

Both sessions completed with clean exit. Raw intervals, timings, i915 samples, mask script and source receipts are retained under `U:/OpenRC-intel-club-ablation-20261123`.

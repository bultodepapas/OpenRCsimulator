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

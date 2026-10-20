# VQ-01c — manual Stik flight, 18:31 Bogotá

2026-10-19, America/Bogota. The user manually flew one Jensen Das Ugly Stik 60
session with pilot/chase/orbit/close-up camera changes. The recording is complete:
4,029 frame rows, 4,031 draw signals, normal observer teardown and process exit 0.
No engine/script error or kernel fault was logged. Prop-strike/hard-landing messages
are recorded simulation events; the application did not terminate unexpectedly.

The native run used Godot 4.7.2 Compatibility / RTX 3090, **3840×2160**, VSync 1,
no explicit FPS cap and real WASAPI audio. Normal player preferences, controls and
focus safety were active. This differs from earlier 1280×720 automated probes and
is not a before/after comparison. No production code, physics, controls, timestep
or quality setting was changed for this recording or its analysis.

## Measured result

The active endpoint filter selects focused frames with an existing simulation and
`paused=0`; it includes resume/camera transitions. Context is polled every 100 ms.
These are **engine observer callback intervals**, not display-present latency.

| Active-flight measurement | Result |
| --- | ---: |
| Samples / summed intervals | 3,223 / 79.359 s |
| Mean FPS | 40.61 |
| Frame interval p50 / p95 / p99 | 20.49 / 37.07 / 57.32 ms |
| Maximum interval | 4,987.44 ms |
| Intervals over 50 / 100 ms | 90 / 11 |
| Endpoint simulation / wall progress | 71.033 / 79.330 s = 0.8954 |
| Simulator CPU median | 78.3% of one logical core; 3.26% of all 24 logical cores |
| Whole-adapter GPU median / maximum during active flight | 35% / 52% |
| Active process RSS range | 938–974 MiB |

The simulation-progress ratio uses the first and last active sample endpoints,
excludes the first interval and retains stalls. It describes this changing manual
flight, not a qualified steady-state benchmark. Mean FPS above includes all active
intervals, including the long freeze; no unfavorable frame was trimmed.

See the [timeline](timeline.png), [analysis](analysis.json),
[raw frames](frames.csv), [host samples](host.jsonl), [GPU samples](gpu.csv),
[context events](events.jsonl) and [console log](console.log).

## Findings and diagnostic limits

1. **Five-second wait/stall remains unexplained.** From **18:32:49.445 to
   18:32:54.432 Bogotá**, the observer received no frame callback for 4.987 s.
   Recorded endpoint state stayed focused, unpaused, in pilot view, with no fault;
   only 12 simulation ticks advanced across the gap. During the gap, simulator CPU
   fell to 3.1%, then 0%, then 3.4% of one core; GPU samples from 18:32:50 through
   18:32:54 report 0% utilization. The next engine process-monitor refresh reports
   4.963 s. This supports a waiting/stalled process rather than sustained heavy
   computation, but identifies neither the blocked thread/function nor the cause.
   Driver/presentation waits, OS interference and synchronous waits remain
   possibilities, not established diagnoses. A thread/wait-stack trace during a
   reproduction is required before selecting a repair.

2. **Loading and first-view stalls are separate.** Home construction took 6.799 s
   before the frame clock was primed. A 3.638 s gap crossed Home→Fly, followed by a
   0.911 s paused-flight interval. Initial active flight had a 0.900 s gap. A
   0.997 s gap ended when the first chase-camera context was observed. The capture
   associates those events in time; it does not time individual constructors,
   shaders or GPU operations. Caches had just been cleared, so startup/cache work
   is a plausible contributor, not proven shader-compilation attribution.

3. **The host was shared.** Other Godot test processes were running and accumulated
   CPU time. Whole-system CPU peaked at 99.9% around a separate 0.238 s flight
   interval near engine time 37.4 s. This contaminates a controlled performance
   baseline and may contribute to some stutters. It does not explain the later
   five-second freeze, when system load and simulator CPU were low. No other
   session's processes were stopped.

4. **No sustained memory growth appears in this short flight.** RSS starts near
   974 MiB and ends near 952 MiB within the active interval; engine static memory
   also decreases slightly. Normal flight node count is 1,071, with a temporary
   maximum of 1,073. Whole-adapter memory and engine video-memory estimates have
   different scopes; neither is per-process resident VRAM. One short session is
   insufficient to establish absence of a leak.

5. **Known visual warning remains.** The imported maple-tree material disables its
   wind deformation because its cull mode is unsupported. No screenshot/video was
   captured, so new visual artifacts cannot be confirmed or excluded. No F12
   markers were recorded.

No runtime patch follows from these measurements alone. In particular, changing
physics calculations, reducing physics frequency, disabling features or reducing
resolution would not identify the waiting call. The next diagnostic step is a
thread/wait-stack capture with comparable settings and background workloads
recorded, followed by a focused reproduction of the identified path.

## Observer integrity and provenance

The observer reads counters and existing session state, receives draw signals and
streams bounded frame batches to disk. Its own timed callbacks average **24.78 µs**
and peak at **635 µs**. Those clocks exclude the external host sampler, renderer,
input dispatch and OS effects; they are not total instrumentation-overhead proof.
The sampler's nominal one-second period was irregular: median gap 1.0004 s,
maximum 5.042 s, with some polling passes themselves lasting several seconds.
It is suitable for coarse correlation, not sub-frame CPU attribution. GPU data
is whole-adapter utilization; no GPU timing queries or GPU wait stacks were used.

The analyzer verifies exact row count against teardown, positive intervals,
monotonic endpoints and equality of consecutive endpoint differences to recorded
intervals. It computes linear-interpolated percentiles and preserves transition
frames. The chart breaks lines across long callback gaps and marks their measured
endpoints instead of drawing a gradual ramp through missing samples.

[Session identity](session.json) retains the launch command, initial Git status,
commit and selected source hashes. The native run began at `21ad34754447dd5c66e95ae926de80134059b17e`;
parallel work continued afterward. Executed [entry](entry.gd),
[observer](observer.gd) and [launcher](record.py) copies match their recorded hashes.
Raw files remain unchanged. [Analyzer](analyze.py) and [manifest](manifest.json)
support the derived analysis; README is outside the measurement manifest.

The preceding headless Home smoke check verified observer startup and metric
output, not native flight. No automated takeoff/landing, full app test suite,
replay equivalence, frame-present trace, thread-stack capture or performance fix
was performed as part of this manual recording.

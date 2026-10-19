# VQ-01c — second manual Stik flight, 18:47 Bogotá

2026-10-19, America/Bogota. One user-controlled Stik flight, several camera cycles,
4K/VSync/Compatibility and WASAPI audio. The app exits normally (code 0), with
5,149 frame rows, 5,151 draw signals, no engine/script errors and no kernel fault.
No F12 markers were recorded. The logged steep-dive/airframe-impact event is an
aircraft simulation outcome, not an application crash. No production runtime,
physics, controls, timestep or visual-quality changes were made for this test.

The previous five-second in-flight stall **did not recur**. The new capture finds
poor tail pacing and a loading snapshot; it does not establish a performance fix
or identify the old waiting call.

## Frame pacing

| Measurement | Result |
| --- | ---: |
| Raw active endpoint samples / mean FPS | 4,005 / 56.20 |
| Active samples excluding snapshot-overlap interval / mean FPS | 4,004 / 58.50 |
| Filtered p50 / p95 / p99 | 13.90 / 48.02 / 59.08 ms |
| Filtered maximum | 76.03 ms |
| Filtered intervals over 50 / 100 ms | 187 / 0 |
| Simulator CPU median | 81.2% of one logical core; 3.38% of 24 logical cores |
| Whole-adapter GPU median / maximum | 36% / 44% |
| Active RSS range | approximately 870–896 MiB |

The endpoint filter requires a simulation, focus and `paused=0`. Menu/camera
context is polled every 100 ms. The 2.828 s Home→Fly interval ends in an active
flight, so the raw endpoint filter includes it. That interval overlaps the
diagnostic snapshot and is explicitly excluded from the filtered summary.
**The entire overlapping interval is excluded; snapshot duration is not simply
subtracted to invent an uninstrumented loading time.** Raw files remain intact.
No other slow interval is removed. Percentiles use linear interpolation.

These are engine observer callback intervals, not display-present latency. See
[analysis](analysis.json), [original automatic summary](summary.json),
[timeline](timeline.png), [raw frames](frames.csv), [host samples](host.jsonl),
[GPU samples](gpu.csv), [contexts](events.jsonl) and [console](console.log).

Against the [first manual flight](../manual-flight-1831/README.md), average FPS is
higher (40.61 → 58.50 filtered), but p95/p99 are worse (37.07/57.32 → 48.02/59.08
ms). This is **an uncontrolled repeat, not a before/after optimization result**:
input trajectories, cache temperature, host load and instrumentation differ.
The first run followed cache cleanup; caches were retained for this run.
`Main`, `Simulation` and project-settings hashes match; `AppRoot` changed through
parallel work. Selected hashes are not complete dependency or input-tape identity.

## Snapshot result

Windows refused the requested CPU/GPU kernel trace with `0xc5585011` because the
current session could not enable performance profiling. No security policy or
privilege was changed, and no kernel trace was collected. The normal-user fallback
uses [MiniDumpWriteDump](https://learn.microsoft.com/en-us/windows/win32/api/minidumpapiset/nf-minidumpapiset-minidumpwritedump)
from a separate process, without a full-heap dump. It triggers after 2.5 s without
frame-file growth, at most three times, at least 15 s apart. Its own activity can
perturb timing and is logged separately.

One snapshot was captured, during **Home→Fly at 18:47:27.403–18:47:30.231**.
Capture itself spans **18:47:29.628–18:47:29.985**, about **358 ms**. There is no
later in-flight snapshot. The fallback cannot recover a call stack for a stall
that never occurred. See [capture events](stalls.jsonl).

LLDB 22.1.8 successfully opened the 323,165-byte dump and unwound its 72 threads.
The earliest-created thread, TID 46508, is thread #1. Its stack contains
`msvcrt.dll!malloc` and `ntdll.dll!RtlAllocateHeap` frames above Godot addresses.
That is a snapshot of an allocation path during loading, **not proof that heap
allocation accounts for the full loading delay or a memory leak**. The official
engine binary has no COFF debug directory; its `NoHotPatch + large-offset` labels
are unresolved nearest-export annotations, not meaningful engine function names.
The snapshot cannot identify the responsible GDScript caller or explain the first
flight's five-second wait. Waiting worker threads alone are not deadlock evidence.

[Decoded stacks](stacks-lldb-2.txt), [thread creation/times](thread-info.json) and
[dump identity](dump-identity.json) retain the result. The binary dump stays in
ignored local `tmp/manual-flight-recordings/20261019-184715-v2/stall-1.dmp`; its
SHA-256 is recorded. The first LLDB attempt failed because `python311.dll` was
missing; [that failure](stacks-lldb.txt) is separate from the successful decoding.
The decoder used the installed LLDB plus a local, checksum-verified
[Python 3.11.9 embeddable runtime](https://www.python.org/downloads/release/python-3119/),
with its PATH set only for the decoder process. No global Python installation or
PATH was changed. [Runtime identity](decoder-runtime.json) records the download.

## CPU contention and memory

Whole-system CPU reached 100%. Coarse correlation with the nearest host sample
within 0.75 s shows markedly worse pacing during high load:

| Whole-system CPU group | Frames | Frame p50 / p95 | Frames over 50 ms |
| --- | ---: | ---: | ---: |
| Below 30% | 3,438 | 13.42 / 21.93 ms | 104 |
| At least 90% | 150 | 50.36 / 60.90 ms | 78 |

See [correlation](cpu-correlation.json). These groups cover different flight phases
and the CPU counter averages its own sample interval. The association supports
host contention as a diagnostic lead, not causal proof or identification of a
particular background program. Initial other-Godot inventory is retained in
[background-at-launch.json](background-at-launch.json); runtime process enumeration
was deliberately removed from the CPU sampler, so later programs are not named.
No other session's processes were stopped.

RSS declines from about 896 to 870 MiB in the active window. Normal node count is
1,071, with temporary changes to 1,073. This short capture shows no sustained
process-memory growth; it does not establish leak freedom. The maple-tree material
wind/cull warning remains. No video or screenshots were recorded, so image defects
cannot be assessed from these counters.

## Recorder validation and remaining work

The frame observer is unchanged from the first capture. Its own callbacks average
19.99 µs and peak at 602 µs, excluding external monitor/dump/OS overhead. The host
sampler now avoids the slow whole-machine process scan: median sample spacing is
1.0004 s, maximum 1.0160 s, versus the prior 5.042 s maximum. This improves recorder
cadence; it is not a claimed game optimization.

Before launch, the revised recorder passed a headless Home smoke check and the
watchdog produced a valid minidump of an owned disposable sleeping process. The
actual capture verifies positive monotonic intervals, exact consecutive timestamp
differences and row-count agreement with normal teardown. Snapshot overlap is
marked rather than hidden. No automatic flight, replay comparison, full test suite
or application-performance repair was performed in this manual campaign.

The remaining technical questions are the old intermittent wait and attribution
of repeated 48–60 ms frames. A controlled idle-host repeat and a matching-symbol or
sampling trace would be needed before selecting a runtime patch. Kernel tracing
remains unavailable in the current non-elevated session; the captured allocation
snapshot does not justify modifying physics or reducing features/quality.

[Session identity](session.json) retains initial Git state and source hashes at
`79254d44070500bee668a976740f7cfd81e14a79`. Executed
[observer](observer.gd), [launcher](record_v2.py), [snapshot helper](hang_dump.py)
and [analyzer](analyze_v2.py) are retained with the [manifest](manifest.json).
README is excluded from the measurement manifest.

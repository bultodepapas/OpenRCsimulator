# VQ-04a — initially disabled aircraft cues, 2026-11-09

The triangle audit identifies repeated auxiliary-view work as a separate cost.
Aircraft cues that start disabled now defer the projector, mask viewport,
receiver and shader materials, and skip the generic fallback-texture upload.
Saved cue Off, Native or Off techniques, and direct `--shadow=off` are covered.
Normal enabled construction and warm-projector reuse retain their existing path.

The implementation deliberately retains eager geometry collection. Mutable
Timber suspension meshes and aircraft articulation make a later collection a
different snapshot. The already-collected shape remains authoritative until
activation; source transforms, in-place mesh edits and newly added children
cannot change it. Precomputed Home shapes keep the same ownership contract.

Main resolves its initial cue before world construction and refreshes saved
preferences after staged yields. An explicit flight cue keeps its precedence.
Pending sources are weak references: reentry/visibility can replay the latest
request, and source deletion releases retained geometry on the next policy frame.
An expired bound source cannot turn into a generic legacy shadow.

## Native result

[Report](report.json) records source hashes, engine/GPU identity, captures and
allocation observations. [Summary](summary.json) retains verified image hashes
and the component results. Reproduce through the existing
[shadow tool guide](../../../../../tools/shadows/README.md#initially-disabled-aircraft-cues).

Windows, RTX 3090, NVIDIA OpenGL 617.42, pinned Godot 4.8-beta2 Compatibility,
1920×1080 output and native internal resolution, MSAA 4×. No other Godot process
was present at the final run's launch. The checked run completed with zero
engine errors or warnings.

All four disabled routes created no projector child and no fallback texture.
The eager control increased the renderer's texture-memory estimate by 611,668
bytes; each deferred route added zero texture bytes before activation. This is
**about 0.58 MiB per carrier in this fixture**, not a total/peak VRAM measurement.
The eager control uses the unchanged enabled constructor/bind path, reproducing
the previous eager resource setup with a shared precomputed full Corsair shape.

After activation, every route produced **byte-identical 256² mask and 1080p
receiver PNGs** to its eager control. Eleven existing full/proxy pose comparisons
and seven stock/fallback binding checks also completed successfully.

| Initially disabled route | Eager setup, ms | Deferred setup, ms | First enable, ms |
| --- | ---: | ---: | ---: |
| Master Off | 4.868 | 0.099 | 6.530 |
| Native | 6.286 | 0.100 | 7.002 |
| Saved cue Off | 13.138 | 0.116 | 6.136 |
| Explicit local Off | 6.944 | 0.116 | 6.215 |

These single component observations use an already-collected shape. They exclude
geometry collection, full world loading and the first visible draw. Shader/driver
warmup and ordinary host variation can affect them; no whole-flight FPS or
repeated-run timing acceptance is claimed. Resource creation moves to first
enable, which can cause a one-time setup hitch. Later toggles reuse the projector.

## Verification

[Verification receipt](verification.json) identifies the final checked sources
and receipts. Nine focused GDScript suites passed **490 checks**, with zero
engine errors or warnings: deferred/startup 80, blur 50, cue controls 50, field
cues 20, ownership 49, Home geometry 54, settings 60, projector 47 and proxy 80.
The new startup test exercises actual flight preparation with a stubbed world;
its scope is ordering and cue resolution.

Separate native debug-bridge sessions exercised the real Main routes at 1080p:

- Direct `--shadow=off` Corsair launch: deferred metadata, zero projector
  children and no fallback texture.
- Home settings → Graphics → Aircraft shadow cue Off → Keep changes → Corsair
  runway flight: the same deferred state with flight-local mode Off. Pressing V
  changed to Sun and installed the retained 178,551-triangle proxy.

Both sessions stopped without a crash or leaked objects. Focus/background
hitches appeared in live logs, so these are route/lifecycle checks. Images remain
in ignored `tmp/deferred-shadow-20261109/final-candidate/`; no PNGs are committed.

The captured mesh still occupies memory while pending. Home's geometry cache,
field projectors, already-warm projectors, other GPU/renderer platforms and a
complete-flight performance campaign are outside this saving. No physics or
collision behavior was changed, and golden flights were not re-recorded.

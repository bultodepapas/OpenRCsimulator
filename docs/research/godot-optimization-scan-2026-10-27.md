# Godot optimization scan, 2026-10-27

Three research scouts (web, Godot source at the pinned `4d10419ca` 4.8-beta1 commit, and
this repository's evidence) looked for CPU, profiling/loop and Compatibility-rendering
techniques. This is dated research, not a runtime result. Items marked **verified** were
checked in this repository; everything else is reported with its source and needs its own
measurement. The [performance plan](../plans/global-performance-visual-quality.md) owns
order and gates; the [2026-10-27 tick attribution](visual-quality-implementation/VQ-01c/tick-observers-2026-10-27/README.md)
holds the measurements that prompted it.

## Corrections to current assumptions

- **Alpha-to-coverage is a no-op on Compatibility.** The GLES3 driver handles
  `BLEND_MODE_ALPHA_TO_COVERAGE` with `// Do nothing for now`
  ([source](https://github.com/godotengine/godot/blob/master/drivers/gles3/rasterizer_scene_gles3.cpp));
  the fix, [PR #114845](https://github.com/godotengine/godot/pull/114845), is open. L6b-R1's
  A2C arm cannot run on 4.8-beta1. 4.8's import option *Preserve Alpha Test Coverage*
  ([PR #104289](https://github.com/godotengine/godot/pull/104289)) addresses distant
  foliage thinning without runtime cost; unverified for GLB-embedded textures.
- **Pipeline-compilation counters read 0 on Compatibility.** `get_pipeline_compilations()`
  returns 0 in `rasterizer_scene_gles3.h` and `rasterizer_canvas_gles3.h`, so the debug
  bridge's pipeline fields (`app/debug/debug_bridge.gd`, **verified** to read them) cannot
  attribute a shader-compile hitch. GL caches program binaries on disk but logs nothing;
  there are no ubershaders on Compatibility
  ([pipeline compilations](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html)).
  Compare fresh and warm shader caches instead.
- **`Engine.time_scale` does not change physics iterations per wall second, and headless
  frames are uncapped** (**verified**, VQ-01c 2026-10-27).
- **`physics/common/run_on_separate_thread` does not move script `_physics_process`** off
  the main thread ([thread-safe APIs](https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html));
  it cannot help a GDScript kernel.
- The plan header still names Godot 4.7.2; `app/get-godot.sh` and STACK pin 4.8-beta1.

## Second pass (same day): engine-commit benchmarks and corrections

- **Official benchmarks exist for the pinned commit** `4d10419ca`
  ([results](https://github.com/godotengine/godot-benchmarks-results/blob/main/2026-10-16_4d10419ca.md),
  i5-12400, Linux; "debug" = editor binary, "release" = `template_release`): empty script call
  ≈ 57 → 31 ns, `Callable.call` 152 → 89 ns, stored lambda call 43 → 25 ns, lambda creation
  ≈ 120 → 90 ns, `signal.emit` with one connection 250 → 170 ns; `Object.new()+free()` ≈ 280 ns
  single-threaded and ≈ 1.4 µs with 12 contending threads. `PackedFloat64Array` beats
  `Array[float]` 1.7×. Editor-to-release speedups across the GDScript suite are 1.14–1.93×.
- **4.8-beta1 export templates and Linux debug symbols are published**
  ([release](https://github.com/godotengine/godot-builds/releases/tag/4.8-beta1)), so a
  release measurement and `perf` sampling need no custom build. `perf` on the dev VM is
  blocked by `kernel.perf_event_paranoid=4` (needs the owner's sudo).
- **The script profiler over-weights small helpers**: with profiling on, the VM reads the
  clock at every script entry, exit and call site
  ([gdscript_vm.cpp](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/modules/gdscript/gdscript_vm.cpp#L704));
  the profiled kernel is ≈ 1.32× its unprofiled time here.
- **Every `{}`/`[]` literal allocates**; only const contexts fold them (read-only), so inline
  `.get(key, {})` defaults in hot paths allocate per call (197 such defaults in `app/physics`,
  75 in `app/sim`). Per-allocation cost is unmeasured.
- **Not worth pursuing (evidence)**: the two lambdas and ≈ 15 Callable calls in
  `Simulation.step` (≈ 3 µs per tick), `stepped.emit` dispatch (≈ 2.5 µs per tick),
  `range(n)` loops (compiled without allocation), RK4 buffer reuse, Dictionary records →
  RefCounted classes, StringName keys, and the experimental separate rendering thread
  ("known bugs… not recommended for production").
- **New candidates**: compute session-immutable layout indices and capability flags once
  (`gear_is_retractable` 32 calls per tick, `flaps.enabled` 25, `_model_wheel_count` 20,
  `glow_is_active` 17; needs the immutable-data rule, like validation caching); share
  accepted-state `air_data`/terrain/wind results among observers (1–3%); a frame cap that
  divides 240 Hz (120) so CPU-bound frames carry a constant tick count (pacing, native
  check); simulation one frame ahead on a worker thread (largest ceiling, needs an owner
  decision on worker-owned simulation state).

## CPU: GDScript kernel and observers

- **Script calls dominate tiny helpers.** A call into another script function goes through
  the generic call path, initializing and destroying every stack slot
  ([VM source](https://github.com/godotengine/godot/blob/master/modules/gdscript/gdscript_vm.cpp));
  about 170–600 ns per call on 4.3 ([forum](https://forum.godotengine.org/t/why-is-there-such-a-massive-overhead-in-calling-a-function/82620)).
  **Verified** here: inlining one per-edge helper made lake queries 36% shorter (LU-25-R3).
  `M.sin_()` wraps a built-in that is otherwise one validated opcode.
- **Typed code** speeds operators/built-ins 25–50% and native calls 70–150%
  ([typed instructions](https://godotengine.org/article/gdscript-progress-report-typed-instructions));
  debug-build figures.
- **Release builds run the tick 1.5–1.9× faster than the debug console binary.** The
  [NITRO-02 probe](glow-engines/NITRO-02/performance-probe.log) (2026-10-13, Windows,
  Godot 4.7.2, one snapshot exported with the official release template) measured p50
  542 → 364 µs for the Stik and 2,424 → 1,303 µs for the glow 2T. Every 2026-10-27 profile
  uses the debug editor binary, so absolute costs overstate shipped builds; relative gains
  are expected to carry over but are not re-measured on the current source
  ([PR #70838](https://github.com/godotengine/godot/pull/70838) reports a similar gap).
- **Native code, this repository's own record:** slipstream 17× on the component but
  P-51 tick −29–39% ([E0b6p](propwash/E0b6p/native/README.md), [Gate P](simulation-state/Gate-P/README.md));
  truck evaluator ≈ 2.8× with RK4 still in GDScript ([RCV-runtime](rc-monster-truck/RCV-runtime/README.md)).
  Dictionary decoding inside native code was 32–39% of the method. Linux/GCC stayed
  bit-exact; Windows MSVC versus MinGW libm can differ
  ([Gaffer](https://gafferongames.com/post/floating_point_determinism/)), so expect
  per-backend goldens. Whole-model ports in practice: JSBSim in Unreal at 120 Hz
  ([README](https://github.com/JSBSim-Team/jsbsim/blob/master/UnrealEngine/README.md)).
- **Observers:** established sims run presentation at frame rate and the flight model at a
  fixed rate (FlightGear/JSBSim, [wiki](https://wiki.flightgear.org/Howto:Methods_to_replace_the_NASAL_code_with_JSBSim_code));
  iRacing reportedly batches 360 Hz samples to 60 Hz consumers (second-hand,
  [forum](https://community.granitedevices.com/t/iracing-360hz-ffb-with-simucube-2/10613)).

## Profiling and pacing tools

| Tool | Status for us | Source |
| --- | --- | --- |
| Tracy | Official since 4.6 (`profiler=tracy`, Tracy 0.13.0); custom engine build; GDScript zones; RAM growth if no client connects | [docs](https://docs.godotengine.org/en/latest/engine_details/development/profiling/tracy.html), [PR #113279](https://github.com/godotengine/godot/pull/113279) |
| perf/Hotspot, VerySleepy, Instruments | Need a `production=yes debug_symbols=yes` build; GDScript shows as interpreter frames | [profiling index](https://docs.godotengine.org/en/latest/engine_details/development/profiling/index.html) |
| `--gpu-profile` | Per-pass GPU times on desktop GL, not ANGLE; not yet run on the pinned binary | [rendering_server_default.cpp](https://github.com/godotengine/godot/blob/master/servers/rendering/rendering_server_default.cpp) |
| RenderDoc, `apitrace replay --pgpu --ppd` | Per-draw GPU time on GL 3.3 | [apitrace](https://github.com/apitrace/apitrace/blob/master/docs/USAGE.markdown) |
| PresentMon (Windows), MangoHud (Linux) | Display-side frame pacing; not available on the dev VM | [jitter/stutter](https://docs.godotengine.org/en/latest/tutorials/rendering/jitter_stutter.html) |

None of these work with official export templates. Measure presented frames, not loop
time ([Croteam, GDC 2018](https://gdcvault.com/browse/gdc-18/play/1025031)). Windows
`MODE_FULLSCREEN` stays composited by design (one-pixel offset in
`display_server_windows.cpp`); test exclusive fullscreen, and VRR caps of `r − r²/3600`
(59 at 60 Hz, 138 at 144 Hz) rather than round numbers.

## Rendering on Compatibility

- Each shadowed omni/spot light adds a pass; MSAA is the only antialiasing; 3D scaling is
  bilinear or nearest (4.7) ([renderers](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html)).
- The depth prepass is on by default except on Apple, Mali, Adreno and PowerVR
  ([ProjectSettings](https://github.com/godotengine/godot/blob/master/doc/classes/ProjectSettings.xml)),
  so the M1 and Windows paths already differ; an on/off A/B is cheap on native hardware.
- Occlusion culling gives little in open scenes; visibility-range fades force transparency.
- Desktop GL has S3TC; BPTC needs an extension or is decompressed at load
  ([config.cpp](https://github.com/godotengine/godot/blob/master/drivers/gles3/storage/config.cpp)).
- Mip streaming in 4.8 is Forward+/Mobile only ([PR #113429](https://github.com/godotengine/godot/pull/113429)).
- Borrowable instancing design: [Terrain3D instancer](https://terrain3d.readthedocs.io/en/latest/docs/instancer.html)
  (32 m cells, one MultiMesh per LOD, low-LOD shadow casters); HLOD in the
  [visibility ranges demo](https://github.com/godotengine/godot-demo-projects/tree/master/3d/visibility_ranges).
  No open-source Godot flight project with documented optimizations was found.

## Ranked backlog

| # | Idea | Outputs | Hardware | Status |
| --- | --- | --- | --- | --- |
| 1 | Conservative bounds before per-point/per-edge contact loops | Bit-identical | Any | Done: LU-25-R3, LU-25-R4 (runway session −22%) |
| 2 | Run presentation observers once per frame, keeping per-tick events in a buffer | Physics identical; presentation by owner | Any | Owner decision across audio, statistics, crash, scenery; measured ceiling: observers are ≈ 34% of main-thread CPU airborne, ≈ 23% on the runway |
| 3 | Inline `M.*` vector/quaternion helpers in hot loops with exact grouping; enforce the math-routing rule by lint | Bit-identical | Any | Candidate; mechanical, needs byte-parity probes |
| 4 | Validate immutable model data once (`wheel_brake_available`, lake/surface guards) | Bit-identical | Any | Session answers done: [NK-2a](native-kernel/NK-2a/README.md) per-tick memo, session tick −8 to −16%; lake/surface guards need an API change across owners |
| 5 | Re-measure a `template_release` export for the current tick | None | Any | Done: [×1.23 airborne, ×1.19 runway](visual-quality-implementation/VQ-01c/release-tick-2026-10-27/README.md) on current source (NITRO-02 had 1.5–1.9× before the 2026-10-27 work) |
| 6 | Attribute GPU passes (`--gpu-profile`, scale 0.5 vs 1.0, depth prepass on/off) | None | Native GPU | Prerequisite for rendering changes |
| 7 | Windows pacing: exclusive fullscreen, VRR-aware caps | None | Native Windows | Candidate |
| 8 | Preserve Alpha Test Coverage on foliage atlases | Visual | Native for motion | Replaces L6b-R1's A2C arm |
| 9 | Guard the ground shader's `parcel()` Voronoi behind its `far` weight | Byte-identical image expected | Native GPU | Only if fill-bound |
| 10 | Whole-tick native kernel | Per-backend goldens | All platforms | Only if 1–5 still miss Gate P; [scoped](native-kernel-scoping-2026-10-27.md): stage evaluator first (≤ ≈ 2×), whole tick needs an SF-08 amendment |

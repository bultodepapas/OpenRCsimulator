# Apple MetalFX engine intake (DT-MAC-11a / 07a1)

This isolated engine experiment does not change `app/get-godot.sh`, install export
templates globally, or promote an unqualified graphics mode. The
[four-technology plan](../../../docs/plans/apple-metalfx.md) owns remaining gates.

`engine.py` pins official Godot commit
`cafc17a192acf67903910a68aeb3c076c0907a4b` (4.8-beta2). Download its
[source ZIP](https://codeload.github.com/godotengine/godot/zip/cafc17a192acf67903910a68aeb3c076c0907a4b)
once into an ignored cache. Required SHA-256:
`83cf257bc53427f2b1ea07015dbad298252c20546e916c5daa30a1cf78c45c1e`.
The helper never downloads dependencies or deletes/reuses an intake directory.
Godot's MIT license and all third-party notices remain in each full source tree;
preserve them when packaging a custom engine.

Use Python 3.11+, Git and native ARM64 macOS for builds. In a task-owned venv,
install `scons==4.10.1 zstandard==0.25.0` (the pinned engine requires zstandard on
Python earlier than 3.14). Use installed Apple developer tools/SDK 26+ for the new
MetalFX APIs. The current native experiment uses SDK 27; compiling a macOS 13
deployment target does not establish execution on macOS 13. No Developer ID is
required for local raw executables. Public signed distribution remains deferred.

Prepare **separate fresh intakes** for editor and release template. Bash/zsh:

```sh
patches=(
  --patch tools/graphics/metalfx/patches/0001-metalfx-allocation-fallback.patch
  --patch tools/graphics/metalfx/patches/0002-metalfx-history-reset.patch
  --patch tools/graphics/metalfx/patches/0003-metalfx-debug-faults.patch
  --patch tools/graphics/metalfx/patches/0004-metalfx-frame-inputs.patch
  --patch tools/graphics/metalfx/patches/0005-metal-triangle-query.patch
  --patch tools/graphics/metalfx/patches/0006-metalfx-gpu-observation.patch
)
python tools/graphics/metalfx/engine.py prepare --archive /cache/godot.zip \
  --out tmp/metalfx-editor "${patches[@]}"
python tools/graphics/metalfx/engine.py build --archive /cache/godot.zip \
  --out tmp/metalfx-editor --target editor --jobs 4 "${patches[@]}"
python tools/graphics/metalfx/engine.py prepare --archive /cache/godot.zip \
  --out tmp/metalfx-template "${patches[@]}"
python tools/graphics/metalfx/engine.py build --archive /cache/godot.zip \
  --out tmp/metalfx-template --target template_release --jobs 4 "${patches[@]}"
python tools/graphics/metalfx/engine.py pair --archive /cache/godot.zip \
  --out tmp/metalfx-editor --template tmp/metalfx-template "${patches[@]}" >tmp/metalfx-pair.json
```

0001 adds allocation/submission guards and per-viewport state; 0002 adds Temporal
reset serials, render-attempt bounds and lifecycle fences. 0003 is an opt-in
diagnostic source patch: `DEBUG_ENABLED` builds accept
`OPENRC_METALFX_TEST_FAILURE=spatial_factory|temporal_factory|spatial_enqueue|temporal_enqueue`.
Its environment is latched on first lookup, so use one fresh process per case.
The controls are absent from release-template code. Normal launches leave it unset.
0004 adds an explicitly requested offscreen HDR scene-input experiment, macOS 26+
SDK bridge and synchronous diagnostic readback. It rejects unsupported scenes,
keeps Temporal reset receipts independent and has no presenter. Its actual M1
readback/lifecycle fixture passed; scene motion and presentation remain open.
0005 adds an opt-in experimental Metal compute triangle-query backend. Launch
with `GODOT_METAL_TRIANGLE_QUERY=1` only for that experiment; ordinary ray-query
and ray-pipeline support remain unavailable. It admits a bounded triangle/instance
subset, not complete OpenRC scenes. The portable controls compile the changed
validation and binding functions, including development-build object naming,
pipeline changes, inactive descriptor-set holes and current TLAS/BLAS residency.
Native compilation and GPU readback for this patch remain pending.
0006 adds opt-in command-buffer completion observation, described below. Its
compiled fake-command controls passed; it has not run on the native Metal backend.

Intake freezes and hashes archive/ordered patch copies, reconstructs the expected
patched catalog, rejects unknown source edits, extra inputs, unsafe paths and
symlinks, and records helper identity. New source files require regular mode
100644 and enter the verified catalog; executable/symlink additions are refused.
`source/` stays pristine; each target builds
in its own disposable `build-source-<target>/`. Native builds use Metal and
Compatibility, without Vulkan, AccessKit, LTO or debug symbols. They record exact
commands, SDK, clang, controlled environment, logs, architecture and artifact
hashes. The explicit SDK libc++ include route accommodates the installed CLT
layout observed on the shared M1. Failed/interrupted builds require a new intake.

`verify` rechecks the pristine intake after a build. `pair` additionally compares
editor/template source, patches, helper, toolchain and flags and rehashes exact
artifacts and logs. Pair verification does not qualify rendering, export,
signing, minimum OS compatibility, performance or a product package. Keep the
export's actual template identity bound to the later package receipt.
Use the same absolute Python invocation spelling for both builds. The verifier
compares recorded command arrays and refuses differing aliases or `..` spellings
even when they resolve to the same interpreter.

```sh
python -m unittest discover -s tools/graphics/metalfx -p test_engine.py
OPENRC_METALFX_SOURCE_ARCHIVE=/cache/godot.zip \
  python -m unittest discover -s tools/graphics/metalfx -p 'test_engine*_patch.py'
```

The second suite compiles selected patched functions with fake rendering/SDK
objects where a compiler is available. This is fault-path source evidence,
separate from the real engine build and native GPU fault injection. Shared-host
Godot runs still use the [checked runner](../../../docs/tools/shared.md#one-godot-script)
and [host admission](../../testqueue/README.md).

The [native API fixture](../../../research/engine-upgrade/metalfx/README.md)
checks the real device independently. Neither fixture is a second profiler.
The verified 0001–0003 pair and the later intake-helper revision are identified
separately in the dated evidence; a helper update deliberately invalidates an
older intake's helper identity until its original frozen helper is restored.

## Optional GPU completion observation

With patch 0006, call
`RenderingServer.viewport_set_metalfx_gpu_observation_requested(viewport_rid, true)`
and read `viewport_get_metalfx_gpu_status(viewport_rid)`. The default is Off. Off
creates no observation state or completion handler. Explicitly requesting it can
allocate CPU state before an effect callback is admitted; an enqueue failure may
therefore have allocated state with ticket zero and `unobserved` status.

Handlers are registered after the actual SDK encode returns. They retain only
shared observation state and value metadata, so retiring a viewport/generation
does not leave a callback holding its owner. Snapshots are coherent per role
(`scaler` or `frame_interpolation`), not an atomic pair. Identify a sample by the
viewport RID, viewport generation, observation generation, frame generation,
role, epoch and ticket. A recovered interpolation context can restart its ticket
counter while its epoch changes. A greatest observed completed ticket is not a
contiguous completion fence or a count of completed frames.

`completed` means the latest encoded ticket's callback reported command-buffer
success; an earlier observed failure stays latched in that observation state.
Temporal GPU reset completion is independent of the legacy encode-call receipt.
Toggling observation does not reset Temporal history or its request serials.

Apple's [completion handler](https://developer.apple.com/documentation/metal/mtlcommandbuffer/addcompletedhandler(_:))
reports the whole command buffer. Its
[GPU start](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime)
and [end](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpuendtime)
timestamps use system Mach seconds; absent, zero or invalid times remain null.
The callback's CPU observation uses `std::chrono::steady_clock` microseconds.
Do not subtract these clocks without calibration, sum durations shared between
roles, or label this effect-only cost, OS presentation, displayed FPS or latency.
`gpu_probe.gd` exercises the native API and retirement cases; parsing and native
execution are still required before accepting that fixture.

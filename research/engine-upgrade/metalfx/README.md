# Native MetalFX API fixture (DT-MAC-11a / F03)

`probe.mm` is a bounded Metal3 API fixture for the
[four-technology plan](../../../docs/plans/apple-metalfx.md). It creates a native
device, queries the actual descriptors and creates supported Spatial, Temporal,
frame-interpolation and denoised effects. Spatial additionally encodes one uniform
linear frame from 1280×720 into **1920×1080**, waits up to 20 seconds and checks
every output component for finite values and maximum absolute error below 0.025.
The uniform witness does not test distant-aircraft readability or moving imagery.

Build in an isolated Mac task workspace with SDK 26 or later:

```sh
mkdir -p tmp/metalfx-api
sdk="$(xcrun --show-sdk-path)"
xcrun clang++ -std=c++17 -arch arm64 -fobjc-arc -fblocks -O2 \
  -mmacosx-version-min=13.0 -isystem "$sdk/usr/include/c++/v1" \
  -framework Foundation -framework Metal -framework MetalFX \
  research/engine-upgrade/metalfx/probe.mm -o tmp/metalfx-api/probe
shasum -a 256 research/engine-upgrade/metalfx/probe.mm tmp/metalfx-api/probe
tmp/metalfx-api/probe >tmp/metalfx-api/result.json
```

Record SDK, clang, OS, source/binary hashes and the command with the output. Run
without another rendered/GPU workload. Availability checks preserve the source's
deployment floor; only the actual tested OS is qualified by a run. The explicit
libc++ SDK include is required by the shared Mac's installed CLT layout.

Inspect **each JSON status**. Exit zero means only that the Spatial witness passed.
`allocated_not_encoded` proves object creation for that descriptor; it does not
prove GPU execution, production inputs, history correctness or presentation.
The Temporal descriptor uses the pinned Godot factory's manual exposure mode;
the native scale bounds and reciprocal, million-unit Godot encoding are retained.
Neither a single cold GPU duration nor allocation time is an FPS benchmark.

In the first M1/macOS 27.0.1 experiment, the denoised descriptor reported support
and allocated despite Apple's feature table listing Apple9 for denoised upscaling.
Retain that disagreement. Never reject by a model-name/family assumption alone,
or infer hardware ray-intersection acceleration from `supportsRaytracing`.
The fixture intentionally does not encode denoising without a real RT producer.
Its synthetic color/depth observations cannot qualify that producer. See the
[dated implementation evidence](../../../docs/research/desktop-delivery-investigations/DT-MAC-11a/README.md).

## Interpolation controls

Compile `frame_interpolation.mm` with the same flags/frameworks as `probe.mm`.
It uses independently checked hard edges, a direct analytic midpoint and endpoint,
crossfade, zero-motion and reversed-motion controls. Run each case separately;
each native process has a twenty-second deadline. Preserve the no-option baseline
before testing warmup or the independent SDK-27 matrix option.

```sh
cases=(uniform crossfade zero reverse-color reverse-input color-pixels input-pixels)
mkdir -p tmp/metalfx-api/frame-warm
for name in "${cases[@]}"; do
  MTL_DEBUG_LAYER=1 tmp/metalfx-api/frame_interpolation "$name" --warmup-static=3 \
    >"tmp/metalfx-api/frame-warm/$name.json" \
    2>"tmp/metalfx-api/frame-warm/$name.stderr" || exit 1
done
reports=()
for name in "${cases[@]}"; do reports+=("tmp/metalfx-api/frame-warm/$name.json"); done
tmp/metalfx-api/frame_interpolation compare "${reports[@]}" \
  >tmp/metalfx-api/frame-warm/comparison.json
```

The comparison requires every matching case/configuration and a predeclared
margin against incorrect controls. On the observed M1, three additional static
encodes made input-grid motion distinguish the midpoint. The first two encodes
alone returned an endpoint; they did not qualify interpolation. This synthetic
result does not fix the convention for Godot's actual motion/depth/jitter inputs.
`--matrices-27`, `--single-edge` and `--small-shift=4` are independent diagnostic
options. Matrix properties are availability-guarded and are not required on 26.

## Ray-traced denoising witness

Compile `denoised_rt.mm` with the same flags and frameworks, then pass
`denoised_rt.metal` as its sole argument. The Metal shader compiles at runtime;
the optional offline `metal` command is not required. This fixture builds a real
two-triangle BLAS, traces primary/reflected rays and supplies real guide textures.
CPU analytic checks validate hits, distances, auxiliary inputs and finite output
after sentinel initialization. Its loose static ROI bound is a sanity control,
not a quality or speedup measurement.

```sh
MTL_DEBUG_LAYER=1 \
MTL_SHADER_VALIDATION=1 \
MTL_SHADER_VALIDATION_DEFAULT_STATE=none \
MTL_SHADER_VALIDATION_ENABLE_PIPELINES=openrc-rt-trace,openrc-rt-clear,openrc-rt-depth \
MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
MTL_SHADER_VALIDATION_ABORT_ON_FAULT=1 \
tmp/metalfx-api/denoised_rt research/engine-upgrade/metalfx/denoised_rt.metal \
  >tmp/metalfx-api/denoised.json 2>tmp/metalfx-api/denoised.stderr
```

Inspect both the exit code and stderr, and confirm each reported producer
pipeline's actual `shaderValidation` state. The selective run excludes SDK
internal pipelines. Global shader instrumentation aborted on the observed SDK
with an internal 1,024-thread dispatch above the instrumented pipeline limit;
API-only and selectively instrumented controls passed. Retain that failure.
Neither control is a clean full-SDK shader-validation claim or Godot integration.

## Real engine boundaries

Build the selected ordered patches with the
[engine intake helper](../../../tools/graphics/metalfx/README.md). Copy each
GDScript fixture into a task-owned project's `tools/` directory and run through
`tools/godot/run_checked.py`; retain its report and exact fixture/engine hashes.
Never put these drafts or deliberate fault controls in the production app.

- `status_probe.gd`: actual Spatial/Mobile or Temporal/Forward+ allocation,
  submission, output sanity, resize generation and viewport isolation.
- `history_probe.gd`: actual Temporal reset/cut coalescing, paused render-attempt
  accounting and camera/scenario/resize lifecycle. GPU completion remains unknown
  even when the SDK encode callback acknowledges the reset serial.
- `fault_probe.gd`: four fresh debug processes with patch 0003's factory/enqueue
  faults. Compare the first failed frame against a changed Native reference and
  stale-image negative control before invoking the production recovery adapter.
- `frame_probe.gd`: actual scene HDR/depth/motion producer with patch 0004;
  full 1080p finite/sentinel readback, paused cut/toggle receipts, resize and
  orthographic/alpha/Canvas/Keep rejection. This native fixture passed; its status
  still labels motion/jitter conventions unverified and the image not presentable.
- `frame_motion_probe.gd`: draft moving-quad witness with independently rendered
  midpoint/endpoints, crossfade control, static HDR-to-sRGB calibration and exactly
  one attempted real render. ROI and margins are fixed in source. Parse and native
  execution are pending; the Mac transfer timed out. Do not call its intended
  comparisons a passing result.
- `gpu_probe.gd`: draft for patch 0006's explicitly requested command-buffer
  observation. It checks Spatial, Temporal reset GPU completion, interpolation
  epochs and observation retirement without changing Temporal receipts. It is
  not parsed or natively executed yet. The
  [engine guide](../../../tools/graphics/metalfx/README.md#optional-gpu-completion-observation)
  owns the status identities, clocks and whole-command-buffer timing limits.
- `triangle_query_probe.gd`: draft for patch 0005's bounded RD triangle-query
  backend. Its runner creates an isolated project and tests both argument-buffer
  and direct binding paths in fresh native processes. Portable compiled controls
  passed; actual Metal compilation, shader lowering and GPU readback remain open.

Keep the normal full product, its physical backend and audio/HID/effects activation
separate from these bounded fixtures. The owning plan retains moving-image,
presentation, latency, end-to-end performance and package gates.

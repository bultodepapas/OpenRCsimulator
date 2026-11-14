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

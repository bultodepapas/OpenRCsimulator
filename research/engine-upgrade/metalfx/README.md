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
  accounting and camera/scenario/resize lifecycle. Original status receipts are
  CPU acknowledgements. With 0019 and 0006, separate optional cases test conditional
  rejection/acceptance, resize fencing and a successful reset GPU completion in
  the unchanged observer generation. A native claim requires overall `ok=true`,
  `conditional_reset.status=tested`, its `gpu_completion.status=observed`, and
  `conditional_resize_fence.status=tested`; older engines deliberately skip them.
  All required cases passed on the clean 19-patch M1 editor.
- `fault_probe.gd`: four fresh debug processes with patch 0003's factory/enqueue
  faults. Compare the first failed frame against a changed Native reference and
  stale-image negative control before invoking the production recovery adapter.
- `frame_probe.gd`: actual scene HDR/depth/motion producer with patch 0004;
  full 1080p finite/sentinel readback, paused cut/toggle receipts, resize and
  orthographic/alpha/Canvas/Keep rejection. This native fixture passed; its status
  still labels motion/jitter conventions unverified and the image not presentable.
  With optional 0020, the native diagnostic-enabled case also matched its known
  viewport/base/mesh/material RIDs and retained the snapshot after producer Off;
  the diagnostic-Off case honestly skipped it. Require `observed`, `matches` and
  `retained_after_off` for that enabled claim, not just the fixture's overall pass.
- `alpha_scene_census.gd`: explicit debug-bridge query of the historical 0020
  snapshot against current mesh and MultiMesh resource candidates. Its walk and
  output are capped at 8,192 nodes and 64 candidates. Shared resources and scene
  changes prevent a unique historical-node or pixel-contribution claim. An R8 Home
  sample matched three NightKit light-sprite candidates in a truncated 35-entry
  alpha list; it was not a complete census or a flight proof.
- `alpha_motion_probe.gd`: 1080p moving opaque/alpha midpoint experiment using the
  separate research-only alpha-input patch. The Off control passed, while enabled
  output failed eight image gates. Full-ROI midpoint MAE was 0.096158 and 0.112968
  against 0.04 for its two cases; the latter was 0.0089285 from an approximate
  Temporal endpoint crossfade reconstructed from 8-bit LDR images. Composition
  is disabled throughout that experiment. This does not qualify transparent FG
  or establish a universal Apple API limitation.
- `settings_stall_probe.gd`: explicit Home/Graphics debug witness for the Settings
  confirmation window. Load it through `ResourceLoader.load(<absolute path>)`,
  call `install(app)`, then choose Temporal Quality through the ordinary UI.
  Its one-shot listener injects a 20-second main-thread delay after the real app
  listener; it never changes draft settings, readiness or the deadline. Query
  `snapshot(app)` after allowing the app to render. The native R9 trial preserved
  the confirmation interval and saved the choice. This tests CPU readiness and
  UI persistence, not GPU completion, OS presentation or cold-compilation time.
- `frame_motion_probe.gd`: moving-quad witness with independently rendered
  midpoint/endpoints, crossfade control, static HDR-to-sRGB calibration and exactly
  one attempted real render. ROI and margins are fixed in source. Checked parsing
  and native 1920×1080 execution passed on the original M1 after access recovered.
  It explicitly disables UPDATE_ONCE after frame completion and checks that idle
  root frames do not add SDK submissions. This bounded quad result does not
  establish flight-scene motion, final presentation or nonlinear HDR correctness.
- `gpu_probe.gd`: fixture for patch 0006's explicitly requested command-buffer
  observation. It checks Spatial, Temporal reset GPU completion, interpolation
  epochs and observation retirement without changing Temporal receipts. It is
  parsed and passed six native observation/lifecycle cases on M1. The
  [engine guide](../../../tools/graphics/metalfx/README.md#optional-gpu-completion-observation)
  owns the status identities, clocks and whole-command-buffer timing limits.
- `real_completion_probe.gd`: patch 0013's main-window real-render completion
  observer and capability-query fixture, with frame generation and Temporal Off.
  The native M1 API-validation run passed 3,589 checks at reported 1920×1080
  window and root-viewport sizes. It observed a pending callback across a
  generation 1→2 reset, followed by a stale callback and 29 fresh records without
  old-generation resurrection; Off and second-owner controls also passed. The
  receipt establishes bounded observer behavior, not changed pixels, display
  pacing or a performance result.
- `present_probe.gd` and `composition_probe.gd`: display-link controls,
  offscreen scene/UI composition and the actual SDK-pair presentation path.
  With the full 0001–0017 development stack, a bounded native M1 run reported one
  generated OS-presented drawable at 1920×1080 in final presenter generation 9,
  zero confirmed GPU failures and five ignored unrequested `NotEnqueued`
  callbacks. A synthetic real-frame duplicate is a separate control. Neither
  result establishes sustained performance, visual qualification or a public
  default. The [engine guide](../../../tools/graphics/metalfx/README.md#experimental-sceneui-composition-and-presentation)
  owns patch order, status scope and remaining limits.
- `triangle_query_probe.gd`: fixture for patch 0005's bounded RD triangle-query
  backend. Its runner creates an isolated project and tests both argument-buffer
  and direct binding paths in fresh native processes. Portable compiled controls
  and 39 native cases passed with patches 0001–0007 plus 0010. The earlier native
  negative battery exposed an empty-device finalization warning, retained in the
  dated evidence; 0010 fixes its queue-ordered fence signal.
- `denoised_query_probe.gd`: fixture for patch 0007's local-RD RT/denoising witness.
  It produces primary/reflected rays and guide textures, rasterizes D32F depth,
  then submits denoising first in a fresh graph using the previously submitted
  inputs. Producer samples and output have explicit finite-value checks. The
  loose analytic ROI and sentinel checks establish sanity. Checked parsing and
  both native binding modes passed with patches 0001–0007 plus 0010, without
  engine errors or warnings. Output includes SDK-required color-attachment usage.
  This is not OpenRC's scene RT consumer or a quality/performance comparison. The
  [engine guide](../../../tools/graphics/metalfx/README.md#experimental-rd-denoised-binding)
  owns the exact texture layout and bounded API contract.
- `rt_scene_probe.gd`: optional 0018 renderer-owned geometry/query prerequisite.
  It uses actual Horizon geometry and an Extra pilot mesh, with a CPU hit oracle.
  Checked parsing and nine fresh M1 cases passed: Off, ground, aircraft component,
  offscreen geometry, source update, raw-buffer escape, release and two unsupported
  shader/material controls. Enable `OPENRC_METAL_RT_SCENE=1` and
  `GODOT_METAL_TRIANGLE_QUERY=1` for enabled cases; use Forward+/Metal and run each
  case in a fresh process. This intentionally stalls the main RD graph. It produces
  no viewport lighting/denoised output and does not complete 13d1.
  The additional `OPENRC_RT_CASE=capture_instance_move` case queues an asynchronous
  readback and requires its callback to move an actual renderer instance inside
  the probe's flush. It checks the historical transform/hit and an independently
  CPU-checked fresh post-move query. It passed on M1, alongside aircraft and Off
  controls. These results are historical; the API does not revalidate instance
  transforms, material or liveness before returning a retained snapshot.

The opt-in application controller and its pure admission policy have separate
focused checks: the current candidates passed 89 and 517, respectively, on
Windows and the clean 0019 M1 editor. These checks do not establish presentation.
Complete native Home/Fly/pause/resume trials
execute Temporal, while full-flight FG qualification remains open. The
[engine guide](../../../tools/graphics/metalfx/README.md#completed-real-frame-observation)
owns the technical startup flags and observer contracts.

Keep the normal full product, its physical backend and audio/HID/effects activation
separate from these bounded fixtures. The owning plan retains moving-image,
presentation, latency, end-to-end performance and package gates. No scene-wide
RT viewport consumer or 13d1 completion is implied by these witnesses.

## File-hash correctness fixture

`sha256_probe.gd` checks FileAccess and incremental HashingContext against 12
independently computed SHA-256 vectors, including empty, block/chunk boundaries
and 1,000,000 bytes, plus a changed-byte negative. It requires a fresh absolute
output directory with an existing parent and writes only its fixture files there.
Use the checked runner and an isolated project/profile:

```sh
python3 tools/godot/run_checked.py --out-dir "$CHECKS" --label sha256-vectors \
  --timeout 120 --require-text 'SHA256_PROBE checks=25 failures=0' -- \
  "$EDITOR" --headless --path "$PROJECT" --audio-driver Dummy \
  --script "$ROOT/research/engine-upgrade/metalfx/sha256_probe.gd" -- \
  --out-dir="$NEW_ABSOLUTE_DIRECTORY"
```

Optional `--target=ABSOLUTE_PCK --target-sha256=EXPECTED_HEX` adds one check
and reports the file-hash call's elapsed microseconds; require 26 passing checks.
Use the same unchanged file and independently retained digest with both exact
editors, fresh outputs, a quiet host and repeated interleaved order. Record cache
conditions. This measures file hashing; frame times and package lifecycle need
their own measurements. The retained 1–19+21 editor passes all 25 vector controls.

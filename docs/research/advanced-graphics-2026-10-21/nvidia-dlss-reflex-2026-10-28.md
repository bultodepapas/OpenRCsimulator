# VQ-07: NVIDIA DLSS and Reflex source review

2026-10-28 · Primary-source review and local source inspection. No build,
rendered experiment, performance measurement or hardware qualification was run
for this report. The [native reconstruction evidence](../visual-quality-implementation/VQ-07/native-reconstruction-2026-10-24/README.md)
owns the existing results; the [graphics guide](../../../tools/graphics/native/README.md)
owns integration and reproduction commands.

## Baseline and priority

The local Windows/Vulkan candidate uses NVIDIA Godot commit
[`135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`](https://github.com/NVIDIA-RTX/godot/commit/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76),
the checked local patch stack, [Streamline 2.11.1](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.11.1)
(released 2026-04-21) and explicit DLSS preset K. A read of NVIDIA's official
`nvidia-pt-dlss` branch on 2026-10-28 returned the same commit, dated
2026-07-24; that does not make it equivalent to the official Godot beta.
Prior 1080p RTX 3090/driver 617.42 tests demonstrated bounded dispatch,
settings changes, failure recovery and an export. They did not establish moving
image acceptance, latency reduction, other hardware support or complete release
qualification.

The recommended order is: (1) camera-history and motion-data verification;
(2) SDK-selected mode and exposure diagnostics; (3) Reflex measurement and
identity/package checks; and (4) separately tested asset/import and engine
maintenance. Keep the known 2.11.1/K baseline while investigating each change.

## 1. DLSS history and temporal inputs

NVIDIA's [DLSS integration checklist](https://developer.nvidia.com/blog/how-to-integrate-nvidia-dlss-4-into-your-game-with-nvidia-streamline/)
(2025-01-30) calls for valid motion vectors, jitter and exposure, and a history
reset at discontinuous camera or scene changes. Its
[2.11.1 constants](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/include/sl_consts.h)
define `reset` for frames whose previous history is unrelated. In the locally
patched fork, the Forward+ DLSS caller sets `reset_accumulation = false`; its
[DLSS effect](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/servers/rendering/renderer_rd/effects/dlss.cpp)
maps that field to the SDK reset constant. This is a source-level gap, not proof
of a visible artifact in a particular shot. A future change needs an explicit,
per-viewport discontinuity signal for camera switches, teleports and scene or
flight resets, with the correct queued frame token. Do not reset continuously
for ordinary camera motion.

The [2.11.1 DLSS guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuideDLSS.md)
requires render-resolution color, depth and motion vectors, output-resolution
color, and consistent jitter and vector scaling. The fork declares normalized
motion-vector scale `(1, 1)`, non-jittered vectors and pixel jitter; these
declarations still need validation against the actual buffers and orientation.
The [earlier OpenRC shader audit](dlss-fsr-2026-10-24.md) identifies a possible
previous-frame mismatch for vegetation driven by the simulation clock. That is
an inference, not an observed DLSS defect.

For a controlled next check, use the same recorded scene, input, time, output
dimensions and camera sequence at actual **1920×1080**: Native/MSAA, DLAA and
DLSS Quality first, then Balanced/Performance where useful. Inspect distant
aircraft markings and attitude, rotating propellers, windy vegetation, water,
smoke, disocclusions, camera cuts and pause/restart. Inspect motion-vector and
jitter diagnostics where available, not just a settled screenshot. Preserve
the deterministic simulation clock and the existing [flight-log contract](../../FLIGHT-LOGGING.md).
Record GPU frame time and artifacts separately; the output of an SDK call does
not by itself prove temporal quality.

## 2. Presets, selected resolution and exposure

NVIDIA's [2.11.1 preset definitions](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/include/sl_dlss.h)
describe K as a transformer preset and the default for DLAA, Quality and
Balanced; M is the documented default for Performance. OpenRC deliberately
applies K to all exposed DLSS modes. On the recorded RTX 3090 setup, the
[controlled K comparison](../visual-quality-implementation/VQ-07/native-reconstruction-2026-10-24/README.md#follow-up-frame-ownership-and-preset-qualification--2026-10-25)
observed two Vulkan image-layout errors with automatic preset selection and
zero with K, without establishing the driver's internal root cause. Do not
switch Performance to M merely because it is the SDK default: test it as one
isolated candidate with the same mode, frame tape, resize sequence, SDK and
validation layer before any adoption. K's successful dispatch does not establish
a speed or image-quality advantage.

NVIDIA recommends querying `slDLSSGetOptimalSettings` for each output/mode;
its result includes optimal and supported input sizes. OpenRC's
[reconstruction policy](../../../app/render/reconstruction.gd) requests fixed
scales, while the fork queries multiple SDK modes and selects the closest valid
input size. The app's displayed policy and estimated dimensions do not prove
which mode and exact dimensions the SDK selected. A useful next diagnostic is
to report the actual selected SDK mode, input/output size and failure separately
from the saved request, then check all modes on 1080p, odd sizes and resize.
The existing bounded fallback remains important if no SDK mode matches.

The [2.11.1 guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuideDLSS.md)
states that absent an exposure tag, DLSS uses its automatic exposure; a correct
exposure texture is preferred when available. In the inspected local fork, a
Godot auto-exposure luminance RID makes the DLSS options set
`useAutoExposure=false`, but the dispatch tags color, depth and motion and does
not tag `kBufferTypeExposure` or add it to the callback resource list. Current
app source uses scripted sky adaptation; this review did not establish that the
conditional Godot camera-auto-exposure path is active during flight. Audit it
before claiming a failure or changing behavior. If a future scene uses it,
verify the meaning, scale and lifetime of a proper exposure multiplier, then
compare HDR day/night transitions with correct graph synchronization. Do not
substitute Godot's average-luminance texture for exposure by assumption.

## 3. Reflex: integration and measurement

NVIDIA's [2.11.1 Reflex guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuideReflex.md)
requires an initial mode setting and, when their features are supported, Sleep
and PCL markers even when low-latency mode is Off. PCL support and actual
`lowLatencyAvailable` are distinct: the latter controls whether Reflex options
should be available in the UI. The [PCL guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuidePCL.md)
describes markers independently of GPU vendor. The headers declare
[Reflex state/options](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/include/sl_reflex.h)
and [PCL state/options](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/include/sl_pcl.h)
non-thread-safe; Sleep and marker calls are declared thread-safe. The local
[synchronization patch](../../../tools/graphics/native/reflex_sync.patch) places
state/options after render synchronization and keeps each queued draw's token.
The existing Off → On → Boost → Off checks show SDK and marker progress on one
host; they do not demonstrate a latency reduction.

NVIDIA's guide also requires the driver-controlled flash trigger when reported.
The [local evidence](../visual-quality-implementation/VQ-07/native-reconstruction-2026-10-24/README.md#follow-up-usable-nvidia-package-and-reflex-integration--2026-10-28)
records that this path is absent. A separate implementation and the
[Reflex verification workflow](https://developer.nvidia.com/rtx/streamline/get-started)
are needed to assess marker placement and latency in Off, On and Boost. Measure
matched GPU-limited and CPU-limited runs, frame pacing and latency rather than
claiming responsiveness from a successful Sleep. A mouse/flash measurement does
not by itself measure a physical RC transmitter-to-display path.

The [Streamline initialization guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuide.md)
describes an NVIDIA application ID or appropriate engine identity, project ID,
runtime feature checks and plugin requirements. The pinned
[NVIDIA fork](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/drivers/streamline/streamline_context.cpp)
contains the inherited `applicationId = 0x90d07004`; this review did not establish
that it identifies OpenRC. Verify identity and release packaging before
distribution rather than inventing an ID. The local patch disables Streamline
OTA plugin loading for reproducible dependencies. NVIDIA documents OTA as a
compatibility mechanism for newer hardware, so any future OTA policy needs its
own identity, security, reproducibility and GPU validation rather than a silent
change to the tested package.

## 4. GPU and engine boundaries

NVIDIA's [GPU comparison](https://www.nvidia.com/en-gb/geforce/graphics-cards/compare/)
lists Super Resolution, DLAA and Ray Reconstruction for RTX 20/30/40/50;
DLSS Frame Generation is listed for RTX 40/50, and Multi Frame Generation for
RTX 50. The RTX 3090 is an RTX 30 card: it is eligible for SR/DLAA and Reflex
but cannot establish NVIDIA Frame Generation support. NVIDIA describes
[Ray Reconstruction](https://www.nvidia.com/en-ph/geforce/news/nvidia-dlss-3-5-ray-reconstruction/)
as useful for ray-traced effects, not raster-only scenes. GPU family is not an
availability test: continue to use the SDK's actual adapter and driver result.
The current product does not enable Frame Generation, Ray Reconstruction or
path tracing; adding DLLs alone does not implement those features. Each would
need its own renderer inputs, UI, latency, compatibility and validation work.

Official [Godot 4.8 beta1](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/)
(2026-10-15) has no DLSS scaling mode in its
[pinned Viewport API](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/Viewport.xml).
The separate [custom-upscaler PR](https://github.com/godotengine/godot/pull/114670)
was open on 2026-10-28 and is not an installed DLSS implementation. The
NVIDIA fork is a distinct 4.8-dev source; editor/template matching, platform
and companion qualification remain independent of the numeric version.

One concrete compatibility gap is maple alpha coverage: the official beta
supports [coverage-preserving mip generation](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/ResourceImporterTexture.xml),
while the [pinned NVIDIA fork's importer](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/editor/import/resource_importer_texture.cpp)
lacks that option. OpenRC's
[GDU-11a evidence](../engine-upgrade/GDU-11/README.md) measured the beta path;
it cannot be transferred to a fresh fork import. A future isolated comparison
could backport the upstream importer or evaluate a pre-mipmapped DDS: Godot's
[4.7 image guide](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)
documents loading DDS mipmaps. Neither alternative is qualified on this fork;
verify imported mip data, alpha coverage, renderer behavior and 1080p moving
views before changing the accepted asset pipeline. Keep engine import caches
and generated outputs separate.

## Version policy

NVIDIA published [Streamline 2.14.16](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.14.16)
on 2026-10-16 with a general stability note. It is not an automatic improvement
for this fork: the [controlled local comparison](../visual-quality-implementation/VQ-07/native-reconstruction-2026-10-24/README.md#follow-up-options-sdk-comparison-and-shutdown--2026-10-25)
rejected it after additional Vulkan device/private-data initialization errors.
Investigate those exact errors in an isolated build, with matching headers and
DLL hashes, feature/extension requirements, validation logs and a single
dependency change. Re-run editor and exported flows before considering a new
pin; do not infer a fix from the release label or replace DLLs independently.

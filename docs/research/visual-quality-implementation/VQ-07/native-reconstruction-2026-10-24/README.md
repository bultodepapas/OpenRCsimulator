# VQ-07d: native FSR 3.1 and DLSS experiment

2026-10-24. The owner requested implementation after the
[DLSS/FSR investigation](../../../advanced-graphics-2026-10-21/dlss-fsr-2026-10-24.md).
The RTX 3090 was the test device for this report; this does not qualify other GPUs.
[Build and launch instructions](../../../../../tools/graphics/native/README.md).

## Implemented scope

The application discovers separate provider capabilities, preserves requested
preferences when a provider is unavailable, and reports the actual provider and
scale. It supports FSR2, FSR 3.1 Native AA/85%/Quality/Balanced/Performance, and
DLAA/DLSS Quality/Balanced/Performance. Native remains the default. Temporal modes
replace MSAA; Native restores the saved MSAA setting. DLSS has no added NIS
sharpening. FSR3 backend failures return the application to full-resolution Native.

The opt-in Windows/Vulkan engine integrates the NVIDIA Godot fork at
`135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`, Streamline 2.10.0 and a locally built
FidelityFX SDK 1.1.4 runtime (FSR 3.1.4). The AMD source archive is SHA-256 pinned;
the patched runtime is locally compiled and unsigned, not AMD's signed prebuilt
DLL. Its SHA-256 is
`5c6aba3469e0e2170c35ce900e510ad3649500fca10139d4489490d634bbca8e`; the build
receipt is `.tools/advanced-rendering/fidelityfx-native-build/fidelityfx-runtime-receipt.json`.
The SDK patch changes the Vulkan luma-history image qualifier from `rgba8` to
`rgba16f` to match its `R16G16B16A16_FLOAT` allocation and adds the stencil aspect
to barriers only for resources marked as stencil targets. The upstream report for
the luma format mismatch remains [open](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/issues/161).
Build receipts retain executable/runtime/integration and toolchain identities;
runtime licenses accompany the DLLs. Streamline automatic plugin downloads are
disabled.

FSR3 receives linear HDR color, finite reverse-Z depth, decoded velocity, jitter
and an R8 reactive mask. Copying the mask preserves Godot's alpha swizzle, which
would otherwise be lost when FFX creates its own VkImageView. FFX supplies its own
exposure normalization: Godot's average-luminance texture is not an exposure
multiplier. Context teardown drains submitted work before releasing native SDK
resources. Render-graph callbacks declare their imported image usage.

This is a Godot **4.8-dev experiment**, not a production engine upgrade. The
production 4.7.2 engine and aircraft identities remain unchanged. Candidate
presentation identities are explicitly regenerated through the existing source
pipeline, with source/hash checks retained. No simulation kernel change or golden
re-recording is included. Frame generation, ray reconstruction and FSR4 are not
enabled.

## Test environment and isolation

Windows, RTX 3090 24 GiB, driver 617.42, Vulkan 1.4.351, Ryzen 9 5900X, 64 GiB RAM.
MSVC 14.5, Windows SDK 10.0.26100.0, Python 3.11.9, SCons 4.10.1.
Vulkan validation layers 1.4.366 were enabled per process, including synchronization
validation. No global driver/layer settings were installed.

The isolated candidate under ignored `tmp/native-reconstruction-candidate/` has two
source pins: its base app/assets snapshot is commit
`343be4b0bba007ec4295e7da408220a0577d97e1`, and its eight reconstruction app
integration files come from commit
`7bfbe2ec071bd142c5b1acf7350fff634ec31f16`. Preparation and package checks read
those pinned Git blobs instead of the changing working tree, isolating concurrent
aircraft authoring and app edits. Its strict presentation pin is 4.8.0;
`presentation-engine-receipt.json` records the generator and regenerated six-family
source closure. Rendered runs use the existing debug bridge on port 47941 and an
isolated user profile. Images and full logs remain ignored.

## Verification recorded so far

| Check | Result |
| --- | --- |
| Stock 4.7.2 reconstruction policy | 94 checks, 0 failed, including provider fallback and runtime-failure restoration |
| Stock advanced graphics settings / preferences | 113 / 88 checks, 0 failed |
| Native graphics settings | 122 checks, 0 failed |
| Custom editor import | Passed, 805 imported files |
| Custom editor reconstruction policy | 93 checks, 0 failed; stock-only absence assertion is inapplicable |
| Custom editor golden flights | Four flights passed existing tolerances; maximum position difference 4.26e-14 m. Tolerance success is not byte-identical engine qualification or physical validation. |
| Candidate presentation source proofs | 97 checks, 0 failures |
| Candidate aircraft customization | 159 checks, 0 failures |
| FSR3 real-GPU dispatch | Session `20261024-213237-47941`: all five FSR3 modes dispatched; 771 dispatches across 10 contexts, SDK version 3.1.4; `last_return_code=0` and `backend_failed=false`. The SDK-specific depth/format diagnostics no longer occurred; this does not erase the separate engine baseline findings. |
| DLSS/DLAA mode and resize checks | All four modes and resize assertions passed. Six `VUID-vkCmdDraw-None-09600` messages remain in the later Performance/resize sequence; this is not a clean validation pass. |
| Native baseline validation | 10 write-after-write reports on the 272-byte buffer and 7 Texture RID reports on the known high-reflection-probe path; retained as baseline findings. |

Checked-runner receipts are under `tmp/native-reconstruction-candidate/checks/`
and `tmp/godot-checks/native-candidate-20261024/`. Builds and receipts are under
`.tools/advanced-rendering/`. GPU timings collected while compilation or validation
layers are active are not performance evidence.

## Validation findings

Earlier sessions exposed a null Win32 HINSTANCE, duplicate Vulkan 1.2 feature
structures, a Volk function-pointer declaration mismatch, and DLSS callback
stage-mask/image-clear validation errors. Those implementation issues were fixed;
the later FSR3 run completed all five modes with 771 actual dispatches. The current
DLSS/DLAA run passes mode changes, resize and assertions, but still has six
`VUID-vkCmdDraw-None-09600` reports in the Performance/resize sequence. The Native baseline's buffer finding and the [known High reflection-probe lifetime finding](../planar-lake-2026-10-22/README.md#engine-lifetime-attribution-and-session-context-2026-10-22) are recorded separately above and are not attributed to
the upscaler providers.

## DLSS residual image-layout finding

The final diagnostic editor run (`20261024-213808-47941`) logs every distinct
app-tagged native image by role and context. The first failing pair,
`0x84c600000084c6` and `0x84c900000084c9`, does not match any tagged color,
output, depth or velocity image. The preceding Performance context tagged output
`0x84720000008472`. The validation layer reports GENERAL expected while the two
untagged images are still UNDEFINED. Six such reports remain; shutdown returned
`crash=null`, `leaked_objects=0`. Those shutdown counters do not include the
separately reported seven Texture RIDs.

The [pinned Streamline DLSS implementation](https://github.com/NVIDIA-RTX/Streamline/blob/v2.10.0/source/plugins/sl.dlss/dlssEntry.cpp)
has its cached-output allocation disabled, and its motion-vector image is used
only when camera motion is absent; this integration supplies camera motion.
[NGX setup](https://github.com/NVIDIA-RTX/Streamline/blob/v2.10.0/source/plugins/sl.common/commonEntry.cpp)
does not expose Vulkan memory allocation hooks. The evidence points to an opaque
SDK/NGX internal first-use transition, but does not prove its exact owner.
No blind transition or validation-message suppression is applied. The diagnostic
and reproduction scripts are retained in the source integration.

DLSS is therefore **experimental and not qualified for release**. Use FSR3 or
Native for this trial when the affected sequence matters. FSR3 also remains an
experimental engine integration pending the broader gates below. The shipped
NVIDIA DLSS DLL is version `310.5.0.0`; these results do not establish support for
newer DLSS model revisions.

## Exported Windows trial

`tmp/native-reconstruction-export/` contains the release executable, PCK, runtime
DLLs, licenses, separate-profile launchers and hash receipts (33 managed files).
The checked PCK export passed in 31.86 seconds with no error or warning records.
The executable SHA-256 is
`22f266b9ed9b60d3b8edf33f2f140e097901518ac535c8e5bdb92e68329063aa`;
the PCK SHA-256 is
`42b9e869119ab7e0cd5f3c73256ef2ca2646295e6ff24753d18b5447524c6def`.
[Machine-readable verification](verification.json) retains the build identities,
checked-run outcomes, capture manifests and image hashes without tracking images.

Exported captures use the existing `--capture --scripted --view=closeup --t=3.0`
route, fullscreen 1920x1080, High, Dummy audio and isolated APPDATA. These tests
run without Vulkan validation layers; the separate editor validation findings
above still apply. This static scripted pose is not motion-quality qualification.

| Exported capture | Result |
| --- | --- |
| Native baseline | Exit 0, 1920x1080, full scale, 16.532 s |
| FSR3 Quality repeat | Exit 0, 1920x1080 output, nominal 1280x720 input, 36 successful SDK dispatches, one context, last return 0, 17.015 s |
| DLSS Quality | Exit 0, 1920x1080 output, nominal 1280x720 input, mode 6, no extra sharpening, 16.937 s |
| FSR3 Quality, new empty application profile | Exit 0, 1920x1080, 36 successful dispatches, no verbose flag, 24.89 s; driver disk cache was not reset |
| Missing AMD DLL fixture | Requested FSR3 Quality retained; effective Native at scale 1, `fsr3_unavailable`, saved MSAA restored; exit 0, 15.032 s |

Native, FSR3 repeat and DLSS capture logs each contain 44 warning records
(loader/texture format warnings); the missing-runtime case has one additional
expected fallback warning. All four have zero engine error records. Capture PNG
hashes match their manifests, and actual viewport size is verified separately
from the requested window size. These durations include startup and shutdown,
and are not FPS or GPU cost measurements.

The first exported FSR3 run saved its 1080p image and manifest (36 successful
dispatches) but stalled during shutdown and was killed by the checked runner at
360 seconds. LLDB was attached after the stall was observed; the main thread was
waiting on a condition variable, consistent with the render-server worker join.
There was no modal dialog. A subsequent Native run, FSR3 repeat and another
FSR3 run with a fresh application profile all exited normally. The fresh-profile
run used the original non-verbose arguments; it did not reset the driver disk
cache. Its log contained zero error/warning records, which does not replace the
separate verbose/layer findings. The initial failure is retained as an intermittent first-run/shutdown
qualification finding; it has not been explained or declared fixed.

## Remaining qualification

The exported provider/fallback capture checks pass, but the initial shutdown
stall and the DLSS Vulkan layout finding keep release qualification open. No FPS
improvement or all-hardware compatibility claim is made from this RTX 3090 session. Cross-vendor/driver/platform qualification, arbitrary
camera-cut history reset, animated shader motion, smoke/water/vegetation motion
quality, stereo/XR, latency and matched GPU cost remain separate gates. The
independent [Godot upgrade gates](../../../../plans/godot-4.8-upgrade.md) remain
open.

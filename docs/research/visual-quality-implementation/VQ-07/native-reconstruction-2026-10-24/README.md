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
`dca756599c0b83f6a9f75d53973046181268555b3b39aecbfd236775c5f07d42`; the build
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

The stable application/asset snapshot is commit
`343be4b0bba007ec4295e7da408220a0577d97e1` under ignored
`tmp/native-reconstruction-candidate/`, with the reconstruction integration overlaid.
This isolates concurrent aircraft authoring. Its strict presentation pin is 4.8.0;
`presentation-engine-receipt.json` records the generator and regenerated six-family
source closure. Rendered runs use the existing debug bridge on port 47941 and an
isolated user profile. Images and full logs remain ignored.

## Verification recorded so far

| Check | Result |
| --- | --- |
| Stock 4.7.2 reconstruction policy | 94 checks, 0 failed, including provider fallback and runtime-failure restoration |
| Native graphics settings | 122 checks, 0 failed |
| Custom editor import | Passed, 805 imported files |
| Custom editor reconstruction policy | 93 checks, 0 failed; stock-only absence assertion is inapplicable |
| Custom editor golden flights | Four flights passed existing tolerances; maximum position difference 4.26e-14 m. Tolerance success is not byte-identical engine qualification or physical validation. |
| Candidate presentation source proofs | 97 checks, 0 failures |
| Candidate aircraft customization | 159 checks, 0 failures |
| FSR3 real-GPU dispatch | Session `20261024-213237-47941`: all five FSR3 modes dispatched; 771 dispatches across 10 contexts, SDK version 3.1.4; last reported validation count was 0. |
| DLSS/DLAA mode and resize checks | All four modes and resize assertions passed. Six remaining Vulkan validation messages are still being traced, so this is not yet a clean validation pass. |
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
validation messages under investigation. The Native baseline's buffer and
reflection-probe findings are recorded separately above and are not attributed to
the upscaler providers.

## Remaining qualification

The Windows export/package gate remains open until the owner records final export
results. No FPS improvement or all-hardware compatibility claim is made from this
RTX 3090 validation session. Cross-vendor/driver/platform qualification, arbitrary
camera-cut history reset, animated shader motion, smoke/water/vegetation motion
quality, stereo/XR, latency and matched GPU cost remain separate gates. The
independent [Godot upgrade gates](../../../../plans/godot-4.8-upgrade.md) remain
open.

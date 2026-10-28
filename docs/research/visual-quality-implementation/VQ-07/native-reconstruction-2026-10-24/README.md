# VQ-07d: native FSR 3.1 and DLSS experiment

**Current DLSS update (2026-10-25):** explicit preset K now passes the tested
1080p mode/resize sequence with Vulkan synchronization validation on the RTX 3090.
Automatic preset selection still reproduces the NGX finding. See
[frame ownership and preset qualification](#follow-up-frame-ownership-and-preset-qualification--2026-10-25)
for the scoped workaround, export proof and remaining limits.

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
`135dff3887a3d2ccf45cafbd9bdffa7b718e1e76`, initially Streamline 2.10.0 and a locally built
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

## Follow-up: options, SDK comparison and shutdown — 2026-10-25

The current experiment pins Streamline **2.11.1**, including its matching headers
and complete release runtime; `nvngx_dlss.dll` reports 310.6.0.0. Header hashes are
recorded and must match between editor and export template. This retains the
documented SR/Vulkan lifecycle fixes without accepting the additional initialization
errors observed with 2.14.16. It does **not** fix the remaining 09600 finding.

The controlled game runs used the same candidate and mode/resize smoke sequence:

| Runtime | Observed validation result | Decision |
| --- | --- | --- |
| 2.10.0 | Six 09600 image-layout errors in one cycle, ten baseline buffer write hazards | Baseline |
| 2.11.1 | Ten reported 09600 errors over two cycles, ten baseline buffer write hazards | Current experimental pin; not a clean DLSS validation pass |
| 2.14.16 | Same reported 09600 count plus `vkCreateDevice` 01387 and `vkCreatePrivateDataSlot` 04564 startup errors | Rejected for this fork |

The layer's repeated-message limit can cap counts; ten reports are not evidence of
an improvement over six per cycle. 2.14.16 names the affected images
`nv.ngx.dlss.resource`, inside `nv.ngx.dlss.Evaluate`, distinct from the app's
tagged input/output images. It requests `VK_NV_low_latency2` without its required
present-ID extension and creates private-data slots without the feature enabled.
No guessed transitions on SDK-owned image handles were added. 2.10.3 was reviewed
but not built/tested: its cited fix concerns frame generation.

Primary references: [2.11.1 release](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.11.1),
[SR/Vulkan changelog](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/changelog.txt),
[2.14.16 release](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.14.16),
[2.14.16 changelog](https://github.com/NVIDIA-RTX/Streamline/blob/v2.14.16/changelog.txt),
[frame-based resource tagging](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuide.md#29-tagging-resources).
The fork's graph callbacks read a mutable global frame token. Migrating deprecated
tag calls safely requires retaining the corresponding token across the asynchronous
render queue; a direct API-call substitution is not included.

`shutdown_thread.patch` follows [Godot PR 123391](https://github.com/godotengine/godot/pull/123391):
after the rendering worker stops, the main rendering device becomes current on
the calling thread before display-server destruction. The unpatched minimal
Native control with a separate render thread completed its frames, then failed
with the finalize-thread guard and exit 3221226505. The patched control completed
192 frames and exited zero in 19.14 s with zero errors (two layer-loader warnings
and the engine's experimental-thread warning). The before run also used 2.14.16
and an earlier fixture with a camera ordering issue; this is evidence for the
specific reported ownership defect, not a controlled attribution of every other
diagnostic or the earlier intermittent export hang.

The corrected [minimal reproducer](../../../../../tools/graphics/native/repro/README.md)
removes game assets, disables extra NIS sharpening and explicitly selects AA.
With 2.11.1, DLSS completes all six phases/384 frames and exits zero in 23.781 s,
but produces two 09600 errors. No baseline buffer hazard occurs in that scene.
The checked runner therefore correctly rejects its Vulkan validation result.

The final FSR3 game run (`20261025-070104-47942`) exercises all five modes and
resize, restores Native MSAA, then switches back to FSR3 Quality before closing.
It records 11 contexts, 636 successful dispatches, version 3.1.4 and return code
zero; no backend failure or FSR3-specific VUID occurs. Stop reports no crash or
leaked objects. The log retains ten baseline buffer hazards, the known seven
Texture RIDs, 43 RGB8 conversion warnings and two layer-loader warnings.

Settings now explain requested versus active presets, estimated input/output
sizes, unavailable providers and preserved FSR sharpening. Native and DLSS disable
the FSR-only slider. Tests originally assumed DLSS was always unavailable and
VSync was the final line; those assumptions failed on the custom engine and were
corrected. Stock settings pass 120 checks and native settings pass 129, both with
zero engine errors. Native reconstruction policy passes 94 checks; stock's extra
absence assertion is inapplicable. No performance benefit is inferred from these
functional checks or validation-layer timings.

The current candidate keeps the original base and three integration files at
`7bfbe2ec071bd142c5b1acf7350fff634ec31f16`; four UI/policy files use
`91b67d620c1adf3f470dddba33ace63f3fb6851c`, and the settings test uses
`ba42e49b7b814a86f0c29f5d7d29f2239a002e03`. Every overlay has its own source and
prepared hash. Raw follow-up evidence remains under ignored
`tmp/native-reconstruction-20261025/`; the dated verification record identifies
the retained logs and final package.

### Final package and 1080p checks

The updated package contains 34 managed files with matching editor/template/SDK
receipts. `Graphics Options.cmd` opens Home with an isolated profile for Settings
→ Graphics; the other three launchers retain direct-flight presets. English and
Spanish settings screenshots were reviewed at actual 1920 × 1080. FSR3 Quality
was selected and kept through the menu; DLSS Quality preview correctly disables
FSR sharpening. Images remain outside Git.

| Exported capture / lifecycle | Result and elapsed wall time |
| --- | --- |
| FSR3 Quality, fresh profile 1 | Exit 0, 26.469 s |
| FSR3 Quality, same profile | Exit 0, 17.468 s |
| FSR3 Quality, fresh profile 2 | Exit 0, 29.281 s |
| Native | Exit 0, 22.641 s |
| DLSS Quality | Exit 0, 29.282 s |

All five complete with zero engine error/warning records in their non-verbose,
non-validation-layer runs. PNG hashes match manifests; actual output dimensions
are 1920 × 1080 and provider receipts match requests. Each FSR3 capture records
36 successful dispatches with no backend failure. These are startup/render/exit
checks, not FPS measurements or a claim that the original intermittent stall is
fixed. Profile resets did not clear the driver cache.

An initial Home check forced exit after 240 frames while the intro was still
loading resources asynchronously; another forced exit after 20 frames produced
more preload errors. Inspection confirmed those resources were already in the
PCK. Repeating with a required AppRoot load marker and 1800 frames at a 60 FPS
cap completed in 42.531 s, exit 0 and zero errors, without changing the package.
Its verbose log records 47 warnings: 45 RGB8 conversions, one loader message and
**121 ObjectDB instances retained at exit**. The editor Home session reported zero
leaked objects. The exported Home lifetime finding is not attributed to FSR3 and
remains a separate qualification issue; this is not a warning-free shutdown pass.
Early forced-exit logs are retained separately;
premature cancellation does not establish missing package assets.

[Verification identities and results](verification-2026-10-25.json) retain both
failed investigative checks and final passes. DLSS Vulkan validity, the original
intermittent shutdown, temporal motion quality and other GPUs remain open gates.

## Release hardening: resource lifetime and buffer synchronization — 2026-10-25

Three additional engine patches address reproduced defects. The production
4.7.2 pin, application candidate, FSR 3.1.4 runtime and Streamline 2.11.1 remain
unchanged. Editor and release-template receipts include each patch hash.

| Isolated comparison | Before | After |
| --- | --- | --- |
| Exported Home, AppRoot load completed before exit | 121 RefCounted objects with reference count zero | Zero leaked ObjectDB instances, exit 0, zero errors |
| Four reflection-probe worlds created and freed | 28 Texture RIDs retained | Zero Texture RIDs retained, exit 0, zero validation errors |
| ColorRect followed by an empty CanvasLayer, 16 frames | Ten reported 272-byte buffer write hazards | Zero validation errors, exit 0 |

`load_token_lifetime.patch` is the proposed
[Godot LoadToken fix](https://github.com/godotengine/godot/pull/121025), still open
at review time. It deletes tokens whose final reference is released, after the
task's last access, and retains a guard while nested completion still needs the
task. The first patched Home check uses the same packed game and SDK as the
baseline, changing the template executable; it completes in 46.515 s. RGB8
conversion/loader warnings and three orphan StringNames remain. Zero ObjectDB
instances does not mean every diagnostic has disappeared.

`reflection_atlas_lifetime.patch` reuses the merged
[Godot color-buffer fix](https://github.com/godotengine/godot/pull/124743), commit
`29d351f9eb0dd7582469ad38e215e9902204df12`, already retained by the
[lake investigation](../planar-lake-2026-10-22/README.md). The four-world comparison
was rerun on this 4.8-dev fork; the earlier 4.7 backport evidence was not treated
as qualification of this engine.

`buffer_write_sync.patch` is a local render-graph fix. Frame reset clears command
indices while retaining resource usage and prior-frame stages. Two consecutive
COPY_TO uses could therefore omit the memory barrier. The correction includes
the retained stages when deciding whether a buffer write requires a barrier.
Its scope is buffers; texture-slice and acceleration-structure rules are unchanged.
[Khronos's synchronization guide](https://docs.vulkan.org/guide/latest/synchronization_examples.html)
requires a memory dependency for write-after-write hazards. The standalone
[canvas regression](../../../../../tools/graphics/native/repro/README.md#canvas-buffer-synchronization-regression)
reproduces the game's same buffer size and hazard without any 3D or reconstruction
provider. A preliminary raw-buffer fixture produced no error and was rejected
as a reproducer. Layer repeat limits still apply to the baseline count.

The final rendered FSR3 session (`20261025-075411-47942`) exercises all five
presets, window resize, return to full-resolution Native with saved MSAA, then
FSR3 Quality active during exit. It records 11 contexts and 698 successful
dispatches, SDK version 3.1.4, return code zero, no backend failure, no engine or
Vulkan error records, no leaked ObjectDB instances and no Texture RID warning.
Loader and RGB8 conversion warnings remain. This supersedes the earlier baseline
buffer-hazard and reflection-texture findings for this tested sequence.

DLSS investigation also traced callback ownership against the pinned
[Streamline guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuide.md).
Callbacks execute at render-graph end. Shared parameters are overwritten for
multiple views; the mono draw path serializes parameter use, but token creation
after enqueue can overlap evaluation. A future correction must generate/capture
the SDK-owned token after rendering sync and before draw enqueue, carry it with
per-callback parameters, and use it consistently for constants, tags and evaluation.
Simply copying the pointer later or renaming the tag API does not establish safe
ordering. This is a source-level finding, not a demonstrated cause or fix for the
remaining NGX image-layout errors. Stereo/XR stays unsupported.

The final DLSS minimal run still emits two 09600 errors and is correctly rejected
by the checked runner despite completing all six phases and exiting zero.
The rebuilt 34-file package passes receipt/source preflight. Home exits zero
with no error records in a fresh profile (42.75 s) and a warm repeat (40.28 s).
Neither retains the former zero-reference LoadTokens. The fresh run does retain
four different objects: AudioStreamMP3, AudioStreamPlaybackMP3, AudioStreamWAV and
AudioStreamPlaybackWAV, each with one reference. The warm repeat retains none.
This intermittent audio shutdown finding remains open; the first isolated
zero-object Home result is not generalized to every exit. All runs use the Dummy
audio driver. No rendering or audio diagnostics are suppressed.

Two final exported FSR3 Quality captures at actual 1920 × 1080 complete with
zero errors/warnings: fresh application profile 24.64 s, warm repeat 17.17 s.
Each receipt reports FSR3 active, no fallback/failure, version 3.1.4 and 36
successful dispatches. PNG hashes match the manifests; the fresh capture was
visually inspected. Native's separate-render-thread control also completes its
192 frames and shutdown with zero errors (15.89 s). These elapsed times describe
lifecycle checks, not rendering performance. Images and raw logs remain ignored.

[Hardening verification](verification-hardening-2026-10-25.json) records package
identities, all 34 verified managed files, the controlled before/after checks,
successful game/export runs and failed investigative checks. FSR3's tested
rendering sequence now passes Vulkan validation. Release qualification still
requires the DLSS error investigation, the intermittent export/audio shutdown
findings, temporal-quality and long-session testing, other GPUs/drivers, and the
separate Godot engine-upgrade gates. The production engine remains 4.7.2.

## Follow-up: frame ownership and preset qualification — 2026-10-25

The current application and prepared package explicitly select **DLSS preset K**.
This supersedes the earlier automatic-preset recommendation for this trial.
The same six-phase minimal case with Streamline 2.11.1, RTX 3090 and driver
617.42 reports two 09600 errors with automatic selection and zero with K.
Each case completes 384 frames; the instrumented backend records 360 successful
evaluations, six contexts and frame ID 384. NVIDIA's
[versioned header](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/include/sl_dlss.h)
describes K as a transformer preset and generally recommends it over J. The
test changes only the preset; it does not establish an internal NGX root cause,
a universal driver fix, or a performance improvement. F/J are available only as
reproducer controls and were not qualified.

`dlss_frame_lifecycle.patch` retains the simulation token and numeric frame ID
when enqueueing a draw. A render-thread slot carries that identity into an owned
callback parameter copy. Constants, resource tags and evaluation use the same
token; execution rejects a recycled token. Frame-based tagging is explicitly
enabled, following the [Streamline frame contract](https://github.com/NVIDIA-RTX/Streamline/blob/v2.11.1/docs/ProgrammingGuide.md#210-frame-tracking).
The fixed-FPS early return also advances tokens. The earlier shared callback
parameters and global-token reads are removed. These repairs alone still
reproduce the two errors with automatic preset selection.

The native status API records successful SDK dispatches and latches failures.
The application then restores Native at full scale and the saved MSAA, retains
the requested preset and exposes the failure reason in English/Spanish.
Failed output initialization and rejected graph callbacks also latch failure;
rejected callbacks release their payload. No diagnostics are suppressed.

| Check | Observed result |
| --- | --- |
| Stock policy / graphics settings | 103 / 120 checks, zero failed |
| Custom-engine policy / isolated graphics settings | 102 / 120 checks, zero failed; stock-only absence assertion is inapplicable |
| Default-preset minimal case, separate thread and fixed FPS | 360 evaluations, two 09600 errors; correctly rejected by checked runner |
| Preset K, identical minimal case | 360 evaluations, zero engine/Vulkan errors; loader and experimental-thread warnings remain |
| Native control, separate thread and fixed FPS | 192 frames, zero errors |
| Full game, preset K, two mode/resize smoke cycles | 943 evaluations across 15 contexts; zero engine/Vulkan errors, no backend failure, clean shutdown with zero leaked ObjectDB instances |
| Real failure recovery | Deliberately requesting scale 0.1 in an isolated Home session cannot match a DLSS mode. Backend code 25 is recorded; effective Native returns to scale 1 and 4× MSAA while the saved request remains DLSS Quality |
| Exported DLSS Quality, 1920×1080, fixed FPS | 32 evaluations, no fallback, zero engine errors/warnings, normal exit; image hash matches its manifest |
| Exported Home launch/exit | Zero engine errors/warnings and normal exit |
| Package integrity | All 34 managed files match their hashes; editor/template source, SDK and patch receipts agree |
| Fresh clone with exact tool overlay | Seven offline tests pass; all 27 affected upstream files accept the real patch stack from pristine source and a second application is identical |

Rendered validation uses the editor with the Khronos layer and synchronization
validation observed in its log. The exported capture requested the same layer
environment, but its release log does not identify layer activation; that export
proves rendering/backend/lifecycle behavior, not separate Vulkan qualification.
The 1080p menu and exported capture were visually inspected. These are static
views, not motion-quality acceptance or GPU benchmarks.

The first candidate update imported a newer complete settings file whose camera
dependency was absent in the pinned snapshot. Its test failed and is retained.
Preparation now overlays only the DLSS message/translation and failure policy,
records source and final hashes separately, and rejects unexpected edits.
The corrected settings test and final rendered run pass. The patch builder also
reconstructs overlapping patches from the verified archive before changing live
sources; offline tests cover drift rejection, repeat builds and Windows endings.

### Godot 4.8 assessment

The NVIDIA source already reports [4.8-dev](https://github.com/NVIDIA-RTX/godot/blob/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/version.py).
Official [4.8 beta1](https://github.com/godotengine/godot-builds/releases/tag/4.8-beta1)
does not add DLSS to its [Viewport scaling modes](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/scene/main/viewport.h#L97),
and the [custom-upscaler API PR](https://github.com/godotengine/godot/pull/114670)
remains open. For this game, maintaining the existing NVIDIA 4.8 integration is
less work than porting it to 4.7.2 or replacing it with official 4.8 beta1. It
does not remove the separate engine-upgrade acceptance gates.

[Verification identities and results](verification-dlss-2026-10-25.json) retain
the failed controls, clean K run, callback/fallback evidence and package hashes.
Raw logs and images stay under ignored `tmp/dlss-implementation-20261025/` and
the named bridge sessions. The automatic-preset NGX finding remains reproducible;
the K workaround is accepted only for the recorded hardware and tested sequences.
Cross-device/driver, camera-cut resets, motion quality, long-session behavior,
latency and matched GPU cost remain open. Frame generation and ray reconstruction
are not enabled, and the production engine pin remains 4.7.2.

## Follow-up: usable NVIDIA package and Reflex integration — 2026-10-28

At the owner's request, the existing DLSS/DLAA candidate was rebuilt and packaged
with the NVIDIA fork's Reflex integration repaired. The official development
engine is now 4.8-beta1; this trial remains a distinct custom build and uses the
pinned older application snapshot `343be4b0bba0` plus its receipted overlays.
It is not a promotion of the current application onto the custom engine.

The new Reflex patches query actual low-latency availability, retain requested
versus SDK-accepted mode, call Sleep even when Off, separate PCL support, and use
the queued draw's token for render/present markers. A follow-up source audit found
that the initial implementation could overlap non-thread-safe state/options calls
with render markers. The final patch performs those calls after rendering sync,
refreshes availability each frame, and returns the accepted mode to Off on loss
of support or a latched SDK failure. No SDK or driver version was changed.
The [integration guide](../../../../../tools/graphics/native/README.md#nvidia-reflex-trial)
owns the commands, environment option and status API.

The generated 40-file package provides DLSS Quality/Balanced/Performance, DLAA,
and Reflex On/Off/Boost launchers, each with a separate local profile. Direct-flight
launchers request borderless 1920×1080. The adapter reports requested and
SDK-accepted modes instead of treating a request as proof of activation. Candidate
and package preflight verify its source hash and autoload registration.

| Final check on RTX 3090, driver 617.42 | Result |
| --- | --- |
| Reflex Off → On → Boost → Off, ordinary render thread | All four phases passed; 199 successful Sleep calls and 200 state queries; zero expired tokens |
| Same sequence, separate thread and fixed FPS | All four phases passed; state queries, Sleep and simulation/render/present markers advanced in every mode; zero expired tokens |
| DLSS preset K, separate thread and fixed FPS | Six phases, 384 frames, 360 successful evaluations; zero engine/Vulkan errors |
| Full game, actual 1080p | DLAA/Quality/Balanced/Performance, resize, Native/MSAA restoration and Reflex mode changes passed |
| Combined DLSS Quality + Reflex On | Camera changes, 120 active drawn frames at idle on the runway, pause and restart passed; final status: 2,410 DLSS evaluations, 5,372 successful Sleep calls, no backend failure; zero ObjectDB leaks at shutdown |
| Final custom-engine reconstruction/settings tests | 102 / 120 checks; zero failed, zero engine errors/warnings |
| Exported direct flight | Reflex On accepted, available and not failed; zero engine errors; normal window-close exit |
| Exported DLSS Quality capture | 1920×1080 PNG and matching manifest hash; 32 evaluations, no fallback, zero errors/warnings; visually inspected |
| Package integrity | All 40 managed files match their receipt hashes; editor/template integration receipts match |
| Fresh clone with exact tool overlay | Nine tests passed; eleven real engine patches applied to 29 pristine files, then repeated without rewriting any file |

The first baseline smoke used fullscreen and therefore ran at the monitor's 4K
resolution. The corrected fixture explicitly sizes and asserts 1080p; that is the
primary-target result above. An initial combined script was refused by the pause
menu's hold; the completed run resumes through the actual menu action. Release
templates reject `--path` and disable the debug bridge, so export verification used
direct checked execution and the built-in capture route. No guard was bypassed.

Vulkan validation was observed in the editor fixture and full-game logs. Loader
notifications, the separate-thread experimental warning and existing RGB8-to-RGBA8
conversion warnings remain visible. The final full-game log has 45 warnings; the
exported direct-flight log has 44. Their only warning categories are loader
notifications and texture conversion; neither has engine/Vulkan errors. The export
capture is clean, but this does not separately establish release-layer activation.

[Verification identities and results](verification-nvidia-2026-10-28.json) retain
the exact builds, package hashes, checked-run reports, full-game statuses and
fresh-clone proof. Raw logs and images remain ignored under
`tmp/nvidia-validation-20261028/` and the named bridge sessions. No FPS improvement,
input-to-photon reduction, physical validation or NVIDIA certification is claimed.
The driver-controlled flash-trigger path required for NVIDIA's complete Reflex
verification remains absent. DLSS camera-cut history resets, temporal motion
quality, long-session behavior and other GPU/driver/platform qualification remain
open. Frame generation, ray reconstruction and path tracing are still disabled.

## Current-source Windows package and settings promotion — 2026-10-28

The owner requested normal selectable NVIDIA settings, superseding their
experimental UI status. `product.py` packages the current application, rather
than the older trial snapshot. The Windows package opens at Home with Forward+;
DLSS/DLAA are saved reconstruction choices and Reflex offers Off, On and Boost,
with On as its default request. Unsupported features remain visibly unavailable.
The [operating guide](../../../../../tools/graphics/native/README.md) owns commands
and platform limits. Official cross-platform engine selection is unchanged.

The frozen package uses application HEAD `a7b3a79bb185` plus the receipted working
tree. Its import and export passed; the 17 packager regressions and receipt
verification passed. The importer rewrote 322 authoring sidecars, so the tool
restores their pinned bytes and reconciles only checked cache identities. The
initial export reproduced a source-proof failure; the corrected export passed
without reimporting or bypassing aircraft/native-kernel plugins. Maple alpha
coverage remains an explicitly unsupported import option, not equivalent output.

On the RTX 3090, the actual 1920×1080 Settings screen passed DLAA dispatch,
DLSS Quality, default Reflex On, Boost/Off, Keep and Revert. The screenshot was
inspected. Quality and Boost survived a process restart, with Boost accepted by
the SDK. The full-game DLSS mode/resize/Native restoration and Reflex marker
fixtures passed. Both bridge sessions closed without crashes or ObjectDB leaks.

The release executable produced an inspected 1080p capture with 32 successful
DLSS dispatches, no fallback, Reflex On accepted and zero expired tokens.
Ordinary Home and the Compatibility recovery launch both passed checked execution
and normal window-close shutdown with zero errors/warnings. An earlier
`--quit-after 180` invocation interrupted asynchronous startup and failed; it is
excluded from acceptance. An independent empty-project PCK check also loaded the
reported resources successfully. Do not use frame-limited termination as proof
that asynchronous Home preparation completed.

[Package identities and verification](verification-product-2026-10-28.json)
retain the exact artifact hashes, checked runs, UI fixture, smoke results and
known failed invocation. Raw logs and images remain in ignored `tmp/` paths.
This is functional verification, not an FPS, latency, temporal-quality or
cross-device guarantee. The [official NVIDIA/Godot review](../../../advanced-graphics-2026-10-21/nvidia-dlss-reflex-2026-10-28.md)
prioritizes the remaining camera-history, exposure, accepted-resolution and
Reflex measurement work.

## DLSS temporal-history follow-up — 2026-10-28

`dlss_history_reset.patch` replaces the constant-false reset input with
viewport-scoped generations. Requests survive warm-up, multiple requests before
evaluation coalesce, and only successful SDK evaluation acknowledges the captured
generation. Camera/scenario RID changes invalidate that viewport. App view/style
changes, flight reset, fly-by reposition, snap zoom, chase teleport and crash-focus
entry/exit submit explicit discontinuities; ordinary camera updates retain history.
The [operating contract](../../../../../tools/graphics/native/README.md#integration-contract)
and [rendered fixture](../../../../../tools/graphics/native/repro/README.md#dlss-temporal-history-regression)
own API details and reproduction commands.

On the RTX 3090 / driver 617.42, two independent 1920 × 1080 DLAA viewports
completed deferred/warm-up requests, coalescing, unchanged attachments and
camera/scenario changes with exactly five successful reset evaluations. Default
rendering completed 377 SDK evaluations; separate-thread fixed-60 rendering
completed 375. Both checked runs had zero engine/Vulkan errors. The six-phase
DLAA/Quality/Balanced/Performance and resize regression also passed on the new
editor with separate-thread fixed-60 rendering and validation enabled. Loader
notifications and Godot's separate-thread warning remain visible; the product
keeps its ordinary rendering-thread configuration.

The eight build regressions and seventeen product regressions passed, including
the actual compiled C++ generation helper. That helper checks acknowledgement
ordering and omitted success; it is not real SDK failure injection. The existing
backend still latches SDK failures and falls back rather than retrying in process.
Global status fields use separate atomics and were sampled after isolated settled
phases; they are not coherent per-viewport telemetry under arbitrary concurrency.
Stereo/XR, arbitrary uninstrumented teleports, moving-image quality and hardware
latency remain outside this evidence. Streamline 2.11.1 and preset K are unchanged.

The frozen application (`b56eb5fa3` plus NVIDIA overlays) passed 177 headless
checks: camera route 35, camera history 24, reconstruction history 16 and
reconstruction policy 102. Native API presence omits stock-only assertions. The
1080p full-game bridge fixture passed pilot-to-chase, steady paused rendering,
flight restart and orbit: each tested discontinuity caused one successful reset,
DLSS continued dispatching and Reflex On remained accepted. The session closed
without a crash or ObjectDB leak. Crash-focus transitions are covered by the
headless route test, not a rendered crash sequence.

Matching editor and release-template receipts produced the updated Windows
package. Its 1080p exported capture passed with 32 DLSS evaluations, one initial
reset, no fallback and Reflex On accepted; the image was inspected. Ordinary
Home startup and normal window-close shutdown also passed checked execution.
Both exported checks had zero errors and warnings. The 33-file package passed
receipt verification before and after promotion to `dist/windows-nvidia`.

The checkout initially changed integration line endings, which package preflight
correctly rejected. Exact editor input bytes were restored before rebuilding the
template. Solver source bytes were also restored before the final snapshot to
preserve the existing physics source identity. The frozen build excludes parallel
FSR SDK/history changes. No receipt check or authoring export gate was bypassed.

[Verification identities and results](verification-history-2026-10-28.json)
include the builds, artifact hashes, twelve checked runs, full-game counters,
shutdown and excluded early fixture/import attempts. Raw logs, captures and the
previous package remain ignored under `tmp/`. The camera-history source gap from
the earlier review is addressed for these events; exposure diagnostics and Reflex
hardware measurement remain open.

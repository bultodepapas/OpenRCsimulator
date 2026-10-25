# Native reconstruction experiment (VQ-07d)

This opt-in Windows/Vulkan build connects NVIDIA's existing DLSS integration and
AMD's FSR 3.1.4 upscaler, built from the pinned SDK with Vulkan fixes. It does not replace the production
Godot 4.7.2 pin. The upstream NVIDIA commit is based on Godot 4.8-dev; run it on
a disposable application copy and qualify an engine upgrade separately before
shipping it. The GPU used for local checks is not the product support boundary.

See the [implementation evidence and known limitations](../../../docs/research/visual-quality-implementation/VQ-07/native-reconstruction-2026-10-24/README.md).
The current trial pins Streamline 2.11.1 and DLSS **preset K**. On the RTX 3090,
automatic preset selection still reproduces the internal NGX image-layout error;
explicit K passes the tested mode/resize sequence with Vulkan synchronization
validation. This is a scoped workaround, not a repair to NVIDIA's closed runtime.
A 2.14.16 trial added startup errors and was rejected. Frame-based tagging now
captures the simulation token through the render queue with independent callback
parameters. The separate-thread shutdown fix and standalone reproduction live in
[repro](repro/README.md). Broader engine and release qualification remains open.

The engine candidate includes three further lifetime/synchronization fixes:
the exported Home LoadToken leak, reflection-atlas color-buffer retention, and
same-usage buffer writes across graph frames. The Home comparison reduced 121
retained LoadToken objects to zero; four reflection worlds reduced 28 retained texture
RIDs to zero; the [canvas regression](repro/README.md#canvas-buffer-synchronization-regression)
reduced ten reported Vulkan write hazards to zero. These bounded checks do not
establish long-session or cross-device release stability. A later fresh-profile
Home exit retained four audio stream/playback objects; its warm repeat retained
none. That separate shutdown finding remains open.

## Build

Requires Python 3.11+, Git, Visual Studio 2026 with C++ tools and Windows SDK,
CMake with the Visual Studio 18 2026 generator, LLVM's `llvm-readobj`, and
`python -m pip install scons==4.10.1`. Tested with CMake 4.4.2 and LLVM 22.1.8.
From the repository root:

```powershell
python tools/graphics/native/build.py --target editor --jobs 4
```

`--prepare-only` downloads and verifies dependencies, applies the checked patches,
and stages headers, NVIDIA runtime DLLs and licenses without compiling. It does
not build or install the AMD runtime and writes a separate preparation receipt.
The full build first compiles the patched FidelityFX runtime. `--cache`
selects a separate build directory. Downloads are pinned by SHA-256. A hash
mismatch is an error; the tool never silently refreshes a pin. Build receipts
record source, integration and runtime identities alongside the executable.
The experiment disables Streamline's automatic plugin downloads so the supplied
SDK runtime remains the tested dependency. Upgrade it as a separate change.

The patch stack is reconstructed from the pinned archive in a temporary directory.
Preparation accepts only pristine, known prefix or fully patched file contents;
unknown source edits fail before any engine source is replaced. This permits
overlapping patches and repeat builds. Offline regression checks:
`python -m unittest tools.graphics.native.test_build -v`.

`load_token_lifetime.patch` applies the still-open
[upstream LoadToken proposal](https://github.com/godotengine/godot/pull/121025),
with local exported-Home evidence. `reflection_atlas_lifetime.patch` is the merged
[upstream color-buffer fix](https://github.com/godotengine/godot/pull/124743).
`buffer_write_sync.patch` is a local, buffer-only render-graph correction: frame
reset must not discard the memory dependency between consecutive writes with
unchanged usage. All three patches are hashed in matching editor/template
receipts and required by package preflight.

The original signed AMD Vulkan DLL has a luma-history storage format mismatch
([upstream issue 161](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/issues/161))
and does not include the stencil aspect in imported depth/stencil barriers.
`fidelityfx.patch` corrects both in source. The resulting DLL is a local, unsigned
build, identified by its receipt; it is not the original AMD-signed binary.
The helper uses the pinned SDK's shader tools and Godot's Vulkan headers, and
creates an import library from the installed Vulkan loader's public exports.
It records the loader, header, compiler and library identities.

The default output is
`.tools/advanced-rendering/godot-135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/bin/`.
Keep its runtime DLLs next to the executable. The same tool accepts
`--target template_debug` and `--target template_release` for matching custom
export templates; ordinary Godot export templates do not contain this integration.
Editor success alone does not qualify an exported game. This initial Vulkan
experiment builds without D3D12, WinRT and AccessKit; it is not a production
accessibility or platform qualification.

The existing [graphics launcher](../README.md) accepts `--godot <custom editor>`.
This application also validates its aircraft presentation source hashes and engine
identity. Merely launching the production tree with 4.8-dev fails that contract.
`prepare_candidate.py` prepares a disposable pinned snapshot, changes its strict
presentation pin to 4.8.0, and regenerates its companion registry through the
existing customization generator. Its receipt records all changed identities;
production aircraft data and the 4.7.2 pin stay intact. Import this copy with the
custom editor before using the [debug bridge](../../debug/README.md):

```powershell
python tools/graphics/native/prepare_candidate.py
$env:OPENRC_GODOT=(Resolve-Path '.tools/advanced-rendering/godot-135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/bin/godot.windows.editor.x86_64.exe').Path
python tools/godot/run_checked.py --label native-import --timeout 900 -- $env:OPENRC_GODOT --headless --path tmp/native-reconstruction-candidate/app --import
$env:OPENRC_GRAPHICS_PROFILE='high'
$env:OPENRC_RECONSTRUCTION='fsr3_quality' # or dlss_quality, fsr3_native, dlss_native
python tools/debug/debugctl.py launch --app tmp/native-reconstruction-candidate/app --port 47941 --resolution 1920x1080 -- --quick-flight
```

Set `OPENRC_DEBUG_BRIDGE` to the returned port for subsequent bridge commands.
Confirm the actual viewport dimensions (`window mode=fullscreen` on the 1080p
test display); a requested window size may exclude desktop decorations. Keep
captures and raw logs outside tracked paths. Do not open the production import
cache with this experimental engine.

The preparer also imports the pinned initial-camera correction: only Main's
startup function and the pilot-camera helper change from the older trial sources.
This places the aircraft and selected view before the first `--quick-flight`
draw. The receipt records the additional startup source and function hashes.
Movie Maker uses a `movie` feature override for an actual 1920×1080 output;
`--resolution 1920x1080` alone does not change its fixed recording viewport.
See the [first-frame investigation](../../../docs/research/menu-investigations/UI-34c-R5/menu-preparation-2026-10-25/README.md#first-view-investigation-runway-start).

After both providers are available, their bridge smoke scripts exercise mode
changes, resizing and MSAA restoration:

```powershell
$env:OPENRC_DEBUG_BRIDGE='47941'
python tools/debug/debugctl.py run tools/graphics/native/fsr3-smoke.txt --fail-on-error
python tools/debug/debugctl.py run tools/graphics/native/dlss-smoke.txt --fail-on-error
python tools/debug/debugctl.py stop
```

Inspect the native engine log separately for Vulkan validation messages. A bridge
assertion or a successful SDK dispatch is not proof of valid image synchronization.

## Local experimental package

```powershell
python tools/graphics/native/build.py --target template_release --jobs 4
python tools/graphics/native/package.py
```

The packager verifies matching editor/template/runtime/source receipts and exports
through the existing checked Godot runner. Output is
`tmp/native-reconstruction-export/`, with the executable, PCK, runtime DLLs,
licenses and hash receipts. `FSR3 Quality.cmd`, `DLSS Quality.cmd` and `Native.cmd`
start a direct flight with separate local profiles. They do not use the player's
production preferences. `Graphics Options.cmd` opens Home in High with its own
profile: Settings → Graphics exposes the available providers and preserves kept
choices. Its initial reconstruction is Native. The standard `app/export.sh` still uses the production
engine and must not be used to package this trial.

## Integration contract

- Native and stock FSR2 remain available on their existing supported renderers.
- FSR3 requires Forward+, the dynamically discovered Viewport enum, and
  `RenderingServer.is_fsr3_available()`. The native adapter checks Vulkan and
  the AMD runtime. It does not infer support from a vendor/model string.
- DLSS requires Forward+, its engine enum and Streamline's actual DLSS
  capability result. No static reference to custom enums enters stock GDScript.
- The application and prepared candidate pin `rendering/streamline/dlss_preset="K"`.
  Package preflight rejects a missing pin. Preset selection is independent of the
  user-facing DLAA/Quality/Balanced/Performance resolution choice.
- `Streamline.get_dlss_status()` reports successful dispatches, context count,
  last frame ID and a latched backend failure. SDK failure, expired frame token,
  failed output initialization or rejected graph callback triggers Native fallback
  on the next application guard. The requested preset and saved MSAA are retained.
  An SDK success code does not imply a clean Vulkan validation result.
- `dlss_frame_lifecycle.patch` enables `slSetTagForFrame`, preserves one simulation
  token through queued draws and owns each callback's parameters. It also advances
  tokens in `--fixed-fps` capture mode. `dlss_failure_paths.patch` handles rejected
  callback ownership and output-clear failures. Both enter editor/template receipts.
- Preferences retain the requested mode across devices. Unsupported requests
  render natively, with the effective mode reported separately. UI options are
  disabled when unavailable. Native remains the default.
- The settings page shows requested/active presets, estimated 3D input and output
  dimensions, and the reason for fallback. Estimated dimensions are not GPU
  allocation measurements; DLSS can choose different integer rounding.
- FSR sharpness controls AMD RCAS; they do not apply an extra sharpening pass to
  DLSS. Temporal reconstruction owns antialiasing. Returning to Native restores
  the saved MSAA preference.
- FSR3 is dispatched inside the engine render graph with linear HDR color,
  reverse-Z depth, decoded motion vectors, reactive mask, jitter and output
  resource dependencies. SDK imported image states are restored to the graph's
  declared states. Context destruction drains recorded and submitted GPU work.
- FSR3 uses its internal automatic exposure for HDR normalization. Godot's
  average-luminance texture is not an exposure multiplier and is not passed as
  one. Reverse-Z plane ordering follows the FFX dispatch contract.
- This adapter handles one view per context. Stereo/XR, temporal-history reset
  on arbitrary camera cuts, animated shader motion and transparency quality
  require separate work and evidence.

FSR 3.1 **upscaling** is independent of frame generation. This implementation
does not enable generated frames, path tracing or ray reconstruction. FSR4 is
not exposed as an available feature: the public Vulkan SDK required for that
path was still forthcoming in the [dated research](../../../docs/research/advanced-graphics-2026-10-21/dlss-fsr-2026-10-24.md).
Other GPUs, platforms and drivers require their own rendered qualification.

## Source and license identities

- [NVIDIA Godot fork](https://github.com/NVIDIA-RTX/godot/tree/135dff3887a3d2ccf45cafbd9bdffa7b718e1e76),
  MIT engine source, with the local integration/validation patches and
  `fsr3.h/.cpp` adapter.
- [FidelityFX SDK 1.1.4](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/releases/tag/v1.1.4),
  including FSR 3.1.4, MIT license; the local runtime is rebuilt with the recorded
  source patch. The SDK's unused frame interpolation dependencies do not enable
  frame generation in the game.
- [Streamline 2.11.1](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.11.1),
  with matching headers and runtime. NVIDIA component licenses are copied with
  the runtime; SDK/source availability is not a replacement for those terms.

Do not swap arbitrary SDK DLL versions or distribute SDK development DLLs.
The tool copies the release `bin/x64` runtime, not `development` binaries.

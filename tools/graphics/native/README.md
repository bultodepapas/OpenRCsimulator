# Native reconstruction experiment (VQ-07d)

This opt-in Windows/Vulkan build connects NVIDIA's existing DLSS integration and
AMD's signed FSR 3.1.4 upscaling runtime. It does not replace the production
Godot 4.7.2 pin. The upstream NVIDIA commit is based on Godot 4.8-dev; run it on
a disposable application copy and qualify an engine upgrade separately before
shipping it. The GPU used for local checks is not the product support boundary.

## Build

Requires Python 3.11+, Git, Visual Studio with C++ tools and Windows SDK, and
`python -m pip install scons==4.10.1`. From the repository root:

```powershell
python tools/graphics/native/build.py --target editor --jobs 12
```

`--prepare-only` downloads and verifies dependencies, applies the checked patch,
and copies SDK headers, runtime DLLs and licenses without compiling. `--cache`
selects a separate build directory. Downloads are pinned by SHA-256. A hash
mismatch is an error; the tool never silently refreshes a pin. Build receipts
record source, integration and runtime identities alongside the executable.

The default output is
`.tools/advanced-rendering/godot-135dff3887a3d2ccf45cafbd9bdffa7b718e1e76/bin/`.
Keep its runtime DLLs next to the executable. The same tool accepts
`--target template_debug` and `--target template_release` for matching custom
export templates; ordinary Godot export templates do not contain this integration.
Editor success alone does not qualify an exported game. This initial Vulkan
experiment builds without D3D12, WinRT and AccessKit; it is not a production
accessibility or platform qualification.

The existing [graphics launcher](../README.md) accepts `--godot <custom editor>`.
For a disposable application copy, use the [debug bridge](../../debug/README.md)
with `OPENRC_GODOT` pointing to that executable and `--app <copy>/app`. Import
the copy first, retain its required sibling assets, and select Forward+ with the
existing High launch mechanism. Do not open the production import cache with
this experimental engine.

## Integration contract

- Native and stock FSR2 remain available on their existing supported renderers.
- FSR3 requires Forward+, the dynamically discovered Viewport enum, and
  `RenderingServer.is_fsr3_available()`. The native adapter checks Vulkan and
  the AMD runtime. It does not infer support from a vendor/model string.
- DLSS requires Forward+, its engine enum and Streamline's actual DLSS
  capability result. No static reference to custom enums enters stock GDScript.
- Preferences retain the requested mode across devices. Unsupported requests
  render natively, with the effective mode reported separately. UI options are
  disabled when unavailable. Native remains the default.
- FSR sharpness controls AMD RCAS; they do not apply an extra sharpening pass to
  DLSS. Temporal reconstruction owns antialiasing. Returning to Native restores
  the saved MSAA preference.
- FSR3 is dispatched inside the engine render graph with linear HDR color,
  reverse-Z depth, decoded motion vectors, reactive mask, jitter and output
  resource dependencies. SDK imported image states are restored to the graph's
  declared states. Context destruction drains recorded and submitted GPU work.
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
  MIT engine source, with the local `engine.patch` and `fsr3.h/.cpp` adapter.
- [FidelityFX SDK 1.1.4](https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/releases/tag/v1.1.4),
  including FSR 3.1.4 and the signed `amd_fidelityfx_vk.dll`, MIT license.
- [Streamline 2.10.0](https://github.com/NVIDIA-RTX/Streamline/releases/tag/v2.10.0),
  matching the fork's headers. NVIDIA component licenses are copied with the
  runtime; SDK/source availability is not a replacement for those terms.

Do not swap arbitrary SDK DLL versions or distribute SDK development DLLs.
The tool copies the release `bin/x64` runtime, not `development` binaries.

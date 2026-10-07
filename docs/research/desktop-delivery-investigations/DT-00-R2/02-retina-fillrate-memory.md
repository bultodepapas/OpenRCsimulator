# DT-00-R2-02 — Retina pixel cost, MSAA, and unified memory

2026-10-07 · Research round **DT-00-R2** · Supports DT-01, DT-05, DT-10, and DT-11c.

**Status:** pixel-budget arithmetic and Godot/Apple source audit. No Retina capture, resident-memory sample, GPU profile, or
Mac performance test was run.

## Question

How much more rendering work can fullscreen Retina or an external high-resolution display request than the app's current
1280×720 window, and what does the exact 4× MSAA setting mean for planning memory and performance tests?

## Current project and display facts

- [`app/project.godot`](../../../../app/project.godot) sets a 1280×720 initial viewport and
  `anti_aliasing/quality/msaa_3d=2`. Godot's enum defines `MSAA_4X = 2`; its 3D viewport documentation describes 4× MSAA as a
  significant performance cost. It does not antialias 2D/UI. The pinned 4.7.2 enum confirms the value ordering. [Godot 4.7
  Viewport](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#enum-viewport-msaa), [renderer feature
  comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html#antialiasing), [Godot 4.7.2
  `viewport.h`](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/main/viewport.h#L115-L121).
- The project does not set a stretch mode; Godot 4.7's default is `disabled`. In that mode the root viewport follows the
  window and renders at the target window size; fullscreen resolution therefore needs to be read at runtime, not inferred
  from the 1280×720 startup size. [Godot 4.7 ProjectSettings: stretch
  mode](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-display-window-stretch-mode),
  [multiple resolutions](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html).
- Pinned Godot 4.7.2's macOS display server converts between Cocoa points and pixel coordinates using a screen backing scale;
  it sets the layer's contents scale and multiplies the resulting window content size by that scale. This confirms that
  logical point dimensions alone do not describe the 3D render target. [Godot 4.7.2
  `display_server_macos.mm`](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/display_server_macos.mm#L102-L160).
- Apple lists the M1 MacBook Air panel at 2560×1600 native resolution. The 2021 M1 Pro 16-inch MacBook Pro panel is 3456×2234
  and supports adaptive ProMotion up to 120 Hz. Those are example panels, not every M1+ Mac's built-in or external display.
  [Apple M1 Air specs](https://support.apple.com/en-us/111883), [Apple M1 Pro 16-inch
  specs](https://support.apple.com/en-us/111901).
- Apple documents Apple Silicon memory as shared by CPU and GPU. An M1 Air was offered with 8 GB unified memory; M1 Pro
  MacBook Pro started at 16 GB. Render targets thus share the machine's memory pool with the app, OS, imported textures, and
  other processes. [Apple Silicon porting
  guide](https://developer.apple.com/documentation/apple-silicon/porting-your-macos-apps-to-apple-silicon), [Apple M1 Air
  specs](https://support.apple.com/en-us/111883), [Apple M1 Pro specs](https://support.apple.com/en-us/111901).

## Pixel and nominal color-buffer arithmetic

The table counts full-resolution pixels. “4× samples” is pixels multiplied by the configured MSAA sample count; it is a
workload indicator, not a prediction of four times the frame time. Compatibility's documented color precision is RGBA8, or
four bytes per stored sample. A simple uncompressed footprint is therefore `pixels × 4 samples × 4 bytes`, plus a
single-sample RGBA8 resolve target (`pixels × 4 bytes`). [Godot renderer feature
comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html#other-features).

| Output | Pixels | Relative to 1280×720 | 4× RGBA8 samples | Plus one RGBA8 resolve |
| --- | ---: | ---: | ---: | ---: |
| App baseline, 1280×720 | 0.922 MP | 1.00× | 14.75 MB | 3.69 MB |
| M1 Air panel, 2560×1600 | 4.096 MP | 4.44× | 65.54 MB | 16.38 MB |
| M1 Pro 16-inch panel, 3456×2234 | 7.721 MP | 8.38× | 123.53 MB | 30.88 MB |
| UHD external reference, 3840×2160 | 8.294 MP | 9.00× | 132.71 MB | 33.18 MB |

`MB` here means decimal megabytes. Each row is arithmetic from the listed dimensions and Godot's configured sample
count/format; it is not a profiler reading.

This intentionally counts only one color sample target and its resolve. It excludes depth/stencil, other render targets, the
window/compositor buffers, textures, imported landscape content, driver bookkeeping, and allocation alignment. MSAA storage
may be tiled or compressed by the GPU, so the table is not a process-RSS estimate or a prediction of physical DRAM traffic.
Godot also warns that MSAA costs vary by renderer and workload. [Godot 4.7 Viewport
MSAA](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-property-msaa-3d), [Apple GPU memory
architecture](https://developer.apple.com/documentation/apple-silicon/porting-your-macos-apps-to-apple-silicon).

The work can rise from two independent multipliers: native display pixels and 4× MSAA samples. A 2560×1600 M1 Air output
contains 4.44× the baseline pixels before MSAA; its nominal color sample count is then 17.78× the 1280×720 single-sample
count. A 3456×2234 16-inch M1 Pro output is 8.38× pixels and 33.51× sample locations. These ratios are not GPU-speed ratios:
fragment shading, overdraw, tile memory, compression, and CPU submission do not scale identically.

The project setting `textures/vram_compression/import_etc2_astc=true` is enabled, and the current tree contains
`app/assets/landscape/trees/atlas.png`. The adjacent project comment still says that no textures are imported. Treat texture
residency as an additional unknown in the memory baseline; this report did not measure the imported format or loaded
allocation.

## Experiment and gate proposal

1. **DT-01/DT-05:** record physical screen dimensions, effective window/viewport pixel dimensions, scale factor, monitor
    identity/topology, chosen “looks like” mode where relevant, and external-display mode. Include the M1 Air 2560×1600
    class, an M1 Pro/Max 120-Hz class if claimed, and the owner's actual external display; do not label all Apple Silicon as
    Retina or ProMotion.
2. **DT-10:** establish the shipped 4× Compatibility baseline on each named host at windowed 1280×720 and fullscreen native
    pixels. Preserve actual viewport dimensions and MSAA in every run. Capture process-loop intervals and system memory
    pressure/usage; a render-size/setting change is a distinct candidate.
3. **DT-11c:** if measured costs justify it, pair one 3D render-scale or MSAA change against the baseline. Keep camera, zoom,
    aircraft pose, field, and display mode fixed. Require the existing blinded aircraft-attitude/readability evidence because
    lower 3D scale or fewer samples can affect small control surfaces and silhouettes. Do not count UI scale as a 3D cost
    reduction.
4. Keep the same package/build identity and run order paired on the same host. Compare per-run results and repeat when the
    difference remains within run variation, as DT-10a requires.

## Limits and sources

The source audit establishes the project's requested settings, not the effective fullscreen size, imported texture format,
exact driver allocation, or Mac throughput. Apple's specification resolution does not guarantee Godot will render every mode
at that size; record the live viewport. No buffer arithmetic here includes a depth attachment or claims actual GPU memory
use.

Primary references: [Godot 4.7 Viewport](https://docs.godotengine.org/en/4.7/classes/class_viewport.html), [Godot 4.7.2
`viewport.h`](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/main/viewport.h), [Godot renderer
comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html), [Godot multiple
resolutions](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html), [Godot 4.7.2 macOS display
source](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/display_server_macos.mm), [Apple M1
Air](https://support.apple.com/en-us/111883), [Apple M1 Pro 16-inch MacBook Pro](https://support.apple.com/en-us/111901), and
[Apple Silicon porting
guide](https://developer.apple.com/documentation/apple-silicon/porting-your-macos-apps-to-apple-silicon). Recheck repository
facts with `sed -n '14,35p' app/project.godot`, `rg --files app/assets`, and `sed -n '802,815p'
app/tests/test_pilot_aids.gd`.

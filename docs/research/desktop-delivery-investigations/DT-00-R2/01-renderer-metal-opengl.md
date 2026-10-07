# DT-00-R2-01 — macOS renderer and driver choices from M1 onward

2026-10-07 · Research round **DT-00-R2** · Supports DT-01, DT-02, DT-10, and DT-11d.

**Status:** pinned-engine documentation/source audit and repository configuration audit. No Mac launch, renderer comparison,
export, or performance measurement was run.

## Question

What graphics path does this app actually select on Apple Silicon, what would change if it moved to Godot's native Metal
path, and which hardware/OS combinations must be recorded before making that decision?

## Audited configuration

- The app pins Godot 4.7.2. [`app/project.godot`](../../../../app/project.godot) sets both `renderer/rendering_method` and
  `.mobile` to `gl_compatibility`, and sets `anti_aliasing/quality/msaa_3d=2`.
- Godot separates a rendering **method** from its graphics **driver**. Compatibility uses OpenGL; Forward+ and Mobile use
  RenderingDevice with Vulkan, Direct3D 12, or Metal. Godot documents desktop OpenGL as OpenGL 3.3 Core Profile. [Godot 4.7
  renderer overview](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html), [internal rendering
  architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html).
- Therefore this project selects Compatibility/OpenGL on macOS. It does not select native Metal merely because it runs on M1
  or later. The pinned Godot macOS setting `rendering/gl_compatibility/driver.macos` defaults to `opengl3`. The audited app
  does not configure ANGLE; do not infer a different backend from its presence in engine options. Godot 4.7.2 registers
  both the `opengl3` default and the macOS Metal/Vulkan RenderingDevice defaults in
  `main.cpp`. [Godot 4.7 ProjectSettings](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-rendering-gl-compatibility-driver-macos),
  [pinned Godot 4.7.2 defaults and driver selection](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp#L2234-L2264).
- Metal is a RenderingDevice driver usable with Forward+ and Mobile. Godot 4.7's macOS default for that driver is `metal` on
  Apple Silicon; Intel Macs use Vulkan through MoltenVK when Metal is unavailable. This default matters only after selecting
  a RenderingDevice renderer. It is not a runtime fallback from this project's explicit Compatibility method. [Godot 4.7
  ProjectSettings](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-rendering-rendering-device-driver-macos),
  [Godot rendering
  architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html#metal).
- Godot's fallback-to-OpenGL setting is a fallback from RenderingDevice-based methods when their required driver is
  unavailable. Its docs say the actual rendering method/driver may differ after fallback or a command-line override; query
  `RenderingServer.get_current_rendering_method()` and `get_current_rendering_driver_name()` at runtime. [Godot 4.7
  ProjectSettings](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-rendering-rendering-device-fallback-to-opengl3).
- The current frame report records `backend` as the rendering method, plus adapter and API strings, but not the driver's
  name. Its `vsync` field is only a boolean. [`app/main.gd`](../../../../app/main.gd) should be treated as incomplete
  graphics-identification evidence for a Mac comparison until DT-10 records the effective driver explicitly.

## Apple Silicon and OS facts

- Godot 4.7 lists macOS 13 as its minimum OS for native Apple Silicon exports; that is an engine floor, not an OpenRC support
  promise. The same page lists M1 as an example Mac CPU and Metal 3 as the macOS graphics API for Forward+/Mobile. [Godot 4.7
  system requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html).
- Apple's Metal-family mapping places M1 GPUs in Apple family 7, M2 in family 8, and M3/M4 in Apple family 9; that number
  describes API feature support, not an interchangeable speed class. GPU core count, memory configuration, cooling, and
  display are still separate host facts. [Apple
    `MTLGPUFamily`](https://developer.apple.com/documentation/metal/mtlgpufamily).
- Godot 4.7 says its native Metal driver runs on Apple Silicon and that Metal 4 is selected only when supported by the
  running OS. Apple Silicon hardware supports Metal 4, but Godot requires macOS 26 or later; older macOS versions use Metal
  3. Do not infer Metal 4 runtime availability from the M-series chip name alone. [Godot 4.7 Metal
  architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html#metal),
  [Apple Metal feature-set tables](https://developer.apple.com/metal/feature-sets/).
- Apple deprecated OpenGL in macOS 10.14 and still lists it as available on Apple Silicon. Deprecation justifies a
  compatibility risk register and native testing; it does not prove current OpenRC failure or a removal date. [Apple: porting
  macOS apps to Apple
  silicon](https://developer.apple.com/documentation/apple-silicon/porting-your-macos-apps-to-apple-silicon).
- For broader OS claims, Godot's current table distinguishes macOS 11 on Intel from macOS 13 on Apple Silicon. Choose and
  test the product's minimum OS separately for the actual exported app and renderer. [Godot 4.7 system
  requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html).

## Experiment and gate proposal

1. **DT-01:** freeze a named Apple Silicon baseline, beginning with an M1-class host and adding a later M-series host only if
    it is part of the intended audience. Record exact SoC/GPU core count, unified-memory size, macOS build, architecture,
    display, resolution, refresh mode, power state, and package hash.
2. **DT-02:** launch the final package natively and preserve the engine startup log. Record requested and effective method,
    effective driver name, adapter/API, package architecture, and any fallback/error. A project setting alone is not proof of
    the driver that ran.
3. **DT-10:** measure the shipped Compatibility build first under its real workload. Only build a separate Mobile/Forward+
    Metal candidate if a measured gap or required feature justifies the renderer change. Compare paired runs on the same host
    and display; do not compare different methods as if they were a one-setting quality toggle.
4. **DT-11d:** retain a renderer change only after the same visual cases pass aircraft attitude/readability review,
    startup/flight behavior stays correct, and paired native measurements exceed run variation. Compatibility, Mobile, and
    Forward+ have different feature support and may need scene/material changes. [Godot renderer
    comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html#feature-comparison).

## Limits

No inference here establishes which renderer is faster on an M1, which MacOS version OpenRC should support, or whether OpenGL
will be removed. Godot's engine minimums and Apple's API capability tables are not application acceptance results. The
current project uses Compatibility, so native Metal comparisons require an explicit candidate configuration and separate
visual validation.

## Sources and reproducibility

Primary sources: Godot 4.7 ProjectSettings, renderer overview, internal rendering architecture, and system requirements;
Apple Developer Metal-family and Apple-Silicon porting documentation. Pinned Godot 4.7.2 implementation: [driver
registration/selection](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp#L2234-L2264), [macOS display
server](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/display_server_macos.mm).
Repository facts can be rechecked with `sed -n '24,34p' app/project.godot`, `sed -n '561,635p' app/main.gd`, and `rg -n
'get_current_rendering_driver_name' app`.

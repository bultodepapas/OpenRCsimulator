# 04 — Apple Silicon slices, loader floor, and native dependencies

2026-10-07 · DT-00-R2 · **Static source/artifact audit; no macOS execution or ARM64 numerical result.**

## Question and scope

What does the current universal macOS executable load on each CPU slice, what minimum OS does it declare, and what must remain true if a native
extension is added? This report covers Mach-O architecture, direct load commands, deployment metadata, and GDExtension packaging. Numerical
equivalence remains with [investigation 11](11-arm64-physics-numerics.md); this report does not claim it.

## Findings

1. Godot 4.7's official macOS template is a Universal 2 `.app` containing x86_64 and arm64 slices. macOS selects arm64 on Apple Silicon when
   present; an x86_64-only process requires Rosetta. A universal main executable does not make a thin plug-in or framework universal. [Godot macOS
   export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html), [Apple universal
   binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary).
2. Rosetta translates an x86_64 process and its dynamically loaded code together. It cannot make an x86_64 extension load into the app's native
   arm64 process. Apple says Rosetta is a transition path through macOS 27, with later support narrower; treat native arm64 as the Apple Silicon
   contract and use Intel hardware for Intel-native qualification.
   [Rosetta](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment), [Apple's 2026
   notice](https://developer.apple.com/news/?id=w5ngl9k2).
3. Godot 4.7 lists exported-project baselines of macOS 11 for Intel and macOS 13 for Apple Silicon. Godot labels these as simple-project baselines
   and says project requirements vary, so macOS 13 is the initial arm64 floor candidate, not a measured OpenRC support promise. [Godot system
   requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html#exported-godot-project).
4. The current preset requests `binary_format/architecture="universal"`, but it does not set per-architecture minimum versions. The already-present
   ignored ZIP is identified only by SHA-256 `801760a90e71d678c76aba1c28725c81eda68865ed4f90d7b475f5b4a8697a55`; its relationship to the dirty
   checkout is unknown. [Preset](../../../../app/export_presets.cfg), [probe](probes/macos_macho_probe.py), [recorded
   metadata](probes/macos_macho_probe.json).
5. That ZIP's 64-bit main executable has x86_64 and arm64 slices. The archive's `Info.plist` says
   `LSMinimumSystemVersionByArchitecture={x86_64:11.00, arm64:13.00}` and `LSArchitecturePriority=[arm64,x86_64]`. The declared arm64 plist floor
   agrees with Godot's baseline. Its slice UUIDs are x86_64 `045e6b99-5b7e-3e28-8a95-f981ddd2c7e4` and arm64 `fd76bc91-ddfc-38c7-93f7-c0133539973c`;
   retain candidate UUIDs separately for exact symbol matching.
6. The Mach-O load-command floors are lower: x86_64 uses `LC_VERSION_MIN_MACOSX` 10.13.0; arm64 uses `LC_BUILD_VERSION` macOS 11.0.0. Neither lower
   command overrides the app's plist declaration or proves that the complete project runs on those older systems. Inspect both records in every
   release candidate; align them deliberately with the advertised floor.
7. Both slices report SDK 26.1.0 in the load command. This is SDK metadata, not the minimum deployment target and not provenance that this ZIP was
   built by the current checkout.
8. The x86_64 slice has these direct `LC_LOAD_DYLIB` framework imports: `ForceFeedback`, `Cocoa`, `Carbon`, `AudioUnit`, `CoreAudio`, `CoreMIDI`,
   `IOKit`, `GameController`, `CoreVideo`, `AVFoundation`, `CoreMedia`, `QuartzCore`, `Security`, `IOSurface`, `Metal`, `AppKit`,
   `ApplicationServices`, `CoreFoundation`, `CoreGraphics`, `CoreServices`, `CoreText`, and `Foundation`.
9. It also imports `/usr/lib/libSystem.B.dylib`, `libz.1.dylib`, `libc++.1.dylib`, and `libobjc.A.dylib`. The arm64 slice imports the same framework
   and `/usr/lib` set plus `CoreHaptics`, `UniformTypeIdentifiers`, `MetalFX`, and `MetalKit`; all listed names are absolute Apple system locations
   in this artifact.
10. Both slices carry `LC_RPATH` entries `@executable_path/../Frameworks` and `@executable_path`. The ZIP contains one Mach-O executable and no
   bundled `.dylib`, `.so`, `.framework`, or `.xcframework`; the runtime dependency inventory is not exhaustive for code loaded later through
   `dlopen` or an extension manifest.
11. A repository scan found no production `.gdextension` or native library payload under `app/`. The experimental `research/native-slipstream/`
   build and vendored Godot test fixture are outside the app's shipped production tree; they do not create a current Mac dependency.
12. If a GDExtension is promoted, its manifest must select a Mac library for the actual process architecture, the binary must match the pinned Godot
   extension interface, and every transitive library must resolve inside the bundle or to an OS-provided dependency. Godot documents
   architecture-specific manifest keys and `Contents/Frameworks` for macOS dependencies. [GDExtension
   format](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/gdextension_file.html).
13. For every supported process, its selected extension and transitive libraries must match that process's architecture and ABI. A universal library
   or separate thin arm64/x86_64 libraries selected by the manifest can both support a universal app; an arm64-only payload is sufficient only if
   Intel support is dropped. [Apple universal binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary).
14. The Mach-O probe reads headers, `LC_UUID`, direct dylib/rpath commands, CodeDirectory flags, and selected plist identity/deployment fields. It
   does not resolve those imports against macOS, discover runtime-loaded libraries, check extension ABI compatibility, validate signatures, or
   launch either slice.

## DT mapping

- **DT-01a:** record the final app's plist deployment target, each Mach-O slice's `minos`, all direct imports and `LC_RPATH` entries; retain macOS
  13 as the Apple Silicon floor candidate until a physical M1 on that OS is accepted.
- **DT-02a/02b:** record the running process architecture (`arm64` versus translated `x86_64`) separately from slice presence; run ARM64 package and
  physics acceptance on an M1. Follow investigation 11 for trajectory, strict-double, and timing limits.
- **DT-07/09c:** recursively inventory all code in the finished bundle. Require architecture coverage, resolvable dependencies and signatures for
  every added extension/framework before widening the product's dependency set.

## Native acceptance commands — UNRUN

Run on a clean macOS candidate after export; these commands were not run in this audit.

```sh
APP="/Applications/OpenRC Simulator.app"
EXE="$APP/Contents/MacOS/OpenRC Simulator"
lipo -archs "$EXE"
otool -arch arm64 -l "$EXE" | egrep 'LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX|LC_RPATH|LC_LOAD'
otool -arch arm64 -L "$EXE"
plutil -p "$APP/Contents/Info.plist" | egrep 'LSMinimumSystemVersion|LSArchitecturePriority'
find "$APP/Contents" -type f -exec file {} \; | grep -E 'Mach-O|dynamically linked shared library'
```

On an M1, record `Engine.get_architecture_name()` from the running app; Godot reports the binary slice, so `arm64` is native and `x86_64` is
translated on that Apple Silicon host. Repeat `lipo`/`otool` for every discovered code object, and inspect each extension manifest. [Godot Engine
architecture](https://docs.godotengine.org/en/4.7/classes/class_engine.html#class-engine-method-get-architecture-name).

## Sources and limits

The static artifact evidence is reproducible with `python3 docs/research/desktop-delivery-investigations/DT-00-R2/probes/macos_macho_probe.py
"dist/macos/OpenRC Simulator.zip"`; the probe writes JSON to stdout and extracts only to a temporary file. The archive is ignored, its build
provenance is unknown, and its hash is included so this observation is not mistaken for the next export.

The source/API audit and artifact metadata do not show that OpenRC runs on macOS 13, that every imported framework is available there, or that
x86_64 and arm64 produce equivalent physics. Those remain native acceptance results.

Sources accessed 2026-10-07: [Godot 4.7 macOS export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html), [Godot
exported-project system requirements](https://docs.godotengine.org/en/4.7/about/system_requirements.html#exported-godot-project), [Godot GDExtension
format](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/gdextension_file.html), [Godot macOS export
settings](https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformmacos.html), [Apple universal
binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary), [Apple
Rosetta](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment), [Apple Rosetta
timeline](https://developer.apple.com/news/?id=w5ngl9k2), and Godot 4.7.2 source [display
server](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/display_server_macos.mm) / [window
delegate](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/godot_window_delegate.mm).

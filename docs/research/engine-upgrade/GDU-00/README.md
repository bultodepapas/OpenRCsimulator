# GDU-00: Godot 4.7.2 → 4.8 upgrade audit

**Date:** 2026-10-21. **Scope:** desk research and a read-only code scan, with no engine run against this project. It lists what the 4.8 changelog and its open regressions can break here. It does not prove 4.8 compatibility. The plan is in [godot-4.8-upgrade](../../../plans/godot-4.8-upgrade.md).

## Release status

| Item | Value | Source |
| --- | --- | --- |
| Current pin | 4.7.2-stable (2026-08-18), commit `ed1daf0bf` | [get-godot.sh](../../../../app/get-godot.sh), [GitHub release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable) |
| Latest 4.8 build | 4.8-beta1, published 2026-10-15, commit `4d10419ca`. Feature freeze; stable is expected in Q4 2026 with no date announced | [beta 1 announcement](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/), [godot-builds release](https://github.com/godotengine/godot-builds/releases/tag/4.8-beta1) |
| Change volume | 1,523 merged PRs, 340 contributors, 16 labelled "breaks compat" | Interactive changelog data `godotengine.godot.4.8.json` ([repository](https://github.com/godotengine/godot-interactive-changelog), master, fetched 2026-10-21) |
| Open 4.8-milestone regressions | 93 on 2026-10-21 | GitHub search `label:regression milestone:4.8 is:open` |
| godot-cpp | 10.0.0-stable is versioned independently of the engine. An extension built with `api_version=4.7` loads in later minor versions | [godot-cpp README](https://github.com/godotengine/godot-cpp#compatibility) |
| Templates | The beta1 `.tpz` still contains `templates/macos.zip` (119.6 MB; 123.6 MB in 4.7.2), `linux_release.x86_64` and `windows_release_x86_64.exe` | Zip central directory read over an HTTP range request |

## Method

1. Downloaded the interactive changelog JSON and filtered PRs by label (`breaks compat`, `topic:*`) and by keywords for Compatibility, sky, audio, input, export, GDScript, import and core math.
2. Read the PR descriptions and diffs that touch APIs this project uses, via `gh api repos/godotengine/godot/pulls/<n>`.
3. Listed the open 4.8 regressions and read the ones that match our APIs.
4. Scanned `app/` with ripgrep and [gdu00_exposure.py](../../../../research/engine-upgrade/gdu00_exposure.py). The script resolves shader `#include`s and lists the engine-version identities.

## Blocking regressions (open upstream on 2026-10-21)

| Issue | Effect here | Exposure |
| --- | --- | --- |
| [#124742](https://github.com/godotengine/godot/issues/124742) Compatibility: non-sampler `global uniform`s read 0/1 once a shader declares ≥ 4 `sampler2D` (regressed dev7→beta1 by [#124336](https://github.com/godotengine/godot/pull/124336)) | Field ground and imported trees lose the exposure/clock/wind globals | `render/ground.gdshader` (8 samplers) and the three `scenery/imported_tree_wind*.gdshader` (10 each); 29 shaders use non-sampler globals |
| [#124744](https://github.com/godotengine/godot/issues/124744) macOS `universal` export packages the debug template for release exports, and the other way round (regression from [#124408](https://github.com/godotengine/godot/pull/124408)) | The release macOS ZIP would ship a debug binary | `export_presets.cfg` preset 2 uses `binary_format/architecture="universal"` |
| [#124731](https://github.com/godotengine/godot/issues/124731) Linux segfault when X11 is unavailable and Wayland is the fallback | Possible native Linux launch failure. Headless CI is not affected | Linux package smoke and Wayland desktops |

Also relevant, but not upstream-blocking: [#124349](https://github.com/godotengine/godot/issues/124349) (`load_resource_pack` breaks the global class list, already present in 4.7.x; pack-mounting probes rely on this path), [#124261](https://github.com/godotengine/godot/issues/124261) (exclusive fullscreen looks maximized; DT/UI-23 display modes) and [#123331](https://github.com/godotengine/godot/issues/123331) (mouse-motion stutter in Windows exports).

## Changes that touch this project

| Area | 4.8 change | Project dependency | Expected action |
| --- | --- | --- | --- |
| Rendering | [#124336](https://github.com/godotengine/godot/pull/124336) moves global and per-instance shader parameters from a UBO to a texture on Compatibility | 29 global-uniform shaders, exposure and shader clock | Correctness after #124742; frame-time check |
| Rendering | [#110911](https://github.com/godotengine/godot/pull/110911), [#111045](https://github.com/godotengine/godot/pull/111045), [#110956](https://github.com/godotengine/godot/pull/110956), [#122268](https://github.com/godotengine/godot/pull/122268), [#107958](https://github.com/godotengine/godot/pull/107958): sky energy color space, background luminance, fog/clear color, sky material lookup, fog in sky reflections | `BG_SKY` + exponential fog + sky ambient/reflections (`render/atmosphere.gd`); `BG_COLOR` previews (Workshop, HX-700 view); `sky_state.gd` was tuned against 4.7.2 | Paired captures; sky retuning only with an explained difference |
| Rendering | [#121676](https://github.com/godotengine/godot/pull/121676) sky `SCREEN_UV` fix (breaks compat) | `render/sky.gdshader` does not read `SCREEN_UV` | None expected; verified by scan |
| Rendering | [#119145](https://github.com/godotengine/godot/pull/119145), [#119161](https://github.com/godotengine/godot/pull/119161), [#121012](https://github.com/godotengine/godot/pull/121012) tangent storage, generation and non-uniform-scale transform | 3 scripts call `generate_tangents`; 53 glTF/GLB imports; normal-mapped film, US-V09b | Normal-map captures; repeat the LEARNINGS tangent check |
| Rendering | [#122236](https://github.com/godotengine/godot/pull/122236), [#121718](https://github.com/godotengine/godot/pull/121718), [#121530](https://github.com/godotengine/godot/pull/121530), [#120230](https://github.com/godotengine/godot/pull/120230), [#124310](https://github.com/godotengine/godot/pull/124310)/[#124342](https://github.com/godotengine/godot/pull/124342): probe ambient blend, AO light affect, `ARRAY_CUSTOM` channels, MultiMesh zero-init and depth/stencil blits on Compatibility | 1 lake reflection probe, 63 MultiMesh scripts, flowers' per-instance colours | Captures of the lake, scenery and flowers |
| Rendering | [#124484](https://github.com/godotengine/godot/pull/124484) particle material UBO binding (fixed after #124336) | 19 particle scripts (smoke, dust) | Smoke/dust captures |
| World | FW-MOON-01 relies on 4.7.2 Compatibility rebuilding sky radiance only for sky ambient/reflections (`render/world/world.gd`) | Per-frame moon cost | Re-run the FW-MOON-01 cost-amplifier probe |
| Audio | [#120304](https://github.com/godotengine/godot/pull/120304) removes unused `gain` from notch/band-limit filters; [#119704](https://github.com/godotengine/godot/pull/119704) interpolates panner gain; [#118870](https://github.com/godotengine/godot/pull/118870), [#120036](https://github.com/godotengine/godot/pull/120036) stream length and WAV parsing | 8 effect users, 14 `AudioStreamWAV` users; the `Soundscape.seamless_loop` workaround; WAV hashes in `tools/audio/check_captures.py` | Mixed-output bench; check whether the 4.7.2 audio quirks still exist |
| Input | [#39708](https://github.com/godotengine/godot/pull/39708) adds `ui_toggle_fullscreen` (Alt+Enter, also Ctrl+Cmd+F on macOS), on in every project via `display/window/size/enable_toggle_fullscreen_shortcut=true` | `app_root.gd` owns the window mode; flight uses Enter and `controller_actions.gd` accepts Alt bindings | Owner decision; the default proposal is to disable it and keep display mode in Settings |
| Input | [#120399](https://github.com/godotengine/godot/pull/120399) ignores joypads in unfocused windows, but only for new projects (editor-created setting) | Radio input with pause on focus-out | Keep current behavior and write the setting explicitly |
| Input | SDL 3.4.16 ([#120373](https://github.com/godotengine/godot/pull/120373)); Windows Shift raw-input change ([#122569](https://github.com/godotengine/godot/pull/122569)) | Calibration keyed by GUID + VID:PID + name (DECISIONS 2026-10-05) | Compare device identity strings on real radios and gamepads |
| GUI | [#120631](https://github.com/godotengine/godot/pull/120631) adds `gui/common/auto_focus_strategy`; the default stays Legacy (0) for existing projects | 65 scripts with focus wiring | Write the setting explicitly; UI focus tests |
| GUI | [#105550](https://github.com/godotengine/godot/pull/105550) reworks default dialog titles (breaks compat) | 48 scripts using dialogs/popups; Spanish localisation | Screens and `es.po` coverage |
| GDScript | [#121833](https://github.com/godotengine/godot/pull/121833) standalone strings warn; [#123248](https://github.com/godotengine/godot/pull/123248) `@onready … as` warning; [#121171](https://github.com/godotengine/godot/pull/121171) forbids inheriting own inner class | 5 triple-quoted strings are shader-code constants, with no `@onready … as` pattern and no self-inheritance | Parse every script; check warning counts |
| Core | [#92002](https://github.com/godotengine/godot/pull/92002) `constexpr` math, the same formulas; [#92102](https://github.com/godotengine/godot/pull/92102) text serialization puts `\n` between Object properties | float64 kernel, PCG32 wind (`physics/wind_turbulence.gd`), `.tscn/.tres` diffs | Exact golden and trace equality; no editor mass-resave |
| Import | [#113429](https://github.com/godotengine/godot/pull/113429) streaming and [#104289](https://github.com/godotengine/godot/pull/104289) alpha-coverage import options | 339 tracked `.import` files | One mechanical reimport commit |
| Export | [#122213](https://github.com/godotengine/godot/pull/122213) `-d` fails in release exports; [#120721](https://github.com/godotengine/godot/pull/120721) export-option serialization; [#112813](https://github.com/godotengine/godot/pull/112813) embedded-PCK header padding; [#124233](https://github.com/godotengine/godot/pull/124233) Linux PIE/RELRO; [#124058](https://github.com/godotengine/godot/pull/124058) compressed embedded shaders | `export.sh` embeds the PCK and smoke-runs the Linux binary | Package checks and size comparison |
| Platform | [#121030](https://github.com/godotengine/godot/pull/121030) raises the macOS minimum to 11.0 (Intel) and 13.0 (ARM) | The 4.7.2 plist already declared 11/13 ([DT-00-R2](../../desktop-delivery-investigations/DT-00-R2/04-arm64-native-dependencies.md)); release notes say "macOS 11+" | Re-read the Mach-O floors in the exported app |

## Engine-version identities

The scanner lists 19 literal pins in `app/`. The CI Windows job (`.github/workflows/ci.yml`) pins the editor URL and folder separately. Identities that must change deliberately:

- `workshop/presentation.gd` `PRESENTATION_ENGINE_VERSION` and `render/presentation_sources.gd` `ENGINE_VERSION_PIN`. Under AE-24 an engine change requires a new presentation identity.
- `ai/companions/profile_loader.gd` `QUALIFIED_ENGINE_VERSION`. Companion profiles need requalification.
- `aircraft/timber_geometry.gd` provenance. It is generated and must be regenerated through its pipeline.
- Version-stamped tests: `test_aircraft_customization`, `test_companions_profiles`, `test_smoke_bindings`, `test_workshop_presentation`.
- The lake terrain bake invalidates itself through `Engine.get_version_info().hex`.

Docs carry 43 version-scoped claims, mostly in DECISIONS (8), LEARNINGS (5), learnings/runtime-and-delivery (5) and learnings/models-and-rendering (4). Each is either re-verified on 4.8 or scoped explicitly to 4.7.2.

## Limits

Nothing here ran 4.8 against the project. Counts are file-level pattern matches, not proofs of use or non-use. The regression list changes daily, so re-run the queries and the scanner at each candidate build.

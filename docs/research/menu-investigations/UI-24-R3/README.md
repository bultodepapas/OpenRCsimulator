# UI-24-R3 / VQ-06b — advanced desktop display controls

2026-10-21. Implemented in current source; Windows release built and launched.
Base revision: `d768619a44d469d5c6f20fc114a6772472c6be8d` plus the source hashes
in [source.json](source.json). This is a manual-controls delivery, not hardware
preset, performance, physical-display or cross-platform acceptance.

## Delivered behavior

- Existing Settings gains a Graphics category: unlimited or
  30/60/90/120/144/165/240 FPS; VSync on/off; main Home/flight viewport MSAA
  off/2×/4×/8×. Workshop's independent preview viewports remain unchanged.
- Display offers Automatic and nine window sizes from 1280×720 to 3840×2160,
  including 16:10 and ultrawide. Oversized windows fit the available desktop;
  borderless fullscreen uses desktop resolution and disables window-size selection.
  Automatic preserves geometry from the start of the settings transaction.
- Settings use the existing schema-1 display store, with optional new keys and
  unchanged defaults. Invalid values are rejected; old files receive defaults;
  future files remain protected. Direct technical flight routes still bypass Home
  preferences. Interactive Home applies saved graphics preferences.
- Display/graphics changes start the existing 15-second wall-clock recovery.
  Keep commits; Revert, timeout and Close restore saved values and native geometry.
  Selecting the saved option again also restores geometry before cancelling the
  timer. Failed saves retain recovery. A successful Keep updates the checkpoint.
- Native recovery includes window position, maximized mode and its normal Restore
  Down rectangle. This uses the OS's restored rectangle before preview sizing.
  Settings over Pause never resume the simulation. Defaults restore graphics only,
  leaving audio, language, text size and window choices in their existing transaction.
- English/Spanish labels and effective output/VSync readback are visible. At large
  text sizes in short windows, a category picker replaces the two-row tabs so the
  scrollable settings body remains usable. Title and Keep/Revert stay pinned.

## Verification

Godot 4.7.2-stable, native Windows, Compatibility, NVIDIA RTX 3090 / driver 617.42.
Headless checks establish logic/layout only. Native capture runs use private test
preferences; the ordinary exported launch uses a private APPDATA/LOCALAPPDATA folder.

| Check | Result |
| --- | --- |
| `test_display_preferences.gd` | 56 checks; types, option bounds, migration, persistence, invalid/future files |
| `test_settings_ui.gd` | 58 checks; preview, timer interactions, failed/reverted changes and four categories |
| `test_ui_settings_integration.gd` | 31 checks; actual keyboard FPS selection, root viewport MSAA, saved state and paused-flight holds |
| `test_advanced_graphics_settings.gd`, headless | 57 checks; transactions, shell relaunch and EN/ES layout |
| Same test, final native 1280×720 | 74 checks, including eight captures and maximized/normal geometry recovery |
| Native compact 960×540 | 60 checks, including eight captures; before the final normal-rectangle repair |
| `test_ui_modal_responsive.gd` | 616 cases across modal screens, four Settings pages, EN/ES, 100/200% text and 14 size/aspect transitions |
| `test_ui_scale.gd` | 72 checks; scaling, contrast, popup alignment and native-resolution preservation |
| Windows release export and ordinary Home startup | Passed; zero engine errors; required native DLL retained alongside executable |

The independent Luna Max review reproduced position/maximized rollback issues,
including cancelling the timer by reselecting a saved option. Added native cases
fail before the respective repairs and pass afterward. Initial short-window layout
failures are retained; the category picker resolves all 16 failing responsive cases.
Two headless harness runs started before engine window initialization and failed
layout checks; deferring the fixture startup fixes this without changing production.
These development failures remain in [verification.json](verification.json) and the
hashed logs; they are not counted as passing runs.

Native VSync Off read back as mode 0 on this Windows driver. The UI also displays
effective state and explains potential driver/compositor overrides. Do not infer
support on every system from this result. The known maple-wind warning remains;
these checks do not close earlier ordinary-release shutdown findings or target-GPU
performance gates. No physics or collision behavior changed.

Representative captures: [Spanish graphics](captures-accepted/es-100-3.png),
[large text](captures-accepted/es-200-3.png),
[compact large text](captures-compact/es-200-3.png).
The complete files and hashes are in [manifest.json](manifest.json); logs are
losslessly gzip-compressed. Checked reports retain exact invocation arguments.

## Reproduction and delivery

Run the named test scripts with the pinned engine through
`python tools/godot/run_checked.py --timeout 150 -- <godot> --headless --path app --audio-driver Dummy --script res://tests/<name>.gd`.
For native geometry/captures, omit `--headless`, pass `--resolution 1280x720` (or
`960x540`), and append `-- --graphics-captures=<new directory>` to the advanced test.
The two new `test_*.gd` scripts are automatically included by `app/test.sh` discovery.
This delivery ran the affected suites, not the complete repository/physics suite.

Local ordinary Windows executable:
`D:/OpenRCsimulator-scratch/graphics-settings-20261021/release/OpenRC Simulator.exe`.
Keep `openrc_ground_vehicle.dll` beside it. [binaries.json](binaries.json) identifies
the exact tested executable and DLL. Native settings behavior was exercised in the
source app; the release check verifies export and ordinary Home startup, not the
entire settings flow inside the package. This is not a published release.

Next: native macOS/Linux and mixed-monitor recovery, then measured Performance/High
profiles and separately qualified scenery/shadow/water controls. Keep physics fixed
across profiles and retain explicit resolution choices. No renderer switch, HDR,
ray tracing, upscaler or automatic GPU classification was added.

API references: [Godot DisplayServer](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html#class-displayserver-method-window-set-vsync-mode),
[Window mode and sizing](https://docs.godotengine.org/en/4.7/classes/class_window.html),
[Viewport MSAA](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-property-msaa-3d).
The DisplayServer note about Compatibility VSync is broader than the observed
Windows behavior; retain effective-state readback and test each target platform.

# UI-22–26-R1: scalable menus and reversible Settings

Date: 2026-10-15. First implementation milestone for the [menu redesign](../../../MENU-REDESIGN-PLAN.md). Baseline: [UI-20-R1](../UI-20-R1/README.md). This is menu software and visual evidence, not physical-flight validation or completion of UI-29.

## Delivered behavior

- The interactive shell uses 1280×720 logical coordinates with native `canvas_items` rendering and expanded aspect ratio. Automatic factors are 1, 1.5, 2 and 3 at 720p, 1080p, 1440p and 4K. No second Windows-DPI multiplier and no low-resolution 3D render texture.
- Home keeps Fly, language and utility actions visible. Setup, practice, Workshop and RC-car selection scroll. Labels wrap instead of losing the language value or abbreviating Controls. Aircraft availability, preview loading and single-activation launch behavior remain.
- Pause groups secondary tools and exit actions. Esc closes an open disclosure before Resume; nested pages preserve the session hold and return focus. Throttle/device warnings, restart and failed-trace recovery retain their existing meanings.
- Settings has pinned Close/Keep/Revert controls, 100–200% themed text, opaque panels, reduced motion, immediate language changes and nested Controls/Help. Display/accessibility settings use a separate validated file (`settings.cfg.display` for the normal route). Only Keep saves those choices; language uses the existing immediate store.
- Shared dark surfaces use 0.94 opacity, an opaque option, consistent field/selector/tab/popup states and amber focus. A 140 ms entrance fade never delays screen input isolation or the session hold. Lower navigation chrome is hidden while a child page is open. Help has a pinned header, focusable scroll area and corrected start guidance.

## Native visual evidence

[Gallery](GALLERY.md): **113 lossless native WebP images** before the separate display-recovery pair:

- 92 captures across EN/ES at 1280×720, 1920×1080, 2560×1440 and 3840×2160. Home, Pause and Settings at each resolution; dense screens at 720p/1080p/4K. Included pages: Help, controller Devices, failures, Natural Random, Workshop, wind/turbulence/atmosphere, lighting and overlays.
- 21 stress captures: ES at 200% themed text (720p Home/Pause/Settings/Help/Controls/conditions and 4K Home/Pause/Settings), plus Home/Pause/Settings at 1024×576, 1280×800, 1920×1200 and 3440×1440.

Windows, Godot 4.7.2 `ed1daf0bf`, Compatibility/OpenGL 3.3, RTX 3090, NVIDIA 610.88, 3840×2160 monitor. Window images were checked for exact native dimensions. Captures wait for layout and entrance animation before reading the viewport. The 1024×576 case is recovery coverage; normal minimum remains 1280×720.

At default size the Home column is 440 logical px, hence 1320 physical px at 4K. At 200% text it may grow to accommodate the pinned controls; its fade follows the real panel edge. Dense text uses intentional vertical scrolling. At 200% Pause, focus reveals Resume and some status text is above the initial scroll position; this is not a claim of a permanently visible safety-status region.

`geometry.json.gz` contains control rectangles, fonts, text-fit observations, actual image sizes and **56 passing sampled flow records**. These use production routes plus the existing event driver; they are not physical keyboard/gamepad qualification. Captures of one tab do not qualify every tab. The new Settings integration test separately uses real injected key events through selector popups and nested routes.

## Checks and reproduction

`tests.json` records **20 passing focused test scripts**; `logs/` retains their output. Coverage includes localization, Home/catalog geometry (including 200% EN/ES), pause, screen stack, conditions, input isolation, controller setup, Workshop, Natural Random, preview cache, Settings persistence/reversion and integrated Settings holds/focus. `parse.json` records 40 passing product-shell script parse checks. Existing contrast checks passed; no golden flights were re-recorded. This is not the complete `app/test.sh` or platform export matrix.

The automatic scale test also checks 16:10, ultrawide and 1024×576 logical dimensions. Geometry checks for an 800×600 native window now compare against its expanded logical viewport, rather than mixing physical and logical coordinates.

```powershell
$Godot = '.tools/Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --path app --audio-driver Dummy --script res://tests/test_ui_settings_integration.gd
& $Godot --headless --path app --script res://tests/test_ui_scale.gd
& $Godot --path app --borderless --position 0,0 --audio-driver Dummy --script <absolute-path>/capture.gd -- --out=<fresh-directory>
& $Godot --path app --borderless --position 0,0 --audio-driver Dummy --script <absolute-path>/stress.gd -- --out=<fresh-directory>
& $Godot --path app --borderless --position 0,0 --audio-driver Dummy --script <absolute-path>/display_trial.gd -- --out=<fresh-directory>
```

`capture.gd`, `stress.gd` and `display_trial.gd` stay outside production. They use isolated preferences and must run one native window experiment at a time. A connected XInput controller was auto-selected by the existing service; no controller profile was changed.

## Identity and boundaries

The shared checkout changed during this work, including unrelated aircraft, physics and accident/economy work and external commits. We did not stage or commit. `sources.json` records the menu-source snapshot; normal capture/test logs predate later accident-report integration. The final display experiment uses detached base `ad8ea65b` plus the menu follow-up changes, with a copied Godot import cache, so unrelated in-progress flight edits cannot invalidate its result. This is a source-run check, not a fresh export proof.

Remaining gates: the complete advanced-tab/pseudo-locale matrix; every Windows DPI mode and monitor transition; real gamepad/radio hardware; rendered ink bounds and all composited contrast states; performance p95; signed/exported builds and other OSes; first-time user studies. Audio/safe-margin settings, thumbnail catalog, paused-weather staging and the rest of the page refinement remain in the active plan. No new aircraft geometry, physics tuning, recording changes, downloaded commercial screenshots or generated UI art were introduced.

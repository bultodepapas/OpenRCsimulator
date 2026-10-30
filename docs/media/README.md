# Presentation media

## README gallery

The [root README](../../README.md) uses **16 images captured on 2026-10-28 and 2026-10-29 (local time) at 1920×1080**: ten model views and six application screenshots. All use native Windows Godot 4.8-beta1, Compatibility/OpenGL and an NVIDIA GeForce RTX 3090. The application's 3D render scale was 1.0. The images are unedited PNGs, copied directly from the capture output.

[readme-captures.json](readme-captures.json) records image hashes, model identities, capture-tool hashes and the studio source state. [readme-gameplay.json](readme-gameplay.json) records application capture times and camera settings; per-image session details override the original session details when present. The receipts identify development captures from separate sessions, not a pristine release build. They do not establish physics accuracy or hardware-performance qualification.

| Application view | Capture |
| --- | --- |
| Home: MoonRunner X99 selected, Club field, Day | [ui-home.png](ui-home.png) |
| Workshop: stock Stik appearance | [ui-workshop-appearance.png](ui-workshop-appearance.png) |
| Workshop: stock Stik flight setup | [ui-workshop-setup.png](ui-workshop-setup.png) |
| MoonRunner X99 airborne over Club field | [flight-moonrunner-x99.png](flight-moonrunner-x99.png) |
| Club field overview | [landscape-club-field.png](landscape-club-field.png) |
| Green paradise overview | [landscape-green-paradise.png](landscape-green-paradise.png) |

The MoonRunner X99 image comes from a simulated flight, paused at tick 4667 (19.4458 s) with the close-up camera and HUD hidden. The landscape pair uses the same elevated camera position and angles; these are scenery overviews, not pilot-eye views. Home and Workshop are interface captures. The debug sessions used isolated profiles and exited without a crash or leaked objects.

Supporter marks retain their original sources and acknowledgment scopes in [BRANDS.md](../../site/BRANDS.md). Aircraft asset terms remain in [aircraft licensing](../AIRCRAFT-LICENSING.md); a screenshot is not a license determination.

## Aircraft stills

Production builders supply the current geometry and materials. A separate studio camera fits each model with a 12% image margin, neutral lights and a dark background. These views do not depict flown maneuvers.

| Model | Current studio view |
| --- | --- |
| Jensen Das Ugly Stik 60 | [View](studio-jensen-das-ugly-stik-60.png) |
| Great Planes Extra 300S .60 | [View](studio-gp-extra-300s-60.png) |
| P-51D Mustang 1/4 | [View](studio-p51d-mustang-120.png) |
| F4U-1D Corsair 1/4.5 | [View](studio-f4u-corsair-250.png) |
| Vantage Jet | [View](studio-sebart-avanti-s-a200-p100rx.png) |
| Turbo Lumber Evolution | [View](studio-turbo-lumber-evolution.png) |
| MoonRunner X99 | [View](studio-moonrunner-x99.png) |
| X-Cell research trainer, HX-700 visual surrogate | [View](studio-xcell-60-research.png) |
| Bisonte MT8 | [View](studio-mt8-bisonte.png) |
| MONSTER CAR 2 | [View](studio-monster-car-2.png) |

All 13 playable catalog/ground configurations were rendered and inspected. The README retains one view per airframe or vehicle; the three additional glow Stik configurations share its visual family, so their redundant images stay outside Git. All ten retained model views were checked for clipping and missing geometry.

## Reproduce

Use the pinned engine and imported assets. Coordinate rendered processes and imports with other work in the same checkout. Keep raw attempts under ignored `tmp/`; retain only images used by the README.

From the repository root in PowerShell:

```powershell
$ReadmeGodot = (Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
$ReadmeOutput = Join-Path (Get-Location) 'tmp/readme-studio-new'
python tools/godot/run_checked.py --label readme-studio --timeout 1200 --require-text 'README_RENDER_OK' -- $ReadmeGodot --path app --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy --script (Resolve-Path 'tools/readme/capture_aircraft.gd').Path -- "--out-dir=$ReadmeOutput" --stills-only
```

The output directory must be fresh and empty. By default the helper follows `Catalog.flyable_ids()`, then adds both trucks. Use repeated or comma-separated `--aircraft=ID` arguments to select the views needed for publication or retry a model. Omitting `--stills-only` also captures 72 orbit frames per vehicle; this is an optional studio animation.

For application screenshots use the [debug bridge](../../tools/debug/README.md), with its isolated profile and explicit session port:

```powershell
$env:OPENRC_GODOT = $ReadmeGodot
python tools/debug/debugctl.py launch --resolution 1920x1080 --port 47880
$env:OPENRC_DEBUG_BRIDGE = '47880'
python tools/debug/debugctl.py window
python tools/debug/debugctl.py eval 'expr=tree.root.scaling_3d_scale'
python tools/debug/debugctl.py screenshot format=png path=C:/DEVELOPMENT/OpenRCsimulator/tmp/readme-home-new.png
```

Use the returned port if launch selected another. Wait for the intended scene/model to finish loading. Require a 1920×1080 viewport and screenshot response; omit `max_width` to avoid downscaling. Drive Home, Workshop and flight through the bridge and inspect every image. An attached controller can trigger a recovery pause: select Keyboard in the isolated profile or satisfy the controller's arming flow before flight capture. Stop only the session you launched.

For the matching landscape overview, after entering a flight and hiding overlays, set `flight._camera.set_meta('pilot_station', [-120.0, 0.0, 0.0])`, `flight._rig.look_height = 85.0` and `flight._rig.look = Vector2(10.0, -25.0)` through the bridge. Reapply after changing landscape. Record the actual engine, renderer, viewport, scale, active landscape, flight state and source context with each refresh.

Package the selected studio run and separately captured application images:

```powershell
python tools/readme/package_media.py $ReadmeOutput docs/media --image tmp/readme-home-new.png=ui-home.png
```

Repeat `--image SOURCE=NAME` for other screenshots. The packager preserves PNG bytes, verifies capture hashes and dimensions, and writes `studio-<catalog-id>.png` plus `readme-captures.json`. Supplied screenshots do not inherit studio-session provenance; update their separate `readme-gameplay.json` receipt. Selective runs retain separate studio sessions. If animation frames exist, the new GIF is `aircraft-tour-current.gif`; the historical GIF and manifest remain unchanged. Pillow is provided by the existing [visual environment](../../app/tests/visual-env.sh).

## Historical media

The original [manifest.json](manifest.json), eight 960×540 stills and [aircraft-tour.gif](aircraft-tour.gif) retain their 2026-10-16 provenance: source `404bb1bfd225f25159a03d60dfebdf89622936e6`, native Windows Godot 4.7.2, Compatibility/OpenGL, RTX 3090. The tour has 576 frames at 800×450, 60 ms per frame, 34.56 s total, with 64-color undithered frames. It predates the Corsair and MoonRunner X99. [flight.png](flight.png) and [flight.json](flight.json) retain the earlier Stik flight capture. These files are no longer used by the root README.

Earlier UI and landscape evidence stays with [UI-33](../research/menu-investigations/UI-33/README.md), [AE-24](../research/aircraft-editor/AE-24/README.md), [AE-12/13](../research/aircraft-editor/AE-12-13/README.md) and [L21–L24](../research/landscape-upgrade/L21-24/README.md). Website partner/support-strip captures remain in [site/](site/), with verification in the [website guide](../../site/README.md#web-06--manufacturer-acknowledgments-2026-10-17).

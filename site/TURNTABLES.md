# Aircraft turntable assets

`assets/turntables.json` describes six models with row-major sprite sheets. Each original sheet contains 36 native Godot renders in a 6 by 6 grid; each frame is 640 by 360 pixels. Each model also has a 320 by 180 per-frame sheet derived from its accepted original WebP atlas and a 640 by 360 poster from frame 4 (40 degrees) for a fast initial image or load fallback. Frame 0 uses a 0 degree camera azimuth. Subsequent frames advance by 10 degrees around world Y, covering a complete 360 degree orbit without a duplicated endpoint.

The viewer uses the smaller sheet only when the displayed stage multiplied by the device pixel ratio fits within 320 by 180 physical pixels. It otherwise uses the original sheet, including for the 1920 by 1080 layout. On enlargement or a pixel-ratio change it upgrades the sheet if needed while preserving the current angle; shrinking does not trigger a downgrade request. A failed upgrade leaves the current view usable. The two-sheet decoded cache includes the resolution in its key. Sheet URLs carry their manifest SHA-256 as a cache version. When publishing a changed manifest, update the `manifestURL` release query in `viewer.js` as well as the viewer script query in the generated pages.

## Models

| Key | Catalog ID | Visual model |
| --- | --- | --- |
| `stik` | `jensen-das-ugly-stik-60` | Jensen Das Ugly Stik 60 |
| `extra` | `gp-extra-300s-60` | Great Planes Extra 300S .60 |
| `mustang` | `p51d-mustang-120` | P-51D Mustang 1/4 |
| `jet` | `sebart-avanti-s-a200-p100rx` | Vantage Jet |
| `timber` | `turbo-lumber-evolution` | Turbo Lumber Evolution |
| `heli` | `xcell-60-research` | HX-700 helicopter visual |

All models are built with `res://render/airplane.gd` from the catalog. The helicopter entry follows that adapter's HX-700 model builder and imported GLB. It is a real model orbit, not a rotated still. Captures are for visual presentation and do not validate flight behavior.

## Capture settings

The capture uses a color background of `#101820`, ambient light `#c8c8c8` at energy `0.45`, and three directional lights at rotations `[-47, -32, -9]`, `[-24, 145, 12]`, and `[48, -28, 0]` degrees with energies `0.90`, `0.38`, and `0.40`. The perspective camera uses a 38 degree field of view, 22 degree elevation, and a distance of 1.28 times the model's largest visible bounds extent. Each aircraft is centered from the bounds of its rendered meshes. The JSON manifest records these settings.

Frames are assembled left to right, then top to bottom. The sheets are WebP at quality 95 to retain fine outlines. Small frames are resized individually with Lanczos filtering from the original compressed WebP, then encoded into a new WebP sheet; they are not fresh lossless renders. `turntables.json` retains the original capture provenance and adds each derivative's dimensions, byte size and SHA-256, plus the derivative script and source-manifest hashes. The source-manifest hash identifies the manifest read at the start of the derivative run; it changes on a subsequent run when the input manifest has changed. For a fresh capture, that hash is null because the source atlases are generated in the same run. The original provenance records the capture engine and renderer, camera and lighting configuration, original sheet hashes, capture and package script hashes, and model, catalog, and project source inputs.

## Rebuild

Use the pinned native Godot build and Pillow 12.3.0. The render process starts hidden and writes its temporary PNG frames under the user's temporary directory:

```powershell
$godot = Join-Path $PWD '.tools\Godot_v4.7.2-stable_win64_console.exe'
$script = (Resolve-Path 'site/capture_turntables.gd').Path
$render = Join-Path $env:TEMP 'openrc-turntables'
$arguments = "--path app --script `"$script`" -- --out-dir=`"$render`""
$process = Start-Process -FilePath $godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
if ($process.ExitCode -ne 0) { throw "Godot turntable capture failed with exit code $($process.ExitCode)." }
python site/package_turntables.py --capture-dir $render
```

The package script validates the complete frame set and writes both sheet sizes, the posters and `assets/turntables.json`. It does not change aircraft builders, simulation data, or the source render assets.

To regenerate only the small sheets from the accepted originals without recapturing, use Pillow 12.3.0 and run:

```sh
python3 site/package_turntables.py --source-manifest site/assets/turntables.json
```

This validates every original sheet and poster against the input manifest before writing, preserves the original assets and capture provenance, and records the derivative hashes. To inspect a candidate first, supply separate `--asset-dir` and `--manifest` paths under `tmp/`.

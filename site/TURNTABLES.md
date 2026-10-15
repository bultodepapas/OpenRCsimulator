# Aircraft turntable assets

`assets/turntables.json` describes six row-major sprite sheets. Each sheet contains 36 native Godot renders in a 6 by 6 grid; each frame is 640 by 360 pixels. Frame 0 uses a 0 degree camera azimuth. Subsequent frames advance by 10 degrees around world Y, covering a complete 360 degree orbit without a duplicated endpoint. Each model also has a 640 by 360 poster from frame 4 (40 degrees) for a fast initial image or load fallback.

## Models

| Key | Catalog ID | Visual model |
| --- | --- | --- |
| `stik` | `jensen-das-ugly-stik-60` | Jensen Das Ugly Stik 60 |
| `extra` | `gp-extra-300s-60` | Great Planes Extra 300S .60 |
| `mustang` | `p51d-mustang-120` | P-51D Mustang 1/4 |
| `jet` | `sebart-avanti-s-a200-p100rx` | Ventage Jet |
| `timber` | `turbo-lumber-evolution` | Turbo Lumber Evolution |
| `heli` | `xcell-60-research` | HX-700 helicopter visual |

All models are built with `res://render/airplane.gd` from the catalog. The helicopter entry follows that adapter's HX-700 model builder and imported GLB. It is a real model orbit, not a rotated still. Captures are for visual presentation and do not validate flight behavior.

## Capture settings

The capture uses a color background of `#101820`, ambient light `#c8c8c8` at energy `0.45`, and three directional lights at rotations `[-47, -32, -9]`, `[-24, 145, 12]`, and `[48, -28, 0]` degrees with energies `0.90`, `0.38`, and `0.40`. The perspective camera uses a 38 degree field of view, 22 degree elevation, and a distance of 1.28 times the model's largest visible bounds extent. Each aircraft is centered from the bounds of its rendered meshes. The JSON manifest records these settings.

Frames are assembled left to right, then top to bottom. The sheets are WebP at quality 95 to retain fine outlines. `turntables.json` records the capture engine and renderer, camera and lighting configuration, individual sheet SHA-256 hashes, the capture and package script hashes, and hashes for the model, catalog, and project source inputs. Its source tree digest identifies the complete listed input set.

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

The package script validates the complete frame set and writes six WebP sheets plus `assets/turntables.json`. It does not change aircraft builders, simulation data, or the source render assets.

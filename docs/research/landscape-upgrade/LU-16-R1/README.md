# LU-16-R1 — Closer mountains from downloaded relief

2026-10-20 · Club field, Godot 4.7.2 Compatibility, native Windows / RTX 3090.
Baseline checkout: `9a55ea7acd92cfe5a888f2dba9428d756b69384c`.

The former sinusoidal ridge at N 3.5–10.5 km is replaced by a reduced SRTM crop
from Colombia's Eastern Cordillera. Its first mesh row is now N 1.6 km, with
the back row at 8.6 km, a 13 km width and a maximum height of 1,482.4 m.
The silhouette, branching valleys, lower green slopes and higher rocky faces
come from the retained relief and the field's shared lighting/haze.

[Before](before.png) · [After](after.png) · [Dusk](dusk.png) · [Night](night.png) · [Flight overview](flight.png).

The existing ridge triangle order exposed the underside under Godot's clockwise
front-face rule. The new order faces upward, and a regression checks every triangle
and each shared chunk edge. No extra surface is used to conceal the problem.

## Source investigation and selection

- [Mapzen Terrain Tiles / AWS Open Data](https://registry.opendata.aws/terrain-tiles/)
  supplies downloadable elevation data without an account. The selected Colombian
  tile uses SRTM. [Provider attribution and rights](https://github.com/tilezen/joerd/blob/master/docs/attribution.md#srtm).
  The exact archive is SHA-256 pinned; a lossless crop is retained for offline regeneration.
- [Godot's 3D optimization guide](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html)
  supports bounded geometry, cullable meshes and avoiding unnecessary shadow work.
  Retain the existing four spatial chunks rather than adding a terrain plugin.
- [Godot spatial shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)
  provide the normal, view transform and material/fog interfaces used here.
- Free [3DTexel heightmaps](https://3dtexel.com/landscape-backdrop/),
  [GameDevGary heightmaps](https://gamedevgary.itch.io/50-free-terrain-heightmaps)
  and [Poly Haven Aerial Rocks 01](https://polyhaven.com/a/aerial_rocks_01)
  were considered. The retained SRTM crop provides real drainage structure without
  a large asset pack or additional photographic material downloads.

Exact source, license, hashes, geographic crop and artistic transforms:
[source provenance](../../../../assets/landscape/mountains/README.md).
The original full download is 15 MiB; the retained source crop is 1.25 MiB.
Only 42,042 bytes of elevation JSON and a 306,313-byte PNG enter the runtime.

## Cost and implementation

Four chunks, **12,288 triangles**, one scene-local material shared by the chunks,
no terrain process callbacks and no mountain shadow-caster passes. A single
513 × 193 RGBA data texture holds world-space normals and gentle cavity shading.
It is lossless, mipmapped and sampled once per fragment; it adds **527,104 GPU
bytes** in the native capture. The elevation grid is validated and cached once.
Materials still update through the existing field time-of-day interface.

The same production capture harness, cameras, 1280 × 720 viewport and disabled
VSync were used before and after. Baseline: 180 measured frames per view;
candidate: 360. This is a short render-only measurement, not a full-flight,
repeated alternating benchmark or lower-end hardware qualification.

| View | Before p95 ms | After p95 ms | Total draws, before = after | Primitives, before = after |
| --- | ---: | ---: | ---: | ---: |
| Pilot north | 1.866 | 2.002 | 84 | 204,089 |
| Raised 120 m | 1.308 | 1.537 | 39 | 129,491 |
| Farm long lens | 1.337 | 1.416 | 62 | 169,377 |
| Aircraft readability view | 1.987 | 1.951 | 312 | 302,745 |

Raw samples, engine/device identity and arguments:
[before](before-report.json), [after](after-report.json), [dusk](dusk-report.json).
The small timing changes include desktop scheduling noise; no speedup is claimed.
The larger on-screen mountain area and one texture fetch are an intentional bounded
cost. No geometry, draw-count or additional shadow-pass growth was observed.

## Verification

- Offline `python tools/terrain/import_mountains.py --check` matches both
  generated outputs to the retained source. A disposable edited elevation
  profile is rejected; the retained crop's SHA-256 is also checked before generation.
- Native editor import and rendered day/dusk/night captures complete without
  script or shader errors. Captures were visually inspected.
- `test_landscape_horizon.gd`: **45 checks, zero failed**; includes triangle
  orientation, shared edges, finite/bounded geometry, texture/mip size,
  scene-local lighting and advancing time without rebuilt topology.
- `test_landscapes.gd`, headless: **49 checks, zero failed**, including
  Club → Green → Club, saved relaunch, aircraft and helicopter simulation.
- Native landscape captures: **54 checks, zero failed** with device enumeration
  isolated to keyboard in this [retained fixture](test_landscapes_keyboard.gd.txt).
  The unchanged native test initially failed three simulation-advance assertions
  because the connected controller correctly held each launch paused for confirmation.
  That run is retained in `landscapes-59_65rie.log`; production input code and
  the canonical landscape fixture were not changed.
- `test_field_integration.gd`: all checks passed.
- `test_world_flow.gd`: **26 checks, zero failed**.
- `test_ui_runway.gd`: all checks passed, including the full aircraft catalog.
  Its first run reached the 120-second timeout; the complete rerun used a
  240-second limit. Both logs are retained.

[Check results, commands and final source hashes](verification.json);
checked-runner logs are retained alongside this report. The existing unsupported
maple-material wind warning occurs in the baseline and candidate. Physical terrain
collision, target-GPU acceptance and independent pilot readability remain outside
this visual delivery. L12/L13 still own physical heightfield integration; no
physical model, input tape or golden flight was changed. Green paradise retains
its deliberately flat presentation. The full `app/test.sh` and release exports
were not run for this focused visual delivery.

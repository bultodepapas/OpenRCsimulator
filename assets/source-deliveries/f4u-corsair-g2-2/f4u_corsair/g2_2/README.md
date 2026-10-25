# F4U Corsair g2.2 — complete livery adaptation

All 13 existing paints adapted to the owner-approved g2.1 model. The g2.1 delivery remains unchanged.

## Files

Open `previews/index.html` for the visual selector. Each paint has a packed editable Blender 5.2.2 source and a standalone GLB. Native sources open at frame 0; GLBs contain frame 100 with gear stowed. Runtime maps are under `textures/liveries/<id>/runtime/`. Editable OpenRaster layers use the current atlas; Carbon 12 retains a 4096-square authoring source and filtered 2048-square runtime maps.

| Paint | Blender | GLB | GLB MB |
| --- | --- | --- | ---: |
| Naval 308 — Midnight | `source/aircraft_game.blend` | `export/aircraft.glb` | 20.03 |
| Coastal Three Tone | `source/aircraft_three_tone.blend` | `export/aircraft_three_tone.glb` | 20.02 |
| Super Corsair 57 / SOHIO | `source/aircraft_scarlet.blend` | `export/aircraft_scarlet.glb` | 20.42 |
| Sunburst Splash | `source/aircraft_splash.blend` | `export/aircraft_splash.glb` | 19.66 |
| Spectrum Wings | `source/aircraft_spectrum.blend` | `export/aircraft_spectrum.glb` | 19.82 |
| Blue Angels Corsair | `source/aircraft_blueangels.blend` | `export/aircraft_blueangels.glb` | 19.59 |
| Thunderbirds Corsair | `source/aircraft_thunderbirds.blend` | `export/aircraft_thunderbirds.glb` | 19.64 |
| Chrome 07 Corsair | `source/aircraft_chrome.blend` | `export/aircraft_chrome.glb` | 21.37 |
| Sharkmouth P-40 Inspired Corsair | `source/aircraft_p40.blend` | `export/aircraft_p40.glb` | 21.87 |
| Captured Corsair / Japan 09 | `source/aircraft_japan.blend` | `export/aircraft_japan.glb` | 21.69 |
| Captured Corsair / Beute 10 | `source/aircraft_luftwaffe.blend` | `export/aircraft_luftwaffe.glb` | 21.78 |
| Deserto 11 / Italian desert concept | `source/aircraft_italy.blend` | `export/aircraft_italy.glb` | 22.05 |
| Carbon 12 / Aero Sport | `source/aircraft_carbon.blend` | `export/aircraft_carbon.glb` | 27.58 |

## What changed

The original aircraft-space painters were regenerated against the g2 UV layout. Direct reuse of the old g1 atlas would misplace markings. Original palettes, numbers, sponsors, camouflage, dirt, graphics and wheel accents are retained. Physical-side projection fixes formerly mirrored side lettering; tail numbers and vertical registration are handled independently. Paint crosses the reference closed positions of flaps and gear doors. Compartment coatings are a removable top layer in each editable file.

The propeller uses g2.1's two-face blade UV and each design's corresponding blade image. Spinner paint is restricted to the existing connected nose-cap component; hub hardware stays metallic. Polished Chrome 07 keeps metallic skins and blade finish with local exhaust/gun deposits. Carbon 12 combines its directional twill detail with the g2 surface bake, keeps graphite/orange wheel accents, gloss resin and restrained orange emission. Direction maps are filtered as doubled-angle vectors, including correct 16-bit source decoding.

## Conservation and validation

Every source retains exactly **337,664 triangles, 82 nodes, all geometry, corner normals, UV arrays, parent relationships and section tags** from g2.1. All 82 world transforms at all 101 gear poses compare exactly after saving and reopening each source. Material assignments change only for the existing spinner cap. Runtime budgets: 57–58 surfaces, 14–15 materials, 19.59–27.58 MB per GLB; no runtime map exceeds 2048 pixels. All images are packed/embedded.

All 13 team `f4u-g2` preflights pass without warnings. The separate livery audit checks final hashes, hierarchy/frame-100 transforms, image bounds and shared AO descriptors. Native snapshots cover 8,282 node/pose matrices per variant. See `checks/livery_suite.json` and `checks/accepted_geometry_signature.json`.

The F4U-18 Godot bench captures eight fixed cameras per livery at 1920×1080 using the Compatibility renderer. The ten-frame visual runs are import/appearance evidence, not performance qualification. Production simulator integration, freeze, compile, and production livery/fold/flap tests are not part of this author delivery. Geometry/clearance and I1 shading qualifications are inherited unchanged from accepted g2.1. Directional carbon and coat appearance depends on renderer support; baked colour, roughness and normal detail remain available independently.

Blender's exporter prints inherited tangent warnings for the unchanged g1.24 wheel meshes; those wheel materials have no normal map. Geometry is intentionally preserved; the Godot import is configured to generate tangents. These are distinct from the warning-free team preflight.

## Re-export

Open the desired packed source in Blender 5.2.2 and run `source/scripts/export_livery.py`. It uses the source's `livery_id`, exports to its matching GLB, restores frame 0 in memory and deduplicates texture descriptors. No R59 or g1 file is needed for this route. The included migration and painter scripts document authoring provenance; rebuilding from scratch additionally requires the accepted g2.1 source and original source inventory. Raster caches are intentionally omitted and are regenerated from `uv-layout.json` when needed.

The catalog includes 13 paints because the owner requested all existing paints after approving g2.1. This supersedes the earlier request to postpone other paints. Historical capture/desert schemes are fictional Corsair interpretations; exhibition schemes adapt existing designs to this airframe and are not claims of documented historic aircraft.

`SHA256SUMS.txt` covers every delivered file except itself. The ZIP is checked member by member and has an external SHA-256 file.

# F4U Corsair — Blue Angels-inspired paint · g1.13

Open **source/aircraft_blueangels.blend** for the fifth paint. Gallery: **previews/index.html**.

Cobalt blue bodywork with yellow leading edges, tips, cowling lip, canopy trim and propeller cone. Yellow U.S. NAVY lettering, interpreted Blue Angels script, tail number 1 and an underside arrow complete the scheme. Black propeller blades keep their yellow tips. Subtle panel finish and contrasting walkways preserve the model's detail.

This is a Blue Angels-inspired concept adapted to the existing Corsair, not a historical aircraft reconstruction. Colours are visual choices, not measured official paint chips. The script is a typographic interpretation. No photographic pixels were incorporated.

## Five complete liveries

| Livery | Blender | GLB |
|---|---|---|
| Blue Angels-inspired · new | source/aircraft_blueangels.blend | export/aircraft_blueangels.glb |
| Spectrum Wings | source/aircraft_spectrum.blend | export/aircraft_spectrum.glb |
| Sunburst Splash | source/aircraft_splash.blend | export/aircraft_splash.glb |
| Naval 308 | source/aircraft_game.blend | export/aircraft.glb |
| 57 / SOHIO | source/aircraft_super57.blend | export/aircraft_super57.glb |

The four earlier models and their textures are preserved byte for byte. The legacy three-tone texture atlas is also retained. aircraft.glb remains the naval paint for compatibility; select aircraft_blueangels.glb for the new scheme.

## Editable paint

- textures/liveries/blueangels/source.ora: eight layers at 2048 × 2048, with individual PNG layers alongside it. Blue base, yellow trim, fuselage lettering, tail number, wing lettering, belly arrow, service finish and atlas padding.
- interiors/source.ora: four layers with BA interior identification. Existing interior normal and ORM maps are preserved.
- basecolor.png uses sRGB; orm.png and roughness.png contain linear data. Painted surfaces remain nonmetallic.
- The yellow cone uses a material on its existing connected mesh component. The black/yellow propeller texture and its existing extra UV layer are preserved.

All model images are packed into Blender and embedded in the GLB. The mesh and UVs are unchanged. Preview colour management is Standard / None, exposure -0.8; lighting and display settings affect the apparent colour and gloss.

## Validation

**99,729 triangles · 58 surfaces · 14 materials · eight images.** Scale 1:4.5; wingspan 2.77777 m. Geometry, all UV sets, hierarchy and all 101 landing-gear poses match the previous model.

The Blender source is saved at frame 0 with gear extended. The GLB follows the existing delivery contract: frame 100, gear retracted, with no exported animation clips. The exported GLB was reimported, its transforms checked and actual runtime views rendered. Reexporting the packed Blender from an isolated folder produced a byte-identical GLB without external textures.

The 2048 atlas limits tiny lettering and very close-up edges. This paint revision does not include a new Godot run or continuous collision simulation; the earlier mechanics are preserved and their transformations checked.

## Reproduce

With Blender 5.2.2 LTS, from this delivery directory:

```text
blender -b source/aircraft_blueangels.blend --python-exit-code 1 --python source/scripts/export_blueangels13.py
blender -b source/aircraft_blueangels.blend --python-exit-code 1 --python source/scripts/verify_blueangels_structure13.py
blender -b source/aircraft_blueangels.blend --python-exit-code 1 --python source/scripts/roundtrip_blueangels13.py
```

Regenerate paint with Python plus NumPy/Pillow using build_blueangels13.py and build_blueangels_interiors13.py in source/scripts, then run export_blueangels13.py with -- --refresh-paint. blueangels_views13.py reproduces the views. Historical scripts are retained as dependencies and provenance; do not run them indiscriminately against the new source.

## References

The [U.S. Navy's FRC Southeast paint report](https://www.dvidshub.net/news/376027/fleet-readiness-center-southeast-plays-critical-part-providing-blue-angels-with-new-super-hornet-aircraft) describes cobalt blue and yellow trim. The [official Blue Angels history](https://www.blueangels.navy.mil/history/events.htm) informed the use of script, canopy-side stripes and a belly arrow. Their placement here is a design adaptation to the Corsair.

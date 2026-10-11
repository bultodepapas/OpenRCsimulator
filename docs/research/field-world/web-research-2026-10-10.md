# Field world: official docs and forums checked (2026-10-10)

**Status:** desk research, used by FW-23/26/27/35. What each source confirms, corrects or leaves open for the night work. Engine claims were also checked in the pinned 4.7.2 source (`drivers/gles3/shaders/*.glsl`).

## Engine (Godot 4.7, Compatibility)

| Question | Source | Finding | Consequence |
| --- | --- | --- | --- |
| Auto-exposure in Compatibility? | [CameraAttributes (official)](https://docs.godotengine.org/en/latest/classes/class_cameraattributes.html) | Forward+ only | Scripted adaptation kept (FW-23); now follows the view target and the ground's share of the picture |
| Ready-made day/night for Compatibility? | [Sky3D (asset store)](https://store.godotengine.org/asset/tokisangames/sky3d/) | Supports Compatibility; manages lighting and exposure | Not adopted: reads `TIME`, and our sky must equal the haze formula (L2). Kept as a reference |
| Light limits | [Lights and shadows (official)](https://docs.godotengine.org/en/4.2/tutorials/3d/lights_and_shadows.html) | 8 omni + 8 spot per mesh; raising it costs performance and shader compile time | Floods capped at 4 in the loader; no shadowed positional lights |
| ALBEDO colour handling differs by backend | [#88214](https://github.com/godotengine/godot/issues/88214) (open), [#70797](https://github.com/godotengine/godot/issues/70797) | Users see different shader albedo colours in Compatibility vs Forward+, unshaded included; no fix linked | Consistent with our finding (cubic `srgb_to_linear` on every ALBEDO, scene.glsl 2398); keep the `engine_srgb` encoding and re-check on engine upgrades |
| Sky brightness inconsistencies in Compatibility | [PR #95662](https://github.com/godotengine/godot/pull/95662), [#92779](https://github.com/godotengine/godot/issues/92779) | Sky colour and luminance-multiplier handling differs across backends; disabling reflections misbehaves until another source is set once | No issue found for the double exposure in the radiance path: worth reporting upstream with our minimal probe. Our ToD mode avoids the radiance path (ambient colour) |
| Tonemapper for night | [Godot 4.4 features (CG Channel)](https://www.cgchannel.com/2025/03/5-key-features-for-cg-artists-in-godot-4-4), [GDQuest glossary](https://school.gdquest.com/glossary/tonemap), [Environment.tonemap_agx_* (official 4.7)](https://docs.godotengine.org/en/4.7/classes/class_environment.html) | ACES is more contrasted with darker shadows; AgX handles bright scenes better; AgX has white (16.29) and contrast controls | Pinned source: Godot's ACES fit has a black point; its AgX (allenwp curve) has a sigmoid toe and soft shoulder. **AgX adopted below a −1° sun** (FW-26); day keeps L1b's ACES |
| Night perception | [Kirk & O'Brien 2011](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2011/EECS-2011-91.pdf), [SIGGRAPH entry](https://history.siggraph.org/?p=114629), [VIRUP](https://arxiv.org/pdf/2110.04308) | Global scotopic shifts give a blue haze over lit areas; per-pixel shifts below a luminance threshold avoid it | FW-26's remaining scotopic grade must be per-pixel and spare lamps and floodlit ground; the cool moonlight convention stays |

## Field and aircraft lighting

| Question | Source | Finding | Consequence |
| --- | --- | --- | --- |
| Wind-turbine obstruction lights | Summaries of FAA AC 70/7460-1M: [Kansas testimony](https://kslegislature.gov/li_2022/b2021_22/committees/ctte_spc_select_committee_on_wind_turbine_lighti_1/documents/testimony/20221027_24.pdf), [Flash Technology buyer's guide](https://flashtechnology.com/faa-wind-buyers-guide) | L-864 red flashing, synchronised within 0.05 s, 30 flashes/min (±3) | FW-40 at 30 fpm = 0.5 Hz (512/1024 Hz, seamless on `sim_clock`). Confirm against the FAA's current revision before calling it measured |
| RC night-flying lights | [Model Airplane News](https://www.modelairplanenews.com/?p=222150), [Flite Test](https://www.flitetest.com/articles/night-flying), [Elektor](https://www.elektormagazine.com/magazine/201011/19491) | Colour coding is about orientation: red left, green right, white tail strobe; wingtip colour differences show heading; high-intensity red and blue on the wings show landing attitude | Confirms the kit; supports D-8 (colour on the belly/wing undersides needs model anchors) |

## Not found

No forum thread or issue reproduces the radiance double exposure; RCGroups threads did not surface in search. Both stay open questions rather than claims.

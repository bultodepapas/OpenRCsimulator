Viewport 1280×720, llvmpipe (LLVM 20.1.2, 256 bits), Godot 4.7.2-stable (official), scene detail low.
Primitives count every MultiMesh instance (instanced LOD nodes measured one by one).

**pilot** (8 views): total drawn primitives max 756,608 (median 405,042), draws max 297 (median 89); sun shadow pass up to 68,838 counter primitives / 21 draws.
**ground** (8 views): total drawn primitives max 811,001 (median 628,174), draws max 327 (median 188); sun shadow pass up to 66,554 counter primitives / 20 draws.
**aerial** (4 views): total drawn primitives max 551,768 (median 240,870), draws max 335 (median 63); sun shadow pass up to 22,316 counter primitives / 18 draws.
Renderer estimates after the first frame: textures 431 MiB, buffers 41 MiB, video 472 MiB.

| Subsystem | Source triangles | Without LOD | Pilot prims max | Pilot draws max | Ground prims max | Ground draws max | Aerial prims max | Aerial draws max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| scenery_ImportedVegetationBatches | 116,962 | 5,272 | 328,598 | 28 | 311,178 | 30 | 109,106 | 22 |
| scenery_Population | 275,158 | 897 | 187,176 | 30 | 195,554 | 30 | 90,136 | 30 |
| scenery_cells | 157,395 | 157,395 | 91,495 | 18 | 124,285 | 26 | 35,770 | 15 |
| scenery_ParkedAircraft | 273,421 | 38,845 | 61,485 | 155 | 123,699 | 179 | 92,875 | 179 |
| field_rough | 84,960 | 84,960 | 84,960 | 1 | 84,960 | 1 | 84,960 | 1 |
| field_flightline_barrier | 81,601 | 38,840 | 81,603 | 6 | 74,193 | 6 | 42,926 | 6 |
| field_Lake | 65,224 | 44,952 | 54,598 | 13 | 57,874 | 13 | 54,598 | 13 |
| field_DistantRidges | 27,648 | 27,648 | 27,648 | 4 | 13,824 | 2 | 0 | 0 |
| scenery_BotanicalHabitats | 32,613 | 568 | 12,145 | 18 | 14,155 | 20 | 3,351 | 14 |
| field_NearGrass | 12,441 | 0 | 12,441 | 3 | 12,441 | 3 | 3,725 | 3 |
| scenery_pit_shelters | 12,096 | 12,096 | 12,096 | 2 | 12,096 | 2 | 12,096 | 2 |
| world_AirfieldLighting | 26,386 | 8,462 | 8,192 | 15 | 6,026 | 16 | 5,866 | 16 |
| field_pilot_station | 6,124 | 6,124 | 6,126 | 2 | 6,126 | 2 | 6,126 | 2 |
| field_treeline | 10,080 | 10,080 | 5,460 | 4 | 5,460 | 4 | 4,344 | 3 |
| field_windsock | 5,266 | 5,266 | 5,268 | 4 | 5,268 | 4 | 5,268 | 4 |
| field_Countryside | 6,764 | 6,764 | 2,516 | 8 | 2,962 | 11 | 2,884 | 9 |
| scenery_PopulationContacts | 1,271 | 1,271 | 1,271 | 1 | 1,271 | 1 | 1,271 | 1 |
| scenery_AirfieldDetail | 2,102 | 0 | 926 | 3 | 926 | 3 | 0 | 0 |
| scenery_contact_shadows | 702 | 702 | 216 | 6 | 612 | 18 | 558 | 15 |
| world_Campfire | 305 | 305 | 610 | 4 | 610 | 4 | 610 | 4 |
| world_FieldLights | 240 | 240 | 432 | 12 | 432 | 12 | 432 | 12 |
| scenery_hedges | 256 | 256 | 256 | 2 | 128 | 1 | 0 | 0 |
| scenery_Motion | 296 | 296 | 160 | 4 | 194 | 2 | 160 | 1 |
| scenery_BuildingRoofs | 100 | 100 | 32 | 8 | 68 | 17 | 28 | 7 |
| scenery_Birds | 24 | 24 | 24 | 1 | 24 | 1 | 0 | 0 |
| field_FlightCueShadows | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| scenery_WoodlandEdges | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| world_SunGlare | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

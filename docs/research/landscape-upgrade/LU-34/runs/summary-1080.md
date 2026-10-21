Viewport 1920×1080, llvmpipe (LLVM 20.1.2, 256 bits), Godot 4.7.2-stable (official).

**pilot** (8 views): total drawn primitives max 412,840 (median 264,704), draws max 326 (median 98); sun shadow pass up to 40,116 primitives / 22 draws.
**ground** (8 views): total drawn primitives max 492,743 (median 319,984), draws max 359 (median 196); sun shadow pass up to 44,851 primitives / 24 draws.
**aerial** (4 views): total drawn primitives max 438,160 (median 161,611), draws max 367 (median 64); sun shadow pass up to 28,821 primitives / 22 draws.
Renderer estimates after the first frame: textures 537 MiB, buffers 44 MiB, video 581 MiB.

| Subsystem | Source triangles | Without LOD | Pilot prims max | Pilot draws max | Ground prims max | Ground draws max | Aerial prims max | Aerial draws max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| scenery_cells | 168,031 | 168,031 | 91,773 | 20 | 134,369 | 26 | 45,578 | 15 |
| scenery_ParkedAircraft | 273,421 | 0 | 69,908 | 155 | 105,222 | 179 | 79,866 | 179 |
| field_rough | 84,960 | 84,960 | 84,960 | 1 | 84,960 | 1 | 84,960 | 1 |
| scenery_Population | 371,573 | 0 | 78,826 | 49 | 64,594 | 49 | 43,070 | 49 |
| scenery_ImportedVegetationBatches | 101,167 | 0 | 62,627 | 32 | 68,567 | 37 | 51,107 | 30 |
| field_Lake | 65,224 | 44,952 | 45,394 | 13 | 45,688 | 13 | 45,354 | 13 |
| field_flightline_barrier | 81,601 | 38,840 | 39,998 | 6 | 39,998 | 6 | 39,693 | 6 |
| field_DistantRidges | 27,648 | 27,648 | 27,648 | 4 | 13,824 | 2 | 0 | 0 |
| scenery_pit_shelters | 12,096 | 12,096 | 12,096 | 2 | 12,096 | 2 | 12,096 | 2 |
| world_AirfieldLighting | 26,386 | 8,462 | 9,580 | 15 | 7,558 | 16 | 6,106 | 16 |
| scenery_BotanicalHabitats | 89,655 | 500 | 6,864 | 19 | 8,054 | 20 | 6,676 | 17 |
| field_treeline | 10,080 | 10,080 | 5,418 | 4 | 6,168 | 4 | 6,270 | 5 |
| field_pilot_station | 6,124 | 6,124 | 6,126 | 2 | 6,126 | 2 | 6,126 | 2 |
| field_windsock | 5,266 | 5,266 | 5,268 | 4 | 5,268 | 4 | 5,268 | 4 |
| field_Countryside | 6,380 | 6,380 | 2,324 | 8 | 2,908 | 8 | 2,524 | 8 |
| scenery_AirfieldDetail | 4,482 | 0 | 2,624 | 5 | 2,624 | 5 | 0 | 0 |
| scenery_PopulationContacts | 1,391 | 1,391 | 1,391 | 1 | 1,391 | 1 | 1,391 | 1 |
| field_NearGrass | 49,579 | 0 | 1,103 | 3 | 1,103 | 3 | 1,001 | 3 |
| scenery_hedges | 848 | 848 | 848 | 2 | 512 | 1 | 0 | 0 |
| scenery_contact_shadows | 702 | 702 | 216 | 6 | 612 | 18 | 558 | 15 |
| world_Campfire | 305 | 305 | 610 | 4 | 610 | 4 | 610 | 4 |
| world_FieldLights | 240 | 240 | 432 | 12 | 432 | 12 | 432 | 12 |
| scenery_WoodlandEdges | 472 | 472 | 142 | 2 | 252 | 3 | 32 | 1 |
| scenery_Motion | 296 | 296 | 160 | 4 | 194 | 2 | 160 | 1 |
| scenery_BuildingRoofs | 100 | 100 | 32 | 8 | 68 | 17 | 28 | 7 |
| scenery_Birds | 24 | 24 | 24 | 1 | 24 | 1 | 0 | 0 |
| field_FlightCueShadows | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| world_SunGlare | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

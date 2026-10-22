Viewport 1280×720, llvmpipe (LLVM 20.1.2, 256 bits), Godot 4.7.2-stable (official).

**pilot** (8 views): total drawn primitives max 451,503 (median 269,722), draws max 335 (median 98); sun shadow pass up to 75,156 primitives / 28 draws.
**ground** (8 views): total drawn primitives max 523,385 (median 379,976), draws max 367 (median 206); sun shadow pass up to 79,891 primitives / 30 draws.
**aerial** (4 views): total drawn primitives max 437,639 (median 174,572), draws max 375 (median 70); sun shadow pass up to 36,312 primitives / 26 draws.
Renderer estimates after the first frame: textures 473 MiB, buffers 46 MiB, video 519 MiB.

| Subsystem | Source triangles | Without LOD | Pilot prims max | Pilot draws max | Ground prims max | Ground draws max | Aerial prims max | Aerial draws max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| scenery_cells | 168,031 | 168,031 | 91,773 | 20 | 134,369 | 26 | 45,578 | 15 |
| scenery_ImportedVegetationBatches | 132,457 | 7,702 | 120,759 | 42 | 126,699 | 47 | 66,089 | 38 |
| scenery_ParkedAircraft | 273,421 | 38,845 | 67,838 | 155 | 95,748 | 179 | 73,760 | 179 |
| field_rough | 84,960 | 84,960 | 84,960 | 1 | 84,960 | 1 | 84,960 | 1 |
| scenery_Population | 371,573 | 897 | 73,734 | 49 | 60,025 | 49 | 34,335 | 49 |
| field_Lake | 65,224 | 44,952 | 45,354 | 13 | 45,688 | 13 | 45,306 | 13 |
| field_flightline_barrier | 81,601 | 38,840 | 39,998 | 6 | 39,998 | 6 | 39,651 | 6 |
| field_DistantRidges | 27,648 | 27,648 | 27,648 | 4 | 13,824 | 2 | 0 | 0 |
| scenery_pit_shelters | 12,096 | 12,096 | 12,096 | 2 | 12,096 | 2 | 12,096 | 2 |
| world_AirfieldLighting | 26,386 | 8,462 | 9,492 | 15 | 7,246 | 16 | 5,946 | 16 |
| scenery_BotanicalHabitats | 89,655 | 2,372 | 6,844 | 19 | 7,760 | 20 | 6,216 | 17 |
| field_treeline | 10,080 | 10,080 | 5,418 | 4 | 6,168 | 4 | 6,270 | 5 |
| field_pilot_station | 6,124 | 6,124 | 6,126 | 2 | 6,126 | 2 | 6,126 | 2 |
| field_windsock | 5,266 | 5,266 | 5,268 | 4 | 5,268 | 4 | 5,268 | 4 |
| field_Countryside | 6,380 | 6,380 | 2,324 | 8 | 2,908 | 8 | 2,524 | 8 |
| scenery_AirfieldDetail | 4,482 | 0 | 2,244 | 5 | 2,244 | 5 | 0 | 0 |
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

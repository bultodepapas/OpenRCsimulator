Viewport 1280×720, llvmpipe (LLVM 20.1.2, 256 bits), Godot 4.7.2-stable (official), scene detail medium.
Primitives count every MultiMesh instance (instanced LOD nodes measured one by one).

**pilot** (8 views): total drawn primitives max 856,360 (median 435,348), draws max 333 (median 92); sun shadow pass up to 74,434 counter primitives / 28 draws.
**ground** (8 views): total drawn primitives max 904,675 (median 744,145), draws max 362 (median 202); sun shadow pass up to 79,790 counter primitives / 27 draws.
**aerial** (4 views): total drawn primitives max 636,113 (median 274,932), draws max 372 (median 68); sun shadow pass up to 29,457 counter primitives / 25 draws.
Renderer estimates after the first frame: textures 468 MiB, buffers 45 MiB, video 512 MiB.

| Subsystem | Source triangles | Without LOD | Pilot prims max | Pilot draws max | Ground prims max | Ground draws max | Aerial prims max | Aerial draws max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| scenery_ImportedVegetationBatches | 126,933 | 7,189 | 345,948 | 42 | 350,886 | 42 | 142,716 | 36 |
| scenery_Population | 341,696 | 897 | 226,870 | 49 | 200,869 | 49 | 99,138 | 49 |
| scenery_ParkedAircraft | 273,421 | 38,845 | 78,295 | 155 | 138,507 | 179 | 97,487 | 179 |
| scenery_cells | 165,303 | 165,303 | 91,773 | 19 | 131,917 | 26 | 43,126 | 15 |
| field_rough | 84,960 | 84,960 | 84,960 | 1 | 84,960 | 1 | 84,960 | 1 |
| field_flightline_barrier | 81,601 | 38,840 | 81,603 | 6 | 74,193 | 6 | 52,486 | 6 |
| field_Lake | 65,224 | 44,952 | 55,102 | 13 | 66,232 | 13 | 54,850 | 13 |
| scenery_BotanicalHabitats | 62,034 | 2,112 | 31,810 | 18 | 40,176 | 20 | 11,451 | 17 |
| field_DistantRidges | 27,648 | 27,648 | 27,648 | 4 | 13,824 | 2 | 0 | 0 |
| field_NearGrass | 25,178 | 0 | 25,178 | 3 | 25,178 | 3 | 15,182 | 3 |
| scenery_pit_shelters | 12,096 | 12,096 | 12,096 | 2 | 12,096 | 2 | 12,096 | 2 |
| world_AirfieldLighting | 26,386 | 8,462 | 8,724 | 15 | 6,478 | 16 | 5,866 | 16 |
| field_pilot_station | 6,124 | 6,124 | 6,126 | 2 | 6,126 | 2 | 6,126 | 2 |
| field_treeline | 10,080 | 10,080 | 5,460 | 4 | 5,460 | 4 | 4,344 | 3 |
| field_windsock | 5,266 | 5,266 | 5,268 | 4 | 5,268 | 4 | 5,268 | 4 |
| field_Countryside | 6,764 | 6,764 | 2,516 | 8 | 2,962 | 11 | 2,884 | 9 |
| scenery_AirfieldDetail | 2,624 | 0 | 1,864 | 4 | 1,864 | 4 | 0 | 0 |
| scenery_PopulationContacts | 1,355 | 1,355 | 1,355 | 1 | 1,355 | 1 | 1,355 | 1 |
| scenery_contact_shadows | 702 | 702 | 216 | 6 | 612 | 18 | 558 | 15 |
| world_Campfire | 305 | 305 | 610 | 4 | 610 | 4 | 610 | 4 |
| scenery_hedges | 488 | 488 | 488 | 2 | 256 | 1 | 0 | 0 |
| world_FieldLights | 240 | 240 | 432 | 12 | 432 | 12 | 432 | 12 |
| scenery_Motion | 296 | 296 | 160 | 4 | 194 | 2 | 160 | 1 |
| scenery_WoodlandEdges | 284 | 284 | 102 | 2 | 160 | 3 | 32 | 1 |
| scenery_BuildingRoofs | 100 | 100 | 32 | 8 | 68 | 17 | 28 | 7 |
| scenery_Birds | 24 | 24 | 24 | 1 | 24 | 1 | 0 | 0 |
| field_FlightCueShadows | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| world_SunGlare | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Viewport 1280×720, llvmpipe (LLVM 20.1.2, 256 bits), Godot 4.7.2-stable (official), scene detail high.
Primitives count every MultiMesh instance (instanced LOD nodes measured one by one).

**pilot** (8 views): total drawn primitives max 1,295,621 (median 803,744), draws max 350 (median 109); sun shadow pass up to 74,947 counter primitives / 28 draws.
**ground** (8 views): total drawn primitives max 1,039,711 (median 805,238), draws max 369 (median 208); sun shadow pass up to 77,381 counter primitives / 30 draws.
**aerial** (4 views): total drawn primitives max 742,866 (median 311,145), draws max 374 (median 71); sun shadow pass up to 31,598 counter primitives / 26 draws.
Renderer estimates after the first frame: textures 473 MiB, buffers 47 MiB, video 520 MiB.

| Subsystem | Source triangles | Without LOD | Pilot prims max | Pilot draws max | Ground prims max | Ground draws max | Aerial prims max | Aerial draws max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| field_treelineDetail | 972,696 | 31,632 | 379,224 | 22 | 81,130 | 6 | 3,722 | 2 |
| scenery_ImportedVegetationBatches | 132,457 | 7,702 | 354,332 | 42 | 353,832 | 47 | 155,030 | 38 |
| scenery_Population | 371,573 | 897 | 272,487 | 49 | 244,784 | 49 | 124,582 | 49 |
| scenery_ParkedAircraft | 273,421 | 38,845 | 95,741 | 155 | 147,623 | 179 | 99,963 | 179 |
| scenery_cells | 168,031 | 168,031 | 91,773 | 20 | 134,369 | 26 | 45,578 | 15 |
| field_rough | 84,960 | 84,960 | 84,960 | 1 | 84,960 | 1 | 84,960 | 1 |
| field_flightline_barrier | 81,601 | 38,840 | 81,603 | 6 | 81,603 | 6 | 68,070 | 6 |
| scenery_BotanicalHabitats | 89,655 | 2,372 | 61,697 | 19 | 73,713 | 20 | 29,705 | 17 |
| field_Lake | 65,224 | 44,952 | 57,034 | 13 | 68,248 | 13 | 56,026 | 13 |
| field_NearGrass | 49,579 | 0 | 49,579 | 3 | 49,579 | 3 | 45,295 | 3 |
| field_DistantRidges | 27,648 | 27,648 | 27,648 | 4 | 13,824 | 2 | 0 | 0 |
| scenery_pit_shelters | 12,096 | 12,096 | 12,096 | 2 | 12,096 | 2 | 12,096 | 2 |
| world_AirfieldLighting | 26,386 | 8,462 | 9,492 | 15 | 7,246 | 16 | 5,946 | 16 |
| field_pilot_station | 6,124 | 6,124 | 6,126 | 2 | 6,126 | 2 | 6,126 | 2 |
| field_windsock | 5,266 | 5,266 | 5,268 | 4 | 5,268 | 4 | 5,268 | 4 |
| field_treeline | 9,318 | 9,318 | 5,208 | 4 | 5,208 | 4 | 4,344 | 3 |
| scenery_AirfieldDetail | 4,482 | 0 | 3,722 | 5 | 3,722 | 5 | 0 | 0 |
| field_Countryside | 6,764 | 6,764 | 2,516 | 8 | 2,962 | 11 | 2,884 | 9 |
| scenery_PopulationContacts | 1,391 | 1,391 | 1,391 | 1 | 1,391 | 1 | 1,391 | 1 |
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

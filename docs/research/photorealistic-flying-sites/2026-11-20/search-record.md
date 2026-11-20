# Search and verification record

Reviewed: 2026-11-20. This record retains **172 distinct search queries** across two geographic-scenery reviews: 100 in the preceding review and 72 in this follow-up. The follow-up produced 24 additional investigations, bringing the consolidated collection to 56. Queries, investigations, source documents, code reads and implementation experiments are different counts.

## Method and count

| Search group | Queries | Scope |
| --- | ---: | --- |
| Preceding geographic review | 100 | Godot terrain, GIS, flight simulators, maps and packaging |
| Games and world generators | 20 | Geographic game-world generation and authoring methods |
| Simulation and globe applications | 32 | Road/robot/drone simulators and globe workflows |
| Terrain algorithms and practical guides | 16 | LOD, formats, precision, mesh optimization and spline grading |
| RC scenery cross-checks | 4 | Recheck relevant photographic/parallax precedents |
| Total | 172 | Exact trimmed query strings are distinct |

Searches were followed by primary-source opens and selected README, schema, guide and API reads. Those direct reads are not counted as extra searches. Three independent research assignments covered the new categories; the lead opened the selected primary sources, checked meaningful limitations and reconciled them with the repository. A bounded adversarial review challenged the proposed integration.

The research uses upstream descriptions as evidence of documented mechanisms, not proof that the tools produced correct output on OpenRC hardware. Negative findings include an unavailable original maps4fs URL, version-sensitive CARLA conversion behavior, a documented zero-for-missing elevation sampler, and reported rather than reproduced Webots import problems. Read the [dossiers](game-world-precedents.md) for the source-specific limits.

## Repository baseline

The current-source compatibility check used main commit `48580b75a796fc6048fb77cdd69875c94ebb69e0`. The existing planning branch began this update at `e1cb8f67c3cd5b78a2fa80ca7136dd3341d4ec1a`. Its SC-PHOTO milestone/status ledger was preserved; changes add dated research and a bounded follow-on mapping.

| Inspected OpenRC file | Git blob identity |
| --- | --- |
| docs/STACK.md | `fb4f35a2eb15e3ee4451bdefcc2a95493a7f8175` |
| app/data/field_loader.gd | `9a37b7b5203fcf7efc3b5e4a375f84fb40f3e7d0` |
| app/physics/ground_surfaces.gd | `8bbc652914c596db81180e6dc5cacdc008b00d27` |

These are Git blob identities, not dataset checksums or runtime fingerprints. AGENTS.md and the documentation map were also read for operating and ownership constraints.

## Selected upstream read identities

The following Git blob identities record selected inspected text. Default-branch documentation can subsequently change. An adoption experiment must pin the complete upstream revision, dependencies and data separately.

| Repository/file | Git blob identity | Inspection scope |
| --- | --- | --- |
| louis-e/arnis README.md | `ef1fcfb0a3118512ea6bc0d3fb29d5f42b15e965` | Project workflow; terrain details separately checked in the wiki |
| BuildTheEarth/terraplusplus README.md | `4060f4f87f0ce6acd2f9dd59bfc9ac174fa251fc` | Providers, setup and geographic commands |
| ZenJakey/maps4fs README.md | `3e73e73f3c53a25e6b4ab34ab12a4798feb44190` | Generation pipeline and component information |
| gaelysam/geo-mapgen README.md | `c8f4420ed63c88fe887f8bd1b414b299730e2141` | Chunked conversion and source configuration |
| KarlCarriere/cs-map-generator README.md | `5b081a72aecc72705f2cedd98537b934b3082c01` | Manifest and stated reproducibility |
| caspervg/SC4Mapper-2026 README.md | `fed16011e933650b3b58d029544e757808ad3b19` | Water mask and game-specific height treatment |
| OlivierB-OB/osm-drone-simulator docs/tile-ring-system.md | `8bd8fd2812e11521aef8d1350165305e6015176e` | Neighborhood, priority and cache design |
| Same repository docs/data/elevation-sampler.md | `ec8904d9bcb66d3e5ab33b92c19a79cfd2efc6ab` | Missing-tile behavior |
| Same repository docs/data/elevations.md | `ec24e7a7a24f7ef3d6459818ba940467b913a7bb` | Terrarium decoding |
| cyberbotics/webots docs/automobile/openstreetmap-importer.md | `6ae242dacffe3f3ec242ae45ada74766b328b068` | Import options and area guidance |
| fstrugar/CDLOD README.md | `4add36d31e6262e9f8650e115f5fee220c798842` | Algorithm and demonstration scope |
| mapbox/martini README.md | `d30e3ba818dd1f4c226414b8925563aa664ce179` | Mesh error control and experimental status |

## Previous review: 100 queries

```text
1. TokisanGames Terrain3D GitHub Godot version renderer compatibility license documentation
2. Zylann godot_heightmap_plugin GitHub renderer Godot 4 license compatibility
3. Zylann godot_voxel GitHub Godot 4 license renderer terrain generator
4. boku-ilen GeoDot Godot geospatial GitHub license Godot 4
5. osgEarth official GitHub license features elevation imagery osg version terrain SDK
6. vsgCs vsgCs GitHub Cesium VulkanSceneGraph 3D Tiles license requirements status
7. 3d-tiles-tools CesiumGS github license transform 3D Tiles install requirements
8. Geospatial Godot plugin geospatial data current Godot 4 open source github geospatial addons DEM GIS
9. site:github.com/ziv/godotiles godotiles data sources tile cache disk web map provider license renderer
10. site:github.com/Zylann/godot_heightmap_plugin Godot 4.6 compatibility renderer shaders license
11. site:github.com/Zylann/godot_voxel compatibility renderer macos Apple silicon supported builds Godot 4.4
12. site:github.com/pelicanmapping/osgearth license LGPL MIT license 3.8 github
13. site:github.com/TokisanGames/Terrain3D Terrain3D 1.1 4.5 heightmap region format renderer compatibility
14. site:github.com/boku-ilen/geodot-plugin Mac x86 M1 GDAL license Godot extension dependencies windows
15. site:github.com/ziv/godotiles renderer compatibility mobile terrain shader zoom cache no download
16. site:github.com/timoore/vsgCs build license features Vulkan macOS limitations LOD
17. site:github.com/ziv/godotiles "renderer" "cache"
18. site:github.com/ziv/godotiles "offline" "cache"
19. site:github.com/TokisanGames/Terrain3D collision height shader CPU physics get_height
20. site:github.com/pelicanmapping/osgearth LICENSE.txt MIT third party GDAL data layer
21. "ziv/godotiles" "cache" macos "compatibility"
22. "godotiles" "godot" "apple" "x86" "arm64"
23. "boku-ilen/geodot-plugin" "Apple Silicon" M1 2025 2026
24. site:store.godotengine.org/asset/ziv/godotiles Godot 4.7 version
25. site:github.com/ziv/godotiles gdextension arm64 supported platform godot 4.7
26. site:github.com/ziv/godotiles "cache" "disable" tile runtime
27. site:github.com/boku-ilen/geodot-plugin "arm64" "macos" github actions
28. site:github.com/pelicanmapping/osgearth "MIT" "LGPL" license change 2026
29. site:docs.osgearth.org "License" "MIT" "LGPL"
30. site:github.com/CesiumGS/3d-tiles-tools license node 0.5.4 release
31. FlightGear scenery architecture terrain tiles airports scenery official documentation TerraSync license GPL
32. TerraGear official GitHub terrain airport scenery generation license FlightGear
33. osm2city GitHub FlightGear buildings vegetation license generator
34. FlightGear TerraSync scenery distribution versioning official documentation
35. GeoFS official about worldwide flight simulator browser Cesium data source terms license
36. Microsoft Flight Simulator SDK 2024 airport terrain terraforming projected meshes documentation
37. X-Plane WorldEditor manual airport terrain mesh scenery gateway license official
38. Ortho4XP GitHub official license elevation mesh orthophoto imagery providers
39. site:gitlab.com osm2city osm2city LICENSE license source code github GitLab
40. github FlightGear flightgear repository LICENSE GNU GPL v2 TerraGear COPYING
41. site:github.com/oscarpilote/Ortho4XP license copyright Triangle source LICENSE
42. site:github.com X-Plane scenery tools WED WorldEditor license source code
43. "Ortho4XP" "GPL" "Triangle" licence site:github.com/oscarpilote/Ortho4XP
44. "oscarpilote/Ortho4XP" license GNU GPL v3 license
45. "osm2city" "license" "GNU" GPL v2 source
46. "TerraGear" "GNU General Public License" v2 source code
47. site:geo-fs.com "terms of use" intellectual property license code scenery
48. site:flightsimulator.com "SDK" "license" agreement scenery Microsoft Flight Simulator
49. site:gateway.x-plane.com airport scenery gateway license GPL v2 Laminar
50. site:developer.x-plane.com "scenery gateway" "license" redistribution scenery
51. site:gdal.org gdalwarp vertical shift geoid grid nodata target aligned pixels documentation license
52. site:proj.org documentation geoid grid vertical transformation network grid availability proj
53. site:pdal.io filters smrf writers gdal ground elevation model documentation
54. site:docs.opendronemap.org dtm dsm georeferencing gcp options open drone map
55. site:github.com/minorua/Qgis2threejs README license terrain DEM threejs export
56. site:github.com domlysz BlenderGIS README georeferencing terrain DEM license Blender GIS
57. site:osm2world.org OSM2World command line export glTF license data ODbL
58. site:docs.overturemaps.org DuckDB parquet access bounding boxes data license attribution download
59. GDAL PROJ PDAL GitHub source code license MIT BSD documentation
60. OpenDroneMap WebODM GitHub AGPL license engine web interface how works
61. OSM2World github license GPL custom textures models OpenStreetMap ODbL
62. Overture Maps data licensing attribution ODbL OpenStreetMap specific contributors DuckDB
63. site:github.com/OpenDroneMap/ODM license AGPL GNU
64. site:github.com/OSGeo/PROJ LICENSE MIT
65. site:minorua.github.io/Qgis2threejs/docs export gltf DEM resolution shift QGIS plugin
66. site:docs.overturemaps.org/guides buildings height infrastructure airport runways theme data
67. site:osm2world.org docs elevation georeference terrain DSM SRTM OpenStreetMap OSM2World
68. site:github.com/tordanik/OSM2World default configuration terrain DEM SRTM elevation georeference mesh texture license
69. site:pdal.io writers.gdal nodata window_size data_type resolution interpolation details
70. site:gdal.org geotransform tutorial pixel line center upper left 0.5 georeference GDAL
71. site:proj.org projsync checksum disable network PROJ_NETWORK projsync local grids
72. site:docs.opendronemap.org/tutorials DSM DTM smrf ground control accuracy geoid rolling shutter
73. site:minorua.github.io/Qgis2threejs/docs/3.2/Exporter.html geometry original DEM values resampling glTF vertical scale export
74. site:github.com/tordanik/OSM2World --input --output osm glb commandline convert
75. site:osm2world.org/docs command line convert --input --output osm glb
76. site:github.com/duckdb/duckdb license MIT
77. site:docs.overturemaps.org release version old releases changing monthly stable gers IDs
78. site:docs.overturemaps.org "retention" "60 days" data releases 2026
79. site:docs.overturemaps.org schema infrastructure runway airport class aeroway
80. site:qgis.org QGIS software licence GPL 2 or greater
81. site:github.com/tordanik/OSM2World tree 0.4 LICENSE LGPL MIT
82. "OSM2World" "0.4.0" license MIT LGPL GitHub
83. site:github.com/tordanik/OSM2World "0.4.0" "LICENSE" MIT
84. site:osm2world.org license MIT LGPL 0.4.0
85. "OSM2World" "MIT" license "LGPL"
86. site:docs.blender.org/manual glTF exporter apply modifiers coordinate Y up Blender export scene objects
87. site:docs.overturemaps.org "subtype" "airport" "runway"
88. site:github.com/protomaps/PMTiles archive range requests license
89. site:github.com/onthegomap/planetiler OpenStreetMap vector tiles license
90. site:github.com/systemed/tilemaker vector tiles PBF license
91. site:github.com/maplibre/martin PMTiles MBTiles tile server license
92. site:github.com/developmentseed/titiler COG STAC raster tiles license
93. site:github.com/stac-utils/pystac-client search satellite data license
94. site:github.com/maplibre/maplibre-native offline maps C++ license
95. site:github.com/geographiclib/geographiclib LocalCartesian geoid license
96. site:docs.protomaps.com PMTiles HTTP range requests immutable
97. site:maplibre.org/martin PMTiles MBTiles
98. site:geographiclib.sourceforge.io LocalCartesian Geoid MIT X11
99. site:developmentseed.org/titiler COG STAC dynamic tiling
100. site:github.com/ziv/godotiles mercator latitude poles 85
```

## This follow-up: 72 queries

### Games and world generators (20)

```text
1. Arnis Minecraft real world map OpenStreetMap generation algorithm github
2. Terra++ Minecraft real world earth generator OpenStreetMap elevation projection github
3. maps4fs farming simulator real terrain generation github DEM OSM
4. Minetest Luanti real terrain world map generation real world DEM github
5. site:github.com cities skylines real world map generator heightmap terrain openstreetmap
6. site:documentation.beamng.com World Editor terrain heightmap import real world lidar
7. site:github.com blosm blender openstreetmap DEM premium terrain license
8. site:github.com "real world" "terrain" "game" "OpenStreetMap" simulator world generator
9. github louis-e Arnis minecraft generation pipeline terrain elevation region source
10. github BuildTheEarth terraplusplus cubic chunks projection datasets roads
11. github iwatkot maps4fs farming simulator DEM roads terrain generation code
12. github cities skylines 2 real world heightmap import generate map 4096 16 bit OSM
13. site:github.com "maps4fs" generation_info.json OSM line width terraforming dem license
14. site:github.com/caspervg/SC4Mapper-2026 "real-world" elevation water height regions
15. site:github.com/gaelysam/geo-mapgen heightmap database nodata tiles 80 land cover
16. site:documentation.beamng.com "Terrain And Road Importer" prominence terraform road
17. site:github.com/ZenJakey/maps4fs "texture schema" "width" "License"
18. site:github.com/louis-e/arnis/wiki "Road" "flatten" elevation OSM
19. site:github.com/caspervg/SC4Mapper-2026 "mapped water" "dry" elevation OSM
20. site:documentation.beamng.com/beamng_tech/tools/terrainandroadimporter "roads" "height" "terraform"
```

### Simulation and globe applications (32)

```text
1. site:carla.readthedocs.io OSM maps OpenDrive conversion OSM2ODR generate world coordinates
2. site:sumo.dlr.de docs osmWebWizard netconvert OSM elevation typemap license
3. site:gazebosim.org docs heightmap DEM geotiff terrain heightmap SDF
4. site:worldwind.arc.nasa.gov java tutorial elevation model tiled terrain elevation
5. site:cyberbotics.com Webots OpenStreetMap OSM importer elevation download road building worlds
6. site:cesium.com learn unreal place actors globe georeference origin shift terrain photogrammetry tileset
7. site:openspaceproject.com documentation digital globe terrain geospatial height maps elevation rendering
8. site:microsoft.github.io AirSim settings origin geopoint NED coordinates GPS Unreal world local
9. site:cyberbotics.com/doc automobile openstreetmap importer configuration SRTM elevation Python command
10. github cyberbotics webots openstreetmap importer elevation SRTM config --no-elevation
11. github microsoft AirSim archived no longer supported MIT license github
12. github carla simulator license MIT code assets CC BY NC OpenStreetMap osm2odr
13. github eclipse sumo license EPL 2.0 GPL 2.0 or later netconvert
14. github gazebo gz-sim license Apache 2 license sdf
15. github NASA WorldWindJava license Apache 2.0 NOSA archived NASA worldwind
16. github CesiumGS cesium-unreal plugin Apache 2.0 source license
17. github openspace openspace license MIT NASA digital planet globe
18. github cyberbotics webots license Apache 2.0 OSM importer python license
19. github microsoft AirSim "This repository was archived" archive date
20. site:cesium.com Cesium World Terrain data license attribution access offline use terms
21. site:github.com/microsoft/AirSim "This repository was archived" AirSim
22. site:github.com/NASAWorldWind/WorldWindJava "archived" "2025"
23. site:github.com/cyberbotics/webots "Elevation Grid Rotated 90"
24. site:docs.openspaceproject.com "Build Local DEM Patches" OpenSpace GDAL
25. site:carla.readthedocs.io "osm2odr" "height" elevation roads
26. site:github.com/microsoft/AirSim "project_airsim.md" AirSim announcement Microsoft IAMAI 
27. site:microsoft.github.io/AirSim real world environment build heightmap georeferenced scenery landscape Cesium
28. site:github.com/microsoft/AirSim real world geographic environment landscape DEM map source
29. site:github.com/Cosys-Lab/Cosys-AirSim "Cesium" real world maps terrain
30. site:github.com/iamaisim/ProjectAirSim "geospatial" "terrain" real world environment
31. CARLA Osm2Odr converter SUMO netconvert license transitive CARLA MIT OSM2ODR
32. site:github.com/carla-simulator/carla "Osm2Odr" "SUMO" license
```

### Terrain algorithms and practical guides (16)

```text
1. geometry clipmaps Losasso Hoppe GPU Gems 2 terrain chapter implementation
2. CDLOD continuous distance dependent level of detail terrain Strugar reference implementation github
3. mapbox martini RTIN terrain mesh github algorithm
4. Cesium quantized mesh terrain format skirts terrain builder github
5. OGC 3D Tiles implicit tiling specification geometric error screen space error bounding volume subtree availability
6. Godot 4 large world coordinates double precision origin shift limitations physics large world documentation
7. meshoptimizer gltfpack EXT_meshopt_compression KHR_texture_basisu gltf transform cli texture resize docs
8. Unreal Engine landscape splines roads terrain deformation documentation mesh road
9. github cesium terrain builder quantized mesh ctb tile command license
10. github godot demo projects large world coordinates demo precision large worlds license
11. site:github.com/CesiumGS/3d-tiles-samples implicit tiling quadtree sample
12. Godot 4 gltf meshopt compression KHR_texture_basisu import supported extension documentation
13. site:dev.epicgames.com documentation export landscape heightmap terrain Unreal splines export heightmap
14. site:github.com zeux meshoptimizer license MIT gltfpack mesh optimization
15. site:github.com mapbox martini github issue tile seams neighboring mesh edge cracks
16. site:github.com ahuarte47 cesium terrain builder master quantized mesh license Apache
```

### RC scenery cross checks (4)

```text
1. PicaSim scenery creation panorama heightfield collision source github
2. CRRCSim scenery panorama heightmap XML terrain how create official
3. site:forums.realflight.com panorama airport import collision objects photofield tutorial
4. site:heli-x.info scenery creation panorama collision objects tutorial
```

## Verification limits

The lead checked the primary evidence and the current integration boundaries, performed count/content/link checks on the documentation, and reviewed the physical/visual and milestone distinctions. Calculated 16-bit encoding increments are analytical examples, not measured terrain errors. No software installation, geographic asset generation, dataset redistribution, runtime benchmark, physical-host capture, exported-build validation or native-equivalence run was performed.

The requested result is research and documentation. The proposed WG01–WG08 fixtures and any geographic runtime extension remain future work under the existing owners and acceptance policy.

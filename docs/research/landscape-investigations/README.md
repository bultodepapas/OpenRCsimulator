# Landscape investigations (2026-10-05)

Eleven focused internet investigations behind [LANDSCAPE-PLAN.md](../../LANDSCAPE-PLAN.md). They build on [landscape-research.md](../landscape-research.md). Five ran a small Godot 4.7.2 spike on a scratch copy of the app; nothing in `app/` was changed. Each note lists its sources with evidence labels, the libraries it found, the plan changes it proposes, and what it could not confirm.

| # | Topic | Spike | Key result |
| --- | --- | --- | --- |
| [01](01-sky-shaders.md) | Sky and cloud shaders in Compatibility | ✅ | `use_debanding` works in sky shaders; our gradient + sun + noise-cloud sky repeats byte for byte; every third-party sky reads `TIME` |
| [02](02-atmosphere-aerial-perspective.md) | Atmosphere models and aerial perspective | — | Aerial perspective is a no-op in 4.7.2 GLES3; the sky must reproduce the engine's fog term; Hosek-Wilkie colours; 23 km haze hides little |
| [03](03-terrain-mesh-gdscript.md) | Chunked heightmap terrain + float64 sampler | ✅ | Sampler vs mesh: 0.0 m at 100,000 points; ~0.1 s build; far rings built once |
| [04](04-trees-and-impostors.md) | Trees and billboard impostors | — | Alpha-to-coverage does nothing; static pilot → fixed LOD per tree; proctree.js/ez-tree offline; FlightGear crossed quads |
| [05](05-grass-rendering.md) | Grass and ground cover | ✅ | Opaque blade clumps beat alpha cards; +1 draw call per MultiMesh; grass matters within ~30 m |
| [06](06-ground-anti-tiling.md) | Ground textures without tiling | ✅ | Anti-tiling + macro variation + mown stripes repeat byte for byte; far runway edge step only 6 % today |
| [07](07-open-source-sims-scenery-code.md) | Scenery in open-source flight sims | — | FlightGear/CRRCSim/PicaSim/YSFlight techniques: one visibility value, positions-only tree data, visible/collides flags |
| [08](08-terrain-generation-tools.md) | Offline terrain generation and DEM pipelines | (Python) | Integer-only generator gives identical SHA in stdlib and NumPy; `openrc-terrain v1` format; export filter trap |
| [09](09-lighting-color-lookdev.md) | Lighting, tonemapping and airplane readability | ✅ | Filmic at exposure 0.8; plane contrast −0.53 baseline; sun `#ffe9d7` |
| [10](10-visual-testing-tools.md) | Testing and measuring landscape work | (FLIP) | Counters read 0 headless; pin Mesa and thread count; FLIP bad-pixel counts; readability metric |
| [11](11-wind-animation-ambience.md) | Windsock, tree sway, flags, ambience | — | FAA/Canada AIM windsock data; sim clock wrapped to 1024 s; global uniforms work in Compatibility |

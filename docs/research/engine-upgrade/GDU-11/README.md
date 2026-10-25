# GDU-11a / L6: maple alpha-coverage mipmaps

2026-10-25. Adopted for local development on official Godot **4.8-beta1**, `4d10419ca`, following the owner's request to exploit 4.8 improvements. The maple leaf albedo now uses coverage-preserving mipmaps at import threshold **0.5**, retaining its authored material cutoff **0.5**. Only this texture's import recipe changes production behavior. This does not close GDU-10 platform/release acceptance.

## Why this feature

The [previous maple review](../../visual-quality-implementation/L6c/map-expansion/README.md#native-review-and-filtering) disabled ordinary mipmaps because the farm/forest crowns dissolved at distance, accepting fine-leaf shimmer. Godot 4.8 adds an importer that adjusts lower-mip alpha coverage; the exact pinned [ResourceImporterTexture documentation](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/ResourceImporterTexture.xml) and [merged implementation](https://github.com/godotengine/godot/pull/104289) confirm the three settings used here. No replacement assets or geometry were created.

The source PNG, glTF, material cutoff, geometry, placements and collision data remain unchanged in the experiment. The native base-level compressed image hash is identical in all three treatments. Other vegetation retains its reviewed import settings, including the separate Quaternius policy and LandscapeLab mip clamp.

## Native comparison

Frozen app copies from `b51ad4772`, with the same source inventory, differ only in the maple leaf importer. Three treatments: existing unmipped, ordinary mipmaps as a negative control, and coverage-preserved mipmaps. All use Windows, RTX 3090, driver 617.42, native Compatibility/OpenGL 3.3, 4x MSAA, fixed lighting/camera, and no wind. Eight subpixel camera phases at each of 32/64/128/256 m were captured at **1920×1080**, then **2560×1440**: 192 verified PNGs.

[Comparison](comparison.json), [verification](verification.json) and [source inventory](source-manifest.json) retain identities, complete mip chains, payload hashes, commands and checks. At 1080p:

| Distance | Ordinary-mip silhouette area change | Preserved-mip silhouette area change | Preserved adjacent-mask transitions / unmipped |
| --- | ---: | ---: | ---: |
| 32 m | −2.91% | −1.62% | 0.491× |
| 64 m | −8.26% | −3.56% | 0.451× |
| 128 m | −18.22% | −5.24% | 0.414× |
| 256 m | −35.79% | −7.48% | 0.469× |

At 1440p, preserved-mip area change ranges from −1.16% to −6.56%; adjacent-mask transitions are 0.423–0.510× the unmipped baseline. These are binary silhouette sampling metrics, including trunk and MSAA edge pixels. They are not fractional alpha coverage, measured shimmer, FPS, GPU residency or pilot readability. At 1080p/32 m, phase-area standard deviation increases 32.7%; not every stability measure improves. At 256 m, mask IoU is about 0.789: filtering redistributes pixels as well as changing net area.

The bounded adoption accepts this tradeoff: substantially less subpixel mask variation than the unmipped workaround, and substantially less distant crown erosion than ordinary mips. It does not assert pixel-equivalent silhouettes. Native farm, southwest forest and clubhouse still pairs retain recognizable crown structure with smoother leaf sampling; no obvious new crown collapse was observed. Two 192-frame clubhouse approach/retreat sequences at actual 1080p have identical cameras, clocks, wind and render counters. Representative frames 0/24/72/120/191 were inspected; human normal-speed playback acceptance remains separate.

## Budget and validation

- The 2048² S3TC leaf image grows from 4,194,304 to 5,592,432 bytes with eleven mip levels: approximately **1.33 MiB** additional image data for the shared atlas, within a 1.34 MiB budget. This is not a GPU-residency measurement. Preservation is computed during import; no new per-frame shader or simulation work was added.
- Source and native `test_imported_tree_rendering.gd` pass, including complete mip readback and the preservation/threshold guard. Each emits four expected warnings from existing intentional invalid-wind/cell controls; no engine errors.
- Six comparison-tool tests pass, covering incomplete/tampered PNGs, source/import drift, fixture mismatch and the analysis-only CLI. The vegetation pipeline check verifies 30 assets, 91 runtime files and four pinned archives.
- Both generated S3TC and ETC2 `.ctex` payloads in the current project match the captured candidate byte for byte. This is import artifact verification, not a new platform execution or export-release qualification.
- The 3,875-path frozen app inventory differs between experiment treatments only at the leaf importer. At verification, simulation, physics, scenery, rendering and UI source paths matched that baseline. Concurrent aircraft edits observed in the live tree are listed separately in `verification.json`; this evidence does not qualify or overwrite them.

The full release suite, native Linux/macOS execution, FPS and human flight acceptance were not repeated for this import-only change. Their existing migration gates remain open.

## Reproduction and retained artifacts

Use the [tree-tool commands](../../../../tools/trees/README.md#maple-alpha-coverage-filtering-gdu-11a--l6). For contextual stills, `quality_capture.gd --mode=field --views=farm_maples,forest_maple,oak_close --width=1920 --height=1080 --wind=off --out=<new>` uses an exact-size SubViewport. The optional view selection leaves the previous default capture set unchanged.

Raw PNGs and full frozen copies stay outside Git at `D:/OpenRCsimulator-experiments/gdu11-alpha/`. Accepted sets: `final-captures/{baseline,ordinary,candidate}`, `field-final/{baseline,candidate}` and `motion/{baseline,candidate}`. Their seven manifests are retained under [captures](captures); checked engine logs are under [checks](checks). All **582 accepted PNGs** were verified against their recorded SHA-256 and actual dimensions. The initial `field/` and `field1080/` attempts were 1920×1061 despite window flags and are explicitly excluded from 1080p qualification. Initial importer-default normalization changed no baseline PNG bytes.

## Other 4.8 candidates reviewed

The [official beta1 announcement](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/) was checked against pinned source and existing runtime contracts:

- **Compatibility decals:** a useful next prototype for terrain-following crash marks. The pinned [GLES3 implementation](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/drivers/gles3/rasterizer_scene_gles3.cpp#L138) limits pairing to eight decals per receiving geometry instance, while the current plane-mark pool allows sixteen. Require bounded use/fallback and slope/9/16-mark tests. Pinned `Decal.xml` still claims no Compatibility support; implementation and [PR118070](https://github.com/godotengine/godot/pull/118070) establish actual support and limits.
- **Texture streaming:** the pinned [implementation rejects Compatibility](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/modules/texture_streaming/texture_streaming.cpp#L279). Enabling it in the current default renderer would not deliver its intended benefit. Defer to a separately qualified Forward+/Mobile profile and measured memory need.
- **Trail3D:** the [native ribbon API](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/doc/classes/Trail3D.xml) does not replace smoke's wind advection, buoyancy, residual and presentation-clock contracts. No demonstrated smoke deficiency justifies that replacement now.

These decisions are reflected in [GDU-11b–d](../../../plans/godot-4.8-upgrade.md#phase-11-owner-authorized-48-improvements); no unrelated feature was enabled just because it is new.

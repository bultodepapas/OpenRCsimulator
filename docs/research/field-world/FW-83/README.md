# FW-83 — distant storm-cloud asset intake

2026-10-14 · Asset intake and source review · **Selected textures for an isolated scene trial; no renderer or visual qualification is claimed.**

The [sky/cloud plan](../../../plans/sky-clouds-weather.md) owns FW-83 implementation and acceptance. This record covers the freely redistributable cloud imagery selected for a Compatibility-renderer trial. It does not approve the final scene geometry or visual treatment.

## Selected source

[WickedInsignia, “Clouds with Transparency”](https://opengameart.org/content/clouds-with-transparency) is an OpenGameArt texture pack published on 2022-02-17. The listing marks the pack CC0 and says it contains ten 2K cloud textures as alpha PNGs plus JPEGs with black backgrounds. The creator says the textures were made in Blender and released into the public domain under CC0. The ZIP contains the image files but no separate license document, so the primary listing and author statement are retained as the license evidence.

The downloaded source archive was `fx_cloudalphas.zip` (28,480,966 bytes), SHA-256 `83514A391C765819BC159B7F9AB61EC9F06C0CAA2B5865AF20A5BD3B2A14CCA4`. It is not vendored. Two original PNG members were selected after visual review:

| Runtime file | Source member | Image data | Size | SHA-256 |
| --- | --- | --- | ---: | --- |
| `app/assets/sky/weather/clouds/FX_CloudAlpha03.png` | `FX_CloudAlpha03.png` | 2048×2048, LA (luminance and alpha) | 2,017,932 bytes | `602A55F5E25E606999BFA218572A9703F54469ED1FE7C857C77E5038CC4681EE` |
| `app/assets/sky/weather/clouds/FX_CloudAlpha06.png` | `FX_CloudAlpha06.png` | 2048×2048, LA (luminance and alpha) | 2,059,759 bytes | `A1F05810C43D7811CB72F460595CC6E446E20FD4601342BA93D30045CB6095F1` |

Both runtime images are byte-identical to their archive members; no crop, color change, alpha edit, or other derivative was made. The asset provenance and runtime license notice are recorded in [source provenance](../../../../assets/sky/weather/PROVENANCE.md) and [the runtime notices](../../../../app/assets/sky/weather/LICENSES.md).

Visual review found `FX_CloudAlpha06` to have the strongest vertically irregular cloud mass in the pack, while `FX_CloudAlpha03` provides a more compact cumuliform shape. Together they offer distinct silhouettes for a small, depth-separated cluster. They are 2D images, not cloud volumes; the root track approved them only as inputs to an isolated scene trial.

## POM Clouds candidate

The [POM Clouds addon](https://github.com/sanketsbrush/Godot-4.6-3D-POM-clouds-addon/tree/8701a9dda9fbeb7e86aeb95255138803a757de15) was reviewed at commit `8701a9dda9fbeb7e86aeb95255138803a757de15`. Its repository includes an MIT license, but no external cloud bitmap: the material embeds a Godot `FastNoiseLite` noise texture and gradient resources. `POM_Clouds.gd` builds a 20-layer `MultiMesh` from one plane and recenters its top-level node on the camera’s horizontal position each frame. The material’s default mesh scale is 100,000 m. That design and the upstream screenshots read as a broad overhead canopy, not a stationary, spatially bounded thunderhead, so it was rejected for this role.

The upstream README advertises Compatibility, Mobile, and Forward+ support. Its screenshots show Godot 4.6.2 and include Forward+ and Mobile editor modes. This intake did not run the addon in the pinned Godot 4.7.2 Compatibility/GLES3 project, consult Context7, or measure performance; the repository claim is not local qualification. The addon remains a possible reference for a separate full-sky treatment, not an adopted dependency.

## Remaining qualification

No Godot runtime files or shaders were changed during intake. The selected PNGs still need an engine import check and a native Compatibility scene trial that demonstrates the cluster’s world anchoring, parallax, overlap/occlusion, and camera-turn behavior at the intended distance. A single isolated card may expose its plane; this intake does not resolve that risk. The pack includes no rain-curtain image or volume, so rain appearance is outside this asset selection. The FW-83 visual and performance acceptance gates remain open.

Downloads and visual-review scratch files are under `.tools/fw83-intake/` and are not application assets.

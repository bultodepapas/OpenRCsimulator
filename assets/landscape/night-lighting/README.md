# Night-lighting source samples

2026-10-13 · **Research inputs only; not imported into the application.**

These unmodified free downloads support the [night-landscape plan](../../../docs/plans/night-landscape-lighting.md). Selection rationale and static inspection are in [FW-66](../../../docs/research/field-world/FW-66/README.md#resource-comparison). [PROVENANCE.json](PROVENANCE.json) records exact download URLs, source authors, archive members and SHA-256 hashes; [LICENSES.md](LICENSES.md) records license evidence.

The [26-investigation follow-up](../../../docs/research/field-world/FW-66/investigations.md) added five source files. The collection now contains **10 art source files, 3,961,937 bytes**, excluding license notes. Source size is not imported GPU memory or shipped package size.

| Source | Files | Intake limitation |
| --- | --- | --- |
| Innerscene twin floodlight | `source/motion-security-floodlight.glb` | Separate housings/arms/lenses, no mast; material adaptation and draw batching pending. |
| Innerscene path light | `source/stake-path-light.glb` | Optional replacement candidate; not a solar-specific product. |
| Kenney Survival Kit 2.0 | `source/campfire-pit.glb`, `source/Textures/colormap.png` | The GLB references this external texture. Keep their relative paths together; no animated flame is included in this model. |
| tauran flame sheet | `source/flame.png` | Baked isometric appearance and nonintegral atlas cell size require an in-engine test. |
| Mikodrak / Martin Jelinek Fire FX | `source/fire-fx-40-frames.zip` | Alternative flame candidate: 80 RGBA PNGs, all 81×123, in two numbered sets of 40, plus previews. Playback, layering and close-range quality are unverified; do not ship the source ZIP. |
| ohyhei smoke sheet | `source/smoke-sprite-sheet.png` | 1280×1280, 5×5 grid, 21 occupied cells. Final four cells are blank; frame order/playback and material treatment need qualification. |
| Rob Tuytel / Poly Haven Burned Ground 01 | `source/burned-ground-01-{diff,nor-gl,rough}-1k.jpg` | Three 1024×1024 maps for a possible local hearth patch. UV scale, edge blending and imported memory must pass intake. |

No source file has been modeled, recolored, repacked or optimized. Godot import, visual quality, timing and export qualification belong to FW-67 onward. Future derivatives must record their source hashes and reproducible conversion; do not overwrite these originals or hand-edit generated results. Ship only accepted derivatives and their credits under the application asset directory.

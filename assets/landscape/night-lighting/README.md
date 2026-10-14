# Night-lighting source samples

2026-10-13 · **Research inputs only; not imported into the application.**

These unmodified free downloads support the [night-landscape plan](../../../docs/plans/night-landscape-lighting.md). Selection rationale and static inspection are in [FW-66](../../../docs/research/field-world/FW-66/README.md#resource-comparison). [PROVENANCE.json](PROVENANCE.json) records exact download URLs, source authors, archive members and SHA-256 hashes; [LICENSES.md](LICENSES.md) records license evidence.

| Source | Files | Intake limitation |
| --- | --- | --- |
| Innerscene twin floodlight | `source/motion-security-floodlight.glb` | Separate housings/arms/lenses, no mast; material adaptation and draw batching pending. |
| Innerscene path light | `source/stake-path-light.glb` | Optional replacement candidate; not a solar-specific product. |
| Kenney Survival Kit 2.0 | `source/campfire-pit.glb`, `source/Textures/colormap.png` | The GLB references this external texture. Keep their relative paths together; no animated flame is included in this model. |
| tauran flame sheet | `source/flame.png` | Baked isometric appearance and nonintegral atlas cell size require an in-engine test. |

No source file has been modeled, recolored, repacked or optimized. Godot import, visual quality, timing and export qualification belong to FW-67 onward. Future derivatives must record their source hashes and reproducible conversion; do not overwrite these originals or hand-edit generated results. Ship only accepted derivatives and their credits under the application asset directory.

# L6b-R2 source-material foliage mask

This evidence records the foliage-only palette mask added to the three-card tree atlas. The mask is derived from the exact source glTF material assignments (`Bark_NormalTree`, `Leaves_NormalTree`, and `Leaves_Pine`); no texture was modeled, painted, or classified from RGB color. The runtime color atlas and source license are unchanged.

The native full build used Godot 4.7.2 Compatibility on an NVIDIA GeForce RTX 3090. Its `--match-atlas` reference was the existing runtime atlas. All 27 outputs match the retained full build manifest. The generated mask and catalog are byte-identical to their integrated runtime files; the generated color atlas was not promoted.

Before edge reconciliation, the baked and runtime alpha silhouettes exceed IoU 0.9988 for all three species at both nonzero coverage and the 0.5 cutoff. The processor then sets the mask alpha to the runtime atlas alpha exactly, filling only the few runtime-only edge labels from the nearest source material ID. The fourth atlas tile remains transparent. `atlas-analysis.json` contains the per-species measurements; `mask-audit.json` is produced by the fixture checker.

The retained binary mask is the exact runtime artifact. `catalog.json`, its import settings, build manifest, processor reports and raw logs are included. Source meshes and source textures are not duplicated here; their pinned hashes remain in [PROVENANCE.json](../../../../../assets/landscape/PROVENANCE.json) and the full build manifest. The [tree pipeline guide](../../../../../tools/trees/README.md) owns the bake and import procedure.

Reproduce the full native bake from the repository root with a fresh output directory:

```powershell
python tools/trees/build.py `
  --out tmp/tree-mask-reproduction `
  --match-atlas app/assets/landscape/trees/atlas.png `
  --godot .tools/Godot_v4.7.2-stable_win64.exe

python docs/research/visual-quality-implementation/L6b-R2/foliage-mask/fixtures/verify_mask.py `
  --build-root tmp/tree-mask-reproduction `
  --write docs/research/visual-quality-implementation/L6b-R2/foliage-mask/mask-audit.json
```

The fixture checker validates runtime provenance hashes, retained mask/catalog equality, exact alpha parity, per-species class coverage and silhouette IoU. With `--build-root`, it also checks every generated output against `manifest.json`.

Headless app checks passed: [test_tree_assets.gd](../../../../../app/tests/test_tree_assets.gd) (68 checks, including imported alpha parity through every mip) and [test_treeline.gd](../../../../../app/tests/test_treeline.gd) (28,631 checks). The tree runtime test reported the existing warning that the imported `oak_tree` alpha-blended source material does not support tree wind; that warning is unrelated to the card mask.

# Grass common short impostor bake

The existing downloaded CC0 `Grass_Common_Short` glTF was rendered directly with the vegetation impostor baker. No source mesh, texture, or material was edited.

- Source: `grass_common_short`, 155 triangles, one surface and one material; geometry SHA-256 `6957b50622c9e26e7296c1b47ea8653bc0d957e0a547de444e2ed96f0075a21a`.
- Source bounds: 0.638870 × 1.334103 × 0.737265 m; source height 1.334103 m; square frame 1.467514 m.
- Bake: Blender 5.2.2 LTS EEVEE; azimuths 0°, 90°, 180°, and 270°; four 256 × 256 frames in a 1024 × 256 RGBA8 straight-alpha PNG.
- Color: source material Base Color and Alpha routed through the existing baker; unlit emission, Standard view transform, transparent background.
- Import: lossless (`compress/mode=0`), mipmaps disabled.
- Atlas SHA-256: `7d94fd6e6be26b4117a419fbcfb782dd73934f8e8e12ce4d8ef835eebabc64c9`.

Rebuild command:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python tools/landscape/vegetation/bake_hedge_impostor.py -- --source-asset-id grass_common_short --output-stem grass_common_short_4view --frame-size 256
```

Validation: the atlas was opened and visually reviewed. The same command with `--check` exited successfully and verified source geometry, source texture, license, archive, and atlas hashes against the manifest.
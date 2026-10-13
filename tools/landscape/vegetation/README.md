# Downloaded vegetation asset pipeline

This pipeline extracts a pinned selection of the free Quaternius Stylized Nature MegaKit Standard glTF files. It copies the archive's geometry, materials and textures without altering them, and writes a runtime catalog with source hashes, bounds, surface counts and triangle counts. It does not generate or model vegetation.

The exact 104,088,529-byte upstream archive is retained at `assets/landscape/vegetation/source/quaternius_stylized_nature_megakit_standard.zip`. Its SHA-256 is `298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9`; the embedded `License_Standard.txt` is CC0-1.0 and its SHA-256 is `120710e542c3ebaf83856c4eb55b4a1e680593b39302eba7fdc5d942dfe78c58`. The same license is copied beside the runtime catalog.

```powershell
python tools/landscape/vegetation/build_library.py
python tools/landscape/vegetation/build_library.py --check
```

Godot 4.7.2 imports the preserved `.gltf` files directly. `ResourceImporterScene` generates automatic mesh LODs and shadow meshes for these sources; original downloaded glTF files remain the geometry source. The selected assets provide two trees, two shrubs, three grass families plus a fern, and three flowering families. The Standard archive has no authored crop or reed models.

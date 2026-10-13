# Downloaded vegetation asset pipeline

`build_library.py` extracts a pinned selection of source geometry without creating or editing any plant geometry. It retains the source archives and license evidence under `assets/landscape/vegetation/source/`, copies exact glTF or OBJ/MTL members into `app/assets/landscape/vegetation/models/`, and writes `catalog.json` with source hashes, authored grounded bounds, surface counts and triangle counts.

The runtime library contains 3 trees, 2 shrubs, 4 grass/herb assets, 3 flowering assets, 2 crops and 1 reed clump. Quaternius's Stylized Nature MegaKit Standard supplies the trees, shrubs, grass, herbs and flowers under CC0-1.0. A second Quaternius CC0 pack supplies mature corn and wheat; Aredon's CC0 low-poly reed supplies the reed clump. Source pages, archive hashes and license evidence are recorded in the catalog and source notices.

```powershell
python tools/landscape/vegetation/build_library.py
python tools/landscape/vegetation/build_library.py --check
```

Godot 4.7.2 imports the preserved glTF sources directly and generates mesh LODs and shadow meshes. Crop and reed OBJ/MTL files are also preserved directly and use Godot's OBJ importer; their source geometry does not receive generated LODs.

# RC ground textures

The source [manifest.json](manifest.json) is authoritative for original-file URLs, dimensions and hashes, including each retained map's SHA-256. It records the Dirt and Grass 001 maps used at runtime and their 4K A/B source counterparts. Runtime uses only the 2K maps under `app/assets/landscape/rc-ground/`; the 4K maps in `source/` are comparison material and are not included in the runtime package. Sparse Grass is recorded as a reviewed, rejected candidate but its unused images are not retained.

Run the offline integrity check from the repository root:

```powershell
python tools/ground/import_rc_ground.py --check
```

It makes no network requests or writes. It verifies retained source and runtime bytes against the recorded hashes and dimensions, checks the Godot import settings, and confirms the packaged manifest is the exact generated runtime subset of the source manifest.

To reproduce only the packaged metadata offline from the checked-in source manifest:

```powershell
python tools/ground/import_rc_ground.py --emit-runtime
```

This writes `app/assets/landscape/rc-ground/manifest.json` and `LICENSES.txt` without touching texture images or import sidecars. To reacquire or refresh original files and provenance from the publishers, run the importer without a mode flag; it uses only Python's standard library and downloads the original JPG maps without pixel transformations. AmbientCG source maps are extracted from its ZIPs and the temporary archives are discarded. After a fresh intake, run `--check`.

License evidence URLs in the source manifest were checked on 2026-10-15. Runtime credits and per-map source URLs are in [LICENSES.txt](../../../app/assets/landscape/rc-ground/LICENSES.txt); attribution is voluntary under the publishers' CC0 1.0 terms.

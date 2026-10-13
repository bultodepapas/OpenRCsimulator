# Lake water sources

Run `powershell -NoProfile -File tools/landscape/lake/fetch_water_sources.ps1` to fetch the pinned MIT shader source, the selected CC0 audio prototype files, and one retained alternate CC0 sound pack. The helper verifies each SHA-256 and refuses to overwrite a local file whose hash differs. Source and license details are in `assets/landscape/lake/water-source/PROVENANCE.md` and `app/assets/audio/water/LICENSES.md`.

The production adaptation is maintained in `app/render/lake/water.gdshader`; it is not generated from the upstream ocean shader. This keeps the Compatibility/OpenGL depth conversion, deterministic simulation clock, shared lake-physics waves, and finite shoreline behavior explicit and reviewable.

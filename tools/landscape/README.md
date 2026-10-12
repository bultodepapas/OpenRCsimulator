# Landscape upgrade tools

Status: LU-06 native evidence tooling, 2026-10-11. Target: pinned Godot 4.7.2 Compatibility.

`app/tests/capture_landscape_upgrade.gd` builds the production world. Set `--out=<absolute-directory>`, `--cases=<comma-separated-postcard-or-glare-cases>`, `--frames=600`, `--width=1920`, and `--height=1080` after Godot's `--`. It captures raw PNGs and frame intervals after 60 warmup frames. Scenery audio is disabled; it measures rendering, not live flight physics. FW presets use `--time_of_day=night|sunset`; explicit TOD uses `--time-of-day=00:00`. The report retains actual engine, renderer, dimensions, arguments, memory, draws and primitives.

Glare cases: `glare_clear,glare_off,glare_blocked,glare_blocked_off,glare_partial,glare_partial_off,glare_aircraft,glare_aircraft_off,glare_aircraft_left,glare_aircraft_left_off,glare_aircraft_right,glare_aircraft_right_off,glare_side,glare_side_off,glare_night,glare_night_off,glare_cloud,glare_cloud_off,glare_low_exposure,glare_low_exposure_off,glare_half`.

`python tools/landscape/verify_glare.py <capture-folder>` checks those matched images. Install the exact optional evidence dependency with `python -m pip install -r tools/landscape/requirements.txt`; it is not an application dependency. The checker writes `glare-checks.json` and fails if any present case violates its bound.

`python tools/landscape/make_validation_snapshot.py <new-directory>` preserves current tracked/untracked nonignored source in an isolated copy, records original SHA-256 hashes, normalizes text line endings only there, and copies the already-installed pinned Linux engine. A shallow clone retains the real source HEAD for replay/build provenance before the current working files are copied over it. It refuses an existing destination. For WSL, copy this snapshot to a new directory on the Linux filesystem (for example under `/var/tmp`) and run `bash app/test.sh` there: per-script engine startup is much slower on `/mnt/c`. This avoids changing concurrent developers' Windows source files during deterministic generator checks. Keep the copy and test command in one WSL invocation; this host discarded `/tmp` copies between invocations.

`app/tests/test_landscape_runtime.gd` exercises actual flight/scenery contact, crash presentation, secondary Godot shapes, pause and reset. `-- --out=<absolute-directory> --soundscape=off` additionally saves five native screenshots and a structured result. A headless run covers state behavior but is not visual evidence.

Production controls: `--sun-glare=0..2` (or `off`), `OPENRC_SUN_GLARE`; `--landscape-upgrade=off`, `OPENRC_LANDSCAPE_UPGRADE=off`; existing scenery switches remain in [scenery tools](../scenery/README.md). The upgrade switch disables the new runtime integration, not the authored people/parking refinements.

Final proofs, screenshots and limits: [LU-06](../../docs/research/landscape-upgrade/LU-06/README.md).

# Atmosphere evidence tools

## Sky collection and conditions UI (FW-78/79)

`sky_gallery.gd` renders the production `World`/`Atmosphere` in a native Compatibility SubViewport at 1280×720 with 4× MSAA. It records nine daytime profiles plus quiet/peak electrical-storm views at full and new moon. `--mode=day`, `--mode=night` or the default `--mode=all` selects the matrix; `--horizon=on` adds low-angle views. `--write-previews=on` writes nine runtime card images under `app/assets/sky/weather/previews/` from daytime renders only; replacing existing images also requires `--overwrite-previews=on`. Reusing capture outputs requires `--overwrite=on`. The manifest records engine/adapter, lighting, camera and event identity. This is a composition fixture without a flown aircraft, not performance or flight-acceptance evidence.

```sh
"$(app/get-godot.sh)" --path app --audio-driver Dummy --script "$PWD/tools/atmosphere/sky_gallery.gd" -- --out=/tmp/sky-gallery --mode=all
"$(app/get-godot.sh)" --path app --audio-driver Dummy --script "$PWD/tools/atmosphere/sky_ui_capture.gd" -- --out=/tmp/sky-ui --locale=es
```

The UI fixture opens the actual Home/weather editor with a temporary preference file and captures the gallery and storm controls. Repeat with `--locale=en`; import thumbnails before running it. Each tool manually draws a bounded set of settled frames and writes only its caller-selected output folder (plus the optional previews). Use a visible native GPU renderer for visual review. [Capture record](../../docs/research/field-world/FW-79/README.md), [UI/lifecycle evidence](../../docs/research/field-world/FW-78/README.md).

## Directional cloud relief (L4c)

`l4c_verify.py` runs native Compatibility captures with exact zero-strength,
repeat, clear-sky and ground parity, plus an aircraft-interior guard allowing one
8-bit level for mixed MSAA coverage. `--profile` instead runs
three alternating pairs of ten-second warmups and sixty-second samples at 720p
and 1080p; only 720p has the predeclared incremental GPU budget. The always-updating
off-screen viewport renders the production field, sky and aircraft through the
real GPU. It isolates static rendering, not whole-flight performance.

`l4c_integration.py` exercises the actual app entry, 721-sample flight traces,
both time-of-day routes and an exported Windows pack. Both tools require a fresh
`--out`, `--godot`, `--baseline` app directory and `--app` candidate directory.
Use the isolated evidence dependencies in `l4c_requirements.txt`; do not upgrade
the project's existing visual environment. Full commands, sources, budgets and
limits: [L4c report](../../docs/research/visual-quality-implementation/L4c/README.md).

## Existing sky and shadow checks

`check_phase6.py` captures and checks the L4b sky and cloud-shadow A/B using the production field, `Atmosphere`, and `ShaderClock` paths. `capture_phase6.gd` is its Godot render script.

Run from the repository root with a fresh output directory:

```sh
"$(app/tests/visual-env.sh)" tools/atmosphere/check_phase6.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l4b-atmosphere
```

The default set compares production strengths with a legacy view that zeros the cluster, cirrus, silver-lining, directional cloud-relief, and ground-shadow terms. Both retain the existing fair-weather cloud deck. It renders 15 views per mode at t=0, 10, and 120 s, plus a two-time high-ground shadow-off control. Each mode runs twice in a fresh process. The checker requires byte-identical repeats, validates camera and knob metadata, measures same-camera A/B deltas and cloud drift, and confirms that the enhanced ground crop changes against an otherwise identical zero-shadow control. `--baseline-app /path/to/frozen/app` additionally captures the pre-Phase-6 code in legacy-only mode and requires its PNGs to match the candidate's zero-strength legacy images. `--legacy-only` runs just that compatibility capture against an old project with no Phase 6 uniforms.

Use `--shadow-strength 0.6` only for a diagnostic enhanced-mode capture; the default reads the value from production `Spec.ATMOSPHERE`. The built-in shadow-off control always sets that one ground uniform to zero while retaining the enhanced sky and all other production parameters.

`--grading` adds a third 15-view mode with Environment adjustment enabled at brightness 1.0, contrast 1.04 and saturation 1.02. It compares those estimated values with the normal enhanced mode. Adjustment stays disabled by default. The summary includes per-file SHA-256 hashes for runtime app sources/assets and both capture producers, and the run fails if any of those files change while captures are being produced.

`check_cloud_probe.py` renders the shared density include into a twelve-panel GPU atlas twice. It checks finite bounded density, 64-cell periodicity, ground/sky projection, the drift wrap and a wrong-sign control. This mathematical probe complements the production shadow-off captures; it does not establish hardware performance. Its output directory can be reused safely.

```sh
"$(app/tests/visual-env.sh)" tools/atmosphere/check_cloud_probe.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l15d-cloud-probe
```

## Distant storm-bank views (FW-83)

`storm_bank_capture.gd` builds the production default field and World with the
Distant Storm profile. It captures day, dusk and full moon at the pilot position
and 500 m cross-track, each at 50° and 25° FOV: 12 PNGs and a JSON manifest. The
formation's actual diagnostic target drives the camera. This is static render
evidence, not a flight or GPU-performance benchmark.

Run the pinned native Godot without `--headless`, using an absolute log path and
a fresh output directory:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy --log-file C:/tmp/fw83.log --script (Resolve-Path tools/atmosphere/storm_bank_capture.gd).Path -- --out=C:/tmp/fw83 --only=all --view=all
```

`--only=day|dusk|fullmoon|all` and `--view=pilot|cross500|all` select subsets.
`--overwrite=on` explicitly allows reuse of an output directory. Keep rejected
probes outside tracked evidence; inspect the results before replacing the selector
preview. [FW-83 evidence](../../docs/research/field-world/FW-83/README.md) owns the
accepted images, resource/license comparison, test results and remaining limits.

`sky_pack_probe.gd` checks all nine catalog profiles/previews, storm audio,
packaged notices and storm scripts/shaders. It also checks the two imported cloud
images' size, LA8 format and mip chains. Running it with `--main-pack=<pack>` proves
those resources load from that PCK; inspect export and engine logs separately,
because an erroring export can still write a PCK and return exit code 0.

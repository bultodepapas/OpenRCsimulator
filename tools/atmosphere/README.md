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

### Cloud-shadow tile agreement (DT-MAC-06b C2)

`shadow_map_probe.gd` compares the periodic noise tile (`render/cloud_shadow_map.gd`, on by default with a renderer) with per-pixel `cloud_density()` on the GPU. It covers four cases: the default deck, a tile wrap, a clustered overcast and a full tile. It fails when the absolute density error exceeds 0.05 at any pixel or 0.003 on average. Linux needs a display; macOS runs natively:

```sh
xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --audio-driver Dummy \
  --script "$PWD/tools/atmosphere/shadow_map_probe.gd" -- --out=/abs/new/result.json
```

On macOS, add `--rendering-method mobile --rendering-driver metal` and omit `xvfb-run`. Probe uniforms are prefixed: `cloud_density()` reassigns a local `cluster`, which a same-named uniform captures on RenderingDevice backends. It also checks C5b `cloud_detail_density` (tile octaves 0–2 plus per-pixel octaves 3–4; ≤ 0.025 / 0.0015). A 3D mode renders a spatial quad with the exact density in R and the tile density in G, so 3D-stage sampling is checked independently of output encoding. This checks density agreement only; appearance, motion and performance need their own evidence.

The v2 probe also exercises a real **sky shader**, refuses headless execution and
fails if any required seed never becomes ready. Canvas retains the original
maximum/mean density bounds. Spatial and sky consumers test the same maximum
inside the shader, before output encoding; encoded R/G differences remain
diagnostics. This avoids interpreting Mobile's sRGB amplification as linear
density error. It does not waive a visual gate.
Blank-tile negative controls must fail agreement in both cache modes and all
three shader stages, so a silently disabled cache cannot pass by comparing the
analytic function to itself. Every case also requires a complete, finite 512×512
readback; missing, wrongly sized or nonfinite images fail even for negative
controls. Reports retain per-case validity, engine and source hashes.

### Cache lifecycle and isolated experiments (DT-MAC-06b-R1)

The production cache now keeps analytic noise until a validated HDR bake is
published. It retries once, then stays analytic for that seed. At most four seeds
are retained. `CloudShadowMap.diagnostics()` distinguishes disabled, unused,
pending, ready, failed and capacity-limited consumers. Readiness checks 16
seed-specific samples in both channels; it is not a complete image comparison.

| Environment | Meaning |
| --- | --- |
| `OPENRC_CLOUD_SHADOW_MAP=0` / `1` | Global off/on; unset enables graphical runs only |
| `OPENRC_CLOUD_SHADOW_MAP_GROUND=0` / `1` | Override ground/near-grass caching independently |
| `OPENRC_CLOUD_SHADOW_MAP_SKY=0` / `1` | Override sky-relief caching independently |
| `OPENRC_CLOUD_DENSITY_BOUNDS=off` / `three` / `two_three` | Sky analytic density baseline, bounds after octave three, or bounds after octaves two and three |

Unset per-consumer cache overrides inherit the global setting. The bounds
experiment defaults to `off`; unknown values also select `off` and remain visible
in diagnostics. Select it **before world construction**. The two shader variants
are cached, not rebuilt during flight. They preserve the original accumulation
for ambiguous samples; a `1e-5` threshold margin is conservative empirical
protection, not a proof for every backend. Cirrus/stretched decks are unchanged.
The sky's analytic relief fallback uses the selected variant too; cached relief
and ground shading retain their separate mechanisms.

Run the same probe with `--bounds=three` and `--bounds=two_three` to compare the
actual GPU candidate to the original analytic function in canvas, spatial and
sky consumers. Eight cases cover coverage extremes, clustering, negative
coordinates, lattice seams and different seeds. A deliberate density mutation
must be detected in all three consumers. The probe amplifies error before
8-bit readback; it is not a float32 bitwise equivalence proof. Its 512² targets
are numerical fixtures, not 1080p performance evidence. Use the
[sustained flight fixture](../../research/performance/README.md#repeatable-active-flight-dt-mac-03)
for matched complete-frame runs and the [capture workflow](../../docs/tools/graphics.md)
for actual 1920×1080 motion/readability review before promoting a variant.

**Native M1 result (2026-11-06):** both original bounded variants failed the
unchanged Metal numerical gate despite their earlier Windows GPU passes. Keep
them experimental and default `off`. A disposable reference-fallback variant
passed the strict `two_three` probe but regressed a layered-cloud flight screen;
it was not integrated. The cache itself passed canvas, spatial and sky checks.
[Native evidence and limits](../../docs/research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-06b-r2--dt-mac-02b-r2-native-verification-2026-11-06).

## Distant storm-bank views (FW-83)

`storm_bank_capture.gd` builds the production default field and World with the
Distant Storm profile. It captures day, dusk and full moon at the pilot position
and 500 m cross-track, each at 50° and 25° FOV: 12 PNGs and a JSON manifest. The
formation's actual diagnostic target drives the camera. This is static render
evidence, not a flight or GPU-performance benchmark.

Run the pinned native Godot without `--headless`, using an absolute log path and
a fresh output directory:

```powershell
& .tools/Godot_v4.8-beta2_win64_console.exe --path app --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy --log-file C:/tmp/fw83.log --script (Resolve-Path tools/atmosphere/storm_bank_capture.gd).Path -- --out=C:/tmp/fw83 --only=all --view=all
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

## Electrical bank pulses (FW-84b)

`electrical_bank_capture.gd` builds the production World and Lightning consumer,
looks at the actual bank target, and captures one deterministic cloud-to-ground
event before, during and after its pulse. Day, dusk, full moon and moonless night
produce 12 frames; Reduced and Off peaks in both night cases add four more.
The manifest records event anchors, bank/light state, actual exposure, astronomical
state, camera, engine/adapter and each PNG's SHA-256. It is a static scene harness
with no aircraft; actual Main captures and flight qualification are separate.

```powershell
& .tools/Godot_v4.8-beta2_win64_console.exe --path app --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy --log-file C:/tmp/fw84b.log --script (Resolve-Path tools/atmosphere/electrical_bank_capture.gd).Path -- --out=C:/tmp/fw84b --only=all
```

Use a fresh absolute output directory. `--only=day|dusk|fullmoon|newmoon|all` selects
lighting cases; `--overwrite=on` permits replacement explicitly. Syntax checking
uses Godot's `--headless --check-only --script <absolute script path>`.
[Accepted FW-84 evidence](../../docs/research/field-world/FW-84/README.md) owns the
captures, quantitative comparisons, preview provenance and remaining gates.

Regenerate the Electrical Storm card from the accepted full-moon peak with the
retained Lanczos resizer. The utility validates both absolute PNG paths and the
384×216 output; it replaces the output file.

```powershell
$source = (Resolve-Path docs/research/field-world/FW-84/captures/fw84b/electrical_storm-fullmoon-peak-full.png).Path
$out = (Resolve-Path app/assets/sky/weather/previews/electrical_storm.png).Path
& .tools/Godot_v4.8-beta2_win64_console.exe --headless --path app --audio-driver Dummy --script (Resolve-Path tools/atmosphere/resize_preview.gd).Path -- "--source=$source" "--out=$out"
```

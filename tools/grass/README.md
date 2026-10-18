# L11a grass placement

## Enhanced grass preview

The implemented preview combines retained 2K grass surface detail, the short-grass-heavy allocation and bounded imported-grass wind. It is opt-in while full-session and owner acceptance remain open. From the repository root on Windows:

```powershell
$env:OPENRC_GRASS_QUALITY = 'enhanced'
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app
```

Clear the variable (`Remove-Item Env:OPENRC_GRASS_QUALITY`) before launching to restore the original route. Unknown values also select the original route. No preference or physics data is changed. [Implementation evidence and outstanding gates](../../docs/research/visual-quality-implementation/grass-quality/README.md).

`quality_capture.gd` captures the complete field at fixed views and through a short moving sequence; `quality_compare.py capture` verifies identities, image hashes and repeat controls. `quality_compare.py profile` reduces five alternating baseline/candidate pairs. `material_capture.gd` isolates source material parity under front/back/shadow/local lights and transformed copies; `material_compare.py <manifest.json> --out <new-report.json>` verifies its pixel controls. Both render tools require a native renderer, not `--headless`. Their detailed protocol is in the evidence report.

The resource audit is read-only and may run headless, with a new output file:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/tools/grass/audit_materials.gd" -- --out="$PWD/tmp/grass-audit-new.json"
```

`check_pack.gd` verifies a Windows-preset PCK from a new, empty project directory. Export with the repository's configured `Windows Desktop` preset; supply absolute paths to the resource-only probe:

```powershell
New-Item -ItemType Directory tmp/grass-pack-new/empty
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app `
  --export-pack 'Windows Desktop' "$PWD/tmp/grass-pack-new/openrc.pck"
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path "$PWD/tmp/grass-pack-new/empty" `
  --script "$PWD/tools/grass/check_pack.gd" -- `
  "$PWD/tmp/grass-pack-new/openrc.pck" "$PWD/app" "$PWD/tmp/grass-pack-new/result.json"
```

The checker mounts the pack itself, loads grass resources and compares them with the source project's imported textures. It does not start the packaged application's native extensions or qualify GPU output. Check the export and probe logs as well as exit codes.

`check_lifecycle.gd` exercises the actual Home buttons, fixed-wing End flight and both RC garage routes using private preferences. It checks rendered surface bindings, scene-owned material isolation, source geometry, released scene references and stable node/object counts. It captures only the first cycle's four startup/paused views, not driving or flight acceptance:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app `
  --script "$PWD/tools/grass/check_lifecycle.gd" -- `
  --quality=enhanced --cycles=20 --capture=on --out="$PWD/tmp/grass-lifecycle-new"
```

Use `--quality=default --cycles=2` for the control. Headless contract checks require `--capture=off`. Run the native capture outside timing campaigns. The full DT reset/Workshop and long-duration soak requirements remain separate.

`profile_session.py` collects a normal visible flight with live input, five alternating default/enhanced pairs, 10 seconds warmup and 60 seconds measured per run. Use an idle host and keep the flight window focused; run captures and other tests separately:

```powershell
python tools/grass/profile_session.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe `
  --app app --out tmp/grass-native-profile-new
python -m unittest discover -s tools/grass -p test_profile_session.py
```

Before each launch, one bounded OS process inventory rejects another Godot process or an unavailable inventory; it never terminates other work. It does not poll subprocesses inside timed intervals or prove that no unrelated process starts later. The runner stops at the first invalid, paused, incomplete or mismatched run and retains its log, available raw data and partial campaign. Missing reports and null pacing results are recorded as ineligible runs; collection exceptions finalize the campaign as stopped and preserve the failed attempt paths. Eligible pacing misses are retained without being recategorized as collection failures. Runtime source/config, glTF buffers, native libraries and engine hashes bracket the campaign, including both the Windows console launcher and its sibling runtime executable. Reports verify the live-input route, camera and render settings. The report-time `grass_scene_snapshot.gd` observer verifies effective ground/grass material bindings, species allocation and scenery quality; hidden or unsubmitted grass cannot qualify. Ground consistency compares texture slots and resource identities, and the runner requires the expected turf and enhanced photographic maps in their exact shader uniforms. Older reports without the per-uniform binding map cannot qualify with this runner. It runs after frame collection and does not measure GPU visibility. Paired p95/p99 changes do not close exact-input, owner or combined visual-budget acceptance.

## Audit and optimization checks

The imported placement selector caches only deterministic per-species rank indices (6,000 packed 64-bit keys). It rechecks field and exclusion acceptance on every call and stops when each species quota is filled. `layout_benchmark.gd` compares complete output dictionaries/order against the independent previous algorithm across field, mask and quality cases. Run timings separately on an idle host:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app `
  --script "$PWD/tools/grass/layout_benchmark.gd" -- --mode=check --report="$PWD/tmp/grass-layout-check.json"
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app `
  --script "$PWD/tools/grass/layout_benchmark.gd" -- --mode=benchmark --grass-mode=enhanced `
  --report="$PWD/tmp/grass-layout-timing.json"
```

Use a new report path; `--grass-mode=default` measures the other profile. Timings cover layout selection, not full scene loading or FPS. Cold rank-cache construction and warm alternating measurements are separate; raw microsecond samples are retained.

`transition_capture.gd -- --material=default|enhanced --quality=low|balanced|high --out=<new-directory>` captures 92 matched visible/hidden poses per profile through the production field. Run it natively with the pinned engine and `--path app`; do not use headless mode. `python tools/grass/transition_compare.py --captures <six-directories> --out <new-report.json>` checks the complete matrix and reports moving-boundary residuals. These are diagnostics, not an automatic pop or static-seam pass.

`filter_capture.gd -- --sampling=filtered|raw --scale=1|8|16 --out=<new-directory>` checks photographic grass sampling natively. Collect filtered 1× twice independently, raw 1×, raw 8× and raw 16×. Then run:

```powershell
python tools/grass/filter_compare.py --filtered <filtered> --raw <raw> `
  --reference8 <reference8> --reference16 <reference16> --repeat <filtered-repeat> --out <new-report.json>
```

The probe verifies active production material bindings, shader-default provenance, crop projection, six-pose production parity and independent repeats. It compares linear-light photographic residuals with supersampled references while preserving base-pixel derivative fade decisions. The reference uncertainty remains part of the gate. This is a bounded sampling check, not universal shimmer or owner acceptance.

`python tools/grass/check_state_invariance.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out <new-directory>` records current Stik/P-51 runway tapes, exact-preflights them, then compares default/enhanced replay in the same process that builds and inspects the grass route. Both RC vehicles use their existing GDScript recorder/checkpoint replay. The headless fixture omits only the independent treeline object and renders no GPU frame. Before/after hashes reject drift in grass/checker sources; flight-log identities independently guard the solver. Existing output is never overwritten. See the [audit evidence](../../docs/research/visual-quality-implementation/grass-quality/README.md#2026-10-18-audit-and-optimization).

## Placement source

`place.py` generates the committed `app/data/fields/grass.json` disk of 6,000 pilot-relative clump offsets. The disk is universal: the renderer clips it to the actual rough field and removes centers inside every runway or mown rectangle expanded by 0.4 m.

Rows are `[north_mm, east_mm, yaw_u16, size_u8]`. All four values are integers. Yaw is one unsigned turn fraction; size maps linearly from 0.75 to 1.25 in the renderer. The row digest is SHA-256 over ASCII lines `north,east,yaw,size\n` in stored order.

The PRNG is SplitMix64 with unbiased integer range sampling. Integer-disk rejection plus `isqrt` supplies directions; another integer rejection sampler gives a capped radial density. For radii above the estimated 3 m center cap, expected clump count per metre is constant, corresponding to spatial density proportional to 1/r. Within the cap, spatial density is constant and finite. Coordinates are rounded symmetrically to millimetres, and duplicate centers are rejected.

The 6,000-clump count is an estimate based on the 6,000-clump rendering spike in [grass investigation 05](../../docs/research/landscape-investigations/05-grass-rendering.md). The 30 m extent comes from that investigation's L11 recommendation. The study asks for 1/r density but does not define a center cap; 3 m is an explicit implementation estimate. This layout is visual and unsurveyed. It does not encode field boundaries, runway/mown exclusions, collision, or terrain.

```sh
python3 tools/grass/place.py
python3 tools/grass/place.py --check
python3 tools/grass/test_place.py
```

`--check` regenerates and compares the exact canonical JSON bytes without writing. The tests cover count, disk bounds, unique centers, integer encoding, radial ring proportions, repeatability, digest integrity, the committed file, and mutation detection using a temporary copy.

## Render evidence

The capture runs two explicit near-grass paths through the production field builder. `candidate-repeat-*` disables scenery and checks the L11a procedural fallback: seven opaque triangles per clump, fixed-root UV-weighted sway, the 22–30 m fade and its bounded draw/primitive cost. `scenery-repeat-*` enables default scenery at high quality and checks 150 placements in three downloaded source batches (`grass_common_short`, `grass_common_tall`, `grass_wispy_tall`), unchanged geometry, opaque per-pixel-lit shading, disabled shadow casting, a 30 m pilot radius and runway exclusion. By default, `static_baseline` retains the original StandardMaterial3D surfaces and 67/42/41 batch allocation (49,579 source triangles). With `OPENRC_GRASS_QUALITY=enhanced`, `qualified_wind` uses the exact `res://scenery/imported_grass.gdshader`; its albedo texture/color, UV scale/offset, vertex-color use, roughness, metallic and specular values must match the source material. This opt-in profile reallocates the same 150 clumps as 100/30/20 (37,720 source triangles). The enhanced profile includes imported-grass wind probes; a static baseline does not. The scenery run also checks the current downloaded flower batches (`clover_1`, `flower_3_group`, `flower_4_group`) under `BotanicalHabitats`.

Both paths compare matched grass-hidden/visible images, enforce the +5 draw / +100k primitive ceiling, constrain changed pixels to the projected 36 m placement envelope and repeat independently byte for byte. The qualified imported-wind probes compare t=0 and t=1 at zero wind, t=0 and t=1 at a 5 m/s wind, the t=0/t=1024 wrap, and a final calm t=0 repeat. The v3 capture contract warms visible grass for 12 frames, then settles each case for three frames. It freezes the global shader clock/wind and supplies case values to capture-owned NearGrass shader copies; only the two global uniform declarations become local declarations. Source identity and material properties are inspected before that capture-only adaptation. Camera interpolation is disabled for these fixed-pose comparisons. They check repeatability, visible image motion and that changed pixels stay inside the projected grass envelope; they do not estimate target-device frame time or prove physical wind response. The L11a report remains dated evidence for its original procedural implementation and baseline parity; it does not describe the current imported default-scene contract. Use a fresh output directory:

```sh
"$(app/tests/visual-env.sh)" tools/grass/check_grass.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l11a-grass
"$(app/tests/visual-env.sh)" tools/grass/check_grass_seam.py \
  --captures /tmp/l11a-grass/candidate-repeat-1 --out /tmp/l11a-grass/seam-summary.json --self-test
```

In its `scenery-repeat-*` runs, the first command uses the default static imported-material baseline. It does not test the enhanced material. To opt into the candidate shader and 100/30/20 allocation for the full repeated capture check, prefix the command with `OPENRC_GRASS_QUALITY=enhanced`:

```sh
OPENRC_GRASS_QUALITY=enhanced "$(app/tests/visual-env.sh)" tools/grass/check_grass.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l11a-grass-enhanced
```

To reproduce only the qualified imported grass pair and five clock/wind probes, leaving independent-repeat and image-contract checking to the full command, use an empty output directory and the same opt-in:

```sh
OPENRC_GRASS_QUALITY=enhanced xvfb-run -a -s "-screen 0 1280x720x24" \
  "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy \
  --script tools/grass/capture_grass.gd -- \
  --out=/tmp/l15c-imported-wind --mode=scenery --scenery=on \
  --scenery_audio=off --scenery_birds=off
```

The capture manifest records `material_mode`, shader path and source-parameter parity separately. A static material baseline emits only the grass pair and is not treated as a wind test. `OPENRC_GRASS_QUALITY=enhanced` is a preview switch and remains opt-in until native full-session qualification. The optional `--baseline-app` flag above compares the L11a grass-off fallback; it is not a comparison between the static imported-material baseline and the qualified wind shader.

For initial L11a acceptance, add `--baseline-app /path/to/pre-L11a/app` to the first command; the retained acceptance run includes this exact grass-off parity check for the legacy fallback. Later regressions can run without the old checkout; a complete capture set alone is not a claim of legacy parity or human Gate L acceptance.

The second command evaluates the projected 25–35 m band in 1 m radial bins and eight screen strips. Every usable cell must keep mean absolute channel change within 3% and FLIP p99 within 0.1 (engineering estimates). Add `--mode imported` and select a `scenery-repeat-*` directory to check the imported route. The radial mask stays centered on the pilot when the camera moves. Every comparison requires matching calm/zero-clock captures. A completed failure writes its JSON and exits 1; an existing output is refused.

With `--self-test`, an identical-image reference must pass and a copy of that reference with a 25 cm dark seam segment must fail. This control remains meaningful when the real candidate already fails. Source captures are never changed. The independent local check supplements the full-annulus average so a narrow seam cannot hide inside a large mask. FLIP's spatial response can extend beyond changed pixels. The static hidden/visible comparison does not establish moving-view continuity; the imported default and enhanced routes both exceed the FLIP limit in the [2026-10-18 result](../../docs/research/visual-quality-implementation/grass-quality/README.md#2026-10-18-integration-follow-up).

These tools validate the recorded capture contract and repeatability only. Their headless OpenGL Compatibility captures do not measure target-GPU frame time or establish complete-session performance. Their success does not close the grass plan, owner visual review, flight readability, target-hardware performance or packaged-resource gates.

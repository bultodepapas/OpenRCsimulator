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

Both paths compare matched grass-hidden/visible images, enforce the +5 draw / +100k primitive ceiling, constrain changed pixels to the projected 36 m placement envelope and repeat independently byte for byte. The qualified imported-wind probes compare t=0 and t=1 at zero wind, t=0 and t=1 at a 5 m/s wind, and the t=0/t=1024 wrap. They check repeatability, visible image motion and that changed pixels stay inside the projected grass envelope; they do not estimate target-device frame time or prove physical wind response. The L11a report remains dated evidence for its original procedural implementation and baseline parity; it does not describe the current imported default-scene contract. Use a fresh output directory:

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

To reproduce only the qualified imported grass pair and four wind probes, leaving independent-repeat and image-contract checking to the full command, use an empty output directory and the same opt-in:

```sh
OPENRC_GRASS_QUALITY=enhanced xvfb-run -a -s "-screen 0 1280x720x24" \
  "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy \
  --script tools/grass/capture_grass.gd -- \
  --out=/tmp/l15c-imported-wind --mode=scenery --scenery=on \
  --scenery_audio=off --scenery_birds=off
```

The capture manifest records `material_mode`, shader path and source-parameter parity separately. A static material baseline emits only the grass pair and is not treated as a wind test. `OPENRC_GRASS_QUALITY=enhanced` is a preview switch and remains opt-in until native full-session qualification. The optional `--baseline-app` flag above compares the L11a grass-off fallback; it is not a comparison between the static imported-material baseline and the qualified wind shader.

For initial L11a acceptance, add `--baseline-app /path/to/pre-L11a/app` to the first command; the retained acceptance run includes this exact grass-off parity check for the legacy fallback. Later regressions can run without the old checkout; a complete capture set alone is not a claim of legacy parity or human Gate L acceptance.

The second command evaluates the projected 25–35 m band in 1 m radial bins and eight screen strips. Every usable cell must keep mean absolute channel change within 3% and FLIP p99 within 0.1 (engineering estimates). A copied image with a 25 cm dark seam segment must fail. Source captures are never changed. The independent local check supplements the full-annulus average so a narrow seam cannot hide inside a large mask.

These tools validate the recorded capture contract and repeatability only. Their headless OpenGL Compatibility captures do not measure target-GPU frame time or establish complete-session performance. Their success does not close the grass plan, owner visual review, flight readability, target-hardware performance or packaged-resource gates.

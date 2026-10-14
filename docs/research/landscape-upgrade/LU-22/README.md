# LU-22 lake water and imported vegetation evidence

**Snapshot date:** 2026-10-13. LU-22–27 implementation and native software verification are delivered. This report records downloaded sources, Compatibility images, an actual flight into the water, captured audio, performance and exported-resource checks. Independent visual/sound preference and lower-end hardware acceptance remain open.

## Sources and runtime data

The lake is a finite, irregular basin in [`app/data/fields/lake.json`](../../../../app/data/fields/lake.json). Its shoreline and bathymetry are estimates, not survey data. The water surface uses the project's separate Compatibility renderer adapter and the shared lake wave data; mean water level is 0.45 m below the surrounding ground and maximum basin depth is 5 m below water, with two bounded wave components and a 5.5 m shore fade. The renderer is pinned to Godot 4.7.2 Compatibility/OpenGL and reconstructs scene depth using OpenGL NDC Z. The upstream source review records the renderer references and why built-in SSR and compute are not used.

The shader reference is the [Boujie Water Shader](https://github.com/Chrisknyfe/boujie_water_shader), pinned at `25f3c2da458e0a4f65bdb5903dc068b050930c06`. Its preserved source file SHA-256 is `09a74e3b97738da896c9f39c73946e38f9487035c6559433316c2136ce84f607`; the preserved upstream MIT license SHA-256 is `fbde0da26c3bec6344219a8da2936e5ecb7eee6254f6080d2fe47d6b315ae856`. The adapted app shader SHA-256 is `8d5128e5e805d531bedb8cf46382b71c087b42154abdccebf1d77d4f1f302943` and [`water_material.gd`](../../../../app/render/lake/water_material.gd) is `31eec0518bb1d6e1750e1160f4d61bd769821d297b67211e3412dee1c360dfa7`. The adaptation removes the infinite ocean, third-party texture dependencies, and upstream vertex Gerstner waves. It uses no downloaded water textures. The exact source record and hashes are in [`water-source/PROVENANCE.md`](../../../../assets/landscape/lake/water-source/PROVENANCE.md); the MIT notice is also reproduced in the exported [`UPGRADE_CREDITS.md`](../../../../app/assets/landscape/UPGRADE_CREDITS.md).

The water audio is an audition/prototype set, not a claim about lake acoustics. The two Peludo splash files are CC0-1.0: `peludo-splash1.wav` SHA-256 `e45d466f7e63e5d566f8a822a7a1a3f7d5131319d17ca0436dcc615b251e9277`, and `peludo-splash2.wav` SHA-256 `ad9472b711666de2d43c3b102d155a5d1118b1fcd0ecd29cb63177256ab63f31`. RandomMind's five-minute Vistula wave recording is CC0-1.0: `randommind-vistula-short.mp3` SHA-256 `8c24607e41edd6f018ec3582a07e5a8dbc57347276339cb68440951a0fb4cfb1`. Exact source pages, download names, and the missing itch.io reference note for Peludo are in [`LICENSES.md`](../../../../app/assets/audio/water/LICENSES.md), SHA-256 `cf0adcdc34f0620d374d798ebfe16b707e4b4bd824d280c528ee6c2e6a726792`.

The runtime vegetation catalog contains 15 unchanged imported model assets: 3 trees, 2 shrubs, 4 grass/herbs, 3 flowers, 2 crops, and 1 reed clump. Their source geometry sums to 21,640 triangles for one of each catalog asset. The catalog SHA-256 is `65d8df415bbcb162405ecbdd7231c38ec41e83e5c9940e8d3a708f2c976a1c99`; the bundled Quaternius CC0 notice SHA-256 is `120710e542c3ebaf83856c4eb55b4a1e680593b39302eba7fdc5d942dfe78c58`. Its three source archives are pinned in the catalog: Quaternius *Stylized Nature MegaKit Standard*, `298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9`; Quaternius *LowPoly Crops Pack*, `48de7f1e092750a3832501e79d1463abeec8218c76090fc4b81fa8dfccacdb52`; and Aredon *LowPoly Reed*, `03fd4f90d92618090829bac1152e4280327edb179139ae3f0c66542af31b89bd`. Each is identified as CC0 in its retained source record. The two runtime four-view impostor manifests are also included in the pack: `bush_common_4view.json` SHA-256 `a5edd61c74228db18157e51975261b638ea72a20425ab69e577d4d849f600006` and `bush_common_flowers_4view.json` SHA-256 `1c673aea5119ad0de5a040d3271fd5ba979e70363a20ede170437c02177e3c85`.

## Export and headless verification

Linux, Windows, and macOS presets explicitly include the lake JSON, vegetation catalog and CC0 notice, both impostor JSON manifests, water audio license manifest, and the credits file containing the upstream MIT notice. [`export_presets.cfg`](../../../../app/export_presets.cfg) and [`UPGRADE_CREDITS.md`](../../../../app/assets/landscape/UPGRADE_CREDITS.md) remain the export and attribution references.

On 2026-10-13, I copied the current app tree and required root-level aircraft authoring proofs into `.tools/water-flyability-verify-20261013/`, imported resources, exported the Windows preset with the pinned Godot 4.7.2 Linux headless binary under WSL, and mounted the resulting 49,482,452-byte PCK in a separate empty project. Its SHA-256 is `7866cf49a679a43f850b690fdec56b31efc2247d9f6109cf5053a03638d43e9e`. The original empty-project verifier passed 60/60 checks at the production 240 Hz physics rate; five additional hedge-shader and water-plume assertions brought the final verifier to 65/65. It found the lake JSON, vegetation/tree catalogs and notices, both impostor manifests, water audio licenses and imported streams, water and bank shaders, and the diffuse-lit hedge impostor shader; all 15 catalog plant scenes loaded. It also loaded the compiled water-effects script and verified its pale plume tint, 0.85 m peak height, and 0.82 s duration. The actual `main.tscn` started an interactive `jensen-das-ugly-stik-60` session with `aircraft.ok=true` and `session.is_flyable()==true`; `start_error` and `pause_reason` were empty, and the field and session had the same normalized lake identity.

Snapshot inputs matched the live app tree byte-for-byte: [`project.godot`](../../../../app/project.godot), SHA-256 `3aabd16a3e29c08cecbff6d57a3d1cd9152e844191ced4235376ea3776bb9563` (reflection atlas count 2); [`export_presets.cfg`](../../../../app/export_presets.cfg), `6dbfec49eaf4e62014387beb605d7a1953a6d378f7441683d5fc2056608af30a`; [`bush_common_4view.gdshader`](../../../../app/assets/landscape/vegetation/impostors/bush_common_4view.gdshader), `73bd8931ad9bf372187976b54ae439a3e5ae43e138d4ff50788e84e098f4f50e`; and [`water_effects.gd`](../../../../app/render/lake/water_effects.gd), `59a6ee8bbb8e9fe6d995c00a5c78691252bfe6c161feca5ffc625a568cfe49e1`. The original empty-project fixture omitted the physics tick setting and therefore defaulted to 60 Hz. Mounting the same PCK under that setting reproduces a fatal aircraft-data rejection: `landing_gear: heave ω·dt = 0.388 (ω 23.3 rad/s at 60 Hz) is not < 0.1`; `aircraft.ok` and `session.is_flyable()` are false, and Main refuses interactive flight before building the field. This was a verifier configuration error, not a warning-only result or a production aircraft failure. At 240 Hz, the same check passes; the remaining inertia message is a nonfatal warning. The PCK is a temporary verification artifact, not a release package or native rendering test.

Headless Godot 4.7.2 checks used `--audio-driver Dummy` and completed without a native renderer capture:

| Check | Result |
| --- | --- |
| `test_imported_vegetation.gd` | Passed; this script prints a pass sentinel but no assertion total. |
| `test_lake_collision.gd` | 24 checks passed. |
| `test_lake_surface.gd` | 52 checks passed. |
| `test_lake_session.gd` | 29 checks passed. |
| `test_lake_ground_contact.gd` | 14 checks passed. |
| `test_lake_world.gd` | 22 checks passed, including basin bounds, bank shader mask, and water mesh checks. |
| `test_water_effects.gd` | 39 checks passed. |
| `test_water_director.gd` | 15 checks passed. |
| `test_water_checkpoint.gd` | 16 checks passed for paired Main checkpoint preflight, restore, pause, dry transition, and no duplicate splash. |
| `test_time_of_day_session.gd` | 9 checks passed, including a flyable interactive Main session under the production 240 Hz project setting. |
| `test_time_of_day_checkpoint.gd` | 48 checks passed. |
| `test_landscape_vegetation.gd` | 36 checks passed. The prior failure record is stale; this current snapshot measured 624,109 complete-scene triangles under the 650,000 ceiling. |

## Final native delivery

The downloaded plant library supplies three mature-tree silhouettes, smaller trees, green/red shrubs, three grass forms, fern, clover, two flower groups, corn, wheat and reeds. Production placement uses 17 imported mature trees, seven imported saplings, 221 habitat placements (including 56 bank plants and 84 crop plants), imported near grass and source-baked green hedges. Shared imported meshes/materials and Godot LODs preserve the authors' geometry. The previous procedural plant prototypes and 2,970 cushion-flower placements are retired. Original sources, licenses and conversion manifests remain under `assets/landscape/vegetation/source/`.

The irregular 20-vertex lake is centred at N=110 m, E=125 m. Continuous polygon-to-runway measurements give **82.152 m from runway edge to water** and **77.026 m to the outer bank**. Water is 0.45 m below the field; the deepest bed is 5.45 m below field level, giving **5 m water depth**. The 44,952-triangle basin/water geometry, scalar contacts, ground cutout and shoreline exclusions share one normalized definition. Nine bales were relocated through their placement generator; no bale remains in the bank footprint. See [siting measurements](native/siting-and-flight-cost.json).

Reviewed native views: [lake overview](native/lake_overview.png), [shore](native/lake_shore.png), [club](native/postcard_club.png), [trees](native/tree_detail.png), [shrubs](native/shrub_detail.png), [herbs/flowers](native/herb_border.png), [crops](native/crop_close.png), [hedges](native/hedge_detail.png), [corrected dusk](native/lake-dusk.png) and [night](native/lake-night.png). Night is intentionally dark away from the existing field lighting; this is not a claim of night-flight readability. The selected Quaternius family remains stylized rather than photographic. The diffuse-lit hedge material fixes an unshaded green glow found during dusk review.

### Actual water impact and audio

The native harness instantiates production Main/FlightSession at 240 Hz and advances the actual simulator from N=110/E=125/D=-2 m with 12 m/s downward body velocity. It does not manufacture an impact event. Water contact occurs at **tick 46**, N=110.25873056/E=125.00540010/D=0.441785315 m, using gear probe 2, at 11.0464 m/s normal speed and 5 m depth. Engine stop, one downloaded splash request, zero dry-crash voices, frozen effects/ambience during pause, advancing effects after resume and clear-on-reset all pass. [Raw report](native/water-entry-final.json), [before](native/water-before.png), [spray](native/water-plume.png), [ripples](native/water-ripples.png), [submersion](native/water-sink.png), [reset](native/water-reset.png).

Final 1920×1080 captures use a soft, perforated spray mask and an open plume base; a rejected solid-looking conical edge was removed after native review. The bounded pool remains one plume, 16 droplets and two rings. Effect time is pause/checkpoint controlled. Sinking is a 0.55 m render-only animation over 2.8 s; it is not a buoyancy or hydrodynamics model.

[Native WASAPI recording](native/water-entry.wav): 48 kHz stereo, 6.453 s, zero dropped frames, peak -7.86 dBFS and RMS -29.09 dBFS. This proves a non-clipping signal path and distinct downloaded water audio; independent human listening preference and calibrated lake acoustics remain unqualified. The ambience source is a river-wave recording, explicitly identified in its credits.

### Rendering and query cost

Windows native Godot 4.7.2, Compatibility/OpenGL 3.3, NVIDIA RTX 3090, driver 610.88. Each performance view uses 600 frames. Measurements are scene-render timings on this shared workstation, not a guarantee of full real-time flight cost on every device.

| Sample | Maximum frame p95 | Notes |
| --- | --- | --- |
| [1080p, ten views](native/qualified-1080.json) | 5.12 ms | At most 126 visible draws and 246,245 rendered primitives; before atlas reservation reduction |
| [720p, five views](native/qualified-720.json) | 5.27 ms | Same renderer and scene family; before atlas reservation reduction |
| [Final two-slot atlas, 1080p](native/bounded-reflections.json) | 4.69 ms | Club/pilot/lake overview/shore; 323.09 MiB reported video memory |
| [Lake disabled comparison](native/comparison-lake-off.json) | 5.07 ms | Largest paired lake-on p95 increase was 0.56 ms; 305.77 MiB video memory |

The 300-draw/1M-rendered-primitive/16.67 ms render gates pass on this GPU. The complete source-geometry ceiling is revised from 600k to **650k** after native measurement; current complete field is **624,109 triangles**, including source geometry before distance LOD. This preserves mixed downloaded tree silhouettes and the shoreline plants rather than destructively simplifying the sources. Habitat geometry is 83,650 triangles under its 90k allocation. This is a measured budget revision, not a claim of unchanged source cost.

Godot's default 64 reflection slots reserved unnecessary memory for one probe. Explicitly setting two slots reduced the measured lake-on total from 567.26 to 323.09 MiB; final lake-on/off difference is approximately **17.32 MiB**. See [ProjectSettings reflection atlas count](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-rendering-reflections-reflection-atlas-reflection-count). The single bounded probe captures static field geometry and refreshes on lighting changes, excluding the moving aircraft/effects. [ReflectionProbe update and masks](https://docs.godotengine.org/en/4.7/classes/class_reflectionprobe.html). Compatibility's reported shadow-draw counter was zero; it is retained as a backend observation, not a general shadow-cost conclusion.

Cold complete-field construction took 4.694 s in the final capture. The focused native scenery build passed at 534 ms; warm scenery-only samples were 166–179 ms. These scopes differ. There is no complete matching before/after vegetation baseline: the earlier working tree already contained some imported habitat work. Lake-on/off is the controlled incremental comparison.

The [retained paired airborne benchmark](native/airborne-cost.log) uses the full 4,980-proxy/1,038-bin scenery world, four warmup ticks and 20 measured precontact steps 10 m above the lake. Lake-off wall p50/p95 is 796/847 µs; lake-on 1,141/1,297 µs; paired median increment **330 µs** (7,147 µs total, 357.4 µs average). States are bit-identical. Conservative vertical rejection avoids unnecessary lake polygon sweeps during high flight. This small benchmark does not qualify worst-case near-water contacts. The earlier pre-optimization native descent cost retained in the siting report is historical; do not treat it as the final airborne measurement or claim the entire 240 Hz budget is proven.

### Final export and regression qualifications

After the spray-mask and airborne-query changes, the isolated app was exported again with native Windows Godot 4.7.2. Final PCK: **49,483,604 bytes**, SHA-256 `e0d2738c5e3d05fbe7b3d44049492078aaececc6c1fc61cc1d29a79ee95cb7a8`. The [empty-project verifier](native/verify_pack.gd) again passed **65/65** at production 240 Hz, including all 15 plants, all three audio streams, shaders and actual interactive Main flyability with matching lake identity. [Export log](native/export-check.log). Final water-effects source SHA-256: `d204e591fb4c131b5ebf22d0a08960dfbdb72ce15116db15bf01684da91acd01`. Earlier PCK hashes above identify the earlier snapshot, not this final artifact.

The final surface/collision/session/FX/director/checkpoint reruns pass 52/24/29/39/15/16 checks respectively; their logs are beside this report. The director and checkpoint harnesses emit two ObjectDB cleanup warnings on Dummy audio, so their zero assertion failures do not imply a leak-free backend audit. Native playback completed successfully. The 15th director assertion preserves an excavated bank impact's actual height; its first isolated rerun exposed a stale director copy, corrected by copying the already-fixed live source before rerunning.

The broader isolated verification loaded **613 GDScript resources with zero load failures**. The H6 transcendental guard and its injected-defect self-test passed after changing the new scalar lake logarithm to the existing `M.log_` boundary. The focused regression batch passed 23/25 scripts. One scenery-build assertion failed under WSL (the retained tail did not identify which assertion), and the legacy scenery-trace run timed out at 90 s; the native Windows scenery-build rerun passed ([log](native/scenery-build.log)), and the earlier native scenery trace passed. The complete canonical `app/test.sh` was not completed, so this report does not claim a fully green repository suite. Existing Linux atmosphere-trim and nearby scenery-query limitations retain their prior qualification.

The final native impact and pack use `.tools/water-flyability-verify-20261013/` with the final lake surface/collision, crash director, water effects and capture harness copied in. Concurrent aircraft/contact/workshop edits in the shared tree prevented a stable final live Main rerun: the first attempt caught an incomplete contact-history function, and the later attempt was refused by the aircraft model-bindings SHA-256 contract. Those unrelated edits were preserved. The isolated production Main passed; acceptance of the evolving shared aircraft work is separate.

### Reproduction

From a coherent checkout with Godot resources imported:

```powershell
python tools/landscape/vegetation/build_library.py --check
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/landscape/vegetation/bake_hedge_impostor.py -- --check
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --path app --rendering-driver opengl3 --audio-driver Dummy --script res://tests/capture_landscape_upgrade.gd -- --out=C:/tmp/lu-landscape --cases=postcard_club,pilot,lake_overview,lake_shore --frames=600 --width=1920 --height=1080 --scenery=on --scenery_birds=off
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --path app --rendering-driver opengl3 --audio-driver WASAPI --script res://tests/capture_lake_entry.gd -- --out=C:/tmp/lu-water-entry --width=1920 --height=1080 --scenery_birds=off
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --script res://tests/bench_lake_session_airborne.gd
```

Use `--lake=off` for the paired baseline; use `--date=2026-03-20 --time-of-day=18:20` for the dusk landscape capture. The library check verifies all 15 assets, 39 runtime files and three pinned archives. The Blender 5.2.2 check validates the downloaded-shrub impostor and source hash; it does not author plant geometry. [Evidence and source hashes](SHA256.json) identify the final retained artifacts.

Independent pilot aesthetic/readability review, human sound preference, lower-end hardware, worst-case combined flight timing and physically calibrated water response remain outside this software qualification.

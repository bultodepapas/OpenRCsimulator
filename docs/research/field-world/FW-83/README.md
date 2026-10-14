# FW-83 — world-anchored distant storm

2026-10-14 · Compatibility implementation and bounded native capture evidence · **Partial FW-83 delivery; flight and minimum-hardware qualification remain open.**

The [sky/cloud plan](../../../plans/sky-clouds-weather.md) owns FW-83 acceptance. Distant Storm now adds a world-anchored towering cloud formation and a distant rain curtain to the existing appearance selector. The original classic profile and flight physics are unchanged. This record retains the downloaded-source comparison, integration decisions and executable evidence; it does not close the plan's flight, tropical-band or performance gates.

## Runtime integration

[StormBank](../../../../app/render/weather/storm_bank.gd) belongs to each `World.build` scene, referenced weakly by its Environment. Its validated catalog descriptor specifies position, dimensions, rain opacity, layout version and the existing cloud layer used for advection. The current formation is about 10.9 km northwest of the field, with an authored base at 1,450 m and top at 6,200 m. These are scene estimates, not measured cloud dimensions.

Thirty depth-separated, yaw-billboard cloud lobes form the tower, broad upper cap and darker shelf. Three crossed rain sheets reuse the downloaded cloud alpha. Two shared cloud materials and one rain material bound resources; ordinary skies keep an empty hidden node and do not load the cloud textures. Configuration changes free the previous geometry. Layout variation uses a private seeded RNG, never flight or global RNG state.

The formation uses the accepted cloud transport phase: Still/calm holds its world position, and wind moves it in the same cardinal direction as the projected deck. The nearest periodic copy is selected around the actual scene camera. Moving the camera within a tile leaves the world centre unchanged; changing copies is permitted only beyond the 21 km far plane plus the validated full formation radius. This fixes an initial origin-centred wrap that could pop into view when the camera travelled far from the aerodrome. Phase rebasing and native checkpoint restoration reconstruct the same geometry and transport.

The cloud and rain shaders consume the sky's **raw scene-linear cloud/haze radiance**, shade and mix it in linear space, then use the existing `encode_for_engine` helper. Compatibility linearizes material ALBEDO and applies Environment exposure once. An initial CPU exposure multiplication made the moonlit bank clip white; the correction is covered by a day/night uniform-transfer test and native captures. The contract is verified against the pinned [GLES3 scene shader](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl) and the repository's existing color encoding include. The distance haze coefficient and vertical shading remain artistic approximations.

Cloud geometry depth-tests against opaque terrain and aircraft. A star MultiMesh sorts as one object at its origin, not at each distant star, so its scene-owned material receives priority −1 while a bank is visible; disabling the bank restores priority 0. This lets blended cloud alpha attenuate background stars without changing the classic path or foreground transparent-material priorities. Individual lobe AABBs include every yaw-billboard orientation.

Home and paused-flight controls, preferences and native visual checkpoint identity reuse the existing appearance contract. The distant-storm description and thumbnail describe the new rendered result. Catalog retunes are intentionally rejected by old native checkpoints whose frozen profile no longer matches; other profiles retain their identity. Selecting this card does not add rain forces, wet surfaces, physical wind, lightning, or thunder.

## Selected source

[WickedInsignia, “Clouds with Transparency”](https://opengameart.org/content/clouds-with-transparency) is an OpenGameArt texture pack published on 2022-02-17. The listing marks the pack CC0 and says it contains ten 2K cloud textures as alpha PNGs plus JPEGs with black backgrounds. The creator says the textures were made in Blender and released into the public domain under CC0. The ZIP contains the image files but no separate license document, so the primary listing and author statement are retained as the license evidence.

The downloaded source archive was `fx_cloudalphas.zip` (28,480,966 bytes), SHA-256 `83514A391C765819BC159B7F9AB61EC9F06C0CAA2B5865AF20A5BD3B2A14CCA4`. It is not vendored. Two original PNG members were selected after visual review:

| Runtime file | Source member | Image data | Size | SHA-256 |
| --- | --- | --- | ---: | --- |
| `app/assets/sky/weather/clouds/FX_CloudAlpha03.png` | `FX_CloudAlpha03.png` | 2048×2048, LA (luminance and alpha) | 2,017,932 bytes | `602A55F5E25E606999BFA218572A9703F54469ED1FE7C857C77E5038CC4681EE` |
| `app/assets/sky/weather/clouds/FX_CloudAlpha06.png` | `FX_CloudAlpha06.png` | 2048×2048, LA (luminance and alpha) | 2,059,759 bytes | `A1F05810C43D7811CB72F460595CC6E446E20FD4601342BA93D30045CB6095F1` |

Both runtime images are byte-identical to their archive members; no crop, color change, alpha edit, or other derivative was made. The asset provenance and runtime license notice are recorded in [source provenance](../../../../assets/sky/weather/PROVENANCE.md) and [the runtime notices](../../../../app/assets/sky/weather/LICENSES.md).

Visual review found `FX_CloudAlpha06` to have a vertically irregular mass, while `FX_CloudAlpha03` provides a more compact cumuliform shape. The runtime uses both original silhouettes in a depth-separated cluster. They are 2D images, not cloud volumes.

The engine imports both as lossless LA8 with a complete 11-level mip chain below the base level. Their measured pixel payload totals **22,369,620 bytes (21.33 MiB)**, within the 64 MiB incremental texture target; the two imported `.ctex` files total **4,675,272 bytes**. This is the imported image payload, not a whole-process VRAM measurement. [Import measurements and hashes](checks/asset-import.json) retain the exact format and byte counts. Mipmapped filtering is enabled, and automatic 3D recompression is disabled so the renderer does not silently substitute an unqualified format.

## POM Clouds candidate

The [POM Clouds addon](https://github.com/sanketsbrush/Godot-4.6-3D-POM-clouds-addon/tree/8701a9dda9fbeb7e86aeb95255138803a757de15) was reviewed at commit `8701a9dda9fbeb7e86aeb95255138803a757de15`. Its repository includes an MIT license, but no external cloud bitmap: the material embeds a Godot `FastNoiseLite` noise texture and gradient resources. `POM_Clouds.gd` builds a 20-layer `MultiMesh` from one plane and recenters its top-level node on the camera’s horizontal position each frame. The material’s default mesh scale is 100,000 m. That design and the upstream screenshots read as a broad overhead canopy, not a stationary, spatially bounded thunderhead, so it was rejected for this role.

The upstream README advertises Compatibility, Mobile, and Forward+ support. Its screenshots show Godot 4.6.2 and include Forward+ and Mobile editor modes. This intake did not run the addon in the pinned Godot 4.7.2 Compatibility/GLES3 project, consult Context7, or measure performance; the repository claim is not local qualification. The addon remains a possible reference for a separate full-sky treatment, not an adopted dependency.

## Native views and reproduction

The [capture manifest](captures/manifest.json) records 12 production `World.build` views: day, dusk and full moon, each from the pilot and a 500 m cross-track position at 50° and 25° FOV. They use Godot 4.7.2 Compatibility/OpenGL3, an NVIDIA RTX 3090, 1280×720 and 4× MSAA. Day uses the astronomical snapshot route at 2026-06-21 13:00 local; dusk uses the field-world clock at 18:25 that date; full moon uses 2026-06-29 00:00. All use 4.7° N, 74.1° W, UTC−5 and cloud seed 1253.

- [Day](captures/distant_storm-day-pilot-fov50.png): broad white upper mass, shaded base and distant shafts.
- [Dusk](captures/distant_storm-dusk-pilot-fov50.png): dark silhouette against the astronomical horizon.
- [Full moon](captures/distant_storm-fullmoon-pilot-fov50.png): dim moonlit cloud/haze and cloud attenuation of stars.

The harness looks at the formation target returned by the actual World, not a second hardcoded position. It forces eight draw frames after each view change and does not advance flight physics. The 500 m offset demonstrates parallax at two zoom levels; these stills are not a flown camera-turn or through-cloud acceptance test. The Distant Storm selector preview is a Godot Lanczos 384×216 downsample of the accepted day/pilot/50° frame; the other previews are unchanged.

Two additional production `app/main.gd` captures include the aircraft and HUD: [day](captures/main-day.png) and [full moon](captures/main-fullmoon.png). The fixed synthetic inspection places the aircraft at 80 m, camera azimuth 321°, elevation 19° and FOV 50°. Its small silhouette/light stays in front of the bank. This is the actual application route, but remains synthetic inspection rather than flown acceptance. Their JSON sidecars retain exact CLI arguments, image hashes, aircraft, camera and the scene-local bank snapshot. The logs record the aircraft inertia warning and two MP3 audio objects still referenced at shutdown; the verbose night log identifies `AudioStreamMP3`/`AudioStreamPlaybackMP3`. No whole-application shutdown or audio qualification is inferred.

From the repository root, use a fresh output directory and an absolute log path:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy --log-file C:/tmp/fw83-capture.log --script (Resolve-Path tools/atmosphere/storm_bank_capture.gd).Path -- --out=C:/tmp/fw83-captures --only=all --view=all
```

The [capture tool guide](../../../../tools/atmosphere/README.md#distant-storm-bank-views-fw-83) owns the arguments. Download/rejected-probe scratch files stay under ignored `.tools/`; only the selected original images, reproducible harness and accepted evidence are retained.

## Checks and limits

This section records the FW-83 snapshot. [FW-84b](../FW-84/README.md#fw-84b--integrated-electrical-bank-2026-10-14) subsequently added Electrical Storm bank/rain illumination and moonless-night captures; the original hashes and measurements below are retained.

The final focused run passes **244 checks across seven suites**, with no failed assertions or script errors:

| Suite | Checks | Evidence |
| --- | ---: | --- |
| Catalog and selection validation | 77 | [log](checks/test_sky_appearance_config.log) |
| Sky render/transport contract | 30 | [log](checks/test_sky_render.log) |
| Native visual checkpoints | 45 | [log](checks/test_sky_checkpoint.log) |
| Actual Home/paused-flight routes | 15 | [log](checks/test_sky_routes.log) |
| Astronomical stars | 22 | [log](checks/test_world_stars.log) |
| Retained world presentation context | 17 | [log](checks/test_world_presentation_context.log) |
| Storm-bank lifecycle/transport/lighting | 38 | [log](checks/test_storm_bank.log) |

These cover catalog bounds, seeded layout/global-RNG isolation, scene ownership, bounded reconfiguration, clear/restore, camera-independent world centres within a tile, cardinal advection, remote-camera periodic-copy selection, phase rebasing, exposure transfer, and star ordering. Actual Home/paused-flight route tests select the bank, remove it with Clear, restore its checkpoint, and compare full flight-state bytes. Run each suite with the pinned engine, `--headless --path app --audio-driver Dummy --script res://tests/<suite>.gd` and an absolute `--log-file`.

The fresh Windows PCK passes **35 resource checks**, including the two mipmapped LA8 cloud images, new shaders/script and CC0 notice. [Package result](checks/package-final-result.json) records the PCK hash and exact commands. This is **not a qualified release export**: the export plugin reports a missing `hx-700` aircraft-model manifest even though Godot writes the PCK and exits 0. The PCK-only probe also reports a missing ground-vehicle native extension; resource assertions still execute. The complete Windows build and Linux/macOS packaging remain separate gates.

This is a distant impostor formation, not a participating cloud volume. Transparent lobes can reveal sorting/plane artifacts during large viewpoint changes, especially from above the cap; close flight and overhead views are not qualified. Rain is a static distant veil transported with the cloud, with no local droplets, precipitation acoustics, runway wetting or aerodynamic effects. The formation does not cast its own spatial shadow, light reflections, or respond internally to electrical events; Electrical Storm still uses its existing separate projected-cloud presentation.

The local GPU was shared with other work, so these captures establish rendering/scene behavior, not the incremental GPU/first-use budget or minimum-hardware performance. Full pilot flight review, moonless-night/directional and above-cloud views, Windows/Linux/macOS release qualification, tropical bands and FW-84 thunderhead integration remain open. Physical spatial wind remains the M5-W05 prerequisite for FW-86–89; a decorative formation does not implement a tornado wind field.

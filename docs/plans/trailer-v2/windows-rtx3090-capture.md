# Trailer 2.0 — retained Windows / RTX 3090 capture study

**R5 priority:** [review the shooting script](cinematic-script-r5.md) and [shot plan](shot-plan-r5.json) before capture. The routes below retain prior production research; their equipment and render settings are proposals, not proof of R5 footage. The current [verification gates](verification-gates.md) supersede older shot-priority assumptions in this study.

**This file documents a future capture setup.** Initial offline shot-plan tools and the opt-in livery hold-last change are implemented and narrowly tested. No new RTX 3090 capture, graphics qualification or benchmark is claimed; additional capture adapters and footage remain pending.

## Reference machine, lock and output
- Target: owner's Windows PC, NVIDIA GeForce RTX 3090, qualified driver. Before filming log Windows version, driver number, GPU/CPU/RAM, monitor/window dimensions, source commit, clean profile, actual Godot executable hash and output storage.
- Engine in current source: official Godot 4.8-beta2. The previous trailer capture tools were documented on older 4.8-beta1 and need to be proven compatible with current main/release.
- First master capture qualification: **native 1920×1080, 60 fps, 16:9**, game audio at 48 kHz. Higher source capture 1440p or native 4K may be tested only after verifying shadows, bloom, reflections, UI, memory and film writer dimensions. Never upscale and label it native 4K.
- Maximum quality means **actual highest supported settings that remain visually stable in this build**, not simultaneously enabling unsupported techniques. A powerful GPU does not guarantee all features.

## Film setup matrix

| Category | Planned value | Practical risk / acceptance |
|---|---|---|
| Renderer | High / Forward+ / native Windows | Confirm actual method/driver; normal build may fall back to Standard/Compatibility. |
| Scene detail | Extreme, if offered on 3090 and qualified | Independent of High; document vegetation, bird, spectator and terrain quality. |
| Antialiasing / 3D reconstruction | First beauty pass Native plus highest practical MSAA | Compare FSR2 and optional NVIDIA DLSS/DLAA only when actual build supports them; reconstruction can blur tiny wing markings or reflections. |
| Shadows | Highest supported cascades, quality/softness/distance | High has 8192 shadow atlas and sun-angle PCSS per project guide; watch near-water shimmering. |
| Sky and clouds | Max supported quality and explicit sky/time presets | Sun/sky must retain actual detail, no inaccurate day-to-night physics transition. |
| Lake | Explicit optional planar mirror on lake shots | Not default High; [adapter](../../../app/render/lake/lake_planar_reflection.gd) gates by High + environmental variable OPENRC_LAKE_REFLECTIONS=planar. |
| Night VFX | Strongest supported per-aircraft RGB/smoke/landing lights | Lights must be visible AND airplane silhouette legible, with no invented smoke outlet. |
| Lens effects | Ultra on impact/rain shots if source route accepts | Independent impact style Curtain/Splatter/Off; camera/touch event determines actual result. |
| HUD | Mostly clean; occasional real instruments/controller overlay | UI must be genuine and unclipped; never fake gameplay FPS. |
| Bloom, SSAO, clouds, foliage | Highest available supported | High does **not** automatically enable SSR, GI, volumetric fog or motion blur. Do not claim those unsupported effects. |

Sources: [OpenRC graphics modes and availability](../../../tools/graphics/README.md), [High profile](../../../app/render/high_graphics_profile.gd), [Godot renderer guide](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html). NVIDIA DLSS/DLAA/Reflex are tied to a distinct Windows NVIDIA engine fork/package; stock official engine does not expose working modes simply because GPU is a 3090.

## Lake-specific High experiment

Historical [VQ-07 planar lake investigation](../../research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/README.md) tested **Vantage Jet** on Windows RTX3090 in 2026-10-22 and obtained a moving reflection; its production result was **default-off experimental High**. The reflection viewport uses 0.5 scale and a 1280×720 maximum. It was not a Corsair flight validation, nor a 60fps gameplay performance report.

Planned PowerShell preflight setup (illustrative, not executed here):

    $env:OPENRC_LAKE_REFLECTIONS = 'planar'
    # Start the approved Windows High/Forward+ build and capture the identical Corsair path.
    # Log effective renderer, lighting, skin and reflection states.
    Remove-Item Env:OPENRC_LAKE_REFLECTIONS

For R5, the essential mirror test uses `three_tone`, the final orbit skin, through the six-second shoreline approach, water crossing and exit: compare flag off/on and the actual moving Corsair. The proposed over-water interval is about 3.225 seconds at the nominal 23 m/s, not the whole six seconds. Additional skin passes are optional coverage, not a requirement to switch paint over the lake. Check reflection geometry, movement, colors, clipping at frame edges and shore; don't assume an environmental/static cubemap proves plane reflection. If the Corsair reflection doesn't qualify, retain a genuine unmirrored Corsair pass; a documented Vantage reflection can be shown only as a separately identified alternate.

## Lens options and precisely what generates them

Source [lens_settings.gd](../../../app/render/lens/lens_settings.gd) implements off/auto/low/medium/high/ultra for lens quality; impact style off/curtain/splatter; impact color red/dark/desaturated; separate rain, glasses, grime and center choices. Normal interactive flight enables default lens behavior. **Scripted/trailer capture routes default lens stack off** unless explicitly overridden; filming code must forward settings and prove actual contact. Future CLI arguments after app argument separator can include:
- --lens-effects=ultra
- --impact-fx=curtain
- --impact-colour=red
- --lens-grime=on
- --lens-rain=on

Blood/splatter requires actual person/pilot collision; terrain crash causes grime, not blood. Camera-lens crack requires eligible closeup/FPV contact at sufficiently high speed (code threshold about 12 m/s), not any impact. Rain is a lens film visual, not changed aerodynamic drag. Verify at 60fps native and offer a no-blood version.

## Genuine time and weather shot schedule
| Set | Site | Time/sky | Conditions | Needed review |
|---|---|---|---|---|
| Corsair lake hero | Club lake | warm morning / soft golden hour, fair/broken cloud | calm | moving mirrored Corsair and livery colors |
| Fast fleet | Club and Green paradise | bright morning and midday | mostly calm | diversity of camera/background |
| Extra + Stik day-night | Club | afternoon, gold, blue hour, Moonrise/night | calm | body + RGB both visible |
| RC trucks | RC dirt circuit | sunny with dusk/neon alternative | dry for dust; actual water/mud only if surface supports | nitro exhaust/neon, tires and landing |
| Scale | Club field / recognizable landmarks | neutral midday | calm | Real giant and tiny trials use different framing, with a closer tiny view; the disclosed cinematic trio supplies the same-depth comparison. |
| FPV | eligible gate course | full daytime | course-preserving weather | gate crossing, actual timer |
| Creator trial | Creator-supported session | bright daytime | calm | preview clearly becomes an eligible test flight |
| Camera effects | proper collision world | readable soft light | set for actual trigger | dust/crack and optional person-impact curtain |

## Capture lanes and evidence

**Lane 1 — existing Godot cinema tools:** [tools/trailer/README.md](../../../tools/trailer/README.md) includes flight director, cars, Corsair deck, formation, night lighting and renderer caveats. R5 adds an opt-in hold-last schedule; the focused schedule test does not prove source-frame alignment or actual GLB appearance. Re-qualify against the pinned engine; do not assume old 4.8-beta1 scripts produce correctly measured beta2 High footage. Movie Maker with --fixed-fps 60 and --write-movie captures offline deterministic frames and synchronized audio when configured; actual dimensions must be ready before the film writer initializes. Track output manifest and screen format. Captured 60fps is not proof that the game ran 60fps in real time.

**Lane 2 — manual gameplay/UI:** use a verified Windows capture route for FPV racing, variable car behavior and Creator menus where capture directors cannot supply controls; OBS is one option to qualify. Record controller input and avoid dropped/duplicate frames.

**Lane 3 — A/B beauty tests:** identical plane/lighting on High Native with and without planar; one Extreme scene detail variant; optional DLSS/FSR *only if actually functional*. Compare original pixels, not just edited grade; check micro-stutter, exposure, true water reflection, small wing text, night luminance, motion and audio.

## Future per-take receipt
Each shot ID must record commit/build and SHA, GPU/driver, Godot method/driver, resolution and actual fps, vehicle/skin/model import rights, landscape, sun/date/time, weather/wind, graphics knobs, lake flag, lens settings, camera location/FOV, input/flight director, crash/contact identity, per-frame tick validity, source media/hash, audio identity, acceptance/rejection and quality reviewer.

## Final film acceptance / distribution
- Source frames: 1080p60 native with documented higher-resolution variant only when truly recorded. Transcode main MP4 to H.264/AAC stereo per [Steamworks recommended trailer upload](https://partner.steamgames.com/doc/store/trailer); YouTube and socials may have different output needs.
- Verify full decode, exactly expected frames and duration, smooth aircraft/rotor/tire motion, HDR-to-sRGB correctness, no startup frames, audio level and true peak, correct localizations and rights.
- For audio and camera work, existing tools provide **real simulator capture**, not a finished user-facing replay editor. Film source and music should live outside Git pending an authorized deliverable upload and license process.

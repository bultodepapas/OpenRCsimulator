# Trailer 2.0 — retained Windows / RTX 3090 capture study

**R7 priority:** review the [shooting script](cinematic-script-r7.md), [shot plan](shot-plan-r7.json) and [direction guide](direction-and-continuity.md) before capture. The routes below retain prior production research; their equipment and render settings are proposals, not proof of R7 footage. The current [verification gates](verification-gates.md) supersede older shot-priority assumptions in this study.

**This file documents a future capture setup.** Initial offline shot-plan tools and the opt-in livery hold-last have historical focused software evidence. No R7 RTX 3090 capture, graphics qualification, benchmark or completed film is claimed; the revised camera and actual footage remain to be checked on the capture route.

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
| Lake | Explicit optional planar mirror on lake shots | Requires active High, non-headless Forward+ and `OPENRC_LAKE_REFLECTIONS=planar`; visibility, projection and camera-height gates also apply. |
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

For R7, compare the actual moving Corsair with planar off/on through the **115–121 s** shoreline approach, crossing and exit, using `three_tone`, the final skin of the **105–115 s** orbit. The `parallel_east` eye holds N145, D−1 and actual CG east minus 8 m; nominal eyes are (145, 47, −1), (145, 116, −1) and (145, 185, −1). It aims at the actual CG's north/east projected onto mean water D+0.45 m, with **34° vertical FOV** (`KEEP_HEIGHT`), so the plane is above the waterline aim. The eastbound nose reads screen-left; the shoreline moves. The manifest records the actual presented CG separately from this aim, plus eye, orientation, lens and application frame/tick. None of this flies the proposed path or establishes a reflection.

The planned over-water interval is about 3.225 seconds at nominal 23 m/s, not the whole six seconds; the actual path, speed, clearance, eye and reflection remain unqualified. The default probe excludes the moving aircraft, so a static environmental cubemap cannot establish its mirror. Inspect actual reflection geometry, movement, colors, clipping and shore. Preserve a genuine unmirrored Corsair pass if the moving reflection fails; any documented Vantage result remains a separately identified historical alternate.

## Lens options and precisely what generates them

Source [lens_settings.gd](../../../app/render/lens/lens_settings.gd) implements off/auto/low/medium/high/ultra for lens quality; impact style off/curtain/splatter; impact color red/dark/desaturated; separate rain, glasses, grime and center choices. Normal interactive flight enables default lens behavior. **Scripted/trailer capture routes default lens stack off** unless explicitly overridden; filming code must forward settings and prove actual contact. Future CLI arguments after app argument separator can include:
- --lens-effects=ultra
- --impact-fx=curtain
- --impact-colour=red
- --lens-grime=on
- --lens-rain=on

Blood/splatter requires actual person/pilot collision; terrain crash causes grime, not blood. Camera-lens crack requires eligible closeup/FPV contact at sufficiently high speed (code threshold about 12 m/s), not any impact. Rain is a lens film visual, not changed aerodynamic drag. Verify at 60fps native and offer a no-blood version.

## Genuine time and weather shot schedule

These are distinct prepared sessions, not a continuous simulated day. For named field-world presets use
`--time= --time_of_day=<preset> --time_scale=0 --sky=<preset>` on a route that accepts those settings.
The blank `--time=` suppresses inherited `OPENRC_TIME`, which otherwise overrides even a named preset.
For calibrated fixed Day use `--time= --time_of_day= --time_scale=0 --sky=clear` in a fresh direct
session with empty `session_preset` and legacy lighting. The blank time-of-day value suppresses inherited
`OPENRC_TIME_OF_DAY`; `--time_of_day=day` is not a field-world preset. These use the underscore interface,
not the separate `--time-of-day` lighting API.

Clear `OPENRC_DATE`, `OPENRC_LAT`, `OPENRC_LON` and `OPENRC_UTC_OFFSET` for the source reference, or
deliberately set and record alternatives. Record the actual resolved preset, date/place, local hour and time
scale; night searches forward for its moon view. Match date/place/sky for the orbit and lake, and retain
actual moon configuration, cloud/wind settings, renderer and view exposure. Freezing solar time does not
freeze camera-dependent exposure. Options are route-specific: the fixed-wing harness accepts `--sky=clear`,
while the vehicle harness does not automatically forward every sky setting. Confirm readback for each take.

| Set | Site | Time/sky | Conditions | Needed review |
|---|---|---|---|---|
| Opening aircraft | Club field | `morning`, rising apparent sun +25°; clear | calm | Flight, skin and camera readability. |
| Monster Car 2 jump | Club field | `morning`; clear | calm | R4-02's planned 42° view needs a qualified manual or adapted route. The existing jump harness rejects time/sky arguments, uses classic sky and a 46° orbit. |
| Mechanisms, FPV and scale | Club field / course | calibrated fixed Day | calm, except documented ground breeze | Real mechanisms and gate crossing; the proposed close tiny camera needs a separate trial-capable route, and the simultaneous trio is disclosed as cinematic. |
| Extra smoke | Club field | `afternoon`, setting +35° | calm | Admitted stock smoke, body and climb remain readable. |
| Corsair orbit and lake | Club lake | same `golden_hour`, setting +6°; clear | calm | Match livery, date/place/sky and actual exposure; check the real moving reflection. |
| Bisonte shore | Club lake | `sunset`, setting +0.5°; clear | calm | Five-second shallow approach/stop and real water contact; use the documented golden alternate if unreadable. |
| Creator | Creator-supported session | native UI, followed by the actual eligible flight setting | actual source | Preview becomes an eligible trial only when its real route qualifies. |
| Turbo Lumber | Club field | `night`, nearly full moon; `blue_hour` alternate | calm | Actual admitted Night Radian lights and readable body; record selected moon/date. |
| Optional lens effects | proper collision world | readable soft light | actual trigger | Dust/crack and any person-impact curtain must come from eligible real events. |

## Capture lanes and evidence

**Lane 1 — existing Godot cinema tools:** [tools/trailer/README.md](../../../tools/trailer/README.md) includes flight director, cars, Corsair deck, formation, night lighting and renderer caveats. R5 added an opt-in hold-last schedule; its focused schedule test does not prove source-frame alignment or actual GLB appearance. The R7 camera-only adapter composes at priority 20 after the existing director at 10; it records the actual CG and its independent aim and checks frame/tick freshness. It cannot select the skin, spawn or fly the aircraft, and its capture route still needs qualification. R4-37's proposed tiny-trial eye is N28.5, D−1.2, actual CG east minus 1 m, with 24° vertical FOV. A 10% Workshop trial uses a `workshop-<hash>` runtime model ID, whereas the camera-recipe guard requires the stock ID; a separate qualified route is needed to combine them. The existing Bisonte vehicle harness is a four-second chase/input reference, not the five-second shore scene. The strict Monster Car 2 jump harness does not accept the field-world time/sky arguments above; its earlier jump footage proves only its original settings. Re-qualify against the pinned engine; do not assume old 4.8-beta1 scripts produce correctly measured beta2 High footage. Movie Maker with --fixed-fps 60 and --write-movie captures offline deterministic frames and synchronized audio when configured; actual dimensions must be ready before the film writer initializes. Track output manifest and screen format. Captured 60fps is not proof that the game ran 60fps in real time.

**Lane 2 — manual gameplay/UI:** use a verified Windows capture route for FPV racing, variable car behavior and Creator menus where capture directors cannot supply controls; OBS is one option to qualify. Record controller input and avoid dropped/duplicate frames.

**Lane 3 — A/B beauty tests:** identical plane/lighting on High Native with and without planar; one Extreme scene detail variant; optional DLSS/FSR *only if actually functional*. Compare original pixels, not just edited grade; check micro-stutter, exposure, true water reflection, small wing text, night luminance, motion and audio.

## Future per-take receipt
Each shot ID must record commit/build and SHA, GPU/driver, Godot method/driver, resolution and actual fps, vehicle/skin/model import rights, landscape, sun/date/time and displayed moon, sky/seed/weather/wind, actual exposure, graphics knobs, lake flag, lens settings, actual CG and camera eye/aim/vertical FOV, input/flight director, crash/contact identity, per-frame engine and simulation-tick validity, source media/hash, audio identity, acceptance/rejection and quality reviewer.

## Final film acceptance / distribution
- Source frames: 1080p60 native with documented higher-resolution variant only when truly recorded. Transcode main MP4 to H.264/AAC stereo per [Steamworks recommended trailer upload](https://partner.steamgames.com/doc/store/trailer); YouTube and socials may have different output needs.
- Verify full decode, exactly expected frames and duration, smooth aircraft/rotor/tire motion, HDR-to-sRGB correctness, no startup frames, audio level and true peak, correct localizations and rights.
- For audio and camera work, existing tools provide **real simulator capture**, not a finished user-facing replay editor. Film source and music should live outside Git pending an authorized deliverable upload and license process.

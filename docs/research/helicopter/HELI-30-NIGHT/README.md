# HELI-30 — RC helicopter night kit

2026-10-14. Presentation implementation for the playable X-Cell reference/HX-700 visual surrogate. [Current controls](../../../HELICOPTER.md#night-flight) are authoritative; this report records evidence and limits. No physics parameters, generated model assets or flight golden traces changed for this work.

## Reference investigation

- [Blade 230 S complete night kit](https://www.horizonhobby.com/product/complete-night-light-kit-upgrade-230-s/BLH1554.html): frame/tail-fin LEDs and illuminated main blades are an actual RC installation pattern. The frame uses the flight pack and the blades use separate removable 1S batteries. This supports a visible airframe and lit stopped blades; it does not identify this aircraft's electrical load or lamp output.
- [Night Magic instructions, v2.1](https://www.nightmagicblades.com/download/nmb/nmbmanualv2.1.pdf) and [programmable upper/lower RGB blades](https://www.nightmagicblades.com/?product=nmb26led325rgb): independent blade-side colors and rotating LED patterns provide an attitude cue. Our amber upper/blue-cyan lower palette is an authored choice, not a copy of a measured installation.
- [FAA Helicopter Flying Handbook](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/helicopter_flying_handbook), chapter 12: the red-left, green-right, white-aft orientation convention. This RC implementation does not claim regulatory angular coverage or certified intensities.
- [Godot 4.7 rendering architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html), [spatial shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html) and [environment/post-processing](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html): reuse the project's Compatibility exposure encoding and additive lights. A real SpotLight3D illuminates the ground; an emissive ribbon alone does not do that. Local rotor halos use the same draw rather than changing world glow.

Product photographs of the Night 230 S and its frame/fin LED modules were inspected during the investigation. They were not copied into runtime assets or redistributed here. The supplied HX-700 mesh, existing light-sprite/LED-strip shaders and existing world remain the asset sources.

## Implemented behavior and estimates

The scene-local kit owns ten surface ribbons, five light sprites, four rotor ribbon meshes, one unshadowed landing spotlight and one bounded local spill light. Canopy ribbons come from triangle cross-sections; rotor phase and upper/lower skin clearance come from authored blade vertices. Mount transforms preserve runtime radius and cyclic tilt. The kit remains outside the original blade visibility hierarchy, so normal rotor blur cannot hide the LEDs.

Automatic intensity transitions smoothly between solar elevations +3° and −4°. The fixed astronomical path reads geometric solar elevation, not its clamped rendering sun elevation. Explicit all/navigation/off modes work through L, the controller action and `--heli-lights`. The armed red beacon uses the accepted simulation clock (1 s period, 78.125 ms pulse); no shader uses wall-clock `TIME`. Lights do not require an armed motor.

Two LED stations per blade lie at 0.66r and 0.93r. A fixed 1/60 s shutter integrates signed shaft speed/phase into discrete stopped LEDs, short spool arcs and long running arcs. Both opposite blades and complete revolutions contribute to the exposure. Upper/lower colors are gated by view side. Minimum projected widths preserve visibility while reducing radiance for enlargement. A soft radial halo is contained in the rotor draw. It is an appearance approximation, not a camera/retinal response calibration.

The model has no measured photometry. LED colors, 6–12 mm body strip widths, 8 mm rotor LED width, 1.5 mm blade-skin clearance, screen-size floors, display caps and light spill are estimates. The landing cone points 40° downward, has 32° half-angle and 12 m range. Its energy is capped by exposure; it is a nearby-ground cue, not a searchlight. A rotor-only gain `max(1, 60 / exposure)` maintains readability in the fixed SDR path (exposure 0.6), under the same display cap. This does not brighten the environment.

## Visual evidence

Godot 4.7.2, native Windows Compatibility/OpenGL 3.3, NVIDIA RTX 3090, driver 610.88, 1280×720. Images are actual engine renders. The field, moon, ambient lighting and exposure policy are unchanged.

| Capture | What was inspected |
| --- | --- |
| [Ground, pilot](pilot-ground.png) / [hover, pilot](pilot-airborne.png) | Actual production flight route, authored pad and solved practice-hover start. |
| [Close ground](close-ground.png) / [slow spool](slow-spool.png) | Body outline, ground light, stopped points and finite arcs. |
| [Upper rotor](upper-hover.png) / [lower rotor](lower-hover.png) | Amber versus blue-cyan attitude cue, separate tail rotor, depth occlusion. |
| [Navigation](navigation.png) / [off](lights-off.png) | Mode separation without changing sky or field lighting. |
| [Home](home-night.png) / [fixed night Home](fixed-0.png) / [day Home](fixed-12.png) | Shared kit, still preview, automatic daylight off. |
| [Fixed astronomical hover](fixed/close-hover.png) | Blade arcs remain visible under fixed SDR exposure. |
| [50 m](distance-50m.png) / [100 m](distance-100m.png) | Wide-view limits: lights remain detectable, but at 100 m the airframe is too small for reliable attitude reading without pilot zoom. |

Close/upper/lower/distance fixtures set presentation poses and rotor telemetry directly; they are not simulated maneuvers or flight validation. The fixture's camera views are inspection views, not proof of a clear flyable route around its visible fence. The previous unlit pad capture remains in HELI-20 as historical evidence.

Reproduce the presentation matrix from the repository root (native window needed):

```powershell
$NightCapture = (Resolve-Path research/helicopter/night_lights/capture.gd).Path
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --resolution 1280x720 --script $NightCapture -- --time_of_day=night --out-dir=C:/captures/heli-night
# Fixed astronomical SDR matrix:
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --resolution 1280x720 --script $NightCapture -- --fixed-night --out-dir=C:/captures/heli-fixed
# Production route; substitute airborne for the practice-hover image:
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --resolution 1280x720 -- --aircraft=xcell-60-research --capture --start=ground --t=0 --view=pilot --time_of_day=night --field-lighting=airfield --out=C:/captures/heli-pad.png
```

## Verification and cost

[Logs](checks/) retain nine passing focused suites: kit and rotor checks, existing visual/render audits, control dispatch/reference checks, Home/cache checks and bilingual Help. The new tests exercise real-model skin clearance, mode cycling via keyboard/controller, isolated materials, daylight off, fixed-time elevation, exposure caps, directional ground illumination, retained Home selection, phase holds and unchanged input telemetry/body pose. Eight touched GDScripts parse without engine errors; native captures compile the shaders. The [manifest](manifest.json) records source and image hashes for 23 captures. The full application test suite and export matrix were not run for this presentation patch.

The focused kit test passes 27 checks; the rotor test passes 18. Existing helicopter visual and render audits pass 25 and 32 checks. Home/cache assertions pass; those broader tests report ObjectDB cleanup warnings, retained in their logs. The isolated kit test exits without such warnings. Help was also adjusted to fit the expanded shared English/Spanish controls within 704 px including padding at 720p; a missing flight-log shortcut translation surfaced during that shared check and was supplied.

The kit adds 1,178 triangles in at most 19 mesh submissions, plus two unshadowed local lights; each rotor is 512 triangles. The final headless 1,000-update sample was about 19 µs per presentation update on this host (other verification was running). This is a small CPU scope observation, not a controlled benchmark, GPU frame-rate or input-latency guarantee. No per-frame geometry generation, image downloads, simulation integration or physics loads are added.

Remaining acceptance: other GPUs/platforms, smaller displays, human pilot orientation review, and physical lamp/aircraft calibration. Software and appearance verification do not qualify the HX-700 flight model or real-world night flying.

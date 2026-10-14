# FW-84 electrical storm components

Evidence for the first electrical-storm slice (2026-10-13) and its integrated cloud-bank follow-up (2026-10-14). FW-84 remains open: neither record establishes the full flown night gate, final sound selection, or performance budget.

## FW-84b — integrated electrical bank (2026-10-14)

Electrical Storm now uses the FW-83 world-anchored formation and its two unchanged downloaded CC0 masks: 30 cloud lobes and three rain sheets. The electrical profile spans 8.2 × 4.5 km, from 1.25 to 7 km altitude, northwest of the field. It is an authored distant impostor, not a meteorological volume. The profile's transport scale is 1,000 m to keep its periodic copies outside the accepted view range. This catalog retune intentionally invalidates older native checkpoints containing the former Electrical Storm profile; the stable preference ID and Classic defaults are unchanged.

`storm_cell.gd` shares bank placement and periodic-copy math between rendering and the deterministic scheduler. Contextual events evaluate the accepted float64 cloud transport at emission time. Existing event IDs, pulse schedules and random draw order remain unchanged; missing context keeps the legacy event contract. `main.gd` binds the scene's bank through a weak reference and supplies accepted transport. The bank copy is synchronized after the camera update. Lightning retains only the active emitted event's placement through subsequent pulses and camera cuts; queued thunder keeps its original channel, with inaudible arrivals pruned by the existing bounded audio consumer.

The bank shader adds a blue-white, Gaussian-weighted contribution inside the downloaded cloud mask, with a smaller contribution in rain. Alpha is unchanged, so a pulse cannot fill cloud gaps. Full uses the branched channel and existing capped, shadowless directional light; Reduced keeps 18% of the cloud/rain pulse without the channel or landscape light; Off clears transient illumination. Pause, backward seek, reconfiguration, reset, rebinding and scene exit clear the old bank pulse. Two simultaneous Worlds retain separate material state. The projected cloud-flash deck remains a fallback for the component without valid bank context.

**Exposure correction:** the first-slice inference that additive unshaded VFX bypassed the accepted exposure was wrong. In pinned Godot 4.7.2 GLES3, the [scene shader](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl#L2548) uses ALBEDO in the unshaded branch, ignores EMISSION, and then applies Environment exposure. The [renderer](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp#L2273) supplies that exposure to transparent rendering too; additive blending does not bypass it. Bounded transient material contributions now use `encode_for_engine(linear_cap / exposure)`, with the existing exact engine inverse. The earlier direct division of encoded color caused the disappearing bolt. World exposure, shared Sky uniforms and atmospheric time remain untouched. Ribbon widths are apparent-bloom art controls, not physical channel diameters.

### Native matrix

The [manifest](captures/fw84b/manifest.json) records 16 native Compatibility frames on Godot 4.7.2 / RTX 3090, 1280×720, 4× MSAA, Dummy audio. Each lighting case uses the production default field, actual `World.build`, Still transport, pilot camera at 50° FOV, field lamps/fire off, seed 1253, and cloud-to-ground event `3102985321:7` (start 88.8666667 s). Samples are −0.05 s, +0.0375 s and +1 s from onset. Both night cases also capture Reduced and Off at the same peak. No aircraft or physics advances in this harness.

| Lighting at 4.7° N, 74.1° W, UTC−5 | Actual exposure | Peak frame |
| --- | ---: | --- |
| 2026-06-21 13:00 | 0.6000 | [Day](captures/fw84b/electrical_storm-day-peak-full.png) |
| 2026-06-21 18:25 | 41.3285 | [Dusk](captures/fw84b/electrical_storm-dusk-peak-full.png) |
| 2026-06-29 00:00; moon +55.60°, 99.3% illuminated | 39607.5820 | [Full moon](captures/fw84b/electrical_storm-fullmoon-peak-full.png) |
| 2026-06-15 00:00 | 90000.0 | [Moonless night](captures/fw84b/electrical_storm-newmoon-peak-full.png) |

The [pixel comparisons](captures/fw84b/metrics.json) verify all 16 image hashes, constant exposure within each lighting case, zero pre/post/Off bank and scene-light contribution, and unchanged upper sky pixels outside the bank. Mean displayed luminance in the fixed cloud ROI is Full/Reduced/Off **32.277 / 15.001 / 8.027** with the full moon and **27.424 / 7.788 / 0.022** without it (8-bit sRGB-weighted values, not physical luminance). Pre/post images are pixel-identical at dusk and in both night cases; day differs by at most one channel code. These measurements establish this camera's pulse localization and return to baseline, not all-view occlusion or pilot readability. [Capture log](checks/fw84b-capture-matrix.log); [reproduction tool](../../../../tools/atmosphere/README.md#electrical-bank-pulses-fw-84b).

Three additional captures use the actual `app/main.gd` route with the aircraft at a fixed 80 m inspection distance, 321° azimuth, 19° elevation and simulation time 88.9 s: [day](captures/fw84b-main-day.png), [full moon](captures/fw84b-main-fullmoon.png) and [moonless night](captures/fw84b-main-newmoon.png). Their adjacent JSON sidecars preserve exact CLI arguments, PNG hashes, World lighting, bank and Lightning state. The airplane remains a small central silhouette/light against the lit formation; these are synthetic inspection frames, not a flown circuit. Logs retain the existing aircraft inertia warning; day and moonless captures also report two referenced objects at shutdown, so no whole-application shutdown qualification is inferred. The selector's Electrical Storm preview is a 384×216 Godot Lanczos downsample of the accepted full-moon peak, with provenance in the matrix metrics.

### Focused software checks

**278 assertions pass across eight suites**, including event transport/placement, mode-independent scheduling, lifecycle, independent Worlds, the 100 m camera cut retaining queued thunder and a 100 km cut pruning inaudible arrivals without retargeting the active channel.

| Suite | Passed | Log |
| --- | ---: | --- |
| Sky appearance validation | 77 | [result](checks/fw84b-test_sky_appearance_config.log) |
| Sky render/transport | 30 | [result](checks/fw84b-test_sky_render.log) |
| Sky checkpoints | 45 | [result](checks/fw84b-test_sky_checkpoint.log) |
| Home/paused-flight sky routes | 15 | [result](checks/fw84b-test_sky_routes.log) |
| Storm-bank lifecycle | 38 | [result](checks/fw84b-test_storm_bank.log) |
| Storm events | 22 | [result](checks/fw84b-test_storm_events.log) |
| Storm-cell contract | 19 | [result](checks/fw84b-test_storm_cell.log) |
| Integrated electrical bank | 32 | [result](checks/fw84b-test_electrical_bank.log) |

Run each with the pinned engine, `--headless --path app --audio-driver Dummy --script res://tests/<suite>.gd` and an absolute log path. The native capture compiles the actual material shaders; headless assertions alone do not verify pixels.

A fresh 2 s Classic/Electrical pair produces identical headers and all **481 numerical flight rows** at 240 Hz, excluding comment metadata. Both use the same default flight state and disabled soundscape. [Parity result](checks/fw84b-trace-parity.json), [Classic log](checks/fw84b-trace-classic.log), [Electrical log](checks/fw84b-trace-electrical.log). Use the pinned headless engine with `-- --trace=<absolute CSV> --t=2 --soundscape=off --sky=classic`, then repeat with `--sky=electrical_storm` and separate output/log paths. This is exact software parity for that case, not physical storm validation.

The freshly written Windows PCK passes **38 weather resource checks**, including the storm-cell script, integrated consumer, bolt shader, cloud images, preview and notices. [Package result](checks/fw84b-package-result.json), [resource log](checks/fw84b-package-probe.log). This is not a qualified release export: the [export log](checks/fw84b-package-export.log) reports a SHA-256 mismatch for `assets/aircraft/turbo-lumber-evolution/mesh-measurements.json` in the concurrently modified aircraft track, despite writing a PCK and exiting 0. The isolated PCK-only invocation also reports the absent ground-vehicle native extension before the weather assertions; that diagnostic is recorded in the package result. Neither unrelated issue was bypassed or repaired by weather work.

[Source snapshot and image verification](checks/fw84b-source-and-evidence.json) record the final weather source hashes and the three Main-sidecar image checks. The whole application test suite and cross-platform release builds were not rerun for this increment.

### Remaining qualification

The formation is a distant transparent impostor; close/overhead traversal, large camera rotations and sorting artifacts remain unqualified. Cloud/rain illumination is local, but Full's directional scene light is global and shadowless: terrain can receive light without physical occlusion. Reflections do not receive transient flashes. First-strike mesh construction, peak GPU cost and minimum-hardware budgets are unmeasured because this GPU is shared with other work. Mast/lake overlap, complete bright/dark-aircraft night circuits, audio audition/mixing and native OS release gates remain open. Spatial wind, tropical bands and tornado mechanics are separate, still-unimplemented phases.

## First-slice record (2026-10-13)

The remaining sections retain the original evidence and hashes. The fixed-cap unshaded-shader interpretation in this historical record is superseded by FW-84b's correction above, and Electrical Storm now uses the integrated bank when valid context is available.

## Runtime pieces

- `app/environment/storm_events.gd` provides a deterministic, versioned presentation schedule. Event identity derives from the visual seed and fixed 12-second schedule slot. Each slot uses a private seeded RNG stream, so querying other slots or changing render cadence cannot consume a shared stream. The schedule is disabled unless `preset` is `electrical_storm`; Full/Reduced/Off is not an input to event generation.
- Events carry a stable ID, appearance generation, start tick and time, kind, geometry seed, float64 render-world source/channel anchors, pulse envelope, intensity and thunder asset ID. Query work is capped at 64 recent schedule slots so a seek cannot replay unbounded history.
- `app/render/weather/lightning.gd` consumes simulation time and a scene camera position. It pools one shadowless `DirectionalLight3D` with `SKY_MODE_LIGHT_ONLY`, a local cloud-deck overlay, and two ribbon mesh instances for the halo and core. The transient scene light is inverse-capped against accepted exposure; unshaded shader color and emission use fixed display caps because their output does not scale like lit surfaces. The world exposure, solar light, physics state, and shared Sky uniforms remain untouched.
- `app/render/weather/cloud_flash.gdshader` includes the existing `cloud_field.gdshaderinc` and uses the same ray-to-deck projection as the sky's layered cloud mask. `Lightning.set_cloud_state()` applies the profile's effective coverage (`clamp(layer.coverage + (cloud_cover - 0.5) * 0.5, 0, 1)`) and optical opacity (`layer.density * cloud_density`) once before passing them to the local deck shader. Macro tone modulation only affects color. The overlay is local scene geometry at the selected storm deck altitude, with a 4.2 km horizontal Gaussian e-fold radius around the storm source; cloud gaps and distant sky remain unlit. Sky cubemap/radiance state is untouched.
- Full shows cloud pulses, occasional seeded branched channels and the brief directional scene light. Reduced keeps dim cloud-local pulses and suppresses channel and landscape-light peaks. Off suppresses all lightning illumination. These modes preserve the underlying event IDs and geometry seeds.
- `app/audio/storm_audio.gd` bounds the queue to 12 pending arrivals and three spatial voices, schedules onset from the event channel and active listener using the supplied sound speed, and routes to the existing `OpenRC Environment` bus when present. A restored simulation queries only the bounded audible travel window and queues arrivals still in the future. Late arrivals are discarded and active tails fade on a detected camera cut. Pause holds pending playback; reset and sound-disabled paths clear it.

The caller-facing API is `configure(config)`, `update_at(sim_time_s, listener_position, paused, exposure)`, `set_cloud_state(snapshot)`, `set_sound_speed(value)`, `set_audio_enabled(enabled)` and `reset()`. `listener_position` is a rendering `Vector3`; schedule anchors are serialized as float64 triples at the component boundary.

## Intake and license evidence

Storm source and audio hashes, source licenses, and the direct-copy relationship for the thunder candidate are recorded in [weather asset provenance](../../../../assets/sky/weather/PROVENANCE.md). The selected OpenGameArt member is CC0 and unchanged. Human audition and mix review are still pending, so it remains a candidate rather than a qualified final sound.

## Checks run

- Pinned Godot `4.7.2.stable.official.ed1daf0bf`, actual `app/` project, headless `test_storm_events.gd`: 22 checks passed for disabled classic behavior, deterministic/mode-independent event IDs, bounded restore queries, global RNG isolation, 30/60/144 FPS sampling, effective cloud-mask input parity, localized flash radius, stable node allocation, silent audio allocation, restoration between flash and arrival, and pause/resume without a duplicate queue entry.
- Paired CLI traces used identical simulation duration, aircraft state, and disabled soundscape. Exact commands:

  ```powershell
  & .tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --log-file=C:/DEVELOPMENT/OpenRCsimulator/.tools/storm-parity-classic.log -- --trace=C:/DEVELOPMENT/OpenRCsimulator/.tools/storm-parity-classic.csv --t=2.0 --soundscape=off
  & .tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --log-file=C:/DEVELOPMENT/OpenRCsimulator/.tools/storm-parity-electrical.log -- --trace=C:/DEVELOPMENT/OpenRCsimulator/.tools/storm-parity-electrical.csv --t=2.0 --soundscape=off --sky=electrical_storm
  ```

  Comparing non-comment CSV rows in `.tools/storm-parity-classic.csv` and `.tools/storm-parity-electrical.csv` produced equal headers and 481 identical data rows in each file (482 non-comment rows including the header). The comment metadata differs as expected; the recorded physics samples match exactly. [Comparison and source hashes](checks/trace-parity.json) preserve the result; the trace files are ignored scratch evidence and are not committed.
- A native Compatibility SubViewport probe ran on an NVIDIA RTX 3090 at a cloud-to-ground event peak with the localized 4.2 km cloud-flash radius. Godot 4.7.2 compiled and rendered the local cloud and bolt shaders without reported errors at exposures 0.6 and 10,000. The transient light energy was 1.15 for day and 0.0002 at night. The local cloud patch remains visible while surrounding sky stays dark. The engine log is `.tools/storm-draft/project/storm-radius-4200.log`; captures are `.tools/storm-draft/captures/storm_day.png` and `.tools/storm-draft/captures/storm_night.png`, with `.tools/storm-draft/captures/report.json` recording engine, adapter, exposure and event identity.
- The probe used a minimal environment to check shader compilation, geometry, localization and exposure caps. It is not the production sky/night-flight acceptance capture and does not measure GPU/first-strike cost. Production cloud composition, terrain occlusion, speaker/headphone audition, night flight qualification, and the FW-84 performance gate remain pending.

## Actual main-route captures

Both images were captured by the production `app/main.gd` route with Godot 4.7.2, the native RTX 3090 Compatibility renderer, Dummy audio, and the fixed 80 m synthetic-inspection camera. They are deterministic presentation evidence, not flight replay or flown acceptance. The sidecars preserve both `visual_evidence.lighting` and `visual_evidence.world_lighting`; for these field-world clock arguments, the latter records the active Ephemeris-based scene state while the former remains the legacy visual-context snapshot.

- [Electrical storm at the full-moon timestamp](captures/electrical-full-moon-event-peak.png) and [capture sidecar](captures/electrical-full-moon-event-peak.json): 2026-06-29 00:00 local at 4.7° N, 74.1° W, UTC−5; simulation clock 88.8829167 s; sky seed 1253. The sidecar reports the moon as the active light source, solar elevation −62.0741°, lunar elevation +55.5953°, and illumination 0.992774. The moon disc is outside the fixed camera view, so this proves the moonlit world state rather than a visible moon-disc composition. At the captured tick, the schedule has cloud-to-ground event 3102985321:7, started at 88.8666667 s with geometry seed 1446583379. The branched bolt is visible near the right edge, partly cropped by the frame, and the aircraft silhouette remains small at the requested distance.
- [Prestorm at local noon](captures/prestorm-day.png) and [capture sidecar](captures/prestorm-day.json): 2026-06-29 12:00 local at the same coordinates; simulation clock 0 s; sky preset prestorm. The sidecar reports solar elevation +71.5075° and the sun as the active light source; the aircraft silhouette is visible against the cloud deck. The capture uses the explicit local clock because `day` is not a valid field-world clock preset.

The exact application arguments were:

~~~powershell
--capture --scripted --visual_pose=level --visual_distance=80 --visual_elevation=25 --visual_azimuth=315 --autozoom=0 --sky=electrical_storm --time=00:00 --date=2026-06-29 --lat=4.7 --lon=-74.1 --utc_offset=-5 --t=88.8829166666667 --soundscape=off --case=fw84_electrical_full_moon_event_peak --out=C:/DEVELOPMENT/OpenRCsimulator/docs/research/field-world/FW-84/captures/electrical-full-moon-event-peak.png
--capture --scripted --visual_pose=level --visual_distance=80 --visual_elevation=25 --visual_azimuth=315 --autozoom=0 --sky=prestorm --time=12:00 --date=2026-06-29 --lat=4.7 --lon=-74.1 --utc_offset=-5 --t=0 --soundscape=off --case=fw84_prestorm_day --out=C:/DEVELOPMENT/OpenRCsimulator/docs/research/field-world/FW-84/captures/prestorm-day.png
~~~

The command arguments and image SHA-256 values are recorded in the sidecars. The pinned-engine output is retained in [electrical capture log](checks/capture_electrical_full_moon.log) and [prestorm capture log](checks/capture_prestorm_day.log); the focused storm test output is in [test_storm_events.log](checks/test_storm_events.log). Both image hashes match their sidecar values. The engine reports the existing aircraft inertia warning for these captures; the requested frames were saved successfully.

## Known first-slice limits

The cloud flash is a finite horizontal scene-local deck that reuses the procedural density mask, not a volumetric cloud model. The storm bolt is rebuilt from one fixed-seed branch mesh at each cloud-to-ground event. Reflections do not receive transient flashes. The thunder candidate has one source recording and uses a bounded point-source delay; it does not model acoustic propagation through the channel. These are presentation approximations and make no meteorological or physical-weather claim.

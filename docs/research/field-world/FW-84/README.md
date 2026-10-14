# FW-84 electrical storm components

Evidence for the first electrical-storm runtime slice, recorded 2026-10-13. The FW-84 plan remains open: this work does not establish the full flown night gate, final sound selection, or performance budget.

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

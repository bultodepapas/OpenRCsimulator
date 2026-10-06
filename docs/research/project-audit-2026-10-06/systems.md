# Runtime systems audit — 2026-10-06

Status: complete supporting audit. Scope: Godot project organization, app lifecycle, input and radio, rendering, audio, performance instrumentation, related tests and plans. Includes targeted headless probes; broader app checks and capture results are recorded in the master report.

## What is sound

### The runtime has useful boundaries for this stage

**Inspected:** [`project.godot`](../../../app/project.godot), [`app_root.gd`](../../../app/app_root.gd), [`main.gd`](../../../app/main.gd), [`flight_session.gd`](../../../app/sim/flight_session.gd), [`simulation.gd`](../../../app/sim/simulation.gd), [`frames.gd`](../../../app/render/frames.gd), and [`airplane.gd`](../../../app/render/airplane.gd).

The app root owns Home/flight/pause lifecycle. `FlightSession` owns aircraft loading, trimmed reset, input policy and crash/session state. `Simulation` owns the fixed-step state and faults. Rendering has separate aircraft, camera, field, atmosphere, shadow and clock modules. Physics state remains 64-bit and is converted to Godot's 3D types at the render boundary; `Frames` is the single NED/body-to-render conversion point. This is a good early architecture: the live app is still small enough to follow, while the most important seams already exist.

**Evidence:** the session runs before its simulation child (`flight_session.gd:86–88`); rendering consumes interpolated sim state (`main.gd:289–300`); catalog dispatch keeps each aircraft's visual builder and data ID aligned (`airplane.gd:27–44`); Home and flight use the same field builder (`home_scene.gd:54`, `main.gd:391–412`). The catalog refuses unknown and preview-only flight data rather than silently swapping airplanes (`main.gd:115–123`).

**Importance:** positive foundation, preserve. **Timing:** no change needed. Keep the current seams and split a module only when a feature creates a second real owner or a measured maintenance/performance problem.

### Radio safety and menu isolation are unusually deliberate

**Inspected:** [`rc_input.gd`](../../../app/input/rc_input.gd), [`rc_calibration.gd`](../../../app/input/rc_calibration.gd), [`flight_session.gd`](../../../app/sim/flight_session.gd), [`ui_input.gd`](../../../app/ui/ui_input.gd), [`held_keys.gd`](../../../app/ui/held_keys.gd), [`pause_menu.gd`](../../../app/ui/pause_menu.gd), and the radio/UI tests.

The code separates keyboard keys, menu navigation and raw radio axes. A radio throttle does not arm until its axis has actually reported low; disconnect centers controls, idles the engine and pauses. Calibration is a pure state machine with per-device profiles. The menu removes joypad bindings from `ui_*` while leaving raw-axis reads available, and a named session hold prevents input sampling or crash countdown under pause. Held keyboard navigation keys are masked until released after Continue.

**Evidence:** safeguards are implemented in `rc_input.gd:67–84,108–139`, `flight_session.gd:113–165,384–399`, and `app_root.gd:138–153,215–223`. Tests cover fake-radio arming/disconnect/reconnect/calibration (`test_e2e_radio.gd`), raw profile mapping (`test_rc_input.gd`), calibration (`test_rc_calibration.gd`), joypad/UI isolation (`test_ui_input.gd`), pause and focus (`test_ui_pause.gd`), and shortcut-table consistency (`test_controls_reference.gd`). These are meaningful code-path tests, not just calls to button signals.

**Counterevidence and limit:** they do not establish setup quality or feel with the owner's transmitter. The research correctly says Godot/SDL samples joystick state once per main-loop iteration, so a 240 Hz simulation can see the same radio value on several ticks; at 60 rendered frames/s this is a 60 Hz staircase across four ticks. The integration and replay properties apply to a given sequence of per-tick samples, not to identical physical-radio sampling at every frame rate. See [radio/latency research](../roadmap-investigations/06-radio-input-servos-latency.md), particularly its input chain and latency model.

**Importance:** sound approach; hardware input latency and feel remain open validation. **Timing:** record latency and pilot feel at Gate 2/M3 on the target machine. Do not claim that the 240 Hz physics tick means 240 Hz radio response.

### Render foundations favor repeatable evidence over early effects

**Inspected:** [`field.gd`](../../../app/render/field.gd), [`treeline.gd`](../../../app/render/treeline.gd), [`tree_assets.gd`](../../../app/render/tree_assets.gd), [`shader_clock.gd`](../../../app/render/shader_clock.gd), [`visual_evidence.gd`](../../../app/render/visual_evidence.gd), [`frame_samples.gd`](../../../app/render/frame_samples.gd), and the visual-quality/landscape plans.

The Compatibility renderer is selected explicitly, runtime dependencies are kept out of the renderer, and the current field uses data-driven surfaces plus bounded MultiMesh sectors. Shader animation reads a wrapped simulation clock, not wall-clock `TIME`; positions and hashes make the treeline repeatable. The capture harness records the actual pose, camera, backend, data hashes and render counters. The frame logger records monotonic wall intervals and raw per-frame metrics, and its docs distinguish llvmpipe evidence from target-GPU performance.

**Evidence:** `project.godot:26–33`; `field.gd:11–25`; `treeline.gd:1–6,35–87`; `shader_clock.gd:1–5,17–35`; `visual_evidence.gd:67–95`; `main.gd:493–529,531–620`. The L6 work also bounds vegetation draw groups and labels tree size as an estimate; see [LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md) and [VQ-01b evidence](../visual-quality-implementation/VQ-01b/README.md).

**Importance:** strong visual/testing foundation. **Timing:** keep simple scenes and measured budgets as landscape work grows; the current plans already gate closer trees, terrain and alternate renderers behind pixel/counter evidence.

## Findings and limits

### SYS-01 — Real radio input is frame-sampled, not physics-tick sampled

**Inspected:** the physics scheduling and input path in `project.godot:19–24`, `flight_session.gd:86–88,113–116,384–399`, and `rc_input.gd:115–139`; the detailed source investigation in [roadmap investigation 06](../roadmap-investigations/06-radio-input-servos-latency.md).

`FlightSession` polls radio axes before each simulation step, which avoids an extra whole-tick command delay. Godot's `Input.get_joy_axis()` reads its latest stored axis value; on Linux, the Godot 4.7.2 main loop processes pending OS events before its frame iteration. Multiple 240 Hz physics ticks can therefore poll the same stored value between event-poll iterations. Automated keyboard/fixed-input frame-rate tests prove integration stability for injected samples, not physical radio latency across 30/60/144 Hz. The renderer also uses Godot's physics interpolation fraction; the official docs describe the normal interpolation tradeoff as displaying a state in the past, so include that delay when measuring control-to-screen response.

**Independent engine evidence:** [Godot 4.7.2 `Input::get_joy_axis()`](https://github.com/godotengine/godot/blob/4.7.2-stable/core/input/input.cpp) reads the stored axis map; the [Linux 4.7.2 main loop](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/linuxbsd/os_linuxbsd.cpp) processes pending OS events before its frame iteration. The app uses `Engine.get_physics_interpolation_fraction()` at `main.gd:289–300`; [Godot 4.7's interpolation guide](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html) explains that interpolation displays a state in the past and can add input delay.

**Importance:** medium, already understood. **Why it matters:** RC response depends on input-to-photon latency and command stair-stepping, not only integrator frequency. **Counterevidence:** the research traces this pipeline and proposes a camera/latency-patch test; D6d and Gate 2 remain open, and no artificial radio transport delay is currently added. **Recommendation:** retain the current fixed-step design; at Gate 2 capture real-radio latency and feel at the owner's monitor refresh, and report the test rate with the result. Measure input event → observed sample → rendered pose rather than treating 240 Hz as end-to-end response. **Timing:** hardware validation before claiming radio realism; no architectural rewrite now.

### SYS-02 — The static Home scene and the flight scene assemble the same world separately

**Inspected:** `home_scene.gd:40–75` and `main.gd:391–412`.

Both routes correctly reuse the field, atmosphere, aircraft, shadow and shader-clock modules, and existing transition captures check camera/environment counts. The root scene setup is nevertheless duplicated: each route separately creates its environment, adds the field and sun, and applies route-specific airplane/camera composition. As more field lighting, weather, quality settings or selectable fields arrive, the two compositions can drift even while their terrain meshes still match.

**Importance:** low-medium growth risk, not a current correctness failure. **Counterevidence:** the field itself was deliberately extracted as a shared builder at L5, and Home is a still image with no session or simulation. The duplicated orchestration is currently short and understandable. **Recommendation:** do not introduce a generic world framework now. Keep a Home/flight parity check whenever a shared world setting changes; extract only the actual common assembly if the second route begins diverging. **Timing:** monitor through UI-06 and the next field/weather changes.

### SYS-03 — Home-to-flight transition cost has not been validated on player hardware

**Inspected:** `app_root.gd:60–73,100–116`, `home_scene.gd:41–75`, `main.gd:87–131,391–412`, and the UI plan's recorded startup trial.

Home builds a full static 3D field and selected aircraft; pressing Fly removes it and synchronously creates the flight world and simulation. The UI plan records about 0.35–0.45 seconds of CPU work and a 1.4-second / 145 MB first frame in a software-rendered VM for the Home backdrop; it explicitly says owner-machine measurement is pending. That is not evidence of a target-machine stall, but a second synchronous world build can make the Fly action hitch, especially after future landscape growth.

**Importance:** medium performance risk to the first-launch flow. **Counterevidence:** only one world is retained at a time, capture work is deterministic, and the llvmpipe number is explicitly not a GPU budget. **Recommendation:** measure cold and warm Home→Fly wall time and peak memory on the owner's machine before adding more background assets. Keep this synchronous design if it is below the agreed interaction budget; if it is visible, add a focused loading/transition seam or cache immutable resources instead of a broad architecture rewrite. **Timing:** Gate 2 / before L7–L11 world expansion.

### SYS-04 — Placeholder engine audio has approximately 186 ms of queued control response

**Inspected:** [`engine_sound.gd`](../../../app/render/engine_sound.gd), `main.gd:227–230,360–368`, [`test_engine_sound.gd`](../../../app/tests/test_engine_sound.gd), and [menu audio investigation 19](../menu-investigations/19-audio-ajustes-pausa.md).

The synth is explicitly a two-stroke rpm cue and its current tests verify firing frequency, phase continuity and sample bounds. Godot 4.7.2 chooses a power-of-two buffer size from `mix_rate * buffer_length` in [the pinned engine source](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/effects/audio_stream_generator.cpp). An independent pinned-engine probe reproduced the app's 0.15-second × 22,050 Hz settings: 4096 ring slots, 4095 writable/queued frames, 185.7 ms. Its source and output are saved as [probe](evidence/systems-audio-buffer-probe.gd) and [log](evidence/systems-audio-buffer-probe.log); the earlier app-level measurement is in [menu investigation 19](../menu-investigations/19-audio-ajustes-pausa.md). The app fills all available frames in `main.gd:227–230`, so throttle/rpm changes reach sound about 186 ms behind the simulation, before output-device latency. [Godot 4.7's class docs](https://docs.godotengine.org/en/4.7/classes/class_audiostreamgenerator.html) explicitly say shorter buffers reduce latency at the cost of faster script-side production, and recommend 22,050 Hz as a viable GDScript rate. The sample rate is a reasonable early-stage choice; filling the entire queue is the latency choice to revisit.

**Importance:** medium for perceived response, low for current physics correctness. **Counterevidence:** the code and `STACK.md` label this as a placeholder and reserve recordings/realistic propagation for G3; the simulation does not consume audio state. The sound track already recommends a shorter target-fill queue, synthesis snapshots and tests. **Recommendation:** keep sound out of realism acceptance until G3 reduces/measures queue latency and validates output with listening as well as the Dummy driver. Include median/p95 control-to-audio delay in the audio/perception gate. **Timing:** before realistic audio is claimed or PT4 treats sound as a pilot cue; no need to block current physics work.

### SYS-06 — Saved radio-profile validation is structural but permissive

**Inspected:** `rc_calibration.gd:107–143`, `rc_input.gd:67–84,141–184`, and `test_rc_calibration.gd:84–99`.

The calibration wizard enforces unique channel axes and plausible centred-stick sweeps. On loading a saved profile, `valid()` checks dictionaries, numeric endpoints, boolean inversion, axis range and `min < max`, but accepts duplicate channel axes, an out-of-range center, out-of-range endpoints, an unknown `kind`, and NaN endpoints. A targeted Godot 4.7.2 probe reproduced all five acceptances; see [probe source](evidence/systems-profile-probe.gd) and [output](evidence/systems-profile-probe.log). The current unit test rejects an axis index of 12 but does not probe these combinations. Such a profile generally clamps or maps poorly rather than crashing, but it can make a control move the wrong channel after a malformed, hand-edited or stale settings file. Nonfinite derived controls are rejected by `simulation.gd:128–130`, limiting propagation into the flight state.

**Importance:** low-medium input robustness gap. **Counterevidence:** profiles are written by the constrained wizard, keyed per device, and the next UI input track already plans to extract shared device/profile ownership. **Recommendation:** strengthen profile validation and add malformed-profile tests as part of UI-10a/UI-10b; reject non-`radio` profile kinds for radio calibration, require four distinct axes and finite ordered endpoints with center in range. **Timing:** before profile import/sharing or broad controller support; not a reason to delay current single-radio testing.

### SYS-07 — ObjectDB exit warnings are transient audio teardown, not repeat-cycle growth

**Inspected:** verbose `test_e2e_input.gd` shutdown, `test_aircraft_catalog.gd` teardown, `test_ui_pause.gd` cycle test, `app_root.gd:100–116,192–206`, and `main.gd:33–45,87–92`.

The suite reports one leaked `AudioStreamGeneratorPlayback` after `test_aircraft_catalog`, `test_e2e_input`, and `test_e2e_radio`. A verbose run identified the same class at refcount 1. The e2e tests quit with their flight scene/audio player still active; the catalog test frees its flight and quits immediately. A clean targeted headless probe used the real Home → Fly → pause → End methods for five cycles: `OBJECT_NODE_COUNT` was 218 at every Home, and only the newest audio playback remained valid shortly after End; after one idle second all five playback IDs were invalid and the node count remained 218. The probe and output are saved as [source](evidence/systems-lifecycle-probe.gd), [lifecycle log](evidence/systems-lifecycle-probe.log), and [verbose test log](evidence/systems-e2e-input-verbose.log). This agrees with the app's existing five-cycle node-count test in `test_ui_pause.gd:181–197`.

**Importance:** low test-diagnostic noise; no gameplay leak reproduced. The audio server briefly retains the active playback while it tears down, and the suite's immediate quit makes ObjectDB observe that in-flight resource at process shutdown. **Counterevidence:** playback instances drain during the next idle interval and live node counts stay flat across repeated routes. **Recommendation:** do not change app lifecycle based on this warning. If the team wants clean leak-check output, add explicit audio stop/flight cleanup plus a short settle interval to the affected fixtures and retain a regression check. **Timing:** test hygiene when touching those fixtures; no gameplay fix now.

## Roadmap and sequencing checks

- **Good ordering:** the UI plan handled focus/pause/cleanup before preferences, device selection and expanded settings. Visual plans require a readability gate before close trees, terrain, props or alternate backends. This controls scope and ties added scenery to pilot evidence.
- **Keep radio ownership singular:** current FlightSession owns the one active pad, starts from the first connected device and does not silently hand control to another device after disconnect. That is a defensible failsafe. Explicit selection is correctly deferred to UI-12, but playtest instructions should say to connect only the intended controller until selection exists.
- **Keep manual controls distinct from simulator aids:** keyboard has rate-limited virtual sticks; radio values are passed through because the transmitter already supplies rates/expo. Home and Help communicate connection/arming, while trims and actual radio configuration still need the owner's Gate 2 decision.
- **Treat auto-zoom as a readability aid, not neutral camera realism:** `pilot_camera.gd:23–33,54–66` targets 30 px and clamps FOV to 6°–50°. The perception research derives that this erases looming over a substantial distance band and magnifies background scale. The plan correctly makes zoom configurable and asks the blinded human test to compare modes. Preserve that gate; do not silently bake current auto-zoom into all future camera modes.
- **Audio work should follow simulation data contracts:** the sound investigation's snapshot/ring-buffer recommendation is sound because realtime audio should not read mutable physics state. Keep G3 after engine/propeller states are accurate, and avoid calling the present buzzer realistic.
- **No engine/module rewrite is justified:** Compatibility, GDScript and a custom flight model fit the selected native radio path; the exportable stack is pinned, and the plans reserve a measured Gate P before GDExtension. Revisit renderer or language only from target-platform evidence.

## Research and validation limits

The project's system research is strong: menu investigations cover lifecycle, focus, identity, localization, accessibility, settings and audio; roadmap investigation 06 traces Godot/SDL, EdgeTX, servos and latency; investigation 10 separates headless checks, captures, exports and hardware tests. The source tree includes corresponding tests and telemetry instead of relying only on prose.

This pass used targeted headless probes and one verbose end-to-end run; it did not open the rendered app or test physical hardware. The lead's broader runtime logs and rendered captures must still decide whether the static performance/input hypotheses reproduce at this revision. Automated radio tests use injected events and fake device identity; they do not prove real transmitter enumeration, stick direction, setup comprehension, USB behavior or feel. llvmpipe captures prove deterministic render paths and visual measurements under that environment, not target GPU throughput. The first owner flight and the human readability gate remain important acceptance work, not paperwork to waive.

## Reproduction commands

Run from the repository root with the pinned Godot binary. The project path remains `app/`; the three probe scripts are audit evidence outside that project directory.

```sh
$(app/get-godot.sh) --verbose --headless --path app --audio-driver Dummy --script res://tests/test_e2e_input.gd
$(app/get-godot.sh) --verbose --headless --path app --audio-driver Dummy --script "$PWD/docs/research/project-audit-2026-10-06/evidence/systems-lifecycle-probe.gd"
$(app/get-godot.sh) --verbose --headless --path app --audio-driver Dummy --script "$PWD/docs/research/project-audit-2026-10-06/evidence/systems-profile-probe.gd"
$(app/get-godot.sh) --verbose --headless --path app --audio-driver Dummy --script "$PWD/docs/research/project-audit-2026-10-06/evidence/systems-audio-buffer-probe.gd"
```

The verbose e2e command intentionally shows the shutdown warning; the lifecycle probe demonstrates why it is not a repeated Home→Fly leak. The other probes print the permissive profile-validation cases and the generator's full-queue frame count.

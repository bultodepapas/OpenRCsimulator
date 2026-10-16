# RC Helicopter Research Trainer

The playable rotorcraft uses published X-Cell .60 SE equations and the supplied HX-700 Blender visual. The visual is flybarless; this flight reference includes an effective flybar response. This pairing is an experimental research surrogate, not an identified HX-700 flight model.

## Start and controls

For the **advanced articulated HX-700 mechanism**, run `./research/helicopter/inspect-mechanics.ps1`. Its separate inspector exposes collective, cyclic, four servo horns, nine rigid links and tail pitch with close cameras and slow rotation. [Controls, source pipeline and limits](../assets/aircraft/hx-700/articulated/README.md); [HELI-26a verification](research/helicopter/HELI-26a/README.md). This mechanical inspection does not yet replace the flight session below or provide achieved servo dynamics.

Select **RC Helicopter Research Trainer** on Home. The default start is on the authored flat grass pad at north 6 m, east 0 m, facing east, beside the runway midpoint. The runway occupies north 9–21 m; the helicopter is outside it. **Start: hover** remains available for airborne practice. R repeats the selected start. Home removes unqualified turbulence while preserving supported steady wind and deterministic gusts.

On the pad the rotor is stopped, the motor disarmed, hold engaged, and the collective initialized to zero blade pitch (about 17% stick on this model's normal curve). Center cyclic/yaw, press **B** to arm, then **H** to release hold. Wait for **GOVERNED** before increasing collective with W. The 12 s torque ramp is an explicit simulator estimate; it is not an identified engine or ESC response. The earlier 4 s candidate exceeded the configured skid yaw capacity.

Arrow keys command cyclic: Up pitches the nose down, Down up. A/D command yaw; W/S change collective. Keyboard B disarms as well as arms. Keyboard H enters a latched zero-drive hold; the rotor coasts down physically. P pauses/resumes, C changes camera, Esc opens the pause menu. K and Enter operate radio calibration.

Recognized standard gamepads receive these helicopter defaults automatically. Controller settings shows the active vehicle's assignments; **Remap**, **Clear** and **Save** preserve explicit choices. The flight HUD displays the actual bindings. Raw radios and unmapped joysticks require explicit configuration.

| Action | Xbox / PlayStation |
| --- | --- |
| Arm / disarm | A / Cross |
| Engage / release rotor hold | B / Circle |
| Normal / idle-up curve | RB / R1 |
| Trainer / direct cyclic | Left stick click (L3) |
| Latched motor cut | LB / L1 |
| Camera | Y / Triangle |
| Restart selected flight, then Continue | View / Share or Create |
| Pause menu | Menu / Options |

Release the motor-cut button before attempting to release rotor hold. Releasing cut alone never restarts the rotor; an explicit hold-release command is still required. Arm, hold release, curve and trainer changes are refused during pause, modal holds or controller loss. Curve switching retains the pitch-jump confirmation described below.

A physical radio must first satisfy input arming at low collective, then match the displayed zero blade pitch before motor arming. A gamepad retains the selected starting collective. Motor arming and hold release are refused during pause, a modal hold or controller loss. Pause freezes simulation time and the startup ramp. Resume is explicit.

The trainer applies attitude/rate feedback through cyclic and heading/rate feedback through tail pitch. It has no position or altitude hold. G selects direct cyclic. I requests the other authored pitch/throttle curve; a pitch jump above 0.5° requires a second explicit press, preserving the pilot's stick. Check the pitch shown before confirming. This is not a qualified aerobatic controller.

Direct launch from the repository root:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app -- --aircraft=xcell-60-research
# Explicit airborne practice:
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app -- --aircraft=xcell-60-research --start=airborne
```

Technical `--trace`/`--capture` invocations retain their historical airborne fixture unless `--start=ground` is supplied. `--alt` applies only to airborne starts; contradictory ground/altitude requests are refused.

## Physics and state

Simulation state remains float64. The common body state has 13 values. Airborne practice retains six rotor/controller values: shaft speed, two flap harmonics, induced velocity, heading reference and yaw integral. Ground-start sessions append eight world north/east skid bristle strains, two per contact. All derivatives use the same RK stages. Ground initialization solves four-skid support and checks all six force/moment residuals; it does not reuse an airborne body pose, rotor speed or wake.

Bristle friction supplies static resistance on the qualified flat pad, with a Coulomb force limit and dissipative release. Tangential stiffness/damping reuse the estimated normal coefficients as an explicitly estimated isotropic proxy. Relaxation is bounded at 100 s⁻¹; unloaded memory decays over 0.2 s without applying an adhesive force. Other surfaces retain the historical sliding-contact law; slope starts remain unqualified. The pad's current ideal static yaw capacity is about 3.65 N·m.

The ground trainer derives a collective-to-tail compensation reference from its own calm-air hover equations at 3 m and the selected density; actual wind still enters every live aerodynamic stage. This is controller precompensation, not measured aircraft calibration. Yaw integral accumulation stops while skids contact the ground. Actual rotor and body dynamics remain coupled throughout startup, liftoff and landing. Reduce collective as the ground-effect cushion builds during landing.

Below the identified RPM range, main and tail models use explicitly estimated bounded dimensional startup laws, smoothly joined to the existing flight equations. They retain relative wind. Their metadata and HUD do not label this regime identified. The session's bounded stop-event integrator prevents negative shaft stages, resolves the stop and consumes the remainder of the fixed tick. Zero-speed shaft friction prevents numerical restart chatter. Hold remains a one-speed drive proxy, not a separate clutch/freewheel or qualified autorotation mode.

Terminal contacts stop the accepted flight state and cut drive. The separate aftermath continues until paused or restarted; see below.

## Impacts and wreckage

The helicopter reports the struck component, contact point, normal and incident speed. Skids retain the existing 40 mm terminal travel threshold; ordinary support and gentle landings do not create wreckage. Fuselage, boom and fin probes use explicitly estimated bounds from the HX-700 visual. Body probes sweep against terrain and authored obstacle proxies. Main and tail rotors use a conservative analytic terrain disc at speed; scenery uses 32 padded diameters covering the disc. Slow/stopped rotors use a finite blade at the accepted tick-end phase. These are conservative collision proxies, not exact blade-surface intersection or elastic blade dynamics.

A terminal impact cuts the motor and switches to disposable wreckage using the existing named model parts. Part release depends on the contact and provisional severity: individual blades, canopy, skids, boom and fin remain distinct. Detached blades inherit tangential motion bounded by their share of shaft energy. Collisions, surface dust, composite chips and impact sounds continue while the flight solver stays stopped. **P** pauses/resumes the aftermath, **Esc** opens the menu, and **R** clears the wreck and restores the selected start. Rotor blur and LED arcs stop; enabled stationary night-kit optics follow their respective wreck parts. Reset restores the flight kit.

The brief grey plume represents nonthermal fracture dust. The active glow reference has no declared crash fuel/battery inventory, so the HX visual's battery mesh does not trigger an invented LiPo fire. Shared crash textures and audio are reused. Debris masses, separation, severity and effects remain presentation estimates, not measured helicopter failure predictions. [HELI-33 evidence](research/helicopter/HELI-33/README.md) records fixtures, regression tapes and native captures.

## Night flight

The helicopter has a dedicated RC night kit in flight and on Home. **L** cycles **automatic → all → navigation → off**; the controller's existing light-cycle action does the same. Automatic fades the kit in as the sun falls from +3° to −4° and leaves it off in daylight. Lights work with the motor stopped. Direct launch accepts `--heli-lights=auto|all|nav|off`.

Red marks the left side, green the right, and white the tail. Warm canopy/boom strips and blue-cyan skids/fin outline the airframe. Main-blade LEDs appear amber from above and blue-cyan from below; their points become arcs as the rotor accelerates. A downward-forward landing lamp illuminates nearby ground. The red beacon flashes only while the motor is armed. Navigation mode retains position lights and the armed beacon, without the strips, rotor LEDs or landing lamp.

Rotor light phase uses the same accepted shaft phase as the visible blades; pause holds it. The exposure trace uses a fixed 1/60 s visual shutter, not frame delta or a second rotor simulation. Geometry, width, brightness, local spill and the fixed-SDR readability gain are presentation estimates, not a calibrated lighting installation or added battery load. The kit does not change the aircraft's mass, aerodynamics, motor or world exposure.

[HELI-30 night evidence](research/helicopter/HELI-30-NIGHT/README.md) records RC references, native ground/hover and top/bottom captures, controls, tests and limitations. Use pilot zoom at long range; a wide 32° view at 100 m does not provide enough airframe pixels to identify attitude reliably.

## Data, recording and replay

Regenerate the rotorcraft schema and authored data with `python research/helicopter/xcell/derive.py`; never edit generated JSON. The loader rejects invalid units, evidence, inertias, gearing, controller capabilities and contact parameters. The separate `hx700_electric_3d_experimental.json` is generated from `research/helicopter/hx700/derive.py`. It has a body-rate FBL controller and independent declared/estimated 700-class quantities, but remains **laboratory-only** and is refused by the playable session. Achieved servos, freewheel/energy behavior, signed maneuver qualification and aircraft-specific flight data remain release gates. It does not inherit X-Cell validation.

T records `openrc-helicopter-trace v2`. Its 46 columns contain body/rotor/contact state, commands, loads, power/hold/mode, ramp scale and main/tail phase, with distinct endpoint and load-stage times. Bristle columns are zero for the six-state airborne fixture. Metadata declares the actual continuous layout and selected start. Recording failures prevent saving a misleading partial trace.

Native Variant `openrc-helicopter-checkpoint v4` includes power lifecycle, selected start/pad, all continuous contact memory, authoritative accepted-tick shaft phase and obstacle-inventory identity. Reset the same aircraft/start before restoring. Restore validates aircraft bytes, weather, field, obstacles, trim, mass/gravity/inertia, commands, RPM projection, phase and lifecycle before committing, then pauses. Historical v1/v2/v3 files are refused explicitly because they lack the current contact boundary. Failed restore leaves the live state unchanged. Crashed sessions cannot save a resumable flight checkpoint. Reset sets phase to zero; restore retains saved phase. Rendering only interpolates accepted tick telemetry.

[HELI-20 implementation evidence](research/helicopter/HELI-20/README.md) records numerical tests, captures and remaining limits. [HELI-25](research/helicopter/HELI-25/README.md) owns visual provenance and export; [HELI-16](research/helicopter/HELI-16/README.md) retains the original flight verification and audit. Software verification does not establish physical validation. Remaining actuator, mechanism, 3D maneuver, collision, pilot and performance gates are in the [helicopter plan](plans/helicopter.md#14-ground-start-and-aerobatic-3d-execution-plan).

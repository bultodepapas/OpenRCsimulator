# RC Helicopter Research Trainer

The playable rotorcraft uses published X-Cell .60 SE equations and the supplied HX-700 Blender visual. The visual is flybarless; this flight reference includes an effective flybar response. This pairing is an experimental research surrogate, not an identified HX-700 flight model.

## Start and controls

Select **RC Helicopter Research Trainer** on Home. The default start is on the authored flat grass pad at north 6 m, east 0 m, facing east, beside the runway midpoint. The runway occupies north 9–21 m; the helicopter is outside it. **Start: hover** remains available for airborne practice. R repeats the selected start. Home removes unqualified turbulence while preserving supported steady wind and deterministic gusts.

On the pad the rotor is stopped, the motor disarmed, hold engaged, and the collective initialized to zero blade pitch (about 17% stick on this model's normal curve). Center cyclic/yaw, press **B** to arm, then **H** to release hold. Wait for **GOVERNED** before increasing collective with W. The 12 s torque ramp is an explicit simulator estimate; it is not an identified engine or ESC response. The earlier 4 s candidate exceeded the configured skid yaw capacity.

Arrow keys command cyclic: Up pitches the nose down, Down up. A/D command yaw; W/S change collective. B disarms as well as arms. H enters a latched zero-drive hold; the rotor coasts down physically. Releasing a controller's throttle-cut switch does not restart it. P pauses/resumes, C changes camera, Esc opens the pause menu. K and Enter operate radio calibration. Controller settings can assign helicopter arm, hold, mode and trainer actions; these additional bindings are unassigned by default.

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

The ground trainer derives a collective-to-tail compensation reference from its own hover equations; it is controller precompensation, not measured aircraft calibration. Yaw integral accumulation stops while skids contact the ground. Actual rotor and body dynamics remain coupled throughout startup, liftoff and landing. Reduce collective as the ground-effect cushion builds during landing.

Below the identified RPM range, main and tail models use explicitly estimated bounded dimensional startup laws, smoothly joined to the existing flight equations. They retain relative wind. Their metadata and HUD do not label this regime identified. The session's bounded stop-event integrator prevents negative shaft stages, resolves the stop and consumes the remainder of the fixed tick. Zero-speed shaft friction prevents numerical restart chatter. Hold remains a one-speed drive proxy, not a separate clutch/freewheel or qualified autorotation mode.

Rotor/terrain clearance and excessive skid compression stop the flight; R recovers. Current full-disc terrain checks are conservative and do not provide swept scenery collision or parked-blade precision.

## Data, recording and replay

Regenerate the rotorcraft schema and authored data with `python research/helicopter/xcell/derive.py`; never edit generated JSON. The loader rejects invalid units, evidence, inertias, gearing, controller capabilities and contact parameters. The separate `hx700_electric_3d_experimental.json` is generated from `research/helicopter/hx700/derive.py`. It has a body-rate FBL controller and independent declared/estimated 700-class quantities, but remains **laboratory-only** and is refused by the playable session. Achieved servos, freewheel/energy behavior, signed maneuver qualification and aircraft-specific flight data remain release gates. It does not inherit X-Cell validation.

T records `openrc-helicopter-trace v2`. Its 46 columns contain body/rotor/contact state, commands, loads, power/hold/mode, ramp scale and main/tail phase, with distinct endpoint and load-stage times. Bristle columns are zero for the six-state airborne fixture. Metadata declares the actual continuous layout and selected start. Recording failures prevent saving a misleading partial trace.

Native Variant `openrc-helicopter-checkpoint v3` includes power lifecycle, selected start/pad, all continuous contact memory and authoritative accepted-tick shaft phase. Reset the same aircraft/start before restoring. Restore validates aircraft bytes, weather, field, trim, mass/gravity/inertia, commands, RPM projection, phase and lifecycle before committing, then pauses. Historical v1/v2 files are refused explicitly. Failed restore leaves the live state unchanged. Reset sets phase to zero; restore retains saved phase. Rendering only interpolates accepted tick telemetry.

[HELI-20 implementation evidence](research/helicopter/HELI-20/README.md) records numerical tests, captures and remaining limits. [HELI-25](research/helicopter/HELI-25/README.md) owns visual provenance and export; [HELI-16](research/helicopter/HELI-16/README.md) retains the original flight verification and audit. Software verification does not establish physical validation. Remaining actuator, mechanism, 3D maneuver, collision, pilot and performance gates are in the [helicopter plan](plans/helicopter.md#14-ground-start-and-aerobatic-3d-execution-plan).

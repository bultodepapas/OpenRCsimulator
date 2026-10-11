# AUD-01 Runtime integration audit

2026-10-11 · **Status: read-only integration audit; no runtime changes.**

## Snapshot inputs

- `FlightSession.AUX_RPM` is index 0 of `session.sim.aux`. It is the accepted physical shaft RPM in rpm for glow, electric and turbine models. Read `session.sim.inputs[3]` for normalized throttle (0–1), `session.engine_running` for source enabled, `session.sim.tick` / `time()` for accepted tick and seconds, and `session.sim.paused` for pause state. These are read-only observations.
- Electric load telemetry is available from pure `session.electrical_state()`: actual RPM, enabled state, duty and motor/battery current in amperes, plus battery fields where applicable. There is no shared load scalar for every source; keep any throttle/load-to-timbre mapping explicitly estimated.
- Turbine throttle is an ECU command: its throttle map produces a shaft-RPM demand, while the spool schedule/governor produces the actual `AUX_RPM`. Turbines have no propeller. The current turbine model does not include start sequence, flameout, fuel burn or EGT. The existing D5 buzz is a two-stroke single-cylinder placeholder, so it is not a turbine voice.
- `session.air_data(session.sim.state).V` gives true airspeed in m/s. `session.wind_at(session.sim.time())` gives the current read-only NED wind vector in m/s, including deterministic turbulence when configured. Ground velocity can be derived from body velocity and attitude if needed.
- Render-space position is in meters. After `_render_pose`, use `_airplane.root.global_position` for the aircraft source and `_camera.global_position` for the active listener anchor. The camera is current; pilot view stays at the field station and inspect view moves with the aircraft.
- For day/night mix, use the current sun elevation. The fixed lighting path exposes it in `_lighting`; field-world time of day updates `Atmosphere.state.sun_elevation_deg` through `World.update`. `World.flow_hour()` returns local decimal hours only while time is flowing; it returns -1 otherwise.

## Lifecycle and seams

`session.resetting` fires before physical reset, including the automatic restart after a crash. Clear queued flight audio and reset any position/Doppler observer there; after reset and `_render_pose`, prime the soundscape from the new tick-zero snapshot. In `_process`, publish the read-only snapshot after `_render_pose` so source and listener anchors match the rendered frame. `sim.paused` covers menu/focus/failsafe/calibration/crash pauses; keep flight-tied audio aligned with that state. `session.crash` distinguishes the impact hold. No audio callback should alter simulation arrays, commands, RNG, or clocks.

The current engine voice is created in `main.gd` only for non-electric flights and updated from `sim.aux[0]`. Gate it behind the planned `--soundscape=legacy` mode when the new soundscape is active, preserving the legacy path for G3b qualification. `--scenery=on` also creates a 2D looping wind-and-bird bed through `Scenery.attach`; scenery audio defaults on when scenery is enabled. If the new soundscape owns those ambience layers, disable the old bed (`--scenery_audio=off` or `OPENRC_SCENERY_AUDIO=off`) or replace that creation through the scenery interface, so both beds cannot play together. Scenery is off by default.

## Inspected interfaces

`app/main.gd`, `app/sim/flight_session.gd`, `app/sim/simulation.gd`, `app/physics/turbine.gd`, `app/physics/propulsion.gd`, `app/render/pilot_camera.gd`, `app/render/world/world.gd`, `app/render/field.gd`, and `app/scenery/scenery.gd`. Graph search located the symbols; graph snippets around GDScript functions were stale, so conclusions above use current working-tree source reads.

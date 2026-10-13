# OpenRC Simulator

An open-source RC airplane simulator for a USB transmitter, gamepad or keyboard. Fly from the pilot's position on the field, or use chase, orbit and close-up views. **Early alpha:** automated checks verify the software; flight models still need independent RC measurements and pilot validation.

![Animated studio tour of all five aircraft](docs/media/aircraft-tour.gif)

The five aircraft shown from changing angles. [Still views and render provenance](docs/media/README.md#aircraft-stills).

## Download and fly

[Download the rc8 alpha](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc8) for Windows, Linux or macOS. Extract the ZIP and launch the executable. Godot is not required for a downloaded build. Packages are unsigned; see the [first-launch guide](docs/FIRST-LAUNCH.md) for platform setup, controls, radio calibration and diagnostics.

**First flight:** new Home preferences start on the Stik runway with gentle wind and passing evening; saved choices take precedence. Select **Airborne**, **Calm** and **Day** for trimmed airborne practice. [Player guide and controls](docs/FIRST-LAUNCH.md).

The downloads are the **rc8 snapshot**; the features and aircraft below describe **current source, checked 2026-10-13**. In rc8, Turbo Lumber Evolution is a visual preview; its electric flight and runway start are newer source features. See the [rc8 release notes](docs/releases/v0.1.0-rc8.md) for the packaged build.

## Aircraft

| Aircraft | Configuration | Status |
| --- | --- | --- |
| [Jensen Das Ugly Stik 60](docs/UGLY-STIK-PLAN.md) | 1.52 m, .61 glow, tricycle gear | Reference model under evaluation; Home offers airborne or experimental runway start |
| [Great Planes Extra 300S .60](docs/EXTRA-300-PLAN.md) | 1.63 m, .61 glow, taildragger | Experimental |
| [P-51D Mustang 1/4](docs/P51-PLAN.md) | 2.82 m, 120 cc gasoline, taildragger | Experimental |
| [Ventage Jet](docs/AVANTI-S-PLAN.md) | 2.00 m, JetCat P100-RX turbine | Experimental; airborne, flaps and gear up |
| [Turbo Lumber Evolution](docs/TIMBER-INTEGRATION-PLAN.md) | 1.55 m, 800 Kv, 4S electric, fixed wheels | Experimental; airborne or runway start; flaps up, assists off |

All five aircraft have flight data in current source. Ventage Jet starts airborne with its flaps and gear up. Turbo Lumber Evolution has an articulated imported model and its own electric sound; its motor losses and two-blade propeller map are estimated or borrowed, and its prescribed 4S bus does not model battery depletion.

## Current features

| Area | Available in current source |
| --- | --- |
| Flight physics | Custom float64 six-degree-of-freedom solver at 240 Hz, trim, local aerodynamic loads, stalls/spins and servo dynamics. Recent work includes [wing/tail pitching corrections](docs/research/aero-consistency/E0a2c/README.md) and [ground effect on the Stik](docs/research/ground-effect/M5-GE-1/README.md). [Flight model](AIRCRAFT_CONTRACT.md) |
| Propulsion | Glow and gasoline propellers, coupled electric motor/ESC/battery models, and a spooling turbine. Torque, gyroscopic effects, P-factor and propwash are enabled by aircraft data where configured. [Propulsion](docs/PROPULSION-CORE-PLAN.md) · [Electric models](docs/ELECTRIC-PROPULSION-PLAN.md) |
| Ground handling | Per-wheel spin, suspension, steering, rolling resistance and tire slip/grip over maintained and rough grass. Home offers experimental runway starts for the Stik and Turbo Lumber Evolution. [Ground model](docs/research/ground-physics/GP-05/README.md) |
| Controls | USB radio/gamepad input, saved calibration, throttle arming and disconnection failsafe. Keyboard/gamepad sticks use aircraft-specific normal rates and expo; radios retain their own settings. [Controls and radio setup](docs/FIRST-LAUNCH.md#3-fly) |
| Cameras | Ground pilot, chase, mouse-controlled orbit and close-up views, manual zoom, auto-zoom and a ground-shadow aid. **C / Shift+C** cycle views; right-drag rotates the orbit camera. [View controls](docs/FIRST-LAUNCH.md#3-fly) |
| Flight overlays | Separate flight data, transmitter sticks/trims, warnings, wind, telemetry, diagnostics and performance panels. **F2** cycles presets; Pause → Flight overlays selects panels, units and transmitter Mode 1/2. [Overlay guide](docs/plans/flight-overlays.md) |
| Weather | Editable wind, repeating gusts, seeded turbulence, field elevation, temperature, QNH and humidity. Restart repeats the selected conditions. [Wind](docs/WIND-PLAN.md) · [Atmosphere](docs/ATMOSPHERE-PLAN.md) |
| Lighting | Day, dawn, dusk, night and passing evening, with editable time/date/location. Stars, moonlight, runway/club lamps and experimental aircraft lights support night practice. Visual time remains separate from physical weather. [Time of day](docs/TIME-OF-DAY-PLAN.md) |
| Field and scenery | Detailed turf and near grass, trees and horizon, club buildings, parked aircraft, textured vehicles, animated people, birds, sun glare and night lighting. [Landscape delivery](docs/research/landscape-upgrade/LU-21/README.md) |
| Audio | Positional combustion, electric and turbine voices, propeller/airframe sound, wind, foliage and wildlife. Doppler follows aircraft and listener motion; PCM loop continuity has been repaired. [Audio](docs/AUDIO-PLAN.md) · [Recent audio work](docs/plans/audio-realism.md) |
| Smoke | Faint Stik glow exhaust plus an optional white smoke trail, drifting with the configured wind. **H** toggles the pump on keyboard; **J** assigns a radio AUX control. [Smoke feature](docs/SMOKE-PLAN.md) |
| Collisions and crashes | Approximate tree/prop/building collision proxies, severity-dependent wrecks, debris, marks, fire/smoke and crash audio. Lightweight scenery and fence pieces can break; major structures remain. The aftermath persists until Restart. [Crash scope](docs/CRASH-DAMAGE-PLAN.md) |
| Menus and settings | English/Spanish Home and Help, saved aircraft/weather/lighting choices, pause on focus loss and an exported-build update notice with manual downloads. [Player guide](docs/FIRST-LAUNCH.md) |
| Recording and diagnostics | Flight CSV traces, complete-state checkpoints/replay, controller reports, frame-time/physics benchmarks, a filmed-latency marker and deterministic captures. [Tools and commands](docs/TOOLS.md) |

Takeoff/landing calibration, controller compatibility, target-machine performance and pilot readability still require acceptance. Collision proxies, damage thresholds and wreck deformation are engineering estimates; flyable aircraft structural damage remains unimplemented. The [roadmap](ROADMAP.md) records the remaining gates.

![Ugly Stik flying over the field](docs/media/flight.png)

| Field by day | Runway at night |
| --- | --- |
| ![Aerial view of the club, runway, parking and trees](docs/research/landscape-upgrade/LU-21/evidence/final-after-day/aerial_overview.png) | ![Illuminated runway threshold and club at night](docs/research/landscape-upgrade/LU-21/evidence/final-after-night/runway_threshold.png) |

These are unedited Godot captures from the [landscape verification](docs/research/landscape-upgrade/LU-21/README.md).

## In development

- **RC helicopters:** initial rotor inflow and swashplate kernels exist, with isolated swashplate verification. Aircraft data, full-session integration and a flyable helicopter remain ahead. [Helicopter track](docs/plans/helicopter.md) · [Swashplate evidence](docs/research/helicopter/HELI-13/README.md)
- **FPV drone racing:** vehicle, controller and race-mode design/research are underway, using the shared rotor foundations. A flyable drone and playable race mode are planned. [Drone track](docs/plans/drone-racing.md)
- Further camera modes, audio realism, menu redesign and desktop delivery are tracked in the [documentation map](docs/README.md#tracks-plans-and-step-ids).

## Develop and contribute

The simulator lives in `app/`, using pinned **Godot 4.7.2**, GDScript and the Compatibility renderer. Its own float64 flight solver runs at 240 Hz. `prototypes/stage0/three/` is the frozen platform bake-off.

Aircraft use the strict `openrc-aircraft v2` contract: quantities include units, evidence and sources, and invalid configurations are refused. Geometry and physics data are rebuilt through their source generators. Headless regression tests, golden flights, schema/trace checks, rendered captures and export smoke checks support incremental changes.

- [Setup, commands, tests and exports](docs/TOOLS.md)
- [Architecture and stack](STACK.md)
- [Documentation and ownership map](docs/README.md)
- [Contributing](CONTRIBUTING.md) · [Repository guidance](AGENTS.md)
- [Roadmap and acceptance gates](ROADMAP.md) · [Decisions](DECISIONS.md) · [Lessons](LEARNINGS.md)

For feedback, include build identity, aircraft, operating system and controller, then describe the maneuver or failure. [Pilot feedback](https://github.com/bultodepapas/OpenRCsimulator/issues/new?template=pilot_feedback.md) · [Bug report](https://github.com/bultodepapas/OpenRCsimulator/issues/new?template=bug_report.md).

## License

Project code is [MIT](LICENSE). Third-party assets retain their licenses; [landscape provenance](assets/landscape/PROVENANCE.json), [scenery provenance](assets/scenery/PROVENANCE.json), [field asset credits](app/assets/landscape/UPGRADE_CREDITS.md), [tree license](app/assets/landscape/trees/LICENSE.txt) and [media provenance](docs/media/README.md) identify retained sources. Reference scans with unclear redistribution rights are not bundled.

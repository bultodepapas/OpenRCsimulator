# OpenRC Simulator

**[Explore the project website](https://bultodepapas.github.io/OpenRCsimulator/)** — aircraft, field, downloads and project details in English and Spanish.

> [!NOTE]
> **Thank you, OpenAI, for supporting open source.**
>
> I'm grateful to [OpenAI](https://openai.com/) for providing a **ChatGPT Pro subscription** to support my open-source projects, including OpenRC Simulator. That support gives me more room to build, experiment and share this work with the RC community.
>
> **AI development contributor:** [Codex by OpenAI](https://openai.com/codex/).

An open-source RC airplane simulator for a USB transmitter, gamepad or keyboard. Fly from the pilot's position on the field, or use chase, orbit and close-up views. **Early alpha:** automated checks verify the software; flight models still need independent RC measurements and pilot validation.

![Rotating studio tour: Ventage Jet, helicopter, two RC trucks and four more airplanes](docs/media/aircraft-tour.gif)

Eight vehicles in a full 360° studio tour: Ventage Jet first, followed by the helicopter, Bisonte MT8, MONSTER CAR 2 and the other four airplanes. [Still views and render provenance](docs/media/README.md#aircraft-stills).

## Download and fly

[Download v0.1.3](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.3) for Windows, Linux or macOS. Extract the ZIP and launch the executable. Godot is not required for a downloaded build. Packages are unsigned; see the [first-launch guide](docs/FIRST-LAUNCH.md) for checksums, platform setup, controls and radio calibration.

**First flight:** new Home preferences start on the Stik runway with gentle wind and passing evening; saved choices take precedence. Select **Airborne**, **Calm** and **Day** for trimmed airborne practice. [Player guide and controls](docs/FIRST-LAUNCH.md).

The aircraft and features below describe **current source**, which may differ from the download. The [v0.1.3 release notes](docs/releases/v0.1.3.md) describe that package and its known limits. Software checks do not establish physical flight validation.

## Aircraft

| Aircraft | Configuration | Status |
| --- | --- | --- |
| [Jensen Das Ugly Stik 60](docs/UGLY-STIK-PLAN.md) | 1.52 m, .61 glow, tricycle gear | Reference model under evaluation |
| [Great Planes Extra 300S .60](docs/EXTRA-300-PLAN.md) | 1.63 m, .61 glow, taildragger | Experimental |
| [P-51D Mustang 1/4](docs/P51-PLAN.md) | 2.82 m, 120 cc gasoline, retractable taildragger gear | Experimental; simulated flaps and retracts |
| [Ventage Jet](docs/AVANTI-S-PLAN.md) | 2.00 m, JetCat P100-RX turbine | Experimental; simulated flaps and retracts |
| [Turbo Lumber Evolution](docs/TIMBER-INTEGRATION-PLAN.md) | 1.55 m, 4S electric, fixed wheels | Experimental; finite battery by default, optional ideal supply; flaps up, assists off |
| [RC Helicopter Research Trainer](docs/HELICOPTER.md) | X-Cell .60 SE flight reference with an HX-700 visual surrogate | Experimental historical playable reference; ground-pad or hover start; physical validation remains open |

All five fixed-wing airframes offer runway or airborne starts. The Stik also has three experimental [glow-engine installations](docs/GLOW-ENGINES.md): O.S. MAX-61FX and MAX-55AX two-strokes, and FS-64V four-stroke, with finite fuel and engine start/cut/mixture controls. These share the Stik visual family.

The playable helicopter uses X-Cell reference physics. The articulated HX-700 inspector and electric 3D candidate are separate research tools; the candidate is laboratory-only. Aircraft-specific controls and modeling limits live in the linked guides.

## Current features

| Area | Available in current source |
| --- | --- |
| Flight physics | Custom float64 six-degree-of-freedom solver at 240 Hz, with trim, local aerodynamic loads, stalls/spins and servo dynamics. Aircraft, helicopter and ground-vehicle sessions use the [shared kernel](docs/STACK.md#boundaries-and-data-flow) with vehicle-specific models. [Aircraft contract](docs/AIRCRAFT_CONTRACT.md) |
| Propulsion | Glow and gasoline propellers, coupled electric motor/ESC/battery models, experimental finite-fuel two-/four-stroke glow installations, and a spooling turbine. Torque, gyroscopic effects, P-factor and propwash are enabled by aircraft data where configured. [Propulsion](docs/PROPULSION-CORE-PLAN.md) · [Glow engines](docs/GLOW-ENGINES.md) · [Electric models](docs/ELECTRIC-PROPULSION-PLAN.md) |
| Ground handling | Per-wheel spin, suspension, steering, rolling resistance and tire slip/grip over maintained and rough grass. Runway starts remain experimental. [Ground model](docs/research/ground-physics/GP-05/README.md) |
| Controls | Keyboard, controller profiles/remapping, radio calibration, low-throttle arming and disconnection failsafe. Keyboard/gamepads use configured rates and curves; radios retain transmitter settings. [Controls and radio setup](docs/FIRST-LAUNCH.md#3-fly) |
| Cameras | Ground pilot, chase, mouse-controlled orbit and close-up views, manual zoom, auto-zoom and a ground-shadow aid. **C / Shift+C** cycle views; right-drag rotates the orbit camera. [View controls](docs/FIRST-LAUNCH.md#3-fly) |
| Flight overlays | Flight data, sticks/trims, warnings, wind, device-aware controls, telemetry and diagnostics. **F2** cycles presets; Pause → Flight overlays selects panels and units. [Overlay guide](docs/plans/flight-overlays.md) |
| Weather and sky | Editable physical wind, repeating gusts, seeded turbulence, field elevation, temperature, QNH and humidity. Separate sky profiles add cloud motion and electrical-storm presentation; they do not add spatial storm forces. Restart repeats selected flight conditions. [Wind](docs/WIND-PLAN.md) · [Atmosphere](docs/ATMOSPHERE-PLAN.md) · [Field world](docs/FIELD-WORLD-PLAN.md#sky-and-cloud-controls) |
| Lighting | Day, dawn, dusk, night and passing evening; editable time/date/location, field lamps, campfire, stars and moonlight. Visual time is separate from physical weather. [Time of day](docs/TIME-OF-DAY-PLAN.md) · [Field world](docs/FIELD-WORLD-PLAN.md#night-field-and-campfire) |
| Field and scenery | Grass, vegetation, lake, club buildings, parked aircraft/vehicles, people and birds. Contacts remain engineering models; water impacts do not simulate buoyancy. [Landscape status and evidence](docs/LANDSCAPE-PLAN.md#landscape-integration) |
| Audio | Positional combustion/electric/turbine, propeller/airframe, wind and wildlife sound, with Doppler, propagation delay and air absorption. [Audio](docs/AUDIO-PLAN.md) · [Audio realism](docs/plans/audio-realism.md) |
| Smoke | Faint Stik glow exhaust plus an optional white smoke trail, drifting with the configured wind. **H** toggles the pump on keyboard; **J** assigns a radio AUX control. [Smoke feature](docs/SMOKE-PLAN.md) |
| Collisions and crashes | Approximate collision proxies, wrecks, debris, fire/smoke and a component damage/cost report. Prices and repair outcomes are estimates. Aftermath persists until Restart. [Crash scope](docs/CRASH-DAMAGE-PLAN.md) |
| Menus and settings | English/Spanish Home and Help, saved aircraft/weather/lighting choices, pause on focus loss, and Settings for window mode, interface scale, opaque panels, reduced motion, game volume and menu volume. Aircraft Workshop trials, Natural Random briefings and optional fixed-wing emergency practice are also available. [Player guide](docs/FIRST-LAUNCH.md) · [Workshop](docs/AIRCRAFT-WORKSHOP.md) · [Natural Random](docs/plans/natural-random-flight.md) · [Failure practice](docs/plans/failure-mode.md) |
| Recording and diagnostics | **F10** records fixed-wing flights; **F11** marks maneuvers. [Export CSV, verify exact replay and compare candidate physics](docs/FLIGHT-LOGGING.md). Separate helicopter/truck recorders, controller reports, captures and a source-only [flight-test card](research/flight-test/README.md) support investigations. [Tools and commands](docs/TOOLS.md) |

Takeoff/landing calibration, controller compatibility, target-machine performance and pilot readability still require acceptance. Collision proxies, damage thresholds and wreck deformation are engineering estimates; flyable aircraft structural damage remains unimplemented. The [roadmap](ROADMAP.md) records the remaining gates.

![Ugly Stik flying over the field](docs/media/flight.png)

| Field by day | Runway at night |
| --- | --- |
| ![Aerial view of the club, runway, parking and trees](docs/research/landscape-upgrade/LU-21/evidence/final-after-day/aerial_overview.png) | ![Illuminated runway threshold and club at night](docs/research/landscape-upgrade/LU-21/evidence/final-after-night/runway_threshold.png) |

These are unedited Godot captures from the [landscape verification](docs/research/landscape-upgrade/LU-21/README.md).

## Other experimental activities

- **RC monster truck:** experimental Bisonte MT8 and MONSTER CAR 2 vehicles share a garage and driving course, with separate vehicle sessions and replay. MONSTER CAR 2 adds nitro propulsion and fuel state. Physical accuracy and target-machine performance remain unqualified. [Operating and research guide](research/rc-monster-truck/README.md)
- **FPV drone racing:** a research-grade multirotor plant uses the shared simulation kernel and rotor foundations. A playable drone, FPV activity and race mode are not yet implemented. [Drone track](docs/plans/drone-racing.md)
- Further aircraft, camera, audio, menu and desktop qualification remains in the [documentation map](docs/README.md#tracks-plans-and-step-ids).

## Partners

Thank you to these manufacturers for authorizing product representations in OpenRC Simulator.

| Savox | SonicModell | Hitec RCD |
| --- | --- | --- |
| [<img src="site/assets/brands/savox/TeamSavox-Logo-Mono-Black.webp" alt="Savox" width="180">](https://www.teamsavox.com/) | [<img src="site/assets/brands/sonicmodell/sonicmodell-logo.png" alt="SonicModell" width="180">](https://www.sonicmodell.com/) | [<img src="site/assets/brands/hitec/hitec-radio-logo-footer.png" alt="Hitec RCD" width="180">](https://www.hitecrcd.com/) |
| Product representations authorized; engineering contact offered. [Servo catalogue integration is planned](docs/plans/savox-servos.md). | Appearance, names and branding authorized for the models covered by our request, including Skyhunter models. Integration is pending. | Servos published on Hitec websites may be featured with official product links. Integration is pending. |

Permissions have specific scopes; they do not imply financial sponsorship or validation of our physical models. Brand assets remain outside the MIT code license. [Permission scope and logo sources](site/BRANDS.md).

## Develop and contribute

The simulator lives in `app/`, using pinned **Godot 4.7.2**, GDScript and the Compatibility renderer. Start with [developer setup and commands](docs/TOOLS.md#developer-setup). `prototypes/stage0/three/` is the frozen platform bake-off.

Aircraft use the strict `openrc-aircraft v2` contract: quantities include units, evidence and sources, and invalid configurations are refused. Geometry and physics data are rebuilt through their source generators. Headless regression tests, golden flights, schema/trace checks, rendered captures and export smoke checks support incremental changes.

- [Setup, commands, tests and exports](docs/TOOLS.md)
- [Architecture and stack](docs/STACK.md)
- [Aircraft data and authoring contract](docs/AIRCRAFT_CONTRACT.md)
- [Documentation and ownership map](docs/README.md)
- [Original source deliveries and current asset references](assets/source-deliveries/README.md)
- [Contributing](CONTRIBUTING.md) · [Repository guidance](AGENTS.md)
- [Roadmap and acceptance gates](ROADMAP.md) · [Decisions](docs/DECISIONS.md) · [Lessons](docs/LEARNINGS.md)

For feedback, include build identity, aircraft, operating system and controller, then describe the maneuver or failure. [Pilot feedback](https://github.com/bultodepapas/OpenRCsimulator/issues/new?template=pilot_feedback.md) · [Bug report](https://github.com/bultodepapas/OpenRCsimulator/issues/new?template=bug_report.md).

## License

Project code is [MIT](LICENSE). Third-party assets retain their licenses; [landscape provenance](assets/landscape/PROVENANCE.json), [scenery provenance](assets/scenery/PROVENANCE.json), [field asset credits](app/assets/landscape/UPGRADE_CREDITS.md), [tree license](app/assets/landscape/trees/LICENSE.txt) and [media provenance](docs/media/README.md) identify retained sources. Reference scans with unclear redistribution rights are not bundled.

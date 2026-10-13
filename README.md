# OpenRC Simulator

An open-source RC airplane simulator for a USB transmitter, gamepad or keyboard, viewed from the pilot's position on the field. **Early alpha:** automated checks verify the software; flight models still need independent RC measurements and pilot validation.

![Ugly Stik flying over the field](docs/media/flight.png)

## Download and fly

[Download the rc8 alpha](https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc8) for Windows, Linux or macOS. Extract the ZIP and launch the executable. Godot is not required for a downloaded build. Packages are unsigned; see the [first-launch guide](docs/FIRST-LAUNCH.md) for platform setup, controls, radio calibration and diagnostics.

**rc8 first flight:** new Home preferences start on the Stik runway with gentle wind and passing evening; saved choices take precedence. [Release notes](docs/releases/v0.1.0-rc8.md) describe the download; the [player guide](docs/FIRST-LAUNCH.md#current-source) explains the flight setup.

## Aircraft

| Aircraft | Configuration | Status |
| --- | --- | --- |
| [Jensen Das Ugly Stik 60](docs/UGLY-STIK-PLAN.md) | 1.52 m, .61 glow, tricycle gear | Reference model under evaluation; Home offers airborne or experimental runway start |
| [Great Planes Extra 300S .60](docs/EXTRA-300-PLAN.md) | 1.63 m, .61 glow, taildragger | Experimental |
| [P-51D Mustang 1/4](docs/P51-PLAN.md) | 2.82 m, 120 cc gasoline, taildragger | Experimental |
| [Ventage Jet](docs/AVANTI-S-PLAN.md) | 2.00 m, JetCat P100-RX turbine | Experimental; airborne, flaps and gear up |
| [Turbo Lumber Evolution](docs/TIMBER-INTEGRATION-PLAN.md) | 1.55 m, 800 Kv, 4S electric, fixed wheels | Experimental; flaps up, assists off |

Current source includes six-degree-of-freedom flight, stalls/spins, servos, combustion and electric propeller dynamics, turbine dynamics, wheel contact, wind/gusts/turbulence, field atmosphere, selectable lighting, scenery, audio and crash presentation. Static scenery collision proxies and wreck presentation use engineering estimates; flyable structural damage remains unimplemented. Takeoff/landing, controller compatibility and target-machine performance require further acceptance. Turbo Lumber Evolution flies with estimated motor losses and a borrowed two-blade propeller map; its fixed bus does not model battery depletion.

## Develop and contribute

The simulator lives in `app/`, using pinned **Godot 4.7.2**, GDScript and the Compatibility renderer. Its own float64 flight solver runs at 240 Hz. `prototypes/stage0/three/` is the frozen platform bake-off.

- [Setup, commands, tests and exports](docs/TOOLS.md)
- [Architecture and stack](STACK.md)
- [Documentation and ownership map](docs/README.md)
- [Contributing](CONTRIBUTING.md) · [Repository guidance](AGENTS.md)
- [Roadmap and acceptance gates](ROADMAP.md) · [Decisions](DECISIONS.md) · [Lessons](LEARNINGS.md)

For feedback, include build identity, aircraft, operating system and controller, then describe the maneuver or failure. [Pilot feedback](https://github.com/bultodepapas/OpenRCsimulator/issues/new?template=pilot_feedback.md) · [Bug report](https://github.com/bultodepapas/OpenRCsimulator/issues/new?template=bug_report.md).

## License

Project code is [MIT](LICENSE). Third-party assets retain their licenses; [asset provenance](assets/landscape/PROVENANCE.json), [tree license](app/assets/landscape/trees/LICENSE.txt) and [media provenance](docs/media/README.md) identify retained sources. Reference scans with unclear redistribution rights are not bundled.

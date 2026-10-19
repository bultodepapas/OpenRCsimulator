# Architecture and stack

Status: current implementation, checked 2026-10-14. Runtime settings live in [project.godot](app/project.godot); the exact engine version and SHA-512 are pinned by [get-godot.sh](app/get-godot.sh). Setup and commands: [TOOLS](docs/TOOLS.md).

## Runtime

| Layer | Implementation |
| --- | --- |
| Engine/language | Official Godot 4.7.2-stable; GDScript, with an optional pinned C++ ground-vehicle evaluator |
| Rendering | Compatibility, `opengl3`; 1280×720 default viewport, 4× MSAA |
| Simulation | Custom float64 six-degree-of-freedom solver and RK4 at 240 Hz; Godot rigid-body nodes do not solve flight |
| Aircraft | Catalog JSON `openrc-aircraft v2` with strict validation, per-quantity units/evidence/source and derived mass/CG/inertia; historical v1 is explicit compatibility; [contract](AIRCRAFT_CONTRACT.md) |
| Input | Physical keyboard keys and raw joystick axes, device calibration and throttle arming |
| Product shell | Home, Settings, Help, pause and conditions editors; shared screen stack and native canvas UI scaling; English source text and Spanish gettext catalog |
| Audio | Positional engine sources plus wind/foliage/wildlife soundscape; original PCM assets and procedural mixing |
| Delivery | Windows x86_64, Linux x86_64 and macOS universal ZIP exports; build identity embedded by an export plugin |
| Checks | Headless GDScript tests, Python schema/trace/tool checks, golden flights, rendered captures and package smoke checks |

Flight physics has no third-party native solver dependency. The experimental Bisonte MT8 ground activity can use the repository's float64 C++ evaluator through GDExtension, with the GDScript implementation retained as its reference and fallback. Its [pinned builder and qualification](research/rc-monster-truck/native/README.md) own Windows/Linux artifacts generated into ignored `app/native/ground_vehicle/`; macOS uses the reference path. Other C++ experiments remain separate from the application. Python, Node, SciPy and asset-generation packages are development tools with per-tool pins. The archived three.js build retains its lockfile and [platform comparison](prototypes/stage0/COMPARISON.md).

## Boundaries and data flow

`app_root.tscn` loads `app_root.gd`. With no user arguments, the app opens Home and reads validated preferences. `--input-report` starts standalone diagnostics; `--vehicle=mt8-bisonte` or `--vehicle=monster-car-2` selects the separate truck activity; other user arguments select a technical flight. Technical routes ignore Home preferences. The selected catalog ID chooses the fixed-wing or helicopter route.

Home's RC car selector starts a separate paused ground-vehicle garage for Bisonte MT8 or MONSTER CAR 2. Its Session installs the car's `VehicleModel` into the shared `Simulation` kernel, which owns the 31-value float64 state (13-value body plus 18 coupled values) and the fixed 240 Hz ticks; the Session keeps experiments, recovery, recording and checkpoint identity. The [nitro adapter](research/rc-monster-truck/monster-car-2/README.md) adds engine speed and fuel mass to form a 33-value state and couples its midpoint powertrain update to the existing RK4 body step. Rendering articulates the supplied Blender models from detached state. Native and reference body backends share equations and road samples; checkpoints pin the selected vehicle and implementation and cannot switch them during replay. [Controls and research tools](research/rc-monster-truck/README.md#rcv-05-full-vehicle-runtime-experiments).

The aircraft catalog resolves one ID to matching physics data and its visual builder. The loader validates the configuration and derives the normalized model before `FlightSession` accepts it. A failed initial preparation refuses flight; a failed reload retains the accepted session.

The explicit experimental rotorcraft ID selects a dedicated quantity reader/schema, `HelicopterFlightSession` and `RotorcraftRecorder`, reusing `Simulation` for joint float64 body/shaft/wake/controller integration. The supplied HX-700 Blender visual and X-Cell reference physics are a declared surrogate; physical and performance qualification remain open. [Current helicopter controls and limits](docs/HELICOPTER.md).

Input is sampled before each simulation tick. `FlightSession` owns trim/start, controls, environment, pause/reset/crash, accepted aircraft and state identity. `Simulation` commits fixed ticks for the one `VehicleModel` (`app/sim/vehicle_model.gd`) its session installs; the model declares the state layout, supplies read-only stage evaluators and may declare one tick event that the kernel locates (`app/physics/event_step.gd`); located events are recorded per tick. Physics modules evaluate rigid-body, actuator, propulsion and contact state. Finite resources such as fuel change mass, CG and inertia about a fixed body datum through one shared kernel: `MassInventory.prepare_reference/evaluate_reference` (`app/physics/mass_inventory.gd`) and `FixedDatumBody.derivative` (`app/physics/fixed_datum_body.gd`, co-moving efflux). Fuel densities come from `app/data/fuels/openrc-fuel-registry.json` ([FUEL-02/04](docs/plans/fuel-mass-balance.md)). A finite electric pack keeps its mass: the `pack_ecm` law (`app/physics/battery/`) carries charge, RC polarization, temperature and the sampled ESC cutoff in the session's continuous block, with generated pack data in `app/data/batteries/` ([BAT-04](docs/research/battery/BAT-04/specification.md)). RK stages use their stage time and state. Checkpoints retain complete replay state; CSV traces are versioned diagnostics with declared sampling times.

Two event locators serve the kernel, both fourth order ([SF-04b](docs/research/simulation-foundation/SF-04b/README.md)). The declared-event locator evaluates RK stages beyond the boundary while it brackets a crossing, so its law must continue smoothly there (electric shafts; the battery and glow policies nest it). A law that refuses the far side keeps a domain-guarded step policy: the rotorcraft adapter (`app/physics/rotorcraft/simulation_step_adapter.gd`) never evaluates Ω < 0. A step policy owns its whole tick and is never split into contact substeps; the kernel refuses a policy tick that asks for more than one (SF-05 substeps apply to the kernel's own RK4 and the declared-event locator).

A native backend may replace exactly one evaluation boundary (`VehicleModel.stage`, or the ground vehicle's evaluator), never the tick transaction; RK stages, substeps, events, checkpoints and faults stay in the kernel. It declares ABI and backend versions, its build receipt pins the toolchain and library hashes, and checkpoints pin the active backend so replay refuses a switch. Adoption needs a byte-identical oracle comparison on at least ten thousand states including malformed inputs, exact multi-tick kernel trajectories, the fleet fingerprints and p50/p95 tick cost on the owner's target host. The reference GDScript path is selected whenever the binary, receipt or identity is missing or mismatched; macOS is reference-only and nothing in the catalog may depend on a native backend. A fixed-wing port starts only when the optimized GDScript tick still exceeds the 500 µs budget on the target host, by owner decision ([SF-08](DECISIONS.md)).

Simulation positions use NED (north/east/down), body vectors use FRD (forward/right/down), and attitudes map body to NED. Scalar doubles and packed float64 arrays remain inside physics. `render/frames.gd` converts detached state into Godot's render vectors and attitude. Aircraft geometry, forces and controls share the declared datum and hinge contract.

The Workshop compiler builds a detached candidate from validated aircraft data, exposes only operations supported by that aircraft's modules, and freezes the accepted candidate for a test flight. Natural Random resolves an airplane, start, physical weather and visual conditions into a repeatable scenario. Optional failure practice is currently a fixed-wing session feature; its saved settings default to off.

The renderer composes the field, sky, lighting and scenery. Physical weather controls air velocity/density; each session queries wind, air, terrain, water and course through one environment contract (`app/sim/environment.gd`). Visual lighting has its own configuration and history. Visual time changes do not change flight weather. Collision proxies are scalar geometry consumed by the simulation, with scenery rendering and response kept separate.

## Repository layout

| Path | Responsibility |
| --- | --- |
| `app/app_root.*`, `app/ui/`, `app/app_state/`, `app/i18n/` | Product shell, catalog, preferences, localization and build information |
| `app/sim/`, `app/physics/`, `app/input/` | Fixed-wing, rotorcraft and ground-vehicle sessions; float64 state/replay; flight equations and control devices |
| `app/workshop/`, `app/scenarios/`, `app/failures/` | Validated aircraft variants, resolved random-flight scenarios and optional fixed-wing failure practice |
| `app/data/` | Aircraft, contracts/schemas, ground profiles, field, scenery and sky configuration |
| `app/aircraft/`, `app/render/`, `app/environment/`, `app/scenery/`, `app/audio/` | Aircraft models, presentation, lighting context, field life and sound |
| `app/assets/` | Runtime assets and bundled third-party licenses |
| `app/tests/` | Headless tests, trace/capture verification and benchmarks |
| `assets/` | Authored source geometry, generators and provenance |
| `tools/` | Reusable asset, visual, capture and qualification workflows |
| `research/` | Reproducible experiments, derivations, data generators and measurement reducers |
| `docs/` | Current guides, active plans, dated evidence and sources; [map](docs/README.md) |
| `tmp/`, `.playwright-mcp/` | Ignored local scratch outputs and browser sessions; retain accepted sources and evidence under `docs/research/` |
| `prototypes/stage0/` | Frozen bake-off specification, comparison and three.js prototype |
| `Timber turbo evolution/` (historical source); `Timber Trubo Evolucion V2 BLENDER/turbo_timber_evolution_r2/r2/` (current delivery) | The immutable r2 package is hash-pinned in the [source manifest](assets/aircraft/turbo-lumber-evolution/source-manifest.json); its runtime GLB copy is loaded through `app/aircraft/timber_model.gd`. Experimental electric flight data is generated by `research/timber/tt07/derive_physics.py` |

## Limits and upgrades

The engine permits at most 12 catch-up ticks per rendered frame. Below about 20 fps, simulation slows instead of accumulating unlimited work. The 500 µs physics budget on the target machine remains an acceptance gate, not a guaranteed maximum. Aircraft-specific calibration, pilot handling/readability and platform/GPU qualification remain open in [ROADMAP](ROADMAP.md).

Current exports are unsigned ZIPs; installers, fullscreen defaults and web/mobile delivery are not shipped. Current source includes reversible display/accessibility Settings and automatic menu scaling; [menu evidence](docs/research/menu-investigations/UI-22-26-R1/README.md) records its qualification limits. Active proposals are indexed separately in the [documentation map](docs/README.md).

For an engine upgrade, change the pin and hash deliberately, then run app tests, inspect captures and verify exports/CI. Preserve numerical and render baselines unless the change intentionally explains their replacement. The original platform investigation is retained in the [research notebook](docs/research/initial-notebook.md); it does not describe today's dependencies.

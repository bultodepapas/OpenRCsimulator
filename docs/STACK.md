# Architecture and stack

Status: current implementation, checked 2026-10-19. Runtime settings live in [project.godot](../app/project.godot); Godot's exact version and SHA-512 are pinned by [get-godot.sh](../app/get-godot.sh). Setup and commands: [TOOLS](TOOLS.md).

Display development follows the [shared resolution policy](../AGENTS.md#display-resolution-priorities): **1080p primary → above-1080p resolutions (including 4K) secondary desirable → 720p tertiary, last**. The configured default viewport below describes current implementation, not product priority or performance qualification.

## Runtime

| Layer | Implementation |
| --- | --- |
| Engine/language | Official Godot 4.8-beta1; GDScript. Owner-authorized adoption with [local verification](research/engine-upgrade/GDU-03/README.md); broader [platform/release gates](plans/godot-4.8-upgrade.md) remain open |
| Rendering | Compatibility renderer (`gl_compatibility`); 1280×720 default viewport; 4× 3D MSAA |
| Simulation | Shared float64 rigid-body kernel, RK4 and fixed 240 Hz ticks; Godot rigid-body nodes do not solve flight |
| Aircraft data | Strict `openrc-aircraft v2` validation, unit-tagged quantities and derived mass/CG/inertia; v1 is an explicit historical path; [contract](AIRCRAFT_CONTRACT.md) |
| Input and shell | Physical-keyboard controls and radio profiles with device calibration and throttle arming; Home, Settings, Help, pause and flight/vehicle activities |
| Audio | Positional installed powertrain profiles, licensed recording banks, phase-aware glow voices, contact-driven landing gear and field soundscape; [audio guide](AUDIO-PLAN.md) |
| Delivery | Windows x86_64, Linux x86_64 and macOS universal ZIP exports; build identity embedded at export |
| Checks | Headless GDScript and Python checks, golden flights, rendered captures and package smoke checks |

Aircraft flight has no third-party native solver. The experimental RC ground activity can use an optional C++ GDExtension for its evaluator; GDScript remains its reference and fallback, and macOS uses the reference path. The [native build guide](../research/rc-monster-truck/native/README.md) pins its toolchain and artifacts. Python, Node and asset-generation tools are development dependencies pinned in their own manifests. The three.js bake-off is frozen; its lockfile and [comparison](../prototypes/stage0/COMPARISON.md) remain historical.

## Supported vehicle paths

| Vehicle | Runtime status |
| --- | --- |
| Fixed-wing aircraft | Main flight route; aircraft catalog and v2 data contract |
| Helicopter | Experimental route with its own quantity reader, session and recorder. HX-700 visuals and X-Cell reference physics are declared surrogates; physical and performance qualification remain open; [guide](HELICOPTER.md) |
| RC ground vehicle | Experimental Bisonte MT8 and MONSTER CAR 2 activities with a separate data/session contract; qualification remains open; [research and controls](../research/rc-monster-truck/README.md) |
| Multirotor | Physics groundwork and focused tests exist, but there is no runtime session, catalog route or racing activity; see the [active plan](plans/drone-racing.md) |

## Boundaries and data flow

[`ui/startup.tscn`](../app/ui/startup.tscn) presents the official SVG identity on rendered interactive launches, then hands off to [`app_root.tscn`](../app/app_root.tscn), which loads `app_root.gd`. Headless and command-line launches bypass the intro. No user arguments opens Home; `--input-report` starts diagnostics; `--vehicle=mt8-bisonte` and `--vehicle=monster-car-2` start the corresponding ground activity; remaining arguments take the direct-flight route. Direct flights do not read Home preferences. The aircraft catalog routes fixed-wing IDs to `main.tscn` and rotorcraft IDs to the `helicopter_main.gd` activity.

The explicit [landscape catalog](../app/landscapes/catalog.gd) registers Club field (default) and Green paradise. Home remembers a landscape ID and rebuilds its backdrop; flight and Workshop trials receive the same ID and field path. Direct flights resolve `--landscape=<id>` independently. Both flight routes validate field data before building the selected adapter's visuals and matching obstacle inventory. Field surfaces still supply ground contact; the shared kernel has no landscape branches. Selection changes only on Home between flights. [Authoring contract](LANDSCAPES.md).

The fixed-wing, helicopter and ground-vehicle sessions each install one `VehicleModel` into `Simulation`. The model declares the state layout and read-only stage evaluators; the [VehicleModel contract](../app/sim/vehicle_model.gd) defines callback purity, events and substeps. The kernel owns tick validation, integration, event handling, state publication, checkpoints and fault recovery; it does not branch on vehicle type. Sessions and adapters own vehicle data, controls, environment setup and replay identity. The ground activity drives the same kernel through explicit 240 Hz ticks.

The rigid-body state has 13 float64 values; optional continuous state blocks are packed after it for integration. Simulation code uses scalars and packed float64 arrays: positions are NED (north/east/down), body vectors are FRD (forward/right/down), and attitudes map body to NED. Rendering converts detached state at [frames.gd](../app/render/frames.gd). Checkpoint envelopes identify the selected vehicle and law/backend so replay cannot silently switch implementations.

Models may opt into an explicitly sized `state_layout_identity`, a pure `endpoint_transition` and a clock-aware `state_validator`. The kernel commits the complete accepted frame and bounded events atomically after final projection; checkpoint v2 pins that layout. Legacy models retain checkpoint v1. The endpoint context reports whether a body filter changed the integrated trajectory. Prepared-reset commit returns success/failure, which adopting session transactions must honor. [GP-16](research/ground-physics/GP-16/README.md) records the contract and tests; it is a generic kernel capability, not an installed stock-aircraft damage model.

Aircraft data is validated and normalized before `FlightSession` accepts it. Invalid initial data cannot fly, and a failed reload preserves the accepted session. Specialized vehicle paths keep their own schemas and acceptance gates. Physical weather and field queries use [the shared environment contract](../app/sim/environment.gd); visual lighting and time remain separate from flight weather.

Finite-fuel mass, CG and inertia updates use [MassInventory](../app/physics/mass_inventory.gd) and [FixedDatumBody](../app/physics/fixed_datum_body.gd). Fuel and electric-pack design details live in the [fuel standard](FUEL-SYSTEM.md) and [battery specification](research/battery/BAT-04/specification.md).

A native backend may replace one evaluator boundary, never the kernel's tick transaction. Its receipt pins the toolchain, ABI, backend version and library hashes; missing or mismatched artifacts select the GDScript reference path. Adoption requires byte-identical reference agreement on at least 10,000 states including malformed inputs, exact kernel trajectories, fleet fingerprints and target-host p50/p95 tick cost. No catalog entry may require a native backend. A fixed-wing port requires an optimized GDScript workload still exceeding the 500 µs target-host budget and an owner decision; [SF-08](research/simulation-foundation/README.md#6-backend-policy-sf-08) records the policy and evidence.

## Repository layout

| Path | Responsibility |
| --- | --- |
| `app/app_root.*`, `app/ui/`, `app/app_state/`, `app/i18n/` | Product shell, catalog, preferences, localization and build identity |
| `app/sim/`, `app/physics/`, `app/input/` | Sessions, shared kernel, vehicle laws, float64 state/replay and control devices |
| `app/workshop/`, `app/scenarios/`, `app/failures/` | Aircraft variants, resolved flight scenarios and fixed-wing failure practice |
| `app/landscapes/` | Ordered landscape registry, renderers, obstacle inventories and custom field definitions |
| `app/data/` | Aircraft, schemas, ground-vehicle, field, scenery and sky data |
| `app/aircraft/`, `app/render/`, `app/environment/`, `app/scenery/`, `app/audio/` | Vehicle visuals, presentation, lighting, field life and sound |
| `app/assets/`, `app/tests/` | Runtime assets/licenses; tests, trace/capture checks and benchmarks |
| `assets/`, `assets/source-deliveries/` | Authored geometry, generators and provenance; [source-delivery index](../assets/source-deliveries/README.md) |
| `tools/`, `research/` | Reusable workflows, experiments, data generators and measurement reducers |
| `docs/`, `site/` | Current guides, plans, dated evidence and project website; [documentation map](README.md), [site guide](../site/README.md) |
| `tmp/`, `output/`, browser scratch folders | Ignored local outputs; accepted evidence belongs under `docs/research/` or `docs/media/` |
| `prototypes/stage0/` | Frozen bake-off specification, comparison and three.js prototype |

## Limits and upgrades

The engine permits at most 12 catch-up ticks per rendered frame; below about 20 fps, simulation slows instead of accumulating unlimited work. The 500 µs physics budget is an acceptance gate, not a guaranteed maximum. Aircraft calibration, handling/readability and platform/GPU qualification remain open in the [ROADMAP](../ROADMAP.md).

Current packages are unsigned desktop ZIPs. Installers and web/mobile delivery are not shipped. Active proposals and their owners are listed in the [documentation map](README.md).

For an engine upgrade, change the version pin and hash deliberately, then run the app checks, inspect captures and verify exports/CI. Preserve numerical and render baselines unless an intentional change explains replacing them. The original platform investigation is in the [research notebook](research/initial-notebook.md); it records historical evidence, not current dependencies.

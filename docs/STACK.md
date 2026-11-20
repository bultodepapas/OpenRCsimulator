# Architecture and stack

Current implementation guide. Runtime settings live in [project.godot](../app/project.godot); Godot's exact version and SHA-512 are pinned by [get-godot.sh](../app/get-godot.sh). Setup and commands: [TOOLS](TOOLS.md).

Display development follows the [shared resolution policy](../AGENTS.md#display-resolution-priorities): **1080p primary → above-1080p resolutions (including 4K) secondary desirable → 720p tertiary, last**. The configured default viewport below describes current implementation, not product priority or performance qualification.

## Runtime

| Layer | Implementation |
| --- | --- |
| Engine/language | Official Godot 4.8-beta2; GDScript and qualified C++ GDExtensions. Owner-authorized adoption with [beta 2 verification](research/engine-upgrade/GDU-12/README.md); broader [platform/release gates](plans/godot-4.8-upgrade.md) remain open |
| Rendering | Project renderer Compatibility (`gl_compatibility`), a [frozen legacy path](DECISIONS.md#compatibility-is-a-frozen-legacy-renderer) kept for weak GPUs, fallback and CI captures; Automatic selects Forward+ (High) on capable Windows/Linux GPUs; Mobile on native Metal for Apple Silicon (`rendering_method.arm64`, with a [renderer guard](../app/app_state/renderer_guard.gd)); 1280×720 default viewport; 4× 3D MSAA |
| Simulation | Shared float64 rigid-body kernel, RK4 and fixed 240 Hz ticks; Godot rigid-body nodes do not solve flight |
| Aircraft data | Strict `openrc-aircraft v2` validation, unit-tagged quantities and derived mass/CG/inertia; v1 is an explicit historical path; [contract](AIRCRAFT_CONTRACT.md) |
| Input and shell | Physical-keyboard controls and radio profiles with device calibration and throttle arming; Home, Settings, Help, pause and flight/vehicle activities |
| Audio | Positional installed powertrain profiles, licensed recording banks, phase-aware glow voices, contact-driven landing gear and field soundscape; [audio guide](AUDIO-PLAN.md) |
| Delivery | Windows x86_64, Linux x86_64 and macOS universal ZIP exports; build identity embedded at export |
| Checks | Headless GDScript and Python checks, golden flights, rendered captures and package smoke checks |

Ordinary aircraft flights request the in-house NK-3 C++ evaluator through the existing `VehicleModel` callbacks. ABI 2 prepares supported fixed-wing propulsion families and helicopter configurations, with native weather evaluation and configuration guards. Actual selection depends on the platform, validated configuration and verified artifacts; the [native guide](../research/native-kernel/README.md#normal-flight-backend-selection) owns coverage, refused or unqualified cases, Linux/Windows packaging and checkpoint/replay identity. Refused native preparation leaves reference callbacks in place; model admission can still refuse the start. `--physics-backend=gdscript_reference` selects reference explicitly, as required by the servo-interval law. Low-level sessions default to reference for tools and replay. A supported family or historical fleet pass does not qualify every current aircraft/start/weather combination.

The [Apple Silicon source-editor route](../research/native-kernel/README.md#experimental-macos-arm64) automatically admits screened stock fixed-wing configurations with matching engine, library and source identities. Since [DT-MAC-11a](DECISIONS.md#default-to-native-physics-on-supported-apple-silicon-flights), a performance-promotion marker is optional for that route; domain and live configuration guards remain required. Public Mac packages retain reference physics; native package, audio-enabled shutdown and full-scene target-hardware qualification keep their separate gates.

The experimental RC ground activity can use an optional C++ GDExtension for its evaluator; GDScript remains its reference and fallback, and macOS uses the reference path. The [native build guide](../research/rc-monster-truck/native/README.md) pins its toolchain and artifacts. Python, Node and asset-generation tools are development dependencies pinned in their own manifests. The three.js bake-off is frozen; its lockfile and [comparison](../prototypes/stage0/COMPARISON.md) remain historical.

## Supported vehicle paths

| Vehicle | Runtime status |
| --- | --- |
| Fixed-wing aircraft | Main flight route; aircraft catalog and v2 data contract |
| Helicopter | Experimental route with its own quantity reader, session and recorder. HX-700 visuals and X-Cell reference physics are declared surrogates; physical and performance qualification remain open; [guide](HELICOPTER.md) |
| RC ground vehicle | Experimental Bisonte MT8 and MONSTER CAR 2 activities with a separate data/session contract; qualification remains open; [research and controls](../research/rc-monster-truck/README.md) |
| RC airship | Experimental 5 m blimp in Home's vehicle catalog (its skins are its paints), with its own session, presentation, Workshop and flight log; [software evidence and limits](research/rc-airship/BL-12/README.md) |
| Multirotor | Experimental FPV quad in Home's vehicle catalog, with closed-loop flight, a local three-lap gate race and replay; [software evidence and limits](research/drone-racing/M1-M3-2026-11-11/README.md) |

## Boundaries and data flow

[`ui/startup.tscn`](../app/ui/startup.tscn) presents the official SVG identity on rendered interactive launches, then hands off to [`app_root.tscn`](../app/app_root.tscn), which loads `app_root.gd`. Headless and command-line launches bypass the intro. No user arguments opens Home; `--input-report` starts diagnostics; `--vehicle=mt8-bisonte` and `--vehicle=monster-car-2` start the corresponding ground activity; remaining arguments take the direct-flight route. Direct flights do not read Home preferences. The aircraft catalog routes fixed-wing IDs to `main.tscn` and rotorcraft IDs to the `helicopter_main.gd` activity.

The explicit [landscape catalog](../app/landscapes/catalog.gd) registers Club field (default) and Green paradise. Home remembers a landscape ID and rebuilds its backdrop; flight and Workshop trials receive the same ID and field path. Direct flights resolve `--landscape=<id>` independently. Both flight routes validate field data before building the selected adapter's visuals and matching obstacle inventory. Field surfaces still supply ground contact; the shared kernel has no landscape branches. Selection changes only on Home between flights. [Authoring contract](LANDSCAPES.md).

The fixed-wing, helicopter and ground-vehicle sessions each install one `VehicleModel` into `Simulation`. The model declares the state layout and read-only stage evaluators; the [VehicleModel contract](../app/sim/vehicle_model.gd) defines callback purity, events and substeps. The kernel owns tick validation, integration, event handling, state publication, checkpoints and fault recovery; it does not branch on vehicle type. Sessions and adapters own vehicle data, controls, environment setup and replay identity. The ground activity drives the same kernel through explicit 240 Hz ticks. The experimental FPV quad ([session](../app/sim/multirotor/session.gd), [plant](../app/physics/multirotor/controlled_plant.gd)) is the first closed-loop vehicle: its model selects the opt-in `framed-sampled-v1` protocol, in which the kernel samples the flight controller once per tick on the detached accepted frame and hands that one sample to every stage, so controller memory lives only in the checkpointed arrays. Local gate racing [wraps](../app/sim/race/race_model.gd) that model and keeps race state in the same tick transaction.

The rigid-body state has 13 float64 values; optional continuous state blocks are packed after it for integration. Simulation code uses scalars and packed float64 arrays: positions are NED (north/east/down), body vectors are FRD (forward/right/down), and attitudes map body to NED. Rendering converts detached state at [frames.gd](../app/render/frames.gd). Checkpoint envelopes identify the selected vehicle and law/backend so replay cannot silently switch implementations.

The optional `joint-interval-v1` protocol transports detached before/after sampled arrays, modes, inputs and the outer clock to joint stages and a contextual step policy. It retains `pre_tick` sampling and requires an explicit layout. Reset evaluation uses equal before/after arrays and zero duration. Contexts are read-only; repeated stages do not resample; checkpoint v2 pins the protocol. Stock vehicles retain their existing protocol. The separate `joint-interval-local-v1` supplies a tick origin, piece origin and piece phase without collapsing short servo intervals into an absolute-clock ULP. Its owning policy retains absolute public event times and rejects unresolved event chronology. The explicitly selected fixed-wing `normalized-slew-arrivals-v1` adapter uses this local protocol in its restricted base reference-provider domain. Its [qualification record](research/aircraft-creator/AC-12-servo-arrivals-2026-11-16.md) distinguishes component integration, the failed absolute-clock attempt and the separately required local campaign from public-flight acceptance.

Models may opt into an explicitly sized `state_layout_identity`, a pure `endpoint_transition` and a clock-aware `state_validator`. The kernel commits the complete accepted frame and bounded events atomically after final projection; checkpoint v2 pins that layout. Legacy models retain checkpoint v1. The endpoint context reports whether a body filter changed the integrated trajectory. Prepared-reset commit returns success/failure, which adopting session transactions must honor. Its optional synchronous publication hook runs after physical commit and before the reset sample. The Session’s prepared runway, airborne, hand-launch and reload routes close old observers with an explicit previous-flight context. Rejected candidates notify nobody and retain the old flight; explicit commit receipts distinguish them from accepted observer faults, which pause the new flight and cannot be relabeled rollback. Restore reuses that owner and an optional postcommit hook before automatic pause, with no stepped sample; refused restores preserve the old recording, while accepted restores retain paused noncredit replay semantics. Pause/fault listener violations repair the committed protected frame without recursive fault publication. Pending weather selection uses the same guarded old closing context without a tick or statistics credit; the explicit reset remains the physical start. Pending shaft selection uses the same boundary, installs its existing callbacks before notification, and retains the explicit physical reset requirement. [Shaft selection contract](research/ground-physics/GP-14/README.md#accepted-pending-shaft-selection-gp-14i). [Weather selection contract](research/ground-physics/GP-14/README.md#accepted-pending-weather-selection-gp-14h). [Common start contract/evidence](research/ground-physics/GP-14/README.md#common-start-and-reload-transactions-gp-14e), [restore contract/evidence](research/ground-physics/GP-14/README.md#accepted-restore-publication-gp-14f). [GP-16](research/ground-physics/GP-16/README.md) records the contract and tests; it is a generic kernel capability, not an installed stock-aircraft damage model.

Aircraft data is validated and normalized before `FlightSession` accepts it. Invalid initial data cannot fly, and a failed reload preserves the accepted session. Specialized vehicle paths keep their own schemas and acceptance gates. Physical weather and field queries use [the shared environment contract](../app/sim/environment.gd); visual lighting and time remain separate from flight weather.

Creator's non-flight [source resolver](../app/workshop/creator/source_resolver.gd) pins an indexed UUID/revision/record hash, re-admits source and presentation, and returns a detached owner. The [selection owner](../app/app_state/creator_selection_state.gd) tracks source generations and explicit persistence intents without granting flight. [AC-18 evidence](research/aircraft-creator/AC-18-source-reference-2026-11-16.md) distinguishes those prerequisites from the still-open Home, preference, published-flight and target gates.

Finite-fuel mass, CG and inertia updates use [MassInventory](../app/physics/mass_inventory.gd) and [FixedDatumBody](../app/physics/fixed_datum_body.gd). Fuel and electric-pack design details live in the [fuel standard](FUEL-SYSTEM.md) and [battery specification](research/battery/BAT-04/specification.md).

### Native backend policy

Follow the [native development preference](../AGENTS.md#native-development). Native work can be chosen before the reference exceeds the 500 µs target-host budget; that budget remains a performance acceptance gate. Owner-directed native promotion superseded SF-08's blanket fixed-wing deferral, while its numerical, identity and target-host evidence requirements remain applicable ([decision](DECISIONS.md#native-acceleration-replaces-a-stage-not-the-transaction); [historical policy](research/simulation-foundation/README.md#6-backend-policy-sf-08)).

A native backend replaces declared model evaluation callbacks. `Simulation` keeps integration, events, atomic state publication, checkpoints and fault recovery. Missing, mismatched or unsupported native inputs preserve the reference during preparation; a failed live configuration/context guard refuses the tick before native evaluation. It does not silently change an accepted flight's backend. Keep the reference selectable and catalog models usable without a native artifact.

Qualification follows the [native guide](../research/native-kernel/README.md#verification-and-local-installation): byte-identical reference comparisons on at least 10,000 states including malformed inputs, exact kernel trajectories, actual native-call coverage, fault/restore and refusal checks, and the applicable fleet and package gates. Receipts bind the toolchain, engine, ABI/backend version, source/data and library identities; packages additionally bind the executable and manifest. Preserve strict floating-point behavior and the required negative controls. Measure matched production workloads on the target host and report p50/p95 with their defined scope; reference fallback, historical receipts or a partial fleet cannot qualify a new native candidate.

## Godot runtime boundaries

- **Workers and the scene tree:** keep active scene-tree changes on the main thread. Give workers detached inputs and single ownership of mutable resources; synchronize shared plain data. Preserve the existing job owner through completion and discard abandoned results. A mutex does not make arbitrary engine/resource operations thread-safe. The [flight scene loader](../app/ui/flight_scene_load.gd) shows the project's completion and retirement boundary; its engine-specific workaround is not a universal loader recipe.
- **Resource ownership:** repeated `load()` calls and scene instances can share resources. Share immutable assets; isolate the material or subresource that needs independent edits and check what the chosen duplication method actually copies. Do not assume a second load or a shallow duplicate provides independent mutable state, or deep-copy whole asset graphs without a need. [Observed aliasing and lifecycle lessons](learnings/runtime-and-delivery.md#godot-execution-and-test-isolation).
- **Scene reuse:** removing and reattaching a node does not normally rerun `_ready()`, and `remove_child()` does not free it. Define suspend/resume and final disposal explicitly, preserving signal connections and focus state without duplicate initialization. The [screen stack](../app/ui/screen_stack.gd) owns OpenRC's reused-screen handoff; use `request_ready()` only when reinitialization is intended.

For input, retain the [separate menu-focus and flight-input paths](learnings/runtime-and-delivery.md#radio-input-and-menus). For loading, follow [selected preparation](plans/menu-redesign.md#selected-preparation-while-home-is-visible) and its version-scoped evidence. Confirm changed engine behavior with the pinned build; the [practice review](research/development-practices-2026-11-19.md#godot-and-game-development) records the external API sources and their limits.

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
| `assets/`, `assets/source-deliveries/` | Authored geometry, generators, complete owner packages and provenance; [source-delivery index](../assets/source-deliveries/README.md) |
| `tools/`, `research/` | Reusable workflows, experiments, data generators and measurement reducers |
| `docs/`, `site/` | Current guides, plans, dated evidence and project website; [documentation map](README.md), [site guide](../site/README.md) |
| `tmp/`, `output/`, browser scratch folders | Ignored local outputs; accepted evidence belongs under `docs/research/` or `docs/media/` |
| `prototypes/stage0/` | Frozen bake-off specification, comparison and three.js prototype |

## Limits and upgrades

The engine permits at most 12 catch-up ticks per rendered frame; below about 20 fps, simulation slows instead of accumulating unlimited work. The 500 µs physics budget is an acceptance gate, not a guaranteed maximum. Aircraft calibration, handling/readability and platform/GPU qualification remain open in the [ROADMAP](../ROADMAP.md).

Current packages are unsigned desktop ZIPs. Installers and web/mobile delivery are not shipped. Active proposals and their owners are listed in the [documentation map](README.md).

For an engine upgrade, change the version pin and hash deliberately, then run the app checks, inspect captures and verify exports/CI. Preserve numerical and render baselines unless an intentional change explains replacing them. The original platform investigation is in the [research notebook](research/initial-notebook.md); it records historical evidence, not current dependencies.

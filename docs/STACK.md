# Architecture and stack

OpenRC runs in Godot. Each flight or vehicle session installs one model into a shared 240 Hz simulation. Start with the session for the family you are changing and the shared contract below. [Developer setup](TOOLS.md) · [Documentation index](README.md)

## Runtime

| Layer | Implementation |
| --- | --- |
| Engine | Official Godot 4.8-beta2, GDScript and C++ GDExtensions. The fetcher pins the official binary and checksum. [Engine pin](../app/get-godot.sh) · [Upgrade gates](plans/godot-4.8-upgrade.md) |
| Rendering | Compatibility is the OpenGL fallback for weak GPUs and CI. Automatic can select Forward+ on capable Windows/Linux GPUs. The ARM64 project setting selects Mobile on Metal for Apple Silicon. The configured viewport is 1280×720 with 4× 3D MSAA. [Project settings](../app/project.godot) · [Renderer selection](../app/app_state/renderer_preference.gd) · [Display targets](../AGENTS.md#display-resolution-priorities) |
| Physics | Custom float64 rigid-body dynamics, fixed ticks, RK4, model-selected substeps and event policies. [Simulation](../app/sim/simulation.gd) · [VehicleModel](../app/sim/vehicle_model.gd) |
| Flight data | Fixed-wing aircraft use validated `openrc-aircraft v2` quantities, provenance, capabilities and modules. Other vehicle families own their schemas. [Aircraft contract](AIRCRAFT_CONTRACT.md) |
| Presentation | Godot scenes consume detached state. Flight audio uses installed powertrain profiles, recording banks, accepted contact and field sound. Keyboard and radio inputs go through the owning activity. [Coordinate conversion](../app/render/frames.gd) · [Audio guide](AUDIO-PLAN.md) |
| Delivery | Unsigned ZIP exports for Linux x86_64, Windows x86_64 and universal macOS. The export embeds build identity. The macOS app is ad-hoc signed. [Export script](../app/export.sh) · [Presets](../app/export_presets.cfg) |

## Supported vehicle paths

Home selects the activity. Direct routes enter through the same application root. Each family retains its own admission, recording and validation scope. [Startup scene](../app/ui/startup.tscn) · [Application routing](../app/app_root.gd)

| Family | Entry and simulation owner |
| --- | --- |
| Fixed-wing | Main flight route. The catalog selects aircraft and the session binds propulsion, contact, weather and controls. [Flight session](../app/sim/flight_session.gd) · [Flight logging and replay](FLIGHT-LOGGING.md) |
| Helicopter | Experimental rotorcraft route with its own session, quantity reader and recorder. The HX-700 visuals and X-Cell physical reference are surrogates. [Helicopter session](../app/sim/helicopter_flight_session.gd) · [Aircraft and evidence limits](HELICOPTER.md) |
| Ground vehicle | Experimental Bisonte MT8 and MONSTER CAR 2. The session drives the shared kernel in explicit ticks and owns steering, damage, events and replay. Its optional C++ ground evaluator has a separate ABI, build and receipts on Windows/Linux. macOS uses GDScript. [Ground session](../app/sim/ground_vehicle/session.gd) · [Ground evaluator](../research/rc-monster-truck/native/README.md) |
| Airship | Experimental five-metre blimp with its own model, skin selection, Workshop and flight log. [Airship session](../app/sim/airship/session.gd) · [Software evidence and limits](research/rc-airship/BL-12/README.md) |
| Multirotor | Experimental ION R5 FPV quad. The closed-loop plant samples its controller once per tick. The local three-lap race wraps that model so gate and plant state commit together. [Session](../app/sim/multirotor/session.gd) · [Plant](../app/physics/multirotor/controlled_plant.gd) · [Race model](../app/sim/race/race_model.gd) |

## Boundaries and data flow

1. **Prepare the session.** The activity validates vehicle data, field, controls and initial conditions before installing a model. A refused fixed-wing start or reload preserves the accepted flight. The landscape catalog resolves stock fields and calibrated Phoenix revisions. The session supplies physical wind, terrain and obstacles independently of visual lighting. [Landscape catalog](../app/landscapes/catalog.gd) · [Environment](../app/sim/environment.gd) · [Start and reload contracts](research/ground-physics/GP-14/README.md#common-start-and-reload-transactions-gp-14e)
2. **Evaluate one tick.** The installed model declares its state layout, read-only stage callbacks, optional event or step policy and endpoint rules. The rigid body has 13 float64 values, followed by any continuous blocks. Positions use north/east/down, body vectors use forward/right/down, and orientation maps body to world. A session or adapter owns the vehicle laws. [Rigid body](../app/physics/rigid_body.gd) · [Model protocols](../app/sim/vehicle_model.gd)
3. **Commit and publish.** `Simulation` validates and atomically publishes the accepted frame and its events. It owns reset, checkpoint, rollback and fault handling. Rejected candidates leave observers on the old flight. An observer fault after a committed reset pauses the new flight. A successful restore pauses without publishing a stepped sample. [Simulation](../app/sim/simulation.gd) · [Publication and restore](research/ground-physics/GP-14/README.md#accepted-restore-publication-gp-14f) · [Endpoint transitions](research/ground-physics/GP-16/README.md)
4. **Consume accepted state.** Rendering converts detached state into Godot scene coordinates. Recorders bind the accepted frame to session and backend identity. An exact replay needs the recorded implementation. Fixed-wing candidate replay uses a compatible recorded command tape and reports a changed solver. [Frame conversion](../app/render/frames.gd) · [Replay contract](FLIGHT-LOGGING.md)

The optional `framed-sampled-v1` protocol holds one controller sample across every stage and checkpoints controller memory. The joint interval protocols expose detached before/after samples. `joint-interval-local-v1` also carries a local piece clock to preserve short servo intervals at large absolute times. The fixed-wing servo-arrival law requires explicit reference selection. [Protocol definitions](../app/sim/vehicle_model.gd) · [Servo interval qualification](research/aircraft-creator/AC-12-servo-arrivals-2026-11-16.md)

Creator trials freeze a live accepted candidate, admitted inspected source and placement. The separate published-source resolver checks an indexed UUID, revision and hash; successful resolution does not grant flight admission. Finite fuel uses a mass inventory and fixed-datum body so mass, CG and inertia change together. [Creator source resolution](../app/workshop/creator/source_resolver.gd) · [Trial checks](../app/workshop/creator/trial.gd) · [Mass inventory](../app/physics/mass_inventory.gd) · [Fixed-datum body](../app/physics/fixed_datum_body.gd)

### Native backend policy

Fixed-wing and helicopter flight screens request native for ordinary flights. Standalone sessions start with the GDScript reference. The adapter checks the prepared configuration and records the selected identity. Full platform admission, fallback, source installation, release and replay rules belong to the [native guide](../research/native-kernel/README.md#normal-flight-backend-selection). The flight backend and its call counters identify what actually ran. [Fixed-wing entry](../app/main.gd) · [Helicopter entry](../app/helicopter_main.gd) · [Stage adapter](../app/sim/native_stage.gd)

The C++ kernel can integrate RK4, substeps and declared events for its own unbound legacy joint stage. Eligibility also requires continuous state, no endpoint or joint-interval protocol, and a supported step policy. Native stage callbacks can still run when GDScript integrates the tick. An empty native integration answer leaves integration to the reference path. A native fault reaches the existing fault handler. In either case `Simulation` keeps pre-step, commit, publication, checkpoints and rollback. Preserve float64, strict floating-point order, byte parity and recorded identities when moving another boundary. The 500 µs physics target governs acceptance. Native development can begin before a budget overrun. [Integration dispatch](../app/sim/simulation.gd) · [C++ entry point](../research/native-kernel/src/nk_kernel.cpp) · [Decision](DECISIONS.md#native-acceleration-keeps-the-reference-as-its-specification) · [Batch qualification](plans/native-kernel-roadmap.md)

## Godot runtime boundaries

- Keep active scene-tree changes on the main thread. Workers take detached inputs, own their mutable resources through completion and discard abandoned results. [Flight scene loader](../app/ui/flight_scene_load.gd)
- Godot can share resources across loads and instances. Share immutable assets and duplicate only the material or subresource that needs independent edits. [Resource ownership and test isolation](learnings/runtime-and-delivery.md#godot-execution-and-test-isolation)
- Reattaching a node normally does not rerun `_ready()`. Define suspend, resume and disposal for reused screens, including focus and signal ownership. [Screen stack](../app/ui/screen_stack.gd) · [Menu and flight input](learnings/runtime-and-delivery.md#radio-input-and-menus)

## Repository layout

| Path | Responsibility |
| --- | --- |
| `app/app_root.gd`, `app/app_state/`, `app/ui/`, `app/input/` | Activity routing, catalog, preferences, screens and devices |
| `app/sim/`, `app/physics/` | Kernel, sessions, adapters, vehicle laws, state and replay |
| `app/data/`, `app/workshop/`, `app/scenarios/`, `app/failures/` | Validated data, variants and flight scenarios |
| `app/landscapes/`, `app/render/`, `app/vehicles/`, `app/audio/` | Field and vehicle presentation, rendering and sound |
| `assets/`, `app/assets/` | Authoring inputs, provenance, and runtime assets/licenses. [Source deliveries](../assets/source-deliveries/README.md) |
| `app/tests/`, `tools/`, `research/`, `docs/research/` | Checks, development tools, reproducible experiments and dated evidence. [Tool index](tools/README.md) |
| `site/`, `prototypes/stage0/` | Project website and frozen three.js comparison. [Website](../site/README.md) · [Stage 0 evidence](../prototypes/stage0/COMPARISON.md) |

## Limits and upgrades

The engine allows 12 catch-up ticks per rendered frame. Below about 20 fps the simulation can fall behind wall time. Gate P measures whole-tick cost in specified regimes using p95 of 120-tick batch averages. Replay, physical calibration, pilot acceptance and target-hardware pacing each need their own evidence. [Gate P method](research/simulation-state/Gate-P/README.md) · [Open gates](../ROADMAP.md)

When changing the pinned engine, recheck numerical and replay baselines, rendered captures and the affected exported executables on their target platforms. [Upgrade contract](plans/godot-4.8-upgrade.md)

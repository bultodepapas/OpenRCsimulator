# Documentation map

Use the guides for current behavior, track specifications for task-specific acceptance, and dated research for results on its recorded inputs. For current priorities, dependencies and the proof required to close each project gate, start with the [project roadmap](../ROADMAP.md).

## Start here

| I want to… | Start with |
| --- | --- |
| Download a build and fly | [Downloads](../README.md#download-and-fly) · [First launch, controls and troubleshooting](FIRST-LAUNCH.md) · [Release notes by tag](releases/) |
| Build, run or export the simulator | [Developer setup and commands](TOOLS.md) · [Contribution workflow](../CONTRIBUTING.md) |
| Find a test, recorder, profiler or debugging procedure | [Tool index](tools/README.md) · [Choose the scope of verification](tools/shared.md#verification-scope) |
| Trace a tick from controls to the displayed aircraft | [Engine architecture and data flow](STACK.md#boundaries-and-data-flow) |
| Investigate handling with repeatable controls | [Record, replay and compare flights](FLIGHT-LOGGING.md) · [Fly a test card](../research/flight-test/README.md) |
| Change an aircraft, landscape or flight feature | [Aircraft and flight features](#aircraft-and-flight-features) · [Graphics and landscapes](#graphics-and-landscapes) |
| Find the owner of a file, subsystem or step ID | [Track ownership](TRACKS.md) |
| Explore longer-term product ideas | [Product vision and conditional proposals](../MOONSHOT.md) |
| Find out why a design was chosen or what a result proves | [Decisions](DECISIONS.md) · [Reusable lessons](LEARNINGS.md) · [Research and verification records](research/README.md) |

## Engine and physics

| Subject | Guide |
| --- | --- |
| Fixed clock, numerical state, model boundaries and native backend selection | [Architecture](STACK.md) · [Native backend coverage and verification](../research/native-kernel/README.md) |
| Aircraft laws, inputs, units and model identity | [Aircraft contract](AIRCRAFT_CONTRACT.md) · [Numerical change checks](tools/physics.md#numerical-change-checks) |
| Wind, atmosphere and contact | [Wind and atmosphere reference](WIND-ATMOSPHERE-REFERENCE.md) · [Ground contact work and evidence](plans/advanced-ground-flight-physics.md) |
| Engines, batteries and mass | [Shaft coupling](PROPULSION-CORE-PLAN.md) · [Electric propulsion](ELECTRIC-PROPULSION-PLAN.md) · [Glow engines](GLOW-ENGINES.md) · [Turbines](plans/turbine-realism.md) · [Fuel system](FUEL-SYSTEM.md) |
| Physical measurements | [Field measurement reducers](TOOLS.md#aircraft-measurement-reducers) · [Validation dashboard](../research/validation/dashboard.md) |

## Performance and delivery

| Task | Guide |
| --- | --- |
| Measure a slow frame or stutter | [Graphics tools](tools/graphics.md) · [Session capture and diagnostics](../tools/debug/README.md) · [Full-session benchmark](../tools/godtest/README.md) |
| Compare native and reference physics | [Backend policy](STACK.md#native-backend-policy) · [Native qualification work](plans/native-kernel-roadmap.md) |
| Qualify a graphics change on hardware | [Display targets](../AGENTS.md#display-resolution-priorities) · [Intel integrated GPU investigation](plans/low-end-gpu-performance.md) · [Apple Silicon qualification](plans/apple-silicon-performance.md) |
| Run a shared-host test | [Test queue](../tools/testqueue/README.md) · [PRIMIS Linux GPU](tools/primis-testlab.md) · [Apple M1](tools/macos-m1.md) |
| Package and qualify a release | [Release commands](TOOLS.md#release-sequence) · [Desktop qualification](DESKTOP-DELIVERY-PLAN.md) · [Linux packaging](plans/linux-support-distribution.md) |

## Graphics and landscapes

| Subject | Guide |
| --- | --- |
| Renderer, quality presets and hardware selection | [First-launch renderer and presets](plans/automatic-graphics.md#first-launch-policy-on-main) · [Display targets](../AGENTS.md#display-resolution-priorities) · [Graphics debugging](tools/debugging-graphics.md) |
| Upscaling and frame pacing | [Dynamic resolution](plans/dynamic-resolution.md) · [AMD FSR](plans/amd-fsr-completion.md) · [Apple MetalFX](plans/apple-metalfx.md) |
| Import and fly a Phoenix site | [Phoenix scenery player guide](PHOENIX-SCENERY.md) |
| Add or qualify a bundled landscape | [Landscape registration and validation](LANDSCAPES.md) |
| Terrain, scenery and lighting | [Landscape integration](LANDSCAPE-PLAN.md) · [Scenery](SCENERY-PLAN.md) · [Field world](FIELD-WORLD-PLAN.md) · [Time of day](TIME-OF-DAY-PLAN.md) |
| Aircraft lighting and smoke | [Lighting](AIRCRAFT-LIGHTING.md) · [Smoke profiles and behavior](SMOKE.md) |

[Visual quality plan](VISUAL-QUALITY-PLAN.md) is a frozen hash input for the [visual capture cases](../app/tests/visual_quality_cases.py). Its Compatibility and 1080p assumptions describe the original baseline. For current behavior, follow the [project renderer configuration](../app/project.godot), [exported-build selection](../app/app_state/renderer_preference.gd) and display targets above.

## Aircraft and flight features

| Task | Guide |
| --- | --- |
| Identify an aircraft and its authoring owner | [Aircraft overview](../README.md#aircraft) · [Airframe guides and source owners](TRACKS.md#aircraft-and-other-vehicles) |
| Add an aircraft or repaint a model | [Aircraft contract](AIRCRAFT_CONTRACT.md#add-an-aircraft-using-supported-laws) · [Blender delivery](BLENDER-AIRCRAFT-DELIVERY.md) · [Skins tutorial](AIRCRAFT-SKINS.md) · [Asset licensing](AIRCRAFT-LICENSING.md) |
| Edit an aircraft or import a source model | [Workshop](AIRCRAFT-WORKSHOP.md) · [Creator](plans/aircraft-creator.md) · [ClearView player guide](../site/clearview-import-en.md) · [Phoenix aircraft](plans/phoenix-aircraft-import.md) · [Flight Simulator import design](plans/flight-simulator-aircraft-import.md) |
| Set up a radio or check stick response | [Radio setup](FIRST-LAUNCH.md#radio-setup) · [Controller diagnostics](TOOLS.md#radio-diagnostics) |
| Fly companions, review statistics or investigate an incident | [Companions](AI-FLIGHT-COMPANIONS.md) · [Flight statistics](FLIGHT-STATISTICS.md) · [Crash and damage](CRASH-DAMAGE-PLAN.md) |
| Change aircraft or field sounds | [Flight audio](AUDIO-PLAN.md) · [Recording provenance and licenses](audio-asset-sources.md) |
| Work on another vehicle family | [Helicopters](HELICOPTER.md) · [FPV racing](plans/drone-racing.md) · [Trucks](../research/rc-monster-truck/README.md) · [RC airship](plans/rc-airship.md) |

## Records and project services

| Need | Home |
| --- | --- |
| Find a study, script, data file or provenance record | [Studies and verification](research/README.md) · [Research scripts and datasets](../research/README.md) · [Source deliveries](../assets/source-deliveries/README.md) · [Documentation media credits](media/README.md) |
| Review telemetry consent or data collection | [Consent, disclosure and controls](plans/telemetry/consent.md) · [Data contract](plans/telemetry/data-contract.md) |
| Operate a project service or prepare a trailer | [Telemetry receiver](../services/telemetry/README.md) · [Project website](../site/README.md) · [Website analytics](plans/website-analytics.md) · [Trailer production](../tools/trailer/README.md) |

## Agent instruction files

For shared and directory-specific rules, read the [repository instructions](../AGENTS.md). For helper selection and handoffs, see [subagent collaboration](SUBAGENTS.md). [Instruction maintenance](DOCUMENTATION.md#agent-instruction-files) explains loading and verification.

## Tracks, plans and step IDs

The [track registry](TRACKS.md) identifies each subsystem's source paths, interfaces and work IDs.

## Step-ID namespaces

Use the [naming rules](TRACKS.md#step-id-namespaces) when assigning a new step or repair.

## Gates

The [project roadmap](../ROADMAP.md) owns cross-project sequencing and gate status. Follow the linked task specifications for acceptance details.

## Conventions for documents

Use the [documentation guide](DOCUMENTATION.md) when updating a guide, recording evidence or retiring a plan.

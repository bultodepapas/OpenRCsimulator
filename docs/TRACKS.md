# Track ownership

Use the step family to find the code owner and the interface to coordinate before editing. The [roadmap](../ROADMAP.md) orders work across tracks. A shared file can contain hooks owned by several tracks.

## Step-ID namespaces

Register a new track's prefix and source scope here. Carry an existing ID through implementation, tests and evidence. Use `<step>-R<n>` for repairs and qualify ambiguous visual IDs as `P51-V01` or `US-V01`. M1–M5 refer to the main flight milestones.

## Simulation, measurement and input

| Step family | Scope and source ownership | Interface owner to involve |
| --- | --- | --- |
| A–H, PT, VAL, DATA, PERC | [Main-line flight physics](STACK.md), `app/physics/`, `app/sim/`, `app/input/`, `app/main.gd` and physical validation fixtures | Aircraft owners supply installation data. Flight-session and model owners control accepted inputs and events. |
| SF | [Simulation kernel](STACK.md#boundaries-and-data-flow), `simulation.gd`, `vehicle_model.gd`, math, integration and shared contact/event protocols | Vehicle models own their laws. Simulation owns tick commit, checkpoint, publication and rollback. |
| NK | [Native evaluation and integration](../research/native-kernel/README.md), `app/sim/native/` and `research/native-kernel/` | SF and the installed vehicle model own reference behavior. DT owns package qualification. |
| FL, FT | [Flight logs and replay](FLIGHT-LOGGING.md), `tools/flight_log/`; [flight cards and pilots](../research/flight-test/README.md), `research/flight-test/` | Observe accepted session state. Send a handling defect to the aircraft or physics owner. |
| GP | [Ground contact](plans/advanced-ground-flight-physics.md), wheel state, terrain profiles and force tests | AS owns installation bindings, landscape owns surface geometry, CR consumes accepted contacts. |
| M5-W, M5-W-AUD, W-A/W-B, M5-ATM, M5-ATM-AUD | [Wind and atmosphere](WIND-ATMOSPHERE-REFERENCE.md), wind kernels, atmosphere, weather identity and fixtures | Session owns accepted weather, rendering reads it, engine and trim use density. |
| G2, EL, EL1e-STIK | [Coupled shaft](PROPULSION-CORE-PLAN.md), [electric powertrain](ELECTRIC-PROPULSION-PLAN.md), state/trace adapters and installation tests | BAT owns pack behavior. Airframe owners own generated installations. |
| BAT | [Battery behavior](plans/battery-realism.md), `app/physics/battery/`, generated `app/data/batteries/` and source fixtures | EL owns motor and ESC behavior, AE and aircraft owners own authoring and generated bindings. |
| NITRO, NITRO-2T, NITRO-4T, FUEL | [Glow engines](GLOW-ENGINES.md) and [fuel inventory and mass balance](FUEL-SYSTEM.md), glow profiles, fuel readers and reducers | Keep two-stroke and four-stroke installation evidence separate. Coordinate AS, G2, AV, AE and accepted audio observations. |
| D6-GP, F1/3/4/6-GP, UI-10/12/15-GP | [Controller support](plans/controller-support.md), input profiles, actions and diagnostics | UI owns menus. Flight sessions consume conditioned commands. |
| D6-JETI, F1/4/6-JETI, UI-15-JETI · D6-ETX, UI-15-ETX, HUD-ETX, F1/F4-ETX | [JETI](plans/jeti-support.md) and [EdgeTX](plans/edgetx-airplane-controls.md) recognition, mapping and tests | D6 owns input conditioning. UI/HUD own setup and instrument views. |
| UI-15-UX, D6-UX, D6-TRIM, D6-SRV, D6-SAV | [Setup flow](plans/controls-setup-ux.md), trim practice, [servo dynamics](plans/servo-dynamics.md) and [Savox installations](plans/savox-servos.md) | Input owns detection/bindings. Physics owns actuator laws. AE owns editable installations. |

## Aircraft and other vehicles

Airframe owners maintain their source pipeline, geometry, declared bindings and aircraft-specific tests. The [aircraft contract](AIRCRAFT_CONTRACT.md) governs shared schemas, units and node names.

| Step family | Airframe or vehicle and source scope | Shared interfaces |
| --- | --- | --- |
| AS | [Aircraft standardization](plans/aircraft-standardization.md), shared modules, binding generators and conformance fixtures | Extend shared capabilities with the consumer and the affected airframe owners. |
| US, US-V | [Ugly Stik .60](UGLY-STIK-PLAN.md), `assets/aircraft/ugly-stik-60/`, `ugly_stik_*` model code and `app/render/airplane.gd` | D-series aero, NITRO and EL own their laws. |
| EX | [Extra 300S .60](EXTRA-300-PLAN.md), `assets/aircraft/extra-300s-60/`, `extra_300s_*`, `research/extra-300/` | Propulsion, generated physics, catalog. |
| AV | [Vantage Jet](AVANTI-S-PLAN.md), `assets/aircraft/avanti-s-a200/` and `avanti_s_*` | Turbine, finite fuel, retracts and flight controls. |
| P51, P51-V | [P-51D Mustang](P51-PLAN.md), `assets/aircraft/p51d-mustang-120/`, `p51d_*` and handling tests | Slipstream, fuel, contact and presentation. |
| TT | [Turbo Lumber Evolution](TIMBER-INTEGRATION-PLAN.md), `assets/aircraft/turbo-lumber-evolution/` and `timber_*` | Electric power, battery, controls and source delivery. |
| F4U | [F4U Corsair](F4U-PLAN.md), `assets/aircraft/f4u-corsair-250/` and `research/f4u-corsair/` | AS bindings, propulsion, flaps and retracts. |
| X8 | [MoonRunner X99](X8-PLAN.md), `assets/aircraft/skywalker-x8/` and `research/skywalker-x8/` | AS elevons, tailless aero and pusher propulsion. |
| HELI | [Helicopters](HELICOPTER.md), `app/physics/rotorcraft/`, family session, recorder, schema and tests | SF, ground, input and model owners. |
| DR | [Multirotor flight and racing](plans/drone-racing.md), `app/physics/multirotor/`, `app/sim/multirotor/`, `app/sim/race/`, `app/vehicles/multirotor/` | SF sampled-event protocol, EL/BAT, controller, camera and UI. |
| RCV | [RC trucks and courses](plans/rc-monster-truck.md), `app/physics/ground_vehicle/`, `app/sim/ground_vehicle/`, `app/vehicles/ground/` | GP/SF contact and state, UI routes and landscape material. |
| BL | [RC airship](plans/rc-airship.md), `app/physics/airship/`, `app/sim/airship/`, `app/vehicles/airship/` | SF, airframe data, atmosphere, power, contact and session controls. |

## Flight features and authoring

| Step family | Scope and source ownership | Shared interfaces |
| --- | --- | --- |
| UI, UI-FS | [Product shell](MENU-PLAN.md), `app/app_root.gd`, `app/ui/`, preferences and i18n; [flight statistics](FLIGHT-STATISTICS.md) in `app/statistics/` | Sessions own holds and flight/contact facts. DT owns display and package behavior. |
| AE | [Aircraft Workshop](AIRCRAFT-WORKSHOP.md), `app/workshop/`, Workshop UI, previews and data | AS and aircraft owners own capabilities/bindings. Flight owns trial admission. |
| AC, AC-CV, AC-PX, AC-FS, IAQ | [Creator and shared qualification](plans/aircraft-creator.md), `app/workshop/creator/`, Creator data and UI. [ClearView](../site/clearview-import-en.md), [Phoenix](plans/phoenix-aircraft-import.md), [Flight Simulator design](plans/flight-simulator-aircraft-import.md) and [cross-provider quality](plans/imported-aircraft-quality.md) | Adapters own their formats. AE owns trials and storage, physics owns flight admission, authors retain rights to assets. |
| NR, EM | [Natural Random](plans/natural-random-flight.md) in `app/scenarios/` and [emergency practice](plans/failure-mode.md) in `app/failures/` | UI owns briefing/preferences. Weather, actuators, propulsion and session owners retain their laws. |
| AFC | [AI companions](AI-FLIGHT-COMPANIONS.md), `app/ai/companions/` and companion controls | Aircraft/SF own vehicle sessions. Scenery, collision, audio and UI own their consumers. |
| CR | [Crash handling](CRASH-DAMAGE-PLAN.md), `app/render/crash/`; [repair estimates](plans/crash-damage-economics.md), `app/economy/`, `app/data/economy/` | Contact owns physical outcomes. AS/AE own bindings and saved builds. UI and audio consume incident data. |
| CAM, HUD, LENS | [Cameras](plans/camera-views.md), [overlays](plans/flight-overlays.md) and [lens effects](plans/lens-screen-effects.md) in their respective `app/render/` subtrees | Coordinate session/main hooks, crash events, audio listener, menus and HUD settings. |

## Graphics, world and sound

| Step family | Scope and source ownership | Shared interfaces |
| --- | --- | --- |
| VQ, VQ-04b-S, VQ-07 | [Renderer selection](../app/app_state/renderer_preference.gd), [visual capture baseline](VISUAL-QUALITY-PLAN.md), [shadows](plans/shadows.md), [advanced graphics](plans/advanced-graphics.md) and [automatic settings](plans/automatic-graphics.md) | UI owns player choices, DT/GDU own platform/engine behavior, PT owns measurement. |
| L, LU, L-PX | [Landscape and integration](LANDSCAPE-PLAN.md), terrain, water, vegetation, `app/render/landscape_upgrade/`; [bundled landscapes and imported Phoenix sites](LANDSCAPES.md) in `app/landscapes/` | Coordinate field/terrain contacts with GP and vehicle owners, selection with UI, site visuals with FW/SC. |
| FW, FW-MOON, SUN, TOD | [Field world](FIELD-WORLD-PLAN.md), [sun](plans/sun.md), [moon](plans/moon.md), and [time of day](TIME-OF-DAY-PLAN.md), `app/render/world/` and `app/environment/` | Weather and the session clock supply observations. UI owns settings and saved state. |
| FW-RGB | [Aircraft lighting](AIRCRAFT-LIGHTING.md) in `app/render/lighting/` | Aircraft owners supply anchors, AE owns customization, FW owns scene-light allocation. |
| SC, SC-HUM, SC-BIRD | [Scenery and field life](SCENERY-PLAN.md), `app/scenery/`, source assets, scenery tooling and tests | Landscape, collision, world rendering and companions own their interfaces. |
| AUD, G3b | [Flight audio](AUDIO-PLAN.md), `app/audio/`, source recordings, soundscape assets and `tools/audio/` | Read accepted observations. Aircraft owners supply installation identity. |
| SM | [Smoke](SMOKE.md), `app/render/smoke/`, profile contracts and `tools/smoke/` | AS owns outlets, AE owns customization, M5 owns wind and FUEL owns physical fluid stores. |

## Tools, platforms and project services

| Step family | Scope and source ownership | Shared interfaces |
| --- | --- | --- |
| GOD, PT1h-R15 | [Session benchmarks](../tools/godtest/README.md) in `tools/godtest/` and [stutter capture](../tools/debug/README.md) in `app/debug/` and `tools/debug/` | PT/VQ/DT own timing definitions and device evidence. Flight, UI and scenery retain their behaviors. |
| DX, TQ, TQ-05-F, TQ-06-P | [Tool guidance](tools/README.md) in `docs/tools/` and repository skill folders; [shared-host admission](../tools/testqueue/README.md) in `tools/testqueue/` | Individual tools own commands. Test queue owns admission, session recovery and fleet evidence. CI owns workflow policy. |
| DT, DT-UPD, DT-LNX, DT-MAC | [Desktop delivery](DESKTOP-DELIVERY-PLAN.md), [GitHub updates](plans/github-updates.md), [Linux distribution](plans/linux-support-distribution.md), [Apple qualification](plans/apple-silicon-performance.md) and `tools/release/` | Export/CI owns packages, UI owns presentation, NK/SF/FL own backend and replay identity, VQ owns renderer behavior. |
| GDU | [Engine upgrades](plans/godot-4.8-upgrade.md), engine/template pin scripts, CI engine pins and engine-upgrade research | DT/PT own release qualification and performance measurement. |
| PT1, PT1-CI, v* tags | [Releases](releases/), build identities, `.github/workflows/`, `tools/ci/`, `app/test.sh`, `app/capture.sh` | DT owns promotion/provenance. Native, numerical and visual owners define their checks. |
| TELEM | [Telemetry](plans/telemetry.md), `app/telemetry/`, `services/telemetry/`, `tools/telemetry/` | UI owns consent, sessions own lifecycle, PT/VQ own metric meaning, operator owns publication. |
| WEB, TRA | [Public website](../site/README.md) in `site/` and [trailer production](../tools/trailer/README.md) in `tools/trailer/` | WEB owns publication. Release owners control build identity. Camera, vehicle and model tracks own source behavior. |

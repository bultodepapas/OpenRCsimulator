# Roadmap

2026-10-12 · Revision 9 · **Status: working early alpha. Gate 2, PT2, readability, physical calibration and target-machine performance acceptance remain open.** This document owns main-line step/gate status. Track guides own their detailed work; [documentation and ownership map](docs/README.md), [current architecture](STACK.md), [commands](docs/TOOLS.md).

## Rules for every step

Follow [AGENTS](AGENTS.md) and [CONTRIBUTING](CONTRIBUTING.md): one small working change, labeled evidence, reproducible proof and preserved parallel work. Test known-answer mathematics before unknown aircraft behavior. Verification establishes implementation; independent measurements and pilots establish physical validity. Measure before tuning. The physics budget is 500 µs per 240 Hz tick on the accepted target machine; measure representative aircraft/regimes before claiming it is met.

## Where we are

- **Physics and simulation:** float64 240 Hz RK4, local aerodynamic loads, trim, controls, propulsion, wheel contact and complete-state replay are implemented; main-line delivery records are below.
- **Aircraft contract:** v2 standardization AS-00…05 is delivered; [AIRCRAFT_CONTRACT](AIRCRAFT_CONTRACT.md) owns authoring, with [migration/verification evidence](docs/research/aircraft-standardization/AS-05/README.md).
- **Ground physics:** GP-00…05 is delivered; [integrated ground model](docs/research/ground-physics/GP-05/README.md) records wheel/terrain/profile behavior and open calibration/performance limits.
- **Stik circuit:** automated approach, landing, full circuit, rendered review, replay and sensitivity tools exist; manual owner circuit and E3c/E4/PT2 physical acceptance remain open.
- **Ugly Stik:** [model/finish guide](docs/UGLY-STIK-PLAN.md); [pull-up investigation](docs/UGLY-STIK-PULLUP-PLAN.md) keeps candidate polars opt-in and production selection open.
- **Extra:** [experimental model and realism guide](docs/EXTRA-300-PLAN.md); independent flight calibration remains open.
- **Avanti:** [experimental turbine guide/plan](docs/AVANTI-S-PLAN.md); current configuration is airborne, gear and flaps up.
- **P-51:** [P51-PLAN](docs/P51-PLAN.md) owns the experimental model and generated physics; [realism implementation](docs/P51-REALISM-PLAN.md) owns P51-15…18, the full-envelope audit and paired-hardware inertia correction; [visual plan](docs/P51-PLAN.md) owns appearance acceptance.
- **Timber:** [integration plan](docs/TIMBER-INTEGRATION-PLAN.md); the r1 visual asset is frozen, measured, imported, articulated and listed as a catalog preview (TT-01…03, TT-05, TT-06: Fly refused, scripted circle only); electric physics data (TT-07) is next.
- **Product shell:** [implemented menus](docs/MENU-PLAN.md); UI-20/21 refactor delivered, UI-22…29 [redesign](docs/MENU-REDESIGN-PLAN.md) remains proposed.
- **Field/readability:** [landscape step registry](docs/LANDSCAPE-PLAN.md) and [visual guide](docs/VISUAL-QUALITY-PLAN.md); Gate L needs pilot/target-display evidence.
- **Landscape integration:** [active LU plan](LANDSCAPE_UPGRADE_PLAN.md) preserves the continuing LU-07…10 work and its separate cost/acceptance gates.
- **World/time:** [world guide](docs/FIELD-WORLD-PLAN.md) and [lighting/history guide](docs/TIME-OF-DAY-PLAN.md); selectable night and passing evening exist, with further lifecycle and owner acceptance open.
- **Scenery:** [default-on field life](docs/SCENERY-PLAN.md), with static collision proxies; Gate SC readability/performance acceptance remains open.
- **Audio:** [AUD-01…05 soundscape guide](docs/AUDIO-PLAN.md); acoustic calibration and target-platform timing remain separate limits.
- **Crash:** [experimental presentation](docs/CRASH-DAMAGE-PLAN.md) is implemented; physical thresholds, structural/flyable damage and Gate CR remain open.
- **Weather:** [wind/gust/turbulence](docs/WIND-PLAN.md) and [field atmosphere](docs/ATMOSPHERE-PLAN.md) are implemented; practice presets are estimates, and physical/performance acceptance remains open.
- **Propulsion:** [coupled shaft](docs/PROPULSION-CORE-PLAN.md) and [synthetic electric routes](docs/ELECTRIC-PROPULSION-PLAN.md) exist; default promotion, matched powerplant data and the 500 µs gate remain open.
- **Radio/validation tools:** controller reports, latency marker/reducer, field-measurement reducers and the [VAL-3 dashboard](research/validation/dashboard.md) exist; synthetic fixtures do not count as physical measurements.
- **Desktop/release:** [rc7](docs/releases/v0.1.0-rc7.md) is published; current source is newer. Packages are ZIP exports; [desktop qualification/installers/fullscreen](docs/DESKTOP-DELIVERY-PLAN.md) remain pending.
- **Smoke:** [unimplemented proposal and research](docs/SMOKE-PLAN.md); no exhaust/pump-smoke runtime feature is shipped.

## Execution order and release gates

| Gate / outcome | Current state | Required evidence |
| --- | --- | --- |
| Gate 1: platform | Decided: Godot, 2026-10-05 | [Bake-off comparison](prototypes/stage0/COMPARISON.md), [decision](DECISIONS.md) |
| Gate F: aero architecture | Decided: component buildup grown from the corrected linear oracle | [Flight repair](docs/research/flight-repair-implementation.md); aircraft calibration is separate |
| Gate 2: first owner flight | Open | Named build/radio/OS; circuits, roll/loop/stall/spin recovery; per-axis −2…+2 handling ratings against a real RC model, 100 m readability and setup time |
| PT2 / M2 circuit | Software tools delivered; physical acceptance open | Manual runway–circuit–landing trace and [flight card](docs/research/menu-investigations/UI-06c/FLIGHT-CARD.md), independent ground/flight comparison |
| Gate P: physics headroom | Open | Per-aircraft/regime p50/p95 on an idle target host; include ground, active wake and electric event costs; profile before deciding on GDExtension |
| Physical calibration | Open | Identified aircraft mass/CG/inertia/throws, installed propulsion and rollout/flight observations, uncertainty and held-out cases |
| Native delivery/readability | Open where the owning track says so | Actual downloaded Windows/macOS/Linux launch, physical radios, target GPU/display and pilot evidence; package structure/headless checks are separate |

The next main-line outcome is the manual Stik circuit. Use existing measurement, trace, capture and replay tools to identify the next bounded repair. Keep automated verification and external validation distinct. Active track work proceeds within its documented ownership and acceptance boundaries.

## Completed foundations

| IDs | Delivered foundation | Durable proof |
| --- | --- | --- |
| A1…A4 | MIT license, repository conventions, exact pins and CI | [License](LICENSE), [CI](.github/workflows/ci.yml), [tool workflows](docs/TOOLS.md) |
| B1…B7 / Gate 1 | Shared platform bake-off, input/render seams and Godot promotion | [Specification](prototypes/stage0/SPEC.md), [comparison](prototypes/stage0/COMPARISON.md) |
| C1…C7 | Float64 math, rigid body/RK4, known-answer/refinement tests, fixed ticks and traces | [Tests](app/tests/), [state research](docs/research/README.md#flight-model-and-simulation) |

## Milestones from here: each one ends in a build the owner flies

Completed IDs below retain navigation to their tests/evidence. Reports record the exact source snapshot and original results; those results are not a claim that today's complete working tree has passed the same run.

### M1 — First flight (owner flies the Ugly Stik with keyboard or radio)

| IDs | Implemented result | Evidence / remaining work |
| --- | --- | --- |
| D1…D5, D5.9 | Validated aircraft, air/load model, trim/propulsion and session separation | [Aircraft contract](AIRCRAFT_CONTRACT.md), [physics research](docs/research/README.md#flight-model-and-simulation) |
| D6a/b/c | Raw radio reader, saved calibration/arming and physical servos | [Radio research](docs/research/radio-input/), [controls](docs/FIRST-LAUNCH.md#3-fly) |
| D6d / Gate 2 | Owner radio/handling session | Open; real hardware/pilot evidence required |
| D7, D8a | Camera/zoom/shadow aids, regression flights and modal verification | [Tests](app/tests/), [validation boundary](docs/research/validation/VAL-3/README.md) |
| D8b, D10, D11a | Independent-reference comparison and sensitivity tools | [Current sensitivity](research/sensitivity/results.md); actual Stik mass/inertia/handling calibration remains open |
| D9a…d, D9-R/D10-R repairs | Full-envelope/local loads, gyro, crash detection and rudder/robustness fixes | [Delivered repair](docs/research/flight-repair-implementation.md), [diagnosis](docs/research/ugly-stik-rudder-audit.md) |
| D8b-R2a…i | Experimental polar diagnostics and high-speed pull-up qualification | [Active pull-up guide](docs/UGLY-STIK-PULLUP-PLAN.md); production selection and RC validation open |
| C7-R1/R2, D1-R1…R5, D4-R1/R2 | Trace/loader/trim integrity and transactional aircraft acceptance | [Trace evidence](docs/research/trace-integrity/), [aircraft integrity](docs/research/aircraft-validation/), [trim integrity](docs/research/trim-integrity/D4-R2/README.md) |
| D6b-R1/R2 | Strict calibration profiles and fresh low-throttle rearming | [Profile integrity](docs/research/radio-input/D6b-R1/README.md), [arming](docs/research/radio-input/D6b-R2/README.md) |
| PT1a…h | Verified templates, exports, smoke checks, tagged publication and integration | [Release evidence](docs/research/release-readiness/), [commands](docs/TOOLS.md#release-sequence); native/pilot gates remain separate |

### M1 follow-up — flight-model consistency (D11)

D11a comparison is regenerated; D11b characterization, D11d strip consistency and D11f/g fin/oracle follow-ups have implementation evidence in [aero-consistency](docs/research/aero-consistency/). D11e needs measured inertia (VAL-6), D11h needs qualified cross-rate derivatives, and D11c remains conditional offline-tool research. Current local/oracle consistency does not validate borrowed coefficients for the real Stik.

### Phase H — State contract and measured headroom

H1…H9, H8a/R1, H9-R1 and H11…H15 delivered profiling, float64/transcendental guards, bounded state ownership, atomic RK updates, replay/refinement policy and measured allocation reductions. H10 found no justified contributor-interface extraction. [State evidence](docs/research/README.md#flight-model-and-simulation) retains exact refactor/parity records.

H15's shipped benchmark fixtures met the median budget on the measured host. Active smooth-wake, ground and electric-event workloads have separate cost limits. [Prepared-wake evidence](docs/research/propwash/E0b6p/prepared-model/README.md) is research, not an adopted runtime native backend. Gate P remains open.

### M2 — Takeoff and landing

E0a local tail, E0a2a/b downwash split/lag, E0b P-51 slipstream and wake experiments, E1/E1b contact, E2 steering, E3a/b friction/rest/takeoff, E3c1a/E3c2a/b approach/circuit review and E4a/b replay/sensitivity have software evidence. [Ground-contact evidence](docs/research/ground-contact/), [landing experiments](research/landing/), [propwash evidence](docs/research/propwash/) and [GP-05](docs/research/ground-physics/GP-05/README.md) identify their actual regimes and assumptions.

E3c/E4/PT2 external circuit acceptance remains open. E5a/b taildragger/nose-over checks are software fixtures, with aircraft-specific physical calibration pending. E0b promotion and low-speed authority require matched propulsion/wake data and cost qualification.

### M3 — Radio breadth and measured latency

F1 controller reporting, F3b1 event-cost characterization, F6a marker and F6b video reduction are delivered. [Radio evidence](docs/research/radio-input/) and [diagnostic commands](docs/TOOLS.md#radio-diagnostics) own their contracts. F4 compatibility rows and F6 physical latency measurements remain open. F2 linkage-trim policy, F3 reconnection breadth, F5/UI radio setup and further servo/control features require their own measured need; they are not current functionality.

### M4 — Propulsion response, operating range and sound

G1a1 importer and G1b1 range auditor, G2-R1 equilibrium guards, experimental G2a/G2b coupling and G3b/AUD audio have implementation evidence in [propulsion research](docs/research/propulsion/) and [audio](docs/AUDIO-PLAN.md). Matched G1a/VAL-7 powerplant data, online G1b range coverage, G1d stopped/windmilling drag, G2 promotion and acoustic calibration remain open. Full fuel/engine-operation simulation is not delivered.

#### M4b — Electric propulsion

EL1b…e and EL2a provide synthetic fixed-bus and OCV/resistance/SOC flight, stop/depletion events, replay and telemetry. EL2a-P1/P2/P3 and E1 have dated optimization/maneuver proof. The [electric plan](docs/ELECTRIC-PROPULSION-PLAN.md) owns current equations, open EL2b…6 work, physical data and performance acceptance. Timber is not validated or enabled by these fixtures.

### M5 — Atmosphere and advanced flight envelopes

M5-W uniform wind/repeating gusts/temporal turbulence and M5-ATM-1/2 with the first shaft-charge correction are implemented. Their [wind](docs/WIND-PLAN.md) and [atmosphere](docs/ATMOSPHERE-PLAN.md) guides own the remaining spatial/spectral/calibration work. M5-GE-1 wing/tail ground effect is implemented as the opt-in `aero.ground_effect` module, declared by the Stik only ([evidence](docs/research/ground-effect/M5-GE-1/README.md); fitted generic constants, flare/liftoff validation open). Other advanced-envelope and receiver-assistance ideas are research inputs, not implemented features or prerequisites for the current circuit.

## Validation and aircraft-data work

| IDs | Current state | Evidence / next proof |
| --- | --- | --- |
| VAL-3/4 | Dashboard and metamorphic software checks delivered | [Validation evidence](docs/research/validation/) |
| VAL-5a, VAL-6a, VAL-7a…c, VAL-8a/b | Measurement reducers delivered | [Field measurement workflows](docs/TOOLS.md#aircraft-measurement-reducers); synthetic examples remain labeled |
| VAL-5…8 | Physical mass/CG, swing-test inertia, static/transient propulsion and video flight measurements | Open; retain raw inputs, calibration, uncertainty, configuration and independent references |
| VAL-9…15 | Logger/identification and further validation breadth | Not delivered; select a bounded task only when data and acceptance are available |
| DATA-1/2a/2b/3/4a/4b | Generator freshness, load-cost reductions, exact hashes and historical-v1 schema/loader coverage | [Aircraft-validation evidence](docs/research/aircraft-validation/); strict load-time bound remains open |
| DATA-8 / AS-00…05 | V2 contract, explicit capabilities, migration and authoring template delivered | [Contract](AIRCRAFT_CONTRACT.md), [AS-05](docs/research/aircraft-standardization/AS-05/README.md); supersedes the old conditional-v2 proposal |
| Other DATA / PERC work | Broader authoring and pilot-perception research | Unimplemented options remain in the [phase knowledge base](docs/research/roadmap-investigations/README.md); new runtime capabilities need contract/ownership review |

### Owner's field kit

1. Weigh one identified assembly, locate CG and record fuel/battery/gear state (VAL-5).
2. Measure inertia with a validated swing rig and uncertainty budget (VAL-6).
3. Measure installed propeller thrust/RPM and throttle steps with matched diameter and density (VAL-7).
4. Record the manual runway circuit, roll/stall/glide and takeoff/landing video against surveyed or calibrated observations (VAL-8/PT2).
5. Capture radio firmware/USB mode, axes, calibration, platform and filmed latency (D6d/F4/F6).

Use the [existing reducers](docs/TOOLS.md) and record what remains unknown. Estimates and virtual mass inventories must not become measurements through repeated use.

## Research tracks

Start at [docs/research/README](docs/research/README.md). The [initial notebook](docs/research/initial-notebook.md), [phase investigations](docs/research/roadmap-investigations/README.md), [DECISIONS](DECISIONS.md) and dated reports preserve the evidence/rationale behind prior reviews. Completed review checklists and superseded implementation proposals are removed from the active queue.

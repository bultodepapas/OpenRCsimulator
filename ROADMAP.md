# Roadmap

2026-10-19 · **Status: working early alpha. Gate 2, PT2, readability, physical calibration and target-machine performance acceptance remain open.** This document owns main-line step/gate status. Track guides own their detailed work; [documentation and ownership map](docs/README.md), [current architecture](docs/STACK.md), [commands](docs/TOOLS.md).

## Rules for every step

Follow [AGENTS](AGENTS.md) and [CONTRIBUTING](CONTRIBUTING.md): one small working change, labeled evidence, reproducible proof and preserved parallel work. Test known-answer mathematics before unknown aircraft behavior. Verification establishes implementation; independent measurements and pilots establish physical validity. Measure before tuning. The physics budget is 500 µs per 240 Hz tick on the accepted target machine; measure representative aircraft/regimes before claiming it is met.

## Where we are

- **Simulation:** float64 240 Hz RK4, local aerodynamics, trim, propulsion, ground contact and complete-state replay are implemented. The shared kernel serves fixed-wing, helicopter and ground-vehicle sessions; [STACK](docs/STACK.md#boundaries-and-data-flow) owns its boundaries and [SF evidence](docs/research/simulation-foundation/README.md) records the delivered foundation.
- **Aircraft and vehicles:** five fixed-wing airframes, three additional Stik glow installations, the historical helicopter trainer and two RC trucks are playable. Runway/airborne airplane starts and Timber's finite-pack/ideal options are source features. Models remain experimental or under evaluation. The [aircraft overview](README.md#aircraft), [helicopter guide](docs/HELICOPTER.md) and [truck guide](research/rc-monster-truck/README.md) own configuration limits. Multirotor groundwork exists; a playable drone/race route does not.
- **Controls and product shell:** Home, Settings, controller profiles/calibration/remapping, Workshop trials, Natural Random and optional fixed-wing failures have runtime implementations. Use the [player guide](docs/FIRST-LAUNCH.md) and [track registry](docs/README.md#tracks-plans-and-step-ids) for scope and remaining acceptance.
- **Field and presentation:** wind/atmosphere, time of day, landscape/scenery, audio, smoke, overlays and crash presentation are integrated. Their owning guides and gates are in the [track registry](docs/README.md#tracks-plans-and-step-ids); rendering and incident-cost estimates do not establish physical accuracy.
- **Validation tools:** scripted approaches/circuits, the [flight-test card](research/flight-test/README.md), [flight logging and exact/candidate replay](docs/FLIGHT-LOGGING.md), measurement reducers and the [validation dashboard](research/validation/dashboard.md) support investigations. Manual Stik circuit, independent physical measurements, radio compatibility and target-host performance remain open.
- **Delivery:** unsigned Windows/Linux/macOS ZIPs are published; [downloads](README.md#download-and-fly) and [release notes](docs/releases/) describe package contents. Windowed/borderless Settings are implemented. [Desktop qualification and installers](docs/DESKTOP-DELIVERY-PLAN.md) remain separate work.

## Execution order and release gates

| Gate / outcome | Current state | Required evidence |
| --- | --- | --- |
| Gate 1: platform | Decided: Godot, 2026-10-05 | [Bake-off comparison](prototypes/stage0/COMPARISON.md), [decision](docs/DECISIONS.md) |
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
| D1…D5, D5.9 | Validated aircraft, air/load model, trim/propulsion and session separation | [Aircraft contract](docs/AIRCRAFT_CONTRACT.md), [physics research](docs/research/README.md#flight-model-and-simulation) |
| D6a/b/c | Raw radio reader, saved calibration/arming and physical servos | [Radio research](docs/research/radio-input/), [controls](docs/FIRST-LAUNCH.md#3-fly) |
| D6d / Gate 2 | Owner radio/handling session | Open; real hardware/pilot evidence required |
| D7, D8a | Camera/zoom/shadow aids, regression flights and modal verification | [Tests](app/tests/), [validation boundary](docs/research/validation/VAL-3/README.md) |
| D8b, D10, D11a | Independent-reference comparison and sensitivity tools | [Current sensitivity](research/sensitivity/results.md); actual Stik mass/inertia/handling calibration remains open |
| D9a…d, D9-R/D10-R repairs, D10-R2, D10-R5 | Full-envelope/local loads, gyro, crash detection and rudder/robustness fixes; D10-R2 (2026-10-18) adds the Stik's fin-efficiency/fuselage Cnβ and reference-based recovery criteria; D10-R5 (2026-10-19) gives the local law the Stik's wing-body roll due to sideslip | [Delivered repair](docs/research/flight-repair-implementation.md), [diagnosis](docs/research/ugly-stik-rudder-audit.md), [D10-R2](docs/research/flight-dynamics/stik-lateral-directional-2026-10-18/README.md), [D10-R5](docs/research/flight-dynamics/stik-roll-sideslip-2026-10-19/README.md); full-rudder sideslip (rudder throw), the side-force level and its consistency between the oracle and the local law (no sustained knife-edge) and R02 remain pending |
| D8b-R2a…i | Experimental polar diagnostics and high-speed pull-up qualification | [Active pull-up guide](docs/UGLY-STIK-PULLUP-PLAN.md); production selection and RC validation open |
| C7-R1/R2, D1-R1…R5, D4-R1/R2 | Trace/loader/trim integrity and transactional aircraft acceptance | [Trace evidence](docs/research/trace-integrity/), [aircraft integrity](docs/research/aircraft-validation/), [trim integrity](docs/research/trim-integrity/D4-R2/README.md) |
| D6b-R1/R2 | Strict calibration profiles and fresh low-throttle rearming | [Profile integrity](docs/research/radio-input/D6b-R1/README.md), [arming](docs/research/radio-input/D6b-R2/README.md) |
| PT1a…h | Verified templates, exports, smoke checks, tagged publication and integration | [Release evidence](docs/research/release-readiness/), [commands](docs/TOOLS.md#release-sequence); native/pilot gates remain separate |

### M1 follow-up — flight-model consistency (D11)

D11a comparison is regenerated; D11b characterization, D11d strip consistency and D11f/g fin/oracle follow-ups have implementation evidence in [aero-consistency](docs/research/aero-consistency/). D11e needs measured inertia (VAL-6), D11h needs qualified cross-rate derivatives, and D11c remains conditional offline-tool research. Current local/oracle consistency does not validate borrowed coefficients for the real Stik.

2026-10-13: the [elevator investigation](docs/research/flight-dynamics/elevator-repair-2026-10-13.md) found the generated aircraft (Extra, P-51, Ventage Jet) without the Stik's free tail law: half the pitch damping and no Cmα̇ in the local regime, an inflated elevator τ that stalled the tail from half stick, and a P-51 static step between regimes. D11i (regime-consistency test, `test_regime_consistency.gd`), E0a2c (generators emit `downwash_gradient`), D11j (`wing_section_cm_ac` on the strips) and D8a-R2 (overdamped short period in `flight_modes.gd`) are implemented with [evidence](docs/research/aero-consistency/E0a2c/README.md). D6e input rates/expo and the D6e-R2 in-flight rate switch (N) are also implemented ([evidence](docs/research/radio-input/D6e/README.md)). The investigation closed on 2026-10-18; its open items continue under D8b-R2 (post-stall lateral gain), AV-01 (Ventage Jet neutral point), P-51 realism (CG/neutral point) and VAL-5…8.

### Phase H — State contract and measured headroom

H1…H9, H8a/R1, H9-R1 and H11…H17 delivered profiling, float64/transcendental guards, bounded state ownership, atomic RK updates, replay/refinement policy and measured allocation reductions. H10 found no justified contributor-interface extraction. [State evidence](docs/research/README.md#flight-model-and-simulation) retains exact refactor/parity records.

H15's shipped benchmark fixtures met the median budget on the measured host. [H16](docs/research/simulation-state/H16/README.md) later removed repeated ground-stage layout queries: three airborne repeats measured median paired CPU reductions of 5.20% Stik, 5.06% Lumber and 2.34% P-51; the runway result was flat. [H17](docs/research/simulation-state/H17/README.md) reuses segmented-slipstream geometry and interval values locally: three P-51 trim repeats measured 0.90–1.66% lower paired CPU cost with exact trajectories; the Stik control was flat. [H18](docs/research/simulation-state/H18/README.md) evaluates the ground-effect wing wake once per oracle call and hoists strip-loop invariants: electric Stik runway tick −9.6% in three pairs, bit-identical. Active smooth-wake, ground and electric-event workloads have separate cost limits. [Prepared-wake evidence](docs/research/propwash/E0b6p/prepared-model/README.md) is research, not an adopted runtime native backend. Gate P remains open.

### M2 — Takeoff and landing

E0a local tail, E0a2a/b downwash split/lag, E0b P-51 slipstream and wake experiments, E1/E1b contact, E2 steering, E3a/b friction/rest/takeoff, E3c1a/E3c2a/b approach/circuit review and E4a/b replay/sensitivity have software evidence. [Ground-contact evidence](docs/research/ground-contact/), [landing experiments](research/landing/), [propwash evidence](docs/research/propwash/) and [GP-05](docs/research/ground-physics/GP-05/README.md) identify their actual regimes and assumptions.

E3c/E4/PT2 external circuit acceptance remains open. E5a/b taildragger/nose-over checks are software fixtures, with aircraft-specific physical calibration pending. E0b promotion and low-speed authority require matched propulsion/wake data and cost qualification.

### M3 — Radio breadth and measured latency

F1 controller reporting, F3b1 event-cost characterization, F6a marker and F6b video reduction are delivered. [Radio evidence](docs/research/radio-input/) and [diagnostic commands](docs/TOOLS.md#radio-diagnostics) own their contracts. F4 compatibility rows and F6 physical latency measurements remain open. Controller selection, calibration, profiles, remapping and AUX setup are implemented; the [controller track](docs/plans/controller-support.md) owns their remaining qualification. F2 linkage-trim policy, F3 reconnection breadth and further servo/control work retain their own acceptance requirements.

### M4 — Propulsion response, operating range and sound

G1a1 importer and G1b1 range auditor, G2-R1 equilibrium guards, experimental G2a/G2b coupling and G3b/AUD audio have implementation evidence in [propulsion research](docs/research/propulsion/) and [audio](docs/AUDIO-PLAN.md). The experimental Stik glow installations now run finite-fuel two-stroke and four-stroke models; their estimates and qualification limits are documented in the [glow guide](docs/GLOW-ENGINES.md). Matched G1a/VAL-7 powerplant data, online G1b range coverage, G1d stopped/windmilling drag, G2 promotion, and physical and pilot qualification of the glow installations remain open.

The [RC glow engine realism plan](docs/plans/RC_NITRO_ENGINE_REALISM_PLAN.md) owns mandatory, separate two-stroke and true four-stroke research, implementation, calibration and validation milestones; both family gates must close before that feature is complete.

#### M4b — Electric propulsion

EL1b…e and EL2a provide synthetic fixed-bus and OCV/resistance/SOC fixtures, stop/depletion events, replay and telemetry; their optimization/maneuver proof remains dated evidence. Timber also offers a finite `pack_ecm` battery by default and an ideal supply option. The [electric guide](docs/ELECTRIC-PROPULSION-PLAN.md) and [battery plan](docs/plans/battery-realism.md) own implemented laws, remaining steps and qualification. Synthetic fixtures do not validate the installed aircraft or battery.

### M5 — Atmosphere and advanced flight envelopes

M5-W uniform wind/repeating gusts/temporal turbulence and M5-ATM-1/2 with the first shaft-charge correction are implemented. Their [wind](docs/WIND-PLAN.md) and [atmosphere](docs/ATMOSPHERE-PLAN.md) guides own the remaining spatial/spectral/calibration work. M5-GE-1 wing/tail ground effect is implemented as the opt-in `aero.ground_effect` module, declared by the Stik only ([evidence](docs/research/ground-effect/M5-GE-1/README.md); fitted generic constants, flare/liftoff validation open). Other advanced-envelope and receiver-assistance ideas are research inputs, not implemented features or prerequisites for the current circuit.

## Validation and aircraft-data work

| IDs | Current state | Evidence / next proof |
| --- | --- | --- |
| VAL-3/4 | Dashboard and metamorphic software checks delivered | [Validation evidence](docs/research/validation/) |
| VAL-5a, VAL-6a, VAL-7a…c, VAL-8a/b | Measurement reducers delivered | [Field measurement workflows](docs/TOOLS.md#aircraft-measurement-reducers); synthetic examples remain labeled |
| VAL-5…8 | Physical mass/CG, swing-test inertia, static/transient propulsion and video flight measurements | Open; retain raw inputs, calibration, uncertainty, configuration and independent references |
| VAL-9…15 | Physical logging/identification and further validation breadth | Remains open; simulator flight logs are delivered separately under [FL-01…04](docs/FLIGHT-LOGGING.md) and do not close physical-data gates |
| DATA-1/2a/2b/3/4a/4b | Generator freshness, load-cost reductions, exact hashes and historical-v1 schema/loader coverage | [Aircraft-validation evidence](docs/research/aircraft-validation/); strict load-time bound remains open |
| DATA-8 / AS-00…05 | V2 contract, explicit capabilities, migration and authoring template delivered | [Contract](docs/AIRCRAFT_CONTRACT.md), [AS-05](docs/research/aircraft-standardization/AS-05/README.md); supersedes the old conditional-v2 proposal |
| Other DATA / PERC work | Broader authoring and pilot-perception research | Unimplemented options remain in the [phase knowledge base](docs/research/roadmap-investigations/README.md); new runtime capabilities need contract/ownership review |

### Owner's field kit

1. Weigh one identified assembly, locate CG and record fuel/battery/gear state (VAL-5).
2. Measure inertia with a validated swing rig and uncertainty budget (VAL-6).
3. Measure installed propeller thrust/RPM and throttle steps with matched diameter and density (VAL-7).
4. Record the manual runway circuit, roll/stall/glide and takeoff/landing video against surveyed or calibrated observations (VAL-8/PT2).
5. Capture radio firmware/USB mode, axes, calibration, platform and filmed latency (D6d/F4/F6).

Use the [existing reducers](docs/TOOLS.md) and record what remains unknown. Estimates and virtual mass inventories must not become measurements through repeated use.

## Research tracks

Start at [docs/research/README](docs/research/README.md). The [initial notebook](docs/research/initial-notebook.md), [phase investigations](docs/research/roadmap-investigations/README.md), [DECISIONS](docs/DECISIONS.md) and dated reports preserve the evidence/rationale behind prior reviews. Completed review checklists and superseded implementation proposals are removed from the active queue.
